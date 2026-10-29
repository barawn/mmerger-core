`timescale 1ns / 1ps
`include "interfaces.vh"
`define NO_PREFIX_TAG(x) 


// map the Xilly seekable stream interface to the combined if
// This version allows us to cross-clock from xilly-side to combined-if side.
// This is needed to drop the clock frequency down.
module xilly_to_combined_cc(
        input xilclk,
        input clk,
        input [63:0] sk_data_in,
        output [63:0] sk_data_out,
        input [31:0] sk_addr,
        input sk_rden,
        input sk_wren,
        input sk_update,
        input sk_wropen,
        input sk_rdopen,
        output sk_full,
        output sk_empty,
        
        `HOST_NAMED_PORTS_COMBINED_IF( `NO_PREFIX_TAG(dummy) )        
    );
    
    parameter MAX_ADDR_BITS = 31;
    
    localparam FSM_BITS=3;
    localparam [FSM_BITS-1:0] IDLE = 0;
    localparam [FSM_BITS-1:0] ISSUE_READ = 1;
    localparam [FSM_BITS-1:0] WAIT_READ = 2;
    localparam [FSM_BITS-1:0] ISSUE_WRITE = 3;
    localparam [FSM_BITS-1:0] WAIT_WRITE = 4;
    reg [FSM_BITS-1:0] state = IDLE;
    
    localparam C_FSM_BITS=3;
    localparam [C_FSM_BITS-1:0] C_IDLE = 0;
    localparam [C_FSM_BITS-1:0] C_ISSUE_READ = 1;
    localparam [C_FSM_BITS-1:0] C_READ = 2;
    localparam [C_FSM_BITS-1:0] C_ISSUE_WRITE = 3;
    localparam [C_FSM_BITS-1:0] C_WRITE = 4;
    localparam [C_FSM_BITS-1:0] C_COMPLETE = 5;
    reg [C_FSM_BITS-1:0] c_state = IDLE;
    
    wire read_flag;
    wire c_read_flag;
    wire write_flag;
    wire c_write_flag;
    
    wire read_done_flag;
    wire c_read_done_flag;
    wire write_done_flag;
    wire c_write_done_flag;

    wire reset_flag;
    wire c_reset_flag;

    // we just need two of these, no way around it.
    // data captures the write data on wren in xilclk,
    // and register_read_data_ff captures the read data
    // on read_data_valid in clk
    reg [63:0] data = {64{1'b0}};
    reg [63:0] register_read_data_ff = {64{1'b0}};
    reg [1:0] be = {2{1'b0}};
    reg [28:0] address = {(MAX_ADDR_BITS-2){1'b0}};
    
    wire [1:0] write_enables = sk_addr[(MAX_ADDR_BITS-2) +: 2];    
    
    wire my_reset = !sk_wropen || !sk_rdopen;
    reg reset_reg = 0;
    assign reset_flag = my_reset && !reset_reg;
    flag_sync u_reset_sync(.clkA(xilclk),.clkB(clk),
                           .in_clkA(reset_flag),.out_clkB(c_reset_flag));
    always @(posedge xilclk) begin
        reset_reg <= my_reset;
        
        if (my_reset) state <= IDLE;
        else begin
            case (state)
                IDLE: if (sk_update && (write_enables == 2'b00)) state <= ISSUE_READ;
                      else if (sk_wren) state <= ISSUE_WRITE;
                ISSUE_READ: state <= WAIT_READ;
                ISSUE_WRITE: state <= WAIT_WRITE;
                WAIT_READ: if (read_done_flag) state <= IDLE;
                WAIT_WRITE: if (write_done_flag) state <= IDLE;
            endcase
        end
        
        if (read_done_flag) data <= register_read_data_ff;
        else if (state == IDLE && sk_wren) data <= sk_data_in;
        
        if (sk_update) address <= sk_addr[0 +: (MAX_ADDR_BITS-2)];
        if (sk_update) be <= write_enables;
    end
    assign read_flag = (state == ISSUE_READ);
    assign write_flag = (state == ISSUE_WRITE);
    flag_sync u_read_sync(.in_clkA(read_flag),.out_clkB(c_read_flag),
                          .clkA(xilclk),.clkB(clk));
    flag_sync u_write_sync(.in_clkA(write_flag),.out_clkB(c_write_flag),
                          .clkA(xilclk),.clkB(clk));
                          

    always @(posedge clk) begin
        if (c_reset_flag) c_state <= IDLE;
        else begin
            case (c_state)
                C_IDLE: if (c_read_flag) c_state <= C_ISSUE_READ;
                        else if (c_write_flag) c_state <= C_ISSUE_WRITE;
                C_ISSUE_READ: c_state <= C_READ;
                C_READ: if (register_read_data_valid) c_state <= C_IDLE;
                C_ISSUE_WRITE: c_state <= C_WRITE;
                C_WRITE: if (interface_ready) c_state <= C_IDLE;
            endcase
        end
        if (register_read_data_valid) register_read_data_ff <= register_read_data;
    end
    assign c_read_done_flag = (c_state == C_READ && register_read_data_valid);
    assign c_write_done_flag = (c_state == C_WRITE && interface_ready);
    
    flag_sync u_read_done_sync(.in_clkA(c_read_done_flag),.out_clkB(read_done_flag),
                               .clkA(clk),.clkB(xilclk));
    flag_sync u_write_done_sync(.in_clkA(c_write_done_flag),.out_clkB(write_done_flag),
                               .clkA(clk),.clkB(xilclk));
    
    // Full can transition after wren or update.
    assign sk_full = (state != IDLE);
    // Empty can transition after update or rden, but we don't care about rden
    assign sk_empty = (state == ISSUE_READ || state == WAIT_READ);
    
    assign sk_data_out = data;

    // these are guaranteed to be static
    assign register_write_data = data;
    assign register_write_be = { {4{be[1]}}, {4{be[0]}} };
    // flags
    assign register_write_enable = (c_state == C_ISSUE_WRITE);
    assign register_read_enable = (c_state == C_ISSUE_READ);
    // Also static
    // We shift these up 3 to match. they're 64 bit,
    // address bits are MAX_ADDR_BITS-2, so need
    // (64-(MAX_ADDR_BITS-2)-3)
    assign register_write_address = { {(64-(MAX_ADDR_BITS-2)-3){1'b0}}, address, 3'b000 };
    assign register_read_address = { {(64-(MAX_ADDR_BITS-2)-3){1'b0}}, address, 3'b000 };
    assign register_request_tag = {8{1'b0}};
        
endmodule
