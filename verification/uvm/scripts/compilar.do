# =============================================================================
# compilar.do
# Compila o DUT (VHDL) e o testbench UVM (SystemVerilog).
# Chamado pelos scripts run_uvm_batch.do e run_uvm_gui.do — nao precisa rodar
# sozinho. Deve ser executado com o diretorio atual em uvm/sim.
#
# Caminho do ModelSim: variavel de ambiente MODELSIM_DIR (padrao: D:/modelsim_ase)
# =============================================================================

if {[info exists ::env(MODELSIM_DIR)]} {
    set MS [string map {\\ /} $::env(MODELSIM_DIR)]
} else {
    set MS D:/modelsim_ase
}
set UVM_SRC $MS/verilog_src/uvm-1.2/src

# --- Biblioteca de trabalho limpa ---
if {[file exists work]} {
    vdel -all -lib work
}
vlib work

# --- PASSO 1: VHDL do controlador (pasta rlt/ na raiz do repositorio) ---
# Procura rlt/ subindo a partir de uvm/sim, para funcionar em qualquer
# profundidade (ex.: uvm/ ou verification/uvm/).
set RAIZ [pwd]
while {![file isdirectory [file join $RAIZ rlt]]} {
    set PAI [file dirname $RAIZ]
    if {$PAI eq $RAIZ} { error "Pasta rlt/ nao encontrada acima de [pwd]" }
    set RAIZ $PAI
}
set RLT [file join $RAIZ rlt]

# Ordem: pacote -> unidades folha -> intermediarias -> controlador -> top.
# Arquivos ausentes sao pulados: pso_swarm_update_unit so existe no RTL antigo
# (antes da otimizacao de area); a lista serve para as duas versoes.
foreach f {hybrid_mppt_pkg mppt_measurement_unit mppt_fuzzy_ffp_unit
           pso_search_window_unit pso_random_coeff_unit pso_particle_update_unit
           pso_swarm_update_unit pso_best_tracker_unit hybrid_pso_fuzzy_mppt
           mppt_top} {
    if {[file exists $RLT/$f.vhd]} {
        vcom -2008 -work work "$RLT/$f.vhd"
    }
}

# Wrapper VHDL <-> SystemVerilog (converte portas integer em std_logic_vector)
vcom -2008 -work work ../rtl/mppt_top_wrapper.vhd

# --- PASSO 2: UVM 1.2 + testbench ---
# Ordem: pacote UVM -> interface -> pacote do testbench -> top-level
foreach f [list $UVM_SRC/uvm_pkg.sv ../tb/mppt_if.sv ../tb/mppt_tb_pkg.sv ../tb/tb_top.sv] {
    vlog -sv -work work +incdir+$UVM_SRC +incdir+../tb $f
}

# Garante que o vsim use o GCC 4.2.1 do proprio ModelSim (DPI da UVM)
set ::env(MODEL_TECH) "$MS/win32aloem"
set ::env(PATH) "$MS/gcc-4.2.1-mingw32vc12/bin;$MS/win32aloem;$::env(PATH)"
