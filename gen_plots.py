from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd
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

    for col in required:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df = df.dropna(subset=["sample", "timestamp_date", "timestamp_time"])
    df["timestamp_date"] = df["timestamp_date"].astype(int)

    return df


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
) -> None:
    df = read_result_file(result_file)
    day_df = df[df["timestamp_date"] == target_date].sort_values("sample").copy()

    if day_df.empty:
        raise ValueError(f"Nenhuma amostra encontrada para a data {target_date} em {result_file.name}")

    month = parse_month_name(result_file)
    x = range(len(day_df))

    voltage = day_df["voltage"] / voltage_scale
    current = day_df["current"] / current_scale

    fig, axes = plt.subplots(4, 1, figsize=(11, 8), sharex=True)

    axes[0].plot(x, voltage)
    axes[0].set_title("Input - Vpv")
    axes[0].set_ylabel("Voltage")

    axes[1].plot(x, current)
    axes[1].set_title("Input - Ipv")
    axes[1].set_ylabel("Current")

    axes[2].plot(x, day_df["error"])
    axes[2].set_title("Error (dP/dV)")
    axes[2].set_ylabel("Error")

    axes[3].plot(x, day_df["delta_e"])
    axes[3].set_title("CE (dE)")
    axes[3].set_ylabel("CE")
    axes[3].set_xlabel("Samples")

    fig.tight_layout()

    output_path = output_dir / f"{month}_{target_date}_inputs_error_ce.png"
    fig.savefig(output_path, dpi=300)
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(9, 5))
    ax.plot(x, day_df["duty"])
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
    ax.set_title(f"Power - {target_date}")
    ax.set_xlabel("Samples")
    ax.set_ylabel("Power")
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
            "Potencia maxima diaria media por mes",
            "Power",
            "monthly_p_best_final.png",
        ),
        (
            "N_conv_98_mean",
            "N_conv_98_std",
            "Amostras ate 98% da melhor potencia diaria",
            "Samples",
            "monthly_n_conv_98.png",
        ),
        (
            "T_conv_98_seconds_mean",
            "T_conv_98_seconds_std",
            "Tempo ate 98% da melhor potencia diaria",
            "Seconds",
            "monthly_t_conv_98_seconds.png",
        ),
        (
            "duty_std_after_conv_mean",
            "duty_std_after_conv_std",
            "Oscilacao media do duty apos convergencia",
            "Duty standard deviation",
            "monthly_duty_std_after_conv.png",
        ),
        (
            "P_ripple_after_conv_mean",
            "P_ripple_after_conv_std",
            "Ripple medio de potencia apos convergencia",
            "Power standard deviation",
            "monthly_power_ripple_after_conv.png",
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


def plot_score_like_monthly_summary(general_df: pd.DataFrame, output_dir: Path) -> None:
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
        ("P_best_final", "Potencia maxima diaria", "Power", "daily_p_best_final_by_month.png"),
        ("T_conv_98_seconds", "Tempo diario ate 98% da potencia maxima", "Seconds", "daily_t_conv_98_by_month.png"),
        ("duty_std_after_conv", "Oscilacao diaria do duty apos convergencia", "Duty standard deviation", "daily_duty_std_by_month.png"),
        ("P_ripple_after_conv", "Ripple diario de potencia apos convergencia", "Power standard deviation", "daily_power_ripple_by_month.png"),
        ("mean_abs_error", "Erro absoluto medio diario", "Mean absolute error", "daily_mean_abs_error_by_month.png"),
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
    required = {"month", "duty_std_after_conv_mean", "T_conv_98_seconds_mean"}

    if not required.issubset(general_df.columns):
        print("Pulando scatter: colunas insuficientes.")
        return

    fig, ax = plt.subplots(figsize=(8, 6))

    x = pd.to_numeric(general_df["T_conv_98_seconds_mean"], errors="coerce")
    y = pd.to_numeric(general_df["duty_std_after_conv_mean"], errors="coerce")

    ax.scatter(x, y)

    for _, row in general_df.iterrows():
        ax.annotate(str(row["month"]), (row["T_conv_98_seconds_mean"], row["duty_std_after_conv_mean"]))

    ax.set_title("Trade-off: tempo de convergencia vs estabilidade do duty")
    ax.set_xlabel("Mean T_conv_98_seconds")
    ax.set_ylabel("Mean duty_std_after_conv")
    ax.grid(True)

    fig.tight_layout()
    fig.savefig(output_dir / "tradeoff_convergence_vs_duty_stability.png", dpi=300)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", default="results")
    parser.add_argument("--output-dir", default="graficos_uteis")
    parser.add_argument("--day-result-file", default="Apr_2023_results.txt")
    parser.add_argument("--target-date", type=int, default=20230415)
    parser.add_argument("--voltage-scale", type=float, default=1.0)
    parser.add_argument("--current-scale", type=float, default=1.0)
    args = parser.parse_args()

    results_dir = Path(args.results_dir).resolve()
    output_dir = Path(args.output_dir).resolve()

    ensure_dir(output_dir)

    day_result_file = results_dir / args.day_result_file

    if day_result_file.exists():
        plot_day_inputs_and_fuzzy(
            result_file=day_result_file,
            output_dir=output_dir,
            target_date=args.target_date,
            voltage_scale=args.voltage_scale,
            current_scale=args.current_scale,
        )
    else:
        print(f"Arquivo nao encontrado para grafico diario: {day_result_file}")

    general_path = results_dir / "metrics_general.csv"
    daily_path = results_dir / "metrics_daily_all.csv"

    if general_path.exists():
        general_df = read_general_metrics(general_path)
        plot_monthly_comparisons(general_df, output_dir)
        plot_score_like_monthly_summary(general_df, output_dir)
        plot_tradeoff_scatter(general_df, output_dir)
    else:
        print(f"Arquivo nao encontrado: {general_path}")

    if daily_path.exists():
        daily_df = read_daily_metrics(daily_path)
        plot_daily_metric_lines(daily_df, output_dir)
    else:
        print(f"Arquivo nao encontrado: {daily_path}")

    print(f"Graficos salvos em: {output_dir}")


if __name__ == "__main__":
    main()
