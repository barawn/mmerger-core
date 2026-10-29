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
-- Test bench for HELIX TTCS using counters for the control signals.
--
--*********************************************************************************

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_unsigned.all;

entity ttcs_intfc_tb is
end ttcs_intfc_tb;

architecture behave of ttcs_intfc_tb is

    constant ICKPER                     : time                          := 5 ns;
    constant ICKHPER                    : time                          := ICKPER/2;
    constant DCKPER                     : time                          := 12.5 ns;
    constant DCKHPER                    : time                          := DCKPER/2;
    constant HIGH_PRFM_MODE             : string                        := "TRUE";
    constant REFCLK_FREQUENCY           : real                          := 200.0;
    constant RUNNW                      : integer                       := 3;--don't really care here
    constant TTAGW                      : integer                       := 3;--don't really care here
    constant TTMEW                      : integer                       := 3;--don't really care here
    constant RGBUF_TYP                  : natural                       := 0;
    constant USE_FIFO                   : natural                       := 0;
    constant ODELAY_CNTVALUEIN          : std_logic_vector(4 downto 0)  := 5X"F";
    constant IDELAY_CNTVALUEIN          : std_logic_vector(4 downto 0)  := 5X"0";
    constant FRMDWDT                    : positive                      := 16;
    constant FRMSEED                    : positive                      := 202;
    constant MGRTXLNK                   : positive                      := 4;
    constant MGRRXLNK                   : positive                      := 1;
    constant FEBTXLNK                   : positive                      := 1;
    constant FEBRXLNK                   : positive                      := 4;
    constant INV_DAQ_CLK                : std_logic                     := '0';
    constant INV_FST_CTRL               : std_logic                     := '0';
    constant INV_SYNC                   : std_logic                     := '0';
    constant INV_STRG                   : std_logic                     := '0';
    constant INV_FST_CLK                : std_logic                     := '0';
    constant INV_FST_STAT               : std_logic                     := '0';
    
    -- UUT port signals
    signal lreset                       : std_logic;
    --signal clk200m                      : std_logic;
    signal idelay_clk                   : std_logic         := '0';
    signal idelay_ld                    : std_logic;
    --signal idelayctrl_rdy               : std_logic_vector(0 downto 0);
    -- UUT 1 ----------------------------------------------
    -- IO TX interface (connect to pins)
    signal mgr_io_daq_clk_p             : std_logic;
    signal mgr_io_daq_clk_n             : std_logic;
    signal mgr_io_fst_ctrl_p            : std_logic;
    signal mgr_io_fst_ctrl_n            : std_logic;
    signal mgr_io_sync_p                : std_logic;
    signal mgr_io_sync_n                : std_logic;
    signal mgr_io_strg_p                : std_logic;
    signal mgr_io_strg_n                : std_logic;
    -- Fabric RX interface
    signal mgr_fbrc_daq_clk             : std_logic         := '0';
    signal mgr_fbrc_fst_ctrl            : std_logic;
    signal mgr_fbrc_sync                : std_logic;
    signal mgr_fbrc_strg                : std_logic;
    -- IO TX interface (connect to pins)
    signal mgr_io_fst_clk_p             : std_logic;
    signal mgr_io_fst_clk_n             : std_logic;
    signal mgr_io_fst_stat_p            : std_logic;
    signal mgr_io_fst_stat_n            : std_logic;
    -- Fabric TX interface
    signal mgr_bufg_fst_clk             : std_logic; -- buffered I/O clock
    signal mgr_fbrc_fst_clk             : std_logic;  -- IN_FIFO clock
    signal mgr_fbrc_fst_stat            : std_logic;
    -- UUT 2 ----------------------------------------------
    signal feb_io_daq_clk_p             : std_logic;
    signal feb_io_daq_clk_n             : std_logic;
    signal feb_io_fst_ctrl_p            : std_logic;
    signal feb_io_fst_ctrl_n            : std_logic;
    signal feb_io_sync_p                : std_logic;
    signal feb_io_sync_n                : std_logic;
    signal feb_io_strg_p                : std_logic;
    signal feb_io_strg_n                : std_logic;
    -- Fabric RX interface
    signal feb_bufg_daq_clk             : std_logic; -- buffered I/O clock
    signal feb_fbrc_daq_clk             : std_logic;  -- IN_FIFO clock
    signal feb_fbrc_fst_ctrl            : std_logic;
    signal feb_fbrc_sync                : std_logic;
    signal feb_fbrc_strg                : std_logic;
    -- IO TX interface (connect to pins)
    signal feb_io_fst_clk_p             : std_logic;
    signal feb_io_fst_clk_n             : std_logic;
    signal feb_io_fst_stat_p            : std_logic;
    signal feb_io_fst_stat_n            : std_logic;
    -- Fabric TX interface
    signal feb_fbrc_fst_clk             : std_logic; -- clock used for fst_stat (busy, etc.)
    signal feb_fbrc_fst_stat            : std_logic;
    -- Event builder interface
    signal run_number                   : std_logic_vector(RUNNW-1 downto 0);
    signal trg_tag                      : std_logic_vector(TTAGW-1 downto 0);
    signal trg_time                     : std_logic_vector(TTMEW-1 downto 0);

    signal mgr_frm_dout                 : std_logic_vector(1 to MGRTXLNK);
    signal mgr_frm_din                  : std_logic_vector(1 to MGRRXLNK);

    signal feb_frm_dout                 : std_logic_vector(1 to FEBTXLNK);
    signal feb_frm_din                  : std_logic_vector(1 to FEBRXLNK);

    signal invalid                      : std_logic                             := '0';
    signal dvalid                       : std_logic                             := '0';
    signal data_cntr                    : std_logic_vector(2 downto 0);
    signal data_enable                  : std_logic;
    signal verify_cntr                  : std_logic_vector(2 downto 0)     := (others => '0');
    signal verify_vec                   : std_logic_vector(2 downto 0);
    signal verify_data                  : std_logic_vector(2 downto 0);

    alias mgr_inject_err is <<signal mgr_frm_ins.inject_err        : std_logic_vector(1 to MGRTXLNK)>>;
    alias feb_inject_err is <<signal feb_frm_ins.inject_err        : std_logic_vector(1 to FEBTXLNK)>>;

begin

---------------------------------------------------------------------------------------------------------
-- Component instantiations
---------------------------------------------------------------------------------------------------------

    -------------------------------------------------------
    -- Instantiate the front-end unit under test
    -- Swap TX and RX here.
    -------------------------------------------------------
    UUT_MGR : entity work.ttcs_intfc_mgr
    generic map(
        RGBUF_TYP                       => RGBUF_TYP,       --0=BUFIO,1=BUFR (regional clock buffer type)
        USE_FIFO                        => USE_FIFO,        --0=don't use IN_FIFO, 1=use IN_FIFO (for CDC)
        HIGH_PRFM_MODE                  => HIGH_PRFM_MODE,  --TRUE=high-performance/power, FALSE=high-jitter/low-power (IDELAY)
        REFCLK_FREQUENCY                => REFCLK_FREQUENCY,--IDELAY reference clock frequency
        INV_DAQ_CLK                     => INV_DAQ_CLK,
        INV_FST_CTRL                    => INV_FST_CTRL,
        INV_SYNC                        => INV_SYNC,
        INV_STRG                        => INV_STRG,
        INV_FST_CLK                     => INV_FST_CLK,
        INV_FST_STAT                    => INV_FST_STAT)
    port map(
        lreset                          => lreset,
        --idelayctrl_rdy                => --idelayctrl_rdy,
        idelay_clk                      => idelay_clk,
        idelay_ld                       => idelay_ld,
        idelay_cntvalin                 => IDELAY_CNTVALUEIN ,
        odelay_cntvalin                 => ODELAY_CNTVALUEIN ,
        -- IO TX interface (connect to pins)
        io_daq_clk_p                    => mgr_io_daq_clk_p ,
        io_daq_clk_n                    => mgr_io_daq_clk_n ,
        io_fst_ctrl_p                   => mgr_io_fst_ctrl_p,
        io_fst_ctrl_n                   => mgr_io_fst_ctrl_n,
        io_sync_p                       => mgr_io_sync_p,
        io_sync_n                       => mgr_io_sync_n,
        io_strg_p                       => mgr_io_strg_p,
        io_strg_n                       => mgr_io_strg_n,
        -- Fabric TX interface
        fbrc_daq_clk                    => mgr_fbrc_daq_clk ,
        fbrc_fst_ctrl                   => mgr_fbrc_fst_ctrl,
        fbrc_sync                       => mgr_fbrc_sync,
        fbrc_strg                       => mgr_fbrc_strg,
        -- IO RX interface (connect to pins)
        io_fst_clk_p                    => mgr_io_fst_clk_p ,
        io_fst_clk_n                    => mgr_io_fst_clk_n ,
        io_fst_stat_p                   => mgr_io_fst_stat_p,
        io_fst_stat_n                   => mgr_io_fst_stat_n,
        -- Fabric RX interface
        bufg_fst_clk                    => mgr_bufg_fst_clk ,
        fbrc_fst_clk                    => mgr_fbrc_fst_clk ,
        fbrc_fst_stat                   => mgr_fbrc_fst_stat
    );

    -------------------------------------------------------
    -- Instantiate the receive (zFPGA) unit under test
    -------------------------------------------------------
    UUT_FEB : entity work.ttcs_intfc_feb
    generic map(
        RGBUF_TYP                       => RGBUF_TYP,       --0=BUFIO,1=BUFR (regional clock buffer type)
        USE_FIFO                        => USE_FIFO,        --0=don't use IN_FIFO, 1=use IN_FIFO (for CDC)
        HIGH_PRFM_MODE                  => HIGH_PRFM_MODE,  --TRUE=high-performance/power, FALSE=high-jitter/low-power (IDELAY)
        REFCLK_FREQUENCY                => REFCLK_FREQUENCY,--IDELAY reference clock frequency    
        RUNNW                           => RUNNW,
        TTAGW                           => TTAGW,
        TTMEW                           => TTMEW,
        INV_DAQ_CLK                     => INV_DAQ_CLK,
        INV_FST_CTRL                    => INV_FST_CTRL,
        INV_SYNC                        => INV_SYNC,
        INV_STRG                        => INV_STRG,
        INV_FST_CLK                     => INV_FST_CLK,
        INV_FST_STAT                    => INV_FST_STAT)
    port map(
        lreset                          => lreset,
        --idelayctrl_rdy                => idelayctrl_rdy,
        idelay_clk                      => idelay_clk,
        idelay_ld                       => idelay_ld,
        idelay_cntvalin                 => IDELAY_CNTVALUEIN,
        odelay_cntvalin                 => ODELAY_CNTVALUEIN,
        -- IO RX interface (connect to pins)
        io_daq_clk_p                    => feb_io_daq_clk_p,
        io_daq_clk_n                    => feb_io_daq_clk_n,
        io_fst_ctrl_p                   => feb_io_fst_ctrl_p,
        io_fst_ctrl_n                   => feb_io_fst_ctrl_n,
        io_sync_p                       => feb_io_sync_p,
        io_sync_n                       => feb_io_sync_n,
        io_strg_p                       => feb_io_strg_p,
        io_strg_n                       => feb_io_strg_n,
        -- Fabric RX interface
        bufg_daq_clk                    => feb_bufg_daq_clk , -- buffered I/O clock
        fbrc_daq_clk                    => feb_fbrc_daq_clk , -- IN_FIFO clock
        fbrc_fst_ctrl                   => feb_fbrc_fst_ctrl,
        fbrc_sync                       => feb_fbrc_sync,
        fbrc_strg                       => feb_fbrc_strg,
        -- IO TX interface (connect to pins)
        io_fst_clk_p                    => feb_io_fst_clk_p,
        io_fst_clk_n                    => feb_io_fst_clk_n,
        io_fst_stat_p                   => feb_io_fst_stat_p,
        io_fst_stat_n                   => feb_io_fst_stat_n,
        -- Fabric TX interface
        fbrc_fst_clk                    => feb_fbrc_fst_clk,-- clock used for fst_stat (busy, etc.)
        fbrc_fst_stat                   => feb_fbrc_fst_stat,
        run_number                      => run_number,
        trg_tag                         => trg_tag,
        trg_time                        => trg_time
    );

    mgr_frm_ins : entity work.ttcs_framing_mgr
    generic map(
        TXLNK                           => MGRTXLNK,
        RXLNK                           => MGRRXLNK,
        DWDT                            => FRMDWDT,
        SEED                            => FRMSEED)
    port map(
        clk                             => mgr_fbrc_daq_clk,
        reset                           => lreset,
        dout                            => mgr_frm_dout,
        din                             => mgr_frm_din
    );

    feb_frm_ins : entity work.ttcs_framing_feb
    generic map(
        TXLNK                           => FEBTXLNK,
        RXLNK                           => FEBRXLNK,
        DWDT                            => FRMDWDT,
        SEED                            => FRMSEED)
    port map(   
        clk                             => feb_bufg_daq_clk,
        reset                           => lreset,
        dout                            => feb_frm_dout,
        din                             => feb_frm_din
    );

---------------------------------------------------------------------------------------------------------
-- Concurrent statements
---------------------------------------------------------------------------------------------------------
    assert (invalid='0') report "Input and output do not match" severity ERROR;

    -- generate clocks, they could be out of phase
    mgr_fbrc_daq_clk <= (not mgr_fbrc_daq_clk) after DCKHPER;
    -- wrap the clock around as it will likely be in hardware
    mgr_fbrc_fst_clk <= mgr_fbrc_daq_clk;
    mgr_fbrc_fst_ctrl <= mgr_frm_dout(1);
    mgr_fbrc_sync     <= mgr_frm_dout(2);
    mgr_fbrc_strg     <= mgr_frm_dout(3);
    mgr_frm_din(1)    <= mgr_fbrc_fst_stat;

    -- connect the external ports/bus
    feb_io_daq_clk_p  <= mgr_io_daq_clk_p;
    feb_io_daq_clk_n  <= mgr_io_daq_clk_n;
    feb_io_fst_ctrl_p <= mgr_io_fst_ctrl_p;
    feb_io_fst_ctrl_n <= mgr_io_fst_ctrl_n;
    feb_io_sync_p     <= mgr_io_sync_p;
    feb_io_sync_n     <= mgr_io_sync_n;
    feb_io_strg_p     <= mgr_io_strg_p;
    feb_io_strg_n     <= mgr_io_strg_n;
    mgr_io_fst_clk_p  <= feb_io_fst_clk_p;
    mgr_io_fst_clk_n  <= feb_io_fst_clk_n;
    mgr_io_fst_stat_p <= feb_io_fst_stat_p;
    mgr_io_fst_stat_n <= feb_io_fst_stat_n;

    feb_frm_din(1) <= feb_fbrc_fst_ctrl;
    feb_frm_din(2) <= feb_fbrc_sync;
    feb_frm_din(3) <= feb_fbrc_strg;
    feb_frm_din(4) <= feb_fbrc_fst_stat;

    -- wrap the clock around as it will likely be in hardware
    feb_fbrc_fst_clk <= feb_bufg_daq_clk;
    feb_fbrc_daq_clk <= feb_bufg_daq_clk;
    -- wrap the control bit to the status bit
    feb_fbrc_fst_stat <= feb_fbrc_fst_ctrl;


    -- simulate power on reset
    lreset <= '1', '0' after DCKPER*20;
    idelay_clk <= not idelay_clk after ICKHPER;
    idelay_ld <= '0', '1' after ICKPER*16, '0' after ICKPER*17;

    data_enable <= '0', '1' after DCKPER*64;

    verify_vec <= feb_fbrc_fst_ctrl & feb_fbrc_sync & feb_fbrc_strg;

    mgr_inject_err <= (others => '0');
    feb_inject_err <= (others => '0');

---------------------------------------------------------------------------------------------------------
-- Sequential statements
---------------------------------------------------------------------------------------------------------


    --------------------------------------------------------------------
    ---- Wait until data output is valid.
    --------------------------------------------------------------------
    --valid_pcs : process(lreset,feb_bufg_daq_clk)
    --begin
    --    if lreset = '1' then
    --        dvalid <= '0';
    --    else
    --        if rising_edge(feb_bufg_daq_clk) then
    --            if feb_fbrc_strg = '1' then
    --                dvalid  <= '1';
    --            end if;
    --        end if;
    --    end if;
    --end process;
    --
    --verify_data <= verify_vec'delayed(DCKPER*2);
    --
    --------------------------------------------------------------------
    ---- Verify that the output matches the input.
    --------------------------------------------------------------------
    --verify_pcs : process(feb_bufg_daq_clk)
    --begin
    --    if rising_edge(feb_bufg_daq_clk) then
    --        if dvalid = '1' then
    --            verify_cntr <= verify_cntr + '1';
    --            if verify_data /= verify_cntr then
    --                invalid <= '1';
    --            else
    --                invalid <= '0';
    --            end if;
    --        end if;
    --    end if;
    --end process;

end behave;