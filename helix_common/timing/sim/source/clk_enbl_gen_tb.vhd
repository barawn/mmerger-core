--*********************************************************************************
-- Indiana University
-- Center for Exploration of Energy and Matter (CEEM)
--
-- Project: HELIX
--
-- Author:  Brandon Kunkler
--
-- Date:    04/20/2017
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
-- Test bench clock enable generator.
--
--*********************************************************************************

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;

entity clk_enbl_tb is
end clk_enbl_tb;

architecture behave of clk_enbl_tb is

    constant CKPER                     : time                           := 1 ns;
    constant CKHPER                    : time                           := CKPER/2;
    
    constant MINRT                     : positive                       := 64;--minimum rate
    constant NENBL                     : positive                       := 1;

    signal clk                         : std_logic                      :='0';
    signal reset                       : std_logic;
    signal enable                      : std_logic_vector(1 to NENBL);
    signal strobe                      : std_logic_vector(1 to NENBL);

begin

---------------------------------------------------------------------------------------------------------
-- Component instantiations
---------------------------------------------------------------------------------------------------------

    -------------------------------------------------------
    -- Instantiate the unit under test.
    -------------------------------------------------------
    uut : entity work.clk_enbl_gen
    generic map(
        MINRT                           => MINRT,
        NENBL                           => NENBL)
    port map(                           
        clk                             => clk    ,
        reset                           => reset  ,
        enable                          => enable ,
        strobe                          => strobe 
    );
    


---------------------------------------------------------------------------------------------------------
-- Concurrent statements
---------------------------------------------------------------------------------------------------------



    -- simulate power on reset
    reset <= '1', '0' after CKPER*8;
    clk <= not clk after CKHPER;



---------------------------------------------------------------------------------------------------------
-- Sequential statements
---------------------------------------------------------------------------------------------------------





end behave;