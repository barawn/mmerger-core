`timescale 1ns/1ps

module event_processor #(   parameter NUM_LINKS=8,
                            parameter NUM_FRAMES=10,
                            parameter COMPLETE_IN=56,
                            parameter DONE_IN=64,
                            parameter DEBUG="TRUE" )
                        (   input aclk,
                            input aresetn,
                            input [NUM_LINKS*COMPLETE_IN-1:0]   s_axis_cmpl_tdata,
                            input [NUM_LINKS-1:0]               s_axis_cmpl_tvalid,
                            output [NUM_LINKS-1:0]              s_axis_cmpl_tready,
                            
                            // This allows the streaming for the other links through the stream switch.
                            output [NUM_LINKS-1:0]              stream_allow_o,
                            output [NUM_LINKS-1:0]              stream_last_o,
                            // These are configuration constants from the event builder's register interface.
                            // Right now this is just the "detector configuration" buried within the
                            // data status flag.
                            input [15:0]                        config_i,   
                            // Timeout after seeing a nonzero complete from one that an error is declared
                            input [15:0]                        timeout_i,
                            // These indicate frames that shouldn't go into events. 8 and 9 right now
                            // are special-magic inside the event processor.                         
                            input [NUM_FRAMES-1:0]              frame_mask_i,
                            // config_i/frame_mask_i are only updated after exit of reset (at enable)
                            input                               enable_i,
                            output [7:0]                        state_o,
                            
                            input [NUM_LINKS*DONE_IN-1:0]       s_axis_done_tdata,
                            input [NUM_LINKS-1:0]               s_axis_done_tvalid,
                            output [NUM_LINKS-1:0]              s_axis_done_tready,
                            
                            input [NUM_LINKS-1:0]               stream_done_i,
                             
                            output [511:0]                      m_axis_evhd_tdata,
                            output                              m_axis_evhd_tvalid,
                            input                               m_axis_evhd_tready,
                            
                            // This is what drives either the DMA readout,
                            // or the DataMover for the event storage.
                            // It's really just pulled off from the event header stream.
                            // (we check BOTH evhd_tready and evtag_tready)
                            // 32-bit length, 8 bit tag (just incrementing from 0).
                            output [39:0]                       m_axis_evtag_tdata,
                            output                              m_axis_evtag_tvalid,
                            input                               m_axis_evtag_tready,
                            
                            output [31:0]                       m_axis_err_tdata,
                            output                              m_axis_err_tvalid,
                            input                               m_axis_err_tready);

    // Each event has a header of 64 bytes, which is 16 32-bit words.
    // 10 of those are frame pointers, for up to 10 frames/event.
    // This is more than we need, this is for 'safety margin'
    // (there's a way that we could sneak extra crap on, I can imagine useful ways to do this)
    // First dword is "Ev00" (Nahee has the order backwards)
    // 2nd dword is (detector conf/data status)
    // 3rd word is total length.
    // 4th/5th/6th words are reserved.
    // 7-16 are the frame pointers, NULL if not present.
    // They're *** byte *** pointers past their own location.
    // As in, "frame_ptr[0]" should be 40, always: there are 9 frame pointers ahead of it,
    // each is 4 bytes, plus itself = 40 = (0x28)
    // Then if the total length of frame[0] is 0x80 bytes, frame_ptr[1] would be
    // 0xA8.
    localparam [15:0] IDENTIFIER = "Ev";
    localparam [15:0] VERSION = "00";

    localparam [31:0] RESERVED4 = {32{1'b0}};
    localparam [31:0] RESERVED5 = {32{1'b0}};
    localparam [31:0] RESERVED6 = {32{1'b0}};

    reg [31:0] total_length = {32{1'b0}};
    reg [7:0]  tag          = {8{1'b0}};
    
    reg [15:0] config_reg = {16{1'b0}};
    reg [15:0] data_status = {16{1'b0}};    
    reg [31:0] frame_ptr[NUM_FRAMES-1:0];
    integer fi;
    initial for (fi=0;fi<NUM_FRAMES;fi=fi+1) frame_ptr[fi] <= {32{1'b0}};
    
    wire [511:0] event_header_in = { frame_ptr[9],
                                     frame_ptr[8],
                                     frame_ptr[7],
                                     frame_ptr[6],
                                     frame_ptr[5],
                                     frame_ptr[4],
                                     frame_ptr[3],
                                     frame_ptr[2],
                                     frame_ptr[1],
                                     frame_ptr[0],
                                     RESERVED6,
                                     RESERVED5,
                                     RESERVED4,
                                     total_length,
                                     { config_reg, data_status },
                                     { IDENTIFIER, VERSION } };
    assign m_axis_evhd_tdata = event_header_in;                                     
    reg evheader_wr = 0;
    assign m_axis_evhd_tvalid = evheader_wr;
    
    assign m_axis_evtag_tdata = { tag, total_length };
    assign m_axis_evtag_tvalid = evheader_wr;    
    
    reg [7:0] stream_allow = {8{1'b0}};
    assign stream_allow_o = stream_allow;
    reg [7:0] stream_last = {8{1'b0}};
    assign stream_last_o = stream_last;    
    reg [2:0] complete_select = {3{1'b0}};
    reg [2:0] done_select = {3{1'b0}};    
    reg [NUM_LINKS-1:0] complete_tready = {NUM_LINKS{1'b0}};
    assign s_axis_cmpl_tready = complete_tready;
    reg [NUM_LINKS-1:0] done_tready = {NUM_LINKS{1'b0}};
    assign s_axis_done_tready = done_tready;
    
    wire [DONE_IN-1:0] done_tdata = s_axis_done_tdata[DONE_IN*done_select +: DONE_IN];
    wire [COMPLETE_IN-1:0] cmpl_tdata = s_axis_cmpl_tdata[COMPLETE_IN*complete_select +: COMPLETE_IN];
    
    wire [NUM_LINKS-1:0] everything_done = (s_axis_done_tvalid & stream_done_i);
    
    reg [31:0] error_tdata = {32{1'b0}};
    assign m_axis_err_tdata = error_tdata;
    reg        error_tvalid = 0;    
        
    reg [7:0]   state = {8{1'b0}};        
        
    reg [7:0] pb_inport = {8{1'b0}};
    wire [7:0] pb_outport;
    wire [7:0] pb_port;
    wire [11:0] pb_address;
    wire [17:0] pb_instr;
    wire        pb_write;
    wire        pb_kwrite;
    wire [7:0] pb_hyport = (pb_kwrite) ? { {4{1'b0}}, pb_port[3:0] } : pb_port;
    wire        pb_hywrite = (pb_write || pb_kwrite);
    wire        pb_read;
    wire        pb_bram_en;
    wire        pb_reset = !enable_i || !aresetn;
    
    // REGISTER SPACE
    // Need 10*4 = 40 addresses for the frame pointers, so give them 64 = 1/4th of address space.    
    // = 40-7F
    // assign register 0 = stream_allow (use write/kwrite) - flags only         write
    // assign register 1 = complete select                                      write
    // assign register 2 = done select                                          write
    // assign register 3 = header write (use write/kwrite)                      read/write
    // assign register 4 = data status 0                                        write
    // assign register 5 = data status 1                                        write
    // assign register 6 = complete tvalid / complete tready (use write/kwrite) read/write
    // assign register 7 = done tvalid / done tready (use write/kwrite)         read/write
    // assign register 8-B: error data                                          write
    // assign register C = error tvalid/tready                                  read/write
    // assign register D = stream last                                          write
    // assign register E/F = config value (read-hywrite)                        read/write
    // assign register 10-17: complete                                          read
    // assign register 18-1F: done                                              read
    // assign register 20/21 = timeout value (read)                             read
    // assign register 22/23 = frame mask                                       read
    // assign register 24-27 = total length                                     write
    // assign register 28 = tag                                                 write
    // Everything else can basically be reserved, maybe I'll add a debuggy state or something.
    integer i;
    always @(posedge aclk) begin
    
        stream_allow <= (pb_hywrite && (pb_hyport[7:0] == 8'h00)) ? pb_outport : 8'h00;
        if (pb_hywrite && (pb_hyport[7:0] == 8'h01)) complete_select <= pb_outport[2:0];
        if (pb_hywrite && (pb_hyport[7:0] == 8'h02)) done_select <= pb_outport[2:0];
        evheader_wr <= (pb_hywrite && (pb_hyport[7:0] == 8'h03) && pb_outport[0]);
        if (pb_hywrite && (pb_hyport[7:0] == 8'h04)) data_status[7:0] <= pb_outport;
        if (pb_hywrite && (pb_hyport[7:0] == 8'h05)) data_status[15:8] <= pb_outport;
        complete_tready <= (pb_hywrite && (pb_hyport[7:0] == 8'h06)) ? pb_outport : 8'h00;
        done_tready <= (pb_hywrite && (pb_hyport[7:0] == 8'h07)) ? pb_outport : 8'h00;
        // 8-B are error data
        if (pb_hywrite && (pb_hyport[7:0] == 8'h08)) error_tdata[7:0] <= pb_outport;
        if (pb_hywrite && (pb_hyport[7:0] == 8'h09)) error_tdata[15:8] <= pb_outport;
        if (pb_hywrite && (pb_hyport[7:0] == 8'h0A)) error_tdata[23:16] <= pb_outport;
        if (pb_hywrite && (pb_hyport[7:0] == 8'h0B)) error_tdata[31:24] <= pb_outport;
        
        error_tvalid <= (pb_hywrite && (pb_hyport[7:0] == 8'h0C) && pb_outport[0]);
        if (pb_hywrite && (pb_hyport[7:0] == 8'h0D)) stream_last <= pb_outport;
        
        if (pb_hywrite && (pb_hyport[7:0] == 8'h0E)) config_reg[7:0] <= pb_outport;
        if (pb_hywrite && (pb_hyport[7:0] == 8'h0F)) config_reg[15:8] <= pb_outport;

        if (pb_write && pb_port[7:0] == 8'h24) total_length[7:0] <= pb_outport;
        if (pb_write && pb_port[7:0] == 8'h25) total_length[15:8] <= pb_outport;
        if (pb_write && pb_port[7:0] == 8'h26) total_length[23:16] <= pb_outport;
        if (pb_write && pb_port[7:0] == 8'h27) total_length[31:24] <= pb_outport;
        
        if (pb_write && pb_port[7:0] == 8'h28) tag <= pb_outport;
        
        if (pb_write && pb_port[7:0] == 8'hFF) state <= pb_outport;
        
        // Frame pointers
        for (i=0;i<NUM_FRAMES;i=i+1) begin
            if (pb_write && (pb_port[7:6] == 2'b01) && pb_port[5:2] == i) begin
                if (pb_port[1:0] == 2'b00) frame_ptr[i][7:0] <= pb_outport;
                if (pb_port[1:0] == 2'b01) frame_ptr[i][15:8] <= pb_outport;
                if (pb_port[1:0] == 2'b10) frame_ptr[i][23:16] <= pb_outport;
                if (pb_port[1:0] == 2'b11) frame_ptr[i][31:24] <= pb_outport;
            end
        end
                
        // don't bother with write-only registers
        if (pb_port[7:0] == 8'h03) pb_inport <= { {7{1'b0}}, m_axis_evhd_tready && m_axis_evtag_tready };
        else if (pb_port[7:0] == 8'h06) pb_inport <= s_axis_cmpl_tvalid;
        // Require BOTH tvalid AND stream_done to be high before we consider it OK.
        else if (pb_port[7:0] == 8'h07) pb_inport <= everything_done;
        else if (pb_port[7:0] == 8'h0C) pb_inport <= m_axis_err_tready;
        else if (pb_port[7:0] == 8'h0E) pb_inport <= config_i[7:0];
        else if (pb_port[7:0] == 8'h0F) pb_inport <= config_i[15:8];
        else if (pb_port[7:0] == 8'h10) pb_inport <= cmpl_tdata[7:0];
        else if (pb_port[7:0] == 8'h11) pb_inport <= cmpl_tdata[15:8];
        else if (pb_port[7:0] == 8'h12) pb_inport <= cmpl_tdata[23:16];
        else if (pb_port[7:0] == 8'h13) pb_inport <= cmpl_tdata[31:24];
        else if (pb_port[7:0] == 8'h14) pb_inport <= cmpl_tdata[39:32];
        else if (pb_port[7:0] == 8'h15) pb_inport <= cmpl_tdata[47:40];
        else if (pb_port[7:0] == 8'h16) pb_inport <= cmpl_tdata[55:48];
        // 17 doesn't do anything
        else if (pb_port[7:0] == 8'h18) pb_inport <= done_tdata[7:0];
        else if (pb_port[7:0] == 8'h19) pb_inport <= done_tdata[15:8];
        else if (pb_port[7:0] == 8'h1A) pb_inport <= done_tdata[23:16];
        else if (pb_port[7:0] == 8'h1B) pb_inport <= done_tdata[31:24];
        else if (pb_port[7:0] == 8'h1C) pb_inport <= done_tdata[39:32];
        else if (pb_port[7:0] == 8'h1D) pb_inport <= done_tdata[47:40];
        else if (pb_port[7:0] == 8'h1E) pb_inport <= done_tdata[55:48];
        else if (pb_port[7:0] == 8'h1F) pb_inport <= done_tdata[63:56];
        else if (pb_port[7:0] == 8'h20) pb_inport <= timeout_i[7:0];
        else if (pb_port[7:0] == 8'h21) pb_inport <= timeout_i[15:8];
        else if (pb_port[7:0] == 8'h22) pb_inport <= frame_mask_i[7:0];
        else if (pb_port[7:0] == 8'h23) pb_inport <= { {(8-(NUM_FRAMES-8)){1'b0}}, frame_mask_i[8 +: (NUM_FRAMES-8)] };        
    end
    wire download_reset;
    wire total_reset = (DEBUG == "TRUE") ? (pb_reset || download_reset) : pb_reset;
    kcpsm6 u_processor(.address(pb_address),.instruction(pb_instr),.bram_enable(pb_bram_en),
                        .in_port(pb_inport),
                        .out_port(pb_outport),
                        .port_id(pb_port),
                        .write_strobe(pb_write),
                        .k_write_strobe(pb_kwrite),
                        .read_strobe(pb_read),
                        .interrupt(1'b0),
                        .interrupt_ack(),
                        .sleep(1'b0),
                        .reset(total_reset),
                        .clk(aclk));
                        
    event_processor_rom #(.USE_JTAG_LOADER(DEBUG)) u_rom( .clk(aclk),.address(pb_address),.instruction(pb_instr),.enable(pb_bram_en),.rdl(download_reset));

    wire [7:0] pb_inout = (pb_hywrite) ? pb_outport : pb_inport;
    // probes:
    // read, hywrite, hyport, pb_inout, address, state, cmpl_tvalid, done_tvalid
    generate
        if (DEBUG == "TRUE") begin : ILA
            event_processor_ila u_ila(.clk(aclk),
                                      .probe0(pb_read),
                                      .probe1(pb_hywrite),
                                      .probe2(pb_hyport),
                                      .probe3(pb_inout),
                                      .probe4(pb_address),
                                      .probe5(state),
                                      .probe6(s_axis_cmpl_tvalid),
                                      .probe7(everything_done));
          end
    endgenerate
    
    assign state_o = state;
    assign m_axis_err_tvalid = error_tvalid;
endmodule
