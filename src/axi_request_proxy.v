//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 08-Sep-22  DWW  1000  Initial creation
//===================================================================================================


`define M_AXI_ADDR_WIDTH 32
`define M_AXI_DATA_WIDTH 32
`define M_AXI_DATA_BYTES (`M_AXI_DATA_WIDTH/8)

module axi_request_proxy
(
    input clk, resetn,

    //=========================  Stream interface for the AXI request  ==============================
    input[95:0]    AXIS_IN_TDATA,
    input          AXIS_IN_TVALID,
    output reg     AXIS_IN_TREADY,
    //===============================================================================================


    //=========================  Stream interface for the AXI response  =============================
    output[255:0]  AXIS_OUT_TDATA,
    output reg     AXIS_OUT_TVALID,
    input          AXIS_OUT_TREADY,
    //===============================================================================================


    //============================  An AXI-Lite Master Interface  ===================================

    // "Specify write address"        -- Master --    -- Slave --
    output[`M_AXI_ADDR_WIDTH-1:0]     M_AXI_AWADDR,   
    output                            M_AXI_AWVALID,  
    output[2:0]                       M_AXI_AWPROT,
    input                                             M_AXI_AWREADY,

    // "Write Data"                   -- Master --    -- Slave --
    output[`M_AXI_DATA_WIDTH-1:0]     M_AXI_WDATA,      
    output                            M_AXI_WVALID,
    output[`M_AXI_DATA_BYTES-1:0]     M_AXI_WSTRB,
    input                                             M_AXI_WREADY,

    // "Send Write Response"          -- Master --    -- Slave --
    input[1:0]                                        M_AXI_BRESP,
    input                                             M_AXI_BVALID,
    output                            M_AXI_BREADY,

    // "Specify read address"         -- Master --    -- Slave --
    output[`M_AXI_ADDR_WIDTH-1:0]     M_AXI_ARADDR,     
    output                            M_AXI_ARVALID,
    output[2:0]                       M_AXI_ARPROT,     
    input                                             M_AXI_ARREADY,

    // "Read data back to master"     -- Master --    -- Slave --
    input[`M_AXI_DATA_WIDTH-1:0]                       M_AXI_RDATA,
    input                                              M_AXI_RVALID,
    input[1:0]                                         M_AXI_RRESP,
    output                            M_AXI_RREADY
    //===============================================================================================
);

    // Some convenience parameters
    localparam M_AXI_ADDR_WIDTH = `M_AXI_ADDR_WIDTH;
    localparam M_AXI_DATA_WIDTH = `M_AXI_DATA_WIDTH;

    //===============================================================================================
    // We'll communicate with the AXI4-Lite Master core with these signals.
    //===============================================================================================

    // AXI Master Control Interface for AXI writes
    reg [M_AXI_ADDR_WIDTH-1:0] amci_waddr;
    reg [M_AXI_DATA_WIDTH-1:0] amci_wdata;
    reg                        amci_write;
    wire[                 1:0] amci_wresp;
    wire                       amci_widle;
   
    // AXI Master Control Interface for AXI reads
    reg [M_AXI_ADDR_WIDTH-1:0] amci_raddr;
    reg                        amci_read;
    wire[M_AXI_DATA_WIDTH-1:0] amci_rdata;
    wire[                 1:0] amci_rresp;
    wire                       amci_ridle;
    //===============================================================================================


    //===============================================================================================
    // Field definitions for the TDATA lines
    //===============================================================================================
    localparam PKT_TYPE_OFFS = 0;
    localparam AXI_MODE_OFFS = 8;
    localparam AXI_RESP_OFFS = 16;
    localparam AXI_ADDR_OFFS = 24;
    localparam AXI_DATA_OFFS = 56;

   
    wire[31:0] axi_addr_in = AXIS_IN_TDATA[AXI_ADDR_OFFS +:32];
    wire[31:0] axi_data_in = AXIS_IN_TDATA[AXI_DATA_OFFS +:32];
    wire       axi_mode_in = AXIS_IN_TDATA[AXI_MODE_OFFS];

    // axi4lite responses are always packet type 1
    assign AXIS_OUT_TDATA[0 +:8] = 1;

    reg[ 7:0] axi_mode_out; assign AXIS_OUT_TDATA[AXI_MODE_OFFS +:8 ] = axi_mode_out;
    reg[ 7:0] axi_resp_out; assign AXIS_OUT_TDATA[AXI_RESP_OFFS +:8 ] = axi_resp_out;
    reg[31:0] axi_addr_out; assign AXIS_OUT_TDATA[AXI_ADDR_OFFS +:32] = axi_addr_out;
    reg[31:0] axi_data_out; assign AXIS_OUT_TDATA[AXI_DATA_OFFS +:32] = axi_data_out;
    //===============================================================================================


    // State definitions for the state machine
    localparam FSM_START              = 0;
    localparam FSM_WAIT_FOR_CMD       = 1;
    localparam FSM_WAIT_FOR_AXI_WRITE = 2;
    localparam FSM_WAIT_FOR_AXI_READ  = 3;
    localparam FSM_STREAM_HANDSHAKE   = 4;

    // This is the state of our state machine
    reg[2:0] fsm_state;

    always @(posedge clk) begin
        
        // When these are raised, they strobe high for exactly 1 clock cycle
        amci_write <= 0;
        amci_read  <= 0;

        if (resetn == 0) begin
            fsm_state       <= 0;
            AXIS_IN_TREADY  <= 0;
            AXIS_OUT_TVALID <= 0;
        end

        else case (fsm_state)

            FSM_START:
                begin
                    AXIS_IN_TREADY <= 1;
                    fsm_state      <= FSM_WAIT_FOR_CMD;
                end
            
            FSM_WAIT_FOR_CMD:
                if (AXIS_IN_TREADY & AXIS_IN_TVALID) begin
                   AXIS_IN_TREADY <= 0;
                    axi_mode_out <= axi_mode_in;
                    if (axi_mode_in == 0) begin
                        amci_waddr  <= axi_addr_in;
                        amci_wdata  <= axi_data_in;
                        amci_write  <= 1;
                        fsm_state   <= FSM_WAIT_FOR_AXI_WRITE;
                    end else begin
                        amci_raddr  <= axi_addr_in;
                        amci_read   <= 1;
                        fsm_state   <= FSM_WAIT_FOR_AXI_READ;
                    end

                end
            
            FSM_WAIT_FOR_AXI_WRITE:
                if (amci_widle) begin
                    axi_addr_out    <= amci_waddr;
                    axi_data_out    <= amci_wdata;
                    axi_resp_out    <= amci_wresp;
                    AXIS_OUT_TVALID <= 1;
                    fsm_state       <= FSM_STREAM_HANDSHAKE;
                end
            
            FSM_WAIT_FOR_AXI_READ:
                if (amci_ridle) begin
                    axi_addr_out    <= amci_raddr;
                    axi_data_out    <= amci_rdata;
                    axi_resp_out    <= amci_rresp;
                    AXIS_OUT_TVALID <= 1;
                    fsm_state       <= FSM_STREAM_HANDSHAKE;                    
                end
            
            FSM_STREAM_HANDSHAKE:
                if (AXIS_OUT_TVALID & AXIS_OUT_TREADY) begin
                    AXIS_OUT_TVALID <= 0;
                    AXIS_IN_TREADY  <= 1;
                    fsm_state       <= FSM_WAIT_FOR_CMD;
                end


        endcase
        
    end


    //===============================================================================================
    // This connects us to an AXI4-Lite master core that drives the system interconnect
    //===============================================================================================
    axi4_lite_master# 
    (
        .AXI_ADDR_WIDTH(M_AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(M_AXI_DATA_WIDTH)        
    )
    axi_master_to_system
    (
        .clk            (clk),
        .resetn         (resetn),
        
        // AXI AW channel
        .AXI_AWADDR     (M_AXI_AWADDR ),
        .AXI_AWVALID    (M_AXI_AWVALID),   
        .AXI_AWPROT     (M_AXI_AWPROT ),
        .AXI_AWREADY    (M_AXI_AWREADY),
        
        // AXI W channel
        .AXI_WDATA      (M_AXI_WDATA ),
        .AXI_WVALID     (M_AXI_WVALID),
        .AXI_WSTRB      (M_AXI_WSTRB ),
        .AXI_WREADY     (M_AXI_WREADY),

        // AXI B channel
        .AXI_BRESP      (M_AXI_BRESP ),
        .AXI_BVALID     (M_AXI_BVALID),
        .AXI_BREADY     (M_AXI_BREADY),

        // AXI AR channel
        .AXI_ARADDR     (M_AXI_ARADDR ), 
        .AXI_ARVALID    (M_AXI_ARVALID),
        .AXI_ARPROT     (M_AXI_ARPROT ),
        .AXI_ARREADY    (M_AXI_ARREADY),

        // AXI R channel
        .AXI_RDATA      (M_AXI_RDATA ),
        .AXI_RVALID     (M_AXI_RVALID),
        .AXI_RRESP      (M_AXI_RRESP ),
        .AXI_RREADY     (M_AXI_RREADY),

        // AMCI write registers
        .AMCI_WADDR     (amci_waddr),
        .AMCI_WDATA     (amci_wdata),
        .AMCI_WRITE     (amci_write),
        .AMCI_WRESP     (amci_wresp),
        .AMCI_WIDLE     (amci_widle),

        // AMCI read registers
        .AMCI_RADDR     (amci_raddr),
        .AMCI_RDATA     (amci_rdata),
        .AMCI_READ      (amci_read ),
        .AMCI_RRESP     (amci_rresp),
        .AMCI_RIDLE     (amci_ridle)
    );
    //===============================================================================================

endmodule