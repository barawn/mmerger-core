------------------------------------------------------------------------------/
-- (c) Copyright 2013 Xilinx, Inc. All rights reserved.
--
-- This file contains confidential and proprietary information
-- of Xilinx, Inc. and is protected under U.S. and
-- international copyright and other intellectual property
-- laws.
--
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- Xilinx, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) Xilinx shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or Xilinx had been advised of the
-- possibility of the same.
--
-- CRITICAL APPLICATIONS
-- Xilinx products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of Xilinx products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
--
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
--
--
--------------------------------------------------------------------------------
library IEEE;
  use IEEE.numeric_std.all;
  use ieee.std_logic_unsigned.all;
  use ieee.std_logic_misc.all;
  use ieee.std_logic_1164.all;

library UNISIM;
  use UNISIM.Vcomponents.ALL;

--***************************** Entity Declaration ****************************

entity aurora_8b10b_gt_common_wrapper is
generic
(
    -- Simulation attributes
    WRAPPER_SIM_GTRESET_SPEEDUP    : string   := "FALSE" -- Set to "TRUE" to speed up sim reset
);
port
(
    ---------------------------- Common Block - Ports --------------------------
    gt0_pll0refclksel_in        :  in    std_logic_vector(2 downto 0);
    gt0_pll1refclksel_in        :  in    std_logic_vector(2 downto 0);
    gt0_gtrefclk0_in            :  in    std_logic;
    gt0_gtrefclk1_in            :  in    std_logic;
    gt0_pll0lock_out            :  out   std_logic;
    gt0_pll1lock_out            :  out   std_logic;
    gt0_plllockdetclk_in        :  in    std_logic;
    gt0_pll0refclklost_out      :  out   std_logic;
    gt0_pll1refclklost_out      :  out   std_logic;
    gt0_pll0outclk              :  out   std_logic;
    gt0_pll1outclk              :  out   std_logic;
    gt0_pll0outrefclk           :  out   std_logic;
    gt0_pll1outrefclk           :  out   std_logic;
    gt0_pll0reset_in            :  in    std_logic;
    gt0_pll1reset_in            :  in    std_logic


);
end aurora_8b10b_gt_common_wrapper;

architecture STRUCTURE of aurora_8b10b_gt_common_wrapper is

--***************************** Parameter Declarations ************************
    constant PLL0_FBDIV_IN      :   integer := 4;
    constant PLL1_FBDIV_IN      :   integer := 4;
    constant PLL0_FBDIV_45_IN   :   integer := 5;
    constant PLL1_FBDIV_45_IN   :   integer := 5;
    constant PLL0_REFCLK_DIV_IN :   integer := 1;
    constant PLL1_REFCLK_DIV_IN :   integer := 1;

--***************************** Wire Declarations *****************************
    signal  tied_to_ground_i                :   std_logic;
    signal  tied_to_ground_vec_i            :   std_logic_vector(63 downto 0);
    signal  tied_to_vcc_i                   :   std_logic;

    signal cpllpd0_quad0_wait      : std_logic_vector(95 downto 0)  := x"FFFFFFFFFFFFFFFFFFFFFFFF";
    signal cpllreset0_quad0_wait   : std_logic_vector(127 downto 0) := x"000000000000000000000000000000FF";
    signal cpllpd0_ovrd_quad0_i    : std_logic ;
    signal cpllreset0_ovrd_quad0_i : std_logic ;
    signal cpllreset0_quad0_i      : std_logic ;

    signal cpllpd1_quad0_wait      : std_logic_vector(95 downto 0)  := x"FFFFFFFFFFFFFFFFFFFFFFFF";
    signal cpllreset1_quad0_wait   : std_logic_vector(127 downto 0) := x"000000000000000000000000000000FF";
    signal cpllpd1_ovrd_quad0_i    : std_logic ;
    signal cpllreset1_ovrd_quad0_i : std_logic ;
    signal cpllreset1_quad0_i      : std_logic ;

    attribute equivalent_register_removal: string;
    attribute equivalent_register_removal of cpllpd0_quad0_wait : signal is "no";
    attribute equivalent_register_removal of cpllreset0_quad0_wait : signal is "no";

    attribute equivalent_register_removal of cpllpd1_quad0_wait : signal is "no";
    attribute equivalent_register_removal of cpllreset1_quad0_wait : signal is "no";

begin


--********************************* Main Body of Code**************************

    tied_to_ground_i                    <= '0';
    tied_to_ground_vec_i(63 downto 0)   <= (others => '0');
    tied_to_vcc_i                       <= '1';

    cpllreset0_quad0_i         <=  cpllreset0_ovrd_quad0_i or gt0_pll0reset_in;

    process( gt0_gtrefclk0_in )
    begin
        if(gt0_gtrefclk0_in'event and gt0_gtrefclk0_in = '1') then
           cpllpd0_quad0_wait <= cpllpd0_quad0_wait(94 downto 0) & '0';
           cpllreset0_quad0_wait <= cpllreset0_quad0_wait(126 downto 0) & '0';
         end if;
    end process;

    cpllpd0_ovrd_quad0_i <= cpllpd0_quad0_wait(95);
    cpllreset0_ovrd_quad0_i <= cpllreset0_quad0_wait(127);

    cpllreset1_quad0_i         <=  cpllreset1_ovrd_quad0_i or gt0_pll1reset_in;

    process( gt0_gtrefclk1_in )
    begin
        if(gt0_gtrefclk1_in'event and gt0_gtrefclk1_in = '1') then
           cpllpd1_quad0_wait <= cpllpd1_quad0_wait(94 downto 0) & '0';
           cpllreset1_quad0_wait <= cpllreset1_quad0_wait(126 downto 0) & '0';
         end if;
    end process;

    cpllpd1_ovrd_quad0_i <= cpllpd1_quad0_wait(95);
    cpllreset1_ovrd_quad0_i <= cpllreset1_quad0_wait(127);
    --_________________________________________________________________________
    --_________________________________________________________________________
    --_________________________GTPE2_COMMON____________________________________

    gtpe2_common_0_i : GTPE2_COMMON
    generic map
        (
        -- Simulation attributes
        SIM_RESET_SPEEDUP               => WRAPPER_SIM_GTRESET_SPEEDUP,
        SIM_PLL0REFCLK_SEL              => ("001"),
        SIM_PLL1REFCLK_SEL              => ("001"),
        SIM_VERSION                     => ("2.0"),

        PLL0_FBDIV                      => PLL0_FBDIV_IN     ,
        PLL0_FBDIV_45                   => PLL0_FBDIV_45_IN  ,
        PLL0_REFCLK_DIV                 => PLL0_REFCLK_DIV_IN,
        PLL1_FBDIV                      => PLL1_FBDIV_IN     ,
        PLL1_FBDIV_45                   => PLL1_FBDIV_45_IN  ,
        PLL1_REFCLK_DIV                 => PLL1_REFCLK_DIV_IN,
        ------------------COMMON BLOCK Attributes---------------
        BIAS_CFG                        =>     (x"0000000000050001"),
        COMMON_CFG                      =>     (x"00000000"),
        ----------------------------PLL Attributes----------------------------
        PLL0_CFG                        =>     (x"01F03DC"),
        PLL0_DMON_CFG                   =>     ('0'),
        PLL0_INIT_CFG                   =>     (x"00001E"),
        PLL0_LOCK_CFG                   =>     (x"1E8"),
        PLL1_CFG                        =>     (x"01F03DC"),
        PLL1_DMON_CFG                   =>     ('0'),
        PLL1_INIT_CFG                   =>     (x"00001E"),
        PLL1_LOCK_CFG                   =>     (x"1E8"),
        PLL_CLKOUT_CFG                  =>     (x"00"),
        ----------------------------Reserved Attributes----------------------------
        RSVD_ATTR0                      =>     (x"0000"),
        RSVD_ATTR1                      =>     (x"0000"))
        port map
        (
        DMONITOROUT                     => open,
        ------------- Common Block  - Dynamic Reconfiguration Port (DRP) -----------
        DRPADDR                         =>      tied_to_ground_vec_i(7 downto 0),
        DRPCLK                          =>      tied_to_ground_i,
        DRPDI                           =>      tied_to_ground_vec_i(15 downto 0),
        DRPDO                           =>      open,
        DRPEN                           =>      tied_to_ground_i,
        DRPRDY                          =>      open,
        DRPWE                           =>      tied_to_ground_i,
        ---------------------------- Common Block - Ports --------------------------
        BGRCALOVRDENB                   =>      tied_to_vcc_i,
        GTEASTREFCLK0                   =>      tied_to_ground_i,
        GTEASTREFCLK1                   =>      tied_to_ground_i,
        GTGREFCLK0                      =>      tied_to_ground_i,
        GTGREFCLK1                      =>      tied_to_ground_i,
        GTREFCLK0                       =>      gt0_gtrefclk0_in,
        GTREFCLK1                       =>      gt0_gtrefclk1_in,
        GTWESTREFCLK0                   =>      tied_to_ground_i,
        GTWESTREFCLK1                   =>      tied_to_ground_i,
        PLL0FBCLKLOST                   =>      open,
        PLL0LOCK                        =>      gt0_pll0lock_out,
        PLL0LOCKDETCLK                  =>      gt0_plllockdetclk_in,
        PLL0LOCKEN                      =>      tied_to_vcc_i,
        PLL0OUTCLK                      =>      gt0_pll0outclk,
        PLL0OUTREFCLK                   =>      gt0_pll0outrefclk,
        PLL0PD                          =>      cpllpd0_ovrd_quad0_i,
        PLL0REFCLKLOST                  =>      gt0_pll0refclklost_out,
        PLL0REFCLKSEL                   =>      gt0_pll0refclksel_in,--"001",
        PLL0RESET                       =>      cpllreset0_quad0_i,
        PLL1FBCLKLOST                   =>      open,
        PLL1LOCK                        =>      gt0_pll1lock_out,
        PLL1LOCKDETCLK                  =>      gt0_plllockdetclk_in,
        PLL1LOCKEN                      =>      tied_to_vcc_i,
        PLL1OUTCLK                      =>      gt0_pll1outclk,
        PLL1OUTREFCLK                   =>      gt0_pll1outrefclk,
        PLL1PD                          =>      cpllpd1_ovrd_quad0_i,
        PLL1REFCLKLOST                  =>      gt0_pll1refclklost_out,
        PLL1REFCLKSEL                   =>      gt0_pll1refclksel_in,--"001",
        PLL1RESET                       =>      cpllreset1_quad0_i,
        PLLRSVD1                        =>      "0000000000000000",
        PLLRSVD2                        =>      "00000",
        PMARSVDOUT                      =>      open,
        REFCLKOUTMONITOR0               =>      open,
        REFCLKOUTMONITOR1               =>      open,
        ----------------------------- Common Block Ports ---------------------------
        BGBYPASSB                       =>      tied_to_vcc_i,
        BGMONITORENB                    =>      tied_to_vcc_i,
        BGPDB                           =>      tied_to_vcc_i,
        BGRCALOVRD                      =>      "11111",
        PMARSVD                         =>      "00000000",
        RCALENB                         =>      tied_to_vcc_i
    );

end STRUCTURE;

