`timescale 1ns / 1ps
// I originally started off making a Mega Huge event builder setup but realized
// I want to rip out the "basically AXI4-Stream only" and the main interface stuff.
// So this wraps 'em.

// FOUR CLOCK DOMAINS WOOOO
`include "interfaces.vh"
`define NO_PREFIX_TAG(x)

// v4 just has some minor changes to use the standardized interfaces.vh.
module event_builder_wrap_v4 #(
        parameter NUM_LINKS = 8,
        parameter COMPLETE_IN = 64,
        parameter DEBUG_OUT = 64,
        parameter DONE_OUT = 32,
        parameter WIDTH_IN = 512,
        parameter EVENT_OUT = 256,
        parameter DEBUG = "TRUE"
        )(
        // Combined interface path.
        input clk,
        input reset,
        `TARGET_NAMED_PORTS_COMBINED_IF( `NO_PREFIX_TAG(dummy) ),
        // Output event path.        
        input dclk,
        input dreset,
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_event_ , EVENT_OUT ),
        output m_event_tlast,
        output dma_en_o,
         
        output track_event_o,
         
        // ACLK path.
        input aclk,
        input aresetn,
        // completion streams in
        input [COMPLETE_IN*NUM_LINKS-1:0] s_axis_cmpl_tdata,
        input [NUM_LINKS-1:0] s_axis_cmpl_tvalid,
        output [NUM_LINKS-1:0] s_axis_cmpl_tready,
        // done streams out
        output [DONE_OUT*NUM_LINKS-1:0] m_axis_done_tdata,
        output [NUM_LINKS-1:0] m_axis_done_tvalid,
        input [NUM_LINKS-1:0] m_axis_done_tready,
        // command path to datamover
        output [71:0] mm2s_cmd_tdata,
        output        mm2s_cmd_tvalid,
        input         mm2s_cmd_tready,
        // status path from datamover
        input [7:0]  mm2s_sts_tdata,
        input        mm2s_sts_tvalid,
        output       mm2s_sts_tready,
        // Debug output
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_axis_dbg_ , 64),
        output      m_axis_dbg_tlast,
                
        // MEMCLK path.
        input memclk,
        input memresetn,
        input [WIDTH_IN-1:0] s_axis_tdata,
        input                s_axis_tvalid,
        input                s_axis_tlast,
        output               s_axis_tready        
    );
    
    
    (* ASYNC_REG = "TRUE" *)
    reg [1:0] ctrl_reset = {2{1'b0}};
    always @(posedge aclk) ctrl_reset <= {ctrl_reset[0], reset};    
    // god I hate this. poorly specified interfaces can go bite me
    `DEFINE_AXI4L_IF( swaxi_ , 16, 64 );
    // I'm going to expand this into a register core in a bit
    // this is for simplicity, it's programmed as "final stream" so it's
    // really ~(1 << (final_stream+1))-1
    // 0 = 1 => 1111_1110
    // 1 = 3 => 1111_1100
    // 2 = 7 => 1111_1000
    // etc.
    // Note that this also prevents someone from totally disabling stuff, which
    // would, uh, never work.
    wire [NUM_LINKS-1:0] link_mask;
    
    // Current links showing valid. Only makes sense if you stall.
    wire [NUM_LINKS-1:0] current_valid;
    // Current event tag. Only makes sense if you stall.
    wire [7:0] current_tag;
    
    // detector config
    wire [15:0]          detector_config;
    wire                 dma_en;
    wire                 event_tdest;
    ebrc_v3 u_ebrc( .clk(clk),.reset(reset),.aclk(aclk),
                    .current_valid_i(current_valid),
                    .current_tag_i(current_tag),
                    .link_mask_o(link_mask),
                    .detector_config_o(detector_config),
                    .dma_en_o(dma_en_o),
                    .event_tdest_o(event_tdest),
                    .track_event_o(track_event_o),
                    `CONNECT_COMBINED_IF( `NO_PREFIX_TAG(dummy), `NO_PREFIX_TAG(dummy) ),
                    `CONNECT_AXI4L_IF( m_axi_ , swaxi_ ) );

    // Pull the completion tags into a vector
    `DEFINE_AXI4S_MIN_IFV( cmplv_ , COMPLETE_IN, [NUM_LINKS-1:0] );
    // Outputs from the reordering switch
    `DEFINE_AXI4S_MIN_IFV( complete_fr_ , COMPLETE_IN, [NUM_LINKS-1:0] );
    // And devectored.
    wire [COMPLETE_IN*NUM_LINKS-1:0] complete_tags_tdata;
    wire [NUM_LINKS-1:0] complete_tags_tvalid;
    wire [NUM_LINKS-1:0] complete_tags_tready;
        
    generate
        genvar i;
        for (i=0;i<NUM_LINKS;i=i+1) begin : VEC
            // vectorize...
            assign cmplv_tdata[i] = s_axis_cmpl_tdata[COMPLETE_IN*i +: COMPLETE_IN];
            assign cmplv_tvalid[i] = s_axis_cmpl_tvalid[i];
            assign s_axis_cmpl_tready[i] = cmplv_tready[i];
            // devectorize
            assign complete_tags_tdata[ COMPLETE_IN*i +: COMPLETE_IN ] = complete_fr_tdata[i];
            assign complete_tags_tvalid[ i ] = complete_fr_tvalid[i];
            assign complete_fr_tready[i] = complete_tags_tready[i];
        end
    endgenerate
    
    // This is the programmable switch for the completion tags. They define the
    // event order.
    eb_cmplswitch u_switch( .aclk(aclk), .aresetn( aresetn ),
                             .ctrl_aresetn(!ctrl_reset[1]),
                             .clk(clk),.resetn(!reset),
                             `CONNECT_AXI4L_IF(s_axi_ , swaxi_ ),
                             // dorks actually use ARPROT/AWPROT
                             .s_axi_arprot( 3'b000 ),
                             .s_axi_awprot( 3'b000 ),
                             `CONNECT_AXI4S_MIN_IFV( s0_axis_ ,cmplv_ , [0] ),
                             `CONNECT_AXI4S_MIN_IFV( s1_axis_ ,cmplv_ , [1] ),
                             `CONNECT_AXI4S_MIN_IFV( s2_axis_ ,cmplv_ , [2] ),
                             `CONNECT_AXI4S_MIN_IFV( s3_axis_ ,cmplv_ , [3] ),
                             `CONNECT_AXI4S_MIN_IFV( s4_axis_ ,cmplv_ , [4] ),
                             `CONNECT_AXI4S_MIN_IFV( s5_axis_ ,cmplv_ , [5] ),
                             `CONNECT_AXI4S_MIN_IFV( s6_axis_ ,cmplv_ , [6] ),
                             `CONNECT_AXI4S_MIN_IFV( s7_axis_ ,cmplv_ , [7] ),
                             // aaugh all the goddamn tdests are pointless too
                             // but needed for simulation
                             .s0_axis_tdest( 3'h0 ),
                             .s1_axis_tdest( 3'h0 ),
                             .s2_axis_tdest( 3'h0 ),
                             .s3_axis_tdest( 3'h0 ),
                             .s4_axis_tdest( 3'h0 ),
                             .s5_axis_tdest( 3'h0 ),
                             .s6_axis_tdest( 3'h0 ),
                             .s7_axis_tdest( 3'h0 ),                             
                             `CONNECT_AXI4S_MIN_IFV( m0_axis_ ,complete_fr_, [0] ),
                             `CONNECT_AXI4S_MIN_IFV( m1_axis_ ,complete_fr_, [1] ),
                             `CONNECT_AXI4S_MIN_IFV( m2_axis_ ,complete_fr_, [2] ),
                             `CONNECT_AXI4S_MIN_IFV( m3_axis_ ,complete_fr_, [3] ),
                             `CONNECT_AXI4S_MIN_IFV( m4_axis_ ,complete_fr_, [4] ),
                             `CONNECT_AXI4S_MIN_IFV( m5_axis_ ,complete_fr_, [5] ),
                             `CONNECT_AXI4S_MIN_IFV( m6_axis_ ,complete_fr_, [6] ),
                             `CONNECT_AXI4S_MIN_IFV( m7_axis_ ,complete_fr_, [7] )
                             );
    // Event builder spits out the event stream.
    event_builder_v3 u_builder( .dclk(dclk),.dreset(dreset),
                                `CONNECT_AXI4S_MIN_IF( m_ev_ , m_event_ ),
                                .m_ev_tlast(m_event_tlast),
                                
                                .aclk(aclk),
                                .aresetn(aresetn),
                                `CONNECT_AXI4S_MIN_IF( s_axis_cmpl_ , complete_tags_ ),
                                `CONNECT_AXI4S_MIN_IF( m_axis_done_ , m_axis_done_ ),
                                `CONNECT_AXI4S_MIN_IF( mm2s_cmd_ , mm2s_cmd_ ),
                                `CONNECT_AXI4S_MIN_IF( mm2s_sts_ , mm2s_sts_ ),
                                
                                .memclk(memclk),
                                .memresetn(memresetn),
                                `CONNECT_AXI4S_MIN_IF( s_axis_ , s_axis_ ),
                                .s_axis_tlast(s_axis_tlast),
                                
                                `CONNECT_AXI4S_MIN_IF( m_axis_dbg_ , m_axis_dbg_ ),
                                .m_axis_dbg_tlast(m_axis_dbg_tlast),
                                
                                .event_tdest_i(event_tdest),
                                .link_mask_i(link_mask),
                                .current_valid_o(current_valid),
                                .current_tag_o(current_tag),
                                .detector_config_i(detector_config));                            
        
    generate
        if (DEBUG == "TRUE") begin : DBG
            ebv3_ila u_ila(.clk(aclk),
                           .probe0( m_axis_dbg_tdata ),
                           .probe1( m_axis_dbg_tready ),
                           .probe2( m_axis_dbg_tvalid ),
                           .probe3( m_axis_dbg_tlast ));
        end
    endgenerate
    
endmodule
