`timescale 1ns / 1ps
// this allows me to test the frame pointer calculation separately
module frame_pointer_calc_v3 #(parameter BRCVD_WIDTH=23, parameter FRAME_PTR_WIDTH=32, parameter TOT_WIDTH=24, parameter NUM_LINKS=8)(
        input clk,
        input calc_i,
        input [NUM_LINKS-1:0] mask_i,
        output done_o,
        input [BRCVD_WIDTH*NUM_LINKS-1:0] brcvd_i,
        output [FRAME_PTR_WIDTH*NUM_LINKS-1:0] frameptr_o,
        output [TOT_WIDTH-1:0] tot_length_o
    );
    // and these are the internal cascades
    wire [47:0] frame_cascade[NUM_LINKS-1:1];
    wire [BRCVD_WIDTH-1:0] brcvd[NUM_LINKS-1:0];

    localparam DONE_DELAY = 8;
    wire done;
    SRLC32E u_delay(.D(calc_i),.Q(done),.A(DONE_DELAY),.CLK(clk),.CE(1'b1));
    FD u_done(.D(done),.C(clk),.Q(done_o));

    localparam [47:0] FRAME_PTR_START_VALUE = 48'd40;

    generate
        genvar i;
        // OK. So we need to calculate the frame pointers.
        // The first frame pointer is always 40.
        // Then the next one is the number of received bytes from the previous frame,
        // plus the previous frame pointer, minus 4 (because we moved ahead one).
        for (i=0;i<NUM_LINKS+1;i=i+1) begin : DEC_ADD
            wire [47:0] dspout;
            // The complete stream is { error, brcvd, address }
            if (i < NUM_LINKS) begin : BRCVD
                assign brcvd[i] = brcvd_i[ BRCVD_WIDTH*i +: BRCVD_WIDTH ];
            end
            if (i == 0) begin : CONSTANT
                assign dspout = FRAME_PTR_START_VALUE;
                assign frameptr_o[FRAME_PTR_WIDTH*i +: FRAME_PTR_WIDTH] = dspout[0 +: FRAME_PTR_WIDTH];
            end else if (i == 1) begin : HEAD
                wire [47:0] dspin = { {(48-BRCVD_WIDTH){1'b0}}, brcvd[i-1] };
                // functionally this is adding the previous frame ptr
                wire [47:0] concatin = FRAME_PTR_START_VALUE - 4;
                                                         
                fp_head_dsp u_head( .CONCAT( concatin ),
                                    .C( dspin ),
                                    .SCLRC( mask_i[i-1] ),
                                    .P( dspout ),
                                    .PCOUT( frame_cascade[i] ),
                                    .CLK( clk ));
                assign frameptr_o[FRAME_PTR_WIDTH*i +: FRAME_PTR_WIDTH] = dspout[0 +: FRAME_PTR_WIDTH];
            end else if (i < NUM_LINKS) begin : BODY
                wire [47:0] dspin = { {(48-BRCVD_WIDTH){1'b0}}, brcvd[i-1] };
                fp_body_dsp u_body( .PCIN( frame_cascade[i-1] ),
                                    .CONCAT( -48'd4 ),
                                    .C( dspin ),
                                    .SCLRC( mask_i[i-1] ),
                                    .P( dspout ),
                                    .PCOUT( frame_cascade[i] ),
                                    .CLK( clk ));
                assign frameptr_o[FRAME_PTR_WIDTH*i +: FRAME_PTR_WIDTH] = dspout[0 +: FRAME_PTR_WIDTH];
            end else begin : TAIL
                // However, at the *tail* where we need to compute the total length,
                // we've now subtracted out a bunch. Imagine the case where brcvd 0/1/2 are 4 and the others are 0.
                // frameptr[0] = 40
                // frameptr[1] = 40 (brcvd0=4, frameptr[0]=40, subtract 4)
                // frameptr[2] = 40 (brcvd1=4, frameptr[1]=40, subtract 4)
                // frameptr[3] = 40 (brcvd2=4, frameptr[1]=40, subtract 4) 
                // frameptr[4] = 36
                // frameptr[5] = 32
                // frameptr[6] = 28
                // frameptr[7] = 24
                // The *total length* is 64 + 12 = 76.
                // If we add 24 to the final one, that's 44, so we need to add 28 more (from the 7 frame
                // pointers we subtracted). Or a total of 52.
                fp_tail_dsp u_tail( .PCIN( frame_cascade[i-1] ),
                                    .C( brcvd[i-1] ),
                                    .SCLRC( mask_i[i-1] ),
                                    // add back in the header parts plus the 7 subtracted frame pointers
                                    .CONCAT( 48'd52 ),
                                    .P( dspout ),
                                    .CLK( clk ));
                assign tot_length_o = dspout[0 +: TOT_WIDTH];
            end
        end
    endgenerate
        
    
endmodule
