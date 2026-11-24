# NOTE NOTE NOTE: we ASSUME that the flag_sync module
# gets covered by the main design.

# Protect everything in a namespace, then call an init function.
namespace eval MMergerCore {
    namespace export init
    
    proc set_cc_paths { srcClk dstClk ctlist } {
	if {$srcClk eq ""} {
	    puts "set_cc_paths: No source clock: returning."
	    return
	}
	if {$dstClk eq ""} {
	    puts "set_cc_paths: No destination clock: returning."
	    return
	}
	array set ctypes $ctlist
	set srcType $ctypes($srcClk)
	set dstType $ctypes($dstClk)
	set maxTime [get_property PERIOD $srcClk]
	set srcRegs [get_cells -hier -filter "CUSTOM_CC_SRC == $srcType"]
	set dstRegs [get_cells -hier -filter "CUSTOM_CC_DST == $dstType"]
	if {[llength $srcRegs] == 0} {
	    puts "set_cc_paths: No registers flagged with CUSTOM_CC_SRC $srcType: returning."
	    return
	}
	if {[llength $dstRegs] == 0} {
	    puts "set_cc_paths: No registers flagged with CUSTOM_CC_DST $dstType: returning."
	    return
	}
	set_max_delay -datapath_only -from $srcRegs -to $dstRegs $maxTime
    }

    proc set_gray_paths { srcClk dstClk ctlist } {
	if {$srcClk eq ""} {
	    puts "set_gray_paths: No source clock: returning."
	    return
	}
	if {$dstClk eq ""} {
	    puts "set_gray_paths: No destination clock: returning."
	    return
	}
	array set ctypes $ctlist
	set srcType $ctypes($srcClk)
	set dstType $ctypes($dstClk)
	set maxTime [get_property PERIOD $srcClk]
	set maxSkew [expr min([get_property PERIOD $srcClk], [get_property PERIOD $dstClk])]
	set srcRegs [get_cells -hier -filter "CUSTOM_GRAY_SRC == $srcType"]
	set dstRegs [get_cells -hier -filter "CUSTOM_GRAY_DST == $dstType"]
	if {[llength $srcRegs] == 0} {
	    puts "set_gray_paths: No registers flagged with CUSTOM_GRAY_SRC $srcType: returning."
	    return
	}
	if {[llength $dstRegs] == 0} {
	    puts "set_gray_paths: No registers flagged with CUSTOM_GRAY_DST $dstType: returning."
	    return
	}
	set_max_delay -datapath_only -from $srcRegs -to $dstRegs $maxTime
	set_bus_skew -from $srcRegs -to $dstRegs $maxSkew
    }

    proc set_ignore_paths { srcClk dstClk ctlist } {
	if {$srcClk eq ""} {
	    puts "set_ignore_paths: No source clock: returning."
	    return
	}
	if {$dstClk eq ""} {
	    puts "set_ignore_paths: No destination clock: returning."
	    return
	}
	array set ctypes $ctlist
	set srcType $ctypes($srcClk)
	set dstType $ctypes($dstClk)
	set srcRegs [get_cells -hier -filter "CUSTOM_IGN_SRC == $srcType"]
	set dstRegs [get_cells -hier -filter "CUSTOM_IGN_DST == $dstType"]
	if {[llength $srcRegs] == 0} {
	    puts "set_ignore_paths: No registers flagged with CUSTOM_IGN_SRC $srcType: returning."
	    return
	}
	if {[llength $dstRegs] == 0} {
	    puts "set_ignore_paths: No registers flagged with CUSTOM_IGN_DST $dstType: returning."
	    return
	}
	set_false_path -from $srcRegs -to $dstRegs
    }    
    
    proc init { } {
	
	# We find the core by searching for MMRG as the identifier.
	# If we add a second one we'll need to search for either/or.
	# We'll end up getting a list, and then we need to split them
	# by / and find the shortest one.
	
	set identcells [get_cells -hier -filter { IDENT == "MMRG" }]
	set corename ""
	set minCount Inf
	foreach elem $identcells {
	    set count [llength [split $elem "/"]]
	    if {$count < $minCount} {
		set minCount $count
		set corename $elem
	    }
	}

	puts "mmerger-core: identified core name as $corename"

	set initclk [get_clocks -of_objects [get_nets $corename/init_clk]]
	set clktypes($initclk) INITCLK
	set xilclk [get_clocks -of_objects [get_nets $corename/xilclk]]
	set clktypes($xilclk) XILCLK
	set aurclk [get_clocks -of_objects [get_nets $corename/u_aurora/LANE[0].u_cc_flowctrl_count/clkA]]
	set clktypes($aurclk) AURCLK
	set aclk [get_clocks -of_objects [get_nets $corename/aclk]]
	set clktypes($aclk) ACLK
	set bufrefclk [get_clocks -of_objects [get_nets $corename/u_aurora/gt_refclk_bufg]]
	set clktypes($bufrefclk) BUFREFCLK
	

	# We're going to use the magic clock functions, but
	# we need to manually tag some of them because it's awkward to do it
	# internally.
	set dspfilt "NAME =~ $corename/u_aurora/LANE[*].u_vwrap/u_dnpcie_aurora_core/u_core_wrapper/u_reset/u_hp_reset_counter/*u_counter"
	set hp_count_dsps [get_cells -hier -filter $dspfilt]
	foreach dsp $hp_count_dsps {
	    set_property CUSTOM_CC_DST INITCLK $dsp
	}

	# create clocktypes list
	set clktypelist [array get clktypes]
	
	set_cc_paths $aurclk $xilclk $clktypelist
	set_cc_paths $xilclk $initclk $clktypelist
    }
}

MMergerCore::init
