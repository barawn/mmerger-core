// goal:
// when XOFF asserts, we want to drop any new frames that
// come in.
// so if (s_axis_xoff && s_axis_tlast && s_axis_tvalid) => holdoff goes high
// OR if (s_axis_xoff && !frame_transmitting) => holdoff goes high
// holdoff clears when s_axis_xoff is low and no frame is being transmitted, or at the end of that frame.
// 
// We also need the corner case where (s_axis_tvalid && s_axis_xoff && s_axis_tuser[0])
// all become valid in the same clock cycle.

module dnpcie_frame_holdoff_v2( input aclk, input aresetn,
                            input [31:0] s_axis_tdata,
                            input        s_axis_tvalid,
                            input [2:0] s_axis_tuser,
                            input       s_axis_tlast,
                            input       s_axis_xoff,
                            
                            output          m_axis_dropped,
                            output [31:0]   m_axis_tdata,
                            output          m_axis_tvalid,
                            output [2:0]    m_axis_tuser,
                            output          m_axis_tlast);
    reg frame_transmitting = 0;
    reg holdoff = 0;    
    
    reg [31:0]  axis_tdata = {32{1'b0}};
    reg         axis_tvalid = 0;
    reg [2:0]   axis_tuser = {3{1'b0}};
    reg         axis_tlast = 0;    

    reg         axis_dropped = 0;

    always @(posedge aclk) begin
        if (!aresetn) frame_transmitting <= 0;
        else if (s_axis_tuser[0] && s_axis_tvalid) frame_transmitting <= 1;
        else if (s_axis_tlast && s_axis_tvalid) frame_transmitting <= 0;
        
        // xoff is supposed to be an emergency cutoff now.
        // So we want holdoff asserted immediately when it comes in, and kept asserted
        // until a frame isn't being transmitted, or the frame currently being
        // held off ends.
        if (!aresetn) holdoff <= 0;
        else if (s_axis_xoff) holdoff <= 1;
        else if (holdoff && !s_axis_xoff && !frame_transmitting) holdoff <= 0;
        else if (holdoff && !s_axis_xoff && s_axis_tlast && s_axis_tvalid) holdoff <= 0;
        
        if (s_axis_tvalid) axis_tdata <= s_axis_tdata;
        if (s_axis_tvalid) axis_tuser <= s_axis_tuser;
        if (s_axis_tvalid) axis_tlast <= s_axis_tlast;
        axis_tvalid <= s_axis_tvalid && !(holdoff || s_axis_xoff);

        axis_dropped <= (holdoff || s_axis_xoff) && s_axis_tuser[0] && s_axis_tvalid;
    end
    
    assign m_axis_tdata = axis_tdata;
    assign m_axis_tuser = axis_tuser;
    assign m_axis_tlast = axis_tlast;
    assign m_axis_tvalid = axis_tvalid;    
    assign m_axis_dropped = axis_dropped;
endmodule
                            