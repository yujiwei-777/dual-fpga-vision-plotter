`timescale 1ns/1ps
module tb_multicoord_independent;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,frame_start=0,recognition_enable=1,multi_active=1;
 reg [11:0] x=0,y=0;
 reg [511:0] boxes=0;
 reg [3:0] slots=4'b1111;
 wire [19:0] frame_bcd;
 wire [15:0] x_bcd,y_bcd;
 wire [23:0] area_bcd;
 wire [6:0] digit_addr;
 wire [3:0] digit;
 wire panel,border,text;
 wire [23:0] color;
 wire [7:0] glyph;
 wire [3:0] row;
 integer checks=0,i;
 integer xc[0:3],yc[0:3];
 osd_operator_decimal_snapshot dec(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),
  .frame_number(16'd12345),.target_x(11'd777),.target_y(10'd555),.target_area(24'd123456),
  .operator_data(153'd0),.multi_boxes(boxes),.frame_bcd(frame_bcd),.target_x_bcd(x_bcd),
  .target_y_bcd(y_bcd),.area_bcd(area_bcd),.operator_digit_addr(digit_addr),.operator_digit(digit));
 osd_compact_panel #(.PAPER_STATUS_ENABLE(0)) ui(.clk(clk),.rst_n(rst_n),.x(x),.y(y),
  .pcb_mode(1'b0),.pcb_status(3'd0),.pcb_suspect(1'b0),.algo_mode(5'd0),.he_on(1'b0),
  .lat_valid(1'b1),.lat_overflow(1'b0),.frame_bcd(frame_bcd),.lat_bcd(16'h0123),
  .target_x_bcd(x_bcd),.target_y_bcd(y_bcd),.area_bcd(area_bcd),.remote(1'b1),
  .ovl_valid(1'b1),.target_color(2'd0),.shape3(2'd1),.target_shape(1'b0),
  .motion_enable(1'b0),.motion_bcd(20'd0),.multi_active(multi_active),
  .recognition_enable(recognition_enable),.multi_slots(slots),.multi_classes(16'h9631),
  .multi_conf_bcd(48'h100087061009),.operator_valid(1'b0),.operator_data(153'd0),
  .operator_digit(digit),.operator_digit_addr(digit_addr),.panel_on(panel),.panel_border(border),
  .text_on(text),.text_color(color),.font_glyph(glyph),.font_row(row),.font_row_bits(16'hffff));
 task putbox(input integer n,input integer x0,input integer y0,input integer x1,input integer y1);
  begin boxes[n*128+:11]=x0;boxes[n*128+16+:10]=y0;boxes[n*128+32+:11]=x1;boxes[n*128+48+:10]=y1;end
 endtask
 task checkcell(input integer colidx,input integer py,input [7:0] c,input integer on);
  begin @(negedge clk);x=872+colidx*16+5;y=py;repeat(5)@(posedge clk);#1;
   checks=checks+1;
   if(text!==on || (on&&glyph!==c))begin
    $display("FAIL check=%0d colidx=%0d y=%0d glyph=%h expected=%h text=%b expected=%b addr=%h digit=%h",checks,colidx,py,glyph,c,text,on,digit_addr,digit);$fatal(1);
   end
  end
 endtask
 task center_row(input integer slot,input integer xv,input integer yv);
  integer p,divisor;
  begin
   checkcell(0,164+slot*40,"X",1);checkcell(1,164+slot*40,":",1);
   divisor=1000;
   for(p=0;p<4;p=p+1)begin checkcell(2+p,164+slot*40,8'h30+(xv/divisor)%10,1);divisor=divisor/10;end
   checkcell(7,164+slot*40,"Y",1);checkcell(8,164+slot*40,":",1);
   divisor=1000;
   for(p=0;p<4;p=p+1)begin checkcell(9+p,164+slot*40,8'h30+(yv/divisor)%10,1);divisor=divisor/10;end
  end
 endtask
 initial begin
  xc[0]=50;yc[0]=50;xc[1]=200;yc[1]=200;xc[2]=900;yc[2]=500;xc[3]=1139;yc[3]=660;
  putbox(0,0,0,100,100);putbox(1,100,100,300,300);putbox(2,600,300,1200,700);putbox(3,1000,600,1279,720);
  repeat(3)@(negedge clk);rst_n=1;@(negedge clk);frame_start=1;@(negedge clk);frame_start=0;
  repeat(330)@(posedge clk);#1;
  checks=checks+1;if(frame_bcd!==20'h12345||x_bcd!==16'h0777||y_bcd!==16'h0555||area_bcd!==24'h123456)$fatal(1,"legacy metadata changed");
  for(i=0;i<4;i=i+1)center_row(i,xc[i],yc[i]);
  checkcell(7,144,"0",1);checkcell(8,144,"0",1);checkcell(9,144,"9",1);checkcell(10,144,"%",1);
  checkcell(7,264,"1",1);checkcell(8,264,"0",1);checkcell(9,264,"0",1);
  slots=4'b0011;checkcell(2,244,"?",0);checkcell(2,284,"?",0);
  recognition_enable=0;
  checkcell(2,124,"?",0);checkcell(2,144,"?",0);checkcell(2,164,"?",0);checkcell(2,204,"?",0);checkcell(2,244,"?",0);checkcell(2,284,"?",0);
  checkcell(2,76,"1",1);
  recognition_enable=1;multi_active=0;
  checkcell(2,124,"0",1);checkcell(3,124,"7",1);checkcell(4,124,"7",1);checkcell(5,124,"7",1);
  recognition_enable=0;checkcell(2,124,"?",0);checkcell(3,148,"?",0);
  $display("PASS independent multicoord review checks=%0d",checks);$finish;
 end
endmodule


