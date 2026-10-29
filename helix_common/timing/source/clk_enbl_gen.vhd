--*********************************************************************************
-- Indiana University Cyclotron Facility (IUCF)
--
-- Project: Belle-II
--
-- Author:  Brandon Kunkler
--
-- Date:    02/25/2014
--
--*********************************************************************************
-- Description:
-- Generate N clock enables and strobes operating at multiples of two. The enables
-- are aliged with the rising edge of the strobes. The rate decreases by a factor
-- of two as the vector index increases.
--*********************************************************************************
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.math_real.all;
    use ieee.numeric_std.all;


entity clk_enbl_gen is
generic(
    MINRT                       : positive       := 2;--minimum rate
    NENBL                       : positive       := 1);
port(
    clk                         : in  std_logic;
    reset                       : in  std_logic;
    enable                      : out std_logic_vector(1 to NENBL);
    strobe                      : out std_logic_vector(1 to NENBL));
end clk_enbl_gen;


architecture behave of clk_enbl_gen is

    constant LGMIN              : natural                       := INTEGER(CEIL(LOG2(REAL(MINRT))));
    constant CTRW               : natural                       := LGMIN+NENBL-1;
    constant CTRL               : natural                       := CTRW-1;
    constant CTRR               : natural                       := 0;
    constant CTRS               : natural                       := CTRL-NENBL+1;
    constant VECR               : natural                       := NENBL;

    signal enbl_ctr             : unsigned(CTRL downto 0);
    signal enable_vec_q0        : std_logic_vector(1 to VECR);
    signal enable_vec_q1        : std_logic_vector(1 to VECR);
    signal enable_vec_re        : std_logic_vector(1 to VECR);    

    signal strobe_vec_q2        : std_logic_vector(1 to VECR);    

begin

------------------------------------------------------------------------------------------------
-- Component instantiations
------------------------------------------------------------------------------------------------


------------------------------------------------------------------------------------------------
-- Concurrent statements.
------------------------------------------------------------------------------------------------

    enable <=  enable_vec_re;
    strobe <=  strobe_vec_q2;
    
------------------------------------------------------------------------------------------------
-- Synchronous and Asynchronous processes.
------------------------------------------------------------------------------------------------
    
    -------------------------------------------------------
    -- Free running counter for enable/strobe generation.
    -------------------------------------------------------
    counter_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                enbl_ctr <= (others => '1');
            else
                enbl_ctr <= enbl_ctr - 1;
            end if;
        end if;
    end process;
    
    -------------------------------------------------------
    -- Generate enables from rising egde of counter.
    -------------------------------------------------------    
    enable_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            enable_vec_q0 <= STD_LOGIC_VECTOR(enbl_ctr(CTRL downto CTRS));
            enable_vec_q1 <= enable_vec_q0;
            enable_vec_re <= enable_vec_q0 and (not enable_vec_q1);
        end if;
    end process;
    
    -------------------------------------------------------
    -- Generate strobes from delay counter bit - align them
    -- with the enables.
    -------------------------------------------------------    
   strobe_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            strobe_vec_q2 <= enable_vec_q0;
        end if;
    end process;    

end behave;