#Execute this script after changing to this directory.
#/HELIX/firmware/common/adc_smpl/sim/

vlib adc_smpl_lib "./library/adc_smpl_lib"

#Compile our sources
vcom -2008 -work adc_smpl_lib ../source/adc_smpl.vhd
vcom -2008 -work adc_smpl_lib ./source/adc_smpl_tb.vhd

vsim -lib adc_smpl_lib adc_smpl_tb +access +r

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

run 50 us;