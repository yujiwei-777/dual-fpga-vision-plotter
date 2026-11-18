`timescale 1ns/1ps
module tb_no_suspect_text;
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

  osd_compact_panel dut(
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


  wire [5:0] base_operator_digit_addr;
  wire base_panel_on,base_panel_border,base_text_on;
  wire [23:0] base_text_color;wire [7:0] base_font_glyph;
  wire [3:0] base_font_row;wire [15:0] base_bits;
  osd_compact_font_rom base_font(.clk(clk),.glyph(base_font_glyph),.row(base_font_row),.row_bits(base_bits));
  osd_compact_panel_control reference(
    .clk(clk),.rst_n(rst_n),.x(x),.y(y),.pcb_mode(pcb_mode),.pcb_status(pcb_status),
    .pcb_suspect(1'b0),.algo_mode(5'd18),.he_on(1'b0),.lat_valid(1'b0),
    .lat_overflow(1'b0),.frame_bcd(20'd0),.lat_bcd(16'd0),.target_x_bcd(16'd0),
    .target_y_bcd(16'd0),.area_bcd(24'd0),.remote(1'b1),.ovl_valid(1'b0),
    .target_color(2'd0),.shape3(2'd0),.target_shape(1'b0),.motion_enable(1'b0),
    .motion_bcd(20'd0),.multi_active(1'b0),.multi_slots(4'd0),.multi_classes(16'd0),
    .multi_conf_bcd(48'd0),.operator_valid(operator_valid),.operator_data(operator_data),
    .operator_digit(operator_digit),.operator_digit_addr(base_operator_digit_addr),
    .panel_on(base_panel_on),.panel_border(base_panel_border),.text_on(base_text_on),
    .text_color(base_text_color),.font_glyph(base_font_glyph),.font_row(base_font_row),
    .font_row_bits(base_bits));

  integer checks=0,prefix_checks=0,s,ix,iy,k,c,st,f;
  reg remove_prefix;
  task sample_compare;
    begin
      repeat(5) @(posedge clk);#1;
      remove_prefix=operator_valid&&(operator_data[0]||operator_data[1])&&operator_data[10:8]==2&&
          x>=808&&x<1256&&y>=280&&y<296;
      if({panel_on,panel_border,text_color,font_row}!==
         {base_panel_on,base_panel_border,base_text_color,base_font_row})
        $fatal(1,"layout/color/decimal routing changed x%0d y%0d",x,y);
      if(remove_prefix)begin
        if(font_glyph!==8'h20||text_on!==0)$fatal(1,"PCB suspected-coordinate row still visible");
        prefix_checks++;
      end else if({font_glyph,text_on}!=={base_font_glyph,base_text_on})
        $fatal(1,"unrelated glyph/pixel changed x%0d y%0d got%h expected%h",x,y,font_glyph,base_font_glyph);
      if(!remove_prefix&&operator_digit_addr!==base_operator_digit_addr)$fatal(1,"numeric address changed");
      checks++;
    end
  endtask
  initial begin
    repeat(4)@(posedge clk);@(negedge clk);rst_n=1;
    pcb_mode=1;pcb_suspect=1;operator_valid=0;
    for(s=0;s<8;s++)begin
      pcb_status=s;
      for(iy=584;iy<680;iy++)for(ix=24;ix<312;ix++)begin x=ix;y=iy;sample_compare();end
    end
    operator_valid=1;operator_data=0;operator_data[0]=1;operator_data[4]=1;
    operator_data[7]=1;operator_digit=4'd7;
    for(k=1;k<=4;k++)for(st=0;st<8;st++)begin
      operator_data[10:8]=k;operator_data[13:11]=st;
      for(iy=280;iy<296;iy++)for(ix=808;ix<1256;ix++)begin x=ix;y=iy;sample_compare();end
    end
    // Other operator rows, busy/page-full/recovery, invalid input and idle.
    for(f=0;f<5;f++)begin
      operator_data[3:0]=(f==4)?0:(1<<f);operator_data[10:8]=2;
      for(iy=224;iy<424;iy+=4)for(ix=800;ix<1264;ix+=4)begin x=ix;y=iy;sample_compare();end
    end
    operator_valid=0;
    for(iy=64;iy<224;iy+=4)for(ix=864;ix<1200;ix+=4)begin x=ix;y=iy;pcb_mode=0;sample_compare();end
    if(prefix_checks==0)$fatal(1,"prefix checks missing");
    $display("NO_SUSPECT_TEXT_PASS checks=%0d prefix_checks=%0d",checks,prefix_checks);$finish;
  end
  initial begin #1000000000;$fatal(1,"timeout");end
endmodule
