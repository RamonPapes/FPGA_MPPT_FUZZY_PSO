library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg.ALL;

entity mppt_fuzzy_ffp_unit is
    generic (
        DEADZONE_G        : integer := 2;
        FOKKER_STEP_MIN_G : integer := 1;
        FOKKER_STEP_MAX_G : integer := 8;
        FUZZY_STEP_G      : integer := 30;
        FUZZY_EDGE_G      : integer := 90;
        DUTY_DIRECTION_G  : integer := -1
    );
    port (
        duty_in       : in  duty_t;
        delta_p       : in  delta_t;
        delta_v       : in  delta_t;
        error_in      : in  err_t;
        delta_e_in    : in  err_t;

        fuzzy_delta   : out rule_t;
        fokker_step   : out step_t;
        refined_duty  : out duty_t
    );
end mppt_fuzzy_ffp_unit;

architecture Behavioral of mppt_fuzzy_ffp_unit is

    -- Os pontos de quebra sao resolvidos na elaboracao, com o mesmo clamp que
    -- fuzzy_compute aplicava em tempo de execucao.
    constant STEP_V : integer := clamp(FUZZY_STEP_G, 1, 49);
    constant EDGE_V : integer := clamp(FUZZY_EDGE_G, (2 * STEP_V) + 1, 100);

    -- Tabela de pertinencia, calculada na elaboracao. Substitui as catorze
    -- avaliacoes em hardware das funcoes triangle/trapezoidal_*, cada uma com
    -- seu proprio divisor. Como mu_e depende apenas de error_in e mu_de apenas
    -- de delta_e_in, e ambos sao um unico valor de 8 bits, os mesmos valores
    -- saem de duas consultas a esta constante.
    constant MF_TABLE : mf_table_t := build_mf_table(STEP_V, EDGE_V);

begin

    process(all)
        variable e_c          : err_t;
        variable de_c         : err_t;
        variable mu_e         : fuzzy_array;
        variable mu_de        : fuzzy_array;
        variable fuzzy_next   : rule_t;
        variable step_next    : step_t;
        variable pno_dir      : integer range -1 to 1;
        variable refined_next : duty_t;
    begin
        e_c  := clamp(error_in, -100, 100);
        de_c := clamp(delta_e_in, -100, 100);

        -- O motor fuzzy e avaliado uma unica vez. Antes, fokker_planck_step
        -- chamava fuzzy_compute de novo com os mesmos argumentos, o que fazia
        -- o Quartus instanciar dois motores fuzzy completos em paralelo.
        if abs_int(e_c) < DEADZONE_G and abs_int(de_c) < DEADZONE_G then
            fuzzy_next := 0;
        else
            mu_e  := MF_TABLE(e_c);
            mu_de := MF_TABLE(de_c);

            fuzzy_next := fuzzy_defuzz(mu_e, mu_de);
        end if;

        step_next := fokker_planck_step(
            fuzzy_next,
            FOKKER_STEP_MIN_G,
            FOKKER_STEP_MAX_G
        );

        pno_dir := pno_direction(delta_p, delta_v);
        if pno_dir = 0 then
            pno_dir := sign_int(fuzzy_next);
        end if;

        if pno_dir = 0 then
            refined_next := duty_in;
        else
            refined_next := clamp(duty_in + (DUTY_DIRECTION_G * pno_dir * step_next), DUTY_MIN, DUTY_MAX);
        end if;

        fuzzy_delta <= fuzzy_next;
        fokker_step <= step_next;
        refined_duty <= refined_next;
    end process;

end Behavioral;
