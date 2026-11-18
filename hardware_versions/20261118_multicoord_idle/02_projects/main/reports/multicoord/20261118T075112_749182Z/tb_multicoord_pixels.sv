`timescale 1ns/1ps
module tb_multicoord_pixels;
reg clk=0,rst_n=0,frame_start=0,recognition=1,multi_active=1;
always #5 clk=~clk;
reg [11:0] x=0,y=0;
reg [511:0] boxes=0;
reg [3:0] slots=15;
reg [15:0] classes=16'h9751;
wire [6:0] addr;
wire [3:0] number;
wire [19:0] fb;
wire [15:0] xb,yb;
wire [23:0] ab;
wire panel_on,border,text;
wire [23:0] color;
wire [7:0] glyph;
wire [3:0] row;
wire [15:0] bits;
integer checks=0;
osd_operator_decimal_snapshot dec(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),
 .frame_number(16'd12345),.target_x(11'd640),.target_y(10'd360),.target_area(24'd123456),
 .operator_data(153'd0),.multi_boxes(boxes),.operator_digit_addr(addr),.operator_digit(number),
 .frame_bcd(fb),.target_x_bcd(xb),.target_y_bcd(yb),.area_bcd(ab));
osd_compact_panel #(.PAPER_STATUS_ENABLE(0)) dut(.clk(clk),.rst_n(rst_n),.x(x),.y(y),
 .pcb_mode(1'b0),.pcb_status(3'd0),.pcb_suspect(1'b0),.algo_mode(5'd0),.he_on(1'b0),
 .lat_valid(1'b1),.lat_overflow(1'b0),.frame_bcd(fb),.lat_bcd(16'h0123),
 .target_x_bcd(xb),.target_y_bcd(yb),.area_bcd(ab),.remote(1'b1),.ovl_valid(1'b1),
 .target_color(2'd0),.shape3(2'd1),.target_shape(1'b0),.motion_enable(1'b0),.motion_bcd(20'd0),
 .multi_active(multi_active),.recognition_enable(recognition),.multi_slots(slots),.multi_classes(classes),
 .multi_conf_bcd(48'h100085037009),.operator_valid(1'b0),.operator_data(153'd0),
 .operator_digit(number),.operator_digit_addr(addr),.panel_on(panel_on),.panel_border(border),
 .text_on(text),.text_color(color),.font_glyph(glyph),.font_row(row),.font_row_bits(bits));
osd_compact_font_rom font(.clk(clk),.glyph(glyph),.row(row),.row_bits(bits));
function [15:0] bcd(input integer n);
begin bcd=((n/1000)%10)*4096+((n/100)%10)*256+((n/10)%10)*16+(n%10);end
endfunction
task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
task snap;
begin
 frame_start=1;tick(1);frame_start=0;tick(321);
 if(dec.busy!==0||dec.decimal_valid!==14'h3fff)$fatal(1,"converter not finished coherently");
 if(fb!==20'h12345||xb!==16'h0640||yb!==16'h0360||ab!==24'h123456)$fatal(1,"legacy fields changed");
end endtask
task cell_check(input integer col,input integer py,input reg[7:0] expect_glyph,input bit valid);
begin
 x=872+col*16;y=py;tick(6);
 if(valid && expect_glyph!=0 && glyph!==expect_glyph)$fatal(1,"glyph mismatch col%0d y%0d got%h expected%h addr%0d",col,py,glyph,expect_glyph,addr);
 if(dut.valid_s2!==valid)$fatal(1,"valid mismatch y%0d slot%0d",py,dut.multi_slot);
 checks++;
end endtask
task check_slot(input integer slot,input integer cx,input integer cy);
integer py,c,n;
reg [15:0] xx,yy;
begin
 xx=bcd(cx);yy=bcd(cy);py=164+slot*40;
 if(dec.decimal_words[6+slot*2]!=={4'd0,xx} || dec.decimal_words[7+slot*2]!=={4'd0,yy})
  $fatal(1,"centre BCD mismatch slot%0d got%h/%h expected%h/%h",slot,dec.decimal_words[6+slot*2],dec.decimal_words[7+slot*2],xx,yy);
 cell_check(0,py,"X",1);cell_check(1,py,":",1);cell_check(7,py,"Y",1);cell_check(8,py,":",1);
 for(c=0;c<4;c++)begin
  n=(xx>>((3-c)*4))&15;cell_check(2+c,py,8'h30+n,1);
  n=(yy>>((3-c)*4))&15;cell_check(9+c,py,8'h30+n,1);
 end
end endtask

reg [15:0] expect_bits[0:4095];reg[7:0] want_char;
reg[3:0] want_row,want_col;reg[15:0] expected_pixels[0:2];
integer s,c,r,j,cyc=0,a,b,k;
reg [15:0] xx,yy;
initial begin
 for(k=0;k<4096;k++)expect_bits[k]=font.glyph_rom[k];
 tick(4);rst_n=1;
 for(s=0;s<4;s++)begin
  boxes[s*128+:16]=s*200;boxes[s*128+32+:16]=s*200+140;
  boxes[s*128+16+:16]=s*100;boxes[s*128+48+:16]=s*100+80;
 end
 snap;
 for(s=0;s<4;s++)for(r=0;r<16;r++)for(c=0;c<13;c++)for(j=0;j<16;j++)begin
  xx=bcd(s*200+70);yy=bcd(s*100+40);
  want_char=" ";
  case(c)
   0:want_char="X";1,8:want_char=":";7:want_char="Y";
   2,3,4,5:want_char=8'h30+((xx>>((5-c)*4))&15);
   9,10,11,12:want_char=8'h30+((yy>>((12-c)*4))&15);
  endcase
  @(negedge clk);x=872+c*16+j;y=164+s*40+r;
  expected_pixels[cyc%3]=(expect_bits[{want_char,4'(r)}]>>(15-j))&1;
  @(posedge clk);#1;
  if(cyc>=1&&text!==expected_pixels[(cyc-1)%3][0])
   $fatal(1,"pixel pipeline mismatch cycle%0d slot%0d col%0d row%0d got%b expected%b",cyc,s,c,r,text,expected_pixels[(cyc-1)%3][0]);
  cyc++;
 end
 $display("MULTICOORD_PIXEL_PIPELINE_PASS pixels=%0d",cyc);$finish;
end
endmodule
