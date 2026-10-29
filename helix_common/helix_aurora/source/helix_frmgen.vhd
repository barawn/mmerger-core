--*********************************************************************************
-- Indiana University
-- Center for Exploration of Energy and Matter (CEEM)
--
-- Project: HELIX
--
-- Author:  Brandon Kunkler
--
-- Date:    01/17/2018
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
-- Generate test frames that will work for 16-bit to 16-bit interfaces and 16-bit
-- to 32-bit interfaces. The header and trailer are 16-bits when TX16 to RX16. The
-- header and trailer and 32-bits when TX16 to RX32.
--
-- Deficiencies:
-- The last word in the frame is not received properly when TX32 to RX16 no matter
-- what tkeep values are used.
--
--*********************************************************************************
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity helix_frmgen is
generic(
    TXDWDT                          : integer := 32;
    RXDWDT                          : integer := 32;
    KWDT                            : integer := 2;
    NFRM                            : integer := 6);
port(
    -- System Interface
    user_clk                        : in  std_logic;
    reset                           : in  std_logic;
    channel_up                      : in  std_logic;
    -- User Interface
    tready                          : in  std_logic;
    tuser                           : out std_logic;
    tlast                           : out std_logic;
    tvalid                          : out std_logic;
    tdata                           : out std_logic_vector(0 to TXDWDT-1);
    tkeep                           : out std_logic_vector(0 to KWDT-1);
    -- NFC Interface
    tx_nfc_xoff                     : out std_logic);
    --rx_nfc_xoff                     : in std_logic);
end helix_frmgen;

architecture behave of helix_frmgen is

    --constant MAXF                   : integer                                   := NFRM-2;
    constant FRMSOF                 : std_logic_vector(0 to 15)                 := X"FEED"; --SOF word
    constant FRMEOF                 : std_logic_vector(0 to 15)                 := X"CAFE"; --EOF word
    constant GBGSOF                 : std_logic_vector(0 to 15)                 := X"BAD5"; --Garbage near SOF
    constant GBGEOF                 : std_logic_vector(0 to 15)                 := X"BADE"; --Garbage near EOF
    constant MINLEN                 : positive                                  := 2;
    constant MINDLY                 : positive                                  := 8;

    constant CEM                    : integer                                   := 1;
    constant CQD                    : time                                      := 1 ns; -- clock to Q delay for Aurora
    --constant DLYM                   : unsigned(9 downto 0)                      := TO_UNSIGNED(2**5,10); --inter-frame delay max

    function MAXF return positive is
        variable v : integer;
    begin
        if TXDWDT = 32 then
            v := NFRM-3;
        else
            v := NFRM-2;
        end if;
        return v;
    end function;

    function DINC return positive is
        variable v : integer;
    begin
        if TXDWDT = 32 then
            v := 2;
        else
            v := 1;
        end if;
        return v;
    end function;

    type frm_fsm_type is (RESETS,IDLES,SOFS,PLDS,EOFS,PAUSES);

    signal fsm_ce_cnt               : integer range 0 to CEM                    := CEM;
    signal fsm_ce_cnt_tc            : std_logic                                 := '0';
    signal fsm_ce                   : std_logic                                 := '0';

    -- frame generator signals
    signal start_frame              : std_logic;
    signal frm_fsm_cs               : frm_fsm_type; --current state
    signal frm_fsm_ns               : frm_fsm_type; --next state
    signal frm_fsm_dt               : std_logic_vector(1 downto 0);--data type

    signal frm_len_ctr_ld           : std_logic;
    signal frm_len_ctr_en           : std_logic;
    signal frm_len_ctr_tc           : std_logic;
    signal frm_len_ctr              : unsigned(9 downto 0);
    signal frm_len_lfsr             : unsigned(1 to 9);

    signal nfc_xoff_ctr              : unsigned(11 downto 0);
    signal nfc_xoff_ctr_tc           : std_logic;

    signal frm_dat_ctr_en           : std_logic;
    signal frm_dat_ctr0             : unsigned(0 to 15);
    signal frm_dat_ctr1             : unsigned(0 to 15);

    signal dly_ctr_ld               : std_logic;
    signal dly_ctr_tc               : std_logic;
    signal dly_ctr                  : unsigned(9 downto 0);
    signal dly_lfsr                 : unsigned(1 to 10);

begin    

    -----------------------------------------------------------------
    -- Select logic for 32-bit transmit (when this component is 32-bit
    -----------------------------------------------------------------
    gen_tx32bit : if TXDWDT = 32 generate        
        frm_dat_ctr_en <= tready when frm_fsm_dt(1)='0' else '0';--SOF or payload, not EOF
        start_frame <= tready and channel_up;
        --------------------------------------------------
        -- Mux output interface signals.
        -- Must be async because ready allows no pause.
        --------------------------------------------------
        data_regs_pcs : process(all)
        begin            
            case frm_fsm_dt is
            when "00" =>
                tuser     <= fsm_ce  after CQD;
                tlast     <= '0' after CQD;
                tvalid    <= '1' after CQD;
                tdata     <= FRMSOF & (STD_LOGIC_VECTOR(frm_dat_ctr1)) after CQD;
                tkeep     <= "1111" after CQD;
            when "01" =>
                tuser     <= '0' after CQD;
                tlast     <= '0' after CQD;
                tvalid    <= '1' after CQD;
                tdata     <= STD_LOGIC_VECTOR(frm_dat_ctr0 & (frm_dat_ctr1)) after CQD;
                tkeep     <= "1111";
            when "10" =>
                tuser     <= '0' after CQD;
                tlast     <= fsm_ce  after CQD;
                tvalid    <= '1' after CQD;
                tdata     <= STD_LOGIC_VECTOR(frm_dat_ctr0) & FRMEOF after CQD;
                tkeep     <= "1100" after CQD;
                --01 => CAFE comes out, tvalid goes low, then tlast asserted, last data word is skipped
                --10 => CAFE comes out, tvalid goes low, then tlast asserted, last data word is skipped
                --11 => CAFE comes out, tvalid stays high, then tlast asserted, last data word is skipped
            when "11" =>
                tuser     <= '0' after CQD;
                tlast     <= '0' after CQD;
                tvalid    <= '0' after CQD;
                tdata     <= FRMEOF & GBGEOF after CQD;
                tkeep     <= "1111" after CQD;
            when others =>
                tuser     <= '0' after CQD;
                tlast     <= '0' after CQD;
                tvalid    <= '0' after CQD;
                tdata     <= (others => 'X') after CQD;
                tkeep     <= "1111" after CQD;
            end case;            
        end process;
    end generate;

    -----------------------------------------------------------------
    -- Select logic for 16-bit transmit (when this component is 32-bit)
    -----------------------------------------------------------------
    gen_tx16bit : if TXDWDT = 16 generate        
        frm_dat_ctr_en <= tready when frm_fsm_dt="01" else '0';
        start_frame <= tready and channel_up;
        tkeep    <= (others => '1');
        --------------------------------------------------
        -- Mux output interface signals.
        -- Must be async because ready allows no pause.
        --------------------------------------------------
        data_regs_pcs : process(all)
        begin
            case frm_fsm_dt is
            when "00" =>
                tuser     <= not fsm_ce after CQD;
                tlast     <= '0' after CQD;
                tvalid    <= '1' after CQD;--frm_dat_ce    after CQD;
                tdata     <= FRMSOF after CQD;
            when "01" =>
                tuser     <= '0' after CQD;
                tlast     <= '0' after CQD;
                tvalid    <= '1' after CQD;--frm_dat_ce    after CQD;
                tdata     <= STD_LOGIC_VECTOR(frm_dat_ctr1) after CQD;
            when "10" =>
                tuser     <= '0' after CQD;
                tlast     <= fsm_ce after CQD;
                tvalid    <= '1' after CQD;--frm_dat_ce    after CQD;
                tdata     <= FRMEOF after CQD;
            when "11" =>
                tuser     <= '0' after CQD;
                tlast     <= '0' after CQD;
                tvalid    <= '0' after CQD;
                tdata     <= FRMEOF after CQD;
            when others =>
                tuser     <= '0' after CQD;
                tlast     <= '0' after CQD;
                tvalid    <= '0' after CQD;
                tdata     <= (others => 'X') after CQD;
            end case;            
        end process;

    end generate;

    -----------------------------------------------------------------
    -- Select logic for 32-bit receive (when destination is 32-bit)
    -----------------------------------------------------------------
    gen_rx32bit : if RXDWDT = 32 generate
        fsm_ce_cnt_tc <= '1' when fsm_ce_cnt = CEM else '0';
        fsm_ce <= fsm_ce_cnt_tc and tready; --extend SOF state when TX16 and RX32 --!!!!!!!!
    end generate;

    -----------------------------------------------------------------
    -- Select logic for 16-bit receive (when destination is 16-bit)
    -----------------------------------------------------------------
    gen_rx16bit : if RXDWDT = 16 generate
        fsm_ce_cnt_tc <= '0';
        fsm_ce <= tready;
    end generate;

    ------------------------------------------------------------------
    -- Create a clock enable to extend signals as needed.
    ------------------------------------------------------------------
    fsm_ce_proc : process(user_clk)
    begin
        if (user_clk'event and user_clk='1') then
            if frm_fsm_dt(frm_fsm_dt'right) = '1' then
                fsm_ce_cnt <= 0;                
            else
                if tready = '1' then--deal with tready at SOF/EOF!!!!!!!!!!!
                    if fsm_ce_cnt = 0 then
                        fsm_ce_cnt <= CEM;                    
                    else
                        fsm_ce_cnt <= fsm_ce_cnt - 1;
                    end if;                
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Framing state machine async portion.
    -- Must be async because ready allows no pause.
    ------------------------------------------------------------------
    frm_fsm_a_pcs : process(all)
    begin
        case frm_fsm_cs is
        -- reset/load counters, etc.
        when RESETS =>
            dly_ctr_ld <= '1';
            frm_len_ctr_ld <= '1';
            frm_len_ctr_en <= '0';
            frm_fsm_dt <= "11";
            frm_fsm_ns <= IDLES;
        -- wait a time between packets
        when IDLES =>
            dly_ctr_ld <= '1';
            frm_len_ctr_ld <= '1';
            frm_len_ctr_en <= '0';
            frm_fsm_dt <= "11";
            if start_frame then
                frm_fsm_ns <= SOFS;
            else
                frm_fsm_ns <= IDLES;
            end if;
        -- mark the SOF for the GT interface
        when SOFS =>
            dly_ctr_ld <= '1';
            frm_len_ctr_ld <= '0';
            frm_len_ctr_en <= tready;
            frm_fsm_dt <= "00";--just some garbage
            if fsm_ce = '1' then
                frm_fsm_ns <= PLDS;
            else
                frm_fsm_ns <= SOFS;
            end if;
        -- send the IPBus packet data
        when PLDS =>
            dly_ctr_ld <= '1';
            frm_len_ctr_ld <= '0';
            frm_len_ctr_en <= tready;
            frm_fsm_dt <= "01";-- this would be real IBPbus data, headers and all
            if tready = '1' then
                if frm_len_ctr_tc = '1' then
                    frm_fsm_ns <= EOFS;
                else
                    frm_fsm_ns <= PLDS;
                end if;
            else
                frm_fsm_ns <= PLDS;
            end if;
        -- mark the EOF for the GT interface
        when EOFS =>
            dly_ctr_ld <= '1';
            frm_len_ctr_ld <= '0';
            frm_len_ctr_en <= '0';
            frm_fsm_dt <= "10";
            if fsm_ce = '1' then
                frm_fsm_ns <= PAUSES;
            else
                frm_fsm_ns <= EOFS;
            end if;
        -- pause between frames
        when PAUSES =>            
            dly_ctr_ld <= '0';
            frm_len_ctr_ld <= '0';
            frm_len_ctr_en <= '0';
            frm_fsm_dt <= "11";
            if dly_ctr_tc = '1' then
                frm_fsm_ns <= IDLES;
            else
                frm_fsm_ns <= PAUSES;
            end if;
        when others =>            
            dly_ctr_ld <= '1';
            frm_len_ctr_ld <= '0';
            frm_len_ctr_en <= '0';
            frm_fsm_dt <= "11";
            frm_fsm_ns <= IDLES;
        end case;
    end process;

    ------------------------------------------------------------------
    -- Framing state machine sync portion.
    ------------------------------------------------------------------
    frm_fsm_s_pcs : process(user_clk)
    begin
        if(user_clk'event and user_clk = '1') then
            if reset = '1' then
                frm_fsm_cs <= RESETS;
            else
                frm_fsm_cs <= frm_fsm_ns;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Frame generator
    ----------------------------------------------------------------
    frm_gen_pcs : process(user_clk)
    begin
        if(user_clk'event and user_clk = '1') then
            -- load a random value for frame length ------------------
            if reset = '1' then
                frm_len_lfsr <= (others => '0');
            else
                frm_len_lfsr <= (frm_len_lfsr(9) xnor frm_len_lfsr(5)) & frm_len_lfsr(1 to (frm_len_lfsr'right-1));
            end if;
            if frm_len_ctr_ld  = '1' then
                frm_len_ctr_tc <= '0';
                --must be divisible by two for proper framing
                if frm_len_lfsr > MINLEN then
                    frm_len_ctr <= (frm_len_lfsr & '0');--MAXF;
                else
                    frm_len_ctr <= TO_UNSIGNED(MINLEN,frm_len_ctr'length);
                end if;
            else
                if frm_len_ctr_en = '1' then
                    if frm_len_ctr = 0 then
                        frm_len_ctr <= frm_len_ctr;
                        frm_len_ctr_tc <= '1';
                    else
                        frm_len_ctr <= frm_len_ctr - 1;
                        frm_len_ctr_tc <= '0';  
                    end if;
                end if;
            end if;
            -- use a systematic period for NCF XOFF generation ----------------
            if reset = '1' then
                nfc_xoff_ctr <= (others => '1');                
            else
                nfc_xoff_ctr <= nfc_xoff_ctr - 1;
            end if;
            nfc_xoff_ctr_tc <= '1' when nfc_xoff_ctr < 9 else '0';
            if frm_len_ctr < 7 then -- not too close to the end
                tx_nfc_xoff <= '0';
            else
                tx_nfc_xoff <= nfc_xoff_ctr_tc and channel_up;--this can be pipelined unlike TREADY logic
            end if;
            --create two data counters, one delayed, for interleaved 32-bit data stream -----------
            if reset = '1' then
                frm_dat_ctr0 <= (others => '1');
                frm_dat_ctr1 <= (others => '0');
            else
                if frm_dat_ctr_en = '1' then
                    frm_dat_ctr0 <= frm_dat_ctr0 + DINC;
                    frm_dat_ctr1 <= frm_dat_ctr1 + DINC;
                else
                    frm_dat_ctr0 <= frm_dat_ctr0;
                    frm_dat_ctr1 <= frm_dat_ctr1;
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Create a delay between packets.
    ----------------------------------------------------------------
    dly_ctr_pcs : process(user_clk)
    begin
        if(user_clk'event and user_clk = '1') then
            if reset = '1' then
                dly_lfsr <= TO_UNSIGNED(NFRM,dly_lfsr'length);
            else
                dly_lfsr <= (dly_lfsr(10) xnor dly_lfsr(7)) & dly_lfsr(1 to (dly_lfsr'right-1));
            end if;
            if dly_ctr_ld = '1' then
                if dly_lfsr > MINDLY then
                    dly_ctr <= dly_lfsr;--DLYM;
                else -- let the end of frame chars be sent
                    dly_ctr <= TO_UNSIGNED(MINDLY,dly_ctr'length);
                end if;
                dly_ctr_tc <= '0';
            else
                if dly_ctr > 0 then
                    dly_ctr <= dly_ctr - 1;
                    dly_ctr_tc <= '0';
                else
                    dly_ctr <= dly_ctr;
                    dly_ctr_tc <= '1';
                end if;
            end if;
        end if;
    end process;

end behave;

