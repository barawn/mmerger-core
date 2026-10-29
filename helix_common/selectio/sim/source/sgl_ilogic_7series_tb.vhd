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

entity sgl_ilogic_7series_tb is
end sgl_ilogic_7series_tb;

architecture behave of sgl_ilogic_7series_tb is

    constant ICKPER                     : time                          := 5 ns;
    constant ICKHPER                    : time                          := ICKPER/2;
    constant DCKPER                     : time                          := 12.5 ns;
    constant DCKHPER                    : time                          := DCKPER/2;
	constant USE_IDELAY				    : natural range 0 to 1	        := 0;--0=no,1=yes
	constant USE_BUFG				    : natural range 0 to 1	        := 0;--0=no,1=yes
	constant RGBUF_TYP				    : natural range 0 to 1	        := 1;--0=BUFIO,1=BUFR    
    constant USE_FIFO                   : natural range 0 to 1          := 0;--0=don't use IN_FIFO,1= use IN_FIFO    
    constant REFCLK_FREQUENCY           : real                          := 200.0;
    constant HIGH_PRFM_MODE             : string                        := "FALSE";
    constant DWDT                       : positive                      := 12;    
    constant USE_IDLYDL                 : std_logic                     := '1';

    signal lreset                       : std_logic;
    signal idelay_clk                   : std_logic                     := '0';
    signal idelay_ld                    : std_logic;
    signal idelay_cntvalin              : std_logic_vector(4 downto 0)  := "00000";
    signal io_clk_out                   : std_logic;
    signal io_clk_in                    : std_logic                     := '0';
    signal fbrc_tx_clk                  : std_logic;
    signal idelay_clkg                  : std_logic;
    signal idelay_clkr                  : std_logic;

    signal io_data                      : std_logic_vector(DWDT/2-1 downto 0);
    signal fbrc_data                    : std_logic_vector(DWDT-1 downto 0);

    signal data_ctr                     : unsigned(DWDT/2-1 downto 0)   := (others => '0');
    signal delay_ctr                    : unsigned(5 downto 0)          := (others => '0');
    signal dithr_ctr                    : integer                       := 0;

begin

---------------------------------------------------------------------------------------------------------
-- Component instantiations
---------------------------------------------------------------------------------------------------------

    -------------------------------------------------------
    -- Instantiate the unit under test.
    -------------------------------------------------------
    clogic_ins : entity work.sgl_clogic_7series
    generic map(
        USE_IDELAY						=> USE_IDELAY,
        USE_BUFG						=> USE_BUFG,
        RGBUF_TYP						=> RGBUF_TYP,
        HIGH_PRFM_MODE                  => HIGH_PRFM_MODE,
        REFCLK_FREQUENCY                => REFCLK_FREQUENCY)
    port map(
        lreset                          => lreset           ,
        --idelayctrl_rdy                => idelayctrl_rdy   ,
        idelay_clk                      => idelay_clk       ,
        idelay_ld                       => idelay_ld        ,
        idelay_cntvalin                 => idelay_cntvalin  ,
        -- IO interface                                     ,
        io_clk_out                      => io_clk_out       ,
        -- IO interface                                     ,
        io_clk_in                       => io_clk_in        ,
        -- Fabric interface                                 ,
        fbrc_tx_clk                     => fbrc_tx_clk      ,
        idelay_clkg                     => idelay_clkg      ,
        idelay_clkr                     => idelay_clkr
    );

    ilogic_ins : entity work.sgl_ilogic_7series
    generic map(
        USE_FIFO                        => USE_FIFO,
        HIGH_PRFM_MODE                  => HIGH_PRFM_MODE,
        REFCLK_FREQUENCY                => REFCLK_FREQUENCY,
        DWDT                            => DWDT)
    port map(
        lreset                          => lreset           ,
        idelay_clk                      => idelay_clk       ,
        idelay_ld                       => idelay_ld        ,
        fbrc_clk                        => fbrc_tx_clk      ,
        idelay_cntvalin                 => idelay_cntvalin  ,
        -- ilogic side connections
        io_clk                          => io_clk_out       ,
        io_data                         => io_data          ,
        -- Fabric side connections
        fbrc_data                       => fbrc_data
    );


---------------------------------------------------------------------------------------------------------
-- Concurrent statements
---------------------------------------------------------------------------------------------------------

    -- simulate power on reset
    lreset <= '1', '0' after DCKPER*8;
    idelay_clk <= not idelay_clk after ICKHPER;
    io_clk_in   <= not io_clk_in after DCKHPER;
    fbrc_tx_clk <= io_clk_in'delayed(DCKHPER/8);

    io_data <= STD_LOGIC_VECTOR(data_ctr);
    
    idelay_cntvalin <= STD_LOGIC_VECTOR(delay_ctr(idelay_cntvalin'left downto 0));

---------------------------------------------------------------------------------------------------------
-- Sequential statements
---------------------------------------------------------------------------------------------------------
    data_gen : process(io_clk_in)
    begin
        if rising_edge(io_clk_in) then
            data_ctr <= data_ctr + 1;
        end if;
    end process;

    delay_gen : process(idelay_clk,delay_ctr(5))
    begin
        if rising_edge(idelay_clk) then
            delay_ctr <= delay_ctr + 1;
            if dithr_ctr < 6 then
                idelay_ld <= '0';
                dithr_ctr <= dithr_ctr + 1;
            else
                idelay_ld <= USE_IDLYDL;
                dithr_ctr <= 0;
            end if;            
        end if;
    end process;


end behave;