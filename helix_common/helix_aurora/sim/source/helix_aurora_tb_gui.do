#Execute this script after changing to this directory.
#/HELIX/firmware/merger/helix_aurora/sim/

#Compile our sources
do ./source/helix_aurora_tb_compile.do

#Run the simulation
vsim -lib helix_aurora_lib helix_aurora_tb +access +r

transcript off
#Display interesting signals in waveform viewer.
do ./source/helix_aurora_tb_wave.do
transcript on

run 10 us;

simstats