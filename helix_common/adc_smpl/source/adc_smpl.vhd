--*********************************************************************************
-- Indiana University Cyclotron Facility (IUCF)
--
-- Project: HELIX
--
-- Author:  Brandon Kunkler
--
-- Date:    07/11/2018
--
--*********************************************************************************
-- This notification is to inform you that the schematics/source-code provided by
-- Indiana University are controlled under the US Export Control Regulations.  The
-- schematics/source code are classified as ECCN 3E991.  Under these --controls this
-- information cannot be shared with individuals from or shipped to Cuba, Iran,
-- North Korea, Syria, or Sudan.  If there is a need to share this information with
-- any other individuals please contact export@iu.edu prior to sharing the information
-- so it can be determined if a US export control license is required.
--
--*********************************************************************************
-- Description:
-- Generate clock enable and strobes operating at any rate for sampling ADCs. The
-- enables are aliged with the rising edge of the strobes.
--*********************************************************************************
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.math_real.all;
    use ieee.numeric_std.all;


entity adc_smpl is
generic(
    MAXVAL                      : positive       := 2;--max counter value sets rate
    NENBL                       : positive       := 1);-- number of outputs
port(
    clk                         : in  std_logic;
    reset                       : in  std_logic;
    enable                      : out std_logic_vector(1 to NENBL);
    strobe                      : out std_logic_vector(1 to NENBL));
end adc_smpl;


architecture behave of adc_smpl is

    constant CTRI               : natural                       := MAXVAL-1;
    constant CTRW               : natural                       := INTEGER(CEIL(LOG2(REAL(CTRI))));
    constant CTRL               : natural                       := CTRW-1;

    signal enbl_ctr             : unsigned(CTRL downto 0);
    signal enable_vec_q0        : std_logic;
    signal enable_vec_q1        : std_logic_vector(1 to NENBL);
    signal enable_vec_re        : std_logic_vector(1 to NENBL);    

    signal strobe_vec_q2        : std_logic_vector(1 to NENBL);    

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
                enbl_ctr <= (others => '0');
            else
                if enbl_ctr < CTRI then
                    enbl_ctr <= enbl_ctr + 1;
                else
                    enbl_ctr <= (others => '0');
                end if;
            end if;
        end if;
    end process;
    
    -------------------------------------------------------
    -- Generate enables from rising egde of counter.
    -------------------------------------------------------    
    enable_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            enable_vec_q0 <= enbl_ctr(CTRL);
            enable_vec_q1 <= (others => enable_vec_q0);
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
            strobe_vec_q2 <= (others => enable_vec_q0);
        end if;
    end process;    

end behave;