// Physical-only bring-up top for the standalone secondary-A SPI bit.
// The production Ethernet/DDR top instantiates secondary_a_top and supplies
// its ROI stream.  This wrapper keeps those integration ports internal so TD
// can generate a safe SPI electrical smoke-test bit with only J1 pins exposed.
module secondary_a_bit_top(
    input wire I_sys_clk,
    input wire I_spi_miso,
    input wire I_spi_ready,
    output wire O_spi_sclk,
    output wire O_spi_mosi,
    output wire O_spi_cs_n,
    output wire O_spi_frame
);
    wire pixel_ready;
    secondary_a_top u_bridge(
        .I_sys_clk(I_sys_clk),.I_rst_n(1'b1),.I_start(1'b0),.I_job_id(32'd0),.I_purpose(8'd0),
        .I_accel_ready(1'b0),.I_pixel_valid(1'b0),.O_pixel_ready(pixel_ready),.I_pixel_rgb(24'd0),.I_pixel_last(1'b0),
        .O_spi_sclk(O_spi_sclk),.O_spi_mosi(O_spi_mosi),.I_spi_miso(I_spi_miso),.O_spi_cs_n(O_spi_cs_n),
        .O_spi_frame(O_spi_frame),.I_spi_ready(I_spi_ready),.O_busy(),.O_frame_done(),
        .O_frame_error(),.O_ready());
endmodule
