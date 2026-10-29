-- this wraps the dncpcie_aurora_core, simplifying some of its interfacing
--
-- The output Aurora clock is at 160 MHz, which should be fine for basically anything.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library unisim;
use unisim.vcomponents.all;

library work;
use work.ttcs_intfc_pkg.all;

entity aurora_vwrap is
generic(
        EXAMPLE_SIMULATION          : integer;   --- 0
        LANE                        : integer;
        XOFF_BUSY                   : string := "FALSE");
port(           
    -- this should be the same frequency as gt_refclk, 160 MHz
    aclk                     : in    std_logic;
    -- 16 bit transmit path
    s_axis_tx_tdata          : in    std_logic_vector(15 downto 0);
    s_axis_tx_tvalid         : in    std_logic;
    s_axis_tx_tready         : out   std_logic;
    s_axis_tx_tlast          : in    std_logic;
    s_axis_tx_tuser          : in    std_logic;
    -- auxiliary output indicating I'm gonna dump yer stuff
    s_axis_tx_will_discard   : out   std_logic;
    --Flow control assertion. This isn't an AXI4-Stream qualified signal, it just means that
    --on this link, transmission should stop AFTER this frame. This feeds into the
    --streamer which checks it before starting an actual transmission sequence.
    axis_tx_xoff               : out std_logic;
    -- dumb bullshit only used if xoff busy is used
    busy_reset                  : in std_logic;
    going_full                  : in std_logic;
    trig                        : out std_logic;
    -- Raw 32-bit receive path.
        m_axis_raw_tdata             : out std_logic_vector(0 to 31);
        m_axis_raw_tkeep             : out std_logic_vector(0 to 3);
        m_axis_raw_tvalid            : out std_logic;
        m_axis_raw_tlast             : out std_logic;
    -- 32-bit receive path. 3 bits are tkeep err, CRC err, tuser
    m_axis_rx_tdata          : out std_logic_vector(31 downto 0);
    m_axis_rx_tvalid         : out std_logic;
    m_axis_rx_tlast          : out std_logic;
    m_axis_rx_tuser          : out std_logic_vector(2 downto 0);
    -- Flow control. There's two inputs, one to transmit the XOFF and another to initiate frame dropping
    -- in case the partner didn't stop. There's also an output which indicates that a frame was dropped.
    axis_rx_xoff           : in std_logic;
    axis_rx_drop           : in std_logic;
    axis_rx_dropped        : out std_logic;
    -- status clock. err/status/ctrl are all in the status_clk domain (100 MHz register clock)
    status_clk               : in std_logic;
    -- error outputs (crc/frame/soft/hard)
    err                      : out std_logic_vector(3 downto 0);
    -- (reset busy, link reset out, rx_resetdone/tx_resetdone, powerdown, 3-bit loopback, tx_lock, GT powergood, channel up, lane up)
    status                   : out std_logic_vector(11 downto 0);
    -- powerdown/3-bit loopback/error reset/full reset
    control                  : in std_logic_vector(5 downto 0);
    -- GT reset length
    gt_reset_len             : in std_logic_vector(15 downto 0);
    -- GT layer
    gt_refclk                : in    std_logic;
    gt_bufclk                : in    std_logic;
    init_clk                 : in    std_logic;
    tx_out_clk               : out   std_logic;
    rxp                      : in    std_logic;
    rxn                      : in    std_logic;
    txp                      : out   std_logic;
    txn                      : out   std_logic);
    
end entity;

architecture struct of aurora_vwrap is

    component dnpcie_aurora_core
    generic(
        CC_FREQ_FACTOR              : integer;   --  := 5'd12,
        EXAMPLE_SIMULATION          : integer;   --- 0
        LANE                        : integer;        
        XOFF_BUSY                   : string;
        DEBUG_MASK                  : std_logic_vector(7 downto 0)); --0      
    port(
        --AXI TX Interface
        s_axis_tx_tdata              : in  std_logic_vector(0 to 15);
        s_axis_tx_tkeep              : in  std_logic_vector(0 to 1);
        s_axis_tx_tvalid             : in  std_logic;
        s_axis_tx_tlast              : in  std_logic;
        s_axis_tx_tready             : out std_logic;
        -- Debugging.
        m_axis_raw_tdata             : out std_logic_vector(0 to 31);
        m_axis_raw_tkeep             : out std_logic_vector(0 to 3);
        m_axis_raw_tvalid            : out std_logic;
        m_axis_raw_tlast             : out std_logic;
        --AXI RX Interface
        m_axis_rx_tdata              : out std_logic_vector(0 to 31);
        m_axis_rx_tkeep              : out std_logic_vector(0 to 3);
        m_axis_rx_tvalid             : out std_logic;
        m_axis_rx_tuser              : out std_logic;
        m_axis_rx_tlast              : out std_logic;
        m_axis_crc_pass_fail_n       : out std_logic;
        m_axis_crc_valid             : out std_logic;
        m_axis_length_err            : out std_logic;
        --Native Flow Control TX Interface
        s_axis_tx_nfc_xoff          : in std_logic;
        m_axis_rx_nfc_xoff          : out std_logic;
        -- dumb bullshit only used in XOFF BUSY mode
        busy_reset                  : in std_logic;
        going_full                  : in std_logic;
        trig                        : out std_logic;
        --GT Serial I/O
        rxp                         : in  std_logic;
        rxn                         : in  std_logic;
        txp                         : out std_logic;
        txn                         : out std_logic;
        --GT Reference Clock Interface
        gt_refclk                   : in  std_logic;
        gt_bufclk                   : in  std_logic;
        --Error Detection Interface
        hard_err                    : out std_logic;
        soft_err                    : out std_logic;
        frame_err                   : out std_logic;
        --Status
        channel_up                  : out std_logic;
        lane_up                     : out std_logic;
        link_reset_out              : out std_logic;
        --System Interface
        init_clk                    : in  std_logic;
        user_clk                    : in  std_logic;
        ext_reset                   : in  std_logic;

        tx_out_clk                  : out std_logic;
        pll_not_locked              : in  std_logic;
        power_down                  : in  std_logic;
        loopback                    : in  std_logic_vector(2 downto 0);

        tx_resetdone                : out std_logic;
        rx_resetdone                : out std_logic;
        gt_reset_len                : in std_logic_vector(15 downto 0);
        reset_busy                  : out std_logic;
        drpclk                      : in  std_logic;
        drpaddr                     : in  std_logic_vector(8 downto 0);
        drpdi                       : in  std_logic_vector(15 downto 0);
        drpdo                       : out std_logic_vector(15 downto 0);
        drpen                       : in  std_logic;
        drprdy                      : out std_logic;
        drpwe                       : in  std_logic;
        ------------------
        gt_powergood                : out  std_logic;
        bufg_gt_clr                 : out  std_logic;
        tx_lock                     : out  std_logic);
    end component;

    component flag_sync
      generic (
          CLKEDGEA : string := "POSEDGE";
          CLKEDGEB : string := "POSEDGE"
      );
      port (
          clkA : in std_logic;
          clkB : in std_logic;
          in_clkA : in std_logic;
          out_clkB : out std_logic;
          busy_clkA : out std_logic
      );
    end component;

    COMPONENT dnpcie_frame_holdoff_v2
        PORT (
            aclk : in std_logic;
            aresetn : in std_logic;
            s_axis_tdata : in std_logic_vector(31 downto 0);
            s_axis_tvalid : in std_logic;
            s_axis_tuser : in std_logic_vector(2 downto 0);
            s_axis_tlast : in std_logic;
            m_axis_tdata : out std_logic_vector(31 downto 0);
            m_axis_tvalid : out std_logic;
            m_axis_tuser : out std_logic_vector(2 downto 0);
            m_axis_tlast : out std_logic;
            s_axis_xoff : in std_logic;
            m_axis_dropped : out std_logic
        );
    END COMPONENT;
    
    signal reset_busy_initclk : std_logic;
    signal reset_busy_statusclk_sync : std_logic := '0';
    signal reset_busy_statusclk : std_logic := '0';
    
    signal link_reset_out_reg : std_logic := '0';
    signal link_reset_out_rereg : std_logic := '0';
    signal link_reset_out : std_logic;
    signal link_reset_out_flag_initclk : std_logic;
    signal link_reset_out_flag_statusclk : std_logic;
    signal link_reset_out_statusclk : std_logic := '0';    
    signal core_tready : std_logic;
    
    signal rx_tkeep : std_logic_vector(3 downto 0);
    signal rx_length_err : std_logic;
    signal gt_crc_pass_fail_n : std_logic;
    signal gt_crc_valid : std_logic;
    -- rx path, so 32-bits
    signal preholdoff_rx_tdata : std_logic_vector(31 downto 0);
    signal preholdoff_rx_tvalid : std_logic;
    signal preholdoff_rx_tlast : std_logic;
    signal preholdoff_rx_tuser : std_logic_vector(2 downto 0);
    
    signal err_aclk : std_logic_vector(3 downto 0);
    signal err_aclk_reg : std_logic_vector(3 downto 0) := "0000";
    signal err_aclk_last : std_logic_vector(3 downto 0) := "0000";
    signal err_aclk_changed : std_logic := '0';
    signal err_statclk_changed : std_logic;
    signal ctrl_aclk : std_logic_vector(3 downto 0) := "0000";
    signal up_aclk : std_logic_vector(1 downto 0);
    signal tx_lock_aclk : std_logic;
    signal resetdone_aclk : std_logic_vector(1 downto 0);
    signal gt_powergood_async : std_logic;
        
    signal err_statclk : std_logic_vector(3 downto 0) := "0000";    
    signal status_statclk : std_logic_vector(9 downto 0) := "0000000000";
    signal status_statclk_sync : std_logic_vector(9 downto 0) := "0000000000";
    signal ctrl_statclk_last : std_logic_vector(5 downto 0) := "000000";
    signal ctrl_statclk_changed : std_logic := '0';
    signal ctrl_aclk_changed : std_logic;
    signal ext_reset_flag : std_logic;
    signal ext_reset_flag_initclk : std_logic;
    signal reset_clear_aclk : std_logic := '0';

    signal frame_err : std_logic;

    -- here we embed:
    -- the frame holdoff (which can be completely disabled in a control register)
    -- the CRC inline embedding
    begin
        status <= reset_busy_statusclk & link_reset_out_statusclk & status_statclk;
        err <= err_statclk;
        
        STATCLK_PROCESS : process(status_clk)
        begin
            if rising_edge(status_clk) then
                if control(4) = '1' then
                    link_reset_out_statusclk <= '0';
                elsif link_reset_out_flag_statusclk = '1' then
                    link_reset_out_statusclk <= '1';
                end if;
                
                ctrl_statclk_last <= control;
                if ctrl_statclk_last /= control then
                    ctrl_statclk_changed <= '1';
                else
                    ctrl_statclk_changed <= '0';
                end if;
                
                if err_statclk_changed = '1' then
                    err_statclk <= err_aclk_reg;
                end if;
                
                status_statclk <= status_statclk_sync;
                status_statclk_sync(3 downto 0) <= ctrl_aclk(3 downto 0);
                status_statclk_sync(5 downto 4) <= resetdone_aclk;
                status_statclk_sync(7 downto 6) <= up_aclk;
                status_statclk_sync(8) <= tx_lock_aclk;
                status_statclk_sync(9) <= gt_powergood_async;                
                
                reset_busy_statusclk_sync <= reset_busy_initclk;
                reset_busy_statusclk <= reset_busy_statusclk_sync;
            end if;
        end process;
    
        ext_reset_flag <= control(5) and not ctrl_statclk_last(5); 
        link_reset_out_flag_initclk <= link_reset_out_reg and not link_reset_out_rereg;
        
        u_ext_reset_sync : flag_sync
        port map(
            clkA => status_clk,
            clkB => init_clk, 
            in_clkA => ext_reset_flag,
            out_clkB => ext_reset_flag_initclk
        );
    
        u_ctrl_changed_sync : flag_sync
        port map(
            clkA => status_clk,
            clkB => aclk,
            in_clkA => ctrl_statclk_changed,
            out_clkB => ctrl_aclk_changed
        );        
        u_err_changed_sync : flag_sync
        port map(
            clkA => aclk,
            clkB => status_clk,
            in_clkA => err_aclk_changed,
            out_clkB => err_statclk_changed
        );
        u_lro_flag_sync : flag_sync
        port map(
            clkA => init_clk,
            clkB => status_clk,
            in_clkA =>  link_reset_out_flag_initclk,
            out_clkB => link_reset_out_flag_statusclk
        );
        INITCLK_PROCESS : process(init_clk)
        begin
            if rising_edge(init_clk) then
                link_reset_out_reg <= link_reset_out;
                link_reset_out_rereg <= link_reset_out_reg;
            end if;
        end process;
        
        ACLK_PROCESS : process(aclk)
        begin
            if rising_edge(aclk) then
                if ctrl_aclk_changed = '1' then
                    reset_clear_aclk <= control(4);
                else
                    reset_clear_aclk <= '0';
                end if;
                if ctrl_aclk_changed = '1' then
                    ctrl_aclk <= control(3 downto 0);
                end if;
                if reset_clear_aclk = '1' then
                    err_aclk_reg <= "0000";
                else
                    if err_aclk(0) = '1' then
                        err_aclk_reg(0) <= '1';
                    end if;
                    if err_aclk(1) = '1' then
                        err_aclk_reg(1) <= '1';
                    end if;
                    if err_aclk(2) = '1' then
                        err_aclk_reg(2) <= '1';
                    end if;
                    if err_aclk(3) = '1' then
                        err_aclk_reg(3) <= '1';
                    end if;
                end if;
                err_aclk_last <= err_aclk_reg;
                if err_aclk_last /= err_aclk_reg then
                    err_aclk_changed <= '1';
                else
                    err_aclk_changed <= '0';
                end if;
            end if;
        end process;
                        
        preholdoff_rx_tuser(2) <= '0' when (x"F"=rx_tkeep and '0'=rx_length_err) else '1';
        preholdoff_rx_tuser(1) <= not gt_crc_pass_fail_n and gt_crc_valid;
        err_aclk(3) <= preholdoff_rx_tuser(1);
        -- err_aclk is a sticky value, we can't set it unless it's qualified
        err_aclk(2) <= frame_err or (preholdoff_rx_tuser(2) and preholdoff_rx_tvalid);
        -- ultrasleaze the tready: if the lane goes down, THERE GOES YOUR DATA
        s_axis_tx_tready <= core_tready or not up_aclk(1);
        s_axis_tx_will_discard <= not up_aclk(1);
    u_dnpcie_aurora_core : dnpcie_aurora_core
    generic map(
        CC_FREQ_FACTOR                      => 12,
        EXAMPLE_SIMULATION                  => EXAMPLE_SIMULATION,
        LANE                                => LANE,
        XOFF_BUSY                           => XOFF_BUSY,
        DEBUG_MASK                          => B"0000_0000")
    port map(    
        m_axis_raw_tdata                    => m_axis_raw_tdata,
        m_axis_raw_tkeep                    => m_axis_raw_tkeep,
        m_axis_raw_tvalid                   => m_axis_raw_tvalid,
        m_axis_raw_tlast                    => m_axis_raw_tlast,
        s_axis_tx_tdata                     => s_axis_tx_tdata,
        s_axis_tx_tkeep                     => "11",
        s_axis_tx_tvalid                    => s_axis_tx_tvalid,
        s_axis_tx_tlast                     => s_axis_tx_tlast,
        -- ultrasleaze the tready in cases 
        s_axis_tx_tready                    => core_tready,
        -- this is named weird: it pertains to the TX path, but it's receiving the XOFF
        m_axis_rx_nfc_xoff                  => axis_tx_xoff,
        --
        busy_reset                          => busy_reset,
        going_full                          => going_full,
        trig                                => trig,
        --        
        m_axis_rx_tdata                     => preholdoff_rx_tdata,
        m_axis_rx_tkeep                     => rx_tkeep,
        m_axis_rx_tvalid                    => preholdoff_rx_tvalid,
        m_axis_rx_tuser                     => preholdoff_rx_tuser(0),
        m_axis_rx_tlast                     => preholdoff_rx_tlast,
        m_axis_crc_pass_fail_n              => gt_crc_pass_fail_n,
        m_axis_crc_valid                    => gt_crc_valid,
        m_axis_length_err                   => rx_length_err,
        -- this is named weird: it pertains to the RX path, but it's transmitting the XOFF
        s_axis_tx_nfc_xoff                  => axis_rx_xoff,
        -- hard_err/soft_err/frame_err are synchronous to aclk (user_clk)
        hard_err                            => err_aclk(0),
        soft_err                            => err_aclk(1),
        frame_err                           => frame_err,
        -- channel up/lane up are synchronous to aclk (user_clk)
        channel_up                          => up_aclk(0),
        lane_up                             => up_aclk(1),
        link_reset_out                      => link_reset_out,
        -- tx_lock is aclk
        tx_lock                             => tx_lock_aclk,
        -- gt_powergood is asynchronous
        gt_powergood                        => gt_powergood_async,
        -- loopback is aclk
        loopback                            => ctrl_aclk(2 downto 0),
        -- power down is aclk
        power_down                          => ctrl_aclk(3),
        -- resetdones are aclk
        tx_resetdone                        => resetdone_aclk(0),
        rx_resetdone                        => resetdone_aclk(1),
        -- do something with these
        -- pll_not_locked
        -- bufg_gt_clr
        pll_not_locked                      => '0',
        bufg_gt_clr                         => open,
        gt_reset_len                        => gt_reset_len,
        reset_busy                          => reset_busy_initclk,
        drpclk                              => init_clk,
        drpaddr                             => (others => '0'),
        drpdi                               => (others => '0'),
        drpdo                               => open,
        drpen                               => '0',
        drprdy                              => open,
        drpwe                               => '0',
        --
        gt_refclk                           => gt_refclk,
        gt_bufclk                           => gt_bufclk,
        user_clk                            => aclk,
        init_clk                            => init_clk,
        tx_out_clk                          => tx_out_clk,
        -- ext_reset is synchronous to init_clk
        ext_reset                           => ext_reset_flag_initclk,
        rxp                                 => rxp,
        rxn                                 => rxn,
        txp                                 => txp,
        txn                                 => txn );
        
        u_dnpcie_frame_holdoff : dnpcie_frame_holdoff_v2
        port map(
            aclk                    => aclk,
            aresetn                 => up_aclk(1),
            s_axis_tdata            => preholdoff_rx_tdata,
            s_axis_tuser            => preholdoff_rx_tuser,
            s_axis_tlast            => preholdoff_rx_tlast,
            s_axis_tvalid           => preholdoff_rx_tvalid,
            s_axis_xoff             => axis_rx_drop,
            
            m_axis_tdata            => m_axis_rx_tdata,
            m_axis_tvalid           => m_axis_rx_tvalid,
            m_axis_tlast            => m_axis_rx_tlast,
            m_axis_tuser            => m_axis_rx_tuser,
            m_axis_dropped          => axis_rx_dropped);
        
end struct;