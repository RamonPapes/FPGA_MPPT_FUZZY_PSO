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
        FUZZY_EDGE_G      : integer := 90
    );
    port (
        duty_in       : in  integer;
        delta_p       : in  integer;
        delta_v       : in  integer;
        error_in      : in  integer;
        delta_e_in    : in  integer;

        fuzzy_delta   : out integer;
        fokker_step   : out integer;
        refined_duty  : out integer
    );
end mppt_fuzzy_ffp_unit;

architecture Behavioral of mppt_fuzzy_ffp_unit is
begin

    process(all)
        variable fuzzy_next   : integer;
        variable step_next    : integer;
        variable pno_dir      : integer;
        variable refined_next : integer;
    begin
        fuzzy_next := fuzzy_compute(
            error_in,
            delta_e_in,
            DEADZONE_G,
            FUZZY_STEP_G,
            FUZZY_EDGE_G
        );

        step_next := fokker_planck_step(
            error_in,
            delta_e_in,
            DEADZONE_G,
            FOKKER_STEP_MIN_G,
            FOKKER_STEP_MAX_G,
            FUZZY_STEP_G,
            FUZZY_EDGE_G
        );

        pno_dir := pno_direction(delta_p, delta_v);
        if pno_dir = 0 then
            pno_dir := sign_int(fuzzy_next);
        end if;
        if pno_dir = 0 then
            pno_dir := 1;
        end if;

        refined_next := clamp(duty_in + (pno_dir * step_next), DUTY_MIN, DUTY_MAX);

        fuzzy_delta <= fuzzy_next;
        fokker_step <= step_next;
        refined_duty <= refined_next;
    end process;

end Behavioral;