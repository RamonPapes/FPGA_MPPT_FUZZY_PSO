-- =============================================================================
-- mppt_top_wrapper.vhd
-- Wrapper que converte as portas "integer" do mppt_top para std_logic_vector,
-- permitindo conexao com a interface SystemVerilog do UVM.
-- =============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity mppt_top_wrapper is
    generic (
        SETTLE_CYCLES : integer := 1
    );
    port (
        -- Entradas (mesmo tipo do mppt_top, mas signed vira std_logic_vector)
        clk              : in  std_logic;
        reset            : in  std_logic;
        enable           : in  std_logic;
        current_in       : in  std_logic_vector(15 downto 0);
        voltage_in       : in  std_logic_vector(15 downto 0);

        -- Saidas (tudo std_logic_vector para compatibilidade com SV)
        duty_out         : out std_logic_vector(7 downto 0);
        store_valid      : out std_logic;
        control_duty_out : out std_logic_vector(31 downto 0);
        gbest_duty_out   : out std_logic_vector(31 downto 0);
        gbest_power_out  : out std_logic_vector(31 downto 0);
        error_out        : out std_logic_vector(31 downto 0);
        delta_e_out      : out std_logic_vector(31 downto 0);
        fuzzy_delta_out  : out std_logic_vector(31 downto 0)
    );
end mppt_top_wrapper;

architecture Wrapper of mppt_top_wrapper is

    -- Sinais internos para receber as saidas integer do mppt_top
    signal control_duty_int  : integer;
    signal gbest_duty_int    : integer;
    signal gbest_power_int   : integer;
    signal error_int         : integer;
    signal delta_e_int       : integer;
    signal fuzzy_delta_int   : integer;

begin

    -- Instancia o DUT original, sem modificar nada nele
    u_dut: entity work.mppt_top
        generic map (
            SETTLE_CYCLES => SETTLE_CYCLES
        )
        port map (
            clk              => clk,
            reset            => reset,
            enable           => enable,
            -- Converte std_logic_vector -> signed na entrada
            current_in       => signed(current_in),
            voltage_in       => signed(voltage_in),
            -- Saidas diretas (tipos ja compativeis)
            duty_out         => duty_out,
            store_valid      => store_valid,
            -- Saidas integer -> vao para sinais internos
            control_duty_out => control_duty_int,
            gbest_duty_out   => gbest_duty_int,
            gbest_power_out  => gbest_power_int,
            error_out        => error_int,
            delta_e_out      => delta_e_int,
            fuzzy_delta_out  => fuzzy_delta_int
        );

    -- Converte integer -> std_logic_vector(31 downto 0) para as saidas
    control_duty_out <= std_logic_vector(to_signed(control_duty_int, 32));
    gbest_duty_out   <= std_logic_vector(to_signed(gbest_duty_int, 32));
    gbest_power_out  <= std_logic_vector(to_signed(gbest_power_int, 32));
    error_out        <= std_logic_vector(to_signed(error_int, 32));
    delta_e_out      <= std_logic_vector(to_signed(delta_e_int, 32));
    fuzzy_delta_out  <= std_logic_vector(to_signed(fuzzy_delta_int, 32));

end Wrapper;
