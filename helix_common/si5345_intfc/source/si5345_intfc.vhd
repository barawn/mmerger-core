--*********************************************************************************
-- Indiana University
-- Center for Exploration of Energy and Matter (CEEM)
--
-- Project: HELIX
--
-- Author:  Brandon Kunkler
--
-- Date:    11/08/2018
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
-- Four-wire SPI interface to SI5345. Writes pre-amble, waits, writes configuration
-- registers, reads back pre-amble + configuration registers, writes post-amble. The
-- post-amble writes over pre-amble values so the post-amble is written after the
-- configuration registers. The generics allow for configuration of pre/post-amble
-- size. Assumes data is stored in a ROM.
--
-- Know Issues:
-- The post-amble is not read back and verified.
--*********************************************************************************

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.math_real.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_misc.all;
library unisim;
    use unisim.vcomponents.all;

entity si5345_intfc is
generic(
    SCLKPER                             : real    := 50.0;  --serial clock period in ns
    NREGS                               : integer := 128;-- number of config registers
    NPREAMBL                            : integer := 3;-- number of registers in pre-amble
    NPSTAMBL                            : integer := 3;-- number of registers in post-amble
    PHASE_VAL                           : integer := 8;-- adjust delay between data and clock
    SIM_SPDUP                           : boolean := FALSE;
    USE_ILA                             : boolean := FALSE);
port(
    clk                                 : in std_logic;
    ce                                  : in std_logic;
    strobe                              : in std_logic;
    reset                               : in std_logic;
    -- fabric interface
    cfg_enbl                            : in std_logic;
    cfg_done                            : out std_logic;
    rdb_err                             : out std_logic;
    -- field programmer interface
    fp_sclk                             : in std_logic;-- SPI
    fp_a0_csb                           : in std_logic;
    fp_sda_sdio                         : in std_logic;
    fp_a1_sdo                           : out std_logic;-- Stat/Ctrl
    -- si5345 interface
    si_ifen                             : out std_logic;
    si_rstb                             : out std_logic;
    si_sclk                             : out std_logic;-- SPI
    si_a0_csb                           : out std_logic;
    si_sda_sdio                         : out std_logic;
    si_a1_sdo                           : in std_logic;-- Stat/Ctrl
    si_oeb                              : out std_logic;
    si_intrb                            : in std_logic;
    si_lolb                             : in std_logic);
end si5345_intfc;

-------------------------------------------------------------------------------
-- Architecture for writing, reading, and verifying data for production use.
-------------------------------------------------------------------------------
architecture rdwr_arch of si5345_intfc is

    component si5345_ila
    port (
        clk                             : in std_logic;
        probe0                          : in std_logic_vector(0  downto 0);
        probe1                          : in std_logic_vector(0  downto 0);
        probe2                          : in std_logic_vector(0  downto 0);
        probe3                          : in std_logic_vector(0  downto 0);
        probe4                          : in std_logic_vector(0  downto 0);
        probe5                          : in std_logic_vector(0 downto 0);
        probe6                          : in std_logic_vector(0  downto 0);
        probe7                          : in std_logic_vector(0 downto 0);
        probe8                          : in std_logic_vector(9 downto 0);
        probe9                          : in std_logic_vector(31 downto 0);
        probe10                         : in std_logic_vector(0  downto 0);
        probe11                         : in std_logic_vector(15 downto 0);
        probe12                         : in std_logic_vector(15 downto 0);
        probe13                         : in std_logic_vector(15 downto 0);
        probe14                         : in std_logic_vector(15 downto 0);
        probe15                         : in std_logic_vector(0  downto 0);
        probe16                         : in std_logic_vector(7  downto 0));
    end component;

    --constant DWDT                       : integer := 32;-- data width
    constant MAX_CFG                    : integer := NREGS-1;--test
    --constant ASIC_REGS                  : integer := 1144;
    --constant RDPAUSE                    : integer := ASIC_REGS-2;--test
    constant NBIT                       : integer                               := 8;      --numbers of bits in a SI5345 register
    constant NTRACT                     : integer                               := NBIT*2; --number of registers per SI5345 transaction (instruction + value)
    constant NSHFT                      : integer                               := (NTRACT+2)*4;--numbers of bits to shift for a read/write cycle, add 2 CS cycles
    constant RDPAUSE                    : integer                               := 67;
    --constant PAUSEW                     : integer                               := INTEGER(CEIL(LOG2(REAL(RDPAUSE))));
    constant ENDIANESS                  : string                                := "LTL";--BIG or LTL
    constant CSROMVAL                   : std_logic_vector(NSHFT-1 downto 0)    := 72UX"C00030000C0003";
    constant PREAMBTM                   : real                                  := 900000000.0;-- preamble calibration time in ns

    constant SETADR                     : std_logic_vector(7 downto 0)          := X"00";--Set Address
    constant WRDAT                      : std_logic_vector(7 downto 0)          := X"40";--Write Data
    constant RDDAT                      : std_logic_vector(7 downto 0)          := X"80";--Read Data
    constant WRDATAI                    : std_logic_vector(7 downto 0)          := X"70";--Write Data + Address Increment
    constant RDDATAI                    : std_logic_vector(7 downto 0)          := X"A0";--Read Data + Address Increment
    constant BWRDAT                     : std_logic_vector(7 downto 0)          := X"E0";--Burst Write Data
    constant PGADR                      : std_logic_vector(7 downto 0)          := X"01";--page address

    function PREVAL(sp : boolean; rv : real; ckp : real) return natural is
        constant SV         : real      := 30080.0;
        variable outp       : natural;
    begin
        if sp then
            outp := INTEGER(CEIL(SV/ckp));
        else
            outp := INTEGER(CEIL(rv/ckp));
        end if;
        return outp;
    end function;

    constant PREAMBTC                   : natural                               := PREVAL(SIM_SPDUP,PREAMBTM,SCLKPER);

    type fsm_type is (INITS,WLOADS,WRITES,PREAMBS,PREPSS,SHFTPSS,READPSS,READS,VERIFYS,DONES);

    signal si_ifen_q0                   : std_logic;
    signal si_rstb_q0                   : std_logic;
    signal si_sclk_q0                   : std_logic;-- SPI
    signal si_a0_csb_q0                 : std_logic;
    signal si_sda_sdio_q0               : std_logic;
    signal si_a1_sdo_q0                 : std_logic;-- Stat/Ctrl
    signal si_oeb_q0                    : std_logic;
    signal si_intrb_q0                  : std_logic;
    signal si_lolb_q0                   : std_logic;
    signal si_intrb_q1                  : std_logic;
    signal si_lolb_q1                   : std_logic;

    signal fsm_cs                       : fsm_type;
    signal fsm_ifen                     : std_logic;
    signal fsm_rstb                     : std_logic;
    signal fsm_sclk_en                  : std_logic;
    --signal fsm_a0_csb                   : std_logic;
    signal fsm_cfg_done                 : std_logic;
    signal rwcmd                        : std_logic_vector(7 downto 0);
    signal cfg_adr_ld                   : std_logic;
    signal cfg_adr_en                   : std_logic;
    signal cfg_wra_tc                   : std_logic;
    signal cfg_rda_tc                   : std_logic;
    signal cfg_pre_tc                   : std_logic;
    signal cfg_pst_tc                   : std_logic;
    signal cfg_adr                      : integer range 0 to MAX_CFG;
    signal cfg_rom_out                  : std_logic_vector(31 downto 0)     := (others => '0');
    signal rdbkadr_en                   : std_logic;
    signal rdbkcmp_en                   : std_logic;
    signal piso_ld                      : std_logic;
    signal piso                         : std_logic_vector(NSHFT-1 downto 0);--parallel data in serial out
    signal csrom                        : std_logic_vector(NSHFT-1 downto 0);--ROM for CS signal
    signal sipo_rdy                     : std_logic;
    signal sipo                         : std_logic_vector(7 downto 0);--serial in parallel data out
    signal rdbk_data                    : std_logic_vector(7 downto 0);
    signal vrfy_data                    : std_logic_vector(7 downto 0);
    signal bit_ctr_ld                   : std_logic;
    signal bit_ctr_tc                   : std_logic;
    signal bit_ctr_rd                   : std_logic;
    signal bit_ctr                      : natural range 0 to NSHFT-1;
    signal preamb_ctr_ld                : std_logic;
    signal preamb_ctr_tc                : std_logic;
    signal preamb_ctr                   : natural range 0 to PREAMBTC;

    signal pause_ctr_ld                 : std_logic;
    signal pause_ctr_tc                 : std_logic;
    signal pause_ctr                    : natural range 0 to RDPAUSE;
    signal phase_reg                    : std_logic_vector(PHASE_VAL-1 downto 0);    
    
    signal reg_sclk                     : std_logic;    

    alias set_pag_adr : std_logic_vector(15 downto 0) is piso(71 downto 56);
    alias set_pag_dat : std_logic_vector(15 downto 0) is piso(53 downto 38);
    alias set_val_adr : std_logic_vector(15 downto 0) is piso(35 downto 20);
    alias get_val_dat : std_logic_vector(15 downto 0) is piso(17 downto 2);

    attribute ASYNC_REG : string;    
    attribute ASYNC_REG of si_intrb_q0      : signal is "TRUE";
    attribute ASYNC_REG of si_lolb_q0       : signal is "TRUE";
    attribute ASYNC_REG of si_intrb_q1      : signal is "TRUE";
    attribute ASYNC_REG of si_lolb_q1       : signal is "TRUE";

begin


--------------------------------------------------------------------------
-- Component instantiations
--------------------------------------------------------------------------

    ------------------------------------------------------------------
    -- Create a ROM to be used as a LUT for all configuration.
    -- The device has a block write function. Try to write the last
    -- (reset) address then wrap to the lower addresses.
    ------------------------------------------------------------------
    cfg_ram_ins : entity work.si5345_cfg_ram(cfg_ram_arch)
    port map(
        clk                             => clk,
        ce                              => '1',--bit_ctr_tc
        reset                           => '0',--reset,
        wren                            => '0',--tie low to make a ROM
        wr_adr                          => (others => '0'),
        wr_data                         => (others => '0'),
        cfg_adr                         => cfg_adr,
        cfg_out                         => cfg_rom_out
    );

    ------------------------------------------------------------------
    -- ILA for test.
    ------------------------------------------------------------------
    ila_gen : if USE_ILA = TRUE generate
        si5345_ila_ins : si5345_ila
        port map (
            clk                         => clk,
            probe0(0)                   => si_sclk_q0,    
            probe1(0)                   => si_a0_csb_q0,  
            probe2(0)                   => si_sda_sdio_q0,
            probe3(0)                   => si_a1_sdo_q0,  
            probe4(0)                   => si_intrb_q0,  
            probe5(0)                   => si_lolb_q0,  
            probe6(0)                   => rdb_err,  
            probe7(0)                   => cfg_done,  
            probe8                      => STD_LOGIC_VECTOR(TO_UNSIGNED(cfg_adr,10)),
            probe9                      => cfg_rom_out,
            probe10(0)                  => piso_ld,
            probe11                     => set_pag_adr,
            probe12                     => set_pag_dat,
            probe13                     => set_val_adr,
            probe14                     => get_val_dat,
            probe15(0)                  => sipo_rdy,
            probe16                     => sipo
        );
    end generate;

--------------------------------------------------------------------------
-- Concurrent Statements
--------------------------------------------------------------------------

    --map signals to ports
    si_ifen     <= si_ifen_q0;
    si_rstb     <= si_rstb_q0;
    si_sclk     <= si_sclk_q0;
    si_a0_csb   <= si_a0_csb_q0;
    si_sda_sdio <= si_sda_sdio_q0;
    si_oeb      <= si_oeb_q0;

    -- internal
    -- these may need to registered for timing, but what will happen to functionality?
    cfg_adr_en <= bit_ctr_tc and ce and preamb_ctr_ld and (not fsm_cfg_done);
    cfg_wra_tc <= '1' when cfg_adr = (MAX_CFG-NPSTAMBL-1) else '0';--!!!must add post amble check logic
    cfg_rda_tc <= '1' when cfg_adr = (MAX_CFG-NPSTAMBL-1) else '0';
    cfg_pre_tc <= '1' when cfg_adr = (NPREAMBL-1) else '0';--!!!must add post amble check logic
    cfg_pst_tc <= '1' when cfg_adr = MAX_CFG else '0';--!!!must add post amble check logic
    reg_sclk <= phase_reg(phase_reg'left) and fsm_sclk_en;   -- adjust clock phase to compensate for internal delays
    piso_ld <= bit_ctr_tc and (not cfg_adr_ld) and preamb_ctr_ld;

    csrom <= CSROMVAL;

    ------------------------------------------------------------------
    -- Pipeline outputs.
    ------------------------------------------------------------------
    pipe_pcs : process(clk)
    begin
        if (clk'event and clk='1') then

            -- inputs -------------
            si_a1_sdo_q0    <= si_a1_sdo;
            si_intrb_q0     <= si_intrb;
            si_lolb_q0      <= si_lolb;
            si_intrb_q1     <= si_intrb_q0;
            si_lolb_q1      <=  si_lolb_q0;

            -- outputs --------------
            si_ifen_q0      <= fsm_ifen;
            si_rstb_q0      <= fsm_rstb;
            si_oeb_q0       <= '0';
            si_sclk_q0      <= reg_sclk;
            si_a0_csb_q0    <= csrom(bit_ctr) or (not preamb_ctr_ld);
            si_sda_sdio_q0  <= piso(piso'left);           

            cfg_done  <= fsm_cfg_done;            

            -- internal ---------------
            -- shift the strobe for phase adjustment
            phase_reg <= phase_reg(phase_reg'left-1 downto 0) & strobe;
            rwcmd <= RDDAT when rdbkadr_en else WRDAT;--swap read and write command depending on state/mode
        end if;
    end process;

    ------------------------------------------------------------------
    -- Compare serial read-back data to ROM read-back data. Assert
    -- an error if they don't match.
    ------------------------------------------------------------------
    valid_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                vrfy_data <= (others => '0');
                rdbkcmp_en <= '0';
                rdbk_data <= (others => '0');
                rdb_err <= '0';
            else
                if ce then
                    vrfy_data <= rdbk_data;
                    if bit_ctr_tc then
                        rdbkcmp_en <= rdbkadr_en;
                    end if;
                    --if cfg_adr_en and rdbkcmp_en then
                    if cfg_adr_en and rdbkadr_en then
                        rdbk_data <= cfg_rom_out(7 downto 0);
                    end if;
                end if;
                if sipo_rdy = '1' then
                    if vrfy_data /= sipo then
                        rdb_err <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Simple state machine to control streaming of config data.
    ------------------------------------------------------------------
    fsm_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                fsm_ifen <= '1';
                fsm_rstb <= '0';--!?'1';
                fsm_sclk_en <= '0';
                bit_ctr_ld <= '1';
                preamb_ctr_ld <= '1';
                pause_ctr_ld <= '1';
                rdbkadr_en <= '0';
                cfg_adr_ld <= '1';
                --fsm_a0_csb <= '1';
                fsm_cfg_done <= '0';
                fsm_cs <= INITS;
            else
                if ce = '1' then
                    case fsm_cs is
                    when INITS =>
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '0';
                        bit_ctr_ld <= '1';
                        preamb_ctr_ld <= '0';
                        pause_ctr_ld <= '1';
                        rdbkadr_en <= '0';
                        cfg_adr_ld <= '1';
                        --fsm_a0_csb <= '1';
                        fsm_cfg_done <= '0';
                        if preamb_ctr_tc then--wait for reset recovery, re-use counter, > 750 ms
                            fsm_cs <= WLOADS;
                        else
                            fsm_cs <= INITS;
                        end if;
                    when WLOADS => -- load counters, get ready
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '0';
                        bit_ctr_ld <= '0';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '1';
                        rdbkadr_en <= '0';
                        cfg_adr_ld <= '0';
                        --fsm_a0_csb <= '1';
                        fsm_cfg_done <= '0';
                        if bit_ctr_tc then
                            fsm_cs <= WRITES;
                        else
                            fsm_cs <= WLOADS;
                        end if;
                    when WRITES => -- write values to registers
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '1';
                        rdbkadr_en <= '0';
                        cfg_adr_ld <= '0';-- increment ROM address
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        if bit_ctr_tc then
                            --? this is a sketchy thing to do
                            if cfg_pre_tc then   --pre-amble
                                fsm_cs <= PREPSS;
                            elsif cfg_wra_tc then--config-regs
                                fsm_cs <= READPSS;
                            elsif cfg_pst_tc then--post-amble
                                fsm_cs <= DONES;
                            else
                                fsm_cs <= WRITES;
                            end if;
                        end if;
                    when PREPSS => -- pause for last register write
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';
                        rdbkadr_en <= '0';
                        cfg_adr_ld <= '0';
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        if pause_ctr_tc then
                            --bit_ctr_ld <= '0';
                            preamb_ctr_ld <= '1';
                            pause_ctr_ld <= '0';
                            fsm_cs <= PREAMBS;
                        else
                            --bit_ctr_ld <= '1';
                            preamb_ctr_ld <= '1';
                            pause_ctr_ld <= '0';
                            fsm_cs <= PREPSS;
                        end if;
                    when PREAMBS => -- pause pre-amble
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';
                        rdbkadr_en <= '0';
                        cfg_adr_ld <= '0';
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        if  bit_ctr_tc and preamb_ctr_tc then
                            preamb_ctr_ld <= '1';
                            fsm_cs <= WRITES;
                        else
                            preamb_ctr_ld <= '0';
                            fsm_cs <= PREAMBS;
                        end if;
                    when READPSS => -- pause for last register write
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';
                        preamb_ctr_ld <= '1';
                        rdbkadr_en <= '0';
                        cfg_adr_ld <= '1';
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        if pause_ctr_tc then
                            --bit_ctr_ld <= '0';
                            pause_ctr_ld <= '1';
                            fsm_cs <= READS;
                        else
                            --bit_ctr_ld <= '1';
                            pause_ctr_ld <= '0';
                            fsm_cs <= READPSS;
                        end if;
                    when READS => -- finish reading last word
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '1';
                        rdbkadr_en <= '1';
                        cfg_adr_ld <= '0';-- increment ROM address
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        if bit_ctr_tc and cfg_rda_tc then
                            fsm_cs <= VERIFYS;
                        else
                            fsm_cs <= READS;
                        end if;
                    when VERIFYS => -- verify the last last word
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '0';
                        --fsm_a0_csb <= '0';
                        cfg_adr_ld <= '0';-- increment ROM address
                        fsm_cfg_done <= '0';
                        if pause_ctr_tc then
                            rdbkadr_en <= '0';
                            --fsm_cs <= DONES;
                            fsm_cs <= WRITES;
                        else
                            rdbkadr_en <= '1';
                            fsm_cs <= VERIFYS;
                        end if;
                    when DONES => -- stay here when finished
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        preamb_ctr_ld <= '1';
                        rdbkadr_en <= '0';
                        pause_ctr_ld <= '0';
                        fsm_cfg_done <= (si_intrb_q1 or si_lolb_q1);--wait for lock, intr should also be used?
                        if pause_ctr_tc then
                            fsm_sclk_en <= '0';
                            bit_ctr_ld <= '1';
                            cfg_adr_ld <= '1';
                            --fsm_a0_csb <= '0';
                            --fsm_cfg_done <= '1';
                        else
                            fsm_sclk_en <= '1';
                            bit_ctr_ld <= '0';                            
                            cfg_adr_ld <= '0';
                            --fsm_a0_csb <= '1';
                            --fsm_cfg_done <= '0';                            
                        end if;
                        if cfg_enbl then
                            fsm_cs <= INITS;
                        else
                            fsm_cs <= DONES;
                        end if;
                    when others =>
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '0';
                        bit_ctr_ld <= '1';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '1';
                        rdbkadr_en <= '0';
                        cfg_adr_ld <= '1';
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        fsm_cs <= INITS;
                    end case;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Shift register for writing.
    ------------------------------------------------------------------
    piso_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                piso <= (others => '0');
            else
                if ce = '1' then
                    if piso_ld = '1' then
                        piso <= SETADR & PGADR & "11" & WRDAT & cfg_rom_out(31 downto 24) & "11" & SETADR & cfg_rom_out(23 downto 16) & "11" & rwcmd & cfg_rom_out(7 downto 0) & "11";
                    else
                        piso <= piso(piso'left-1 downto 0) & '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Shift register for reading.
    ------------------------------------------------------------------
    sipo_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                sipo_rdy <= '0';
                sipo <= (others => '0');
            else
                if ce = '1' then
                    sipo_rdy <= '1' when (bit_ctr_rd='1' and (rdbkadr_en and rdbkcmp_en)='1') else '0';
                    sipo <=  sipo(sipo'left-1 downto 0) & si_a1_sdo_q0;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Count the number bits written/read.
    ------------------------------------------------------------------
    bit_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if bit_ctr_ld then
                bit_ctr_tc <= '1';
                bit_ctr_rd <= '1';
                bit_ctr <= 0;
            else
                if ce = '1' then
                    bit_ctr_tc <= '1' when bit_ctr = 1 else '0'; -- count bits in word
                    bit_ctr_rd <= '1' when bit_ctr = 3 else '0'; -- count bits in word
                    if bit_ctr_tc then
                        bit_ctr <= NSHFT-1;
                    else
                        if bit_ctr = 0 then
                            bit_ctr <= NSHFT-1;
                        else
                            bit_ctr <= bit_ctr - 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Configuration memory address counter.
    -- The register spreadsheet in data sheet starts a the low bits,
    -- but the high bit must be shifted first, so start with max
    -- address and decrement.
    ------------------------------------------------------------------
    cfg_adr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if cfg_adr_ld then
                cfg_adr <= 0;
            else
                if cfg_adr_en then
                    if cfg_adr < MAX_CFG then
                        cfg_adr <= cfg_adr + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Generate a timer for the preamble delay.
    ------------------------------------------------------------------
    preamb_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if preamb_ctr_ld then
                preamb_ctr_tc <= '0';
                preamb_ctr <= PREAMBTC;
            else
                if ce then
                    preamb_ctr_tc <= '1' when preamb_ctr = 0 else '0';
                    if preamb_ctr > 0 then
                        preamb_ctr <= preamb_ctr - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Count the number bits from write until shifted into chip.
    ------------------------------------------------------------------
    pause_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if pause_ctr_ld = '1' then
                pause_ctr_tc <= '0';
                pause_ctr <= RDPAUSE;
            else
                --if ce and (not pause_ctr_tc) then
                if ce then
                    pause_ctr_tc <= '1' when pause_ctr = 0 else '0'; -- pause between read and write
                    if pause_ctr > 0 then
                        pause_ctr <= pause_ctr - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end rdwr_arch;

-------------------------------------------------------------------------------
-- Architecture for writing data for debug use.
-------------------------------------------------------------------------------
architecture wr_arch of si5345_intfc is

    component si5345_ila
    port (
        clk                             : in std_logic;
        probe0                          : in std_logic_vector(0  downto 0);
        probe1                          : in std_logic_vector(0  downto 0);
        probe2                          : in std_logic_vector(0  downto 0);
        probe3                          : in std_logic_vector(0  downto 0);
        probe4                          : in std_logic_vector(0  downto 0);
        probe5                          : in std_logic_vector(0 downto 0);
        probe6                          : in std_logic_vector(0  downto 0);
        probe7                          : in std_logic_vector(0 downto 0);
        probe8                          : in std_logic_vector(9 downto 0);
        probe9                          : in std_logic_vector(31 downto 0);
        probe10                         : in std_logic_vector(0  downto 0);
        probe11                         : in std_logic_vector(15 downto 0);
        probe12                         : in std_logic_vector(15 downto 0);
        probe13                         : in std_logic_vector(15 downto 0);
        probe14                         : in std_logic_vector(15 downto 0);
        probe15                         : in std_logic_vector(0  downto 0);
        probe16                         : in std_logic_vector(7  downto 0));
    end component;

    --constant DWDT                       : integer := 32;-- data width
    constant MAX_CFG                    : integer := NREGS-1;--test
    --constant ASIC_REGS                  : integer := 1144;
    --constant RDPAUSE                    : integer := ASIC_REGS-2;--test
    constant NBIT                       : integer                               := 8;      --numbers of bits in a SI5345 register
    constant NTRACT                     : integer                               := NBIT*2; --number of registers per SI5345 transaction (instruction + value)
    constant NSHFT                      : integer                               := (NTRACT+2)*4;--numbers of bits to shift for a read/write cycle, add 2 CS cycles
    constant RDPAUSE                    : integer                               := 67;
    --constant PAUSEW                     : integer                               := INTEGER(CEIL(LOG2(REAL(RDPAUSE))));
    constant ENDIANESS                  : string                                := "LTL";--BIG or LTL
    constant CSROMVAL                   : std_logic_vector(NSHFT-1 downto 0)    := 72UX"C00030000C0003";
    constant PREAMBTM                   : real                                  := 2500000000.0;-- preamble calibration time in ns

    constant SETADR                     : std_logic_vector(7 downto 0)          := X"00";--Set Address
    constant WRDAT                      : std_logic_vector(7 downto 0)          := X"40";--Write Data
    constant RDDAT                      : std_logic_vector(7 downto 0)          := X"80";--Read Data
    constant WRDATAI                    : std_logic_vector(7 downto 0)          := X"70";--Write Data + Address Increment
    constant RDDATAI                    : std_logic_vector(7 downto 0)          := X"A0";--Read Data + Address Increment
    constant BWRDAT                     : std_logic_vector(7 downto 0)          := X"E0";--Burst Write Data
    constant PGADR                      : std_logic_vector(7 downto 0)          := X"01";--page address

    function PREVAL(sp : boolean; rv : real; ckp : real) return natural is
        constant SV         : real      := 30080.0;
        variable outp       : natural;
    begin
        if sp then
            outp := INTEGER(CEIL(SV/ckp));
        else
            outp := INTEGER(CEIL(rv/ckp));
        end if;
        return outp;
    end function;

    constant PREAMBTC                   : natural                               := PREVAL(SIM_SPDUP,PREAMBTM,SCLKPER);

    type fsm_type is (INITS,WLOADS,WRITES,PREAMBS,PREPSS,DONES);

    signal si_ifen_q0                   : std_logic;
    signal si_rstb_q0                   : std_logic;
    signal si_sclk_q0                   : std_logic;-- SPI
    signal si_a0_csb_q0                 : std_logic;
    signal si_sda_sdio_q0               : std_logic;
    signal si_a1_sdo_q0                 : std_logic;-- Stat/Ctrl
    signal si_oeb_q0                    : std_logic;
    signal si_intrb_q0                  : std_logic;
    signal si_lolb_q0                   : std_logic;

    signal fsm_cs                       : fsm_type;
    signal fsm_rstb                     : std_logic;
    signal fsm_sclk_en                  : std_logic;
    --signal fsm_a0_csb                   : std_logic;
    signal fsm_cfg_done                 : std_logic;
    signal cfg_adr_ld                   : std_logic;
    signal cfg_adr_en                   : std_logic;
    signal cfg_wra_tc                   : std_logic;
    signal cfg_rda_tc                   : std_logic;
    signal cfg_pre_tc                   : std_logic;
    signal cfg_pst_tc                   : std_logic;
    signal cfg_adr                      : integer range 0 to MAX_CFG;
    signal cfg_rom_out                  : std_logic_vector(31 downto 0)     := (others => '0');
    signal piso_ld                      : std_logic;
    signal piso                         : std_logic_vector(NSHFT-1 downto 0);--parallel data in serial out
    signal csrom                        : std_logic_vector(NSHFT-1 downto 0);--ROM for CS signal

    signal bit_ctr_ld                   : std_logic;
    signal bit_ctr_tc                   : std_logic;
    signal bit_ctr_rd                   : std_logic;
    signal bit_ctr                      : natural range 0 to NSHFT-1;
    signal preamb_ctr_ld                : std_logic;
    signal preamb_ctr_tc                : std_logic;
    signal preamb_ctr                   : natural range 0 to PREAMBTC;

    signal pause_ctr_ld                 : std_logic;
    signal pause_ctr_tc                 : std_logic;
    signal pause_ctr                    : natural range 0 to RDPAUSE;
    signal phase_reg                    : std_logic_vector(PHASE_VAL-1 downto 0);    
    
    signal reg_sclk                     : std_logic;

    alias set_pag_adr : std_logic_vector(15 downto 0) is piso(71 downto 56);
    alias set_pag_dat : std_logic_vector(15 downto 0) is piso(53 downto 38);
    alias set_val_adr : std_logic_vector(15 downto 0) is piso(35 downto 20);
    alias get_val_dat : std_logic_vector(15 downto 0) is piso(17 downto 2);

begin


--------------------------------------------------------------------------
-- Component instantiations
--------------------------------------------------------------------------

    ------------------------------------------------------------------
    -- Create a ROM to be used as a LUT for all configuration.
    -- The device has a block write function. Try to write the last
    -- (reset) address then wrap to the lower addresses.
    ------------------------------------------------------------------
    cfg_ram_ins : entity work.si5345_cfg_ram(cfg_ram_arch)
    port map(
        clk                             => clk,
        ce                              => '1',--bit_ctr_tc
        reset                           => '0',--reset,
        wren                            => '0',              --tie low to make a ROM
        wr_adr                          => (others => '0'),
        wr_data                         => (others => '0'),
        cfg_adr                         => cfg_adr,
        cfg_out                         => cfg_rom_out
    );

    ------------------------------------------------------------------
    -- ILA for test.
    ------------------------------------------------------------------
    ila_gen : if USE_ILA = TRUE generate
        si5345_ila_ins : si5345_ila
        port map (
            clk                         => clk,
            probe0(0)                   => si_sclk_q0,    
            probe1(0)                   => si_a0_csb_q0,  
            probe2(0)                   => si_sda_sdio_q0,
            probe3(0)                   => si_a1_sdo_q0,  
            probe4(0)                   => si_intrb_q0,  
            probe5(0)                   => si_lolb_q0,  
            probe6(0)                   => rdb_err,  
            probe7(0)                   => cfg_done,  
            probe8                      => STD_LOGIC_VECTOR(TO_UNSIGNED(cfg_adr,10)),
            probe9                      => cfg_rom_out,
            probe10(0)                  => piso_ld,
            probe11                     => set_pag_adr,
            probe12                     => set_pag_dat,
            probe13                     => set_val_adr,
            probe14                     => get_val_dat,
            probe15(0)                  => bit_ctr_ld,
            probe16                     => STD_LOGIC_VECTOR(TO_UNSIGNED(bit_ctr,10))
        );
    end generate;

--------------------------------------------------------------------------
-- Concurrent Statements
--------------------------------------------------------------------------

    --map signals to ports
    si_ifen     <= si_ifen_q0;
    si_rstb     <= si_rstb_q0;
    si_sclk     <= si_sclk_q0;
    si_a0_csb   <= si_a0_csb_q0;
    si_sda_sdio <= si_sda_sdio_q0;
    si_oeb      <= si_oeb_q0;

    -- internal
    -- these may need to registered for timing, but what will happen to functionality?
    cfg_adr_en <= bit_ctr_tc and ce and preamb_ctr_ld and (not fsm_cfg_done);
    cfg_wra_tc <= '1' when cfg_adr = (MAX_CFG-NPSTAMBL) else '0';--!!!must add post amble check logic
    cfg_rda_tc <= '1' when cfg_adr = (MAX_CFG-NPSTAMBL) else '0';
    cfg_pre_tc <= '1' when cfg_adr = (NPREAMBL-1) else '0';--!!!must add post amble check logic
    cfg_pst_tc <= '1' when cfg_adr = MAX_CFG else '0';--!!!must add post amble check logic
    reg_sclk <= phase_reg(phase_reg'left);--! and fsm_sclk_en;   -- adjust clock phase to compensate for internal delays
    piso_ld <= bit_ctr_tc and (not cfg_adr_ld) and preamb_ctr_ld;

    csrom <= CSROMVAL;

    ------------------------------------------------------------------
    -- Pipeline outputs.
    ------------------------------------------------------------------
    pipe_pcs : process(clk)
    begin
        if (clk'event and clk='1') then

            -- inputs -------------
            si_a1_sdo_q0    <= si_a1_sdo;
            si_intrb_q0     <= si_intrb;
            si_lolb_q0      <= si_lolb;

            -- outputs --------------
            si_ifen_q0      <= '1';
            si_rstb_q0      <= '1';--fsm_rstb;
            si_oeb_q0       <= '0';
            si_sclk_q0      <= reg_sclk;
            si_a0_csb_q0    <= csrom(bit_ctr) or (not preamb_ctr_ld);
            si_sda_sdio_q0  <= piso(piso'left);            

            rdb_err <= '0';
            cfg_done  <= fsm_cfg_done;            

            -- internal ---------------
            -- shift the strobe for phase adjustment
            phase_reg <= phase_reg(phase_reg'left-1 downto 0) & strobe;            
        end if;
    end process;

    ------------------------------------------------------------------
    -- Simple state machine to control streaming of config data.
    ------------------------------------------------------------------
    fsm_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                fsm_rstb <= '1';
                fsm_sclk_en <= '0';
                bit_ctr_ld <= '1';
                preamb_ctr_ld <= '1';
                pause_ctr_ld <= '1';                
                cfg_adr_ld <= '1';
                --fsm_a0_csb <= '1';
                fsm_cfg_done <= '0';
                fsm_cs <= INITS;
            else
                if ce = '1' then
                    case fsm_cs is
                    when INITS =>
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '0';
                        bit_ctr_ld <= '1';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '1';                        
                        cfg_adr_ld <= '1';
                        --fsm_a0_csb <= '1';
                        fsm_cfg_done <= '0';
                        if preamb_ctr_tc then--wait for reset recovery, re-use counter, > 750 ms
                            fsm_cs <= WLOADS;
                        else
                            fsm_cs <= INITS;
                        end if;
                    when WLOADS => -- load counters, get ready
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '0';
                        bit_ctr_ld <= '0';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '1';
                        cfg_adr_ld <= '0';
                        --fsm_a0_csb <= '1';
                        fsm_cfg_done <= '0';
                        if bit_ctr_tc then
                            fsm_cs <= WRITES;
                        else
                            fsm_cs <= WLOADS;
                        end if;
                    when WRITES => -- write values to registers
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '1';
                        cfg_adr_ld <= '0';-- increment ROM address
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        if bit_ctr_tc then
                            --? this is a sketchy thing to do
                            if cfg_pre_tc then   --pre-amble
                                fsm_cs <= PREPSS;
                            elsif cfg_wra_tc then--config-regs
                                fsm_cs <= WRITES;
                            elsif cfg_pst_tc then--post-amble
                                fsm_cs <= DONES;
                            else
                                fsm_cs <= WRITES;
                            end if;
                        end if;
                    when PREPSS => -- pause for last register write
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';
                        cfg_adr_ld <= '0';
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        if pause_ctr_tc then
                            --bit_ctr_ld <= '0';
                            preamb_ctr_ld <= '1';
                            pause_ctr_ld <= '0';
                            fsm_cs <= PREAMBS;
                        else
                            --bit_ctr_ld <= '1';
                            preamb_ctr_ld <= '1';
                            pause_ctr_ld <= '0';
                            fsm_cs <= PREPSS;
                        end if;
                    when PREAMBS => -- pause pre-amble
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';
                        cfg_adr_ld <= '0';
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        if  bit_ctr_tc and preamb_ctr_tc then
                            preamb_ctr_ld <= '1';
                            fsm_cs <= WRITES;
                        else
                            preamb_ctr_ld <= '0';
                            fsm_cs <= PREAMBS;
                        end if;
                    when DONES => -- stay here when finished
                        fsm_rstb <= '1';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '0';
                        if pause_ctr_tc then
                            fsm_sclk_en <= '0';
                            bit_ctr_ld <= '1';
                            cfg_adr_ld <= '1';
                            --fsm_a0_csb <= '0';
                            fsm_cfg_done <= '1';
                        else
                            fsm_sclk_en <= '1';
                            bit_ctr_ld <= '0';                            
                            cfg_adr_ld <= '0';
                            --fsm_a0_csb <= '1';
                            --fsm_cfg_done <= '0';
                            fsm_cfg_done <= si_lolb;--wait for lock, intr should also be used?
                        end if;
                        if cfg_enbl then
                            fsm_cs <= INITS;
                        else
                            fsm_cs <= DONES;
                        end if;
                    when others =>
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '0';
                        bit_ctr_ld <= '1';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '1';
                        cfg_adr_ld <= '1';
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        fsm_cs <= INITS;
                    end case;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Shift register for writing.
    ------------------------------------------------------------------
    piso_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                piso <= (others => '0');
            else
                if ce = '1' then
                    if piso_ld = '1' then
                        piso <= SETADR & PGADR & "11" & WRDAT & cfg_rom_out(31 downto 24) & "11" & SETADR & cfg_rom_out(23 downto 16) & "11" & WRDAT & cfg_rom_out(7 downto 0) & "11";
                    else
                        piso <= piso(piso'left-1 downto 0) & '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Count the number bits written/read.
    ------------------------------------------------------------------
    bit_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if bit_ctr_ld then
                bit_ctr_tc <= '1';
                bit_ctr_rd <= '1';
                bit_ctr <= 0;
            else
                if ce = '1' then
                    bit_ctr_tc <= '1' when bit_ctr = 1 else '0'; -- count bits in word
                    bit_ctr_rd <= '1' when bit_ctr = 3 else '0'; -- count bits in word
                    if bit_ctr_tc then
                        bit_ctr <= NSHFT-1;
                    else
                        if bit_ctr = 0 then
                            bit_ctr <= NSHFT-1;
                        else
                            bit_ctr <= bit_ctr - 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Configuration memory address counter.
    -- The register spreadsheet in data sheet starts a the low bits,
    -- but the high bit must be shifted first, so start with max
    -- address and decrement.
    ------------------------------------------------------------------
    cfg_adr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if cfg_adr_ld then
                cfg_adr <= 0;
            else
                if cfg_adr_en then
                    if cfg_adr < MAX_CFG then
                        cfg_adr <= cfg_adr + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Generate a timer for the preamble delay.
    ------------------------------------------------------------------
    preamb_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if preamb_ctr_ld then
                preamb_ctr_tc <= '0';
                preamb_ctr <= PREAMBTC;
            else
                if ce then
                    preamb_ctr_tc <= '1' when preamb_ctr = 0 else '0';
                    if preamb_ctr > 0 then
                        preamb_ctr <= preamb_ctr - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Count the number bits from write until shifted into chip.
    ------------------------------------------------------------------
    pause_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if pause_ctr_ld = '1' then
                pause_ctr_tc <= '0';
                pause_ctr <= RDPAUSE;
            else
                --if ce and (not pause_ctr_tc) then
                if ce then
                    pause_ctr_tc <= '1' when pause_ctr = 0 else '0'; -- pause between read and write
                    if pause_ctr > 0 then
                        pause_ctr <= pause_ctr - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end wr_arch;

-------------------------------------------------------------------------------
-- Architecture for writing data and clearing sticky registers for debug use.
-------------------------------------------------------------------------------
architecture wrclr_arch of si5345_intfc is

    component si5345_ila
    port (
        clk                             : in std_logic;
        probe0                          : in std_logic_vector(0  downto 0);
        probe1                          : in std_logic_vector(0  downto 0);
        probe2                          : in std_logic_vector(0  downto 0);
        probe3                          : in std_logic_vector(0  downto 0);
        probe4                          : in std_logic_vector(0  downto 0);
        probe5                          : in std_logic_vector(0 downto 0);
        probe6                          : in std_logic_vector(0  downto 0);
        probe7                          : in std_logic_vector(0 downto 0);
        probe8                          : in std_logic_vector(9 downto 0);
        probe9                          : in std_logic_vector(31 downto 0);
        probe10                         : in std_logic_vector(0  downto 0);
        probe11                         : in std_logic_vector(15 downto 0);
        probe12                         : in std_logic_vector(15 downto 0);
        probe13                         : in std_logic_vector(15 downto 0);
        probe14                         : in std_logic_vector(15 downto 0);
        probe15                         : in std_logic_vector(0  downto 0);
        probe16                         : in std_logic_vector(7  downto 0));
    end component;

    --constant DWDT                       : integer := 32;-- data width
    constant MAX_CFG                    : integer := NREGS-1;--test
    --constant ASIC_REGS                  : integer := 1144;
    --constant RDPAUSE                    : integer := ASIC_REGS-2;--test
    constant NBIT                       : integer                               := 8;      --numbers of bits in a SI5345 register
    constant NTRACT                     : integer                               := NBIT*2; --number of registers per SI5345 transaction (instruction + value)
    constant NSHFT                      : integer                               := (NTRACT+2)*4;--numbers of bits to shift for a read/write cycle, add 2 CS cycles
    constant RDPAUSE                    : integer                               := 67;

    
    constant CSROMVAL                   : std_logic_vector(NSHFT-1 downto 0)    := 72UX"C00030000C0003";
    constant NSTICKY                    : integer                               := 4;-- number of sticky registers to clear
    constant PREAMBTM                   : real                                  := 3500000000.0;-- preamble calibration time in ns

    constant SETADR                     : std_logic_vector(7 downto 0)          := X"00";--Set Address
    constant WRDAT                      : std_logic_vector(7 downto 0)          := X"40";--Write Data
    constant RDDAT                      : std_logic_vector(7 downto 0)          := X"80";--Read Data
    constant WRDATAI                    : std_logic_vector(7 downto 0)          := X"70";--Write Data + Address Increment
    constant RDDATAI                    : std_logic_vector(7 downto 0)          := X"A0";--Read Data + Address Increment
    constant BWRDAT                     : std_logic_vector(7 downto 0)          := X"E0";--Burst Write Data
    constant PGADR                      : std_logic_vector(7 downto 0)          := X"01";--page address

    function PREVAL(sp : boolean; rv : real; ckp : real) return natural is
        constant SV         : real      := 30080.0;
        variable outp       : natural;
    begin
        if sp then
            outp := INTEGER(CEIL(SV/ckp));
        else
            outp := INTEGER(CEIL(rv/ckp));
        end if;
        return outp;
    end function;

    constant PREAMBTC                   : natural                               := PREVAL(SIM_SPDUP,PREAMBTM,SCLKPER);

    type fsm_type is (INITS,WLOADS,WRITES,PREAMBS,PREPSS,DONES);

    signal si_ifen_q0                   : std_logic;
    signal si_rstb_q0                   : std_logic;
    signal si_sclk_q0                   : std_logic;-- SPI
    signal si_a0_csb_q0                 : std_logic;
    signal si_sda_sdio_q0               : std_logic;
    signal si_a1_sdo_q0                 : std_logic;-- Stat/Ctrl
    signal si_oeb_q0                    : std_logic;
    signal si_intrb_q0                  : std_logic;
    signal si_lolb_q0                   : std_logic;
    signal si_intrb_q1                  : std_logic;
    signal si_lolb_q1                   : std_logic;                                                    

    signal fsm_cs                       : fsm_type;
    signal fsm_ifen                     : std_logic;                                                
    signal fsm_rstb                     : std_logic;
    signal fsm_sclk_en                  : std_logic;
    --signal fsm_a0_csb                   : std_logic;
    signal fsm_cfg_done                 : std_logic;
    signal cfg_adr_ld                   : std_logic;
    signal cfg_adr_en                   : std_logic;
    --signal cfg_wra_tc                   : std_logic;
    --signal cfg_rda_tc                   : std_logic;
    signal cfg_pre_tc                   : std_logic;
    signal cfg_pst_tc                   : std_logic;
    signal cfg_clr_tc                   : std_logic;
    signal cfg_adr                      : integer range 0 to MAX_CFG;
    signal cfg_rom_out                  : std_logic_vector(31 downto 0)     := (others => '0');
    signal piso_ld                      : std_logic;
    signal piso                         : std_logic_vector(NSHFT-1 downto 0);--parallel data in serial out
    signal csrom                        : std_logic_vector(NSHFT-1 downto 0);--ROM for CS signal

    signal bit_ctr_ld                   : std_logic;
    signal bit_ctr_tc                   : std_logic;
    signal bit_ctr_rd                   : std_logic;
    signal bit_ctr                      : natural range 0 to NSHFT-1;
    signal preamb_ctr_ld                : std_logic;
    signal preamb_ctr_tc                : std_logic;
    signal preamb_ctr                   : natural range 0 to PREAMBTC;

    signal pause_ctr_ld                 : std_logic;
    signal pause_ctr_tc                 : std_logic;
    signal pause_ctr                    : natural range 0 to RDPAUSE;
    signal phase_reg                    : std_logic_vector(PHASE_VAL-1 downto 0);

    signal reg_sclk                     : std_logic;

    alias set_pag_adr : std_logic_vector(15 downto 0) is piso(71 downto 56);
    alias set_pag_dat : std_logic_vector(15 downto 0) is piso(53 downto 38);
    alias set_val_adr : std_logic_vector(15 downto 0) is piso(35 downto 20);
    alias get_val_dat : std_logic_vector(15 downto 0) is piso(17 downto 2);

    attribute ASYNC_REG : string;    
    attribute ASYNC_REG of si_intrb_q0      : signal is "TRUE";
    attribute ASYNC_REG of si_lolb_q0       : signal is "TRUE";
    attribute ASYNC_REG of si_intrb_q1      : signal is "TRUE";
    attribute ASYNC_REG of si_lolb_q1       : signal is "TRUE";                                
begin


--------------------------------------------------------------------------
-- Component instantiations
--------------------------------------------------------------------------

    ------------------------------------------------------------------
    -- Create a ROM to be used as a LUT for all configuration.
    -- The device has a block write function. Try to write the last
    -- (reset) address then wrap to the lower addresses.
    ------------------------------------------------------------------
    cfg_ram_ins : entity work.si5345_cfg_ram(cfg_ram_arch)
    port map(
        clk                             => clk,
        ce                              => '1',--bit_ctr_tc
        reset                           => '0',--reset,
        wren                            => '0',              --tie low to make a ROM
        wr_adr                          => (others => '0'),
        wr_data                         => (others => '0'),
        cfg_adr                         => cfg_adr,
        cfg_out                         => cfg_rom_out
    );

    ------------------------------------------------------------------
    -- ILA for test.
    ------------------------------------------------------------------
    ila_gen : if USE_ILA = TRUE generate
        si5345_ila_ins : si5345_ila
        port map (
            clk                         => clk,
            probe0(0)                   => si_sclk_q0,
            probe1(0)                   => si_a0_csb_q0,
            probe2(0)                   => si_sda_sdio_q0,
            probe3(0)                   => si_a1_sdo_q0,
            probe4(0)                   => si_intrb_q0,
            probe5(0)                   => si_lolb_q0,
            probe6(0)                   => rdb_err,
            probe7(0)                   => cfg_done,
            probe8                      => STD_LOGIC_VECTOR(TO_UNSIGNED(cfg_adr,10)),
            probe9                      => cfg_rom_out,
            probe10(0)                  => piso_ld,
            probe11                     => set_pag_adr,
            probe12                     => set_pag_dat,
            probe13                     => set_val_adr,
            probe14                     => get_val_dat,
            probe15(0)                  => bit_ctr_ld,
            probe16                     => STD_LOGIC_VECTOR(TO_UNSIGNED(bit_ctr,8))
        );
    end generate;

--------------------------------------------------------------------------
-- Concurrent Statements
--------------------------------------------------------------------------

    --map signals to ports
    si_ifen     <= si_ifen_q0;
    si_rstb     <= si_rstb_q0;
    si_sclk     <= si_sclk_q0;
    si_a0_csb   <= si_a0_csb_q0;
    si_sda_sdio <= si_sda_sdio_q0;
    si_oeb      <= si_oeb_q0;

    -- internal
    -- these may need to registered for timing, but what will happen to functionality?
    cfg_adr_en <= bit_ctr_tc and ce and preamb_ctr_ld and (not fsm_cfg_done);
    --cfg_wra_tc <= '1' when cfg_adr = (MAX_CFG-NPSTAMBL-1) else '0';--!!!must add post amble check logic
    --cfg_rda_tc <= '1' when cfg_adr = (MAX_CFG-NPSTAMBL-1) else '0';
    cfg_pre_tc <= '1' when cfg_adr = (NPREAMBL-1) else '0';        --!!!must add post amble check logic
    cfg_pst_tc <= '1' when cfg_adr = (MAX_CFG-NSTICKY) else '0'; --!!!must add post amble check logic
    cfg_clr_tc <= '1' when cfg_adr = MAX_CFG else '0';             --!!!must add post amble check logic
    reg_sclk <= phase_reg(phase_reg'left) and fsm_sclk_en;         -- adjust clock phase to compensate for internal delays
    piso_ld <= bit_ctr_tc and (not cfg_adr_ld) and preamb_ctr_ld;

    csrom <= CSROMVAL;

    ------------------------------------------------------------------
    -- Pipeline outputs.
    ------------------------------------------------------------------
    pipe_pcs : process(clk)
    begin
        if (clk'event and clk='1') then

            -- inputs -------------
            si_a1_sdo_q0    <= si_a1_sdo;
            si_intrb_q0     <= si_intrb;
            si_lolb_q0      <= si_lolb;
            si_intrb_q1     <= si_intrb_q0;
            si_lolb_q1      <=  si_lolb_q0;

            -- outputs --------------
            si_ifen_q0      <= fsm_ifen;
            si_rstb_q0      <= fsm_rstb;
            si_oeb_q0       <= '0';
            si_sclk_q0      <= reg_sclk;
            si_a0_csb_q0    <= csrom(bit_ctr) or (not preamb_ctr_ld);
            si_sda_sdio_q0  <= piso(piso'left);

            rdb_err <= '0';
            cfg_done  <= fsm_cfg_done;

            -- internal ---------------
            -- shift the strobe for phase adjustment
            phase_reg <= phase_reg(phase_reg'left-1 downto 0) & strobe;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Simple state machine to control streaming of config data.
    ------------------------------------------------------------------
    fsm_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                fsm_ifen <= '1';
                fsm_rstb <= '0';
                fsm_sclk_en <= '0';
                bit_ctr_ld <= '1';
                preamb_ctr_ld <= '1';
                pause_ctr_ld <= '1';
                cfg_adr_ld <= '1';
                --fsm_a0_csb <= '1';
                fsm_cfg_done <= '0';
                fsm_cs <= INITS;
            else
                if ce = '1' then
                    case fsm_cs is
                    when INITS =>
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '0';
                        bit_ctr_ld <= '1';
                        preamb_ctr_ld <= '0';
                        pause_ctr_ld <= '1';
                        cfg_adr_ld <= '1';
                        --fsm_a0_csb <= '1';
                        fsm_cfg_done <= '0';
                        if preamb_ctr_tc then--wait for reset recovery, re-use counter, > 750 ms
                            fsm_cs <= WLOADS;
                        else
                            fsm_cs <= INITS;
                        end if;
                    when WLOADS => -- load counters, get ready
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '0';
                        bit_ctr_ld <= '0';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '1';
                        cfg_adr_ld <= '0';
                        --fsm_a0_csb <= '1';
                        fsm_cfg_done <= '0';
                        if bit_ctr_tc then
                            fsm_cs <= WRITES;
                        else
                            fsm_cs <= WLOADS;
                        end if;
                    when WRITES => -- write values to registers
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '1';
                        cfg_adr_ld <= '0';-- increment ROM address
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        if bit_ctr_tc then
                            --? this is a sketchy thing to do
                            if cfg_pre_tc then   --pre-amble
                                fsm_cs <= PREPSS;
                            elsif cfg_pst_tc then--post-amble
                                fsm_cs <= PREPSS;
                            elsif cfg_clr_tc then--post-amble
                                fsm_cs <= DONES;
                            else
                                fsm_cs <= WRITES;
                            end if;
                        end if;
                    when PREPSS => -- pause for last register write
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';
                        cfg_adr_ld <= '0';
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        if pause_ctr_tc then
                            --bit_ctr_ld <= '0';
                            preamb_ctr_ld <= '1';
                            pause_ctr_ld <= '0';
                            fsm_cs <= PREAMBS;
                        else
                            --bit_ctr_ld <= '1';
                            preamb_ctr_ld <= '1';
                            pause_ctr_ld <= '0';
                            fsm_cs <= PREPSS;
                        end if;
                    when PREAMBS => -- pause for pre-amble
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';
                        cfg_adr_ld <= '0';
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        if  bit_ctr_tc and preamb_ctr_tc then
                            preamb_ctr_ld <= '1';
                            fsm_cs <= WRITES;
                        else
                            preamb_ctr_ld <= '0';
                            fsm_cs <= PREAMBS;
                        end if;
                    when DONES => -- stay here when finished
                        fsm_ifen <= '1';
                        fsm_rstb <= '1';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '0';
                        fsm_cfg_done <= (si_intrb_q1 or si_lolb_q1);--wait for lock, intr should also be used?
                        if pause_ctr_tc then
                            fsm_sclk_en <= '0';
                            bit_ctr_ld <= '1';
                            cfg_adr_ld <= '1';
                        else
                            fsm_sclk_en <= '1';
                            bit_ctr_ld <= '0';
                            cfg_adr_ld <= '0';
                        end if;
                        if cfg_enbl then
                            fsm_cs <= INITS;
                        else
                            fsm_cs <= DONES;
                        end if;
                    when others =>
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '0';
                        bit_ctr_ld <= '1';
                        preamb_ctr_ld <= '1';
                        pause_ctr_ld <= '1';
                        cfg_adr_ld <= '1';
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        fsm_cs <= INITS;
                    end case;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Shift register for writing.
    ------------------------------------------------------------------
    piso_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                piso <= (others => '0');
            else
                if ce = '1' then
                    if piso_ld = '1' then
                        piso <= SETADR & PGADR & "11" & WRDAT & cfg_rom_out(31 downto 24) & "11" & SETADR & cfg_rom_out(23 downto 16) & "11" & WRDAT & cfg_rom_out(7 downto 0) & "11";
                    else
                        piso <= piso(piso'left-1 downto 0) & '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Count the number bits written/read.
    ------------------------------------------------------------------
    bit_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if bit_ctr_ld then
                bit_ctr_tc <= '1';
                bit_ctr_rd <= '1';
                bit_ctr <= 0;
            else
                if ce = '1' then
                    bit_ctr_tc <= '1' when bit_ctr = 1 else '0'; -- count bits in word
                    bit_ctr_rd <= '1' when bit_ctr = 3 else '0'; -- count bits in word
                    if bit_ctr_tc then
                        bit_ctr <= NSHFT-1;
                    else
                        if bit_ctr = 0 then
                            bit_ctr <= NSHFT-1;
                        else
                            bit_ctr <= bit_ctr - 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Configuration memory address counter.
    -- The register spreadsheet in data sheet starts a the low bits,
    -- but the high bit must be shifted first, so start with max
    -- address and decrement.
    ------------------------------------------------------------------
    cfg_adr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if cfg_adr_ld then
                cfg_adr <= 0;
            else
                if cfg_adr_en then
                    if cfg_adr < MAX_CFG then
                        cfg_adr <= cfg_adr + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Generate a timer for the preamble delay.
    ------------------------------------------------------------------
    preamb_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if preamb_ctr_ld then
                preamb_ctr_tc <= '0';
                preamb_ctr <= PREAMBTC;
            else
                if ce then
                    preamb_ctr_tc <= '1' when preamb_ctr = 0 else '0';
                    if preamb_ctr > 0 then
                        preamb_ctr <= preamb_ctr - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Count the number bits from write until shifted into chip.
    ------------------------------------------------------------------
    pause_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if pause_ctr_ld = '1' then
                pause_ctr_tc <= '0';
                pause_ctr <= RDPAUSE;
            else
                --if ce and (not pause_ctr_tc) then
                if ce then
                    pause_ctr_tc <= '1' when pause_ctr = 0 else '0'; -- pause between read and write
                    if pause_ctr > 0 then
                        pause_ctr <= pause_ctr - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end wrclr_arch;

-------------------------------------------------------------------------------
-- Architecture for reading data for debug use.
-------------------------------------------------------------------------------
architecture rd_arch of si5345_intfc is

    component si5345_ila
    port (
        clk                             : in std_logic;
        probe0                          : in std_logic_vector(0  downto 0);
        probe1                          : in std_logic_vector(0  downto 0);
        probe2                          : in std_logic_vector(0  downto 0);
        probe3                          : in std_logic_vector(0  downto 0);
        probe4                          : in std_logic_vector(0  downto 0);
        probe5                          : in std_logic_vector(0 downto 0);
        probe6                          : in std_logic_vector(0  downto 0);
        probe7                          : in std_logic_vector(0 downto 0);
        probe8                          : in std_logic_vector(9 downto 0);
        probe9                          : in std_logic_vector(31 downto 0);
        probe10                         : in std_logic_vector(0  downto 0);
        probe11                         : in std_logic_vector(15 downto 0);
        probe12                         : in std_logic_vector(15 downto 0);
        probe13                         : in std_logic_vector(15 downto 0);
        probe14                         : in std_logic_vector(15 downto 0);
        probe15                         : in std_logic_vector(0  downto 0);
        probe16                         : in std_logic_vector(7  downto 0));
    end component;

    --constant DWDT                       : integer := 32;-- data width
    constant MAX_CFG                    : integer := NREGS-1;--test
    --constant ASIC_REGS                  : integer := 1144;
    --constant RDPAUSE                    : integer := ASIC_REGS-2;--test
    constant NBIT                       : integer                               := 8;      --numbers of bits in a SI5345 register
    constant NTRACT                     : integer                               := NBIT*2; --number of registers per SI5345 transaction (instruction + value)
    constant NSHFT                      : integer                               := (NTRACT+2)*4;--numbers of bits to shift for a read/write cycle, add 2 CS cycles
    constant RDPAUSE                    : integer                               := 67;    
    
    constant CSROMVAL                   : std_logic_vector(NSHFT-1 downto 0)    := 72UX"C00030000C0003";

    constant SETADR                     : std_logic_vector(7 downto 0)          := X"00";--Set Address
    constant WRDAT                      : std_logic_vector(7 downto 0)          := X"40";--Write Data
    constant RDDAT                      : std_logic_vector(7 downto 0)          := X"80";--Read Data
    constant WRDATAI                    : std_logic_vector(7 downto 0)          := X"70";--Write Data + Address Increment
    constant RDDATAI                    : std_logic_vector(7 downto 0)          := X"A0";--Read Data + Address Increment
    constant BWRDAT                     : std_logic_vector(7 downto 0)          := X"E0";--Burst Write Data
    constant PGADR                      : std_logic_vector(7 downto 0)          := X"01";--page address

    type fsm_type is (INITS,WLOADS,READS,VERIFYS,DONES);

    signal si_ifen_q0                   : std_logic;
    signal si_rstb_q0                   : std_logic;
    signal si_sclk_q0                   : std_logic;-- SPI
    signal si_a0_csb_q0                 : std_logic;
    signal si_sda_sdio_q0               : std_logic;
    signal si_a1_sdo_q0                 : std_logic;-- Stat/Ctrl
    signal si_oeb_q0                    : std_logic;
    signal si_intrb_q0                  : std_logic;
    signal si_lolb_q0                   : std_logic;

    signal fsm_cs                       : fsm_type;
    signal fsm_rstb                     : std_logic;
    signal fsm_sclk_en                  : std_logic;
    --signal fsm_a0_csb                   : std_logic;
    signal fsm_cfg_done                 : std_logic;
    signal cfg_adr_ld                   : std_logic;
    signal cfg_adr_en                   : std_logic;
    signal cfg_wra_tc                   : std_logic;
    signal cfg_rda_tc                   : std_logic;
    signal cfg_pre_tc                   : std_logic;
    signal cfg_pst_tc                   : std_logic;
    signal cfg_adr                      : integer range 0 to MAX_CFG;
    signal cfg_rom_out                  : std_logic_vector(31 downto 0)     := (others => '0');
    signal rdbkadr_en                   : std_logic;
    signal rdbkcmp_en                   : std_logic;
    signal piso_ld                      : std_logic;
    signal piso                         : std_logic_vector(NSHFT-1 downto 0);--parallel data in serial out
    signal csrom                        : std_logic_vector(NSHFT-1 downto 0);--ROM for CS signal
    signal sipo_rdy                     : std_logic;
    signal sipo                         : std_logic_vector(7 downto 0);--serial in parallel data out
    signal rdbk_data                    : std_logic_vector(7 downto 0);
    signal vrfy_data                    : std_logic_vector(7 downto 0);
    signal bit_ctr_ld                   : std_logic;
    signal bit_ctr_tc                   : std_logic;
    signal bit_ctr_rd                   : std_logic;
    signal bit_ctr                      : natural range 0 to NSHFT-1;

    signal pause_ctr_ld                 : std_logic;
    signal pause_ctr_tc                 : std_logic;
    signal pause_ctr                    : natural range 0 to RDPAUSE;
    signal phase_reg                    : std_logic_vector(PHASE_VAL-1 downto 0);    
    
    signal reg_sclk                     : std_logic;    

    alias set_pag_adr : std_logic_vector(15 downto 0) is piso(71 downto 56);
    alias set_pag_dat : std_logic_vector(15 downto 0) is piso(53 downto 38);
    alias set_val_adr : std_logic_vector(15 downto 0) is piso(35 downto 20);
    alias get_val_dat : std_logic_vector(15 downto 0) is piso(17 downto 2);

begin


--------------------------------------------------------------------------
-- Component instantiations
--------------------------------------------------------------------------

    ------------------------------------------------------------------
    -- Create a ROM to be used as a LUT for all configuration.
    -- The device has a block write function. Try to write the last
    -- (reset) address then wrap to the lower addresses.
    ------------------------------------------------------------------
    cfg_ram_ins : entity work.si5345_cfg_ram(cfg_ram_arch)
    port map(
        clk                             => clk,
        ce                              => '1',--bit_ctr_tc
        reset                           => '0',--reset,
        wren                            => '0',              --tie low to make a ROM
        wr_adr                          => (others => '0'),
        wr_data                         => (others => '0'),
        cfg_adr                         => cfg_adr,
        cfg_out                         => cfg_rom_out
    );

    ------------------------------------------------------------------
    -- ILA for test.
    ------------------------------------------------------------------
    ila_gen : if USE_ILA = TRUE generate
        si5345_ila_ins : si5345_ila
        port map (
            clk                         => clk,
            probe0(0)                   => si_sclk_q0,    
            probe1(0)                   => si_a0_csb_q0,  
            probe2(0)                   => si_sda_sdio_q0,
            probe3(0)                   => si_a1_sdo_q0,  
            probe4(0)                   => si_intrb_q0,  
            probe5(0)                   => si_lolb_q0,  
            probe6(0)                   => rdb_err,  
            probe7(0)                   => cfg_done,  
            probe8                      => STD_LOGIC_VECTOR(TO_UNSIGNED(cfg_adr,10)),
            probe9                      => cfg_rom_out,
            probe10(0)                  => piso_ld,
            probe11                     => set_pag_adr,
            probe12                     => set_pag_dat,
            probe13                     => set_val_adr,
            probe14                     => get_val_dat,
            probe15(0)                  => sipo_rdy,
            probe16                     => sipo
        );
    end generate;

--------------------------------------------------------------------------
-- Concurrent Statements
--------------------------------------------------------------------------

    --map signals to ports
    si_ifen     <= si_ifen_q0;
    si_rstb     <= si_rstb_q0;
    si_sclk     <= si_sclk_q0;
    si_a0_csb   <= si_a0_csb_q0;
    si_sda_sdio <= si_sda_sdio_q0;
    si_oeb      <= si_oeb_q0;

    -- internal
    -- these may need to registered for timing, but what will happen to functionality?
    cfg_adr_en <= bit_ctr_tc and ce and (not fsm_cfg_done);
    cfg_wra_tc <= '1' when cfg_adr = (MAX_CFG-NPSTAMBL) else '0';--!!!must add post amble check logic
    cfg_rda_tc <= '1' when cfg_adr = (MAX_CFG-NPSTAMBL) else '0';
    cfg_pre_tc <= '1' when cfg_adr = (NPREAMBL-1) else '0';--!!!must add post amble check logic
    cfg_pst_tc <= '1' when cfg_adr = MAX_CFG else '0';--!!!must add post amble check logic
    reg_sclk <= phase_reg(phase_reg'left) and fsm_sclk_en;   -- adjust clock phase to compensate for internal delays
    piso_ld <= bit_ctr_tc and (not cfg_adr_ld);

    csrom <= CSROMVAL;

    ------------------------------------------------------------------
    -- Pipeline outputs.
    ------------------------------------------------------------------
    pipe_pcs : process(clk)
    begin
        if (clk'event and clk='1') then

            -- inputs -------------
            si_a1_sdo_q0    <= si_a1_sdo;
            si_intrb_q0     <= si_intrb;
            si_lolb_q0      <= si_lolb;

            -- outputs --------------
            si_ifen_q0      <= '1';
            si_rstb_q0      <= '1';--fsm_rstb;
            si_oeb_q0       <= '0';
            si_sclk_q0      <= reg_sclk;
            si_a0_csb_q0    <= csrom(bit_ctr);
            si_sda_sdio_q0  <= piso(piso'left);
            

            cfg_done  <= fsm_cfg_done;            

            -- internal ---------------
            -- shift the strobe for phase adjustment
            phase_reg <= phase_reg(phase_reg'left-1 downto 0) & strobe;
            
        end if;
    end process;

    ------------------------------------------------------------------
    -- Compare serial read-back data to ROM read-back data. Assert
    -- an error if they don't match.
    ------------------------------------------------------------------
    valid_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                vrfy_data <= (others => '0');
                rdbkcmp_en <= '0';
                rdbk_data <= (others => '0');
                rdb_err <= '0';
            else
                if ce then
                    vrfy_data <= rdbk_data;
                    if bit_ctr_tc then
                        rdbkcmp_en <= rdbkadr_en;
                    end if;
                    --if cfg_adr_en and rdbkcmp_en then
                    if cfg_adr_en and rdbkadr_en then
                        rdbk_data <= cfg_rom_out(7 downto 0);
                    end if;
                end if;
                if sipo_rdy = '1' then
                    if vrfy_data /= sipo then
                        rdb_err <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Simple state machine to control streaming of config data.
    ------------------------------------------------------------------
    fsm_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                fsm_rstb <= '1';
                fsm_sclk_en <= '0';
                bit_ctr_ld <= '1';                
                pause_ctr_ld <= '1';
                rdbkadr_en <= '0';
                cfg_adr_ld <= '1';
                --fsm_a0_csb <= '1';
                fsm_cfg_done <= '0';
                fsm_cs <= INITS;
            else
                if ce = '1' then
                    case fsm_cs is
                    when INITS =>
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '0';
                        bit_ctr_ld <= '1';                        
                        pause_ctr_ld <= '1';
                        rdbkadr_en <= '0';
                        cfg_adr_ld <= '1';
                        --fsm_a0_csb <= '1';
                        fsm_cfg_done <= '0';
                        if cfg_enbl then
                            fsm_cs <= WLOADS;
                        else
                            fsm_cs <= INITS;
                        end if;
                    when WLOADS => -- load counters, get ready
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '0';
                        bit_ctr_ld <= '0';                        
                        pause_ctr_ld <= '1';
                        rdbkadr_en <= '0';
                        cfg_adr_ld <= '0';
                        --fsm_a0_csb <= '1';
                        fsm_cfg_done <= '0';
                        if bit_ctr_tc then
                            fsm_cs <= READS;
                        else
                            fsm_cs <= WLOADS;
                        end if;
                    when READS => -- finish reading last word
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';                        
                        pause_ctr_ld <= '1';
                        rdbkadr_en <= '1';
                        cfg_adr_ld <= '0';-- increment ROM address
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        if bit_ctr_tc and cfg_rda_tc then
                            fsm_cs <= VERIFYS;
                        else
                            fsm_cs <= READS;
                        end if;
                    when VERIFYS => -- verify the last last word
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '1';
                        bit_ctr_ld <= '0';                        
                        pause_ctr_ld <= '0';
                        --fsm_a0_csb <= '0';
                        cfg_adr_ld <= '0';-- increment ROM address
                        fsm_cfg_done <= '0';
                        if pause_ctr_tc then
                            rdbkadr_en <= '0';
                            fsm_cs <= DONES;
                        else
                            rdbkadr_en <= '1';
                            fsm_cs <= VERIFYS;
                        end if;
                    when DONES => -- stay here when finished
                        fsm_rstb <= '1';                        
                        rdbkadr_en <= '0';
                        pause_ctr_ld <= '0';
                        if pause_ctr_tc then
                            fsm_sclk_en <= '0';
                            bit_ctr_ld <= '1';
                            cfg_adr_ld <= '1';
                            --fsm_a0_csb <= '0';
                            fsm_cfg_done <= '1';
                        else
                            fsm_sclk_en <= '1';
                            bit_ctr_ld <= '0';                            
                            cfg_adr_ld <= '0';
                            --fsm_a0_csb <= '1';
                            --fsm_cfg_done <= '0';
                            fsm_cfg_done <= si_lolb;--wait for lock, intr should also be used?
                        end if;
                        if cfg_enbl then
                            fsm_cs <= INITS;
                        else
                            fsm_cs <= DONES;
                        end if;
                    when others =>
                        fsm_rstb <= '1';
                        fsm_sclk_en <= '0';
                        bit_ctr_ld <= '1';                        
                        pause_ctr_ld <= '1';
                        rdbkadr_en <= '0';
                        cfg_adr_ld <= '1';
                        --fsm_a0_csb <= '0';
                        fsm_cfg_done <= '0';
                        fsm_cs <= INITS;
                    end case;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Shift register for writing.
    ------------------------------------------------------------------
    piso_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                piso <= (others => '0');
            else
                if ce = '1' then
                    if piso_ld = '1' then
                        piso <= SETADR & PGADR & "11" & WRDAT & cfg_rom_out(31 downto 24) & "11" & SETADR & cfg_rom_out(23 downto 16) & "11" & RDDAT & cfg_rom_out(7 downto 0) & "11";
                    else
                        piso <= piso(piso'left-1 downto 0) & '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Shift register for reading.
    ------------------------------------------------------------------
    sipo_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if reset = '1' then
                sipo_rdy <= '0';
                sipo <= (others => '0');
            else
                if ce = '1' then
                    sipo_rdy <= '1' when (bit_ctr_rd='1' and (rdbkadr_en and rdbkcmp_en)='1') else '0';
                    sipo <=  sipo(sipo'left-1 downto 0) & si_a1_sdo_q0;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Count the number bits written/read.
    ------------------------------------------------------------------
    bit_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if bit_ctr_ld then
                bit_ctr_tc <= '1';
                bit_ctr_rd <= '1';
                bit_ctr <= 0;
            else
                if ce = '1' then
                    bit_ctr_tc <= '1' when bit_ctr = 1 else '0'; -- count bits in word
                    bit_ctr_rd <= '1' when bit_ctr = 3 else '0'; -- count bits in word
                    if bit_ctr_tc then
                        bit_ctr <= NSHFT-1;
                    else
                        if bit_ctr = 0 then
                            bit_ctr <= NSHFT-1;
                        else
                            bit_ctr <= bit_ctr - 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Configuration memory address counter.
    -- The register spreadsheet in data sheet starts a the low bits,
    -- but the high bit must be shifted first, so start with max
    -- address and decrement.
    ------------------------------------------------------------------
    cfg_adr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if cfg_adr_ld then
                cfg_adr <= 0;
            else
                if cfg_adr_en then
                    if cfg_adr < MAX_CFG then
                        cfg_adr <= cfg_adr + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;


    ------------------------------------------------------------------
    -- Count the number bits from write until shifted into chip.
    ------------------------------------------------------------------
    pause_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if pause_ctr_ld = '1' then
                pause_ctr_tc <= '0';
                pause_ctr <= RDPAUSE;
            else
                --if ce and (not pause_ctr_tc) then
                if ce then
                    pause_ctr_tc <= '1' when pause_ctr = 0 else '0'; -- pause between read and write
                    if pause_ctr > 0 then
                        pause_ctr <= pause_ctr - 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end rd_arch;

-------------------------------------------------------------------------------
-- Architecture for routing SiLabs dongle data through debug use.
-------------------------------------------------------------------------------
architecture dongle_arch of si5345_intfc is

    component si5345_ila
    port (
        clk                             : in std_logic;
        probe0                          : in std_logic_vector(0  downto 0);
        probe1                          : in std_logic_vector(0  downto 0);
        probe2                          : in std_logic_vector(0  downto 0);
        probe3                          : in std_logic_vector(0  downto 0);
        probe4                          : in std_logic_vector(0  downto 0);
        probe5                          : in std_logic_vector(0 downto 0);
        probe6                          : in std_logic_vector(0  downto 0);
        probe7                          : in std_logic_vector(0 downto 0);
        probe8                          : in std_logic_vector(9 downto 0);
        probe9                          : in std_logic_vector(31 downto 0);
        probe10                         : in std_logic_vector(0  downto 0);
        probe11                         : in std_logic_vector(15 downto 0);
        probe12                         : in std_logic_vector(15 downto 0);
        probe13                         : in std_logic_vector(15 downto 0);
        probe14                         : in std_logic_vector(15 downto 0);
        probe15                         : in std_logic_vector(0  downto 0);
        probe16                         : in std_logic_vector(7  downto 0));
    end component;

    --constant DWDT                       : integer := 32;-- data width
    constant MAX_CFG                    : integer := NREGS-1;--test
    --constant ASIC_REGS                  : integer := 1144;
    --constant RDPAUSE                    : integer := ASIC_REGS-2;--test
    constant NBIT                       : integer                               := 8;      --numbers of bits in a SI5345 register
    constant NTRACT                     : integer                               := NBIT*2; --number of registers per SI5345 transaction (instruction + value)
    constant NSHFT                      : integer                               := NTRACT*4;--numbers of bits to shift for a read/write cycle, add 2 CS cycles

    constant SETADR                     : std_logic_vector(7 downto 0)          := X"00";--Set Address
    constant WRDAT                      : std_logic_vector(7 downto 0)          := X"40";--Write Data
    constant RDDAT                      : std_logic_vector(7 downto 0)          := X"80";--Read Data
    constant WRDATAI                    : std_logic_vector(7 downto 0)          := X"70";--Write Data + Address Increment
    constant RDDATAI                    : std_logic_vector(7 downto 0)          := X"A0";--Read Data + Address Increment
    constant BWRDAT                     : std_logic_vector(7 downto 0)          := X"E0";--Burst Write Data
    constant PGADR                      : std_logic_vector(7 downto 0)          := X"01";--page address

    signal si_ifen_q0                   : std_logic;
    signal si_rstb_q0                   : std_logic;
    signal si_sclk_q0                   : std_logic;-- SPI
    signal si_sclk_q1                   : std_logic;-- SPI
    signal si_a0_csb_q0                 : std_logic;
    signal si_sda_sdio_q0               : std_logic;
    signal si_a1_sdo_q0                 : std_logic;-- Stat/Ctrl
    signal si_oeb_q0                    : std_logic;
    signal si_intrb_q0                  : std_logic;
    signal si_lolb_q0                   : std_logic;

    signal cfg_adr_ld                   : std_logic;    
    signal cfg_adr_en                   : std_logic;
    signal cfg_wra_tc                   : std_logic;
    signal cfg_rda_tc                   : std_logic;
    signal cfg_pre_tc                   : std_logic;
    signal cfg_pst_tc                   : std_logic;
    signal cfg_adr                      : integer range 0 to MAX_CFG;
    signal cfg_rom_out                  : std_logic_vector(31 downto 0)     := (others => '0');

    signal piso_ld                      : std_logic;
    signal piso                         : std_logic_vector(NSHFT-1 downto 0);--parallel data in serial out

    signal sipo_rdy                     : std_logic;
    signal sipo                         : std_logic_vector(7 downto 0);--serial in parallel data out


    signal bit_ctr_tc                   : std_logic;
    signal bit_ctr_rd                   : std_logic;
    signal bit_ctr                      : natural range 0 to NSHFT-1;
    
    signal reg_sclk                     : std_logic;    

    alias set_pag_adr : std_logic_vector(15 downto 0) is piso(63 downto 48);
    alias set_pag_dat : std_logic_vector(15 downto 0) is piso(47 downto 32);
    alias set_val_adr : std_logic_vector(15 downto 0) is piso(31 downto 16);
    alias get_val_dat : std_logic_vector(15 downto 0) is piso(15 downto 0);

begin


--------------------------------------------------------------------------
-- Component instantiations
--------------------------------------------------------------------------

    ------------------------------------------------------------------
    -- Create a ROM to be used as a LUT for all configuration.
    -- The device has a block write function. Try to write the last
    -- (reset) address then wrap to the lower addresses.
    ------------------------------------------------------------------
    cfg_ram_ins : entity work.si5345_cfg_ram(cfg_ram_arch)
    port map(
        clk                             => clk,
        ce                              => '1',--bit_ctr_tc
        reset                           => reset,
        wren                            => '0',              --tie low to make a ROM
        wr_adr                          => (others => '0'),
        wr_data                         => (others => '0'),
        cfg_adr                         => cfg_adr,
        cfg_out                         => cfg_rom_out
    );

    ------------------------------------------------------------------
    -- ILA for test.
    ------------------------------------------------------------------
    ila_gen : if USE_ILA = TRUE generate
        si5345_ila_ins : si5345_ila
        port map (
            clk                         => clk,
            probe0(0)                   => si_sclk_q0,    
            probe1(0)                   => si_a0_csb_q0,  
            probe2(0)                   => si_sda_sdio_q0,
            probe3(0)                   => si_a1_sdo_q0,  
            probe4(0)                   => si_intrb_q0,  
            probe5(0)                   => si_lolb_q0,  
            probe6(0)                   => rdb_err,  
            probe7(0)                   => cfg_done,  
            probe8                      => STD_LOGIC_VECTOR(TO_UNSIGNED(cfg_adr,10)),
            probe9                      => cfg_rom_out,
            probe10(0)                  => piso_ld,
            probe11                     => set_pag_adr,
            probe12                     => set_pag_dat,
            probe13                     => set_val_adr,
            probe14                     => get_val_dat,
            probe15(0)                  => sipo_rdy,
            probe16                     => sipo
        );
    end generate;

--------------------------------------------------------------------------
-- Concurrent Statements
--------------------------------------------------------------------------

    --map signals to ports
    si_ifen     <= si_ifen_q0;
    si_rstb     <= si_rstb_q0;
    si_sclk     <= fp_sclk;
    si_a0_csb   <= fp_a0_csb;
    si_sda_sdio <= fp_sda_sdio;
    si_oeb      <= si_oeb_q0;
    fp_a1_sdo   <= si_a1_sdo;

    -- internal
    -- these may need to registered for timing, but what will happen to functionality?
    cfg_adr_en <= bit_ctr_tc and (reg_sclk and (not si_a0_csb_q0));
    cfg_wra_tc <= '1' when cfg_adr = (MAX_CFG-NPSTAMBL) else '0';--!!!must add post amble check logic
    cfg_rda_tc <= '1' when cfg_adr = (MAX_CFG-NPSTAMBL) else '0';
    cfg_pre_tc <= '1' when cfg_adr = (NPREAMBL-1) else '0';--!!!must add post amble check logic
    cfg_pst_tc <= '1' when cfg_adr = MAX_CFG else '0';--!!!must add post amble check logic

    piso_ld <= bit_ctr_tc and (not cfg_adr_ld);

    ------------------------------------------------------------------
    -- Pipeline outputs.
    ------------------------------------------------------------------
    pipe_pcs : process(clk)
    begin
        if (clk'event and clk='1') then

            -- inputs -------------
            si_a1_sdo_q0    <= si_a1_sdo;
            si_intrb_q0     <= si_intrb;
            si_lolb_q0      <= si_lolb;

            -- outputs --------------
            si_ifen_q0      <= '1';
            si_rstb_q0      <= '1';--fsm_rstb;
            si_oeb_q0       <= '0';
            si_sclk_q0      <= fp_sclk;
            si_a0_csb_q0    <= fp_a0_csb;
            si_sda_sdio_q0  <= fp_sda_sdio;           

            cfg_done  <= si_lolb and si_intrb;            
            rdb_err   <= '0';

            -- internal ---------------
            si_sclk_q0 <= si_sclk_q0;
            si_sclk_q1 <= si_sclk_q0;
            reg_sclk   <= (not si_sclk_q1) and si_sclk_q0;

        end if;
    end process;

    ------------------------------------------------------------------
    -- Shift register for writing.
    ------------------------------------------------------------------
    piso_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if cfg_enbl = '1' then
                piso <= (others => '0');
            else
                if (reg_sclk and (not si_a0_csb_q0)) then
                    if piso_ld = '1' then
                        piso <= SETADR & PGADR & WRDAT & cfg_rom_out(31 downto 24) & SETADR & cfg_rom_out(23 downto 16) & WRDAT & cfg_rom_out(7 downto 0);
                    else
                        piso <= piso(piso'left-1 downto 0) & '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Shift register for reading.
    ------------------------------------------------------------------
    sipo_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if cfg_enbl = '1' then
                sipo_rdy <= '0';
                sipo <= (others => '0');
            else
                if (reg_sclk and (not si_a0_csb_q0)) then
                    sipo_rdy <= '1' when bit_ctr_rd='1' else '0';
                    sipo <=  sipo(sipo'left-1 downto 0) & si_a1_sdo_q0;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Count the number bits written/read.
    ------------------------------------------------------------------
    bit_ctr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if cfg_enbl then
                bit_ctr_tc <= '1';
                bit_ctr_rd <= '1';
                bit_ctr <= 0;
            else
                if (reg_sclk and (not si_a0_csb_q0))  then
                    bit_ctr_tc <= '1' when bit_ctr = 1 else '0'; -- count bits in word
                    bit_ctr_rd <= '1' when bit_ctr = 3 else '0'; -- count bits in word
                    if bit_ctr_tc then
                        bit_ctr <= NSHFT-1;
                    else
                        if bit_ctr = 0 then
                            bit_ctr <= NSHFT-1;
                        else
                            bit_ctr <= bit_ctr - 1;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    ------------------------------------------------------------------
    -- Configuration memory address counter.
    -- The register spreadsheet in data sheet starts a the low bits,
    -- but the high bit must be shifted first, so start with max
    -- address and decrement.
    ------------------------------------------------------------------
    cfg_adr_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if cfg_enbl then
                cfg_adr <= 0;
            else
                if cfg_adr_en then
                    if cfg_adr < MAX_CFG then
                        cfg_adr <= cfg_adr + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

end dongle_arch;
