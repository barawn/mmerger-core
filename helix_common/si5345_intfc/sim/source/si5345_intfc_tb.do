#Execute this script after changing to this directory.
#/HELIX/firmware/common/si5345_intfc/sim/

vlib si5345_intfc_lib "./library/si5345_intfc_lib"

#Compile our sources
vcom -2008 -work si5345_intfc_lib ../../../common/timing/source/clk_enbl_gen.vhd
vcom -2008 -work si5345_intfc_lib ../source/si5345_cfg_ram.vhd
vcom -2008 -work si5345_intfc_lib ../source/si5345_intfc.vhd
vcom -2008 -work si5345_intfc_lib ./source/si5345.vhd
vcom -2008 -work si5345_intfc_lib ./source/si5345_intfc_tb.vhd

vsim -lib si5345_intfc_lib si5345_intfc_tb +access +r

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

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Device Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave device/*

#-------------------------------------------
transcript on

run 25 ms;