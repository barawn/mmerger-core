clear all;
close all;
fclose('all');
SIAWDT = 16;%ROM data width
SIMDWDT = 16;%ROM data width
RAMWDT = SIAWDT + SIMDWDT;

DETSEL = "tracker";%tracker, merger, or rich
TRKPATH = "./../../../examples/tracker/si5345_ram/";
RHCPATH = "./../../../rich/si5345_ram/";
MGRPATH = "./../../../merger/si5345_ram/";
%FNAME = 'Si5345-RevD-MERGINSL-Registers.txt';%Merger
FNAME = 'Si5345-RevD-HelixADC-Registers.txt';%Tracker

DETPATH = TRKPATH;%SELECT THE PATH!!!!!!!!
PNAME = strcat(DETPATH,FNAME);

[A,D,idx] = parse_file(PNAME,SIAWDT,SIAWDT);
[ram_init,ninit] = file_to_bram_init(RAMWDT,A,D,idx);
write_ram_file(RAMWDT,ram_init,ninit,idx,DETPATH);
disp(strcat('Number of registers=',num2str(idx)));