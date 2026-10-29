`timescale 1ns / 1ps
`include "interfaces.vh"

module xilly_stream_inout(
        input aclk,
        input aresetn,
        input xil_clk,
        
        input [63:0] stream_data,
        input [4:0]  stream_addr,
        input        stream_addr_update,
        input        stream_write,
        output       stream_full,
        input        stream_open,
        
        output [63:0] stream_out_data,
        output        stream_out_empty,
        input         stream_out_read,
        input         stream_out_open,
        output [31:0] stream_out_waiting,
        
        `HOST_NAMED_PORTS_AXI4S_MIN_IF( m_axis_ , 16 ),
        output [2:0] m_axis_tdest,
        output m_axis_tlast,
        
        `TARGET_NAMED_PORTS_AXI4S_MIN_IF( s_axis_ , 64 ),
        input s_axis_tlast        
    );
    
    // define the streams
    `DEFINE_AXI4S_MIN_IF( ctrl64_ , 64);
    wire ctrl64_tlast;
    wire [2:0] ctrl64_tdest;
        
    // the srst here is wr_clock side, reset on close
    reg [2:0] stream_addr_reg = {3{1'b0}};
    always @(posedge xil_clk) if (stream_addr_update) stream_addr_reg <= stream_addr[2:0];
    // why did I bother making this 68. oh well.
    fifo68_cc_fwft u_ctrl_ccfifo(.wr_clk(xil_clk),
                                 .rd_clk(aclk),
                                 .din( { 1'b1, stream_addr_reg, stream_data } ),
                                 .wr_en( stream_write ),
                                 .srst( !stream_open ),
                                 .full( stream_full ),
                                 .dout( { ctrl64_tlast, ctrl64_tdest, ctrl64_tdata } ),
                                 .valid( ctrl64_tvalid ),
                                 .rd_en( ctrl64_tvalid && ctrl64_tready));
    // now convert
    axis_width_64to16_tlast_tdest u_widthconv( .aclk(aclk),.aresetn(aresetn),
                                              `CONNECT_AXI4S_MIN_IF(s_axis_ , ctrl64_ ),
                                              .s_axis_tlast(ctrl64_tlast),
                                              .s_axis_tdest(ctrl64_tdest),
                                              `CONNECT_AXI4S_MIN_IF(m_axis_ , m_axis_ ),
                                              .m_axis_tlast(m_axis_tlast),
                                              .m_axis_tdest(m_axis_tdest));
    
    // stream stuff is trivial
    wire stat_full;
    assign s_axis_tready = !stat_full;
    wire xil_tlast;
    fifo65_cc u_stat_ccfifo(.wr_clk(aclk),
                            .rd_clk(xil_clk),
                            .srst(!aresetn),
                            .din( { s_axis_tlast, s_axis_tdata } ),
                            .wr_en( s_axis_tvalid && s_axis_tready ),
                            .full( stat_full ),
                            .dout( { xil_tlast, stream_out_data } ),
                            .rd_en( stream_out_read ),
                            .empty( stream_out_empty) );
    reg [31:0] cur_nwords = {32{1'b0}};
    reg [31:0] tot_nwords = {32{1'b0}};
    reg xil_data_valid = 0;
    reg xil_update = 0;
    always @(posedge xil_clk) begin
        xil_data_valid <= stream_out_read;
        xil_update <= xil_data_valid && xil_tlast;
        if (!stream_out_open) begin
            cur_nwords <= {32{1'b0}};
            tot_nwords <= {32{1'b0}};
        end else begin
            if (xil_update) tot_nwords <= cur_nwords;
            if (stream_out_read) cur_nwords <= cur_nwords + 1;
        end
    end
        
            
    assign stream_out_waiting = tot_nwords;                                                  
    
endmodule
