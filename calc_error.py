from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd
import numpy as np


def load_dataset(path: Path) -> pd.DataFrame:
    df = pd.read_csv(
        path,
        sep=r"\s+",
        header=None,
        names=["timestamp_date", "timestamp_time", "voltage", "current"],
        engine="python",
    )

    for col in ["voltage", "current"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df = df.dropna(subset=["voltage", "current"]).copy()
    df["voltage"] = df["voltage"].astype(int)
    df["current"] = df["current"].astype(int)

    return df


def analyze(
    df: pd.DataFrame,
    power_scale_den: int,
    deadzones: list[int],
    target_error: int,
    percentile: float,
) -> pd.DataFrame:
    df = df.copy()

    df["power"] = (df["voltage"] * df["current"]) // power_scale_den
    df["delta_p"] = df["power"].diff()
    df["delta_v"] = df["voltage"].diff()

    df = df.dropna(subset=["delta_p", "delta_v"]).copy()
    df["delta_p"] = df["delta_p"].astype(int)
    df["delta_v"] = df["delta_v"].astype(int)

    rows = []

    for deadzone in deadzones:
        valid = df[df["delta_v"].abs() >= deadzone].copy()

        if valid.empty:
            rows.append({
                "DELTA_V_DEADZONE": deadzone,
                "valid_points": 0,
                "ignored_percent": 100.0,
                "p50_abs_slope": 0.0,
                "p90_abs_slope": 0.0,
                "p95_abs_slope": 0.0,
                "p99_abs_slope": 0.0,
                "recommended_ERROR_GAIN": 1,
                "estimated_saturation_percent": 0.0,
            })
            continue

        valid["slope"] = np.trunc(valid["delta_p"] / valid["delta_v"]).astype(int)
        valid["abs_slope"] = valid["slope"].abs()

        p50 = float(np.percentile(valid["abs_slope"], 50))
        p90 = float(np.percentile(valid["abs_slope"], 90))
        p95 = float(np.percentile(valid["abs_slope"], 95))
        p99 = float(np.percentile(valid["abs_slope"], 99))

        ref = float(np.percentile(valid["abs_slope"], percentile))

        if ref <= 0:
            gain = 1
        else:
            gain = max(1, int(target_error // ref))

        valid["error_est"] = valid["slope"] * gain
        saturation_percent = float((valid["error_est"].abs() >= 100).mean() * 100.0)

        ignored_percent = float((1.0 - (len(valid) / len(df))) * 100.0)

        rows.append({
            "DELTA_V_DEADZONE": deadzone,
            "valid_points": int(len(valid)),
            "ignored_percent": ignored_percent,
            "p50_abs_slope": p50,
            "p90_abs_slope": p90,
            "p95_abs_slope": p95,
            "p99_abs_slope": p99,
            "recommended_ERROR_GAIN": gain,
            "estimated_saturation_percent": saturation_percent,
        })

    return pd.DataFrame(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", default="dados_pre_processados/Apr_2023_dataset.txt")
    parser.add_argument("--power-scale-den", type=int, default=2048)
    parser.add_argument("--target-error", type=int, default=80)
    parser.add_argument("--percentile", type=float, default=95)
    parser.add_argument("--output", default="error_scaling_analysis.csv")

    args = parser.parse_args()

    dataset = Path(args.dataset)
    df = load_dataset(dataset)

    result = analyze(
        df=df,
        power_scale_den=args.power_scale_den,
        deadzones=[4, 8, 16, 24, 32, 48, 64],
        target_error=args.target_error,
        percentile=args.percentile,
    )

    result.to_csv(args.output, index=False)

    print(result.to_string(index=False))
    print(f"\nArquivo salvo em: {args.output}")


if __name__ == "__main__":
    main()
