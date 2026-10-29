#Execute this script after changing to this directory.
#/HELIX/firmware/merger/helix_aurora/sim/

vlib helix_framing_lib "./library/helix_framing_lib"

#######################################
#Compile our sources
#######################################
vcom -2008 -work helix_framing_lib ../../ttcs_intfc/source/ttcs_intfc_pkg.vhd

vcom -2008 -work helix_framing_lib ../source/aurora_8b10b_aurora_pkg.vhd
vcom -2008 -work helix_framing_lib ../source/aurora_8b10b_ll_to_axi.vhd
vcom -2008 -work helix_framing_lib ../source/aurora_8b10b_axi_to_ll.vhd

vcom -2008 -work helix_framing_lib ../source/aurora_8b10b_frame_gen.vhd
vcom -2008 -work helix_framing_lib ../source/aurora_8b10b_frame_check.vhd
vcom -2008 -work helix_framing_lib ../source/helix_frmgen.vhd
vcom -2008 -work helix_framing_lib ../source/helix_frmchk.vhd

vcom -2008 -work helix_framing_lib ./source/helix_framing_tb.vhd

vsim -lib helix_framing_lib helix_aurora_tb +access +r

transcript off
#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Testbench Signals"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave *

#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Frame Generator"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave frmgen_typ_gen/frm_gen_ins/*
#-------------------------------------------


#-------------------------------------------------------------
wave -divider "/---------------------------"
wave -divider "Frame Checker"
wave -divider "/---------------------------"
#-------------------------------------------------------------
wave frmchk_typ_gen/frm_chk_ins/*
#-------------------------------------------
transcript on

run 5 ms;