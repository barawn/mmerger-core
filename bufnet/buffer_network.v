`timescale 1ns/1ps

module buffer_network #( parameter WIDTH = 64,
                         parameter USER_WIDTH = 3,
                         parameter NUM_PATHS = 8,
                         parameter NUM_NET_IN = 12,
                         parameter NUM_EV_OUT = 13,
                         parameter DEBUG = "LITE" )
                       ( input aclk,
                         input aresetn,
                         // The network inputs have their routes attached via tdest
                         input [WIDTH*NUM_NET_IN-1:0] s_axis_tdata,
                         input [NUM_NET_IN-1:0] s_axis_tvalid,
                         input [USER_WIDTH*NUM_NET_IN-1:0] s_axis_tuser,
                         input [NUM_NET_IN-1:0] s_axis_tlast,
                         input [4*NUM_NET_IN-1:0] s_axis_tdest,
                         output [NUM_NET_IN-1:0] s_axis_tready,
                         // The network outputs need their routes fed in.
                         input [4*NUM_PATHS-1:0] evout_route,
                         
                         // Suppress debug arbitration cycles.
                         input [8:0] debug_suppress,
                         // Rerouted debug path from event builder
                         input  [WIDTH-1:0] s_ev_dbg_tdata,
                         input              s_ev_dbg_tvalid,
                         output             s_ev_dbg_tready,
                         input              s_ev_dbg_tlast,                         
                         
                         output [WIDTH*NUM_EV_OUT-1:0] m_axis_tdata,
                         output [NUM_EV_OUT-1:0] m_axis_tvalid,
                         output [USER_WIDTH*NUM_EV_OUT-1:0] m_axis_tuser,
                         output [NUM_EV_OUT-1:0] m_axis_tlast,
                         input [NUM_EV_OUT-1:0] m_axis_tready );
    // Let's try to add debug path sequencing.
    // We change the outbound switch from 8-to-13 to 8-to-12,
    // and put individual 1-to-2 switches at the output of each link,
    // plus an 8-to-1 switch to reduce them.
    // We can reuse the dump switch.
    localparam NUM_SWOUT = NUM_EV_OUT-1;
    localparam DBG_STREAM= NUM_EV_OUT-1;
    // These are the debug paths.
    wire [WIDTH*NUM_PATHS-1:0]      dp_tdata;
    wire [NUM_PATHS-1:0]            dp_tready;
    wire [NUM_PATHS-1:0]            dp_tvalid;
    wire [NUM_PATHS-1:0]            dp_tlast;
    wire [USER_WIDTH*NUM_PATHS-1:0] dp_tuser;
            
    // Fix issue #9. The dump path needs to be *individual* for each path. Because we mapped 8-15 all to the
    // dump path, this is actually easy: just add another switch in front, with tdest[3] shoved to it,
    // and dump the upper path.
    // Then pick off the remaining low 3 bits for the 'real' tdest.
    
    // These are the "undumped", after the dump switch.
    wire [WIDTH*NUM_NET_IN-1:0] netin_tdata;
    wire [NUM_NET_IN-1:0]       netin_tready;
    wire [NUM_NET_IN-1:0]       netin_tvalid;
    wire [NUM_NET_IN-1:0]       netin_tlast;
    wire [USER_WIDTH*NUM_NET_IN-1:0] netin_tuser;    
    wire [3*NUM_NET_IN-1:0]     netin_tdest;
    
    generate
        genvar in;
        for (in=0;in<NUM_NET_IN;in=in+1) begin : DS
            wire [WIDTH-1:0] dump_tdata;
            wire             dump_tvalid;
            wire             dump_tready = 1'b1;
            wire [USER_WIDTH-1:0] dump_tuser;
            wire             dump_tlast;
            bufnet_dump_switch u_dump_switch( .aclk(aclk),.aresetn(aresetn),
                                .s_axis_tdata(s_axis_tdata[WIDTH*in +: WIDTH]),
                                .s_axis_tvalid(s_axis_tvalid[in]),
                                .s_axis_tready(s_axis_tready[in]),
                                .s_axis_tlast(s_axis_tlast[in]),
                                .s_axis_tuser(s_axis_tuser[USER_WIDTH*in +: USER_WIDTH]),
                                .s_axis_tdest(s_axis_tdest[4*in + 3]),
                                .m_axis_tdata( { dump_tdata     , netin_tdata[WIDTH*in +: WIDTH] } ),
                                .m_axis_tvalid({ dump_tvalid    , netin_tvalid[in]               } ),
                                .m_axis_tlast( { dump_tlast     , netin_tlast[in]                } ),
                                .m_axis_tuser( { dump_tuser     , netin_tuser[USER_WIDTH*in +: USER_WIDTH] } ),
                                .m_axis_tready({ dump_tready    , netin_tready[in] } ),
                                .m_axis_tdest(),
                                .s_decode_err());
            assign netin_tdest[3*in +: 3] = s_axis_tdest[4*in +: 3];
        end
    endgenerate    
               
    wire [WIDTH*NUM_PATHS-1:0]  net_tdata;
    wire [NUM_PATHS:0]        net_tready;
    wire [NUM_PATHS:0]        net_tvalid;
    wire [NUM_PATHS:0]        net_tlast;
    wire [USER_WIDTH*NUM_PATHS-1:0]      net_tuser;
    
    wire [WIDTH*NUM_PATHS-1:0]  evin_tdata;
    wire [NUM_PATHS-1:0]        evin_tready;
    wire [NUM_PATHS-1:0]        evin_tvalid;
    wire [NUM_PATHS-1:0]        evin_tlast;
    wire [USER_WIDTH*NUM_PATHS-1:0]      evin_tuser;
    
    bufnet_switch_in u_inswitch( .aclk(aclk),.aresetn(aresetn),
                                .s_axis_tdata( netin_tdata),
                                .s_axis_tvalid(netin_tvalid),
                                .s_axis_tready(netin_tready),
                                .s_axis_tlast (netin_tlast),
                                .s_axis_tuser (netin_tuser),
                                .s_axis_tdest (netin_tdest),
                                .m_axis_tdata (net_tdata),
                                .m_axis_tready(net_tready),
                                .m_axis_tvalid(net_tvalid),
                                .m_axis_tlast (net_tlast),
                                .m_axis_tuser (net_tuser),
                                .m_axis_tdest(),
                                .s_decode_err());

    generate
        genvar path;
        for (path=0;path<NUM_PATHS;path=path+1) begin : BUFS
            // Temporary path to the dump switch.
            wire [WIDTH-1:0]        path_tdata;
            wire                    path_tvalid;
            wire                    path_tready;
            wire                    path_tlast;
            wire [USER_WIDTH-1:0]   path_tuser;
            // OK, this is hackery: the routes are 0-11 => event/reroute switch, 12+ -> debug switch
            // So just checking the top two bits will do it.
            wire                    path_tdest = (evout_route[4*path+2 +: 2] == 2'b11);
            if (path == 0) begin : LARGE
                // Large paths get 3 medium buffers (stupid Xilinx).
                wire [WIDTH-1:0]      b0_tdata;
                wire                  b0_tready;
                wire                  b0_tlast;
                wire                  b0_tvalid;
                wire [USER_WIDTH-1:0] b0_tuser;
                
                wire [WIDTH-1:0]      b1_tdata;
                wire                  b1_tready;
                wire                  b1_tlast;
                wire                  b1_tvalid;
                wire [USER_WIDTH-1:0] b1_tuser;

                bufnet_medium u_large0(.s_aclk(aclk),.s_aresetn(aresetn),
                                    .s_axis_tdata( net_tdata[WIDTH*path +: WIDTH]),
                                    .s_axis_tvalid(net_tvalid[path]),
                                    .s_axis_tready(net_tready[path]),
                                    .s_axis_tuser (net_tuser[USER_WIDTH*path +: USER_WIDTH]),
                                    .s_axis_tlast (net_tlast[path]),
                                    .m_axis_tdata (b0_tdata),
                                    .m_axis_tvalid(b0_tvalid),
                                    .m_axis_tready(b0_tready),
                                    .m_axis_tuser (b0_tuser),
                                    .m_axis_tlast (b0_tlast));                                    
                bufnet_medium u_large1(.s_aclk(aclk),.s_aresetn(aresetn),
                                    .s_axis_tdata( b0_tdata),
                                    .s_axis_tvalid(b0_tvalid),
                                    .s_axis_tready(b0_tready),
                                    .s_axis_tuser (b0_tuser),
                                    .s_axis_tlast (b0_tlast),
                                    .m_axis_tdata (b1_tdata),
                                    .m_axis_tvalid(b1_tvalid),
                                    .m_axis_tready(b1_tready),
                                    .m_axis_tuser (b1_tuser),
                                    .m_axis_tlast (b1_tlast));                                    
                bufnet_medium u_large2(.s_aclk(aclk),.s_aresetn(aresetn),
                                    .s_axis_tdata( b1_tdata),
                                    .s_axis_tvalid(b1_tvalid),
                                    .s_axis_tready(b1_tready),
                                    .s_axis_tuser (b1_tuser),
                                    .s_axis_tlast (b1_tlast),
                                    .m_axis_tdata (path_tdata),
                                    .m_axis_tvalid(path_tvalid),
                                    .m_axis_tready(path_tready),
                                    .m_axis_tuser (path_tuser),
                                    .m_axis_tlast (path_tlast));                
            end
            if (path == 1) begin : MEDIUM
                // Medium paths get the medium buffer.
                bufnet_medium u_medium(.s_aclk(aclk),.s_aresetn(aresetn),
                                    .s_axis_tdata( net_tdata[WIDTH*path +: WIDTH]),
                                    .s_axis_tvalid(net_tvalid[path]),
                                    .s_axis_tready(net_tready[path]),
                                    .s_axis_tuser (net_tuser[USER_WIDTH*path +: USER_WIDTH]),
                                    .s_axis_tlast (net_tlast[path]),
                                    .m_axis_tdata (path_tdata),
                                    .m_axis_tvalid(path_tvalid),
                                    .m_axis_tready(path_tready),
                                    .m_axis_tuser (path_tuser),
                                    .m_axis_tlast (path_tlast));                                    
            end
            if (path == 2 || path == 3) begin : SMALL
                // Small paths get the small buffer.
                bufnet_small u_small(.s_aclk(aclk),.s_aresetn(aresetn),
                                    .s_axis_tdata( net_tdata[WIDTH*path +: WIDTH]),
                                    .s_axis_tvalid(net_tvalid[path]),
                                    .s_axis_tready(net_tready[path]),
                                    .s_axis_tuser (net_tuser[USER_WIDTH*path +: USER_WIDTH]),
                                    .s_axis_tlast (net_tlast[path]),
                                    .m_axis_tdata (path_tdata),
                                    .m_axis_tvalid(path_tvalid),
                                    .m_axis_tready(path_tready),
                                    .m_axis_tuser (path_tuser),
                                    .m_axis_tlast (path_tlast));                                    
            end 
            if (path > 3) begin : TINY
                // Tiny paths get the tiny buffer.
                bufnet_tiny u_tiny(.s_aclk(aclk),.s_aresetn(aresetn),
                                    .s_axis_tdata( net_tdata[WIDTH*path +: WIDTH]),
                                    .s_axis_tvalid(net_tvalid[path]),
                                    .s_axis_tready(net_tready[path]),
                                    .s_axis_tuser (net_tuser[USER_WIDTH*path +: USER_WIDTH]),
                                    .s_axis_tlast (net_tlast[path]),
                                    .m_axis_tdata (path_tdata),
                                    .m_axis_tvalid(path_tvalid),
                                    .m_axis_tready(path_tready),
                                    .m_axis_tuser (path_tuser),
                                    .m_axis_tlast (path_tlast));                                    
            end
            // Now we need a simple destination switch to determine which router we go to.
            bufnet_dump_switch u_droute(.aclk(aclk),.aresetn(aresetn),
                                        .s_axis_tdata(  path_tdata  ),
                                        .s_axis_tvalid( path_tvalid ),
                                        .s_axis_tready( path_tready ),
                                        .s_axis_tuser(  path_tuser  ),
                                        .s_axis_tlast(  path_tlast  ),
                                        .s_axis_tdest(  path_tdest  ),
                                        .m_axis_tdata(  { dp_tdata[WIDTH*path +: WIDTH], evin_tdata[WIDTH*path +: WIDTH] } ),
                                        .m_axis_tvalid( { dp_tvalid[path], evin_tvalid[path] } ),
                                        .m_axis_tready( { dp_tready[path], evin_tready[path] } ),
                                        .m_axis_tlast(  { dp_tlast[path],  evin_tlast[path]  } ),
                                        .m_axis_tuser(  { dp_tuser[USER_WIDTH*path +: USER_WIDTH], evin_tuser[USER_WIDTH*path +: USER_WIDTH] } ));                                        
        end
    endgenerate
    // Note that the evout_route here could *conceivably* be an invalid route,
    // but it will never happen when there's valid data there because "invalid routes"
    // all map to the debug path, which diverts data away from here.
    //
    // Note this is also going to help us move to the control routing switch method
    // to save resources, because this is now a fixed point-to-point routing matrix.
    // Just need to translate the Dini accesses into AXI4-Lite.
    bufnet_switch_out u_outswitch( .aclk(aclk),.aresetn(aresetn),
                                    .s_axis_tdata ( evin_tdata ),
                                    .s_axis_tvalid( evin_tvalid),
                                    .s_axis_tready( evin_tready),
                                    .s_axis_tlast ( evin_tlast ),
                                    .s_axis_tuser ( evin_tuser ),
                                    .s_axis_tdest ( evout_route),
                                    
                                    .m_axis_tdata ( m_axis_tdata[0 +: WIDTH*NUM_SWOUT]  ),
                                    .m_axis_tvalid( m_axis_tvalid[0 +: NUM_SWOUT]  ),
                                    .m_axis_tready( m_axis_tready[0 +: NUM_SWOUT]  ),
                                    .m_axis_tuser ( m_axis_tuser[0 +: USER_WIDTH*NUM_SWOUT]  ),
                                    .m_axis_tlast ( m_axis_tlast[0 +: NUM_SWOUT]  ),
                                    .m_axis_tdest(),
                                    .s_decode_err() );
    // And here's the other part of the switch.
    // We add a holdoff to prevent rapid arbitration cycles with really short events.
    // This is because if an event is only, say, 1 clock long, the downstream control
    // won't be able to see that the event has arrived and turn off arbitration.
    // Shouldn't do anything with long events.
    reg              req_suppress_holdoff = 0;
    wire             req_suppress_holdoff_reached;
    wire [8:0]       req_suppress = (req_suppress_holdoff) ? 9'h1FF : debug_suppress;
   // start holdoff at an arbitration cycle, clear it when the frame completes
   
    // Full debug path includes the rerouted event debug path at the top.  
    wire [8:0] all_dbg_tvalid = { s_ev_dbg_tvalid, dp_tvalid };    
    wire [8:0] all_dbg_tready;
    assign dp_tready = all_dbg_tready[7:0];
    assign s_ev_dbg_tready = all_dbg_tready[8];
    wire [8:0] all_dbg_tlast = { s_ev_dbg_tlast, dp_tlast };
    wire [WIDTH*(NUM_PATHS+1)-1:0] all_dbg_tdata = { s_ev_dbg_tdata , dp_tdata };
    wire [USER_WIDTH*(NUM_PATHS+1)-1:0] all_dbg_tuser = { {3{1'b0}}, dp_tuser };
    
    always @(posedge aclk) begin
        if (!aresetn) req_suppress_holdoff <= 0;
        else if (|(all_dbg_tvalid & all_dbg_tready & all_dbg_tlast) && req_suppress_holdoff_reached) req_suppress_holdoff <= 0;
        else if (|(all_dbg_tvalid & all_dbg_tready)) req_suppress_holdoff <= 1;
    end
    dsp_counter_terminal_count #(.FIXED_TCOUNT("TRUE"),.HALT_AT_TCOUNT("TRUE"),.FIXED_TCOUNT_VALUE(4))
        u_suppress_holdoff( .clk_i(aclk),
                            .rst_i(!req_suppress_holdoff),
                            .count_i(req_suppress_holdoff && !req_suppress_holdoff_reached),
                            .tcount_reached_o(req_suppress_holdoff_reached));
    
    
    bufnet_debug_switch u_dbgswitch( .aclk(aclk),.aresetn(aresetn),
                                     .s_axis_tdata( all_dbg_tdata ),
                                     .s_axis_tvalid(all_dbg_tvalid),
                                     .s_axis_tready(all_dbg_tready),
                                     .s_axis_tuser( all_dbg_tuser ),
                                     .s_axis_tlast( all_dbg_tlast ),
                                     .m_axis_tdata( m_axis_tdata[WIDTH*DBG_STREAM +: WIDTH] ),
                                     .m_axis_tvalid(m_axis_tvalid[DBG_STREAM]),
                                     .m_axis_tready(m_axis_tready[DBG_STREAM]),
                                     .m_axis_tuser (m_axis_tuser[USER_WIDTH*DBG_STREAM +: USER_WIDTH] ),
                                     .m_axis_tlast (m_axis_tlast[DBG_STREAM]),
                                     .s_req_suppress(req_suppress));
    generate
        if (DEBUG == "LITE" || DEBUG == "FULL") begin : DBGANY
            wire [2:0] in_link_select;
            wire [2:0] out_link_select;
            wire out_select; // only for 'lite' debugging
            reg [63:0] debug_in_tdata = {64{1'b0}};
            reg [63:0] debug_out_tdata = {64{1'b0}};
            reg debug_in_tvalid = 0;
            reg debug_out_tvalid = 0;
            reg debug_in_tready = 0;
            reg debug_out_tready = 0;
            reg debug_in_tlast = 0;
            reg debug_out_tlast = 0;
            reg debug_in_tstart = 0;
            reg debug_out_tstart = 0;
            always @(posedge aclk) begin : DBGMUX
                debug_in_tdata <= s_axis_tdata[in_link_select*WIDTH +: WIDTH];
                debug_out_tdata <= m_axis_tdata[out_link_select*WIDTH +: WIDTH];
                debug_in_tvalid <= s_axis_tvalid[in_link_select];
                debug_out_tvalid <= m_axis_tvalid[out_link_select];
                debug_in_tready <= s_axis_tready[in_link_select];
                debug_out_tready <= m_axis_tready[out_link_select];
                debug_in_tlast <= s_axis_tlast[in_link_select];
                debug_out_tlast <= m_axis_tlast[out_link_select];
                debug_in_tstart <= s_axis_tuser[USER_WIDTH*in_link_select];
                debug_out_tstart <= m_axis_tuser[USER_WIDTH*out_link_select];
            end
            if (DEBUG == "LITE") begin : LITEILA
                // lite only views either in or out
                reg [63:0] debug_tdata = {64{1'b0}};
                reg debug_tvalid = 0;
                reg debug_tready = 0;
                reg debug_tlast = 0;
                reg debug_tstart = 0;
                always @(posedge aclk) begin : LITEMUX
                    if (out_select) begin
                        debug_tdata <= debug_out_tdata;
                        debug_tvalid <= debug_out_tvalid;
                        debug_tready <= debug_out_tready;
                        debug_tlast <= debug_out_tlast;
                        debug_tstart <= debug_out_tstart;
                    end else begin
                        debug_tdata <= debug_in_tdata;
                        debug_tvalid <= debug_in_tvalid;
                        debug_tready <= debug_in_tready;
                        debug_tlast <= debug_in_tlast;
                        debug_tstart <= debug_in_tstart;
                    end
                end // LITEMUX
                bufnet_ila_lite u_ila(.clk(aclk),
                                        .probe0(debug_tdata),
                                        .probe1(debug_tvalid),
                                        .probe2(debug_tready),
                                        .probe3(debug_tlast),
                                        .probe4(debug_tstart));
            end // LITEILA
            else begin : FULLILA
                bufnet_ila u_ila(.clk(aclk),
                                .probe0(debug_in_tdata),
                                .probe1(debug_in_tvalid),
                                .probe2(debug_in_tready),
                                .probe3(debug_in_tlast),
                                .probe4(debug_in_tstart),
                                .probe5(debug_out_tdata),
                                .probe6(debug_out_tvalid),
                                .probe7(debug_out_tready),
                                .probe8(debug_out_tlast),
                                .probe9(debug_out_tstart));
            end // FULLILA
            bufnet_vio u_vio(.clk(aclk),
                             .probe_in0(aresetn),
                             .probe_out0(in_link_select),
                             .probe_out1(out_link_select),
                             .probe_out2(out_select));
        end // DBGANY
    endgenerate
                                
endmodule
