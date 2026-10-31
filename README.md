# Hybrid PSO-Fuzzy MPPT in VHDL

Implementation and evaluation of a hybrid MPPT controller in VHDL, combining fuzzy logic, Particle Swarm Optimization (PSO), and a Fokker–Planck-inspired stage.

The project uses preprocessed historical voltage and current data. Therefore, the current simulation operates in an open-loop configuration: the calculated duty cycle does not affect the power measured in the dataset. Consequently, the evaluation focuses on duty-cycle stability, numerical consistency, and the computational behavior of the controller.

## Project Structure

- `rlt/hybrid_mppt_pkg.vhd`: Constants, types, fuzzy rules, and auxiliary functions.
- `rlt/mppt_measurement_unit.vhd`: Calculates power, error, and error variation.
- `rlt/mppt_fuzzy_ffp_unit.vhd`: Computes the fuzzy/Fokker–Planck action on the duty cycle.
- `rlt/pso_search_window_unit.vhd`: Computes the dynamic PSO search window.
- `rlt/pso_random_coeff_unit.vhd`: Generates the swarm's pseudorandom coefficients.
- `rlt/pso_particle_update_unit.vhd`: Updates the position and velocity of a particle.
- `rlt/pso_swarm_update_unit.vhd`: Instantiates parallel particle updates.
- `rlt/pso_best_tracker_unit.vhd`: Updates `pbest`, `gbest`, and detects power drops.
- `rlt/hybrid_pso_fuzzy_mppt.vhd`: Core of the hybrid controller.
- `rlt/mppt_top.vhd`: Synthesizable top-level module.
- `rlt/tb_hybrid_pso_fuzzy_export.vhd`: Testbench that reads input data and exports results.
- `run_experiment.ps1`: Main script for reproducing the experiments.

## Scripts

- `scripts/pre_process_data.py`: Converts the original CSV files into fixed-point input files for the testbench.
- `scripts/optimize_hyperparameters.py`: Performs an exploratory search over the controller's hyperparameters.
- `scripts/gen_results.py`: Computes daily metrics, monthly summaries, and CSV/LaTeX tables.
- `scripts/gen_plots.py`: Generates plots for analysis and reporting.
- `scripts/calc_error.py`: Analyzes error scaling and assists in selecting numerical parameters.

## How to Run

Full experiment (preprocessing, optimization, simulation, metrics, plots, and error analysis):

```powershell
.\run_experiment.ps1 -ArchiveDir archive_final -ResultsDir results_final -CleanWork
```

To skip optimization and use the current parameters:

```powershell
.\run_experiment.ps1 -ArchiveDir archive_final -ResultsDir results_final -CleanWork -SkipOptimization
```

By default, simulations run sequentially (`-MaxParallel 1`). This prevents license checkout errors with Questa/ModelSim Starter uncounted node-locked licenses, which typically allow only one active session at a time. Use a `-MaxParallel` value greater than 1 only if your license permits multiple concurrent sessions.

To recompute only the metrics and tables from previously generated simulation results:

```powershell
python .\scripts\gen_results.py --results-dir results_final
python .\scripts\gen_plots.py --results-dir results_final --output-dir results_final\graficos_uteis
```

## Outputs

- `results_final/*_results.txt`: Results exported by the testbench.
- `results_final/*_daily_metrics.csv`: Daily metrics for each month.
- `results_final/metrics_daily_all.csv`: Consolidated daily metrics.
- `results_final/metrics_general.csv`: Monthly means and standard deviations.
- `results_final/tabelas_metricas_por_dia/`: Daily tables in CSV and LaTeX formats.
- `results_final/graficos_uteis/`: Plots generated for analysis.

## Main Metrics

- `P_best_final`: Maximum power observed during the day.
- `N_conv_98`: Number of samples required to reach 98% of the day's maximum observed power.
- `T_conv_98_seconds`: Time required to reach 98% of the day's maximum observed power.
- `duty_std_after_conv`: Standard deviation of the control duty cycle after convergence.
- `P_ripple_after_conv`: Power fluctuations after convergence.
- `mean_abs_error`: Mean absolute error throughout the day.

## References

PATNAIK, Bhabani; SWAIN, Sarat Chandra; DASH, Ritesh; BALLAJI, Adithya. *Design and analysis of MPPT using advanced PSO based on fuzzy Fokker-Planck solution under partial shading condition*. SMART GENCON, 2022.
