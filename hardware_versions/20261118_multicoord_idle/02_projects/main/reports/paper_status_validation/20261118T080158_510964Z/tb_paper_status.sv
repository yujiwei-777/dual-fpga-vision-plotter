`timescale 1ns/1ps
module tb_paper_status;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0;
  reg [11:0] x=0,y=0;
  reg pcb_mode=0,pcb_suspect=0;
  reg [2:0] pcb_status=0;
  reg operator_valid=0;
  reg [152:0] operator_data=0;
  reg [3:0] operator_digit=0;
  wire [5:0] operator_digit_addr;
  wire panel_on,panel_border,text_on;
  wire [23:0] text_color;
  wire [7:0] font_glyph;
  wire [3:0] font_row;
  wire [15:0] font_row_bits;

  osd_compact_panel #(.PAPER_STATUS_ENABLE(1'b0)) dut(
    .clk(clk),.rst_n(rst_n),.x(x),.y(y),.pcb_mode(pcb_mode),.pcb_status(pcb_status),
    .pcb_suspect(pcb_suspect),.algo_mode(5'd18),.he_on(1'b0),.lat_valid(1'b0),
    .lat_overflow(1'b0),.frame_bcd(20'd0),.lat_bcd(16'd0),.target_x_bcd(16'd0),
    .target_y_bcd(16'd0),.area_bcd(24'd0),.remote(1'b1),.ovl_valid(1'b0),
    .target_color(2'd0),.shape3(2'd0),.target_shape(1'b0),.motion_enable(1'b0),
    .motion_bcd(20'd0),.multi_active(1'b0),.multi_slots(4'd0),.multi_classes(16'd0),
    .multi_conf_bcd(48'd0),.operator_valid(operator_valid),.operator_data(operator_data),
    .operator_digit(operator_digit),.operator_digit_addr(operator_digit_addr),
    .panel_on(panel_on),.panel_border(panel_border),.text_on(text_on),
    .text_color(text_color),.font_glyph(font_glyph),.font_row(font_row),
    .font_row_bits(font_row_bits));
  osd_compact_font_rom font(.clk(clk),.glyph(font_glyph),.row(font_row),.row_bits(font_row_bits));


  wire[152:0] sanitized=operator_data & ~(153'd1<<2);
  wire[5:0] default_operator_digit_addr;wire default_panel_on,default_panel_border,default_text_on;wire[23:0]default_text_color;wire[7:0]default_font_glyph;wire[3:0]default_font_row;wire[15:0]default_bits;
  osd_compact_panel default_dut(
    .clk(clk),.rst_n(rst_n),.x(x),.y(y),.pcb_mode(pcb_mode),.pcb_status(pcb_status),
    .pcb_suspect(pcb_suspect),.algo_mode(5'd18),.he_on(1'b0),.lat_valid(1'b0),
    .lat_overflow(1'b0),.frame_bcd(20'd0),.lat_bcd(16'd0),.target_x_bcd(16'd0),
    .target_y_bcd(16'd0),.area_bcd(24'd0),.remote(1'b1),.ovl_valid(1'b0),
    .target_color(2'd0),.shape3(2'd0),.target_shape(1'b0),.motion_enable(1'b0),
    .motion_bcd(20'd0),.multi_active(1'b0),.multi_slots(4'd0),.multi_classes(16'd0),
    .multi_conf_bcd(48'd0),.operator_valid(operator_valid),.operator_data(operator_data),
    .operator_digit(operator_digit),.operator_digit_addr(default_operator_digit_addr),
    .panel_on(default_panel_on),.panel_border(default_panel_border),.text_on(default_text_on),
    .text_color(default_text_color),.font_glyph(default_font_glyph),.font_row(default_font_row),
    .font_row_bits(default_bits));
  osd_compact_font_rom default_font(.clk(clk),.glyph(default_font_glyph),.row(default_font_row),.row_bits(default_bits));
  wire[5:0] old_operator_digit_addr;wire old_panel_on,old_panel_border,old_text_on;wire[23:0]old_text_color;wire[7:0]old_font_glyph;wire[3:0]old_font_row;wire[15:0]old_bits;
  osd_compact_panel_control old_dut(
    .clk(clk),.rst_n(rst_n),.x(x),.y(y),.pcb_mode(pcb_mode),.pcb_status(pcb_status),
    .pcb_suspect(pcb_suspect),.algo_mode(5'd18),.he_on(1'b0),.lat_valid(1'b0),
    .lat_overflow(1'b0),.frame_bcd(20'd0),.lat_bcd(16'd0),.target_x_bcd(16'd0),
    .target_y_bcd(16'd0),.area_bcd(24'd0),.remote(1'b1),.ovl_valid(1'b0),
    .target_color(2'd0),.shape3(2'd0),.target_shape(1'b0),.motion_enable(1'b0),
    .motion_bcd(20'd0),.multi_active(1'b0),.multi_slots(4'd0),.multi_classes(16'd0),
    .multi_conf_bcd(48'd0),.operator_valid(operator_valid),.operator_data(operator_data),
    .operator_digit(operator_digit),.operator_digit_addr(old_operator_digit_addr),
    .panel_on(old_panel_on),.panel_border(old_panel_border),.text_on(old_text_on),
    .text_color(old_text_color),.font_glyph(old_font_glyph),.font_row(old_font_row),
    .font_row_bits(old_bits));
  osd_compact_font_rom old_font(.clk(clk),.glyph(old_font_glyph),.row(old_font_row),.row_bits(old_bits));
  wire[5:0] clean_operator_digit_addr;wire clean_panel_on,clean_panel_border,clean_text_on;wire[23:0]clean_text_color;wire[7:0]clean_font_glyph;wire[3:0]clean_font_row;wire[15:0]clean_bits;
  osd_compact_panel_control clean_dut(
    .clk(clk),.rst_n(rst_n),.x(x),.y(y),.pcb_mode(pcb_mode),.pcb_status(pcb_status),
    .pcb_suspect(pcb_suspect),.algo_mode(5'd18),.he_on(1'b0),.lat_valid(1'b0),
    .lat_overflow(1'b0),.frame_bcd(20'd0),.lat_bcd(16'd0),.target_x_bcd(16'd0),
    .target_y_bcd(16'd0),.area_bcd(24'd0),.remote(1'b1),.ovl_valid(1'b0),
    .target_color(2'd0),.shape3(2'd0),.target_shape(1'b0),.motion_enable(1'b0),
    .motion_bcd(20'd0),.multi_active(1'b0),.multi_slots(4'd0),.multi_classes(16'd0),
    .multi_conf_bcd(48'd0),.operator_valid(operator_valid),.operator_data(sanitized),
    .operator_digit(operator_digit),.operator_digit_addr(clean_operator_digit_addr),
    .panel_on(clean_panel_on),.panel_border(clean_panel_border),.text_on(clean_text_on),
    .text_color(clean_text_color),.font_glyph(clean_font_glyph),.font_row(clean_font_row),
    .font_row_bits(clean_bits));
  osd_compact_font_rom clean_font(.clk(clk),.glyph(clean_font_glyph),.row(clean_font_row),.row_bits(clean_bits));

 integer checks=0,blank_pixels=0,default_checks=0,preserved_checks=0,hidden_full=0,red_checks=0,fx,st,k,ix,iy,v,which;
 reg is_paper_row;
 task sample;
 begin
  repeat(5)@(posedge clk);#1;
  if({default_panel_on,default_panel_border,default_text_on,default_text_color,default_font_glyph,default_font_row,default_operator_digit_addr}!==
     {old_panel_on,old_panel_border,old_text_on,old_text_color,old_font_glyph,old_font_row,old_operator_digit_addr})$fatal(1,"default1 changed x%0d y%0d",x,y);
  default_checks++;
  is_paper_row=(x>=808&&x<1256&&y>=328&&y<344)&&dut.operator_show;
  if(is_paper_row)begin
   if(font_glyph!==8'h20||text_on!==0)$fatal(1,"paper remaining row not blank x%0d y%0d glyph%h",x,y,font_glyph);
   blank_pixels++;
  end else begin
   if({panel_on,panel_border,text_on,text_color,font_glyph,font_row,operator_digit_addr}!==
      {clean_panel_on,clean_panel_border,clean_text_on,clean_text_color,clean_font_glyph,clean_font_row,clean_operator_digit_addr})$fatal(1,"nonpaper output changed x%0d y%0d f%h state%0d",x,y,operator_data[3:0],operator_data[13:11]);
   preserved_checks++;
  end
  if(x>=800&&x<1264&&y>=224&&y<424&&operator_valid&&operator_data[3:0]==4)begin
   if(panel_on!==0||panel_border!==0||text_on!==0)$fatal(1,"full-only panel visible");hidden_full++;
  end
  if(dut.operator_show&&x>=808&&x<1256&&y>=232&&y<248)begin
   if(operator_data[3]||operator_data[13:11]==5)begin
    if(text_color!==24'hff6060)$fatal(1,"real recovery/error color removed %h",text_color);red_checks++;
   end else if(text_color!==24'hffe070)$fatal(1,"full bit turned normal text red %h",text_color);
  end
  checks++;
 end endtask
 initial begin
  repeat(5)@(posedge clk);@(negedge clk);rst_n=1;operator_valid=1;
  // All active flag/kind/state combinations, plus invalid metadata; every row sampled.
  for(v=0;v<2;v++)for(fx=0;fx<16;fx++)for(st=0;st<8;st++)for(k=1;k<=4;k++)begin
   operator_valid=v;operator_data=0;operator_data[3:0]=fx;operator_data[10:8]=k;operator_data[13:11]=st;
   operator_data[7]=1;operator_data[63:60]=(k==3)?5:1;operator_data[152:150]=(st==5)?4:0;operator_data[149:142]=(st==5)?6:0;operator_digit=7;
   for(iy=232;iy<424;iy+=24)for(ix=808;ix<1256;ix+=47)begin x=ix;y=iy;sample();end
  end
  // Entire former paper remaining line: no text pixels at any column/row.
  operator_valid=1;
  for(fx=1;fx<16;fx+=4)begin
   operator_data=0;operator_data[3:0]=fx;operator_data[7]=1;
   for(iy=328;iy<344;iy++)for(ix=808;ix<1256;ix++)begin x=ix;y=iy;sample();end
  end
  // Paper feed/eject and progress/error footer tokens remain equal except paper row.
  for(k=0;k<8;k++)begin
   operator_data=0;operator_data[1]=1;operator_data[7]=1;operator_data[152:150]=k;operator_data[63:60]=k;
   for(iy=352;iy<424;iy+=4)for(ix=808;ix<1256;ix+=4)begin x=ix;y=iy;sample();end
  end
  // Ordinary multi-object CNN summary / motion count / all PCB statuses.
  operator_data=0;operator_valid=1;
  for(st=0;st<8;st++)begin
   pcb_mode=st[0];pcb_status=st;
   for(iy=64;iy<224;iy+=11)for(ix=864;ix<1200;ix+=13)begin x=ix;y=iy;sample();end
   for(iy=584;iy<680;iy+=7)for(ix=24;ix<312;ix+=13)begin x=ix;y=iy;sample();end
  end
  if(blank_pixels==0||hidden_full==0||red_checks==0)$fatal(1,"missing coverage");
  $display("PAPER_STATUS_DISABLED_PASS checks=%0d default=%0d blank_pixels=%0d preserved=%0d full_hidden=%0d real_error_red=%0d",checks,default_checks,blank_pixels,preserved_checks,hidden_full,red_checks);$finish;
 end
 initial begin #1000000000;$fatal(1,"timeout");end
endmodule
