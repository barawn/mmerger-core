------------------------------------------------------------------------------
-- (c) Copyright 2010 Xilinx, Inc. All rights reserved.
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
------------------------------------------------------------------------------
--
--  AXI_TO_LL
--
--
--  Description: This light wrapper/shim convertes Legacy LocalLink interface
--               signals from AXI-4 Stream protocol signals
--
--
------------------------------------------------------------------------------/
library IEEE;
use IEEE.numeric_std.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_misc.all;
use ieee.std_logic_1164.all;

entity helix_ll_to_axi is
generic
(
    DATA_WIDTH  : integer :=   16;      -- DATA bus width
    STRB_WIDTH  : integer :=   2;       -- STROBE bus width
    USE_UFC_REM : integer :=   0;       -- UFC REM bus width identifier
    REM_WIDTH   : integer :=   1        -- REM bus width
);  

port
(

  ----------------------  AXI4-S Interface -------------------------------
  AXI4_S_OP_TDATA                 : out   std_logic_vector(0 to DATA_WIDTH-1);
  AXI4_S_OP_TKEEP                 : out   std_logic_vector(0 to STRB_WIDTH-1);
  AXI4_S_OP_TVALID                : out   std_logic;
  AXI4_S_OP_TLAST                 : out   std_logic;
  AXI4_S_IP_TREADY                : in    std_logic;

  ----------------------  LocalLink Interface ----------------------------
  LL_IP_DATA                      : in    std_logic_vector(0 to DATA_WIDTH-1);
  LL_IP_REM                       : in    std_logic_vector(0 to REM_WIDTH-1);
  LL_IP_SRC_RDY_N                 : in    std_logic;
  LL_IP_SOF_N                     : in    std_logic;
  LL_IP_EOF_N                     : in    std_logic;
  LL_OP_DST_RDY_N                 : out   std_logic

);

end helix_ll_to_axi;

architecture BEHAVIORAL of helix_ll_to_axi is


--***********************************Parameter Declarations***************************

    constant DLY                  : time      := 1 ns;
    signal   AXI4_S_OP_TKEEP_i    : std_logic_vector(0 to STRB_WIDTH-1);

begin

--*********************************Main Body of Code**********************************
 
    AXI4_S_OP_TDATA      <= LL_IP_DATA;
 
    

    -- This should be compliant with the local link spec
    --gen_32bit : if DATA_WIDTH = 32 generate -- modified by BMK, not sure it's correct
    --    AXI4_S_OP_TKEEP_i   <= X"F" when (LL_IP_REM = "11") else
    --                           X"E" when (LL_IP_REM = "10") else
    --                           X"C" when (LL_IP_REM = "01") else
    --                           X"8";
    --end generate;

    -- Violate the local spec so TKEEP can manipulated
    gen_32bit : if DATA_WIDTH = 32 generate -- modified by BMK, not sure it's correct
        AXI4_S_OP_TKEEP <= AXI4_S_OP_TKEEP_i;
        AXI4_S_OP_TKEEP_i   <= X"F" when (LL_IP_REM = "11") else
                               X"C" when (LL_IP_REM = "10") else
                               X"3" when (LL_IP_REM = "01") else
                               X"F";
    end generate;

    -- This should be compliant with the local link spec
    gen_16bit : if DATA_WIDTH = 16 generate -- modified by BMK, not sure it's correct
        AXI4_S_OP_TKEEP <= AXI4_S_OP_TKEEP_i  when (LL_IP_EOF_N = '0') else (others => '1');
        AXI4_S_OP_TKEEP_i   <= "11" when (LL_IP_REM(0) = '1') else "10";
    end generate;

    AXI4_S_OP_TVALID    <= not LL_IP_SRC_RDY_N;
    AXI4_S_OP_TLAST     <= not LL_IP_EOF_N;
    LL_OP_DST_RDY_N     <= not AXI4_S_IP_TREADY;

end BEHAVIORAL;
