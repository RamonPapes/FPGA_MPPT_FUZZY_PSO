from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd


DAILY_COLUMNS = [
    "month",
    "timestamp_date",
    "n_samples",
    "P_best_final",
    "N_conv_98",
    "T_conv_98_seconds",
    "duty_converged",
    "N_conv_duty_stable",
    "T_conv_duty_stable_seconds",
    "duty_mean_after_stable",
    "duty_std_after_stable",
    "duty_step_mean_after_stable",
    "duty_range_after_stable",
    "duty_saturation_percent",
    "duty_saturation_after_stable_percent",
    "gbest_consistency_violations",
    "gbest_monotonic_violations",
    "stability_score",
    "duty_std_after_conv",
    "P_ripple_after_conv",
    "mean_abs_error",
    "std_abs_error",
]

SUMMARY_METRIC_COLUMNS = [
    col for col in DAILY_COLUMNS
    if col not in {"month", "timestamp_date", "n_samples"}
]

GENERAL_COLUMNS = ["month", "n_days"]
for metric_col in SUMMARY_METRIC_COLUMNS:
    GENERAL_COLUMNS.extend([f"{metric_col}_mean", f"{metric_col}_std"])

DUTY_STABLE_WINDOW = 200
DUTY_STD_THRESHOLD = 1.0
DUTY_STEP_THRESHOLD = 0.75


def parse_month_name(path: Path) -> str:
    name = path.stem

    if name.endswith("_results"):
        name = name[: -len("_results")]

    if name.startswith("resultados_hybrid_"):
        name = name[len("resultados_hybrid_") :]

    return name


def parse_hhmmss_to_seconds(value: object) -> int:
    if pd.isna(value):
        return 0

    text = str(value).strip()

    if "." in text:
        text = text.split(".", 1)[0]

    text = "".join(ch for ch in text if ch.isdigit())

    if not text:
        return 0

    text = text.zfill(6)

    hours = int(text[-6:-4])
    minutes = int(text[-4:-2])
    seconds = int(text[-2:])

    return hours * 3600 + minutes * 60 + seconds


def std_or_zero(series: pd.Series) -> float:
    series = pd.to_numeric(series, errors="coerce").dropna()

    if len(series) < 2:
        return 0.0

    return float(series.std(ddof=1))


def mean_or_zero(series: pd.Series) -> float:
    series = pd.to_numeric(series, errors="coerce").dropna()

    if len(series) == 0:
        return 0.0

    return float(series.mean())


def read_result_file(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path, sep=r"\s+", engine="python")

    required = {
        "sample",
        "timestamp_date",
        "timestamp_time",
        "power_now",
        "duty",
        "error",
    }

    missing = required - set(df.columns)

    if missing:
        raise ValueError(
            f"{path.name} nao possui as colunas obrigatorias: {sorted(missing)}"
        )

    numeric_cols = [
        "sample",
        "timestamp_date",
        "timestamp_time",
        "power_now",
        "duty",
        "error",
    ]

    optional_numeric_cols = [
        "gbest_power",
        "POWER_SCALE_DEN",
    ]

    numeric_cols.extend(
        col for col in optional_numeric_cols
        if col in df.columns
    )

    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df = df.dropna(subset=["sample", "timestamp_date", "timestamp_time"])
    df["timestamp_date"] = df["timestamp_date"].astype(int)
    df["timestamp_seconds"] = df["timestamp_time"].apply(parse_hhmmss_to_seconds)

    if "gbest_power" in df.columns:
        df["expected_gbest_power"] = df["power_now"].cummax()
        df["gbest_consistency_violation"] = (
            df["gbest_power"] != df["expected_gbest_power"]
        ).astype(int)
        df["gbest_monotonic_violation"] = (
            df["gbest_power"].diff().fillna(0) < 0
        ).astype(int)
    else:
        df["gbest_consistency_violation"] = 0
        df["gbest_monotonic_violation"] = 0

    return df


def find_duty_stable_point(day_df: pd.DataFrame) -> tuple[pd.Series | None, int]:
    window = min(DUTY_STABLE_WINDOW, max(20, len(day_df) // 10))

    if len(day_df) < window:
        return None, window

    duty = pd.to_numeric(day_df["duty"], errors="coerce")
    duty_step = duty.diff().abs().fillna(0.0)

    rolling_std = duty.rolling(window, min_periods=window).std()
    rolling_step = duty_step.rolling(window, min_periods=window).mean()

    stable = (
        (rolling_std <= DUTY_STD_THRESHOLD)
        & (rolling_step <= DUTY_STEP_THRESHOLD)
    )

    stable_rows = day_df[stable]

    if stable_rows.empty:
        return None, window

    return stable_rows.iloc[0], window


def stability_score(
    duty_converged: int,
    duty_std: float,
    duty_step_mean: float,
    duty_range: float,
    saturation_percent: float,
) -> float:
    penalty = (
        duty_std
        + duty_step_mean
        + 0.10 * duty_range
        + 0.50 * saturation_percent
    )

    if duty_converged == 0:
        penalty += 10.0

    return float(100.0 / (1.0 + penalty))


def calculate_day_metrics(month: str, date_value: int, day_df: pd.DataFrame) -> dict[str, float | int | str]:
    day_df = day_df.sort_values(["sample"]).copy()

    n_samples = int(len(day_df))

    if n_samples == 0:
        return {
            "month": month,
            "timestamp_date": date_value,
            "n_samples": 0,
            "P_best_final": 0.0,
            "N_conv_98": -1,
            "T_conv_98_seconds": -1.0,
            "duty_converged": 0,
            "N_conv_duty_stable": -1,
            "T_conv_duty_stable_seconds": -1.0,
            "duty_mean_after_stable": 0.0,
            "duty_std_after_stable": 0.0,
            "duty_step_mean_after_stable": 0.0,
            "duty_range_after_stable": 0.0,
            "duty_saturation_percent": 0.0,
            "duty_saturation_after_stable_percent": 0.0,
            "gbest_consistency_violations": 0,
            "gbest_monotonic_violations": 0,
            "stability_score": 0.0,
            "duty_std_after_conv": 0.0,
            "P_ripple_after_conv": 0.0,
            "mean_abs_error": 0.0,
            "std_abs_error": 0.0,
        }

    # IMPORTANTE:
    # Aqui a convergencia diaria NAO usa gbest_power do VHDL.
    # O gbest_power do VHDL e acumulado ao longo da simulacao mensal.
    # Como nao estamos resetando o controlador a cada dia, usar gbest_power
    # causaria N_conv_98 = 0 em dias posteriores.
    #
    # Portanto, para manter a analise diaria sem rodar dia por dia,
    # calculamos um "gbest local" apenas para a janela daquele dia:
    # local_gbest_power[k] = max(power_now[0:k]) dentro do proprio dia.
    #
    # Isso mede convergencia diaria relativa ao sinal de potencia observado
    # naquele dia, nao a memoria interna acumulada do PSO.
    day_df["local_gbest_power"] = day_df["power_now"].cummax()

    p_best_final = float(day_df["power_now"].max())
    threshold = 0.98 * p_best_final

    if p_best_final <= 0:
        n_conv_98 = -1
        t_conv_98 = -1.0
        steady = day_df
    else:
        conv_df = day_df[day_df["local_gbest_power"] >= threshold]

        if len(conv_df) == 0:
            n_conv_98 = -1
            t_conv_98 = -1.0
            steady = day_df
        else:
            first_conv = conv_df.iloc[0]
            first_sample = int(day_df.iloc[0]["sample"])
            first_time = int(day_df.iloc[0]["timestamp_seconds"])

            n_conv_98 = int(first_conv["sample"]) - first_sample
            t_conv_98 = float(int(first_conv["timestamp_seconds"]) - first_time)

            if t_conv_98 < 0:
                t_conv_98 = 0.0

            steady = day_df[day_df["sample"] >= first_conv["sample"]]

    abs_error = day_df["error"].abs()
    duty = pd.to_numeric(day_df["duty"], errors="coerce")
    duty_step = duty.diff().abs().fillna(0.0)

    stable_point, _ = find_duty_stable_point(day_df)

    if stable_point is None:
        duty_converged = 0
        n_conv_duty_stable = -1
        t_conv_duty_stable = -1.0
        duty_steady = day_df.tail(min(len(day_df), DUTY_STABLE_WINDOW))
    else:
        duty_converged = 1
        first_sample = int(day_df.iloc[0]["sample"])
        first_time = int(day_df.iloc[0]["timestamp_seconds"])

        n_conv_duty_stable = int(stable_point["sample"]) - first_sample
        t_conv_duty_stable = float(int(stable_point["timestamp_seconds"]) - first_time)

        if t_conv_duty_stable < 0:
            t_conv_duty_stable = 0.0

        duty_steady = day_df[day_df["sample"] >= stable_point["sample"]]

    duty_steady_values = pd.to_numeric(duty_steady["duty"], errors="coerce")
    duty_steady_step = duty_steady_values.diff().abs().fillna(0.0)
    duty_saturation = (duty <= 0) | (duty >= 100)
    duty_steady_saturation = (duty_steady_values <= 0) | (duty_steady_values >= 100)

    duty_std_stable = std_or_zero(duty_steady_values)
    duty_step_mean_stable = mean_or_zero(duty_steady_step)
    duty_range_stable = float(duty_steady_values.max() - duty_steady_values.min())
    duty_sat_stable = float(duty_steady_saturation.mean() * 100.0)

    return {
        "month": month,
        "timestamp_date": int(date_value),
        "n_samples": n_samples,
        "P_best_final": p_best_final,
        "N_conv_98": int(n_conv_98),
        "T_conv_98_seconds": float(t_conv_98),
        "duty_converged": duty_converged,
        "N_conv_duty_stable": int(n_conv_duty_stable),
        "T_conv_duty_stable_seconds": float(t_conv_duty_stable),
        "duty_mean_after_stable": mean_or_zero(duty_steady_values),
        "duty_std_after_stable": duty_std_stable,
        "duty_step_mean_after_stable": duty_step_mean_stable,
        "duty_range_after_stable": duty_range_stable,
        "duty_saturation_percent": float(duty_saturation.mean() * 100.0),
        "duty_saturation_after_stable_percent": duty_sat_stable,
        "gbest_consistency_violations": int(day_df["gbest_consistency_violation"].sum()),
        "gbest_monotonic_violations": int(day_df["gbest_monotonic_violation"].sum()),
        "stability_score": stability_score(
            duty_converged=duty_converged,
            duty_std=duty_std_stable,
            duty_step_mean=duty_step_mean_stable,
            duty_range=duty_range_stable,
            saturation_percent=duty_sat_stable,
        ),
        "duty_std_after_conv": std_or_zero(steady["duty"]),
        "P_ripple_after_conv": std_or_zero(steady["power_now"]),
        "mean_abs_error": mean_or_zero(abs_error),
        "std_abs_error": std_or_zero(abs_error),
    }


def summarize_month(month: str, daily_df: pd.DataFrame) -> dict[str, float | int | str]:
    summary: dict[str, float | int | str] = {
        "month": month,
        "n_days": int(len(daily_df)),
    }

    for col in SUMMARY_METRIC_COLUMNS:
        valid = pd.to_numeric(daily_df[col], errors="coerce")
        valid = valid[valid >= 0].dropna()

        summary[f"{col}_mean"] = float(valid.mean()) if len(valid) else 0.0
        summary[f"{col}_std"] = float(valid.std(ddof=1)) if len(valid) > 1 else 0.0

    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", default="results")
    args = parser.parse_args()

    results_dir = Path(args.results_dir).resolve()

    if not results_dir.exists():
        raise FileNotFoundError(f"Pasta de resultados nao encontrada: {results_dir}")

    result_files = sorted(results_dir.glob("*_results.txt"))

    if not result_files:
        raise FileNotFoundError(f"Nenhum arquivo *_results.txt encontrado em: {results_dir}")

    all_daily_rows: list[dict[str, float | int | str]] = []
    general_rows: list[dict[str, float | int | str]] = []

    for result_file in result_files:
        month = parse_month_name(result_file)

        print(f"Calculando metricas open-loop e convergencia do duty: {result_file.name}")

        df = read_result_file(result_file)

        daily_rows: list[dict[str, float | int | str]] = []

        for date_value, day_df in df.groupby("timestamp_date", sort=True):
            daily_rows.append(calculate_day_metrics(month, int(date_value), day_df))

        daily_df = pd.DataFrame(daily_rows, columns=DAILY_COLUMNS)

        month_daily_path = results_dir / f"{month}_daily_metrics.csv"
        daily_df.to_csv(month_daily_path, index=False)

        general_rows.append(summarize_month(month, daily_df))
        all_daily_rows.extend(daily_rows)

        print(f"Arquivo gerado: {month_daily_path}")

    all_daily_df = pd.DataFrame(all_daily_rows, columns=DAILY_COLUMNS)
    all_daily_path = results_dir / "metrics_daily_all.csv"
    all_daily_df.to_csv(all_daily_path, index=False)

    general_df = pd.DataFrame(general_rows, columns=GENERAL_COLUMNS)
    general_path = results_dir / "metrics_general.csv"
    general_df.to_csv(general_path, index=False)

    print(f"Arquivo geral diario gerado: {all_daily_path}")
    print(f"Resumo geral gerado: {general_path}")


if __name__ == "__main__":
    main()
