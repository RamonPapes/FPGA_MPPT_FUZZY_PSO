// =============================================================================
// mppt_test.sv
// Test — o "diretor" que orquestra toda a verificacao.
//
// Ele faz:
//   1. Constroi o Environment (build_phase)
//   2. Cria a Sequence com os estimulos de teste (run_phase)
//   3. Dispara a Sequence no Sequencer do Agent
//   4. Espera terminar
//   5. O UVM chama report_phase automaticamente (Scoreboard mostra resultado)
//
// Para rodar este teste no ModelSim, usamos:
//   +UVM_TESTNAME=mppt_test
// =============================================================================

class mppt_test extends uvm_test;

    `uvm_component_utils(mppt_test)

    mppt_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // -------------------------------------------------------------------------
    // build_phase: constroi o Environment (que constroi tudo dentro)
    // -------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = mppt_env::type_id::create("env", this);
    endfunction

    // -------------------------------------------------------------------------
    // run_phase: executa o teste
    // -------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        mppt_sequence seq;

        // raise_objection: diz ao UVM "nao termine a simulacao, ainda estou rodando"
        phase.raise_objection(this);

        `uvm_info("TEST", "========== INICIO DO TESTE ==========", UVM_LOW)

        // Cria a sequencia de estimulos
        seq = mppt_sequence::type_id::create("seq");

        // Dispara a sequencia no Sequencer do Agent
        // Isso faz: Sequence -> Sequencer -> Driver -> DUT
        seq.start(env.agt.sqr);

        // Espera mais alguns ciclos para o DUT terminar de processar
        #1000;

        `uvm_info("TEST", "========== FIM DO TESTE ==========", UVM_LOW)

        // drop_objection: diz ao UVM "terminei, pode encerrar"
        phase.drop_objection(this);
    endtask

endclass
