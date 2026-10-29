#*********************************************************************************
# Indiana University
# Center for Exploration of Energy and Matter (CEEM)
#
# Project: HELIX
#
# Author:  Brandon Kunkler
#
# Date:    04/20/2017
#
#*********************************************************************************
# This notification is to inform you that the schematics/source-code provided by
# Indiana University are controlled under the US Export Control Regulations.  The
# schematics/source code are classified as ECCN 3E991.  Under these --controls this
# information cannot be shared with individuals from or shipped to Cuba, Iran,
# North Korea, Syria, or Sudan.  If there is a need to share this information with
# any other individuals please contact export@iu.edu prior to sharing the information
# so it can be determined if a US export control license is required.
#
#*********************************************************************************
# Description:
# Floorplanning constraints for TTCS.
#
#*********************************************************************************

##===================================================================================================##
##======================================  FLOORPLANNING  ============================================##
##===================================================================================================##

##==========##
## P BLOCKS ##
##==========##
##Example block that must be added to your constraints file ######################
#create_pblock ttcs_pblock
#add_cells_to_pblock [get_pblocks ttcs_pblock] [get_cells -quiet [list top_level/ttcs_ins]]
#resize_pblock [get_pblocks ttcs_pblock] -add {CLOCKREGION_X0Y1:CLOCKREGION_X0Y1}

##============##
## PRIMITIVES ##
##============##

## PLL:
##-----------------

#set_property LOC PLLE2_ADV_X0Y2 [get_cells txpll/plle2_adv_inst]

## MMCM:
##---------------------------

#set_property LOC MMCME2_ADV_X0Y6 [get_cells gbtExmplDsgn/*/latOpt_phalgnr_gen.mmcm_inst/pll/inst/mmcm_adv_inst]

##===================================================================================================##
##===================================================================================================##

