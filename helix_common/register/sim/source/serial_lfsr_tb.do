#Change to the dirctory below, then execute this script:
#./HELIX/firmware/common/ttcs_intfc/sim/

vlib serial_lfsr_lib "./library/serial_lfsr_lib"

#Compile our sources
vcom -2008 -work serial_lfsr_lib ../source/serial_lfsr_tx.vhd
vcom -2008 -work serial_lfsr_lib ../source/serial_lfsr_rx.vhd

vcom -2008 -work serial_lfsr_lib ./source/serial_lfsr_tb.vhd

vsim -lib serial_lfsr_lib serial_lfsr_tb +access +r -ieee_nowarn

transcript off
#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Testbench Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave *


#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Transmitter Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave tx_ins/*

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Receiver Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave rx_ins/*


#-------------------------------------------
transcript on

run 5 ms;