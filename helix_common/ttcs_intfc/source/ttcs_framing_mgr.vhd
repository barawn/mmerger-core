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
    TXLNK                           : positive  := 3;
    RXLNK                           : positive  := 1;
    DWDT                            : positive  := 16;
    SEED                            : positive  := 202);
port(
    clk                             : in std_logic;
    reset                           : in std_logic;        
    dout                            : out std_logic_vector(1 to TXLNK);
    din                             : in std_logic_vector(1 to RXLNK));
end ttcs_framing_mgr;

---------------------------------------------------------------------------------------------------------
-- Architecture declaration
---------------------------------------------------------------------------------------------------------
architecture behave of ttcs_framing_mgr is   

    component ttcs_framing_vio
    port(
        clk                         : in std_logic;
        probe_out0                  : out std_logic_vector(3 downto 0));
    end component;

    component ttcs_framing_ila
    port (
        clk                         : in std_logic;
        probe0                      : in std_logic_vector(9 downto 0);
        probe1                      : in std_logic_vector(9 downto 0);
        probe2                      : in std_logic_vector(9 downto 0);
        probe3                      : in std_logic_vector(7 downto 0);
        probe4                      : in std_logic_vector(7 downto 0);
        probe5                      : in std_logic_vector(7 downto 0);
        probe6                      : in std_logic_vector(7 downto 0);
        probe7                      : in std_logic_vector(7 downto 0);
        probe8                      : in std_logic_vector(7 downto 0);
        probe9                      : in std_logic_vector(7 downto 0);
        probe10                     : in std_logic_vector(7 downto 0);
        probe11                     : in std_logic_vector(7 downto 0);
        probe12                     : in std_logic_vector(7 downto 0));
    end component;

    type num_err_type is array (1 to RXLNK) of std_logic_vector(7 downto 0);

    signal locked                   : std_logic_vector(1 to RXLNK);
    signal bit_err                  : std_logic_vector(1 to RXLNK);
    signal dout_err                 : std_logic_vector(1 to TXLNK);
    signal inject_err               : std_logic_vector(1 to TXLNK);
    signal num_err                  : num_err_type;    

begin
------------------------------------------------------------------------------------------------
-- Component instantiations
------------------------------------------------------------------------------------------------
    tx_gen : for I in 1 to TXLNK generate
        tx_ins : entity work.serial_lfsr_tx
        generic map(
            DWDT                    => DWDT,
            SEED                    => SEED+(I*3))
        port map(
            -- clock / reset     ---------------
            clk                     => clk,
            reset                   => reset,
            -- FEX interface  ---------------
            dout                    => dout_err(I)
        );
    end generate;
    -----------------------------------
    
    rx_gen : for I in 1 to RXLNK generate
        rx_ins : entity work.serial_lfsr_rx
        generic map(
            DWDT                        => DWDT,
            SEED                        => SEED)
        port map(
            -- clock / reset     ---------------
            clk                         => clk,
            reset                       => reset,
            -- FEX interface  ---------------        
            din                         => din(I),
            bit_err                     => bit_err(I),
            num_err                     => num_err(I),
            locked                      => locked(I)
        );
    end generate;

    vio_ins : ttcs_framing_vio
    port map(
        clk                             => clk,
        probe_out0                      => inject_err
    );

    ila_ins : ttcs_framing_ila
    port map(
        clk                             => clk,
        probe0                          => din,
        probe1                          => locked,
        probe2                          => bit_err,
        probe3                          => num_err(1),
        probe4                          => num_err(2),
        probe5                          => num_err(3),
        probe6                          => num_err(4),
        probe7                          => num_err(5),
        probe8                          => num_err(6),
        probe9                          => num_err(7),
        probe10                         => num_err(8),
        probe11                         => num_err(9),
        probe12                         => num_err(10)
    );


------------------------------------------------------------------------------------------------
-- Concurrent statements
------------------------------------------------------------------------------------------------

    data_pcs : process(clk)
    begin
        if clk'event and clk='1' then
            for I in 1 to TXLNK loop
                dout(I) <= dout_err(I) when inject_err(I)='0' else (not dout_err(I));
            end loop;
        end if;
    end process;

------------------------------------------------------------------------------------------------
-- Asynchronous and Synchronous processes.
------------------------------------------------------------------------------------------------



end behave;
