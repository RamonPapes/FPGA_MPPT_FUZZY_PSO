-- Testbench for hybrid_pso_fuzzy_mppt with export to resultados_hybrid.txt
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity tb_hybrid_pso_fuzzy_export is
    generic (
        DATASET_FILE      : string  := "dataset_scaled.txt";
        RESULT_FILE       : string  := "resultados_hybrid.txt";

        SETTLE_CYCLES_G   : integer := 1;

        W_PSO_G_TB           : integer := 50;
        C1_PSO_G_TB          : integer := 50;
        C2_PSO_G_TB          : integer := 40;
        RHO_MIN_G_TB         : integer := 53;
        RHO_MAX_G_TB         : integer := 56;
        VEL_MIN_G_TB         : integer := -20;
        VEL_MAX_G_TB         : integer := 20;
        DEADZONE_G_TB        : integer := 2;
        SEARCH_RADIUS_G_TB   : integer := 12;
        FOKKER_STEP_MIN_G_TB : integer := 1;
        FOKKER_STEP_MAX_G_TB : integer := 8;
        FUZZY_STEP_G_TB      : integer := 30;
        FUZZY_EDGE_G_TB      : integer := 90
    );
end tb_hybrid_pso_fuzzy_export;

architecture sim of tb_hybrid_pso_fuzzy_export is

    signal clk             : std_logic := '0';
    signal reset           : std_logic := '1';
    signal enable          : std_logic := '0';

    signal current_in      : signed(15 downto 0) := (others => '0');
    signal voltage_in      : signed(15 downto 0) := (others => '0');

    signal duty_out        : std_logic_vector(7 downto 0);
    signal store_valid     : std_logic;

    signal gbest_duty_out  : integer := 0;
    signal gbest_power_out : integer := 0;
    signal error_out       : integer := 0;
    signal delta_e_out     : integer := 0;
    signal fuzzy_delta_out : integer := 0;

    signal finished        : boolean := false;

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
            SETTLE_CYCLES     => SETTLE_CYCLES_G,

            W_PSO_G           => W_PSO_G_TB,
            C1_PSO_G          => C1_PSO_G_TB,
            C2_PSO_G          => C2_PSO_G_TB,
            RHO_MIN_G         => RHO_MIN_G_TB,
            RHO_MAX_G         => RHO_MAX_G_TB,
            VEL_MIN_G         => VEL_MIN_G_TB,
            VEL_MAX_G         => VEL_MAX_G_TB,
            DEADZONE_G        => DEADZONE_G_TB,
            SEARCH_RADIUS_G   => SEARCH_RADIUS_G_TB,
            FOKKER_STEP_MIN_G => FOKKER_STEP_MIN_G_TB,
            FOKKER_STEP_MAX_G => FOKKER_STEP_MAX_G_TB,
            FUZZY_STEP_G      => FUZZY_STEP_G_TB,
            FUZZY_EDGE_G      => FUZZY_EDGE_G_TB
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

    clk_process : process
    begin
        while not finished loop
            clk <= '0';
            wait for 10 ns;
            clk <= '1';
            wait for 10 ns;
        end loop;

        wait;
    end process;

    stim_proc : process
        file data_file   : text open read_mode is DATASET_FILE;
        file result_file : text open write_mode is RESULT_FILE;

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

        write(out_line, string'("sample voltage current duty gbest_duty gbest_power error delta_e fuzzy_delta "));
        write(out_line, string'("W_PSO C1_PSO C2_PSO RHO_MIN RHO_MAX VEL_MIN VEL_MAX DEADZONE SEARCH_RADIUS FOKKER_STEP_MIN FOKKER_STEP_MAX FUZZY_STEP FUZZY_EDGE"));
        writeline(result_file, out_line);

        while not endfile(data_file) loop

            readline(data_file, line_buf);
            read(line_buf, volt_val);
            read(line_buf, curr_val);

            wait until rising_edge(clk);

            voltage_in <= to_signed(clamp_16(volt_val), 16);
            current_in <= to_signed(clamp_16(curr_val), 16);

            wait until store_valid = '1' for 10 ms;

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
            write(out_line, string'(" "));

            write(out_line, W_PSO_G_TB);
            write(out_line, string'(" "));

            write(out_line, C1_PSO_G_TB);
            write(out_line, string'(" "));

            write(out_line, C2_PSO_G_TB);
            write(out_line, string'(" "));

            write(out_line, RHO_MIN_G_TB);
            write(out_line, string'(" "));

            write(out_line, RHO_MAX_G_TB);
            write(out_line, string'(" "));

            write(out_line, VEL_MIN_G_TB);
            write(out_line, string'(" "));

            write(out_line, VEL_MAX_G_TB);
            write(out_line, string'(" "));

            write(out_line, DEADZONE_G_TB);
            write(out_line, string'(" "));

            write(out_line, SEARCH_RADIUS_G_TB);
            write(out_line, string'(" "));

            write(out_line, FOKKER_STEP_MIN_G_TB);
            write(out_line, string'(" "));

            write(out_line, FOKKER_STEP_MAX_G_TB);
            write(out_line, string'(" "));

            write(out_line, FUZZY_STEP_G_TB);
            write(out_line, string'(" "));

            write(out_line, FUZZY_EDGE_G_TB);

            writeline(result_file, out_line);

            sample_idx := sample_idx + 1;

            wait until rising_edge(clk);
            wait until store_valid = '0' for 10 ms;

        end loop;

        wait for 100 ns;

        enable <= '0';
        finished <= true;

        assert false report "Simulation finished successfully." severity failure;
    end process;

end sim;
