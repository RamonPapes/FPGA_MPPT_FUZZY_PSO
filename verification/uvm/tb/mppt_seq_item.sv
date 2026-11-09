// =============================================================================
// mppt_seq_item.sv
// Sequence Item — representa uma transacao (um par corrente/tensao de entrada
// e as saidas observadas do DUT).
//
// Analogia: eh o "formulario" que circula no testbench.
//   - O Sequence preenche os campos de entrada (current, voltage).
//   - O Driver le esses campos e aplica os sinais no DUT.
//   - O Monitor preenche os campos de saida depois de observar o DUT.
//   - O Scoreboard le tudo e verifica se esta correto.
// =============================================================================

class mppt_seq_item extends uvm_sequence_item;

    // -------------------------------------------------------------------------
    // Campos de ENTRADA (o que sera aplicado no DUT)
    // "rand" significa que o UVM pode gerar valores aleatorios para estes campos
    // -------------------------------------------------------------------------
    rand bit [15:0] current_in;     // Corrente do painel solar (signed 16 bits)
    rand bit [15:0] voltage_in;     // Tensao do painel solar (signed 16 bits)

    // -------------------------------------------------------------------------
    // Campos de SAIDA (o que o Monitor captura do DUT)
    // NAO sao "rand" porque nao geramos estes valores — observamos.
    // -------------------------------------------------------------------------
    bit [7:0]       duty_out;           // Duty cycle [0-100]
    bit             store_valid;        // Pulso de dado valido
    bit signed [31:0] control_duty_out; // Duty refinado pelo fuzzy
    bit signed [31:0] gbest_duty_out;   // Melhor duty global (PSO)
    bit signed [31:0] gbest_power_out;  // Melhor potencia global (PSO)
    bit signed [31:0] error_out;        // Sinal de erro
    bit signed [31:0] delta_e_out;      // Derivada do erro
    bit signed [31:0] fuzzy_delta_out;  // Saida do controlador fuzzy

    // -------------------------------------------------------------------------
    // Registro na UVM
    // Isto diz ao UVM: "estes campos fazem parte desta transacao".
    // Permite que o UVM imprima, copie e compare transacoes automaticamente.
    // -------------------------------------------------------------------------
    `uvm_object_utils_begin(mppt_seq_item)
        `uvm_field_int(current_in,       UVM_ALL_ON)
        `uvm_field_int(voltage_in,       UVM_ALL_ON)
        `uvm_field_int(duty_out,         UVM_ALL_ON)
        `uvm_field_int(store_valid,      UVM_ALL_ON)
        `uvm_field_int(control_duty_out, UVM_ALL_ON)
        `uvm_field_int(gbest_duty_out,   UVM_ALL_ON)
        `uvm_field_int(gbest_power_out,  UVM_ALL_ON)
        `uvm_field_int(error_out,        UVM_ALL_ON)
        `uvm_field_int(delta_e_out,      UVM_ALL_ON)
        `uvm_field_int(fuzzy_delta_out,  UVM_ALL_ON)
    `uvm_object_utils_end

    // -------------------------------------------------------------------------
    // Construtor (obrigatorio no UVM — toda classe precisa de um)
    // -------------------------------------------------------------------------
    function new(string name = "mppt_seq_item");
        super.new(name);
    endfunction

endclass
