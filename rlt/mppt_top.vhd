library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mppt_top is
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

        current_in       : in  signed(15 downto 0);
        voltage_in       : in  signed(15 downto 0);

        duty_out         : out std_logic_vector(7 downto 0);
        control_duty_out : out integer;
        store_valid      : out std_logic;

        gbest_duty_out   : out integer;
        gbest_power_out  : out integer;
        error_out        : out integer;
        delta_e_out      : out integer;
        fuzzy_delta_out  : out integer
    );
end mppt_top;

architecture Structural of mppt_top is
begin

    u_hybrid_controller: entity work.hybrid_pso_fuzzy_mppt
        generic map (
            SETTLE_CYCLES     => SETTLE_CYCLES,
            W_PSO_G           => W_PSO_G,
            C1_PSO_G          => C1_PSO_G,
            C2_PSO_G          => C2_PSO_G,
            RHO_MIN_G         => RHO_MIN_G,
            RHO_MAX_G         => RHO_MAX_G,
            VEL_MIN_G         => VEL_MIN_G,
            VEL_MAX_G         => VEL_MAX_G,
            DEADZONE_G        => DEADZONE_G,
            SEARCH_RADIUS_G   => SEARCH_RADIUS_G,
            FOKKER_STEP_MIN_G => FOKKER_STEP_MIN_G,
            FOKKER_STEP_MAX_G => FOKKER_STEP_MAX_G,
            FUZZY_STEP_G      => FUZZY_STEP_G,
            FUZZY_EDGE_G      => FUZZY_EDGE_G,
            POWER_SCALE_DEN_G => POWER_SCALE_DEN_G,
            ERROR_GAIN_G      => ERROR_GAIN_G,
            DELTA_V_MIN_G     => DELTA_V_MIN_G,
            DUTY_DIRECTION_G  => DUTY_DIRECTION_G,
            SEARCH_CENTER_MODE_G => SEARCH_CENTER_MODE_G,
            MEMORY_HALF_LIFE_G => MEMORY_HALF_LIFE_G,
            MAX_PBEST_AGE_G => MAX_PBEST_AGE_G,
            ENABLE_CHANGE_DETECTION_G => ENABLE_CHANGE_DETECTION_G,
            DROP_THRESHOLD_PERCENT_G => DROP_THRESHOLD_PERCENT_G,
            DROP_PATIENCE_G => DROP_PATIENCE_G
        )
        port map (
            clk              => clk,
            reset            => reset,
            enable           => enable,
            current_in       => current_in,
            voltage_in       => voltage_in,
            duty_out         => duty_out,
            control_duty_out => control_duty_out,
            store_valid      => store_valid,
            gbest_duty_out   => gbest_duty_out,
            gbest_power_out  => gbest_power_out,
            error_out        => error_out,
            delta_e_out      => delta_e_out,
            fuzzy_delta_out  => fuzzy_delta_out
        );

end Structural;
