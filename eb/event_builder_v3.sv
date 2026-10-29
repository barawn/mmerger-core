`timescale 1ns / 1ps
// Sigh. Try #3 for an event builder.
//
// This time we do things a little simpler:
// we use switches again to route the links to
// their location in the event header and order
// in the event, and just let software figure out
// how much to stream out.
// Converting this to a bundle build is harder,
// because then we have to build another interface
// to essentially do the same thing.
//
// But who knows, maybe we'll skip the bundle
// build portion and do that in software.
//
// From CPU side they need to repeatedly do
// DMA transfers of the header, but only
// need to check the identifier. Once it completes,
// then do *another* DMA transfer of the remaining
// length starting at the address above the
// header.

// Unlike the event builder v2, *this* version
// sees:
// 1: 8x completion stream inputs
// 2: 8x done stream outputs
// 3: a *single* input stream coming from the *single* DataMover in the FMN
// 4: a command stream to that data mover
// 5: a status stream from that data mover
// 6: a target and split interface.
`include "interfaces.vh"
module event_builder_v3 #(
            parameter WIDTH_IN=512,
            parameter COMPLETE_IN=64,
            parameter DONE_OUT=32,
            parameter NUM_LINKS=8,
            parameter SPLIT_OUT=256,
            parameter DEBUG_OUT=64,
            parameter DEBUG="TRUE"
        )(
        input dclk,
        input dreset,
        output [ SPLIT_OUT-1:0 ] m_ev_tdata,
        output                   m_ev_tvalid,
        input                    m_ev_tready,
        output                   m_ev_tlast,
        
        input aclk,
        input aresetn,

        // data from memory        
        input memclk,
        input memresetn,
        input [WIDTH_IN-1:0] s_axis_tdata,
        input                s_axis_tvalid,
        input                s_axis_tlast,
        output               s_axis_tready,
        // command path to datamover
        output [71:0] mm2s_cmd_tdata,
        output        mm2s_cmd_tvalid,
        input         mm2s_cmd_tready,
        // status path from datamover
        input [7:0]  mm2s_sts_tdata,
        input        mm2s_sts_tvalid,
        output       mm2s_sts_tready,

        input [NUM_LINKS-1:0] link_mask_i,
        input [15:0] detector_config_i,
        input event_tdest_i,
        // if we stall, this tells us who we're waiting on
        // and what tag it ended on
        output [NUM_LINKS-1:0] current_valid_o,
        output [7:0]           current_tag_o,
                                                
        // completion streams in
        input [COMPLETE_IN*NUM_LINKS-1:0] s_axis_cmpl_tdata,
        input [NUM_LINKS-1:0] s_axis_cmpl_tvalid,
        output [NUM_LINKS-1:0] s_axis_cmpl_tready,
        // done streams out
        output [DONE_OUT*NUM_LINKS-1:0] m_axis_done_tdata,
        output [NUM_LINKS-1:0] m_axis_done_tvalid,
        input [NUM_LINKS-1:0] m_axis_done_tready,
        // debug stream out (aclk)
        output [DEBUG_OUT-1:0] m_axis_dbg_tdata,
        output                 m_axis_dbg_tvalid,
        output                 m_axis_dbg_tlast,
        input                  m_axis_dbg_tready
    );

    `include "stream_functions.vh"
    
    localparam [31:0] IDENTVERSION = "Ev00";    

    // Only updatable while ARESET is asserted.
    reg [7:0] link_mask = {8{1'b0}};
    reg [15:0] detector_config = {16{1'b0}};
    always @(posedge aclk) begin
        if (!aresetn) begin 
            link_mask <= link_mask_i;
            detector_config <= detector_config_i;
        end
    end
     //////////////////////////////
    // DUMB DEFINITIONS         //
    //////////////////////////////
    
    // these are here to cut down on typing
    // giant-ass broadcaster
    `define axis_broadcast512x2 axis_broadcast #(.M_COUNT(2),           \
                                                 .DATA_WIDTH(COMPLETE_IN*NUM_LINKS),      \
                                                 .KEEP_ENABLE(1),       \
                                                 .LAST_ENABLE(0),       \
                                                 .ID_ENABLE(0),         \
                                                 .DEST_ENABLE(0),       \
                                                 .USER_ENABLE(0))
    `define axis_broadcast64x2 axis_broadcast #(.M_COUNT(2),            \
                                                .DATA_WIDTH(COMPLETE_IN),\
                                                .KEEP_ENABLE(0),        \
                                                .LAST_ENABLE(0),        \
                                                .ID_ENABLE(0),          \
                                                .DEST_ENABLE(0),        \
                                                .USER_ENABLE(0))

    // Giant-ass merged stream of all of the completion tags
    `DEFINE_AXI4S_MIN_IF( event_tags_ , NUM_LINKS*COMPLETE_IN );
    wire [(NUM_LINKS*COMPLETE_IN)/8 - 1:0] event_tags_tkeep;
    assign event_tags_tvalid = &(s_axis_cmpl_tvalid | link_mask);    
    assign event_tags_tdata = s_axis_cmpl_tdata;
    generate
        genvar ci;
        for (ci=0;ci<8;ci=ci+1) begin : RV
            assign event_tags_tkeep[(COMPLETE_IN/8)*ci +: (COMPLETE_IN/8)] = {(COMPLETE_IN/8){!link_mask[ci]}};
            // Combining is safe because the destination tvalid is not conditioned on the destination tready.
            // NOTE NOTE NOTE: we should actually peel off the complete_tdatas and shove them directly into the
            // refill when they're masked for assholes who run them through the event link, but I don't *THINK* it's an issue.
            assign s_axis_cmpl_tready[ci] = link_mask[ci] | (event_tags_tready && event_tags_tvalid);
        end
    endgenerate

    // Now these are out of the broadcaster.
    `DEFINE_AXI4S_MIN_IF( head_tags_ , NUM_LINKS*COMPLETE_IN );
    wire [(NUM_LINKS*COMPLETE_IN)/8 - 1:0] head_tags_tkeep;
    `DEFINE_AXI4S_MIN_IF( command_tags_ , NUM_LINKS*COMPLETE_IN );
    wire [(NUM_LINKS*COMPLETE_IN)/8 - 1:0] command_tags_tkeep;

    // We now broadcast the Giant Ass completion stream to two sources: first for the header calculation
    // and generation and second for the command generation.
    `axis_broadcast512x2 u_evbroadcast( .clk(aclk),.rst(!aresetn),
                                        `CONNECT_AXI4S_MIN_IF( s_axis_ , event_tags_ ),
                                        .s_axis_tkeep( event_tags_tkeep ),
                                        
                                        .m_axis_tdata( { head_tags_tdata, command_tags_tdata } ),
                                        .m_axis_tvalid({ head_tags_tvalid,command_tags_tvalid} ),
                                        .m_axis_tready({ head_tags_tready,command_tags_tready} ),
                                        .m_axis_tkeep ({ head_tags_tkeep, command_tags_tkeep } ));    
    // OK. Here's our attempt #3.
    // Reminder of format:
    // word 0: identversion
    // word 1: configstatus
    // word 2: total length
    // word 3: rsvd
    // word 4: rsvd
    // word 5: rsvd
    // word 6: frame pointer 0
    // word 7: frame pointer 1
    // word 8: frame pointer 2
    // word 9: frame pointer 3
    // word 10: frame pointer 4
    // word 11: frame pointer 5
    // word 12: frame pointer 6
    // word 13: frame pointer 7
    // word 14: frame pointer 8
    // word 15: frame pointer 9
    // Obviously the last two words are functionally reserved.
    // So we write "max frame #" in.
    // Then our build occurs with:
    // if all s_axis_cmpl_tvalid less than or equal to max frame # are set,
    // we write everything and pop the DataMover requests in
    // frame pointer 0 is always 40 (decimal)
    // frame pointer 1 is frame pointer 0 + BRCVD (frame 0)
    // frame pointer 2 is frame pointer 1 + BRCVD (frame 1)
    // So obviously this starts to look like a DSP chain. Let's do it that way.
    wire [NUM_LINKS*32-1:0] frame_pointers;
    wire [NUM_LINKS*23-1:0] brcvd;
    wire [23:0] total_length;

    // We'll need to delay the final "everything OK" until the DSP chain completes.
    // Really want to measure this though...!
    reg all_valid_reg = 0;
    reg begin_calc = 0;
    wire calc_done;
    reg header_is_valid = 0;
    `DEFINE_AXI4S_MIN_IF( header_ , 512 );
    assign header_tvalid = header_is_valid;
    assign head_tags_tready = header_tvalid && header_tready;
    // Output of FIFO.
    `DEFINE_AXI4S_MIN_IF( headerout_ , 512 );
    wire headerout_tlast = 1'b1;
    // the tuser inputs are the "actual tlast" inputs.
    wire headerout_tuser = 1'b0;
    
    // I'm going to relocate ALL of this inside a header generator. 
    // That way *this* module will literally be nothing but AXI4-streams and peeloffs.
    reg [7:0] tag = {8{1'b0}};
    always @(posedge aclk) begin    
        if (!aresetn || (header_tvalid && header_tready)) all_valid_reg <= 1'b0;
        else all_valid_reg <= head_tags_tvalid;

        if (!aresetn) tag <= 8'h00;
        else if (header_tvalid && header_tready) tag <= tag + 1;
        
        if (!aresetn) begin_calc <= 1'b0;
        else begin_calc <= (head_tags_tvalid && !all_valid_reg);
    
        if (!aresetn) header_is_valid <= 1'b0;
        else if (calc_done) header_is_valid <= 1'b1;
        else if (header_tready && header_tvalid) header_is_valid <= 1'b0;
    end
    
    wire [15:0] data_status;
    assign data_status[NUM_LINKS +: (16-NUM_LINKS)] = {(16-NUM_LINKS){1'b0}};
    generate
        genvar i;
        for (i=0;i<NUM_LINKS;i=i+1) begin : DEC_ADD
            // The complete stream is { error, brcvd, address }
            // However, we need to qualify these on the tkeep
            assign brcvd[23*i +: 23] = cmpl_brcvd(head_tags_tdata[COMPLETE_IN*i +: COMPLETE_IN]);
            assign data_status[i] = |cmpl_error(head_tags_tdata[COMPLETE_IN*i +: COMPLETE_IN], head_tags_tkeep[(COMPLETE_IN/8)*i +: (COMPLETE_IN/8)]);
        end
    endgenerate
    frame_pointer_calc_v3 u_frp_calc(.clk(aclk),
                                     .calc_i(begin_calc),
                                     .done_o(calc_done),
                                     .mask_i(link_mask),
                                     .brcvd_i(brcvd),
                                     .frameptr_o(frame_pointers),
                                     .tot_length_o(total_length));
    // Now construct the actual header.
    // IDENTVERSION
    localparam DWIDTH=32;
    assign header_tdata[DWIDTH*0 +: DWIDTH] = IDENTVERSION;
    // Detector config and data status.
    assign header_tdata[DWIDTH*1 +: DWIDTH] = { detector_config, data_status };
    // Total length and tag.
    assign header_tdata[DWIDTH*2 +: DWIDTH] = { tag, total_length };
    // 3/4/5 reserved.
    assign header_tdata[DWIDTH*3 +: DWIDTH] = {DWIDTH{1'b0}};
    assign header_tdata[DWIDTH*4 +: DWIDTH] = {DWIDTH{1'b0}};
    assign header_tdata[DWIDTH*5 +: DWIDTH] = {DWIDTH{1'b0}};
    // 6-Frame pointers. Let's see what nulling them out does to timing.
    assign header_tdata[DWIDTH*6 +: DWIDTH] =   (link_mask[0]) ? {DWIDTH{1'b0}} : frame_pointers[DWIDTH*0 +: DWIDTH];
    assign header_tdata[DWIDTH*7 +: DWIDTH] =   (link_mask[1]) ? {DWIDTH{1'b0}} : frame_pointers[DWIDTH*1 +: DWIDTH];
    assign header_tdata[DWIDTH*8 +: DWIDTH] =   (link_mask[2]) ? {DWIDTH{1'b0}} : frame_pointers[DWIDTH*2 +: DWIDTH];
    assign header_tdata[DWIDTH*9 +: DWIDTH] =   (link_mask[3]) ? {DWIDTH{1'b0}} : frame_pointers[DWIDTH*3 +: DWIDTH];
    assign header_tdata[DWIDTH*10 +: DWIDTH] =  (link_mask[4]) ? {DWIDTH{1'b0}} : frame_pointers[DWIDTH*4 +: DWIDTH];
    assign header_tdata[DWIDTH*11 +: DWIDTH] =  (link_mask[5]) ? {DWIDTH{1'b0}} : frame_pointers[DWIDTH*5 +: DWIDTH];
    assign header_tdata[DWIDTH*12 +: DWIDTH] =  (link_mask[6]) ? {DWIDTH{1'b0}} : frame_pointers[DWIDTH*6 +: DWIDTH];
    assign header_tdata[DWIDTH*13 +: DWIDTH] =  (link_mask[7]) ? {DWIDTH{1'b0}} : frame_pointers[DWIDTH*7 +: DWIDTH];
    assign header_tdata[DWIDTH*14 +: DWIDTH] = {DWIDTH{1'b0}};
    assign header_tdata[DWIDTH*15 +: DWIDTH] = {DWIDTH{1'b0}};

    // Then the header goes into the FIFO and through the frame joiner, and either to the
    // DMA or the RLDRAM datamover. 
    wire header_full;
    assign header_tready = !header_full;
    header_ccfifo u_fifo( .wr_clk(aclk), .rd_clk(memclk), .rst(!aresetn),
                          .din( header_tdata ),
                          .wr_en( header_tvalid && header_tready ),
                          .full(header_full),
                          .dout( headerout_tdata ),
                          .rd_en(headerout_tvalid && headerout_tready),
                          .valid(headerout_tvalid));                              

//    // And these are out of the resizer for the commands, which issues them in order.
//    `DEFINE_AXI4S_MIN_IF( command_ , COMPLETE_IN);
//    wire [(COMPLETE_IN/8)-1:0] command_tkeep;

    // OK, commanding path (command_tags_ AXI4-Stream).
    // However we strip off the errors (cuz we don't need 'em) and replace them with stream identifiers. So define a new...
    `DEFINE_AXI4S_MIN_IF( cmd_all_ , COMPLETE_IN*NUM_LINKS );
    wire [(COMPLETE_IN*NUM_LINKS/8)-1 : 0] cmd_all_tkeep;
    assign cmd_all_tkeep = command_tags_tkeep;
    assign cmd_all_tvalid = command_tags_tvalid;
    assign command_tags_tready = cmd_all_tready;
    // and strip the errors and replace them. We're going to peel these off and pass them as tags to the DataMover
    // and use those as TDESTs to reroute when complete. Which means we need to get the source from the completion.
    // We're ALSO going to determine if we're the last one and set that as a bit in the tag too. That way when it pops
    // out as done in the DataMover, we can push the event descriptor.
    // We *may* also use it to reset the stream path back? Not entirely sure about that, as they're in different
    // clock domains, so the handshaking's awkward.
    generate
        genvar j;
        for (j=0;j<NUM_LINKS;j=j+1) begin : REASSIGN
            wire [3:0] path = cmpl_path(command_tags_tdata[COMPLETE_IN*j +: COMPLETE_IN]);
            assign cmd_all_tdata[COMPLETE_IN*j +: (COMPLETE_IN-8)] = command_tags_tdata[COMPLETE_IN*j +: (COMPLETE_IN-8)];
            assign cmd_all_tdata[COMPLETE_IN*j + (COMPLETE_IN-8) +: 3] = path[2:0];
            if (j==NUM_LINKS-1) begin : TAIL
                // we only use one tkeep bit, cuz we know they're the same.
                // if my tkeep is set, I'm the last one.
                assign cmd_all_tdata[COMPLETE_IN*j + (COMPLETE_IN-5)] = cmd_all_tkeep[(COMPLETE_IN/8)*j];
            end else begin : BODY
                // if my tkeep bit is set and the NEXT guy isn't, I'm the last one
                assign cmd_all_tdata[COMPLETE_IN*j + (COMPLETE_IN-5)] = cmd_all_tkeep[(COMPLETE_IN/8)*j] && !cmd_all_tkeep[(COMPLETE_IN/8)*(j+1)];
            end
            assign cmd_all_tdata[COMPLETE_IN*j + (COMPLETE_IN-4) +: 4] = 4'h0;
        end
    endgenerate
    // First pass through resizer.
    `DEFINE_AXI4S_MIN_IF( cmd_single_ , COMPLETE_IN );
    wire [(COMPLETE_IN/8)-1:0] cmd_single_tkeep;
    // just use one, they're all the same
    wire cmd_single_keep_all = cmd_single_tkeep[0];
    command_downsize u_cmd_downsizer( .aclk(aclk),.aresetn(aresetn),
                                      `CONNECT_AXI4S_MIN_IF( s_axis_ , cmd_all_ ),
                                      .s_axis_tkeep( cmd_all_tkeep ),
                                      `CONNECT_AXI4S_MIN_IF( m_axis_ , cmd_single_ ),
                                      .m_axis_tkeep( cmd_single_tkeep ) );
                                      
    // Small FIFO to help buffer the event building a bit more, but we strip the null bytes here.
    `DEFINE_AXI4S_MIN_IF( cmd_out_ , COMPLETE_IN );
    wire cmd_single_full;
    assign cmd_single_tready = (!cmd_single_keep_all && cmd_single_tvalid) || !cmd_single_full;
    // this ILA is huge, don't use it if we don't need it
    generate
        if (DEBUG == "TRUE") begin : DBG
            command_ila u_ila(.clk(aclk),.probe0( cmd_all_tdata ),
                                         .probe1( cmd_all_tkeep ),
                                         .probe2( cmd_all_tready ),
                                         .probe3( cmd_all_tvalid ),
                                         .probe4( cmd_single_tdata ),
                                         .probe5( cmd_single_tkeep ),
                                         .probe6( cmd_single_tready ),
                                         .probe7( cmd_single_tvalid ),
                                         .probe8( cmd_single_full ));                                      
        end
    endgenerate
    

    cmd_single_fifo u_cmdfifo( .clk(aclk),.srst(!aresetn),
                            .din( cmd_single_tdata ),
                            .wr_en( cmd_single_tvalid && cmd_single_tready ),
                            .full( cmd_single_full ),
                            .dout( cmd_out_tdata ),
                            .valid(cmd_out_tvalid ),
                            .rd_en(cmd_out_tvalid && cmd_out_tready));
    // and broadcast it to both the DataMover and the address FIFO (grr)
    `DEFINE_AXI4S_MIN_IF( cmd_to_dm_ , COMPLETE_IN);
    `DEFINE_AXI4S_MIN_IF( cmd_to_addr_ , COMPLETE_IN);
    `axis_broadcast64x2 u_cmdaddrbroadcast( .clk(aclk),.rst(!aresetn),
                                            `CONNECT_AXI4S_MIN_IF( s_axis_ , cmd_out_ ),
                                            .m_axis_tdata( { cmd_to_addr_tdata , cmd_to_dm_tdata } ),
                                            .m_axis_tvalid({ cmd_to_addr_tvalid, cmd_to_dm_tvalid} ),
                                            .m_axis_tready({ cmd_to_addr_tready, cmd_to_dm_tready} ));
    // now assign the DataMover command.
    // Note the importance of using the cmpl_ functions here: the address
    // is actually expanded out.
    assign mm2s_cmd_tdata = dm_command( cmpl_address( cmd_to_dm_tdata ),    // address
                                        cmpl_brcvd(   cmd_to_dm_tdata ),    // brcvd
                                        cmd_to_dm_tdata[ 56 +: 4 ],         // tag
                                        cmd_to_dm_tdata[59],                // EOF (set TLAST: only for last frame)
                                        1'b1 );                             // incr
    assign mm2s_cmd_tvalid = cmd_to_dm_tvalid;
    assign cmd_to_dm_tready = mm2s_cmd_tready;
    // and the address FIFO
    `DEFINE_AXI4S_MIN_IF( mm2s_addr_ , 32 );
    // the address FIFO just peels off the address
    assign mm2s_addr_tdata = cmpl_address(cmd_to_addr_tdata);
    assign mm2s_addr_tvalid = cmd_to_addr_tvalid;
    assign cmd_to_addr_tready = mm2s_addr_tready;
    // output of the address FIFO...
    `DEFINE_AXI4S_MIN_IF( mm2s_outaddr_ , 32 );
    
    mm2s_addrfifo u_addrfifo( .s_aclk(aclk),.s_aresetn(aresetn),
                            `CONNECT_AXI4S_MIN_IF(s_axis_ , mm2s_addr_ ),
                            `CONNECT_AXI4S_MIN_IF(m_axis_ , mm2s_outaddr_ ));
    
    // We then link the address FIFO to the status FIFO back from the DataMover.
    // we **might** link this to an event push later, who knows...
    `DEFINE_AXI4S_MIN_IF( done_addrs_ , 32);
    wire [2:0] done_addrs_tdest;
    assign done_addrs_tdata = mm2s_outaddr_tdata;
    assign done_addrs_tdest = mm2s_sts_tdata[2:0];
    assign done_addrs_tvalid = mm2s_sts_tvalid && mm2s_outaddr_tvalid;
    assign mm2s_outaddr_tready = done_addrs_tready && done_addrs_tvalid;
    assign mm2s_sts_tready = done_addrs_tready && done_addrs_tvalid;
    
    // and now that goes through a switch, and it's done.
    doneaddr_switch u_doneaddr_switch( .aclk(aclk),.aresetn(aresetn),
                                       `CONNECT_AXI4S_MIN_IF( s_axis_ , done_addrs_ ),
                                       .s_axis_tdest(done_addrs_tdest),
                                       `CONNECT_AXI4S_MIN_IF( m_axis_ , m_axis_done_ ));
    
    //////////////////
    // MEMCLK LAND  //
    //////////////////
    
    // Our input streams are headerout_ and s_axis_. Merge into event_.
    `DEFINE_AXI4S_MIN_IF( eventall_ , 512 );
    wire eventall_tlast;
    reg event_tdest_aclk = 0;
    reg [1:0] eventall_tdest = {2{1'b0}};
    // We need to pop the both of them through a switch. We use the req_suppress
    // mechanism. One stream for each header.
    reg allow_data = 0;
    always @(posedge aclk) begin
        if (!aresetn) event_tdest_aclk <= event_tdest_i;
    end
    always @(posedge memclk) begin
        eventall_tdest <= { eventall_tdest[0], event_tdest_aclk };
        if (!memresetn) allow_data <= 0;
        else if (s_axis_tvalid && s_axis_tready && s_axis_tlast) allow_data <= 0;
        else if (headerout_tvalid && headerout_tready) allow_data <= 1;
    end
    wire [1:0] req_suppress = { !allow_data , allow_data };
    
    eb_data_switch u_dataswitch( .aclk(memclk),.aresetn(memresetn),
                                .s_axis_tdata({ s_axis_tdata , headerout_tdata } ),
                                .s_axis_tvalid({s_axis_tvalid, headerout_tvalid} ),
                                .s_axis_tready({s_axis_tready, headerout_tready} ),
                                // this is intentional, tlast is passed as tuser here
                                .s_axis_tuser( {s_axis_tlast,  headerout_tuser} ),
                                .s_axis_tlast( {s_axis_tlast,  headerout_tlast} ),
                                .s_req_suppress(req_suppress),
                                `CONNECT_AXI4S_MIN_IF( m_axis_ , eventall_ ),
                                // also intentional, we use tuser as the true tlast after being merged.
                                .m_axis_tuser( eventall_tlast ));   
    // and the switch to determine destination
    `DEFINE_AXI4S_MIN_IF( event_ , 512 );
    wire event_tlast;
    `DEFINE_AXI4S_MIN_IF( eventdbg_ , 512 );    
    wire eventdbg_tlast;
    eb_dbg_switch u_dbgswitch( .aclk(memclk),.aresetn(memresetn),
                               `CONNECT_AXI4S_MIN_IF( s_axis_ , eventall_ ),
                               .s_axis_tlast( eventall_tlast ),
                               .s_axis_tdest( eventall_tdest[1] ),
                               
                               .m_axis_tdata( { eventdbg_tdata, event_tdata } ),
                               .m_axis_tvalid({ eventdbg_tvalid, event_tvalid } ),
                               .m_axis_tready({ eventdbg_tready, event_tready } ),
                               .m_axis_tlast( { eventdbg_tlast, event_tlast } ) );
    // Debug path gets downsized before clock-crossing (it's just a debug path anyway)
    `DEFINE_AXI4S_MIN_IF( eventdbg64_ , 64 );
    wire eventdbg64_tlast;
    eb_dbg_widthconvert u_dbgwidthconv( .aclk(memclk),.aresetn(memresetn),
                                        `CONNECT_AXI4S_MIN_IF( s_axis_ , eventdbg_ ),
                                        .s_axis_tlast( eventdbg_tlast ),
                                        `CONNECT_AXI4S_MIN_IF( m_axis_ , eventdbg64_ ),
                                        .m_axis_tlast( eventdbg64_tlast ) );
    // Now clock cross.
    eb_dbg_ccfifo u_dbgccfifo( .s_aclk(memclk),.s_aresetn(memresetn),.m_aclk( aclk ),
                            `CONNECT_AXI4S_MIN_IF( s_axis_ , eventdbg64_ ),
                            .s_axis_tlast( eventdbg64_tlast ),
                            `CONNECT_AXI4S_MIN_IF( m_axis_ , m_axis_dbg_ ),
                            .m_axis_tlast( m_axis_dbg_tlast ));
     
    // Now we downsize this. This is ONLY DONE for the direct EB output ONLY.
    `DEFINE_AXI4S_MIN_IF( evnarrow_ , 256 );
    wire evnarrow_tlast;
    eb_event_downsize u_ev_downsize( .aclk(memclk), .aresetn(memresetn),
                                    `CONNECT_AXI4S_MIN_IF( s_axis_ , event_ ),
                                    .s_axis_tlast(event_tlast),
                                    `CONNECT_AXI4S_MIN_IF( m_axis_ , evnarrow_ ),
                                    .m_axis_tlast(evnarrow_tlast));
    eb_event_ccfifo u_event_ccfifo( .s_aclk(memclk), .m_aclk(dclk),
                                    .s_aresetn(memresetn),
                                    `CONNECT_AXI4S_MIN_IF( s_axis_ , evnarrow_ ),
                                    .s_axis_tlast( evnarrow_tlast ),
                                    `CONNECT_AXI4S_MIN_IF( m_axis_ , m_ev_ ),
                                    .m_axis_tlast( m_ev_tlast ));
                                    
    // So now split_ev_ can be directly coupled to the event DMA controller.
    
    // Then every time a request comes in, if it matches our address
    // *and* the FIFO is valid, we output its data. Otherwise
    // we output zeros.
    //
    // So let's state-machine sketch this out.
    // Our base starts at 0x0100_0000_0000_0000.
    // Events can't be larger than 1M, so we only need to pay attention to
    //                                  0F_FFFF.
    // (address[19:0]).
    // We're a 256-bit input so that means bits 0-4 are unimportant.
    //                                  0F_FFE0
    // and the header's 512-bit so we check
    //                                  0F_FFC0
    // So we check if bits [19:6] = 0
    // IDLE: dma_from_host_valid = 1
    //       if ([19:6] == 0) state <= HEADER_LENGTH;
    //       else state <= DATA_LENGTH;
    // HEADER_LENGTH: if (!dma_to_host_almost_full) state <= HEADER_OUTPUT_0;
    // HEADER_OUTPUT_0: if (dma_to_host_almost_full) state <= HEADER_STALL_0;
    //                  else if (length_remaining == 8) state <= HEADER_LAST_1;
    //                  else state <= HEADER_OUTPUT_1;
    // HEADER_OUTPUT_1: else if (dma_to_host_almost_full) state <= HEADER_STALL_1;
    //                  else if (length_remaining == 8) state <= HEADER_LAST_0;
    //                  else state <= HEADER_OUTPUT_0;
    // HEADER_STALL_0: if (!dma_to_host_almost_full) begin
    //                   if (length_remaining == 8) state <= HEADER_LAST_1;
    //                   else state <= HEADER_OUTPUT_1;
    //                 end
    // HEADER_STALL_1: if (!dma_to_host_almost_full) state <= HEADER_OUTPUT_0;
    // DATA_LENGTH: if (!dma_to_host_almost_full) state <= DATA_OUTPUT;
    // DATA_OUTPUT: if (!length_remaining 
    // 

    assign current_valid_o = s_axis_cmpl_tvalid | link_mask;
    assign current_tag_o = tag;
endmodule
