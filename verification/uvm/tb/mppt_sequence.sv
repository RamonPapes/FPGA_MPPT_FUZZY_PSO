// =============================================================================
// mppt_sequence.sv
// Sequence — roteiro de verificacao funcional com 28 cenarios.
//
// Estrategia: tensao em rampa (dV=20 entre TXs consecutivas) com corrente
// variando dramaticamente, de modo que o erro (dP/dV) seja nao-nulo e
// os graficos mostrem comportamento real do controlador.
//
// 7 categorias x 4 cenarios = 28 transacoes:
//   Cat 1: Warmup          — estabelece estado base
//   Cat 2: Oscilacao       — corrente alterna alto/baixo (erro oscila)
//   Cat 3: Queda brusca    — corrente colapsa e recupera (erro extremo)
//   Cat 4: Estabilizacao   — corrente gradual (erro tende a zero)
//   Cat 5: Negativos       — corrente negativa (potencia negativa)
//   Cat 6: Inversao        — corrente max positivo/negativo (erro maximo)
//   Cat 7: Atenuacao       — corrente decresce ate quase zero
// =============================================================================

class mppt_sequence extends uvm_sequence #(mppt_seq_item);

    `uvm_object_utils(mppt_sequence)

    function new(string name = "mppt_sequence");
        super.new(name);
    endfunction

    task send_tx(input string cat_name, input bit [15:0] i_val, input bit [15:0] v_val);
        mppt_seq_item tx;
        tx = mppt_seq_item::type_id::create("tx");
        start_item(tx);
        tx.current_in = i_val;
        tx.voltage_in = v_val;
        finish_item(tx);
        `uvm_info("SEQ", $sformatf("[%s] Enviado: I=%0d, V=%0d",
            cat_name, $signed(tx.current_in), $signed(tx.voltage_in)), UVM_LOW)
    endtask

    virtual task body();

        // =================================================================
        // CATEGORIA 1: Warmup (4 cenarios)
        // Estabelece estado base. Tensao parte de 1000.
        // =================================================================
        `uvm_info("SEQ", "--- CAT 1: Warmup ---", UVM_LOW)
        send_tx("CAT1", 16'sd0,     16'sd1000);   // 1  P=0
        send_tx("CAT1", 16'sd0,     16'sd1020);   // 2  P=0
        send_tx("CAT1", 16'sd5000,  16'sd1040);   // 3  P=79, primeiro P>0
        send_tx("CAT1", 16'sd10000, 16'sd1060);   // 4  P=161

        // =================================================================
        // CATEGORIA 2: Oscilacao moderada (4 cenarios)
        // Corrente alterna entre alto e baixo — erro oscila positivo/negativo
        // =================================================================
        `uvm_info("SEQ", "--- CAT 2: Oscilacao moderada ---", UVM_LOW)
        send_tx("CAT2", 16'sd20000, 16'sd1080);   // 5  P=329, err~+8
        send_tx("CAT2", 16'sd5000,  16'sd1100);   // 6  P=83,  err~-12
        send_tx("CAT2", 16'sd25000, 16'sd1120);   // 7  P=427, err~+17
        send_tx("CAT2", 16'sd5000,  16'sd1140);   // 8  P=86,  err~-17

        // =================================================================
        // CATEGORIA 3: Queda brusca + recuperacao (4 cenarios)
        // Corrente colapsa para 100 e depois volta a 30000 — erros extremos
        // =================================================================
        `uvm_info("SEQ", "--- CAT 3: Queda brusca + recuperacao ---", UVM_LOW)
        send_tx("CAT3", 16'sd100,   16'sd1160);   // 9  P~1,   err~-4
        send_tx("CAT3", 16'sd30000, 16'sd1180);   // 10 P~540, err~+26
        send_tx("CAT3", 16'sd100,   16'sd1200);   // 11 P~1,   err~-26
        send_tx("CAT3", 16'sd30000, 16'sd1220);   // 12 P~558, err~+27

        // =================================================================
        // CATEGORIA 4: Estabilizacao (4 cenarios)
        // Corrente varia pouco — erro tende a zero, sistema se acalma
        // =================================================================
        `uvm_info("SEQ", "--- CAT 4: Estabilizacao ---", UVM_LOW)
        send_tx("CAT4", 16'sd15000, 16'sd1240);   // 13 P~283, err~-13
        send_tx("CAT4", 16'sd16000, 16'sd1260);   // 14 P~307, err~+1
        send_tx("CAT4", 16'sd14000, 16'sd1280);   // 15 P~273, err~-1
        send_tx("CAT4", 16'sd15000, 16'sd1300);   // 16 P~297, err~+1

        // =================================================================
        // CATEGORIA 5: Valores negativos (4 cenarios)
        // Corrente negativa produz potencia negativa. Verifica que o PSO
        // nao rastreia potencia negativa como melhor solucao (V4).
        // =================================================================
        `uvm_info("SEQ", "--- CAT 5: Valores negativos ---", UVM_LOW)
        send_tx("CAT5", -16'sd10000, 16'sd1320);  // 17 P~-201, err~-24
        send_tx("CAT5", -16'sd20000, 16'sd1340);  // 18 P~-409, err~-10
        send_tx("CAT5", 16'sd15000,  16'sd1360);  // 19 P~311,  err~+36
        send_tx("CAT5", -16'sd15000, 16'sd1380);  // 20 P~-315, err~-31

        // =================================================================
        // CATEGORIA 6: Inversao extrema (4 cenarios)
        // Corrente inverte entre +30000 e -30000 — erros maximos
        // =================================================================
        `uvm_info("SEQ", "--- CAT 6: Inversao extrema ---", UVM_LOW)
        send_tx("CAT6", 16'sd30000,  16'sd1400);  // 21 P~640,  err~+47
        send_tx("CAT6", -16'sd30000, 16'sd1420);  // 22 P~-650, err~-64
        send_tx("CAT6", 16'sd30000,  16'sd1440);  // 23 P~659,  err~+65
        send_tx("CAT6", -16'sd30000, 16'sd1460);  // 24 P~-668, err~-66

        // =================================================================
        // CATEGORIA 7: Atenuacao (4 cenarios)
        // Corrente decresce gradualmente — sistema retorna ao repouso
        // =================================================================
        `uvm_info("SEQ", "--- CAT 7: Atenuacao ---", UVM_LOW)
        send_tx("CAT7", 16'sd20000, 16'sd1480);   // 25 P~451, err~+55
        send_tx("CAT7", 16'sd10000, 16'sd1500);   // 26 P~228, err~-11
        send_tx("CAT7", 16'sd3000,  16'sd1520);   // 27 P~69,  err~-7
        send_tx("CAT7", 16'sd100,   16'sd1540);   // 28 P~2,   err~-3

    endtask

endclass
