# Hybrid PSO-Fuzzy MPPT in VHDL

Implementation and evaluation of a hybrid MPPT controller in VHDL, combining fuzzy logic, Particle Swarm Optimization (PSO), and a Fokker–Planck-inspired stage.

The project uses preprocessed historical voltage and current data. Therefore, the current simulation operates in an open-loop configuration: the calculated duty cycle does not affect the power measured in the dataset. Consequently, the evaluation focuses on duty-cycle stability, numerical consistency, and the computational behavior of the controller.

Duas consequencias da malha aberta que valem para todos os resultados:

- **As entradas nao sao grandezas DC do painel.** A tensao e a tensao AC do
  quadro de baixa tensao da microrrede (`MG-LV-MSB_AC_Voltage`, ~480 V) e a
  corrente e derivada como `I = P_PV / V_AC` a partir de `PVPCS_Active_Power`,
  normalizada pelo maximo de cada mes. O erro `dP/dV` calculado sobre elas
  nao e a inclinacao da curva P-V do painel.
- **O PSO nao influencia as metricas.** O `control_duty` (`pno_candidate`) e
  atualizado so a partir do seu valor anterior e das medicoes, pelo caminho
  fuzzy/Fokker-Planck/P&O. Como as medicoes nao dependem do duty aplicado, o
  estado do PSO nunca volta para ele: trocar so parametros de PSO/memoria deixa
  `control_duty`, `error`, `delta_e` e todas as metricas identicos bit a bit.
  O PSO afeta apenas `duty_out` (comando das particulas) e o `gbest`.

Relatorio em desenvolvimento: [Overleaf](https://www.overleaf.com/read/cqjckrcscbzw#d27700).

## Estrutura

- `rlt/hybrid_mppt_pkg.vhd`: constantes, subtipos, regras fuzzy e funcoes auxiliares.
- `rlt/mppt_measurement_unit.vhd`: calcula potencia, erro e variacao do erro.
- `rlt/mppt_fuzzy_ffp_unit.vhd`: calcula a acao fuzzy/Fokker--Planck sobre o duty cycle.
- `rlt/pso_search_window_unit.vhd`: calcula a janela dinamica de busca do PSO.
- `rlt/pso_random_coeff_unit.vhd`: gera os coeficientes pseudoaleatorios do enxame.
- `rlt/pso_particle_update_unit.vhd`: atualiza posicao e velocidade de uma particula.
- `rlt/pso_best_tracker_unit.vhd`: atualiza o `pbest` de uma particula com memoria adaptativa (o `gbest` e a deteccao de queda ficam no FSM de `hybrid_pso_fuzzy_mppt`).
- `rlt/mppt_clock_reset_unit.vhd`: divisor de clock e sincronizador de reset do top de sintese.
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

O caminho critico do controlador limita o core a cerca de 5,8 MHz no pior
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

- `sta_summary.csv`: uma linha por clock e por canto de operacao, com Fmax e
  os slacks de setup, hold, recovery, removal e largura minima de pulso.
- `sta_critical_paths.csv`: os caminhos criticos de setup, separados por
  dominio de clock, com no de origem e destino.
- `sta_full_report.txt`: relatorio completo dos quatro cantos.

Duas observacoes sobre como o script extrai os numeros, porque ambas afetam
a leitura dos resultados.

O Fmax e calculado como `1 / (T - slack)`, e nao lido do painel de relatorio
do Quartus. A API de paineis (`get_report_panel_id`) exige o banco de
relatorios carregado, o que nao ocorre sob `quartus_sta -t`. A conta e a
mesma que o painel oficial faz, e o valor confere com o reportado pela
ferramenta.

Os caminhos criticos sao filtrados por dominio com `-to_clock`. Sem esse
filtro, o `clk_osc` domina a lista inteira: ele tem periodo de 20 ns e
poucos nanossegundos de folga, contra os 320 ns de periodo e mais de 100 ns
de folga do `clk_core`. O resultado seria uma lista composta so pelo
contador do divisor, escondendo o caminho critico do controlador.

### Resultados

Compilacao no 5CEBA4F23C7, Quartus Prime Lite 20.1.1, com o core em
3,125 MHz (`CLK_DIV_G = 16`) e os hiperparametros otimizados nos generics de
`mppt_fpga_top` (os mesmos de `results_final/optimization_runs/optimization_final_best.csv`
e dos defaults de `run_experiment.ps1`):

| Canto | Fmax `clk_core` | Setup | Hold | Recovery | Removal | MPW `clk_core` |
|---|---|---|---|---|---|---|
| Slow 1100mV 85C | 6,049 MHz | +154,681 | +0,381 | +313,832 | +2,150 | +159,339 |
| Slow 1100mV 0C  | 5,848 MHz | +148,991 | +0,362 | +314,125 | +2,028 | +159,271 |
| Fast 1100mV 85C | 12,587 MHz | +240,554 | +0,178 | +315,971 | +1,222 | +159,657 |
| Fast 1100mV 0C  | 13,471 MHz | +245,767 | +0,169 | +316,482 | +1,096 | +159,631 |

Slacks em nanossegundos, dominio `clk_core`. Todos positivos: o projeto fecha
timing em todos os cantos, e o Timing Analyzer reporta `Design is fully
constrained` tanto para setup quanto para hold. O MPW e o pior de cada clock
(o `clk_osc` fica entre +9,235 e +9,348 ns).

O pior canto e o Slow 1100mV 0C, com **Fmax de 5,848 MHz**, no caminho
`prev_voltage` -> `pno_candidate` (medicao, fuzzy, Fokker-Planck e P&O num
unico ciclo). O comportamento e o esperado: setup piora nos cantos lentos,
hold piora nos rapidos. O menor slack do projeto inteiro e o hold de +0,169 ns
no Fast 0C, em registradores que realimentam a si mesmos (`div_count`,
`track_i`, `wait_counter`); o menor removal e +1,096 ns, do sincronizador de
reset (`reset_sync`) ate o clear dos registradores do core. Sao os numeros a
vigiar caso a frequencia suba.

Latencia (`verification/tb_latency.vhd`): uma iteracao completa sobre as dez
particulas leva `10 * SETTLE_CYCLES + 142` ciclos de `clk_core`, ou seja,
10.142 ciclos = ~3,25 ms com `SETTLE_CYCLES = 1000` a 3,125 MHz.

Antes de existir SDC, o Quartus reportava 5,63 MHz. O valor atual e menor
porque agora ha `derive_clock_uncertainty` aplicando jitter e porque o
`clk_core` e um clock de fabric numa rede global, com skew real. O numero
anterior era otimista por omissao, nao melhor.

Utilizacao correspondente: 3.535 de 18.480 ALMs (19%), 9 de 66 blocos DSP
(14%), 44 de 224 pinos (20%), 677 registradores, 0 de 308 blocos M10K.

Os generics viram constantes na sintese, entao trocar hiperparametros muda a
area e o timing. Com a configuracao anterior de generics (W=70, C1=60, C2=60,
deteccao de queda desligada), o mesmo RTL dava 3.449 ALMs, 8 DSPs e
5,987 MHz. Antes da rodada de otimizacao de area eram
11.892 ALMs (64%) e 41 DSPs (62%), com Fmax de 5,230 MHz no pior canto. Ver
`docs/otimizacao_de_sintese.md`.

## Otimizacao de sintese

`docs/otimizacao_de_sintese.md` documenta uma rodada de otimizacao de area com
cinco alteracoes de RTL que nao alteram nenhum valor calculado. A comparacao
abaixo usa a configuracao de generics da epoca (W=70, C1=60, C2=60); os
numeros do build atual estao na secao anterior.

| Metrica | Antes | Depois |
|---|---|---|
| ALMs | 11.892 (64%) | **3.449 (19%)** |
| Blocos DSP | 41 (62%) | **8 (12%)** |
| ALUTs combinacionais | 22.883 | **5.727** |
| Divisores inferidos | 63 | **9** |
| Fmax no pior canto | 5,230 MHz | **5,987 MHz** |

O que mudou: `pso_best_tracker_unit` e `pso_random_coeff_unit` passaram a ser
percorridos em serie, uma particula por ciclo, como o enxame ja era; as catorze
funcoes de pertinencia viraram uma tabela calculada na elaboracao; `div_trunc`
deixou de escrever dois operadores `/`; e `age_t` foi estreitado de 16 para 10
bits.

O ponto de partida era que 78% dos ALUTs estavam dentro de divisores, e 62 das
63 instancias dividiam por uma constante.

Verificacao: 5 configuracoes de genericos x 3.000 amostras, 0 divergencias
contra o RTL original, e os arquivos de resultado do experimento saem identicos
byte a byte. O documento traz o antes e depois de cada alteracao, o uso de
recursos do dispositivo e como reproduzir cada medicao.

## Hiperparametros

A configuracao adotada e a primeira linha de
`results_final/optimization_runs/optimization_final_best.csv` (stage 2,
trial 4, score -2,6054), gravada nos generics de `rlt/mppt_fpga_top.vhd` e nos
defaults de `run_experiment.ps1`:

| W/C1/C2 | rho | VEL | DEADZONE | RADIUS / centro | FOKKER | FUZZY_STEP / EDGE | DIRECTION | HALF_LIFE / MAX_AGE | Deteccao de queda |
|---|---|---|---|---|---|---|---|---|---|
| 30/30/50 | 55-65 | [-30, 10] | 3 | 6 / gbest | 1-12 | 30 / 100 | -1 | 450 / 500 | desligada |

Tres trials empataram nesse score. `rank_results` em
`scripts/optimize_hyperparameters.py` desempata de forma deterministica:
score decrescente, depois deteccao de queda desligada (hardware mais simples),
depois menor trial. Como o score nao depende dos parametros de PSO/memoria (ver
acima), esses parametros nao sao identificaveis pela busca: nos 8 grupos de
trials com os mesmos parametros fuzzy (25 trials), o score foi identico.

## Verificacao

- `verification/tb_extremes.vhd`: teste dirigido dos extremos de
  `signed(15 downto 0)` na unidade de medicao, contra `trunc(I*V/65536)`.
  Cobre o caso I = V = -32768, que estourava `raw_power_t` antes da correcao.
  ```powershell
  vlib work_ext
  vcom -2008 -work work_ext rlt/hybrid_mppt_pkg.vhd rlt/mppt_measurement_unit.vhd verification/tb_extremes.vhd
  vsim -c -lib work_ext tb_extremes -do "run -all; quit -f"   # TB_EXTREMES PASS
  ```
- `verification/tb_latency.vhd`: mede os ciclos entre pulsos de `store_valid`
  e confere `SETTLE_CYCLES + 13` por particula e `10 * SETTLE_CYCLES + 142` por
  iteracao (compilar o RTL e o testbench na mesma biblioteca).
- `verification/tb_equivalence.vhd`: roda o RTL atual e o RTL original
  preservado em `verification/ref/` lado a lado, com o mesmo estimulo, e
  compara amostra a amostra. Execute com
  `.\verification\run_equivalence.ps1`.
- `verification/check_equivalence_model.py`: modelo das duas versoes em
  Python, util para checar equivalencia e estouro de faixa sem abrir o
  simulador. Execute com `python verification\check_equivalence_model.py`.

## Scripts

- `scripts/pre_process_data.py`: Converts the original CSV files into fixed-point input files for the testbench.
- `scripts/optimize_hyperparameters.py`: Performs an exploratory search over the controller's hyperparameters.
- `scripts/gen_results.py`: Computes daily metrics, monthly summaries, and CSV/LaTeX tables.
- `scripts/gen_plots.py`: Generates plots for analysis and reporting.
- `scripts/calc_error.py`: Analyzes error scaling and assists in selecting numerical parameters.

## Documentacao

- `docs/guia_de_validacao.md`: passo a passo para validar o RTL do zero --
  simulacao de equivalencia, sintese, Fitter, STA e geracao do `.sof`. Cada
  passo traz o comando, a saida esperada e os numeros de referencia.
- `docs/atribuicao_de_pinos.md`: como definir em quais pinos fisicos cada porta
  sai, com exemplo para a DE0-CV. **Necessario antes de gravar na placa** -- o
  projeto hoje tem zero atribuicoes e o Fitter posiciona os 44 pinos
  automaticamente.
- `docs/otimizacao_de_sintese.md`: a rodada de otimizacao de area, com o antes e
  depois de cada alteracao, o uso de recursos do dispositivo e a verificacao.
- `docs/notas_sintese_e_sta.md`: notas de estudo da refatoracao anterior, da
  falha de sintese ao fechamento de timing.

Validacao rapida, a partir da raiz do projeto (Quartus e ModelSim ja estao
no PATH de usuario; ver o Passo 0 do guia se nao estiverem):

```powershell
.\verification\run_equivalence.ps1 -Samples 3000 -CleanWork   # comportamento
quartus_map mptt_fuzzy_pso -c mptt_fuzzy_pso                  # sintese
quartus_fit mptt_fuzzy_pso -c mptt_fuzzy_pso                  # place & route
quartus_sta -t scripts\run_sta.tcl                            # timing
quartus_asm mptt_fuzzy_pso -c mptt_fuzzy_pso                  # .sof
```

## Como Rodar

Dependencias Python (versoes validadas em `requirements.txt`, Python 3.14):

```powershell
python -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt
```

Experimento completo (pre-processamento, otimizacao, simulacao, metricas, graficos e analise de erro). Reproduz as tabelas e figuras do artigo:

```powershell
.\run_experiment.ps1 -ArchiveDir archive_final -ResultsDir results_final -CleanWork -PythonExe .venv\Scripts\python.exe
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
