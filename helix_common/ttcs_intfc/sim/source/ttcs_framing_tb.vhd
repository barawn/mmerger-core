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
-- Test bench for TTCS framing entity.
--
-- Deficiencies:
--*********************************************************************************
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

entity ttcs_framing_tb is
end ttcs_framing_tb;

---------------------------------------------------------------------------------------------------------
-- Architecture declaration
---------------------------------------------------------------------------------------------------------
architecture behave of ttcs_framing_tb is

    constant CKPER                  : time              := 1 ns;
    constant DWDT                   : positive          := 16;
    constant SEED                   : positive          := 202;
    constant MGRTXLNK               : positive          := 4;
    constant MGRRXLNK               : positive          := 10;
    constant FEBTXLNK               : positive          := 1;
    constant FEBRXLNK               : positive          := 4;

    type feb_dout_type is array(1 to 10) of std_logic_vector(1 to FEBTXLNK);
    type feb_din_type  is array(1 to 10) of std_logic_vector(1 to FEBRXLNK);

    signal clk                      : std_logic         := '0';
    signal reset                    : std_logic;

    signal mgr_dout                 : std_logic_vector(1 to MGRTXLNK);
    signal mgr_din                  : std_logic_vector(1 to MGRRXLNK);    

    signal feb_dout                 : feb_dout_type;
    signal feb_din                  : feb_din_type;

    --alias feb_inject_err is <<signal feb_ins.inject_err : std_logic_vector(1 to FEBTXLNK)>>;
    alias mgr_inject_err is <<signal mgr_ins.inject_err        : std_logic_vector(1 to MGRTXLNK)>>;

begin
------------------------------------------------------------------------------------------------
-- Component instantiations
------------------------------------------------------------------------------------------------

    mgr_ins : entity work.ttcs_framing_mgr
    generic map(
        TXLNK                           => MGRTXLNK,
        RXLNK                           => MGRRXLNK,
        DWDT                            => DWDT,
        SEED                            => SEED)
    port map(
        clk                             => clk,
        reset                           => reset,
        dout                            => mgr_dout,
        din                             => mgr_din
    );

    feb_gen : for I in 1 to 10 generate
        feb_ins : entity work.ttcs_framing_feb
        generic map(
            TXLNK                       => FEBTXLNK,
            RXLNK                       => FEBRXLNK,
            DWDT                        => DWDT,
            SEED                        => SEED)
        port map(
            clk                         => clk,
            reset                       => reset,
            dout                        => feb_dout(I),
            din                         => feb_din(I)
        );
    end generate;

------------------------------------------------------------------------------------------------
-- Concurrent statements
------------------------------------------------------------------------------------------------

    clk <= (not clk) after CKPER/2;
    reset <= '1', '0' after CKPER*10;

    mgr_inject_err <= 4UX"0", 4UX"1" after CKPER*5000, 4UX"0" after CKPER*5001;
    --feb_inject_err <= (others => '0'), (others => '1') after CKPER*5000, (others => '0') after CKPER*5001;

    data_gen : for I in 1 to 10 generate
        mgr_din(I) <= feb_dout(I)(feb_dout(I)'left);
        feb_din(I) <= mgr_dout;
    end generate;

------------------------------------------------------------------------------------------------
-- Asynchronous and Synchronous processes.
------------------------------------------------------------------------------------------------

end behave;
