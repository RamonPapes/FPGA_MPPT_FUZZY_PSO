// =============================================================================
// mppt_env.sv
// Environment — o "escritorio completo" do testbench.
//
// Contem:
//   - Agent (Sequencer + Driver + Monitor)
//   - Scoreboard
//
// A conexao TLM mais importante esta aqui:
//   Monitor.analysis_port --> Scoreboard.analysis_imp
//
// Isso faz com que toda transacao capturada pelo Monitor seja automaticamente
// enviada ao Scoreboard para verificacao.
//
// Hierarquia completa:
//   Test
//     └── Environment
//           ├── Agent
//           │     ├── Sequencer
//           │     ├── Driver
//           │     └── Monitor
//           └── Scoreboard
// =============================================================================

class mppt_env extends uvm_env;

    `uvm_component_utils(mppt_env)

    // Componentes do Environment
    mppt_agent      agt;    // O departamento (Sequencer + Driver + Monitor)
    mppt_scoreboard scb;    // O juiz

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // -------------------------------------------------------------------------
    // build_phase: cria Agent e Scoreboard
    // -------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = mppt_agent::type_id::create("agt", this);
        scb = mppt_scoreboard::type_id::create("scb", this);
    endfunction

    // -------------------------------------------------------------------------
    // connect_phase: conecta Monitor ao Scoreboard
    // Esta eh a conexao TLM — o "tubo" de transacoes.
    // -------------------------------------------------------------------------
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // Monitor envia transacoes --> Scoreboard recebe e verifica
        agt.mon.analysis_port.connect(scb.analysis_imp);
    endfunction

endclass
