-- Testbench for hybrid_pso_fuzzy_mppt with export to resultados_hybrid.txt
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity tb_hybrid_pso_fuzzy_export is
end tb_hybrid_pso_fuzzy_export;

architecture sim of tb_hybrid_pso_fuzzy_export is

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

    function clamp_16(x : integer) return integer is
    begin
        if x < -32768 then
            return -32768;
        elsif x > 32767 then
            return 32767;
        else
            return x;
        end if;
    end function;

begin

    uut: entity work.hybrid_pso_fuzzy_mppt
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
        while true loop
            clk <= '0';
            wait for 10 ns;
            clk <= '1';
            wait for 10 ns;
        end loop;
    end process;

    -- Stimulus and export process
    stim_proc : process
        file data_file   : text open read_mode is "dataset_scaled.txt";
        file result_file : text open write_mode is "resultados_hybrid.txt";

        variable line_buf : line;
        variable out_line : line;

        variable volt_val   : integer;
        variable curr_val   : integer;
        variable sample_idx : integer := 0;
    begin

        voltage_in <= to_signed(0, 16);
        current_in <= to_signed(0, 16);

        wait for 40 ns;

        reset <= '0';
        enable <= '1';

        wait until rising_edge(clk);

        write(out_line, string'("sample voltage current duty gbest_duty gbest_power error delta_e fuzzy_delta"));
        writeline(result_file, out_line);

        while not endfile(data_file) loop

            readline(data_file, line_buf);

            if line_buf'length > 0 then
                read(line_buf, volt_val);
                read(line_buf, curr_val);

                voltage_in <= to_signed(clamp_16(volt_val), 16);
                current_in <= to_signed(clamp_16(curr_val), 16);

                wait until store_valid = '1' for 1 ms;

                if store_valid /= '1' then
                    assert false report "Timeout waiting for store_valid." severity failure;
                end if;

                wait for 1 ns;

                write(out_line, sample_idx);
                write(out_line, string'(" "));

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

                sample_idx := sample_idx + 1;

                wait until store_valid = '0';
            end if;

        end loop;

        wait for 100 ns;

        enable <= '0';

        assert false report "Simulation finished successfully." severity failure;
    end process;

end sim;