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

entity ttcs_framing_mgr is
generic(
    DWDT                            : positive;
    SEED                            : positive);
port(
    clk                             : in std_logic;
    reset                           : in std_logic;        
    dout                            : std_logic;
    din                             : std_logic;
    inject_err                      : out std_logic
    locked                          : out std_logic;
    bit_err                         : out std_logic;
    num_err                         : out std_logic_vector(7 downto 0));
end ttcs_framing_mgr;

---------------------------------------------------------------------------------------------------------
-- Architecture declaration
---------------------------------------------------------------------------------------------------------
architecture behave of ttcs_framing_mgr is   

begin
------------------------------------------------------------------------------------------------
-- Component instantiations
------------------------------------------------------------------------------------------------
    tx_gen : for I in 1 to 3 generate
        tx_ins : entity work.serial_lfsr_tx
        generic map(
            DWDT                    => DWDT,
            SEED                    => SEED)
        port map(
            -- clock / reset     ---------------
            clk                     => clk,
            reset                   => reset,
            -- FEX interface  ---------------
            dout                    => dout
        );
    end generate;
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

    data_pcs : process(clk)
    begin
        if clk'event and clk='1' then
            din <= dout when inject_err='0' else (not dout);
        end if;
    end process;

------------------------------------------------------------------------------------------------
-- Asynchronous and Synchronous processes.
------------------------------------------------------------------------------------------------



end behave;
