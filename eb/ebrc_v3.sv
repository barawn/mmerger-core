`timescale 1ns / 1ps
// eff me, do this as dumb as possible
// event builder register core.
// Takes 16 bits of address in.
// 0x0000 - 0x8000 : local registers
// 0x8000 - 0xFFFF : AXI4-Lite space mapped in
//
// Local register space:
// 0x0000 : EBCONTROL. Bit 0 enables the event builder's DMA path. Note that the event builder itself is
//                     always enabled, it's just its outputs that change.
//                     Bit 1 enables the event builder's debug output. Note that this overrides the DMA
//                     path.
// 0x0008 : NUMFRAME.  Write the number of frames *minus one* expected for each event.
//                     Note that this functions as a link mask. Suppose you have the trigger output
//                     in event path 6, and the TOF in event path 4. You write 6 into MI_MUX[0]
//                     meaning trigger (event path 6) -> builder input 0, and 4 into MI_MUX[1], meaning
//                     TOF (event path 4) -> builder input 1. The other MI_MUX registers should be written
//                     to 0x80000000 to disable them, or they can be written to route other inputs. (Truth
//                     is that because the low interface wins anything about MI_MUX[1] actually doesn't matter).
//                     You then write "1" into NUMFRAME.
//                     NOTE: Unused inputs SHOULD BE ROUTED TO DUMP! You do NOT USE THE EVENT BUILDER
//                     to dump undesired data!
// 0x0010 : DETCONFIG. This is a 16-bit value stored in the event.
// 0x0014 : CURVALID.  8-bit indicator of which links are valid or masked.
// remainder: reserved
// 
//
//
// The AXI4-Lite space currently just contains the AXI4 Stream Switch
// register space, which should just be
// 0x8000 : CONTROL. Write 0x2 to update the routing registers.
// 0x8040 : MI_MUX[0]
// 0x8044 : MI_MUX[1]
// 0x8048 : MI_MUX[2]
// 0x804C : MI_MUX[3]
// 0x8050 : MI_MUX[4]
// 0x8054 : MI_MUX[5]
// 0x8058 : MI_MUX[6]
// 0x805C : MI_MUX[7]
// The MI_MUX registers determines what FMB output ( = event input path ) gets routed to what completion port.
// This determines what order they're filled in the event.
`include "interfaces.vh"
`define NO_PREFIX_TAG(x)

module ebrc_v3(
        input clk,
        input reset,
        // this is ONLY for the clock domain crossing
        input aclk,
        // These are ONLY picked up externally while ARESET is active!
        output dma_en_o,
        output event_tdest_o,
        output track_event_o,
        //
        output [7:0] link_mask_o,
        input [7:0] current_valid_i,
        input [7:0] current_tag_i,
        output [15:0] detector_config_o,
        
        `TARGET_NAMED_PORTS_COMBINED_IF( `NO_PREFIX_TAG(dummy) ),
        
        `HOST_NAMED_PORTS_AXI4L_IF( m_axi_ , 16, 64)
    );
    
    reg dma_en = 0;
    reg dma_en_aclk = 0;
    reg event_tdest = 0;
    reg event_tdest_aclk = 0;
    reg track_event = 0;
    reg [2:0] num_frame = {3{1'b0}};
    reg [2:0] num_frame_aclk = {3{1'b0}};
    reg [7:0] link_mask = {8{1'b0}};    


    wire [7:0] current_valid_clk;
    async_register #(.WIDTH(8), .UPDATE_PERIOD(6))
        u_cur_valid_reg(.clkA(aclk),.clkB(clk),
                        .in_clkA(current_valid_i),
                        .out_clkB(current_valid_clk));

    wire [7:0] current_tag_clk;
    async_register #(.WIDTH(8),.UPDATE_PERIOD(6))
        u_cur_tag_reg(.clkA(aclk),.clkB(clk),
                        .in_clkA(current_tag_i),
                        .out_clkB(current_tag_clk));

    reg [15:0] detector_config = {16{1'b0}};
    reg [15:0] detector_config_aclk = {16{1'b0}};

    function [7:0] build_mask;
        input [2:0] num_frames;
        begin
            case (num_frames)
                3'd0: build_mask = 8'b1111_1110;
                3'd1: build_mask = 8'b1111_1100;
                3'd2: build_mask = 8'b1111_1000;
                3'd3: build_mask = 8'b1111_0000;
                3'd4: build_mask = 8'b1110_0000;
                3'd5: build_mask = 8'b1100_0000;
                3'd6: build_mask = 8'b1000_0000;
                3'd7: build_mask = 8'b0000_0000;
            endcase
        end
    endfunction
    
    reg update_clk = 0;
    wire update_aclk;
    wire update_done_clk;    
    flag_sync u_update_sync(.in_clkA(update_clk),.clkA(clk),.out_clkB(update_aclk),.clkB(aclk));
    flag_sync u_update_done_sync(.in_clkA(update_aclk),.clkA(aclk),.out_clkB(update_done_clk),.clkB(clk));    
    
    wire [63:0] local_regs[3:0];
    assign local_regs[0] = { {61{1'b0}}, track_event, event_tdest, dma_en };
    assign local_regs[1] = { {61{1'b0}}, num_frame };
    assign local_regs[2] = { {48{1'b0}}, detector_config };
    assign local_regs[3] = { {24{1'b0}},current_tag_clk,{24{1'b0}}, current_valid_clk };
    
    localparam FSM_BITS = 4;
    localparam [FSM_BITS-1:0] IDLE = 0;    
    localparam [FSM_BITS-1:0] ASSERT_AWADDR_WDATA = 1;
    localparam [FSM_BITS-1:0] ASSERT_WDATA = 2;
    localparam [FSM_BITS-1:0] ASSERT_AWADDR = 8;
    localparam [FSM_BITS-1:0] ASSERT_ARADDR = 3;
    localparam [FSM_BITS-1:0] WAIT_RVALID = 4;
    localparam [FSM_BITS-1:0] LOCAL_WRITE = 5;
    localparam [FSM_BITS-1:0] LOCAL_READ = 6;
    localparam [FSM_BITS-1:0] LOCAL_WRITE_WAIT = 7;    
    reg [FSM_BITS-1:0] state = IDLE;
    
    reg [7:0]   tag_capture = {8{1'b0}};
    reg [15:0]  addr = {16{1'b0}};
    reg [63:0]  data = {64{1'b0}};
    reg [7:0]   byte_enable = {8{1'b0}};
    reg         read_valid = 0;
    always @(posedge clk) begin
        if (register_write_enable) addr <= register_write_address[15:0];
        else if (register_read_enable) addr <= register_read_address[15:0];
        
        if (register_write_enable) byte_enable <= register_write_be;
        
        if (register_write_enable) data <= register_write_data;
        else if (state == LOCAL_READ) data <= local_regs[ addr[4:3] ];
        else if (state == WAIT_RVALID && m_axi_rvalid && m_axi_rready) data <= m_axi_rdata;

        read_valid <= (m_axi_rvalid && m_axi_rready && (state == WAIT_RVALID)) || (state == LOCAL_READ);
        
        if (register_read_enable) tag_capture <= register_request_tag;
        
        if (reset) state <= IDLE;
        else begin case (state)
            IDLE: if (register_write_enable) begin
                      if (register_write_address[15])
                        state <= ASSERT_AWADDR_WDATA;
                      else
                        state <= LOCAL_WRITE;
                  end else if (register_read_enable) begin
                      if (register_read_address[15])
                        state <= ASSERT_ARADDR;
                      else
                        state <= LOCAL_READ;
                  end                  
            // I dunno, handle *both* cases?
            ASSERT_AWADDR_WDATA: begin
                if (m_axi_awready && m_axi_wready) state <= IDLE;
                else if (m_axi_awready) state <= ASSERT_WDATA;
                else if (m_axi_wready) state <= ASSERT_AWADDR;
            end
            ASSERT_WDATA: if (m_axi_wready) state <= IDLE;
            ASSERT_AWADDR: if (m_axi_awready) state <= IDLE;
            ASSERT_ARADDR: if (m_axi_arready) state <= WAIT_RVALID;
            WAIT_RVALID: if (m_axi_rvalid) state <= IDLE;
            LOCAL_WRITE: state <= LOCAL_WRITE_WAIT;
            LOCAL_READ: state <= IDLE;
            LOCAL_WRITE_WAIT: if (update_done_clk) state <= IDLE;
            endcase
        end
        update_clk = (state == LOCAL_WRITE);
        if (state == LOCAL_WRITE) begin
            // ok now be smart. dma_en/event_tdest are both
            // [15:3] == 0 and byte_enable[0].
            if (register_write_address[15:3] == 13'd0 && byte_enable[0]) begin
                dma_en <= data[0];
                event_tdest <= data[1];
                track_event <= data[2];
            end
            if (register_write_address[15:3] == 13'd1 && byte_enable[0]) begin
                num_frame <= data[2:0];
            end
            if (register_write_address[15:3] == 13'd2) begin
                if (byte_enable[0]) detector_config[7:0] <= data[7:0];
                if (byte_enable[1]) detector_config[15:8] <= data[15:8];
            end
        end
    end

    always @(posedge aclk) begin
        if (update_aclk) begin
            dma_en_aclk <= dma_en;
            event_tdest_aclk <= event_tdest;
            num_frame_aclk <= num_frame;
            detector_config_aclk <= detector_config;
        end
        link_mask <= build_mask(num_frame_aclk);
    end
    
    assign interface_ready = (state == IDLE);
    assign register_read_data_tag = tag_capture;
    assign register_read_data = data;
    assign register_read_data_valid = read_valid;
    
    assign m_axi_araddr = addr;
    assign m_axi_awaddr = addr;
    assign m_axi_arvalid = (state == ASSERT_ARADDR);
    assign m_axi_awvalid = (state == ASSERT_AWADDR || state == ASSERT_AWADDR_WDATA);
    assign m_axi_wvalid = (state == ASSERT_WDATA || state == ASSERT_AWADDR_WDATA);
    assign m_axi_wdata = data;
    assign m_axi_wstrb = byte_enable;
    assign m_axi_rready = (state == WAIT_RVALID);
    assign m_axi_bready = 1'b1;
    
    assign dma_en_o = dma_en_aclk;
    assign event_tdest_o = event_tdest_aclk;
    assign link_mask_o = link_mask;
    assign detector_config_o = detector_config_aclk;    
    assign track_event_o = track_event;
endmodule
