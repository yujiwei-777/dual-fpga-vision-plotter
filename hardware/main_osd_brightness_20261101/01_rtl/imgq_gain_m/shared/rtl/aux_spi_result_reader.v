// SPI mode-0 reader used for the B-to-A result transaction.
// A starts one fixed 88-byte transaction after frame TX completes. MOSI is
// held at zero while MISO bytes are exposed to aux_spi_result_parser.
module aux_spi_result_reader #(
    parameter integer CLK_DIV = 3,
    parameter integer RESPONSE_BYTES = 88
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    output reg        busy,
    output reg        done,
    output reg        frame_error,
    output wire [7:0] byte_data,
    output wire       byte_valid,
    output reg        transaction_end,
    output wire       spi_sclk,
    output wire       spi_cs_n,
    output wire       spi_mosi,
    input  wire       spi_miso
);
    reg master_start;
    reg [7:0] byte_count;
    reg tx_valid,tx_last;
    wire master_busy,master_done,master_tx_ready;
    wire [7:0] master_rx_data;
    wire master_rx_valid;

    assign byte_valid=master_rx_valid;
    assign byte_data=master_rx_data;

    aux_spi_frame_master #(.CLK_DIV(CLK_DIV)) u_master(
        .clk(clk),.rst_n(rst_n),.start(master_start),.busy(master_busy),
        .done(master_done),.tx_data(8'd0),.tx_valid(tx_valid),
        .tx_last(tx_last),.tx_ready(master_tx_ready),.rx_data(master_rx_data),
        .rx_valid(master_rx_valid),.spi_sclk(spi_sclk),.spi_cs_n(spi_cs_n),
        .spi_mosi(spi_mosi),.spi_miso(spi_miso));

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            master_start<=0;byte_count<=0;tx_valid<=0;tx_last<=0;
            busy<=0;done<=0;frame_error<=0;transaction_end<=0;
        end else begin
            master_start<=0;done<=0;transaction_end<=0;
            tx_valid<=busy && master_busy;
            tx_last<=busy && (byte_count==RESPONSE_BYTES-1);
            if(!busy && start) begin
                busy<=1;byte_count<=0;master_start<=1;frame_error<=0;
            end else if(busy && master_tx_ready) begin
                if(byte_count<RESPONSE_BYTES-1) byte_count<=byte_count+1'b1;
            end
            if(busy && master_done) begin
                busy<=0;done<=1;transaction_end<=1;
            end
        end
    end
endmodule
