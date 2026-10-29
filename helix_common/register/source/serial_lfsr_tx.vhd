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

entity serial_lfsr_tx is
generic(
    DWDT                            : positive   := 16;
    SEED                            : positive   := 202);
port(
    -- clock / reset     ---------------
    clk                             : in std_logic;
    reset                           : in std_logic;
    -- FEX interface  ---------------
    dout                            : out std_logic);
end serial_lfsr_tx;

---------------------------------------------------------------------------------------------------------
-- Architecture declaration
---------------------------------------------------------------------------------------------------------
architecture behave of serial_lfsr_tx is

    constant USEED                  : unsigned := TO_UNSIGNED(SEED,DWDT);
    constant BWDT                   : integer  := INTEGER(CEIL(LOG2(REAL(DWDT))));

    signal tx_lfsr                  : std_logic_vector(1 to DWDT);
    signal piso                     : std_logic_vector(1 to DWDT);

    signal bit_ctr_tc               : std_logic;
    signal bit_ctr                  : unsigned(BWDT-1 downto 0);

begin
------------------------------------------------------------------------------------------------
-- Component instantiations
------------------------------------------------------------------------------------------------

    -----------------------------------

------------------------------------------------------------------------------------------------
-- Concurrent statements
------------------------------------------------------------------------------------------------
    dout <= piso(piso'left);


------------------------------------------------------------------------------------------------
-- Asynchronous and Synchronous processes.
------------------------------------------------------------------------------------------------

    ---------------------------------------------
    -- Generate fake TOB data values.
    ---------------------------------------------
    data_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset then
                tx_lfsr <= STD_LOGIC_VECTOR(USEED);
                piso    <= (others => '1');
            else
                if bit_ctr_tc then
                    -- pseudo-random data transmit
                    tx_lfsr <= (tx_lfsr(16) xnor tx_lfsr(15) xnor tx_lfsr(13) xnor tx_lfsr(4)) & tx_lfsr(1 to (tx_lfsr'right-1));
                    piso <= tx_lfsr;
                else
                    tx_lfsr <= tx_lfsr;
                    piso <= piso(2 to 16) & '0';
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------
    -- Count number of valid words.
    ---------------------------------------------
    bit_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                bit_ctr <= (others => '1');
            else -- down count
                bit_ctr <= bit_ctr - '1';
            end if;
            -- terminal logic
            if bit_ctr = 0 then
                bit_ctr_tc <= '1';
            else
                bit_ctr_tc <= '0';
            end if;
        end if;
    end process;

end behave;
