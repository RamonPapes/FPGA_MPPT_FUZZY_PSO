# =============================================================================
# run_uvm_batch.do
# Modo batch: compila, roda a verificacao e salva o transcript.
# Use pelo rodar_uvm_batch.bat (ele ja entra em uvm/sim e ajusta o PATH).
#
# Saida: uvm/resultados/transcript.txt
# =============================================================================

transcript file ../resultados/transcript.txt

do ../scripts/compilar.do

vsim -c -voptargs=+acc work.tb_top \
    +UVM_TESTNAME=mppt_test \
    +UVM_VERBOSITY=UVM_LOW \
    -suppress 12110 \
    -sv_lib uvm_dpi \
    -onfinish stop

run -all

quit -f
