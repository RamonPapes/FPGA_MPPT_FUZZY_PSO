library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg.ALL;

entity hybrid_pso_fuzzy_mppt is
    generic (
        SETTLE_CYCLES     : integer := 1000;
        W_PSO_G           : integer := 50;
        C1_PSO_G          : integer := 50;
        C2_PSO_G          : integer := 40;
        RHO_MIN_G         : integer := 53;
        RHO_MAX_G         : integer := 56;
        VEL_MIN_G         : integer := -20;
        VEL_MAX_G         : integer := 20;
        DEADZONE_G        : integer := 2;
        SEARCH_RADIUS_G   : integer := 12;
        FOKKER_STEP_MIN_G : integer := 1;
        FOKKER_STEP_MAX_G : integer := 8;
        FUZZY_STEP_G      : integer := 30;
        FUZZY_EDGE_G      : integer := 90;
        POWER_SCALE_DEN_G : integer := 65536;
        ERROR_GAIN_G      : integer := 1;
        DELTA_V_MIN_G     : integer := 16;
        DUTY_DIRECTION_G  : integer := -1;
        SEARCH_CENTER_MODE_G : integer := 1;
        MEMORY_HALF_LIFE_G : integer := 300;
        MAX_PBEST_AGE_G : integer := 500;
        ENABLE_CHANGE_DETECTION_G : integer := 0;
        DROP_THRESHOLD_PERCENT_G : integer := 70;
        DROP_PATIENCE_G : integer := 30
    );
    port (
        clk              : in  std_logic;
        reset            : in  std_logic;
        enable           : in  std_logic;

        current_in       : in  signed(15 downto 0);  -- Q1.15 normalizado
        voltage_in       : in  signed(15 downto 0);  -- Q12.4 por padrao

        duty_out         : out std_logic_vector(7 downto 0);
        control_duty_out : out duty_t;
        store_valid      : out std_logic;

        gbest_duty_out   : out duty_t;
        gbest_power_out  : out power_t;
        error_out        : out err_t;
        delta_e_out      : out err_t;
        fuzzy_delta_out  : out rule_t
    );
end hybrid_pso_fuzzy_mppt;

architecture Structural of hybrid_pso_fuzzy_mppt is

    function init_particle_positions return duty_array is
        variable arr  : duty_array;
        variable seed : unsigned(15 downto 0) := x"ACE1";
    begin
        for i in 0 to N_PARTICLES - 1 loop
            seed := next_lfsr(seed);
            arr(i) := rand_0_100(seed);
        end loop;

        return arr;
    end function;

    function init_particle_velocities return vel_array is
        variable arr  : vel_array;
    begin
        for i in 0 to N_PARTICLES - 1 loop
            arr(i) := 0;
        end loop;

        return arr;
    end function;

    constant INIT_POS : duty_array := init_particle_positions;
    constant INIT_VEL : vel_array := init_particle_velocities;

    signal particle_pos      : duty_array := INIT_POS;
    signal particle_vel      : vel_array := INIT_VEL;
    signal pbest_pos         : duty_array := INIT_POS;
    signal pbest_power       : power_array := (others => 0);
    signal pbest_age         : age_array := (others => 0);

    -- Saida da unica instancia de atualizacao de particula, aplicada a uma
    -- particula por ciclo de clock.
    signal next_particle_pos : duty_t := 50;
    signal next_particle_vel : vel_t := 0;

    -- Saida da unica instancia do rastreador de melhores, aplicada a uma
    -- particula por ciclo durante TRACK_BEST.
    signal next_pbest_pos    : duty_t := 50;
    signal next_pbest_power  : power_t := 0;
    signal next_pbest_age    : age_t := 0;

    -- Entradas multiplexadas do rastreador.
    signal trk_pos     : duty_t := 50;
    signal trk_power   : power_t := 0;
    signal trk_age     : age_t := 0;
    signal trk_is_cur  : std_logic := '0';

    -- Valores amostrados no inicio de TRACK_BEST. Precisam ser registrados
    -- porque prev_power/prev_voltage mudam no mesmo ciclo, e com eles muda
    -- power_now_sig, que e combinacional.
    signal track_i      : particle_idx_t := 0;
    signal track_cur    : particle_idx_t := 0;
    signal track_power  : power_t := 0;
    signal track_duty   : duty_t := 50;

    -- Maximo corrente da varredura, no lugar da cadeia de nove comparadores
    -- em serie que o laco desenrolado produzia.
    signal run_best_power : power_t := 0;
    signal run_best_pos   : duty_t := 50;

    -- Os arrays rho1_arr/rho2_arr deixaram de existir. O par de coeficientes
    -- da particula corrente e produzido sob demanda por pso_random_coeff_unit,
    -- diretamente sobre sel_rho1/sel_rho2.

    signal gbest_pos         : duty_t := 50;
    signal gbest_power       : power_t := 0;
    signal drop_counter      : drop_t := 0;

    constant WAIT_MAX : integer := max_int(SETTLE_CYCLES, 1);

    signal current_idx       : particle_idx_t := 0;
    signal swarm_idx         : particle_idx_t := 0;
    signal wait_counter      : integer range 0 to WAIT_MAX := 0;

    -- Multiplexadores explicitos da particula corrente. Um nome indexado por
    -- um sinal nao e um nome estatico e nem toda ferramenta o aceita direto
    -- como actual de port map, entao a selecao e feita aqui.
    signal sel_pos   : duty_t := 50;
    signal sel_vel   : vel_t := 0;
    signal sel_pbest : duty_t := 50;
    signal sel_rho1  : coeff_t := 53;
    signal sel_rho2  : coeff_t := 53;

    signal prev_power        : power_t := 0;
    signal prev_voltage      : volt_t := 0;
    signal prev_error        : err_t := 0;

    signal power_now_sig     : power_t := 0;
    signal voltage_now_sig   : volt_t := 0;
    signal delta_p_sig       : delta_t := 0;
    signal delta_v_sig       : delta_t := 0;
    signal error_next_sig    : err_t := 0;
    signal delta_e_next_sig  : err_t := 0;

    signal fuzzy_next_sig    : rule_t := 0;
    signal ffp_step_sig      : step_t := 1;
    signal refined_duty_sig  : duty_t := 50;

    signal error_reg         : err_t := 0;
    signal delta_e_reg       : err_t := 0;
    signal fuzzy_delta       : rule_t := 0;

    signal duty_reg          : duty_t := 50;
    signal pno_candidate     : duty_t := 50;
    signal search_center     : duty_t := 50;
    signal fokker_step       : step_t := 1;

    signal search_low        : duty_t := 38;
    signal search_high       : duty_t := 62;

    signal lfsr              : unsigned(15 downto 0) := x"ACE1";
    signal next_lfsr_sig     : unsigned(15 downto 0) := x"ACE1";

    signal state             : state_type := APPLY_PARTICLE;

begin

    u_search_window: entity work.pso_search_window_unit
        generic map (
            SEARCH_RADIUS_G => SEARCH_RADIUS_G
        )
        port map (
            search_center_in => search_center,
            search_low_out   => search_low,
            search_high_out  => search_high
        );

    u_measurement: entity work.mppt_measurement_unit
        generic map (
            POWER_SCALE_DEN_G => POWER_SCALE_DEN_G,
            ERROR_GAIN_G      => ERROR_GAIN_G,
            DELTA_V_MIN_G     => DELTA_V_MIN_G
        )
        port map (
            current_in     => current_in,
            voltage_in     => voltage_in,
            prev_power     => prev_power,
            prev_voltage   => prev_voltage,
            prev_error     => prev_error,

            power_now      => power_now_sig,
            voltage_now    => voltage_now_sig,
            delta_p        => delta_p_sig,
            delta_v        => delta_v_sig,
            error_next     => error_next_sig,
            delta_e_next   => delta_e_next_sig
        );

    u_fuzzy_ffp: entity work.mppt_fuzzy_ffp_unit
        generic map (
            DEADZONE_G        => DEADZONE_G,
            FOKKER_STEP_MIN_G => FOKKER_STEP_MIN_G,
            FOKKER_STEP_MAX_G => FOKKER_STEP_MAX_G,
            FUZZY_STEP_G      => FUZZY_STEP_G,
            FUZZY_EDGE_G      => FUZZY_EDGE_G,
            DUTY_DIRECTION_G  => DUTY_DIRECTION_G
        )
        port map (
            duty_in       => pno_candidate,
            delta_p       => delta_p_sig,
            delta_v       => delta_v_sig,
            error_in      => error_next_sig,
            delta_e_in    => delta_e_next_sig,

            fuzzy_delta   => fuzzy_next_sig,
            fokker_step   => ffp_step_sig,
            refined_duty  => refined_duty_sig
        );

    -- Uma unica unidade de atualizacao de particula, multiplexada por
    -- swarm_idx. A versao anterior replicava esta unidade N_PARTICLES vezes
    -- via generate, o que sozinho respondia por dezenas de milhares de
    -- elementos logicos. Como cada particula so depende de si mesma, do
    -- gbest e da janela de busca, percorrer o enxame em serie produz
    -- exatamente o mesmo resultado.
    sel_pos   <= particle_pos(swarm_idx);
    sel_vel   <= particle_vel(swarm_idx);
    sel_pbest <= pbest_pos(swarm_idx);

    trk_pos    <= pbest_pos(track_i);
    trk_power  <= pbest_power(track_i);
    trk_age    <= pbest_age(track_i);
    trk_is_cur <= '1' when track_i = track_cur else '0';

    u_particle_update: entity work.pso_particle_update_unit
        generic map (
            W_PSO_G   => W_PSO_G,
            C1_PSO_G  => C1_PSO_G,
            C2_PSO_G  => C2_PSO_G,
            VEL_MIN_G => VEL_MIN_G,
            VEL_MAX_G => VEL_MAX_G
        )
        port map (
            particle_pos_in  => sel_pos,
            particle_vel_in  => sel_vel,
            pbest_pos_in     => sel_pbest,
            gbest_pos_in     => gbest_pos,
            rho1_in          => sel_rho1,
            rho2_in          => sel_rho2,
            search_low_in    => search_low,
            search_high_in   => search_high,

            particle_pos_out => next_particle_pos,
            particle_vel_out => next_particle_vel
        );

    u_best_tracker: entity work.pso_best_tracker_unit
        generic map (
            MEMORY_HALF_LIFE_G => MEMORY_HALF_LIFE_G,
            MAX_PBEST_AGE_G    => MAX_PBEST_AGE_G
        )
        port map (
            is_current_in   => trk_is_cur,
            duty_in         => track_duty,
            power_now_in    => track_power,

            pbest_pos_in    => trk_pos,
            pbest_power_in  => trk_power,
            pbest_age_in    => trk_age,

            pbest_pos_out   => next_pbest_pos,
            pbest_power_out => next_pbest_power,
            pbest_age_out   => next_pbest_age
        );

    u_random_coefficients: entity work.pso_random_coeff_unit
        generic map (
            RHO_MIN_G => RHO_MIN_G,
            RHO_MAX_G => RHO_MAX_G
        )
        port map (
            lfsr_in   => lfsr,
            rho1_out  => sel_rho1,
            rho2_out  => sel_rho2,
            lfsr_out  => next_lfsr_sig
        );

    process(clk, reset)
        variable best_power_v : power_t;
        variable best_pos_v   : duty_t;
        variable sampled_p    : power_t;
    begin
        if reset = '1' then
            particle_pos <= INIT_POS;
            particle_vel <= INIT_VEL;
            pbest_pos    <= INIT_POS;
            pbest_power  <= (others => 0);
            pbest_age    <= (others => 0);

            gbest_pos    <= 50;
            gbest_power  <= 0;
            drop_counter <= 0;

            current_idx  <= 0;
            swarm_idx    <= 0;
            wait_counter <= 0;

            track_i        <= 0;
            track_cur      <= 0;
            track_power    <= 0;
            track_duty     <= 50;
            run_best_power <= 0;
            run_best_pos   <= 50;

            prev_power   <= 0;
            prev_voltage <= 0;
            prev_error   <= 0;

            error_reg    <= 0;
            delta_e_reg  <= 0;
            fuzzy_delta  <= 0;

            duty_reg      <= 50;
            pno_candidate <= 50;
            search_center <= 50;
            fokker_step   <= 1;
            duty_out      <= std_logic_vector(to_unsigned(50, 8));

            store_valid  <= '0';

            lfsr         <= x"ACE1";
            state        <= APPLY_PARTICLE;

        elsif rising_edge(clk) then
            store_valid <= '0';

            if enable = '1' then
                case state is

                    when APPLY_PARTICLE =>
                        duty_reg <= particle_pos(current_idx);

                        duty_out <= std_logic_vector(
                            to_unsigned(particle_pos(current_idx), 8)
                        );

                        wait_counter <= 0;
                        state <= WAIT_SETTLE;

                    when WAIT_SETTLE =>
                        if wait_counter < SETTLE_CYCLES then
                            wait_counter <= wait_counter + 1;
                        else
                            state <= SAMPLE_AND_UPDATE;
                        end if;

                    when SAMPLE_AND_UPDATE =>
                        error_reg <= error_next_sig;
                        delta_e_reg <= delta_e_next_sig;
                        fuzzy_delta <= fuzzy_next_sig;
                        fokker_step <= ffp_step_sig;
                        pno_candidate <= refined_duty_sig;

                        prev_power <= power_now_sig;
                        prev_voltage <= voltage_now_sig;
                        prev_error <= error_next_sig;

                        -- A varredura do enxame gasta N_PARTICLES ciclos, e
                        -- power_now_sig e combinacional sobre prev_power /
                        -- prev_voltage, que mudam nesta mesma borda. Por isso
                        -- a potencia e o duty da amostra sao registrados aqui,
                        -- ja saturados como o rastreador os consumia.
                        if power_now_sig < 0 then
                            sampled_p := 0;
                        else
                            sampled_p := power_now_sig;
                        end if;

                        track_power <= sampled_p;
                        track_duty  <= duty_reg;
                        track_cur   <= current_idx;
                        track_i     <= 0;

                        state <= TRACK_BEST;

                    -- Uma particula por ciclo. track_power, track_duty e
                    -- track_cur ficam estaveis durante toda a varredura, entao
                    -- cada particula enxerga o mesmo instantaneo que enxergava
                    -- na versao combinacional desenrolada.
                    when TRACK_BEST =>
                        pbest_pos(track_i)   <= next_pbest_pos;
                        pbest_power(track_i) <= next_pbest_power;
                        pbest_age(track_i)   <= next_pbest_age;

                        if track_i = 0 or next_pbest_power > run_best_power then
                            best_power_v := next_pbest_power;
                            best_pos_v   := next_pbest_pos;
                        else
                            best_power_v := run_best_power;
                            best_pos_v   := run_best_pos;
                        end if;

                        run_best_power <= best_power_v;
                        run_best_pos   <= best_pos_v;

                        if track_i = N_PARTICLES - 1 then
                            -- Deteccao de queda: depende do maximo final sobre
                            -- todo o enxame, entao roda uma unica vez, aqui.
                            if ENABLE_CHANGE_DETECTION_G /= 0 and
                               best_power_v > 0 and
                               (track_power * 100) < (best_power_v * DROP_THRESHOLD_PERCENT_G) then

                                if drop_counter >= DROP_PATIENCE_G - 1 then
                                    pbest_power  <= (others => track_power);
                                    pbest_pos    <= particle_pos;
                                    pbest_age    <= (others => 0);
                                    gbest_power  <= track_power;
                                    gbest_pos    <= track_duty;
                                    drop_counter <= 0;
                                else
                                    gbest_power  <= best_power_v;
                                    gbest_pos    <= best_pos_v;
                                    drop_counter <= min_int(drop_counter + 1, drop_t'high);
                                end if;
                            else
                                gbest_power  <= best_power_v;
                                gbest_pos    <= best_pos_v;
                                drop_counter <= 0;
                            end if;

                            store_valid <= '1';

                            if track_cur = N_PARTICLES - 1 then
                                current_idx <= 0;
                                state <= PREPARE_SWARM;
                            else
                                current_idx <= track_cur + 1;
                                state <= APPLY_PARTICLE;
                            end if;
                        else
                            track_i <= track_i + 1;
                        end if;

                    when PREPARE_SWARM =>
                        if SEARCH_CENTER_MODE_G = 0 then
                            search_center <= pno_candidate;
                        elsif SEARCH_CENTER_MODE_G = 1 then
                            search_center <= gbest_pos;
                        else
                            search_center <= clamp((gbest_pos + pno_candidate) / 2, DUTY_MIN, DUTY_MAX);
                        end if;

                        swarm_idx <= 0;
                        state <= UPDATE_SWARM;

                    -- Uma particula por ciclo. search_center, rho1_arr,
                    -- rho2_arr, gbest_pos e pbest_pos ficam estaveis durante
                    -- toda a varredura, entao cada particula enxerga o mesmo
                    -- instantaneo que enxergaria na versao paralela.
                    when UPDATE_SWARM =>
                        particle_pos(swarm_idx) <= next_particle_pos;
                        particle_vel(swarm_idx) <= next_particle_vel;

                        -- Dois passos por particula: depois de N_PARTICLES
                        -- ciclos o LFSR avancou os mesmos 20 passos que a
                        -- versao paralela avancava de uma vez em PREPARE_SWARM.
                        lfsr <= next_lfsr_sig;

                        if swarm_idx = N_PARTICLES - 1 then
                            swarm_idx <= 0;
                            state <= FINALIZE_SWARM;
                        else
                            swarm_idx <= swarm_idx + 1;
                        end if;

                    -- A particula 0 e sobrescrita pelo candidato P&O/fuzzy,
                    -- exatamente como acontecia no fim do estado paralelo.
                    when FINALIZE_SWARM =>
                        particle_pos(0) <= pno_candidate;
                        particle_vel(0) <= 0;
                        search_center <= pno_candidate;

                        state <= APPLY_PARTICLE;

                end case;
            end if;
        end if;
    end process;

    control_duty_out <= pno_candidate;
    gbest_duty_out  <= gbest_pos;
    gbest_power_out <= gbest_power;
    error_out       <= error_reg;
    delta_e_out     <= delta_e_reg;
    fuzzy_delta_out <= fuzzy_delta;

end Structural;
