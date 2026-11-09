library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg_ref.ALL;

entity pso_best_tracker_unit_ref is
    generic (
        MEMORY_HALF_LIFE_G        : integer := 300;
        MAX_PBEST_AGE_G           : integer := 500;
        ENABLE_CHANGE_DETECTION_G : integer := 0;
        DROP_THRESHOLD_PERCENT_G  : integer := 70;
        DROP_PATIENCE_G           : integer := 30
    );
    port (
        current_idx_in   : in  integer range 0 to N_PARTICLES - 1;
        duty_in          : in  integer;
        power_now_in     : in  integer;
        particle_pos_in  : in  particle_array;
        pbest_pos_in     : in  particle_array;
        pbest_power_in   : in  particle_array;
        pbest_age_in     : in  particle_array;
        drop_counter_in  : in  integer;

        pbest_pos_out    : out particle_array;
        pbest_power_out  : out particle_array;
        pbest_age_out    : out particle_array;
        gbest_pos_out    : out integer;
        gbest_power_out  : out integer;
        drop_counter_out : out integer
    );
end pso_best_tracker_unit_ref;

architecture Combinational of pso_best_tracker_unit_ref is
begin

    process(all)
        variable lambda_num          : integer;
        variable power_for_best      : integer;
        variable aged_pbest          : integer;
        variable updated_power       : integer;
        variable updated_pos         : integer;
        variable updated_age         : integer;
        variable best_power_next     : integer;
        variable best_pos_next       : integer;
        variable pbest_pos_next      : particle_array;
        variable pbest_power_next    : particle_array;
        variable pbest_age_next      : particle_array;
        variable gbest_pos_next      : integer;
        variable gbest_power_next    : integer;
        variable drop_counter_next   : integer;
    begin
        if MEMORY_HALF_LIFE_G <= 0 then
            lambda_num := 10000;
        else
            lambda_num := 10000 - ((693 * 10000) / (MEMORY_HALF_LIFE_G * 1000));
        end if;

        lambda_num := clamp(lambda_num, 0, 10000);

        if power_now_in < 0 then
            power_for_best := 0;
        else
            power_for_best := power_now_in;
        end if;

        best_power_next := 0;
        best_pos_next := pbest_pos_in(0);

        for i in 0 to N_PARTICLES - 1 loop
            aged_pbest := (pbest_power_in(i) * lambda_num) / 10000;
            updated_power := aged_pbest;
            updated_pos := pbest_pos_in(i);
            updated_age := pbest_age_in(i) + 1;

            if i = current_idx_in then
                if power_for_best > aged_pbest or
                   pbest_age_in(i) >= MAX_PBEST_AGE_G then
                    updated_power := power_for_best;
                    updated_pos := duty_in;
                    updated_age := 0;
                end if;
            end if;

            pbest_power_next(i) := updated_power;
            pbest_pos_next(i) := updated_pos;
            pbest_age_next(i) := updated_age;

            if i = 0 or updated_power > best_power_next then
                best_power_next := updated_power;
                best_pos_next := updated_pos;
            end if;
        end loop;

        if ENABLE_CHANGE_DETECTION_G /= 0 then
            if best_power_next > 0 and
               (power_for_best * 100) <
               (best_power_next * DROP_THRESHOLD_PERCENT_G) then

                if drop_counter_in >= DROP_PATIENCE_G - 1 then
                    pbest_power_next := (others => power_for_best);
                    pbest_pos_next := particle_pos_in;
                    pbest_age_next := (others => 0);
                    gbest_power_next := power_for_best;
                    gbest_pos_next := duty_in;
                    drop_counter_next := 0;
                else
                    gbest_power_next := best_power_next;
                    gbest_pos_next := best_pos_next;
                    drop_counter_next := drop_counter_in + 1;
                end if;
            else
                gbest_power_next := best_power_next;
                gbest_pos_next := best_pos_next;
                drop_counter_next := 0;
            end if;
        else
            gbest_power_next := best_power_next;
            gbest_pos_next := best_pos_next;
            drop_counter_next := 0;
        end if;

        pbest_pos_out <= pbest_pos_next;
        pbest_power_out <= pbest_power_next;
        pbest_age_out <= pbest_age_next;
        gbest_pos_out <= gbest_pos_next;
        gbest_power_out <= gbest_power_next;
        drop_counter_out <= drop_counter_next;
    end process;

end Combinational;
