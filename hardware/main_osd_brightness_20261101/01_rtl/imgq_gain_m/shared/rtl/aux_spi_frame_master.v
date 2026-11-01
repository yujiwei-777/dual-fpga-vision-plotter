// Byte-stream SPI master for the auxiliary-board link.
//
// The framing layer (SYNC, job header, payload and CRC) is deliberately kept
// above this block. This module only provides a lossless, MSB-first SPI byte
// stream with back-pressure and a sampled return stream. It is suitable for
// sending a 64x64 RGB888 frame (12,288 payload bytes) without a second frame
// buffer in the SPI block.
module aux_spi_frame_master #(
    parameter integer CLK_DIV = 3
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    output reg        busy,
    output reg        done,
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    input  wire       tx_last,
    output wire       tx_ready,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        spi_sclk,
    output reg        spi_cs_n,
    output reg        spi_mosi,
    input  wire       spi_miso
);
    localparam [1:0] ST_IDLE=2'd0, ST_LOAD=2'd1, ST_SHIFT=2'd2, ST_FINISH=2'd3;
    reg [1:0] state;
    reg [15:0] div_count;
    reg [2:0] bit_count;
    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg last_q;

    assign tx_ready = busy && (state == ST_LOAD);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            busy <= 1'b0;
            done <= 1'b0;
            div_count <= 16'd0;
            bit_count <= 3'd0;
            tx_shift <= 8'd0;
            rx_shift <= 8'd0;
            last_q <= 1'b0;
            rx_data <= 8'd0;
            rx_valid <= 1'b0;
            spi_sclk <= 1'b0;
            spi_cs_n <= 1'b1;
            spi_mosi <= 1'b0;
        end else begin
            done <= 1'b0;
            rx_valid <= 1'b0;
            case (state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    spi_cs_n <= 1'b1;
                    spi_sclk <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        spi_cs_n <= 1'b0;
                        state <= ST_LOAD;
                    end
                end
                ST_LOAD: begin
                    if (tx_valid) begin
                        tx_shift <= tx_data;
                        last_q <= tx_last;
                        spi_mosi <= tx_data[7];
                        bit_count <= 3'd0;
                        rx_shift <= 8'd0;
                        div_count <= 16'd0;
                        state <= ST_SHIFT;
                    end
                end
                ST_SHIFT: begin
                    if (div_count == CLK_DIV-1) begin
                        div_count <= 16'd0;
                        if (!spi_sclk) begin
                            // Rising edge: slave samples MOSI and master
                            // samples the previous MISO bit.
                            spi_sclk <= 1'b1;
                            rx_shift <= {rx_shift[6:0], spi_miso};
                        end else begin
                            spi_sclk <= 1'b0;
                            if (bit_count == 3'd7) begin
                                rx_data <= {rx_shift[6:0], spi_miso};
                                rx_valid <= 1'b1;
                                if (last_q) state <= ST_FINISH;
                                else state <= ST_LOAD;
                            end else begin
                                bit_count <= bit_count + 1'b1;
                                tx_shift <= {tx_shift[6:0],1'b0};
                                spi_mosi <= tx_shift[6];
                            end
                        end
                    end else begin
                        div_count <= div_count + 1'b1;
                    end
                end
                ST_FINISH: begin
                    busy <= 1'b0;
                    spi_cs_n <= 1'b1;
                    spi_sclk <= 1'b0;
                    spi_mosi <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
