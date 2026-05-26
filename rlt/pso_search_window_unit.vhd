library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg.ALL;

entity pso_search_window_unit is
    generic (
        SEARCH_RADIUS_G : integer := 12
    );
    port (
        search_center_in : in  integer;
        search_low_out   : out integer;
        search_high_out  : out integer
    );
end pso_search_window_unit;

architecture Combinational of pso_search_window_unit is
begin

    process(all)
    begin
        search_low_out <= clamp(search_center_in - SEARCH_RADIUS_G, DUTY_MIN, DUTY_MAX);
        search_high_out <= clamp(search_center_in + SEARCH_RADIUS_G, DUTY_MIN, DUTY_MAX);
    end process;

end Combinational;
