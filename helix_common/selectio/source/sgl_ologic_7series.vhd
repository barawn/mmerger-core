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
-- Configurable width SelectIO (OLOGIC) output bus for Xilinx 7-Series FPGAs.
--
--*********************************************************************************

library ieee;
    use ieee.std_logic_1164.all;
library unisim;
    use unisim.vcomponents.all;

entity sgl_ologic_7series is
generic(
    DWDT                            : integer range 1 to 40 := 10);
port (
    lreset                          : in std_logic;
    fbrc_clk                        : in std_logic;
    -- output to I/O
    io_data                         : out std_logic_vector(DWDT/2-1 downto 0);
    -- input from fabric
    fbrc_data                       : in std_logic_vector(DWDT-1 downto 0));
end sgl_ologic_7series;

architecture struct_7series of sgl_ologic_7series is    

    signal oddr_q                  : std_logic_vector(DWDT/2-1 downto 0);

begin     

    ------------------------------------------------------
    -- Data OLOGIC
    ------------------------------------------------------    
    ologic_gen :
    for I in 0 to DWDT/2-1 generate
        --------------------------------------------------
        -- Input delay primitives
        --------------------------------------------------    
        data_oddr : ODDR
        generic map(
            DDR_CLK_EDGE        => "SAME_EDGE",     -- "OPPOSITE_EDGE" or "SAME_EDGE" 
            INIT                => '0',             -- Initial value for Q port ('1' or '0')
            SRTYPE              => "SYNC")          -- Reset Type ("ASYNC" or "SYNC")
        port map(                              
            Q                   => oddr_q(I),    -- 1-bit DDR output
            C                   => fbrc_clk,        -- 1-bit clock input
            CE                  => '1',             -- 1-bit clock enable input
            D1                  => fbrc_data(I*2),  -- 1-bit data input (positive edge)
            D2                  => fbrc_data(I*2+1),-- 1-bit data input (negative edge)
            R                   => '0',             -- 1-bit reset input
            S                   => '0'              -- 1-bit set input
        );
        
        --------------------------------------------------
        -- Differential output buffers
        --------------------------------------------------        
        tx_ctrl_ibuf_ins : OBUF
        generic map (
            IOSTANDARD            => "DEFAULT",
            SLEW                  => "SLOW")
        port map(
            O                     => io_data(I),
            I                     => oddr_q(I)
        );               
        
    end generate;
    
end struct_7series;
