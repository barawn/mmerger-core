--*********************************************************************************
-- Indiana University
-- Center for Exploration of Energy and Matter (CEEM)
--
-- Project: HELIX
--
-- Author:  Brandon Kunkler
--
-- Date:    11/09/2018
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
-- Package for common items related to trigger/status/control.
--
--*********************************************************************************
library ieee;
    use ieee.std_logic_1164.all;

package ttcs_intfc_pkg is
    -- common little endian vectors
    type ttcs_2ble_type  is array (natural range <>) of std_logic_vector(1  downto 0);
    type ttcs_3ble_type  is array (natural range <>) of std_logic_vector(2  downto 0);
    type ttcs_4ble_type  is array (natural range <>) of std_logic_vector(3  downto 0);
    type ttcs_8ble_type  is array (natural range <>) of std_logic_vector(7  downto 0);
    type ttcs_16ble_type is array (natural range <>) of std_logic_vector(15 downto 0);    
    -- common big endian vectors
    type ttcs_2bbe_type  is array (natural range <>) of std_logic_vector(0 to 1);
    type ttcs_3bbe_type  is array (natural range <>) of std_logic_vector(0 to 2);
    type ttcs_4bbe_type  is array (natural range <>) of std_logic_vector(0 to 3);
    type ttcs_8bbe_type  is array (natural range <>) of std_logic_vector(0 to 7);
    type ttcs_16bbe_type is array (natural range <>) of std_logic_vector(0 to 15);
    type ttcs_32bbe_type is array (natural range <>) of std_logic_vector(0 to 31);


end;

package body ttcs_intfc_pkg is


end;