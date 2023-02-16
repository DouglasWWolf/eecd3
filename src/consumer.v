//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 25-Oct-22  DWW  1000  Initial creation
//===================================================================================================


module axis_consumer#
(
    parameter DATA_WIDTH  = 512
) 
(
    input clk,
    
    // This is high when the row-request engine is idle, low when that engine issuing requests
    input row_requestor_idle,

    // This pulses high when a long break is detected in incoming data and "row_requestor_idle' is low
    output reg underflow_out,
    
    // This pulses high when a long break is detecting in incoming data and 'row_requestor_idle' is high
    output reg job_complete_out,

    // This goes high every time a complete row has been received
    output reg row_complete,
    
    // This goes high every time the first cycle of a new row of data has been received
    output reg lvds_data,

    // The megabytes-per-second of data received. 1 MB = 1,048,576 bytes
    output reg[31:0] mb_per_sec,

    // This is the number of rows of data received
    output reg[63:0] rows_rcvd,

    // Elapsed seconds since the data-set transfer began
    output reg[31:0] elapsed_secs,

    // The number of data-integrity errors encountered
    output reg[31:0] errors,

    //========================  AXI Stream interface for the input side  ============================
    input[DATA_WIDTH-1:0]    AXIS_IN_TDATA,
    input                    AXIS_IN_TVALID,
    output reg               AXIS_IN_TREADY,
    //===============================================================================================

    //========================  AXI Stream interface for AXI requests==  ============================
    output [71:0] AXI_REQ_TDATA,
    output reg    AXI_REQ_TVALID,
    input         AXI_REQ_TREADY
    //===============================================================================================
);

//===============================================================================================
// Field definitions for the TDATA lines
//===============================================================================================
wire[7:0]  packet_type  = AXIS_IN_TDATA[511:504];

wire[31:0] axi_addr_in  = AXIS_IN_TDATA[31:00];
wire[31:0] axi_data_in  = AXIS_IN_TDATA[63:32];
wire       axi_mode_in  = AXIS_IN_TDATA[64];

reg[31:0] axi_addr_out; assign AXI_REQ_TDATA[31:00] = axi_addr_out;
reg[31:0] axi_data_out; assign AXI_REQ_TDATA[63:32] = axi_data_out;
reg       axi_mode_out; assign AXI_REQ_TDATA[64   ] = axi_mode_out;
//===============================================================================================



// This is the frequency of 'clk'
localparam CYCLES_PER_SECOND = 322265625;

// If no row-data arrives for this many cycles, an underflow has occured
localparam UNDERFLOW_TIMEOUT = 1000;

// Counts the number of cycles that have occured where data is received
reg[7:0] data_cycle_counter;

// Counts down to zero when consecutive cycles haven't any received data
reg[31:0] idle_watchdog;

// Counts the number of clock cycles up to CYCLES_PER_SEC
reg[31:0] clock_cycles;

// The number of bytes thus far transferred in the current second
reg[63:0] bytes_per_sec;

// Counts the number of seconds that have elapsed
reg[31:0] seconds;

// State of the consumer state machine
reg[1:0] csm_state;

// We're going to watch for a low-going edge on "row_requestor_idle"
reg old_row_requestor_idle = 1;

// A new dataset begins on a low-going edge of "row_requestor_idle"
wire new_dataset = (old_row_requestor_idle == 1 && row_requestor_idle == 0);

always @(posedge clk) begin

    // Keep track of the current state of "row_requestor_idle" for the next cycle
    old_row_requestor_idle <= row_requestor_idle;

    // We're always ready to receive data
    AXIS_IN_TREADY <= 1;

    // When this is raised, it strobes high for exactly one cycle
    AXI_REQ_TVALID <= 0;

    // When this is raised, it will strobe high for exactly one cycle
    row_complete <= 0;

    // This will be high on the first cycle after a data-row header is received
    lvds_data <= 0;

    // Count down the watchdog timer that tells how long since we've received row data
    if (idle_watchdog) idle_watchdog <= idle_watchdog - 1;

    // If we go too long without receiving row-data, pulse the "underflow" output
    underflow_out <= (~row_requestor_idle && idle_watchdog == 1);

    // If the idle-watchdog runs out of time while the row-requestor is idle, the sequencing job has completed
    job_complete_out <= (row_requestor_idle && idle_watchdog == 1);

    // If a new dataset is starting...
    if (new_dataset) begin
        elapsed_secs  <= 0;
        rows_rcvd     <= 0;
        csm_state     <= 0;
        bytes_per_sec <= 0;

    end else case(csm_state)
        
        // Waiting for the first data-cycle of a packet
        0:  if (AXIS_IN_TVALID & AXIS_IN_TREADY) begin
            
                // If this cycle is an AXI read/write request...
                if (packet_type == 1) begin
                    axi_data_out   <= axi_data_in;  // Fill in the data-word in AXIS_IN_TDATA
                    axi_addr_out   <= axi_addr_in;  // Fill in the AXI address in AXIS_IN_TDATA
                    axi_mode_out   <= axi_mode_in;  // Assume this is an AXI write-request
                    AXI_REQ_TVALID <= 1;            // Emit this AXI read/write request
                end

                else begin

                    // This is the first data-cycle of a row of LVDS data
                    lvds_data <= 1;

                    // Receiving data means we're no longer idle
                    idle_watchdog <= UNDERFLOW_TIMEOUT;

                    // Next data-cycle is the first cycle of row-data
                    data_cycle_counter <= 1;

                    // Go wait for the rest of the data-packet to arrive
                    csm_state <= 1;
                end
            end
        
        // Here we're waiting for all the data-cycles containing row-data to arrive
        1:  if (AXIS_IN_TVALID & AXIS_IN_TREADY) begin
    
                // Accumulate a total of data-bytes received
                bytes_per_sec <= bytes_per_sec + 64;

                // The input stream isn't idle
                idle_watchdog <= UNDERFLOW_TIMEOUT;

                // If this is the 32nd data-cycle, it the last of the data for this row
                if (data_cycle_counter == 32) begin
                    csm_state <= 2;
                end 

                // Keep track of how many data-cycles we've recieved
                data_cycle_counter <= data_cycle_counter + 1;
            end

        // Here we're waiting for the row-trailer data-cycle
        2:  if (AXIS_IN_TVALID & AXIS_IN_TREADY) begin
                rows_rcvd    <= rows_rcvd + 1;
                elapsed_secs <= seconds;
                row_complete <= 1;
                csm_state    <= 0;
            end

    endcase

    // Once every second, compute the "megabytes per second" throughput rate
    if (new_dataset) begin
        clock_cycles <= 0;
        seconds      <= 0;
    end else if (clock_cycles == CYCLES_PER_SECOND) begin
        mb_per_sec    <= bytes_per_sec >> 20;
        bytes_per_sec <= 0;
        clock_cycles  <= 0;
        seconds       <= seconds + 1;
    end else begin
        clock_cycles <= clock_cycles + 1;
    end

end


//===============================================================================================
// This state machine counts the number of malformed row-data records.  This is useful when
// running a bulk data-integrity test using a specially formatted dataset
//===============================================================================================

// Every 32-bit value on the AXIS_IN_TDATA bus will be one of these values
wire[31:0] value1 = AXIS_IN_TDATA[31:0];
wire[31:0] value2 = AXIS_IN_TDATA[31:0] ^ 32'hFFFF_FFFF;
wire[31:0] value3 = AXIS_IN_TDATA[31:0] ^ 32'hAAAA_AAAA;
wire[31:0] value4 = AXIS_IN_TDATA[31:0] ^ 32'h5555_5555;

always @(posedge clk) begin
    
    // Clear the error count whenever a new dataset begins
    if (new_dataset)  errors <= 0;

    // Keep track of how many row-data data-cycles have an error
    if (csm_state == 1 && AXIS_IN_TVALID) begin
        if (AXIS_IN_TDATA[ 63: 32] != value2) errors <= errors + 1;
        if (AXIS_IN_TDATA[ 95: 64] != value3) errors <= errors + 1;
        if (AXIS_IN_TDATA[127: 96] != value4) errors <= errors + 1;
        if (AXIS_IN_TDATA[159:128] != value1) errors <= errors + 1;
        if (AXIS_IN_TDATA[191:160] != value2) errors <= errors + 1;
        if (AXIS_IN_TDATA[223:192] != value3) errors <= errors + 1;
        if (AXIS_IN_TDATA[255:224] != value4) errors <= errors + 1;
        if (AXIS_IN_TDATA[287:256] != value1) errors <= errors + 1;
        if (AXIS_IN_TDATA[319:288] != value2) errors <= errors + 1;
        if (AXIS_IN_TDATA[351:320] != value3) errors <= errors + 1;
        if (AXIS_IN_TDATA[383:352] != value4) errors <= errors + 1;
        if (AXIS_IN_TDATA[415:384] != value1) errors <= errors + 1;
        if (AXIS_IN_TDATA[447:416] != value2) errors <= errors + 1;
        if (AXIS_IN_TDATA[479:448] != value3) errors <= errors + 1;
        if (AXIS_IN_TDATA[511:480] != value4) errors <= errors + 1;
    end

end
//===============================================================================================

endmodule