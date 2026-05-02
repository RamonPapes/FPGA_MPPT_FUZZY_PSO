library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package hybrid_mppt_pkg is

    constant N_PARTICLES : integer := 5;

    constant W_PSO  : integer := 50;   -- 0.50 scaled by 100
    constant C1_PSO : integer := 120;  -- 1.20 scaled by 100
    constant C2_PSO : integer := 120;  -- 1.20 scaled by 100

    constant VEL_MIN : integer := -20;
    constant VEL_MAX : integer :=  20;

    constant DUTY_MIN : integer := 0;
    constant DUTY_MAX : integer := 100;

    constant DEADZONE   : integer := 2;
    constant FUZZY_GAIN : integer := 10;

    type particle_array is array (0 to N_PARTICLES - 1) of integer;
    type fuzzy_array is array (0 to 6) of integer;
    type rule_table is array (0 to 6, 0 to 6) of integer;

    type state_type is (
        APPLY_PARTICLE,
        WAIT_SETTLE,
        SAMPLE_AND_UPDATE,
        UPDATE_SWARM
    );

    constant FUZZY_RULES : rule_table := (
        ( -100, -80, -60, -40, -20, -10,   0),
        ( -80,  -60, -40, -20, -10,   0,  10),
        ( -60,  -40, -20, -10,   0,  10,  20),
        ( -40,  -20, -10,   0,  10,  20,  40),
        ( -20,  -10,   0,  10,  20,  40,  60),
        ( -10,    0,  10,  20,  40,  60,  80),
        (   0,   10,  20,  40,  60,  80, 100)
    );

    function clamp(x, low, high : integer) return integer;
    function min_int(a, b : integer) return integer;

    function triangle(x, a, b, c : integer) return integer;

    function trapezoidal_shoulder_neg(
        x, plateau_end, slope_start, slope_end : integer
    ) return integer;

    function trapezoidal_shoulder_pos(
        x, slope_start, slope_end, plateau_start : integer
    ) return integer;

    function next_lfsr(x : unsigned(15 downto 0)) return unsigned;
    function rand_0_100(x : unsigned(15 downto 0)) return integer;

    function fuzzy_compute(e_in, de_in : integer) return integer;

end package hybrid_mppt_pkg;


package body hybrid_mppt_pkg is

    function clamp(x, low, high : integer) return integer is
    begin
        if x < low then
            return low;
        elsif x > high then
            return high;
        else
            return x;
        end if;
    end function;

    function min_int(a, b : integer) return integer is
    begin
        if a < b then
            return a;
        else
            return b;
        end if;
    end function;

    function triangle(x, a, b, c : integer) return integer is
    begin
        if x <= a or x >= c then
            return 0;
        elsif x = b then
            return 100;
        elsif x < b then
            return ((x - a) * 100) / (b - a);
        else
            return ((c - x) * 100) / (c - b);
        end if;
    end function;

    function trapezoidal_shoulder_neg(
        x, plateau_end, slope_start, slope_end : integer
    ) return integer is
    begin
        if x <= plateau_end then
            return 100;
        elsif x >= slope_end then
            return 0;
        elsif x > slope_start then
            return ((slope_end - x) * 100) / (slope_end - slope_start);
        else
            return 100;
        end if;
    end function;

    function trapezoidal_shoulder_pos(
        x, slope_start, slope_end, plateau_start : integer
    ) return integer is
    begin
        if x >= plateau_start then
            return 100;
        elsif x <= slope_start then
            return 0;
        elsif x < slope_end then
            return ((x - slope_start) * 100) / (slope_end - slope_start);
        else
            return 100;
        end if;
    end function;

    function next_lfsr(x : unsigned(15 downto 0)) return unsigned is
        variable y  : unsigned(15 downto 0);
        variable fb : std_logic;
    begin
        fb := x(15) xor x(13) xor x(12) xor x(10);
        y := x(14 downto 0) & fb;
        return y;
    end function;

    function rand_0_100(x : unsigned(15 downto 0)) return integer is
    begin
        return to_integer(x(7 downto 0)) mod 101;
    end function;

    function fuzzy_compute(e_in, de_in : integer) return integer is
        variable mu_e  : fuzzy_array;
        variable mu_de : fuzzy_array;

        variable numerator   : integer := 0;
        variable denominator : integer := 0;

        variable min_mu   : integer;
        variable rule_val : integer;
        variable e        : integer;
        variable de       : integer;
    begin
        e  := clamp(e_in,  -100, 100);
        de := clamp(de_in, -100, 100);

        if abs(e) < DEADZONE and abs(de) < DEADZONE then
            return 0;
        end if;

        mu_e(0) := trapezoidal_shoulder_neg(e, -100, -90, -60);
        mu_e(1) := triangle(e, -90, -60, -30);
        mu_e(2) := triangle(e, -60, -30, 0);
        mu_e(3) := triangle(e, -30, 0, 30);
        mu_e(4) := triangle(e, 0, 30, 60);
        mu_e(5) := triangle(e, 30, 60, 90);
        mu_e(6) := trapezoidal_shoulder_pos(e, 60, 90, 100);

        mu_de(0) := trapezoidal_shoulder_neg(de, -100, -90, -60);
        mu_de(1) := triangle(de, -90, -60, -30);
        mu_de(2) := triangle(de, -60, -30, 0);
        mu_de(3) := triangle(de, -30, 0, 30);
        mu_de(4) := triangle(de, 0, 30, 60);
        mu_de(5) := triangle(de, 30, 60, 90);
        mu_de(6) := trapezoidal_shoulder_pos(de, 60, 90, 100);

        for i in 0 to 6 loop
            for j in 0 to 6 loop
                min_mu := min_int(mu_e(i), mu_de(j));
                rule_val := FUZZY_RULES(i, j);

                numerator := numerator + min_mu * rule_val;
                denominator := denominator + min_mu;
            end loop;
        end loop;

        if denominator /= 0 then
            return numerator / denominator;
        else
            return 0;
        end if;
    end function;

end package body hybrid_mppt_pkg;