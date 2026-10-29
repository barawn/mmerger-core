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
-- Test bench for HELIX Merger Aurora Quad.
--
--*********************************************************************************

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;
library work;
    use work.ttcs_intfc_pkg.all;
library helix_aurora_lib;
    use helix_aurora_lib.helix_aurora;
    use helix_aurora_lib.helix_framing;

entity merger_model is
generic(
    NLANE                               : natural range 1 to 4          := 4);
port(
    -- GT Serial I/O
    mgr_rxp                             : in  std_logic_vector(0 to NLANE-1);
    mgr_rxn                             : in  std_logic_vector(0 to NLANE-1);
    mgr_txp                             : out std_logic_vector(0 to NLANE-1);
    mgr_txn                             : out std_logic_vector(0 to NLANE-1));
end merger_model;

architecture behave of merger_model is

    constant FRPER                      : time                                  := 20 ns;
    constant FRHPER                     : time                                  := FRPER/2;
    constant DAQPER                     : time                                  := 12.5 ns;
    constant DAQHPER                    : time                                  := DAQPER/2;
    constant MGRPER                     : time                                  := 6.25 ns;
    constant MGRHPER                    : time                                  := MGRPER/2;
    constant PCIPER                     : time                                  := 5.0 ns;
    constant PCIHPER                    : time                                  := PCIPER/2;
    constant SI5343_LKTM                : time                                  := 300 ns;
    constant LINE_RATE_VEC              : unsigned(0 to NLANE-1)                := "1000";
    constant STBL_CLK_PER               : integer                               := 20;
    constant USEREFCLK1                 : boolean                               := TRUE;
    constant SIM_SPDUP                  : boolean                               := FALSE;--Channel/lane up are never asserted when speed-up is use!!!!!    
    constant INJECT_ERR                 : natural                               := 1;

    -- Clocks
    signal mgr_gt_refclk_p              : std_logic;
    signal mgr_gt_refclk_n              : std_logic;
    signal mgr_init_clk                 : std_logic                             := '0';
    signal mgr_user_clk                 : std_logic_vector(0 to NLANE-1)        := (others => '0');
    -- Resets
    signal mgr_ext_reset                : std_logic;--free running clock reset
    -- AXI TX Interface
    signal mgr_s_axi_tx_tdata           : ttcs_16bbe_type(0 to NLANE-1);
    signal mgr_s_axi_tx_tkeep           : ttcs_2bbe_type(0 to NLANE-1);
    signal mgr_s_axi_tx_tvalid          : std_logic_vector(0 to NLANE-1);
    signal mgr_s_axi_tx_tready          : std_logic_vector(0 to NLANE-1);
    signal mgr_s_axi_tx_tlast           : std_logic_vector(0 to NLANE-1);
    -- AXI RX Interface
    signal mgr_m_axi_rx_tdata           : ttcs_16bbe_type(0 to NLANE-1);
    signal mgr_m_axi_rx_tkeep           : ttcs_2bbe_type(0 to NLANE-1);
    signal mgr_m_axi_rx_tvalid          : std_logic_vector(0 to NLANE-1);
    signal mgr_m_axi_rx_tlast           : std_logic_vector(0 to NLANE-1);
    -- Native Flow Control TX Interface
    signal mgr_s_axi_nfc_req            : std_logic_vector(0 to NLANE-1);
    signal mgr_s_axi_nfc_nb             : ttcs_4bbe_type(0 to NLANE-1);
    signal mgr_s_axi_nfc_ack            : std_logic_vector(0 to NLANE-1);
    -- Native Flow Control RX Interface
    signal mgr_m_axi_rx_snf             : std_logic_vector(0 to NLANE-1);
    signal mgr_m_axi_rx_fc_nb           : ttcs_4bbe_type(0 to NLANE-1);
    --CRC  status signals
    signal mgr_crc_pass_fail_n          : std_logic_vector(0 to NLANE-1);
    signal mgr_crc_valid                : std_logic_vector(0 to NLANE-1);
    -- Error Detection Interface
    signal mgr_frame_err                : std_logic_vector(0 to NLANE-1);
    signal mgr_hard_err                 : std_logic_vector(0 to NLANE-1);
    signal mgr_soft_err                 : std_logic_vector(0 to NLANE-1);
    signal mgr_channel_up               : std_logic_vector(0 to NLANE-1);
    signal mgr_lane_up                  : std_logic_vector(0 to NLANE-1);
    signal mgr_tx_out_clk               : std_logic_vector(0 to NLANE-1);
    -- System Interface
    signal mgr_pll_not_locked           : std_logic;
    signal mgr_power_down               : std_logic_vector(0 to NLANE-1);
    signal mgr_loopback                 : ttcs_3ble_type(0 to NLANE-1);
    signal mgr_tx_lock                  : std_logic_vector(0 to NLANE-1);
    signal mgr_tx_resetdone             : std_logic_vector(0 to NLANE-1);
    signal mgr_rx_resetdone             : std_logic_vector(0 to NLANE-1);
    --DRP Ports
    signal mgr_drpclk                   : std_logic                         := '0';
    signal mgr_drpaddr                  : std_logic_vector(8 downto 0);
    signal mgr_drpdi                    : std_logic_vector(15 downto 0);
    signal mgr_drpdo                    : ttcs_16ble_type(0 to NLANE-1);
    signal mgr_drpen                    : std_logic;
    signal mgr_drprdy                   : std_logic_vector(0 to NLANE-1);
    signal mgr_drpwe                    : std_logic;

    signal vcc_vec                      : std_logic_vector(0 to NLANE-1) := (others => '1');

    -- Declare stimulus signals
    signal stim_si5343_ready            : std_logic     := '0';
    signal stim_si5343_daq_clk          : std_logic     := '0';
    signal stim_si5343_pci_clk          : std_logic     := '0';

--    alias init_clk_g        is <<signal uut.init_clk_g                  : std_logic>>;

begin

---------------------------------------------------------------------------------------------------------
-- Component instantiations
---------------------------------------------------------------------------------------------------------

    -------------------------------------------------------
    -- Instantiate a Merger Aurora instance.
    -------------------------------------------------------
    merger_ins : entity helix_aurora_lib.helix_aurora
    generic map(
        NLANE                           => NLANE,
        STBL_CLK_PER                    => STBL_CLK_PER, 
        LINE_RATE_VEC                   => LINE_RATE_VEC,
        USEREFCLK1                      => USEREFCLK1,   
        SIM_SPDUP                       => SIM_SPDUP)
    port map(
        -- Clocks                       
        gt_refclk0_p                    => mgr_gt_refclk_p,
        gt_refclk0_n                    => mgr_gt_refclk_n,
        gt_refclk1_p                    => mgr_gt_refclk_p,
        gt_refclk1_n                    => mgr_gt_refclk_n,
        init_clk                        => mgr_init_clk,
        user_clk                        => mgr_user_clk,
        -- Resets
        ext_reset                       => mgr_ext_reset,
        -- AXI TX Interface
        s_axi_tx_tdata                  => mgr_s_axi_tx_tdata,
        s_axi_tx_tkeep                  => mgr_s_axi_tx_tkeep,
        s_axi_tx_tvalid                 => mgr_s_axi_tx_tvalid,
        s_axi_tx_tready                 => mgr_s_axi_tx_tready,
        s_axi_tx_tlast                  => mgr_s_axi_tx_tlast,
        -- AXI RX Interface
        m_axi_rx_tdata                  => mgr_m_axi_rx_tdata,
        m_axi_rx_tkeep                  => mgr_m_axi_rx_tkeep,
        m_axi_rx_tvalid                 => mgr_m_axi_rx_tvalid,
        m_axi_rx_tlast                  => mgr_m_axi_rx_tlast,
        -- Native Flow Control TX Interface
        s_axi_nfc_req                   => mgr_s_axi_nfc_req,
        s_axi_nfc_nb                    => mgr_s_axi_nfc_nb ,
        s_axi_nfc_ack                   => mgr_s_axi_nfc_ack,
        -- Native Flow Control RX Interface
        m_axi_rx_snf                    => mgr_m_axi_rx_snf   ,
        m_axi_rx_fc_nb                  => mgr_m_axi_rx_fc_nb ,
        --CRC  status signals
        crc_pass_fail_n                 => mgr_crc_pass_fail_n,
        crc_valid                       => mgr_crc_valid      ,
        -- Error Detection Interface
        frame_err                       => mgr_frame_err ,
        hard_err                        => mgr_hard_err  ,
        soft_err                        => mgr_soft_err  ,
        channel_up                      => mgr_channel_up,
        lane_up                         => mgr_lane_up   ,
        -- System Interface
        tx_out_clk                      => mgr_tx_out_clk,
        pll_not_locked                  => mgr_pll_not_locked,
        power_down                      => mgr_power_down,
        loopback                        => mgr_loopback,
        tx_lock                         => mgr_tx_lock,
        tx_resetdone                    => mgr_tx_resetdone,
        rx_resetdone                    => mgr_rx_resetdone,
        qpll_status                     => open,
        --DRP Ports
        drpclk                          => mgr_drpclk,
        drpaddr                         => mgr_drpaddr,
        drpdi                           => mgr_drpdi,
        drpdo                           => mgr_drpdo,
        drpen                           => mgr_drpen,
        drprdy                          => mgr_drprdy,
        drpwe                           => mgr_drpwe,
        -- GT Serial I/O
        rxp                             => mgr_rxp,
        rxn                             => mgr_rxn,
        txp                             => mgr_txp,
        txn                             => mgr_txn
    );

    mgr_framing_ins : entity helix_aurora_lib.helix_framing
    generic map(
        NLANE                            => NLANE)
    port map(       
        user_clk                         => mgr_user_clk,
        -- Resets       
        tx_resetdone                     => mgr_tx_resetdone,
        rx_resetdone                     => mgr_rx_resetdone,
        --CRC  status signals
        crc_pass_fail_n                  => mgr_crc_pass_fail_n,
        crc_valid                        => mgr_crc_valid,
        -- Error Detection Interface   
        frame_err                        => mgr_frame_err,
        hard_err                         => mgr_hard_err,
        soft_err                         => mgr_soft_err,
        channel_up                       => mgr_channel_up,
        lane_up                          => mgr_lane_up,
        tx_lock                          => mgr_tx_lock,
        -- AXI TX Interface                
        s_axi_tx_tdata                   => mgr_s_axi_tx_tdata,
        s_axi_tx_tkeep                   => mgr_s_axi_tx_tkeep,
        s_axi_tx_tvalid                  => mgr_s_axi_tx_tvalid,
        s_axi_tx_tready                  => mgr_s_axi_tx_tready,
        s_axi_tx_tlast                   => mgr_s_axi_tx_tlast,
        -- AXI RX Interface                
        m_axi_rx_tdata                   => mgr_m_axi_rx_tdata,
        m_axi_rx_tkeep                   => mgr_m_axi_rx_tkeep,
        m_axi_rx_tvalid                  => mgr_m_axi_rx_tvalid,
        m_axi_rx_tlast                   => mgr_m_axi_rx_tlast,
        -- Native Flow Control TX Interface
        s_axi_nfc_req                    => mgr_s_axi_nfc_req,
        s_axi_nfc_nb                     => mgr_s_axi_nfc_nb ,
        s_axi_nfc_ack                    => mgr_s_axi_nfc_ack,
        -- Native Flow Control RX Interface
        m_axi_rx_snf                     => mgr_m_axi_rx_snf  ,
        m_axi_rx_fc_nb                   => mgr_m_axi_rx_fc_nb
    );


---------------------------------------------------------------------------------------------------------
-- Concurrent statements
---------------------------------------------------------------------------------------------------------

    --free running clock for reset
    mgr_init_clk <= not mgr_init_clk after FRHPER;


    -- reference/system clock
    stim_si5343_ready <= '0', '1' after SI5343_LKTM;

    stim_clk_pcs : process(all)
    begin
        if stim_si5343_ready then
            stim_si5343_daq_clk <= not stim_si5343_daq_clk after DAQHPER;
            stim_si5343_pci_clk <= not stim_si5343_pci_clk after PCIHPER;
        else
            stim_si5343_daq_clk <= '0';
            stim_si5343_pci_clk <= '0';
        end if;
    end process;

    mgr_gt_refclk_p <= stim_si5343_pci_clk;
    mgr_gt_refclk_n <= not stim_si5343_pci_clk;

    mgr_user_clk <= mgr_tx_out_clk;


    -- resets must be asserted for at least six clocks
    mgr_ext_reset <= '1', '0' after SI5343_LKTM, '1' after 100 us, '0' after 101 us;

    mgr_power_down        <= (others => '0');
    mgr_loopback          <= (others => (others => '0'));

    mgr_drpclk            <= not mgr_drpclk after FRHPER;
    mgr_drpaddr           <= (others => '0');
    mgr_drpdi             <= (others => '0');
    mgr_drpen             <= '0';
    mgr_drpwe             <= '0';
    mgr_pll_not_locked    <= '0';

end behave;