`timescale 1ns/1ps
`include "interfaces.vh"

`define NO_PREFIX_TAG( x )

`define EMPTY `NO_PREFIX_TAG( dummy )

// Second attempt at the merged ARC-based firmware.
// Our biggest problem is that in order to maximize DDR4 throughput, we need to be able to
// provide 64 bytes every 250 MHz clock cycle. 
//
// Aggregate *input*, however, is only 5.12*8 = 40.96 Gb/s, or 64 bytes at 80 MHz clock.
// The fill path isn't very fast, so therefore what we need to do is make sure we can
// support efficient memory usage.
// The difficulty with this is that while it's not difficult to store 4 KiB, in order
// to support a 512-bit output path at 250 MHz we need 8 BRAMs/link, period,
// or 64 BRAMs total. 
//
// To avoid this, we make the 4 "nominally unused" links low bandwidth: we put the
// width converter *after* the clock cross. This reduces our 'base' usage to 32 BRAMs.
// The 'tiny' links will only have a single BRAM buffer for them (512x64). (1 BRAM x 4 links)
// The 'small' links will have a 4-BRAM FIFO, the data-width converter (64-to-512),       (12 BRAM x 2 links)
//              followed by the clock-cross buffer (40 kB)
// The 'medium' links will have an 8-BRAM FIFO, followed by a data-width-converter, 
//              followed by the clock-cross buffer, for a total of  64k.   (16 BRAM x 1 link)
// The 'large' link will have an 16-BRAM FIFO followed by an 8 BRAM FIFO (stupid Xilinx)
//              followed by the clock-cross buffer, for a total of 128k.   (32 BRAM x 1 link)
// for a total BRAM usage of 76 BRAMs.
//
// The 4 'fast' links can empty a single memory burst in 256 ns, and take
// 6400 ns to fill.
// The 4 'slow' links take 4 times longer to empty.
//
// However, given that the DDR has to handle readout as well, that puts the
// empty time at 512 ns typical, assuming 100% efficiency. With 4 links
// that means we need DDR running at ~30% efficiency, on average, which
// shouldn't be a problem.
//
// All links have:
// (aurora) -> (flow buffer) -> (splitter) -> (resize to 64) -> (clock cross) -> network input
//                                    |-----> status
//                                    \-----> error
//
// So these are getting merged into a single module, "aurora_input_core".
//
// then into the switch.
// Tiny, Low bandwidth links have:
// (switch out) -> 1 BRAM FIFO -> event switch -> (1 BRAM clock cross) -> (resize to 512) -> FMB
// Small, High bandwidth links have:
// (switch out) -> 4 BRAM FIFO -> event switch -> (resize to 512) - > (8 BRAM clock cross) -> FMB
// Medium, High bandwidth links have:
// (switch out) -> 8 BRAM FIFO -> event switch -> (resize to 512) -> (8 BRAM clock cross) -> FMB
// Large, High bandwidth links have:
// (switch out) -> 16 BRAM FIFO + 8 BRAM FIFO -> event switch -> (resize to 512) -> (8 BRAM clock cross) -> FMB
//
// Chaining all links would give 44 BRAMs + 8 BRAM clock cross = 52 BRAMs = 208 kB
// *pre-DDR* storage.
//
// Note that ALL links, no matter the size, have a flow buffer, however if you do input -> tiny -> debug readout
// the total buffering will be fairly small. 
//
module aurora_merge_v3 #( parameter NUM_LANES=8,
                          parameter WIDTH_CTRL=16,
                          parameter WIDTH_OUT=64,
                          parameter [31:0] IDENT = {32{1'b0}},
                          parameter [31:0] DATEVERSION = {32{1'b0}}                              
                           )
                         ( input init_clk,                     
                     input rclk,
                     input rreset,
                     `TARGET_NAMED_PORTS_COMBINED_IF( `NO_PREFIX_TAG(dummy) ),
                     // aclk is really just rclk
                     output       aclk,
                     output       aresetn,                                          
                     // event-y stuff
                     input        going_full,
                     output       trig,
                     // control transmit path (aclk)
                     input [WIDTH_CTRL-1:0] s_axis_ctrl_tdata,
                     input        s_axis_ctrl_tvalid,
                     input [2:0]  s_axis_ctrl_tdest,
                     input        s_axis_ctrl_tlast,
                     output       s_axis_ctrl_tready,
                     // status receive path (aclk)
                     output [WIDTH_OUT-1:0] m_axis_stat_tdata,
                     output        m_axis_stat_tvalid,
                     output        m_axis_stat_tlast,
                     input         m_axis_stat_tready,
                     output [2:0]  m_axis_stat_tuser,
                     
                     // event data path. (aclk) to FMBs
                     output [NUM_LANES*WIDTH_OUT-1:0] m_axis_tdata,
                     output [NUM_LANES-1:0]   m_axis_tvalid,
                     output [NUM_LANES-1:0]   m_axis_tlast,
                     output [3*NUM_LANES-1:0] m_axis_tuser,
                     input  [NUM_LANES-1:0]   m_axis_tready,
                                          
                     // debug data path (aclk)
                     // back from event builder, allowed through on a special write.
                     // (it's only allowed if bit[16] is *set* on a control write)
                     //
                     input [WIDTH_OUT-1:0] s_ev_dbg_tdata,
                     input                 s_ev_dbg_tvalid,
                     input                 s_ev_dbg_tlast,
                     output                s_ev_dbg_tready,

                     // actual debug path to debug readout                     
                     input [8:0]    m_req_suppress,
                     output [WIDTH_OUT-1:0] m_debug_tdata,
                     output         m_debug_tvalid,
                     output         m_debug_tlast,
                     input          m_debug_tready,
                     output [2:0]   m_debug_tuser,
                                                               
                     // link status output for QSFP infrastructure.
                     output [7:0] link_status_o,
                     input gtp_clk_p,
                     input gtp_clk_n,                     
                     input [7:0] gtp_rx_p,
                     input [7:0] gtp_rx_n,
                     output [7:0] gtp_tx_p,
                     output [7:0] gtp_tx_n
                     
                     );
                     

    localparam STATUS_BITS = 12;
    localparam ERR_BITS = 10;
    localparam AURORA_ERR_BITS = 4;
    localparam CONTROL_BITS = 6;
    
    localparam FLOWCTRL_COUNT_WIDTH = 8;
    localparam IN_STATISTICS_WIDTH = 24;
    localparam OUT_STATISTICS_WIDTH = 8;
    localparam ERR_STATISTICS_WIDTH = 24;
    localparam DBG_STATISTICS_WIDTH = 24;    
    // These are the number of bits that come out of each Aurora core, before going into HAIC
    localparam LANE_IN_WIDTH = 32;
    // These are the number of bits that come out of HAIC
    localparam LANE_OUT_WIDTH = WIDTH_OUT;
    
    localparam EXTRA_ERROR_WIDTH = 32;
    
    wire [NUM_LANES*EXTRA_ERROR_WIDTH-1:0] extra_error_full;
    
    wire gt_refclk;    
    wire gt_refclk_bufg;

    // Vwrap status/control. These are all rclk domain already.
    // They need to pass into the register core, so we vector them.
    wire [NUM_LANES*STATUS_BITS-1:0] aurora_status_rclk;
    // Extract out the link up bits.
    wire [7:0] link_status;
    assign link_status_o = link_status;
    //  every 8, so 0,17,27,37,47,57,67,77
    generate
        genvar li;
        for (li=0;li<NUM_LANES;li=li+1) begin : LSL
            assign link_status[li] = aurora_status_rclk[ STATUS_BITS*li + 7 ];
        end
    endgenerate
    wire [NUM_LANES*ERR_BITS-1:0] aurora_err_rclk;
    wire [NUM_LANES*CONTROL_BITS-1:0] aurora_control_rclk;
    
    // output clocks from each Aurora core
    wire [NUM_LANES-1:0] tx_out_clk;
    // pick off lane 0's output clock for the 160 MHz portion of the network
    wire aurora_clk;
    assign aurora_clk = tx_out_clk[0];
    reg areset_aurora_clk = 0;
    wire aresetn_aurora_clk = ~areset_aurora_clk;


    // Master network reset. This is *separate* from the
    // GT reset, and ensures that none of the network controls
    // can be changed when the network is flowing.
    assign aclk = rclk;
    wire areset;
    reg areset_reg = 0;
    wire areset_flag = (areset && !areset_reg);
    wire areset_flag_aurora_clk;
    always @(posedge aclk) areset_reg <= areset;
    
    assign aresetn = !areset;
    // This is a flag to update aclk controls. Only goes when areset
    // is asserted, right before it's to be deasserted.
    wire update;    
    wire update_aurora_clk;

    flag_sync u_reset_sync(.in_clkA(areset_flag),.clkA(aclk),.clkB(aurora_clk),.out_clkB(areset_flag_aurora_clk));
    flag_sync u_update_sync(.in_clkA(update),.clkA(aclk),.clkB(aurora_clk),.out_clkB(update_aurora_clk));
    always @(posedge aurora_clk) begin
        if (update_aurora_clk) areset_aurora_clk <= 0; 
        else if (areset_flag_aurora_clk) areset_aurora_clk <= 1;
    end        

    // after clock cross
    wire [15:0] aurora_ctrl_tdata;
    wire        aurora_ctrl_tvalid;
    wire        aurora_ctrl_tready;
    wire        aurora_ctrl_tlast;
    wire [2:0]  aurora_ctrl_tdest;
    wire        aurora_ctrl_fifo_empty;
        
    // Aurora network transmit path. These come out of the switch,
    // so we present them as vectored.
    wire [16*NUM_LANES-1:0] control_tx_tdata;
    wire [NUM_LANES-1:0] control_tx_tvalid;
    wire [NUM_LANES-1:0] control_tx_tready;
    wire [NUM_LANES-1:0] control_tx_tlast;

    // Indicates a packet was dropped.
    wire [NUM_LANES-1:0] aurora_dropped;

    // Aurora network status receive path (after FIFO). These go into the switch.
    wire [LANE_OUT_WIDTH*NUM_LANES-1:0] status_rx_tdata;
    wire [NUM_LANES-1:0] status_rx_tvalid;
    wire [NUM_LANES-1:0] status_rx_tlast;
    wire [NUM_LANES-1:0] status_rx_tready;
    wire [3*NUM_LANES-1:0] status_rx_tuser;

    // Aurora network error (non-data/status) path. These go into a switch
    // then into a FIFO-ish type thing which doesn't fill (it autodumps when nearly full).
    // Their readout is obviously horribly inefficient because we don't need to do it often.
    // The error path also has a reroute from the event switch.
    wire [LANE_OUT_WIDTH*NUM_LANES-1:0] err_rx_tdata;
    wire [NUM_LANES-1:0] err_rx_tvalid;
    wire [NUM_LANES-1:0] err_rx_tready;
    // bottom 3 are normal tuser, 1 indicating a partial 64-bit word, then 3 for origin
    wire [7*NUM_LANES-1:0] err_rx_tuser;
    wire [NUM_LANES-1:0] err_rx_tlast;
    
    // Output of error switch. This is designed to be exactly 72 bits (64 + 7 tuser + 1 tlast)
    wire [LANE_OUT_WIDTH-1:0] error_tdata;
    wire        error_tvalid;
    wire        error_tready;
    wire [6:0]  error_tuser;
    wire        error_tlast;

    // Destination routing for each lane. The first event switch
    // provides 9 paths, 8 buffers and a dump path.
    // tdest=0 large buffer         (116 BRAM, 512k)
    // tdest=1 med buffer           (57.5 BRAM, 256k)
    // tdest=2 small buffer 0       (29 BRAM, 128k)
    // tdest=3 small buffer 1       (29 BRAM, 128k)
    // tdest=4 tiny buffer 0        (8 BRAM, 32k)
    // tdest=5 tiny buffer 1        (8 BRAM, 32k)
    // tdest=6 tiny buffer 2        (8 BRAM, 32k)
    // tdest=7 tiny buffer 3        (8 BRAM, 32k)
    // tdest=8+ dump path
    //
    // The second event switch takes 8 inputs and routes
    // to 13 output paths: the first 8 are handled by the
    // event readout. The remaining 4 are reroutes back to the first event switch,
    // to allow buffer chaining.
    // tdest=0-7 event lane 0-7
    // tdest=8 reroute 0
    // tdest=9 reroute 1
    // tdest=10 reroute 2
    // tdest=11 reroute 3
    // tdest=12+ debug route    
    //
    // This means that a dumbass can screw up the whole thing
    // with feedback: in0 -> buf0 -> out9 -> buf0 (etc.)
    // A loop can also form: out9 -> buf0 -> out8 -> buf1 -> out9
    // but these aren't a problem since they have no input.
    // The feedback problems only occur when someone double-maps the
    // inputs to anything other than the dump path, so we just completely disallow
    // that in the register configuration.
    
    // number of buffer paths
    localparam NUM_BUFS = 8;
    // number of reroutes available
    localparam NUM_REROUTES = 4;    
    // inputs to the first switch 
    localparam NUM_NET_IN = NUM_LANES+NUM_REROUTES;
    // outputs from the first switch (buffers + dump path)
    localparam NUM_NET_OUT = NUM_BUFS + 1;
    // inputs to the second switch
    localparam NUM_EV_IN = NUM_BUFS;
    // number of outputs of the second switch: lane outputs, reroutes, and debug path.
    localparam NUM_EV_OUT = NUM_LANES + NUM_REROUTES + 1;
    // TDEST address of the debug output.    
    localparam DEBUG_TDEST = NUM_EV_OUT-1;
    // TDEST address of the dump output.
    localparam DUMP_TDEST = NUM_NET_OUT-1;
    // TDEST where the reroutes start
    localparam REROUTE_TDEST_BASE = 8;
    
    // Wide event path to network switch (to buffers)
    wire [LANE_OUT_WIDTH*NUM_NET_IN-1:0] net_tdata;
    wire [NUM_NET_IN-1:0] net_tvalid;
    wire [NUM_NET_IN-1:0] net_tready;
    wire [NUM_NET_IN-1:0] net_tlast;
    wire [3*NUM_NET_IN-1:0] net_tuser;
    reg  [4*NUM_NET_IN-1:0] net_tdest_route = {4*NUM_NET_IN{1'b1}};
    wire [4*NUM_NET_IN-1:0] net_tdest_route_rclk;
    
    // Wide event paths out of switch (to buffers).
    wire [LANE_OUT_WIDTH*NUM_NET_OUT-1:0] netout_tdata;
    wire [NUM_NET_OUT-1:0] netout_tvalid;
    wire [NUM_NET_OUT-1:0] netout_tready;
    wire [NUM_NET_OUT-1:0] netout_tlast;
    wire [3*NUM_NET_OUT-1:0] netout_tuser;

    // Wide event paths to event switch
    wire [LANE_OUT_WIDTH*NUM_EV_IN-1:0] event_tdata;
    wire [NUM_EV_IN-1:0] event_tvalid;
    wire [NUM_EV_IN-1:0] event_tready;
    wire [NUM_EV_IN-1:0] event_tlast;
    wire [3*NUM_EV_IN-1:0] event_tuser;
    reg [4*NUM_EV_IN-1:0] event_tdest_route = {4*NUM_EV_IN{1'b1}};
    wire [4*NUM_EV_IN-1:0] event_tdest_route_rclk;
        
    // Wide event paths out of event switch 
    wire [LANE_OUT_WIDTH*NUM_EV_OUT-1:0] eventout_tdata;
    wire [NUM_EV_OUT-1:0] eventout_tvalid;
    wire [NUM_EV_OUT-1:0] eventout_tready;
    wire [NUM_EV_OUT-1:0] eventout_tlast;
    wire [3*NUM_EV_OUT-1:0] eventout_tuser;

    // Now jumper the reroutes. There are 4 of them, we jumper them all at once.
    assign net_tdata[LANE_OUT_WIDTH*REROUTE_TDEST_BASE +: LANE_OUT_WIDTH*NUM_REROUTES] = eventout_tdata[LANE_OUT_WIDTH*REROUTE_TDEST_BASE +: LANE_OUT_WIDTH*NUM_REROUTES];
    assign net_tvalid[REROUTE_TDEST_BASE +: NUM_REROUTES] = eventout_tvalid[REROUTE_TDEST_BASE +: NUM_REROUTES];
    assign net_tlast[REROUTE_TDEST_BASE +: NUM_REROUTES] = eventout_tlast[REROUTE_TDEST_BASE +: NUM_REROUTES];
    assign net_tuser[3*REROUTE_TDEST_BASE +: 3*NUM_REROUTES] = eventout_tuser[3*REROUTE_TDEST_BASE +: 3*NUM_REROUTES];
    assign eventout_tready[REROUTE_TDEST_BASE +: NUM_REROUTES] = net_tready[REROUTE_TDEST_BASE +: NUM_REROUTES];

    // make the dump buffer a dump
    assign netout_tready[DUMP_TDEST] = 1'b1;

    // and hook the debug readout
    assign m_debug_tdata = eventout_tdata[LANE_OUT_WIDTH*DEBUG_TDEST +: LANE_OUT_WIDTH];
    assign m_debug_tvalid = eventout_tvalid[DEBUG_TDEST];
    assign m_debug_tlast = eventout_tlast[DEBUG_TDEST];
    assign m_debug_tuser = eventout_tuser[3*DEBUG_TDEST +: 3];
    assign eventout_tready[DEBUG_TDEST] = m_debug_tready;

    // Flow buffer XOFF level for buffer. The buffers are relatively small (512 entries).
    // These are "level + 256" as anything smaller really doesn't make sense.
    // 0xFF shuts off XOFF entirely.
    wire [8*NUM_LANES-1:0] xoff_level;
    // Hysteresis on XOFF. This programs the programmable empty value as (xoff_level+256-xoff_hysteresis).
    wire [8*NUM_LANES-1:0] xoff_hysteresis;
    // Indicates that a frame was dropped, in aclk domain
    wire [NUM_LANES-1:0] flow_dropped;
    // Indicates that a frame was dropped, in rclk domain
    reg [NUM_LANES-1:0] flow_dropped_rclk = {NUM_LANES{1'b0}};
    // Indicates that a frame overflowed, in aclk domain
    wire [NUM_LANES-1:0] flow_overflow;
    // Indicates that a frame overflowed, in rclk domain
    reg [NUM_LANES-1:0] flow_overflow_rclk = {NUM_LANES{1'b0}};
    // Indicates that an event path hit its jam counter.
    wire [NUM_LANES-1:0] flow_jammed;
    // Indicates that an input path hit its stuck counter.
    wire [NUM_LANES-1:0] flow_stuck;
    reg [NUM_LANES-1:0] flow_stuck_rclk = {NUM_LANES{1'b0}};
    
    // someone tried to send data on a link that can't take it
    reg [NUM_LANES-1:0] tx_err = {NUM_LANES{1'b0}};
    reg [NUM_LANES-1:0] tx_err_rclk = {NUM_LANES{1'b0}};
    
    // Indicates that the outgoing path has been stopped for too long.
    wire [NUM_LANES-1:0] vwrap_stopped;
    // in rclk domain
    reg [NUM_LANES-1:0] vwrap_stopped_rclk = {NUM_LANES{1'b0}};
       
    // Number of clock cycles in the jam counter for all links.
    wire [31:0] jam_delay;
    // Disable the jam error.
    wire        jam_disable;    
    
    // Number of clock cycles in the stuck counter for all links.
    wire [31:0] stuck_delay;
    // Disable the stuck error.
    wire        stuck_disable;
    
    // Number of clock cycles in the stopped counter for all links.
    wire [31:0] stop_delay;
    // Disable the stop error.
    wire        stop_disable;
    
    // Number of 65536-clock periods to assert gt_reset for on a reset.
    wire [15:0] gt_reset_len;
    
    // swapendian bits
    wire [NUM_LANES-1:0] swapendian;
    reg [NUM_LANES-1:0] swapendian_rclk = {NUM_LANES{1'b0}};
    
    // statistics
    wire [NUM_LANES*FLOWCTRL_COUNT_WIDTH-1:0] flowctrl_count;
    wire [NUM_LANES*IN_STATISTICS_WIDTH-1:0] in_statistics;
    wire [NUM_LANES*OUT_STATISTICS_WIDTH-1:0] out_statistics;
    wire [ERR_STATISTICS_WIDTH-1:0] err_statistics;
    wire [DBG_STATISTICS_WIDTH-1:0] dbg_statistics;
    
    // QSFP status is now OUTSIDE this.
    // general infrastructure modules
//    qsfp_infrastructure u_qsfp_infra( .clk(rclk),
//                                      .link_status(link_status),
//                                        .QSFP_RESETN(QSFP_RESETN),
//                                        .QSFP_SCL(QSFP_SCL),
//                                        .QSFP_SDA(QSFP_SDA),
//                                        .QSFP_LED(QSFP_LED),
//                                        .QSFP_LPMODE(QSFP_LPMODE),
//                                        .QSFP_MODPRSN(QSFP_MODPRSN),
//                                        .QSFP_MODSELN(QSFP_MODSELN),
//                                        .QSFP_INTN(QSFP_INTN),
//                                        .QSFP_OSC_FS(QSFP_OSC_FS));
    wire gt_to_bufg;
    IBUFDS_GTE3 #(.REFCLK_HROW_CK_SEL(2'b00))
        u_gtrefclk_ibuf(.I(gtp_clk_p),.IB(gtp_clk_n),
                        .CEB(1'b0),
                        .O(gt_refclk),
                        .ODIV2(gt_to_bufg));                                                                    
    BUFG_GT u_gtrefclkbufg_ibuf(.I(gt_to_bufg),.O(gt_refclk_bufg));
 
    assign s_axis_ctrl_tready = !aurora_ctrl_fifo_full;
    aurora_ctrl_fifo u_ctrl_fifo( .wr_clk(aclk),.rst(areset),
                                  .din( { s_axis_ctrl_tlast, s_axis_ctrl_tdest, s_axis_ctrl_tdata } ),
                                  .full( aurora_ctrl_fifo_full ),
                                  .wr_en( s_axis_ctrl_tready && s_axis_ctrl_tvalid ),
                                  .rd_clk(aurora_clk),
                                  .dout( { aurora_ctrl_tlast, aurora_ctrl_tdest, aurora_ctrl_tdata } ),
                                  .valid( aurora_ctrl_tvalid ),
                                  .rd_en( aurora_ctrl_tvalid && aurora_ctrl_tready ) );
                        
    // control switch
    aurora_control_switch u_control_switch( .aclk(aurora_clk),.aresetn(aresetn_aurora_clk),
                                            .s_axis_tdata( aurora_ctrl_tdata ),
                                            .s_axis_tvalid( aurora_ctrl_tvalid ),
                                            .s_axis_tready( aurora_ctrl_tready ),
                                            .s_axis_tlast( aurora_ctrl_tlast ),
                                            .s_axis_tdest( aurora_ctrl_tdest ),
                                            .m_axis_tdata( control_tx_tdata ),
                                            .m_axis_tvalid( control_tx_tvalid ),
                                            .m_axis_tready( control_tx_tready ),
                                            .m_axis_tlast( control_tx_tlast ) );

    // le sigh. I was hoping not to ever have to grab this crap.
    wire [31:0] dbg_tdata_full[NUM_LANES-1:0];
    wire [NUM_LANES-1:0] dbg_tvalid_full;
    wire [NUM_LANES-1:0] dbg_tlast_full;
    wire [2:0] dbg_tuser_full[NUM_LANES-1:0];

    // le double sigh
    wire [31:0] raw_tdata_full[NUM_LANES-1:0];
    wire [NUM_LANES-1:0] raw_tvalid_full;
    wire [4*NUM_LANES-1:0] raw_tkeep_full;
    wire [NUM_LANES-1:0] raw_tlast_full;
                
    wire [2:0] dbg_select_vio;                
    reg [2:0] dbg_select_sync = {3{1'b0}};                
    reg [2:0] dbg_select = {3{1'b0}};                
    reg [31:0]  dbg_tdata = {32{1'b0}};
    reg         dbg_tvalid = 0;
    reg         dbg_tlast = 0;
    reg [2:0]   dbg_tuser = {3{1'b0}};

    reg [15:0] dbg_tx_tdata = {16{1'b0}};
    reg        dbg_tx_tready = 1'b0;
    reg        dbg_tx_tvalid = 1'b0;
    reg        dbg_tx_tlast = 1'b0;
    wire [NUM_LANES-1:0] tx_will_discard;
    reg        dbg_tx_will_discard = 1'b0;
    reg [ERR_BITS-1:0] dbg_err_bits_resync = {ERR_BITS{1'b0}};
    reg [ERR_BITS-1:0] dbg_err_bits = {ERR_BITS{1'b0}};

    reg [31:0] raw_tdata = {32{1'b0}};
    reg [3:0] raw_tkeep = {4{1'b0}};
    reg raw_tvalid = 0;
    reg raw_tlast = 0;
    
    always @(posedge aurora_clk) begin
        dbg_select_sync <= dbg_select_vio;
        dbg_select <= dbg_select_sync;

        // these will optimize away
        raw_tdata <= raw_tdata_full[dbg_select];
        raw_tvalid <= raw_tvalid_full[dbg_select];
        raw_tkeep <= raw_tkeep_full[dbg_select];
        raw_tlast <= raw_tlast_full[dbg_select];
        
        dbg_tdata <= dbg_tdata_full[dbg_select];
        dbg_tvalid <= dbg_tvalid_full[dbg_select];
        dbg_tlast <= dbg_tlast_full[dbg_select];
        dbg_tuser <= dbg_tuser_full[dbg_select];

        dbg_tx_tdata <= control_tx_tdata[16*dbg_select +: 16];
        dbg_tx_tvalid <= control_tx_tvalid[dbg_select];
        dbg_tx_tready <= control_tx_tready[dbg_select];
        dbg_tx_tlast <= control_tx_tlast[dbg_select];
        dbg_tx_will_discard <= tx_will_discard[dbg_select];
        dbg_err_bits_resync <= aurora_err_rclk[ERR_BITS*dbg_select +: ERR_BITS];
        dbg_err_bits <= aurora_err_rclk[dbg_select];
    end
    aurora_merge_ila u_ila(.clk(aurora_clk),.probe0(dbg_tdata),.probe1(dbg_tvalid),.probe2(dbg_tlast),.probe3(dbg_tuser),
                           .probe4(dbg_tx_tdata),
                           .probe5(dbg_tx_tvalid),
                           .probe6(dbg_tx_tready),
                           .probe7(dbg_tx_tlast),
                           .probe8(dbg_tx_will_discard),
                           .probe9(dbg_err_bits));
    // aurora lane loop
    generate
        genvar ln;
        for (ln=0;ln<NUM_LANES;ln=ln+1) begin : LANE
            wire [EXTRA_ERROR_WIDTH-1:0] extra_error;
            assign extra_error_full[EXTRA_ERROR_WIDTH*ln +: EXTRA_ERROR_WIDTH] = extra_error;
            
            // zero them out right now
            assign extra_error[31:8] = {24{1'b0}};
            
            wire        tx_discarded_link_stopped;
            
            // Path out of the stop detector for control frames for each lane, to go to vwrap.
            wire [15:0] vwrap_tx_tdata;
            wire        vwrap_tx_tvalid;
            wire        vwrap_tx_tlast;
            wire        vwrap_tx_tready;
            wire        vwrap_tx_will_discard;
            assign      tx_will_discard[ln] = vwrap_tx_will_discard;
                                
            wire        vwrap_tx_xoff;                    
            // initial outbound path for each lane, to go to HAIC
            wire [31:0] vwrap_tdata;
            wire        vwrap_tvalid;
            wire        vwrap_tlast;
            wire [2:0]  vwrap_tuser;
                        
            assign dbg_tdata_full[ln] = vwrap_tdata;
            assign dbg_tvalid_full[ln] = vwrap_tvalid;
            assign dbg_tuser_full[ln] = vwrap_tuser;
            assign dbg_tlast_full[ln] = vwrap_tlast;
            
            // swapendian
            reg         swapendian_aclk = 0;
            
            // flow buffer xoff transmit
            wire        flow_xoff;
            wire        flow_drop;
            wire        dropped_flag;
            
            reg         flow_xoff_reg = 0;
            reg [FLOWCTRL_COUNT_WIDTH-1:0] flowctrl_count_aurora = {FLOWCTRL_COUNT_WIDTH{1'b0}};
            
            always @(posedge aurora_clk) begin : AURORA_CLK_LOGIC            
                flow_xoff_reg <= flow_xoff;
                
                if (!aresetn_aurora_clk) begin
                    flowctrl_count_aurora <= {FLOWCTRL_COUNT_WIDTH{1'b0}};
                end else if (flow_xoff && !flow_xoff_reg) begin
                    flowctrl_count_aurora <= flowctrl_count_aurora + 1;
                end
                
                if (!aresetn_aurora_clk)
                    tx_err[ln] <= 1'b0;
                else if (tx_discarded_link_stopped || (vwrap_tx_tvalid && tx_will_discard[ln]))
                    tx_err[ln] <= 1'b1;                   
            end
            
            // ratio here is 1.6/1, just do 8
            async_register #(.WIDTH(8),.UPDATE_PERIOD(8)) 
                u_cc_flowctrl_count(.in_clkA(flowctrl_count_aurora),.clkA(aurora_clk),
                                    .out_clkB(flowctrl_count[FLOWCTRL_COUNT_WIDTH*ln +: FLOWCTRL_COUNT_WIDTH]),
                                    .clkB(rclk));
                                    
            aurora_statistics #(.IN_STATISTICS_WIDTH(24),.OUT_STATISTICS_WIDTH(8))
                u_statistics(.aurora_clk(aurora_clk),
                             .aurora_reset(!aresetn_aurora_clk),
                             .clk(rclk),
                             .in_count(vwrap_tvalid),
                             .out_count(vwrap_tx_tvalid && (vwrap_tx_tready && !vwrap_tx_will_discard)),
                             .in_statistics( in_statistics[IN_STATISTICS_WIDTH*ln +: IN_STATISTICS_WIDTH]),
                             .out_statistics( out_statistics[OUT_STATISTICS_WIDTH*ln +: OUT_STATISTICS_WIDTH]));                                  

            control_stop_detector u_stop_det(.aclk(aurora_clk),.aresetn(aresetn_aurora_clk),
                                             .s_axis_tdata(control_tx_tdata[16*ln +: 16]),
                                             .s_axis_tvalid(control_tx_tvalid[ln]),
                                             .s_axis_tready(control_tx_tready[ln]),
                                             .s_axis_tlast(control_tx_tlast[ln]),
                                             .m_axis_tdata(vwrap_tx_tdata),
                                             .m_axis_tvalid(vwrap_tx_tvalid),
                                             .m_axis_tlast(vwrap_tx_tlast),
                                             .m_axis_tready(vwrap_tx_tready),
                                             .tx_discard_o(tx_discarded_link_stopped),
                                             .xoff_i(vwrap_tx_xoff),
                                             .stop_delay_i(stop_delay),
                                             .stop_disable_i(stop_disable),
                                             .update_i(update_aurora_clk),
                                             .stopped_o(vwrap_stopped[ln]));
            wire ln_busy_reset;
            wire ln_going_full;
            wire ln_trig;
            if (ln == 0) begin : MT
                reg [2:0] reset_resync = {3{1'b0}};
                reg [2:0] going_full_resync = {3{1'b0}};
                always @(posedge aurora_clk) begin : RS
                    reset_resync <= { reset_resync[1:0], !aresetn };
                    going_full_resync <= { going_full_resync[1:0], going_full };
                end
                assign ln_busy_reset = reset_resync[2];
                assign ln_going_full = going_full_resync[2];
                flag_sync u_tsync(.in_clkA(ln_trig),.out_clkB(trig),.clkA(aurora_clk),.clkB(aclk));
            end else begin : NOMT
                assign ln_busy_reset = 1'b0;
                assign ln_going_full = 1'b0;
            end

            aurora_vwrap #(.EXAMPLE_SIMULATION(0),.LANE(ln),.XOFF_BUSY(ln==0 ? "TRUE" : "FALSE")) u_vwrap(.aclk(aurora_clk),
                                .m_axis_raw_tdata(raw_tdata_full[ln]),
                                .m_axis_raw_tkeep(raw_tkeep_full[ln]),
                                .m_axis_raw_tvalid(raw_tvalid_full[ln]),
                                .m_axis_raw_tlast(raw_tlast_full[ln]),
                                
                                .s_axis_tx_tdata(   vwrap_tx_tdata  ),
                                .s_axis_tx_tvalid(  vwrap_tx_tvalid ),
                                .s_axis_tx_tready(  vwrap_tx_tready ),
                                .s_axis_tx_tlast(   vwrap_tx_tlast  ),
                                .s_axis_tx_will_discard( vwrap_tx_will_discard ),
                                .s_axis_tx_tuser(1'b0),
                                // maybe according to Brandon this isn't needed...?
                                .axis_tx_xoff(vwrap_tx_xoff),

                                .busy_reset(ln_busy_reset),
                                .going_full(ln_going_full),
                                .trig(ln_trig),
                                
                                // receive path
                                .m_axis_rx_tdata(vwrap_tdata),
                                .m_axis_rx_tvalid(vwrap_tvalid),
                                .m_axis_rx_tlast(vwrap_tlast),
                                .m_axis_rx_tuser(vwrap_tuser),
                                .axis_rx_xoff(flow_xoff),
                                .axis_rx_drop(flow_drop),
                                .axis_rx_dropped(dropped_flag),
                                
                                .status_clk(rclk),
                                .err(aurora_err_rclk[ERR_BITS*ln +: AURORA_ERR_BITS]),
                                .status(aurora_status_rclk[STATUS_BITS*ln +: STATUS_BITS]),
                                .control(aurora_control_rclk[CONTROL_BITS*ln +: CONTROL_BITS]),
                                .gt_reset_len(gt_reset_len),
                                .gt_refclk(gt_refclk),
                                .gt_bufclk(gt_refclk_bufg),
                                .init_clk(init_clk),
                                .tx_out_clk(tx_out_clk[ln]),
                                .rxp(gtp_rx_p[ln]),
                                .rxn(gtp_rx_n[ln]),
                                .txp(gtp_tx_p[ln]),
                                .txn(gtp_tx_n[ln]));
            // flow_jammed is already in rclk domain                                
            assign aurora_err_rclk[ERR_BITS*ln + AURORA_ERR_BITS +: (ERR_BITS-AURORA_ERR_BITS)] = { tx_err_rclk[ln], vwrap_stopped_rclk[ln], flow_stuck_rclk[ln], flow_jammed[ln], flow_overflow_rclk[ln], flow_dropped_rclk[ln] };            
            wire [4:0] err_rx_tuser_raw;            
            assign err_rx_tuser[7*ln +: 3] = err_rx_tuser_raw[2:0];
            // err_rx_tuser[4] is now 'partial 64-bit value'
            assign err_rx_tuser[7*ln + 3] = (err_rx_tuser_raw[4:3] != 2'b11);
            assign err_rx_tuser[7*ln + 4 +: 3] = ln;
            helix_aurora_input_core u_haic(.s_axis_aclk(aurora_clk),
                                           .s_axis_aresetn(aresetn_aurora_clk),
                                           .s_axis_tdata(vwrap_tdata),
                                           .s_axis_tvalid(vwrap_tvalid),
                                           .s_axis_tlast(vwrap_tlast),
                                           .s_axis_tuser(vwrap_tuser),
                                           .flow_xoff_o(flow_xoff),
                                           .flow_drop_o(flow_drop),
                                           .dropped_flag_i(dropped_flag),
                                           .dropped_o(flow_dropped[ln]),
                                           .overflow_o(flow_overflow[ln]),
                                           .jammed_o(flow_jammed[ln]),
                                           .jam_delay_i(jam_delay),
                                           .jam_disable_i(jam_disable),   
                                           .stuck_delay_i(stuck_delay),
                                           .stuck_disable_i(stuck_disable),
                                           .stuck_o(flow_stuck[ln]),                                        
                                           .xoff_level_i(xoff_level[8*ln +: 8]),
                                           .xoff_hysteresis_i(xoff_hysteresis[8*ln +: 8]),
                                           .s_update_i(update_aurora_clk),
                                           .m_update_i(update),
                                           
                                           .extra_error_o(extra_error[7:0]),
                                           
                                           .m_axis_aclk(rclk),
                                           .m_axis_aresetn(aresetn),
                                           
                                           .m_axis_ev_tdata( net_tdata[ WIDTH_OUT*ln +: WIDTH_OUT ] ),
                                           .m_axis_ev_tready(net_tready[ ln ] ),
                                           .m_axis_ev_tvalid(net_tvalid[ ln ] ),
                                           .m_axis_ev_tuser( net_tuser[ 3*ln +: 3 ] ),
                                           .m_axis_ev_tlast( net_tlast[ ln ] ),
                                           
                                           .m_axis_st_tdata( status_rx_tdata[ WIDTH_OUT*ln +: WIDTH_OUT ] ),
                                           .m_axis_st_tready(status_rx_tready[ ln ] ),
                                           .m_axis_st_tvalid(status_rx_tvalid[ ln ] ),
                                           .m_axis_st_tuser( status_rx_tuser[ 3*ln +: 3] ),
                                           .m_axis_st_tlast( status_rx_tlast[ ln ] ),
                                           
                                           .m_axis_err_tdata(   err_rx_tdata[ WIDTH_OUT*ln +: WIDTH_OUT ] ),
                                           .m_axis_err_tready(  err_rx_tready[ ln ] ),
                                           .m_axis_err_tvalid(  err_rx_tvalid[ ln ] ),
                                           .m_axis_err_tuser(   err_rx_tuser_raw ),
                                           .m_axis_err_tlast(   err_rx_tlast[ ln ] ));
               
        end                
    endgenerate
    // These are generic and can use the par_axis_switch, 64 bits, 7 bit tuser.
    // Don't arbitrate on tlast, that could conceivably jam the frame splitter.
    par_axis_switch #(.C_NUM_SI_SLOTS(8),.C_LOG_SI_SLOTS(3),.C_AXIS_TDATA_WIDTH(WIDTH_OUT),.C_AXIS_TUSER_WIDTH(7),.C_ARB_ON_TLAST(1'b0))
        u_err_switch( .aclk(aclk), .aresetn(aresetn),
                      .s_axis_tdata( err_rx_tdata ),
                      .s_axis_tvalid(err_rx_tvalid),
                      .s_axis_tready(err_rx_tready),
                      .s_axis_tuser( err_rx_tuser ),
                      .s_axis_tlast( err_rx_tlast ),
                      .m_axis_tdata( error_tdata ),
                      .m_axis_tvalid(error_tvalid),
                      .m_axis_tready(error_tready),
                      .m_axis_tuser( error_tuser ),
                      .m_axis_tlast( error_tlast ) );

    // The error path also needs a FIFO, but it needs to be an unblockable FIFO. If the error FIFO fills up,
    // you just lose the error data. Maybe make this configurable, I dunno.
    // But because of that we don't use an AXI4-Stream FIFO generator mode. We just use a normal FIFO generator.
    // The error path is packed to be a single BRAM FIFO: 64 + 7 tuser + 1 tlast = 72.
    
    wire [63:0] rclk_err_tdata;
    wire [6:0]  rclk_err_tuser;
    wire        rclk_err_tready;
    wire        rclk_err_tvalid;
    wire        rclk_err_tlast;
    
    wire        err_count = (error_tvalid);
    
    wire err_fifo_full;
    assign error_tready = 1'b1;
    aurora_err_fifo u_err_fifo(.wr_clk(aclk),.rd_clk(rclk),.srst(!aresetn),
                               .din( {error_tlast, error_tuser, error_tdata }),
                               .wr_en( error_tvalid && !err_fifo_full),
                               .full( err_fifo_full ),
                               .dout( {rclk_err_tlast, rclk_err_tuser, rclk_err_tdata }),
                               .valid( rclk_err_tvalid ),
                               .rd_en( rclk_err_tvalid && rclk_err_tready ));
                      
    // Status switch
    par_axis_switch #(.C_NUM_SI_SLOTS(8),.C_LOG_SI_SLOTS(3),.C_AXIS_TDATA_WIDTH(WIDTH_OUT),.C_AXIS_TUSER_WIDTH(3))
        u_stat_switch( .aclk(aclk), .aresetn(aresetn),
                       .s_axis_tdata(   status_rx_tdata     ),
                       .s_axis_tvalid(  status_rx_tvalid    ),
                       .s_axis_tready(  status_rx_tready    ),
                       .s_axis_tuser(   status_rx_tuser     ),
                       .s_axis_tlast(   status_rx_tlast     ),
                       .m_axis_tdata(   m_axis_stat_tdata   ),
                       .m_axis_tvalid(  m_axis_stat_tvalid  ),
                       .m_axis_tready(  m_axis_stat_tready  ),
                       .m_axis_tuser(   m_axis_stat_tuser   ),
                       .m_axis_tlast(   m_axis_stat_tlast   ));

    // Event buffer network.
    // This includes the debug suppressor, but we're forcing it to 0 now to see if we can
    // create a method for building events through the debug path.
    buffer_network u_bufnet( .aclk(aclk) ,.aresetn(aresetn),
                             .s_axis_tdata  (   net_tdata   ),
                             .s_axis_tready (   net_tready  ),
                             .s_axis_tvalid (   net_tvalid  ),
                             .s_axis_tdest  (   net_tdest_route ),
                             .s_axis_tuser  (   net_tuser   ),
                             .s_axis_tlast  (   net_tlast   ),
                             
                             .evout_route   ( event_tdest_route ),
                            
                             .debug_suppress(   m_req_suppress  ),
                             .s_ev_dbg_tdata(   s_ev_dbg_tdata  ),
                             .s_ev_dbg_tready(  s_ev_dbg_tready ),
                             .s_ev_dbg_tvalid(  s_ev_dbg_tvalid ),
                             .s_ev_dbg_tlast(   s_ev_dbg_tlast  ),
                             
                             .m_axis_tdata  (   eventout_tdata  ),
                             .m_axis_tready (   eventout_tready ),
                             .m_axis_tvalid (   eventout_tvalid ),
                             .m_axis_tuser  (   eventout_tuser  ),
                             .m_axis_tlast  (   eventout_tlast  ));

    // debug path
    assign m_axis_tdata = eventout_tdata[ 0 +: NUM_LANES*WIDTH_OUT ];
    assign m_axis_tvalid = eventout_tvalid[ 0 +: NUM_LANES ];
    assign m_axis_tlast = eventout_tlast[0 +: NUM_LANES];
    assign eventout_tready[0 +: NUM_LANES] = m_axis_tready;
    assign m_axis_tuser = eventout_tuser[0 +: NUM_LANES*3];

    wire dbg_count = (m_debug_tvalid && m_debug_tready);    

    aurora_merge_vio u_vio( .clk(rclk),.probe_out0(dbg_select_vio),
                            .probe_in0( aurora_err_rclk[ERR_BITS*0 +: ERR_BITS]),
                            .probe_in1( aurora_err_rclk[ERR_BITS*1 +: ERR_BITS]),
                            .probe_in2( aurora_err_rclk[ERR_BITS*2 +: ERR_BITS]),
                            .probe_in3( aurora_err_rclk[ERR_BITS*3 +: ERR_BITS]),
                            .probe_in4( aurora_err_rclk[ERR_BITS*4 +: ERR_BITS]),
                            .probe_in5( aurora_err_rclk[ERR_BITS*5 +: ERR_BITS]),
                            .probe_in6( aurora_err_rclk[ERR_BITS*6 +: ERR_BITS]),
                            .probe_in7( aurora_err_rclk[ERR_BITS*7 +: ERR_BITS]),
                            .probe_in8( aurora_status_rclk[STATUS_BITS*0 +: STATUS_BITS] ),
                            .probe_in9( aurora_status_rclk[STATUS_BITS*1 +: STATUS_BITS] ),
                            .probe_in10(aurora_status_rclk[STATUS_BITS*2 +: STATUS_BITS] ),
                            .probe_in11(aurora_status_rclk[STATUS_BITS*3 +: STATUS_BITS] ),
                            .probe_in12(aurora_status_rclk[STATUS_BITS*4 +: STATUS_BITS] ),
                            .probe_in13(aurora_status_rclk[STATUS_BITS*5 +: STATUS_BITS] ),
                            .probe_in14(aurora_status_rclk[STATUS_BITS*6 +: STATUS_BITS] ),
                            .probe_in15(aurora_status_rclk[STATUS_BITS*7 +: STATUS_BITS] ));
                            

    always @(posedge rclk) begin
        flow_dropped_rclk <= flow_dropped;
        flow_overflow_rclk <= flow_overflow;
        flow_stuck_rclk <= flow_stuck;
        vwrap_stopped_rclk <= vwrap_stopped;
        tx_err_rclk <= tx_err;
    end
    always @(posedge aclk) begin
        if (update) begin
            // wtf this is for aclk side, not aurora_clk side
            net_tdest_route <= net_tdest_route_rclk;
            event_tdest_route <= event_tdest_route_rclk;
        end
    end

    // Error and debug statistics counter.
    wire [47:0] errdbg_count_aclk;    
    dual_dsp_counters u_errdbg_count(.clk(aclk),.rst(!aresetn),
                                     .increment({dbg_count, err_count}),
                                     .count(errdbg_count_aclk));
    // cross to rclk
    async_register #(.WIDTH(48),.UPDATE_PERIOD(8)) 
        u_cc_errstatistics( .clkA(aclk),
                            .in_clkA(errdbg_count_aclk),
                            .clkB(rclk),
                            .out_clkB({dbg_statistics, err_statistics}));
    // Register core.
    aurora_register_core #(.IDENT(IDENT),.DATEVERSION(DATEVERSION),.CONTROL_BITS(CONTROL_BITS),.STATUS_BITS(STATUS_BITS),.ERR_BITS(ERR_BITS),.NUM_LANES(NUM_LANES))
                         u_registers( .clk(rclk),.reset(rreset),
                                      `CONNECT_COMBINED_IF( `NO_PREFIX_TAG(dummy), `NO_PREFIX_TAG(dummy) ),
                                      .areset(areset),
                                      .update(update),
                                      .aurora_err(aurora_err_rclk),
                                      .aurora_status(aurora_status_rclk),
                                      .aurora_control(aurora_control_rclk),
                                      .net_tdest_route(net_tdest_route_rclk),
                                      .event_tdest_route(event_tdest_route_rclk),
                                      .swapendian(swapendian),
                                      .xoff_level(xoff_level),
                                      .xoff_hysteresis(xoff_hysteresis),
                                      .flowctrl_count(flowctrl_count),
                                      .in_statistics(in_statistics),
                                      .out_statistics(out_statistics),
                                      .err_statistics(err_statistics),
                                      .dbg_statistics(dbg_statistics),
                                      .jam_delay_o(jam_delay),
                                      .jam_disable_o(jam_disable),
                                      .stuck_delay_o(stuck_delay),
                                      .stuck_disable_o(stuck_disable),
                                      .stop_delay_o(stop_delay),
                                      .stop_disable_o(stop_disable),
                                      .gt_reset_len_o(gt_reset_len),
                                      
                                      .extra_error_i(extra_error_full),
                                      
                                      .s_axis_tdata(rclk_err_tdata),
                                      .s_axis_tvalid(rclk_err_tvalid),
                                      .s_axis_tready(rclk_err_tready),
                                      .s_axis_tuser(rclk_err_tuser),
                                      .s_axis_tlast(rclk_err_tlast));
              
endmodule
