#Change to the dirctory below, then execute this script:
#./HELIX/firmware/common/ttcs_intfc/sim/

vlib ttcs_intfc_lib "./library/ttcs_intfc_lib"

#Compile our sources
vcom -2008 -work ttcs_intfc_lib ../../selectio/source/dif_ilogic_7series.vhd
vcom -2008 -work ttcs_intfc_lib ../../selectio/source/dif_ologic_7series.vhd
vcom -2008 -work ttcs_intfc_lib ../../selectio/source/dif_clogic_7series.vhd
vcom -2008 -work ttcs_intfc_lib ../../register/source/serial_lfsr_tx.vhd
vcom -2008 -work ttcs_intfc_lib ../../register/source/serial_lfsr_rx.vhd
vcom -2008 -work ttcs_intfc_lib ../source/ttcs_intfc_mgr.vhd
vcom -2008 -work ttcs_intfc_lib ../source/ttcs_intfc_feb.vhd
vcom -2008 -work ttcs_intfc_lib ../source/ttcs_framing_feb.vhd
vcom -2008 -work ttcs_intfc_lib ../source/ttcs_framing_mgr.vhd
#vcom -2008 -work ttcs_intfc_lib ./source/ttcs_intfc_ctr_tb.vhd
vcom -2008 -work ttcs_intfc_lib ./source/ttcs_intfc_rdm_tb.vhd

vsim -lib ttcs_intfc_lib ttcs_intfc_tb +access +r -ieee_nowarn

transcript off
#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Testbench Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave *

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Merger Top"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave UUT_MGR/*

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Merger Reveiver"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave UUT_MGR/rx_data_ins/*

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Meger Transmiter"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave UUT_MGR/tx_data_ins/*

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Front-End Top"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave UUT_FEB/*

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Front-End Reciever"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave UUT_FEB/rx_bg_ins/*

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Front-End Transmitter"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave UUT_FEB/tx_data_ins/*

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Merger Framing"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave mgr_frm_ins/*

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Front End Framing"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave feb_frm_ins/*

#-------------------------------------------
transcript on

run 500 us;