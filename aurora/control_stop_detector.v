`timescale 1ns/1ps

module control_stop_detector( input aclk,
                              input aresetn,
                              input [15:0] s_axis_tdata,
                              input        s_axis_tvalid,
                              input        s_axis_tlast,
                              output       s_axis_tready,
                              output [15:0] m_axis_tdata,
                              output        m_axis_tvalid,
                              output        m_axis_tlast,
                              input         m_axis_tready,
                              output        tx_discard_o,
                              input         xoff_i,
                              input         update_i,
                              input [31:0]  stop_delay_i,
                              input         stop_disable_i,
                              output        stopped_o );

    wire stop_count = xoff_i;
    wire stop_delay_reached;
    reg link_stopped = 0;
    reg stop_disable = 0;
    // jam_disable needs a local register. The jam count is internally registered by the C register in the DSP.
    always @(posedge aclk) begin
        if (update_i) stop_disable <= stop_disable_i;
        if (!aresetn) link_stopped <= 1'b0;
        else if (stop_delay_reached) link_stopped <= 1'b1;       
    end
    dsp_counter_terminal_count #(.RESET_TCOUNT_AT_RESET("FALSE")) u_stop_counter(.clk_i(aclk),
                                             .rst_i(!aresetn|| !stop_count),
                                             .count_i(stop_count),
                                             .tcount_i(stop_delay_i),
                                             .update_tcount_i(update_i),
                                             .tcount_reached_o(stop_delay_reached));
    
    assign m_axis_tdata = s_axis_tdata;
    assign m_axis_tvalid = s_axis_tvalid && !link_stopped;
    assign m_axis_tlast = s_axis_tlast;
    assign s_axis_tready = (link_stopped) ? 1'b1 : m_axis_tready;

    assign stopped_o = link_stopped;
    assign tx_discard_o = (link_stopped && m_axis_tvalid);
endmodule
