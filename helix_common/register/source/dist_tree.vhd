--*********************************************************************************
-- Indiana University Cyclotron Facility (IUCF)
--
-- Project: ATLAS
--
-- Author:  Brandon Kunkler
--
-- Date:    04/28/2016
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
-- Create a distribution tree from a single input. The NDIST value is the ratio.
-- For example, NDIST = 4 routes one Q output to four D inputs. The calcuations
-- generate the closed form solution to a power series, so some NOUT/NDIST ratios
-- don't work (a 10/2 ratio will output two FFs before the 2^3 tree output) and
-- some ratios will leave disconnected FFs (a 10/4 ratio wastes 4*4-10 FFs).
--*********************************************************************************
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.math_real.all;

entity dist_tree is
generic(
    INIT                        : std_logic := '1';
    NDIST                       : integer   := 2;  -- distribution factor = 1 to N
    NOUT                        : integer   := 10);-- distribution factor squared
port(
    clk                         : in std_logic;
    sig                         : in std_logic;
    dist                        : out std_logic_vector(1 to NOUT));
end dist_tree;


architecture behave of dist_tree is

    -- calcualate the order of the power series
    constant LOUT               : real    := LOG2(REAL(NOUT));
    constant LDIST              : real    := LOG2(REAL(NDIST));
    constant LRATIO             : real    := LOUT/LDIST;--each line separate for simulator
    constant PWR                : integer := INTEGER(LRATIO);
    -- calculate the number of nodes in the tree
    constant NNODE              : integer := (1-NDIST**PWR)/(1-NDIST);
    -- calculate the number of flip-flops in the tree
    constant NFF                : integer := NNODE*NDIST;

    --------------------------------------------------------------------------
    -- Signal declarations.
    --------------------------------------------------------------------------
    signal tree                 : std_logic_vector(0 to NFF)    := (others => INIT);--add one for the fore the input

    attribute dont_touch         : string;
    attribute dont_touch of tree : signal is "TRUE";

begin

------------------------------------------------------------------------------------------------
-- Component instantiations
------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------------------------
-- Concurrent statements
------------------------------------------------------------------------------------------------
    --------------------------------------------------------
    -- Map signals out of the port
    --------------------------------------------------------
    dist <= tree(NFF-NOUT+1 to NFF);

    --------------------------------------------------------
    -- Combinational logic
    --------------------------------------------------------

    --------------------------------------------------------
    -- Processes
    --------------------------------------------------------
    ------------------------------------------------------------------
    -- Input registers.
    ------------------------------------------------------------------
    tree_pcs : process(clk)
    begin
        if (clk'event and clk='1') then
            tree(0) <= sig;-- map input
            for I in 1 to NNODE loop-- loop through nodes
                for J in 1 to NDIST loop-- map inputs of vectors of NDIST size
                    tree((NDIST*(I-1))+J) <= tree(I-1);
                end loop;
            end loop;
        end if;
    end process;

end behave;