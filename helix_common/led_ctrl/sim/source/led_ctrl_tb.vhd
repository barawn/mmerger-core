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
    use ieee.numeric_std.all;

entity led_ctrl_tb is
end led_ctrl_tb;

architecture behave of led_ctrl_tb is

    constant CKPER                      : time                           := 1 ns;
    constant CKHPER                     : time                           := CKPER/2;
    
    constant MAXVAL                     : positive                       := 31;
    constant NENBL                      : positive                       := 1;

    signal clk                          : std_logic                      :='0';
    signal led_dis                      : std_logic;
    signal sig_vec                      : std_logic_vector(0 to 7);
    signal led_ck                       : std_logic;
    signal led_ds                       : std_logic;

    signal shft_reg                     : std_logic_vector(0 to 7);
    signal strg_reg                     : std_logic_vector(0 to 7);

begin

---------------------------------------------------------------------------------------------------------
-- Component instantiations
---------------------------------------------------------------------------------------------------------

    -------------------------------------------------------
    -- Instantiate the unit under test.
    -------------------------------------------------------
    uut : entity work.led_ctrl
    generic map(
        SIM_SPDUP                       => TRUE)
    port map(
        clk                             => clk,
        led_dis                         => led_dis,
        sig_vec							=> sig_vec,
        led_ck                          => led_ck,
        led_ds                          => led_ds  
    );
    


---------------------------------------------------------------------------------------------------------
-- Concurrent statements
---------------------------------------------------------------------------------------------------------

    -- simulate power on reset
    led_dis <= '1', '0' after CKPER*300, '1' after CKPER*8000;
    clk <= not clk after CKHPER;

    sig_vec <= X"EE", X"11" after CKPER*2000, X"AA" after CKPER*4000;



---------------------------------------------------------------------------------------------------------
-- Sequential statements
---------------------------------------------------------------------------------------------------------
    nxp74vhd595_pcs : process(led_ck)
    begin
        if (led_ck'event and led_ck='1') then
            shft_reg <= led_ds & shft_reg(0 to shft_reg'right-1);
            strg_reg <= shft_reg;
        end if;
    end process;

end behave;