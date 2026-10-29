--*********************************************************************************
-- Indiana University
-- Center for Exploration of Energy and Matter (CEEM)
--
-- Project: HELIX
--
-- Author:  Brandon Kunkler
--
-- Date:    01/13/2019
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
-- Generates data patterns for testing serial timing and trigger interface signals.
--
-- Deficiencies:
--*********************************************************************************
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

entity serial_lfsr_tb is
end serial_lfsr_tb;

---------------------------------------------------------------------------------------------------------
-- Architecture declaration
---------------------------------------------------------------------------------------------------------
architecture behave of serial_lfsr_tb is   
    
    constant CKPER                  : time              := 1 ns;
    constant DWDT                   : positive          := 16;
    constant SEED                   : positive          := 202;

    signal clk                      : std_logic         := '0';
    signal reset                    : std_logic;

    signal dout                     : std_logic;
    signal din                      : std_logic;
    signal locked                   : std_logic;
    signal bit_err                  : std_logic;
    signal num_err                  : std_logic_vector(7 downto 0);

    signal inject_err               : std_logic;

begin
------------------------------------------------------------------------------------------------
-- Component instantiations
------------------------------------------------------------------------------------------------
    tx_ins : entity work.serial_lfsr_tx
    generic map(
        DWDT                        => DWDT,
        SEED                        => SEED)
    port map(
        -- clock / reset     ---------------
        clk                         => clk,
        reset                       => reset,
        -- FEX interface  ---------------
        dout                        => dout
    );
    -----------------------------------

    rx_ins : entity work.serial_lfsr_rx
    generic map(
        DWDT                        => DWDT,
        SEED                        => SEED)
    port map(
        -- clock / reset     ---------------
        clk                         => clk,
        reset                       => reset,
        -- FEX interface  ---------------        
        din                         => din,
        bit_err                     => bit_err,
        num_err                     => num_err,
        locked                      => locked
    );

------------------------------------------------------------------------------------------------
-- Concurrent statements
------------------------------------------------------------------------------------------------

    clk <= (not clk) after CKPER/2;
    reset <= '1', '0' after CKPER*10;

    din <= dout when inject_err='0' else (not dout);

    inject_err <= '0', '1' after CKPER*5000, '0' after CKPER*5001;

------------------------------------------------------------------------------------------------
-- Asynchronous and Synchronous processes.
------------------------------------------------------------------------------------------------



end behave;
