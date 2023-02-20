//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 19-Feb-23  DWW  1000  Initial creation
//===================================================================================================


module bpf_stage2 #
(
    parameter DATA_WIDTH  = 512
) 
(
    input clk, resetn,

    //=========================  AXI Stream interface for the input side  ============================
    input[DATA_WIDTH-1:0]      AXIS_RX_TDATA,
    input[(DATA_WIDTH/8)-1:0]  AXIS_RX_TKEEP,
    input                      AXIS_RX_TVALID,
    input                      AXIS_RX_TLAST,
    input                      AXIS_RX_TUSER,
    output reg                 AXIS_RX_TREADY,
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
    input[7:0] AXIS_PS_TDATA,
    input      AXIS_PS_TVALID,
    output reg AXIS_PS_TREADY
    //===============================================================================================
);

// This is what a garbage data-cycle looks like
localparam[511:0] GARBAGE = 512'hFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFEFE;

// The output stream is mapped directly to the input stream
assign AXIS_TX_TDATA  = AXIS_RX_TDATA;
assign AXIS_TX_TKEEP  = AXIS_RX_TKEEP;
assign AXIS_TX_TLAST  = AXIS_RX_TLAST;
assign AXIS_TX_TUSER  = AXIS_RX_TUSER;

reg[1:0] fsm_state;
reg      bad_packet;

// The TX stream is only valid during an RX handshake and the RX data isn't garbage
assign AXIS_TX_TVALID = (AXIS_RX_TVALID & AXIS_RX_TREADY) & ~(bad_packet & AXIS_RX_TDATA == GARBAGE);


//===============================================================================================
// This state machine waits for a byte to arrive on AXIS_PS.  When it does, it will then read
// an entire packet from AXIS_RX, and pass on (to AXIS_TX) every data-cycle that isn't garbage
//===============================================================================================
always @(posedge clk) begin
    if (resetn == 0) begin
        fsm_state      <= 0;
        AXIS_PS_TREADY <= 0;
        AXIS_RX_TREADY <= 0;
    end else case(fsm_state)

        // As we come out of reset, we want to read from the "packet-status" queue
        0:  begin
                AXIS_RX_TREADY <= 0;
                AXIS_PS_TREADY <= 1;
                fsm_state      <= 1;
            end

        // If something has arrive on the PS (packet-status) stream...
        1:  if (AXIS_PS_TVALID) begin
                bad_packet     <= AXIS_PS_TDATA;
                AXIS_PS_TREADY <= 0;
                AXIS_RX_TREADY <= 1;
                fsm_state      <= 2;
            end

        // Keep copying data cycles from RX to TX until we hit the end of the packet
        2:  if (AXIS_RX_TVALID & AXIS_RX_TLAST) begin
                AXIS_PS_TREADY <= 1;
                AXIS_RX_TREADY <= 0;
                fsm_state      <= 1;
            end


    endcase

end
//===============================================================================================


endmodule