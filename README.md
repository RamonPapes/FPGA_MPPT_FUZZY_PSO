# Hybrid PSO-Fuzzy MPPT em VHDL

Projeto de implementacao e avaliacao de um controlador MPPT hibrido em VHDL, combinando logica fuzzy, PSO e uma etapa inspirada em Fokker--Planck.

O projeto usa dados historicos pre-processados de tensao e corrente. Portanto, a simulacao atual e em malha aberta: o duty cycle calculado nao altera a potencia medida no dataset. Por isso, a avaliacao prioriza estabilidade do duty cycle, consistencia numerica e comportamento computacional do controlador.

Relatorio em desenvolvimento: [Overleaf](https://www.overleaf.com/read/cqjckrcscbzw#d27700).

## Estrutura

- `hybrid_mppt_pkg.vhd`: constantes, tipos, regras fuzzy e funcoes auxiliares.
- `mppt_measurement_unit.vhd`: calcula potencia, erro e variacao do erro.
- `mppt_fuzzy_ffp_unit.vhd`: calcula a acao fuzzy/Fokker--Planck sobre o duty cycle.
- `pso_particle_update_unit.vhd`: atualiza posicao e velocidade das particulas do PSO.
- `hybrid_pso_fuzzy_mppt.vhd`: modulo principal do controlador hibrido.
- `tb_hybrid_pso_fuzzy_export.vhd`: testbench que le os dados e exporta resultados.
- `run_experiment.ps1`: script principal de reproducao dos experimentos.

## Scripts

- `scripts/pre_process_data.py`: converte os CSVs originais para arquivos de entrada do testbench em ponto fixo.
- `scripts/optimize_hyperparameters.py`: faz busca exploratoria dos hiperparametros do controlador.
- `scripts/gen_results.py`: calcula metricas diarias, resumos mensais e tabelas em CSV/LaTeX.
- `scripts/gen_plots.py`: gera graficos uteis para analise e relatorio.
- `scripts/calc_error.py`: analisa o escalonamento do erro e auxilia na escolha de parametros numericos.

## Como Rodar

Experimento completo (pre-processamento, otimizacao, simulacao, metricas, graficos e analise de erro):

```powershell
.\run_experiment.ps1 -ArchiveDir archive_final -ResultsDir results_final -CleanWork
```

Para pular a otimizacao e usar os parametros atuais:

```powershell
.\run_experiment.ps1 -ArchiveDir archive_final -ResultsDir results_final -CleanWork -SkipOptimization
```

Por padrao, as simulacoes rodam sequencialmente (`-MaxParallel 1`). Isso evita erro de checkout em licencas Questa/ModelSim Starter uncounted node-locked, que normalmente permitem apenas uma sessao por vez. Use `-MaxParallel` maior que 1 apenas se a sua licenca permitir multiplas sessoes simultaneas.

Para recalcular apenas metricas e tabelas a partir dos resultados ja simulados:

```powershell
python .\scripts\gen_results.py --results-dir results_final
python .\scripts\gen_plots.py --results-dir results_final --output-dir results_final\graficos_uteis
```

## Saidas

- `results_final/*_results.txt`: resultados exportados pelo testbench.
- `results_final/*_daily_metrics.csv`: metricas diarias por mes.
- `results_final/metrics_daily_all.csv`: metricas diarias consolidadas.
- `results_final/metrics_general.csv`: medias e desvios padrao mensais.
- `results_final/tabelas_metricas_por_dia/`: tabelas por dia em CSV e LaTeX.
- `results_final/graficos_uteis/`: graficos gerados para analise.

## Metricas Principais

- `P_best_final`: maior potencia observada no dia.
- `N_conv_98`: amostras ate atingir 98% da melhor potencia diaria.
- `T_conv_98_seconds`: tempo ate atingir 98% da melhor potencia diaria.
- `duty_std_after_conv`: desvio padrao do duty de controle apos convergencia.
- `P_ripple_after_conv`: oscilacao da potencia apos convergencia.
- `mean_abs_error`: erro medio absoluto ao longo do dia.

## Referencias

PATNAIK, Bhabani; SWAIN, Sarat Chandra; DASH, Ritesh; BALLAJI, Adithya. *Design and analysis of MPPT using advanced PSO based on fuzzy Fokker-Planck solution under partial shading condition*. SMART GENCON, 2022.
