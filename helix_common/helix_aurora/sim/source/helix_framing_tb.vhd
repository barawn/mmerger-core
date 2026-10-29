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
    constant SI5343_LKTM                : time                                  := 300 ns;
    constant DWDT                       : positive                              := 32;--16 or 32
    constant CWDT                       : positive                              := 16;--16 or 32
    constant KWDT                       : positive                              := DWDT/8;
    constant RWDT                       : positive                              := INTEGER(CEIL(LOG2(REAL(KWDT))));
    constant NLANE                      : natural                               := 4;
    constant LINE_RATE_VEC              : unsigned(0 to NLANE-1)                := "1000";
    constant USEREFCLK1                 : boolean                               := TRUE;
    constant SIM_SPDUP                  : boolean                               := FALSE;--Channel/lane up are never asserted when speed-up is use!!!!!    
    constant FRM_TYP                    : string                                := "IUB";--IUB or XLX

    signal user_clk                     : std_logic;
                                          
    signal tx_resetdone                 : std_logic;
    signal rx_resetdone                 : std_logic;                                                                                   

    signal channel_up                   : std_logic;                                          
    
    signal s_axi_tx_tkeep               : std_logic_vector(KWDT-1 downto 0);    
    signal s_axi_tx_tready              : std_logic;
    signal s_axi_tx_tvalid              : std_logic;
    signal s_axi_tx_tlast               : std_logic;
    signal s_axi_tx_tdata               : std_logic_vector(DWDT-1 downto 0);    
    
    signal m_axi_rx_tkeep               : std_logic_vector(KWDT-1 downto 0);
    signal m_axi_rx_tvalid              : std_logic;
    signal m_axi_rx_tlast               : std_logic;
    signal m_axi_rx_tdata               : std_logic_vector(DWDT-1 downto 0);
                                          
    signal s_axi_nfc_req                : std_logic;
    signal s_axi_nfc_nb                 : std_logic_vector(3 downto 0);
    signal s_axi_nfc_ack                : std_logic;
                                          
    signal m_axi_rx_snf                 : std_logic;
    signal m_axi_rx_fc_nb               : std_logic_vector(3 downto 0);

    signal ll_ip_dst_rdy_n              : std_logic;    
    signal ll_op_rem                    : std_logic_vector(RWDT-1 downto 0);    
    signal ll_op_sof_n                  : std_logic;
    signal ll_op_eof_n                  : std_logic;
    signal ll_op_src_rdy_n              : std_logic;
    signal ll_op_data                   : std_logic_vector(DWDT-1 downto 0);

    signal ll_op_dst_rdy_n              : std_logic;
    signal ll_ip_rem                    : std_logic_vector(RWDT-1 downto 0);    
    signal ll_ip_sof_n                  : std_logic;
    signal ll_ip_eof_n                  : std_logic;
    signal ll_ip_src_rdy_n              : std_logic;    
    signal ll_ip_data                   : std_logic_vector(DWDT-1 downto 0);    

    --signal ll_op_dst_rdy_n_q0           : std_logic;
    --signal ll_ip_rem_q0                 : std_logic;    
    --signal ll_ip_sof_n_q0               : std_logic;
    --signal ll_ip_eof_n_q0               : std_logic;
    --signal ll_ip_src_rdy_n_q0           : std_logic;
    signal ll_ip_data_q0                : std_logic_vector(DWDT-1 downto 0);    

    signal tx_resetdone_nq0             : std_logic;
    signal rx_resetdone_nq0             : std_logic;

    signal frm_chk_err                  : std_logic_vector(7 downto 0);
    signal inject_err                   : std_logic;
    signal err_shift                    : std_logic_vector(0 to 3);
    signal err_re                       : std_logic;
    signal err_vec                      : std_logic;

    signal vcc_vec                      : std_logic_vector(0 to NLANE-1) := (others => '1');

    signal s_axi_nfc_req_n              : std_logic;
    signal s_axi_nfc_ack_n              : std_logic;

    -- Declare stimulus signals
    signal stim_si5343_ready            : std_logic     := '0';
    signal stim_si5343_daq_clk          : std_logic     := '0';
    signal stim_frm_err                 : std_logic     := '0';

begin

---------------------------------------------------------------------------------------------------------
-- Component instantiations
---------------------------------------------------------------------------------------------------------

    -------------------------------------------------------
    -- Instantiate the unit under test.
    -------------------------------------------------------
        -------------------------------------------------------
        -- Frame generator.
        -------------------------------------------------------
        frmgen_typ_gen : if FRM_TYP = "XLX" generate
            frm_gen_ins : entity work.aurora_8b10b_FRAME_GEN
            port map(
                -- User Interface
                TX_D                           => ll_ip_data,
                TX_REM                         => ll_ip_rem(0),
                TX_SOF_N                       => ll_ip_sof_n,
                TX_EOF_N                       => ll_ip_eof_n,
                TX_SRC_RDY_N                   => ll_ip_src_rdy_n,
                TX_DST_RDY_N                   => ll_op_dst_rdy_n,
                -- NFC Interface
                NFC_REQ_N                      => s_axi_nfc_req_n,
                NFC_NB                         => s_axi_nfc_nb,
                NFC_ACK_N                      => s_axi_nfc_ack_n,
                -- System Interface
                USER_CLK                       => user_clk,
                RESET                          => tx_resetdone_nq0,--user clock domain!
                CHANNEL_UP                     => channel_up
            );

            ll_to_axi_ins : entity work.aurora_8b10b_LL_TO_AXI
            generic map(
                DATA_WIDTH                      => DWDT,-- DATA bus width
                STRB_WIDTH                      => KWDT,-- STROBE bus width
                USE_UFC_REM                     => 0,   -- UFC REM bus width identifier
                REM_WIDTH                       => RWDT)-- REM bus width
            port map(
                -- AXI4-S Interface
                AXI4_S_OP_TDATA                 => s_axi_tx_tdata,
                AXI4_S_OP_TKEEP                 => s_axi_tx_tkeep,
                AXI4_S_OP_TVALID                => s_axi_tx_tvalid,
                AXI4_S_OP_TLAST                 => s_axi_tx_tlast,
                AXI4_S_IP_TREADY                => s_axi_tx_tready,
                -- LocalLink Interface
                LL_IP_DATA                      => ll_ip_data_q0,
                LL_IP_REM                       => ll_ip_rem(0),
                LL_IP_SRC_RDY_N                 => ll_ip_src_rdy_n,
                LL_IP_SOF_N                     => ll_ip_sof_n,
                LL_IP_EOF_N                     => ll_ip_eof_n,
                LL_OP_DST_RDY_N                 => ll_op_dst_rdy_n
            );
        else generate
            frm_gen_ins : entity work.helix_frmgen
            generic map(
                TXDWDT                          => DWDT,
                RXDWDT                          => CWDT,
                KWDT                            => KWDT,
                NFRM                            => 16)
            port map(
                -- system interface
                user_clk                       => user_clk,
                reset                          => tx_resetdone_nq0,--user clock domain!
                channel_up                     => channel_up,
                -- user interface
                tready                          => s_axi_tx_tready,
                tuser                           => s_axi_tx_tuser,
                tlast                           => s_axi_tx_tlast,
                tvalid                          => s_axi_tx_tvalid,
                tdata                           => s_axi_tx_tdata,
                tkeep                           => s_axi_tx_tkeep,
                -- nfc interface
                nfc_req_n                      => s_axi_nfc_req_n,
                nfc_nb                         => s_axi_nfc_nb,
                nfc_ack_n                      => s_axi_nfc_ack_n
            );
        end generate;

        frmchk_typ_gen : if FRM_TYP = "XLX" generate
            frm_chk_ins : entity work.aurora_8b10b_FRAME_CHECK
            port map(
                -- User Interface
                RX_D                            => ll_op_data,
                RX_REM                          => ll_op_rem(0),
                RX_SOF_N                        => ll_op_sof_n,
                RX_EOF_N                        => ll_op_eof_n,
                RX_SRC_RDY_N                    => ll_op_src_rdy_n,
                -- NFC INterface
                RX_SNF                          => m_axi_rx_snf,
                RX_FC_NB                        => m_axi_rx_fc_nb,
                -- System Interface
                USER_CLK                        => user_clk,
                RESET                           => rx_resetdone_nq0,
                CHANNEL_UP                      => channel_up,
                ERR_COUNT                       => frm_chk_err
            );

            axi_to_ll_ins : entity work.aurora_8b10b_AXI_TO_LL
            generic map(
                DATA_WIDTH                      => DWDT,  -- DATA bus width
                STRB_WIDTH                      => KWDT,  -- STROBE bus width
                REM_WIDTH                       => RWDT,  -- REM bus width
                USE_4_NFC                       => 0,     --  0 => PDU, 1 => NFC, 2 => UFC
                USE_UFC_REM                     => 0)     -- UFC REM bus width identifier
            port map(
                -- AXI4-S Interface
                AXI4_S_IP_TX_TDATA              => m_axi_rx_tdata,
                AXI4_S_IP_TX_TKEEP              => m_axi_rx_tkeep,
                AXI4_S_IP_TX_TVALID             => m_axi_rx_tvalid,
                AXI4_S_IP_TX_TLAST              => m_axi_rx_tlast,
                AXI4_S_OP_TX_TREADY             => open,
                --  LocalLink Interface
                LL_OP_DATA                      => ll_op_data,
                LL_OP_REM                       => ll_op_rem(0),
                LL_OP_SRC_RDY_N                 => ll_op_src_rdy_n,
                LL_OP_SOF_N                     => ll_op_sof_n,
                LL_OP_EOF_N                     => ll_op_eof_n,
                LL_IP_DST_RDY_N                 => ll_ip_dst_rdy_n,
                -- System Interface
                USER_CLK                        => user_clk,
                RESET                           => rx_resetdone_nq0,
                CHANNEL_UP                      => channel_up
            );
        else generate
            frm_chk_ins : entity work.helix_frmchk
            generic map(
                DWDT                            => DWDT,                
                KWDT                            => KWDT,
                NFRM                            => 16)
            port map(
                -- system interface
                user_clk                        => user_clk,
                reset                           => rx_resetdone_nq0,
                channel_up                      => channel_up,
                -- user interface
                tuser                           => m_axi_rx_tuser,
                tlast                           => m_axi_rx_tlast,
                tvalid                          => m_axi_rx_tvalid,
                tdata                           => m_axi_rx_tdata,
                tkeep                           => m_axi_rx_tkeep,
                -- nfc interface
                rx_snf                          => m_axi_rx_snf,
                rx_fc_nb                        => m_axi_rx_fc_nb,
                err_count                       => frm_chk_err
            );
        end generate;

---------------------------------------------------------------------------------------------------------
-- Concurrent statements
---------------------------------------------------------------------------------------------------------

    -- reference/system clock
    stim_si5343_ready <= '0', '1' after SI5343_LKTM;

    stim_clk_pcs : process(all)
    begin
        if stim_si5343_ready then
            stim_si5343_daq_clk <= not stim_si5343_daq_clk after DAQHPER;            
        else
            stim_si5343_daq_clk <= '0';            
        end if;
    end process;

    user_clk <= stim_si5343_daq_clk;

    -- resets must be asserted for at least six clocks
    tx_resetdone <= '0', '0' after SI5343_LKTM, '1' after 1 us;
    rx_resetdone <= '0', '0' after SI5343_LKTM, '1' after 2 us;
    channel_up <= '0', '0' after SI5343_LKTM, '1' after 3 us;

    tx_resetdone_nq0 <= not tx_resetdone after DAQHPER;
    rx_resetdone_nq0 <= not rx_resetdone after DAQHPER;

    --mgr_inject_err <= (others => '0'), (others => '1') after 2200 us;
    --feb_inject_err <= (others => '0'), (others => '1') after 2200 us;

    s_axi_nfc_ack <= s_axi_nfc_req after DAQPER*1;

    s_ready_pcs : process(user_clk)
        variable rdy_lfsr       : std_logic_vector(1 to 16);
    begin
        if rising_edge(user_clk) then
            if (not channel_up) then
                s_axi_tx_tready <= '0';
                rdy_lfsr := (others => '0');
            else
                rdy_lfsr := (rdy_lfsr(16) xnor rdy_lfsr(15) xnor rdy_lfsr(13) xnor rdy_lfsr(4)) & rdy_lfsr(1 to (rdy_lfsr'right-1));
                s_axi_tx_tready <= rdy_lfsr(rdy_lfsr'left);
            end if;
        end if;
    end process;

    ll_ip_dst_rdy_n <= (not channel_up) after DAQPER*20;

    inject_err <= s_axi_tx_tready after DAQPER*1000;

    m_axi_rx_tdata  <= s_axi_tx_tdata;
    m_axi_rx_tkeep  <= s_axi_tx_tkeep;
    m_axi_rx_tvalid <= (s_axi_tx_tvalid and s_axi_tx_tready);
    m_axi_rx_tlast  <= s_axi_tx_tlast;

    m_axi_rx_snf    <= s_axi_nfc_req;
    m_axi_rx_fc_nb  <= s_axi_nfc_nb;

    ll_ip_data_q0   <= ll_ip_data when (not err_vec) else (not ll_ip_data); --inject error;

    s_axi_nfc_req   <= not s_axi_nfc_req_n;
    s_axi_nfc_ack_n <= not s_axi_nfc_ack;

    stim_frm_err <= '1' when UNSIGNED(frm_chk_err) > 0 else '0';
    assert (stim_frm_err='0') report "Frame Error" severity warning;

    error_pcs : process(user_clk)
    begin
        if user_clk'event and user_clk='1' then
            -- cross clock domains just in case
            err_shift  <= inject_err & err_shift(err_shift'left to err_shift'right-1);
            -- detect rising edge of VIO output
            err_re     <= err_shift(err_shift'right-1) and (not err_shift(err_shift'right));
            -- hold inject signal until data is sent
            if tx_resetdone_nq0 then
                err_vec <= '0';
            else
                if err_re then
                    err_vec <= '1';
                else
                    if s_axi_tx_tvalid then
                        err_vec <= '0';
                    end if;
                end if;
            end if;                
        end if;
    end process;

end behave;