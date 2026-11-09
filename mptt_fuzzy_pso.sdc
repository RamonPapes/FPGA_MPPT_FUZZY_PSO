# ======================================================================
# Restricoes temporais - Hybrid PSO-Fuzzy MPPT
# Alvo: Cyclone V 5CEBA4F23C7 (DE0-CV)
#
# Uso: quartus_sta mptt_fuzzy_pso -c mptt_fuzzy_pso
#      ou o script scripts/run_sta.tcl para extrair as metricas em CSV.
# ======================================================================

# ----------------------------------------------------------------------
# Parametros
#
# CLK_DIV deve ser igual ao generic CLK_DIV_G de mppt_fpga_top. Se um mudar
# sem o outro, o clock analisado deixa de ser o clock implementado e todo o
# relatorio fica invalido.
# ----------------------------------------------------------------------

set OSC_PERIOD_NS 20.000
set CLK_DIV       16

# ----------------------------------------------------------------------
# Clock do oscilador da placa
# ----------------------------------------------------------------------

create_clock -name clk_osc \
    -period $OSC_PERIOD_NS \
    -waveform [list 0.000 [expr {$OSC_PERIOD_NS / 2.0}]] \
    [get_ports clk]

# ----------------------------------------------------------------------
# Clock do core, gerado pelo divisor em mppt_clock_reset_unit
#
# O no alvo e a saida do registrador clk_core_reg. O nome e resolvido por
# curinga porque o caminho hierarquico exato depende de como o Quartus
# achatou a hierarquia. Se a colecao vier vazia, rode "report_clocks" no
# Timing Analyzer, localize o registrador que gera o clock e ajuste o
# padrao abaixo.
# ----------------------------------------------------------------------

set core_clk_pin [get_pins -compatibility_mode -nowarn {*clk_core_reg*|q}]

if {[get_collection_size $core_clk_pin] == 0} {
    post_message -type critical_warning \
        "SDC: nao encontrei o registrador do divisor de clock (*clk_core_reg*|q). \
         O clock do core ficara sem restricao e a analise sera invalida. \
         Rode report_clocks e ajuste o padrao em mptt_fuzzy_pso.sdc."
} else {
    create_generated_clock -name clk_core \
        -source [get_ports clk] \
        -divide_by $CLK_DIV \
        $core_clk_pin

    post_message -type info \
        "SDC: clk_core criado como clk_osc/$CLK_DIV = \
         [format %.3f [expr {1000.0 / ($OSC_PERIOD_NS * $CLK_DIV)}]] MHz."
}

# ----------------------------------------------------------------------
# Incerteza de clock
#
# derive_clock_uncertainty aplica os numeros de jitter e variacao do
# fabricante para cada canto. Sem isso a analise fica otimista.
# ----------------------------------------------------------------------

derive_clock_uncertainty

# ----------------------------------------------------------------------
# Entradas e saidas
#
# O prototipo atual e alimentado por arquivo no testbench, nao por um ADC
# com timing especificado. Nao existe relacao de fase conhecida entre as
# bordas do core e a chegada de current_in/voltage_in, entao modelar
# set_input_delay aqui seria inventar numeros e contaminar o relatorio.
#
# As portas sao declaradas como false path de forma explicita, o que deixa
# a analise concentrada nos caminhos registrador a registrador, que e o que
# define o Fmax do controlador. Se um dia o dado vier de um conversor real,
# troque este bloco por set_input_delay / set_output_delay com os tempos do
# componente e reavalie.
# ----------------------------------------------------------------------

set_false_path -from [get_ports {enable}]
set_false_path -from [get_ports {current_in[*]}]
set_false_path -from [get_ports {voltage_in[*]}]

set_false_path -to [get_ports {duty_out[*]}]
set_false_path -to [get_ports {store_valid}]

# ----------------------------------------------------------------------
# Reset
#
# reset entra assincrono e so alimenta o clear do sincronizador de duas
# etapas em mppt_clock_reset_unit. O caminho do pino ate esse clear e
# genuinamente assincrono e nao deve ser temporizado.
#
# Ja o reset interno (reset_core) e liberado de forma sincrona, entao o
# caminho dele ate os registradores do core continua sendo analisado
# normalmente em recovery e removal. E isso que valida o sincronizador.
# ----------------------------------------------------------------------

set_false_path -from [get_ports {reset}]
