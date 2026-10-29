`timescale 1ns/1ps

module haic_xoff_logic( input clk,
                        input reset,
                        input update_i,
                        output xoff_o,
                        output xoff_drop_o,
                        output dropped_o,
                        output overflow_o,
                        input dropped_flag_i,
                        input valid_data_i,
                        input [7:0] xoff_level_i,
                        input [7:0] xoff_hysteresis_i,
                        output [8:0] prog_full_thresh_assert_o,
                        output [8:0] prog_full_thresh_negate_o,
                        input prog_full_i,
                        input almost_full_i );

    reg [8:0] flow_prog_full_assert = {9{1'b1}};
    reg [8:0] flow_prog_full_negate = {9{1'b1}};
    reg flow_xoff_en = 1'b0;
    reg dropped = 1'b0;
    reg overflow = 1'b0;
    reg flow_xoff = 1'b0;
    reg flow_critical = 1'b0;
    
    always @(posedge clk) begin        
        if (update_i) begin
            flow_prog_full_assert <= { 1'b1, xoff_level_i };
            flow_prog_full_negate <= { 1'b1, xoff_level_i } - { 1'b0, xoff_hysteresis_i };
            // Enable XOFF unless we're set to 0xFF
            flow_xoff_en <= !(xoff_level_i == 8'hFF);
        end
        if (reset || !flow_xoff_en) flow_xoff <= 1'b0;
        else begin
            flow_xoff <= prog_full_i;
        end
        if (reset || !flow_xoff_en) flow_critical <= 1'b0;
        else begin
            if (almost_full_i) flow_critical <= 1'b1;
            else if (!prog_full_i) flow_critical <= 1'b0;
        end
        if (reset) dropped <= 1'b0;
        else if (dropped_flag_i) dropped <= 1'b1;
        if (reset) overflow <= 1'b0;
        else if (valid_data_i && almost_full_i) overflow <= 1'b1;
    end
    
    assign xoff_o = flow_xoff;
    assign xoff_drop_o = flow_critical;
    assign dropped_o = dropped;
    assign overflow_o = overflow;
    assign prog_full_thresh_assert_o = flow_prog_full_assert;
    assign prog_full_thresh_negate_o = flow_prog_full_negate;

endmodule
