#Execute this script after changing to this directory.
#/HELIX/firmware/common/selectio/sim/

vlib sgl_ilogic_lib "./library/sgl_ilogic_lib"

#Compile our sources
vcom -2008 -work sgl_ilogic_lib ../source/sgl_clogic_7series.vhd
vcom -2008 -work sgl_ilogic_lib ../source/sgl_ilogic_7series.vhd

vcom -2008 -work sgl_ilogic_lib ./source/sgl_ilogic_7series_tb.vhd

vsim -lib sgl_ilogic_lib sgl_ilogic_7series_tb +access +r

transcript off
#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Testbench Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave *

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Clock Logic Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave clogic_ins/*

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Input Logic Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave ilogic_ins/*


#-------------------------------------------
transcript on

run 20 us;