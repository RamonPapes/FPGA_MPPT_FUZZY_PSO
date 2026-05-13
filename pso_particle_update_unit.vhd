library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg.ALL;

entity pso_particle_update_unit is
    generic (
        W_PSO_G   : integer := 50;
        C1_PSO_G  : integer := 50;
        C2_PSO_G  : integer := 40;
        VEL_MIN_G : integer := -20;
        VEL_MAX_G : integer := 20
    );
    port (
        particle_pos_in  : in  integer;
        particle_vel_in  : in  integer;
        pbest_pos_in     : in  integer;
        gbest_pos_in     : in  integer;
        rho1_in          : in  integer;
        rho2_in          : in  integer;
        search_low_in    : in  integer;
        search_high_in   : in  integer;

        particle_pos_out : out integer;
        particle_vel_out : out integer
    );
end pso_particle_update_unit;

architecture Behavioral of pso_particle_update_unit is
begin

    process(all)
        variable low_bound   : integer;
        variable high_bound  : integer;
        variable cognitive   : integer;
        variable social      : integer;
        variable v_new       : integer;
        variable p_new       : integer;
    begin
        if search_low_in <= search_high_in then
            low_bound := search_low_in;
            high_bound := search_high_in;
        else
            low_bound := search_high_in;
            high_bound := search_low_in;
        end if;

        cognitive := (C1_PSO_G * rho1_in * (pbest_pos_in - particle_pos_in)) / 10000;
        social := (C2_PSO_G * rho2_in * (gbest_pos_in - particle_pos_in)) / 10000;

        v_new := ((W_PSO_G * particle_vel_in) / 100) + cognitive + social;
        v_new := clamp(v_new, VEL_MIN_G, VEL_MAX_G);

        p_new := particle_pos_in + v_new;
        p_new := clamp(p_new, low_bound, high_bound);
        p_new := clamp(p_new, DUTY_MIN, DUTY_MAX);

        particle_vel_out <= v_new;
        particle_pos_out <= p_new;
    end process;

end Behavioral;