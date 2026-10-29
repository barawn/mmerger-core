#Execute this script after changing to this directory.
#/HELIX/firmware/common/clk_enbl_gen/sim/

vlib clk_enbl_lib "./library/clk_enbl_lib"

#Compile our sources
vcom -2008 -work clk_enbl_lib ../source/clk_enbl_gen.vhd
vcom -2008 -work clk_enbl_lib ./source/clk_enbl_gen_tb.vhd

vsim -lib clk_enbl_lib clk_enbl_tb +access +r

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