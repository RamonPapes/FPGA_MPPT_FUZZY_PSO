// =============================================================================
// mppt_tb_pkg.sv
// Pacote do testbench — inclui todos os componentes UVM na ordem correta.
//
// A ORDEM IMPORTA! Cada arquivo depende dos anteriores:
//   1. seq_item (transacao) — nao depende de ninguem
//   2. sequencer — depende do seq_item
//   3. driver — depende do seq_item
//   4. monitor — depende do seq_item
//   5. scoreboard — depende do seq_item
//   6. agent — depende do sequencer, driver, monitor
//   7. env — depende do agent, scoreboard
//   8. sequence — depende do seq_item
//   9. test — depende de tudo
// =============================================================================

package mppt_tb_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "mppt_seq_item.sv"
    `include "mppt_sequencer.sv"
    `include "mppt_driver.sv"
    `include "mppt_monitor.sv"
    `include "mppt_scoreboard.sv"
    `include "mppt_agent.sv"
    `include "mppt_env.sv"
    `include "mppt_sequence.sv"
    `include "mppt_test.sv"

endpackage
