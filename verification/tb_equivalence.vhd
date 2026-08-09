-- ----------------------------------------------------------------------
-- Testbench de equivalencia.
--
-- Roda lado a lado o RTL refatorado (mppt_top) e o RTL original preservado
-- em verification/ref (mppt_top_ref), com os mesmos genericos e o mesmo
-- estimulo, e compara amostra a amostra todas as saidas.
--
-- Os dois DUTs NAO estao em lockstep de ciclo: a versao nova percorre o
-- enxame em serie e gasta alguns ciclos a mais por rodada de PSO. Por isso
-- cada DUT tem seu proprio processo de estimulo, sincronizado pelo respectivo
-- store_valid, exatamente como faz o testbench de exportacao. A comparacao e
-- feita no dominio de amostras, nao no de ciclos.
-- ----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

entity tb_equivalence is
    generic (
        N_SAMPLES : integer := 1200;
        SEED_G    : integer := 305419896;

        SETTLE_CYCLES_G   : integer := 1;

        W_PSO_G_TB           : integer := 70;
        C1_PSO_G_TB          : integer := 60;
        C2_PSO_G_TB          : integer := 60;
        RHO_MIN_G_TB         : integer := 55;
        RHO_MAX_G_TB         : integer := 65;
        VEL_MIN_G_TB         : integer := -20;
        VEL_MAX_G_TB         : integer := 20;
        DEADZONE_G_TB        : integer := 1;
        SEARCH_RADIUS_G_TB   : integer := 10;
        FOKKER_STEP_MIN_G_TB : integer := 1;
        FOKKER_STEP_MAX_G_TB : integer := 4;
        FUZZY_STEP_G_TB      : integer := 40;
        FUZZY_EDGE_G_TB      : integer := 100;
        POWER_SCALE_DEN_G_TB : integer := 65536;
        ERROR_GAIN_G_TB      : integer := 1;
        DELTA_V_MIN_G_TB     : integer := 16;
        DUTY_DIRECTION_G_TB  : integer := 1;
        SEARCH_CENTER_MODE_G_TB : integer := 2;
        MEMORY_HALF_LIFE_G_TB : integer := 300;
        MAX_PBEST_AGE_G_TB : integer := 500;
        ENABLE_CHANGE_DETECTION_G_TB : integer := 0;
        DROP_THRESHOLD_PERCENT_G_TB : integer := 70;
        DROP_PATIENCE_G_TB : integer := 30
    );
end tb_equivalence;

architecture sim of tb_equivalence is

    -- ------------------------------------------------------------------
    -- Estimulo
    -- ------------------------------------------------------------------

    type stim_rec is record
        volt : integer;
        curr : integer;
    end record;

    type stim_arr is array (0 to N_SAMPLES - 1) of stim_rec;

    function xorshift32(x : unsigned(31 downto 0)) return unsigned is
        variable y : unsigned(31 downto 0) := x;
    begin
        y := y xor shift_left(y, 13);
        y := y xor shift_right(y, 17);
        y := y xor shift_left(y, 5);

        return y;
    end function;

    -- Quatro regimes, para cobrir os caminhos que dados reais exercitam de
    -- forma desigual:
    --   1) aleatorio de faixa cheia, satura erro e delta e;
    --   2) rampa lenta, mantem o controlador dentro da deadzone;
    --   3) tensao quantizada grosseiramente, gera muitos delta_v = 0 e ativa
    --      o ramo DELTA_V_MIN;
    --   4) aleatorio de novo, para sair de qualquer estado preso.
    function make_stimulus return stim_arr is
        variable arr   : stim_arr;
        variable s     : unsigned(31 downto 0) := to_unsigned(SEED_G, 32);
        variable quart : integer := N_SAMPLES / 4;
        variable v     : integer;
        variable c     : integer;
    begin
        for i in 0 to N_SAMPLES - 1 loop
            s := xorshift32(s);

            if i < quart then
                v := to_integer(signed(s(15 downto 0)));
                c := to_integer(signed(s(31 downto 16)));

            elsif i < 2 * quart then
                v := 4000 + ((i - quart) * 7);
                c := 12000 + (to_integer(signed(s(23 downto 16))) / 4);

            elsif i < 3 * quart then
                v := 8192 * (to_integer(s(9 downto 8)));
                c := to_integer(signed(s(31 downto 16)));

            else
                v := to_integer(signed(s(15 downto 0)));
                c := to_integer(signed(s(31 downto 16)));
            end if;

            if v > 32767 then
                v := 32767;
            elsif v < -32768 then
                v := -32768;
            end if;

            if c > 32767 then
                c := 32767;
            elsif c < -32768 then
                c := -32768;
            end if;

            arr(i) := (volt => v, curr => c);
        end loop;

        return arr;
    end function;

    constant STIM : stim_arr := make_stimulus;

    -- ------------------------------------------------------------------
    -- Captura das saidas
    -- ------------------------------------------------------------------

    type obs_rec is record
        duty         : integer;
        control_duty : integer;
        gbest_duty   : integer;
        gbest_power  : integer;
        err          : integer;
        delta_e      : integer;
        fuzzy_delta  : integer;
    end record;

    type obs_arr is array (0 to N_SAMPLES - 1) of obs_rec;

    constant OBS_INIT : obs_rec := (others => 0);

    signal obs_new : obs_arr := (others => OBS_INIT);
    signal obs_ref : obs_arr := (others => OBS_INIT);

    signal done_new : boolean := false;
    signal done_ref : boolean := false;
    signal finished : boolean := false;

    -- ------------------------------------------------------------------
    -- Sinais dos dois DUTs
    -- ------------------------------------------------------------------

    signal clk    : std_logic := '0';
    signal reset  : std_logic := '1';
    signal enable : std_logic := '0';

    signal curr_new : signed(15 downto 0) := (others => '0');
    signal volt_new : signed(15 downto 0) := (others => '0');
    signal curr_ref : signed(15 downto 0) := (others => '0');
    signal volt_ref : signed(15 downto 0) := (others => '0');

    signal duty_new        : std_logic_vector(7 downto 0);
    signal control_duty_new : integer;
    signal sv_new          : std_logic;
    signal gbest_duty_new  : integer;
    signal gbest_power_new : integer;
    signal error_new       : integer;
    signal delta_e_new     : integer;
    signal fuzzy_new       : integer;

    signal duty_ref        : std_logic_vector(7 downto 0);
    signal control_duty_ref : integer;
    signal sv_ref          : std_logic;
    signal gbest_duty_ref  : integer;
    signal gbest_power_ref : integer;
    signal error_ref       : integer;
    signal delta_e_ref     : integer;
    signal fuzzy_ref       : integer;

begin

    -- ------------------------------------------------------------------
    -- DUT refatorado
    -- ------------------------------------------------------------------
    dut_new: entity work.mppt_top
        generic map (
            SETTLE_CYCLES     => SETTLE_CYCLES_G,
            W_PSO_G           => W_PSO_G_TB,
            C1_PSO_G          => C1_PSO_G_TB,
            C2_PSO_G          => C2_PSO_G_TB,
            RHO_MIN_G         => RHO_MIN_G_TB,
            RHO_MAX_G         => RHO_MAX_G_TB,
            VEL_MIN_G         => VEL_MIN_G_TB,
            VEL_MAX_G         => VEL_MAX_G_TB,
            DEADZONE_G        => DEADZONE_G_TB,
            SEARCH_RADIUS_G   => SEARCH_RADIUS_G_TB,
            FOKKER_STEP_MIN_G => FOKKER_STEP_MIN_G_TB,
            FOKKER_STEP_MAX_G => FOKKER_STEP_MAX_G_TB,
            FUZZY_STEP_G      => FUZZY_STEP_G_TB,
            FUZZY_EDGE_G      => FUZZY_EDGE_G_TB,
            POWER_SCALE_DEN_G => POWER_SCALE_DEN_G_TB,
            ERROR_GAIN_G      => ERROR_GAIN_G_TB,
            DELTA_V_MIN_G     => DELTA_V_MIN_G_TB,
            DUTY_DIRECTION_G  => DUTY_DIRECTION_G_TB,
            SEARCH_CENTER_MODE_G => SEARCH_CENTER_MODE_G_TB,
            MEMORY_HALF_LIFE_G => MEMORY_HALF_LIFE_G_TB,
            MAX_PBEST_AGE_G => MAX_PBEST_AGE_G_TB,
            ENABLE_CHANGE_DETECTION_G => ENABLE_CHANGE_DETECTION_G_TB,
            DROP_THRESHOLD_PERCENT_G => DROP_THRESHOLD_PERCENT_G_TB,
            DROP_PATIENCE_G => DROP_PATIENCE_G_TB
        )
        port map (
            clk => clk, reset => reset, enable => enable,
            current_in => curr_new, voltage_in => volt_new,
            duty_out => duty_new,
            control_duty_out => control_duty_new,
            store_valid => sv_new,
            gbest_duty_out => gbest_duty_new,
            gbest_power_out => gbest_power_new,
            error_out => error_new,
            delta_e_out => delta_e_new,
            fuzzy_delta_out => fuzzy_new
        );

    -- ------------------------------------------------------------------
    -- DUT de referencia (RTL original)
    -- ------------------------------------------------------------------
    dut_ref: entity work.mppt_top_ref
        generic map (
            SETTLE_CYCLES     => SETTLE_CYCLES_G,
            W_PSO_G           => W_PSO_G_TB,
            C1_PSO_G          => C1_PSO_G_TB,
            C2_PSO_G          => C2_PSO_G_TB,
            RHO_MIN_G         => RHO_MIN_G_TB,
            RHO_MAX_G         => RHO_MAX_G_TB,
            VEL_MIN_G         => VEL_MIN_G_TB,
            VEL_MAX_G         => VEL_MAX_G_TB,
            DEADZONE_G        => DEADZONE_G_TB,
            SEARCH_RADIUS_G   => SEARCH_RADIUS_G_TB,
            FOKKER_STEP_MIN_G => FOKKER_STEP_MIN_G_TB,
            FOKKER_STEP_MAX_G => FOKKER_STEP_MAX_G_TB,
            FUZZY_STEP_G      => FUZZY_STEP_G_TB,
            FUZZY_EDGE_G      => FUZZY_EDGE_G_TB,
            POWER_SCALE_DEN_G => POWER_SCALE_DEN_G_TB,
            ERROR_GAIN_G      => ERROR_GAIN_G_TB,
            DELTA_V_MIN_G     => DELTA_V_MIN_G_TB,
            DUTY_DIRECTION_G  => DUTY_DIRECTION_G_TB,
            SEARCH_CENTER_MODE_G => SEARCH_CENTER_MODE_G_TB,
            MEMORY_HALF_LIFE_G => MEMORY_HALF_LIFE_G_TB,
            MAX_PBEST_AGE_G => MAX_PBEST_AGE_G_TB,
            ENABLE_CHANGE_DETECTION_G => ENABLE_CHANGE_DETECTION_G_TB,
            DROP_THRESHOLD_PERCENT_G => DROP_THRESHOLD_PERCENT_G_TB,
            DROP_PATIENCE_G => DROP_PATIENCE_G_TB
        )
        port map (
            clk => clk, reset => reset, enable => enable,
            current_in => curr_ref, voltage_in => volt_ref,
            duty_out => duty_ref,
            control_duty_out => control_duty_ref,
            store_valid => sv_ref,
            gbest_duty_out => gbest_duty_ref,
            gbest_power_out => gbest_power_ref,
            error_out => error_ref,
            delta_e_out => delta_e_ref,
            fuzzy_delta_out => fuzzy_ref
        );

    clk_process : process
    begin
        while not finished loop
            clk <= '0';
            wait for 10 ns;
            clk <= '1';
            wait for 10 ns;
        end loop;

        wait;
    end process;

    reset_process : process
    begin
        reset <= '1';
        enable <= '0';
        wait for 40 ns;
        reset <= '0';
        enable <= '1';
        wait;
    end process;

    -- ------------------------------------------------------------------
    -- Estimulo do DUT novo
    -- ------------------------------------------------------------------
    drive_new : process
    begin
        wait until reset = '0';
        wait until rising_edge(clk);

        for i in 0 to N_SAMPLES - 1 loop
            wait until rising_edge(clk);

            volt_new <= to_signed(STIM(i).volt, 16);
            curr_new <= to_signed(STIM(i).curr, 16);

            wait until sv_new = '1' for 10 ms;
            assert sv_new = '1'
                report "DUT novo: timeout esperando store_valid na amostra " & integer'image(i)
                severity failure;

            wait for 1 ns;

            obs_new(i) <= (
                duty         => to_integer(unsigned(duty_new)),
                control_duty => control_duty_new,
                gbest_duty   => gbest_duty_new,
                gbest_power  => gbest_power_new,
                err          => error_new,
                delta_e      => delta_e_new,
                fuzzy_delta  => fuzzy_new
            );

            wait until rising_edge(clk);
            wait until sv_new = '0' for 10 ms;
        end loop;

        done_new <= true;
        wait;
    end process;

    -- ------------------------------------------------------------------
    -- Estimulo do DUT de referencia
    -- ------------------------------------------------------------------
    drive_ref : process
    begin
        wait until reset = '0';
        wait until rising_edge(clk);

        for i in 0 to N_SAMPLES - 1 loop
            wait until rising_edge(clk);

            volt_ref <= to_signed(STIM(i).volt, 16);
            curr_ref <= to_signed(STIM(i).curr, 16);

            wait until sv_ref = '1' for 10 ms;
            assert sv_ref = '1'
                report "DUT ref: timeout esperando store_valid na amostra " & integer'image(i)
                severity failure;

            wait for 1 ns;

            obs_ref(i) <= (
                duty         => to_integer(unsigned(duty_ref)),
                control_duty => control_duty_ref,
                gbest_duty   => gbest_duty_ref,
                gbest_power  => gbest_power_ref,
                err          => error_ref,
                delta_e      => delta_e_ref,
                fuzzy_delta  => fuzzy_ref
            );

            wait until rising_edge(clk);
            wait until sv_ref = '0' for 10 ms;
        end loop;

        done_ref <= true;
        wait;
    end process;

    -- ------------------------------------------------------------------
    -- Comparacao
    -- ------------------------------------------------------------------
    check_process : process
        variable mismatches : integer := 0;
        variable shown      : integer := 0;
        variable a          : obs_rec;
        variable b          : obs_rec;
        variable l          : line;

        procedure diff_field(
            name  : in string;
            idx   : in integer;
            va    : in integer;
            vb    : in integer;
            count : inout integer;
            shows : inout integer
        ) is
            variable ll : line;
        begin
            if va /= vb then
                count := count + 1;

                if shows < 20 then
                    shows := shows + 1;
                    write(ll, string'("  DIVERGENCIA amostra "));
                    write(ll, idx);
                    write(ll, string'(" campo "));
                    write(ll, name);
                    write(ll, string'(": novo="));
                    write(ll, va);
                    write(ll, string'(" ref="));
                    write(ll, vb);
                    writeline(output, ll);
                end if;
            end if;
        end procedure;

    begin
        wait until done_new and done_ref;
        wait for 1 ns;

        for i in 0 to N_SAMPLES - 1 loop
            a := obs_new(i);
            b := obs_ref(i);

            diff_field("duty", i, a.duty, b.duty, mismatches, shown);
            diff_field("control_duty", i, a.control_duty, b.control_duty, mismatches, shown);
            diff_field("gbest_duty", i, a.gbest_duty, b.gbest_duty, mismatches, shown);
            diff_field("gbest_power", i, a.gbest_power, b.gbest_power, mismatches, shown);
            diff_field("error", i, a.err, b.err, mismatches, shown);
            diff_field("delta_e", i, a.delta_e, b.delta_e, mismatches, shown);
            diff_field("fuzzy_delta", i, a.fuzzy_delta, b.fuzzy_delta, mismatches, shown);
        end loop;

        write(l, string'("=== Equivalencia: "));
        write(l, N_SAMPLES);
        write(l, string'(" amostras, "));
        write(l, mismatches);
        write(l, string'(" divergencias de campo."));
        writeline(output, l);

        assert mismatches = 0
            report "FALHA: o RTL refatorado divergiu do original."
            severity failure;

        report "OK: o RTL refatorado e equivalente ao original." severity note;

        finished <= true;
        wait;
    end process;

end sim;
