library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg_ref.ALL;

entity pso_random_coeff_unit_ref is
    generic (
        RHO_MIN_G : integer := 53;
        RHO_MAX_G : integer := 56
    );
    port (
        lfsr_in      : in  unsigned(15 downto 0);
        rho1_arr_out : out particle_array;
        rho2_arr_out : out particle_array;
        lfsr_out     : out unsigned(15 downto 0)
    );
end pso_random_coeff_unit_ref;

architecture Combinational of pso_random_coeff_unit_ref is
begin

    process(all)
        variable lfsr_var : unsigned(15 downto 0);
        variable rho1_var : particle_array;
        variable rho2_var : particle_array;
    begin
        lfsr_var := lfsr_in;

        for i in 0 to N_PARTICLES - 1 loop
            lfsr_var := next_lfsr(lfsr_var);
            rho1_var(i) := rand_rho(lfsr_var, RHO_MIN_G, RHO_MAX_G);

            lfsr_var := next_lfsr(lfsr_var);
            rho2_var(i) := rand_rho(lfsr_var, RHO_MIN_G, RHO_MAX_G);
        end loop;

        rho1_arr_out <= rho1_var;
        rho2_arr_out <= rho2_var;
        lfsr_out <= lfsr_var;
    end process;

end Combinational;
