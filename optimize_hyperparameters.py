from __future__ import annotations

import argparse
import itertools
import random
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import pandas as pd


VHDL_FILES = [
    "hybrid_mppt_pkg.vhd",
    "mppt_measurement_unit.vhd",
    "mppt_fuzzy_ffp_unit.vhd",
    "pso_particle_update_unit.vhd",
    "hybrid_pso_fuzzy_mppt.vhd",
    "tb_hybrid_pso_fuzzy_export.vhd",
]

# Rodada 1: busca ampla nos parametros que mais afetam a dinamica
# e que sao faceis de interpretar.
STAGE1_PARAM_RANGES = {
    # PSO
    "W_PSO_G_TB": [30, 40, 50, 60, 70],
    "C1_PSO_G_TB": [30, 40, 50, 60, 70],
    "C2_PSO_G_TB": [20, 30, 40, 50, 60],

    # Espaco de busca
    "SEARCH_RADIUS_G_TB": [6, 8, 10, 12, 16, 20],
    "SEARCH_CENTER_MODE_G_TB": [0, 1, 2],

    # Fuzzy / Fokker-Planck
    "DEADZONE_G_TB": [1, 2, 3, 4, 5],
    "FOKKER_STEP_MAX_G_TB": [4, 6, 8, 10, 12],
    "FUZZY_STEP_G_TB": [20, 30, 40],

    # Hipotese de direcao do duty
    "DUTY_DIRECTION_G_TB": [-1, 1],
}

# Fixos na rodada 1.
# Esses parametros sao fixados inicialmente para nao explodir o espaco de busca.
STAGE1_FIXED_PARAMS = {
    "SETTLE_CYCLES_G": 1,
    "RHO_MIN_G_TB": 53,
    "RHO_MAX_G_TB": 56,
    "VEL_MIN_G_TB": -20,
    "VEL_MAX_G_TB": 20,
    "FOKKER_STEP_MIN_G_TB": 1,
    "FUZZY_EDGE_G_TB": 90,
    "POWER_SCALE_DEN_G_TB": 2048,
}

# Rodada 2: refinamento.
# Aqui a gente fixa os melhores parametros da rodada 1 e varia parametros
# mais estruturais/sensiveis.
STAGE2_PARAM_RANGES = {
    "FUZZY_EDGE_G_TB": [70, 80, 90, 100],
    "VEL_MIN_G_TB": [-30, -20, -10],
    "VEL_MAX_G_TB": [10, 20, 30],
    "RHO_MIN_G_TB": [50, 53, 55],
    "RHO_MAX_G_TB": [56, 60, 65],
}

ALL_GENERIC_KEYS = sorted(
    set(STAGE1_PARAM_RANGES)
    | set(STAGE1_FIXED_PARAMS)
    | set(STAGE2_PARAM_RANGES)
)


def run_cmd(cmd: list[str], cwd: Path, log_file: Path | None = None) -> None:
    print(" ".join(cmd))

    if log_file is None:
        subprocess.run(cmd, cwd=cwd, check=True)
        return

    with log_file.open("w", encoding="utf-8", errors="ignore") as f:
        subprocess.run(cmd, cwd=cwd, check=True, stdout=f, stderr=subprocess.STDOUT)


def compile_project(project_dir: Path, clean_work: bool) -> None:
    work_dir = project_dir / "work"

    if clean_work and work_dir.exists():
        shutil.rmtree(work_dir)

    if not work_dir.exists():
        run_cmd(["vlib", "work"], cwd=project_dir)

    for file_name in VHDL_FILES:
        file_path = project_dir / file_name

        if not file_path.exists():
            raise FileNotFoundError(f"Arquivo VHDL nao encontrado: {file_path}")

        run_cmd(["vcom", "-2008", file_name], cwd=project_dir)


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


def create_subset_dataset(source_dataset: Path, subset_dataset: Path, n_days: int) -> list[int]:
    df = pd.read_csv(
        source_dataset,
        sep=r"\s+",
        header=None,
        names=["timestamp_date", "timestamp_time", "voltage", "current"],
        engine="python",
    )

    if df.empty:
        raise ValueError(f"Dataset vazio: {source_dataset}")

    dates = sorted(df["timestamp_date"].dropna().astype(int).unique().tolist())

    if len(dates) < n_days:
        raise ValueError(
            f"Dataset tem apenas {len(dates)} dias, mas n_days={n_days}: {source_dataset}"
        )

    selected_dates = dates[:n_days]
    subset = df[df["timestamp_date"].astype(int).isin(selected_dates)].copy()

    subset_dataset.parent.mkdir(parents=True, exist_ok=True)
    subset.to_csv(subset_dataset, sep=" ", index=False, header=False)

    return selected_dates


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


def calculate_metrics(result_file: Path) -> dict[str, float]:
    df = pd.read_csv(result_file, sep=r"\s+", engine="python")

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
        raise ValueError(f"{result_file.name} sem colunas obrigatorias: {sorted(missing)}")

    for col in required:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df = df.dropna(subset=["sample", "timestamp_date", "timestamp_time"])
    df["timestamp_date"] = df["timestamp_date"].astype(int)
    df["timestamp_seconds"] = df["timestamp_time"].apply(parse_hhmmss_to_seconds)

    daily_rows = []

    for _, day_df in df.groupby("timestamp_date", sort=True):
        day_df = day_df.sort_values("sample").copy()

        if day_df.empty:
            continue

        day_df["local_gbest_power"] = day_df["power_now"].cummax()

        p_best_final = float(day_df["power_now"].max())

        if p_best_final <= 0:
            n_conv_98 = -1
            t_conv_98 = -1.0
            steady = day_df
        else:
            threshold = 0.98 * p_best_final
            conv_df = day_df[day_df["local_gbest_power"] >= threshold]

            if conv_df.empty:
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

        duty_diff = day_df["duty"].diff().abs().dropna()

        daily_rows.append({
            "P_best_final": p_best_final,
            "N_conv_98": float(n_conv_98),
            "T_conv_98_seconds": float(t_conv_98),
            "duty_std_after_conv": std_or_zero(steady["duty"]),
            "duty_step_mean": mean_or_zero(duty_diff),
            "duty_range_after_conv": float(steady["duty"].max() - steady["duty"].min()) if len(steady) else 0.0,
            "P_ripple_after_conv": std_or_zero(steady["power_now"]),
            "mean_abs_error": mean_or_zero(day_df["error"].abs()),
            "std_abs_error": std_or_zero(day_df["error"].abs()),
        })

    if not daily_rows:
        raise ValueError(f"Nenhuma metrica diaria calculada para {result_file}")

    daily = pd.DataFrame(daily_rows)

    metrics = {
        f"{col}_mean": float(daily[col].mean())
        for col in daily.columns
    }

    metrics.update({
        f"{col}_std": float(daily[col].std(ddof=1)) if len(daily) > 1 else 0.0
        for col in daily.columns
    })

    # Com o testbench open-loop atual, power_now vem do dataset e nao do duty_out.
    # Por isso o score prioriza estabilidade do duty, que depende diretamente do controlador.
    metrics["score"] = -(
        1.00 * metrics["duty_std_after_conv_mean"]
        + 0.50 * metrics["duty_step_mean_mean"]
        + 0.10 * metrics["duty_range_after_conv_mean"]
    )

    return metrics


def make_param_sets(
    param_ranges: dict[str, list[int]],
    mode: str,
    n_trials: int,
    seed: int,
) -> list[dict[str, int]]:
    keys = list(param_ranges.keys())

    if mode == "grid":
        all_sets = [
            dict(zip(keys, values))
            for values in itertools.product(*(param_ranges[k] for k in keys))
        ]
        return all_sets[:n_trials] if n_trials > 0 else all_sets

    if n_trials <= 0:
        raise ValueError("n_trials precisa ser > 0 quando mode='random'.")

    rng = random.Random(seed)
    seen = set()
    param_sets = []

    max_unique = 1
    for values in param_ranges.values():
        max_unique *= len(values)

    target = min(n_trials, max_unique)

    while len(param_sets) < target:
        params = {key: rng.choice(values) for key, values in param_ranges.items()}
        signature = tuple(params[key] for key in keys)

        if signature in seen:
            continue

        seen.add(signature)
        param_sets.append(params)

    return param_sets


def normalize_int(value: object) -> int:
    return int(round(float(value)))


def extract_params_from_row(row: pd.Series) -> dict[str, int]:
    params = {}

    for key in ALL_GENERIC_KEYS:
        if key in row and not pd.isna(row[key]):
            params[key] = normalize_int(row[key])

    return params


def run_trial(
    stage: str,
    trial_idx: int,
    params: dict[str, int],
    project_dir: Path,
    dataset_file: Path,
    trial_dir: Path,
    base_trial: int | None = None,
) -> dict[str, float | int | str]:
    trial_name = f"{stage}_trial_{trial_idx:04d}"
    result_file = trial_dir / f"{trial_name}_results.txt"
    log_file = trial_dir / f"{trial_name}_vsim.log"
    wlf_file = trial_dir / f"{trial_name}.wlf"

    cmd = [
        "vsim",
        "-c",
        "work.tb_hybrid_pso_fuzzy_export",
        "-wlf",
        wlf_file.as_posix(),
        "-l",
        log_file.as_posix(),
        f"-gDATASET_FILE={dataset_file.as_posix()}",
        f"-gRESULT_FILE={result_file.as_posix()}",
    ]

    for key, value in params.items():
        cmd.append(f"-g{key}={value}")

    cmd.extend(["-do", "run -all; quit -f"])

    try:
        run_cmd(cmd, cwd=project_dir, log_file=log_file)
        metrics = calculate_metrics(result_file)

        row: dict[str, float | int | str] = {
            "stage": stage,
            "trial": trial_idx,
            "base_trial": -1 if base_trial is None else base_trial,
            "status": "OK",
        }

        row.update(params)
        row.update(metrics)

        return row

    except Exception as exc:
        row = {
            "stage": stage,
            "trial": trial_idx,
            "base_trial": -1 if base_trial is None else base_trial,
            "status": "ERROR",
            "error_message": str(exc),
        }
        row.update(params)
        return row


def run_trials(
    stage: str,
    param_sets: list[dict[str, int]],
    project_dir: Path,
    dataset_file: Path,
    trial_dir: Path,
    max_workers: int,
    base_trials: list[int | None] | None = None,
) -> pd.DataFrame:
    rows = []

    if base_trials is None:
        base_trials = [None] * len(param_sets)

    if max_workers <= 1:
        for idx, (params, base_trial) in enumerate(zip(param_sets, base_trials)):
            print(f"\n=== {stage} trial {idx + 1}/{len(param_sets)} ===")
            rows.append(run_trial(stage, idx, params, project_dir, dataset_file, trial_dir, base_trial))
    else:
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {
                executor.submit(run_trial, stage, idx, params, project_dir, dataset_file, trial_dir, base_trial): idx
                for idx, (params, base_trial) in enumerate(zip(param_sets, base_trials))
            }

            for future in as_completed(futures):
                idx = futures[future]
                print(f"{stage} trial finalizado: {idx}")
                rows.append(future.result())

    return pd.DataFrame(rows)


def save_ranked_results(df: pd.DataFrame, out_dir: Path, prefix: str, top_n: int = 20) -> pd.DataFrame:
    out_dir.mkdir(parents=True, exist_ok=True)
    out_csv = out_dir / f"{prefix}_results.csv"
    best_csv = out_dir / f"{prefix}_best.csv"

    df.to_csv(out_csv, index=False)

    ok = df[df["status"] == "OK"].copy()

    if ok.empty or "score" not in ok.columns:
        print(f"Nenhum resultado OK em {prefix}.")
        return ok

    ok = ok.sort_values("score", ascending=False)
    ok.head(top_n).to_csv(best_csv, index=False)

    print(f"\nTop 10 - {prefix}:")
    cols = [
        "stage",
        "trial",
        "base_trial",
        "score",
        "W_PSO_G_TB",
        "C1_PSO_G_TB",
        "C2_PSO_G_TB",
        "DUTY_DIRECTION_G_TB",
        "SEARCH_CENTER_MODE_G_TB",
        "SEARCH_RADIUS_G_TB",
        "DEADZONE_G_TB",
        "FOKKER_STEP_MAX_G_TB",
        "FUZZY_STEP_G_TB",
        "FUZZY_EDGE_G_TB",
        "VEL_MIN_G_TB",
        "VEL_MAX_G_TB",
        "RHO_MIN_G_TB",
        "RHO_MAX_G_TB",
        "duty_std_after_conv_mean",
        "duty_step_mean_mean",
        "duty_range_after_conv_mean",
    ]
    cols = [c for c in cols if c in ok.columns]
    print(ok[cols].head(10).to_string(index=False))

    print(f"\nResultados completos: {out_csv}")
    print(f"Melhores resultados: {best_csv}")

    return ok


def build_stage2_param_sets(
    stage1_best: pd.DataFrame,
    top_k: int,
    mode: str,
    trials_per_base: int,
    seed: int,
) -> tuple[list[dict[str, int]], list[int | None]]:
    if stage1_best.empty:
        raise ValueError("stage1_best vazio. Nao da para montar rodada 2.")

    selected = stage1_best.head(top_k)

    final_param_sets: list[dict[str, int]] = []
    base_trials: list[int | None] = []

    for base_idx, (_, row) in enumerate(selected.iterrows()):
        base_params = extract_params_from_row(row)

        # Garante que todos os fixos necessarios existem.
        for key, value in STAGE1_FIXED_PARAMS.items():
            base_params.setdefault(key, value)

        stage2_sets = make_param_sets(
            STAGE2_PARAM_RANGES,
            mode=mode,
            n_trials=trials_per_base,
            seed=seed + base_idx,
        )

        for stage2_params in stage2_sets:
            merged = {**base_params, **stage2_params}
            final_param_sets.append(merged)
            base_trials.append(normalize_int(row["trial"]) if "trial" in row else None)

    return final_param_sets, base_trials


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", default=".")
    parser.add_argument("--dataset", default="dados_pre_processados/Apr_2023_dataset.txt")
    parser.add_argument("--out-dir", default="optimization_runs")
    parser.add_argument("--n-days", type=int, default=5)

    parser.add_argument("--stage", choices=["stage1", "stage2", "both"], default="both")

    parser.add_argument("--stage1-mode", choices=["random", "grid"], default="random")
    parser.add_argument("--stage1-trials", type=int, default=50)

    parser.add_argument("--stage2-mode", choices=["random", "grid"], default="random")
    parser.add_argument("--stage2-top-k", type=int, default=5)
    parser.add_argument("--stage2-trials-per-base", type=int, default=30)

    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--compile", action="store_true")
    parser.add_argument("--clean-work", action="store_true")
    parser.add_argument("--max-workers", type=int, default=1)

    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()
    source_dataset = (project_dir / args.dataset).resolve()
    out_dir = (project_dir / args.out_dir).resolve()
    stage1_dir = out_dir / "stage1"
    stage2_dir = out_dir / "stage2"
    stage1_trial_dir = stage1_dir / "trials"
    stage2_trial_dir = stage2_dir / "trials"
    subset_dataset = out_dir / f"subset_{source_dataset.stem}_{args.n_days}_days.txt"

    if not source_dataset.exists():
        raise FileNotFoundError(f"Dataset nao encontrado: {source_dataset}")

    out_dir.mkdir(parents=True, exist_ok=True)
    stage1_trial_dir.mkdir(parents=True, exist_ok=True)
    stage2_trial_dir.mkdir(parents=True, exist_ok=True)

    selected_dates = create_subset_dataset(
        source_dataset=source_dataset,
        subset_dataset=subset_dataset,
        n_days=args.n_days,
    )

    print(f"Dataset de otimizacao: {subset_dataset}")
    print(f"Dias usados: {selected_dates}")

    if args.compile:
        compile_project(project_dir, clean_work=args.clean_work)

    stage1_best = pd.DataFrame()

    if args.stage in ("stage1", "both"):
        stage1_param_sets = make_param_sets(
            STAGE1_PARAM_RANGES,
            mode=args.stage1_mode,
            n_trials=args.stage1_trials,
            seed=args.seed,
        )

        stage1_param_sets = [
            {**STAGE1_FIXED_PARAMS, **params}
            for params in stage1_param_sets
        ]

        print("\n=== Rodada 1 ===")
        print(f"Configuracoes: {len(stage1_param_sets)}")
        print(f"Paralelismo: {args.max_workers}")

        stage1_results = run_trials(
            stage="stage1",
            param_sets=stage1_param_sets,
            project_dir=project_dir,
            dataset_file=subset_dataset,
            trial_dir=stage1_trial_dir,
            max_workers=args.max_workers,
        )

        stage1_best = save_ranked_results(stage1_results, stage1_dir, "stage1")

    if args.stage in ("stage2", "both"):
        if args.stage == "stage2":
            stage1_best_path = stage1_dir / "stage1_best.csv"

            if not stage1_best_path.exists():
                raise FileNotFoundError(
                    f"Para rodar apenas stage2, primeiro gere: {stage1_best_path}"
                )

            stage1_best = pd.read_csv(stage1_best_path)

        stage2_param_sets, base_trials = build_stage2_param_sets(
            stage1_best=stage1_best,
            top_k=args.stage2_top_k,
            mode=args.stage2_mode,
            trials_per_base=args.stage2_trials_per_base,
            seed=args.seed + 1000,
        )

        print("\n=== Rodada 2 ===")
        print(f"Top-k da rodada 1 usados: {args.stage2_top_k}")
        print(f"Configuracoes por base: {args.stage2_trials_per_base}")
        print(f"Total de configuracoes: {len(stage2_param_sets)}")
        print(f"Paralelismo: {args.max_workers}")

        stage2_results = run_trials(
            stage="stage2",
            param_sets=stage2_param_sets,
            project_dir=project_dir,
            dataset_file=subset_dataset,
            trial_dir=stage2_trial_dir,
            max_workers=args.max_workers,
            base_trials=base_trials,
        )

        stage2_best = save_ranked_results(stage2_results, stage2_dir, "stage2")

        if not stage2_best.empty:
            final_csv = out_dir / "optimization_final_best.csv"
            stage2_best.head(20).to_csv(final_csv, index=False)
            print(f"\nMelhores finais salvos em: {final_csv}")

    print(
        "\nAVISO: com o testbench open-loop atual, power_now nao depende do duty_out. "
        "Portanto, esta otimizacao serve principalmente para estabilidade do duty, "
        "nao para provar ganho real de MPPT em malha fechada."
    )


if __name__ == "__main__":
    main()
