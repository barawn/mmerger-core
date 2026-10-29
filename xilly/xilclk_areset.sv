`timescale 1ns / 1ps
// generate areset in xilclk domain
module xilclk_areset(
        input aclk,
        input aresetn,
        input xilclk,
        output xilreset
    );
    
    wire reset_delay_done;
    reg areset_reg = 0;
    reg xilreset_reg = 0;
    wire aclk_reset_flag = (~aresetn && ~areset_reg);
    wire xilclk_reset_flag;
    always @(posedge aclk) begin
        areset_reg <= ~aresetn;
    end
    flag_sync u_reset_sync(.in_clkA(aclk_reset_flag),.out_clkB(xilclk_reset_flag),
                           .clkA(aclk),.clkB(xilclk));
    SRLC32E u_xilreset_delay(.D(xilclk_reset_flag),.CLK(xilclk),.CE(1'b1),.A(5'd16),.Q(reset_delay_done));
    always @(posedge xilclk) begin
        if (reset_delay_done) xilreset_reg <= 1'b0;
        else if (xilclk_reset_flag) xilreset_reg <= 1'b1;
    end
                    
    assign xilreset = xilreset_reg;
endmodule
