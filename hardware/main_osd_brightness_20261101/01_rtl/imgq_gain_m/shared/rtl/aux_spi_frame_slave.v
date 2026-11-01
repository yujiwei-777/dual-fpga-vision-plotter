// SPI mode-0 byte receiver for the third-board input path.
// Bytes are delivered in the spi_sclk domain, MSB first. The consumer should
// capture byte_valid/byte_data or synchronize them into its processing clock.
module aux_spi_frame_slave(
    input  wire       rst_n,
    input  wire       spi_sclk,
    input  wire       spi_cs_n,
    input  wire       spi_mosi,
    output reg  [7:0] byte_data,
    output reg        byte_valid,
    output wire       frame_active,
    output reg        frame_start,
    output reg        frame_end
);
    reg cs_d;
    reg [7:0] shift;
    reg [2:0] bit_count;
    assign frame_active = !spi_cs_n;

    always @(posedge spi_sclk or negedge rst_n) begin
        if(!rst_n) begin
            cs_d<=1'b1;shift<=0;bit_count<=0;byte_data<=0;
            byte_valid<=0;frame_start<=0;frame_end<=0;
        end else begin
            byte_valid<=0;frame_start<=0;frame_end<=0;
            if(spi_cs_n) begin
                bit_count<=0;shift<=0;
                if(!cs_d) frame_end<=1'b1;
            end else begin
                if(cs_d) frame_start<=1'b1;
                shift<={shift[6:0],spi_mosi};
                if(bit_count==3'd7) begin
                    byte_data<={shift[6:0],spi_mosi};
                    byte_valid<=1'b1;
                    bit_count<=0;
                end else begin
                    bit_count<=bit_count+1'b1;
                end
            end
            cs_d<=spi_cs_n;
        end
    end
endmodule
