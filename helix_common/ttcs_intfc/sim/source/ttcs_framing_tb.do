#Change to the dirctory below, then execute this script:
#./HELIX/firmware/common/ttcs_intfc/sim/

vlib ttcs_framing_lib "./library/ttcs_framing_lib"

#Compile our sources
vcom -2008 -work ttcs_framing_lib ../../register/source/serial_lfsr_tx.vhd
vcom -2008 -work ttcs_framing_lib ../../register/source/serial_lfsr_rx.vhd

vcom -2008 -work ttcs_framing_lib ../source/ttcs_framing_mgr.vhd
vcom -2008 -work ttcs_framing_lib ../source/ttcs_framing_feb.vhd

vcom -2008 -work ttcs_framing_lib ./source/ttcs_framing_tb.vhd

vsim -lib ttcs_framing_lib ttcs_framing_tb +access +r -ieee_nowarn

transcript off
#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Testbench Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave *


#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Merger Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave mgr_ins/*

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Front-End Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave feb_gen__1/feb_ins/*

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Merger Transmitter Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave mgr_ins/tx_gen__1/tx_ins/*

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Front-End Receiver Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave feb_gen__1/feb_ins/rx_gen__1/rx_ins/*

#-------------------------------------------
transcript on

run 10 ms;