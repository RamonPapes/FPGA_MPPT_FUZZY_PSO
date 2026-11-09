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
        particle_pos_in  : in  duty_t;
        particle_vel_in  : in  vel_t;
        pbest_pos_in     : in  duty_t;
        gbest_pos_in     : in  duty_t;
        rho1_in          : in  coeff_t;
        rho2_in          : in  coeff_t;
        search_low_in    : in  duty_t;
        search_high_in   : in  duty_t;

        particle_pos_out : out duty_t;
        particle_vel_out : out vel_t
    );
end pso_particle_update_unit;

architecture Behavioral of pso_particle_update_unit is

    -- C1/C2 e rho vao ate 255 e a diferenca de posicoes ate +/-100, logo o
    -- produto dos tres cabe em 23 bits com sinal.
    constant ATTRACT_BITS : positive := 23;
    subtype attract_t is integer range -(2 ** ATTRACT_BITS) to (2 ** ATTRACT_BITS) - 1;

    -- W ate 255 vezes a velocidade em vel_t.
    constant INERTIA_BITS : positive := 18;
    subtype inertia_t is integer range -(2 ** INERTIA_BITS) to (2 ** INERTIA_BITS) - 1;

    -- Soma dos tres termos antes da saturacao em VEL_MIN_G..VEL_MAX_G.
    subtype vel_acc_t is integer range -8192 to 8191;

    -- Posicao antes da saturacao na janela de busca.
    subtype pos_acc_t is integer range -8192 to 8191;

begin

    process(all)
        variable low_bound   : duty_t;
        variable high_bound  : duty_t;
        variable cognitive_n : attract_t;
        variable social_n    : attract_t;
        variable inertia_n   : inertia_t;
        variable cognitive   : vel_acc_t;
        variable social      : vel_acc_t;
        variable inertia     : vel_acc_t;
        variable v_new       : vel_acc_t;
        variable v_sat       : vel_t;
        variable p_new       : pos_acc_t;
    begin
        if search_low_in <= search_high_in then
            low_bound := search_low_in;
            high_bound := search_high_in;
        else
            low_bound := search_high_in;
            high_bound := search_low_in;
        end if;

        cognitive_n := C1_PSO_G * rho1_in * (pbest_pos_in - particle_pos_in);
        social_n := C2_PSO_G * rho2_in * (gbest_pos_in - particle_pos_in);
        inertia_n := W_PSO_G * particle_vel_in;

        cognitive := div_trunc(cognitive_n, 10000, ATTRACT_BITS);
        social := div_trunc(social_n, 10000, ATTRACT_BITS);
        inertia := div_trunc(inertia_n, 100, INERTIA_BITS);

        v_new := inertia + cognitive + social;
        v_sat := clamp(v_new, VEL_MIN_G, VEL_MAX_G);

        p_new := particle_pos_in + v_sat;
        p_new := clamp(p_new, low_bound, high_bound);

        particle_vel_out <= v_sat;
        particle_pos_out <= clamp(p_new, DUTY_MIN, DUTY_MAX);
    end process;

end Behavioral;
