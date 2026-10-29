#Execute this script after changing to this directory.
#/HELIX/firmware/merger/helix_aurora/sim/

vlib helix_aurora_lib "./library/helix_aurora_lib"

#######################################
#Compile our sources
#######################################
vcom -2008 -work helix_aurora_lib ../../ttcs_intfc/source/ttcs_intfc_pkg.vhd

vcom -2008 -work helix_aurora_lib ../../../common/register/source/cdc_register.vhd
vcom -2008 -work helix_aurora_lib ../../../common/register/source/reset_bridge.vhd

vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_aurora_pkg.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_cdc_sync.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_gtrxreset_seq.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_rx_startup_fsm.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_tx_startup_fsm.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_gt_common_wrapper.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_gt.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_multi_gt.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_transceiver_wrapper.vhd

vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_channel_err_detect.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_channel_init_sm.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_chbond_count_dec.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_crc_top.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_err_detect.vhd

vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_hotplug.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_idle_and_ver_gen.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_lane_init_sm.vhd

vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_reset_logic.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_rxcrc.vhd

vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_rx_ll_nfc.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_rx_ll_pdu_datapath.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_rx_ll.vhd

vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_standard_cc_module.vhd

vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_sym_dec.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_sym_gen.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_txcrc.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_tx_ll_control.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_tx_ll_datapath.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_tx_ll.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_global_logic.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_aurora_lane.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_ll_to_axi.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_axi_to_ll.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_core.vhd
vcom -2008 -work helix_aurora_lib ../source/helix_aurora_reset.vhd
vcom -2008 -work helix_aurora_lib ../source/helix_aurora.vhd

vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_frame_gen.vhd
vcom -2008 -work helix_aurora_lib ../source/aurora_8b10b_frame_check.vhd
vcom -2008 -work helix_aurora_lib ../source/helix_frmgen.vhd
vcom -2008 -work helix_aurora_lib ../source/helix_frmchk.vhd
vcom -2008 -work helix_aurora_lib ../source/helix_ll_to_axi.vhd
vcom -2008 -work helix_aurora_lib ../source/helix_axi_to_ll.vhd
vcom -2008 -work helix_aurora_lib ../source/helix_frmgen.vhd
vcom -2008 -work helix_aurora_lib ../source/helix_framing.vhd

vcom -2008 -work helix_aurora_lib ./source/helix_aurora_tb.vhd
