`timescale 1ns / 1ps

`include "interfaces.vh"

`define NO_PREFIX_TAG( x )

// This now abstracts out a lot of the master merger interface to allow
// it to port between devices. In order to do this we have to separate
// out the event storage/building and the xilly interfaces.
//
// Functionally what this means is that the frame memory network is 
// now *outside* this module. This allows for us to virtualize it via
// a buffer implemented in software for devices lacking memory
// (which is fine, they won't really be running high rate anyway).
//
// For the virtualized FMN, the Xillybus interface adds outbound
// streams for each lane along with a single outbound control path
// (which just transmits the lane number and length in one word).
// Then it also has an outbound command path and an inbound status
// path as well as an inbound event path.
//
// So it's 8 outbound streams (only 4 have basically any buffering),
// 1 outbound frame control stream (multiplexed between all) - 
// 1 outbound event request stream
// 1 inbound event status stream
// 1 inbound event path
// The virtual FMN module handles all of the mapping and reduction.
module mmerger_xilly_core #(parameter NUM_LANES=8,
                            parameter WIDTH_OUT=64,
                            parameter WIDTH_DONE=32,
                            parameter WIDTH_CMPL=64,
                            parameter WIDTH_CMD=72,
                            parameter WIDTH_STS=8,
                            parameter WIDTH_EVENT=512,
                            parameter [31:0] IDENT="MMRG",
                            parameter [31:0] DATEVERSION={32{1'b0}},
                            parameter DEBUG_XILREG="TRUE")(
        // internal register clock and reset
        input           register_clk,
        input           register_reset,
        // register path from xillybus
        input           xilclk,
    
        `TARGET_NAMED_PORTS_XIL_ADDRESSED( mm_ , 32, 64 ),

//        `TARGET_NAMED_PORTS_XIL_ADDRESSED( mm_ , 32, 64 ),        
//        input           mm_rden,
//        input           mm_wren,
//        input           mm_rdopen,
//        input           mm_wropen,
//        input [31:0]    mm_addr,
//        input           mm_addr_update,
//        input [63:0]    mm_data_in,
//        output [63:0]   mm_data_out,        
//        output          mm_full,
//        output          mm_empty,
//        output          mm_eof,
        // Xillybus event path

        `TARGET_NAMED_PORTS_XIL_TOHOST( mm_event_ , 256 ),        
//        output [255:0]  mm_event,
//        output          mm_event_empty,
//        output          mm_event_eof,
//        input           mm_event_ready,
//        input           mm_event_open,

        // Xillybus event waiting path
        `TARGET_NAMED_PORTS_XIL_TOHOST( mm_event_waiting_ , 32 ),        
//        output [31:0]   mm_event_waiting,
//        output          mm_event_waiting_empty,
//        output          mm_event_waiting_eof,
//        input           mm_event_waiting_read,
//        input           mm_event_waiting_open,        

        // stream path from xillybus
        `TARGET_NAMED_PORTS_XIL_FROMHOSTADDR( mm_stream_ , 5, 64 ),
//        input [63:0]    mm_stream,
//        input [4:0]     mm_stream_addr,
//        input           mm_stream_addr_update,
//        input           mm_stream_write,
//        output          mm_stream_full,
//        input           mm_stream_open,

        // status path to xillybus
        `TARGET_NAMED_PORTS_XIL_TOHOST( mm_stream_out_ , 64 ),
//        output [63:0]   mm_stream_out,
//        output          mm_stream_out_empty,
//        output          mm_stream_out_eof,
//        input           mm_stream_out_read,
//        input           mm_stream_out_open,
        // pending status path data
        `TARGET_NAMED_PORTS_XIL_TOHOST( mm_stream_out_waiting_ , 32 ),


        // debug path to xillybus
        `TARGET_NAMED_PORTS_XIL_TOHOST( mm_debug_ , 64 ),
//        output [63:0]   mm_debug,
//        output          mm_debug_empty,
//        output          mm_debug_eof,
//        input           mm_debug_read,
//        input           mm_debug_open,
                
// FIGURE THIS OUT
//    // status stream waitings
//    reg [31:0]  mm_stream_out_waiting;
    
        // GTP stuff. The SFP crap is outside of here.
        input   init_clk,
        input   gtp_clk_p,
        input   gtp_clk_n,
        input   [NUM_LANES-1:0] gtp_rx_n,
        input   [NUM_LANES-1:0] gtp_rx_p,
        output  [NUM_LANES-1:0] gtp_tx_n,
        output  [NUM_LANES-1:0] gtp_tx_p,        
        // link status (rclk)
        output  [7:0] link_status_o,

        ///// FMB INTERFACE
        // We segregate out the FMB so now we need all the AXI4-Stream paths over there.

        // This is now the path to the FMB.
        input memclk,
        input memresetn,
        output aclk,
        output aresetn,
        // Status lines.
        input going_full_i,
        output track_event_o,
        // Don't have a way to do arrayed interfaces yet, sigh.
        output [NUM_LANES*WIDTH_OUT-1:0]    m_fmb_tdata,
        output [NUM_LANES-1:0]              m_fmb_tvalid,
        input [NUM_LANES-1:0]               m_fmb_tready,
        output [3*NUM_LANES-1:0]            m_fmb_tuser,
        output [NUM_LANES-1:0]              m_fmb_tlast,
        
        // And the done to FMB/completions from the FMB...
        input [NUM_LANES*WIDTH_CMPL-1:0]    s_cmpl_tdata,
        input [NUM_LANES-1:0]               s_cmpl_tvalid,
        output [NUM_LANES-1:0]              s_cmpl_tready,
        output [NUM_LANES*WIDTH_DONE-1:0]   m_done_tdata,
        output [NUM_LANES-1:0]              m_done_tvalid,
        input [NUM_LANES-1:0]               m_done_tready,

        // command to FMB/status from FMB...
        `HOST_NAMED_PORTS_AXI4S_MIN_IF(     m_cmd_ , WIDTH_CMD ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF(   s_sts_ , WIDTH_STS ),
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF(   s_event_ , WIDTH_EVENT ),
        input                               s_event_tlast
    );
    
    // width of data going into Aurora core
    localparam WIDTH_IN = 16;

    localparam MEM_OUT = WIDTH_EVENT;

    // sigh, naming stupidity
    wire xil_clk = xilclk;

    // check this
    wire interface_not_ready;
    
    // register access
    // the Xilly register access path has 11 signals
    assign mm_eof = 1'b0;
    
    

// Xilly is UPSTREAM of this.
//    (* KEEP = "TRUE" *)
//    FD #(.INIT(1'b0)) u_clkrun(.D(1'b1),.C(xil_clk),.Q(LED_USER[4]));
        
//    xillybus u_xilly( .PCIE_TX_P(PCIE_TX_P),
//                      .PCIE_TX_N(PCIE_TX_N),
//                      .PCIE_RX_P(PCIE_RX_P),
//                      .PCIE_RX_N(PCIE_RX_N),
//                      .PCIE_REFCLK_P(CLK_PCIE_FPGA_IN_P),
//                      .PCIE_REFCLK_N(CLK_PCIE_FPGA_IN_N),
//                      .PCIE_PERST_B_LS(RSTN_PERSTN_FINGERS_FPGA),
//                      .bus_clk(xil_clk),
//                      .quiesce(interface_not_ready),
//                      .GPIO_LED(LED_USER[3:0]),
                      
//                      // address space (11 signals) 
//                      .user_r_mm_registers_data(mm_rddata),
//                      .user_w_mm_registers_data(mm_wrdata),
//                      .user_r_mm_registers_empty(mm_empty),
//                      .user_r_mm_registers_eof(mm_eof),
//                      .user_w_mm_registers_full(mm_full),
//                      .user_mm_registers_addr(mm_addr),
//                      .user_r_mm_registers_open(mm_rdopen),
//                      .user_w_mm_registers_open(mm_wropen),
//                      .user_mm_registers_addr_update(mm_addr_update),
//                      .user_w_mm_registers_wren(mm_wren),
//                      .user_r_mm_registers_rden(mm_rden),
                      
//                      // stream in (control)
//                      .user_w_mm_stream_in_data(mm_stream),
//                      .user_mm_stream_in_addr(mm_stream_addr),
//                      .user_mm_stream_in_addr_update(mm_stream_addr_update),
//                      .user_w_mm_stream_in_wren(mm_stream_write),
//                      .user_w_mm_stream_in_full(mm_stream_full),
//                      .user_w_mm_stream_in_open(mm_stream_open),
                      
//                      // stream out (status)
//                      .user_r_mm_stream_out_data(mm_stream_out),
//                      .user_r_mm_stream_out_rden(mm_stream_out_read),
//                      .user_r_mm_stream_out_eof(mm_stream_out_eof),
//                      .user_r_mm_stream_out_empty(mm_stream_out_empty),
//                      .user_r_mm_stream_out_open(mm_stream_out_open),
                      
//                      // stream out waiting
//                      .user_r_mm_stream_out_waiting_data( mm_stream_out_waiting ),
//                      .user_r_mm_stream_out_waiting_rden(),
//                      .user_r_mm_stream_out_waiting_empty( 1'b0 ),
//                      .user_r_mm_stream_out_waiting_open(),
//                      .user_r_mm_stream_out_waiting_eof(1'b0),
                      
//                      // debug out
//                      .user_r_mm_debug_out_data(mm_debug),
//                      .user_r_mm_debug_out_rden(mm_debug_read),
//                      .user_r_mm_debug_out_eof(mm_debug_eof),
//                      .user_r_mm_debug_out_empty(mm_debug_empty),
//                      .user_r_mm_debug_out_open(mm_debug_open),
                      
//                      // event out
//                      .user_r_mm_event_out_data(mm_event),
//                      .user_r_mm_event_out_rden(mm_event_read),
//                      .user_r_mm_event_out_eof(mm_event_eof),
//                      .user_r_mm_event_out_empty(mm_event_empty),
//                      .user_r_mm_event_out_open(mm_event_open),
                      
//                      // event waiting
//                      .user_r_mm_event_waiting_data(mm_event_waiting),
//                      .user_r_mm_event_waiting_rden(mm_event_waiting_read),
//                      .user_r_mm_event_waiting_eof(mm_event_waiting_eof),
//                      .user_r_mm_event_waiting_empty(mm_event_waiting_empty),
//                      .user_r_mm_event_waiting_open(mm_event_waiting_open));

    // The original space split up in 20-bit chunks
    // 0x000000 Dini stuff (we'll implement our own stuff here later)
    // 0x100000 ARC (identical)
    // 0x200000 Debug
    // 0x300000 Stream
    // 0x400000 EBRC (identical)
    //
    // The stream block goes to never-never land at this point, it's pointless. Stream outs
    // use an lseek to point to the correct link, and read stream_waiting to discover the amount of data waiting.
    // There are no registers involved at all at this point. I might add some later.
    //
    // The debug core is dramatically simplified:
    // 0x0: LINKALLOW - 9-bit value indicating which link is allowed to send data. This is write-only - each write allows 1 frame.
    //                  Bit 31 resets the allow in case no data is received.
    // 0x8: WAITING - 32-bit value indicating how much data is available to read at userland.
    //
    // So to split up the address space here we just grab bits [22:20] and qualify
    // register_write_enable
    // register_read_enable
    // interface_ready
    // register_read_data_valid
    

    `DEFINE_COMBINED_IF( xilly_ );
    // now the unmuxed guys
    wire [63:0] xilly_register_read_data_unmuxed[7:0];
    wire [7:0] xilly_interface_ready_unmuxed;
    wire [7:0] xilly_register_read_data_valid_unmuxed;
    wire [7:0] xilly_register_read_data_tag_unmuxed;
    
    assign xilly_register_read_data = xilly_register_read_data_unmuxed[ xilly_register_read_address[22:20] ];
    assign xilly_register_read_data_valid = xilly_register_read_data_valid_unmuxed[ xilly_register_read_address[22:20] ];
    assign xilly_interface_ready = xilly_interface_ready_unmuxed[ xilly_register_read_address[22:20] ];        
    assign xilly_register_read_data_tag = xilly_register_read_data_tag_unmuxed[ xilly_register_read_address[22:20] ];

    `DEFINE_COMBINED_IF( config_ );
    `DEFINE_COMBINED_IF( aurora_ );
    `DEFINE_COMBINED_IF( stream_ );
    `DEFINE_COMBINED_IF( debug_ );
    `DEFINE_COMBINED_IF( eb_ );
    
    `define MAP_COMBINED_IF( host , target, addr ) \
        assign host``interface_ready_unmuxed[ addr ] = target``interface_ready; \
        assign target``register_write_address = { {12{1'b0}}, host``register_write_address[19:0] };                             \
        assign target``register_write_data = host``register_write_data; \
        assign target``register_write_be = host``register_write_be; \
        assign target``register_write_enable = host``register_write_enable && (host``register_write_address[22:20] == addr);    \
        assign target``register_read_address = { {12{1'b0}}, host``register_read_address[19:0] };                               \
        assign target``register_request_tag = host``register_request_tag; \
        assign target``register_read_enable = host``register_read_enable && (host``register_read_address[22:20] == addr);       \
        assign host``register_read_data_unmuxed[ addr ] = target``register_read_data; \
        assign host``register_read_data_tag_unmuxed[ addr ] = target``register_read_data_tag; \
        assign host``register_read_data_valid_unmuxed[ addr ] = target``register_read_data_valid

    `define SHADOW_COMBINED_IF( host , shadow_addr , real_addr ) \
        assign host``register_read_data_unmuxed[ shadow_addr ] = host``register_read_data_unmuxed[ real_addr ] ; \
        assign host``register_read_data_tag_unmuxed[ shadow_addr ] = host``register_read_data_tag_unmuxed[ real_addr ] ; \
        assign host``register_read_data_valid_unmuxed[ shadow_addr ] = host``register_read_data_valid_unmuxed[ real_addr ] ; \
        assign host``interface_ready_unmuxed[ shadow_addr ] = host``interface_ready_unmuxed[ real_addr ]

    // kills from a target side
    `define KILL_COMBINED_IF( name ) \
        assign name``register_read_data_valid = 1'b1; \
        assign name``register_read_data_tag = {8{1'b0}}; \
        assign name``register_read_data = {64{1'b0}} ; \
        assign name``interface_ready = 1'b1

    `MAP_COMBINED_IF( xilly_ , config_ , 0);        
    `MAP_COMBINED_IF( xilly_ , aurora_ , 1);
    `MAP_COMBINED_IF( xilly_ , debug_ , 2);
    `MAP_COMBINED_IF( xilly_ , stream_ , 3);
    `MAP_COMBINED_IF( xilly_ , eb_ , 4);        
    `SHADOW_COMBINED_IF( xilly_ , 5, 1);
    `SHADOW_COMBINED_IF( xilly_ , 6, 2);
    `SHADOW_COMBINED_IF( xilly_ , 7, 3);
    
    `KILL_COMBINED_IF( config_ );
    `KILL_COMBINED_IF( stream_ );

    
   // Generate the register (and aclk) clocks
   // We run these at 160 MHz (which is actually faster than the 100 MHz on the
   // Darklite impl!)
   
   
//    wire register_clk;
//    wire register_clk_lock;
//    wire register_reset = !register_clk_lock;    
//    xilly_rclk_wiz u_rclk(.clk_in1(init_clk),.reset(1'b0),.clk_out1(register_clk),.locked(register_clk_lock));
        
    mega_debug_ila u_regila( .clk(register_clk),
                             .probe0( xilly_register_write_address[0 +: 23] ),
                             .probe1( xilly_register_read_address[0 +: 23] ),
                             .probe2( xilly_register_write_data ),
                             .probe3( xilly_register_read_data ),
                             .probe4( xilly_register_read_enable ),
                             .probe5( xilly_register_write_enable ),
                             .probe6( xilly_register_read_data_valid_unmuxed ),
                             .probe7( xilly_interface_ready_unmuxed ),
                             .probe8( register_reset ),
                             .probe9( xilly_register_write_be ));
                             
        
   xilly_to_combined_cc u_xtoc( .clk(register_clk),
                                 .xilclk(xil_clk),
                              .sk_data_in( mm_wrdata ),
                              .sk_data_out( mm_rddata ),
                              .sk_addr(mm_addr),
                              .sk_rden(mm_rden),
                              .sk_wren(mm_wren),
                              .sk_update(mm_addr_update),
                              .sk_wropen(mm_wropen),
                              .sk_rdopen(mm_rdopen),
                              .sk_full(mm_full),
                              .sk_empty(mm_empty),
                              `CONNECT_COMBINED_IF( `NO_PREFIX_TAG(dummy), xilly_ ));
    
    
    
    `DEFINE_AXI4S_MIN_IF( ctrl_ , WIDTH_IN );
    wire ctrl_tlast;
    wire [2:0] ctrl_tdest;
        
    `DEFINE_AXI4S_MIN_IF( stat_ , WIDTH_OUT );
    wire stat_tlast;

    // The FMB is now external, so assign these out. Keep the name the same to simplify.
    wire [NUM_LANES*WIDTH_OUT-1:0]  fmb_tdata;
    wire [NUM_LANES-1:0]            fmb_tvalid;
    wire [NUM_LANES-1:0]            fmb_tready;
    wire [NUM_LANES-1:0]            fmb_tlast;
    wire [3*NUM_LANES-1:0]          fmb_tuser;
    assign m_fmb_tdata = fmb_tdata;
    assign m_fmb_tvalid = fmb_tvalid;
    assign fmb_tready = m_fmb_tready;
    assign m_fmb_tlast = fmb_tlast;
    assign m_fmb_tuser = fmb_tuser;


    wire [NUM_LANES*WIDTH_DONE-1:0] done_tdata;
    wire [NUM_LANES-1:0]            done_tvalid;
    wire [NUM_LANES-1:0]            done_tready;
    assign m_done_tdata = done_tdata;
    assign m_done_tvalid = done_tvalid;
    assign done_tready = m_done_tready;

    wire [NUM_LANES*WIDTH_CMPL-1:0] complete_tdata;
    wire [NUM_LANES-1:0]            complete_tvalid;
    wire [NUM_LANES-1:0]            complete_tready;    
    assign complete_tdata = s_cmpl_tdata;
    assign complete_tvalid = s_cmpl_tvalid;
    assign s_cmpl_tready = complete_tready;

    // Debug readout path back from builder.
    `DEFINE_AXI4S_MIN_IF( evdbg_ , WIDTH_OUT);
    wire                            evdbg_tlast;
    
    // And the frame DMA path to debug readout.
    `DEFINE_AXI4S_MIN_IF( debug_rx_ , WIDTH_OUT);
    wire [2:0] debug_rx_tuser;
    wire       debug_rx_tlast;

    // Event/complete/done path to builder.
    // Here we keep the same internal name and hook it to the external.
    // SINGLE LINK from FMN to EB
    `DEFINE_AXI4S_MIN_IF( event_ , MEM_OUT );
    wire                event_tlast;    
    assign event_tdata = s_event_tdata;
    assign event_tvalid = s_event_tvalid;
    assign event_tlast = s_event_tlast;
    assign s_event_tready = event_tready;
    
    
    // Command path to FMN readout.
    // Again, external, but same name.
    `DEFINE_AXI4S_MIN_IF( mm2s_cmd_ , 72);
    assign m_cmd_tdata = mm2s_cmd_tdata;
    assign m_cmd_tvalid = mm2s_cmd_tvalid;
    assign mm2s_cmd_tready = m_cmd_tready;
        
    // Status path from FMN readout.
    // See above.
    `DEFINE_AXI4S_MIN_IF( mm2s_sts_ , 8);
    assign mm2s_sts_tdata = s_sts_tdata;
    assign mm2s_sts_tvalid = s_sts_tvalid;
    assign s_sts_tready = mm2s_sts_tready;

    // Event streamer out.
    wire evstream_enable;
    `DEFINE_AXI4S_MIN_IF( evstream_ , 256 );
    wire evstream_tlast;
    wire dclk = xil_clk;
    wire xil_areset;
    wire dreset = xil_areset;
    
    xilclk_areset u_xil_reset(.aclk(aclk),.aresetn(aresetn),.xilclk(xil_clk),.xilreset(xil_areset));

    // Control/status streams.
    wire [8:0] req_suppress;    
    xilly_stream_inout u_ctrlstat( .aclk(aclk),.aresetn(aresetn),
                                   .xil_clk(xil_clk),
                                   `CONNECT_AXI4S_MIN_IF( m_axis_ , ctrl_ ),
                                   .m_axis_tlast( ctrl_tlast ),
                                   .m_axis_tdest( ctrl_tdest ),
                                   `CONNECT_AXI4S_MIN_IF( s_axis_ , stat_ ),
                                   .s_axis_tlast( stat_tlast ),
                                   .stream_data( mm_stream_data ),
                                   .stream_addr( mm_stream_addr ),
                                   .stream_addr_update( mm_stream_addr_update ),
                                   .stream_write( mm_stream_wren ),
                                   .stream_full( mm_stream_full ),
                                   .stream_open( mm_stream_open),
                                   
                                   .stream_out_data( mm_stream_out_data ),
                                   .stream_out_empty( mm_stream_out_empty ),
                                   .stream_out_read( mm_stream_out_rden ),
                                   .stream_out_open( mm_stream_out_open ),
                                   .stream_out_waiting( mm_stream_out_waiting_data ));                                                                  
    // no EOF
    assign mm_stream_out_eof = 1'b0;
    // stream out waiting just provides static data.
    assign mm_stream_out_waiting_empty = 1'b0;
    assign mm_stream_out_waiting_eof = 1'b0;

    // Debug readout path.
    xilly_debug_readout u_dbg( .aclk(aclk),
                               .xil_clk(xil_clk),
                               .rclk(register_clk),
                               .aresetn(aresetn),
                               .rreset(register_reset),
                               `CONNECT_COMBINED_IF( `NO_PREFIX_TAG(dummy), debug_ ),
                               
                               `CONNECT_AXI4S_MIN_IF( s_axis_ , debug_rx_ ),
                               .s_axis_tlast(debug_rx_tlast),
                               .s_axis_tuser(debug_rx_tuser),
                               .req_suppress(req_suppress),
                               
                               .debug_data( mm_debug_data ),
                               .debug_empty( mm_debug_empty ),
                               .debug_read( mm_debug_rden ),
                               .debug_open( mm_debug_open ) );                               
    assign mm_debug_eof = 1'b0;

    xilly_event_streamer u_evstream( .clk(xil_clk),.reset(xil_areset),
                                `CONNECT_AXI4S_MIN_IF( s_axis_ , evstream_ ),
                                .s_axis_tlast(evstream_tlast),
                                
                                .enable_i(evstream_enable),
                                
                                .event_open( mm_event_open ),
                                .event_data( mm_event_data ),
                                .event_empty( mm_event_empty ),
                                .event_read( mm_event_rden ),
                                
                                .waiting_open( mm_event_waiting_open ),
                                .waiting_data( mm_event_waiting_data ),
                                .waiting_empty( mm_event_waiting_empty ),
                                .waiting_read( mm_event_waiting_rden ));
    // no EOFs
    assign mm_event_eof = 1'b0;
    assign mm_event_waiting_eof = 1'b0;
                                                                   
    wire going_full;
    assign going_full = going_full_i;
                      
    // Merge v3 drops the QSFP crap and moves it outside.
    aurora_merge_v3 #(.IDENT(IDENT),.DATEVERSION(DATEVERSION)) u_aurora( .init_clk(init_clk),
                           .rclk(register_clk),.rreset(register_reset),
                           
                           .going_full(going_full),
                           
                           `CONNECT_COMBINED_IF( `NO_PREFIX_TAG(dummy), aurora_ ),

                           `CONNECT_AXI4S_MIN_IF( s_axis_ctrl_ , ctrl_ ),
                           .s_axis_ctrl_tlast( ctrl_tlast ),
                           .s_axis_ctrl_tdest( ctrl_tdest ),

                           `CONNECT_AXI4S_MIN_IF( m_axis_stat_ , stat_ ),                           
                           .m_axis_stat_tlast( stat_tlast ),
                           .m_axis_stat_tuser( stat_tuser ),
                           
                           `CONNECT_AXI4S_MIN_IF( s_ev_dbg_ , evdbg_ ),
                           .s_ev_dbg_tlast( evdbg_tlast ),
                           
                           // macros work even if these are concatenated
                           `CONNECT_AXI4S_MIN_IF( m_axis_ , fmb_ ),
                           .m_axis_tlast( fmb_tlast ),
                           .m_axis_tuser( fmb_tuser ),

                           `CONNECT_AXI4S_MIN_IF( m_debug_ , debug_rx_ ),
                           .m_debug_tlast( debug_rx_tlast ),
                           .m_debug_tuser( debug_rx_tuser ),
                           .m_req_suppress(req_suppress),
                           
                           .aclk( aclk ),
                           .aresetn( aresetn ),
                           .link_status_o( link_status_o ),
                           .gtp_clk_p( gtp_clk_p ),
                           .gtp_clk_n( gtp_clk_n ),
                           
                           .gtp_rx_p( gtp_rx_p ),
                           .gtp_rx_n( gtp_rx_n ),
                           .gtp_tx_p( gtp_tx_p ),
                           .gtp_tx_n( gtp_tx_n ) );

//                           .GT_CLK_P( CLK_QSFP0_OSC_OUTP ),
//                           .GT_CLK_N( CLK_QSFP0_OSC_OUTN ),
//                           .RXP( { QSFP1_RXP, QSFP0_RXP } ),
//                           .RXN( { QSFP1_RXN, QSFP0_RXN } ),
//                           .TXP( { QSFP1_TXP, QSFP0_TXP } ),
//                           .TXN( { QSFP1_TXN, QSFP0_TXN } ),
//                           .QSFP_RESETN( {QSFP1_RESETN, QSFP0_RESETN} ),
//                           .QSFP_SCL( {QSFP1_SCL, QSFP0_SCL} ),
//                           .QSFP_SDA( {QSFP1_SDA, QSFP0_SDA} ),
//                           .QSFP_LED( { QSFP1_LED, QSFP0_LED } ),
//                           .QSFP_LPMODE( { QSFP1_LPMODE, QSFP0_LPMODE } ),
//                           .QSFP_OSC_FS( { QSFP1_OSC_FS, QSFP0_OSC_FS } ),
//                           .QSFP_MODPRSN( { QSFP1_MODPRSN, QSFP0_MODPRSN } ),
//                           .QSFP_MODSELN( { QSFP1_MODSELN, QSFP0_MODSELN } ),
//                           .QSFP_INTN( {QSFP1_INTN, QSFP0_INTN} ) );                           

    // FMN
    wire ddr4_reset;
    wire ddr4_ready;

//                             // Command input.
//                             `TARGET_NAMED_PORTS_AXI4S_MIN_IF( mm2s_cmd_ , 72 ),
//                             // Status output
//                             `HOST_NAMED_PORTS_AXI4S_MIN_IF( mm2s_sts_ , 8 ),

//    wire memclk;
//    wire memresetn;  
    wire track_event;
    assign track_event_o = track_event;
    
    // The FMN is now outside the core.
    // So we just need to track the actual interfaces we're using.
    
    // going_full
    // track_event
    // AXIS fmb_ ( => m_fmb_ )
    // AXIS event_ ( => s_event_ )
    // AXIS complete_ ( => s_cmpl_ )
    // AXIS done_ ( => m_done_ )
    // AXIS mm2s_cmd_ ( => m_cmd_ )
    // AXIS mm2s_sts_ ( => s_sts_ )

//    frame_memory_network_v2 u_fmn( 
//                                .aclk( aclk ) ,.aresetn( aresetn ),
//                                .memclk(memclk),
//                                .memresetn(memresetn),
                                
//                                .going_full(going_full),
//                                .track_event_i(track_event),
                                
//                                .s_axis_tdata(  fmb_tdata ),
//                                .s_axis_tvalid( fmb_tvalid ),
//                                .s_axis_tready( fmb_tready ),
//                                .s_axis_tuser ( fmb_tuser ),
//                                .s_axis_tlast ( fmb_tlast ),
                                
//                                // memclk domain
//                                .m_axis_tdata(  event_tdata     ),
//                                .m_axis_tvalid( event_tvalid    ),
//                                .m_axis_tready( event_tready    ),
//                                .m_axis_tlast(  event_tlast     ),
                                
//                                .m_axis_cmpl_tdata ( complete_tdata  ),
//                                .m_axis_cmpl_tready( complete_tready ),
//                                .m_axis_cmpl_tvalid( complete_tvalid ),
                                
//                                .s_axis_done_tdata ( done_tdata  ),
//                                .s_axis_done_tready( done_tready ),
//                                .s_axis_done_tvalid( done_tvalid ),
                                
//                                `CONNECT_AXI4S_MIN_IF( mm2s_cmd_ , mm2s_cmd_ ),
//                                `CONNECT_AXI4S_MIN_IF( mm2s_sts_ , mm2s_sts_ ),
                                
//                                .ddr4_reset( ddr4_reset ),
//                                .ddr4_ready( ddr4_ready ),
                                
//                                .ddr4_clk_p( CLK_DDR4_OSCP ),
//                                .ddr4_clk_n( CLK_DDR4_OSCN ),
//                                .DDR4_ACT_N(DDR4_ACTN),
//                                .DDR4_A(DDR4_A[16:0]),
//                                .DDR4_BA(DDR4_BA[1:0]),
//                                .DDR4_BG(DDR4_BG[1:0]),
//                                .DDR4_CK_C(DDR4_CKN),
//                                .DDR4_CK_T(DDR4_CKP),
//                                .DDR4_CKE(DDR4_CKE[0]),
//                                .DDR4_CS_N(DDR4_CSN[0]),
//                                .DDR4_DM_DBI_N(DDR4_DMN_DBIN[8:0]),
//                                .DDR4_DQ(DDR4_DQ[71:0]),
//                                .DDR4_DQS_C(DDR4_DQSN[8:0]),
//                                .DDR4_DQS_T(DDR4_DQSP[8:0]),
//                                .DDR4_ODT(DDR4_ODT[0]),
//                                .DDR4_RESET_N(DDR4_RESETN));

    // All the event_builder stuff now hooks up to external interfaces for the FMB.
    event_builder_wrap_v4 u_eb(.aclk(aclk),.aresetn(aresetn),
                        .clk(register_clk),.reset(register_reset),
                        `CONNECT_COMBINED_IF( `NO_PREFIX_TAG(dummy) , eb_ ),
    
                        .dclk(xil_clk),.dreset(xil_areset),
                        `CONNECT_AXI4S_MIN_IF( m_event_ , evstream_ ),
                        .m_event_tlast(evstream_tlast),
                        .dma_en_o(evstream_enable),
                        
                        
                        .memclk(memclk),
                        .memresetn(memresetn),
                        //
                        .track_event_o(track_event),
                        
                        // event path from FMN in memclk domain
                        `CONNECT_AXI4S_MIN_IF(  s_axis_       ,     event_      ),
                                               .s_axis_tlast(       event_tlast ),
                        // Event debug path over to aurora_merge, in aclk domain
                        `CONNECT_AXI4S_MIN_IF(  m_axis_dbg_   ,     evdbg_      ),
                                               .m_axis_dbg_tlast(   evdbg_tlast ),                        
                        // Completion and done streams to/from FMN
                        `CONNECT_AXI4S_MIN_IF(  s_axis_cmpl_ ,      complete_ ),
                        `CONNECT_AXI4S_MIN_IF(  m_axis_done_ ,      done_ ),
                        // DataMover command/status streams from FMN
                        `CONNECT_AXI4S_MIN_IF(  mm2s_cmd_ ,         mm2s_cmd_ ),
                        `CONNECT_AXI4S_MIN_IF(  mm2s_sts_ ,         mm2s_sts_ )
                         );


    generate
        if (DEBUG_XILREG == "TRUE") begin : REGILA
            xilly_reg_ila u_regila( .clk(xil_clk),
                                    .probe0(mm_rden),
                                    .probe1(mm_wren),
                                    .probe2(mm_rdopen),
                                    .probe3(mm_wropen),
                                    .probe4(mm_full),
                                    .probe5(mm_empty),
                                    .probe6(mm_addr),
                                    .probe7(mm_addr_update),
                                    .probe8(mm_rddata),
                                    .probe9(mm_wrdata));
        end
    endgenerate        
    
//    assign LED_USER[7:5] = 3'h0;
    // debug defparams
//    defparam u_eb.u_builder.DEBUG = "FALSE";        // this is the builder command debug ILA, it's big and difficult
//    defparam u_eb.DEBUG = "TRUE";                   // this is the debug output ILA


endmodule
