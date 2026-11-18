`timescale 1ns/1ps
module tb_cnn_panel_hidden;
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

  reg [1:0] S_mode_sel_px=0;
  wire S_mode_cnn_px=(S_mode_sel_px==2'd0);
  wire S_operator_valid_px=operator_valid;
  osd_compact_panel dut(
    .clk(clk),.rst_n(rst_n),.x(x),.y(y),.pcb_mode(pcb_mode),.pcb_status(pcb_status),
    .pcb_suspect(pcb_suspect),.algo_mode(5'd18),.he_on(1'b0),.lat_valid(1'b0),
    .lat_overflow(1'b0),.frame_bcd(20'd0),.lat_bcd(16'd0),.target_x_bcd(16'd0),
    .target_y_bcd(16'd0),.area_bcd(24'd0),.remote(1'b1),.ovl_valid(1'b0),
    .target_color(2'd0),.shape3(2'd0),.target_shape(1'b0),.motion_enable(1'b0),
    .motion_bcd(20'd0),.multi_active(1'b0),.multi_slots(4'd0),.multi_classes(16'd0),
    .multi_conf_bcd(48'd0),.operator_valid(S_operator_valid_px && !S_mode_cnn_px),.operator_data(operator_data),
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
  osd_compact_panel reference(
    .clk(clk),.rst_n(rst_n),.x(x),.y(y),.pcb_mode(pcb_mode),.pcb_status(pcb_status),
    .pcb_suspect(pcb_suspect),.algo_mode(5'd18),.he_on(1'b0),.lat_valid(1'b0),
    .lat_overflow(1'b0),.frame_bcd(20'd0),.lat_bcd(16'd0),.target_x_bcd(16'd0),
    .target_y_bcd(16'd0),.area_bcd(24'd0),.remote(1'b1),.ovl_valid(1'b0),
    .target_color(2'd0),.shape3(2'd0),.target_shape(1'b0),.motion_enable(1'b0),
    .motion_bcd(20'd0),.multi_active(1'b0),.multi_slots(4'd0),.multi_classes(16'd0),
    .multi_conf_bcd(48'd0),.operator_valid(operator_valid),.operator_data(operator_data),
    .operator_digit(operator_digit),.operator_digit_addr(base_operator_digit_addr),
    .panel_on(base_panel_on),.panel_border(base_panel_border),.text_on(base_text_on),
    .text_color(base_text_color),.font_glyph(base_font_glyph),.font_row(base_font_row),
    .font_row_bits(base_bits));

  integer checks=0,hidden=0,preserved=0,m,v,f,ix,iy,k;
  task sample;
   begin
    repeat(5)@(posedge clk);#1;
    if(S_mode_cnn_px&&x>=800&&x<1264&&y>=224&&y<424)begin
      if(panel_on!==0||panel_border!==0||text_on!==0)$fatal(1,"CNN writing panel visible flags=%h x%0d y%0d",operator_data[3:0],x,y);
      if(operator_valid&&operator_data[3:0]!=0&&base_panel_on!==1)$fatal(1,"control panel did not exercise expected visibility");
      hidden++;
    end else begin
      if({panel_on,panel_border,text_on,text_color,font_glyph,font_row,operator_digit_addr}!==
         {base_panel_on,base_panel_border,base_text_on,base_text_color,base_font_glyph,base_font_row,base_operator_digit_addr})
        $fatal(1,"unrelated panel pixel changed mode%0d x%0d y%0d",S_mode_sel_px,x,y);
      preserved++;
    end
    checks++;
   end
  endtask
  initial begin
   repeat(5)@(posedge clk);@(negedge clk);rst_n=1;
   for(m=0;m<4;m++)for(v=0;v<2;v++)for(f=0;f<16;f++)begin
    S_mode_sel_px=m;pcb_mode=(m==1);operator_valid=v;operator_data=0;
    operator_data[3:0]=f;operator_data[10:8]=m+1;operator_data[13:11]=5;
    for(iy=224;iy<424;iy+=17)for(ix=800;ix<1264;ix+=23)begin x=ix;y=iy;sample();end
    // Ordinary CNN summary and the lower-left PCB result remain byte/pixel equal.
    for(iy=64;iy<224;iy+=17)for(ix=864;ix<1200;ix+=23)begin x=ix;y=iy;sample();end
    for(iy=584;iy<680;iy+=13)for(ix=24;ix<312;ix+=23)begin x=ix;y=iy;sample();end
   end
   // Changing view mode must not erase Type21 data or require a new packet.
   operator_valid=1;operator_data[3:0]=8;pcb_mode=0;x=800;y=224;
   S_mode_sel_px=2;sample();S_mode_sel_px=0;sample();S_mode_sel_px=1;pcb_mode=1;sample();
   S_mode_sel_px=0;pcb_mode=0;sample();S_mode_sel_px=2;sample();
   if(hidden==0||preserved==0)$fatal(1,"missing coverage");
   $display("CNN_PANEL_HIDDEN_PASS checks=%0d hidden=%0d preserved=%0d all_flags_all_modes_transition",checks,hidden,preserved);$finish;
  end
  initial begin #100000000;$fatal(1,"timeout");end
endmodule
