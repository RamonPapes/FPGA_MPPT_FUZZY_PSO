library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg.ALL;

entity mppt_measurement_unit is
    generic (
        POWER_SCALE_DEN_G : integer := 65536;
        ERROR_GAIN_G      : integer := 1;
        DELTA_V_MIN_G     : integer := 16
    );
    port (
        current_in    : in  signed(15 downto 0);
        voltage_in    : in  signed(15 downto 0);
        prev_power    : in  power_t;
        prev_voltage  : in  volt_t;
        prev_error    : in  err_t;

        power_now     : out power_t;
        voltage_now   : out volt_t;
        delta_p       : out delta_t;
        delta_v       : out delta_t;
        error_next    : out err_t;
        delta_e_next  : out err_t
    );
end mppt_measurement_unit;

architecture Behavioral of mppt_measurement_unit is

    -- Produto bruto tensao x corrente, antes do reescalonamento. Dois
    -- operandos de 16 bits com sinal cabem em 31 bits.
    subtype raw_power_t is integer range -(2 ** 30) to (2 ** 30) - 1;

    -- Numerador do quociente dP/dV depois do ganho. Cobre ERROR_GAIN_G ate
    -- 255 com delta_p no pior caso.
    subtype error_num_t is integer range -(2 ** 24) to (2 ** 24) - 1;

begin

    -- Verificada na elaboracao. error_num_t foi dimensionado para delta_p no
    -- pior caso (+/-65535) vezes o ganho; acima de 255 o produto estoura.
    assert ERROR_GAIN_G <= 255
        report "ERROR_GAIN_G acima de 255 estoura error_num_t. " &
               "Alargue o subtipo error_num_t em mppt_measurement_unit.vhd."
        severity failure;

    process(all)
        variable voltage_now_v  : volt_t;
        variable raw_power_v    : raw_power_t;
        variable power_now_v    : power_t;
        variable delta_p_v      : delta_t;
        variable delta_v_v      : delta_t;
        variable error_gain_v   : integer;
        variable delta_v_min_v  : integer;
        variable error_num_v    : error_num_t;
        variable error_raw_v    : error_num_t;
        variable error_next_v   : err_t;
        variable delta_e_next_v : err_t;
    begin
        voltage_now_v := to_integer(voltage_in);

        raw_power_v := to_integer(current_in) * voltage_now_v;

        if POWER_SCALE_DEN_G <= 0 then
            power_now_v := raw_power_v / 1;
        else
            power_now_v := raw_power_v / POWER_SCALE_DEN_G;
        end if;

        delta_p_v := power_now_v - prev_power;
        delta_v_v := voltage_now_v - prev_voltage;

        if ERROR_GAIN_G <= 0 then
            error_gain_v := 1;
        else
            error_gain_v := ERROR_GAIN_G;
        end if;

        if DELTA_V_MIN_G <= 0 then
            delta_v_min_v := 1;
        else
            delta_v_min_v := DELTA_V_MIN_G;
        end if;

        -- Com dados historicos quantizados, delta_v=0 e comum. Nesses casos
        -- dP/dV fica indefinido, entao nao se fabrica uma inclinacao artificial.
        if abs_int(delta_v_v) < delta_v_min_v then
            error_raw_v := 0;
        else
            error_num_v := delta_p_v * error_gain_v;
            error_raw_v := error_num_v / delta_v_v;
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
