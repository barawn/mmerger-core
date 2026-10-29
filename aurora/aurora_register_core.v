`include "interfaces.vh"
`define DLYFF #1

`define NO_PREFIX_TAG( x )

module aurora_register_core #(
        parameter [31:0] IDENT = {32{1'b0}},
        parameter [31:0] DATEVERSION = {32{1'b0}},
        parameter WIDTH_IN = 64,
        parameter USER_IN = 7,
        parameter CONTROL_BITS = 6,
        parameter STATUS_BITS = 12,
        parameter ERR_BITS = 10,
        parameter NUM_LANES = 8,
        parameter NUM_REROUTES = 4,
        parameter FLOWCTRL_COUNT_WIDTH=8,
        parameter IN_STATISTICS_WIDTH=24,
        parameter OUT_STATISTICS_WIDTH=8,
        parameter DBG_STATISTICS_WIDTH=24,
        parameter ERR_STATISTICS_WIDTH=24,
        parameter PIPELINE_REG_READ = "TRUE" )(
        input clk,
        input reset,
        `TARGET_NAMED_PORTS_COMBINED_IF( `NO_PREFIX_TAG(dummy) ),
        // Aurora error/control/status.
        output [NUM_LANES*CONTROL_BITS-1:0] aurora_control,
        input [NUM_LANES*STATUS_BITS-1:0] aurora_status,
        input [NUM_LANES*ERR_BITS-1:0] aurora_err,
        
        input [ERR_STATISTICS_WIDTH-1:0] err_statistics,
        input [DBG_STATISTICS_WIDTH-1:0] dbg_statistics,
        
        input [NUM_LANES*IN_STATISTICS_WIDTH-1:0] in_statistics,
        input [NUM_LANES*OUT_STATISTICS_WIDTH-1:0] out_statistics,
        
        output [31:0] jam_delay_o,
        output        jam_disable_o,
        
        output [31:0] stuck_delay_o,
        output        stuck_disable_o,

        output [31:0] stop_delay_o,
        output        stop_disable_o,
        
        output [15:0] gt_reset_len_o,
        
        input [NUM_LANES*32-1:0] extra_error_i,
        
        output [NUM_LANES-1:0] swapendian,
        
        input [NUM_LANES*FLOWCTRL_COUNT_WIDTH-1:0] flowctrl_count,
        output [8*NUM_LANES-1:0] xoff_level,
        output [8*NUM_LANES-1:0] xoff_hysteresis,
                
        output [(NUM_LANES+NUM_REROUTES)*4-1:0] net_tdest_route,
        output [NUM_LANES*4-1:0] event_tdest_route,
        output areset,
        output update,
        
        input [WIDTH_IN-1:0] s_axis_tdata,
        input        s_axis_tvalid,
        output       s_axis_tready,
        input        s_axis_tlast,
        input [USER_IN-1:0]  s_axis_tuser        
    );
    // 1 ms
    localparam JAM_DELAY_DEFAULT =   100000;
    // 10 ms
    localparam STUCK_DELAY_DEFAULT = 1000000;
    // 1 ms
    localparam STOP_DELAY_DEFAULT =  100000;
    // 1.5 seconds
    localparam GT_RESET_LEN_DEFAULT = 5000;
    
    localparam NUM_LANE_ROUTES = 8;

    localparam MY_CONTROL_BITS = CONTROL_BITS + 1;

    localparam AURORA_ERR_BITS = 3;

    // The register core repeats for each of the 8 lanes:
    // register 100 : status/error (including flow drop/overflow and the common errors
    // register 108 : control (including the common areset control and lane mask in the lower qword)
    // register 110 : xoff level/hysteresis
    // register 118 : net route/event route
    // So this takes
    // 100
    // 120
    // 140
    // 160
    // 180
    // 1A0
    // 1C0
    // Then register 0200 is the error buffer read.
    localparam [15:0]   ADDR_AURORA_IDENT_MASK  =   16'h0300;
    localparam [15:0]   ADDR_AURORA_IDENT_BASE  =   16'h0000;
    localparam [15:0]   ADDR_AURORA_IDENT       =   16'h0000;
    localparam  [15:0]  ADDR_AURORA_DATEVERSION =   16'h0004;
    // The reroutes are handled special, to make sure they can't clash with the routes.
    localparam  [15:0]  ADDR_AURORA_REROUTE0    =   16'h0008;
    localparam  [15:0]  ADDR_AURORA_REROUTE1    =   16'h0010;
    localparam  [15:0]  ADDR_AURORA_REROUTE2    =   16'h0018;
    localparam  [15:0]  ADDR_AURORA_REROUTE3    =   16'h0020;
    // Error and debug statistics.
    localparam  [15:0]  ADDR_AURORA_ERRDBG_STAT =   16'h0028;    
    // Jam delay
    localparam  [15:0]  ADDR_AURORA_JAMDELAY    =   16'h0030;
    // Stuck delay
    localparam  [15:0]  ADDR_AURORA_STUCKDELAY  =   16'h0034;
    // Stop delay
    localparam  [15:0]  ADDR_AURORA_STOPDELAY   =   16'h0038;
    // Length of GT Reset assertion
    localparam  [15:0]  ADDR_AURORA_GTRESETLEN  =   16'h003C;
    
    // Additional error select
    localparam  [15:0]  ADDR_AURORA_ERRORSEL    =   16'h0040;
    // and the actual additional errors
    localparam  [15:0]  ADDR_AURORA_EXTRA_ERR   =   16'h0044;
    
    
    localparam  [15:0]  ADDR_AURORA_STATCOMMON  =   16'h0100;
    localparam  [15:0]  ADDR_AURORA_STATERROR   =   16'h0104;
    localparam  [15:0]  ADDR_AURORA_CTRLCOMMON  =   16'h0108;
    localparam  [15:0]  ADDR_AURORA_CTRL        =   16'h010C;
    localparam  [15:0]  ADDR_AURORA_FLOWCTRL    =   16'h0110;
    localparam  [15:0]  ADDR_AURORA_STATISTICS  =   16'h0114;
    localparam  [15:0]  ADDR_AURORA_NETROUTE    =   16'h0118;
    localparam  [15:0]  ADDR_AURORA_EVENTROUTE  =   16'h011C;
    
    // just do above address + lane*this
    localparam  [15:0]  ADDR_AURORA_LANE_BASE   =   16'h0100;
    localparam  [15:0]  ADDR_AURORA_LANE_OFFSET =   16'h0020;
    localparam integer NUM_AURORA_REGS=ADDR_AURORA_LANE_OFFSET[15:2];
    // anding address with this ignores which lane it's coming from
    // 1111 1111 0001 1111
    localparam  [15:0]  ADDR_AURORA_LANE_MASK   =   16'hFF1F;
    
    localparam  [15:0]  ADDR_AURORA_ERROR       =   16'h0200;
    localparam  [15:0]  ADDR_AURORA_ERROR_MASK  =   16'h0300;
        
    // The vwrap error mappings are
    // [0] = hard err
    // [1] = soft err
    // [2] = frame err
    // [3] = crc err
    // We also have
    // [4] = drop error
    // [5] = overflow error
    // hard/soft/frame are aurora errors.
    // CRC/drop/overflow are data errors.
    // the control maps are
    // [2:0] - loopback
    // [3] - powerdown
    // [4] - error reset
    // [5] - full reset
    // The vwrap status mappings are
    // [2:0] - current loopback mode
    // [3] - powerdown mode
    // [4] - tx reset done
    // [5] - rx reset done
    // [6] - channel up
    // [7] - lane up
    // [8] - tx lock
    // [9] - gt_powergood
    // 
    // rx_resetdone/tx_resetdone, powerdown, 3-bit loopback, tx_lock, GT powergood, channel up, lane up
    // lane_down is just !(channel_up && lane_up).
    // powerdown/3-bit loopback/error reset/full reset
    
    
    reg [7:0] lane_mask = {8{1'b0}};
    wire [7:0] lane_down;
    wire [7:0] lane_down_masked = lane_down & ~lane_mask;
    wire [7:0] lane_aurora_error;
    wire [7:0] lane_aurora_error_masked = lane_aurora_error & ~lane_mask;
    wire [7:0] lane_data_error;
    wire [7:0] lane_data_error_masked = lane_data_error & ~lane_mask;
    // So statcommon is just
    // [7:0] lane_down_masked
    // [23:16] lane_data_error_masked
    
    reg areset_rereg = 0;
    reg areset_reg = 0;
    assign update = (!areset_reg && areset_rereg);
    assign areset = areset_reg || areset_rereg;


    // Register logic. 16-bit address path, 64-bit data path.
    //% Reregistered write address.
    reg [15:0]  register_write_address_ff = {16{1'b0}};
    //% Reregistered write data.
    reg [63:0]  register_write_data_ff = {64{1'b0}};
    //% Reregistered byte enables.
    reg [7:0]   register_write_be_ff = {8{1'b0}};
    //% Reregistered write enable.
    reg         register_write_enable_ff = 0;
    //% Reregistered read address.
    reg [15:0]  register_read_address_ff = {16{1'b0}};
    //% Reregistered read enable.
    reg         register_read_enable_ff = 0;
    //% to flagify
    reg         register_read_enable_ff_reg = 0;
    //% Reregistered request tag.
    reg [7:0]   register_request_tag_ff = {8{1'b0}};

    wire        register_read_enable_sel = (PIPELINE_REG_READ == "TRUE") ? register_read_enable_ff :
                                                                           register_read_enable;
    wire [15:0] register_read_address_sel = (PIPELINE_REG_READ == "TRUE") ? register_read_address_ff :
                                                                            register_read_address[15:0];

    wire [7:0]  register_request_tag_sel = (PIPELINE_REG_READ == "TRUE") ? register_request_tag_ff :
                                                                           register_request_tag;
    //% Indicates we're ready.
    reg interface_ready_ff = 0;

    //% Indicates we're waiting for the clock-domain cross to complete.
    reg write_flag = 0;
    
    // Need to hold the read data tag, and control valid.
    //% Storage to echo the request tag back to the requester.
    reg [7:0]   register_read_data_tag_ff = {8{1'b0}};
    //% Indicates that the data on the bus is valid.
    reg         register_read_data_valid_ff = 0;
    //% Holds read data.
    reg [63:0]  register_read_data_ff = {64{1'b0}};

    // Jam delay and disable.
    reg [31:0]  jam_delay = JAM_DELAY_DEFAULT;
    assign jam_disable_o = (jam_delay == {32{1'b0}});
    assign jam_delay_o = jam_delay;
    // Stuck delay and disable.
    reg [31:0] stuck_delay = STUCK_DELAY_DEFAULT;
    assign stuck_disable_o = (stuck_delay == {32{1'b0}});
    assign stuck_delay_o = stuck_delay;
    // Stop delay and disable
    reg [31:0] stop_delay = STOP_DELAY_DEFAULT;
    assign stop_disable_o = (stop_delay == {32{1'b0}});
    assign stop_delay_o = stop_delay;
    // HP delay (how long to assert gt_reset)
    reg [15:0] gt_reset_len = GT_RESET_LEN_DEFAULT;
    assign gt_reset_len_o = gt_reset_len ;
    
    // extra error select
    reg [2:0] extra_error_sel = {3{1'b0}};
    wire [31:0] extra_errors = extra_error_i[(extra_error_sel)*32 +: 32];
    

    `define ADDRESS_MATCH( addr, write_addr, write_be ) \
        (( write_addr [15:3] == addr [15:3] ) && write_be [ addr [2]*4] )
    `define DATA_MATCH( addr, write_data, start, length ) \
        ( write_data [ ( addr [2] * 32 + start ) +: length ] )
    `define ASSIGN_IF_WRITE_MATCHES( addr , write_addr, write_be, register , write_data, length) \
        if (`ADDRESS_MATCH( addr, write_addr, write_be ) ) \
            register <= `DATA_MATCH( addr, write_data, 0, length)

    // This prevents multi-mapping outputs.
    // We allow multiply-assigning net routes 8-15 (so route[3] acts as an 'enable' for the check)
    // and event route 13-15 (so route[3:2] acts as an 'enable' for the check).
    reg [NUM_LANE_ROUTES-1:0] net_route_taken = {NUM_LANE_ROUTES{1'b0}};
    wire [NUM_LANES+NUM_REROUTES-1:0] net_route_taken_set[NUM_LANE_ROUTES-1:0];
    wire [NUM_LANES+NUM_REROUTES-1:0] net_route_taken_clear[NUM_LANE_ROUTES-1:0];

    reg [NUM_LANE_ROUTES+NUM_REROUTES-1:0] event_route_taken = {NUM_LANE_ROUTES+NUM_REROUTES{1'b0}};    
    wire [15:0] event_route_taken_exp = { {4{1'b0}}, event_route_taken };

    // we want to be able to loop over the first index and or out, so NUM_LANES is the lowest index
    wire [NUM_LANES-1:0] event_route_taken_set[NUM_LANE_ROUTES+NUM_REROUTES-1:0];
    wire [NUM_LANES-1:0] event_route_taken_clear[NUM_LANE_ROUTES+NUM_REROUTES-1:0];

    // Register muxing. This is 64 addresses. (8 groups of 8). Takes 6 bits to form 64 values. Only 5 are needed.
    wire [31:0] register_mux[NUM_LANES*8-1:0];
    wire [5:0] register_mux_address_low = {register_read_address_sel[3 +: 5],1'b0};
    wire [5:0] register_mux_address_high = {register_read_address_sel[3 +: 5],1'b1};

    wire [31:0] reroute_reg[3:0];
    wire [31:0] register_ident_mux[31:0];
    wire [4:0] register_ident_mux_address_low = {register_read_address_sel[3 +: 4],1'b0};
    wire [4:0] register_ident_mux_address_high = {register_read_address_sel[3 +: 4],1'b1};
    assign register_ident_mux[0] = IDENT;
    assign register_ident_mux[1] = DATEVERSION;    
    assign register_ident_mux[2] = reroute_reg[0];
    assign register_ident_mux[3] = {32{1'b0}};
    assign register_ident_mux[4] = reroute_reg[1];
    assign register_ident_mux[5] = {32{1'b0}};
    assign register_ident_mux[6] = reroute_reg[2];
    assign register_ident_mux[7] = {32{1'b0}};
    assign register_ident_mux[8] = reroute_reg[3];
    assign register_ident_mux[9] = {32{1'b0}};
    assign register_ident_mux[10] = { {(32-ERR_STATISTICS_WIDTH){1'b0}}, err_statistics };
    assign register_ident_mux[11] = { {(32-DBG_STATISTICS_WIDTH){1'b0}}, dbg_statistics };
    assign register_ident_mux[12] = jam_delay;
    assign register_ident_mux[13] = stuck_delay;
    assign register_ident_mux[14] = stop_delay;
    assign register_ident_mux[15] = gt_reset_len;

    assign register_ident_mux[16] = { {29{1'b0}}, extra_error_sel };
    assign register_ident_mux[17] = extra_errors;
    assign register_ident_mux[18] = register_ident_mux[2] ;
    assign register_ident_mux[19] = register_ident_mux[3] ;
    assign register_ident_mux[20] = register_ident_mux[4] ;
    assign register_ident_mux[21] = register_ident_mux[5] ;
    assign register_ident_mux[22] = register_ident_mux[6] ;
    assign register_ident_mux[23] = register_ident_mux[7] ;
    assign register_ident_mux[24] = register_ident_mux[8] ;
    assign register_ident_mux[25] = register_ident_mux[9] ;
    assign register_ident_mux[26] = register_ident_mux[10];
    assign register_ident_mux[27] = register_ident_mux[11];
    assign register_ident_mux[28] = register_ident_mux[12];
    assign register_ident_mux[29] = register_ident_mux[13];
    assign register_ident_mux[30] = register_ident_mux[14];
    assign register_ident_mux[31] = register_ident_mux[15];

    reg err_not_empty = 0;

    wire [31:0] aurora_statcommon = { err_not_empty, {7{1'b0}}, lane_data_error_masked, lane_aurora_error_masked, lane_down_masked };
    wire [31:0] aurora_ctrlcommon = { areset_reg, {23{1'b0}}, lane_mask };

    generate
        genvar ln,rr,nrr,nrb,erb;
        for (rr=0;rr<NUM_REROUTES;rr=rr+1) begin : RROUTE
            reg [3:0] reroute_route = {4{1'b1}};
            assign reroute_reg[rr] = { {28{1'b0}}, reroute_route }; 
            assign net_tdest_route[4*(NUM_LANES+rr) +: 4] = reroute_route;
            wire [15:0] local_reroute_addr = ADDR_AURORA_REROUTE0 + 8*rr;
            for (nrr=0;nrr<NUM_LANE_ROUTES;nrr=nrr+1) begin : NRR
                assign net_route_taken_set[nrr][NUM_LANES+rr] = (register_write_enable_ff &&
                                        `ADDRESS_MATCH(local_reroute_addr, register_write_address_ff, register_write_be_ff) &&
                                        !register_write_data_ff[ local_reroute_addr[2]*32 + 3] &&
                                        register_write_data_ff[ local_reroute_addr[2]*32 +: 3] == nrr);
                assign net_route_taken_clear[nrr][NUM_LANES+rr] = (register_write_enable_ff &&
                                        `ADDRESS_MATCH(local_reroute_addr, register_write_address_ff, register_write_be_ff) &&
                                        !reroute_route[3] &&
                                        reroute_route[2:0] == nrr);
            end
            always @(posedge clk) begin : RR_LOGIC
                    // netroute/eventroute are special, they take EFFORT.
                    if (`ADDRESS_MATCH(local_reroute_addr, register_write_address_ff, register_write_be_ff)) begin
                        if (register_write_data_ff[ local_reroute_addr[2]*32 + 3] == 1'b0) begin
                            // this isn't a dummy route, check if it can be set.
                            if (!net_route_taken[ register_write_data_ff[ local_reroute_addr[2]*32 +: 3 ] ])
                                reroute_route <= register_write_data_ff[ local_reroute_addr[2]*32 +: 4];
                        end else begin
                            // no checking from 8-15
                            reroute_route <= register_write_data_ff[ local_reroute_addr[2]*32 +: 4];
                        end
                    end
            end                
        end
        for (ln=0;ln<NUM_LANES;ln=ln+1) begin : LN
            assign lane_down[ln] = !(aurora_status[STATUS_BITS*ln + 6] && aurora_status[STATUS_BITS*ln + 7]);
            assign lane_data_error[ln] = (|aurora_err[ERR_BITS*ln + AURORA_ERR_BITS +: (ERR_BITS-AURORA_ERR_BITS)]);
            assign lane_aurora_error[ln] = (|aurora_err[ERR_BITS*ln +: AURORA_ERR_BITS]);
            reg [MY_CONTROL_BITS-1:0] lane_control = {MY_CONTROL_BITS{1'b0}};

            reg [15:0] xoff_hys_xoff = {{8{1'b0}},{8{1'b1}}};
            reg [3:0] net_route = {4{1'b1}};
            reg [3:0] event_route = {4{1'b1}};
            wire [FLOWCTRL_COUNT_WIDTH-1:0] this_flowctrl_count = flowctrl_count[FLOWCTRL_COUNT_WIDTH*ln +: FLOWCTRL_COUNT_WIDTH];
            wire [IN_STATISTICS_WIDTH-1:0] this_in_statistics = in_statistics[IN_STATISTICS_WIDTH*ln +: IN_STATISTICS_WIDTH];
            wire [OUT_STATISTICS_WIDTH-1:0] this_out_statistics = out_statistics[OUT_STATISTICS_WIDTH*ln +: OUT_STATISTICS_WIDTH];            
            // ADDR_AURORA_LANE_OFFSET is 0020 = 0000_0000_0010_0000. [15:2] is 0000_0000_0010_00, or 0x8.
            assign register_mux[ NUM_AURORA_REGS*ln + (ADDR_AURORA_STATCOMMON[15:2]) - ADDR_AURORA_LANE_BASE[15:2] ] = aurora_statcommon;
            assign register_mux[ NUM_AURORA_REGS*ln + (ADDR_AURORA_STATERROR[15:2]) - ADDR_AURORA_LANE_BASE[15:2] ] = 
                { {(16-ERR_BITS){1'b0}}, aurora_err[ERR_BITS*ln +: ERR_BITS], 
                  {(16-STATUS_BITS){1'b0}}, aurora_status[STATUS_BITS*ln +: STATUS_BITS] };
            assign register_mux[ NUM_AURORA_REGS*ln + (ADDR_AURORA_CTRLCOMMON[15:2]) - ADDR_AURORA_LANE_BASE[15:2]] = aurora_ctrlcommon;
            assign register_mux[ NUM_AURORA_REGS*ln + (ADDR_AURORA_CTRL[15:2]) - ADDR_AURORA_LANE_BASE[15:2]] = 
                { {(32-MY_CONTROL_BITS){1'b0}}, lane_control };
            // Flow control register. Now contains XOFF, XOFFHYS, and flow control count.
            assign register_mux[ NUM_AURORA_REGS*ln + (ADDR_AURORA_FLOWCTRL[15:2]) - ADDR_AURORA_LANE_BASE[15:2]] = { {8{1'b0}}, this_flowctrl_count, xoff_hys_xoff };
            assign register_mux[ NUM_AURORA_REGS*ln + (ADDR_AURORA_STATISTICS[15:2]) - ADDR_AURORA_LANE_BASE[15:2]] = { this_out_statistics, this_in_statistics };
            assign register_mux[ NUM_AURORA_REGS*ln + (ADDR_AURORA_NETROUTE[15:2]) - ADDR_AURORA_LANE_BASE[15:2]] = { {28{1'b0}}, net_route };
            assign register_mux[ NUM_AURORA_REGS*ln + (ADDR_AURORA_EVENTROUTE[15:2]) - ADDR_AURORA_LANE_BASE[15:2]] = { {28{1'b0}}, event_route };            
            assign aurora_control[CONTROL_BITS*ln +: CONTROL_BITS] = lane_control[0 +: CONTROL_BITS];
            assign xoff_level[8*ln +: 8] = xoff_hys_xoff[7:0];
            assign xoff_hysteresis[8*ln +: 8] = xoff_hys_xoff[15:8];
            assign net_tdest_route[4*ln +: 4] = net_route;
            assign event_tdest_route[4*ln +: 4] = event_route;
            // swapendian is the top bit
            assign swapendian[ln] = lane_control[CONTROL_BITS];

            wire [15:0] local_control_addr = ADDR_AURORA_CTRL + (ADDR_AURORA_LANE_OFFSET * ln);
            wire [15:0] local_flowctrl_addr = ADDR_AURORA_FLOWCTRL + (ADDR_AURORA_LANE_OFFSET * ln);
            wire [15:0] local_statistics_addr = ADDR_AURORA_STATISTICS + (ADDR_AURORA_LANE_OFFSET * ln);
            wire [15:0] local_netroute_addr = ADDR_AURORA_NETROUTE + (ADDR_AURORA_LANE_OFFSET * ln);
            wire [15:0] local_eventroute_addr = ADDR_AURORA_EVENTROUTE + (ADDR_AURORA_LANE_OFFSET * ln);      
            // route_taken[i][j] : [i] is the routing index, [j] is the lane index      
            for (nrb=0;nrb<NUM_LANE_ROUTES;nrb=nrb+1) begin : NR
                // This gets set even if the net route write is actually disallowed.
                // This is fine (and important, see below), because if it's disallowed, it's already set anyway.
                // We do have to ensure set takes priority over clear, because if someone tries to
                // write the *same* route, we don't want to clear the taken bit.
                // In this case, the taken bit and the clear bit will both be set,
                // the write won't happen (but it doesn't matter, obviously) and the route taken shouldn't update.
                
                // Set it if either the route or reroute is being updated to the target. Note that the route always has precedence
                // over the reroute (see below).
                assign net_route_taken_set[nrb][ln] = (register_write_enable_ff &&
                                           `ADDRESS_MATCH(local_netroute_addr, register_write_address_ff, register_write_be_ff) &&
                                           !register_write_data_ff[ local_netroute_addr[2]*32 + 3] && 
                                           register_write_data_ff[ local_netroute_addr[2]*32 +: 3] == nrb);
                // Clear it if either the route is being updated away from the destination.
                assign net_route_taken_clear[nrb][ln] = (register_write_enable_ff &&
                                            `ADDRESS_MATCH(local_netroute_addr, register_write_address_ff, register_write_be_ff) &&
                                            !net_route[3] &&
                                            net_route[2:0] == nrb);            
            end
            for (erb=0;erb<NUM_LANE_ROUTES+NUM_REROUTES;erb=erb+1) begin : ER
                assign event_route_taken_set[erb][ln] = (register_write_enable_ff &&
                                           `ADDRESS_MATCH(local_eventroute_addr, register_write_address_ff, register_write_be_ff) &&
                                           register_write_data_ff[ local_eventroute_addr[2]*32 +: 4] == erb);
                assign event_route_taken_clear[erb][ln] = (register_write_enable_ff &&
                                            `ADDRESS_MATCH(local_eventroute_addr, register_write_address_ff, register_write_be_ff) &&
                                            event_route[3:0] == erb);
            end
            always @(posedge clk) begin : LOGIC
                if (reset) begin
                    lane_control <= {MY_CONTROL_BITS{1'b0}};
                    xoff_hys_xoff[7:0] <= {8{1'b1}};
                    xoff_hys_xoff[15:8] <= {8{1'b0}};
                    net_route <= {4{1'b1}};
                    event_route <= {4{1'b1}};
                end else if (register_write_enable_ff) begin
                    `ASSIGN_IF_WRITE_MATCHES( local_control_addr, 
                                              register_write_address_ff, 
                                              register_write_be_ff,
                                              lane_control,
                                              register_write_data_ff,
                                              MY_CONTROL_BITS );
                    `ASSIGN_IF_WRITE_MATCHES( local_flowctrl_addr,
                                              register_write_address_ff, 
                                              register_write_be_ff,
                                              xoff_hys_xoff,
                                              register_write_data_ff,
                                              16 );
                    // netroute/eventroute are special, they take EFFORT.
                    if (`ADDRESS_MATCH(local_netroute_addr, register_write_address_ff, register_write_be_ff)) begin
                        if (register_write_data_ff[ local_netroute_addr[2]*32 + 3] == 1'b0) begin
                            // this isn't a dummy route, check if it can be set.
                            if (!net_route_taken[ register_write_data_ff[ local_netroute_addr[2]*32 +: 3 ] ])
                                net_route <= register_write_data_ff[ local_netroute_addr[2]*32 +: 4];
                        end else begin
                            // no checking from 8-15
                            net_route <= register_write_data_ff[ local_netroute_addr[2]*32 +: 4];
                        end
                    end
                    if (`ADDRESS_MATCH(local_eventroute_addr, register_write_address_ff, register_write_be_ff)) begin
                        if (register_write_data_ff[ (local_eventroute_addr[2]*32)+2 +: 2] != 2'b11) begin
                            // not a debug route, check if it can be set
                            if (!event_route_taken_exp[ register_write_data_ff[ local_eventroute_addr[2]*32 +: 4] ])
                                event_route <= register_write_data_ff[ local_eventroute_addr[2]*32 +: 4];
                        end else begin
                            // no checking 12-15
                            event_route <= register_write_data_ff[ local_eventroute_addr[2]*32 +: 4];
                        end
                    end
                end
            end
        end
    endgenerate

    integer nr_i, nr_j;
    integer er_i, er_j;
    // ignore the lane select bits                    
    wire [15:0] common_addr = (register_write_address_ff & ADDR_AURORA_LANE_MASK);
    always @(posedge clk) begin
        if (areset_reg) err_not_empty <= 1'b0;
        else begin
            if (s_axis_tready) err_not_empty <= 0;
            else if (s_axis_tvalid) err_not_empty <= 1;
        end
    
        if (reset) begin
            net_route_taken <= {NUM_LANE_ROUTES{1'b0}};
            event_route_taken <= {NUM_LANE_ROUTES+NUM_REROUTES{1'b0}};
        end else begin
            // index is [i][j] i = route (output), j = lane (input).
            // so iterate over number of routes, or-reduce the lanes
            
            // the net routes here are wider (they have more inputs),
            // but the or-reduce takes care of that for us.
            // the event routes have more outputs, so we need to iterate over them differently.
            for (nr_i=0;nr_i<NUM_LANE_ROUTES;nr_i=nr_i+1) begin
                if (|net_route_taken_set[nr_i]) net_route_taken[nr_i] <= 1'b1;
                else if (|net_route_taken_clear[nr_i]) net_route_taken[nr_i] <= 1'b0;
            end
            for (er_i=0;er_i<NUM_LANE_ROUTES+NUM_REROUTES;er_i=er_i+1) begin
                if (|event_route_taken_set[er_i]) event_route_taken[er_i] <= 1'b1;
                else if (|event_route_taken_clear[er_i]) event_route_taken[er_i] <= 1'b0;
            end
        end    
        if (reset) lane_mask <= {NUM_LANES{1'b0}};
        else if (register_write_enable_ff) begin
            // lane mask
            `ASSIGN_IF_WRITE_MATCHES( ADDR_AURORA_CTRLCOMMON,
                                      common_addr,
                                      register_write_be_ff,
                                      lane_mask,
                                      register_write_data_ff,
                                      8 );
        end
        if (reset) areset_reg <= 0;
        else if (register_write_enable_ff) begin
            if ((common_addr[15:3] == ADDR_AURORA_CTRLCOMMON[15:3]) &&
                register_write_be_ff[ ADDR_AURORA_CTRLCOMMON[2]*4 + 3 ] )
                areset_reg <= register_write_data_ff[ ADDR_AURORA_CTRLCOMMON[2]*32 + 31 ];
        end
        areset_rereg <= areset_reg;
        
        if (reset) begin
            jam_delay <= JAM_DELAY_DEFAULT;
            stuck_delay <= STUCK_DELAY_DEFAULT;        
            stop_delay <= STOP_DELAY_DEFAULT;
            gt_reset_len <= GT_RESET_LEN_DEFAULT;
            extra_error_sel <= {3{1'b0}};
        end else if (register_write_enable_ff) begin
            if (register_write_address_ff[15:3] == ADDR_AURORA_JAMDELAY[15:3]) begin
                if (register_write_be_ff[0]) jam_delay[7:0] <= register_write_data_ff[7:0];
                if (register_write_be_ff[1]) jam_delay[15:8] <= register_write_data_ff[15:8];
                if (register_write_be_ff[2]) jam_delay[23:16] <= register_write_data_ff[23:16];
                if (register_write_be_ff[3]) jam_delay[31:24] <= register_write_data_ff[31:24];
                if (register_write_be_ff[4]) stuck_delay[7:0] <= register_write_data_ff[32 +: 8];
                if (register_write_be_ff[5]) stuck_delay[15:8] <= register_write_data_ff[40 +: 8];
                if (register_write_be_ff[6]) stuck_delay[23:16] <= register_write_data_ff[48 +: 8];
                if (register_write_be_ff[7]) stuck_delay[31:24] <= register_write_data_ff[56 +: 8];
            end
            if (register_write_address_ff[15:3] == ADDR_AURORA_STOPDELAY[15:3]) begin
                if (register_write_be_ff[0]) stop_delay[7:0] <= register_write_data_ff[7:0];
                if (register_write_be_ff[1]) stop_delay[15:8] <= register_write_data_ff[15:8];
                if (register_write_be_ff[2]) stop_delay[23:16] <= register_write_data_ff[23:16];
                if (register_write_be_ff[3]) stop_delay[31:24] <= register_write_data_ff[31:24];
                if (register_write_be_ff[4]) gt_reset_len[7:0] <= register_write_data_ff[32 +: 8];
                if (register_write_be_ff[5]) gt_reset_len[15:8] <= register_write_data_ff[40 +: 8];
            end
            if (register_write_address_ff[15:3] == ADDR_AURORA_ERRORSEL[15:3]) begin
                if (register_write_be_ff[0]) extra_error_sel <= register_write_data_ff[2:0];
            end           
        end
            

        // Reregister everything coming in for easy timing.

        // only write_enable needs to be reset qualified, everything else qualifies on it
        if (reset) register_write_enable_ff <= 0;
        else register_write_enable_ff <= register_write_enable;

        register_write_enable_ff <= register_write_enable;
        register_write_address_ff <= register_write_address[15:0];
        register_write_data_ff <= register_write_data;
        register_write_be_ff <= register_write_be;
    
        // only read_enable_ff needs to be reset qualified, everything else qualifies on it
        // After here, we always refer to register_read_enable_ff as register_read_enable_sel
        // to allow autopipelining based on parameter.
        if (reset) register_read_enable_ff <= 0;
        else register_read_enable_ff <= register_read_enable;

        if (reset) register_read_enable_ff_reg <= 0;
        else register_read_enable_ff_reg <= register_read_enable_sel;
            
        // after here, we always refer to these with _sel postfix to
        // allow for autopipelining.
        register_read_address_ff <= register_read_address[15:0];
        register_request_tag_ff <= register_request_tag;
        
        // We're ready so long as a write isn't processing.
        if (reset) interface_ready_ff <= 0;
        else interface_ready_ff <= !register_write_enable && !register_write_enable_ff;
        
        // If a read enable is seen set valid to 1 unless in reset
        if (reset) register_read_data_valid_ff <= 0;
        else register_read_data_valid_ff <= register_read_enable_sel;
        
        // if read enable seen, store the tag
        if (register_read_enable_sel) register_read_data_tag_ff <= register_request_tag_sel;
        
        // read handling. Only capture stuff on read_enable high, doesn't matter otherwise.
        if  (register_read_enable_sel) begin
            if (((register_read_address_sel & ADDR_AURORA_IDENT_MASK) == ADDR_AURORA_IDENT_BASE)) begin
                register_read_data_ff[0 +: 32] <= register_ident_mux[register_ident_mux_address_low];
                register_read_data_ff[32 +: 32] <= register_ident_mux[register_ident_mux_address_high];
            end else if (((register_read_address_sel & ADDR_AURORA_ERROR_MASK) == ADDR_AURORA_ERROR) && !register_read_enable_ff_reg) begin
                // 7 user, valid, last = 9
                if (register_read_address_sel[3]) register_read_data_ff <= { {(64-2-USER_IN){1'b0}}, s_axis_tvalid, s_axis_tlast, s_axis_tuser };
                else register_read_data_ff <= (WIDTH_IN < 64) ? { {(64-WIDTH_IN){1'b0}}, s_axis_tdata } : s_axis_tdata;
            end else begin
                register_read_data_ff[0 +: 32] <= register_mux[register_mux_address_low];
                register_read_data_ff[32 +: 32] <= register_mux[register_mux_address_high];
            end             
        end
    end

    assign s_axis_tready = (register_read_enable_sel && !register_read_enable_ff_reg) && (register_read_address_sel == ADDR_AURORA_ERROR) && !register_read_address_sel[3] && !areset_reg;
        

    `undef ASSIGN_IF_WRITE_MATCHES
    `undef DATA_MATCH
    `undef ADDRESS_MATCH

    assign interface_ready = interface_ready_ff;

    assign register_read_data = register_read_data_ff;
    assign register_read_data_tag = register_read_data_tag_ff;
    assign register_read_data_valid = register_read_data_valid_ff;    

endmodule
`undef DLYFF