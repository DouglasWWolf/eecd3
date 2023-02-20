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

    // This pulsess high every time a complete row has been received
    output reg row_complete,
   
    // This pulses high every time a row-header is recieved
    output lvds_data,

    // This is true when we're sitting around doing nothing 
    output reg idle_out,

    // The megabytes-per-second of data received. 1 MBaxis_tready = 1,048,576 bytes
    output reg[31:0] mb_per_sec,

    // This is the number of rows of data received
    output reg[63:0] rows_rcvd,

    // Elapsed seconds since the data-set transfer began
    output reg[31:0] elapsed_secs,

    // The number of data-integrity errors encountered
    output reg[31:0] errors,


    // Data from the two input channels when they hold valid data
    output reg[DATA_WIDTH-1:0] rx0_data, rx1_data,
    output reg[1:0]            rx_last,
    output                     rx_valid,
    output reg[1:0]            rx_buffer_valid,
 

    //========================  AXI Stream interfaces for the input side  ============================
    input[DATA_WIDTH-1:0]     AXIS_CH0_TDATA,
    input[(DATA_WIDTH/8)-1:0] AXIS_CH0_TKEEP,
    input                     AXIS_CH0_TVALID,
    input                     AXIS_CH0_TLAST,
    output                    AXIS_CH0_TREADY,
    
    input[DATA_WIDTH-1:0]     AXIS_CH1_TDATA,
    input[(DATA_WIDTH/8)-1:0] AXIS_CH1_TKEEP,
    input                     AXIS_CH1_TVALID,
    input                     AXIS_CH1_TLAST,
    output                    AXIS_CH1_TREADY,
    //===============================================================================================

    //========================  AXI Stream interface for AXI requests  ==============================
    output [71:0] AXI_REQ_TDATA,
    output reg    AXI_REQ_TVALID,
    input         AXI_REQ_TREADY
    //===============================================================================================
);

//===============================================================================================
// Signals for managing the two input streams
//===============================================================================================

// Names for all four combinations of the two channels
localparam NEITHER = 0;
localparam CH0     = 1;
localparam CH1     = 2;
localparam BOTH    = 3;

// The types of packets we know how to handle
localparam PKT_TYPE_ROW_DATA = 0;
localparam PKT_TYPE_AXI      = 1;
localparam PKT_TYPE_TESTP    = 3;


// axis_tready controls the TREADY lines of both input channels
reg[1:0] axis_tready = BOTH;
assign AXIS_CH0_TREADY = axis_tready[0];
assign AXIS_CH1_TREADY = axis_tready[1];

// Define the handshakes for the two input channels
wire handshake_ch0 = AXIS_CH0_TVALID & AXIS_CH0_TREADY; 
wire handshake_ch1 = AXIS_CH1_TVALID & AXIS_CH1_TREADY; 

// rx_valid is true whenever both input buffers contain valid data
assign rx_valid = (rx_buffer_valid == BOTH);
//===============================================================================================



//===============================================================================================
// Field definitions for the TDATA lines
//===============================================================================================
wire[7:0]  packet_type  = rx1_data[511:504];

wire[31:0] axi_addr_in  = rx1_data[31:00];
wire[31:0] axi_data_in  = rx1_data[63:32];
wire       axi_mode_in  = rx1_data[64];

reg[31:0] axi_addr_out; assign AXI_REQ_TDATA[31:00] = axi_addr_out;
reg[31:0] axi_data_out; assign AXI_REQ_TDATA[63:32] = axi_data_out;
reg       axi_mode_out; assign AXI_REQ_TDATA[64   ] = axi_mode_out;
//===============================================================================================


// This is the frequency of 'clk'
localparam CYCLES_PER_SECOND = 322265625;

// This is the width of the input stream (both channels combined) in bytes
localparam DATA_BYTES = (DATA_WIDTH  + DATA_WIDTH) / 8;

// Number of data-cycles required to receive a 2048 byte row of data (assuming we're receiving on both channels)
localparam DATA_CYCLES_PER_ROW = 2048 / DATA_BYTES;

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
localparam CSM_WAIT_FOR_PACKET = 0;
localparam CSM_WAIT_ROW_DATA   = 1;
localparam CSM_WAIT_ROW_FOOTER = 2;
localparam CSM_TOSS_PACKET     = 3;

// We're going to watch for a low-going edge on "row_requestor_idle"
reg old_row_requestor_idle = 1;

// A new dataset begins on a low-going edge of "row_requestor_idle"
wire new_dataset = (old_row_requestor_idle == 1 && row_requestor_idle == 0);

// Drive this line high every time a row-header arrives
assign lvds_data = (csm_state == 0 & rx_valid & packet_type != 1);


//===============================================================================================
// This state machine reads the two input channels in pairs, effectively merging two input
// channels into a single channel.
//
// At the end of each clock cycle:
//     If rx_valid is 1, rx0_data and rx1_data contain valid input data
//===============================================================================================
always @(posedge clk) begin
    
    if (~handshake_ch0 & ~handshake_ch1) begin      // If no data arrived on either channel
        if (axis_tready[0]) begin                   //   If we were expecting data on Ch0...
            rx_buffer_valid[0] <= 0;                //     The rx buffer for Ch0 is now empty
            rx_last[0]         <= 0;                //     And lower this just for neatness in the ILA display    
        end                                         //   Endif
        
        if (axis_tready[1]) begin                   //   If we were expecting data on Ch1
            rx_buffer_valid[1] <= 0;                //     The rx buffer for Ch1 is now empty
            rx_last[1]         <= 0;                //     And lower this just for neatness in the ILA display
        end                                         //   Endif
    end                                             // Endif
    
    else if (handshake_ch0 & handshake_ch1) begin   // If data arrived on both channels...
        rx0_data        <= AXIS_CH0_TDATA;          //   Capture TDATA from channel 0
        rx_last[0]      <= AXIS_CH0_TLAST;          //   Capture TLAST from channel 0
        rx1_data        <= AXIS_CH1_TDATA;          //   Capture TDATA from channel 1
        rx_last[1]      <= AXIS_CH1_TLAST;          //   Capture TLAST from channel 1
        rx_buffer_valid <= BOTH;                    //   Both rx buffers contain valid data
    end                                             // Endif

    else if (handshake_ch0 & ~handshake_ch1) begin  // If data arrived on Ch0 but not on Ch1
        rx0_data           <= AXIS_CH0_TDATA;       //   Capture TDATA from channel 0
        rx_last[0]         <= AXIS_CH0_TLAST;       //   Capture TLAST from channel 0
        axis_tready[0]     <= ~axis_tready[1];      //   If Ch1 data has previously arrived, make Ch0 ready to receive
        axis_tready[1]     <= 1;                    //   Make Ch1 ready to receive
        rx_buffer_valid[0] <= 1;                    //   The Ch0 rx buffer contains valid data
        rx_buffer_valid[1] <= ~axis_tready[1];      //   If Ch1 data has not yet arrived, mark the buffer as empty
    end                                             // Endif

    else if (~handshake_ch0 & handshake_ch1) begin  // If data arrived on Ch1 but not on Ch0
        rx1_data           <= AXIS_CH1_TDATA;       //   Capture TDATA from channel 1
        rx_last[1]         <= AXIS_CH1_TLAST;       //   Capture TLAST from channel 1
        axis_tready[1]     <= ~axis_tready[0];      //   If Ch0 data has previously arrived, make Ch1 ready to receive
        axis_tready[0]     <= 1;                    //   Make Ch0 ready to receive
        rx_buffer_valid[1] <= 1;                    //   The Ch1 rx buffer contains valid data
        rx_buffer_valid[0] <= ~axis_tready[0];      //   If Ch0 data has not yet arrived, mark the buffer as empty
    end                                             // Endif
end
//===============================================================================================


//===============================================================================================
// This state machine consumes and counts rows of data received
//===============================================================================================

always @(posedge clk) begin

    // Keep track of the current state of "row_requestor_idle" for the next cycle
    old_row_requestor_idle <= row_requestor_idle;

    // When this is raised, it strobes high for exactly one cycle
    AXI_REQ_TVALID <= 0;

    // When this is raised, it will strobe high for exactly one cycle
    row_complete <= 0;

    // Count down the watchdog timer that tells how long since we've received row data
    if (idle_watchdog)
         idle_watchdog <= idle_watchdog - 1;
    else
         if (row_requestor_idle) idle_out <= 1;

    // If we go too long without receiving row-data, pulse the "underflow" output
    underflow_out <= (~row_requestor_idle && idle_watchdog == 1);

    // If the idle-watchdog runs out of time while the row-requestor is idle, the sequencing job has completed
    job_complete_out <= (row_requestor_idle && idle_watchdog == 1);

    // If a new dataset is starting...
    if (new_dataset) begin
        idle_out      <= 0;
        elapsed_secs  <= 0;
        rows_rcvd     <= 0;
        csm_state     <= 0;
        bytes_per_sec <= 0;
        clock_cycles  <= 0;
        seconds       <= 0;

    end else case(csm_state)
        
        // Waiting for the first data-cycle of a packet
        CSM_WAIT_FOR_PACKET:
            
            if (rx_valid) begin
            
                // If this cycle is an AXI read/write request...
                if (packet_type == PKT_TYPE_AXI) begin
                    axi_data_out   <= axi_data_in;      // Fill in the data-word in AXIS_IN_TDATA
                    axi_addr_out   <= axi_addr_in;      // Fill in the AXI address in AXIS_IN_TDATA
                    axi_mode_out   <= axi_mode_in;      // Assume this is an AXI write-request
                    AXI_REQ_TVALID <= 1;                // Emit this AXI read/write request
                end

                else if (packet_type == PKT_TYPE_ROW_DATA) begin
                    idle_watchdog      <= UNDERFLOW_TIMEOUT;
                    data_cycle_counter <= 1;
                    csm_state          <= CSM_WAIT_ROW_DATA;
                end

                else begin
                    csm_state <= CSM_TOSS_PACKET;
                end
            end
        
        // Here we're waiting for all the data-cycles containing row-data to arrive
        CSM_WAIT_ROW_DATA:
        
            if (rx_valid) begin
    
                // Accumulate a total of data-bytes received
                bytes_per_sec <= bytes_per_sec + DATA_BYTES;

                // The input stream isn't idle
                idle_watchdog <= UNDERFLOW_TIMEOUT;

                // If this is the last data-cycle for this row, go wait for the row-footer to arrive
                if (data_cycle_counter == DATA_CYCLES_PER_ROW) begin
                    csm_state <= CSM_WAIT_ROW_FOOTER;
                end 

                // Keep track of how many data-cycles we've recieved
                data_cycle_counter <= data_cycle_counter + 1;
            end

        // Here we're waiting for the row-trailer data-cycle
        CSM_WAIT_ROW_FOOTER:

            if (rx_valid) begin
                rows_rcvd    <= rows_rcvd + 1;
                elapsed_secs <= seconds;
                row_complete <= 1;
                csm_state    <= CSM_WAIT_FOR_PACKET;
            end

        // If we get here we are throwing away an unrecognized packet
        CSM_TOSS_PACKET:
        
            if (rx_valid & rx_last) begin
                csm_state <= CSM_WAIT_FOR_PACKET;
            end

    endcase

    // Once every second, compute the "megabytes per second" throughput rate
    if (~new_dataset) begin
        if (clock_cycles == CYCLES_PER_SECOND) begin
            mb_per_sec    <= bytes_per_sec >> 20;
            bytes_per_sec <= 0;
            clock_cycles  <= 0;
            seconds       <= seconds + 1;
        end else begin
            clock_cycles <= clock_cycles + 1;
        end
    end
end
//===============================================================================================



//===============================================================================================
// This state machine counts the number of malformed row-data records.  This is useful when
// running a bulk data-integrity test using a specially formatted dataset
//===============================================================================================

// Every 32-bit value on the RX0 bus will be one of these values
wire[31:0] value01 = rx0_data[31:0];
wire[31:0] value02 = rx0_data[31:0] ^ 32'hFFFF_FFFF;
wire[31:0] value03 = rx0_data[31:0] ^ 32'hAAAA_AAAA;
wire[31:0] value04 = rx0_data[31:0] ^ 32'h5555_5555;


// Every 32-bit value on the RX1 bus will be one of these values
wire[31:0] value11 = rx1_data[31:0];
wire[31:0] value12 = rx1_data[31:0] ^ 32'hFFFF_FFFF;
wire[31:0] value13 = rx1_data[31:0] ^ 32'hAAAA_AAAA;
wire[31:0] value14 = rx1_data[31:0] ^ 32'h5555_5555;


always @(posedge clk) begin
    
    // Clear the error count whenever a new dataset begins
    if (new_dataset)  errors <= 0;

    // Keep track of how many row-data data-cycles have an error
    if (csm_state == 1 && rx_valid) begin
        if (rx0_data[ 63: 32] != value02) errors <= errors + 1;
        if (rx0_data[ 95: 64] != value03) errors <= errors + 1;
        if (rx0_data[127: 96] != value04) errors <= errors + 1;
        if (rx0_data[159:128] != value01) errors <= errors + 1;
        if (rx0_data[191:160] != value02) errors <= errors + 1;
        if (rx0_data[223:192] != value03) errors <= errors + 1;
        if (rx0_data[255:224] != value04) errors <= errors + 1;
        if (rx0_data[287:256] != value01) errors <= errors + 1;
        if (rx0_data[319:288] != value02) errors <= errors + 1;
        if (rx0_data[351:320] != value03) errors <= errors + 1;
        if (rx0_data[383:352] != value04) errors <= errors + 1;
        if (rx0_data[415:384] != value01) errors <= errors + 1;
        if (rx0_data[447:416] != value02) errors <= errors + 1;
        if (rx0_data[479:448] != value03) errors <= errors + 1;
        if (rx0_data[511:480] != value04) errors <= errors + 1;

        if (rx1_data[ 63: 32] != value12) errors <= errors + 1;
        if (rx1_data[ 95: 64] != value13) errors <= errors + 1;
        if (rx1_data[127: 96] != value14) errors <= errors + 1;
        if (rx1_data[159:128] != value11) errors <= errors + 1;
        if (rx1_data[191:160] != value12) errors <= errors + 1;
        if (rx1_data[223:192] != value13) errors <= errors + 1;
        if (rx1_data[255:224] != value14) errors <= errors + 1;
        if (rx1_data[287:256] != value11) errors <= errors + 1;
        if (rx1_data[319:288] != value12) errors <= errors + 1;
        if (rx1_data[351:320] != value13) errors <= errors + 1;
        if (rx1_data[383:352] != value14) errors <= errors + 1;
        if (rx1_data[415:384] != value11) errors <= errors + 1;
        if (rx1_data[447:416] != value12) errors <= errors + 1;
        if (rx1_data[479:448] != value13) errors <= errors + 1;
        if (rx1_data[511:480] != value14) errors <= errors + 1;
    end

end
//===============================================================================================

endmodule