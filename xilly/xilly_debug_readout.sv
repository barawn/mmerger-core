`timescale 1ns / 1ps
`include "interfaces.vh"
`define NO_PREFIX_TAG(x)

// Xillybus debug readout.
module xilly_debug_readout(
        input aclk,
        input xil_clk,
        input rclk,
        input rreset,
        input aresetn,        
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_axis_ , 64 ),
        input s_axis_tlast,
        input [2:0] s_axis_tuser,
        output [8:0] req_suppress,
        
        output [63:0] debug_data,
        output debug_empty,
        input debug_read,
        input debug_open,
        
        `TARGET_NAMED_PORTS_COMBINED_IF( `NO_PREFIX_TAG(dummy) )
    );

    reg [31:0] cur_nwords = {32{1'b0}};
    reg [31:0] tot_nwords = {32{1'b0}};
    reg [31:0] tot_nwords_rclk = {32{1'b0}};

    reg [2:0] cur_tuser = {3{1'b0}};
    reg [2:0] cur_tuser_rclk = {3{1'b0}};

    reg [2:0] err_aclk_sticky = {3{1'b0}};
    wire [2:0] s_axis_tuser_sticky = s_axis_tuser | err_aclk_sticky;

    wire tlast_seen_xilclk;
    wire tlast_seen_rclk;
    flag_sync u_tlast_seen_sync(.in_clkA(tlast_seen_xilclk),.out_clkB(tlast_seen_rclk),
                                .clkA(xil_clk),.clkB(rclk));
    reg capture_nwords_tuser = 0;
    wire tlast_done_aclk;
    flag_sync u_tlast_done_sync(.in_clkA(capture_nwords_tuser),.out_clkB(tlast_done_aclk),
                                .clkA(rclk),.clkB(xil_clk));
    wire allow_update;
    wire allow_update_busy;
    wire allow_update_aclk;
    flag_sync u_allow_update_sync(.in_clkA(allow_update),.out_clkB(allow_update_aclk),
                                  .busy_clkA(allow_update_busy),
                                  .clkA(rclk),.clkB(aclk));    
    
    reg [8:0] allow = {9{1'b0}};
    reg [8:0] allow_aclk = {9{1'b0}};
    reg allow_reset = 0;
    
    wire s_axis_complete = (s_axis_tvalid && s_axis_tready && s_axis_tlast);    

    reg allow_write = 0;
    reg allow_write_ff = 0;
    reg write_cc_busy = 0;
    reg [7:0] register_read_tag = {8{1'b0}};
    reg [63:0] register_read_data_ff = {64{1'b0}};
    reg register_read_valid;
                    
    always @(posedge aclk) begin
        // Keep the tuser bits sticky.
        if (!aresetn) err_aclk_sticky <= {3{1'b0}};
        else if (s_axis_complete) err_aclk_sticky <= {3{1'b0}};
        else err_aclk_sticky <= s_axis_tuser_sticky;
        
        // req_suppress is the inverted allow: we allow updates to it only when
        // frames are complete, unless it's a reset.
        if (s_axis_complete || (allow_update_aclk && allow_reset)) allow_aclk <= {9{1'b0}};
        else if (allow_update_aclk) begin
            if (allow_aclk == {9{1'b0}}) allow_aclk <= allow;
        end
    end        

    always @(posedge rclk) begin
        if (register_read_enable) register_read_tag <= register_request_tag;
        register_read_valid <= register_read_enable;
        
        capture_nwords_tuser <= tlast_seen_rclk;

        if (allow_update) begin
            cur_tuser_rclk <= {3{1'b0}};
            tot_nwords_rclk <= {32{1'b0}};
        end else if (capture_nwords_tuser) begin  
            cur_tuser_rclk <= cur_tuser;
            tot_nwords_rclk <= tot_nwords;
        end
        
        // need to add the combined if interface here:
        // write to the allow register, then generate the flag to aclk
        allow_write <= register_write_enable && register_write_be[0];
        allow_write_ff <= allow_write;
        if (register_write_enable && register_write_be[0]) begin
            allow <= register_write_data[8:0];
            allow_reset <= register_write_data[31];
        end
        
        if (!allow_update_busy) write_cc_busy <= 1'b0;
        else if (register_write_enable && register_write_be[0]) write_cc_busy <= 1; 
    end

    assign allow_update = allow_write && !allow_write_ff;


    // THIS METHOD BLOWS
    // WHY ARE WE DOING THIS
    // What we SHOULD do is use a FWFT FIFO to cross into
    // xilclk domain. In xilclk, watch for tlast and hold off
    // writing into a second tiny FIFO which just handles the Xilly-side
    // interfacing. Probably just make it a standard FIFO guy.
    
    // AND YET THE OLD CODE ACTUALLY WORKS

///// OLD CODE

//    localparam FSM_BITS = 2;
//    localparam [FSM_BITS-1:0] IDLE = 0;
//    localparam [FSM_BITS-1:0] READ_HOLDOFF = 1;
//    localparam [FSM_BITS-1:0] TLAST_SEEN = 2;
//    localparam [FSM_BITS-1:0] TLAST_WAIT = 3;
//    reg [FSM_BITS-1:0] state = IDLE;
//    wire xil_empty;
//    wire xil_tlast;
//    wire [2:0] xil_tuser;

//    always @(posedge xil_clk) begin
//        if (!debug_open) state <= IDLE;
//        else begin
//            case (state)
//                IDLE: if (debug_read && !xil_empty) state <= READ_HOLDOFF;
//                READ_HOLDOFF: if (xil_tlast) state <= TLAST_SEEN;
//                              else state <= IDLE;
//                TLAST_SEEN: state <= TLAST_WAIT;
//                TLAST_WAIT: if (tlast_done_aclk) state <= IDLE;
//            endcase
//        end
//        if (!debug_open || state == TLAST_SEEN) cur_nwords <= {32{1'b0}};
//        else if (state == READ_HOLDOFF) cur_nwords <= cur_nwords + 1;

//        if (state == TLAST_SEEN) tot_nwords <= cur_nwords;        
                    
//        if (state == TLAST_WAIT && tlast_done_aclk) cur_tuser <= {3{1'b0}};
//        else if (state == READ_HOLDOFF) cur_tuser <= cur_tuser | xil_tuser;        
//    end

//    assign tlast_seen_xilclk = (state == TLAST_SEEN);

//    xilly_debug_ila u_dbgila(.clk(xil_clk),
//                             .probe0( debug_read ),
//                             .probe1( state ),
//                             .probe2( debug_data ),
//                             .probe3( xil_tlast ),
//                             .probe4( tot_nwords ));
            
//    wire event_full;
//    assign s_axis_tready = !event_full;
//    fifo68_cc u_stat_ccfifo(.wr_clk(aclk),
//                            .rd_clk(xil_clk),
//                            .srst(!aresetn),
//                            .din( { s_axis_tlast, s_axis_tuser_sticky, s_axis_tdata } ),
//                            .wr_en( s_axis_tvalid && s_axis_tready ),
//                            .full( event_full ),
//                            .dout( { xil_tlast, xil_tuser, debug_data } ),
//                            .rd_en( debug_read && state == IDLE ),
//                            .empty( xil_empty) );
//     //we want to assert empty *whenever* we leave IDLE.
//     //Our throughput then is only half of what it could be,
//     //but it's still plenty fast (1 GB/s).
//        assign debug_empty = ((state == IDLE) && xil_empty) || (state != IDLE);
    

// END OLD CODE
/////////////////////////////////////////////////////////////////////////////////

// NONWORKING NEW CODE
    reg xil_holdoff = 0;
    reg frame_end = 0;
    reg flag_frame_end = 0;

    // This connects the input to the xilclk domain
    wire ccfifo_tlast;
    wire [63:0] ccfifo_tdata;
    wire [2:0] ccfifo_tuser;
    wire ccfifo_empty;

    // these guys cross to the isolation FIFO
    wire xfifo_full;
    wire ccfifo_tready = !xfifo_full && !xil_holdoff;
    wire ccfifo_tvalid;        
    wire xfifo_wr = ccfifo_tvalid && ccfifo_tready;

    assign tlast_seen_xilclk = flag_frame_end;

    // OK: so *when* tlast is seen, xil_holdoff gets set.
    // This kills any more data flowing between the two FIFOs.

    // so the sequence goes:
    // clk tvalid&&tlast&&tready frame_end  flag_frame_end xil_holdoff  cur_nwords tot_nwords
    // 0   1                     0          0              0            N-1        X
    // 1   0                     1          0              1            N          X
    // 2   0                     0          1              1            0          N
    // 3   0                     0          0              1            0          N
    // we then cross to rclk...
    // rclk tlast_seen_rclk capture_nwords_tuser
    // ..0  1               0
    // 1    0               1
    // 2    0               0
    // and back to xilclk where capture_nwords_tuser becomes tlast_done_aclk
    
    always @(posedge xil_clk) begin
        if (!debug_open) xil_holdoff <= 0;
        else if (tlast_done_aclk) xil_holdoff <= 0;
        else if (ccfifo_tvalid && ccfifo_tready && ccfifo_tlast) xil_holdoff <= 1;

        if (!debug_open || frame_end) cur_nwords <= {32{1'b0}};
        else if (ccfifo_tvalid && ccfifo_tready) cur_nwords <= cur_nwords + 1;
        
        if (frame_end) tot_nwords <= cur_nwords + 1;
        
        frame_end <= ccfifo_tvalid && ccfifo_tready && ccfifo_tlast;
        flag_frame_end <= frame_end;        
    end

    // This FIFO crosses clock to xil_clk...
    // It acts as the sink for the s_axis_ input.
    // So s_axis_tready is just !ccfifo_full
    // The xil_holdoff occurs *between* the two.
    assign s_axis_tready = !ccfifo_full;
    fifo68_cc_fwft u_dbg_ccfifo(.wr_clk(aclk),
                                .rd_clk(xil_clk),
                                .srst(!aresetn),
                                .din( { s_axis_tlast, s_axis_tuser_sticky, s_axis_tdata } ),
                                .wr_en( s_axis_tvalid && s_axis_tready ),
                                .full(ccfifo_full),
                                .valid(ccfifo_tvalid),
                                .rd_en(ccfifo_tvalid && ccfifo_tready),
                                .dout( { ccfifo_tlast, ccfifo_tuser, ccfifo_tdata } ));

    // and then our logic runs between it and xfifo
    fifo64_small u_xfifo( .clk(xil_clk),
                          .srst(!aresetn),
                          .din(ccfifo_tdata),
                          .wr_en( xfifo_wr ),
                          .full( xfifo_full ),
                          .dout(debug_data),
                          .rd_en(debug_read),
                          .empty(debug_empty));
                                
    xilly_debug_vio u_dbgvio(.clk(aclk),.probe_in0(req_suppress));

    wire [7:0] this_error = { cur_tuser, {5{1'b0}} };

        
    assign interface_ready = !write_cc_busy;
    assign register_read_data = { tot_nwords_rclk , {8{1'b0}}, this_error, {16{1'b0}} };
    assign register_read_data_valid = register_read_valid;
    assign register_read_data_tag = register_read_tag;
        
    assign req_suppress = ~allow_aclk;
endmodule
