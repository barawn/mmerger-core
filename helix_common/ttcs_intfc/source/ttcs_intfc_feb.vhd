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
-- Top level front-end portion of timing, trigger, control, and status interface.
-- The bufg_daq_clk can be connected to fbrc_daq_clk if DAQ clock is used as TDC clock.
-- The inputs need to connect to a single byte group. Not necessarily byte group 0.
--
-- Deficiencies/Know Issues:
-- 1) Need to add generics to add/remove IN_FIFO.
--*********************************************************************************

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity ttcs_intfc_feb is
generic(
    RGBUF_TYP                       : natural               := 0;      --0=BUFIO,1=BUFR (regional clock buffer type)
    USE_FIFO                        : natural               := 0;      --0=don't use IN_FIFO, 1=use IN_FIFO (for CDC)
    NO_EDGEDET                      : boolean               := FALSE;  --TRUE=remove edge detectors, FALSE=use edge detectors
    HIGH_PRFM_MODE                  : string                := "FALSE";--TRUE=high-performance/power, FALSE=high-jitter/low-power (IDELAY)
    REFCLK_FREQUENCY                : real                  := 200.0;  --IDELAY reference clock frequency
    RUNNW                           : integer range 1 to 32 := 10;
    TTAGW                           : integer range 1 to 48 := 10;
    TTMEW                           : integer range 1 to 32 := 10;
    INV_DAQ_CLK                     : std_logic             := '0';
    INV_FST_CTRL                    : std_logic             := '0';
    INV_SYNC                        : std_logic             := '0';
    INV_STRG                        : std_logic             := '0';
    INV_FST_CLK                     : std_logic             := '0';
    INV_FST_STAT                    : std_logic             := '0');
port(
    lreset                          : in std_logic;
    --idelayctrl_rdy                  : in std_logic_vector(0 downto 0);
    idelay_clk                      : in std_logic; -- free running clock, e.g 200 MHz
    idelay_ld                       : in std_logic; -- pulse once after DAQ_CLK is stable to load delay
    idelay_cntvalin                 : in std_logic_vector(4 downto 0);
    odelay_cntvalin                 : in std_logic_vector(4 downto 0);
    -- IO RX interface (connect to pins)
    io_daq_clk_p                    : in std_logic;
    io_daq_clk_n                    : in std_logic;
    io_fst_ctrl_p                   : in std_logic;
    io_fst_ctrl_n                   : in std_logic;
    io_sync_p                       : in std_logic;
    io_sync_n                       : in std_logic;
    io_strg_p                       : in std_logic;
    io_strg_n                       : in std_logic;
    -- Fabric RX interface
    bufg_daq_clk                    : out std_logic; -- buffered I/O clock
    fbrc_daq_clk                    : in std_logic;  -- IN_FIFO clock
    fbrc_fst_ctrl                   : out std_logic;
    fbrc_sync                       : out std_logic;
    fbrc_strg                       : out std_logic;
    -- IO TX interface (connect to pins)
    io_fst_clk_p                    : out std_logic;
    io_fst_clk_n                    : out std_logic;
    io_fst_stat_p                   : out std_logic;
    io_fst_stat_n                   : out std_logic;
    -- Fabric TX interface
    fbrc_fst_clk                    : in std_logic; -- clock used for fst_stat (busy, etc.)
    fbrc_fst_stat                   : in std_logic;
    -- Event builder interface
    run_number                      : out std_logic_vector(RUNNW-1 downto 0);
    trg_tag                         : out std_logic_vector(TTAGW-1 downto 0);
    trg_time                        : out std_logic_vector(TTMEW-1 downto 0));
end ttcs_intfc_feb;

architecture struct of ttcs_intfc_feb is

    constant RXDWDT                 : integer       := 6;-- double for DDR
    constant TXDWDT                 : integer       := 2;-- double for DDR
    constant CTRLB                  : integer       := 4;
    constant SYNCB                  : integer       := 2;
    constant STRGB                  : integer       := 0;

    signal io_rx_bg0_p              : std_logic_vector(RXDWDT/2-1 downto 0);
    signal io_rx_bg0_n              : std_logic_vector(RXDWDT/2-1 downto 0);
    signal io_tx_data_p             : std_logic_vector(TXDWDT/2-1 downto 0);
    signal io_tx_data_n             : std_logic_vector(TXDWDT/2-1 downto 0);
    signal fbrc_tx_data             : std_logic_vector(TXDWDT-1 downto 0);
    signal fbrc_rx_bg0              : std_logic_vector(RXDWDT-1 downto 0);

    signal idelay_cntvalclk         : std_logic_vector(4 downto 0);
    signal idelay_cntvaldat         : std_logic_vector(4 downto 0);

    --signal idelay_cntvalout         : std_logic_vector(4 downto 0);
    signal global_clk               : std_logic;
    signal regional_clk             : std_logic;

    signal fbrc_fst_ctrl_q0         : std_logic;
    signal fbrc_sync_q0             : std_logic;
    signal fbrc_strg_q0             : std_logic;

    signal fbrc_fst_ctrl_re         : std_logic;
    signal fbrc_sync_re             : std_logic;
    signal fbrc_strg_re             : std_logic;


    signal run_num_ctr              : unsigned(RUNNW-1 downto 0);
    signal trg_tag_ctr              : unsigned(TTAGW-1 downto 0);
    signal trg_time_ctr             : unsigned(TTMEW-1 downto 0);

begin

----------------------------------------------------------------
-- Component instantiations
----------------------------------------------------------------

    --------------------------------------------------
    -- Buffer and delay the clocks.
    --------------------------------------------------
    rx_clk_ins : entity work.dif_clogic_7series
    generic map(
        USE_IDELAY              => 0,--0=no,1=yes (don't mess with the clock unless you're desperate!)
        USE_BUFG                => 1,--0=no,1=yes
        RGBUF_TYP               => RGBUF_TYP,--0=BUFIO,1=BUFR
        HIGH_PRFM_MODE          => HIGH_PRFM_MODE,
        REFCLK_FREQUENCY        => REFCLK_FREQUENCY,
        CLK_IN_INV              => INV_DAQ_CLK,
        CLK_OUT_EDGE            => "RISE")
    port map(
        lreset                  => lreset,
        --idelayctrl_rdy
        idelay_clk              => idelay_clk,
        idelay_ld               => idelay_ld,
        idelay_cntvalin         => idelay_cntvalclk,
        -- IO interface
        io_clk_out_p            => io_fst_clk_p,
        io_clk_out_n            => io_fst_clk_n,
        -- IO interface
        io_clk_in_p             => io_daq_clk_p,
        io_clk_in_n             => io_daq_clk_n,
        -- Fabric interface
        fbrc_tx_clk             => fbrc_fst_clk,
        global_clk              => global_clk,
        regional_clk            => regional_clk
    );

    --------------------------------------------------
    -- Receive byte group 0. Data capture and clock
    -- domain crossing.
    --------------------------------------------------
    rx_bg_ins : entity work.dif_ilogic_7series
    generic map(
        USE_FIFO                => USE_FIFO,
        HIGH_PRFM_MODE          => HIGH_PRFM_MODE,
        REFCLK_FREQUENCY        => REFCLK_FREQUENCY,
        DWDT                    => RXDWDT)
    port map(
        lreset                  => lreset,
        idelay_clk              => idelay_clk,
        idelay_ld               => idelay_ld,
        idelay_cntvalin         => idelay_cntvaldat,
        fbrc_clk                => fbrc_daq_clk,
        -- input from I/O
        io_clk                  => regional_clk,
        io_data_p               => io_rx_bg0_p,
        io_data_n               => io_rx_bg0_n,
        -- output to fabric
        fbrc_data               => fbrc_rx_bg0
    );

    --------------------------------------------------
    -- Transmit bits.
    --------------------------------------------------
    tx_data_ins : entity work.dif_ologic_7series
    generic map(
        DWDT                    => TXDWDT)
    port map(
        lreset                  => lreset,
        fbrc_clk                => fbrc_fst_clk,
        -- output to I/O
        io_data_p               => io_tx_data_p,
        io_data_n               => io_tx_data_n,
        -- input from fabric
        fbrc_data               => fbrc_tx_data
    );

----------------------------------------------------------------
-- Concurrent statements
----------------------------------------------------------------
    -- keep the clock static and move the data
    idelay_cntvalclk <= 5UX"0";
    idelay_cntvaldat <= idelay_cntvalin;

    bufg_daq_clk <= global_clk;

    -- map the IO pins to the ILOGIC
    io_rx_bg0_p  <= io_fst_ctrl_p & io_sync_p & io_strg_p;
    io_rx_bg0_n  <= io_fst_ctrl_n & io_sync_n & io_strg_n;

    -- map the ILOGIC to the fabric (DDR to SDR if not encoded)
    edge_gen : if NO_EDGEDET=FALSE generate
        fbrc_fst_ctrl <= fbrc_fst_ctrl_re;
        fbrc_sync     <= fbrc_sync_re;
        fbrc_strg     <= fbrc_strg_re;
    else generate
        fbrc_fst_ctrl <= fbrc_fst_ctrl_q0;
        fbrc_sync     <= fbrc_sync_q0;
        fbrc_strg     <= fbrc_strg_q0;
    end generate;

    -- map the fabric to the OLOGIC
    fbrc_tx_data <= (fbrc_fst_stat xor INV_FST_STAT) & (fbrc_fst_stat xor INV_FST_STAT);

    -- map the OLOGIC to the pins
    io_fst_stat_p <= io_tx_data_p(0);
    io_fst_stat_n <= io_tx_data_n(0);

    run_number <= STD_LOGIC_VECTOR(run_num_ctr);
    trg_tag    <= STD_LOGIC_VECTOR(trg_tag_ctr);
    trg_time   <= STD_LOGIC_VECTOR(trg_time_ctr);

----------------------------------------------------------------
-- Processes
----------------------------------------------------------------
    --------------------------------------------------
    -- Rising edge detector to prevent assertion when
    -- inputs are not connected.
    --! Will not work if multiple signals encoded onto
    -- these lines.
    --------------------------------------------------
    edge_detect_pcs : process(global_clk)
    begin
        if global_clk'event and global_clk='1' then
            fbrc_fst_ctrl_q0 <= fbrc_rx_bg0(CTRLB) xor INV_FST_CTRL;
            fbrc_sync_q0     <= fbrc_rx_bg0(SYNCB) xor INV_SYNC;
            fbrc_strg_q0     <= fbrc_rx_bg0(STRGB) xor INV_STRG;
            fbrc_fst_ctrl_re <= fbrc_rx_bg0(CTRLB) and (not fbrc_fst_ctrl_q0);
            fbrc_sync_re     <= fbrc_rx_bg0(SYNCB) and (not fbrc_sync_q0);
            fbrc_strg_re     <= fbrc_rx_bg0(STRGB) and (not fbrc_strg_q0);
        end if;
    end process;

    --------------------------------------------------
    -- Run number counter.
    --! The control signals for this don't exist yet
    --------------------------------------------------
    run_num_pcs : process(global_clk)
    begin
        if global_clk'event and global_clk='1' then
            if fbrc_sync_re = '1' then--!fake it
                run_num_ctr <= (others => '0');
            else
                if fbrc_fst_ctrl_re = '1' then--!fake it
                    run_num_ctr <= run_num_ctr + 1;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------
    -- Trigger tag counter.
    --------------------------------------------------
    trg_tag_pcs : process(global_clk)
    begin
        if global_clk'event and global_clk='1' then
            if fbrc_sync_re = '1' then
                trg_tag_ctr <= (others => '0');
            else
                if fbrc_strg_re = '1' then
                    trg_tag_ctr <= trg_tag_ctr + 1;
                end if;
            end if;
        end if;
    end process;

    --------------------------------------------------
    -- Trigger time counter.
    --------------------------------------------------
    trg_time_pcs : process(global_clk)
    begin
        if global_clk'event and global_clk='1' then
            if fbrc_sync_re = '1' then
                trg_time_ctr <= (others => '0');
            else
                trg_time_ctr <= trg_time_ctr + 1;
            end if;
        end if;
    end process;

end struct;
