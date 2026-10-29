`timescale 1ns / 1ps
`include "interfaces.vh"
// Xillybus high-bandwidth event streamer.
//
// Here we have 2 output FIFOs: one, the event length FIFO (that's mm_event_waiting)
// and two, the actual event data itself.
//
// Both are asynchronous FIFOs. Internally here we use common-clock FIFOs because
// the event builder transfers data to the xilclk domain.
module xilly_event_streamer(
        // this is xilclk and aresetn transferred into xilclk domain
        input clk,
        input reset,
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_axis_ , 256 ),
        input s_axis_tlast,
        
        input enable_i,
        
        input event_open,
        output [255:0] event_data,
        output event_empty,
        input event_read,
        
        input waiting_open,
        output [31:0] waiting_data,
        output waiting_empty,
        input waiting_read        
    );
    parameter DEBUG = "TRUE";
    
    reg [31:0] this_event_count = {32{1'b0}};
    reg [31:0] this_event_count_rr = {32{1'b0}};
    reg [31:0] total_event_count = {32{1'b0}};
    reg last_flag = 0;
    reg write_count = 0;
    always @(posedge clk) begin
        // This generates the count that's fed to waiting.
        // We add 1 because we reset at tlast, so we need to add it back. 
        last_flag <= s_axis_tvalid && s_axis_tready && s_axis_tlast;
        if (last_flag) total_event_count <= this_event_count_rr + 1;
        // Push the write in.
        write_count <= last_flag;
        
        if ((s_axis_tvalid && s_axis_tready && s_axis_tlast) || reset) this_event_count <= {32{1'b0}};
        else if (s_axis_tvalid && s_axis_tready) this_event_count <= this_event_count + 1;
        // Delay this_event_count so that it still holds the value the cycle after tlast
        // so last_flag can be used to capture total_event_count.
        // This way data can flow uninterrupted into the FIFO even through multiple events (although that shouldn't be possible)
        this_event_count_rr <= this_event_count;
    end
    wire ev_full;
    wire waiting_full;
    // we need *both* of them to be available
    assign s_axis_tready = !ev_full && !waiting_full && enable_i;
    fifo256 u_evfifo(.clk(clk),.srst(reset),
                     .din( s_axis_tdata ),
                     .wr_en( s_axis_tvalid && s_axis_tready && enable_i),
                     .full( ev_full ),
                     .dout( event_data ),
                     .rd_en( event_read ),
                     .empty( event_empty ));
    fifo32 u_waitingfifo(.clk(clk),.srst(reset),
                         .din( total_event_count ),
                         .wr_en(write_count),
                         .full(waiting_full),
                         .dout(waiting_data),
                         .rd_en(waiting_read),
                         .empty(waiting_empty));

    // *very* simplified ILA, this is running fast
    // don't even try to grab the data, that's ridiculous
    // *maybe* if we need to we'll somehow try to grab one of the IDs or something, who knows
    generate
        if (DEBUG == "TRUE") begin : DBG
            xilly_event_ila u_ila(.clk(clk),
                                   .probe0( s_axis_tvalid ),
                                   .probe1( ev_full  ),
                                   .probe2( waiting_full ),
                                   .probe3( s_axis_tlast ),
                                   .probe4( total_event_count ));
        end
    endgenerate
endmodule
