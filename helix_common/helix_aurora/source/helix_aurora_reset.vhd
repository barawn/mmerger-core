--*********************************************************************************
-- Indiana University
-- Center for Exploration of Energy and Matter (CEEM)
--
-- Project: HELIX
--
-- Author:  Brandon Kunkler
--
-- Date:    11/19/2018
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
-- Aurora 8b/10b interface reset. Try to follow the reset sequence in the Aurora
-- 8b/10b user guide reset section (not really clear)
--
-- Known Issues:

--*********************************************************************************

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.std_logic_misc.all;
    use ieee.numeric_std.all;

entity helix_aurora_reset is
port(    
    user_clk                    : in std_logic;
    init_clk                    : in std_logic;
    ext_reset                   : in std_logic;
    gt_reset                    : out std_logic;
    chan_reset                  : out std_logic);
end helix_aurora_reset;

architecture behave of helix_aurora_reset is

    type rst_fsm_t is (RESETS,LOADS,PRECTRS,CHANS,PSTCTRS,DONES);

    signal rst_fsm_cs           : rst_fsm_t;
    signal fsm_gt_reset         : std_logic;
    signal fsm_aurora_reset     : std_logic;
    signal fsm_done             : std_logic;
    signal second_flag_clr      : std_logic;
    signal second_flag          : std_logic                 := '0';
    signal lgc_gt_reset         : std_logic;
    signal lgc_aurora_reset     : std_logic;
    signal cycle_ctr_ld         : std_logic;
    signal cycle_ctr_tc         : std_logic;
    signal cycle_ctr            : unsigned(6 downto 0);
    signal brdg_aurora_reset    : std_logic;

begin

    -------------------------------------------------------
    -- Cross clock domains.
    -------------------------------------------------------
    chan_cdc_ins : entity work.cdc_register
    generic map(
        LEN                     => 3,
        INIT                    => '1')
    port map(
        clk                     => user_clk,
        sig_in                  => brdg_aurora_reset,
        sig_out                 => chan_reset
    );

    -------------------------------------------------------
    -- Pulse after clock stable.
    -------------------------------------------------------
    chan_brdg_ins : entity work.reset_bridge
    generic map(
        LEN                     => 8,
        INIT                    => '1')
    port map(
        clk                     => init_clk,
        rst_in                  => lgc_aurora_reset,
        rst_out                 => brdg_aurora_reset
    );

    -------------------------------------------------------
    -- Pulse after clock stable.
    -------------------------------------------------------
    si5345_intfcrst_brdg_ins : entity work.reset_bridge
    generic map(
        LEN                     => 8,
        INIT                    => '1')
    port map(
        clk                     => init_clk,
        rst_in                  => lgc_gt_reset,
        rst_out                 => gt_reset
    );


    --------------------------------------------------
    -- Gradually remove resets.
    -- The logic resets should be held high. The FIFO
    -- resets should be held low until the logic ready
    -- and then pulsed (see Xilinx memory user guide).
    --------------------------------------------------
    fsm_pcs : process(init_clk)
    begin
        if init_clk'event and init_clk='1' then
            if ext_reset then
                fsm_gt_reset         <= '1';
                fsm_aurora_reset     <= '1';
                fsm_done             <= '0';
                second_flag_clr      <= '0';
                cycle_ctr_ld         <= '1';
                rst_fsm_cs           <= RESETS;
            else
                case rst_fsm_cs is
                when RESETS =>--check if already reset
                    fsm_gt_reset     <= '1';
                    fsm_aurora_reset <= '1';
                    fsm_done         <= '0';                    
                    cycle_ctr_ld     <= '1';
                    if second_flag then
                        second_flag_clr  <= '0';
                        rst_fsm_cs  <= PRECTRS;
                    else
                        second_flag_clr  <= '1';
                        rst_fsm_cs  <= LOADS;
                    end if;
                when LOADS =>--load and get ready
                    fsm_gt_reset     <= '1';
                    fsm_aurora_reset <= '1';
                    fsm_done         <= '0';
                    second_flag_clr  <= '1';
                    cycle_ctr_ld     <= '1';
                    rst_fsm_cs       <= CHANS;
                when PRECTRS =>--assert aurora reset for >= 128 clocks
                    fsm_gt_reset     <= '0';
                    fsm_aurora_reset <= '1';
                    fsm_done         <= '0';
                    second_flag_clr  <= '0';
                    cycle_ctr_ld     <= '0';
                    if cycle_ctr_tc then
                        rst_fsm_cs  <= CHANS;
                    else
                        rst_fsm_cs  <= PRECTRS;
                    end if;
                when CHANS =>--assert GT reset for reset time (by using reset bridge)
                    fsm_gt_reset     <= '1';
                    fsm_aurora_reset <= '1';
                    fsm_done         <= '0';
                    second_flag_clr  <= '1';
                    cycle_ctr_ld     <= '1';
                    rst_fsm_cs       <= PSTCTRS;
                when PSTCTRS =>---assert aurora reset for >= 128 clocks
                    fsm_gt_reset     <= '0';
                    fsm_aurora_reset <= '1';
                    fsm_done         <= '0';
                    second_flag_clr  <= '0';
                    cycle_ctr_ld     <= '0';
                    if cycle_ctr_tc then
                        rst_fsm_cs  <= DONES;
                    else
                        rst_fsm_cs  <= PSTCTRS;
                    end if;
                when DONES =>--pulse MMCM reset
                    fsm_gt_reset     <= '0';
                    fsm_aurora_reset <= '0';
                    fsm_done         <= '1';
                    second_flag_clr  <= '0';
                    cycle_ctr_ld     <= '1';
                    rst_fsm_cs       <= DONES;
                when others =>
                    fsm_gt_reset     <= '1';
                    fsm_aurora_reset <= '1';
                    second_flag_clr  <= '1';
                    cycle_ctr_ld     <= '1';
                    rst_fsm_cs <= RESETS;
                end case;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Test if first reset since power-up.
    ------------------------------------------------------------------
    test_pcs : process(init_clk)
    begin
        if (init_clk'event and init_clk='1') then
            if second_flag_clr then
                second_flag <= '0';
                lgc_gt_reset <= '1';
                lgc_aurora_reset <= '1';
            else
                lgc_gt_reset     <= fsm_gt_reset and (not second_flag);
                lgc_aurora_reset <= fsm_aurora_reset;
                if fsm_done then
                    second_flag <= '1';
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Count number of clock cycles reset is held.
    ------------------------------------------------------------------
    ctr_pcs : process(init_clk)
    begin
        if (init_clk'event and init_clk='1') then
            if cycle_ctr_ld then
                cycle_ctr <= (others => '1');
            else
                cycle_ctr <= cycle_ctr - 1;
            end if;
            cycle_ctr_tc <= '1' when cycle_ctr=0 else '0';
        end if;
    end process;

end behave;
