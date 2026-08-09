# ======================================================================
# Static Timing Analysis do Hybrid PSO-Fuzzy MPPT.
#
# Roda o Timing Analyzer em todos os cantos de operacao disponiveis e
# extrai, para cada um: Fmax, slack de setup, hold, recovery, removal e
# largura minima de pulso, mais os caminhos criticos.
#
# Requer que o Fitter ja tenha rodado com sucesso.
#
# Uso, a partir da raiz do projeto:
#   quartus_sta -t scripts/run_sta.tcl
#   quartus_sta -t scripts/run_sta.tcl -project mptt_fuzzy_pso -paths 20
# ======================================================================

package require ::quartus::project
package require ::quartus::sta
package require ::quartus::report

# ----------------------------------------------------------------------
# Argumentos
# ----------------------------------------------------------------------

set project   "mptt_fuzzy_pso"
set revision  "mptt_fuzzy_pso"
set out_dir   "results_final/sta"
set n_paths   10

for {set i 0} {$i < [llength $quartus(args)]} {incr i} {
    set arg [lindex $quartus(args) $i]

    switch -- $arg {
        "-project"  { incr i; set project  [lindex $quartus(args) $i] }
        "-revision" { incr i; set revision [lindex $quartus(args) $i] }
        "-out"      { incr i; set out_dir  [lindex $quartus(args) $i] }
        "-paths"    { incr i; set n_paths  [lindex $quartus(args) $i] }
    }
}

file mkdir $out_dir

# ----------------------------------------------------------------------
# Utilitarios
# ----------------------------------------------------------------------

# Menor slack de uma colecao de caminhos, ou "n/a" se nao houver caminho
# daquele tipo (por exemplo, removal num projeto sem reset assincrono).
proc worst_slack {paths} {
    set worst ""

    foreach_in_collection p $paths {
        set s [get_path_info $p -slack]

        if {$worst eq "" || $s < $worst} {
            set worst $s
        }
    }

    if {$worst eq ""} {
        return "n/a"
    }

    return $worst
}

proc fmt {v} {
    if {$v eq "n/a"} {
        return "n/a"
    }

    return [format "%.3f" $v]
}

# Pior slack de largura minima de pulso.
#
# Nao existe get_timing_paths para essa checagem, e a API de paineis
# (get_report_panel_id) exige o banco de relatorios carregado, o que nao
# acontece sob "quartus_sta -t". Entao a tabela e gerada em arquivo e o
# primeiro valor numerico da coluna Slack e extraido dela.
proc mpw_worst_slack {tmp_file} {
    if {[catch {
        set fh [open $tmp_file r]
        set txt [read $fh]
        close $fh
    }]} {
        return "n/a"
    }

    foreach line [split $txt "\n"] {
        if {[regexp {^;\s*(-?[0-9]+\.[0-9]+)\s*;} $line -> value]} {
            return $value
        }
    }

    return "n/a"
}

# ----------------------------------------------------------------------
# Abertura do projeto
# ----------------------------------------------------------------------

if {![project_exists $project]} {
    post_message -type error "Projeto $project nao encontrado."
    qexit -error
}

project_open $project -revision $revision

set summary_csv [open [file join $out_dir "sta_summary.csv"] w]
puts $summary_csv "corner,clock,period_ns,target_mhz,setup_slack_ns,fmax_mhz,hold_slack_ns,recovery_slack_ns,removal_slack_ns,mpw_slack_ns"

set paths_csv [open [file join $out_dir "sta_critical_paths.csv"] w]
puts $paths_csv "corner,rank,slack_ns,from_node,to_node"

set any_violation 0
set corner_count 0

set full [file join $out_dir "sta_full_report.txt"]
file delete -force $full

# ----------------------------------------------------------------------
# Varredura dos cantos de operacao
#
# A netlist temporal e criada UMA vez, antes de qualquer coisa:
# get_available_operating_conditions so funciona com uma netlist existente.
# Dentro do laco, trocar de canto e questao de set_operating_conditions
# seguido de update_timing_netlist, sem recriar a netlist do zero.
# ----------------------------------------------------------------------

create_timing_netlist
read_sdc
update_timing_netlist

foreach_in_collection oc [get_available_operating_conditions] {

    set corner [get_operating_conditions_info $oc -display_name]
    incr corner_count

    set_operating_conditions $oc
    update_timing_netlist

    post_message -type info "=== Canto: $corner"

    # Largura minima de pulso: valor global do canto, repetido em cada linha
    # de clock. O detalhamento por clock esta no relatorio de texto.
    set mpw_tmp [file join $out_dir "_mpw_tmp.txt"]
    file delete -force $mpw_tmp
    catch {report_min_pulse_width -nworst 1 -file $mpw_tmp}
    set mpw_slack [mpw_worst_slack $mpw_tmp]
    file delete -force $mpw_tmp

    # Uma linha por clock. Os slacks sao filtrados por dominio com -to_clock,
    # em vez do pior global, para que a linha de cada clock seja coerente.
    #
    # Fmax e calculado como 1 / (T - slack), que e a mesma conta do painel
    # oficial do Quartus. Nao se usa aqui a API de paineis de relatorio
    # (get_report_panel_id) porque ela exige o banco de relatorios carregado,
    # o que nem sempre acontece sob "quartus_sta -t".
    foreach_in_collection ck [all_clocks] {
        set cname [get_clock_info $ck -name]

        if {[catch {set period [get_clock_info $ck -period]}]} {
            continue
        }

        if {$period <= 0} {
            continue
        }

        set c_setup    [worst_slack [get_timing_paths -setup    -npaths 1 -detail summary -to_clock $ck]]
        set c_hold     [worst_slack [get_timing_paths -hold     -npaths 1 -detail summary -to_clock $ck]]
        set c_recovery [worst_slack [get_timing_paths -recovery -npaths 1 -detail summary -to_clock $ck]]
        set c_removal  [worst_slack [get_timing_paths -removal  -npaths 1 -detail summary -to_clock $ck]]

        set target [format "%.3f" [expr {1000.0 / $period}]]

        if {$c_setup eq "n/a" || $period <= $c_setup} {
            set fmax "n/a"
        } else {
            set fmax [format "%.3f" [expr {1000.0 / ($period - $c_setup)}]]
        }

        puts $summary_csv "$corner,$cname,[format %.3f $period],$target,[fmt $c_setup],$fmax,[fmt $c_hold],[fmt $c_recovery],[fmt $c_removal],[fmt $mpw_slack]"

        foreach s [list $c_setup $c_hold $c_recovery $c_removal] {
            if {$s ne "n/a" && $s < 0} {
                set any_violation 1
            }
        }
    }

    if {$mpw_slack ne "n/a" && $mpw_slack < 0} {
        set any_violation 1
    }

    # Pior caso global do canto, para os caminhos criticos listados abaixo.
    set setup_paths [get_timing_paths -setup -npaths $n_paths -detail summary]

    # Caminhos criticos de setup.
    set rank 0
    foreach_in_collection p $setup_paths {
        incr rank

        set slack [get_path_info $p -slack]
        set from  [get_node_info [get_path_info $p -from] -name]
        set to    [get_node_info [get_path_info $p -to] -name]

        puts $paths_csv "$corner,$rank,[fmt $slack],\"$from\",\"$to\""
    }

    # Relatorio completo deste canto, acumulado no mesmo arquivo.
    set hdr [open $full a]
    puts $hdr "\n\n========================================================"
    puts $hdr "  Canto de operacao: $corner"
    puts $hdr "========================================================\n"
    close $hdr

    report_clocks                                              -file $full -append
    report_clock_fmax_summary                                  -file $full -append
    report_timing -setup    -npaths $n_paths -detail full_path -file $full -append
    report_timing -hold     -npaths 5        -detail full_path -file $full -append
    report_timing -recovery -npaths 5        -detail summary   -file $full -append
    report_timing -removal  -npaths 5        -detail summary   -file $full -append
    report_min_pulse_width  -nworst 5                          -file $full -append
    report_ucp                                                 -file $full -append
}

delete_timing_netlist

close $summary_csv
close $paths_csv

project_close

post_message -type info "STA concluida em $corner_count canto(s)."
post_message -type info "  $out_dir/sta_summary.csv"
post_message -type info "  $out_dir/sta_critical_paths.csv"
post_message -type info "  $out_dir/sta_full_report.txt"

if {$any_violation} {
    post_message -type critical_warning "Ha slack negativo. Veja sta_summary.csv."
    qexit -error
}

post_message -type info "Todos os cantos fecharam com slack positivo."
qexit -success
