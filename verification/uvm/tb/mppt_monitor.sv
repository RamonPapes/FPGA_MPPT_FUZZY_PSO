// =============================================================================
// mppt_monitor.sv
// Monitor — o "observador silencioso" do DUT.
//
// Ele NAO dirige nenhum sinal. Apenas observa:
//   - Quando store_valid = 1, captura todas as saidas e entradas
//   - Empacota tudo num mppt_seq_item
//   - Envia para o Scoreboard via analysis_port
//
// Analogia: eh a camera de seguranca do laboratorio. Ela grava tudo o que
// acontece mas nunca toca em nada.
// =============================================================================

class mppt_monitor extends uvm_monitor;

    `uvm_component_utils(mppt_monitor)

    // Porta de analise — por onde o Monitor envia transacoes ao Scoreboard
    uvm_analysis_port #(mppt_seq_item) analysis_port;

    // Handle para a interface virtual
    virtual mppt_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Cria a porta de analise
        analysis_port = new("analysis_port", this);
        // Busca a interface virtual
        if (!uvm_config_db #(virtual mppt_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "Nao encontrou a interface virtual 'vif'.")
    endfunction

    // -------------------------------------------------------------------------
    // run_phase: fica em loop esperando store_valid pulsar
    // -------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        mppt_seq_item tx;

        // Espera o reset terminar
        @(negedge vif.reset);
        `uvm_info("MON", "Reset concluido. Monitor observando.", UVM_LOW)

        forever begin
            // Espera store_valid = 1 (DUT terminou de processar)
            @(posedge vif.clk);
            if (vif.store_valid === 1'b1) begin

                // Cria uma nova transacao e captura TODOS os sinais
                tx = mppt_seq_item::type_id::create("tx");

                // Captura entradas (o que foi aplicado neste ciclo)
                tx.current_in       = vif.current_in;
                tx.voltage_in       = vif.voltage_in;

                // Captura saidas (o que o DUT produziu)
                tx.duty_out         = vif.duty_out;
                tx.store_valid      = vif.store_valid;
                tx.control_duty_out = vif.control_duty_out;
                tx.gbest_duty_out   = vif.gbest_duty_out;
                tx.gbest_power_out  = vif.gbest_power_out;
                tx.error_out        = vif.error_out;
                tx.delta_e_out      = vif.delta_e_out;
                tx.fuzzy_delta_out  = vif.fuzzy_delta_out;

                `uvm_info("MON", $sformatf(
                    "Capturado: duty=%0d, gbest_pwr=%0d, err=%0d (I=%0d, V=%0d)",
                    tx.duty_out, $signed(tx.gbest_power_out),
                    $signed(tx.error_out),
                    $signed(tx.current_in), $signed(tx.voltage_in)),
                    UVM_MEDIUM)

                // Envia para o Scoreboard
                analysis_port.write(tx);
            end
        end
    endtask

endclass
