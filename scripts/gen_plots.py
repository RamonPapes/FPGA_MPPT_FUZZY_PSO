from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def parse_month_name(path: Path) -> str:
    name = path.stem

    if name.endswith("_results"):
        name = name[: -len("_results")]

    if name.startswith("resultados_hybrid_"):
        name = name[len("resultados_hybrid_") :]

    return name


def read_result_file(path: Path) -> pd.DataFrame:
    df = pd.read_csv(path, sep=r"\s+", engine="python")

    required = {
        "sample",
        "timestamp_date",
        "timestamp_time",
        "voltage",
        "current",
        "power_now",
        "duty",
        "error",
        "delta_e",
    }

    missing = required - set(df.columns)

    if missing:
        raise ValueError(f"{path.name} nao possui as colunas obrigatorias: {sorted(missing)}")

    optional_numeric = {
        "gbest_duty",
        "gbest_power",
        "fuzzy_delta",
        "POWER_SCALE_DEN",
    }

    for col in required | (optional_numeric & set(df.columns)):
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df = df.dropna(subset=["sample", "timestamp_date", "timestamp_time"])
    df["timestamp_date"] = df["timestamp_date"].astype(int)

    return df


def get_day_metric(daily_df: pd.DataFrame | None, target_date: int, column: str) -> float | None:
    if daily_df is None or column not in daily_df.columns:
        return None

    rows = daily_df[daily_df["timestamp_date"] == target_date]

    if rows.empty:
        return None

    value = pd.to_numeric(rows.iloc[0][column], errors="coerce")

    if pd.isna(value):
        return None

    return float(value)


def read_general_metrics(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f"Arquivo nao encontrado: {path}")

    df = pd.read_csv(path)

    if "month" not in df.columns:
        raise ValueError(f"{path.name} nao possui coluna 'month'.")

    return df


def read_daily_metrics(path: Path) -> pd.DataFrame:
    if not path.exists():
        raise FileNotFoundError(f"Arquivo nao encontrado: {path}")

    df = pd.read_csv(path)

    required = {"month", "timestamp_date"}

    missing = required - set(df.columns)

    if missing:
        raise ValueError(f"{path.name} nao possui as colunas obrigatorias: {sorted(missing)}")

    df["timestamp_date"] = pd.to_numeric(df["timestamp_date"], errors="coerce").astype("Int64")
    df["day"] = df["timestamp_date"].astype(str).str[-2:].astype(int)

    return df


def plot_day_inputs_and_fuzzy(
    result_file: Path,
    output_dir: Path,
    target_date: int,
    voltage_scale: float,
    current_scale: float,
    daily_df: pd.DataFrame | None = None,
) -> None:
    df = read_result_file(result_file)
    day_df = df[df["timestamp_date"] == target_date].sort_values("sample").copy()

    if day_df.empty:
        raise ValueError(f"Nenhuma amostra encontrada para a data {target_date} em {result_file.name}")

    month = parse_month_name(result_file)
    x = range(len(day_df))
    stable_sample = get_day_metric(daily_df, target_date, "N_conv_duty_stable")

    voltage = day_df["voltage"] / voltage_scale
    current = day_df["current"] / current_scale

    fig, axes = plt.subplots(4, 1, figsize=(11, 8), sharex=True)

    axes[0].plot(x, voltage)
    axes[0].set_title("Input - Vpv")
    axes[0].set_ylabel("Voltage (V)")

    axes[1].plot(x, current)
    axes[1].set_title("Input - Ipv")
    axes[1].set_ylabel("Current (p.u.)")

    axes[2].plot(x, day_df["error"])
    axes[2].set_title("Error (dP/dV)")
    axes[2].set_ylabel("Error")

    axes[3].plot(x, day_df["delta_e"])
    axes[3].set_title("CE (dE)")
    axes[3].set_ylabel("CE")
    axes[3].set_xlabel("Samples")

    if stable_sample is not None and stable_sample >= 0:
        for ax in axes:
            ax.axvline(stable_sample, color="tab:green", linestyle="--", linewidth=1)

    fig.tight_layout()

    output_path = output_dir / f"{month}_{target_date}_inputs_error_ce.png"
    fig.savefig(output_path, dpi=300)
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(9, 5))
    ax.plot(x, day_df["duty"])
    if "gbest_duty" in day_df.columns:
        ax.plot(x, day_df["gbest_duty"], linewidth=1, alpha=0.75, label="gbest duty")
        ax.legend()
    if stable_sample is not None and stable_sample >= 0:
        ax.axvline(stable_sample, color="tab:green", linestyle="--", linewidth=1)
    ax.set_title(f"Duty Cycle - {target_date}")
    ax.set_xlabel("Samples")
    ax.set_ylabel("Duty Cycle (%)")
    ax.grid(True)

    fig.tight_layout()

    output_path = output_dir / f"{month}_{target_date}_duty_cycle.png"
    fig.savefig(output_path, dpi=300)
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(9, 5))
    ax.plot(x, day_df["power_now"])
    if "gbest_power" in day_df.columns:
        ax.plot(x, day_df["gbest_power"], linewidth=1, alpha=0.75, label="gbest power")
        ax.legend()
    ax.set_title(f"Power - {target_date}")
    ax.set_xlabel("Samples")
    ax.set_ylabel("Scaled power")
    ax.grid(True)

    fig.tight_layout()

    output_path = output_dir / f"{month}_{target_date}_power.png"
    fig.savefig(output_path, dpi=300)
    plt.close(fig)


def bar_with_error(
    df: pd.DataFrame,
    output_dir: Path,
    mean_col: str,
    std_col: str,
    title: str,
    ylabel: str,
    filename: str,
) -> None:
    if mean_col not in df.columns:
        print(f"Pulando {filename}: coluna ausente {mean_col}")
        return

    months = df["month"].astype(str)
    means = pd.to_numeric(df[mean_col], errors="coerce")

    if std_col in df.columns:
        stds = pd.to_numeric(df[std_col], errors="coerce").fillna(0.0)
    else:
        stds = None

    fig, ax = plt.subplots(figsize=(11, 5))

    ax.bar(months, means, yerr=stds, capsize=4)
    ax.set_title(title)
    ax.set_ylabel(ylabel)
    ax.set_xlabel("Month")
    ax.tick_params(axis="x", rotation=45)

    fig.tight_layout()
    fig.savefig(output_dir / filename, dpi=300)
    plt.close(fig)


def plot_monthly_comparisons(general_df: pd.DataFrame, output_dir: Path) -> None:
    plots = [
        (
            "P_best_final_mean",
            "P_best_final_std",
            "Potencia maxima diaria do historico",
            "Scaled power",
            "monthly_p_best_final.png",
        ),
        (
            "N_conv_duty_stable_mean",
            "N_conv_duty_stable_std",
            "Amostras ate estabilidade do duty",
            "Samples",
            "monthly_n_conv_duty_stable.png",
        ),
        (
            "T_conv_duty_stable_seconds_mean",
            "T_conv_duty_stable_seconds_std",
            "Tempo ate estabilidade do duty",
            "Seconds",
            "monthly_t_conv_duty_stable_seconds.png",
        ),
        (
            "duty_std_after_stable_mean",
            "duty_std_after_stable_std",
            "Oscilacao do duty apos estabilidade",
            "Duty standard deviation",
            "monthly_duty_std_after_stable.png",
        ),
        (
            "duty_step_mean_after_stable_mean",
            "duty_step_mean_after_stable_std",
            "Passo medio do duty apos estabilidade",
            "Mean absolute duty step",
            "monthly_duty_step_mean_after_stable.png",
        ),
        (
            "duty_saturation_after_stable_percent_mean",
            "duty_saturation_after_stable_percent_std",
            "Saturacao do duty apos estabilidade",
            "Percent",
            "monthly_duty_saturation_after_stable.png",
        ),
        (
            "stability_score_mean",
            "stability_score_std",
            "Score de estabilidade do controlador",
            "Score",
            "monthly_stability_score.png",
        ),
        (
            "mean_abs_error_mean",
            "mean_abs_error_std",
            "Erro absoluto medio por mes",
            "Mean absolute error",
            "monthly_mean_abs_error.png",
        ),
    ]

    for mean_col, std_col, title, ylabel, filename in plots:
        bar_with_error(
            df=general_df,
            output_dir=output_dir,
            mean_col=mean_col,
            std_col=std_col,
            title=title,
            ylabel=ylabel,
            filename=filename,
        )

    legacy_plots = [
        (
            "N_conv_98_mean",
            "N_conv_98_std",
            "Amostras ate 98% da melhor potencia historica",
            "Samples",
            "legacy_monthly_n_conv_98.png",
        ),
        (
            "duty_std_after_conv_mean",
            "duty_std_after_conv_std",
            "Oscilacao do duty apos 98% da potencia historica",
            "Duty standard deviation",
            "legacy_monthly_duty_std_after_conv.png",
        ),
        (
            "P_ripple_after_conv_mean",
            "P_ripple_after_conv_std",
            "Variacao historica de potencia apos 98%",
            "Power standard deviation",
            "legacy_monthly_power_ripple_after_conv.png",
        ),
    ]

    for mean_col, std_col, title, ylabel, filename in legacy_plots:
        bar_with_error(
            df=general_df,
            output_dir=output_dir,
            mean_col=mean_col,
            std_col=std_col,
            title=title,
            ylabel=ylabel,
            filename=filename,
        )


def plot_score_like_monthly_summary(general_df: pd.DataFrame, output_dir: Path) -> None:
    if {"month", "stability_score_mean"}.issubset(general_df.columns):
        df = general_df.copy()
        fig, ax = plt.subplots(figsize=(11, 5))
        ax.bar(
            df["month"].astype(str),
            pd.to_numeric(df["stability_score_mean"], errors="coerce"),
        )
        ax.set_title("Resumo comparativo de estabilidade por mes")
        ax.set_ylabel("Stability score")
        ax.set_xlabel("Month")
        ax.tick_params(axis="x", rotation=45)

        fig.tight_layout()
        fig.savefig(output_dir / "monthly_stability_score_like.png", dpi=300)
        plt.close(fig)
        return

    required = {
        "month",
        "duty_std_after_conv_mean",
        "mean_abs_error_mean",
        "P_ripple_after_conv_mean",
    }

    if not required.issubset(general_df.columns):
        print("Pulando grafico resumo: colunas insuficientes.")
        return

    df = general_df.copy()
    df["stability_score_like"] = -(
        pd.to_numeric(df["duty_std_after_conv_mean"], errors="coerce")
        + 0.01 * pd.to_numeric(df["P_ripple_after_conv_mean"], errors="coerce")
        + 0.10 * pd.to_numeric(df["mean_abs_error_mean"], errors="coerce")
    )

    fig, ax = plt.subplots(figsize=(11, 5))
    ax.bar(df["month"].astype(str), df["stability_score_like"])
    ax.set_title("Resumo comparativo de estabilidade por mes")
    ax.set_ylabel("Score relativo")
    ax.set_xlabel("Month")
    ax.tick_params(axis="x", rotation=45)

    fig.tight_layout()
    fig.savefig(output_dir / "monthly_stability_score_like.png", dpi=300)
    plt.close(fig)


def plot_daily_metric_lines(daily_df: pd.DataFrame, output_dir: Path) -> None:
    metrics = [
        ("P_best_final", "Potencia maxima diaria escalada", "Scaled power", "daily_p_best_final_by_month.png"),
        ("T_conv_duty_stable_seconds", "Tempo diario ate estabilidade do duty", "Seconds", "daily_t_conv_duty_stable_by_month.png"),
        ("N_conv_duty_stable", "Amostras ate estabilidade do duty", "Samples", "daily_n_conv_duty_stable_by_month.png"),
        ("duty_std_after_stable", "Oscilacao diaria do duty apos estabilidade", "Duty standard deviation", "daily_duty_std_after_stable_by_month.png"),
        ("duty_step_mean_after_stable", "Passo medio diario do duty apos estabilidade", "Mean absolute duty step", "daily_duty_step_mean_after_stable_by_month.png"),
        ("duty_saturation_after_stable_percent", "Saturacao diaria do duty apos estabilidade", "Percent", "daily_duty_saturation_after_stable_by_month.png"),
        ("stability_score", "Score diario de estabilidade", "Score", "daily_stability_score_by_month.png"),
        ("mean_abs_error", "Erro absoluto medio diario", "Mean absolute error", "daily_mean_abs_error_by_month.png"),
        ("gbest_consistency_violations", "Violacoes diarias de consistencia do gbest", "Count", "daily_gbest_consistency_violations.png"),
        ("gbest_monotonic_violations", "Violacoes diarias de monotonicidade do gbest", "Count", "daily_gbest_monotonic_violations.png"),
    ]

    for metric, title, ylabel, filename in metrics:
        if metric not in daily_df.columns:
            print(f"Pulando {filename}: coluna ausente {metric}")
            continue

        fig, ax = plt.subplots(figsize=(11, 5))

        for month, month_df in daily_df.groupby("month", sort=True):
            month_df = month_df.sort_values("day")
            ax.plot(month_df["day"], pd.to_numeric(month_df[metric], errors="coerce"), marker="o", label=str(month))

        ax.set_title(title)
        ax.set_xlabel("Day of month")
        ax.set_ylabel(ylabel)
        ax.legend(fontsize="small", ncols=2)
        ax.grid(True)

        fig.tight_layout()
        fig.savefig(output_dir / filename, dpi=300)
        plt.close(fig)


def plot_tradeoff_scatter(general_df: pd.DataFrame, output_dir: Path) -> None:
    if {
        "month",
        "duty_std_after_stable_mean",
        "T_conv_duty_stable_seconds_mean",
    }.issubset(general_df.columns):
        x_col = "T_conv_duty_stable_seconds_mean"
        y_col = "duty_std_after_stable_mean"
        filename = "tradeoff_duty_convergence_vs_stability.png"
        title = "Trade-off: convergencia do duty vs estabilidade"
    else:
        x_col = "T_conv_98_seconds_mean"
        y_col = "duty_std_after_conv_mean"
        filename = "tradeoff_convergence_vs_duty_stability.png"
        title = "Trade-off: tempo de convergencia vs estabilidade do duty"

    required = {"month", x_col, y_col}

    if not required.issubset(general_df.columns):
        print("Pulando scatter: colunas insuficientes.")
        return

    fig, ax = plt.subplots(figsize=(8, 6))

    x = pd.to_numeric(general_df[x_col], errors="coerce")
    y = pd.to_numeric(general_df[y_col], errors="coerce")

    ax.scatter(x, y)

    for _, row in general_df.iterrows():
        ax.annotate(str(row["month"]), (row[x_col], row[y_col]))

    ax.set_title(title)
    ax.set_xlabel(x_col)
    ax.set_ylabel(y_col)
    ax.grid(True)

    fig.tight_layout()
    fig.savefig(output_dir / filename, dpi=300)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", default="results")
    parser.add_argument("--output-dir", default="results/graficos_uteis")
    parser.add_argument("--day-result-file", default="Apr_2023_results.txt")
    parser.add_argument("--target-date", type=int, default=20230415)
    parser.add_argument("--voltage-scale", type=float, default=16.0)
    parser.add_argument("--current-scale", type=float, default=32767.0)
    args = parser.parse_args()

    results_dir = Path(args.results_dir).resolve()
    output_dir = Path(args.output_dir).resolve()

    ensure_dir(output_dir)

    day_result_file = results_dir / args.day_result_file
    daily_path = results_dir / "metrics_daily_all.csv"
    daily_df = None

    if daily_path.exists():
        daily_df = read_daily_metrics(daily_path)

    if day_result_file.exists():
        plot_day_inputs_and_fuzzy(
            result_file=day_result_file,
            output_dir=output_dir,
            target_date=args.target_date,
            voltage_scale=args.voltage_scale,
            current_scale=args.current_scale,
            daily_df=daily_df,
        )
    else:
        print(f"Arquivo nao encontrado para grafico diario: {day_result_file}")

    general_path = results_dir / "metrics_general.csv"

    if general_path.exists():
        general_df = read_general_metrics(general_path)
        plot_monthly_comparisons(general_df, output_dir)
        plot_score_like_monthly_summary(general_df, output_dir)
        plot_tradeoff_scatter(general_df, output_dir)
    else:
        print(f"Arquivo nao encontrado: {general_path}")

    if daily_df is not None:
        plot_daily_metric_lines(daily_df, output_dir)
    else:
        print(f"Arquivo nao encontrado: {daily_path}")

    print(f"Graficos salvos em: {output_dir}")


if __name__ == "__main__":
    main()
