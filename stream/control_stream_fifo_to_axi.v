// this dopey module streams data to AXI side 4 words at a time
module control_stream_fifo_to_axi(
        input clk,
        input reset,        
        input allow_fake_status,
        input use_stream_tlast,
        output streaming_done,
        input   [15:0]      s_axis_fifo_tdata,
        input               s_axis_fifo_tvalid,
        input               s_axis_fifo_tlast,
        output              s_axis_fifo_tready,
        
        output  [15:0]      m_axis_tx_tdata,
        output  [1:0]       m_axis_tx_tkeep,
        output              m_axis_tx_tvalid,
        input               m_axis_tx_tready,
        output              m_axis_tx_tlast
    );

    localparam  ACLK_TIMER_WAIT_BITS = 8;
    localparam [15:0] CONTROL_PREFIX = 16'hC751;
    localparam [15:0] STATUS_PREFIX = 16'h57A7;
    
    reg [ACLK_TIMER_WAIT_BITS-1:0] aclk_timer_wait = {ACLK_TIMER_WAIT_BITS{1'b0}};
    wire [ACLK_TIMER_WAIT_BITS:0]  aclk_timer_wait_minus_one = aclk_timer_wait - 1;

    // sooo stupid
    reg [15:0] prefix = {16{1'b0}};
    reg [15:0] ctrl0 = {16{1'b0}};
    reg [15:0] ctrl1 = {16{1'b0}};
    reg [15:0] ctrl2 = {16{1'b0}};

    localparam FSM_BITS = 4;
    localparam [FSM_BITS-1:0]   RESET = 0;
    localparam [FSM_BITS-1:0]   WAIT_FOR_PREFIX = 1;
    localparam [FSM_BITS-1:0]   WAIT_FOR_CTRL0 = 2;
    localparam [FSM_BITS-1:0]   WAIT_FOR_CTRL1 = 3;
    localparam [FSM_BITS-1:0]   WAIT_FOR_CTRL2 = 4;
    localparam [FSM_BITS-1:0]   STREAM_PREFIX = 5;
    localparam [FSM_BITS-1:0]   STREAM_CTRL0 = 6;
    localparam [FSM_BITS-1:0]   STREAM_CTRL1 = 7;
    localparam [FSM_BITS-1:0]   STREAM_CTRL2 = 8;
    localparam [FSM_BITS-1:0]   WAIT = 9;
    localparam [FSM_BITS-1:0]   JUST_GO_READ = 10;
    localparam [FSM_BITS-1:0]   JUST_GO_WRITE = 11;
    localparam [FSM_BITS-1:0]   DONE = 12;
    reg [FSM_BITS-1:0] state = RESET;   

    reg s_axis_fifo_tready_ff = 0;
    reg m_axis_tx_tvalid_ff = 0;
    reg [15:0] m_axis_tx_tdata_ff = {16{1'b0}};
    reg m_axis_tx_tlast_ff = 0;

    reg stream_tlast_seen = 0;
    
    // I should shove this definition somewhere...
    `define AXIS_OK( prefix ) ( prefix``tready && prefix``tvalid )
    
    always @(posedge clk) begin
        if (reset) state <= RESET;
        else case(state)
            RESET: if (use_stream_tlast) state <= JUST_GO_READ; else state <= WAIT_FOR_PREFIX;
            WAIT_FOR_PREFIX: if (`AXIS_OK(s_axis_fifo_) && 
                                 (s_axis_fifo_tdata == CONTROL_PREFIX || 
                                 (allow_fake_status))) state <= WAIT_FOR_CTRL0;
            WAIT_FOR_CTRL0: if (`AXIS_OK(s_axis_fifo_)) state <= WAIT_FOR_CTRL1; 
            WAIT_FOR_CTRL1: if (`AXIS_OK(s_axis_fifo_)) state <= WAIT_FOR_CTRL2; 
            WAIT_FOR_CTRL2: if (`AXIS_OK(s_axis_fifo_)) state <= STREAM_PREFIX;
            STREAM_PREFIX: if (`AXIS_OK(m_axis_tx_)) state <= STREAM_CTRL0;
            STREAM_CTRL0: if (`AXIS_OK(m_axis_tx_)) state <= STREAM_CTRL1;
            STREAM_CTRL1: if (`AXIS_OK(m_axis_tx_)) state <= STREAM_CTRL2;
            STREAM_CTRL2: if (`AXIS_OK(m_axis_tx_)) state <= WAIT;
            WAIT: if (aclk_timer_wait_minus_one[ACLK_TIMER_WAIT_BITS]) begin
                if (stream_tlast_seen) state <= DONE;
                else state <= WAIT_FOR_PREFIX;
            end
            JUST_GO_READ: if (`AXIS_OK(s_axis_fifo_)) state <= JUST_GO_WRITE;
            JUST_GO_WRITE: if (`AXIS_OK(m_axis_tx_)) begin
                if (stream_tlast_seen) state <= DONE;
                else state <= JUST_GO_READ;
            end
            DONE: state <= DONE;           
            default: state <= RESET;
        endcase

        if (reset) stream_tlast_seen <= 0;
        else if (`AXIS_OK(s_axis_fifo_) && s_axis_fifo_tlast) stream_tlast_seen <= 1;

        if (reset) s_axis_fifo_tready_ff <= 0;
        // shut off when we read in JUST_GO mode
        else if (state == JUST_GO_READ && `AXIS_OK(s_axis_fifo_)) s_axis_fifo_tready_ff <= 0;
        // turn back on when we write in JUST_GO mode
        else if (state == JUST_GO_WRITE && `AXIS_OK(m_axis_tx_)) s_axis_fifo_tready_ff <= 1;
        else if (state == RESET || (state == WAIT && aclk_timer_wait_minus_one[ACLK_TIMER_WAIT_BITS])) s_axis_fifo_tready_ff <= 1;
        else if (state == WAIT_FOR_CTRL2 && `AXIS_OK(s_axis_fifo_)) s_axis_fifo_tready_ff <= 0;
        
        if (reset) m_axis_tx_tvalid_ff <= 0;
        // turn on after we read successfully in JUST GO mode
        else if (state == JUST_GO_READ && `AXIS_OK(s_axis_fifo_)) m_axis_tx_tvalid_ff <= 1;
        // shut off after we write successfully in JUST GO mode
        else if (state == JUST_GO_WRITE && `AXIS_OK(m_axis_tx_)) m_axis_tx_tvalid_ff <= 0;
        else if (state == WAIT_FOR_CTRL2 && s_axis_fifo_tvalid) m_axis_tx_tvalid_ff <= 1;
        else if (state == STREAM_CTRL2 && `AXIS_OK(m_axis_tx_)) m_axis_tx_tvalid_ff <= 0;        

        if (state == STREAM_PREFIX && `AXIS_OK(m_axis_tx_)) m_axis_tx_tdata_ff <= ctrl0;
        else if (state == STREAM_CTRL0 && `AXIS_OK(m_axis_tx_)) m_axis_tx_tdata_ff <= ctrl1;
        else if (state == STREAM_CTRL1 && `AXIS_OK(m_axis_tx_)) m_axis_tx_tdata_ff <= ctrl2;
        // always capture data in JUST GO mode
        else if (state == JUST_GO_READ && `AXIS_OK(s_axis_fifo_)) m_axis_tx_tdata_ff <= s_axis_fifo_tdata;
        else m_axis_tx_tdata_ff <= prefix;
        
        if (state == WAIT_FOR_PREFIX && `AXIS_OK(s_axis_fifo_)) prefix <= s_axis_fifo_tdata;
        if (state == WAIT_FOR_CTRL0 && `AXIS_OK(s_axis_fifo_)) ctrl0 <= s_axis_fifo_tdata;
        if (state == WAIT_FOR_CTRL1 && `AXIS_OK(s_axis_fifo_)) ctrl1 <= s_axis_fifo_tdata;
        if (state == WAIT_FOR_CTRL2 && `AXIS_OK(s_axis_fifo_)) ctrl2 <= s_axis_fifo_tdata;
        
        if (state == STREAM_CTRL1 && `AXIS_OK(m_axis_tx_)) m_axis_tx_tlast_ff <= 1;
        // tlast is stream captured in JUST GO mode
        else if (state == JUST_GO_READ) m_axis_tx_tlast_ff <= s_axis_fifo_tlast;
        else if (state != STREAM_CTRL2) m_axis_tx_tlast_ff <= 0;

        // sleazy countdown timer: if you haven't seen it before,
        // this uses the carry chain output of the adder (well, subtractor)
        // when we enter the WAIT state, aclk_timer_wait goes to 8'hFF, and aclk_timer_wait_minus_one[ACLK_TIMER_WAIT_BITS] falls.
        // when aclk_timer_wait drops to 0, aclk_timer_wait_minus_one[ACLK_TIMER_WAIT_BITS] goes high and we exit the state
        // (and the counter stops)
        if (state == STREAM_CTRL2 && `AXIS_OK(m_axis_tx_) || !aclk_timer_wait_minus_one[ACLK_TIMER_WAIT_BITS]) aclk_timer_wait <= aclk_timer_wait_minus_one;
        else aclk_timer_wait <= {ACLK_TIMER_WAIT_BITS{1'b0}};
    end
    
    assign streaming_done = (state == DONE);
    
    assign s_axis_fifo_tready = s_axis_fifo_tready_ff;
    
    assign m_axis_tx_tdata = m_axis_tx_tdata_ff;
    assign m_axis_tx_tvalid = m_axis_tx_tvalid_ff;
    assign m_axis_tx_tkeep = 2'h3;
    assign m_axis_tx_tlast = m_axis_tx_tlast_ff;
endmodule
    