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
        control_duty_out : out integer;
        store_valid      : out std_logic;

        gbest_duty_out   : out integer;
        gbest_power_out  : out integer;
        error_out        : out integer;
        delta_e_out      : out integer;
        fuzzy_delta_out  : out integer
    );
end hybrid_pso_fuzzy_mppt;

architecture Structural of hybrid_pso_fuzzy_mppt is

    function init_particle_positions return particle_array is
        variable arr  : particle_array;
        variable seed : unsigned(15 downto 0) := x"ACE1";
    begin
        for i in 0 to N_PARTICLES - 1 loop
            seed := next_lfsr(seed);
            arr(i) := rand_0_100(seed);
        end loop;

        return arr;
    end function;

    function init_particle_velocities return particle_array is
        variable arr  : particle_array;
    begin
        for i in 0 to N_PARTICLES - 1 loop
            arr(i) := 0;
        end loop;

        return arr;
    end function;

    constant INIT_POS : particle_array := init_particle_positions;
    constant INIT_VEL : particle_array := init_particle_velocities;

    signal particle_pos      : particle_array := INIT_POS;
    signal particle_vel      : particle_array := INIT_VEL;
    signal pbest_pos         : particle_array := INIT_POS;
    signal pbest_power       : particle_array := (others => 0);
    signal pbest_age         : particle_array := (others => 0);

    signal next_particle_pos : particle_array := INIT_POS;
    signal next_particle_vel : particle_array := INIT_VEL;

    signal next_pbest_pos    : particle_array := INIT_POS;
    signal next_pbest_power  : particle_array := (others => 0);
    signal next_pbest_age    : particle_array := (others => 0);
    signal next_gbest_pos    : integer := 50;
    signal next_gbest_power  : integer := 0;
    signal next_drop_counter : integer := 0;

    signal rho1_arr          : particle_array := (others => 53);
    signal rho2_arr          : particle_array := (others => 53);
    signal next_rho1_arr     : particle_array := (others => 53);
    signal next_rho2_arr     : particle_array := (others => 53);

    signal gbest_pos         : integer := 50;
    signal gbest_power       : integer := 0;
    signal drop_counter      : integer := 0;

    signal current_idx       : integer range 0 to N_PARTICLES - 1 := 0;
    signal wait_counter      : integer := 0;

    signal prev_power        : integer := 0;
    signal prev_voltage      : integer := 0;
    signal prev_error        : integer := 0;

    signal power_now_sig     : integer := 0;
    signal voltage_now_sig   : integer := 0;
    signal delta_p_sig       : integer := 0;
    signal delta_v_sig       : integer := 0;
    signal error_next_sig    : integer := 0;
    signal delta_e_next_sig  : integer := 0;

    signal fuzzy_next_sig    : integer := 0;
    signal ffp_step_sig      : integer := 1;
    signal refined_duty_sig  : integer := 50;

    signal error_reg         : integer range -100 to 100 := 0;
    signal delta_e_reg       : integer range -100 to 100 := 0;
    signal fuzzy_delta       : integer := 0;

    signal duty_reg          : integer range 0 to 100 := 50;
    signal pno_candidate     : integer range 0 to 100 := 50;
    signal search_center     : integer range 0 to 100 := 50;
    signal fokker_step       : integer := 1;

    signal search_low        : integer := 38;
    signal search_high       : integer := 62;

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

    u_swarm_update: entity work.pso_swarm_update_unit
        generic map (
            W_PSO_G   => W_PSO_G,
            C1_PSO_G  => C1_PSO_G,
            C2_PSO_G  => C2_PSO_G,
            VEL_MIN_G => VEL_MIN_G,
            VEL_MAX_G => VEL_MAX_G
        )
        port map (
            particle_pos_in  => particle_pos,
            particle_vel_in  => particle_vel,
            pbest_pos_in     => pbest_pos,
            gbest_pos_in     => gbest_pos,
            rho1_arr_in      => rho1_arr,
            rho2_arr_in      => rho2_arr,
            search_low_in    => search_low,
            search_high_in   => search_high,

            particle_pos_out => next_particle_pos,
            particle_vel_out => next_particle_vel
        );

    u_best_tracker: entity work.pso_best_tracker_unit
        generic map (
            MEMORY_HALF_LIFE_G          => MEMORY_HALF_LIFE_G,
            MAX_PBEST_AGE_G             => MAX_PBEST_AGE_G,
            ENABLE_CHANGE_DETECTION_G   => ENABLE_CHANGE_DETECTION_G,
            DROP_THRESHOLD_PERCENT_G    => DROP_THRESHOLD_PERCENT_G,
            DROP_PATIENCE_G             => DROP_PATIENCE_G
        )
        port map (
            current_idx_in      => current_idx,
            duty_in             => duty_reg,
            power_now_in        => power_now_sig,
            particle_pos_in     => particle_pos,
            pbest_pos_in        => pbest_pos,
            pbest_power_in      => pbest_power,
            pbest_age_in        => pbest_age,
            drop_counter_in     => drop_counter,

            pbest_pos_out       => next_pbest_pos,
            pbest_power_out     => next_pbest_power,
            pbest_age_out       => next_pbest_age,
            gbest_pos_out       => next_gbest_pos,
            gbest_power_out     => next_gbest_power,
            drop_counter_out    => next_drop_counter
        );

    u_random_coefficients: entity work.pso_random_coeff_unit
        generic map (
            RHO_MIN_G => RHO_MIN_G,
            RHO_MAX_G => RHO_MAX_G
        )
        port map (
            lfsr_in      => lfsr,
            rho1_arr_out => next_rho1_arr,
            rho2_arr_out => next_rho2_arr,
            lfsr_out     => next_lfsr_sig
        );

    process(clk, reset)
    begin
        if reset = '1' then
            particle_pos <= INIT_POS;
            particle_vel <= INIT_VEL;
            pbest_pos    <= INIT_POS;
            pbest_power  <= (others => 0);
            pbest_age    <= (others => 0);

            rho1_arr     <= (others => 53);
            rho2_arr     <= (others => 53);

            gbest_pos    <= 50;
            gbest_power  <= 0;
            drop_counter <= 0;

            current_idx  <= 0;
            wait_counter <= 0;

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
                        duty_reg <= clamp(particle_pos(current_idx), DUTY_MIN, DUTY_MAX);

                        duty_out <= std_logic_vector(
                            to_unsigned(
                                clamp(particle_pos(current_idx), DUTY_MIN, DUTY_MAX),
                                8
                            )
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
                        error_reg <= clamp(error_next_sig, -100, 100);
                        delta_e_reg <= clamp(delta_e_next_sig, -100, 100);
                        fuzzy_delta <= fuzzy_next_sig;
                        fokker_step <= ffp_step_sig;
                        pno_candidate <= refined_duty_sig;

                        pbest_pos <= next_pbest_pos;
                        pbest_power <= next_pbest_power;
                        pbest_age <= next_pbest_age;
                        gbest_pos <= next_gbest_pos;
                        gbest_power <= next_gbest_power;
                        drop_counter <= next_drop_counter;

                        prev_power <= power_now_sig;
                        prev_voltage <= voltage_now_sig;
                        prev_error <= clamp(error_next_sig, -100, 100);

                        store_valid <= '1';

                        if current_idx = N_PARTICLES - 1 then
                            current_idx <= 0;
                            state <= PREPARE_SWARM;
                        else
                            current_idx <= current_idx + 1;
                            state <= APPLY_PARTICLE;
                        end if;

                    when PREPARE_SWARM =>
                        if SEARCH_CENTER_MODE_G = 0 then
                            search_center <= pno_candidate;
                        elsif SEARCH_CENTER_MODE_G = 1 then
                            search_center <= gbest_pos;
                        else
                            search_center <= clamp((gbest_pos + pno_candidate) / 2, DUTY_MIN, DUTY_MAX);
                        end if;

                        rho1_arr <= next_rho1_arr;
                        rho2_arr <= next_rho2_arr;
                        lfsr <= next_lfsr_sig;
                        state <= UPDATE_SWARM;

                    when UPDATE_SWARM =>
                        for i in 0 to N_PARTICLES - 1 loop
                            particle_vel(i) <= next_particle_vel(i);
                            particle_pos(i) <= next_particle_pos(i);
                        end loop;

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
