-- Testbench for hybrid_pso_fuzzy_mppt with export to resultados_hybrid.txt
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity tb_hybrid_pso_fuzzy_export is
end tb_hybrid_pso_fuzzy_export;

architecture sim of tb_hybrid_pso_fuzzy_export is

    component hybrid_pso_fuzzy_mppt
        generic (
            SETTLE_CYCLES : integer := 1000
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
    end component;

    signal clk             : std_logic := '0';
    signal reset           : std_logic := '1';
    signal enable          : std_logic := '0';

    signal current_in      : signed(15 downto 0) := (others => '0');
    signal voltage_in      : signed(15 downto 0) := (others => '0');

    signal duty_out        : std_logic_vector(7 downto 0);
    signal store_valid     : std_logic;

    signal gbest_duty_out  : integer;
    signal gbest_power_out : integer;
    signal error_out       : integer;
    signal delta_e_out     : integer;
    signal fuzzy_delta_out : integer;

begin

    -- Instantiate UUT
    uut: hybrid_pso_fuzzy_mppt
        generic map (
            SETTLE_CYCLES => 1
        )
        port map (
            clk             => clk,
            reset           => reset,
            enable          => enable,

            current_in      => current_in,
            voltage_in      => voltage_in,

            duty_out        => duty_out,
            store_valid     => store_valid,

            gbest_duty_out  => gbest_duty_out,
            gbest_power_out => gbest_power_out,
            error_out       => error_out,
            delta_e_out     => delta_e_out,
            fuzzy_delta_out => fuzzy_delta_out
        );

    -- Clock generation: 50 MHz equivalent, period = 20 ns
    clk_process : process
    begin
        clk <= '0';
        wait for 10 ns;

        clk <= '1';
        wait for 10 ns;
    end process;

    -- Stimulus and export process
    stim_proc : process
		file data_file : text open read_mode is "C:/Users/Ferna/Documents/mppt_fuzzy_pso/dataset_scaled.txt";
        file result_file  : text open write_mode is "C:/Users/Ferna/Documents/mppt_fuzzy_pso/resultados_hybrid.txt";

        variable line_buf : line;
        variable out_line : line;

        variable volt_val : integer;
        variable curr_val : integer;
    begin

        wait for 40 ns;

        reset <= '0';
        enable <= '1';

        wait for 20 ns;

        -- Header
        write(out_line, string'("voltage current duty gbest_duty gbest_power error delta_e fuzzy_delta"));
        writeline(result_file, out_line);

        while not endfile(data_file) loop

            readline(data_file, line_buf);
            read(line_buf, volt_val);
            read(line_buf, curr_val);

            voltage_in <= to_signed(volt_val, 16);
            current_in <= to_signed(curr_val, 16);

            -- Wait until the controller finishes one valid sample/update
            wait until rising_edge(clk) and store_valid = '1';

            write(out_line, volt_val);
            write(out_line, string'(" "));

            write(out_line, curr_val);
            write(out_line, string'(" "));

            write(out_line, to_integer(unsigned(duty_out)));
            write(out_line, string'(" "));

            write(out_line, gbest_duty_out);
            write(out_line, string'(" "));

            write(out_line, gbest_power_out);
            write(out_line, string'(" "));

            write(out_line, error_out);
            write(out_line, string'(" "));

            write(out_line, delta_e_out);
            write(out_line, string'(" "));

            write(out_line, fuzzy_delta_out);

            writeline(result_file, out_line);

            wait for 20 ns;

        end loop;

        wait for 100 ns;

        enable <= '0';

			assert false report "Simulation finished successfully." severity failure;
    end process;

end sim;