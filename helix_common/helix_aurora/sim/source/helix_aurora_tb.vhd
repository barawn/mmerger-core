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

entity helix_aurora_tb is
end helix_aurora_tb;

architecture behave of helix_aurora_tb is

    constant FRPER                      : time                                  := 20 ns;
    constant FRHPER                     : time                                  := FRPER/2;
    constant DAQPER                     : time                                  := 12.5 ns;
    constant DAQHPER                    : time                                  := DAQPER/2;
    constant PCIPER                     : time                                  := 6.25 ns;
    constant PCIHPER                    : time                                  := PCIPER/2;
    constant SI5343_LKTM                : time                                  := 300 ns;
    constant NLANE                      : natural                               := 4;
    constant LINE_RATE_VEC              : unsigned(0 to NLANE-1)                := "1000";
    constant USEREFCLK1                 : boolean                               := TRUE;
    constant SIM_SPDUP                  : boolean                               := FALSE;--Channel/lane up are never asserted when speed-up is use!!!!!    
    constant INJECT_ERR                 : natural                               := 1;

    -- Clocks
    signal mgr_gt_refclk0_p             : std_logic;
    signal mgr_gt_refclk0_n             : std_logic;
    signal mgr_gt_refclk1_p             : std_logic;
    signal mgr_gt_refclk1_n             : std_logic;
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
    signal mgr_s_axi_tx_tuser           : std_logic_vector(0 to NLANE-1);
    -- AXI RX Interface
    signal mgr_m_axi_rx_tdata           : ttcs_16bbe_type(0 to NLANE-1);
    signal mgr_m_axi_rx_tkeep           : ttcs_2bbe_type(0 to NLANE-1);
    signal mgr_m_axi_rx_tvalid          : std_logic_vector(0 to NLANE-1);
    signal mgr_m_axi_rx_tlast           : std_logic_vector(0 to NLANE-1);
    signal mgr_m_axi_rx_tuser           : std_logic_vector(0 to NLANE-1);
    -- Native Flow Control TX Interface
    signal mgr_s_axi_tx_nfc_xoff        : std_logic_vector(0 to NLANE-1);
    -- Native Flow Control RX Interface
    --signal mgr_m_axi_rx_nfc_xoff        : std_logic_vector(0 to NLANE-1);
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
    signal mgr_qpll_status                  : std_logic_vector(4 downto 0);
    --DRP Ports
    signal mgr_drpclk                   : std_logic                         := '0';
    signal mgr_drpaddr                  : std_logic_vector(8 downto 0);
    signal mgr_drpdi                    : std_logic_vector(15 downto 0);
    signal mgr_drpdo                    : ttcs_16ble_type(0 to NLANE-1);
    signal mgr_drpen                    : std_logic;
    signal mgr_drprdy                   : std_logic_vector(0 to NLANE-1);
    signal mgr_drpwe                    : std_logic;
    -- GT Serial I/O
    signal mgr_rxp                      : std_logic_vector(0 to NLANE-1);
    signal mgr_rxn                      : std_logic_vector(0 to NLANE-1);
    signal mgr_txp                      : std_logic_vector(0 to NLANE-1);
    signal mgr_txn                      : std_logic_vector(0 to NLANE-1);

    -- Clocks
    signal feb_gt_refclk0_p             : std_logic;
    signal feb_gt_refclk0_n             : std_logic;
    signal feb_gt_refclk1_p             : std_logic;
    signal feb_gt_refclk1_n             : std_logic;
    signal feb_init_clk                 : std_logic                         := '0';
    signal feb_user_clk                 : std_logic_vector(0 to NLANE-1)    := (others => '0');--Aurora logic clock
    -- Resets
    signal feb_ext_reset              : std_logic;--free running clock reset
    -- AXI TX Interface
    signal feb_s_axi_tx_tdata           : ttcs_16bbe_type(0 to NLANE-1);
    signal feb_s_axi_tx_tkeep           : ttcs_2bbe_type(0 to NLANE-1);
    signal feb_s_axi_tx_tvalid          : std_logic_vector(0 to NLANE-1);
    signal feb_s_axi_tx_tready          : std_logic_vector(0 to NLANE-1);
    signal feb_s_axi_tx_tlast           : std_logic_vector(0 to NLANE-1);
    signal feb_s_axi_tx_tuser           : std_logic_vector(0 to NLANE-1);
    -- AXI RX Interface
    signal feb_m_axi_rx_tdata           : ttcs_16bbe_type(0 to NLANE-1);
    signal feb_m_axi_rx_tkeep           : ttcs_2bbe_type(0 to NLANE-1);
    signal feb_m_axi_rx_tvalid          : std_logic_vector(0 to NLANE-1);
    signal feb_m_axi_rx_tlast           : std_logic_vector(0 to NLANE-1);
    signal feb_m_axi_rx_tuser           : std_logic_vector(0 to NLANE-1);
    -- Native Flow Control TX Interface
    signal feb_s_axi_tx_nfc_xoff     : std_logic_vector(0 to NLANE-1);
    -- Native Flow Control RX Interface
    --signal feb_m_axi_rx_nfc_xoff     : std_logic_vector(0 to NLANE-1);
    --CRC  status signals
    signal feb_crc_pass_fail_n          : std_logic_vector(0 to NLANE-1);
    signal feb_crc_valid                : std_logic_vector(0 to NLANE-1);
    -- Error Detection Interface
    signal feb_frame_err                : std_logic_vector(0 to NLANE-1);
    signal feb_hard_err                 : std_logic_vector(0 to NLANE-1);
    signal feb_soft_err                 : std_logic_vector(0 to NLANE-1);
    signal feb_channel_up               : std_logic_vector(0 to NLANE-1);
    signal feb_lane_up                  : std_logic_vector(0 to NLANE-1);
    -- System Interface
    signal feb_tx_out_clk               : std_logic_vector(0 to NLANE-1);
    signal feb_pll_not_locked           : std_logic;
    signal feb_power_down               : std_logic_vector(0 to NLANE-1);
    signal feb_loopback                 : ttcs_3ble_type(0 to NLANE-1);
    signal feb_tx_lock                  : std_logic_vector(0 to NLANE-1);
    signal feb_tx_resetdone             : std_logic_vector(0 to NLANE-1);
    signal feb_rx_resetdone             : std_logic_vector(0 to NLANE-1);
    signal feb_qpll_status                  : std_logic_vector(4 downto 0);
    --DRP Ports
    signal feb_drpclk                   : std_logic                         := '0';
    signal feb_drpaddr                  : std_logic_vector(8 downto 0);
    signal feb_drpdi                    : std_logic_vector(15 downto 0);
    signal feb_drpdo                    : ttcs_16ble_type(0 to NLANE-1);
    signal feb_drpen                    : std_logic;
    signal feb_drprdy                   : std_logic_vector(0 to NLANE-1);
    signal feb_drpwe                    : std_logic;
    -- GT Serial I/O
    signal feb_rxp                      : std_logic_vector(0 to NLANE-1);
    signal feb_rxn                      : std_logic_vector(0 to NLANE-1);
    signal feb_txp                      : std_logic_vector(0 to NLANE-1);
    signal feb_txn                      : std_logic_vector(0 to NLANE-1);

    --signal mgr_ll_op_data               : ttcs_16bbe_type(0 to NLANE-1);
    --signal mgr_ll_op_rem                : std_logic_vector(0 to NLANE-1);
    --signal mgr_ll_op_src_rdy_n          : std_logic_vector(0 to NLANE-1);
    --signal mgr_ll_op_sof_n              : std_logic_vector(0 to NLANE-1);
    --signal mgr_ll_op_eof_n              : std_logic_vector(0 to NLANE-1);
    --signal mgr_ll_ip_dst_rdy_n          : std_logic_vector(0 to NLANE-1);
    --
    --signal mgr_ll_ip_data               : ttcs_16bbe_type(0 to NLANE-1);
    --signal mgr_ll_ip_rem                : std_logic_vector(0 to NLANE-1);
    --signal mgr_ll_ip_src_rdy_n          : std_logic_vector(0 to NLANE-1);
    --signal mgr_ll_ip_sof_n              : std_logic_vector(0 to NLANE-1);
    --signal mgr_ll_ip_eof_n              : std_logic_vector(0 to NLANE-1);
    --signal mgr_ll_op_dst_rdy_n          : std_logic_vector(0 to NLANE-1);
    --signal mgr_frm_err                  : ttcs_8ble_type(0 to NLANE-1);

    signal vcc_vec                      : std_logic_vector(0 to NLANE-1) := (others => '1');

    -- Declare stimulus signals
    signal stim_si5343_ready                : std_logic     := '0';
    signal stim_si5343_daq_clk              : std_logic     := '0';
    signal stim_si5343_pci_clk              : std_logic     := '0';

    alias mgr_inject_err is <<signal mgr_framing_ins.inject_err : std_logic_vector(0 to NLANE-1)>>;
    alias feb_inject_err is <<signal feb_framing_ins.inject_err : std_logic_vector(0 to NLANE-1)>>;

begin

---------------------------------------------------------------------------------------------------------
-- Component instantiations
---------------------------------------------------------------------------------------------------------

    -------------------------------------------------------
    -- Instantiate the unit under test.
    -------------------------------------------------------
    merger_ins : entity work.helix_aurora
    generic map(
        NLANE                           => NLANE,
        LINE_RATE_VEC                   => LINE_RATE_VEC,
        USEREFCLK1                      => USEREFCLK1,
        SIM_SPDUP                       => SIM_SPDUP)
    port map(
        -- Clocks                          -- Clocks
        gt_refclk0_p                    => mgr_gt_refclk0_p,
        gt_refclk0_n                    => mgr_gt_refclk0_n,
        gt_refclk1_p                    => mgr_gt_refclk1_p,
        gt_refclk1_n                    => mgr_gt_refclk1_n,
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
        s_axi_tx_tuser                  => mgr_s_axi_tx_tuser,
        -- AXI RX Interface
        m_axi_rx_tdata                  => mgr_m_axi_rx_tdata,
        m_axi_rx_tkeep                  => mgr_m_axi_rx_tkeep,
        m_axi_rx_tvalid                 => mgr_m_axi_rx_tvalid,
        m_axi_rx_tlast                  => mgr_m_axi_rx_tlast,
        m_axi_rx_tuser                  => mgr_m_axi_rx_tuser,
        -- Native Flow Control TX Interface
        s_axi_tx_nfc_xoff               => mgr_s_axi_tx_nfc_xoff,
        -- Native Flow Control RX Interface
        --m_axi_rx_nfc_xoff               => mgr_m_axi_rx_nfc_xoff,
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
        power_down                      => mgr_power_down    ,
        loopback                        => mgr_loopback      ,
        tx_lock                         => mgr_tx_lock       ,
        tx_resetdone                    => mgr_tx_resetdone  ,
        rx_resetdone                    => mgr_rx_resetdone  ,
        qpll_status                     => mgr_qpll_status,
        --DRP Ports
        drpclk                          => mgr_drpclk ,
        drpaddr                         => mgr_drpaddr,
        drpdi                           => mgr_drpdi  ,
        drpdo                           => mgr_drpdo  ,
        drpen                           => mgr_drpen  ,
        drprdy                          => mgr_drprdy ,
        drpwe                           => mgr_drpwe  ,
        -- GT Serial I/O
        rxp                             => mgr_rxp ,
        rxn                             => mgr_rxn ,
        txp                             => mgr_txp ,
        txn                             => mgr_txn
    );

    frnt_end_ins : entity work.helix_aurora
    generic map(
        NLANE                           => NLANE,
        LINE_RATE_VEC                   => LINE_RATE_VEC,
        USEREFCLK1                      => USEREFCLK1,
        SIM_SPDUP                       => SIM_SPDUP)
    port map(
        -- Clocks                          -- Clocks
        gt_refclk0_p                    => feb_gt_refclk0_p,
        gt_refclk0_n                    => feb_gt_refclk0_n,
        gt_refclk1_p                    => feb_gt_refclk1_p,
        gt_refclk1_n                    => feb_gt_refclk1_n,
        init_clk                        => feb_init_clk,
        user_clk                        => feb_user_clk,
        -- Resets
        ext_reset                       => feb_ext_reset,
        -- AXI TX Interface
        s_axi_tx_tdata                  => feb_s_axi_tx_tdata,
        s_axi_tx_tkeep                  => feb_s_axi_tx_tkeep,
        s_axi_tx_tvalid                 => feb_s_axi_tx_tvalid,
        s_axi_tx_tready                 => feb_s_axi_tx_tready,
        s_axi_tx_tlast                  => feb_s_axi_tx_tlast,
        s_axi_tx_tuser                  => feb_s_axi_tx_tuser,
        -- AXI RX Interface
        m_axi_rx_tdata                  => feb_m_axi_rx_tdata,
        m_axi_rx_tkeep                  => feb_m_axi_rx_tkeep,
        m_axi_rx_tvalid                 => feb_m_axi_rx_tvalid,
        m_axi_rx_tlast                  => feb_m_axi_rx_tlast,
        m_axi_rx_tuser                  => feb_m_axi_rx_tuser,
        -- Native Flow Control TX Interface
        s_axi_tx_nfc_xoff               => feb_s_axi_tx_nfc_xoff,
        -- Native Flow Control RX Interface
        --m_axi_rx_nfc_xoff               => feb_m_axi_rx_nfc_xoff,
        --CRC  status signals
        crc_pass_fail_n                 => feb_crc_pass_fail_n,
        crc_valid                       => feb_crc_valid      ,
        -- Error Detection Interface
        frame_err                       => feb_frame_err ,
        hard_err                        => feb_hard_err  ,
        soft_err                        => feb_soft_err  ,
        channel_up                      => feb_channel_up,
        lane_up                         => feb_lane_up   ,
        -- System Interface
        tx_out_clk                      => feb_tx_out_clk,
        pll_not_locked                  => feb_pll_not_locked,
        power_down                      => feb_power_down    ,
        loopback                        => feb_loopback      ,
        tx_lock                         => feb_tx_lock       ,
        tx_resetdone                    => feb_tx_resetdone  ,
        rx_resetdone                    => feb_rx_resetdone  ,
        qpll_status                     => feb_qpll_status,
        --DRP Ports
        drpclk                          => feb_drpclk ,
        drpaddr                         => feb_drpaddr,
        drpdi                           => feb_drpdi  ,
        drpdo                           => feb_drpdo  ,
        drpen                           => feb_drpen  ,
        drprdy                          => feb_drprdy ,
        drpwe                           => feb_drpwe  ,
        -- GT Serial I/O
        rxp                             => feb_rxp ,
        rxn                             => feb_rxn ,
        txp                             => feb_txp ,
        txn                             => feb_txn
    );

    mgr_framing_ins : entity work.helix_framing
    generic map(
        NLANE                            => NLANE)
    port map(       
        user_clk                         => mgr_user_clk,
        -- Resets       
        tx_resetdone                     => mgr_tx_resetdone,
        rx_resetdone                     => mgr_rx_resetdone,
        --CRC  status signals
        crc_pass_fail_n                  => mgr_crc_pass_fail_n,
        crc_valid                        => mgr_crc_valid      ,
        -- Error Detection Interface   
        frame_err                        => mgr_frame_err ,
        hard_err                         => mgr_hard_err  ,
        soft_err                         => mgr_soft_err  ,
        channel_up                       => mgr_channel_up,
        lane_up                          => mgr_lane_up   ,
        tx_lock                          => mgr_tx_lock       ,
        -- AXI TX Interface                
        s_axi_tx_tdata                   => mgr_s_axi_tx_tdata,
        s_axi_tx_tkeep                   => mgr_s_axi_tx_tkeep,
        s_axi_tx_tvalid                  => mgr_s_axi_tx_tvalid,
        s_axi_tx_tready                  => mgr_s_axi_tx_tready,
        s_axi_tx_tlast                   => mgr_s_axi_tx_tlast,
        s_axi_tx_tuser                   => mgr_s_axi_tx_tuser,
        -- AXI RX Interface                
        m_axi_rx_tdata                   => mgr_m_axi_rx_tdata,
        m_axi_rx_tkeep                   => mgr_m_axi_rx_tkeep,
        m_axi_rx_tvalid                  => mgr_m_axi_rx_tvalid,
        m_axi_rx_tlast                   => mgr_m_axi_rx_tlast,
        m_axi_rx_tuser                   => mgr_m_axi_rx_tuser,
        -- Native Flow Control TX Interface
        s_axi_tx_nfc_xoff                => mgr_s_axi_tx_nfc_xoff
        -- Native Flow Control RX Interface
        --m_axi_rx_nfc_xoff                => mgr_m_axi_rx_nfc_xoff
    );

    feb_framing_ins : entity work.helix_framing
    generic map(
        NLANE                            => NLANE)
    port map(       
        user_clk                         => feb_user_clk,
        -- Resets                           
        tx_resetdone                     => feb_tx_resetdone,
        rx_resetdone                     => feb_rx_resetdone,
        --CRC  status signals
        crc_pass_fail_n                  => feb_crc_pass_fail_n,
        crc_valid                        => feb_crc_valid,
        -- Error Detection Interface     
        frame_err                        => feb_frame_err,
        hard_err                         => feb_hard_err,
        soft_err                         => feb_soft_err,
        channel_up                       => feb_channel_up,
        lane_up                          => feb_lane_up,
        tx_lock                          => feb_tx_lock,
        -- AXI TX Interface                 
        s_axi_tx_tdata                   => feb_s_axi_tx_tdata,
        s_axi_tx_tkeep                   => feb_s_axi_tx_tkeep,
        s_axi_tx_tvalid                  => feb_s_axi_tx_tvalid,
        s_axi_tx_tready                  => feb_s_axi_tx_tready,
        s_axi_tx_tlast                   => feb_s_axi_tx_tlast,
        s_axi_tx_tuser                   => feb_s_axi_tx_tuser,
        -- AXI RX Interface                 
        m_axi_rx_tdata                   => feb_m_axi_rx_tdata,
        m_axi_rx_tkeep                   => feb_m_axi_rx_tkeep,
        m_axi_rx_tvalid                  => feb_m_axi_rx_tvalid,
        m_axi_rx_tlast                   => feb_m_axi_rx_tlast,
        m_axi_rx_tuser                   => feb_m_axi_rx_tuser,
        -- Native Flow Control TX Interface
        s_axi_tx_nfc_xoff                => feb_s_axi_tx_nfc_xoff
        -- Native Flow Control RX Interface
        --m_axi_rx_nfc_xoff                => feb_m_axi_rx_nfc_xoff
    );



---------------------------------------------------------------------------------------------------------
-- Concurrent statements
---------------------------------------------------------------------------------------------------------

    --free running clock for reset
    mgr_init_clk <= not mgr_init_clk after FRHPER;
    feb_init_clk <= not feb_init_clk after FRHPER;

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

    mgr_gt_refclk0_p <= stim_si5343_daq_clk;
    mgr_gt_refclk0_n <= not stim_si5343_daq_clk;
    mgr_gt_refclk1_p <= stim_si5343_pci_clk;
    mgr_gt_refclk1_n <= not stim_si5343_pci_clk;

    feb_gt_refclk0_p <= stim_si5343_daq_clk;
    feb_gt_refclk0_n <= not stim_si5343_daq_clk;
    feb_gt_refclk1_p <= stim_si5343_pci_clk;
    feb_gt_refclk1_n <= not stim_si5343_pci_clk;

    --Aurora logic clock
    clk_loop_gen : for I in 0 to NLANE-1 generate
        clk_bit_gen : if LINE_RATE_VEC(I) generate
            mgr_user_clk(I) <= mgr_tx_out_clk(I);
            feb_user_clk(I) <= feb_tx_out_clk(I);
        else generate          
            mgr_user_clk(I) <= stim_si5343_daq_clk;
            feb_user_clk(I) <= stim_si5343_daq_clk;
        end generate;
    end generate;

    -- resets must be asserted for at least six clocks
    mgr_ext_reset <= '1', '0' after SI5343_LKTM, '1' after 100 us, '0' after 101 us;

    feb_ext_reset <= '1', '0' after SI5343_LKTM, '1' after 100 us, '0' after 101 us;

    feb_rxp <= mgr_txp;
    feb_rxn <= mgr_txn;
    mgr_rxp <= feb_txp;
    mgr_rxn <= feb_txn;

    --mgr_s_axi_tx_tdata    <= (others => (others => '0'));
    --mgr_s_axi_tx_tkeep    <= (others => (others => '0'));
    --mgr_s_axi_tx_tvalid   <= (others => '0');
    --mgr_s_axi_tx_tlast    <= (others => '0');
    --
    --mgr_s_axi_nfc_req     <= (others => '0');
    --mgr_s_axi_nfc_nb      <= (others => (others => '0'));

    mgr_power_down        <= (others => '0');
    mgr_loopback          <= (others => (others => '0'));

    mgr_drpclk            <= not mgr_drpclk after FRHPER;
    mgr_drpaddr           <= (others => '0');
    mgr_drpdi             <= (others => '0');
    mgr_drpen             <= '0';
    mgr_drpwe             <= '0';
    mgr_pll_not_locked    <= '0';

    --feb_s_axi_tx_tdata   <= (others => (others => '0'));
    --feb_s_axi_tx_tkeep   <= (others => (others => '0'));
    --feb_s_axi_tx_tvalid  <= (others => '0');
    --feb_s_axi_tx_tlast   <= (others => '0');
    --
    --feb_s_axi_nfc_req    <= (others => '0');
    --feb_s_axi_nfc_nb     <= (others => (others => '0'));

    feb_power_down       <= (others => '0');
    feb_loopback         <= (others => (others => '0'));

    feb_drpclk            <= not mgr_drpclk after FRHPER;
    feb_drpaddr           <= (others => '0');
    feb_drpdi             <= (others => '0');
    feb_drpen             <= '0';
    feb_drpwe             <= '0';
    feb_pll_not_locked    <= '0';

    mgr_inject_err <= (others => '0'), (others => '1') after 2200 us;
    feb_inject_err <= (others => '0'), (others => '1') after 2200 us;

end behave;