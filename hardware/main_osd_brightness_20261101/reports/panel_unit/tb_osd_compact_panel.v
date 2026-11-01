`timescale 1ns/1ps
`include "osd_compact_glyphs.vh"
module tb_osd_compact_panel;
reg clk=0;always #5 clk=~clk;
reg rst_n=0;
reg [11:0] x=0,y=0;
reg pcb_mode=0;reg [2:0] pcb_status=0;reg [4:0] algo_mode=0;
reg he_on=1,lat_valid=1,lat_overflow=0,remote=1,ovl_valid=1;
reg [1:0] target_color=0,shape3=1;reg target_shape=0,motion_enable=1;
wire panel_on,panel_border,text_on;wire [23:0] text_color;
wire [7:0] font_glyph;wire [3:0] font_row;wire [15:0] font_row_bits;
osd_compact_panel dut(.clk(clk),.rst_n(rst_n),.x(x),.y(y),.pcb_mode(pcb_mode),.pcb_status(pcb_status),.algo_mode(algo_mode),
 .he_on(he_on),.lat_valid(lat_valid),.lat_overflow(lat_overflow),.frame_bcd(20'h65535),.lat_bcd(16'h9999),
 .target_x_bcd(16'h1280),.target_y_bcd(16'h0720),.area_bcd(24'h921600),.remote(remote),.ovl_valid(ovl_valid),
 .target_color(target_color),.shape3(shape3),.target_shape(target_shape),.motion_enable(motion_enable),.motion_bcd(20'h54321),
 .panel_on(panel_on),.panel_border(panel_border),.text_on(text_on),.text_color(text_color),.font_glyph(font_glyph),.font_row(font_row),.font_row_bits(font_row_bits));
osd_compact_font_rom rom(.clk(clk),.glyph(font_glyph),.row(font_row),.row_bits(font_row_bits));
reg ep,eb,ev;reg [3:0] ec;reg [23:0] ecolor;reg [15:0] ebits;integer checks=0;
always @(posedge clk) if(rst_n) begin
 ep=dut.panel_s1;eb=dut.border_s1;ev=dut.valid_s1;ec=dut.col_s1;ecolor=dut.color_s1;
 ebits=rom.glyph_rom[{font_glyph,font_row}];
 #1;
 if(panel_on!==ep||panel_border!==eb||text_color!==ecolor||text_on!==(ev&&ebits[15-ec])) begin
  $display("FAIL pipeline x=%0d y=%0d",x,y);$fatal(1);
 end
 checks=checks+1;
end
task expect_glyph;input integer xx,yy;input [7:0] glyph;begin
 @(negedge clk);x=xx;y=yy;#1;
 if(dut.glyph_c!==glyph)begin $display("FAIL glyph %h expected %h at %0d,%0d",dut.glyph_c,glyph,xx,yy);$fatal(1);end
end endtask
integer xx,yy,s,m;
initial begin
 repeat(3)@(negedge clk);rst_n=1;
 for(xx=864;xx<872;xx=xx+1)begin
  @(negedge clk);x=xx;y=72;#1;if(!dut.panel_c||dut.valid_c)$fatal(1,"upper left padding");
 end
 expect_glyph(872,72,`OSD_CN_U5E27);
 expect_glyph(872+2*16,72,"6");expect_glyph(872+6*16,72,"5");
 expect_glyph(872+3*16,120,"2");expect_glyph(872+8*16,120,"0");
 expect_glyph(872+9*16,120,"7");expect_glyph(872+19*16,120,"0");
 expect_glyph(1191,120,"0");
 if(!dut.valid_c||dut.col_c!==4'd15||dut.border_c)$fatal(1,"longest row clipped");
 @(negedge clk);x=1199;y=120;#1;if(!dut.panel_c||!dut.border_c)$fatal(1,"upper geometry changed");
 expect_glyph(872+10*16,144,`OSD_CN_U9501);
 expect_glyph(872,168,`OSD_CN_U8FD0);
 @(negedge clk);motion_enable=0;x=865;y=170;#1;if(dut.panel_c||dut.valid_c)$fatal(1,"motion row not hidden");
 @(negedge clk);motion_enable=1;
 for(m=0;m<19;m=m+1)begin
  @(negedge clk);algo_mode=m;
  expect_glyph(872+3*16,96,dut.mode_char(m,0));
 end
 @(negedge clk);pcb_mode=1;x=865;y=72;#1;if(dut.panel_c||dut.valid_c)$fatal(1,"PCB upper panel must remain hidden");
 for(xx=24;xx<32;xx=xx+1)begin
  @(negedge clk);x=xx;y=592;#1;if(!dut.panel_c||dut.valid_c)$fatal(1,"PCB left padding");
 end
 expect_glyph(32,592,`OSD_CN_U7535);
 for(s=0;s<8;s=s+1)begin
  @(negedge clk);pcb_status=s;
  expect_glyph(32,656,dut.status_char(s,0));
 end
 @(negedge clk);pcb_mode=0;
 for(yy=62;yy<194;yy=yy+1)for(xx=862;xx<1202;xx=xx+1)begin @(negedge clk);x=xx;y=yy;end
 @(negedge clk);pcb_mode=1;
 for(yy=582;yy<682;yy=yy+1)for(xx=22;xx<314;xx=xx+1)begin @(negedge clk);x=xx;y=yy;end
 repeat(3)@(negedge clk);
 $display("PASS compact panel v2 8px-padding/full20cell-row/borders/glyphs/decimal/motion/19modes/8PCB/two-cycle checks=%0d",checks);$finish;
end
endmodule
