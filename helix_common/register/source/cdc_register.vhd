--*********************************************************************************
-- Indiana University
-- Center for Exploration of Energy and Matter (CEEM)
--
-- Project: ATLAS
--
-- Author:  Brandon Kunkler
--
-- Date:    08/19/2016
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
-- Cross clock domains.
--
-- Deficiencies:
--*********************************************************************************
library ieee;
    use ieee.std_logic_1164.all;

entity cdc_register is
generic(
    LEN                     : integer   := 3;
    INIT                    : std_logic := '1');
port(       
    clk                     : in  std_logic;    
    sig_in                  : in  std_logic;
    sig_out                 : out std_logic);
end cdc_register;


architecture behave of cdc_register is

  signal sync_regs          : std_logic_vector(LEN-1 downto 0) := (others => INIT);

  attribute ASYNC_REG                       : string;
  attribute ASYNC_REG of sync_regs          : signal is "TRUE";

  attribute SHREG_EXTRACT                   : string;
  attribute SHREG_EXTRACT of sync_regs      : signal is "NO";
  
begin

    sig_out <= sync_regs(0);
    
    sync_pcs : process(clk)
    begin
        if clk'event and clk='1' then
            sync_regs <= sig_in & sync_regs(sync_regs'left downto 1);
        end if;
    end process;

end behave;


