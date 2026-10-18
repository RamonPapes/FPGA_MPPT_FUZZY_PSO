library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg.ALL;

-- ----------------------------------------------------------------------
-- Envelhece o pbest de UMA particula e decide se ele e substituido pela
-- amostra corrente.
--
-- A versao anterior era um laco combinacional sobre as dez particulas, o que
-- custava 13.400 ALUTs -- 58% do projeto inteiro. O desenrolamento produzia
-- dez multiplicadores de envelhecimento, vinte divisores de 30 bits e uma
-- cadeia de nove comparadores em serie para apurar o gbest.
--
-- Como cada particula depende apenas de si mesma, da potencia amostrada e do
-- indice corrente -- todos estaveis durante a varredura --, percorrer o
-- enxame em serie produz exatamente o mesmo resultado. O maximo corrente e
-- acumulado em registrador pelo hybrid_pso_fuzzy_mppt, no estado TRACK_BEST,
-- o que substitui a cadeia de comparadores por um unico comparador reusado.
--
-- A deteccao de queda de potencia depende do maximo final sobre todo o
-- enxame, entao ficou no hybrid_pso_fuzzy_mppt, aplicada uma unica vez no
-- ultimo ciclo da varredura.
-- ----------------------------------------------------------------------

entity pso_best_tracker_unit is
    generic (
        MEMORY_HALF_LIFE_G : integer := 300;
        MAX_PBEST_AGE_G    : integer := 500
    );
    port (
        is_current_in   : in  std_logic;   -- esta particula e a corrente?
        duty_in         : in  duty_t;
        power_now_in    : in  power_t;

        pbest_pos_in    : in  duty_t;
        pbest_power_in  : in  power_t;
        pbest_age_in    : in  age_t;

        pbest_pos_out   : out duty_t;
        pbest_power_out : out power_t;
        pbest_age_out   : out age_t
    );
end pso_best_tracker_unit;

architecture Combinational of pso_best_tracker_unit is

    -- O fator de decaimento e resolvido em tempo de elaboracao, entao a
    -- multiplicacao pbest_power * lambda_num tem um operando constante.
    -- pbest_power cabe em 16 bits e lambda_num em 14, logo 30 bits bastam.
    constant AGED_BITS : positive := 30;

    function decay_numerator return integer is
        variable lambda : integer;
    begin
        if MEMORY_HALF_LIFE_G <= 0 then
            lambda := 10000;
        else
            lambda := 10000 - ((693 * 10000) / (MEMORY_HALF_LIFE_G * 1000));
        end if;

        return clamp(lambda, 0, 10000);
    end function;

    constant LAMBDA_NUM : integer := decay_numerator;

begin

    -- Verificada na elaboracao. A idade de um pbest cresce de 1 por amostra e
    -- so e zerada quando a particula e a corrente E sua idade ja passou de
    -- MAX_PBEST_AGE_G, o que acontece a cada N_PARTICLES amostras. O pico e
    -- portanto MAX_PBEST_AGE_G + N_PARTICLES.
    assert MAX_PBEST_AGE_G + N_PARTICLES <= age_t'high
        report "MAX_PBEST_AGE_G alto demais para age_t. " &
               "Alargue age_t em hybrid_mppt_pkg.vhd."
        severity failure;

    process(all)
        variable power_for_best : power_t;
        variable aged_pbest     : power_t;
    begin
        if power_now_in < 0 then
            power_for_best := 0;
        else
            power_for_best := power_now_in;
        end if;

        aged_pbest := div_trunc(pbest_power_in * LAMBDA_NUM, 10000, AGED_BITS);

        if is_current_in = '1' and
           (power_for_best > aged_pbest or pbest_age_in >= MAX_PBEST_AGE_G) then
            pbest_power_out <= power_for_best;
            pbest_pos_out   <= duty_in;
            pbest_age_out   <= 0;
        else
            pbest_power_out <= aged_pbest;
            pbest_pos_out   <= pbest_pos_in;
            pbest_age_out   <= min_int(pbest_age_in + 1, age_t'high);
        end if;
    end process;

end Combinational;
