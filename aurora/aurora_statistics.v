`timescale 1ns/1ps
`define DLYFF #1

module aurora_statistics #(parameter IN_STATISTICS_WIDTH=24,
                           parameter OUT_STATISTICS_WIDTH=8)
                          (input aurora_clk,
                           input aurora_reset,
                           input in_count,
                           input out_count,
                           input clk,
                           output [IN_STATISTICS_WIDTH-1:0] in_statistics,
                           output [OUT_STATISTICS_WIDTH-1:0] out_statistics);

    wire [23:0] in_val;
    wire [23:0] out_val;
    dual_dsp_counters u_counters(.clk(aurora_clk),
                                 .rst(aurora_reset),
                                 .increment( {out_count, in_count}),
                                 .count( {out_val, in_val} ));
    async_register #(.WIDTH(IN_STATISTICS_WIDTH),.UPDATE_PERIOD(8)) 
        u_cc_incount( .clkA(aurora_clk),
                      .in_clkA(in_val[0 +: IN_STATISTICS_WIDTH]),
                      .clkB(clk),
                      .out_clkB(in_statistics));
    async_register #(.WIDTH(OUT_STATISTICS_WIDTH),.UPDATE_PERIOD(8))
        u_cc_outcount(.clkA(aurora_clk),
                      .in_clkA(out_val[0 +: OUT_STATISTICS_WIDTH]),
                      .clkB(clk),
                      .out_clkB(out_statistics));
                                         
endmodule
