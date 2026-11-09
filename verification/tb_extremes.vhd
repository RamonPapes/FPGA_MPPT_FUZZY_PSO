-- ----------------------------------------------------------------------
-- Teste dirigido dos extremos de signed(15 downto 0) na unidade de medicao.
--
-- Cobre os cantos do produto I x V que estouravam raw_power_t antes da
-- correcao: com o limite (2**30) - 1, I = V = -32768 abortava a simulacao
-- com "vsim-3421: Value 1073741824 is out of range". Cada caso compara
-- power_now com trunc(I * V / 65536), a mesma referencia do criterio V5.
--
-- Uso, a partir da raiz do projeto:
--   vlib work_ext
--   vcom -2008 -work work_ext rlt/hybrid_mppt_pkg.vhd rlt/mppt_measurement_unit.vhd verification/tb_extremes.vhd
--   vsim -c -lib work_ext tb_extremes -do "run -all; quit -f"
-- Termina com "TB_EXTREMES PASS" ou com failure.
-- ----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg.ALL;

entity tb_extremes is
end tb_extremes;

architecture sim of tb_extremes is

    signal current_s : signed(15 downto 0) := (others => '0');
    signal voltage_s : signed(15 downto 0) := (others => '0');

    signal power_now   : power_t;
    signal voltage_now : volt_t;
    signal delta_p     : delta_t;
    signal delta_v     : delta_t;
    signal error_next  : err_t;
    signal delta_e     : err_t;

    type pair_t is record
        i : integer;
        v : integer;
    end record;

    type pair_array is array (natural range <>) of pair_t;

    constant CASES : pair_array := (
        (     0,      0),
        ( 32767,  32767),
        ( 32767, -32768),
        (-32768,  32767),
        (-32768, -32768),
        (-32768,      1),
        (     1, -32768),
        (    -1,     -1)
    );

begin

    dut : entity work.mppt_measurement_unit
        generic map (
            POWER_SCALE_DEN_G => 65536,
            ERROR_GAIN_G      => 1,
            DELTA_V_MIN_G     => 16
        )
        port map (
            current_in   => current_s,
            voltage_in   => voltage_s,
            prev_power   => 0,
            prev_voltage => 0,
            prev_error   => 0,
            power_now    => power_now,
            voltage_now  => voltage_now,
            delta_p      => delta_p,
            delta_v      => delta_v,
            error_next   => error_next,
            delta_e_next => delta_e
        );

    stimulus : process
        variable expected : integer;
    begin
        for k in CASES'range loop
            current_s <= to_signed(CASES(k).i, 16);
            voltage_s <= to_signed(CASES(k).v, 16);
            wait for 10 ns;

            -- |I * V| <= 2**30 cabe no integer de 32 bits do testbench; a
            -- divisao VHDL trunca para zero, como trunc() em V5.
            expected := (CASES(k).i * CASES(k).v) / 65536;

            assert power_now = expected
                report "I=" & integer'image(CASES(k).i) &
                       " V=" & integer'image(CASES(k).v) &
                       " power_now=" & integer'image(power_now) &
                       " esperado=" & integer'image(expected)
                severity failure;

            report "OK I=" & integer'image(CASES(k).i) &
                   " V=" & integer'image(CASES(k).v) &
                   " power_now=" & integer'image(power_now);
        end loop;

        report "TB_EXTREMES PASS";
        wait;
    end process;

end sim;
