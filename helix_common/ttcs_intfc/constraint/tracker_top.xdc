##===============================================##
## Clock Constraints
##===============================================##
create_clock -name OSC_CLK -period 5.000 [get_ports osc_clk_p]
create_clock -name DAQ_CLK -period 12.50 [get_ports ttcs_io_daq_clk_p]


##===============================================##
## I/O Constraints
##===============================================##
set_property PACKAGE_PIN AP25 [get_ports lreset]; set_property IOSTANDARD LVCMOS33 [get_ports lreset];

set_property PACKAGE_PIN G5 [get_ports osc_clk_p]; set_property IOSTANDARD LVDS_25 [get_ports osc_clk_p]; set_property DIFF_TERM TRUE [get_ports osc_clk_p];
set_property PACKAGE_PIN G4 [get_ports osc_clk_n]; set_property IOSTANDARD LVDS_25 [get_ports osc_clk_n];

set_property PACKAGE_PIN J29 [get_ports ttcs_io_daq_clk_p]; set_property IOSTANDARD LVDS_25 [get_ports ttcs_io_daq_clk_p]; set_property DIFF_TERM TRUE [get_ports ttcs_io_daq_clk_p];
set_property PACKAGE_PIN H29 [get_ports ttcs_io_daq_clk_n]; set_property IOSTANDARD LVDS_25 [get_ports ttcs_io_daq_clk_n];

set_property PACKAGE_PIN J33 [get_ports ttcs_io_fst_ctrl_p]; set_property IOSTANDARD LVDS_25 [get_ports ttcs_io_fst_ctrl_p]; set_property DIFF_TERM TRUE [get_ports ttcs_io_fst_ctrl_p];
set_property PACKAGE_PIN H34 [get_ports ttcs_io_fst_ctrl_n]; set_property IOSTANDARD LVDS_25 [get_ports ttcs_io_fst_ctrl_n];

set_property PACKAGE_PIN H32 [get_ports ttcs_io_sync_p]; set_property IOSTANDARD LVDS_25 [get_ports ttcs_io_sync_p]; set_property DIFF_TERM TRUE [get_ports ttcs_io_sync_p];
set_property PACKAGE_PIN G32 [get_ports ttcs_io_sync_n]; set_property IOSTANDARD LVDS_25 [get_ports ttcs_io_sync_n];

set_property PACKAGE_PIN L33 [get_ports ttcs_io_strg_p]; set_property IOSTANDARD LVDS_25 [get_ports ttcs_io_strg_p]; set_property DIFF_TERM TRUE [get_ports ttcs_io_sync_p];
set_property PACKAGE_PIN L34 [get_ports ttcs_io_strg_n]; set_property IOSTANDARD LVDS_25 [get_ports ttcs_io_strg_n];

set_property PACKAGE_PIN H33 [get_ports ttcs_io_fst_clk_p]; set_property IOSTANDARD LVDS_25 [get_ports ttcs_io_fst_clk_p]; set_property DIFF_TERM TRUE [get_ports ttcs_io_fst_clk_p];
set_property PACKAGE_PIN G34 [get_ports ttcs_io_fst_clk_n]; set_property IOSTANDARD LVDS_25 [get_ports ttcs_io_fst_clk_n];

set_property PACKAGE_PIN K33 [get_ports ttcs_io_fst_stat_p]; set_property IOSTANDARD LVDS_25 [get_ports ttcs_io_fst_stat_p]; set_property DIFF_TERM TRUE [get_ports ttcs_io_fst_stat_p];
set_property PACKAGE_PIN J34 [get_ports ttcs_io_fst_stat_n]; set_property IOSTANDARD LVDS_25 [get_ports ttcs_io_fst_stat_n];

set_property PACKAGE_PIN AP26 [get_ports dummy[1]]; set_property IOSTANDARD LVCMOS33 [get_ports dummy[1]];
set_property PACKAGE_PIN AL25 [get_ports dummy[2]]; set_property IOSTANDARD LVCMOS33 [get_ports dummy[2]];
set_property PACKAGE_PIN AM25 [get_ports dummy[3]]; set_property IOSTANDARD LVCMOS33 [get_ports dummy[3]];

##===============================================##
## In/Out Delay Constraints (Data Capture Window)
##===============================================##
#These are for center sampled DDR data (for now). We need to analyze the actual hardware to get the correct numbers.
#If the clock cycle changes, the delays must change (there is a way to use variables for auto update).
set_input_delay -clock DAQ_CLK -max 3.125 [get_ports ttcs_io_fst_ctrl_p]; #for rising edge setup 
set_input_delay -clock DAQ_CLK -min 3.125 [get_ports ttcs_io_fst_ctrl_p]; #for rising edge hold
set_input_delay -clock DAQ_CLK -max 3.125 [get_ports ttcs_io_fst_ctrl_p] -clock_fall -add_delay;  #for falling edge setup
set_input_delay -clock DAQ_CLK -min 3.125 [get_ports ttcs_io_fst_ctrl_p] -clock_fall -add_delay; #for falling edge hold

set_input_delay -clock DAQ_CLK -max 3.125 [get_ports ttcs_io_sync_p]; #for rising edge setup 
set_input_delay -clock DAQ_CLK -min 3.125 [get_ports ttcs_io_sync_p]; #for rising edge hold
set_input_delay -clock DAQ_CLK -max 3.125 [get_ports ttcs_io_sync_p] -clock_fall -add_delay;  #for falling edge setup
set_input_delay -clock DAQ_CLK -min 3.125 [get_ports ttcs_io_sync_p] -clock_fall -add_delay; #for falling edge hold

set_input_delay -clock DAQ_CLK -max 3.125 [get_ports ttcs_io_strg_p]; #for rising edge setup 
set_input_delay -clock DAQ_CLK -min 3.125 [get_ports ttcs_io_strg_p]; #for rising edge hold
set_input_delay -clock DAQ_CLK -max 3.125 [get_ports ttcs_io_strg_p] -clock_fall -add_delay;  #for falling edge setup
set_input_delay -clock DAQ_CLK -min 3.125 [get_ports ttcs_io_strg_p] -clock_fall -add_delay; #for falling edge hold
##
##
set_output_delay -clock DAQ_CLK -max -3.200 [get_ports ttcs_io_fst_clk_p]; #for rising edge setup
set_output_delay -clock DAQ_CLK -min 3.200 [get_ports ttcs_io_fst_clk_p]; #for rising edge hold
set_output_delay -clock DAQ_CLK -max -3.200 [get_ports ttcs_io_fst_clk_p] -clock_fall -add_delay;  #for falling edge setup
set_output_delay -clock DAQ_CLK -min 3.200 [get_ports ttcs_io_fst_clk_p] -clock_fall -add_delay; #for falling edge hold

set_output_delay -clock DAQ_CLK -max -3.200 [get_ports ttcs_io_fst_stat_p]; #for rising edge setup 
set_output_delay -clock DAQ_CLK -min 3.200 [get_ports ttcs_io_fst_stat_p]; #for rising edge hold
set_output_delay -clock DAQ_CLK -max -3.200 [get_ports ttcs_io_fst_stat_p] -clock_fall -add_delay;  #for falling edge setup
set_output_delay -clock DAQ_CLK -min 3.200 [get_ports ttcs_io_fst_stat_p] -clock_fall -add_delay; #for falling edge hold #0.099

##==========##
## P BLOCKS ##
##==========##
##Example block that must be added to your constraints file ######################
create_pblock ttcs_pblock
add_cells_to_pblock [get_pblocks ttcs_pblock] [get_cells -quiet [list ttcs_ins]]
resize_pblock [get_pblocks ttcs_pblock] -add {CLOCKREGION_X0Y4:CLOCKREGION_X0Y4}




