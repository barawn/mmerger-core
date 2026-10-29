`timescale 1ns/1ps
`include "interfaces.vh"
// tdest = 0 is the error dump
// tdest = 1 is status path
// tdest = 2 or 3 is event path (3 is impossible anyway)
module haic_frame_splitter_v2( input aclk,
                              input aresetn,
                              `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_axis_ , 64 ),
                              input                           s_axis_tlast,
                              input [4:0]                     s_axis_tuser,

                              `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_axis_ , 64 ),
                              output                          m_axis_tlast,
                              output [1:0]                    m_axis_tdest,
                              output [4:0]                    m_axis_tuser );                              

    localparam [15:0] EVENT_HEADER = 16'hDA7A;
    localparam [15:0] STATUS_HEADER = 16'h57A7;
    
    parameter DEBUG = "FALSE";
    
    reg [1:0] tdest_reg = {2{1'b0}};

    wire [1:0] tdest_in;
    
    assign tdest_in[0] = s_axis_tuser[0] ? (s_axis_tdata[31:16] == STATUS_HEADER) : tdest_reg[0];
    assign tdest_in[1] = s_axis_tuser[0] ? (s_axis_tdata[31:16] == EVENT_HEADER) : tdest_reg[1];
    
    always @(posedge aclk) begin
        if (!aresetn) tdest_reg <= {2{1'b0}};
        else if (s_axis_tuser[0] && s_axis_tvalid && s_axis_tready) begin
            tdest_reg[0] <= (s_axis_tdata[31:16] == STATUS_HEADER);
            tdest_reg[1] <= (s_axis_tdata[31:16] == EVENT_HEADER);
        end
    end
    // and now pass it through the register slice
    haic_frame_splitter_slice u_slice(.aclk(aclk),.aresetn(aresetn),
                                 .s_axis_tdata(s_axis_tdata),
                                 .s_axis_tvalid(s_axis_tvalid),
                                 .s_axis_tlast(s_axis_tlast),
                                 .s_axis_tready(s_axis_tready),
                                 .s_axis_tuser(s_axis_tuser),
                                 .s_axis_tdest(tdest_in),
                                 .m_axis_tdata(m_axis_tdata),
                                 .m_axis_tvalid(m_axis_tvalid),
                                 .m_axis_tlast(m_axis_tlast),
                                 .m_axis_tready(m_axis_tready),
                                 .m_axis_tuser(m_axis_tuser),
                                 .m_axis_tdest(m_axis_tdest));
            
    
endmodule

