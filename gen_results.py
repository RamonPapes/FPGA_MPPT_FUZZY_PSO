from __future__ import annotations

import argparse
import math
from pathlib import Path

import pandas as pd


DAILY_COLUMNS = [
    "month",
    "timestamp_date",
    "n_samples",
    "P_best_final",
    "N_conv_98",
    "T_conv_98_seconds",
    "duty_std_after_conv",
    "P_ripple_after_conv",
    "mean_abs_error",
    "std_abs_error",
]

GENERAL_COLUMNS = [
    "month",
    "n_days",
    "P_best_final_mean",
    "P_best_final_std",
    "N_conv_98_mean",
    "N_conv_98_std",
    "T_conv_98_seconds_mean",
    "T_conv_98_seconds_std",
    "duty_std_after_conv_mean",
    "duty_std_after_conv_std",
    "P_ripple_after_conv_mean",
    "P_ripple_after_conv_std",
    "mean_abs_error_mean",
    "mean_abs_error_std",
    "std_abs_error_mean",
    "std_abs_error_std",
]


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
        "gbest_power",
        "error",
    }

    missing = required - set(df.columns)

    if missing:
        raise ValueError(
            f"{path.name} nao possui as colunas obrigatorias: {sorted(missing)}"
        )

    for col in ["sample", "timestamp_date", "timestamp_time", "power_now", "duty", "gbest_power", "error"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df = df.dropna(subset=["sample", "timestamp_date", "timestamp_time"])
    df["timestamp_date"] = df["timestamp_date"].astype(int)
    df["timestamp_seconds"] = df["timestamp_time"].apply(parse_hhmmss_to_seconds)

    return df


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
            "duty_std_after_conv": 0.0,
            "P_ripple_after_conv": 0.0,
            "mean_abs_error": 0.0,
            "std_abs_error": 0.0,
        }

    p_best_final = float(day_df["gbest_power"].max())
    threshold = 0.98 * p_best_final

    conv_df = day_df[day_df["gbest_power"] >= threshold]

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

    return {
        "month": month,
        "timestamp_date": int(date_value),
        "n_samples": n_samples,
        "P_best_final": p_best_final,
        "N_conv_98": int(n_conv_98),
        "T_conv_98_seconds": float(t_conv_98),
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

    metric_cols = [
        "P_best_final",
        "N_conv_98",
        "T_conv_98_seconds",
        "duty_std_after_conv",
        "P_ripple_after_conv",
        "mean_abs_error",
        "std_abs_error",
    ]

    for col in metric_cols:
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

        print(f"Calculando metricas por dia: {result_file.name}")

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
