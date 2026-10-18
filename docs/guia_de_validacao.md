# Guia de validacao: simulacao, sintese e STA

Passo a passo para validar o RTL do zero. Cada etapa traz o comando, o que
esperar na saida e como saber que deu certo.

Ordem importa: **simular primeiro**. Se o comportamento divergiu, nao adianta
olhar area nem timing.

---

## Passo 0 - Conferir o ambiente

Nesta maquina o PATH ja esta configurado de forma permanente: o ModelSim veio
do instalador e a pasta do Quartus (`C:\intelFPGA_lite\20.1\quartus\bin64`) foi
acrescentada ao PATH de usuario. Nao e preciso declarar nada a cada sessao.

Abra um PowerShell **na raiz do projeto** e confirme:

```powershell
foreach ($c in 'quartus_map','quartus_fit','quartus_sta','quartus_asm','vcom','vsim') {
    "{0,-12} {1}" -f $c, (Get-Command $c -ErrorAction SilentlyContinue).Source
}
```

As seis linhas devem trazer um caminho. Se alguma vier vazia, veja abaixo.

### Se as ferramentas nao forem encontradas

Acontece em outra maquina, ou se o PATH for alterado. Ha duas saidas.

**Permanente** (recomendado, uma vez so). Acrescenta a pasta ao PATH de
usuario, sem tocar no PATH de maquina:

```powershell
$novo = "C:\intelFPGA_lite\20.1\quartus\bin64"
$userPath = [Environment]::GetEnvironmentVariable('Path','User')

if ($userPath -split ';' -notcontains $novo) {
    [Environment]::SetEnvironmentVariable('Path', $userPath.TrimEnd(';') + ';' + $novo, 'User')
}
```

Depois **feche e reabra o terminal** -- variaveis de ambiente sao herdadas na
criacao do processo, entao janelas ja abertas continuam com o valor antigo.

> Nao use `setx` para isso. Ele **trunca o valor em 1024 caracteres**, e um PATH
> maior que isso e silenciosamente mutilado. O metodo `[Environment]::
> SetEnvironmentVariable` nao tem esse limite.
>
> E nunca escreva `$env:PATH` de volta no escopo `User`: essa variavel e a
> **juncao** do PATH de maquina com o de usuario. Gravar a juncao no escopo de
> usuario duplica todas as entradas de maquina. Leia sempre com
> `[Environment]::GetEnvironmentVariable('Path','User')`.

**Temporaria**, valida so para a janela atual:

```powershell
$env:PATH = "C:\intelFPGA\20.1\modelsim_ase\win32aloem;C:\intelFPGA_lite\20.1\quartus\bin64;$env:PATH"
```

---

## Passo 1 - Simulacao: o comportamento mudou?

Esta e a etapa que realmente protege o projeto. O testbench roda o RTL atual e
o RTL original preservado em `verification/ref/` lado a lado, com o mesmo
estimulo, e compara amostra a amostra as sete saidas do controlador.

```powershell
.\verification\run_equivalence.ps1 -Samples 3000 -CleanWork
```

Leva cerca de um minuto. Sao cinco configuracoes de genericos diferentes.

**Saida esperada** -- uma linha destas por configuracao:

```
# === Equivalencia: 3000 amostras, 0 divergencias de campo.
# ** Note: OK: o RTL refatorado e equivalente ao original.
```

E, no fim:

```
Todas as configuracoes passaram.
```

**Como saber que deu certo:** `0 divergencias` nas cinco, e a linha final em
verde. Qualquer numero diferente de zero significa que o RTL mudou de
comportamento -- pare aqui e investigue antes de sintetizar.

O script sai com codigo de erro se alguma configuracao falhar, entao da para
usar em automacao:

```powershell
.\verification\run_equivalence.ps1 -Samples 3000 -CleanWork
if ($LASTEXITCODE -eq 0) { "equivalencia OK" } else { "FALHOU" }
```

### Os dois DUTs nao rodam em lockstep

Vale entender por que isso funciona. A versao atual gasta mais ciclos por
amostra que a original -- sao tres varreduras em serie. Por isso cada DUT tem
seu proprio processo de estimulo, sincronizado pelo respectivo `store_valid`, e
a comparacao acontece **no dominio de amostras, nao no de ciclos**. E o que
permite validar serializacoes sem reescrever o testbench a cada mudanca.

### Opcional: experimento ponta a ponta

Se quiser confirmar que os resultados exportados nao mudaram, rode o
experimento normal e compare com `results_final/`:

```powershell
.\run_experiment.ps1 -ArchiveDir archive_final -ResultsDir results_check -CleanWork -SkipOptimization
```

Os arquivos `*_results.txt` devem sair identicos aos de `results_final/`.

---

## Passo 2 - Sintese: cabe no chip?

```powershell
quartus_map mptt_fuzzy_pso -c mptt_fuzzy_pso
```

Leva cerca de 25 segundos.

**Saida esperada no fim:**

```
Info: Quartus Prime Analysis & Synthesis was successful. 0 errors, 10 warnings
```

Os 10 warnings sao esperados. O principal e:

```
Warning (13410): Pin "duty_out[7]" is stuck at GND
```

Isso nao e defeito: o duty nunca passa de 100, e 100 < 128, entao o bit 7 e
sempre zero e o Quartus o elimina. E a ferramenta funcionando.

**Numeros de referencia** (secao `Analysis & Synthesis Resource Usage Summary`
do `output_files/mptt_fuzzy_pso.map.rpt`):

| Metrica | Esperado |
|---|---|
| ALUTs combinacionais | 5.727 |
| ALMs estimados | 3.510 |
| Registradores | 676 |
| Blocos DSP | 8 |

Para conferir rapidamente:

```powershell
Select-String -Path output_files\mptt_fuzzy_pso.map.rpt `
  -Pattern "Combinational ALUT usage for logic|Dedicated logic registers|Total DSP Blocks" |
  Select-Object -First 3
```

### Conferir a contagem de divisores

Divisor e o item mais caro do projeto, entao vale vigiar. No Git Bash:

```bash
grep -oE "u_[a-z_]+\|lpm_divide:(Div|Mod)[0-9]+" output_files/mptt_fuzzy_pso.map.rpt \
  | sort -u | awk -F'[|:]' '{print $1, $3}' | sed 's/[0-9]*$//' | sort | uniq -c
```

Esperado -- **9 no total**:

```
  1 u_best_tracker Div
  2 u_fuzzy_ffp Div
  1 u_measurement Div
  3 u_particle_update Div
  2 u_random_coefficients Mod
```

Atencao ao `(Div|Mod)`: as operacoes de resto aparecem como `lpm_divide:ModN`.
Uma contagem que so procure por `Div` perde as do gerador de coeficientes.

---

## Passo 3 - Fitter: encaixa no dispositivo?

```powershell
quartus_fit mptt_fuzzy_pso -c mptt_fuzzy_pso
```

Leva cerca de 3 a 4 minutos. E a etapa mais demorada.

**Saida esperada:**

```
Info: Quartus Prime Fitter was successful. 0 errors, 4 warnings
```

E, antes disso, a confirmacao de que o SDC foi lido:

```
Info: SDC: clk_core criado como clk_osc/16 =  3.125 MHz.
```

Se essa linha nao aparecer, o `.sdc` nao foi aplicado e o Passo 4 nao vale nada.

**Conferir o resultado:**

```powershell
Get-Content output_files\mptt_fuzzy_pso.fit.summary
```

| Recurso | Esperado |
|---|---|
| ALMs | 3.449 / 18.480 (19%) |
| Registradores | 677 |
| Pinos | 44 / 224 (20%) |
| Blocos DSP | 8 / 66 (12%) |
| Blocos M10K | 0 / 308 |

**Um aviso que voce vai ver e que importa:**

```
Critical Warning (169085): No exact pin location assignment(s)
                           for 44 pins of 44 total pins.
```

Isso significa que os pinos foram posicionados automaticamente, em lugares
arbitrarios. Nao impede a compilacao, mas impede o projeto de funcionar numa
placa real. Ver `docs/atribuicao_de_pinos.md`.

### Utilizacao por modulo

Se quiser o detalhamento, a secao
`Analysis & Synthesis Resource Utilization by Entity` do `.map.rpt` traz uma
linha por modulo. No Git Bash:

```bash
awk '/Resource Utilization by Entity/,/Note: For table entries/' \
  output_files/mptt_fuzzy_pso.map.rpt \
  | grep -E "u_fuzzy_ffp\||u_measurement\||u_particle_update\||u_best_tracker\||u_random_coefficients\||u_search_window\||u_clock_reset\||u_hybrid_controller\|" \
  | grep -v "lpm_divide\|alt_u_div\|sign_div\|add_sub\|lpm_abs" | cut -c1-135
```

---

## Passo 4 - STA: fecha timing?

```powershell
quartus_sta -t scripts\run_sta.tcl
```

Leva cerca de 7 segundos.

**Saida esperada:**

```
Info (332101): Design is fully constrained for setup requirements
Info (332101): Design is fully constrained for hold requirements
Info: STA concluida em 4 canto(s).
Info: Todos os cantos fecharam com slack positivo.
```

As duas linhas `fully constrained` sao essenciais. Se aparecer
`not fully constrained`, algum caminho ficou sem restricao e o relatorio esta
incompleto.

**Conferir os numeros:**

```powershell
Get-Content results_final\sta\sta_summary.csv
```

Esperado para o `clk_core`:

| Canto | Fmax | Setup | Hold | Removal |
|---|---|---|---|---|
| Slow 1100mV 85C | 6,195 MHz | +158,581 | +0,360 | +2,275 |
| Slow 1100mV 0C | **5,987 MHz** | +152,973 | +0,340 | +2,143 |
| Fast 1100mV 85C | 12,802 MHz | +241,889 | +0,178 | +1,174 |
| Fast 1100mV 0C | 13,727 MHz | +247,150 | +0,166 | **+1,037** |

**Como ler:** todos os slacks tem que ser **positivos**. O pior Fmax e o do
canto Slow 0C -- e ele precisa ficar acima dos 3,125 MHz em que o core roda. A
margem atual e de 67%.

O menor slack do projeto e o removal de +1,037 ns no canto Fast 0C, no caminho
do sincronizador de reset. E o numero a vigiar se a frequencia subir.

Saidas geradas:

- `results_final/sta/sta_summary.csv` -- uma linha por clock e por canto
- `results_final/sta/sta_critical_paths.csv` -- caminhos criticos por dominio
- `results_final/sta/sta_full_report.txt` -- relatorio completo

---

## Passo 5 - Assembler: gerar o arquivo de programacao

```powershell
quartus_asm mptt_fuzzy_pso -c mptt_fuzzy_pso
```

Leva cerca de 5 segundos.

```
Info: Quartus Prime Assembler was successful. 0 errors, 1 warning
```

Produz `output_files/mptt_fuzzy_pso.sof`.

**Armadilha que ja custou tempo neste projeto:** o Fitter **nao** gera o
`.sof`. Depois de recompilar, o arquivo em `output_files/` continua sendo o da
compilacao anterior ate que o Assembler rode. Sempre confira a data:

```powershell
Get-Item output_files\mptt_fuzzy_pso.sof | Select-Object Name, LastWriteTime
```

---

## Atalho: rodar tudo de uma vez

```powershell
quartus_sh --flow compile mptt_fuzzy_pso
```

Executa Analysis & Synthesis, Fitter, Assembler e Timing Analyzer em sequencia.
Util para uma verificacao rapida, mas prefira os passos separados quando estiver
investigando algo -- a saida fica muito mais facil de ler.

O `run_sta.tcl` continua precisando ser rodado a parte, porque e ele que gera os
CSVs:

```powershell
quartus_sh --flow compile mptt_fuzzy_pso
quartus_sta -t scripts\run_sta.tcl
```

---

## Resumo

O PATH ja e permanente nesta maquina; nao ha passo 0 a executar.

```powershell
# 1. o comportamento mudou?        -> "Todas as configuracoes passaram."
.\verification\run_equivalence.ps1 -Samples 3000 -CleanWork

# 2. sintetiza?                    -> "was successful. 0 errors"
quartus_map mptt_fuzzy_pso -c mptt_fuzzy_pso

# 3. cabe no chip?                 -> "3,449 / 18,480 ( 19 % )"
quartus_fit mptt_fuzzy_pso -c mptt_fuzzy_pso

# 4. fecha timing?                 -> "Todos os cantos fecharam com slack positivo."
quartus_sta -t scripts\run_sta.tcl

# 5. gera o .sof?                  -> "Assembler was successful"
quartus_asm mptt_fuzzy_pso -c mptt_fuzzy_pso
```

Se os cinco passarem, o RTL esta equivalente ao original, cabe no
5CEBA4F23C7, fecha timing nos quatro cantos e tem arquivo de programacao.

O que isso **nao** garante: que funcione numa placa fisica. Para isso faltam as
atribuicoes de pino (`docs/atribuicao_de_pinos.md`), a interface de ADC e o
gerador de PWM.

---

## Se algo falhar

| Sintoma | Causa provavel |
|---|---|
| `vcom` ou `quartus_map` nao encontrado | PATH alterado, ou terminal aberto antes de o PATH ser configurado. Ver Passo 0 |
| Erro de licenca no `vsim` | ModelSim ASE e node-locked: feche outras sessoes |
| `divergencias` diferente de zero | O RTL mudou de comportamento. Compare com `verification/ref/` |
| `Could not find work.<entidade>` | Arquivo faltando na lista do `run_equivalence.ps1` |
| A linha `SDC: clk_core criado` nao aparece | O `.sdc` nao foi lido; confira a referencia no `.qsf` |
| `not fully constrained` na STA | Algum clock ou caminho ficou sem restricao |
| Fmax caiu muito | Veja o caminho critico em `sta_critical_paths.csv` |
| `.sof` com data antiga | Faltou rodar o `quartus_asm` |
