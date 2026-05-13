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
        POWER_SCALE_DEN_G : integer := 2048;
        DUTY_DIRECTION_G  : integer := -1;
        SEARCH_CENTER_MODE_G : integer := 1
    );
    port (
        clk              : in  std_logic;
        reset            : in  std_logic;
        enable           : in  std_logic;

        current_in       : in  signed(15 downto 0);  -- Q1.15
        voltage_in       : in  signed(15 downto 0);  -- Q12.4

        duty_out         : out std_logic_vector(7 downto 0);
        store_valid      : out std_logic;

        gbest_duty_out   : out integer;
        gbest_power_out  : out integer;
        error_out        : out integer;
        delta_e_out      : out integer;
        fuzzy_delta_out  : out integer
    );
end hybrid_pso_fuzzy_mppt;

architecture Structural of hybrid_pso_fuzzy_mppt is

    type top_state_type is (
        APPLY_PARTICLE,
        WAIT_SETTLE,
        SAMPLE_AND_UPDATE,
        PREPARE_SWARM,
        UPDATE_SWARM
    );

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

    signal next_particle_pos : particle_array := INIT_POS;
    signal next_particle_vel : particle_array := INIT_VEL;

    signal rho1_arr          : particle_array := (others => 53);
    signal rho2_arr          : particle_array := (others => 53);

    signal gbest_pos         : integer := 50;
    signal gbest_power       : integer := 0;

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

    signal state             : top_state_type := APPLY_PARTICLE;

begin

    search_low  <= clamp(search_center - SEARCH_RADIUS_G, DUTY_MIN, DUTY_MAX);
    search_high <= clamp(search_center + SEARCH_RADIUS_G, DUTY_MIN, DUTY_MAX);

    u_measurement: entity work.mppt_measurement_unit
        generic map (
            POWER_SCALE_DEN_G => POWER_SCALE_DEN_G
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
            duty_in       => duty_reg,
            delta_p       => delta_p_sig,
            delta_v       => delta_v_sig,
            error_in      => error_next_sig,
            delta_e_in    => delta_e_next_sig,

            fuzzy_delta   => fuzzy_next_sig,
            fokker_step   => ffp_step_sig,
            refined_duty  => refined_duty_sig
        );

    gen_particle_update: for i in 0 to N_PARTICLES - 1 generate
        u_particle_update: entity work.pso_particle_update_unit
            generic map (
                W_PSO_G   => W_PSO_G,
                C1_PSO_G  => C1_PSO_G,
                C2_PSO_G  => C2_PSO_G,
                VEL_MIN_G => VEL_MIN_G,
                VEL_MAX_G => VEL_MAX_G
            )
            port map (
                particle_pos_in  => particle_pos(i),
                particle_vel_in  => particle_vel(i),
                pbest_pos_in     => pbest_pos(i),
                gbest_pos_in     => gbest_pos,
                rho1_in          => rho1_arr(i),
                rho2_in          => rho2_arr(i),
                search_low_in    => search_low,
                search_high_in   => search_high,

                particle_pos_out => next_particle_pos(i),
                particle_vel_out => next_particle_vel(i)
            );
    end generate;

    process(clk, reset)
        variable lfsr_var : unsigned(15 downto 0);
    begin
        if reset = '1' then
            particle_pos <= INIT_POS;
            particle_vel <= INIT_VEL;
            pbest_pos    <= INIT_POS;
            pbest_power  <= (others => 0);

            rho1_arr     <= (others => 53);
            rho2_arr     <= (others => 53);

            gbest_pos    <= 50;
            gbest_power  <= 0;

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

                        if power_now_sig > pbest_power(current_idx) then
                            pbest_power(current_idx) <= power_now_sig;
                            pbest_pos(current_idx) <= duty_reg;
                        end if;

                        if power_now_sig > gbest_power then
                            gbest_power <= power_now_sig;
                            gbest_pos <= duty_reg;
                        end if;

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

                        lfsr_var := lfsr;

                        for i in 0 to N_PARTICLES - 1 loop
                            lfsr_var := next_lfsr(lfsr_var);
                            rho1_arr(i) <= rand_rho(lfsr_var, RHO_MIN_G, RHO_MAX_G);

                            lfsr_var := next_lfsr(lfsr_var);
                            rho2_arr(i) <= rand_rho(lfsr_var, RHO_MIN_G, RHO_MAX_G);
                        end loop;

                        lfsr <= lfsr_var;
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

    gbest_duty_out  <= gbest_pos;
    gbest_power_out <= gbest_power;
    error_out       <= error_reg;
    delta_e_out     <= delta_e_reg;
    fuzzy_delta_out <= fuzzy_delta;

end Structural;
