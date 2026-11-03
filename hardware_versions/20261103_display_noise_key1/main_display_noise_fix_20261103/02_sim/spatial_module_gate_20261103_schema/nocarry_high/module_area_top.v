module module_area_top(
 input wire I_clk,I_rst_n,I_vsync,I_hsync,I_de,I_user,I_last,
 input wire [23:0] I_data,
 output wire O_vsync,O_hsync,O_de,O_user,O_last,
 output wire [23:0] O_data);
 a4_display_spatial_h1 #(.ENABLE(1),.EDGE_TH(16),.IMG_WIDTH(1280),.IMG_HEIGHT(720)) dut(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_vsync(I_vsync),.I_hsync(I_hsync),
 .I_de(I_de),.I_user(I_user),.I_last(I_last),.I_data(I_data),
 .O_vsync(O_vsync),.O_hsync(O_hsync),.O_de(O_de),
 .O_user(O_user),.O_last(O_last),.O_data(O_data));
endmodule
