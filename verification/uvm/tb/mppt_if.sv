// =============================================================================
// mppt_if.sv
// Interface — o "cabo" entre o testbench UVM e o DUT.
//
// Declara todos os sinais que existem na fronteira do DUT.
// O Driver escreve nos sinais de entrada.
// O Monitor le os sinais de saida.
//
// Todos os tipos aqui sao "logic" porque estamos conectando ao wrapper VHDL
// que ja converteu tudo para std_logic_vector.
// =============================================================================

interface mppt_if (
    input logic clk,
    input logic reset
);

    // Sinais de ENTRADA (Driver escreve aqui)
    logic        enable;
    logic [15:0] current_in;
    logic [15:0] voltage_in;

    // Sinais de SAIDA (Monitor le daqui)
    logic [7:0]  duty_out;
    logic        store_valid;
    logic signed [31:0] control_duty_out;
    logic signed [31:0] gbest_duty_out;
    logic signed [31:0] gbest_power_out;
    logic signed [31:0] error_out;
    logic signed [31:0] delta_e_out;
    logic signed [31:0] fuzzy_delta_out;

endinterface
