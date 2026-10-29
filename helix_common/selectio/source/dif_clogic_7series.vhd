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
-- Input and output clock for a bi-directional, source synchronous interface.
--
--*********************************************************************************

library ieee;
    use ieee.std_logic_1164.all;
library unisim;
    use unisim.vcomponents.all;

entity dif_clogic_7series is
generic(
    USE_IDELAY                      : natural range 0 to 1  := 0;--0=no,1=yes
    USE_BUFG                        : natural range 0 to 1  := 0;--0=no,1=yes
    RGBUF_TYP                       : natural range 0 to 1  := 1;--0=BUFIO,1=BUFR
    HIGH_PRFM_MODE                  : string                := "TRUE";
    REFCLK_FREQUENCY                : real                  := 200.00;
    CLK_IN_INV                      : std_logic             := '0';
    CLK_OUT_EDGE                    : string                := "RISE");--rise or fall
port(
    lreset                          : in std_logic;    
    --idelayctrl_rdy                : in std_logic_vector(0 downto 0);
    idelay_clk                      : in std_logic;
    idelay_ld                       : in std_logic;    
    idelay_cntvalin                 : in std_logic_vector(4 downto 0);
    -- IO interface
    io_clk_out_p                    : out std_logic;
    io_clk_out_n                    : out std_logic;
    -- IO interface
    io_clk_in_p                     : in std_logic;
    io_clk_in_n                     : in std_logic;
    -- Fabric interface
    fbrc_tx_clk                     : in std_logic;
    global_clk                      : out std_logic;
    regional_clk                    : out std_logic);
end dif_clogic_7series;

architecture behave of dif_clogic_7series is

    constant CLK_RE                 : std_logic_vector(1 to 2)               := "10";--clock rising-edge aligned
    constant CLK_FE                 : std_logic_vector(1 to 2)               := "01";--clock falling-edge aligned

    signal io_clk_out_b             : std_logic;
    signal io_clk_in_b              : std_logic;--selected by CLK_IN_INV
    signal idelay_cntvalout         : std_logic_vector(4 downto 0);
    signal idelay_dataout           : std_logic;
    signal idelay_dataout_inv       : std_logic;
    signal clk_out_d                : std_logic_vector(1 to 2);
       
begin

    --------------------------------------------------
    -- Clock Output Buffer
    --------------------------------------------------
    io_clk_out_buf : OBUFDS
    generic map (
        IOSTANDARD                  => "DEFAULT",
        SLEW                        => "SLOW")
    port map(
        O                           => io_clk_out_p,
        OB                          => io_clk_out_n,
        I                           => io_clk_out_b
    );

    ------------------------------------------------------
    -- Forward clock through ODDR to equalize delay (with data)
    ------------------------------------------------------
    clk_oddr : ODDR
    generic map(
        DDR_CLK_EDGE                => "SAME_EDGE",     -- "OPPOSITE_EDGE" or "SAME_EDGE"
        INIT                        => '0',             -- Initial value for Q port ('1' or '0')
        SRTYPE                      => "SYNC")          -- Reset Type ("ASYNC" or "SYNC")
    port map (  
        Q                           => io_clk_out_b,    -- 1-bit DDR output
        C                           => fbrc_tx_clk,     -- 1-bit clock input
        CE                          => '1',             -- 1-bit clock enable input
        D1                          => clk_out_d(1),    -- 1-bit data input (positive edge)
        D2                          => clk_out_d(2),    -- 1-bit data input (negative edge)
        R                           => '0',             -- 1-bit reset input
        S                           => '0'              -- 1-bit set input
    );

    --------------------------------------------------
    -- Clock input buffer
    --------------------------------------------------
    io_clk_in_buf : IBUFGDS
    generic map (
        DIFF_TERM                   => TRUE,
        IBUF_LOW_PWR                => FALSE,
        IOSTANDARD                  => "DEFAULT")
    port map(
        O                           => io_clk_in_b,
        I                           => io_clk_in_p,
        IB                          => io_clk_in_n
    );

    ----------------------------------------------------------------------  
    dly_gen : if USE_IDELAY = 1 generate    
        ---------------------------------------------
        -- Clock delay
        ---------------------------------------------
        clk_delay_ins : IDELAYE2
        generic map (
            CINVCTRL_SEL                => "FALSE",             -- Enable dynamic clock inversion (FALSE, TRUE)
            DELAY_SRC                   => "IDATAIN",           -- Delay input (IDATAIN, DATAIN)
            HIGH_PERFORMANCE_MODE       => HIGH_PRFM_MODE,      -- Reduced jitter ("TRUE"), Reduced power ("FALSE")
            IDELAY_TYPE                 => "VAR_LOAD",          -- FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
            IDELAY_VALUE                => 0,                   -- Input delay tap setting (0-31)
            PIPE_SEL                    => "FALSE",             -- Select pipelined mode, FALSE, TRUE
            REFCLK_FREQUENCY            => REFCLK_FREQUENCY,    -- IDELAYCTRL clock input frequency in MHz (190.0-210.0, 290.0-310.0).
            SIGNAL_PATTERN              => "CLOCK")             -- DATA, CLOCK input signal
        port map (  
            CNTVALUEOUT                 => idelay_cntvalout,    -- 5-bit output: Counter value output
            DATAOUT                     => idelay_dataout,      -- 1-bit output: Delayed data output
            C                           => idelay_clk,          -- 1-bit input: Clock input
            CE                          => '0',                 -- 1-bit input: Active high enable increment/decrement input
            CINVCTRL                    => '0',                 -- 1-bit input: Dynamic clock inversion input
            CNTVALUEIN                  => idelay_cntvalin,     -- 5-bit input: Counter value input
            DATAIN                      => '0',                 -- 1-bit input: Internal delay data input
            IDATAIN                     => io_clk_in_b,         -- 1-bit input: Data input from the I/O
            INC                         => '0',                 -- 1-bit input: Increment / Decrement tap delay input
            LD                          => idelay_ld,           -- 1-bit input: Load IDELAY_VALUE input
            LDPIPEEN                    => '0',                 -- 1-bit input: Enable PIPELINE register to load data input
            REGRST                      => '0'                  -- 1-bit input: Active-high reset tap-delay input
        );
    
    elsif USE_IDELAY = 0 generate

        idelay_dataout  <= io_clk_in_b;

    end generate;--IDELAY
    ------------------------------------------------------
    
	----------------------------------------------------------------------	
	gbl_gen : if USE_BUFG = 1 generate    
        --------------------------------------------------
        -- Clock global buffer
        --------------------------------------------------
        clk_bufg : BUFG
        port map (
           O                            => global_clk,          -- 1-bit output: Clock output port
           I                            => idelay_dataout_inv   -- 1-bit input: Clock buffer input driven by an IBUF, MMCM or local interconnect
        );        

	elsif USE_BUFG = 0 generate
	
		global_clk <= idelay_dataout_inv;

	end generate;--BUFG
	------------------------------------------------------    
    
	----------------------------------------------------------------------	
	rgb_gen : if RGBUF_TYP = 0 generate
	    --------------------------------------------------
		-- Clock I/O buffer
		--! Try this first becaue BUFRs are more valuable
		--------------------------------------------------
		clk_bufr : BUFIO
		port map (
		   O                            => regional_clk,             -- 1-bit output: Clock output port
		   I                            => idelay_dataout            -- 1-bit input: Clock buffer input driven by an IBUF, MMCM or local interconnect
		);
		
	elsif RGBUF_TYP = 1 generate
		--------------------------------------------------
		-- Clock regonial buffer
		--! Use this if BUFIO does not work.
		--------------------------------------------------
		clk_bufr : BUFR
		generic map (
		    BUFR_DIVIDE             => "BYPASS",            -- Values: "BYPASS, 1, 2, 3, 4, 5, 6, 7, 8"
		    SIM_DEVICE              => "7SERIES")           -- Must be set to "7SERIES"
		port map (
		   O                        => regional_clk,        -- 1-bit output: Clock output port
		   CE                       => '1',                 -- 1-bit input: Active high, clock enable (Divided modes only)
		   CLR                      => '0',                 -- 1-bit input: Active high, asynchronous clear (Divided modes only)
		   I                        => idelay_dataout       -- 1-bit input: Clock buffer input driven by an IBUF, MMCM or local interconnect
		);
	end generate;--RGFBUF
	-------------------------------------------------------

    idelay_dataout_inv <= (not idelay_dataout) when CLK_IN_INV else idelay_dataout;--does this need to be a generate statement?
    clk_out_d <= CLK_RE when CLK_OUT_EDGE="RISE" else CLK_FE;

end behave;
