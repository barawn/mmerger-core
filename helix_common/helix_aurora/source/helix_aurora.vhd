--*********************************************************************************
-- Indiana University
-- Center for Exploration of Energy and Matter (CEEM)
--
-- Project: HELIX
--
-- Author:  Brandon Kunkler
--
-- Date:    11/09/2018
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
-- Aurora 8b/10b Interface modified for HELIX.
-- Up to 12 lanes could be used with the addition of generate statements to map the
-- east/west reference clocks to the correct locations (Vivado cannot automatically
-- do this for 7-series parts?). For now, connect PLL0 to GTREFCLK0 and PLL1 to
-- GTREFCLK1. Then, if GTREFCLK1 is used switch the connection in the transceiver
-- (using RX/TXRXSYSCLKSEL).
-- The detector merger board uses two different line rates. Use a vector to select
-- between the line rates (with functions to specify values).
--
-- Known Issues:
-- The common/PLL reset is only correct for one PLL.
--*********************************************************************************
 library ieee;
     use ieee.std_logic_1164.all;
     use ieee.std_logic_misc.all;
     use ieee.numeric_std.all;
library work;
    use work.ttcs_intfc_pkg.all;
-- synthesis translate_off
library unisim;
    use unisim.vcomponents.all;
-- synthesis translate_on

entity helix_aurora is
generic(
    NLANE                           : natural range 1 to 4          := 4;
    STBL_CLK_PER                    : integer                       := 20;  --Period of the stable clock driving this state-machine, unit is [ns]
    LINE_RATE_VEC                   : unsigned(0 to NLANE-1)        := (others => '0');
    USEREFCLK1                      : boolean                       := FALSE;--a transceiver uses MGTREFCLK1
    SIM_SPDUP                       : boolean                       := FALSE);
port(
    -- Clocks
    gt_refclk0_p                    : in  std_logic;
    gt_refclk0_n                    : in  std_logic;
    gt_refclk1_p                    : in  std_logic;
    gt_refclk1_n                    : in  std_logic;
    init_clk                        : in  std_logic;--free running clock for reset
    user_clk                        : in  std_logic_vector(0 to NLANE-1);--Aurora logic clock
    -- Resets
    ext_reset                       : in std_logic;
    -- AXI TX Interface
    s_axi_tx_tdata                  : in  ttcs_16bbe_type(0 to NLANE-1);
    s_axi_tx_tkeep                  : in  ttcs_2bbe_type(0 to NLANE-1);
    s_axi_tx_tvalid                 : in  std_logic_vector(0 to NLANE-1);
    s_axi_tx_tready                 : out std_logic_vector(0 to NLANE-1);
    s_axi_tx_tlast                  : in  std_logic_vector(0 to NLANE-1);
    s_axi_tx_tuser                  : in  std_logic_vector(0 to NLANE-1);
    -- AXI RX Interface
    m_axi_rx_tdata                  : out ttcs_16bbe_type(0 to NLANE-1);
    m_axi_rx_tkeep                  : out ttcs_2bbe_type(0 to NLANE-1);
    m_axi_rx_tvalid                 : out std_logic_vector(0 to NLANE-1);
    m_axi_rx_tlast                  : out std_logic_vector(0 to NLANE-1);
    m_axi_rx_tuser                  : out std_logic_vector(0 to NLANE-1);
    -- Native Flow Control TX Interface
    s_axi_tx_nfc_xoff               : in std_logic_vector(0 to NLANE-1); --transmit XOFF to source channel
    --CRC  status signals
    crc_pass_fail_n                 : out std_logic_vector(0 to NLANE-1);
    crc_valid                       : out std_logic_vector(0 to NLANE-1);
    -- Error Detection Interface
    frame_err                       : out std_logic_vector(0 to NLANE-1);
    hard_err                        : out std_logic_vector(0 to NLANE-1);
    soft_err                        : out std_logic_vector(0 to NLANE-1);
    channel_up                      : out std_logic_vector(0 to NLANE-1);
    lane_up                         : out std_logic_vector(0 to NLANE-1);
    -- System Interface
    tx_out_clk                      : out std_logic_vector(0 to NLANE-1);
    pll_not_locked                  : in  std_logic;
    power_down                      : in  std_logic_vector(0 to NLANE-1);
    loopback                        : in  ttcs_3ble_type(0 to NLANE-1);
    tx_lock                         : out std_logic_vector(0 to NLANE-1);
    tx_resetdone                    : out std_logic_vector(0 to NLANE-1);
    rx_resetdone                    : out std_logic_vector(0 to NLANE-1);
    qpll_status                     : out std_logic_vector(4 downto 0);
    --DRP Ports
    drpclk                          : in  std_logic;
    drpaddr                         : in  std_logic_vector(8 downto 0);
    drpdi                           : in  std_logic_vector(15 downto 0);
    drpdo                           : out ttcs_16ble_type(0 to NLANE-1);
    drpen                           : in  std_logic;
    drprdy                          : out std_logic_vector(0 to NLANE-1);
    drpwe                           : in  std_logic;
    -- GT Serial I/O
    rxp                             : in  std_logic_vector(0 to NLANE-1);
    rxn                             : in  std_logic_vector(0 to NLANE-1);
    txp                             : out std_logic_vector(0 to NLANE-1);
    txn                             : out std_logic_vector(0 to NLANE-1));
end helix_aurora;


architecture behave of helix_aurora is


    component IBUFDS_GTE2
    port (
        O                           : out std_ulogic;
        ODIV2                       : out std_ulogic;
        CEB                         : in  std_ulogic;
        I                           : in  std_ulogic;
        IB                          : in  std_ulogic);
    end component;

    component BUFG
    port(
        O                           : out std_ulogic;
        I                           : in  std_ulogic);
    end component;

    constant PLL0REFCLKSEL          : std_logic_vector(2 downto 0)          := "001";
    constant PLL1REFCLKSEL          : std_logic_vector(2 downto 0)          := "010";
    constant XOFF_VAL               : std_logic_vector(3 downto 0)          := X"F";
    constant XON_VAL                : std_logic_vector(3 downto 0)          := X"0";
    constant CQD                    : time                                  := 1 ns; -- clock to Q delay for Aurora simulation


    signal common_reset_vec         : std_logic_vector(0 to NLANE-1);
    -- COMMON PORTS
    signal common_pll0refclklost    : std_logic;
    signal common_pll1refclklost    : std_logic;
    signal gt0_refclklost           : std_logic_vector(0 to NLANE-1);
    signal common_pll0_lock         : std_logic;
    signal common_pll1_lock         : std_logic;
    signal gt0_common_lock          : std_logic_vector(0 to NLANE-1);
    -- Channel - Ref Clock Ports
    signal gt0_pll0outclk           : std_logic;
    signal gt0_pll1outclk           : std_logic;
    signal gt0_pll0outrefclk        : std_logic;
    signal gt0_pll1outrefclk        : std_logic;
    -- COMMON PORTS
    signal gt_refclk0               : std_logic;
    signal gt_refclk1               : std_logic;
    signal tx_out_clk_i             : std_logic_vector(0 to NLANE-1);
    --signal sync_clk                 : std_logic_vector(0 to NLANE-1);

    signal fr_gt_reset              : std_logic_vector(0 to NLANE-1);--free running clock logic reset
    signal ur_ch_reset              : std_logic_vector(0 to NLANE-1);--free running clock gt reset

    signal rx_new_pkt_d             : std_logic_vector(0 to NLANE-1);
    signal rx_new_pkt_q             : std_logic_vector(0 to NLANE-1);

    signal s_axi_nfc_req            : std_logic_vector(0 to NLANE-1);
    signal s_axi_nfc_nb             : ttcs_4bbe_type(0 to NLANE-1);
    signal s_axi_nfc_ack            : std_logic_vector(0 to NLANE-1);
    signal m_axi_rx_snf             : std_logic_vector(0 to NLANE-1);
    signal m_axi_rx_fc_nb           : ttcs_4bbe_type(0 to NLANE-1);
    signal nfc_xoff_q0              : std_logic_vector(0 to NLANE-1);
    signal nfc_xoff_q1              : std_logic_vector(0 to NLANE-1);
    signal nfc_xoff_re              : std_logic_vector(0 to NLANE-1);
    signal nfc_xoff_fe              : std_logic_vector(0 to NLANE-1);
    signal nfc_xoff_strt            : std_logic_vector(0 to NLANE-1);
    signal nfc_xoff_stop            : std_logic_vector(0 to NLANE-1);

    signal common_reset_bit         : std_logic;

    --signal gt_refclk1_odiv          : std_logic;

    function SIM_SPDUP_STR(SIM_SPDUP : boolean) return string is
    begin
        if SIM_SPDUP then
            return "TRUE";
        else
            return "FALSE";
        end if;
    end function;

    -- transceiver line rate
    function LINE_RATE_FUN(b : std_logic) return real is
    begin
        if b then
            return 6.4;
        else
            return 1.6;
        end if;
    end function;

    function MAX_WAIT_BYPASS_FUN(b : std_logic) return integer is
    begin
        if b then
            return 25344;
        else
            return 45824;
        end if;
    end function;

    function RX_CLK25_DIV_FUN(b : std_logic) return integer is
    begin
        if b then
            return 7;
        else
            return 4;
        end if;
    end function;

    function TX_CLK25_DIV_FUN(b : std_logic) return integer is
    begin
        if b then
            return 7;
        else
            return 4;
        end if;
    end function;

    function RXCDR_CFG_FUN(b : std_logic) return bit_vector is
    begin
        if b then
            return x"0000107FE406001041010";
        else
            return x"0000107FE206001041010";
        end if;
    end function;

    function RXOUT_DIV_FUN(b : std_logic) return integer is
    begin
        if b then
            return 1;
        else
            return 2;
        end if;
    end function;

    function TXOUT_DIV_FUN(b : std_logic) return integer is
    begin
        if b then
            return 1;
        else
            return 2;
        end if;
    end function;

    function RXSYSCLKSEL_FUN(b : std_logic) return std_logic_vector is
    begin
        if b then
            return "11";
        else
            return "00";
        end if;
    end function;

    function TXSYSCLKSEL_FUN(b : std_logic) return std_logic_vector is
    begin
        if b then
            return "11";
        else
            return "00";
        end if;
    end function;

begin

 --*********************************Main Body of Code**********************************

    ibufds_gte2_0_ins :  IBUFDS_GTE2
    port map (
        I                           => gt_refclk0_p,
        IB                          => gt_refclk0_n,
        CEB                         => '0',
        O                           => gt_refclk0,
        ODIV2                       => open
    );

    -- select clock source
    refclk1_gen : if USEREFCLK1 generate
        ibufds_gte2_1_ins :  IBUFDS_GTE2
        port map (
            I                       => gt_refclk1_p,
            IB                      => gt_refclk1_n,
            CEB                     => '0',
            O                       => gt_refclk1,
            ODIV2                   => open
        );
    else generate
        gt_refclk1 <= '0';
    end generate;

    -- Common Transceiver Component (PLL)
    gt_common_ins : entity work.aurora_8b10b_gt_common_wrapper
    generic map(
        WRAPPER_SIM_GTRESET_SPEEDUP => SIM_SPDUP_STR(SIM_SPDUP)) -- Set to "TRUE" to speed up sim reset
    port map(
        gt0_pll0refclksel_in        => PLL0REFCLKSEL,
        gt0_pll1refclksel_in        => PLL1REFCLKSEL,
        gt0_gtrefclk0_in            => gt_refclk0,
        gt0_gtrefclk1_in            => gt_refclk1,
        gt0_pll0lock_out            => common_pll0_lock,
        gt0_pll1lock_out            => common_pll1_lock,
        gt0_plllockdetclk_in        => init_clk,
        gt0_pll0refclklost_out      => common_pll0refclklost,
        gt0_pll1refclklost_out      => common_pll1refclklost,
        gt0_pll0outclk              => gt0_pll0outclk,
        gt0_pll1outclk              => gt0_pll1outclk,
        gt0_pll0outrefclk           => gt0_pll0outrefclk,
        gt0_pll1outrefclk           => gt0_pll1outrefclk,
        gt0_pll0reset_in            => common_reset_bit,
        gt0_pll1reset_in            => common_reset_bit
    );

    --gt_common_ins : entity work.aurora_8b10b_gt_common_wrapper
    --generic map(
    --    WRAPPER_SIM_GTRESET_SPEEDUP => "FALSE")--SIM_SPDUP_STR(SIM_SPDUP)) -- Set to "TRUE" to speed up sim reset
    --port map(
    --    gt0_gtrefclk0_in            => gt_refclk0,
    --    gt0_pll0lock_out            => quad1_common_lock_i,
    --    gt0_pll1lock_out            => quad1_common_pll1_lock_i,
    --    gt0_pll0lockdetclk_in       => init_clk,
    --    gt0_pll0refclklost_out      => gt0_pll0refclklost_i,
    --    gt0_pll0outclk_i            => gt0_pll0outclk_i,
    --    gt0_pll1outclk_i            => gt0_pll1outclk_i,
    --    gt0_pll0outrefclk_i         => gt0_pll0outrefclk_i,
    --    gt0_pll1outrefclk_i         => gt0_pll1outrefclk_i,
    --    gt0_pll0reset_in            => common_reset_vec(1)
    --);

    lane_gen : for I in 0 to NLANE-1 generate

        ---------------------------------------------------
        -- Generate a BUFG if high-rate otherwise map DAQ clock out.
        -- Always use PLL1 with and REFCLK1 with high-rate.
        ---------------------------------------------------
        tx_buf_gen : if LINE_RATE_VEC(I) generate
            gt0_refclklost(I)  <= common_pll1refclklost;
            gt0_common_lock(I) <= common_pll1_lock;
            osc_bufg : BUFG
            port map (
                O                       => tx_out_clk(I), -- 1-bit output: Clock output
                I                       => tx_out_clk_i(I)  -- 1-bit input: Clock input
            );
        else generate
            gt0_refclklost(I)  <= common_pll0refclklost;
            gt0_common_lock(I) <= common_pll0_lock;
            tx_out_clk(I) <= tx_out_clk_i(I);
        end generate;

        reset_ins : entity work.helix_aurora_reset
        port map(
            init_clk                    => init_clk,
            user_clk                    => user_clk(I),
            ext_reset                   => ext_reset, --reset on free-running clock
            gt_reset                    => fr_gt_reset(I),--GT reset on free-running clock
            chan_reset                  => ur_ch_reset(I)--Aurora/logic reset released on user_clk
        );

        ---------------------------------------------------
        -- Aurora Lane (Transceiver)
        ---------------------------------------------------
        aurora_8b10b_ins : entity work.aurora_8b10b_core
        generic map(
            -- Transceiver Parameters
            LINE_RATE                   => LINE_RATE_FUN(LINE_RATE_VEC(I)),--                1.6, -- transceiver line rate
            MAX_WAIT_BYPASS             => MAX_WAIT_BYPASS_FUN(LINE_RATE_VEC(I)),--          45824,
            RX_CLK25_DIV                => RX_CLK25_DIV_FUN(LINE_RATE_VEC(I)),--             4,
            TX_CLK25_DIV                => TX_CLK25_DIV_FUN(LINE_RATE_VEC(I)),--             4,
            RXCDR_CFG                   => RXCDR_CFG_FUN(LINE_RATE_VEC(I)),--                x"0000107FE206001041010",
            RXOUT_DIV                   => RXOUT_DIV_FUN(LINE_RATE_VEC(I)),--                2,
            TXOUT_DIV                   => TXOUT_DIV_FUN(LINE_RATE_VEC(I)),--                2,
            STABLE_CLOCK_PERIOD         => STBL_CLK_PER,  --Period of the stable clock driving this state-machine, unit is [ns]
            SIM_GTRESET_SPEEDUP         => SIM_SPDUP_STR(SIM_SPDUP),
            CC_FREQ_FACTOR              => 24,
            EXAMPLE_SIMULATION          => 0)
        port map (
            -- AXI TX Interface
            s_axi_tx_tdata              => s_axi_tx_tdata(I),
            s_axi_tx_tkeep              => s_axi_tx_tkeep(I),
            s_axi_tx_tvalid             => s_axi_tx_tvalid(I),
            s_axi_tx_tlast              => s_axi_tx_tlast(I),
            s_axi_tx_tready             => s_axi_tx_tready(I),
            -- AXI RX Interface
            m_axi_rx_tdata              => m_axi_rx_tdata(I),
            m_axi_rx_tkeep              => m_axi_rx_tkeep(I),
            m_axi_rx_tvalid             => m_axi_rx_tvalid(I),
            m_axi_rx_tlast              => m_axi_rx_tlast(I),
            -- Native Flow Control TX Interface
            s_axi_nfc_req               => s_axi_nfc_req(I),
            s_axi_nfc_nb                => s_axi_nfc_nb(I),
            s_axi_nfc_ack               => s_axi_nfc_ack(I),
            -- Native Flow Control RX Interface
            m_axi_rx_snf                => m_axi_rx_snf(I),
            m_axi_rx_fc_nb              => m_axi_rx_fc_nb(I),
            -- GT Serial I/O
            rxp                         => rxp(I),
            rxn                         => rxn(I),
            txp                         => txp(I),
            txn                         => txn(I),
            -- GT Reference Clock Interface
            gt_refclk1                  => gt_refclk1,
            -- Error Detection Interface
            frame_err                   => frame_err(I),
            -- Error Detection Interface
            hard_err                    => hard_err(I),
            soft_err                    => soft_err(I),
            -- Status
            channel_up                  => channel_up(I),
            lane_up                     => lane_up(I),
            --CRC Status
            crc_pass_fail_n             => crc_pass_fail_n(I),
            crc_valid                   => crc_valid(I),
            -- System Interface
            user_clk                    => user_clk(I),
            sync_clk                    => user_clk(I),--!sync_clk(I),
            reset                       => ur_ch_reset(I),
            sys_reset_out               => open,
            power_down                  => power_down(I),
            loopback                    => loopback(I),
            gt_reset                    => fr_gt_reset(I),
            tx_lock                     => tx_lock(I),
            init_clk_in                 => init_clk,
            pll_not_locked              => pll_not_locked,
            tx_resetdone_out            => tx_resetdone(I),
            rx_resetdone_out            => rx_resetdone(I),
            link_reset_out              => open,
            drpclk_in                   => drpclk,
            drpaddr_in                  => drpaddr,
            drpen_in                    => drpen,
            drpdi_in                    => drpdi,
            drprdy_out                  => drprdy(I),
            drpdo_out                   => drpdo(I),
            drpwe_in                    => drpwe,
            gt_common_reset_out         => common_reset_vec(I),
            -- COMMON PORTS
            gt0_pll0refclklost_in       => gt0_refclklost(I),
            quad1_common_lock_in        => gt0_common_lock(I),
            -- Channel - Ref Clock Ports
            gt0_rxsysclksel             => RXSYSCLKSEL_FUN(LINE_RATE_VEC(I)),
            gt0_txsysclksel             => TXSYSCLKSEL_FUN(LINE_RATE_VEC(I)),
            gt0_pll0outclk_in           => gt0_pll0outclk,
            gt0_pll1outclk_in           => gt0_pll1outclk,
            gt0_pll0outrefclk_in        => gt0_pll0outrefclk,
            gt0_pll1outrefclk_in        => gt0_pll1outrefclk,
            tx_out_clk                  => tx_out_clk_i(I)
        );

        rx_new_pkt_d(I)   <= '0' when ((m_axi_rx_tvalid(I) and m_axi_rx_tlast(I)) = '1') else
                             '1' when ((m_axi_rx_tvalid(I) and (not m_axi_rx_tlast(I))) = '1') else
                             rx_new_pkt_q(I);

        m_axi_rx_tuser(I) <= (not rx_new_pkt_q(I)) when ((m_axi_rx_tvalid(I) and m_axi_rx_tlast(I)) = '1') else
                          (rx_new_pkt_d(I) and (not rx_new_pkt_q(I)));

        --------------------------------------------------
        -- Start of frame (tuser in AXI) registers.
        --------------------------------------------------
        sof_pcs : process(user_clk(I))
        begin
            if (user_clk(I)'event and user_clk(I)='1') then
                if (ur_ch_reset(I) = '1') then
                    rx_new_pkt_q(I) <= '0' after CQD;
                else
                    rx_new_pkt_q(I) <= rx_new_pkt_d(I) and channel_up(I) after CQD;
                end if;
            end if;
        end process;

        --------------------------------------------------
        -- NFC XON/XOFF logic. Start by sending XOFF when
        -- FIFO is almost full. Conclude by sending XON
        -- when FIFO empties.
        --------------------------------------------------
        nfc_pcs : process(user_clk(I))
        begin
            if (user_clk(I)'event and user_clk(I)='1') then
                if (ur_ch_reset(I) = '1') then
                    nfc_xoff_q0(I) <= '0';
                    nfc_xoff_q1(I) <= '0';
                    nfc_xoff_re(I) <= '0';
                    nfc_xoff_fe(I) <= '0';
                    nfc_xoff_strt(I) <= '0';
                    nfc_xoff_stop(I) <= '0';
                    s_axi_nfc_req(I) <= '0';
                    s_axi_nfc_nb(I)  <= XON_VAL;
                    --m_axi_rx_nfc_xoff(I) <= '0';
                else
                    nfc_xoff_q0(I) <= s_axi_tx_nfc_xoff(I);
                    nfc_xoff_q1(I) <= nfc_xoff_q0(I);
                    nfc_xoff_re(I) <= nfc_xoff_q0(I) and (not nfc_xoff_q1(I));--rising edge
                    nfc_xoff_fe(I) <= (not nfc_xoff_q0(I)) and nfc_xoff_q1(I);--falling edge
                    -- XOFF transmit logic ------------------
                    if (s_axi_nfc_ack(I) and nfc_xoff_strt(I)) = '1' then--clear values when ack occurs                    
                        nfc_xoff_strt(I) <= '0';
                    else            
                        if nfc_xoff_re(I) = '1' then-- rising edge starts XOFF cycle
                            nfc_xoff_strt(I) <= '1';
                        end if;
                    end if;
                    -- XOFF start logic
                    if (s_axi_nfc_ack(I) and (not nfc_xoff_strt(I)) and nfc_xoff_stop(I)) = '1' then--clear values when ack occurs
                        nfc_xoff_stop(I) <= '0';
                    else            
                        if nfc_xoff_fe(I) = '1' then-- falling edge concludes XOFF cycle
                            nfc_xoff_stop(I) <= '1';
                        end if;
                    end if;
                    -- XOFF end logic
                    if s_axi_nfc_ack(I) = '1' then--clear values when ack occurs                    
                        s_axi_nfc_req(I) <= '0' ;
                        s_axi_nfc_nb(I)  <= XON_VAL;--first ack XOFF, second XON
                    else            
                        -- need to request at start and stop
                        s_axi_nfc_req(I) <= nfc_xoff_strt(I) or nfc_xoff_stop(I);
                        if nfc_xoff_strt(I) = '1' then
                            s_axi_nfc_nb(I)  <= XOFF_VAL;--first value always XOFF
                        end if;
                    end if;
                    -- XOFF receive logic ---------------
                    --if m_axi_rx_snf(I) = '1' then
                    --    m_axi_rx_nfc_xoff(I) <= '1' when m_axi_rx_fc_nb(I) = XOFF_VAL else '0';
                    --end if;
                end if;
            end if;
        end process;

    end generate;

    --sync_clk  <= user_clk;

    init_pipe_pcs : process(init_clk)
    begin
        if init_clk'event and init_clk='1' then
            common_reset_bit <= OR_REDUCE(common_reset_vec);
            qpll_status <= common_reset_bit & common_pll1refclklost & common_pll0refclklost & common_pll1_lock & common_pll0_lock;
        end if;
    end process;

 end behave;
