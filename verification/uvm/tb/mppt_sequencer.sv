// =============================================================================
// mppt_sequencer.sv
// Sequencer — o "carteiro" entre Sequence e Driver.
//
// O UVM ja fornece o sequencer pronto (uvm_sequencer). Nos so precisamos
// dizer qual tipo de transacao ele carrega: mppt_seq_item.
//
// Relacao:  Sequence --[cria tx]--> Sequencer --[entrega tx]--> Driver
// =============================================================================

typedef uvm_sequencer #(mppt_seq_item) mppt_sequencer;
