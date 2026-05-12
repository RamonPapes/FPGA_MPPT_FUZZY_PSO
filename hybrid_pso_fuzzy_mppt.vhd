library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg.ALL;

entity hybrid_pso_fuzzy_mppt is
    generic (
        SETTLE_CYCLES    : integer := 1000;
        W_PSO_G          : integer := 50;
        C1_PSO_G         : integer := 50;
        C2_PSO_G         : integer := 40;
        RHO_MIN_G        : integer := 53;
        RHO_MAX_G        : integer := 56;
        VEL_MIN_G        : integer := -20;
        VEL_MAX_G        : integer := 20;
        DEADZONE_G       : integer := 2;
        SEARCH_RADIUS_G  : integer := 12;
        FOKKER_STEP_MIN_G: integer := 1;
        FOKKER_STEP_MAX_G: integer := 8;
        FUZZY_STEP_G     : integer := 30;
        FUZZY_EDGE_G     : integer := 90
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

architecture Behavioral of hybrid_pso_fuzzy_mppt is

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

    signal particle_pos   : particle_array := INIT_POS;
    signal particle_vel   : particle_array := INIT_VEL;
    signal pbest_pos      : particle_array := INIT_POS;
    signal pbest_power    : particle_array := (others => 0);

    signal gbest_pos      : integer := 50;
    signal gbest_power    : integer := 0;

    signal current_idx    : integer range 0 to N_PARTICLES - 1 := 0;
    signal wait_counter   : integer := 0;

    signal prev_power     : integer := 0;
    signal prev_voltage   : integer := 0;
    signal prev_error     : integer := 0;

    signal error_reg      : integer range -100 to 100 := 0;
    signal delta_e_reg    : integer range -100 to 100 := 0;
    signal fuzzy_delta    : integer := 0;

    signal duty_reg       : integer range 0 to 100 := 50;
    signal pno_candidate  : integer range 0 to 100 := 50;
    signal search_center  : integer range 0 to 100 := 50;
    signal fokker_step    : integer := 1;

    signal lfsr           : unsigned(15 downto 0) := x"ACE1";

    signal state          : state_type := APPLY_PARTICLE;

begin

    process(clk, reset)
        variable power_now       : integer;
        variable voltage_now     : integer;
        variable delta_p         : integer;
        variable delta_v         : integer;
        variable error_raw       : integer;
        variable error_next      : integer;
        variable delta_e_next    : integer;
        variable fuzzy_next      : integer;

        variable rho1            : integer;
        variable rho2            : integer;
        variable v_new           : integer;
        variable p_new           : integer;
        variable cognitive       : integer;
        variable social          : integer;

        variable lfsr_var        : unsigned(15 downto 0);
        variable pno_dir         : integer;
        variable ffp_step        : integer;
        variable refined_duty    : integer;
        variable search_low      : integer;
        variable search_high     : integer;
    begin
        if reset = '1' then
            particle_pos <= INIT_POS;
            particle_vel <= INIT_VEL;
            pbest_pos    <= INIT_POS;
            pbest_power  <= (others => 0);

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

            duty_reg     <= 50;
            pno_candidate <= 50;
            search_center <= 50;
            fokker_step   <= 1;
            duty_out     <= std_logic_vector(to_unsigned(50, 8));

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
                        voltage_now := to_integer(voltage_in);
                        power_now := (to_integer(current_in) * to_integer(voltage_in)) / 65536;

                        delta_p := power_now - prev_power;
                        delta_v := voltage_now - prev_voltage;

                        if abs_int(delta_v) < 4 then
                            error_raw := 0;
                        else
                            error_raw := (delta_p * 100) / delta_v;
                        end if;

                        error_next := clamp(error_raw, -100, 100);
                        delta_e_next := clamp(error_next - prev_error, -100, 100);
                        fuzzy_next := fuzzy_compute(
                            error_next,
                            delta_e_next,
                            DEADZONE_G,
                            FUZZY_STEP_G,
                            FUZZY_EDGE_G
                        );

                        pno_dir := pno_direction(delta_p, delta_v);
                        if pno_dir = 0 then
                            pno_dir := sign_int(fuzzy_next);
                        end if;
                        if pno_dir = 0 then
                            pno_dir := 1;
                        end if;

                        ffp_step := fokker_planck_step(
                            error_next,
                            delta_e_next,
                            DEADZONE_G,
                            FOKKER_STEP_MIN_G,
                            FOKKER_STEP_MAX_G,
                            FUZZY_STEP_G,
                            FUZZY_EDGE_G
                        );

                        refined_duty := clamp(
                            duty_reg + (pno_dir * ffp_step),
                            DUTY_MIN,
                            DUTY_MAX
                        );

                        error_reg <= error_next;
                        delta_e_reg <= delta_e_next;
                        fuzzy_delta <= fuzzy_next;
                        fokker_step <= ffp_step;
                        pno_candidate <= refined_duty;

                        if power_now > pbest_power(current_idx) then
                            pbest_power(current_idx) <= power_now;
                            pbest_pos(current_idx) <= duty_reg;
                        end if;

                        if power_now > gbest_power then
                            gbest_power <= power_now;
                            gbest_pos <= duty_reg;
                        end if;

                        prev_power <= power_now;
                        prev_voltage <= voltage_now;
                        prev_error <= error_next;

                        store_valid <= '1';

                        if current_idx = N_PARTICLES - 1 then
                            current_idx <= 0;
                            state <= UPDATE_SWARM;
                        else
                            current_idx <= current_idx + 1;
                            state <= APPLY_PARTICLE;
                        end if;

                    when UPDATE_SWARM =>
                        lfsr_var := lfsr;

                        search_low := clamp(search_center - SEARCH_RADIUS_G, DUTY_MIN, DUTY_MAX);
                        search_high := clamp(search_center + SEARCH_RADIUS_G, DUTY_MIN, DUTY_MAX);

                        for i in 0 to N_PARTICLES - 1 loop
                            lfsr_var := next_lfsr(lfsr_var);
                            rho1 := rand_rho(lfsr_var, RHO_MIN_G, RHO_MAX_G);

                            lfsr_var := next_lfsr(lfsr_var);
                            rho2 := rand_rho(lfsr_var, RHO_MIN_G, RHO_MAX_G);

                            cognitive :=
                                (C1_PSO_G * rho1 * (pbest_pos(i) - particle_pos(i))) / 10000;

                            social :=
                                (C2_PSO_G * rho2 * (gbest_pos - particle_pos(i))) / 10000;

                            v_new :=
                                ((W_PSO_G * particle_vel(i)) / 100) +
                                cognitive +
                                social;

                            v_new := clamp(v_new, VEL_MIN_G, VEL_MAX_G);

                            p_new := particle_pos(i) + v_new;
                            p_new := clamp(p_new, search_low, search_high);
                            p_new := clamp(p_new, DUTY_MIN, DUTY_MAX);

                            particle_vel(i) <= v_new;
                            particle_pos(i) <= p_new;
                        end loop;

                        particle_pos(0) <= pno_candidate;
                        particle_vel(0) <= 0;
                        search_center <= pno_candidate;

                        lfsr <= lfsr_var;

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

end Behavioral;
