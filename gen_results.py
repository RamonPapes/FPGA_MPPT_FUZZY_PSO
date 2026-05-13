from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


VHDL_FILES = [
    "hybrid_mppt_pkg.vhd",
    "mppt_measurement_unit.vhd",
    "mppt_fuzzy_ffp_unit.vhd",
    "pso_particle_update_unit.vhd",
    "hybrid_pso_fuzzy_mppt.vhd",
    "tb_hybrid_pso_fuzzy_export.vhd",
]


def run_cmd(cmd: list[str], cwd: Path) -> None:
    print(" ".join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True)


def compile_project(project_dir: Path) -> None:
    run_cmd(["vlib", "work"], cwd=project_dir)

    for file_name in VHDL_FILES:
        run_cmd(["vcom", "-2008", file_name], cwd=project_dir)


def run_simulation(
    project_dir: Path,
    dataset_file: Path,
    result_file: Path,
    settle_cycles: int,
    w_pso: int,
    c1_pso: int,
    c2_pso: int,
    rho_min: int,
    rho_max: int,
    vel_min: int,
    vel_max: int,
    deadzone: int,
    search_radius: int,
    fokker_step_min: int,
    fokker_step_max: int,
    fuzzy_step: int,
    fuzzy_edge: int,
) -> None:
    result_file.parent.mkdir(parents=True, exist_ok=True)

    dataset_arg = dataset_file.as_posix()
    result_arg = result_file.as_posix()

    cmd = [
        "vsim",
        "-c",
        "work.tb_hybrid_pso_fuzzy_export",
        f"-gDATASET_FILE={dataset_arg}",
        f"-gRESULT_FILE={result_arg}",
        f"-gSETTLE_CYCLES_G={settle_cycles}",
        f"-gW_PSO_G_TB={w_pso}",
        f"-gC1_PSO_G_TB={c1_pso}",
        f"-gC2_PSO_G_TB={c2_pso}",
        f"-gRHO_MIN_G_TB={rho_min}",
        f"-gRHO_MAX_G_TB={rho_max}",
        f"-gVEL_MIN_G_TB={vel_min}",
        f"-gVEL_MAX_G_TB={vel_max}",
        f"-gDEADZONE_G_TB={deadzone}",
        f"-gSEARCH_RADIUS_G_TB={search_radius}",
        f"-gFOKKER_STEP_MIN_G_TB={fokker_step_min}",
        f"-gFOKKER_STEP_MAX_G_TB={fokker_step_max}",
        f"-gFUZZY_STEP_G_TB={fuzzy_step}",
        f"-gFUZZY_EDGE_G_TB={fuzzy_edge}",
        "-do",
        "run -all; quit -f",
    ]

    run_cmd(cmd, cwd=project_dir)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", default=".", help="Pasta onde estão os arquivos VHDL.")
    parser.add_argument("--dataset-dir", default="datasets", help="Pasta com os arquivos .txt de cada mês.")
    parser.add_argument("--result-dir", default="results", help="Pasta de saída dos resultados.")
    parser.add_argument("--compile", action="store_true", help="Compila os arquivos VHDL antes de simular.")

    parser.add_argument("--settle-cycles", type=int, default=1)
    parser.add_argument("--w-pso", type=int, default=50)
    parser.add_argument("--c1-pso", type=int, default=50)
    parser.add_argument("--c2-pso", type=int, default=40)
    parser.add_argument("--rho-min", type=int, default=53)
    parser.add_argument("--rho-max", type=int, default=56)
    parser.add_argument("--vel-min", type=int, default=-20)
    parser.add_argument("--vel-max", type=int, default=20)
    parser.add_argument("--deadzone", type=int, default=2)
    parser.add_argument("--search-radius", type=int, default=12)
    parser.add_argument("--fokker-step-min", type=int, default=1)
    parser.add_argument("--fokker-step-max", type=int, default=8)
    parser.add_argument("--fuzzy-step", type=int, default=30)
    parser.add_argument("--fuzzy-edge", type=int, default=90)

    args = parser.parse_args()

    project_dir = Path(args.project_dir).resolve()
    dataset_dir = (project_dir / args.dataset_dir).resolve()
    result_dir = (project_dir / args.result_dir).resolve()

    if args.compile:
        compile_project(project_dir)

    dataset_files = sorted(dataset_dir.glob("*.txt"))

    if not dataset_files:
        raise FileNotFoundError(f"Nenhum .txt encontrado em: {dataset_dir}")

    for dataset_file in dataset_files:
        result_file = result_dir / f"resultados_hybrid_{dataset_file.stem}.txt"

        print(f"\n=== Rodando dataset: {dataset_file.name} ===")

        run_simulation(
            project_dir=project_dir,
            dataset_file=dataset_file,
            result_file=result_file,
            settle_cycles=args.settle_cycles,
            w_pso=args.w_pso,
            c1_pso=args.c1_pso,
            c2_pso=args.c2_pso,
            rho_min=args.rho_min,
            rho_max=args.rho_max,
            vel_min=args.vel_min,
            vel_max=args.vel_max,
            deadzone=args.deadzone,
            search_radius=args.search_radius,
            fokker_step_min=args.fokker_step_min,
            fokker_step_max=args.fokker_step_max,
            fuzzy_step=args.fuzzy_step,
            fuzzy_edge=args.fuzzy_edge,
        )

    print("\nTodas as simulações terminaram.")


if __name__ == "__main__":
    main()
