library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg.ALL;

entity mppt_measurement_unit is
    generic (
        POWER_SCALE_DEN_G : integer := 2048
    );
    port (
        current_in    : in  signed(15 downto 0);
        voltage_in    : in  signed(15 downto 0);
        prev_power    : in  integer;
        prev_voltage  : in  integer;
        prev_error    : in  integer;

        power_now     : out integer;
        voltage_now   : out integer;
        delta_p       : out integer;
        delta_v       : out integer;
        error_next    : out integer;
        delta_e_next  : out integer
    );
end mppt_measurement_unit;

architecture Behavioral of mppt_measurement_unit is
begin

    process(all)
        variable voltage_now_v  : integer;
        variable power_now_v    : integer;
        variable delta_p_v      : integer;
        variable delta_v_v      : integer;
        variable error_raw_v    : integer;
        variable error_next_v   : integer;
        variable delta_e_next_v : integer;
    begin
        voltage_now_v := to_integer(voltage_in);
        
        if POWER_SCALE_DEN_G <= 0 then
            power_now_v := (to_integer(current_in) * voltage_now_v) / 1;
        else
            power_now_v := (to_integer(current_in) * voltage_now_v) / POWER_SCALE_DEN_G;
        end if;
        
        delta_p_v := power_now_v - prev_power;
        delta_v_v := voltage_now_v - prev_voltage;

        if abs_int(delta_v_v) < 4 then
            error_raw_v := 0;
        else
            error_raw_v := (delta_p_v * 100) / delta_v_v;
        end if;

        error_next_v := clamp(error_raw_v, -100, 100);
        delta_e_next_v := clamp(error_next_v - prev_error, -100, 100);

        power_now <= power_now_v;
        voltage_now <= voltage_now_v;
        delta_p <= delta_p_v;
        delta_v <= delta_v_v;
        error_next <= error_next_v;
        delta_e_next <= delta_e_next_v;
    end process;

end Behavioral;