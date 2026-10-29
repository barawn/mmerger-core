`include "interfaces.vh"
`define NO_PREFIX_TAG( x )
// test module to stream packets downstream

// NOTE: AXI4-Stream (like all AXI) is LITTLE ENDIAN
// That means LOW ORDER WORDS COME FIRST
//
// So a control transfer (which is actually a single 4-word write!)
// is
//    63:48     47:32      31:16      15:0
// ( ctrl 2 ) ( ctrl 1 ) (ctrl 0 ) ( 0xC751 )
//
// 0x0000: tx_link_select (bits 2:0)
// 0x0004: resetn (bit 0), fifo_emptied (bit 1), fifo_reset (bit 2)
// 0x8000+: FIFO stream access (write-only, unaddressed)
//
// how to use:
// 1) select the link in register 0
// 2) write a bunch of control frames to address 0x8000
// 3) write 1 to bit 0 of register 4
// 4) read register 4 and watch for bit 1 to go high
// 5) write 0 to bit 0 of register 4
//
// the control streamer automatically imposes about a 260-clock period for 4 bytes,
// so there shouldn't be any risk of overflowing the downstream links - maximum throughput is HORRIBLY low

module  stream_registers_v3 #(parameter TX_WIDTH = 16, parameter RX_WIDTH = 64)(
        input   clk,
        input   reset,
        `TARGET_NAMED_PORTS_COMBINED_IF( `NO_PREFIX_TAG(dummy) ),
        
        input                   aclk,
        // we don't actually USE this aresetn.
        input                   aresetn,
        output  [2:0]           m_axis_tx_tdest,
        output  [TX_WIDTH-1:0]  m_axis_tx_tdata,
        output  [1:0]           m_axis_tx_tkeep,
        output                  m_axis_tx_tvalid,
        input                   m_axis_tx_tready,
        output                  m_axis_tx_tlast,

        input   [RX_WIDTH-1:0]  s_axis_rx_tdata,
        input                   s_axis_rx_tvalid,
        input                   s_axis_rx_tlast,
        input   [2:0]           s_axis_rx_tuser,
        output                  s_axis_rx_tready
    );

    reg [2:0] tx_link_select_clk    = {3{1'b0}};
    reg [2:0] tx_link_select_aclk   = {3{1'b0}};
    
    reg resetn_clk = 0;
    reg resetn_aclk = 0;
    
    reg fifo_reset = 0;
    reg fifo_reset_seen = 0;
    wire fifo_reset_flag = fifo_reset && !fifo_reset_seen;
    
    reg rxfifo_reset = 0;
    reg rxfifo_reset_seen = 0;
    wire rxfifo_reset_flag = rxfifo_reset && !rxfifo_reset_seen;
    wire rxfifo_reset_flag_aclk;
    
    reg fifo_out_tvalid_ff = 0;
    wire fifo_emptied_flag_aclk;
    wire fifo_emptied_flag_clk;
    reg fifo_emptied_clk = 0;
        
    // write flag for clock crossing
    reg write_flag = 0;
    // write flag in the aclk domain
    wire write_flag_aclk;
    // write flag is clock crossing
    wire write_cdc_busy_clk;

    // Reregistered write address.
    reg [15:0]  register_write_address_ff = {16{1'b0}};
    // Reregistered write data.
    reg [63:0]  register_write_data_ff = {64{1'b0}};
    // Reregistered byte enables.
    reg [7:0]   register_write_be_ff = {8{1'b0}};
    // Reregistered write enable.
    reg         register_write_enable_ff = 0;
    // Reregistered read address.
    reg [15:0]  register_read_address_ff = {16{1'b0}};
    // Reregistered read enable.
    reg         register_read_enable_ff = 0;
    // Reregistered request tag.
    reg [7:0]   register_request_tag_ff = {8{1'b0}};
    // Read data is valid
    reg         register_read_data_valid_ff = 0;
    // Read data
    reg [63:0]  register_read_data_ff = {64{1'b0}};
    // interface is ready
    reg         interface_ready_ff = 0;

    flag_sync u_write_flag_sync(.in_clkA(write_flag),.clkA(clk),.out_clkB(write_flag_aclk),.clkB(aclk),.busy_clkA(write_cdc_busy_clk));
    flag_sync u_rxreset_flag_sync(.in_clkA(rxfifo_reset_flag),.clkA(clk),.out_clkB(rxfifo_reset_flag_aclk),.clkB(aclk));
    
    `DEFINE_AXI4S_MIN_IF( convert_in_ , 64 );
    wire [7:0] convert_in_tkeep = register_write_be_ff;
    wire       convert_in_tlast = register_write_address_ff[3];
    assign convert_in_tdata = register_write_data_ff;
    assign convert_in_tvalid = write_flag && register_write_address_ff[15];    
    
    `DEFINE_AXI4S_MIN_IF( fifo_in_ , 16 );
    wire                  fifo_in_tlast;
    `DEFINE_AXI4S_MIN_IF( fifo_out_ , 16 );
    wire                  fifo_out_tlast;
    
    // after we exit reset, watch for the FIFO's output side to stop being valid. That SHOULD be an indication that it finished.
    assign fifo_emptied_flag_aclk = !fifo_out_tvalid && fifo_out_tvalid_ff;
    flag_sync u_emptied_flag_sync(.in_clkA(fifo_emptied_flag_aclk),.clkA(aclk),.out_clkB(fifo_emptied_flag_clk),.clkB(clk));
    
    reg allow_fake_status = 0;
    reg use_stream_tlast = 0;
    wire [31:0] status_fifo_ctrlstat;
    wire [63:0] status_fifo_data;
    wire status_fifo_read = (register_read_enable_ff && register_read_address_ff[15:14] == 2'b01);
    // our only two are TX link select and reset
    // OK we now have 3
    wire select_registers = (register_write_address_ff[15:14] == 2'b00);
    wire select_tx = !register_write_address_ff[3];
    wire select_rx = register_write_address_ff[3];

    wire streaming_done_aclk;
    reg [1:0] streaming_done_clk = {2{1'b0}};

    always @(posedge clk) begin
        streaming_done_clk <= {streaming_done_clk[0], streaming_done_aclk};
        // only write_enable needs to be reset qualified, everything else qualifies on it
        if (reset) register_write_enable_ff <= 0;
        else register_write_enable_ff <= register_write_enable;
    
        register_write_enable_ff <= register_write_enable;
        register_write_address_ff <= register_write_address[15:0];
        register_write_data_ff <= register_write_data;
        register_write_be_ff <= register_write_be;

        // only read_enable_ff needs to be reset qualified, everything else qualifies on it
        if (reset) register_read_enable_ff <= 0;
        else register_read_enable_ff <= register_read_enable;
            
        register_read_address_ff <= register_read_address[15:0];

        write_flag <= !register_write_enable && register_write_enable_ff;

        if (reset) interface_ready_ff <= 0;
        else interface_ready_ff <= !register_write_enable && !register_write_enable_ff && !write_cdc_busy_clk && !write_flag && convert_in_tready;

        
        if (write_flag && select_registers && select_tx && register_write_be_ff[0]) tx_link_select_clk <= register_write_data_ff[2:0];
        if (write_flag && select_registers && select_tx && register_write_be_ff[3]) allow_fake_status <= register_write_data_ff[31];
        if (write_flag && select_registers && select_tx && register_write_be_ff[3]) use_stream_tlast <= register_write_data_ff[30];
        if (write_flag && select_registers && select_tx && register_write_be_ff[4]) begin
            resetn_clk <= register_write_data_ff[32];
            fifo_reset <= register_write_data_ff[34];
        end
        fifo_reset_seen <= fifo_reset;

        rxfifo_reset <= (write_flag && select_registers && select_rx && register_write_be_ff[3] && register_write_data[31]);       
        rxfifo_reset_seen <= rxfifo_reset;
        
        if (register_read_enable_ff) begin
            if (register_read_address_ff[15:14] == 2'b01) begin
                register_read_data_ff <= status_fifo_data;
            end else if (register_read_address_ff[3]) begin
                register_read_data_ff <= { {32{1'b0}}, status_fifo_ctrlstat };
            end else begin
                register_read_data_ff[0 +: 32] <= {allow_fake_status,use_stream_tlast,{27{1'b0}},tx_link_select_clk};
                register_read_data_ff[32 +: 32] <= {{28{1'b0}},streaming_done_clk[1],fifo_reset,fifo_emptied_clk,resetn_clk};
            end
        end        
        
        if (!resetn_clk) fifo_emptied_clk <= 0;
        else if (fifo_emptied_flag_clk) fifo_emptied_clk <= 1;        

        // if read enable seen, store the tag
        if (register_read_enable_ff) register_request_tag_ff <= register_request_tag;

        // If a read enable is seen set valid to 1 unless in reset
        if (reset) register_read_data_valid_ff <= 0;
        else register_read_data_valid_ff <= register_read_enable_ff;        
    end

    (* ASYNC_REG = "TRUE" *)
    reg [1:0] allow_fake_status_aclk = {2{1'b0}};

    (* ASYNC_REG = "TRUE" *)
    reg [1:0] use_stream_tlast_aclk = {2{1'b0}};

    always @(posedge aclk) begin
        if (write_flag_aclk) resetn_aclk <= resetn_clk;
        if (write_flag_aclk) tx_link_select_aclk <= tx_link_select_clk;

        fifo_out_tvalid_ff <= fifo_out_tvalid;
        allow_fake_status_aclk <= {allow_fake_status_aclk[0],allow_fake_status};
        use_stream_tlast_aclk <= {use_stream_tlast_aclk[0], use_stream_tlast};
    end


    // adapt from 64 to 16 bits...
    stream_width_convert_64to16 u_converter(.aclk(clk),.aresetn(!fifo_reset_flag),
                                            `CONNECT_AXI4S_MIN_IF( s_axis_, convert_in_ ),
                                            .s_axis_tlast( convert_in_tlast ),
                                            .s_axis_tkeep( convert_in_tkeep ),
                                            `CONNECT_AXI4S_MIN_IF( m_axis_, fifo_in_ ),
                                            .m_axis_tlast( fifo_in_tlast) );

    stream_fifo u_fifo(.s_aclk(clk),.m_aclk(aclk),.s_aresetn(!fifo_reset_flag),
                       `CONNECT_AXI4S_MIN_IF( s_axis_ , fifo_in_ ),
                       .s_axis_tlast( fifo_in_tlast),
                       `CONNECT_AXI4S_MIN_IF( m_axis_ , fifo_out_ ),
                       .m_axis_tlast( fifo_out_tlast));

    
    wire [63:0] stat64_fifo_tdata;
    assign      status_fifo_data = stat64_fifo_tdata;
    wire [2:0]  stat64_fifo_tuser;
    wire        stat64_fifo_tvalid;
    wire        stat64_fifo_tlast;
    wire        stat64_fifo_tready = status_fifo_read;
    wire [9:0]  stat64_fifo_rd_count;
        
    // bit [9:0] = occupancy
    // bit [10]  = tvalid (should be 1)
    // bit [11]  = tlast (should be 1)
    // bit [14:12] = tuser: 0=first word (should be set), 1=CRC error, 2=TKEEP error (short packet)
    // bit [31]  = RX Fifo reset.
    assign status_fifo_ctrlstat = { rxfifo_reset,
                                         {16{1'b0}},
                                         stat64_fifo_tuser,
                                         stat64_fifo_tlast,
                                         stat64_fifo_tvalid,
                                         stat64_fifo_rd_count };
                                            
    stream_status_fifo_v2 u_status_fifo(.s_aclk(aclk),.m_aclk(clk),.s_aresetn(!rxfifo_reset_flag_aclk),
                                     `CONNECT_AXI4S_MIN_IF( s_axis_ , s_axis_rx_ ),
                                     .s_axis_tuser(s_axis_rx_tuser),
                                     .s_axis_tlast(s_axis_rx_tlast),
                                     `CONNECT_AXI4S_MIN_IF( m_axis_ , stat64_fifo_ ),
                                     .m_axis_tuser(stat64_fifo_tuser),
                                     .m_axis_tlast(stat64_fifo_tlast),
                                     .axis_rd_data_count(stat64_fifo_rd_count));

    control_stream_fifo_to_axi u_streamer(.clk(aclk),.reset(!resetn_aclk),.allow_fake_status(allow_fake_status_aclk[1]),
                                          .use_stream_tlast(use_stream_tlast),
                                          .streaming_done(streaming_done_aclk),
                                          `CONNECT_AXI4S_MIN_IF( s_axis_fifo_ , fifo_out_ ),
                                          .s_axis_fifo_tlast(fifo_out_tlast),
                                          `CONNECT_AXI4S_MIN_IF( m_axis_tx_ , m_axis_tx_ ),
                                          .m_axis_tx_tkeep(m_axis_tx_tkeep),
                                          .m_axis_tx_tlast(m_axis_tx_tlast));  

    assign register_read_data = register_read_data_ff;
    assign register_read_data_tag = register_request_tag_ff;
    assign register_read_data_valid = register_read_data_valid_ff;

    assign m_axis_tx_tdest = tx_link_select_aclk;
    assign interface_ready = interface_ready_ff;
    
endmodule
    
