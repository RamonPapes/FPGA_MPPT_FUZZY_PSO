library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg.ALL;

entity pso_swarm_update_unit is
    generic (
        W_PSO_G   : integer := 50;
        C1_PSO_G  : integer := 50;
        C2_PSO_G  : integer := 40;
        VEL_MIN_G : integer := -20;
        VEL_MAX_G : integer := 20
    );
    port (
        particle_pos_in  : in  particle_array;
        particle_vel_in  : in  particle_array;
        pbest_pos_in     : in  particle_array;
        gbest_pos_in     : in  integer;
        rho1_arr_in      : in  particle_array;
        rho2_arr_in      : in  particle_array;
        search_low_in    : in  integer;
        search_high_in   : in  integer;

        particle_pos_out : out particle_array;
        particle_vel_out : out particle_array
    );
end pso_swarm_update_unit;

architecture Structural of pso_swarm_update_unit is
begin

    gen_particle_update: for i in 0 to N_PARTICLES - 1 generate
        u_particle_update: entity work.pso_particle_update_unit
            generic map (
                W_PSO_G   => W_PSO_G,
                C1_PSO_G  => C1_PSO_G,
                C2_PSO_G  => C2_PSO_G,
                VEL_MIN_G => VEL_MIN_G,
                VEL_MAX_G => VEL_MAX_G
            )
            port map (
                particle_pos_in  => particle_pos_in(i),
                particle_vel_in  => particle_vel_in(i),
                pbest_pos_in     => pbest_pos_in(i),
                gbest_pos_in     => gbest_pos_in,
                rho1_in          => rho1_arr_in(i),
                rho2_in          => rho2_arr_in(i),
                search_low_in    => search_low_in,
                search_high_in   => search_high_in,

                particle_pos_out => particle_pos_out(i),
                particle_vel_out => particle_vel_out(i)
            );
    end generate;

end Structural;
