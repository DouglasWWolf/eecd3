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

    // This is high when the row-request engine is active and issuing requests
    input row_requestor_active,

    // This pulses high when a long break is detected in incoming data and "row_requestor_active' is high
    output reg underflow_out,
  
    // This pulses high when a long break is detected in incoming data and 'row_requestor_active' is low
    output reg job_complete_out,

    // This pulsess high every time a complete row has been received
    output reg row_complete,
   
    // This pulses high every time a row-header is recieved
    output lvds_data,

    // This is true when we're sitting around doing nothing 
    output idle_out,

    // The megabytes-per-second of data received. 1 MBaxis_tready = 1,048,576 bytes
    output reg[31:0] mb_per_sec,

    // The number of bad packets encountered
    output reg[31:0] bad_packets,

    // This is the number of rows of data received
    output reg[63:0] rows_rcvd,

    // Elapsed seconds since the data-set transfer began
    output reg[31:0] elapsed_secs,

    // The number of data-integrity errors encountered
    output reg[31:0] errors,


    // Data from the two input channels when they hold valid data
    output reg[DATA_WIDTH-1:0] rx0_data, rx1_data,
    output reg[1:0]            rx_tlast,
    output                     rx_valid,
    output reg[1:0]            rx_buffer_valid,
 

    //========================  AXI Stream interfaces for the input side  ============================
    input[DATA_WIDTH-1:0]     AXIS_CH0_TDATA,
    input[(DATA_WIDTH/8)-1:0] AXIS_CH0_TKEEP,
    input                     AXIS_CH0_TVALID,
    input                     AXIS_CH0_TLAST,
    input                     AXIS_CH0_TUSER,
    output                    AXIS_CH0_TREADY,
    
    input[DATA_WIDTH-1:0]     AXIS_CH1_TDATA,
    input[(DATA_WIDTH/8)-1:0] AXIS_CH1_TKEEP,
    input                     AXIS_CH1_TVALID,
    input                     AXIS_CH1_TLAST,
    input                     AXIS_CH1_TUSER,
    output                    AXIS_CH1_TREADY,
    //===============================================================================================

    //========================  AXI Stream interface for AXI requests  ==============================
    output reg [95:0] AXI_REQ_TDATA,
    output reg        AXI_REQ_TVALID,
    input             AXI_REQ_TREADY
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
wire[7:0] packet_type  = rx1_data[7:0];

// This is the frequency of 'clk'
localparam CYCLES_PER_SECOND = 322265625;

// This is the width of the input stream (both channels combined) in bytes
localparam DATA_BYTES = (DATA_WIDTH  + DATA_WIDTH) / 8;

// Number of data-cycles required to receive a 2048 byte row of data (assuming we're receiving on both channels)
localparam DATA_CYCLES_PER_ROW = 2048 / DATA_BYTES;

// When "silence_counter" hits this value, the receive stream is considered "silent"
localparam SILENT_LIMIT = 100000;

// If no row-data arrives for this many cycles, an underflow has occured.  This value should be less than
// the SILENT_LIMIT
localparam UNDERFLOW_TIMEOUT = 1000;

// Counts the number of cycles that have occured where data is received
reg[7:0] data_cycle_counter;

// This counter is incremented on every clock cycle when the RX stream is silent
reg[31:0] silence_counter = SILENT_LIMIT;

// We are considered 'silent' when the 
wire rx_silent = (silence_counter == SILENT_LIMIT && ~rx_valid);

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

// A new dataset begins on the first valid data-cycle during a silent period
wire new_dataset = (silence_counter == SILENT_LIMIT && rx_valid);

// Drive this line high every time a row-header arrives
assign lvds_data = (csm_state == 0 & rx_valid & packet_type == PKT_TYPE_ROW_DATA);

// For visual use in the ILA: we're idle when the RX channel is silent and the row requestor is idle
assign idle_out = rx_silent & ~row_requestor_active;

//===============================================================================================
// This state machine reads the two input channels in pairs, effectively merging two input
// channels into a single channel.
//
// At the end of each clock cycle:
//     If rx_valid is 1, rx0_data and rx1_data contain valid input data
//===============================================================================================
always @(posedge clk) begin

    // Keep track of how many bad packets we encounter
    if (handshake_ch0 & AXIS_CH0_TUSER) bad_packets <= bad_packets + 1;
    if (handshake_ch1 & AXIS_CH1_TUSER) bad_packets <= bad_packets + 1;
    if (new_dataset)                    bad_packets <= 0;

    if (~handshake_ch0 & ~handshake_ch1) begin      // If no data arrived on either channel
        if (axis_tready[0]) begin                   //   If we were expecting data on Ch0...
            rx_buffer_valid[0] <= 0;                //     The rx buffer for Ch0 is now empty
            rx_tlast[0]        <= 0;                //     And lower this just for neatness in the ILA display    
        end                                         //   Endif
        
        if (axis_tready[1]) begin                   //   If we were expecting data on Ch1
            rx_buffer_valid[1] <= 0;                //     The rx buffer for Ch1 is now empty
            rx_tlast[1]        <= 0;                //     And lower this just for neatness in the ILA display
        end                                         //   Endif
    end                                             // Endif
    
    else if (handshake_ch0 & handshake_ch1) begin   // If data arrived on both channels...
        rx0_data        <= AXIS_CH0_TDATA;          //   Capture TDATA from channel 0
        rx_tlast[0]     <= AXIS_CH0_TLAST;          //   Capture TLAST from channel 0
        rx1_data        <= AXIS_CH1_TDATA;          //   Capture TDATA from channel 1
        rx_tlast[1]     <= AXIS_CH1_TLAST;          //   Capture TLAST from channel 1
        rx_buffer_valid <= BOTH;                    //   Both rx buffers contain valid data
    end                                             // Endif

    else if (handshake_ch0 & ~handshake_ch1) begin  // If data arrived on Ch0 but not on Ch1
        rx0_data           <= AXIS_CH0_TDATA;       //   Capture TDATA from channel 0
        rx_tlast[0]        <= AXIS_CH0_TLAST;       //   Capture TLAST from channel 0
        axis_tready[0]     <= ~axis_tready[1];      //   If Ch1 data has previously arrived, make Ch0 ready to receive
        axis_tready[1]     <= 1;                    //   Make Ch1 ready to receive
        rx_buffer_valid[0] <= 1;                    //   The Ch0 rx buffer contains valid data
        rx_buffer_valid[1] <= ~axis_tready[1];      //   If Ch1 data has not yet arrived, mark the buffer as empty
    end                                             // Endif

    else if (~handshake_ch0 & handshake_ch1) begin  // If data arrived on Ch1 but not on Ch0
        rx1_data           <= AXIS_CH1_TDATA;       //   Capture TDATA from channel 1
        rx_tlast[1]        <= AXIS_CH1_TLAST;       //   Capture TLAST from channel 1
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

    // When this is raised, it strobes high for exactly one cycle
    AXI_REQ_TVALID <= 0;

    // When this is raised, it will strobe high for exactly one cycle
    row_complete <= 0;

    // Keep track of the number of consecutive cycles of no RX data
    if (~rx_valid & silence_counter < SILENT_LIMIT) silence_counter <= silence_counter + 1;

    // If we go too long without receiving row-data, pulse the "underflow" output
    underflow_out <= (row_requestor_active && silence_counter == UNDERFLOW_TIMEOUT);

    // If the idle-watchdog runs out of time while the row-requestor is idle, the sequencing job has completed
    job_complete_out <= (~row_requestor_active & ~rx_valid & silence_counter == SILENT_LIMIT - 1);

    case(csm_state)
        
        // Waiting for the first data-cycle of a packet
        CSM_WAIT_FOR_PACKET:
            
            if (rx_valid) begin
            
                // If this cycle is an AXI read/write request...
                if (packet_type == PKT_TYPE_AXI) begin
                    AXI_REQ_TDATA  <= rx1_data;         // Copy this message to the AXI_REQ output bus
                    AXI_REQ_TVALID <= 1;                // Emit this AXI read/write request
                end

                // Otherwise, if this is the header-cycle for a packet of row-data...
                else if (packet_type == PKT_TYPE_ROW_DATA) begin
                    silence_counter    <= 0;
                    data_cycle_counter <= 1;
                    csm_state          <= CSM_WAIT_ROW_DATA;
                end

                // Otherwise assume this is test-pattern data
                else begin
                    silence_counter    <= 0;
                    bytes_per_sec      <= bytes_per_sec + DATA_BYTES;
                    csm_state          <= CSM_TOSS_PACKET;
                end
            end
        
        // Here we're waiting for all the data-cycles containing row-data to arrive
        CSM_WAIT_ROW_DATA:
        
            if (rx_valid) begin
                bytes_per_sec   <= bytes_per_sec + DATA_BYTES;
                silence_counter <= 0;
                if (data_cycle_counter == DATA_CYCLES_PER_ROW) begin
                    csm_state  <= CSM_WAIT_ROW_FOOTER;
                end 
                data_cycle_counter <= data_cycle_counter + 1;
            end

        // Here we're waiting for the row-trailer data-cycle
        CSM_WAIT_ROW_FOOTER:

            if (rx_valid) begin
                silence_counter <= 0;
                rows_rcvd       <= rows_rcvd + 1;
                elapsed_secs    <= seconds;
                row_complete    <= 1;
                csm_state       <= CSM_WAIT_FOR_PACKET;
            end

        // If we get here we are throwing away an unrecognized packet
        CSM_TOSS_PACKET:

            if (rx_valid) begin
                bytes_per_sec   <= bytes_per_sec + DATA_BYTES;
                silence_counter <= 0;

                if (rx_tlast) begin
                    rows_rcvd    <= rows_rcvd + 1;
                    elapsed_secs <= seconds;
                    csm_state    <= CSM_WAIT_FOR_PACKET;
                end
            end

    endcase


    // If RX is silent, our state machine is always idle
    if (rx_silent) csm_state <= 0;

    // If a new dataset is starting...
    if (new_dataset) begin
        elapsed_secs  <= 0;
        rows_rcvd     <= 0;
        bytes_per_sec <= 0;
        clock_cycles  <= 0;
        seconds       <= 0;
    end

    // Once every second, compute the "megabytes per second" throughput rate
    else begin
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
    if (new_dataset) errors <= 0;

    // Keep track of how many row-data data-cycles have an error
    if (csm_state == CSM_WAIT_ROW_DATA && rx_valid) begin
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