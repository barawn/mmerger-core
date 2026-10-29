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
-- Top level transmitter portion of timing, trigger, control,
-- and status interface.
--
--*********************************************************************************

library ieee;
    use ieee.std_logic_1164.all;

entity ttcs_intfc_mgr is
generic(
    RGBUF_TYP                       : natural               := 0;     --0=BUFIO,1=BUFR (regional clock buffer type)
    USE_FIFO                        : natural               := 0;     --0=don't use IN_FIFO, 1=use IN_FIFO (for CDC)
    HIGH_PRFM_MODE                  : string                := "TRUE";--TRUE=high-performance/power, FALSE=high-jitter/low-power (IDELAY)
    REFCLK_FREQUENCY                : real                  := 200.0; --IDELAY reference clock frequency
    INV_DAQ_CLK                     : std_logic             := '0';
    INV_FST_CTRL                    : std_logic             := '0';
    INV_SYNC                        : std_logic             := '0';
    INV_STRG                        : std_logic             := '0';
    INV_FST_CLK                     : std_logic             := '0';
    INV_FST_STAT                    : std_logic             := '0');
port(
    lreset                          : in std_logic;
    --idelayctrl_rdy                  : in std_logic_vector(0 downto 0);
    idelay_clk                      : in std_logic;
    idelay_ld                       : in std_logic;-- pulse once after DAQ_CLK is stable to load delay
    idelay_cntvalin                 : in std_logic_vector(4 downto 0);
    odelay_cntvalin                 : in std_logic_vector(4 downto 0);
    -- IO TX interface (connect to pins)
    io_daq_clk_p                    : out std_logic;
    io_daq_clk_n                    : out std_logic;
    io_fst_ctrl_p                   : out std_logic;
    io_fst_ctrl_n                   : out std_logic;
    io_sync_p                       : out std_logic;
    io_sync_n                       : out std_logic;
    io_strg_p                       : out std_logic;
    io_strg_n                       : out std_logic;
    -- Fabric TX interface
    fbrc_daq_clk                    : in std_logic;
    fbrc_fst_ctrl                   : in std_logic;
    fbrc_sync                       : in std_logic;
    fbrc_strg                       : in std_logic;
    -- IO RX interface (connect to pins)
    io_fst_clk_p                    : in std_logic;
    io_fst_clk_n                    : in std_logic;
    io_fst_stat_p                   : in std_logic;
    io_fst_stat_n                   : in std_logic;
    -- Fabric RX interface
    bufg_fst_clk                    : out std_logic; -- buffered I/O clock
    fbrc_fst_clk                    : in std_logic;  -- IN_FIFO clock
    fbrc_fst_stat                   : out std_logic);
end ttcs_intfc_mgr;

architecture behave of ttcs_intfc_mgr is

    constant TXDWDT                 : integer := 6;-- double for DDR
    constant RXDWDT                 : integer := 2;-- double for DDR

    signal io_tx_data_p             : std_logic_vector(TXDWDT/2-1 downto 0);
    signal io_tx_data_n             : std_logic_vector(TXDWDT/2-1 downto 0);
    signal io_rx_data_p             : std_logic_vector(RXDWDT/2-1 downto 0);
    signal io_rx_data_n             : std_logic_vector(RXDWDT/2-1 downto 0);    
    signal fbrc_tx_data             : std_logic_vector(TXDWDT-1 downto 0);
    signal fbrc_rx_data             : std_logic_vector(RXDWDT-1 downto 0);

    signal idelay_cntvalout         : std_logic_vector(4 downto 0);
    signal regional_clk             : std_logic;

    function CLK_INV_FUN(b : std_logic) return string is
    begin
        if b then
        --invert clock when true/high
            return "FALL";
        else
            return "RISE";
        end if;
    end function;

begin
  
    --------------------------------------------------
    -- Buffer and delay the clocks.
    --------------------------------------------------
    tx_clk_ins : entity work.dif_clogic_7series
    generic map(
        USE_IDELAY                 => 0,--0=no,1=yes
        USE_BUFG                   => 0,--0=no,1=yes
        RGBUF_TYP                  => RGBUF_TYP,--0=BUFIO,1=BUFR
        HIGH_PRFM_MODE             => HIGH_PRFM_MODE,
        REFCLK_FREQUENCY           => REFCLK_FREQUENCY,
        CLK_OUT_EDGE               => CLK_INV_FUN(INV_DAQ_CLK))
    port map(
        lreset                      => lreset,
        --idelayctrl_rdy
        idelay_clk                  => idelay_clk,
        idelay_ld                   => idelay_ld ,
        idelay_cntvalin             => idelay_cntvalin,
        -- IO interface
        io_clk_out_p                => io_daq_clk_p,
        io_clk_out_n                => io_daq_clk_n,
        -- IO interface
        io_clk_in_p                 => io_fst_clk_p,
        io_clk_in_n                 => io_fst_clk_n,
        -- Fabric interface
        fbrc_tx_clk                 => fbrc_daq_clk,
        global_clk                  => bufg_fst_clk,
        regional_clk                => regional_clk
    );

    --------------------------------------------------
    -- Data capture and clock domain crossing.
    --------------------------------------------------
    tx_data_ins : entity work.dif_ologic_7series
    generic map(
        DWDT                        => TXDWDT)
    port map(
        lreset                      => lreset,
        fbrc_clk                    => fbrc_daq_clk,
        -- output to I/O
        io_data_p                   => io_tx_data_p,
        io_data_n                   => io_tx_data_n,
        -- input from fabric
        fbrc_data                   => fbrc_tx_data
    );

    --------------------------------------------------
    -- Data capture and clock domain crossing.
    --------------------------------------------------
    rx_data_ins : entity work.dif_ilogic_7series
    generic map(
        USE_FIFO                    => USE_FIFO,
        HIGH_PRFM_MODE              => HIGH_PRFM_MODE,
        REFCLK_FREQUENCY            => REFCLK_FREQUENCY,
        DWDT                        => RXDWDT)
    port map(
        lreset                      => lreset,
        idelay_clk                  => idelay_clk,
        idelay_ld                   => idelay_ld ,      
        idelay_cntvalin             => idelay_cntvalin,        
        fbrc_clk                    => fbrc_fst_clk,        
        -- input from I/O
        io_clk                      => regional_clk,
        io_data_p                   => io_rx_data_p,
        io_data_n                   => io_rx_data_n,
        -- output to fabric
        fbrc_data                   => fbrc_rx_data
    );  


    -- map the fabric to the OLOGIC (use both DDR bits unless encoding is used)
    fbrc_tx_data <= ((fbrc_fst_ctrl xor INV_FST_CTRL) & (fbrc_fst_ctrl xor INV_FST_CTRL)) &
                    ((fbrc_sync xor INV_SYNC) & (fbrc_sync xor INV_SYNC)) &
                    ((fbrc_strg xor INV_STRG) & (fbrc_strg xor INV_STRG));
       
    -- map the OLOGIC to the pins
    io_fst_ctrl_p <= io_tx_data_p(2); 
    io_sync_p     <= io_tx_data_p(1);
    io_strg_p     <= io_tx_data_p(0);
    io_fst_ctrl_n <= io_tx_data_n(2);
    io_sync_n     <= io_tx_data_n(1);
    io_strg_n     <= io_tx_data_n(0);    
    
    -- map the pins to the ILOGIC
    io_rx_data_p(0) <= io_fst_stat_p;
    io_rx_data_n(0) <= io_fst_stat_n;  
        
    -- Map the ILOGIC to the fabric
    pipe_pcs : process(fbrc_fst_clk)
    begin
        if fbrc_fst_clk'event and fbrc_fst_clk='1' then
            fbrc_fst_stat <= fbrc_rx_data(0) xor INV_FST_STAT;--pipeline this!!!???
        end if;
    end process;
        
end behave;
