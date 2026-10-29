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
-- Test bench for HELIX TTCS using counters for the control signals.
--
--*********************************************************************************

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

entity si5345_intfc_tb is
end si5345_intfc_tb;

architecture behave of si5345_intfc_tb is

    constant CKPER                      : time                                  := 20 ns;
    constant CKHPER                     : time                                  := CKPER/2;
    constant BASE_ADDR                  : integer                               := 128*2-1;        
    constant MINRT                      : natural                               := 2**2;
    constant NENBL                      : natural                               := 1;
    constant INJECT_ERR                 : natural                               := 0;
    constant SCLKPER                    : real                                  := 80.0; --serial clock period in ns
    constant PHASE_VAL                  : integer                               := 2;--usually half CE period (16=8,8=4,4=2
    constant NREGS                      : natural                               := 526;
    constant NPREAMBL                   : integer                               := 3;-- number of registers in pre-amble
    constant NPSTAMBL                   : integer                               := 4;-- number of registers in post-amble
    constant SIM_SPDUP                  : boolean                               := TRUE;

    constant CSR_SELECT                 : std_logic                             := '1'; -- 0=probe regs, 1=control regs

    signal clk                          : std_logic                             := '0';
    signal ce                           : std_logic_vector(1 to NENBL);
    signal strobe                       : std_logic_vector(1 to NENBL);
    signal reset                        : std_logic;

    signal cfg_enbl                     : std_logic         := '0';
    signal cfg_done                     : std_logic;
    signal rdb_err                      : std_logic;

    -- field programmer interface
    signal fp_sclk                      : std_logic;-- SPI
    signal fp_a0_csb                    : std_logic;
    signal fp_sda_sdio                  : std_logic;
    signal fp_a1_sdo                    : std_logic;-- Stat/Ctrl

    signal si_ifen                      : std_logic;
    signal si_rstb                      : std_logic;
    signal si_sclk                      : std_logic;-- SPI
    signal si_a0_csb                    : std_logic;
    signal si_sda_sdio                  : std_logic;
    signal si_a1_sdo                    : std_logic;-- Stat/Ctrl
    signal si_oeb                       : std_logic;
    signal si_intrb                     : std_logic;
    signal si_lolb                      : std_logic;

    signal err_signal                   : std_logic;
    signal rdb_err_en                   : std_logic := '0';
    signal rdb_err_tst                  : std_logic := '1';

begin

---------------------------------------------------------------------------------------------------------
-- Component instantiations
---------------------------------------------------------------------------------------------------------

    -------------------------------------------------------
    -- Instantiate the unit under test.
    -------------------------------------------------------
    uut : entity work.si5345_intfc(rdwr_arch)
    generic map(
        SCLKPER                         => SCLKPER,
        NREGS                           => NREGS,
        NPREAMBL                        => NPREAMBL,-- number of registers in pre-amble
        NPSTAMBL                        => NPSTAMBL,-- number of registers in post-amble
        PHASE_VAL                       => PHASE_VAL,-- adjust delay between data and clock
        SIM_SPDUP                       => SIM_SPDUP,
        USE_ILA                         => FALSE)
    port map(       
        clk                             => clk,
        ce                              => ce(1),
        strobe                          => strobe(1),
        reset                           => reset,
        --                              
        cfg_enbl                        => cfg_enbl,
        cfg_done                        => cfg_done,
        rdb_err                         => rdb_err,
        -- field programmer interface
        fp_sclk                         => fp_sclk      ,   
        fp_a0_csb                       => fp_a0_csb   ,
        fp_sda_sdio                     => fp_sda_sdio ,
        fp_a1_sdo                       => fp_a1_sdo   ,
        --      
        si_ifen                         => si_ifen,
        si_rstb                         => si_rstb,
        si_sclk                         => si_sclk,
        si_a0_csb                       => si_a0_csb,
        si_sda_sdio                     => si_sda_sdio,
        si_a1_sdo                       => si_a1_sdo,
        si_oeb                          => si_oeb,
        si_intrb                        => si_intrb,
        si_lolb                         => si_lolb
    );

    -------------------------------------------------------
    -- Instantiate the device model.
    -------------------------------------------------------
    device : entity work.si5345
    port map(
        rstb                        => si_rstb,    
        sclk                        => si_sclk,    
        a0_csb                      => si_a0_csb,  
        sda_sdio                    => si_sda_sdio,
        a1_sdo                      => si_a1_sdo,  
        oeb                         => si_oeb,     
        intrb                       => si_intrb,   
        lolb                        => si_lolb    
    );

    -------------------------------------------------------
    -- Clock enable generator.
    -------------------------------------------------------
    clk_enbl_ins : entity work.clk_enbl_gen
    generic map(
        MINRT                           => MINRT,
        NENBL                           => NENBL)
    port map(
        clk                             => clk,
        reset                           => reset,
        enable                          => ce,
        strobe                          => strobe
    );

---------------------------------------------------------------------------------------------------------
-- Concurrent statements
---------------------------------------------------------------------------------------------------------

    -- simulate power on reset
    clk <= not clk after CKHPER;
    reset <= '0', '1' after CKPER*200, '0' after CKPER*201;
    cfg_enbl <= '0', '1' after CKPER*300, '0' after CKPER*364;

    fp_sclk     <= '0';
    fp_a0_csb   <= '0';
    fp_sda_sdio <= '0';

    -- inject an error
    err_gen : if INJECT_ERR = 1 generate
        err_signal <= '0' when srout_sr = '1' else '1';
    elsif INJECT_ERR = 0 generate
        err_signal <= '0';
    end generate;

---------------------------------------------------------------------------------------------------------
-- Sequential statements
---------------------------------------------------------------------------------------------------------

    -------------------------------------------------------
    -- Assertions to generate message when problems.
    -------------------------------------------------------
    verify_pcs : process(clk)
    begin
        if rising_edge(clk) then
            if cfg_enbl then
                rdb_err_en <= '1';
            else
                if rdb_err then
                    rdb_err_en <= '0';
                end if;
            end if;
            rdb_err_tst <= '1' when rdb_err_en = '0' else (not rdb_err);
            assert (rdb_err_tst) report "Read-back error" severity error;
        end if;
    end process;

end behave;