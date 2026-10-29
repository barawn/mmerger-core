--*********************************************************************************
-- Indiana University Cyclotron Facility (IUCF)
--
-- Project: HELIX
--
-- Author:  Brandon Kunkler
--
-- Date:    04/28/2016
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
-- Initialization state machine, timing and synchronization logic for HELIX FPGAs.
--
--Start with high-priority resets and disable as functions are successfully
-- initialized. Start with initialization of clock, select I/O, and transceivers,
-- then move to logic.
--*********************************************************************************
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_misc.all;
--synthesis_translate off
library unisim;
    use unisim.vcomponents.all;
--synthesis_translate on


entity  det_tmg_init is
generic(
    NLANE                       : integer   := 3;--1=allow operation when no FELIX present
    USE_SPRCLK                  : boolean   := FALSE;
    INIT_MINRT                  : natural   := 2**4;
    TTCS_MINRT                  : natural   := 2**4;
    SIM_SPDUP                   : boolean   := FALSE);
port(
    hk_clk_p                    : in  std_logic;
    hk_clk_n                    : in  std_logic;
    spare_clk_p                 : in  std_logic;
    spare_clk_n                 : in  std_logic;
    daq_clk                     : in  std_logic;
    pci_clk                     : in  std_logic;
    osc_clk_g                   : out std_logic;
    init_clk_g                  : out std_logic;
    spare_clk_g                 : out std_logic;
    hard_reset                  : in  std_logic;
    si5345_cfgdone              : in  std_logic;
    mmcm_lock                   : in  std_logic;
    gt_txrstdone                : in  std_logic_vector(0 to NLANE-1);
    gt_rxrstdone                : in  std_logic_vector(0 to NLANE-1);
    gt_channel_up               : in  std_logic_vector(0 to NLANE-1);
    gt_lane_up                  : in  std_logic_vector(0 to NLANE-1);
    idelay_rdy                  : in  std_logic;
    si5345_intfcrst             : out std_logic;
    mmcm_reset                  : out  std_logic;
    idelayctrl_reset            : out std_logic;
    idelay_load                 : out std_logic;
    ttcs_intfcrst               : out std_logic;
    gt_intfcrst                 : out std_logic_vector(0 to NLANE-1);
    daq_logicrst                : out std_logic_vector(0 to 31);
    daq_fiforst                 : out std_logic_vector(0 to 31);
    pci_logicrst                : out std_logic_vector(0 to 31);
    pci_fiforst                 : out std_logic_vector(0 to 31);
    init_ce0                    : out std_logic_vector(0 to 7);
    init_strb0                  : out std_logic_vector(0 to 7);
    ttcs_ce0                    : out std_logic_vector(0 to 7);
    ttcs_strb0                  : out std_logic_vector(0 to 7));
end  det_tmg_init;


architecture behave of  det_tmg_init is
    
    constant INIT_NENBL         : natural                           := 1;
    constant TTCS_NENBL         : natural                           := 1;--4


    -- pattern for proper built-in FIFO reset
    constant LOGICSHFT_INIT     : std_logic_vector(15 downto 0)     := X"FFFF";
    constant FIFOSHFT_INIT      : std_logic_vector(15 downto 0)     := X"3000";
    constant ZGCEM              : integer                           := 6;

    type init_fsm_t is (SI5345S,MMCMS,TTSCS,GTPS,AURORAS,IDLYRSTS,IDLYLDS,DONES);
    --------------------------------------------------------------------------
    -- Signal declarations.
    --------------------------------------------------------------------------

    signal osc_clk_b            : std_logic;   
    signal spare_clk_b          : std_logic;

    signal init_clken           : std_logic_vector(1 to INIT_NENBL);
    signal init_strobe          : std_logic_vector(1 to INIT_NENBL);
    signal ttcs_clken           : std_logic_vector(1 to TTCS_NENBL);
    signal ttcs_strobe          : std_logic_vector(1 to TTCS_NENBL);
    signal init_ctr             : unsigned(1 downto 0) := (others => '0');
    signal init_sel0            : std_logic;
    signal init_sel1            : std_logic;
    signal init_sel2            : std_logic;
    signal init_sel3            : std_logic;

    signal fsm_si5345_intfcrst  : std_logic;
    signal fsm_mmcm_rst         : std_logic;
    signal fsm_ttcs_intfcrst    : std_logic;
    signal fsm_fast_logic_rst   : std_logic;
    signal fsm_gt_intfcrst      : std_logic;    
    signal fsm_idelay_rst       : std_logic;
    signal fsm_idelay_load      : std_logic;
    signal fsm_daq_logicrst     : std_logic;

    signal init_fsm_cs          : init_fsm_t;

    signal gt_txrstdone_q0      : std_logic_vector(0 to NLANE-1);
    signal gt_rxrstdone_q0      : std_logic_vector(0 to NLANE-1);
    signal gt_txrstdone_q1      : std_logic;
    signal gt_rxrstdone_q1      : std_logic;
    signal gt_channel_up_q0     : std_logic_vector(0 to NLANE-1);
    signal gt_lane_up_q0        : std_logic_vector(0 to NLANE-1);
    signal gt_channel_up_q1     : std_logic;
    signal gt_lane_up_q1        : std_logic;

    signal cdc_si5345_cfgdone   : std_logic;
    signal cdc_mmcm_lock        : std_logic;
    signal cdc_gt_txrstdone     : std_logic;
    signal cdc_gt_rxrstdone     : std_logic;
    signal cdc_channel_up       : std_logic;
    signal cdc_lane_up          : std_logic;
    signal cdc_idelay_rdy       : std_logic;

    signal init_fsm_reset       : std_logic;
    signal brdg_gt_intfcrst     : std_logic;
    signal brdg_aurora_rst      : std_logic;
    signal brdg_daq_logicrst    : std_logic;
    signal brdg_pci_logicrst    : std_logic;

    signal daq_logicrst_shift   : std_logic_vector(15 downto 0)     := LOGICSHFT_INIT;--pattern for fifo reset
    signal daq_fiforst_shift    : std_logic_vector(15 downto 0)     := FIFOSHFT_INIT;--pattern for fifo reset

    signal pci_logicrst_shift   : std_logic_vector(15 downto 0)     := LOGICSHFT_INIT;--pattern for fifo reset
    signal pci_fiforst_shift    : std_logic_vector(15 downto 0)     := FIFOSHFT_INIT;--pattern for fifo reset

begin

------------------------------------------------------------------------------------------------
-- Component instantiations
------------------------------------------------------------------------------------------------
    --------------------------------------------------
    -- Free-running clock source from XO  - IO Buffer
    --------------------------------------------------
    osc_ibuf : IBUFGDS
    generic map (
        DIFF_TERM                       => TRUE,         -- Differential Termination
        IBUF_LOW_PWR                    => FALSE,        -- Low power (TRUE) vs. performance (FALSE) setting for referenced I/O standards
        IOSTANDARD                      => "DEFAULT")
    port map(
        O                               => osc_clk_b,   -- Buffer output
        I                               => hk_clk_p,   -- Diff_p buffer input (connect directly to top-level port)
        IB                              => hk_clk_n    -- Diff_n buffer input (connect directly to top-level port)
    );

    --------------------------------------------------
    -- Free-running clock source from XO  - Clock Buffer
    --------------------------------------------------
    osc_bufg : BUFG
    port map (
        O                               => osc_clk_g, -- 1-bit output: Clock output
        I                               => osc_clk_b  -- 1-bit input: Clock input
    );

    sprclk_gen : if USE_SPRCLK generate
        --------------------------------------------------
        -- Spare clock source from Si5345 - IO Buffer
        --------------------------------------------------
        spare_ibuf : IBUFGDS
        generic map (
            DIFF_TERM                       => TRUE,          -- Differential Termination
            IBUF_LOW_PWR                    => FALSE,         -- Low power (TRUE) vs. performance (FALSE) setting for referenced I/O standards
            IOSTANDARD                      => "DEFAULT")
        port map(
            O                               => spare_clk_b,    -- Buffer output
            I                               => spare_clk_p,   -- Diff_p buffer input (connect directly to top-level port)
            IB                              => spare_clk_n    -- Diff_n buffer input (connect directly to top-level port)
        );

        --------------------------------------------------
        -- Spare clock source from Si5345 - Clock Buffer
        --------------------------------------------------
        spare_bufg : BUFG
        port map (
            O                               => spare_clk_g, -- 1-bit output: Clock output
            I                               => spare_clk_b-- 1-bit input: Clock input
        );
    end generate;

    --------------------------------------------------
    -- Generate a clock from the free-running clock
    -- without an MMCM or weird routing for Aurora
    -- inialization, etc.
    --------------------------------------------------
    init_bufg_ins : BUFGCTRL
    generic map (
      INIT_OUT                          => 0,     -- Initial value of BUFGCTRL output ($VALUES;)
      PRESELECT_I0                      => FALSE, -- BUFGCTRL output uses I0 input ($VALUES;)
      PRESELECT_I1                      => FALSE) -- BUFGCTRL output uses I1 input ($VALUES;)
    port map (
      O                                 => init_clk_g,-- 1-bit output: Clock output
      CE0                               => '1',       -- 1-bit input: Clock enable input for I0
      CE1                               => '1',       -- 1-bit input: Clock enable input for I1
      I0                                => '1',       -- 1-bit input: Primary clock
      I1                                => '0',       -- 1-bit input: Secondary clock
      IGNORE0                           => '1',       -- 1-bit input: Clock ignore input for I0
      IGNORE1                           => '1',       -- 1-bit input: Clock ignore input for I1
      S0                                => init_sel0, -- 1-bit input: Clock select for I0
      S1                                => init_sel1  -- 1-bit input: Clock select for I1
    );

    init_clk_en_ins : entity work.clk_enbl_gen
    generic map(
        MINRT                           => INIT_MINRT,
        NENBL                           => INIT_NENBL)
    port map(
        clk                             => init_clk_g,
        reset                           => si5345_intfcrst,
        enable                          => init_clken,
        strobe                          => init_strobe
    );

    ttcs_clk_en_ins : entity work.clk_enbl_gen
    generic map(
        MINRT                           => TTCS_MINRT,
        NENBL                           => TTCS_NENBL)
    port map(
        clk                             => daq_clk,
        reset                           => ttcs_intfcrst,
        enable                          => ttcs_clken,
        strobe                          => ttcs_strobe
    );

    -------------------------------------------------------
    -- Cross clock domains.
    -------------------------------------------------------
    fsm_reset_cdc_ins : entity work.cdc_register
    generic map(
        LEN                     => 3,
        INIT                    => '0')
    port map(
        clk                     => osc_clk_g,
        sig_in                  => hard_reset,
        sig_out                 => init_fsm_reset
    );

    -------------------------------------------------------
    -- Cross clock domains.
    -------------------------------------------------------    
    si5345_cfgdone_cdc_ins : entity work.cdc_register
    generic map(
        LEN                     => 3,
        INIT                    => '0')
    port map(
        clk                     => osc_clk_g,
        sig_in                  => si5345_cfgdone,
        sig_out                 => cdc_si5345_cfgdone
    );

    -------------------------------------------------------
    -- Cross clock domains.
    -------------------------------------------------------    
    mmcm_lock_cdc_ins : entity work.cdc_register
    generic map(
        LEN                     => 3,
        INIT                    => '0')
    port map(
        clk                     => osc_clk_g,
        sig_in                  => mmcm_lock,
        sig_out                 => cdc_mmcm_lock
    );

    -------------------------------------------------------
    -- Cross clock domains.
    -------------------------------------------------------
    gt_txrstdone_cdc_ins : entity work.cdc_register
    generic map(
        LEN                     => 3,
        INIT                    => '0')
    port map(
        clk                     => osc_clk_g,
        sig_in                  => gt_txrstdone_q1,
        sig_out                 => cdc_gt_txrstdone
    );

    -------------------------------------------------------
    -- Cross clock domains.
    -------------------------------------------------------
    gt_rxrstdone_cdc_ins : entity work.cdc_register
    generic map(
        LEN                     => 3,
        INIT                    => '0')
    port map(
        clk                     => osc_clk_g,
        sig_in                  => gt_rxrstdone_q1,
        sig_out                 => cdc_gt_rxrstdone
    );

    -------------------------------------------------------
    -- Cross clock domains.
    -------------------------------------------------------
    channel_up_cdc_ins : entity work.cdc_register
    generic map(
        LEN                     => 3,
        INIT                    => '0')
    port map(
        clk                     => osc_clk_g,
        sig_in                  => gt_channel_up_q1,
        sig_out                 => cdc_channel_up
    );

    -------------------------------------------------------
    -- Cross clock domains.
    -------------------------------------------------------
    lane_up_cdc_ins : entity work.cdc_register
    generic map(
        LEN                     => 3,
        INIT                    => '0')
    port map(
        clk                     => osc_clk_g,
        sig_in                  => gt_lane_up_q1,
        sig_out                 => cdc_lane_up
    );

    -------------------------------------------------------
    -- Cross clock domains.
    -------------------------------------------------------
    idelay_rdy_cdc_ins : entity work.cdc_register
    generic map(
        LEN                     => 3,
        INIT                    => '0')
    port map(
        clk                     => osc_clk_g,
        sig_in                  => idelay_rdy,
        sig_out                 => cdc_idelay_rdy
    );

    -------------------------------------------------------
    -- Pulse after clock stable.
    -------------------------------------------------------
    si5345_intfcrst_brdg_ins : entity work.reset_bridge
    generic map(
        LEN                     => 8,
        INIT                    => '1')
    port map(
        clk                     => init_clk_g,
        rst_in                  => fsm_si5345_intfcrst,
        rst_out                 => si5345_intfcrst
    );

    -------------------------------------------------------
    -- Pulse after clock stable.
    -------------------------------------------------------
    mmcm_reset_brdg_ins : entity work.reset_bridge
    generic map(
        LEN                     => 8,
        INIT                    => '1')
    port map(
        clk                     => init_clk_g,
        rst_in                  => fsm_mmcm_rst,
        rst_out                 => mmcm_reset
    );

    -------------------------------------------------------
    -- Pulse after clock stable.
    -------------------------------------------------------
    daq_logicrst_brdg_ins : entity work.reset_bridge
    generic map(
        LEN                     => 8,
        INIT                    => '1')
    port map(
        clk                     => daq_clk,
        rst_in                  => fsm_daq_logicrst,
        rst_out                 => brdg_daq_logicrst
    );

    -------------------------------------------------------
    -- Pulse after clock stable.
    -------------------------------------------------------
    pci_logicrst_brdg_ins : entity work.reset_bridge
    generic map(
        LEN                     => 8,
        INIT                    => '1')
    port map(
        clk                     => pci_clk,
        rst_in                  => fsm_daq_logicrst,
        rst_out                 => brdg_pci_logicrst
    );

    -------------------------------------------------------
    -- Pulse after clock stable.
    -------------------------------------------------------
    gt_intfc_brdg_ins : entity work.reset_bridge
    generic map(
        LEN                     => 8,
        INIT                    => '1')
    port map(
        clk                     => init_clk_g,
        rst_in                  => fsm_gt_intfcrst,
        rst_out                 => brdg_gt_intfcrst
    );

    -------------------------------------------------------
    -- Distribute reset.
    -------------------------------------------------------
    gt_intfc_dist_ins : entity work.dist_tree
    generic map(
        INIT                    => '1',
        NDIST                   => 2,
        NOUT                    => NLANE)
    port map(
        clk                     => init_clk_g,
        sig                     => brdg_gt_intfcrst,
        dist                    => gt_intfcrst
    );

    -------------------------------------------------------
    -- Pulse after clock stable.
    -------------------------------------------------------
    aurora_brdg_ins : entity work.reset_bridge
    generic map(
        LEN                     => 8,
        INIT                    => '1')
    port map(
        clk                     => daq_clk,
        rst_in                  => fsm_ttcs_intfcrst,
        rst_out                 => ttcs_intfcrst
    );

    -------------------------------------------------------
    -- Pulse after clock stable.
    -------------------------------------------------------
    idelayctrl_rese_brdg_ins : entity work.reset_bridge
    generic map(
        LEN                     => 8,
        INIT                    => '1')
    port map(
        clk                     => init_clk_g,
        rst_in                  => fsm_idelay_rst,
        rst_out                 => idelayctrl_reset
    );

    -------------------------------------------------------
    -- Distribute reset.
    -------------------------------------------------------
    daq_logic_dist_ins : entity work.dist_tree
    generic map(
        INIT                        => '1',
        NDIST                       => 4,
        NOUT                        => 32)
    port map(
        clk                         => daq_clk,
        sig                         => daq_logicrst_shift(0),
        dist                        => daq_logicrst
    );

    -------------------------------------------------------
    -- Distribute reset.
    -------------------------------------------------------
    daq_fifo_dist_ins : entity work.dist_tree
    generic map(
        INIT                        => '0',
        NDIST                       => 4,
        NOUT                        => 32)
    port map(
        clk                         => daq_clk,
        sig                         => daq_fiforst_shift(0),
        dist                        => daq_fiforst
    );

    -------------------------------------------------------
    -- Distribute reset.
    -------------------------------------------------------
    pci_logic_dist_ins : entity work.dist_tree
    generic map(
        INIT                        => '1',
        NDIST                       => 4,
        NOUT                        => 32)
    port map(
        clk                         => pci_clk,
        sig                         => pci_logicrst_shift(0),
        dist                        => pci_logicrst
    );

    -------------------------------------------------------
    -- Distribute reset.
    -------------------------------------------------------
    pci_fifo_dist_ins : entity work.dist_tree
    generic map(
        INIT                        => '0',
        NDIST                       => 4,
        NOUT                        => 32)
    port map(
        clk                         => pci_clk,
        sig                         => pci_fiforst_shift(0),
        dist                        => pci_fiforst
    );

    -------------------------------------------------------
    -- Distribute clock enable.
    -------------------------------------------------------
    init_ce0_dist_ins : entity work.dist_tree
    generic map(
        INIT                        => '0',
        NDIST                       => 2,
        NOUT                        => 8)
    port map(
        clk                         => init_clk_g,
        sig                         => init_clken(1),
        dist                        => init_ce0
    );

    -------------------------------------------------------
    -- Distribute strobe.
    -------------------------------------------------------
    init_strbx_dist_ins : entity work.dist_tree
    generic map(
        INIT                        => '0',
        NDIST                       => 2,
        NOUT                        => 8)
    port map(
        clk                         => init_clk_g,
        sig                         => init_strobe(1),
        dist                        => init_strb0
    );

    -------------------------------------------------------
    -- Distribute clock enable.
    -------------------------------------------------------
    ttcs_ce0_dist_ins : entity work.dist_tree
    generic map(
        INIT                        => '0',
        NDIST                       => 2,
        NOUT                        => 8)
    port map(
        clk                         => daq_clk,
        sig                         => ttcs_clken(1),
        dist                        => ttcs_ce0
    );

    -------------------------------------------------------
    -- Distribute strobe.
    -------------------------------------------------------
    ttcs_strbx_dist_ins : entity work.dist_tree
    generic map(
        INIT                        => '0',
        NDIST                       => 2,
        NOUT                        => 8)
    port map(
        clk                         => daq_clk,
        sig                         => ttcs_strobe(1),
        dist                        => ttcs_strb0
    );

------------------------------------------------------------------------------------------------
-- Concurrent statements
------------------------------------------------------------------------------------------------
    --------------------------------------------------------
    -- Map signals out of the port
    --------------------------------------------------------

    --------------------------------------------------------
    -- Combinational logic
    --------------------------------------------------------

    --------------------------------------------------------
    -- Processes
    --------------------------------------------------------

    --------------------------------------------------
    -- Gradually remove resets.
    -- The logic resets should be held high. The FIFO
    -- resets should be held low until the logic ready
    -- and then pulsed (see Xilinx memory user guide).
    --------------------------------------------------
    init_fsm_pcs : process(osc_clk_g)
    begin
        if osc_clk_g'event and osc_clk_g='1' then
            if init_fsm_reset then
                fsm_si5345_intfcrst <= '1';
                fsm_mmcm_rst        <= '1';
                fsm_idelay_rst      <= '1';
                fsm_idelay_load     <= '0';
                fsm_ttcs_intfcrst   <= '1';
                fsm_fast_logic_rst  <= '1';
                fsm_gt_intfcrst     <= '1';                
                fsm_daq_logicrst    <= '1';
                init_fsm_cs <= SI5345S;
            else
                case init_fsm_cs is
                when SI5345S =>--pulse si5345 logic interface reset
                    fsm_si5345_intfcrst <= '0';
                    fsm_mmcm_rst        <= '1';
                    fsm_idelay_rst      <= '1';
                    fsm_idelay_load     <= '0';
                    fsm_ttcs_intfcrst   <= '1';
                    fsm_fast_logic_rst  <= '1';
                    fsm_gt_intfcrst     <= '1';                    
                    fsm_daq_logicrst    <= '1';
                    if cdc_si5345_cfgdone then--!use LOS and INTR for this condition
                        init_fsm_cs <= MMCMS;
                    else
                        init_fsm_cs <= SI5345S;
                    end if;
                when MMCMS =>--pulse mmcm interface reset
                    fsm_si5345_intfcrst <= '0';
                    fsm_mmcm_rst        <= '0';
                    fsm_idelay_rst      <= '1';
                    fsm_idelay_load     <= '0';
                    fsm_ttcs_intfcrst   <= '1';
                    fsm_fast_logic_rst  <= '1';
                    fsm_gt_intfcrst     <= '1';                    
                    fsm_daq_logicrst    <= '1';
                    if cdc_mmcm_lock then
                        init_fsm_cs <= IDLYRSTS;
                    else
                        init_fsm_cs <= MMCMS;
                    end if;
                when IDLYRSTS =>--reset the delay control
                    fsm_si5345_intfcrst <= '0';
                    fsm_mmcm_rst        <= '0';
                    fsm_idelay_rst      <= '0';
                    fsm_idelay_load     <= '1';
                    fsm_ttcs_intfcrst   <= '1';
                    fsm_fast_logic_rst  <= '1';
                    fsm_gt_intfcrst     <= '1';
                    fsm_daq_logicrst    <= '1';
                    if cdc_idelay_rdy then
                        init_fsm_cs <= IDLYLDS;
                    else
                        init_fsm_cs <= IDLYRSTS;
                    end if;
                when IDLYLDS =>--pulse the delay load value
                    fsm_si5345_intfcrst <= '0';
                    fsm_mmcm_rst        <= '0';
                    fsm_idelay_rst      <= '0';
                    fsm_idelay_load     <= '1';
                    fsm_ttcs_intfcrst   <= '1';
                    fsm_fast_logic_rst  <= '1';
                    fsm_gt_intfcrst     <= '1';
                    fsm_daq_logicrst    <= '1';
                    init_fsm_cs <= TTSCS;
                when TTSCS =>--reset the timing and trigger signals
                    fsm_si5345_intfcrst <= '0';
                    fsm_mmcm_rst        <= '0';
                    fsm_idelay_rst      <= '0';
                    fsm_idelay_load     <= '0';
                    fsm_ttcs_intfcrst   <= '0';
                    fsm_fast_logic_rst  <= '0';
                    fsm_gt_intfcrst     <= '1';
                    fsm_daq_logicrst    <= '1';
                    init_fsm_cs         <= GTPS;
                when GTPS =>--hold FELIX reset
                    fsm_si5345_intfcrst <= '0';
                    fsm_mmcm_rst        <= '0';
                    fsm_idelay_rst      <= '0';
                    fsm_idelay_load     <= '0';
                    fsm_ttcs_intfcrst   <= '0';
                    fsm_fast_logic_rst  <= '0';
                    fsm_gt_intfcrst     <= '0';
                    fsm_daq_logicrst    <= '1';
                    --if (cdc_channel_up and cdc_lane_up) then
                    if (cdc_gt_txrstdone and cdc_gt_rxrstdone) then
                        init_fsm_cs <= DONES;
                    else
                        init_fsm_cs <= GTPS;
                    end if;
                when DONES =>-- wait for a reset
                    fsm_si5345_intfcrst <= '0';
                    fsm_mmcm_rst        <= '0';
                    fsm_idelay_rst      <= '0';
                    fsm_idelay_load     <= '0';
                    fsm_ttcs_intfcrst   <= '0';
                    fsm_fast_logic_rst  <= '0';
                    fsm_gt_intfcrst     <= '0';
                    fsm_daq_logicrst    <= '0';
                    init_fsm_cs <= DONES;
                when others =>
                    fsm_si5345_intfcrst <= '1';
                    fsm_mmcm_rst        <= '0';
                    fsm_idelay_rst      <= '1';
                    fsm_idelay_load     <= '0';
                    fsm_ttcs_intfcrst   <= '1';
                    fsm_fast_logic_rst  <= '1';
                    fsm_gt_intfcrst     <= '1';
                    fsm_daq_logicrst    <= '1';
                    init_fsm_cs <= SI5345S;
                end case;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Generate BUFGMUX selects for init clock generation.
    ------------------------------------------------------------------
    init_sel_pcs : process(osc_clk_g)
    begin
        if (osc_clk_g'event and osc_clk_g='1') then
            init_ctr  <= init_ctr + 1;
            init_sel0 <= not init_ctr(init_ctr'left);
            init_sel1 <= init_ctr(init_ctr'left);
            init_sel2 <= not init_ctr(0);
            init_sel3 <= init_ctr(0);
        end if;
    end process;

    ------------------------------------------------------------------
    -- Assert reset for shift length clock cycles at init time (for
    -- simulation), when runreset, or MMCM issue. Cross clock domain.
    ------------------------------------------------------------------
    daq_fmrst_proc : process(daq_clk)
    begin
        if (daq_clk'event and daq_clk='1') then
            if brdg_daq_logicrst = '1' then
                -- assert reset for shift length
                daq_logicrst_shift <= LOGICSHFT_INIT;
                daq_fiforst_shift <= FIFOSHFT_INIT;
            else
                -- de-assert after shift length
                daq_logicrst_shift <= '0' & daq_logicrst_shift(daq_logicrst_shift'length-1 downto 1);
                daq_fiforst_shift <= '0' & daq_fiforst_shift(daq_fiforst_shift'length-1 downto 1);
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Assert reset for shift length clock cycles at init time (for
    -- simulation), when runreset, or MMCM issue. Cross clock domain.
    ------------------------------------------------------------------
    pci_fmrst_proc : process(pci_clk)
    begin
        if (pci_clk'event and pci_clk='1') then
            if brdg_pci_logicrst = '1' then
                -- assert reset for shift length
                pci_logicrst_shift <= LOGICSHFT_INIT;
                pci_fiforst_shift <= FIFOSHFT_INIT;
            else
                -- de-assert after shift length
                pci_logicrst_shift <= '0' & pci_logicrst_shift(pci_logicrst_shift'length-1 downto 1);
                pci_fiforst_shift <= '0' & pci_fiforst_shift(pci_fiforst_shift'length-1 downto 1);
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Register outputs to improve timing and align the signal edges
    ------------------------------------------------------------------
    osc_dly_proc : process(osc_clk_g)
    begin
        if (osc_clk_g'event and osc_clk_g='1') then
            idelay_load <= fsm_idelay_load;--just pipeline this synchronous signal
        end if;
    end process;


    ------------------------------------------------------------------
    -- Register outputs to improve timing and align the signal edges
    ------------------------------------------------------------------
    init_dly_proc : process(init_clk_g)
    begin
        if (init_clk_g'event and init_clk_g='1') then
            gt_txrstdone_q0  <= gt_txrstdone;
            gt_rxrstdone_q0  <= gt_rxrstdone;
            gt_channel_up_q0 <= gt_channel_up;
            gt_lane_up_q0    <= gt_lane_up;
            --Need to add a mask for unused channgels here!!!!!!!!!!!!!
            gt_txrstdone_q1  <= AND_REDUCE(gt_txrstdone_q0);
            gt_rxrstdone_q1  <= AND_REDUCE(gt_rxrstdone_q0);
            gt_channel_up_q1 <= AND_REDUCE(gt_channel_up_q0  );
            gt_lane_up_q1    <= AND_REDUCE(gt_lane_up_q0     );
        end if;
    end process;

end behave;