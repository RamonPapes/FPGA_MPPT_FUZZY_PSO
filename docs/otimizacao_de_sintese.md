# Otimizacao de sintese e uso de recursos no Cyclone V 5CEBA4F23C7

Relatorio de uma rodada de otimizacao de area aplicada ao controlador MPPT
hibrido, com cinco alteracoes de RTL que **nao alteram nenhum valor
calculado**.

Resultado medido: a ocupacao de ALMs caiu de **64% para 19%**, os blocos DSP
de **41 para 8**, e o Fmax no pior canto subiu de **5,230 para 5,987 MHz**.

Todos os numeros deste documento vem de compilacoes reais do
`5CEBA4F23C7` em Quartus Prime Lite 20.1.1, com o top level `mppt_fpga_top`.
A equivalencia funcional foi verificada em simulacao, e o procedimento esta
na secao 6.

Complementa `docs/notas_sintese_e_sta.md`, que cobre a refatoracao anterior.

---

## 1. Realizabilidade no hardware fisico

O fluxo completo executa com sucesso sobre o dispositivo real, e nao apenas em
simulacao.

| Evidencia | Valor |
|---|---|
| Status do Fitter | `Successful`, 0 erros |
| Familia / dispositivo | Cyclone V `5CEBA4F23C7` |
| Top level | `mppt_fpga_top` |
| Modelos de timing | `Final` (nao preliminares) |
| Arquivo de programacao | `output_files/mptt_fuzzy_pso.sof` |
| Timing | `Design is fully constrained` para setup e hold |
| Slacks | positivos nos quatro cantos, `TNS = 0.000` |

O `.sof` e a prova definitiva: ele so e gerado pelo Assembler depois que o
place-and-route encaixou todo o projeto no dispositivo. Esse arquivo pode ser
carregado na DE0-CV pelo Programmer.

### 1.1 O que ainda falta para operar um painel real

Importante separar duas afirmacoes:

- **O circuito cabe e fecha timing no 5CEBA4F23C7.** Verificado acima.
- **O sistema ainda nao e um MPPT de malha fechada.** O prototipo e alimentado
  por arquivo no testbench, nao por um conversor real.

Faltam quatro coisas, e a primeira e a mais facil de esquecer.

**1. Atribuicao de pinos.** O `.qsf` nao tem nenhum `set_location_assignment`, e
o Fitter avisa:

```
Critical Warning (169085): No exact pin location assignment(s)
                           for 44 pins of 44 total pins.
```

Os 44 pinos foram posicionados automaticamente, onde o Fitter achou
conveniente. O `.sof` e valido e carrega, mas `clk` quase certamente nao caiu no
pino do oscilador de 50 MHz da DE0-CV, nem `reset` num botao, nem `duty_out`
num header. **Sem um arquivo de pinos que corresponda ao esquematico da placa,
gravar este `.sof` numa DE0-CV real nao produz um circuito funcional.**

A correcao e adicionar ao `.qsf` as atribuicoes tiradas do manual da placa (a
Terasic distribui um arquivo de pinos pronto para a DE0-CV), e recompilar.

**2. Interface de ADC** para amostrar tensao e corrente. Hoje `current_in` e
`voltage_in` entram como `std_logic_vector(15 downto 0)` ja em ponto fixo, e
estao declarados como `set_false_path` no `.sdc` exatamente porque nao ha um
componente real com timing especificado.

**3. Gerador de PWM** que converta `duty_out` (0..100) em um sinal de
chaveamento para o conversor. Hoje a saida e o numero, nao a onda.

**4. Restricoes de I/O reais** (`set_input_delay` / `set_output_delay`) no lugar
dos false paths, uma vez que 1, 2 e 3 existam.

A area liberada por esta rodada (secao 4) cobre os quatro com folga.

### 1.2 Resumo honesto do estado atual

| Pergunta | Resposta | Verificado como |
|---|---|---|
| O RTL e sintetizavel? | **Sim** | `quartus_map`, 0 erros |
| Cabe no 5CEBA4F23C7? | **Sim**, 19% das ALMs | `quartus_fit`, 0 erros |
| Fecha timing? | **Sim**, 4 cantos | `quartus_sta`, slacks positivos |
| Gera arquivo de programacao? | **Sim** | `quartus_asm`, `.sof` produzido |
| O comportamento mudou? | **Nao** | 15.000 amostras, 0 divergencias |
| Ja rodou numa placa fisica? | **Nao** | ninguem gravou o `.sof` ainda |
| Rodaria numa DE0-CV hoje? | **Nao** | faltam os pinos (item 1 acima) |
| Controlaria um painel real? | **Nao** | faltam ADC e PWM (itens 2 e 3) |

---

## 2. Recursos do hardware utilizados

Numeros do `output_files/mptt_fuzzy_pso.fit.summary`, apos as alteracoes.

| Recurso | Usado | Disponivel | Ocupacao | Folga |
|---|---|---|---|---|
| ALMs | 3.449 | 18.480 | **19%** | 15.031 |
| Blocos DSP | 8 | 66 | **12%** | 58 |
| Pinos de usuario | 44 | 224 | **20%** | 180 |
| Registradores | 677 | — | — | — |
| Bits de memoria | 0 | 3.153.920 | 0% | tudo |
| Blocos M10K | 0 | 308 | 0% | tudo |
| PLLs | 0 | 4 | 0% | 4 |
| DLLs | 0 | 4 | 0% | 4 |

### 2.1 Leitura

**ALMs a 19%.** O recurso mais disputado do projeto deixou de ser um problema.
Sobram mais de quinze mil ALMs, cerca de quatro vezes o que o controlador
inteiro ocupa hoje.

**DSP a 12%.** Os 8 blocos restantes correspondem exatamente as multiplicacoes
com dois operandos variaveis que sobraram: 3 no motor fuzzy, 3 na atualizacao
de particula (os termos cognitive, social e inercia), 1 no envelhecimento do
pbest e 1 no produto tensao x corrente da unidade de medida.

**Pinos a 20%.** Inalterado: 16 de corrente, 16 de tensao, 8 de duty, mais
clock, reset, enable e store_valid.

**Memoria embarcada a 0%.** A tabela de pertinencia da secao 4.2 virou logica
combinacional em LUTs, nao bloco M10K, porque a leitura e feita com endereco
nao registrado. Registrar o endereco migraria os ~2.276 ALUTs do bloco fuzzy
para um unico M10K de 308 disponiveis, ao custo de um ciclo de latencia. Nao
foi feito nesta rodada para manter a equivalencia ciclo a ciclo mais simples de
argumentar. E a proxima otimizacao obvia.

**PLLs a 0%.** O clock do core vem de um divisor em fabric, escolha deliberada
descrita em `docs/notas_sintese_e_sta.md`: e portavel entre familias e permite
um `create_generated_clock` exato.

### 2.2 O que a folga viabiliza

Com 15.031 ALMs e 58 DSPs livres, cabem agora:

- Os blocos de ADC e PWM da secao 1.1.
- Um enxame maior. O custo por particula caiu drasticamente: o
  `pso_best_tracker_unit` deixou de escalar com `N_PARTICLES` em area e passou
  a escalar em ciclos.
- Registradores de pipeline no caminho critico, para elevar o Fmax.
- Um segundo canal MPPT independente.

---

## 3. Resultado consolidado

### 3.1 Fitter (o que efetivamente vai no chip)

| Metrica | Antes | Depois | Variacao |
|---|---|---|---|
| ALMs | 11.892 (64%) | **3.449 (19%)** | -8.443 (-71%) |
| Blocos DSP | 41 (62%) | **8 (12%)** | -33 (-80%) |
| Registradores | 682 | 677 | -5 |
| Pinos | 44 (20%) | 44 (20%) | 0 |

### 3.2 Analysis & Synthesis

| Metrica | Antes | Depois | Variacao |
|---|---|---|---|
| ALUTs combinacionais | 22.883 | **5.727** | -17.156 (-75%) |
| ALMs estimados | 11.963 | 3.510 | -8.453 |
| Registradores | 842 | 676 | -166 |
| Divisores (`lpm_divide`) | 63 | **9** | -54 (-86%) |

A diferenca entre os 842/676 registradores do Analysis & Synthesis e os 682/677
do Fitter e normal: o Fitter empacota e remove registradores redundantes depois
do posicionamento. A comparacao valida e sempre entre a mesma etapa.

### 3.3 Por modulo

ALUTs no formato `total (proprios)`. "Proprios" e a logica escrita naquele
arquivo; o total inclui os divisores que o Quartus gerou dentro dele.

| Modulo | ALUTs antes | ALUTs depois | DSP | Divisores |
|---|---|---|---|---|
| `pso_best_tracker_unit` | 13.400 (1.680) | **742 (156)** | 10 -> 1 | 20 -> 1 |
| `mppt_fuzzy_ffp_unit` | 5.015 (2.411) | **2.802 (2.276)** | 27 -> 3 | 16 -> 2 |
| `pso_particle_update_unit` | 2.026 (266) | **1.109 (227)** | 3 -> 3 | 6 -> 3 |
| `pso_random_coeff_unit` | 1.541 (181) | **154 (18)** | 0 -> 0 | 20 -> 2 |
| `mppt_measurement_unit` | 542 (146) | 545 (148) | 1 -> 1 | 1 -> 1 |
| `hybrid_pso_fuzzy_mppt` (proprio) | 340 | 355 | 0 | 0 |
| `pso_search_window_unit` | dissolvido | 15 (15) | 0 | 0 |
| `mppt_clock_reset_unit` | 4 | 4 | 0 | 0 |

Tres observacoes:

- O `mppt_measurement_unit` cresceu 3 ALUTs e o core cresceu 15. E o custo dos
  registradores e do multiplexador que a serializacao introduziu. Comparado aos
  12.658 ALUTs devolvidos pelo `pso_best_tracker_unit`, e ruido.
- O `pso_search_window_unit` voltou a aparecer como entidade propria. Antes o
  Quartus dissolvia sua hierarquia; com o projeto menor, preservou. Nao mudou
  nada no circuito.
- O unico divisor que resta com denominador variavel e o `dP/dV` do
  `mppt_measurement_unit`. Os outros 8 dividem por constante e sobreviveram
  porque agora existe apenas uma instancia de cada.

### 3.4 Estimativa contra medicao

As estimativas da analise previa se confirmaram.

| Alteracao | Estimado | Medido |
|---|---|---|
| 4.1 Serializar `best_tracker` | -12.300 | **-12.658** |
| 4.2 Tabela de pertinencia | -2.280 | **-2.213** |
| 4.3 Serializar `random_coeff` | -1.400 | **-1.387** |
| 4.4 `div_trunc` com um `/` | -400 | **-917** (so em `particle_update`) |
| 4.5 Estreitar `age_t` | -100 | dentro de 4.1 |
| **Total** | **-16.500** | **-17.156** |

A atribuicao por modulo e limpa para 4.2, 4.3 e 4.4. Os efeitos de 4.1, 4.4 e
4.5 se sobrepoem dentro do `pso_best_tracker_unit` e nao foram medidos
separadamente -- as cinco alteracoes foram aplicadas antes da recompilacao
final.

---

## 4. As alteracoes aplicadas

### 4.1 `pso_best_tracker_unit` serializado

**Antes.** Um laco combinacional sobre as dez particulas, dentro de
`SAMPLE_AND_UPDATE`. O desenrolamento produzia dez multiplicadores de
envelhecimento, vinte divisores de 30 bits e uma cadeia de nove comparadores em
serie para apurar o gbest. 13.400 ALUTs, 58% do projeto.

**Depois.** O modulo processa **uma particula**, e o
`hybrid_pso_fuzzy_mppt` o percorre em serie num estado novo, `TRACK_BEST`, no
mesmo padrao que `UPDATE_SWARM` ja usava para o enxame. O maximo corrente e
acumulado em registrador, no lugar da cadeia de comparadores.

A interface mudou de arrays para escalares:

```vhdl
port (
    is_current_in   : in  std_logic;   -- esta particula e a corrente?
    duty_in         : in  duty_t;
    power_now_in    : in  power_t;

    pbest_pos_in    : in  duty_t;
    pbest_power_in  : in  power_t;
    pbest_age_in    : in  age_t;

    pbest_pos_out   : out duty_t;
    pbest_power_out : out power_t;
    pbest_age_out   : out age_t
);
```

**Um detalhe que era facil errar.** `power_now_sig` e combinacional sobre
`prev_power` / `prev_voltage`, e esses registradores mudam na mesma borda em que
`SAMPLE_AND_UPDATE` termina. Na versao paralela isso nao importava, porque tudo
era consumido no mesmo ciclo. Com a varredura de dez ciclos, a potencia e o duty
da amostra precisam ser **registrados** antes:

```vhdl
if power_now_sig < 0 then
    sampled_p := 0;
else
    sampled_p := power_now_sig;
end if;

track_power <= sampled_p;
track_duty  <= duty_reg;
track_cur   <= current_idx;
track_i     <= 0;

state <= TRACK_BEST;
```

Sem esse latch, cada particula veria uma potencia diferente e o resultado
divergiria do original. O testbench de equivalencia pega isso na hora.

**A deteccao de queda** depende do maximo final sobre todo o enxame, entao saiu
do modulo e ficou no core, aplicada uma unica vez no ultimo ciclo da varredura.

**`store_valid` mudou de lugar**, de `SAMPLE_AND_UPDATE` para o ultimo ciclo de
`TRACK_BEST`. E o que garante que quem le a saida enxergue o `gbest` ja
atualizado, exatamente como antes.

**Custo temporal.** Dez ciclos a mais por amostra, contra os
`SETTLE_CYCLES = 1000` que a FSM ja esperava. Cerca de 1%.

### 4.2 Funcoes de pertinencia em tabela

**Antes.** As catorze funcoes de pertinencia eram avaliadas em hardware a cada
amostra, cada uma com seu proprio `num / den`: catorze `lpm_divide`.

**Depois.** Como `mu_e` depende apenas de `e` e `mu_de` apenas de `de`, e ambos
sao um unico valor de 8 bits, a funcao inteira cabe numa tabela construida em
**tempo de elaboracao**:

```vhdl
constant STEP_V   : integer := clamp(FUZZY_STEP_G, 1, 49);
constant EDGE_V   : integer := clamp(FUZZY_EDGE_G, (2 * STEP_V) + 1, 100);
constant MF_TABLE : mf_table_t := build_mf_table(STEP_V, EDGE_V);
```

`build_mf_table` chama as mesmas funcoes `triangle` / `trapezoidal_*` com os
mesmos argumentos, para cada valor de -100 a 100. Os valores sao identicos por
construcao; a diferenca e que passam a ser calculados uma vez, na elaboracao.

O antigo `fuzzy_compute` foi dividido em duas partes: a tabela acima e
`fuzzy_defuzz`, que combina as 49 regras. Os divisores do bloco fuzzy caem de
16 para 2 -- sobram o da defuzzificacao e o do passo Fokker-Planck.

Dimensoes: 201 entradas x 7 saidas de 7 bits = **9.849 bits**, que caberiam
inteiros em um M10K de 10.240. Ver secao 2.1 sobre por que isso ainda nao
aconteceu.

### 4.3 `pso_random_coeff_unit` serializado

**Antes.** Vinte estagios de `next_lfsr` encadeados e vinte operacoes
`mod 11` combinacionais, mais os 160 flip-flops dos arrays `rho1_arr` /
`rho2_arr`.

**Depois.** Um par de coeficientes por invocacao, consumido sob demanda dentro
de `UPDATE_SWARM`, que ja dura dez ciclos:

```vhdl
lfsr_a := next_lfsr(lfsr_in);
lfsr_b := next_lfsr(lfsr_a);

rho1_out <= rand_rho(lfsr_a, RHO_MIN_G, RHO_MAX_G);
rho2_out <= rand_rho(lfsr_b, RHO_MIN_G, RHO_MAX_G);
lfsr_out <= lfsr_b;
```

**Por que preserva o comportamento.** O LFSR e consumido exatamente na mesma
ordem -- `rho1(0)`, `rho2(0)`, `rho1(1)`, ... Depois de dez ciclos o registrador
avancou os mesmos vinte passos que avancava de uma vez em `PREPARE_SWARM`,
chegando ao mesmo estado final. Cada particula enxerga o mesmo par de
coeficientes.

O avanco do LFSR saiu de `PREPARE_SWARM` e foi para `UPDATE_SWARM`.

### 4.4 `div_trunc` com um unico operador `/`

**Antes.** Dois operadores de divisao, um em cada ramo do `if`. Como a sintese
constroi todos os ramos e depois escolhe com um multiplexador, ela construia os
dois divisores -- 6 em `pso_particle_update_unit` para 3 chamadas, 20 em
`pso_best_tracker_unit` para um laco de 10.

```vhdl
mag := to_unsigned(abs_int(num), num_bits) / den;

if num < 0 then
    return -to_integer(mag);
else
    return to_integer(mag);
end if;
```

`abs_int(num)` devolve exatamente os dois numeradores originais, entao o
resultado e identico bit a bit. Medido: `pso_particle_update_unit` caiu de 6
para 3 divisores e de 2.026 para 1.109 ALUTs.

### 4.5 `age_t` estreitado

**Antes.** `integer range 0 to 65535` -- 16 bits por particula, 160 flip-flops,
e dez somadores, comparadores e muxes de 16 bits dentro do laco mais caro do
projeto.

**Depois.** `integer range 0 to 1023`.

A idade cresce de 1 por amostra e so e zerada quando a particula e a corrente E
sua idade ja passou de `MAX_PBEST_AGE_G`, o que acontece a cada `N_PARTICLES`
amostras. O pico e portanto `MAX_PBEST_AGE_G + N_PARTICLES`. Com
`MAX_PBEST_AGE_G = 500`, simulacao do pior caso da **509** -- a faixa nova cobre
ate 1023, com margem de 514.

Um `assert` em `pso_best_tracker_unit` garante que a faixa nunca seja violada em
silencio se o generic mudar:

```vhdl
assert MAX_PBEST_AGE_G + N_PARTICLES <= age_t'high
    report "MAX_PBEST_AGE_G alto demais para age_t. " &
           "Alargue age_t em hybrid_mppt_pkg.vhd."
    severity failure;
```

---

## 5. Timing

O Fmax subiu em todos os cantos. O caminho critico continua sendo o mesmo --
`prev_voltage` -> `pno_candidate`, atravessando a unidade de medida e o motor
fuzzy inteiro -- mas ficou mais curto, porque os catorze divisores das funcoes
de pertinencia saíram dele.

| Canto | Fmax antes | Fmax depois | Variacao |
|---|---|---|---|
| Slow 1100mV 85C | 5,413 MHz | **6,195 MHz** | +14,4% |
| Slow 1100mV 0C | 5,230 MHz | **5,987 MHz** | +14,5% |
| Fast 1100mV 85C | 11,216 MHz | 12,802 MHz | +14,1% |
| Fast 1100mV 0C | 12,015 MHz | 13,727 MHz | +14,2% |

Slacks no pior canto (Slow 1100mV 0C), em nanossegundos:

| Checagem | Antes | Depois |
|---|---|---|
| Setup | +128,782 | +152,973 |
| Hold | +0,582 | +0,340 |
| Recovery | +314,731 | +313,002 |
| Removal | +1,279 | +2,143 |
| Largura minima de pulso | +8,911 | +9,244 |

O menor slack do projeto inteiro era o **removal de +0,507 ns** no canto Fast
0C, no caminho do sincronizador de reset. Passou para **+1,037 ns** -- dobrou.
Continua sendo o numero a vigiar caso a frequencia suba.

O core segue em 3,125 MHz (`CLK_DIV_G = 16`). Com Fmax de 5,987 MHz, agora
haveria margem para `CLK_DIV_G = 8` (6,25 MHz), mas isso ficaria acima do pior
canto -- **nao mude sem antes elevar o Fmax**. E se mudar, atualize `CLK_DIV` no
`mptt_fuzzy_pso.sdc` junto.

---

## 6. Verificacao

As cinco alteracoes foram validadas em tres niveis, todos com resultado limpo.

### 6.1 Equivalencia funcional em simulacao

O testbench de `verification/` roda o RTL atual e o RTL original preservado em
`verification/ref/` lado a lado, com o mesmo estimulo, e compara amostra a
amostra as sete saidas do controlador.

Os dois DUTs **nao estao em lockstep de ciclo** -- e nem precisam estar. Cada um
tem seu proprio processo de estimulo, sincronizado pelo respectivo
`store_valid`, e a comparacao e feita no dominio de amostras. Foi exatamente
isso que permitiu validar a serializacao do `pso_best_tracker_unit`, que gasta
dez ciclos a mais por amostra.

```powershell
.\verification\run_equivalence.ps1 -Samples 3000 -CleanWork
```

Resultado: **5 configuracoes de genericos x 3.000 amostras = 15.000 comparacoes,
0 divergencias.** As configuracoes cobrem os defaults do VHDL, os parametros do
experimento, a deteccao de queda ligada, centro no P&O com janela larga, e
settle longo com deadzone alta.

### 6.2 Experimento ponta a ponta

Alem da equivalencia, o testbench de exportacao foi rodado com o RTL novo e com
o RTL original sobre o mesmo dataset (4.000 amostras de `Jan_2023`), e os
arquivos de resultado foram comparados:

```
linhas: novo=4002 antigo=4002
RESULTADO: arquivos IDENTICOS byte a byte
```

Ou seja: as metricas do experimento, os graficos e as tabelas do relatorio nao
mudam. Nao e preciso reprocessar `results_final/`.

### 6.3 Verificacao numerica

A faixa de `age_t` (secao 4.5) foi validada por simulacao do pior caso da
dinamica de idade: pico de 509 contra um limite de 1023.

### 6.4 Um defeito corrigido de passagem

O `verification/run_equivalence.ps1` nao listava `rlt/mppt_clock_reset_unit.vhd`,
o que fazia o `vcom` de `mppt_fpga_top.vhd` falhar com
`Could not find work.mppt_clock_reset_unit`. O erro nao invalidava a
equivalencia, porque o testbench usa `mppt_top` e nao `mppt_fpga_top`, mas
poluia a saida. Corrigido.

---

## 7. Como rodar

Todos os comandos a partir da raiz do projeto. As ferramentas nao estao no PATH
por padrao; a primeira linha resolve isso.

```powershell
$env:PATH = "C:\intelFPGA\20.1\modelsim_ase\win32aloem;C:\intelFPGA_lite\20.1\quartus\bin64;$env:PATH"
```

### 7.1 Verificar a equivalencia

```powershell
.\verification\run_equivalence.ps1 -Samples 3000 -CleanWork
```

Esperado: `Todas as configuracoes passaram.` Rode isto depois de **qualquer**
alteracao no RTL.

### 7.2 Recompilar e medir a area

```powershell
quartus_map mptt_fuzzy_pso -c mptt_fuzzy_pso
quartus_fit mptt_fuzzy_pso -c mptt_fuzzy_pso
Get-Content output_files\mptt_fuzzy_pso.fit.summary
```

Para o detalhamento por modulo, a secao
`Analysis & Synthesis Resource Utilization by Entity` do
`output_files/mptt_fuzzy_pso.map.rpt`.

Para recontar os divisores:

```bash
grep -oE "u_[a-z_]+\|lpm_divide:(Div|Mod)[0-9]+" output_files/mptt_fuzzy_pso.map.rpt \
  | sort -u | awk -F'[|:]' '{print $1, $3}' | sed 's/[0-9]*$//' | sort | uniq -c
```

Atencao ao `(Div|Mod)`: as operacoes de resto aparecem como `lpm_divide:ModN` e
sao facilmente esquecidas numa contagem que so procure por `Div`.

### 7.3 Reanalisar o timing

```powershell
quartus_sta -t scripts\run_sta.tcl
Get-Content results_final\sta\sta_summary.csv
```

### 7.4 Gerar o arquivo de programacao

```powershell
quartus_asm mptt_fuzzy_pso -c mptt_fuzzy_pso
```

Produz `output_files/mptt_fuzzy_pso.sof`.

Atencao: o Fitter nao produz o `.sof` -- so o Assembler. Depois de recompilar,
o `.sof` em `output_files/` continua sendo o da compilacao anterior ate que este
comando rode. Confira a data do arquivo antes de gravar.

E vale repetir o item 1 da secao 1.1: enquanto nao houver atribuicao de pinos no
`.qsf`, este `.sof` nao produz um circuito funcional numa DE0-CV real.

### 7.5 Experimento completo

Inalterado, e os resultados sao os mesmos de antes (secao 6.2):

```powershell
.\run_experiment.ps1 -ArchiveDir archive_final -ResultsDir results_final -CleanWork -SkipOptimization
```

---

## 8. O que ficou de fora

### 8.1 Tabela de pertinencia em M10K

Descrito na secao 2.1. Migraria ~2.276 ALUTs para um bloco de memoria que hoje
esta 100% ocioso, ao custo de um ciclo de latencia -- absorvido de sobra pelos
1.000 ciclos de `WAIT_SETTLE`. E a proxima otimizacao obvia.

### 8.2 Multiplicacao por reciproco

Os 9 divisores restantes, com excecao do `dP/dV`, dividem por constante e
poderiam virar multiplicacao por recíproco. As constantes foram calculadas e
verificadas exaustivamente contra o operador `/`:

| Uso | Divisor | `num_bits` | `m` | `m_bits` | `s` | Casos verificados |
|---|---|---|---|---|---|---|
| envelhecimento do pbest | 10000 | 30 | 109951163 | 27 | 40 | 65.536 |
| cognitive / social | 10000 | 23 | 429497 | 20 | 32 | 12.060 |
| inercia | 100 | 18 | 5243 | 13 | 19 | 4.096 |

Zero divergencias em todos. O ganho hoje seria pequeno, porque restam poucas
instancias, e o primeiro caso e uma multiplicacao de 30x27 bits que consome
varios DSPs. Vale para o de inercia (18x13, um DSP) se a area voltar a apertar.

### 8.3 Pipeline no caminho critico

Um registrador entre o `mppt_measurement_unit` e o `mppt_fuzzy_ffp_unit`
partiria o caminho critico em dois e aproximaria o Fmax do dobro, ao custo de um
ciclo de latencia. E o caminho para rodar o core acima de 6 MHz.

### 8.4 Alteracoes que mudam valores

Nao entram na categoria "sem alterar o comportamento" e exigem rodar a avaliacao
completa de novo:

- **Faixa de `rho` em potencia de dois.** `RHO_MIN_G = 55` / `RHO_MAX_G = 65`
  produzem `mod 11`. Uma faixa de 16 valores viraria uma mascara de bits, quase
  gratuita -- mas os coeficientes seriam outros e a trajetoria do PSO mudaria.
- **`POWER_SCALE_DEN_G`, `FUZZY_STEP_G`, `FUZZY_EDGE_G`.** Mudam a escala e o
  formato das funcoes de pertinencia.
- **`N_PARTICLES`.** Agora custa ciclos, nao area -- mas e mudanca de algoritmo.

---

## 9. Arquivos alterados

| Arquivo | Alteracao |
|---|---|
| `rlt/hybrid_mppt_pkg.vhd` | `age_t` estreitado; `div_trunc` com um `/`; `mf_table_t`, `build_mf_table` e `fuzzy_defuzz` no lugar de `fuzzy_compute`; estado `TRACK_BEST` |
| `rlt/pso_best_tracker_unit.vhd` | reescrito para uma particula por invocacao; `assert` de faixa de `age_t` |
| `rlt/pso_random_coeff_unit.vhd` | reescrito para um par de coeficientes por invocacao |
| `rlt/mppt_fuzzy_ffp_unit.vhd` | consulta a `MF_TABLE` no lugar das catorze avaliacoes |
| `rlt/hybrid_pso_fuzzy_mppt.vhd` | estado `TRACK_BEST`; latch de `track_power` / `track_duty` / `track_cur`; maximo corrente em registrador; deteccao de queda movida para ca; `store_valid` no fim da varredura |
| `verification/run_equivalence.ps1` | `mppt_clock_reset_unit.vhd` incluido na lista de compilacao |

Nenhuma alteracao em `mppt_top.vhd`, `mppt_fpga_top.vhd`,
`mppt_measurement_unit.vhd`, `pso_particle_update_unit.vhd`,
`pso_search_window_unit.vhd`, `mppt_clock_reset_unit.vhd`,
`mptt_fuzzy_pso.sdc` ou nos scripts do experimento.
