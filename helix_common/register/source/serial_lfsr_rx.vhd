--*********************************************************************************
-- Indiana University
-- Center for Exploration of Energy and Matter (CEEM)
--
-- Project: HELIX
--
-- Author:  Brandon Kunkler
--
-- Date:    01/13/2019
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
-- Generates data patterns for testing serial timing and trigger interface signals.
--
-- Deficiencies:
--*********************************************************************************
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

entity serial_lfsr_rx is
generic(
    DWDT                            : positive   := 16;
    SEED                            : positive   := 202);
port(
    -- clock / reset     ---------------
    clk                             : in std_logic;
    reset                           : in std_logic;
    -- FEX interface  ---------------
    din                             : in std_logic;
    locked                          : out std_logic;
    bit_err                         : out std_logic;
    num_err                         : out std_logic_vector(7 downto 0));
end serial_lfsr_rx;

---------------------------------------------------------------------------------------------------------
-- Architecture declaration
---------------------------------------------------------------------------------------------------------
architecture behave of serial_lfsr_rx is

    constant PDLY                   : positive := 2;     --processing delay, comma detect to data
    constant RWDT                   : positive := DWDT+2;--processing delay, comma detect to data
    constant USEED                  : unsigned := TO_UNSIGNED(SEED,DWDT);
    constant BWDT                   : integer  := INTEGER(CEIL(LOG2(REAL(DWDT))));

    type rx_fsm_type is (IDLES,SEARCHS,LOCKS,VALIDS,ERRORS);

    signal rx_lfsr                  : std_logic_vector(1 to DWDT);
    signal sipo                     : std_logic_vector(1 to RWDT);--a few bits larger than TX

    signal bit_ctr_ld               : std_logic;
    signal bit_ctr_tc               : std_logic;
    signal bit_ctr                  : unsigned(BWDT-1 downto 0);

    signal vld_ctr_ld               : std_logic;
    signal vld_ctr_tc               : std_logic;
    signal vld_ctr                  : unsigned(3 downto 0);

    signal err_ctr_ld               : std_logic;
    signal err_ctr                  : unsigned(7 downto 0);

    signal rx_lfsr_ld               : std_logic;
    signal comma_vld                : std_logic;
    signal data_vld                 : std_logic;
    signal comp_vld                 : std_logic_vector(PDLY-1 downto 0);
    signal lock_vld                 : std_logic;
    signal link_err                 : std_logic;
    signal fsm_locked               : std_logic;

    signal rx_fsm_cs                : rx_fsm_type;

    alias comma_reg : std_logic_vector(1 to 16) is sipo(PDLY+1 to RWDT);
    alias data_reg  : std_logic_vector(1 to 16) is sipo(1 to DWDT);

begin
------------------------------------------------------------------------------------------------
-- Component instantiations
------------------------------------------------------------------------------------------------

    -----------------------------------

------------------------------------------------------------------------------------------------
-- Concurrent statements
------------------------------------------------------------------------------------------------




------------------------------------------------------------------------------------------------
-- Asynchronous and Synchronous processes.
------------------------------------------------------------------------------------------------

    ---------------------------------------------
    -- Generate fake TOB data values.
    ---------------------------------------------
    data_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if rx_lfsr_ld then
                rx_lfsr <= STD_LOGIC_VECTOR(USEED);
            else
                if bit_ctr_tc then
                    -- pseudo-random data receive (for compare)
                    rx_lfsr <= (rx_lfsr(16) xnor rx_lfsr(15) xnor rx_lfsr(13) xnor rx_lfsr(4)) & rx_lfsr(1 to (rx_lfsr'right-1));
                end if;
            end if;
            --sipo <= din & sipo(1 to 15);
            sipo <= sipo(2 to 18) & din;
            comma_vld <= '1' when UNSIGNED(comma_reg) = USEED else '0';
            data_vld  <= '1' when data_reg = rx_lfsr else '0';
            comp_vld  <= bit_ctr_tc & comp_vld(comp_vld'length-1 downto 1);
            lock_vld  <= data_vld and comp_vld(0);
            link_err  <= comp_vld(0) and (not data_vld);
            num_err   <= STD_LOGIC_VECTOR(err_ctr);
            locked    <= fsm_locked;
        end if;
    end process;

    ---------------------------------------------
    -- Count number of valid words.
    ---------------------------------------------
    bit_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if bit_ctr_ld = '1' then
                bit_ctr <= (others => '1');
            else -- down count
                bit_ctr <= bit_ctr - '1';
            end if;
            -- terminal logic
            if bit_ctr = 1 then
                bit_ctr_tc <= '1';
            else
                bit_ctr_tc <= '0';
            end if;
        end if;
    end process;

    ---------------------------------------------
    -- Count number of valid words.
    ---------------------------------------------
    vld_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if vld_ctr_ld = '1' then
                vld_ctr <= (others => '1');
            else -- down count
                if lock_vld then
                    vld_ctr <= vld_ctr - '1';
                end if;
            end if;
            -- terminal logic
            if vld_ctr = 0 then
                vld_ctr_tc <= '1';
            else
                vld_ctr_tc <= '0';
            end if;
        end if;
    end process;

    ---------------------------------------------
    -- Count number of valid words.
    ---------------------------------------------
    err_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if err_ctr_ld = '1' then
                err_ctr <= (others => '0');
            else -- down count
                if link_err then
                    err_ctr <= err_ctr + 1;
                end if;
            end if;
        end if;
    end process;

    -----------------------------------------------------------------
    -- Control the receiver locking process and check for errors.
    -----------------------------------------------------------------
    out_fsm_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                rx_lfsr_ld <= '1';
                bit_ctr_ld <= '1';
                vld_ctr_ld <= '1';
                err_ctr_ld <= '1';
                bit_err    <= '0';
                fsm_locked <= '0';
                rx_fsm_cs <= IDLES;
            else
                case rx_fsm_cs is
                --when IDLES =>
                --    rx_lfsr_ld <= '1';
                --    bit_ctr_ld <= '1';
                --    vld_ctr_ld <= '1';
                --    err_ctr_ld <= '1';
                --    bit_err    <= '0';
                --    fsm_locked <= '0';
                --    rx_fsm_cs <= SEARCHS;
                --when SEARCHS =>
                when IDLES =>
                    rx_lfsr_ld <= '1';                    
                    vld_ctr_ld <= '1';
                    err_ctr_ld <= '1';
                    bit_err    <= '0';
                    fsm_locked <= '0';
                    if comma_vld then
                        bit_ctr_ld <= '0';
                        rx_fsm_cs <= LOCKS;
                    else
                        bit_ctr_ld <= '1';
                        --rx_fsm_cs <= SEARCHS;
                        rx_fsm_cs <= IDLES;
                    end if;
                when LOCKS =>
                    rx_lfsr_ld <= '0';
                    bit_ctr_ld <= '0';
                    vld_ctr_ld <= '0';
                    err_ctr_ld <= '1';
                    bit_err    <= '0';
                    fsm_locked <= '0';
                    if link_err then
                        rx_fsm_cs <= IDLES;
                    else
                        if vld_ctr_tc = '1' then
                            rx_fsm_cs <= VALIDS;
                        else
                            rx_fsm_cs <= LOCKS;
                        end if;
                    end if;
                when VALIDS =>
                    rx_lfsr_ld <= '0';
                    bit_ctr_ld <= '0';
                    vld_ctr_ld <= '1';
                    err_ctr_ld <= '0';
                    fsm_locked <= '1';
                    if link_err then
                        bit_err <= '1'; --sticky bit when error
                    else
                        bit_err <= bit_err;
                    end if;
                    rx_fsm_cs <= VALIDS;
                when others =>
                    rx_lfsr_ld <= '1';
                    bit_ctr_ld <= '1';
                    vld_ctr_ld <= '1';
                    err_ctr_ld <= '1';
                    bit_err    <= '0';
                    fsm_locked <= '0';
                    rx_fsm_cs <= IDLES;
                end case;
            end if;
        end if;
    end process;

end behave;
