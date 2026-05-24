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
    "duty_mean",
    "duty_std",
    "duty_min",
    "duty_max",
    "duty_range",
    "duty_step_mean",
    "duty_step_max",
    "duty_mean_after_stable",
    "duty_std_after_stable",
    "duty_step_mean_after_stable",
    "duty_range_after_stable",
    "duty_final_mean",
    "duty_final_std",
    "duty_final_range",
    "duty_final_step_mean",
    "duty_saturation_percent",
    "duty_saturation_after_stable_percent",
    "gbest_consistency_violations",
    "gbest_monotonic_violations",
    "stability_score",
    "duty_std_after_conv",
    "P_ripple_after_conv",
    "error_mean",
    "mean_abs_error",
    "max_abs_error",
    "error_saturation_percent",
    "delta_e_mean",
    "mean_abs_delta_e",
    "max_abs_delta_e",
    "delta_e_saturation_percent",
    "std_abs_error",
]

SUMMARY_METRIC_COLUMNS = [
    col for col in DAILY_COLUMNS
    if col not in {"month", "timestamp_date", "n_samples"}
]

GENERAL_COLUMNS = ["month", "n_days"]
for metric_col in SUMMARY_METRIC_COLUMNS:
    GENERAL_COLUMNS.extend([f"{metric_col}_mean", f"{metric_col}_std"])

DAILY_TABLE_METRICS = [
    "P_best_final",
    "N_conv_98",
    "T_conv_98_seconds",
    "duty_std_after_conv",
    "P_ripple_after_conv",
    "mean_abs_error",
]

DAILY_TABLE_LATEX = {
    "P_best_final": {
        "caption": "Valores diarios de $P_{\\text{best\\_final}}$ obtidos pelo controlador hibrido PSO--Fuzzy.",
        "label": "tab:pbest-final-por-dia",
        "header": "$P_{\\text{best\\_final}}$",
        "decimals": 2,
    },
    "N_conv_98": {
        "caption": "Valores diarios de $N_{\\text{conv\\_98}}$ obtidos pelo controlador hibrido PSO--Fuzzy.",
        "label": "tab:nconv-98-por-dia",
        "header": "$N_{\\text{conv\\_98}}$",
        "decimals": 0,
    },
    "T_conv_98_seconds": {
        "caption": "Valores diarios de $T_{\\text{conv\\_98}}$ obtidos pelo controlador hibrido PSO--Fuzzy.",
        "label": "tab:tconv-98-por-dia",
        "header": "$T_{\\text{conv\\_98}}$ (s)",
        "decimals": 1,
    },
    "duty_std_after_conv": {
        "caption": "Valores diarios de $duty_{\\text{std\\_after\\_conv}}$ obtidos pelo controlador hibrido PSO--Fuzzy.",
        "label": "tab:duty-std-after-conv-por-dia",
        "header": "$duty_{\\text{std\\_after\\_conv}}$",
        "decimals": 3,
    },
    "P_ripple_after_conv": {
        "caption": "Valores diarios de $P_{\\text{ripple\\_after\\_conv}}$ obtidos pelo controlador hibrido PSO--Fuzzy.",
        "label": "tab:p-ripple-after-conv-por-dia",
        "header": "$P_{\\text{ripple\\_after\\_conv}}$",
        "decimals": 2,
    },
    "mean_abs_error": {
        "caption": "Valores diarios de $mean_{\\text{abs\\_error}}$ obtidos pelo controlador hibrido PSO--Fuzzy.",
        "label": "tab:mean-abs-error-por-dia",
        "header": "$mean_{\\text{abs\\_error}}$",
        "decimals": 3,
    },
}

DUTY_STABLE_WINDOW = 200
DUTY_STD_THRESHOLD = 1.0
DUTY_STEP_THRESHOLD = 0.75
DUTY_FINAL_BAND = 2.0

SENTINEL_NEGATIVE_COLUMNS = {
    "N_conv_98",
    "T_conv_98_seconds",
    "N_conv_duty_stable",
    "T_conv_duty_stable_seconds",
}

MONTH_ORDER = {
    "Jan": 1,
    "Feb": 2,
    "Mar": 3,
    "Apr": 4,
    "May": 5,
    "Jun": 6,
    "Jul": 7,
    "Aug": 8,
    "Sep": 9,
    "Oct": 10,
    "Nov": 11,
    "Dec": 12,
}


def parse_month_name(path: Path) -> str:
    name = path.stem

    if name.endswith("_results"):
        name = name[: -len("_results")]

    if name.startswith("resultados_hybrid_"):
        name = name[len("resultados_hybrid_") :]

    return name


def month_sort_key(month: str) -> tuple[int, int, str]:
    parts = month.split("_")

    if len(parts) >= 2:
        month_num = MONTH_ORDER.get(parts[0], 99)

        try:
            year = int(parts[1])
        except ValueError:
            year = 9999

        return year, month_num, month

    return 9999, 99, month


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
        "control_duty",
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
        "delta_e",
        "fuzzy_delta",
        "gbest_duty",
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

    adaptive_gbest = "MEMORY_HALF_LIFE" in df.columns

    if "gbest_power" in df.columns and not adaptive_gbest:
        df["expected_gbest_power"] = (
            df.groupby("timestamp_date")["power_now"].cummax()
        )
        df["gbest_consistency_violation"] = (
            df["gbest_power"] != df["expected_gbest_power"]
        ).astype(int)
        df["gbest_monotonic_violation"] = (
            df.groupby("timestamp_date")["gbest_power"].diff().fillna(0) < 0
        ).astype(int)
    else:
        # Com memoria adaptativa, gbest pode cair quando a potencia disponivel
        # cai. Isso nao e violacao; e o comportamento desejado para nao prender
        # o PSO em um pico antigo do dataset.
        df["gbest_consistency_violation"] = 0
        df["gbest_monotonic_violation"] = 0

    return df


def duty_metric_col(day_df: pd.DataFrame) -> str:
    if "control_duty" not in day_df.columns:
        raise ValueError(
            "Coluna control_duty ausente. Regenere os resultados com o testbench atual; "
            "a coluna duty representa a particula do PSO e nao deve ser usada nas metricas."
        )

    return "control_duty"


def find_duty_stable_point(day_df: pd.DataFrame, duty_col: str) -> tuple[pd.Series | None, int]:
    window = min(DUTY_STABLE_WINDOW, max(20, len(day_df) // 10))

    if len(day_df) < window:
        return None, window

    duty = pd.to_numeric(day_df[duty_col], errors="coerce").reset_index(drop=True)
    final_duty = duty.tail(window).dropna()

    if final_duty.empty:
        return None, window

    final_center = float(final_duty.median())
    within_final_band = (duty - final_center).abs() <= DUTY_FINAL_BAND

    # Convergencia aqui significa estabilidade ate o fim do dia, nao apenas
    # a primeira janela quieta. A versao anterior aceitava a primeira janela
    # de 200 amostras e gerava falso N_conv=199 mesmo quando o duty mudava depois.
    tail_stays_in_band = within_final_band.iloc[::-1].cummin().iloc[::-1].astype(bool)
    min_tail_len = window

    for pos, stable_to_end in enumerate(tail_stays_in_band):
        if not stable_to_end:
            continue

        if len(day_df) - pos < min_tail_len:
            break

        tail_duty = duty.iloc[pos:]
        tail_step = tail_duty.diff().abs().dropna()

        if (
            std_or_zero(tail_duty) <= DUTY_STD_THRESHOLD
            and mean_or_zero(tail_step) <= DUTY_STEP_THRESHOLD
        ):
            return day_df.iloc[pos], window

    return None, window


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
            "duty_mean": 0.0,
            "duty_std": 0.0,
            "duty_min": 0.0,
            "duty_max": 0.0,
            "duty_range": 0.0,
            "duty_step_mean": 0.0,
            "duty_step_max": 0.0,
            "duty_mean_after_stable": 0.0,
            "duty_std_after_stable": 0.0,
            "duty_step_mean_after_stable": 0.0,
            "duty_range_after_stable": 0.0,
            "duty_final_mean": 0.0,
            "duty_final_std": 0.0,
            "duty_final_range": 0.0,
            "duty_final_step_mean": 0.0,
            "duty_saturation_percent": 0.0,
            "duty_saturation_after_stable_percent": 0.0,
            "gbest_consistency_violations": 0,
            "gbest_monotonic_violations": 0,
            "stability_score": 0.0,
            "duty_std_after_conv": 0.0,
            "P_ripple_after_conv": 0.0,
            "error_mean": 0.0,
            "mean_abs_error": 0.0,
            "max_abs_error": 0.0,
            "error_saturation_percent": 0.0,
            "delta_e_mean": 0.0,
            "mean_abs_delta_e": 0.0,
            "max_abs_delta_e": 0.0,
            "delta_e_saturation_percent": 0.0,
            "std_abs_error": 0.0,
        }

    # IMPORTANTE:
    # Aqui a convergencia diaria NAO usa gbest_power do VHDL.
    # O gbest_power do VHDL e acumulado ao longo da simulacao mensal.
    # Usar um gbest global causaria N_conv_98 = 0 em dias posteriores quando
    # a melhor potencia ja apareceu em um dia anterior.
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

    duty_col = duty_metric_col(day_df)
    duty = pd.to_numeric(day_df[duty_col], errors="coerce")
    duty_step = duty.diff().abs().fillna(0.0)
    duty_window = min(DUTY_STABLE_WINDOW, max(20, len(day_df) // 10))
    duty_final_values = duty.tail(duty_window)
    duty_final_step = duty_final_values.diff().abs().fillna(0.0)

    error = pd.to_numeric(day_df["error"], errors="coerce")
    abs_error = error.abs()

    if "delta_e" in day_df.columns:
        delta_e = pd.to_numeric(day_df["delta_e"], errors="coerce")
    else:
        delta_e = pd.Series(0.0, index=day_df.index)

    abs_delta_e = delta_e.abs()

    stable_point, _ = find_duty_stable_point(day_df, duty_col)

    if stable_point is None:
        duty_converged = 0
        n_conv_duty_stable = -1
        t_conv_duty_stable = -1.0
        duty_steady = day_df.tail(duty_window)
    else:
        duty_converged = 1
        first_sample = int(day_df.iloc[0]["sample"])
        first_time = int(day_df.iloc[0]["timestamp_seconds"])

        n_conv_duty_stable = int(stable_point["sample"]) - first_sample
        t_conv_duty_stable = float(int(stable_point["timestamp_seconds"]) - first_time)

        if t_conv_duty_stable < 0:
            t_conv_duty_stable = 0.0

        duty_steady = day_df[day_df["sample"] >= stable_point["sample"]]

    duty_steady_values = pd.to_numeric(duty_steady[duty_col], errors="coerce")
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
        "duty_mean": mean_or_zero(duty),
        "duty_std": std_or_zero(duty),
        "duty_min": float(duty.min()),
        "duty_max": float(duty.max()),
        "duty_range": float(duty.max() - duty.min()),
        "duty_step_mean": mean_or_zero(duty_step),
        "duty_step_max": float(duty_step.max()),
        "duty_mean_after_stable": mean_or_zero(duty_steady_values),
        "duty_std_after_stable": duty_std_stable,
        "duty_step_mean_after_stable": duty_step_mean_stable,
        "duty_range_after_stable": duty_range_stable,
        "duty_final_mean": mean_or_zero(duty_final_values),
        "duty_final_std": std_or_zero(duty_final_values),
        "duty_final_range": float(duty_final_values.max() - duty_final_values.min()),
        "duty_final_step_mean": mean_or_zero(duty_final_step),
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
        "duty_std_after_conv": std_or_zero(steady[duty_col]),
        "P_ripple_after_conv": std_or_zero(steady["power_now"]),
        "error_mean": mean_or_zero(error),
        "mean_abs_error": mean_or_zero(abs_error),
        "max_abs_error": float(abs_error.max()),
        "error_saturation_percent": float((abs_error >= 100).mean() * 100.0),
        "delta_e_mean": mean_or_zero(delta_e),
        "mean_abs_delta_e": mean_or_zero(abs_delta_e),
        "max_abs_delta_e": float(abs_delta_e.max()),
        "delta_e_saturation_percent": float((abs_delta_e >= 100).mean() * 100.0),
        "std_abs_error": std_or_zero(abs_error),
    }


def summarize_month(month: str, daily_df: pd.DataFrame) -> dict[str, float | int | str]:
    summary: dict[str, float | int | str] = {
        "month": month,
        "n_days": int(len(daily_df)),
    }

    for col in SUMMARY_METRIC_COLUMNS:
        valid = pd.to_numeric(daily_df[col], errors="coerce")
        valid = valid.dropna()

        if col in SENTINEL_NEGATIVE_COLUMNS:
            valid = valid[valid >= 0]

        summary[f"{col}_mean"] = float(valid.mean()) if len(valid) else 0.0
        summary[f"{col}_std"] = float(valid.std(ddof=1)) if len(valid) > 1 else 0.0

    return summary


def format_month_label(month: str) -> str:
    parts = month.split("_")

    if len(parts) >= 2:
        return f"{parts[0]}/{parts[1]}"

    return month


def format_latex_value(value: object, decimals: int, metric: str) -> str:
    if pd.isna(value):
        return ""

    numeric_value = float(value)

    if metric in SENTINEL_NEGATIVE_COLUMNS and numeric_value < 0:
        return ""

    return f"{numeric_value:.{decimals}f}"


def write_daily_metric_latex_table(pivot: pd.DataFrame, metric: str, output_path: Path) -> None:
    info = DAILY_TABLE_LATEX[metric]
    decimals = int(info["decimals"])
    day_cols = [f"dia_{day:02d}" for day in range(1, 32)]
    column_format = "l" + ("c" * len(day_cols))

    lines = [
        "\\begin{table}[H]",
        "\\centering",
        f"\\caption{{{info['caption']}}}",
        f"\\label{{{info['label']}}}",
        "\\resizebox{\\textwidth}{!}{%",
        f"\\begin{{tabular}}{{{column_format}}}",
        "\\hline",
    ]

    header = ["\\textbf{M\\^es/Ano}"] + [f"\\textbf{{{day:02d}}}" for day in range(1, 32)]
    lines.append(" & ".join(header) + " \\\\")
    lines.append("\\hline")

    for _, row in pivot.iterrows():
        row_values = [format_month_label(str(row["month"]))]

        for day_col in day_cols:
            row_values.append(format_latex_value(row[day_col], decimals, metric))

        lines.append(" & ".join(row_values) + " \\\\")

    lines.extend([
        "\\hline",
        "\\end{tabular}%",
        "}",
        "\\end{table}",
        "",
    ])

    output_path.write_text("\n".join(lines), encoding="utf-8")


def write_daily_metric_tables(daily_df: pd.DataFrame, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    table_df = daily_df.copy()
    table_df["day"] = (
        pd.to_numeric(table_df["timestamp_date"], errors="coerce").astype("Int64") % 100
    )
    table_df["month_order"] = table_df["month"].apply(month_sort_key)

    month_order = (
        table_df[["month", "month_order"]]
        .drop_duplicates()
        .sort_values("month_order")["month"]
        .tolist()
    )

    day_columns = [f"dia_{day:02d}" for day in range(1, 32)]

    for metric in DAILY_TABLE_METRICS:
        pivot = table_df.pivot_table(
            index="month",
            columns="day",
            values=metric,
            aggfunc="mean",
        )

        pivot = pivot.reindex(month_order)
        pivot = pivot.reindex(columns=range(1, 32))
        pivot.columns = day_columns
        pivot = pivot.reset_index()

        output_path = output_dir / f"{metric}_por_dia.csv"
        pivot.to_csv(output_path, index=False, float_format="%.6f")

        latex_path = output_dir / f"{metric}_por_dia.tex"
        write_daily_metric_latex_table(pivot, metric, latex_path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", default="results")
    args = parser.parse_args()

    results_dir = Path(args.results_dir).resolve()

    if not results_dir.exists():
        raise FileNotFoundError(f"Pasta de resultados nao encontrada: {results_dir}")

    result_files = sorted(
        results_dir.glob("*_results.txt"),
        key=lambda path: month_sort_key(parse_month_name(path)),
    )

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

    metric_tables_dir = results_dir / "tabelas_metricas_por_dia"
    write_daily_metric_tables(all_daily_df, metric_tables_dir)

    print(f"Arquivo geral diario gerado: {all_daily_path}")
    print(f"Resumo geral gerado: {general_path}")
    print(f"Tabelas por dia geradas em: {metric_tables_dir}")


if __name__ == "__main__":
    main()
