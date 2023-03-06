//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// This module watches input strobes and uses them to report events on an AXI stream bus
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

//===================================================================================================
//                            ------->  Revision History  <------
//===================================================================================================
//
//   Date     Who   Ver  Changes
//===================================================================================================
// 25-Dec-22  DWW  1000  Initial creation
//===================================================================================================


module event_reporter
(
    input clk, resetn,

    input report_underflow, report_jobcomplete, report_event_b,

    //========================  AXI Stream interface for the output side  ===========================
    output[255:0]  AXIS_OUT_TDATA,
    output reg     AXIS_OUT_TVALID,
    input          AXIS_OUT_TREADY
    //===============================================================================================
);


// This is the number of different types of events we can track
localparam EVENT_TYPES = 3;

// This is the bit position in 'event_list that represents a given event
localparam EVT_UNDERFLOW   = 0;
localparam EVT_JOBCOMPLETE = 1;
localparam EVT_EVENT_B     = 2;

// This aggregates all of the event input strobes into a single 'event_list'
wire[EVENT_TYPES-1:0] event_list;
assign event_list[EVT_UNDERFLOW  ] = report_underflow;
assign event_list[EVT_JOBCOMPLETE] = report_jobcomplete;
assign event_list[EVT_EVENT_B    ] = report_event_b;
 
// This is the input to the FIFO, a registered version of 'event_list'
reg[EVENT_TYPES-1:0] fifo_din;

// These 'event constants' are the event-codes that will be written to the output AXI Stream 
wire[7:0] event_constant[0:EVENT_TYPES-1];
assign event_constant[EVT_UNDERFLOW  ] = 1;
assign event_constant[EVT_JOBCOMPLETE] = 2;
assign event_constant[EVT_EVENT_B    ] = 3;

// This is the output of the FIFO and is the report_XXX input signals all grouped together
wire[EVENT_TYPES-1:0] fifo_dout;

// Write-enable and read-enable signals for the FIFO
reg fifo_wren, fifo_rden;

// This will be high when the FIFO is empty, low when the FIFO contains at least one entry
wire fifo_empty;

// This holds the EVENT_CODE_xxxx that gets written into AXIS_OUT_TDATA
reg[7:0] event_code;

// Byte 0 of the message is the message type, always "2"
assign AXIS_OUT_TDATA[0 +:8] = 2; 

// Byte 1 of the message is the event code
assign AXIS_OUT_TDATA[8 +:8] = event_code;

// Each of the report_xxxx inputs ends up as a bit in this register
reg[EVENT_TYPES-1:0] event_group;

//===============================================================================================
// On any clock cycle during which an event signal is active, write the event_list to the FIFO
//===============================================================================================
always @(posedge clk) begin
    fifo_din  <= event_list;
    fifo_wren <= (event_list != 0) & (resetn == 1);
end
//===============================================================================================


//===============================================================================================
// This state machine reads entries from the FIFO, and outputs a data-cycle on the output stream
// for every bit that is set in an event-group.
//===============================================================================================
// The state of this state machine
reg fsm_state;
//===============================================================================================
always @(posedge clk) begin
    
    // This only strobes high for a single cycle
    fifo_rden <= 0;

    // If we're in RESET, perform basic initialization
    if (resetn == 0) begin
        fsm_state       <= 0;
        AXIS_OUT_TVALID <= 0;
    
    // Otherwise, if we're not in reset...
    end else case (fsm_state)

        // Here we wait around for an event-group to arrive at the read-end of the FIFO
        0: if (~fifo_empty) begin
                event_group     <= fifo_dout;
                fifo_rden       <= 1;
                AXIS_OUT_TVALID <= 0;
                fsm_state       <= 1;
            end

        // Here we write a data-cycle to the output stream for each bit in the group that is a '1'
        1:  if (AXIS_OUT_TVALID == 0 || AXIS_OUT_TREADY) begin
                
                if (event_group == 0)
                    fsm_state <= 0;

                else if (event_group[0]) begin
                    event_group[0] <= 0;
                    event_code     <= event_constant[0];
                end
           
                else if (event_group[1]) begin
                    event_group[1] <= 0;
                    event_code     <= event_constant[1];
                end

                else if (event_group[2]) begin
                    event_group[2] <= 0;
                    event_code     <= event_constant[2];
                end

                AXIS_OUT_TVALID <= (event_group != 0);
            end

    endcase
end
//===============================================================================================



//===============================================================================================
// This is the FIFO that holds incoming event notifications
//===============================================================================================
xpm_fifo_sync #
(
    .CASCADE_HEIGHT       (0),
    .DOUT_RESET_VALUE     ("0"),
    .ECC_MODE             ("no_ecc"),
    .FIFO_MEMORY_TYPE     ("auto"),
    .FIFO_READ_LATENCY    (1),
    .FIFO_WRITE_DEPTH     (16),
    .FULL_RESET_VALUE     (0),
    .PROG_EMPTY_THRESH    (10),
    .PROG_FULL_THRESH     (10),
    .RD_DATA_COUNT_WIDTH  (1),
    .READ_DATA_WIDTH      (EVENT_TYPES),
    .READ_MODE            ("fwft"),
    .SIM_ASSERT_CHK       (0),
    .USE_ADV_FEATURES     ("0000"),
    .WAKEUP_TIME          (0),
    .WRITE_DATA_WIDTH     (EVENT_TYPES),
    .WR_DATA_COUNT_WIDTH  (1)
)
xpm_recv_fifo
(
    .rst        (~resetn   ),
    .full       (          ),
    .din        (fifo_din  ),  
    .wr_en      (fifo_wren ),  
    .wr_clk     (clk       ),   
    .dout       (fifo_dout ), 
    .empty      (fifo_empty), 
    .rd_en      (fifo_rden ),

    .data_valid     (),
    .sleep          (),
    .injectdbiterr  (),
    .injectsbiterr  (),
    .overflow       (),
    .prog_empty     (),
    .prog_full      (),
    .rd_data_count  (),
    .rd_rst_busy    (),
    .sbiterr        (),
    .underflow      (),
    .wr_ack         (),
    .wr_data_count  (),
    .wr_rst_busy    (),
    .almost_empty   (),
    .almost_full    (),
    .dbiterr        ()
);

endmodule
