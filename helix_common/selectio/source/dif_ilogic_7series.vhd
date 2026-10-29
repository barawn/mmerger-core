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
-- Configurable width IDDDR/ISERDES bus with input FIFO for Xilinx 7-Series FPGAs.
--
-- Deficiencies/Know Issues:
-- 1) Need to add delay control state machine for eye scan.
--*********************************************************************************

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
library unisim;
    use unisim.vcomponents.all;

entity dif_ilogic_7series is
generic(
    USE_FIFO                        : natural range 0 to 1  := 0;--0=don't use IN_FIFO,1= use IN_FIFO
    HIGH_PRFM_MODE                  : string                := "TRUE";
    REFCLK_FREQUENCY                : real                  := 200.0;
    DWDT                            : integer range 2 to 12 := 10);
port(
    lreset                          : in std_logic;
    idelay_clk                      : in std_logic;
    idelay_ld                       : in std_logic;    
    idelay_cntvalin                 : in std_logic_vector(4 downto 0);
    fbrc_clk                        : in std_logic;    
    -- ilogic side connections
    io_clk                          : in std_logic;  --forwarded clock
    io_data_p                       : in std_logic_vector(DWDT/2-1 downto 0);
    io_data_n                       : in std_logic_vector(DWDT/2-1 downto 0);
    -- Fabric side connections
    fbrc_data                       : out std_logic_vector(DWDT-1 downto 0));
end dif_ilogic_7series;

architecture behave_7series of dif_ilogic_7series is

    constant LOGICSHFT_INIT         : std_logic_vector(7 downto 0)      := X"FF";
    constant FIFOSHFT_INIT          : std_logic_vector(7 downto 0)      := X"03";
    constant FIFO_UIN               : std_logic_vector(3 downto 0)      := X"0";

    type fifod_t is array (9 downto 0) of std_logic_vector(7 downto 0);
    type cntvalout_t is array (DWDT/2-1 downto 0) of std_logic_vector(4 downto 0);

    signal shift_rst                : std_logic_vector(3 downto 0)      := "1111";--pattern for fifo reset
    signal logicrst_shift           : std_logic_vector(7 downto 0)      := LOGICSHFT_INIT;--pattern for fifo reset
    signal fiforst_shift            : std_logic_vector(7 downto 0)      := FIFOSHFT_INIT;--pattern for fifo reset
    signal write_reset              : std_logic;
    signal fifo_reset               : std_logic;

    signal idelay_cntvalout         : cntvalout_t;
    signal io_data_b                : std_logic_vector(DWDT/2-1 downto 0);
    signal idelay_do                : std_logic_vector(DWDT/2-1 downto 0);
    signal iddr_do                  : std_logic_vector(DWDT-1 downto 0);

    signal fifo_afull               : std_logic;
    signal fifo_full                : std_logic;
    signal fifo_wren                : std_logic                         := '0';
    signal fifo_aepty               : std_logic;
    signal fifo_epty                : std_logic;
    signal fifo_rden                : std_logic                         := '0';

    signal fifo_dvec                : fifod_t                           := (others => (others => '0'));
    signal fifo_qvec                : std_logic_vector(79 downto 0);
    signal fifo_qmap                : std_logic_vector(19 downto 0);

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of shift_rst : signal is "TRUE";

begin

    ----------------------------------------------------------------------
    -- Instantiate the ilogic components
    ----------------------------------------------------------------------
    ilogic_gen:
    for I in 0 to DWDT/2-1 generate
        --------------------------------------------------
        -- Differential input buffers
        --------------------------------------------------
        rx_data_ibuf: IBUFDS
        generic map(
            DIFF_TERM               => TRUE,
            IBUF_LOW_PWR            => FALSE,
            IOSTANDARD              => "DEFAULT")
        port map(
            O                       => io_data_b(I),
            I                       => io_data_p(I),
            IB                      => io_data_n(I)
        );

        --------------------------------------------------
        -- Input delay primitives
        --------------------------------------------------
        data_delay_ins : IDELAYE2
        generic map (
            CINVCTRL_SEL            => "FALSE",             -- Enable dynamic clock inversion (FALSE, TRUE)
            DELAY_SRC               => "IDATAIN",           -- Delay input (IDATAIN, DATAIN)
            HIGH_PERFORMANCE_MODE   => HIGH_PRFM_MODE,      -- Reduced jitter ("TRUE"), Reduced power ("FALSE")
            IDELAY_TYPE             => "VAR_LOAD",          -- FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
            IDELAY_VALUE            => 0,                   -- Input delay tap setting (0-31)
            PIPE_SEL                => "FALSE",             -- Select pipelined mode, FALSE, TRUE
            REFCLK_FREQUENCY        => REFCLK_FREQUENCY,    -- IDELAYCTRL clock input frequency in MHz (190.0-210.0, 290.0-310.0).
            SIGNAL_PATTERN          => "DATA")              -- DATA, CLOCK input signal
        port map (
            CNTVALUEOUT             => idelay_cntvalout(I), -- 5-bit output: Counter value output
            DATAOUT                 => idelay_do(I),        -- 1-bit output: Delayed data output
            C                       => idelay_clk,          -- 1-bit input: Clock input
            CE                      => '0',                 -- 1-bit input: Active high enable increment/decrement input
            CINVCTRL                => '0',                 -- 1-bit input: Dynamic clock inversion input
            CNTVALUEIN              => idelay_cntvalin,     -- 5-bit input: Counter value input
            DATAIN                  => '0',                 -- 1-bit input: Internal delay data input
            IDATAIN                 => io_data_b(I),        -- 1-bit input: Data input from the I/O
            INC                     => '0',                 -- 1-bit input: Increment / Decrement tap delay input
            LD                      => idelay_ld,           -- 1-bit input: Load IDELAY_VALUE input
            LDPIPEEN                => '0',                 -- 1-bit input: Enable PIPELINE register to load data input
            REGRST                  => '0'                  -- 1-bit input: Active-high reset tap-delay input
        );

        --------------------------------------------------
        -- Input DDR registers
        --------------------------------------------------
        iddr_ins : IDDR
        generic map(
            DDR_CLK_EDGE        => "SAME_EDGE_PIPELINED",   -- "OPPOSITE_EDGE" or "SAME_EDGE" or "SAME_EDGE_PIPELINED"
            INIT_Q1             => '0',                     -- Initial value of Q1: '0' or '1'
            INIT_Q2             => '0',                     -- Initial value of Q2: '0' or '1'
            SRTYPE              => "SYNC")                  -- Reset Type ("ASYNC" or "SYNC")
         port map (
            Q1                  => iddr_do(I*2),            -- 1-bit output for positive edge of clock
            Q2                  => iddr_do(I*2+1),          -- 1-bit output for negative edge of clock
            C                   => io_clk,                  -- 1-bit clock input
            CE                  => '1',                     -- 1-bit clock enable input
            D                   => idelay_do(I),            -- 1-bit DDR data input
            R                   => '0',                     -- 1-bit reset
            S                   => '0'                      -- 1-bit set
        );

        fifo_dvec(I) <= STD_LOGIC_VECTOR(RESIZE(UNSIGNED(iddr_do(I*2+1 downto I*2)),fifo_dvec(I)'length));

    end generate;

    ----------------------------------------------------------------------
    fifo_gen : if USE_FIFO = 1 generate    
        --------------------------------------------------
        -- Input (I/O) FIFO crosses from forwarded
        -- clock to fabric clock domain.
        --------------------------------------------------
        in_fifo_inst : IN_FIFO
        generic map (
            ALMOST_EMPTY_VALUE      => 2, -- Almost empty offset (1-2)
            ALMOST_FULL_VALUE       => 2, -- Almost full offset (1-2)
            ARRAY_MODE              => "ARRAY_MODE_4_X_4", -- ARRAY_MODE_4_X_8, ARRAY_MODE_4_X_4
            SYNCHRONOUS_MODE        => "FALSE") -- Clock synchronous (FALSE)
        port map (
            -- FIFO Status Flags: 1-bit (each) output: Flags and other FIFO status outputs
            ALMOSTEMPTY             => fifo_aepty, -- 1-bit output: Almost empty
            ALMOSTFULL              => fifo_afull, -- 1-bit output: Almost full
            EMPTY                   => fifo_epty, -- 1-bit output: Empty
            FULL                    => fifo_full, -- 1-bit output: Full
            -- Q0-Q9: 8-bit (each) output: FIFO Outputs
            Q0                      => fifo_qvec(7 downto 0),   -- 8-bit output: Channel 0
            Q1                      => fifo_qvec(15 downto 8),  -- 8-bit output: Channel 1
            Q2                      => fifo_qvec(23 downto 16), -- 8-bit output: Channel 2
            Q3                      => fifo_qvec(31 downto 24), -- 8-bit output: Channel 3
            Q4                      => fifo_qvec(39 downto 32), -- 8-bit output: Channel 4
            Q5                      => fifo_qvec(47 downto 40), -- 8-bit output: Channel 5
            Q6                      => fifo_qvec(55 downto 48), -- 8-bit output: Channel 6
            Q7                      => fifo_qvec(63 downto 56), -- 8-bit output: Channel 7
            Q8                      => fifo_qvec(71 downto 64), -- 8-bit output: Channel 8
            Q9                      => fifo_qvec(79 downto 72), -- 8-bit output: Channel 9
            -- D0-D9: 4-bit (each) input: FIFO inputs
            D0                      => fifo_dvec(0)(3 downto 0), -- 4-bit input: Channel 0
            D1                      => fifo_dvec(1)(3 downto 0), -- 4-bit input: Channel 1
            D2                      => fifo_dvec(2)(3 downto 0), -- 4-bit input: Channel 2
            D3                      => fifo_dvec(3)(3 downto 0), -- 4-bit input: Channel 3
            D4                      => fifo_dvec(4)(3 downto 0), -- 4-bit input: Channel 4
            D5                      => fifo_dvec(5)(7 downto 0), -- 8-bit input: Channel 5
            D6                      => fifo_dvec(6)(7 downto 0), -- 8-bit input: Channel 6
            D7                      => fifo_dvec(7)(3 downto 0), -- 4-bit input: Channel 7
            D8                      => fifo_dvec(8)(3 downto 0), -- 4-bit input: Channel 8
            D9                      => fifo_dvec(9)(3 downto 0), -- 4-bit input: Channel 9
            -- FIFO Control Signals: 1-bit (each) input: Clocks, Resets and Enables
            RDCLK                   => fbrc_clk, -- 1-bit input: Read clock
            RDEN                    => fifo_rden, -- 1-bit input: Read enable
            RESET                   => fifo_reset, -- 1-bit input: Reset
            WRCLK                   => io_clk, -- 1-bit input: Write clock
            WREN                    => fifo_wren -- 1-bit input: Write enable
        );

    -- pipeline this?
    fifo_qmap <= fifo_qvec(73 downto 72) & fifo_qvec(65 downto 64) & fifo_qvec(57 downto 56) & fifo_qvec(49 downto 48) & fifo_qvec(41 downto 40)
        & fifo_qvec(33 downto 32) & fifo_qvec(25 downto 24) & fifo_qvec(17 downto 16) & fifo_qvec(9 downto 8) & fifo_qvec(1 downto 0);
        
    elsif USE_FIFO = 0 generate
    
        fifo_aepty <= '0';
        fifo_afull <= '0';
        fifo_epty  <= '0'; 
        fifo_full  <= '0'; 
    
        fifo_qmap <= fifo_dvec(9)(1 downto 0) & fifo_dvec(8)(1 downto 0) & fifo_dvec(7)(1 downto 0) & fifo_dvec(6)(1 downto 0) & fifo_dvec(5)(1 downto 0)
            & fifo_dvec(4)(1 downto 0) & fifo_dvec(3)(1 downto 0) & fifo_dvec(2)(1 downto 0) & fifo_dvec(1)(1 downto 0) & fifo_dvec(0)(1 downto 0);
    
    end generate;--FIFO
    ------------------------------------------------------        
        
    fbrc_data <= STD_LOGIC_VECTOR(RESIZE(UNSIGNED(fifo_qmap),fbrc_data'length));
    fifo_reset <= fiforst_shift(0);
    write_reset <= logicrst_shift(0);
    fifo_rden <= not fifo_epty;
    fifo_wren <= not write_reset;
    
    ------------------------------------------------------------------    
    -- Assert reset for shift length clock cycles at init time for FIFO.
    -- Also acts as clock activity monitor so wren is not asserted too
    -- ealry.
    ------------------------------------------------------------------
    reset_pcs : process(fbrc_clk)
    begin
        if (fbrc_clk'event and fbrc_clk='1') then
            -- generate FIFO reset signals
            shift_rst <= lreset & shift_rst(shift_rst'length-1 downto 1);
            if shift_rst(0) = '1' then
                -- assert reset for shift length
                logicrst_shift <= LOGICSHFT_INIT;
                fiforst_shift <= FIFOSHFT_INIT;
            else
                -- de-assert after shift length
                logicrst_shift <= '0' & logicrst_shift(logicrst_shift'length-1 downto 1);
                fiforst_shift  <= '0' & fiforst_shift(fiforst_shift'length-1 downto 1);
            end if;
        end if;
    end process;
    
    ------------------------------------------------------------------    
    -- Pipeline to improve timing.
    ------------------------------------------------------------------    
    --pipe_pcs : process(fbrc_clk)
    --begin
    --    if (fbrc_clk'event and fbrc_clk='1') then
    --        -- generate FIFO control signals
    --        fifo_rden <= not fifo_epty;
    --        fifo_wren <= not write_reset;
    --    end if;
    --end process;    

end behave_7series;
