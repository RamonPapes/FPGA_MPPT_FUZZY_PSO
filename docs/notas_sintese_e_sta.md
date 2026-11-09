# Notas de estudo: da falha de sintese ao fechamento de timing

Documento de acompanhamento do trabalho feito no controlador MPPT hibrido
PSO-Fuzzy. Cobre por que o projeto nao cabia no FPGA, o que foi mudado no
RTL, como provamos que a mudanca nao alterou o comportamento, e como a
analise temporal foi montada e interpretada.

A ordem aqui e a do raciocinio, nao a cronologica.

---

## 1. Ponto de partida

O projeto implementa um MPPT hibrido em VHDL: logica fuzzy para decidir a
magnitude do passo, uma etapa inspirada em Fokker-Planck, P&O para a direcao,
e PSO com dez particulas para busca global. A avaliacao roda em malha aberta
sobre dados historicos de tensao e corrente, o que significa que o duty
calculado nao realimenta a potencia medida.

O alvo e um Cyclone V `5CEBA4F23C7` (placa DE0-CV), que oferece:

| Recurso | Disponivel |
|---|---|
| ALMs | 18.480 (~49.760 elementos logicos) |
| Blocos DSP | 66 |
| Pinos de usuario | 224 |

A compilacao falhava. Dois erros, de naturezas diferentes.

---

## 2. Os dois erros, e como le-los

### Error 179000 — pinos demais

```
Error (179000): Design requires 236 user-specified I/O pins
                -- too many to fit in the 224 user I/O pin locations
```

Acompanhado de dezenas de avisos como:

```
Warning (13410): Pin "control_duty_out[31]" is stuck at GND
```

**Causa.** O top level era o `mppt_top`, cujas portas de depuracao eram
declaradas como `integer`:

```vhdl
control_duty_out : out integer;
gbest_duty_out   : out integer;
gbest_power_out  : out integer;
```

Em VHDL, `integer` sem restricao de faixa e um tipo de 32 bits. Em simulacao
isso e irrelevante, porque o testbench so imprime o valor. Na sintese, cada
porta dessas vira um **barramento de 32 pinos fisicos**. Seis portas de
depuracao = 192 pinos, para valores que cabem em 7 ou 8 bits. Os avisos
"stuck at GND" sao a ferramenta dizendo que os bits altos nunca mudam.

A licao: **o tipo de uma porta de entidade tem custo fisico**. Simulacao
perdoa; sintese cobra.

### Error 11802 — logica demais

```
Info (21057): Implemented 83754 device resources after synthesis
    Info (21061): Implemented 83422 logic cells
    Info (21062): Implemented 96 DSP elements
Error (11802): Can't fit design in device.
```

83.422 elementos logicos contra ~49.760 disponiveis, e 96 DSPs contra 66.
Cerca de 170% do dispositivo.

Note a ordem em que o Quartus falhou: ele parou no problema de I/O antes de
chegar ao de area. Corrigir so o primeiro teria revelado o segundo.

---

## 3. Quatro conceitos de sintese que explicam a area

Antes das correcoes, vale entender o que gera area, porque cada uma das
causas e um mal-entendido comum entre simulacao e hardware.

### 3.1 Funcoes VHDL sao inlined, nao chamadas

Nao existe "chamada de funcao" em hardware. Toda chamada vira uma copia
fisica da logica. Duas chamadas identicas geram **dois circuitos**, operando
em paralelo, mesmo produzindo o mesmo resultado.

Era exatamente o caso do motor fuzzy, detalhado adiante.

### 3.2 `generate` replica fisicamente

```vhdl
gen_particle_update: for i in 0 to N_PARTICLES - 1 generate
    u_particle_update: entity work.pso_particle_update_unit ...
end generate;
```

Isso instancia **dez unidades aritmeticas completas**, todas ativas ao mesmo
tempo. E a escolha certa quando se precisa da vazao; e desperdicio quando o
resultado so e consumido a cada dezenas de ciclos.

### 3.3 `integer` sem faixa vira 32 bits em todo operador

Um sinal declarado `integer` faz a ferramenta dimensionar somadores,
multiplicadores, divisores e registradores para 32 bits, mesmo que o valor
nunca passe de 100. No log de sintese isso aparece como:

```
Parameter "LPM_WIDTHN" = "32"
```

em cada divisor inferido.

A correcao e declarar subtipos:

```vhdl
subtype duty_t is integer range 0 to 100;    -- 7 bits
subtype err_t  is integer range -100 to 100; -- 8 bits
```

### 3.4 Divisao COM SINAL por constante nao vira deslocamento

Este e o menos obvio e foi o mais caro.

O operador `/` do VHDL **trunca em direcao a zero**: `-7/2 = -3`. Ja um
deslocamento aritmetico à direita **arredonda para baixo**: `-7 >> 1 = -4`.
Como os dois nao coincidem para negativos, a ferramenta nao pode simplificar
uma divisao com sinal em deslocamento, e instancia um `lpm_divide` completo.

No log, cada um desses aparecia como:

```
Instantiated megafunction "...|lpm_divide:Div50"
    Parameter "LPM_WIDTHN" = "32"
    Parameter "LPM_NREPRESENTATION" = "SIGNED"
```

O codigo tinha divisoes por 100 e por 10000 em varios lugares, todas sobre
`integer` com sinal. Multiplicadas por dez copias do PSO, davam dezenas de
divisores de 32 bits.

**Divisao SEM sinal por constante e barata**: vira multiplicacao por
reciproco mais deslocamento, em LUTs. A diferenca de custo entre as duas e de
ordens de grandeza.

---

## 4. As correcoes

### 4.1 Top level de sintese separado

Criado o `mppt_fpga_top`, expondo apenas o necessario:

| Porta | Bits |
|---|---|
| `clk`, `reset`, `enable` | 3 |
| `current_in`, `voltage_in` | 32 |
| `duty_out` | 8 |
| `store_valid` | 1 |
| **Total** | **44** |

O `mppt_top` original ficou intacto para o testbench. Isso importa: manter os
dois separados significa que a simulacao continua enxergando todos os sinais
internos, sem que isso custe pinos na sintese.

`TOP_LEVEL_ENTITY` no `.qsf` passou a apontar para o novo top.

### 4.2 Motor fuzzy avaliado uma vez

O codigo era:

```vhdl
fuzzy_next := fuzzy_compute(error_in, delta_e_in, ...);
step_next  := fokker_planck_step(error_in, delta_e_in, ...);
```

e dentro de `fokker_planck_step`:

```vhdl
fuzzy_val := fuzzy_compute(e_in, de_in, deadzone, fuzzy_step, fuzzy_edge);
```

Ou seja, `fuzzy_compute` era avaliada **duas vezes com os mesmos argumentos**.
Cada avaliacao instancia 14 funcoes de pertinencia, um laco de 49 regras e um
divisor de defuzzificacao. Dois motores fuzzy completos, em paralelo,
calculando o mesmo numero.

A correcao foi mudar a assinatura para receber o valor ja calculado:

```vhdl
function fokker_planck_step(
    fuzzy_val, fokker_step_min, fokker_step_max : integer
) return step_t;
```

Resultado identico, metade do hardware.

### 4.3 Enxame serializado

A `pso_swarm_update_unit` foi removida. No lugar, uma unica instancia de
`pso_particle_update_unit`, multiplexada por um indice, com a FSM percorrendo
o enxame **uma particula por ciclo**:

```vhdl
when UPDATE_SWARM =>
    particle_pos(swarm_idx) <= next_particle_pos;
    particle_vel(swarm_idx) <= next_particle_vel;

    if swarm_idx = N_PARTICLES - 1 then
        swarm_idx <= 0;
        state <= FINALIZE_SWARM;
    else
        swarm_idx <= swarm_idx + 1;
    end if;
```

**Por que isso e exatamente equivalente**, e nao uma aproximacao:

1. Cada particula depende apenas de si mesma (`pos`, `vel`, `pbest`), do
   `gbest`, e da janela de busca. Nenhuma particula le o valor novo de outra.
2. `search_center`, `rho1_arr`, `rho2_arr`, `gbest_pos` e `pbest_pos` sao
   registrados em `PREPARE_SWARM` ou `SAMPLE_AND_UPDATE`, e ficam **estaveis**
   durante toda a varredura.
3. Na iteracao `i`, le-se `particle_pos(i)` (valor antigo, ainda nao
   sobrescrito) e escreve-se so o indice `i`.

Portanto cada particula enxerga o mesmo instantaneo que enxergaria na versao
paralela. O custo e de 11 ciclos por rodada de PSO, irrelevante diante do
`SETTLE_CYCLES`.

Um detalhe sutil: a versao antiga sobrescrevia a particula 0 com o candidato
P&O no mesmo ciclo. Isso foi movido para o estado `FINALIZE_SWARM`, para nao
ser desfeito no meio da varredura.

### 4.4 Subtipos com faixa

Todos os sinais ganharam faixa declarada, no pacote:

```vhdl
subtype duty_t   is integer range 0 to 100;
subtype err_t    is integer range -100 to 100;
subtype power_t  is integer range -32768 to 32767;
subtype delta_t  is integer range -65536 to 65535;
subtype vel_t    is integer range -512 to 511;
subtype coeff_t  is integer range 0 to 255;
```

Dimensionar essas faixas exige raciocinar sobre o pior caso de cada sinal.
Exemplo, para `power_t`: tensao em Q12.4 e corrente em Q1.15 sao ambas de 16
bits com sinal, entao o produto vai a `32767 x 32767`, e dividido por 65536
resulta em no maximo 16.383. Cabe em 16 bits com sinal, com folga.

O risco de errar para menos e um estouro em tempo de simulacao. Foi por isso
que o modelo de verificacao checa cada faixa (secao 5).

### 4.5 `div_trunc`

Para tirar os `lpm_divide` do caminho, as divisoes por constante passaram a
rodar sobre a magnitude:

```vhdl
function div_trunc(num : integer; den : positive; num_bits : positive)
    return integer is
    variable mag : unsigned(num_bits - 1 downto 0);
begin
    if num < 0 then
        mag := to_unsigned(-num, num_bits) / den;
        return -to_integer(mag);
    else
        mag := to_unsigned(num, num_bits) / den;
        return to_integer(mag);
    end if;
end function;
```

Reduzir a magnitude, dividir sem sinal, reaplicar o sinal — isso e
**exatamente** a definicao de truncamento em direcao a zero. O resultado e bit
a bit igual a `num/den`, mas o operador de divisao agora e sem sinal e de
largura conhecida.

O parametro `num_bits` existe para impedir que a ferramenta volte a assumir 32
bits.

### 4.6 Resultado

| Metrica | Antes | Depois | Limite |
|---|---|---|---|
| Elementos logicos / ALMs | 83.422 LEs | 11.899 ALMs (64%) | 18.480 ALMs |
| Blocos DSP | 96 | 41 (62%) | 66 |
| Pinos | 236 | 44 (20%) | 224 |
| Registradores | — | 676 | — |

---

## 5. Como provamos que nada mudou

Este passo nao e formalidade. O diretorio `results_final/` e as tabelas do
relatorio no Overleaf foram gerados com o RTL antigo. Se a refatoracao
alterasse o comportamento, todos esses numeros teriam que ser refeitos.

Havia permissao para mudar a numerica, mas **nao foi preciso**: todas as
substituicoes sairam bit a bit identicas.

### 5.1 Testbench de equivalencia

`verification/tb_equivalence.vhd` roda o RTL novo e o original lado a lado.
O RTL antigo foi preservado em `verification/ref/` com as entidades
renomeadas com sufixo `_ref`, para que os dois coexistam na mesma biblioteca.

Um detalhe de projeto do testbench: **os dois DUTs nao estao em lockstep de
ciclo**. A versao nova gasta 11 ciclos a mais por rodada de PSO. Por isso cada
DUT tem seu proprio processo de estimulo, sincronizado pelo respectivo
`store_valid`, e a comparacao acontece no **dominio de amostras**, nao no de
ciclos. Comparar ciclo a ciclo daria divergencia falsa.

### 5.2 Modelo em Python

`verification/check_equivalence_model.py` transliterou as duas versoes para
Python, incluindo a semantica exata do operador `/` do VHDL:

```python
def vdiv(a, b):
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q
```

O modelo tambem verifica, a cada atribuicao, que o valor cabe na faixa
declarada no VHDL. Isso pega o erro mais provavel da refatoracao: um subtipo
dimensionado apertado demais.

Cobertura executada:

- `div_trunc` contra `vdiv`, exaustivamente nas faixas de operacao reais
- 4.000 amostras em 5 configuracoes de genericos
- 80 combinacoes aleatorias de genericos
- 6 casos extremos deliberados

Zero divergencias. O unico estouro encontrado foi com `ERROR_GAIN_G = 1000`,
valor que o projeto nunca usa (e fixado em 1), e ficou protegido por uma
assercao de elaboracao:

```vhdl
assert ERROR_GAIN_G <= 255
    report "ERROR_GAIN_G acima de 255 estoura error_num_t."
    severity failure;
```

### 5.3 O que cada verificacao cobre

| Metodo | Cobre | Nao cobre |
|---|---|---|
| Linter VHDL | sintaxe | tipos, semantica |
| Modelo Python | equivalencia numerica, faixas | sintaxe VHDL, temporizacao |
| `tb_equivalence.vhd` | tudo acima, no simulador | area, timing fisico |
| Quartus | area, pinos, timing | correcao funcional |

Nenhum sozinho basta. E util ter isso explicito ao escrever a secao de
metodologia.

---

## 6. Analise temporal (STA)

### 6.1 O que e

Simulacao responde "o circuito calcula a coisa certa?". STA responde "ele
calcula a tempo?". A diferenca fundamental: **o STA nao roda estimulo**. Ele
enumera todos os caminhos entre registradores e faz aritmetica de atraso em
cada um. Por isso e exaustivo e independente dos dados de entrada.

A conta, para cada caminho:

```
T_clk  >=  T_co + T_logica + T_roteamento + T_setup - T_skew + T_incerteza
```

`slack = tempo disponivel - tempo necessario`. Positivo passa.

### 6.2 As quatro checagens

| Checagem | Pergunta | Piora em | Conserta com |
|---|---|---|---|
| **Setup** | o dado chega cedo o bastante? | cantos lentos | baixar clock, pipeline |
| **Hold** | o dado nao chega cedo demais? | cantos rapidos | atraso no caminho |
| **Recovery / Removal** | o reset solta longe da borda? | ambos | sincronizador de reset |
| **Min Pulse Width** | o clock fica alto/baixo tempo suficiente? | — | restringir o clock direito |

Vale insistir num ponto: **violacao de hold nao se conserta baixando o
clock**. Ela nao depende do periodo, so do atraso relativo entre dado e
clock.

### 6.3 Multicorner

Tudo e repetido em varios cantos de operacao (processo, tensao, temperatura).
No 5CEBA4 sao quatro: Slow 85C, Slow 0C, Fast 85C, Fast 0C.

Um detalhe visivel nos resultados deste projeto: o canto **Slow 0C e pior que
o Slow 85C**. Isso e a *inversao termica* — em tensao baixa, o silicio fica
mais lento no frio, contrariando a intuicao. E o motivo de nao bastar olhar
um canto.

### 6.4 Por que o SDC e obrigatorio

O relatorio de STA original trazia:

```
Critical Warning (332012): Synopsys Design Constraints File file not found
```

Sem SDC, o Quartus assume um clock default de **1 GHz**. Dai vinham o slack
de -170 ns e a violacao de largura de pulso — artefatos, nao resultados.

Vale conferir a aritmetica, porque ela mostra que o Fmax reportado era
consistente:

```
T = 1 ns (1 GHz),  slack = -170,604 ns
Fmax = 1 / (1 + 170,604) ns = 5,83 MHz   <- bate com o relatorio
```

Ha um efeito colateral mais serio que o relatorio invalido: **o Fitter tambem
usa o SDC**. Sem restricao, ele posiciona e roteia sem objetivo temporal
nenhum. Aqueles 5,63 MHz vieram de um fit que nao estava tentando ser rapido.

### 6.5 Divisor de clock e sincronizador de reset

O core faz cerca de 5,2 MHz no pior canto; o oscilador do DE0-CV e de 50 MHz.
O `mppt_clock_reset_unit` resolve duas coisas de uma vez.

**Divisor.** 50 MHz / 16 = 3,125 MHz, com 40% de margem sobre o Fmax. Um
divisor em fabric foi preferido a um PLL por ser portavel e por permitir um
`create_generated_clock` exato, sem depender de IP gerada.

**Sincronizador de reset.** Este e o ponto conceitualmente mais interessante.
O reset externo entrava assincrono direto no clear de todos os registradores.
Nessa forma, recovery e removal sao **inanalisaveis**: nao ha relacao de fase
entre a liberacao do reset e a borda de clock, e a unica saida seria mascarar
tudo com `set_false_path`, ou seja, declarar no relatorio que a checagem nao
foi feita.

A solucao classica e assercao assincrona com liberacao sincrona:

```vhdl
reset_synchronizer : process(clk_core_reg, reset_in)
begin
    if reset_in = '1' then
        reset_sync <= (others => '1');       -- assincrono, imediato
    elsif rising_edge(clk_core_reg) then
        reset_sync <= reset_sync(0) & '0';   -- sincrono, 2 ciclos
    end if;
end process;
```

O reset entra na hora, mas sai alinhado ao clock. Com isso o caminho de
`reset_core` ate os registradores do core vira um caminho temporizado normal,
e passa a ser **medido** em vez de ignorado.

Sem isso, todos os registradores sairiam do reset em ciclos potencialmente
diferentes, e a FSM poderia acordar num estado inconsistente.

### 6.6 O SDC, linha por linha

```tcl
create_clock -name clk_osc -period 20.000 [get_ports clk]
```
Declara o oscilador. Sem isso, nada e analisado.

```tcl
create_generated_clock -name clk_core -source [get_ports clk] -divide_by 16 ...
```
"Gerado", nao "criado". A distincao importa: com dois `create_clock`
independentes, o STA trataria os dominios como assincronos e perderia a
relacao de fase entre eles.

```tcl
derive_clock_uncertainty
```
Aplica jitter e variacao do fabricante por canto. Sem isso a analise fica
otimista — e e o tipo de omissao que um avaliador nota.

```tcl
set_false_path -from [get_ports {current_in[*]}]
```
"Nao analise este caminho." Legitimo aqui porque nao existe relacao de fase
conhecida entre as bordas do core e a chegada dos dados: eles vem de arquivo
no testbench, nao de um ADC com timing especificado. Inventar
`set_input_delay` produziria um numero com aparencia de rigor e nenhum
conteudo.

```tcl
set_false_path -from [get_ports {reset}]
```
Mascara apenas o trecho do pino ate o sincronizador, que e genuinamente
assincrono. O `reset_core` continua analisado.

### 6.7 Resultados

Core em 3,125 MHz (periodo de 320 ns), slacks em nanossegundos:

| Canto | Fmax `clk_core` | Setup | Hold | Recovery | Removal | MPW |
|---|---|---|---|---|---|---|
| Slow 1100mV 85C | 5,413 MHz | +135,266 | +0,598 | +314,446 | +1,360 | +8,882 |
| Slow 1100mV 0C | **5,230 MHz** | +128,782 | +0,582 | +314,731 | +1,279 | +8,911 |
| Fast 1100mV 85C | 11,216 MHz | +230,842 | +0,250 | +316,432 | +0,599 | +8,944 |
| Fast 1100mV 0C | 12,015 MHz | +236,774 | +0,235 | +316,872 | **+0,507** | +9,002 |

Todos positivos. O Timing Analyzer confirma:

```
Info (332101): Design is fully constrained for setup requirements
Info (332101): Design is fully constrained for hold requirements
```

"Fully constrained" significa que nenhum caminho ficou de fora da analise —
era exatamente o problema do relatorio anterior, com 34 entradas e 8 saidas
sem restricao.

Tres leituras:

1. **O Fmax caiu de 5,63 para 5,23 MHz depois do SDC.** Nao e regressao. Agora
   ha `derive_clock_uncertainty` aplicando jitter, e o `clk_core` e um clock de
   fabric numa rede global, com skew real. O numero anterior era otimista por
   omissao.

2. **O padrao dos cantos e livresco**: setup pior no Slow, hold pior no Fast.
   Serve de sanidade — se fosse o contrario, haveria algo errado nas
   restricoes.

3. **O menor slack do projeto e o removal de +0,507 ns**, no caminho do
   sincronizador de reset. Positivo, mas e o que vigiar se a frequencia subir.

Conferindo a formula com os proprios dados:

```
T = 320 ns,  slack = 128,782 ns
Fmax = 1 / (320 - 128,782) ns = 1 / 191,218 ns = 5,230 MHz   <- confere
```

---

## 7. Armadilhas encontradas

Registro dos erros reais que apareceram no caminho. Sao os que provavelmente
voltam.

### `mptt` vs `mppt`

O projeto se chama `mptt_fuzzy_pso` — com typo herdado — enquanto a entidade
top e `mppt_fpga_top`. Rodar `quartus_sh --flow compile mppt_fuzzy_pso` faz o
Quartus **criar um projeto novo e vazio** em vez de reclamar. Os sintomas:

```
Info (20034): Auto device selection ... default device 5CGXFC7C7F23C8 is set.
Error (12007): Top-level design entity "mppt_fuzzy_pso" is undefined
```

O primeiro denuncia que o `.qsf` nem foi lido. Para nao errar:

```powershell
$proj = (Get-Item *.qpf).BaseName
quartus_sh --flow compile $proj
```

### `get_available_operating_conditions` exige netlist

Retorna erro se chamada antes de `create_timing_netlist`. O fluxo correto para
analise multicanto e criar a netlist uma vez e, dentro do laco, so trocar o
canto:

```tcl
create_timing_netlist
read_sdc
update_timing_netlist

foreach_in_collection oc [get_available_operating_conditions] {
    set_operating_conditions $oc
    update_timing_netlist
    ...
}
delete_timing_netlist
```

### API de paineis exige o banco de relatorios carregado

`get_report_panel_id` falha sob `quartus_sta -t` com "Report not loaded". A
saida foi eliminar a dependencia: o Fmax passou a ser calculado como
`1 / (T - slack)`, e a largura de pulso extraida da tabela em texto.

### Caminhos criticos dominados pelo clock errado

Pedir `get_timing_paths -setup` sem filtro devolve o pior slack **global**. Com
dois clocks de periodos muito diferentes, o de periodo curto ganha sempre: o
`clk_osc` tem 20 ns de periodo e ~14 ns de folga, o `clk_core` tem 320 ns e
mais de 100 ns de folga. A lista saia inteira composta pelo contador do
divisor, escondendo o caminho critico do controlador.

Correcao: filtrar por dominio com `-to_clock`.

### CRLF vs LF no git

O repositorio foi commitado com LF, a arvore de trabalho esta em CRLF, e
`core.autocrlf` nao esta definido. Resultado: dezenas de arquivos que ninguem
tocou aparecem como totalmente modificados. Convem estagiar por caminho
explicito ate resolver.

### `*.txt` no `.gitignore`

Um padrao largo demais escondia silenciosamente o `sta_full_report.txt`. Foi
substituido por regras especificas. A licao vale em geral: em `.gitignore`,
ignorar por **padrao de arquivo** e mais seguro que por extensao.

---

## 8. Arquivos

**RTL** (`rlt/`)

| Arquivo | Papel |
|---|---|
| `hybrid_mppt_pkg.vhd` | subtipos, regras fuzzy, `div_trunc` |
| `mppt_measurement_unit.vhd` | potencia, erro, variacao do erro |
| `mppt_fuzzy_ffp_unit.vhd` | acao fuzzy/Fokker-Planck |
| `pso_*.vhd` | janela de busca, coeficientes, particula, bests |
| `hybrid_pso_fuzzy_mppt.vhd` | FSM do controlador |
| `mppt_top.vhd` | top de simulacao, com depuracao |
| `mppt_clock_reset_unit.vhd` | divisor de clock e sincronizador de reset |
| `mppt_fpga_top.vhd` | top de sintese, I/O minima |

**Verificacao** (`verification/`) — `ref/` com o RTL original,
`tb_equivalence.vhd`, `check_equivalence_model.py`, `run_equivalence.ps1`.

**Timing** — `mptt_fuzzy_pso.sdc`, `scripts/run_sta.tcl`, saidas em
`results_final/sta/`.

---

## 9. Em aberto

- Rodar `run_equivalence.ps1` no Questa. O modelo Python confirmou a
  equivalencia, mas a prova dentro do simulador ainda nao foi executada.
- Identificar o caminho critico do `clk_core` no `sta_critical_paths.csv`
  regerado. A hipotese e o cone de defuzzificacao, o maior bloco combinacional
  restante.
- Se for preciso mais frequencia, o proximo alvo e serializar o laco de 49
  regras, hoje inteiramente combinacional.
- Para calcular o MTBF do sincronizador, adicionar ao `.qsf`:
  `set_global_assignment -name SYNCHRONIZER_IDENTIFICATION "FORCED IF ASYNCHRONOUS"`.
- Considerar renomear o projeto de `mptt` para `mppt`.
