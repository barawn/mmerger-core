---*********************************************************************************
-- Indiana University
-- Center for Exploration of Energy and Matter (CEEM)
--
-- Project: ATLAS
--
-- Author:  Brandon Kunkler
--
-- Date:    01/26/2018
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
-- Test bench for distribution tree.
--
-- Deficiencies/Know Issues
--
--*********************************************************************************

library ieee;
	use ieee.std_logic_1164.all;

entity dist_tree_tb is
end dist_tree_tb;

architecture behave of dist_tree_tb is
    
    component dist_tree is
    generic(
        NDIST                       : integer;  -- distribution factor = 1 to N
        NOUT                        : integer); -- distribution factor squared
    port(
        clk                         : in std_logic;
        sig                         : in std_logic;
        dist                        : out std_logic_vector(1 to NOUT));
    end component;

    constant BDCKP                  : time                  := 750 ps;
    constant BDCKHP                 : time                  := BDCKP/2;

    signal bd_clk                   : std_logic             := '0';
    signal pb_reset                 : std_logic;

begin

	-- Generate clock
    bd_clk      <= (not bd_clk) after BDCKHP;
    pb_reset    <= '0', '1' after BDCKHP*4, '0' after BDCKHP*8;
    
    -- UUT -------------------------
    tree_ins : dist_tree
    generic map(
        NDIST                       => 4,
        NOUT                        => 32)
    port map(
        clk                         => bd_clk,
        sig                         => pb_reset,
        dist                        => open
    );    


end behave;