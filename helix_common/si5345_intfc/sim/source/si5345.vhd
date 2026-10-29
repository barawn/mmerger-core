--*********************************************************************************
-- Indiana University
-- Center for Exploration of Energy and Matter (CEEM)
--
-- Project: HELIX
--
-- Author:  Brandon Kunkler
--
-- Date:    04/04/2018
--
--*********************************************************************************
--*********************************************************************************
-- Description:
--
-- si5345 register model.
--
-- Deficiencies/Known Issues:
--
--*********************************************************************************

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

entity si5345 is
port(
    rstb                        : in std_logic;
    sclk                        : in std_logic;-- SPI
    a0_csb                      : in std_logic;
    sda_sdio                    : in std_logic;
    a1_sdo                      : inout std_logic;-- Stat/Ctrl
    oeb                         : in std_logic;
    intrb                       : out std_logic;
    lolb                        : out std_logic);
end si5345;


architecture spi4_arch of si5345 is

    constant SETADR             : std_logic_vector(7 downto 0) := X"00";--Set Address
    constant WRDAT              : std_logic_vector(7 downto 0) := X"40";--Write Data
    constant RDDAT              : std_logic_vector(7 downto 0) := X"80";--Read Data
    constant WRDATAI            : std_logic_vector(7 downto 0) := X"70";--Write Data + Address Increment
    constant RDDATAI            : std_logic_vector(7 downto 0) := X"A0";--Read Data + Address Increment
    constant BWRDAT             : std_logic_vector(7 downto 0) := X"E0";--Burst Write Data
    constant PGADR              : std_logic_vector(7 downto 0) := X"01";--Burst Write Data

    type page_type is array (0 to 255) of std_logic_vector(7 downto 0);

    type reg_type is array(0 to 11) of page_type;

    signal scl                  : std_logic;
    signal cs                   : std_logic;
    signal mosi                 : std_logic;
    signal miso                 : std_logic;
    signal tri_state            : std_logic;

    signal rd_en                : std_logic;
    signal wr_en                : std_logic;
    signal adr_datn             : std_logic;
    signal cmd_datn             : std_logic;
    signal block_mode           : std_logic                         := '0';
    signal lsb                  : std_logic;
    signal cmd_valid            : std_logic;
    signal dat_valid            : std_logic;
    signal reg_valid            : std_logic;
    signal adr_valid            : std_logic;

    signal bit_idx              : integer range 0 to 15;
    signal adr_idx              : integer range 0 to 15;
    signal pag_adr              : unsigned(7 downto 0)              := (others => '0');
    signal reg_adr              : unsigned(7 downto 0)              := (others => '1');
    signal reg_val              : std_logic_vector(7 downto 0)      := (others => '1');
    signal inp_reg              : std_logic_vector(15 downto 0);
    signal cmd_reg              : std_logic_vector(7 downto 0)      := (others => '1');
    signal dat_reg              : std_logic_vector(7 downto 0)      := (others => '1');
    signal piso                 : std_logic_vector(7 downto 0);
    signal dev_regs             : reg_type;

    --alias cmd_reg : std_logic_vector(7 downto 0) is inp_reg(15 downto 8);
    --alias dat_reg : std_logic_vector(7 downto 0) is inp_reg(7 downto 0);

begin

--------------------------------------------------------------------------------
-- Concurrent statements
--------------------------------------------------------------------------------

    -- pin to host mode function
    mosi   <= sda_sdio;
    a1_sdo <= miso;
    scl    <= sclk;
    cs     <= a0_csb;

    lsb <= '1' when bit_idx=0 else '0';
    miso <= piso(piso'left) when tri_state = '0' else 'Z';

    intrb <=  '0', '1' after 100 ns;--need a better way to drive these! find soft reset?
    lolb  <= '0', '1' after 200 ns;

    adr_datn <= '1' when ((cmd_datn='0') and cmd_reg=SETADR) else '0';
    rd_en   <= '1' when ((cmd_reg=RDDAT) or (cmd_reg=RDDATAI)) else '0';
    wr_en   <= '1' when ((cmd_reg=WRDAT) or (cmd_reg=WRDATAI)) else '0';

    -------------------------------------------------------
    -- Generate the device internal registers
    -------------------------------------------------------
    --tri_state <= '1' when ((bit_idx>7) and (TO_INTEGER(UNSIGNED(cmd_reg))>0)) else '0';
    tri_state_pcs : process
    begin
        while(TRUE) loop
            tri_state <= '1';
            wait until cmd_reg = RDDAT;
            tri_state <= '0';
            wait until rising_edge(cs);
        end loop;
    end process;

    -------------------------------------------------------
    -- Generate the device internal registers
    -------------------------------------------------------
    read_pcs : process(scl,cs)
    begin
         --if CS goes high clear/abort
        if cs = '1' then
            bit_idx <= 15;
        else
        --if CS goes low activate
            if rising_edge(scl) then
                --count bits in message
                if bit_idx > 0 then
                    bit_idx <= bit_idx - 1;
                else
                    bit_idx <= 15;
                end if;
            end if;
        end if;
        if rising_edge(scl) then
            inp_reg(bit_idx) <= mosi;
        end if;
        if falling_edge(scl) then
            cmd_datn <= '1' when bit_idx > 7 else '0';
        end if;
        if rising_edge(scl) then
            if bit_idx = 8 then
                cmd_valid <= '1';
            else
                cmd_valid <= '0';
            end if;
            if bit_idx = 0 then
                dat_valid <= '1';
            else
                dat_valid <= '0';
            end if;
        end if;
        if falling_edge(scl) then
            -- capture the address
            if cmd_valid then
                cmd_reg <= inp_reg(15 downto 8);
            end if;
            if dat_valid then
                dat_reg <= inp_reg(7 downto 0);
            end if;
        end if;
        if falling_edge(scl) then
            reg_valid <= dat_valid;
            adr_valid <= reg_valid;
            -- block mode if keep clocking without CS
            if reg_valid then
                if ((cmd_reg=WRDATAI) or (cmd_reg=RDDATAI) or (cmd_reg=BWRDAT)) then
                    block_mode <= '1';
                else
                    block_mode <= '0';
                end if;
                -- increment address if block mode
                if (block_mode='1') and (lsb='1') then
                    reg_adr <= reg_adr + 1;
                else
                    --if adr_datn then
                    if cmd_reg=SETADR then
                        reg_adr <= UNSIGNED(dat_reg);
                    end if;
                    if ((cmd_reg=WRDAT) or (cmd_reg=WRDATAI)) then
                        if (reg_adr=UNSIGNED(PGADR)) then
                            pag_adr <= UNSIGNED(dat_reg);
                        end if;
                    end if;
                end if;
            end if;
            if reg_valid then
                if ((cmd_reg=WRDAT) or (cmd_reg=WRDATAI)) then
                    reg_val <= dat_reg;
                end if;
            end if;
        end if;
        if falling_edge(scl) then
            if tri_state then-- load PISO
                piso <= dev_regs(TO_INTEGER(pag_adr))(TO_INTEGER(reg_adr));
            else-- shift PISO data
                piso <= piso(piso'left-1 downto 0) & '0';
            end if;
        end if;
    end process;

    write_pcs : process(all)
    begin
        -- capture input data using address
        if rising_edge(scl) then--last value is not written because no clock!!!!!!!!!
            if (wr_en and adr_valid) then
                dev_regs(TO_INTEGER(pag_adr))(TO_INTEGER(reg_adr)) <= reg_val;
            end if;
        end if;
    end process;
--------------------------------------------------------------------------------

 end spi4_arch;
