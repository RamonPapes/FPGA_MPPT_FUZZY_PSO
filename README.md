# Hybrid PSO-Fuzzy MPPT em VHDL

Projeto de implementacao e avaliacao de um controlador MPPT hibrido em VHDL, combinando logica fuzzy, PSO e uma etapa inspirada em Fokker--Planck.

O projeto usa dados historicos pre-processados de tensao e corrente. Portanto, a simulacao atual e em malha aberta: o duty cycle calculado nao altera a potencia medida no dataset. Por isso, a avaliacao prioriza estabilidade do duty cycle, consistencia numerica e comportamento computacional do controlador.

Relatorio em desenvolvimento: [Overleaf](https://www.overleaf.com/read/cqjckrcscbzw#d27700).

## Estrutura

- `rlt/hybrid_mppt_pkg.vhd`: constantes, subtipos, regras fuzzy e funcoes auxiliares.
- `rlt/mppt_measurement_unit.vhd`: calcula potencia, erro e variacao do erro.
- `rlt/mppt_fuzzy_ffp_unit.vhd`: calcula a acao fuzzy/Fokker--Planck sobre o duty cycle.
- `rlt/pso_search_window_unit.vhd`: calcula a janela dinamica de busca do PSO.
- `rlt/pso_random_coeff_unit.vhd`: gera os coeficientes pseudoaleatorios do enxame.
- `rlt/pso_particle_update_unit.vhd`: atualiza posicao e velocidade de uma particula.
- `rlt/pso_best_tracker_unit.vhd`: atualiza `pbest`, `gbest` e a deteccao de queda de potencia.
- `rlt/hybrid_pso_fuzzy_mppt.vhd`: nucleo do controlador hibrido.
- `rlt/mppt_top.vhd`: top-level usado pelo testbench, com as saidas de depuracao.
- `rlt/mppt_fpga_top.vhd`: top-level de sintese, sem as saidas de depuracao.
- `rlt/tb_hybrid_pso_fuzzy_export.vhd`: testbench que le os dados e exporta resultados.
- `run_experiment.ps1`: script principal de reproducao dos experimentos.

## Sintese

O top level de sintese e o `mppt_fpga_top`, nao o `mppt_top`. O `mppt_top`
expoe `control_duty_out`, `gbest_duty_out`, `gbest_power_out`, `error_out`,
`delta_e_out` e `fuzzy_delta_out` como `integer`, o que em sintese vira um
barramento de 32 bits por porta: 192 pinos so de depuracao. No 5CEBA4 do
DE0-CV isso da 236 pinos contra os 224 disponiveis. O `mppt_fpga_top` expoe
apenas `clk`, `reset`, `enable`, `current_in`, `voltage_in`, `duty_out` e
`store_valid`, totalizando 44 pinos, e mantem o `mppt_top` intacto para
simulacao.

Tres decisoes de RTL existem por causa de area, e nao de algoritmo:

- `fokker_planck_step` recebe o valor fuzzy ja calculado. Antes ela chamava
  `fuzzy_compute` internamente, o que instanciava um segundo motor fuzzy
  completo em paralelo com o primeiro.
- O enxame e percorrido em serie, uma particula por ciclo, por uma unica
  instancia de `pso_particle_update_unit`. A versao anterior replicava a
  unidade dez vezes com `generate`. Como cada particula so depende de si
  mesma, do `gbest` e da janela de busca, o resultado e identico.
- Os sinais usam subtipos com faixa declarada e as divisoes por constante sao
  feitas sobre a magnitude (`div_trunc`). Com `integer` puro e divisao com
  sinal, o Quartus infere `lpm_divide` de 32 bits em cada `/`.

## Analise temporal (STA)

As restricoes estao em `mptt_fuzzy_pso.sdc`, referenciado pelo `.qsf`. Sem
esse arquivo o Quartus assume um clock default de 1 GHz e o relatorio de
timing gerado nao significa nada.

O caminho critico do controlador limita o core a cerca de 5,6 MHz no pior
canto. Como o oscilador do DE0-CV e de 50 MHz, `mppt_clock_reset_unit` divide
o clock por `CLK_DIV_G` (16 por padrao, resultando em 3,125 MHz) e ainda
sincroniza a liberacao do reset, para que recovery e removal possam ser
analisados de fato em vez de mascarados.

Se alterar `CLK_DIV_G` em `mppt_fpga_top`, altere tambem `CLK_DIV` no `.sdc`.
Os dois precisam concordar, senao o clock analisado deixa de ser o clock
implementado.

As portas de dados sao declaradas como false path: o prototipo e alimentado
por arquivo no testbench, nao por um ADC com timing especificado, entao
modelar `set_input_delay` seria inventar numeros. A analise fica concentrada
nos caminhos registrador a registrador, que definem o Fmax do controlador.

Para rodar e extrair as metricas:

```powershell
quartus_fit mptt_fuzzy_pso -c mptt_fuzzy_pso
quartus_sta -t scripts\run_sta.tcl
```

Saidas em `results_final/sta/`:

- `sta_summary.csv`: por canto de operacao, Fmax e slack de setup, hold,
  recovery, removal e largura minima de pulso.
- `sta_critical_paths.csv`: os caminhos criticos de setup, com no de origem
  e destino.
- `sta_full_report.txt`: relatorio completo, para anexar ao trabalho.

## Verificacao da refatoracao

- `verification/tb_equivalence.vhd`: roda o RTL atual e o RTL original
  preservado em `verification/ref/` lado a lado, com o mesmo estimulo, e
  compara amostra a amostra. Execute com
  `.\verification\run_equivalence.ps1`.
- `verification/check_equivalence_model.py`: modelo das duas versoes em
  Python, util para checar equivalencia e estouro de faixa sem abrir o
  simulador. Execute com `python verification\check_equivalence_model.py`.

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
