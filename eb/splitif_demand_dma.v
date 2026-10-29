`timescale 1ns/1ps

// splitif_demand_dma takes an AXI4-Stream input, and given an execute command and a length,
// pushes that stream into a buffer provided by the SFC.
// We completely and totally ignore all accesses on the register-side, so we'll see if that works.

// Note the inbound path is 256 bits, so need to resize. We'll pick up bandwidth if we
// ditch the outwidth converter in the FMN and change the event builder to push 256 bits through.
// That gets us 25.6 Gb/s, or 3.2 GB/s, which should be enough, I hope.
module splitif_demand_dma   
    #(parameter DEBUG="TRUE")(  input aclk, input aresetn,
                                input [255:0]   s_axis_tdata,
                                input           s_axis_tvalid,
                                input           s_axis_tlast,
                                output          s_axis_tready,

                                // Length is in bytes. We can handle up to 2^24 dwords,
                                // so this needs to be 26 bits. This is 4 MB.
                                input [25:0]    s_len_tdata,
                                input           s_len_tvalid,
                                output          s_len_tready,
                                // you need 2 buffer addresses, one for DMAA, one for DMAB.
                                // 1: check busy (if 1 something's screwed up!)
                                // 2: write addr, write enable.
                                // 3: wait for done_o
                                // 4: when done_o is asserted read cur_buf_o and retain.
                                // 5: write other addr, write enable.
                                // 6: copy data.
                                // 7: go to step 3
                                input [63:0]    dest_addr_i,
                                input           enable_i,
                                output          done_o,
                                output [23:0]   done_dwords_o,
                                output          cur_buf_o,
                                output          busy_o,
                                output          need_reset_o,
                                
                                input           clk,
                                input           reset,
                                
                                input [255:0]   dmaA_from_host_data,
                                input [13:0]    dmaA_from_host_ctrl,
                                input           dmaA_from_host_valid,
                                output          dmaA_from_host_advance,
                                
                                output [255:0]  dmaA_to_host_data,
                                output [13:0]   dmaA_to_host_ctrl,
                                output          dmaA_to_host_valid,
                                input           dmaA_to_host_almost_full,
                                
                                input [255:0]   dmaB_from_host_data,
                                input [13:0]    dmaB_from_host_ctrl,
                                input           dmaB_from_host_valid,
                                output          dmaB_from_host_advance,

                                output [255:0]  dmaB_to_host_data,
                                output [13:0]   dmaB_to_host_ctrl,
                                output          dmaB_to_host_valid,
                                input           dmaB_to_host_almost_full);
    reg [63:0] dmaA_addr = {64{1'b0}};
    reg [63:0] dmaB_addr = {64{1'b0}};
                                    
    // We need to cut the debugging signals, so we're going to multiplex them.
    // it's still a buttload of signals: 256+14+3 = 273, or 4 freaking block RAMs
    reg [255:0] dmaA_data = {256{1'b0}};
    reg [255:0] dmaB_data = {256{1'b0}};
    reg [13:0] dmaA_ctrl = {14{1'b0}};
    reg [13:0] dmaB_ctrl = {14{1'b0}};
    reg dmaA_dir = 0;
    reg dmaA_valid = 0;
    reg dmaA_almost_full = 0;
    reg dmaB_dir = 0;
    reg dmaB_valid = 0;
    reg dmaB_almost_full = 0;
    reg [255:0] dma_data = {256{1'b0}};
    reg [13:0] dma_ctrl = {14{1'b0}};
    reg dma_dir = 0;
    reg dma_valid = 0;
    reg dma_almost_full = 0;

    wire dma_buf_sel;
    always @(posedge clk) begin
        // Let from_host take precedence over to_host, but
        // to_host is the default.
        dmaA_dir <= dmaA_from_host_valid;
        
        if (dmaA_from_host_valid) dmaA_valid <= dmaA_from_host_valid;
        else dmaA_valid <= dmaA_to_host_valid;

        dmaA_almost_full <= dmaA_to_host_almost_full;

        if (dmaA_from_host_valid) begin
            dmaA_data <= dmaA_from_host_data;
            dmaA_ctrl <= dmaA_from_host_ctrl;
        end else begin
            dmaA_data <= dmaA_to_host_data;
            dmaA_ctrl <= dmaA_to_host_ctrl;
        end

        dmaB_dir <= dmaB_from_host_valid;
        
        if (dmaB_from_host_valid) dmaB_valid <= dmaB_from_host_valid;
        else dmaB_valid <= dmaB_to_host_valid;

        dmaB_almost_full <= dmaB_to_host_almost_full;

        if (dmaB_from_host_valid) begin
            dmaB_data <= dmaB_from_host_data;
            dmaB_ctrl <= dmaB_from_host_ctrl;
        end else begin
            dmaB_data <= dmaB_to_host_data;
            dmaB_ctrl <= dmaB_to_host_ctrl;
        end
        
        if (dma_buf_sel) begin
            dma_data    <=  dmaB_data;
            dma_dir     <=  dmaB_dir;
            dma_ctrl    <=  dmaB_ctrl;
            dma_valid   <=  dmaB_valid;
            dma_almost_full <= dmaB_almost_full;
        end else begin
            dma_data    <=  dmaA_data;
            dma_dir     <=  dmaA_dir;
            dma_ctrl    <=  dmaA_ctrl;
            dma_valid   <=  dmaA_valid;
            dma_almost_full <= dmaA_almost_full;
        end
    end
    dma_ila u_ila(.clk(clk),.probe0(dma_data),.probe1(dma_ctrl),.probe2(dma_dir),.probe3(dma_valid),.probe4(dma_almost_full));
    dma_vio u_vio(.clk(clk),.probe_out0(dma_buf_sel));        

    assign dmaA_from_host_advance = 1'b1;
    assign dmaB_from_host_advance = 1'b1;                                
                                
    // If "aresetn" comes when we're transferring data,
    // we need to reset the DMA engine. This flags this.
    // How to reset DMA engine? Uh....    
    reg             need_reset = 0;
    wire            dma_reset_flag;
    
    // single_demand_dma streams. Address,
    // length, and data.
    wire    [63:0]  addrA_tdata;
    wire            addrA_tvalid;
    wire            addrA_tready;
    wire    [25:0]  lenA_tdata;
    wire            lenA_tvalid;
    wire            lenA_tready;
    wire    [255:0] dataA_tdata;
    wire            dataA_tvalid;
    wire            dataA_tready;
    wire            dataA_tlast;
    
    // Busies and done. bufA/B_is_done is cleared
    // faster than the cross-clock registers to avoid
    // latency on the deassertion. Latency on the
    // assertion is unimportant.
    // I don't even know if the busy is useful.
    wire            bufA_busy;
    reg [1:0]       bufA_done_aclk = 2'b00;
    reg [23:0]      dmaA_done_length = {24{1'b0}};
    reg [23:0]      dmaA_done_length_aclk = {24{1'b0}};
    reg             bufA_is_done = 0;
    reg             bufA_done_clk = 0;
    reg             bufA_data_enable = 0;
    

    // as above for DMA B channel
    wire    [63:0]  addrB_tdata;
    wire            addrB_tvalid;
    wire            addrB_tready;
    wire    [25:0]  lenB_tdata;
    wire            lenB_tvalid;
    wire            lenB_tready;
    wire    [255:0] dataB_tdata;
    wire            dataB_tvalid;
    wire            dataB_tready;
        
    wire            bufB_busy;
    reg [1:0]       bufB_done_aclk = 2'b00;        
    reg             bufB_done_clk = 0;     
    reg [23:0]      dmaB_done_length = {24{1'b0}};
    reg [23:0]      dmaB_done_length_aclk = {24{1'b0}};
    reg             bufB_is_done = 0;   
    reg             bufB_data_enable = 0;

    reg             clk_reset_rereg = 0;
    wire            clk_reset_flag = (reset && !clk_reset_rereg);
            
    localparam FSM_BITS=3;
    localparam  [FSM_BITS-1:0]  RESET           =   0;
    localparam  [FSM_BITS-1:0]  INIT_A_READY    =   1;
    localparam  [FSM_BITS-1:0]  ISSUE_A         =   2;
    localparam  [FSM_BITS-1:0]  WAIT_LEN_A      =   3;
    localparam  [FSM_BITS-1:0]  WAIT_B_READY    =   4;
    localparam  [FSM_BITS-1:0]  ISSUE_B         =   5;
    localparam  [FSM_BITS-1:0]  WAIT_LEN_B      =   6;
    localparam  [FSM_BITS-1:0]  WAIT_A_READY    =   7;
    (* fsm_encoding = "auto" *)
    (* fsm_safe_state = "reset_state" *)    
    reg [FSM_BITS-1:0] state = RESET;

    dma_aclk_ila u_aclk_ila(.clk(aclk),.probe0(state),
                            .probe1(enable_i),
                            .probe2(done_o),
                            .probe3(busy_o),
                            .probe4(cur_buf_o));
    
    always @(posedge aclk) begin
        if (enable_i && (state == INIT_A_READY || (state == WAIT_B_READY && bufA_done_aclk[1])))
            dmaA_addr <= dest_addr_i;
        if (enable_i && (state == WAIT_A_READY && bufB_done_aclk[1]))
            dmaB_addr <= dest_addr_i;
    
        if ((bufA_busy || bufB_busy) && !aresetn) need_reset <= 1;
        else if (dma_reset_flag) need_reset <= 0;
    
        if (!aresetn) state <= RESET;
        else case(state)
            RESET: state <= INIT_A_READY;
            INIT_A_READY: if (enable_i) state <= ISSUE_A;
            ISSUE_A: if (addrA_tready) state <= WAIT_LEN_A;
            WAIT_LEN_A: if (lenA_tvalid && lenA_tready) state <= WAIT_B_READY;
            WAIT_B_READY: if (enable_i && bufA_done_aclk[1]) state <= ISSUE_B;
            ISSUE_B: if (addrB_tready) state <= WAIT_LEN_B;
            WAIT_LEN_B: if (lenB_tvalid && lenB_tready) state <= WAIT_A_READY;
            WAIT_A_READY: if (enable_i && bufB_done_aclk[1]) state <= ISSUE_A;
        endcase
        
        if (!aresetn) bufA_data_enable <= 0;
        else if (state == WAIT_LEN_A && lenA_tvalid && lenA_tready) bufA_data_enable <= 1;
        else if (state == WAIT_B_READY && s_axis_tlast && s_axis_tready && s_axis_tvalid) bufA_data_enable <= 0;
        
        if (!aresetn) bufB_data_enable <= 0;
        else if (state == WAIT_LEN_B && lenB_tvalid && lenB_tready) bufB_data_enable <= 1;
        else if (state == WAIT_A_READY && s_axis_tlast && s_axis_tready && s_axis_tvalid) bufB_data_enable <= 0;        
        
        if (!aresetn) begin
            bufA_is_done <= 0;
            bufB_is_done <= 0;
        end else begin
            if (state == WAIT_B_READY) begin
                // This will clear us, and stay clear, as this transitions to
                // the next state.
                if (enable_i && bufA_done_aclk[1]) bufA_is_done <= 0;
                else bufA_is_done <= bufA_done_aclk[1];
            end
            if (state == WAIT_A_READY) begin
                if (enable_i && bufB_done_aclk[1]) bufB_is_done <= 0;
                else bufB_is_done <= bufB_done_aclk[1];
            end
        end
        if (!aresetn) begin
            dmaA_done_length_aclk <= {24{1'b0}};
            dmaB_done_length_aclk <= {24{1'b0}};
        end else begin
            if (state == WAIT_B_READY && bufA_done_aclk[1] && !bufA_is_done && !enable_i)
                dmaA_done_length_aclk <= dmaA_done_length;
            if (state == WAIT_A_READY && bufB_done_aclk[1] && !bufB_is_done && !enable_i)
                dmaB_done_length_aclk <= dmaB_done_length;
        end                    
            
        bufA_done_aclk <= { bufA_done_aclk[0], bufA_done_clk };
        bufB_done_aclk <= { bufB_done_aclk[0], bufB_done_clk };
    end
    
    always @(posedge clk) begin
        clk_reset_rereg <= reset;
        
        if (dmaA_to_host_ctrl[4] && dmaA_to_host_valid) bufA_done_clk <= 0;
        else if (dmaA_from_host_ctrl[5] && dmaA_from_host_valid) bufA_done_clk <= 1;
        
        // Acknowledge descriptor goes 0x1D/0x1C
        // 0001 1101
        // 0001 1100
        // first dword ctrl: {5,0} = 01 = first dword, [4] = 1 = ToHost completion, [3:2] = 11 meaning enables
        if (({dmaA_from_host_ctrl[5],dmaA_from_host_ctrl[0]} == 2'b01) && dmaA_from_host_valid)
            dmaA_done_length <= dmaA_from_host_data[23:0];

        if (dmaB_to_host_ctrl[4] && dmaB_to_host_valid) bufB_done_clk <= 0;
        else if (dmaB_from_host_ctrl[5] && dmaB_from_host_valid) bufB_done_clk <= 1;        

        if (({dmaB_from_host_ctrl[5],dmaB_from_host_ctrl[0]} == 2'b01) && dmaB_from_host_valid)
            dmaB_done_length <= dmaB_from_host_data[23:0];
    end
    
    assign addrA_tdata = dmaA_addr;
    assign addrA_tvalid = (state == ISSUE_A);
    assign addrB_tdata = dmaB_addr;
    assign addrB_tvalid = (state == ISSUE_B);
    assign lenA_tvalid = (state == WAIT_LEN_A) && s_len_tvalid;
    assign lenB_tvalid = (state == WAIT_LEN_B) && s_len_tvalid;
    assign s_len_tready = (state == WAIT_LEN_B && lenB_tready) || (state == WAIT_LEN_A && lenA_tready);
    
    assign dataA_tdata = s_axis_tdata;
    assign dataA_tvalid = (bufA_data_enable) && s_axis_tvalid;
    assign dataB_tdata = s_axis_tdata;
    assign dataB_tvalid = (bufB_data_enable) && s_axis_tvalid;
    assign s_axis_tready = (bufA_data_enable && dataA_tready) || (bufB_data_enable && dataB_tready);    
    
    assign bufA_busy = (state == ISSUE_A) || (state == WAIT_LEN_A) ||
                       (state == WAIT_B_READY && !bufA_done_aclk[1]);
    assign bufB_busy = (state == ISSUE_B) || (state == WAIT_LEN_B) ||
                       (state == WAIT_A_READY && !bufB_done_aclk[1]);       

    flag_sync reset_sync(.clkA(clk),.in_clkA(clk_reset_flag),.clkB(aclk),.out_clkB(dma_reset_flag));

    single_demand_dma dmaA( .aclk(aclk),.aresetn(aresetn),
                            .s_len_tdata(    lenA_tdata     ),
                            .s_len_tvalid(   lenA_tvalid    ),
                            .s_len_tready(   lenA_tready    ),
                            .s_addr_tdata(  addrA_tdata     ),
                            .s_addr_tvalid( addrA_tvalid    ),
                            .s_addr_tready( addrA_tready    ),
                            .s_axis_tdata(  dataA_tdata     ),
                            .s_axis_tvalid( dataA_tvalid    ),
                            .s_axis_tready( dataA_tready    ),
                            .s_axis_tlast(  dataA_tlast     ),
                            .clk(clk),
                            .reset(reset),
                            .dma_to_host_data(          dmaA_to_host_data       ),
                            .dma_to_host_ctrl(          dmaA_to_host_ctrl       ),
                            .dma_to_host_valid(         dmaA_to_host_valid      ),
                            .dma_to_host_almost_full(   dmaA_to_host_almost_full));
    single_demand_dma dmaB( .aclk(aclk),.aresetn(aresetn),
                            .s_len_tdata(    lenB_tdata     ),
                            .s_len_tvalid(   lenB_tvalid    ),
                            .s_len_tready(   lenB_tready    ),
                            .s_addr_tdata(  addrB_tdata     ),
                            .s_addr_tvalid( addrB_tvalid    ),
                            .s_addr_tready( addrB_tready    ),
                            .s_axis_tdata(  dataB_tdata     ),
                            .s_axis_tvalid( dataB_tvalid    ),
                            .s_axis_tready( dataB_tready    ),
                            .s_axis_tlast(  dataB_tlast     ),
                            .clk(clk),
                            .reset(reset),
                            .dma_to_host_data(          dmaB_to_host_data       ),
                            .dma_to_host_ctrl(          dmaB_to_host_ctrl       ),
                            .dma_to_host_valid(         dmaB_to_host_valid      ),
                            .dma_to_host_almost_full(   dmaB_to_host_almost_full));

    assign cur_buf_o = (state == ISSUE_B) || (state == WAIT_LEN_B) || (state == WAIT_A_READY);
    assign done_o = (cur_buf_o == 1) ? bufB_is_done : bufA_is_done;
    assign busy_o = (cur_buf_o == 1) ? bufB_busy : bufA_busy;            
    assign need_reset_o = need_reset;
    assign done_dwords_o = (cur_buf_o == 1) ? dmaB_done_length_aclk : dmaA_done_length_aclk;    
endmodule // splitif_demand_dma

module single_demand_dma(   input aclk,
                            input aresetn,
                            
                            input [25:0]    s_len_tdata,
                            input           s_len_tvalid,
                            output          s_len_tready,
                            
                            input [63:0]    s_addr_tdata,
                            input           s_addr_tvalid,
                            output          s_addr_tready,
                            
                            input [255:0]   s_axis_tdata,
                            input           s_axis_tvalid,
                            input           s_axis_tlast,
                            output          s_axis_tready,
                            
                            input           clk,
                            input           reset,
                            
                            output [255:0]  dma_to_host_data,
                            output [13:0]   dma_to_host_ctrl,
                            output          dma_to_host_valid,
                            input           dma_to_host_almost_full );

    localparam [63:0] BOARD_ADDR = 64'h0100000000000000;    
    // Combine the length and addr using a combiner. Need to expand length to 64 bits.    
    wire [63:0]  len_tdata = { {(64-26){1'b0}}, s_len_tdata };
    wire         len_tvalid = s_len_tvalid;
    wire         len_tready;
    assign       s_len_tready = len_tready;
    
    wire [127:0] cmbn_tdata;
    wire         cmbn_tvalid;
    wire         cmbn_tready;
    
    // Build the descriptors using a width converter. Only 64 bits. Pad to 256
    // at the output. 
    wire [64*4-1:0]    hdr_tdata;
    wire                hdr_tvalid;
    wire                hdr_tready;
    wire                hdr_tlast = 1;
    
    // Last 256-bit word comes first, we're little-endian.
    // Length needs to be in *dwords*, so we grab len[2 +: 24]
    assign hdr_tdata = { cmbn_tdata[63:0],
                         BOARD_ADDR[31:0], 8'hC0, cmbn_tdata[64+2 +: 24],
                         cmbn_tdata[63:0],
                         BOARD_ADDR[63:32], 8'hD0, cmbn_tdata[64+2 +: 24] };
    // hdr_tuser:
    // 0 = 1 (dword 0 enable)
    // 1 = 1 (dword 1 enable)
    // 2 = 1 (demand mode)
    // 3 = 0 tlast
    // 4 = 1 descriptor
    // 5 = 0 rsvd
    // 6 = 0 rsvd
    // 7 = 0 rsvd
    // 8 = 0 dword 2 enable
    // 9 = 0 dword 3 enable
    // 10 = 0 dword 4 enable
    // 11 = 0 dword 5 enable
    // 12 = 0 dword 6 enable
    // 13 = 0 dword 7 enable    
    // descriptor tuser = 0x0017
    // data tuser = 0x3F07 or 0x3F0F.
    //
    // We simplify this by passing just 2 bits in the tuser:
    // tuser[0] = descriptor
    // tuser[1] = data tlast.
    // Then control is { {6{~tuser[0]}}, {3{1'b0}}, tuser[0], tuser[1], {3{1'b1}} }
    assign hdr_tvalid = cmbn_tvalid;
    assign cmbn_tready = hdr_tready;
    
    // Out of the width converter, expanded.
    wire [255:0] hdr_qword_tdata;
    assign hdr_qword_tdata[255:64] = {(256-64){1'b0}};
    wire [1:0]  hdr_qword_tuser = 2'b01;
    wire        hdr_qword_tvalid;
    wire        hdr_qword_tready;
    wire        hdr_qword_tlast;

    wire [1:0]  data_tuser = { s_axis_tlast, 1'b0 };

    // Stream combiner.
    reg         do_data = 0;
    // We can write the logic for do_data like this because
    // s_axis_tready *cannot* be asserted until do_data goes high.
    // So even in the case where it's a single 256-bit write (so tlast is asserted at first),
    // since tready is initially low, the data stream can't win arbitration and tready therefore
    // never goes high.
    always @(posedge aclk) if (!aresetn || (s_axis_tlast && s_axis_tvalid && s_axis_tready)) do_data <= 0;
                           else if (hdr_qword_tlast && hdr_qword_tvalid && hdr_qword_tready) do_data <= 1;
    wire [1:0]  req_suppress = { do_data, !do_data };                                 
    
    // output data
    wire [255:0]    dma_tdata;
    wire [1:0]      dma_tuser;
    wire            dma_tready;
    wire            dma_tvalid;

    // cross clock
    wire [255:0]    dmacc_tdata;
    wire [1:0]      dmacc_tuser;
    wire            dmacc_tvalid;
    reg             dmacc_tready = 0;
    always @(posedge clk) if (reset) dmacc_tready <= 0; else dmacc_tready <= ~dma_to_host_almost_full;
    
    // We need a pipeline register before each one, because the combiner can't actually store
    // information, and the parent modules here assume that the addr/len guys are distinct:
    // they feed addr in first, then length. So the 'simple' combiner (with no pipeline in front of
    // it) blocks the state machine since the 2 valids never come valid at the same time.
    wire [63:0]     addr2comb_tdata;
    wire            addr2comb_tready;
    wire            addr2comb_tvalid;
    
    wire [63:0]     len2comb_tdata;
    wire            len2comb_tready;
    wire            len2comb_tvalid;
    
    splitif_addrlen_rs u_len_rs(.s_axis_tdata( len_tdata ),
                                .s_axis_tvalid(len_tvalid),
                                .s_axis_tready(len_tready),
                                .m_axis_tdata( len2comb_tdata ),
                                .m_axis_tvalid(len2comb_tvalid),
                                .m_axis_tready(len2comb_tready),
                                .aclk(aclk),
                                .aresetn(aresetn));
    splitif_addrlen_rs u_adr_rs(.s_axis_tdata( s_addr_tdata ),
                                .s_axis_tvalid(s_addr_tvalid),
                                .s_axis_tready(s_addr_tready),
                                .m_axis_tdata( addr2comb_tdata ),
                                .m_axis_tvalid(addr2comb_tvalid),
                                .m_axis_tready(addr2comb_tready),
                                .aclk(aclk),
                                .aresetn(aresetn));
    
    // Combine. 
    splitif_addrlen_combiner 
        u_combiner( .aclk(aclk),.aresetn(aresetn),
                    .s_axis_tdata( { len2comb_tdata  , addr2comb_tdata } ),
                    .s_axis_tvalid({ len2comb_tvalid , addr2comb_tvalid } ),
                    .s_axis_tready({ len2comb_tready , addr2comb_tready } ),
                    .m_axis_tdata   ( cmbn_tdata ),
                    .m_axis_tready  ( cmbn_tready ),
                    .m_axis_tvalid  ( cmbn_tvalid ));
    // Width convert.
    splitif_hdr_widthconv 
        u_widthconv(.aclk(aclk),.aresetn(aresetn),
                    .s_axis_tdata(  { hdr_tdata    } ),
                    .s_axis_tvalid( { hdr_tvalid   } ),
                    .s_axis_tready( { hdr_tready   } ),
                    .s_axis_tlast(  { hdr_tlast    } ),
                    .m_axis_tdata(  { hdr_qword_tdata[63:0]   } ),
                    .m_axis_tvalid( { hdr_qword_tvalid  } ),
                    .m_axis_tready( { hdr_qword_tready  } ),
                    .m_axis_tlast(  { hdr_qword_tlast   } ));
                        
    // we can use a par_axis_switch. log_si_slots is # of bits required to hold # of si slots.
    // par_axis_switch should just calculate this for us...
    // arb_algorithm 0 is lowest resource usage, and we do our own arbitration.
    par_axis_switch #(.C_NUM_SI_SLOTS(2),.C_LOG_SI_SLOTS(1),.C_AXIS_TDATA_WIDTH(256),.C_AXIS_TUSER_WIDTH(2),
                      .C_ARB_ALGORITHM(0)) 
                      u_stream_combiner( .aclk(aclk),.aresetn(aresetn),
                                         .s_axis_tdata( { s_axis_tdata  , hdr_qword_tdata   } ),
                                         .s_axis_tvalid({ s_axis_tvalid , hdr_qword_tvalid  } ),
                                         .s_axis_tlast( { s_axis_tlast  , hdr_qword_tlast   } ),
                                         .s_axis_tready({ s_axis_tready , hdr_qword_tready  } ),
                                         .s_axis_tuser( { s_axis_tuser  , hdr_qword_tuser   } ),
                                         .m_axis_tdata(     dma_tdata   ),
                                         .m_axis_tvalid(    dma_tvalid  ),
                                         .m_axis_tready(    dma_tready  ),
                                         .m_axis_tuser(     dma_tuser   ),
                                         .s_req_suppress(   req_suppress ));
     // And cross clock. This is a distram FIFO, only 32 deep. I don't think it needs to be bigger
     // because if it needs to be a block RAM, it'd have to be huge (4 full BRAMs each).
     // Speed-wise once this starts, I think it should flow smoothly. We'll have to take a look.
     splitif_dmacc_fifo u_fifo(.s_aclk(aclk),.s_aresetn(aresetn),.m_aclk(clk),
                               .s_axis_tdata(   dma_tdata       ),
                               .s_axis_tvalid(  dma_tvalid      ),
                               .s_axis_tready(  dma_tready      ),
                               .s_axis_tuser(   dma_tuser       ),
                               .m_axis_tdata(   dmacc_tdata     ),
                               .m_axis_tvalid(  dmacc_tvalid    ),
                               .m_axis_tready(  dmacc_tready    ),
                               .m_axis_tuser(   dmacc_tuser     ));
     
     assign dma_to_host_data = dmacc_tdata;
     assign dma_to_host_valid = dmacc_tvalid;
     assign dma_to_host_ctrl = { {6{~dmacc_tuser[0]}}, {3{1'b0}}, dmacc_tuser[0], dmacc_tuser[1], {3{1'b1}} };
                                                            
endmodule
