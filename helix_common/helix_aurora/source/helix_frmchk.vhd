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
--*********************************************************************************
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity helix_frmchk is
generic(
    DWDT                            : integer := 32;--the data width of this checker    
    KWDT                            : integer := 2;
    NFRM                            : integer := 6);
port(
    -- System Interface
    user_clk                        : in  std_logic;
    reset                           : in  std_logic;
    channel_up                      : in  std_logic;
    -- User Interface
    tuser                           : in  std_logic;
    tlast                           : in  std_logic;
    tvalid                          : in  std_logic;
    tdata                           : in  std_logic_vector(0 to DWDT-1);
    tkeep                           : in  std_logic_vector(0 to KWDT-1);
    err_count                       : out std_logic_vector(7 downto 0));
end helix_frmchk;

architecture behave of helix_frmchk is

    constant MAXF                   : integer                                   := NFRM-2;
    constant FRMSOF                 : std_logic_vector(0 to 15)                 := X"FEED";
    constant FRMEOF                 : std_logic_vector(0 to 15)                 := X"CAFE";
    constant CQD                    : time                                      := 1 ns; -- clock to Q delay for Aurora

    signal frm_len_ctr_en           : std_logic;
    signal frm_len_ctr_tc           : std_logic;
    signal frm_len_ctr              : integer range 0 to MAXF;

    signal frm_dat_ctr_en           : std_logic;
    signal frm_dat_ctr0             : unsigned(0 to 15);
    signal frm_dat_ctr1             : unsigned(0 to 15);
    signal frm_cmp_reg              : unsigned(0 to DWDT-1);
    signal frm_cmp_en               : std_logic;
    signal frm_cmp                  : std_logic;

    --signal frm_len_ctr_ld               : std_logic;
    signal frm_err_ctr_en           : std_logic;
    --signal frm_err_ctr_tc           : std_logic;
    signal frm_err_ctr              : unsigned(7 downto 0);

    signal dly_ctr_ld               : std_logic;
    signal dly_ctr_tc               : std_logic;
    signal dly_ctr                  : unsigned(7 downto 0);

    function DINC return positive is
        variable v : integer;
    begin
        if DWDT = 32 then
            v := 2;
        else
            v := 1;
        end if;
        return v;
    end function;

begin

    --not SOF, not EOF and data valid
    frm_len_ctr_en <= (not tuser) and (not tlast) and tvalid;
    frm_dat_ctr_en <= (not tuser) and (not tlast) and tvalid;
    dly_ctr_ld <= tlast and tvalid;

    gen_rx32bit : if DWDT = 32 generate
        frm_cmp <= '1' when frm_cmp_reg = (frm_dat_ctr0 & frm_dat_ctr1) else '0';
    end generate;

    gen_rx16bit : if DWDT = 16 generate        
        frm_cmp <= '1' when frm_cmp_reg = frm_dat_ctr1 else '0';
    end generate;

    --------------------------------------------------
    -- Pipeline to improve timing.
    --------------------------------------------------
    out_regs_pcs : process(user_clk)
    begin
        if(user_clk'event and user_clk = '1') then
            err_count <= STD_LOGIC_VECTOR(frm_err_ctr);
        end if;
    end process;

    ----------------------------------------------------------------
    -- Generate known patterns for comparison
    ----------------------------------------------------------------
    frm_gen_pcs : process(user_clk)
    begin
        if(user_clk'event and user_clk = '1') then
            if reset  = '1' then
                frm_len_ctr_tc <= '0';
                frm_len_ctr <= 0;
            else
                if frm_len_ctr_en then
                    if frm_len_ctr = MAXF then
                        frm_len_ctr <= 0;
                    else
                        frm_len_ctr <= frm_len_ctr + 1;
                    end if;
                end if;
                if frm_len_ctr = MAXF then
                    frm_len_ctr_tc <= '1';
                else
                    frm_len_ctr_tc <= '0';
                end if;
            end if;
            if reset = '1' then
                frm_dat_ctr0 <= X"FFFE";
                frm_dat_ctr1 <= X"FFFF";
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
    -- Compare know pattern to input
    ----------------------------------------------------------------
    frm_cmp_pcs : process(user_clk)
    begin
        if(user_clk'event and user_clk = '1') then
            frm_cmp_reg <= UNSIGNED(tdata);
            frm_cmp_en <= frm_dat_ctr_en;
            frm_err_ctr_en <= (frm_cmp_en and (not frm_cmp));
            if reset  = '1' then
                frm_err_ctr <= (others => '0');
            else
                if frm_err_ctr_en = '1' then
                    if frm_err_ctr < X"FF" then
                        frm_err_ctr <= frm_err_ctr + 1;
                    end if;
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
                dly_ctr <= (others => '1');
                dly_ctr_tc <= '0';
            else
                if dly_ctr_ld = '1' then
                    dly_ctr <= (others => '1');
                    dly_ctr_tc <= '1';
                else
                    dly_ctr <= dly_ctr - 1;
                    dly_ctr_tc <= '0';
                end if;
            end if;
        end if;
    end process;

end behave;

