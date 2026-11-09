// =============================================================================
// mppt_driver.sv
// Driver — converte transacoes em sinais fisicos no DUT.
//
// Analogia: eh o "operador de bancada" no laboratorio. Ele recebe a ficha
// com os valores de corrente e tensao, gira os botoes (sinais), e espera
// o instrumento (DUT) dar uma leitura (store_valid).
//
// Fluxo:
//   1. Recebe transacao do Sequencer
//   2. Coloca current_in e voltage_in na interface
//   3. Espera store_valid = 1 (DUT processou)
//   4. Avisa o Sequencer que terminou
// =============================================================================

class mppt_driver extends uvm_driver #(mppt_seq_item);

    `uvm_component_utils(mppt_driver)

    // Handle para a interface virtual (a conexao fisica com o DUT)
    virtual mppt_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // -------------------------------------------------------------------------
    // build_phase: pega a interface do banco de configuracao do UVM
    // (alguem no top-level registrou a interface; aqui nos buscamos)
    // -------------------------------------------------------------------------
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual mppt_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "Nao encontrou a interface virtual 'vif'. Verifique o tb_top.")
    endfunction

    // -------------------------------------------------------------------------
    // run_phase: loop principal — roda durante toda a simulacao
    // -------------------------------------------------------------------------
    virtual task run_phase(uvm_phase phase);
        mppt_seq_item tx;

        // Espera o reset terminar antes de comecar
        @(negedge vif.reset);
        `uvm_info("DRV", "Reset concluido. Driver pronto.", UVM_LOW)

        forever begin
            // 1. Pede a proxima transacao ao Sequencer
            seq_item_port.get_next_item(tx);

            // 2. Aplica os sinais na interface (nos fios que vao ao DUT)
            @(posedge vif.clk);
            vif.enable     <= 1'b1;
            vif.current_in <= tx.current_in;
            vif.voltage_in <= tx.voltage_in;

            `uvm_info("DRV", $sformatf("Aplicando: I=%0d, V=%0d",
                $signed(tx.current_in), $signed(tx.voltage_in)), UVM_MEDIUM)

            // 3. Espera o DUT processar (store_valid = 1)
            //    Timeout de 50000 ciclos para nao travar a simulacao
            begin
                int timeout_cnt = 0;
                while (vif.store_valid !== 1'b1 && timeout_cnt < 50000) begin
                    @(posedge vif.clk);
                    timeout_cnt++;
                end
                if (timeout_cnt >= 50000)
                    `uvm_error("DRV", "Timeout esperando store_valid!")
            end

            // 4. Avisa o Sequencer que esta transacao foi aplicada
            seq_item_port.item_done();
        end
    endtask

endclass
