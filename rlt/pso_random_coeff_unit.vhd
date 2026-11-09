library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hybrid_mppt_pkg.ALL;

-- ----------------------------------------------------------------------
-- Gera UM par de coeficientes pseudoaleatorios por invocacao, avancando o
-- LFSR de dois passos.
--
-- A versao anterior gerava os vinte coeficientes de uma vez, com um laco
-- combinacional que desenrolava vinte estagios de next_lfsr encadeados e
-- vinte operacoes "mod (rho_max - rho_min + 1)". Como a faixa padrao tem 11
-- valores, cada uma dessas viravam um lpm_divide completo: 20 instancias,
-- cerca de 1.360 ALUTs, mais os 160 flip-flops dos arrays rho1_arr/rho2_arr.
--
-- O enxame ja e percorrido em serie, uma particula por ciclo, entao o par de
-- coeficientes pode ser produzido sob demanda. O LFSR e consumido exatamente
-- na mesma ordem -- rho1(0), rho2(0), rho1(1), rho2(1), ... -- e depois de
-- N_PARTICLES ciclos o registrador avancou os mesmos vinte passos, chegando
-- ao mesmo estado final. Cada particula enxerga o mesmo par que enxergava na
-- versao paralela.
-- ----------------------------------------------------------------------

entity pso_random_coeff_unit is
    generic (
        RHO_MIN_G : integer := 53;
        RHO_MAX_G : integer := 56
    );
    port (
        lfsr_in   : in  unsigned(15 downto 0);

        rho1_out  : out coeff_t;
        rho2_out  : out coeff_t;
        lfsr_out  : out unsigned(15 downto 0)
    );
end pso_random_coeff_unit;

architecture Combinational of pso_random_coeff_unit is
begin

    process(all)
        variable lfsr_a : unsigned(15 downto 0);
        variable lfsr_b : unsigned(15 downto 0);
    begin
        lfsr_a := next_lfsr(lfsr_in);
        lfsr_b := next_lfsr(lfsr_a);

        rho1_out <= rand_rho(lfsr_a, RHO_MIN_G, RHO_MAX_G);
        rho2_out <= rand_rho(lfsr_b, RHO_MIN_G, RHO_MAX_G);
        lfsr_out <= lfsr_b;
    end process;

end Combinational;
