-- ----------------------------------------------------------------------
-- Medicao de latencia da FSM do hybrid_pso_fuzzy_mppt (via mppt_top).
--
-- Conta ciclos de clock entre pulsos de store_valid com o SETTLE_CYCLES do
-- hardware (1000). store_valid pulsa uma vez por particula amostrada (ultimo
-- ciclo de TRACK_BEST), entao:
--   - intervalo entre pulsos dentro de uma varredura  = SETTLE_CYCLES + 13
--     (APPLY 1 + WAIT_SETTLE SETTLE_CYCLES+1 + SAMPLE 1 + TRACK_BEST 10);
--   - iteracao completa (10 pulsos)                   = 10*SETTLE_CYCLES + 142
--     (+ PREPARE 1 + UPDATE_SWARM 10 + FINALIZE 1).
-- O testbench confere os dois valores e imprime o tempo com clk_core de
-- 320 ns (50 MHz / 16). Termina com "TB_LATENCY PASS" ou com failure.
--
-- Uso, a partir da raiz do projeto (biblioteca ja compilada com o RTL):
--   vcom -2008 verification/tb_latency.vhd
--   vsim -c tb_latency -do "run -all; quit -f"
-- ----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_latency is
    generic (
        SETTLE_CYCLES_G : integer := 1000;
        N_ITER_G        : integer := 3
    );
end tb_latency;

architecture sim of tb_latency is

    constant CLK_PERIOD : time := 320 ns;
    constant N_PART     : integer := 10;

    signal clk         : std_logic := '0';
    signal reset       : std_logic := '1';
    signal enable      : std_logic := '0';
    signal duty_out    : std_logic_vector(7 downto 0);
    signal store_valid : std_logic;
    signal done        : boolean := false;

    signal control_duty_out, gbest_duty_out, gbest_power_out : integer;
    signal error_out, delta_e_out, fuzzy_delta_out           : integer;

begin

    clk <= not clk after CLK_PERIOD / 2 when not done else '0';

    dut : entity work.mppt_top
        generic map (SETTLE_CYCLES => SETTLE_CYCLES_G)
        port map (
            clk              => clk,
            reset            => reset,
            enable           => enable,
            current_in       => to_signed(16000, 16),
            voltage_in       => to_signed(7680, 16),
            duty_out         => duty_out,
            control_duty_out => control_duty_out,
            store_valid      => store_valid,
            gbest_duty_out   => gbest_duty_out,
            gbest_power_out  => gbest_power_out,
            error_out        => error_out,
            delta_e_out      => delta_e_out,
            fuzzy_delta_out  => fuzzy_delta_out
        );

    monitor : process
        type cycle_array is array (0 to N_PART * N_ITER_G) of integer;
        variable pulses   : cycle_array;
        variable n_pulses : integer := 0;
        variable cycle    : integer := 0;
        variable gap      : integer;
        variable iter     : integer;
    begin
        wait for 3 * CLK_PERIOD;
        reset <= '0';
        wait until rising_edge(clk);
        enable <= '1';

        while n_pulses <= N_PART * N_ITER_G loop
            wait until rising_edge(clk);
            cycle := cycle + 1;
            if store_valid = '1' then
                pulses(n_pulses) := cycle;
                n_pulses := n_pulses + 1;
            end if;
        end loop;

        gap := pulses(1) - pulses(0);
        assert gap = SETTLE_CYCLES_G + 13
            report "intervalo entre particulas = " & integer'image(gap) &
                   ", esperado " & integer'image(SETTLE_CYCLES_G + 13)
            severity failure;

        for k in 0 to N_ITER_G - 1 loop
            iter := pulses((k + 1) * N_PART) - pulses(k * N_PART);
            assert iter = 10 * SETTLE_CYCLES_G + 142
                report "iteracao " & integer'image(k) & " = " & integer'image(iter) &
                       " ciclos, esperado " & integer'image(10 * SETTLE_CYCLES_G + 142)
                severity failure;
        end loop;

        report "Intervalo entre particulas: " & integer'image(gap) & " ciclos";
        report "Iteracao completa: " & integer'image(iter) & " ciclos = " &
               integer'image(iter * 320 / 1000) & " us com clk_core de 320 ns";
        report "TB_LATENCY PASS";
        done <= true;
        wait;
    end process;

end sim;
