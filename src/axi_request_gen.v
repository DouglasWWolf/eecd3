//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 15-Nov-22  DWW  1000  Initial creation
//====================================================================================

/*

Usage:


*/


module axi_request_gen
(
    // Clock and reset
    input clk, resetn,

    // This will pulse high every time a complete row of data has been received from ECD_Master
    input row_complete_in,

    // This is high when we're not busy generating row-requests
    output idle_out,

    // A pulse from this signal generates 8 requests
    input button,
    
    //========================  AXI Stream interface for sending requests  ==========================
    output reg[255:0]  AXIS_TX_TDATA,
    output             AXIS_TX_TVALID,
    output             AXIS_TX_TLAST,
    input              AXIS_TX_TREADY,
    //===============================================================================================


    //================== This is an AXI4-Lite slave interface ==================
        
    // "Specify write address"              -- Master --    -- Slave --
    input[31:0]                             S_AXI_AWADDR,   
    input                                   S_AXI_AWVALID,  
    output                                                  S_AXI_AWREADY,
    input[2:0]                              S_AXI_AWPROT,

    // "Write Data"                         -- Master --    -- Slave --
    input[31:0]                             S_AXI_WDATA,      
    input                                   S_AXI_WVALID,
    input[3:0]                              S_AXI_WSTRB,
    output                                                  S_AXI_WREADY,

    // "Send Write Response"                -- Master --    -- Slave --
    output[1:0]                                             S_AXI_BRESP,
    output                                                  S_AXI_BVALID,
    input                                   S_AXI_BREADY,

    // "Specify read address"               -- Master --    -- Slave --
    input[31:0]                             S_AXI_ARADDR,     
    input                                   S_AXI_ARVALID,
    input[2:0]                              S_AXI_ARPROT,     
    output                                                  S_AXI_ARREADY,

    // "Read data back to master"           -- Master --    -- Slave --
    output[31:0]                                            S_AXI_RDATA,
    output                                                  S_AXI_RVALID,
    output[1:0]                                             S_AXI_RRESP,
    input                                   S_AXI_RREADY
    //==========================================================================
 );

    //==========================================================================
    // We'll communicate with the AXI4-Lite Slave core with these signals.
    //==========================================================================
    // AXI Slave Handler Interface for write requests
    wire[31:0]  ashi_waddr;     // Input:  Write-address
    wire[31:0]  ashi_wdata;     // Input:  Write-data
    wire        ashi_write;     // Input:  1 = Handle a write request
    reg[1:0]    ashi_wresp;     // Output: Write-response (OKAY, DECERR, SLVERR)
    wire        ashi_widle;     // Output: 1 = Write state machine is idle

    // AXI Slave Handler Interface for read requests
    wire[31:0]  ashi_raddr;     // Input:  Read-address
    wire        ashi_read;      // Input:  1 = Handle a read request
    reg[31:0]   ashi_rdata;     // Output: Read data
    reg[1:0]    ashi_rresp;     // Output: Read-response (OKAY, DECERR, SLVERR);
    wire        ashi_ridle;     // Output: 1 = Read state machine is idle
    //==========================================================================

    // This is the maximum number of requests we can have "in flight"
    localparam MAX_OUTSTANDING_REQUESTS = 16;

    // The state of our two state machines
    reg[2:0] read_state, write_state;

    // The state machines are idle when they're in state 0 when their "start" signals are low
    assign ashi_widle = (ashi_write == 0) && (write_state == 0);
    assign ashi_ridle = (ashi_read  == 0) && (read_state  == 0);

    // These are the valid values for ashi_rresp and ashi_wresp
    localparam OKAY   = 0;
    localparam SLVERR = 2;
    localparam DECERR = 3;

    // An AXI slave is gauranteed a minimum of 128 bytes of address space
    // (128 bytes is 32 32-bit registers)
    localparam ADDR_MASK = 7'h7F;

    // The indicies of the AXI registers
    localparam REG_COUNTH = 0;
    localparam REG_COUNTL = 1;
    localparam REG_START  = 2;

    // The contents of the AXI registers
    reg[31:0] axi_register[0:2];

    // When this goes high, requests start getting sent out
    reg start_requesting;

    // State of the "requester state-machine"
    reg rsm_state;

    // The 'idle_out' line is high when the requestor-state-machine is idle
    assign idle_out = (rsm_state == 0);
    
    //==========================================================================
    // This state machine handles AXI write-requests
    //==========================================================================
    always @(posedge clk) begin

        // When this goes high, it strobes high for exactly 1 clock cycle
        start_requesting <= 0;

        // If we're in reset, initialize important registers
        if (resetn == 0) begin
            write_state              <= 0;
            axi_register[REG_COUNTH] <= 0;
            axi_register[REG_COUNTL] <= 32;
        
        // If we're not in reset...
        end else begin

            // Pressing the button sends a block of 8 requests
            if (button) begin
                axi_register[REG_COUNTH] <= 0;
                axi_register[REG_COUNTL] <= 8;
                start_requesting         <= 1;
            end

            // If a write-request has come in...
            if (ashi_write) begin

                // Assume for a moment that we will be reporting "OKAY" as a write-response
                ashi_wresp <= OKAY;

                case((ashi_waddr & ADDR_MASK) >> 2)

                    REG_COUNTH: axi_register[REG_COUNTH] <= ashi_wdata;
                    REG_COUNTL: axi_register[REG_COUNTL] <= ashi_wdata;

                    REG_START: 
                        begin
                            if (rsm_state == 0) start_requesting <= 1;
                        end

                    // A write to any other address is a slave-error
                    default: ashi_wresp <= SLVERR;
                endcase
            end
        end
    end
    //==========================================================================


 
    //==========================================================================
    // World's simplest state machine for handling read requests
    //==========================================================================
    always @(posedge clk) begin

        // If we're in reset, initialize important registers
        if (resetn == 0) begin
            read_state <= 0;
        
        // If we're not in reset, and a read-request has occured...        
        end else if (ashi_read) begin
        
            // We'll always acknowledge the read as valid
            ashi_rresp <= OKAY;

            case((ashi_raddr & ADDR_MASK) >> 2)

                REG_COUNTH: ashi_rdata <= axi_register[REG_COUNTH];
                REG_COUNTL: ashi_rdata <= axi_register[REG_COUNTL];

                // A read of any other address returns a 0
                default: ashi_rdata <= 0;
            endcase
        end
    end
    //==========================================================================


    //==========================================================================
    // State machine that sends out requests
    //==========================================================================
    
    // # of data requests sent, and # of data-requests fulfilled
    reg[63:0] requests_sent, requests_completed;

    // Total number of requests we need to send (-1)
    reg[63:0] max_requests;

    // The total number of unfulfilled requests outstanding 
    wire[31:0] requests_outstanding = requests_sent - requests_completed;

    // We send out a new request anytime "requests_outstanding" drops below
    // our threshold
    assign AXIS_TX_TVALID = (rsm_state == 1) & (requests_outstanding < MAX_OUTSTANDING_REQUESTS);

    //==========================================================================
    always @(posedge clk) begin
        
        // Keep track of the number of row-requests that have been fullfilled
        if (rsm_state && row_complete_in) requests_completed <= requests_completed + 1;

        if (resetn == 0) begin
            rsm_state <= 0;
        end

        else case (rsm_state)

        // Here we're waiting around for another thread to tell us to start
        0:  if (start_requesting) begin
                requests_completed <= 0;
                requests_sent      <= 0;
                max_requests       <= {axi_register[REG_COUNTH], axi_register[REG_COUNTL]} - 1;
                AXIS_TX_TDATA      <= 32'h0000_C008;
                rsm_state          <= 1;
            end

        1:  if (AXIS_TX_TVALID & AXIS_TX_TREADY) begin
                AXIS_TX_TDATA[31:0] <= AXIS_TX_TDATA[31:0] + 1;
                if (requests_sent == max_requests) begin
                    rsm_state <= 0;
                end
                requests_sent <= requests_sent + 1;
            end

        endcase
    end
    //==========================================================================

    //==========================================================================
    // This connects us to an AXI4-Lite slave core
    //==========================================================================
    axi4_lite_slave axi_slave
    (
        .clk            (clk),
        .resetn         (resetn),
        
        // AXI AW channel
        .AXI_AWADDR     (S_AXI_AWADDR),
        .AXI_AWVALID    (S_AXI_AWVALID),   
        .AXI_AWPROT     (S_AXI_AWPROT),
        .AXI_AWREADY    (S_AXI_AWREADY),
        
        // AXI W channel
        .AXI_WDATA      (S_AXI_WDATA),
        .AXI_WVALID     (S_AXI_WVALID),
        .AXI_WSTRB      (S_AXI_WSTRB),
        .AXI_WREADY     (S_AXI_WREADY),

        // AXI B channel
        .AXI_BRESP      (S_AXI_BRESP),
        .AXI_BVALID     (S_AXI_BVALID),
        .AXI_BREADY     (S_AXI_BREADY),

        // AXI AR channel
        .AXI_ARADDR     (S_AXI_ARADDR), 
        .AXI_ARVALID    (S_AXI_ARVALID),
        .AXI_ARPROT     (S_AXI_ARPROT),
        .AXI_ARREADY    (S_AXI_ARREADY),

        // AXI R channel
        .AXI_RDATA      (S_AXI_RDATA),
        .AXI_RVALID     (S_AXI_RVALID),
        .AXI_RRESP      (S_AXI_RRESP),
        .AXI_RREADY     (S_AXI_RREADY),

        // ASHI write-request registers
        .ASHI_WADDR     (ashi_waddr),
        .ASHI_WDATA     (ashi_wdata),
        .ASHI_WRITE     (ashi_write),
        .ASHI_WRESP     (ashi_wresp),
        .ASHI_WIDLE     (ashi_widle),

        // AMCI-read registers
        .ASHI_RADDR     (ashi_raddr),
        .ASHI_RDATA     (ashi_rdata),
        .ASHI_READ      (ashi_read ),
        .ASHI_RRESP     (ashi_rresp),
        .ASHI_RIDLE     (ashi_ridle)
    );
    //==========================================================================

endmodule






