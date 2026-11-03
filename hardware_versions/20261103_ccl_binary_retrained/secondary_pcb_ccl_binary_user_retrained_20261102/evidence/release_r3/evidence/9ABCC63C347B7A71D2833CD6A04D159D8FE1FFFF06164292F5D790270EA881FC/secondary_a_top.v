// Bridge-only implementation target for secondary board A.
//
// The production A top can instantiate this block beside its Ethernet/DDR/
// HXA1 logic. I_pixel_* is the 64x64 RGB888 ROI stream produced by the DDR
// reader. The second SPI transaction is generated automatically after the
// image frame: A clocks 88 bytes from B, and aux_spi_result_parser validates
// and exposes the type18 result.
module secondary_a_top(
    input  wire        I_sys_clk,
    input  wire        I_rst_n,
    input  wire        I_start,
    input  wire [31:0] I_job_id,
    input  wire [7:0]  I_purpose,
    input  wire        I_accel_ready,
    input  wire        I_pixel_valid,
    output wire        O_pixel_ready,
    input  wire [23:0] I_pixel_rgb,
    input  wire        I_pixel_last,
    // J1 pins 4..9: SCLK, MOSI, MISO, CS_N, FRAME/VALID, READY/BUSY.
    output wire        O_spi_sclk,
    output wire        O_spi_mosi,
    input  wire        I_spi_miso,
    output wire        O_spi_cs_n,
    output wire        O_spi_frame,
    input  wire        I_spi_ready,
    output wire        O_busy,
    output wire        O_frame_done,
    output wire        O_frame_error,
    output wire        O_ready,
    // Parsed B result, atomically valid for one clock after a good response.
    output wire        O_result_valid,
    output wire [31:0] O_result_job_id,
    output wire [31:0] O_result_inference_us,
    output wire [31:0] O_result_config_version,
    output wire [7:0]  O_result_flags,
    output wire [7:0]  O_result_box_count,
    output wire [511:0] O_result_boxes,
    // Little-endian HXA1 type18 payload: byte 0 is job_id[7:0]. This is the
    // explicit integration stub for the production A HXA1 result sender.
    output wire [639:0] O_type18_payload
);
    wire frame_busy,frame_tx_done,frame_done,frame_error;
    wire [31:0] done_job_id;
    wire result_pulse;
    wire [31:0] result_job_latched;
    wire accelerator_ready = I_accel_ready && I_spi_ready;

    wire parser_valid,parser_error;
    wire [31:0] parser_job,parser_inference,parser_config;
    wire [7:0] parser_flags,parser_count;
    wire [511:0] parser_boxes;
    wire response_byte_valid,response_transaction_end,response_busy;
    wire [7:0] response_byte_data;

    // The bridge owns both image and response-read transactions and muxes
    // their SPI pins at a transaction boundary.
    assign O_spi_frame = !O_spi_cs_n;
    assign O_busy = frame_busy || response_busy;
    assign O_frame_done = frame_done;
    assign O_frame_error = frame_error || parser_error;
    assign O_ready = accelerator_ready && !frame_busy && !response_busy;
    assign O_result_valid = parser_valid;
    assign O_result_job_id = parser_job;
    assign O_result_inference_us = parser_inference;
    assign O_result_config_version = parser_config;
    assign O_result_flags = parser_flags;
    assign O_result_box_count = parser_count;
    assign O_result_boxes = parser_boxes;
    assign O_type18_payload = {parser_boxes,16'd0,parser_count,parser_flags,
                               parser_config,parser_inference,parser_job};

    secondary_a_yolo_bridge #(.SPI_CLK_DIV(3)) u_bridge(
        .clk(I_sys_clk),.rst_n(I_rst_n),.start(I_start),
        .job_id(I_job_id),.purpose(I_purpose),.accel_ready(accelerator_ready),
        .pixel_valid(I_pixel_valid),.pixel_ready(O_pixel_ready),
        .pixel_rgb(I_pixel_rgb),.pixel_last(I_pixel_last),
        .spi_sclk(O_spi_sclk),.spi_cs_n(O_spi_cs_n),.spi_mosi(O_spi_mosi),
        .spi_miso(I_spi_miso),.busy(frame_busy),.frame_tx_done(frame_tx_done),
        .frame_done(frame_done),.frame_error(frame_error),.done_job_id(done_job_id),
        .result_valid(parser_valid),.result_job_id(parser_job),
        .result_pulse(result_pulse),.result_job_latched(result_job_latched),
        .response_byte_valid(response_byte_valid),.response_byte_data(response_byte_data),
        .response_transaction_end(response_transaction_end),.response_busy(response_busy));

    aux_spi_result_parser u_result_parser(
        .clk(I_sys_clk),.rst_n(I_rst_n),.byte_valid(response_byte_valid),
        .byte_data(response_byte_data),.transaction_end(response_transaction_end),
        .result_valid(parser_valid),.frame_error(parser_error),.job_id(parser_job),
        .inference_us(parser_inference),.config_version(parser_config),
        .flags(parser_flags),.box_count(parser_count),.boxes(parser_boxes));
endmodule
