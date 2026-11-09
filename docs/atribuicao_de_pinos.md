# Atribuicao de pinos

Como dizer ao Quartus em quais pinos fisicos do FPGA cada porta do
`mppt_fpga_top` deve sair. Sem isso o projeto compila, gera `.sof` e fecha
timing -- mas nao funciona numa placa real.

---

## 1. O problema, concretamente

O projeto tem hoje **zero** atribuicoes de pino. Confirme:

```powershell
Select-String -Path mptt_fuzzy_pso.qsf -Pattern "set_location_assignment" | Measure-Object
```

Retorna `Count : 0`. E o Fitter avisa:

```
Critical Warning (169085): No exact pin location assignment(s)
                           for 44 pins of 44 total pins.
```

Sem instrucao, o Fitter posiciona os 44 pinos onde for mais conveniente para o
roteamento interno. O resultado e um `.sof` valido e **eletricamente sem
sentido** na placa: o `clk` quase certamente nao caiu no pino ligado ao
oscilador de 50 MHz, o `reset` nao caiu num botao, e o `duty_out` nao caiu em
lugar nenhum util.

Um FPGA nao sabe o que ha do lado de fora. Quem conta e voce.

---

## 2. As 44 portas a atribuir

De `rlt/mppt_fpga_top.vhd`:

| Porta | Direcao | Bits | Natureza |
|---|---|---|---|
| `clk` | in | 1 | oscilador de 50 MHz da placa |
| `reset` | in | 1 | assincrono, ativo alto |
| `enable` | in | 1 | habilita o controlador |
| `current_in` | in | 16 | corrente em Q1.15 |
| `voltage_in` | in | 16 | tensao em Q12.4 |
| `duty_out` | out | 8 | duty cycle, 0..100 |
| `store_valid` | out | 1 | pulso de amostra valida |
| | | **44** | |

Repare no desequilibrio: **32 dos 44 pinos sao os barramentos de entrada**.
Isso muda a estrategia de bring-up, e a secao 6 trata disso.

---

## 3. A sintaxe

Uma atribuicao de pino e uma linha no `.qsf`:

```tcl
set_location_assignment PIN_M9 -to clk
```

Para um barramento, uma linha por bit -- o indice entra entre colchetes:

```tcl
set_location_assignment PIN_AA2 -to duty_out[0]
set_location_assignment PIN_AA1 -to duty_out[1]
```

Alem da localizacao, cada pino precisa de um **padrao eletrico**. Na DE0-CV
quase tudo e 3,3 V LVTTL:

```tcl
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk
```

Como praticamente todos os pinos usam o mesmo padrao, e mais pratico definir o
padrao global uma vez:

```tcl
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"
```

E ha uma configuracao de seguranca que vale sempre ligar:

```tcl
set_global_assignment -name RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED"
```

Ela diz ao Quartus para deixar todos os pinos nao usados como entrada em alta
impedancia. Sem isso, o padrao em algumas configuracoes e conduzi-los, o que
pode colocar o FPGA disputando um sinal com outro componente da placa.

---

## 4. De onde vem o numero do pino

**Nao invente, e nao copie de memoria.** O numero do pino depende da placa, nao
do chip. Duas fontes confiaveis, nesta ordem:

1. **O arquivo de pinos que a Terasic distribui para a DE0-CV.** Vem no CD/
   download do kit, normalmente como um `.qsf` de projeto exemplo
   (`DE0_CV_golden_top`) ou como um `.csv` de pinagem. E a fonte canonica: ja
   tem nome de sinal, numero de pino e padrao eletrico corretos.
2. **O manual do usuario da DE0-CV**, nas tabelas de pinagem por periferico.

O jeito mais seguro e **importar** o arquivo da Terasic em vez de digitar:

```
Assignments > Import Assignments... > escolha o .qsf da Terasic
```

Isso traz os nomes de sinal da placa (`CLOCK_50`, `KEY[0]`, `LEDR[0]`, ...).
Depois voce so precisa ligar os nomes do seu top level a eles -- ou renomear as
portas do seu top para casar com os nomes da placa, que e o caminho mais
direto.

---

## 5. Exemplo completo

Bloco para colar no fim do `mptt_fuzzy_pso.qsf`.

> **Confira cada `PIN_xx` contra o arquivo da Terasic antes de gravar.** Os
> numeros abaixo seguem a pinagem usual da DE0-CV, mas este documento nao
> substitui o manual da placa. Um pino de saida atribuido a um lugar errado
> pode entrar em conflito com outro componente.

```tcl
# ======================================================================
# Atribuicao de pinos - DE0-CV (Cyclone V 5CEBA4F23C7)
#
# CONFERIR contra o arquivo de pinos da Terasic antes de gravar na placa.
# ======================================================================

# Padrao eletrico global e seguranca dos pinos nao usados
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"
set_global_assignment -name RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED"

# ----------------------------------------------------------------------
# Clock - oscilador de 50 MHz (CLOCK_50)
# ----------------------------------------------------------------------
set_location_assignment PIN_M9 -to clk

# ----------------------------------------------------------------------
# Controle - botoes KEY[0] e KEY[1]
#
# Os botoes da DE0-CV sao ATIVOS EM NIVEL BAIXO: soltos leem '1', pressionados
# leem '0'. O reset deste projeto e ativo alto, entao ligar direto significa
# "resetando enquanto o botao NAO esta pressionado". Ver a secao 7.
# ----------------------------------------------------------------------
set_location_assignment PIN_U7 -to reset
set_location_assignment PIN_W9 -to enable

# ----------------------------------------------------------------------
# Saidas - LEDs vermelhos
# duty_out[7] e sempre 0 (duty nunca passa de 100), mas o pino existe.
# ----------------------------------------------------------------------
set_location_assignment PIN_AA2 -to duty_out[0]
set_location_assignment PIN_AA1 -to duty_out[1]
set_location_assignment PIN_W2  -to duty_out[2]
set_location_assignment PIN_Y3  -to duty_out[3]
set_location_assignment PIN_N2  -to duty_out[4]
set_location_assignment PIN_N1  -to duty_out[5]
set_location_assignment PIN_U2  -to duty_out[6]
set_location_assignment PIN_U1  -to duty_out[7]
set_location_assignment PIN_L2  -to store_valid

# ----------------------------------------------------------------------
# Entradas de dados - 32 bits nos headers GPIO
#
# Estes sao os pinos que exigem mais cuidado: sao 32, e precisam vir de um
# ADC ou de uma fonte externa. Ver a secao 6 antes de fiar qualquer coisa.
# Os numeros abaixo sao DE EXEMPLO e precisam sair da tabela GPIO do manual.
# ----------------------------------------------------------------------
# set_location_assignment PIN_xx -to voltage_in[0]
# ...
# set_location_assignment PIN_xx -to current_in[15]
```

Depois de colar, recompile a partir do Fitter:

```powershell
quartus_fit mptt_fuzzy_pso -c mptt_fuzzy_pso
```

O `Critical Warning (169085)` deve desaparecer, ou passar a citar apenas os
pinos que voce deixou comentados.

---

## 6. O problema dos 32 pinos de entrada

Atribuir `current_in` e `voltage_in` a 32 pinos fisicos so faz sentido quando
existir um ADC real fornecendo esses bits. Hoje nao existe -- os dados vem de
arquivo no testbench.

Para uma primeira validacao em placa, ha tres caminhos, do mais simples ao mais
completo:

### 6.1 Sem pinos: In-System Sources and Probes

A forma mais rapida de ver o controlador rodando no silicio de verdade.
Adiciona-se a IP **In-System Sources and Probes** ao projeto, com as fontes
ligadas a `current_in` / `voltage_in` / `enable` e as sondas em `duty_out` /
`store_valid`. Os valores sao escritos e lidos pelo JTAG, direto do Quartus,
sem nenhum fio.

Vantagem: zero risco eletrico, zero fiacao, e permite injetar exatamente os
mesmos vetores do testbench. Para provar que o RTL roda no chip, e o caminho
certo.

### 6.2 Observar sem controlar: Signal Tap

O **Signal Tap Logic Analyzer** captura sinais internos em tempo real, tambem
por JTAG. Combinado com 6.1, da para estimular e observar o controlador inteiro
sem tocar num header.

### 6.3 Pinos de verdade: headers GPIO

A DE0-CV tem dois headers GPIO de 40 pinos. Sao suficientes para os 32 bits,
mas exigem cuidado:

- Confirme os niveis logicos. Os GPIO da DE0-CV sao **3,3 V**. Ligar uma saida
  de 5 V danifica o FPGA.
- Nem todo pino do header e de I/O livre: alguns sao alimentacao e terra.
- Trinta e dois fios e muita coisa para errar. Se o ADC for serial (SPI/I2C), e
  melhor implementar a interface em RTL e usar tres ou quatro pinos.

**Recomendacao:** faca 6.1 primeiro. Ele responde "o RTL funciona no chip?" sem
nenhum risco. So depois disso vale projetar a fiacao.

---

## 7. Dois detalhes eletricos que mordem

### Os botoes sao ativos em nivel baixo

Na DE0-CV, `KEY[n]` fica em '1' quando solto e vai a '0' quando pressionado. O
`reset` deste projeto e **ativo alto**. Ligar um no outro diretamente faz o
controlador ficar permanentemente em reset, saindo dele so enquanto o botao
estiver pressionado.

Duas saidas, ambas legitimas:

**a) Inverter no top level** -- um wrapper fino, sem tocar no RTL existente:

```vhdl
u_controller: entity work.mppt_fpga_top
    port map (
        clk    => CLOCK_50,
        reset  => not KEY(0),      -- botao ativo baixo -> reset ativo alto
        enable => not KEY(1),
        ...
    );
```

**b) Inverter no `.qsf`**, sem mexer no VHDL:

```tcl
set_instance_assignment -name INVERT_LOGIC ON -to reset
```

A primeira e mais clara para quem le o projeto depois. Prefira-a.

### O clock precisa cair num pino de clock dedicado

`clk` alimenta o divisor que gera o `clk_core`, e esse sinal tem fan-out de
mais de 800 registradores. Ele precisa entrar por um pino de clock dedicado,
que tem acesso direto a rede global de distribuicao.

Se cair num pino comum, o Quartus tenta promover o sinal a rede global e emite
um aviso; em alguns casos nao consegue, e o skew de clock explode -- a analise
de timing do Passo 4 do guia de validacao deixaria de fechar. Na DE0-CV,
`CLOCK_50` ja e um pino de clock dedicado.

---

## 8. Conferir o resultado

Depois de recompilar o Fitter, tres formas de verificar.

**No arquivo de pinos gerado:**

```powershell
Select-String -Path output_files\mptt_fuzzy_pso.pin -Pattern "clk|duty_out|store_valid"
```

**Na interface**, que e a mais legivel e mostra o encapsulamento inteiro:

```
Assignments > Pin Planner
```

**No relatorio do Fitter**, secao `Input Pins` / `Output Pins` do
`output_files/mptt_fuzzy_pso.fit.rpt`.

E confirme que o aviso sumiu:

```powershell
Select-String -Path output_files\mptt_fuzzy_pso.fit.rpt -Pattern "169085"
```

Sem resultado significa que todos os pinos tem localizacao definida.

---

## 9. Depois dos pinos

Atribuir pinos resolve **um** dos quatro itens que separam o projeto de um MPPT
funcionando numa placa. Os outros tres continuam pendentes:

- **Interface de ADC**, para que `current_in` e `voltage_in` venham de medidas
  reais em vez de arquivo.
- **Gerador de PWM**, para converter `duty_out` (0..100) numa onda de
  chaveamento.
- **Restricoes de I/O reais** (`set_input_delay` / `set_output_delay`) no lugar
  dos `set_false_path` que hoje estao no `mptt_fuzzy_pso.sdc`. Enquanto as
  entradas forem false path, a STA nao analisa os caminhos de entrada -- o que
  e honesto hoje, porque nao ha componente real com timing especificado, mas
  deixa de ser quando houver.

Ver `docs/otimizacao_de_sintese.md`, secao 1.1.
