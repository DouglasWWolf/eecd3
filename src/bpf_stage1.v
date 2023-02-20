//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 19-Feb-23  DWW  1000  Initial creation
//===================================================================================================


module bpf_stage1 #
(
    parameter DATA_WIDTH  = 512
) 
(
    input clk,

    //=========================  AXI Stream interface for the input side  ============================
    input[DATA_WIDTH-1:0]      AXIS_RX_TDATA,
    input[(DATA_WIDTH/8)-1:0]  AXIS_RX_TKEEP,
    input                      AXIS_RX_TVALID,
    input                      AXIS_RX_TLAST,
    input                      AXIS_RX_TUSER,
    output                     AXIS_RX_TREADY,
    //===============================================================================================


    //=======================  AXI Stream interface for the output side  ============================
    output[DATA_WIDTH-1:0]     AXIS_TX_TDATA,
    output[(DATA_WIDTH/8)-1:0] AXIS_TX_TKEEP,
    output                     AXIS_TX_TVALID,
    output                     AXIS_TX_TLAST,
    output                     AXIS_TX_TUSER,
    input                      AXIS_TX_TREADY,
    //===============================================================================================


    //====================  AXI Stream interface for the packet-status output  ======================
    output[7:0] AXIS_PS_TDATA,
    output      AXIS_PS_TVALID,
    input       AXIS_PS_TREADY
    //===============================================================================================
);

// The output stream is mapped directly to the input stream
assign AXIS_TX_TDATA  = AXIS_RX_TDATA;
assign AXIS_TX_TKEEP  = AXIS_RX_TKEEP;
assign AXIS_TX_TVALID = AXIS_RX_TVALID;
assign AXIS_TX_TLAST  = AXIS_RX_TLAST;
assign AXIS_TX_TUSER  = AXIS_RX_TUSER;
assign AXIS_RX_TREADY = AXIS_TX_TREADY;

//===============================================================================================
// This writes either 0 or 1 to the PS (Packet Status) stream whenever we detect the last
// data-cycle of a packet.  
//
// 0 = No error, 1 = bad-packet
//===============================================================================================
assign AXIS_PS_TDATA  = AXIS_RX_TUSER;
assign AXIS_PS_TVALID = AXIS_RX_TVALID & AXIS_RX_TLAST;
//===============================================================================================


endmodule