// =============================================================================
// tb_top.sv
// Modulo top-level — conecta o mundo UVM ao DUT VHDL.
//
// Aqui acontece a "costura" entre:
//   - Clock e Reset (gerados aqui)
//   - Interface SV (o "cabo")
//   - DUT VHDL (wrapper)
//   - UVM (via run_test)
//
// Conexao:
//   UVM (Driver/Monitor) --> Interface SV --> Sinais --> DUT VHDL (wrapper)
// =============================================================================

`timescale 1ns/1ps

module tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import mppt_tb_pkg::*;

    // -------------------------------------------------------------------------
    // 1. Clock e Reset
    // -------------------------------------------------------------------------
    logic clk = 0;
    logic reset = 1;

    // Clock: 20ns de periodo (50 MHz) — mesma frequencia do testbench VHDL
    always #10 clk = ~clk;

    // Reset: ativo por 100ns, depois desativa
    initial begin
        reset = 1;
        #100;
        reset = 0;
    end

    // -------------------------------------------------------------------------
    // 2. Instancia a Interface
    // -------------------------------------------------------------------------
    mppt_if intf(clk, reset);

    // -------------------------------------------------------------------------
    // 3. Instancia o DUT (wrapper VHDL) e conecta a interface
    //    Aqui eh a ponte VHDL <-> SystemVerilog.
    //    Cada porta do wrapper se conecta a um sinal da interface.
    // -------------------------------------------------------------------------
    mppt_top_wrapper #(
        .SETTLE_CYCLES(1)      // 1 ciclo de espera (rapido para simulacao)
    ) dut (
        .clk              (clk),
        .reset            (reset),
        .enable           (intf.enable),
        .current_in       (intf.current_in),
        .voltage_in       (intf.voltage_in),
        .duty_out         (intf.duty_out),
        .store_valid      (intf.store_valid),
        .control_duty_out (intf.control_duty_out),
        .gbest_duty_out   (intf.gbest_duty_out),
        .gbest_power_out  (intf.gbest_power_out),
        .error_out        (intf.error_out),
        .delta_e_out      (intf.delta_e_out),
        .fuzzy_delta_out  (intf.fuzzy_delta_out)
    );

    // -------------------------------------------------------------------------
    // 4. Registra a interface no UVM e inicia o teste
    // -------------------------------------------------------------------------
    initial begin
        // Registra a interface para que Driver e Monitor possam encontra-la
        uvm_config_db #(virtual mppt_if)::set(null, "*", "vif", intf);

        // Inicia o UVM — ele vai procurar o teste pelo nome passado em
        // +UVM_TESTNAME=mppt_test na linha de comando
        run_test();
    end

endmodule
