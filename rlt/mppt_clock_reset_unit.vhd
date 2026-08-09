library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ----------------------------------------------------------------------
-- Geracao do clock do core e condicionamento do reset.
--
-- Existe por duas razoes de analise temporal:
--
-- 1) O caminho critico do controlador limita o core a cerca de 5,6 MHz no
--    pior canto (Slow 1100mV 0C). O oscilador do DE0-CV e de 50 MHz, entao o
--    core roda num clock dividido. Um divisor em fabric foi preferido a um
--    PLL por ser portavel entre familias e por permitir um
--    create_generated_clock exato, sem depender de IP gerada.
--
-- 2) O reset externo e assincrono. Aplicado direto no pino de clear dos
--    registradores do core, ele torna a analise de recovery/removal
--    impossivel e obriga a mascarar tudo com false_path. Aqui ele passa por
--    um sincronizador de duas etapas: assercao assincrona, liberacao
--    sincrona. Assim o reset interno vira um sinal temporizado normal e o
--    Timing Analyzer consegue analisar recovery/removal de verdade.
--
-- CLK_DIV_G deve ser par. O valor precisa bater com a variavel CLK_DIV no
-- arquivo mptt_fuzzy_pso.sdc.
-- ----------------------------------------------------------------------

entity mppt_clock_reset_unit is
    generic (
        CLK_DIV_G : positive := 16
    );
    port (
        clk_in     : in  std_logic;   -- oscilador da placa (50 MHz)
        reset_in   : in  std_logic;   -- assincrono, ativo alto

        clk_core   : out std_logic;
        reset_core : out std_logic    -- sincrono na borda de clk_core
    );
end mppt_clock_reset_unit;

architecture rtl of mppt_clock_reset_unit is

    constant HALF : positive := CLK_DIV_G / 2;

    signal div_count    : integer range 0 to HALF - 1 := 0;
    signal clk_core_reg : std_logic := '0';
    signal reset_sync   : std_logic_vector(1 downto 0) := (others => '1');

begin

    assert (CLK_DIV_G mod 2) = 0
        report "CLK_DIV_G deve ser par para gerar um clock com 50% de duty cycle."
        severity failure;

    -- Divisor no dominio do oscilador.
    divider : process(clk_in, reset_in)
    begin
        if reset_in = '1' then
            div_count <= 0;
            clk_core_reg <= '0';
        elsif rising_edge(clk_in) then
            if div_count = HALF - 1 then
                div_count <= 0;
                clk_core_reg <= not clk_core_reg;
            else
                div_count <= div_count + 1;
            end if;
        end if;
    end process;

    clk_core <= clk_core_reg;

    -- Sincronizador de reset no dominio do core.
    reset_synchronizer : process(clk_core_reg, reset_in)
    begin
        if reset_in = '1' then
            reset_sync <= (others => '1');
        elsif rising_edge(clk_core_reg) then
            reset_sync <= reset_sync(0) & '0';
        end if;
    end process;

    reset_core <= reset_sync(1);

end rtl;
