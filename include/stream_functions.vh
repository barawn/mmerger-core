// Dumb functions to deal with poor packed type support.

////////////////////////////////////////////////////////////////
// DataMover functions
////////////////////////////////////////////////////////////////

// Build a DataMover command.
// I never use DRE so DSA, DRR are both
// always zero.
// Transactions are always 32 bit
// address widths as well.
function [71:0] dm_command;
    input [31:0] address;
    input [22:0] btt;
    input [3:0]  tag;
    input        eof;
    input        incr;
    begin
        dm_command[22:0] = btt;
        dm_command[23] = incr;
        dm_command[29:24] = {6{1'b0}};
        dm_command[30] = eof;
        dm_command[31] = 1'b0;
        dm_command[32 +: 32] = address;
        dm_command[64 +: 4] = tag;
        dm_command[68 +: 4] = 4'h0;
    end
endfunction

// Extract BRCVD from datamover.
function [22:0] dm_brcvd;
    input [31:0] status;
    begin
        dm_brcvd = status[8 +: 23];
    end
endfunction

// Extract error from DataMover status.
// not OKAY is an error, so invert it
function [3:0] dm_error;
    input [7:0] status;
    begin
        dm_error = { !status[7], status[6:4] };
    end
endfunction

// Extract EOP from DataMover status
function dm_eop;
    input [31:0] status;
    begin
        dm_eop = status[31];
    end
endfunction

////////////////////////////////////////////////////////////////
// Completion functions
////////////////////////////////////////////////////////////////

// Extract path number from completion
function [3:0] cmpl_path;
    input [63:0] completion;
    begin
        cmpl_path = completion[ 0 +: 4];
    end
endfunction

// Extract bytes received from completion
function [22:0] cmpl_brcvd;
    input [63:0] completion;
    begin
        cmpl_brcvd = completion[ 32 +: 23 ];
    end
endfunction

// Extract address from completion
function [31:0] cmpl_address;
    input [63:0] completion;
    begin
        cmpl_address = { completion[ 4 +: 28 ], 4'h0 };
    end
endfunction

// Extract error from completion
function [7:0] cmpl_error;
    input [63:0] completion;
    input [7:0] tkeep;
    begin
        cmpl_error = tkeep[7] ? completion[ 56 +: 8 ] : 8'h00;
    end
endfunction

function [63:0] cmpl_build;
    input [31:0] address;
    input [22:0] brcvd;
    input [7:0] error;
    begin
        cmpl_build = { error, 1'b0, brcvd, address };
    end
endfunction

