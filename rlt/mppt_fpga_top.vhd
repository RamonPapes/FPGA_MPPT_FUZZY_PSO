library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg.ALL;

-- ----------------------------------------------------------------------
-- Top level de SINTESE.
--
-- O mppt_top expoe control_duty_out, gbest_duty_out, gbest_power_out,
-- error_out, delta_e_out e fuzzy_delta_out como "integer". Em simulacao isso
-- e conveniente, mas na sintese cada uma dessas portas vira um barramento de
-- 32 bits: 192 pinos so de depuracao, para valores que cabem em 7 ou 8 bits.
-- Somados aos demais, davam 236 pinos contra os 224 do 5CEBA4 (Error 179000),
-- e ainda produziam os avisos "stuck at GND" nos bits altos.
--
-- Este top expoe apenas o que precisa sair do chip: 44 pinos. O mppt_top
-- original continua no projeto, sem alteracao, para o testbench.
-- ----------------------------------------------------------------------

entity mppt_fpga_top is
    generic (
        SETTLE_CYCLES     : integer := 1000;
        W_PSO_G           : integer := 70;
        C1_PSO_G          : integer := 60;
        C2_PSO_G          : integer := 60;
        RHO_MIN_G         : integer := 55;
        RHO_MAX_G         : integer := 65;
        VEL_MIN_G         : integer := -20;
        VEL_MAX_G         : integer := 20;
        DEADZONE_G        : integer := 1;
        SEARCH_RADIUS_G   : integer := 10;
        FOKKER_STEP_MIN_G : integer := 1;
        FOKKER_STEP_MAX_G : integer := 4;
        FUZZY_STEP_G      : integer := 40;
        FUZZY_EDGE_G      : integer := 100;
        POWER_SCALE_DEN_G : integer := 65536;
        ERROR_GAIN_G      : integer := 1;
        DELTA_V_MIN_G     : integer := 16;
        DUTY_DIRECTION_G  : integer := 1;
        SEARCH_CENTER_MODE_G : integer := 2;
        MEMORY_HALF_LIFE_G : integer := 300;
        MAX_PBEST_AGE_G : integer := 500;
        ENABLE_CHANGE_DETECTION_G : integer := 0;
        DROP_THRESHOLD_PERCENT_G : integer := 70;
        DROP_PATIENCE_G : integer := 30
    );
    port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        enable      : in  std_logic;

        current_in  : in  std_logic_vector(15 downto 0);  -- Q1.15 normalizado
        voltage_in  : in  std_logic_vector(15 downto 0);  -- Q12.4 por padrao

        duty_out    : out std_logic_vector(7 downto 0);
        store_valid : out std_logic
    );
end mppt_fpga_top;

architecture Structural of mppt_fpga_top is

    -- Amarradas internamente para que a sintese as elimine em vez de
    -- promove-las a pinos.
    signal control_duty_unused : duty_t;
    signal gbest_duty_unused   : duty_t;
    signal gbest_power_unused  : power_t;
    signal error_unused        : err_t;
    signal delta_e_unused      : err_t;
    signal fuzzy_delta_unused  : rule_t;

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

            current_in       => signed(current_in),
            voltage_in       => signed(voltage_in),

            duty_out         => duty_out,
            control_duty_out => control_duty_unused,
            store_valid      => store_valid,

            gbest_duty_out   => gbest_duty_unused,
            gbest_power_out  => gbest_power_unused,
            error_out        => error_unused,
            delta_e_out      => delta_e_unused,
            fuzzy_delta_out  => fuzzy_delta_unused
        );

end Structural;
