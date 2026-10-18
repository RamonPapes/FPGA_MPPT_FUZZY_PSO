library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package hybrid_mppt_pkg is

    constant N_PARTICLES : integer := 10;

    constant DUTY_MIN : integer := 0;
    constant DUTY_MAX : integer := 100;

    -- ------------------------------------------------------------------
    -- Subtipos com faixa explicita.
    --
    -- O uso de "integer" puro fazia o Quartus inferir 32 bits em todos os
    -- sinais internos e, principalmente, em todos os operadores "/", o que
    -- gerava divisores lpm_divide de 32 bits (LPM_WIDTHN = 32). Restringir a
    -- faixa reduz drasticamente a largura dos multiplicadores, divisores e
    -- registradores inferidos, sem alterar nenhum valor calculado.
    -- ------------------------------------------------------------------

    -- Duty cycle e posicao de particula: 0..100.
    subtype duty_t is integer range DUTY_MIN to DUTY_MAX;

    -- Erro e variacao do erro, ja saturados em +/-100 pela unidade de medida.
    subtype err_t is integer range -100 to 100;

    -- Grau de pertinencia fuzzy, em escala percentual.
    subtype mu_t is integer range 0 to 100;

    -- Saida defuzzificada e valores da tabela de regras.
    subtype rule_t is integer range -100 to 100;

    -- Velocidade de particula. A faixa acomoda com folga qualquer
    -- VEL_MIN_G/VEL_MAX_G razoavel antes da saturacao.
    subtype vel_t is integer range -512 to 511;

    -- Passo do refinamento Fokker-Planck.
    subtype step_t is integer range 0 to 255;

    -- Coeficientes do PSO (W, C1, C2) e coeficientes pseudoaleatorios rho.
    subtype coeff_t is integer range 0 to 255;

    -- Potencia instantanea. Com V em Q12.4 e I em Q1.15, ambos de 16 bits
    -- com sinal, o produto dividido por 65536 fica limitado a +/-16384.
    subtype power_t is integer range -32768 to 32767;

    -- Tensao amostrada e as diferencas delta_p / delta_v.
    subtype volt_t is integer range -32768 to 32767;
    subtype delta_t is integer range -65536 to 65535;

    -- Idade do pbest, usada pelo criterio MAX_PBEST_AGE_G.
    --
    -- A idade cresce de 1 por amostra e so e zerada quando a particula e a
    -- corrente E sua idade ja passou de MAX_PBEST_AGE_G. Entre duas visitas a
    -- mesma particula passam N_PARTICLES amostras, logo o pico e
    -- MAX_PBEST_AGE_G + N_PARTICLES. Com MAX_PBEST_AGE_G = 500 o maximo
    -- observado e 509, e a faixa abaixo cobre ate 1023.
    --
    -- Era 0 to 65535, o que custava 16 bits por particula (160 flip-flops) e
    -- alargava os dez somadores, comparadores e muxes de idade dentro do laco
    -- de pso_best_tracker_unit. O assert naquele arquivo garante que a faixa
    -- nunca seja violada em silencio se o generic mudar.
    subtype age_t is integer range 0 to 1023;

    -- Contador de paciencia da deteccao de queda de potencia.
    subtype drop_t is integer range 0 to 65535;

    -- Indice de particula.
    subtype particle_idx_t is integer range 0 to N_PARTICLES - 1;

    -- ------------------------------------------------------------------
    -- Tipos de vetor
    -- ------------------------------------------------------------------

    type duty_array is array (0 to N_PARTICLES - 1) of duty_t;
    type vel_array is array (0 to N_PARTICLES - 1) of vel_t;
    type power_array is array (0 to N_PARTICLES - 1) of power_t;
    type age_array is array (0 to N_PARTICLES - 1) of age_t;
    type coeff_array is array (0 to N_PARTICLES - 1) of coeff_t;

    type fuzzy_array is array (0 to 6) of mu_t;
    type rule_table is array (0 to 6, 0 to 6) of rule_t;

    -- Tabela de pertinencia: para cada valor possivel da entrada (err_t, de
    -- -100 a 100) guarda os sete graus de pertinencia. Sao 201 entradas de
    -- 7 x 7 = 49 bits, 9.849 bits no total.
    type mf_table_t is array (-100 to 100) of fuzzy_array;

    -- TRACK_BEST percorre o enxame em serie para envelhecer os pbest e apurar
    -- o gbest, uma particula por ciclo, no mesmo padrao de UPDATE_SWARM. Antes
    -- esse trabalho era feito inteiro dentro de SAMPLE_AND_UPDATE, por um laco
    -- combinacional desenrolado em dez copias.
    type state_type is (
        APPLY_PARTICLE,
        WAIT_SETTLE,
        SAMPLE_AND_UPDATE,
        TRACK_BEST,
        PREPARE_SWARM,
        UPDATE_SWARM,
        FINALIZE_SWARM
    );

    constant FUZZY_RULES : rule_table := (
        ( -100, -80, -60, -40, -20, -10,   0),
        ( -80,  -60, -40, -20, -10,   0,  10),
        ( -60,  -40, -20, -10,   0,  10,  20),
        ( -40,  -20, -10,   0,  10,  20,  40),
        ( -20,  -10,   0,  10,  20,  40,  60),
        ( -10,    0,  10,  20,  40,  60,  80),
        (   0,   10,  20,  40,  60,  80, 100)
    );

    -- Faixas do acumulador de defuzzificacao. Sao 49 regras, cada uma
    -- contribuindo com min_mu (0..100) vezes rule_val (-100..100).
    constant DEFUZZ_DEN_MAX : integer := 49 * 100;
    constant DEFUZZ_NUM_MAX : integer := 49 * 100 * 100;

    subtype defuzz_num_t is integer range -DEFUZZ_NUM_MAX to DEFUZZ_NUM_MAX;
    subtype defuzz_den_t is integer range 0 to DEFUZZ_DEN_MAX;

    -- Numerador e denominador das funcoes de pertinencia. Com e e de
    -- saturados em +/-100, a maior diferenca possivel entre dois pontos de
    -- quebra e 200, logo o numerador nao passa de 200 * 100.
    subtype mf_num_t is integer range 0 to 20000;
    subtype mf_den_t is integer range 1 to 200;

    function clamp(x, low, high : integer) return integer;
    function max_int(a, b : integer) return integer;
    function min_int(a, b : integer) return integer;
    function abs_int(x : integer) return integer;
    function sign_int(x : integer) return integer;

    function triangle(x, a, b, c : integer) return mu_t;

    function trapezoidal_shoulder_neg(
        x, plateau_end, slope_start, slope_end : integer
    ) return mu_t;

    function trapezoidal_shoulder_pos(
        x, slope_start, slope_end, plateau_start : integer
    ) return mu_t;

    function next_lfsr(x : unsigned(15 downto 0)) return unsigned;
    function rand_0_100(x : unsigned(15 downto 0)) return duty_t;
    function rand_rho(x : unsigned(15 downto 0); rho_min, rho_max : integer) return coeff_t;

    -- Constroi a tabela de pertinencia inteira em tempo de ELABORACAO,
    -- chamando as mesmas funcoes triangle/trapezoidal_* com os mesmos
    -- argumentos que fuzzy_compute chamava a cada avaliacao.
    --
    -- Antes, as catorze funcoes de pertinencia eram avaliadas em hardware a
    -- cada amostra, e cada uma carregava seu proprio "num / den": catorze
    -- lpm_divide, cerca de 2.280 ALUTs. Como mu_e depende so de e e mu_de so
    -- de de, e ambos sao um unico valor de 8 bits, o resultado cabe numa
    -- tabela e os divisores desaparecem.
    function build_mf_table(step_v, edge_v : integer) return mf_table_t;

    -- Combina as 49 regras e defuzzifica. E a segunda metade do antigo
    -- fuzzy_compute; a primeira virou a tabela acima.
    function fuzzy_defuzz(mu_e, mu_de : fuzzy_array) return rule_t;

    -- Recebe o valor fuzzy ja calculado. Antes esta funcao chamava
    -- fuzzy_compute internamente, o que instanciava um segundo motor fuzzy
    -- completo em paralelo com o primeiro.
    function fokker_planck_step(
        fuzzy_val,
        fokker_step_min,
        fokker_step_max : integer
    ) return step_t;

    function pno_direction(delta_p, delta_v : integer) return integer;

    -- Divisao inteira com truncamento em direcao a zero, identica ao operador
    -- "/" do VHDL, porem executada sobre a magnitude.
    --
    -- Motivo: divisao COM SINAL por uma constante que nao e potencia de dois
    -- (100, 10000) trunca em direcao a zero e o Quartus so consegue
    -- implementa-la com um lpm_divide completo. A mesma conta sobre um valor
    -- SEM SINAL vira multiplicacao por reciproco mais deslocamento, em LUTs.
    -- Como o numerador e reduzido a magnitude antes da divisao e o sinal e
    -- reaplicado depois, o resultado e bit a bit igual ao de num/den.
    --
    -- num_bits deve comportar abs(num) e serve para manter o operador
    -- estreito; sem ele o Quartus assume 32 bits.
    function div_trunc(num : integer; den : positive; num_bits : positive) return integer;

end package hybrid_mppt_pkg;


package body hybrid_mppt_pkg is

    function clamp(x, low, high : integer) return integer is
    begin
        if x < low then
            return low;
        elsif x > high then
            return high;
        else
            return x;
        end if;
    end function;

    function max_int(a, b : integer) return integer is
    begin
        if a > b then
            return a;
        else
            return b;
        end if;
    end function;

    function min_int(a, b : integer) return integer is
    begin
        if a < b then
            return a;
        else
            return b;
        end if;
    end function;

    function abs_int(x : integer) return integer is
    begin
        if x < 0 then
            return -x;
        else
            return x;
        end if;
    end function;

    function sign_int(x : integer) return integer is
    begin
        if x > 0 then
            return 1;
        elsif x < 0 then
            return -1;
        else
            return 0;
        end if;
    end function;

    -- ------------------------------------------------------------------
    -- Funcoes de pertinencia.
    --
    -- Os quocientes sao montados com numerador e denominador estritamente
    -- positivos (natural) em vez de integer com sinal. Divisao com sinal
    -- trunca em direcao a zero e o Quartus a implementa com lpm_divide;
    -- divisao sem sinal por constante vira multiplicacao por reciproco e
    -- deslocamento, em LUTs. O valor resultante e identico, porque nesses
    -- ramos os operandos ja eram positivos.
    -- ------------------------------------------------------------------

    function triangle(x, a, b, c : integer) return mu_t is
        variable num : mf_num_t;
        variable den : mf_den_t;
    begin
        if b <= a or c <= b then
            return 0;
        elsif x <= a or x >= c then
            return 0;
        elsif x = b then
            return 100;
        elsif x < b then
            num := (x - a) * 100;
            den := b - a;
        else
            num := (c - x) * 100;
            den := c - b;
        end if;

        return num / den;
    end function;

    function trapezoidal_shoulder_neg(
        x, plateau_end, slope_start, slope_end : integer
    ) return mu_t is
        variable num : mf_num_t;
        variable den : mf_den_t;
    begin
        if slope_end <= slope_start then
            return 0;
        elsif x <= plateau_end then
            return 100;
        elsif x >= slope_end then
            return 0;
        elsif x > slope_start then
            num := (slope_end - x) * 100;
            den := slope_end - slope_start;

            return num / den;
        else
            return 100;
        end if;
    end function;

    function trapezoidal_shoulder_pos(
        x, slope_start, slope_end, plateau_start : integer
    ) return mu_t is
        variable num : mf_num_t;
        variable den : mf_den_t;
    begin
        if slope_end <= slope_start then
            return 0;
        elsif x >= plateau_start then
            return 100;
        elsif x <= slope_start then
            return 0;
        elsif x < slope_end then
            num := (x - slope_start) * 100;
            den := slope_end - slope_start;

            return num / den;
        else
            return 100;
        end if;
    end function;

    function next_lfsr(x : unsigned(15 downto 0)) return unsigned is
        variable y  : unsigned(15 downto 0);
        variable fb : std_logic;
    begin
        fb := x(15) xor x(13) xor x(12) xor x(10);
        y := x(14 downto 0) & fb;
        return y;
    end function;

    function rand_0_100(x : unsigned(15 downto 0)) return duty_t is
    begin
        return to_integer(x(7 downto 0)) mod 101;
    end function;

    function rand_rho(x : unsigned(15 downto 0); rho_min, rho_max : integer) return coeff_t is
        variable low_rho  : integer;
        variable high_rho : integer;
    begin
        if rho_min <= rho_max then
            low_rho := rho_min;
            high_rho := rho_max;
        else
            low_rho := rho_max;
            high_rho := rho_min;
        end if;

        return low_rho + (to_integer(x(7 downto 0)) mod (high_rho - low_rho + 1));
    end function;

    function build_mf_table(step_v, edge_v : integer) return mf_table_t is
        variable t : mf_table_t;
    begin
        for x in -100 to 100 loop
            t(x)(0) := trapezoidal_shoulder_neg(x, -100, -edge_v, -(2 * step_v));
            t(x)(1) := triangle(x, -edge_v, -(2 * step_v), -step_v);
            t(x)(2) := triangle(x, -(2 * step_v), -step_v, 0);
            t(x)(3) := triangle(x, -step_v, 0, step_v);
            t(x)(4) := triangle(x, 0, step_v, 2 * step_v);
            t(x)(5) := triangle(x, step_v, 2 * step_v, edge_v);
            t(x)(6) := trapezoidal_shoulder_pos(x, 2 * step_v, edge_v, 100);
        end loop;

        return t;
    end function;

    function fuzzy_defuzz(mu_e, mu_de : fuzzy_array) return rule_t is
        variable numerator   : defuzz_num_t := 0;
        variable denominator : defuzz_den_t := 0;

        variable min_mu   : mu_t;
        variable rule_val : rule_t;
    begin
        for i in 0 to 6 loop
            for j in 0 to 6 loop
                min_mu := min_int(mu_e(i), mu_de(j));
                rule_val := FUZZY_RULES(i, j);

                numerator := numerator + min_mu * rule_val;
                denominator := denominator + min_mu;
            end loop;
        end loop;

        if denominator /= 0 then
            return numerator / denominator;
        else
            return 0;
        end if;
    end function;

    function fokker_planck_step(
        fuzzy_val,
        fokker_step_min,
        fokker_step_max : integer
    ) return step_t is
        variable mag       : mu_t;
        variable span      : step_t;
        variable step_val  : integer;
        variable step_min  : integer;
        variable step_max  : integer;
    begin
        if fokker_step_min <= fokker_step_max then
            step_min := fokker_step_min;
            step_max := fokker_step_max;
        else
            step_min := fokker_step_max;
            step_max := fokker_step_min;
        end if;

        mag := abs_int(fuzzy_val);
        span := step_max - step_min;

        step_val := step_min + ((mag * span) / 100);

        return clamp(step_val, step_min, step_max);
    end function;

    function pno_direction(delta_p, delta_v : integer) return integer is
    begin
        if delta_p > 0 then
            if delta_v > 0 then
                return 1;
            elsif delta_v < 0 then
                return -1;
            else
                return 0;
            end if;
        elsif delta_p < 0 then
            if delta_v > 0 then
                return -1;
            elsif delta_v < 0 then
                return 1;
            else
                return 0;
            end if;
        else
            return 0;
        end if;
    end function;

    function div_trunc(num : integer; den : positive; num_bits : positive) return integer is
        variable mag : unsigned(num_bits - 1 downto 0);
    begin
        -- Um unico operador "/". Antes havia um em cada ramo do if, e como a
        -- sintese constroi todos os ramos antes de escolher com um mux, ela
        -- instanciava DOIS divisores por chamada: 6 em pso_particle_update_unit
        -- para 3 chamadas, e 20 em pso_best_tracker_unit para um laco de 10.
        -- abs_int(num) devolve exatamente os dois numeradores originais, entao
        -- o resultado e identico bit a bit.
        mag := to_unsigned(abs_int(num), num_bits) / den;

        if num < 0 then
            return -to_integer(mag);
        else
            return to_integer(mag);
        end if;
    end function;

end package body hybrid_mppt_pkg;
