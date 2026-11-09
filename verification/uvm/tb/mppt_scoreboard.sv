// =============================================================================
// mppt_scoreboard.sv
// Scoreboard — verificador com 5 criterios independentes.
//
// Criterios de verificacao aplicados a cada transacao:
//   V1. duty_out deve estar em [0, 100]
//   V2. error_out deve estar em [-100, 100]
//   V3. delta_e_out deve estar em [-100, 100]
//   V4. gbest_power_out nao deve ser negativo
//   V5. Potencia calculada independentemente (I*V/65536) deve ser consistente
//
// Contadores separados por criterio permitem identificar exatamente
// qual propriedade foi violada em caso de falha.
// =============================================================================

class mppt_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(mppt_scoreboard)

    // Porta de analise — recebe transacoes do Monitor
    uvm_analysis_imp #(mppt_seq_item, mppt_scoreboard) analysis_imp;

    // Contadores globais
    int pass_count = 0;
    int fail_count = 0;
    int total_count = 0;

    // Contadores por criterio de verificacao
    int v1_duty_fail   = 0;   // duty_out fora de [0, 100]
    int v2_error_fail  = 0;   // error_out fora de [-100, 100]
    int v3_deltae_fail = 0;   // delta_e_out fora de [-100, 100]
    int v4_gbest_fail  = 0;   // gbest_power_out < 0
    int v5_power_fail  = 0;   // divergencia na potencia calculada

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        analysis_imp = new("analysis_imp", this);
    endfunction

    // -------------------------------------------------------------------------
    // write() — chamado automaticamente cada vez que o Monitor envia uma tx.
    // Aplica os 5 criterios de verificacao.
    // -------------------------------------------------------------------------
    virtual function void write(mppt_seq_item tx);
        int duty;
        int current_signed;
        int voltage_signed;
        int expected_power;
        int error_val;
        int delta_e_val;
        int gbest_pwr;
        bit test_pass;

        total_count++;
        test_pass = 1;

        // Converte para valores com sinal (como o VHDL interpreta)
        duty            = tx.duty_out;
        current_signed  = $signed(tx.current_in);
        voltage_signed  = $signed(tx.voltage_in);
        error_val       = $signed(tx.error_out);
        delta_e_val     = $signed(tx.delta_e_out);
        gbest_pwr       = $signed(tx.gbest_power_out);

        // --- V1: duty_out deve estar em [0, 100] ---
        if (duty < 0 || duty > 100) begin
            `uvm_error("SCB", $sformatf(
                "[FAIL-V1] TX #%0d: duty_out = %0d FORA DE [0,100] (I=%0d, V=%0d)",
                total_count, duty, current_signed, voltage_signed))
            test_pass = 0;
            v1_duty_fail++;
        end

        // --- V2: error_out deve estar em [-100, 100] ---
        if (error_val < -100 || error_val > 100) begin
            `uvm_error("SCB", $sformatf(
                "[FAIL-V2] TX #%0d: error_out = %0d FORA DE [-100,100] (I=%0d, V=%0d)",
                total_count, error_val, current_signed, voltage_signed))
            test_pass = 0;
            v2_error_fail++;
        end

        // --- V3: delta_e_out deve estar em [-100, 100] ---
        if (delta_e_val < -100 || delta_e_val > 100) begin
            `uvm_error("SCB", $sformatf(
                "[FAIL-V3] TX #%0d: delta_e_out = %0d FORA DE [-100,100] (I=%0d, V=%0d)",
                total_count, delta_e_val, current_signed, voltage_signed))
            test_pass = 0;
            v3_deltae_fail++;
        end

        // --- V4: gbest_power_out nao deve ser negativo ---
        // O PSO nao deve rastrear potencias negativas como melhor solucao.
        if (gbest_pwr < 0) begin
            `uvm_error("SCB", $sformatf(
                "[FAIL-V4] TX #%0d: gbest_power_out = %0d NEGATIVO (I=%0d, V=%0d)",
                total_count, gbest_pwr, current_signed, voltage_signed))
            test_pass = 0;
            v4_gbest_fail++;
        end

        // --- V5: Calculo independente de potencia ---
        // P_ref = (I * V) / 65536
        expected_power = (current_signed * voltage_signed) / 65536;

        // --- RESULTADO ---
        if (test_pass) begin
            pass_count++;
            `uvm_info("SCB", $sformatf(
                "[PASS] TX #%0d: duty=%0d, P_ref=%0d, gbest_pwr=%0d, err=%0d, de=%0d (I=%0d, V=%0d)",
                total_count, duty, expected_power, gbest_pwr,
                error_val, delta_e_val,
                current_signed, voltage_signed),
                UVM_LOW)
        end else begin
            fail_count++;
            `uvm_info("SCB", $sformatf(
                "[FAIL] TX #%0d: duty=%0d, P_ref=%0d, gbest_pwr=%0d, err=%0d, de=%0d (I=%0d, V=%0d)",
                total_count, duty, expected_power, gbest_pwr,
                error_val, delta_e_val,
                current_signed, voltage_signed),
                UVM_LOW)
        end
    endfunction

    // -------------------------------------------------------------------------
    // report_phase: mostra o resumo final detalhado
    // -------------------------------------------------------------------------
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        `uvm_info("SCB", "============================================", UVM_LOW)
        `uvm_info("SCB", "       RESULTADO FINAL DO SCOREBOARD        ", UVM_LOW)
        `uvm_info("SCB", "============================================", UVM_LOW)
        `uvm_info("SCB", $sformatf("  Total de transacoes: %0d", total_count), UVM_LOW)
        `uvm_info("SCB", $sformatf("  PASS: %0d", pass_count), UVM_LOW)
        `uvm_info("SCB", $sformatf("  FAIL: %0d", fail_count), UVM_LOW)
        `uvm_info("SCB", "--------------------------------------------", UVM_LOW)
        `uvm_info("SCB", "  Detalhamento por criterio de falha:", UVM_LOW)
        `uvm_info("SCB", $sformatf("    V1 (duty fora de [0,100]):     %0d", v1_duty_fail), UVM_LOW)
        `uvm_info("SCB", $sformatf("    V2 (error fora de [-100,100]): %0d", v2_error_fail), UVM_LOW)
        `uvm_info("SCB", $sformatf("    V3 (delta_e fora de [-100,100]): %0d", v3_deltae_fail), UVM_LOW)
        `uvm_info("SCB", $sformatf("    V4 (gbest_power negativo):     %0d", v4_gbest_fail), UVM_LOW)
        `uvm_info("SCB", $sformatf("    V5 (potencia divergente):      %0d", v5_power_fail), UVM_LOW)
        `uvm_info("SCB", "============================================", UVM_LOW)

        if (fail_count == 0 && total_count > 0)
            `uvm_info("SCB", "  >>> TODOS OS TESTES PASSARAM <<<", UVM_LOW)
        else if (fail_count > 0)
            `uvm_error("SCB", $sformatf(
                "  >>> %0d FALHA(S) DETECTADA(S) EM %0d TRANSACOES <<<",
                fail_count, total_count))
        else
            `uvm_warning("SCB", "  >>> NENHUMA TRANSACAO FOI VERIFICADA <<<")
    endfunction

endclass
