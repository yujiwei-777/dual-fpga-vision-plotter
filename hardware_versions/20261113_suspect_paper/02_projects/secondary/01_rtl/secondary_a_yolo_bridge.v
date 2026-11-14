// Secondary-A 64x64 frame bridge.
// A ROI reader can produce pixels much faster than a 20 MHz SPI link can
// consume three bytes per pixel. The bridge therefore captures the complete
// 4096-pixel ROI in inferred RAM before starting the SPI frame.
module secondary_a_yolo_bridge #(
    parameter integer SPI_CLK_DIV = 3
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [31:0] job_id,
    input  wire [7:0]  purpose,
    input  wire        accel_ready,
    input  wire        pixel_valid,
    output wire        pixel_ready,
    input  wire [23:0] pixel_rgb,
    input  wire        pixel_last,
    output wire        spi_sclk,
    output wire        spi_cs_n,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output reg         busy,
    output reg         frame_tx_done,
    output reg         frame_done,
    output reg         frame_error,
    output reg [31:0]  done_job_id,
    input  wire        result_valid,
    input  wire [31:0] result_job_id,
    output reg         result_pulse,
    output reg [31:0]  result_job_latched,
    output wire        response_byte_valid,
    output wire [7:0]  response_byte_data,
    output wire        response_transaction_end,
    output wire        response_busy
);
    localparam [2:0] ST_IDLE=3'd0, ST_WAIT_READY=3'd1,
                     ST_CAPTURE=3'd2, ST_SEND=3'd3,
                     ST_WAIT_RESULT_READY=3'd4, ST_READ_RESULT=3'd5,
                     ST_WAIT_RESULT_PARSE=3'd6, ST_HOLD_RESULT=3'd7;
    reg [2:0] state;
    reg [31:0] job_q;
    reg [7:0] purpose_q;
    reg [11:0] capture_count;
    reg [11:0] tx_pixel_count;
    reg [1:0]  tx_byte_at;
    reg [23:0] pixel_mem [0:4095];
    reg tx_start;
    wire tx_busy,tx_done,tx_error,tx_payload_ready;
    wire tx_spi_sclk,tx_spi_cs_n,tx_spi_mosi;
    reg result_read_start;
    wire result_read_busy,result_read_done,result_read_error;
    wire result_spi_sclk,result_spi_cs_n,result_spi_mosi;
    wire [7:0] result_byte_data;
    wire result_byte_valid,result_transaction_end;
    reg [7:0] tx_payload_data;
    reg tx_payload_valid,tx_payload_last;

    // The capture RAM is ready from the first cycle after start until all
    // 4096 pixels have been stored. A source may stream continuously.
    assign pixel_ready = (state==ST_CAPTURE) && (capture_count < 12'd4096);

    always @* begin
        tx_payload_valid = 1'b0;
        tx_payload_last = 1'b0;
        tx_payload_data = 8'd0;
        if(state==ST_SEND && tx_busy) begin
            tx_payload_valid = 1'b1;
            tx_payload_last = (tx_pixel_count==12'd4095) && (tx_byte_at==2);
            case(tx_byte_at)
                0: tx_payload_data = pixel_mem[tx_pixel_count][23:16];
                1: tx_payload_data = pixel_mem[tx_pixel_count][15:8];
                default: tx_payload_data = pixel_mem[tx_pixel_count][7:0];
            endcase
        end
    end

    aux_spi_frame_tx #(.SPI_CLK_DIV(SPI_CLK_DIV),.PAYLOAD_LENGTH(16'd12288))
    u_frame_tx(
        .clk(clk),.rst_n(rst_n),.start(tx_start),.job_id(job_q),
        .purpose(purpose_q),.payload_data(tx_payload_data),
        .payload_valid(tx_payload_valid),.payload_last(tx_payload_last),
        .payload_ready(tx_payload_ready),.busy(tx_busy),.done(tx_done),
        .frame_error(tx_error),.spi_sclk(tx_spi_sclk),.spi_cs_n(tx_spi_cs_n),
        .spi_mosi(tx_spi_mosi),.spi_miso(spi_miso));

    aux_spi_result_reader #(.CLK_DIV(SPI_CLK_DIV)) u_result_reader(
        .clk(clk),.rst_n(rst_n),.start(result_read_start),
        .busy(result_read_busy),.done(result_read_done),.frame_error(result_read_error),
        .byte_data(result_byte_data),.byte_valid(result_byte_valid),
        .transaction_end(result_transaction_end),
        .spi_sclk(result_spi_sclk),.spi_cs_n(result_spi_cs_n),.spi_mosi(result_spi_mosi),
        .spi_miso(spi_miso));

    assign spi_sclk = (state==ST_READ_RESULT) ? result_spi_sclk : tx_spi_sclk;
    assign spi_cs_n = (state==ST_READ_RESULT) ? result_spi_cs_n : tx_spi_cs_n;
    assign spi_mosi = (state==ST_READ_RESULT) ? result_spi_mosi : tx_spi_mosi;
    assign response_byte_valid = result_byte_valid;
    assign response_byte_data = result_byte_data;
    assign response_transaction_end = result_transaction_end;
    assign response_busy = result_read_busy;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=ST_IDLE;job_q<=0;purpose_q<=0;capture_count<=0;
            tx_pixel_count<=0;tx_byte_at<=0;tx_start<=0;result_read_start<=0;
            busy<=0;frame_tx_done<=0;frame_done<=0;frame_error<=0;done_job_id<=0;
            result_pulse<=0;result_job_latched<=0;
        end else begin
            tx_start<=0;result_read_start<=0;frame_tx_done<=0;frame_done<=0;result_pulse<=0;
            if(result_valid && (state==ST_READ_RESULT || state==ST_HOLD_RESULT) &&
               result_job_id==job_q) begin
                result_job_latched<=result_job_id;result_pulse<=1;
                state<=ST_HOLD_RESULT;
            end
            case(state)
                ST_IDLE: begin
                    busy<=0;capture_count<=0;tx_pixel_count<=0;tx_byte_at<=0;
                    // PCB/template tasks (purpose 1/2) stay in the existing
                    // A-side pipeline and never consume the YOLO SPI link.
                    if(start && purpose==8'd0) begin
                        job_q<=job_id;purpose_q<=purpose;busy<=1;frame_error<=0;
                        // Capture the ROI immediately. B may still be
                        // finishing the previous inference; pixel_ready must
                        // remain asserted so the upstream DDR reader does not
                        // lose this frame while READY is low.
                        state<=ST_CAPTURE;
                    end
                end
                ST_WAIT_READY: if(accel_ready) begin
                    tx_pixel_count<=0;tx_byte_at<=0;tx_start<=1'b1;
                    state<=ST_SEND;
                end
                ST_CAPTURE: begin
                    if(pixel_valid && pixel_ready) begin
                        pixel_mem[capture_count]<=pixel_rgb;
                        if(pixel_last && capture_count!=12'd4095) frame_error<=1;
                        if(capture_count==12'd4095) begin
                            tx_pixel_count<=0;tx_byte_at<=0;
                            if(accel_ready) begin tx_start<=1'b1;state<=ST_SEND;end
                            else state<=ST_WAIT_READY;
                        end else capture_count<=capture_count+1'b1;
                    end
                end
                ST_SEND: begin
                    if(tx_payload_valid && tx_payload_ready) begin
                        if(tx_byte_at==2) begin
                            tx_byte_at<=0;tx_pixel_count<=tx_pixel_count+1'b1;
                        end else tx_byte_at<=tx_byte_at+1'b1;
                    end
                    if(tx_error) frame_error<=1;
                    if(tx_done) begin
                        frame_tx_done<=1;
                        // B keeps READY low during inference. Wait for its
                        // response-ready indication before clocking MISO.
                        state<=ST_WAIT_RESULT_READY;
                    end
                end
                ST_WAIT_RESULT_READY: begin
                    if(accel_ready) begin
                        result_read_start<=1'b1;
                        state<=ST_READ_RESULT;
                    end
                end
                ST_READ_RESULT: begin
                    if(tx_error || result_read_error) frame_error<=1;
                    // The parser commits result_valid on the same clock that
                    // the SPI reader reports done. Wait one system clock so
                    // the nonblocking parser update is observable.
                    if(result_read_done) state<=ST_WAIT_RESULT_PARSE;
                end
                ST_WAIT_RESULT_PARSE: begin
                    if(result_valid && result_job_id==job_q) begin
                        result_job_latched<=result_job_id;result_pulse<=1;
                        busy<=0;done_job_id<=job_q;frame_done<=1;state<=ST_HOLD_RESULT;
                    end else begin
                        frame_error<=1;
                        busy<=0;done_job_id<=job_q;frame_done<=1;state<=ST_IDLE;
                    end
                end
                ST_HOLD_RESULT: begin
                    if(!start) begin
                        busy<=0;done_job_id<=job_q;frame_done<=1;state<=ST_IDLE;
                    end
                end
                default: state<=ST_IDLE;
            endcase
        end
    end
endmodule
