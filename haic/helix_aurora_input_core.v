`timescale 1ns/1ps
`include "interfaces.vh"

module helix_aurora_input_core( input s_axis_aclk,
                                input s_axis_aresetn,
                                input [31:0] s_axis_tdata,
                                input        s_axis_tvalid,
                                input [2:0]  s_axis_tuser,
                                input        s_axis_tlast,
                                output flow_xoff_o,
                                output flow_drop_o,
                                input  dropped_flag_i,
                                output dropped_o,
                                output overflow_o,
                                input [31:0] jam_delay_i,
                                output jammed_o,
                                input jam_disable_i,
                                input [31:0] stuck_delay_i,
                                output stuck_o,
                                input stuck_disable_i,   
                                input [7:0] xoff_level_i,
                                input [7:0] xoff_hysteresis_i,
                                input s_update_i,
                                input m_update_i,
                                
                                output [7:0] extra_error_o,
                                
                                // m_axis_aclk domain
                                input m_axis_aclk,
                                input m_axis_aresetn,
                                `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_axis_ev_ , 64 ),
                                output [2:0] m_axis_ev_tuser,
                                output       m_axis_ev_tlast,
                                `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_axis_st_ , 64 ),
                                output [2:0] m_axis_st_tuser,
                                output       m_axis_st_tlast,
                                `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_axis_err_ , 64 ),
                                output [4:0] m_axis_err_tuser,
                                output       m_axis_err_tlast );

    // Local jam disable, updated at update_i.
    reg jam_disable = 0;
    // Jam error.
    reg jammed = 0;
    // Indicates jam delay reached. One for event path, one for status path.
    wire ev_jam_delay_reached;
    wire stat_jam_delay_reached;
    
    // start counting anytime it's valid, only stop at a tlast.
    reg stuck_count = 0;  
    // local stuck disable  
    reg stuck_disable = 0;
    // stuck error
    reg stuck = 0;
    // Indicates stuck delay reached.
    wire stuck_delay_reached;
    
    // Flow control FIFO needs an extra clock of reset.
    reg flow_fifo_areset_hold = 1'b0;
    wire flow_fifo_reset = !s_axis_aresetn || flow_fifo_areset_hold;
    always @(posedge s_axis_aclk) flow_fifo_areset_hold <= !s_axis_aresetn;    
        
    // flow buffer -> width converter 
    `DEFINE_AXI4S_MIN_IF( flow_ , 32 );
    wire [2:0]            flow_tuser;
    wire [3:0]            flow_tuser_expanded = { 1'b0, flow_tuser };
    wire                  flow_tlast;


    wire flow_prog_full;
    wire flow_almost_full;
    wire [8:0] flow_prog_full_assert;
    wire [8:0] flow_prog_full_negate;    
    haic_xoff_logic u_xoff_logic( .clk(s_axis_aclk),.reset(!s_axis_aresetn),
                                  .update_i(s_update_i),
                                  // XOFF interface
                                  .xoff_o(flow_xoff_o),
                                  .xoff_drop_o(flow_drop_o),
                                  // Status interface
                                  .dropped_o(dropped_o),
                                  .overflow_o(overflow_o),
                                  .dropped_flag_i(dropped_flag_i),
                                  .valid_data_i( s_axis_tvalid ),
                                  // Control inputs
                                  .xoff_level_i(xoff_level_i),
                                  .xoff_hysteresis_i(xoff_hysteresis_i),
                                  // FIFO interface
                                  .prog_full_thresh_assert_o(flow_prog_full_assert),
                                  .prog_full_thresh_negate_o(flow_prog_full_negate),
                                  .almost_full_i(flow_almost_full),
                                  .prog_full_i(flow_prog_full));

    // Adjust tuser and tlast.
    // tuser[0] = start of frame
    // tuser[1] = CRC error, or trimmed packet due to overflow ("this packet isn't what was sent")
    // tuser[2] = TKEEP error (packet was not an integral number of 32-bit words) ("this packet isn't what I expected")
    wire        flow_in_tlast;
    wire [2:0]  flow_in_tuser;
    assign flow_in_tlast = (s_axis_tlast || flow_almost_full);
    assign flow_in_tuser = { s_axis_tuser[2], s_axis_tuser[1] || (s_axis_tlast && flow_almost_full), s_axis_tuser[0] };

    reg in_frame = 0;
    reg malformed_frame = 0;
    reg [1:0] malformed_frame_rclk = {2{1'b0}};

    reg flow_in_frame = 0;
    reg flow_malformed_frame = 0;
    reg [1:0] flow_malformed_frame_rclk = {2{1'b0}};
                                      
    flow_buffer u_buffer(.din( { flow_in_tlast, flow_in_tuser, s_axis_tdata } ),
                         .wr_en( s_axis_tvalid && !flow_drop_o ),
                         .almost_full(flow_almost_full),
                         .dout( { flow_tlast, flow_tuser, flow_tdata } ),
                         .valid( flow_tvalid ),
                         .rd_en( flow_tvalid && flow_tready ),
                         .prog_full_thresh_assert(flow_prog_full_assert),
                         .prog_full_thresh_negate(flow_prog_full_negate),
                         .prog_full(flow_prog_full),
                         .clk(s_axis_aclk),
                         .srst(flow_fifo_reset));    

    // track frames to find the bitch
    always @(posedge s_axis_aclk) begin
        if (!s_axis_aresetn) begin
            in_frame <= 1'b0;
            flow_in_frame <= 1'b0;
        end else begin
            if (flow_in_tlast && s_axis_tvalid) in_frame <= 1'b0;
            else if (flow_in_tuser[0] && s_axis_tvalid) in_frame <= 1'b1;

            if (flow_tlast && flow_tvalid && flow_tready) flow_in_frame <= 1'b0;
            else if (flow_tuser[0] && flow_tvalid && flow_tready) flow_in_frame <= 1'b1;
        end
        
        if (!s_axis_aresetn) malformed_frame <= 1'b0;
        else if (flow_in_tuser[0] && s_axis_tvalid && in_frame) malformed_frame <= 1'b1;
        
        if (!s_axis_aresetn) flow_malformed_frame <= 1'b0;
        else if (flow_tuser[0] && flow_tvalid && flow_tready && flow_in_frame) flow_malformed_frame <= 1'b1;
    end
    always @(posedge m_axis_aclk) flow_malformed_frame_rclk <= { flow_malformed_frame_rclk[0], flow_malformed_frame };    
    always @(posedge m_axis_aclk) malformed_frame_rclk <= { malformed_frame_rclk[0], malformed_frame };    

    // Out of width converter.
    // more frame tracking
    reg flow64_in_frame = 0;
    reg flow64_malformed_frame = 0;
    reg [1:0] flow64_malformed_frame_rclk = {2{1'b0}};
    
    
    `DEFINE_AXI4S_MIN_IF( flow64_ , 64);
    wire [7:0]            flow64_tuser_raw;
    // Coming out of the width converter, we have to qualify the tuser bits here.
    // So let's split them up.
    wire [3:0]            flow64_tuser_high = flow64_tuser_raw[7:4];
    wire [3:0]            flow64_tuser_low = flow64_tuser_raw[3:0];
    wire [7:0]            flow64_tkeep_raw;
    // Now qualify them.
    wire [7:0]            flow64_tuser_qual = { flow64_tuser_high & flow64_tkeep_raw[7:4], flow64_tuser_low & flow64_tkeep_raw[3:0] };
    
    
    // pack TKEEP to store for the error and control streams
    wire [4:0]            flow64_tuser = {  flow64_tkeep_raw[4], flow64_tkeep_raw[0],
                                            flow64_tuser_qual[2] || flow64_tuser_qual[6],
                                            flow64_tuser_qual[1] || flow64_tuser_qual[5],
                                            flow64_tuser_qual[0] || flow64_tuser_qual[4] };
    wire                  flow64_tlast;
    haic_width_converter u_widthconv( .aclk(s_axis_aclk),
                                      .aresetn(s_axis_aresetn),
                                      `CONNECT_AXI4S_MIN_IF( s_axis_ , flow_ ),
                                      .s_axis_tuser( flow_tuser_expanded ),
                                      .s_axis_tlast( flow_tlast ),
                                      `CONNECT_AXI4S_MIN_IF( m_axis_ , flow64_ ),
                                      .m_axis_tkeep( flow64_tkeep_raw ),
                                      .m_axis_tuser( flow64_tuser_raw ),
                                      .m_axis_tlast( flow64_tlast ));

    // track frames to find the bitch
    always @(posedge s_axis_aclk) begin
        if (!s_axis_aresetn) flow64_in_frame = 1'b0;
        else begin
            if (flow64_tlast && flow64_tvalid && flow64_tready) flow64_in_frame <= 1'b0;
            else if (flow64_tuser[0] && flow64_tvalid && flow64_tready) flow64_in_frame <= 1'b1;
        end
        
        if (!s_axis_aresetn) flow64_malformed_frame <= 1'b0;
        else if (flow64_tuser[0] && flow64_tvalid && flow64_tready && flow64_in_frame) flow64_malformed_frame <= 1'b1;
    end
    always @(posedge m_axis_aclk) flow64_malformed_frame_rclk <= { flow64_malformed_frame_rclk[0], flow64_malformed_frame };    

    
    // Cross clock.
    `DEFINE_AXI4S_MIN_IF(   flow64_sysclk_ , 64);
    wire [4:0]              flow64_sysclk_tuser;
    wire                    flow64_sysclk_tlast;
    
    reg sysclk_in_frame = 0;
    reg sysclk_malformed_frame = 0;
    
    haic_cc_fifo u_cc_fifo( .s_aclk(s_axis_aclk),.s_aresetn(s_axis_aresetn),
                            `CONNECT_AXI4S_MIN_IF( s_axis_ ,     flow64_ ),
                                                  .s_axis_tuser( flow64_tuser ),
                                                  .s_axis_tlast( flow64_tlast ),
                            .m_aclk(m_axis_aclk),
                            `CONNECT_AXI4S_MIN_IF( m_axis_ ,     flow64_sysclk_ ),
                                                  .m_axis_tuser( flow64_sysclk_tuser ),
                                                  .m_axis_tlast( flow64_sysclk_tlast ));
    always @(posedge m_axis_aclk) begin
        if (!m_axis_aresetn) sysclk_in_frame <= 1'b0;
        else begin
            if (flow64_sysclk_tlast && flow64_sysclk_tvalid && flow64_sysclk_tready) sysclk_in_frame <= 1'b0;
            else if (flow64_sysclk_tuser[0] && flow64_sysclk_tvalid && flow64_sysclk_tready) sysclk_in_frame <= 1'b1;
        end
        
        if (!m_axis_aresetn) sysclk_malformed_frame <= 1'b0;
        else if (flow64_sysclk_tuser[0] && flow64_sysclk_tvalid && flow64_sysclk_tready && sysclk_in_frame) sysclk_malformed_frame <= 1'b1;
    end
                                  
    // Out of v2 frame splitter.
    `DEFINE_AXI4S_MIN_IF(   split64_ , 64);
    wire [4:0]              split64_tuser;
    wire [1:0]              split64_tdest;
    wire                    split64_tlast;
    haic_frame_splitter_v2 u_frame_splitter( .aclk(m_axis_aclk),.aresetn(m_axis_aresetn),
                                                `CONNECT_AXI4S_MIN_IF( s_axis_ , flow64_sysclk_ ),
                                                .s_axis_tuser( flow64_sysclk_tuser ),
                                                .s_axis_tlast( flow64_sysclk_tlast ),
                                                `CONNECT_AXI4S_MIN_IF( m_axis_ , split64_ ),
                                                .m_axis_tuser( split64_tuser ),
                                                .m_axis_tlast( split64_tlast ),
                                                .m_axis_tdest( split64_tdest ) );    
    // sigh, continue plumbing
    reg split_in_frame = 0;
    reg split_malformed_frame = 0;
    always @(posedge m_axis_aclk) begin
        if (!m_axis_aresetn) begin
            split_in_frame <= 1'b0;
            split_malformed_frame <= 1'b0;
        end else begin
            if (split64_tlast && split64_tvalid && split64_tready) split_in_frame <= 1'b0;
            else if (split64_tuser[0] && split64_tvalid && split64_tready) split_in_frame <= 1'b1;
            
            if (split64_tuser[0] && split64_tvalid && split64_tready && split_in_frame) split_malformed_frame <= 1'b1;
        end
    end
        

    // Out of switch.
    wire [4:0]              ev64_tuser_raw;
    // Drop TKEEP. This pads event frames to 64-bits unconditionally. (They'll eventually be padded to 512-bits).
    assign                  m_axis_ev_tuser = ev64_tuser_raw[2:0];
    // Raw event data.
    wire [63:0]             ev64_tdata_raw;
    assign                  m_axis_ev_tdata[32 +: 32] = ev64_tuser_raw[4] ? ev64_tdata_raw[32 +: 32] : 32'd0;
    assign                  m_axis_ev_tdata[0 +: 32] = ev64_tdata_raw[0 +: 32];
    
    `DEFINE_AXI4S_MIN_IF(   stat64_ , 64);
    wire [4:0]              stat64_tuser_raw;
    // Embed TKEEP error.
    wire [2:0]              stat64_tuser = { stat64_tuser_raw[2] || (stat64_tuser_raw[4:3] != 2'b11),
                                             stat64_tuser_raw[1:0] };
    wire                    stat64_tlast;
    
    
    haic_stream_switch u_switch( .aclk(m_axis_aclk),.aresetn(m_axis_aresetn),
                                 `CONNECT_AXI4S_MIN_IF( s_axis_ , split64_ ),
                                 .s_axis_tuser( split64_tuser ),
                                 .s_axis_tlast( split64_tlast ),
                                 .s_axis_tdest( split64_tdest ),
                                 // not possible
                                 .s_decode_err(),
                                 .m_axis_tdata( { ev64_tdata_raw , stat64_tdata,  m_axis_err_tdata } ),
                                 .m_axis_tready( {m_axis_ev_tready, stat64_tready, m_axis_err_tready} ),
                                 .m_axis_tvalid( {m_axis_ev_tvalid, stat64_tvalid, m_axis_err_tvalid} ),
                                 .m_axis_tlast(  {m_axis_ev_tlast,  stat64_tlast,  m_axis_err_tlast}  ),
                                 .m_axis_tuser(  { ev64_tuser_raw,
                                                   stat64_tuser_raw,
                                                   m_axis_err_tuser } ));
    reg ev_in_frame = 0;
    reg ev_malformed_frame = 0;
    
    reg ev_seen_frame = 0;
    always @(posedge m_axis_aclk) begin
        if (!m_axis_aresetn) begin
            ev_in_frame <= 1'b0;
            ev_malformed_frame <= 1'b0;
            ev_seen_frame <= 1'b0;
        end else begin
            if (m_axis_ev_tlast && m_axis_ev_tvalid && m_axis_ev_tready) ev_in_frame <= 1'b0;
            else if (m_axis_ev_tuser[0] && m_axis_ev_tvalid && m_axis_ev_tready) ev_in_frame <= 1'b1;
            
            if (m_axis_ev_tuser[0] && m_axis_ev_tvalid && m_axis_ev_tready && ev_in_frame) ev_malformed_frame <= 1'b1;
            
            if (m_axis_ev_tuser[0] && m_axis_ev_tvalid && m_axis_ev_tready) ev_seen_frame <= 1'b1;
        end
    end    


    // jam_disable needs a local register. The jam count is internally registered by the C register in the DSP.
    always @(posedge m_axis_aclk) if (m_update_i) jam_disable <= jam_disable_i;
    // jam is sticky until reset
    always @(posedge m_axis_aclk) if (!m_axis_aresetn) jammed <= 1'b0; else if (ev_jam_delay_reached || stat_jam_delay_reached) jammed <= 1'b1;
    assign jammed_o = jammed;
    // Need two jam counters, one for event path, one for status path. Error path doesn't need it.    
    dsp_counter_terminal_count #(.RESET_TCOUNT_AT_RESET("FALSE")) u_ev_jam_counter(.clk_i(m_axis_aclk),
                                             .rst_i(!m_axis_aresetn || m_axis_ev_tready || jam_disable),
                                             .count_i(!m_axis_ev_tready && m_axis_ev_tvalid),
                                             .tcount_i(jam_delay_i),
                                             .update_tcount_i(m_update_i),
                                             .tcount_reached_o(ev_jam_delay_reached));
    dsp_counter_terminal_count #(.RESET_TCOUNT_AT_RESET("FALSE")) u_stat_jam_counter(.clk_i(m_axis_aclk),
                                            .rst_i(!m_axis_aresetn || stat64_tready || jam_disable),
                                            .count_i(!stat64_tready && stat64_tvalid),
                                            .tcount_i(jam_delay_i),
                                            .update_tcount_i(m_update_i),
                                            .tcount_reached_o(stat_jam_delay_reached));

    // jam_disable needs a local register. The jam count is internally registered by the C register in the DSP.
    always @(posedge s_axis_aclk) begin
        if (s_update_i) stuck_disable <= stuck_disable_i;
        // stuck is sticky until reset
        if (!s_axis_aresetn) stuck <= 1'b0; else if (stuck_delay_reached) stuck <= 1'b1;
        
        if (!s_axis_aresetn)
            stuck_count <= 1'b0;
        else if (s_axis_tvalid) begin
            stuck_count <= ~s_axis_tlast;
        end        
    end
    assign stuck_o = stuck;

    dsp_counter_terminal_count #(.RESET_TCOUNT_AT_RESET("FALSE")) u_stuck_counter(.clk_i(s_axis_aclk),
                                             .rst_i(!s_axis_aresetn || !stuck_count || stuck_disable),
                                             .count_i(stuck_count),
                                             .tcount_i(stuck_delay_i),
                                             .update_tcount_i(s_update_i),
                                             .tcount_reached_o(stuck_delay_reached));
    

    haic_status_fifo u_status_fifo( .s_aclk(m_axis_aclk),.s_aresetn(m_axis_aresetn),
                    `CONNECT_AXI4S_MIN_IF( s_axis_ ,    stat64_ ),
                                          .s_axis_tuser(stat64_tuser ),
                                          .s_axis_tlast(stat64_tlast ),
                    `CONNECT_AXI4S_MIN_IF( m_axis_ ,    m_axis_st_ ),
                                          .m_axis_tuser(m_axis_st_tuser ),
                                          .m_axis_tlast(m_axis_st_tlast ));

    assign extra_error_o[0] = malformed_frame_rclk[1];
    assign extra_error_o[1] = flow_malformed_frame_rclk[1];
    assign extra_error_o[2] = flow64_malformed_frame_rclk[1];
    assign extra_error_o[3] = sysclk_malformed_frame;
    assign extra_error_o[4] = split_malformed_frame;
    assign extra_error_o[5] = ev_malformed_frame;
    // reserve
    assign extra_error_o[6] = 1'b0;
    // guarantee things are working
    assign extra_error_o[7] = ev_seen_frame;
    
endmodule
