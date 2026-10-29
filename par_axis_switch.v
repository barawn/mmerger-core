`timescale 1ns/1ps
// This is generic parameterizable N-to-1 AXI4-Stream
// switch, assuming tdata/tuser/tlast are present (only),
// and arbitrating on TLAST.
// This is one of my most common use cases, which is
// why I wrapped the switch from Xilinx's infrastructure
// and made this.
//
// Note that C_ARB_ALGORITHM can be
// 0 : round-robin
// 1 : fixed priority
// 3 : true round-robin
// I dunno what 2 is supposed to be for, maybe that's the external arbiter.
// But don't use it.
module par_axis_switch
  #( parameter integer C_NUM_SI_SLOTS = 1,
     parameter integer C_LOG_SI_SLOTS = 1,
     parameter integer C_AXIS_TDATA_WIDTH = 16,
     parameter integer C_AXIS_TUSER_WIDTH = 1,
     parameter integer C_ARB_ALGORITHM = 0,
     parameter integer C_ARB_ON_TLAST = 1)
   ( input aclk,
     input 			   aresetn,

     input [C_AXIS_TDATA_WIDTH*C_NUM_SI_SLOTS-1:0] s_axis_tdata,
     input [C_NUM_SI_SLOTS-1:0]    s_axis_tvalid,
     input [C_NUM_SI_SLOTS-1:0]    s_axis_tlast,
     input [C_AXIS_TUSER_WIDTH*C_NUM_SI_SLOTS-1:0]  s_axis_tuser,
     output [C_NUM_SI_SLOTS-1:0]   s_axis_tready,

     output [C_AXIS_TDATA_WIDTH-1:0] 		   m_axis_tdata,
     output 			   m_axis_tvalid,
     output 			   m_axis_tlast,
     output [C_AXIS_TUSER_WIDTH-1:0] 		   m_axis_tuser,
     input 			   m_axis_tready,
     input [C_NUM_SI_SLOTS-1:0] s_req_suppress );

   localparam NBYTES = (C_AXIS_TDATA_WIDTH)/8;
      
   axis_switch_v1_1_17_axis_switch
     #( .C_FAMILY("artix7"),
	.C_NUM_SI_SLOTS(C_NUM_SI_SLOTS),
	.C_LOG_SI_SLOTS(C_LOG_SI_SLOTS),
	.C_NUM_MI_SLOTS(1),
	.C_AXIS_TDATA_WIDTH(C_AXIS_TDATA_WIDTH),
	// these have to be 1 minimum because they're used as multipliers and, y'know,
	// apparently Xilinx doesn't know how to guard against pointless crap
	.C_AXIS_TID_WIDTH(1),
	.C_AXIS_TDEST_WIDTH(1),
	.C_AXIS_TUSER_WIDTH(C_AXIS_TUSER_WIDTH),
   // C_AXIS_SIGNAL_SET: each bit if enabled specifies which axis optional signals are present
   //   [0] => TREADY present
   //   [1] => TDATA present
   //   [2] => TSTRB present, TDATA must be present
   //   [3] => TKEEP present, TDATA must be present
   //   [4] => TLAST present
   //   [5] => TID present
   //   [6] => TDEST present
   //   [7] => TUSER present
	.C_AXIS_SIGNAL_SET( 32'b10010011 ),
	.C_ARB_ON_MAX_XFERS(0),
	.C_ARB_ON_NUM_CYCLES(0),
	.C_ARB_ON_TLAST(C_ARB_ON_TLAST),
	.C_INCLUDE_ARBITER(1),
	.C_ARB_ALGORITHM(C_ARB_ALGORITHM),
	.C_OUTPUT_REG(0),
	.C_DECODER_REG(0),
	.C_M_AXIS_CONNECTIVITY_ARRAY({C_NUM_SI_SLOTS{1'b1}}),
	.C_M_AXIS_BASETDEST_ARRAY(1'b0),
	.C_M_AXIS_HIGHTDEST_ARRAY(1'b0),
	.C_ROUTING_MODE(0),
	.C_S_AXI_CTRL_ADDR_WIDTH(7),
	.C_S_AXI_CTRL_DATA_WIDTH(32),
	.C_COMMON_CLOCK(0)) 
   switch( .aclk(aclk),
	   .aresetn(aresetn),
	   .aclken(1'b1),
	   .s_axis_tvalid(s_axis_tvalid),
	   .s_axis_tready(s_axis_tready),
	   .s_axis_tdata(s_axis_tdata),
	   .s_axis_tstrb( {NBYTES*C_NUM_SI_SLOTS{1'b1}} ),
	   .s_axis_tkeep( {NBYTES*C_NUM_SI_SLOTS{1'b1}} ),
	   .s_axis_tlast(s_axis_tlast),
	   .s_axis_tid( {C_NUM_SI_SLOTS{1'b0}}),
	   .s_axis_tdest( {C_NUM_SI_SLOTS{1'b0}}),
	   .s_axis_tuser(s_axis_tuser),
	   .m_axis_tvalid(m_axis_tvalid),
	   .m_axis_tready(m_axis_tready),
	   .m_axis_tdata(m_axis_tdata),
	   .m_axis_tstrb(),
	   .m_axis_tkeep(),
	   .m_axis_tlast(m_axis_tlast),
	   .m_axis_tid(),
	   .m_axis_tdest(),
	   .m_axis_tuser(m_axis_tuser),
	   .arb_req(),
	   .arb_done(),
	   .arb_gnt( {C_NUM_SI_SLOTS{1'b0}} ),
	   .arb_sel( {C_LOG_SI_SLOTS{1'b0}} ),
	   .arb_last(),
	   .arb_id(),
	   .arb_dest(),
	   .arb_user(),
	   .s_req_suppress(s_req_suppress),
	   .s_axi_ctrl_aclk( 1'b0),
	   .s_axi_ctrl_aresetn(1'b0),
	   .s_axi_ctrl_awvalid(1'b0),
	   .s_axi_ctrl_awready(),
	   .s_axi_ctrl_awaddr( 7'h00 ),
	   .s_axi_ctrl_wvalid(1'b0),
	   .s_axi_ctrl_wready(),
	   .s_axi_ctrl_wdata({32{1'b0}}),
	   .s_axi_ctrl_bvalid(),
	   .s_axi_ctrl_bready(1'b0),
	   .s_axi_ctrl_bresp(),
	   .s_axi_ctrl_arvalid(1'b0),
	   .s_axi_ctrl_arready(),
	   .s_axi_ctrl_araddr(7'h00),
	   .s_axi_ctrl_rvalid(),
	   .s_axi_ctrl_rready(1'b0),
	   .s_axi_ctrl_rdata(),
	   .s_axi_ctrl_rresp(),
	   .s_decode_err() );
   

endmodule // custom_frame_switch_wrap

   
					    
				  
