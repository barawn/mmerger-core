#Execute this script after changing to this directory.
#/HELIX/firmware/common/uut_ctrl/sim/

vlib led_ctrl_lib "./library/led_ctrl_lib"

#Compile our sources
vcom -2008 -work led_ctrl_lib ../source/led_ctrl.vhd
vcom -2008 -work led_ctrl_lib ./source/led_ctrl_tb.vhd

vsim -lib led_ctrl_lib led_ctrl_tb +access +r

transcript off
#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Testbench Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave *

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "UUT Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave uut/*

#-------------------------------------------
transcript on

run 100 us;