library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
library unisim;
    use unisim.vcomponents.all;

entity led_ctrl is
generic(
    SIM_SPDUP                       : boolean := FALSE);
port(
    clk                             : in std_logic;
    led_dis                         : in std_logic;
	sig_vec							: in std_logic_vector(0 to 7);
    led_ck                          : out std_logic;
    led_ds                          : out std_logic);
end led_ctrl;

architecture behavioral of led_ctrl is

    function CTR_WDTH(s : boolean) return positive is
        variable outp        : positive;
    begin
        if s then
            outp := 10;
        else
            outp := 25;
        end if;
        return outp;
    end function;
    
    constant LED_INIT               : integer                                   := 9;

    signal time_ctr                 : unsigned(CTR_WDTH(SIM_SPDUP)-1 downto 0) := (others => '0');
    signal update                   : std_logic;
    signal shift                    : std_logic;
    signal shift_bit_q0             : std_logic;
    signal shift_bit_q1             : std_logic;
    signal shft_reg					: std_logic_vector(0 to 7);
    signal led_ctr                  : integer range 0 to LED_INIT;
    signal led_ctr_tc               : std_logic;

begin


----------------------------------------------------------------
-- Component instantiations
----------------------------------------------------------------

    ------------------------------------------------------------------
    -- Pipeline outputs.
    ------------------------------------------------------------------
    led_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            if led_dis then
                time_ctr <= (others => '0');
                update <= '0';
                shift_bit_q0 <= '0';
                shift_bit_q1 <= '0';
                shift <= '0';
                shft_reg <= (others => '1');
                led_ctr  <= LED_INIT;
                led_ctr_tc <= '0';
                led_ck <= '0';
                led_ds <= '1';
            else
                shift_bit_q0 <= time_ctr(4);
                shift_bit_q1 <= shift_bit_q0;
                update <= time_ctr(time_ctr'left);--time_bit_q0  and (not time_bit_q1);
                shift  <= shift_bit_q0 and (not shift_bit_q1);
                time_ctr <= time_ctr + '1';
                if update then
                    shft_reg <= sig_vec;
                    led_ctr  <= LED_INIT;
                    led_ctr_tc <= '0';
                    led_ck  <= led_ck;
                else
                    if (not led_ctr_tc) then
                        led_ck  <= not shift_bit_q1;
                        if shift then
                            shft_reg <= '1' & shft_reg(0 to 6);
                            led_ctr <= led_ctr - 1;
                            led_ctr_tc <= '1' when led_ctr = 1 else '0';
                        else
                            shft_reg <= shft_reg;
                            led_ctr <= led_ctr;
                            led_ctr_tc <= led_ctr_tc;
                        end if;
                    end if;
                end if;
                led_ds <= shft_reg(7);
            end if;
        end if;
    end process;

end behavioral;
