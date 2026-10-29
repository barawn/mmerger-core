`include "interfaces.vh"

`define NO_PREFIX_TAG( x )

`define DLYFF #1
module event_builder_register_core #(parameter NUM_FRAMES=10)(
        input clk,
        input reset,
        `TARGET_NAMED_PORTS_COMBINED_IF( `NO_PREFIX_TAG(dummy) ),

        output [15:0] event_config_o,
        output [15:0] event_timeout_o, 
        output [9:0]  event_frame_mask_o,
        output        event_enable_o,
        
        // DMA stuff. This stuff is independent
        // of WHAT we're sending via DMA.
        // This is all aclk, although we only
        // output-synchronize enable_o, since
        // dest_addr_o is qualified by it.
        input         aclk,
        output [63:0] dest_addr_o,
        output        enable_o,
        input         done_i,
        input [23:0]  done_dwords_i,
        input         cur_buf_i,
        input         busy_i,
        input         need_reset_i,        

        // event error path
        input [31:0] s_axis_tdata,
        input        s_axis_tvalid,
        output       s_axis_tready
    );


    localparam [15:0] IDENT = "Ev";
    localparam [15:0] VERSION = "00";

    // groups of 256 bytes or something like that
    localparam [15:0]   ADDR_EBRC_IDENT         =   16'h0000;
        
    localparam [15:0]   ADDR_EB_EVCONFIG        =   16'h0100;
    localparam [15:0]   ADDR_EB_EVTIMEOUT       =   16'h0104;
    localparam [15:0]   ADDR_EB_EVFRAME_MASK    =   16'h0108;
    localparam [15:0]   ADDR_EB_EVENABLE        =   16'h010C;
    localparam [15:0]   ADDR_EB_EVERROR   =   16'h0110;

    localparam [15:0]   ADDR_EB_DMA_ADDR        =   16'h0200;
    localparam [15:0]   ADDR_EB_DMA_CTRLSTAT    =   16'h0208;

    reg [63:0]  dma_addr = {64{1'b0}};
    reg         dma_en = 0;    
    flag_sync   u_dma_en_sync(.in_clkA(dma_en),.out_clkB(enable_o),.clkA(clk),.clkB(aclk));
    // This crosses clock domains, but it's OK since it's qualified by enable, which must occur
    // 2 clocks after a write to dma_addr, minimum.
    assign      dest_addr_o = dma_addr;
    reg [1:0]   done_sync = {2{1'b0}};
    reg [1:0]   cur_buf_sync = {2{1'b0}};
    reg [23:0]  done_dwords_sync = {24{1'b0}};
    reg [1:0]   busy_sync = {2{1'b0}};
    reg [1:0]   need_reset_sync = {2{1'b0}};
    
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

    // 2 groups for now, the EBRC and the event config portion.
    // Later add more to the EBRC (DMA setup), and the bundle config portion.
    wire [63:0] register_ebrc_ident = { IDENT, VERSION, IDENT, VERSION };    
    wire [63:0] register_ebrc = register_ebrc_ident;
    
    wire [63:0] register_event[3:0];
    wire [31:0] register_event_config;
    wire [31:0] register_event_timeout;
    wire [31:0] register_event_frame_mask;
    wire [31:0] register_event_enable;
    wire [31:0] register_event_error;

    assign register_event[0] = { register_event_timeout, register_event_config };
    assign register_event[1] = { register_event_enable, register_event_frame_mask };
    assign register_event[2] = { register_event_error, register_event_error };
    assign register_event[3] = { register_event_error, register_event_error };
    // actual registers
    reg [15:0] event_config = {16{1'b0}};
    reg [15:0] event_timeout = {16{1'b0}};
    reg [NUM_FRAMES-1:0] event_frame_mask = {NUM_FRAMES{1'b0}};
    reg event_enable = 0;    

    assign register_event_timeout = { {16{1'b0}}, event_timeout };
    assign register_event_config = { {16{1'b0}}, event_config };
    assign register_event_frame_mask = { {22{1'b0}}, event_frame_mask };
    assign register_event_enable = { {30{1'b0}}, s_axis_tvalid, event_enable };
    assign register_event_error = s_axis_tdata;
        
    wire [63:0] register_dma[1:0];
    assign      register_dma[0] = dma_addr;
    // dma[1] is the status/control word.
    // bit[0] = enable
    // bit[1] = done
    // bit[2] = busy
    // bit[3] = cur_buf
    // bit[31] = need_reset
    // bit[32 +: 24] = done_dwords
    assign register_dma[1] = { {12{1'b0}}, done_dwords_i, need_reset_i, {27{1'b0}}, cur_buf_i, busy_i, done_i, dma_en };    

    integer ai;    
    always @(posedge clk) begin
        // cross clock domain back from aclk
        need_reset_sync <= {need_reset_sync[0],need_reset_i};
        done_sync <= {done_sync[0],done_i};
        busy_sync <= {busy_sync[0],busy_i};
        cur_buf_sync <= {cur_buf_sync[0], cur_buf_i};
        if (done_sync[1]) done_dwords_sync <= done_dwords_i;
        // Handle register writes, I guess.
        // Let's try to handle this correctly and see what happens.
        if ( register_write_enable_ff ) begin
            // this matches both ADDR_EB_EVCONFIG and ADDR_EB_EVTIMEOUT
            if ((register_write_address_ff[ 15:3 ] == ADDR_EB_EVCONFIG[15:3])) begin
                if (register_write_be_ff[0]) event_config[0 +: 8] <= register_write_data_ff[0 +: 8];
                if (register_write_be_ff[1]) event_config[8 +: 8] <= register_write_data_ff[8 +: 8];
                if (register_write_be_ff[4]) event_timeout[0 +: 8] <= register_write_data_ff[32 +: 8];
                if (register_write_be_ff[5]) event_timeout[8 +: 8] <= register_write_data_ff[40 +: 8];
            end
            if ((register_write_address_ff[ 15:3] == ADDR_EB_EVFRAME_MASK[15:3])) begin
                if (register_write_be_ff[0]) event_frame_mask[0 +: 8] <= register_write_data_ff[0 +: 8];
                if (register_write_be_ff[1]) event_frame_mask[8 +: 2] <= register_write_data_ff[8 +: 2];
                if (register_write_be_ff[4]) event_enable <= register_write_data[32];
            end
            if ((register_write_address_ff[ 15:3] == ADDR_EB_DMA_ADDR[15:3])) begin
                for (ai=0;ai<8;ai=ai+1) begin
                    if (register_write_be_ff[ai]) dma_addr[8*ai +: 8] <= register_write_data_ff[8*ai +: 8];
                end
            end
        end
        dma_en <= (register_write_enable_ff && register_write_address_ff[15:3] == ADDR_EB_DMA_CTRLSTAT[15:3]
                   && register_write_be_ff[0] && register_write_data_ff[0]);                
        // Reregister everything coming in for easy timing.

        // only write_enable needs to be reset qualified, everything else qualifies on it
        if (reset) register_write_enable_ff <= 0;
        else register_write_enable_ff <= register_write_enable;

        register_write_enable_ff <= register_write_enable;
        register_write_address_ff <= register_write_address[15:0];
        register_write_data_ff <= register_write_data;
        register_write_be_ff <= register_write_be;
    
        // only read_enable_ff needs to be reset qualified, everything else qualifies on it
        if (reset) register_read_enable_ff <= 0;
        else register_read_enable_ff <= register_read_enable;

        if (reset) register_read_enable_ff_reg <= 0;
        else register_read_enable_ff_reg <= register_read_enable_ff;
            
        register_read_address_ff <= register_read_address[15:0];
        register_request_tag_ff <= register_request_tag;
        
        // We're ready so long as a write isn't processing.
        if (reset) interface_ready_ff <= 0;
        else interface_ready_ff <= !register_write_enable && !register_write_enable_ff;
        
        // If a read enable is seen set valid to 1 unless in reset
        if (reset) register_read_data_valid_ff <= 0;
        else register_read_data_valid_ff <= register_read_enable_ff;
        
        // if read enable seen, store the tag
        if (register_read_enable_ff) register_read_data_tag_ff <= register_request_tag_ff;
        
        // read handling. Only capture stuff on read_enable high, doesn't matter otherwise.
        if  (register_read_enable_ff) begin
            if ( register_read_address_ff[15:8] == 8'h01 )
                register_read_data_ff <= register_event[ register_read_address_ff[4:3] ];
            else if (register_read_address_ff[15:8] == 8'h02 )
                register_read_data_ff <= register_dma[ register_read_address_ff[3] ];
            else register_read_data_ff <= register_ebrc;            
        end
    end
    assign interface_ready = interface_ready_ff;

    assign register_read_data = register_read_data_ff;
    assign register_read_data_tag = register_read_data_tag_ff;
    assign register_read_data_valid = register_read_data_valid_ff;    

    assign event_config_o = event_config;
    assign event_timeout_o = event_timeout;
    assign event_frame_mask_o = event_frame_mask;
    assign event_enable_o = event_enable;
    // only read the error register if there's data there. I mean, it won't do anything bad, but you won't know if it's valid.
    assign s_axis_tready = ( register_read_enable_ff &&  (register_read_address_ff[15:3] == ADDR_EB_EVERROR[15:3]));
    

endmodule
`undef DLYFF