# =============================================================================
# run_uvm_gui.do
# Modo grafico: compila, roda a verificacao e mostra o waveform.
#
# Como usar:
#   1. Abra o ModelSim pelo abrir_modelsim.bat
#   2. No console do ModelSim:  cd <repositorio>/uvm/sim
#   3. Depois:                  do ../scripts/run_uvm_gui.do
#   4. Veja o transcript (linhas [PASS]/[FAIL]) e o waveform
# =============================================================================

do ../scripts/compilar.do

vsim -voptargs=+acc work.tb_top \
    +UVM_TESTNAME=mppt_test \
    +UVM_VERBOSITY=UVM_LOW \
    -suppress 12110 \
    -sv_lib uvm_dpi \
    -onfinish stop

# --- Waveform ---
add wave -divider "CLOCK & RESET"
add wave sim:/tb_top/clk
add wave sim:/tb_top/reset

add wave -divider "ENTRADAS"
add wave sim:/tb_top/intf/enable
add wave -radix decimal sim:/tb_top/intf/current_in
add wave -radix decimal sim:/tb_top/intf/voltage_in

add wave -divider "SAIDAS PRINCIPAIS"
add wave -radix unsigned sim:/tb_top/intf/duty_out
add wave sim:/tb_top/intf/store_valid
add wave -radix decimal sim:/tb_top/intf/gbest_power_out

add wave -divider "SAIDAS DEBUG"
add wave -radix decimal sim:/tb_top/intf/control_duty_out
add wave -radix decimal sim:/tb_top/intf/gbest_duty_out
add wave -radix decimal sim:/tb_top/intf/error_out
add wave -radix decimal sim:/tb_top/intf/delta_e_out
add wave -radix decimal sim:/tb_top/intf/fuzzy_delta_out

run -all

wave zoom full
