// =============================================================================
// mppt_agent.sv
// Agent — o "gerente" que agrupa Sequencer, Driver e Monitor.
//
// Ele cria os tres componentes e faz a conexao interna:
//   Sequencer.seq_item_export --> Driver.seq_item_port
//
// Isso permite que as transacoes fluam:
//   Sequence -> Sequencer -> Driver -> DUT
//
// O Monitor fica independente — ele so observa o DUT e envia ao Scoreboard.
//
// Analogia: o Agent eh o "departamento" no organograma da empresa.
// Dentro dele estao o carteiro (Sequencer), o operador (Driver) e
// a camera (Monitor).
// =============================================================================

class mppt_agent extends uvm_agent;

    `uvm_component_utils(mppt_agent)

    // Os tres componentes dentro do Agent
    mppt_sequencer  sqr;     // Carteiro
    mppt_driver     drv;     // Operador
    mppt_monitor    mon;     // Camera/Observador

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // -------------------------------------------------------------------------
    // build_phase: cria os tres componentes
    // -------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sqr = mppt_sequencer::type_id::create("sqr", this);
        drv = mppt_driver::type_id::create("drv", this);
        mon = mppt_monitor::type_id::create("mon", this);
    endfunction

    // -------------------------------------------------------------------------
    // connect_phase: conecta o Sequencer ao Driver
    // Esta conexao eh o que permite o fluxo de transacoes.
    // -------------------------------------------------------------------------
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Conecta a saida do Sequencer na entrada do Driver
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass
