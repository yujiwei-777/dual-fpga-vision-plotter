
`timescale 1ns/1ps
module tb;
reg clk=0;always #2 clk=~clk;
reg rst_n=0,frame_start=0,online=0,update=0,valid=0;
reg [11:0] x=0,y=0;reg [2:0] count=0;reg [511:0] boxes=0;
wire ha,hb;wire [23:0] ca,cb;wire [47:0] ba,bb;wire [3:0] sa,sb;
hxa_multibox_overlay_control a(.I_clk(clk),.I_rst_n(rst_n),.I_x(x),.I_y(y),
 .I_frame_start(frame_start),.I_aux_online(online),.I_update(update),.I_valid(valid),
 .I_count(count),.I_boxes(boxes),.O_hit(ha),.O_color(ca),.O_summary_bcd(ba),.O_summary_slots(sa));
hxa_multibox_overlay_candidate b(.I_clk(clk),.I_rst_n(rst_n),.I_x(x),.I_y(y),
 .I_frame_start(frame_start),.I_aux_online(online),.I_update(update),.I_valid(valid),
 .I_count(count),.I_boxes(boxes),.O_hit(hb),.O_color(cb),.O_summary_bcd(bb),.O_summary_slots(sb));
integer checks=0,frames=0,hits=0,i,j,k,r,n,tx,ty;
reg [31:0] seed=32'h20261113;
function [31:0] rnd;begin seed=seed^(seed<<13);seed=seed^(seed>>17);seed=seed^(seed<<5);rnd=seed;end endfunction
task tick;begin
 @(posedge clk);#0.2;checks=checks+1;
 if({ha,ca,ba,sa}!=={hb,cb,bb,sb})begin
  $display("MISMATCH check=%0d xy=%0d,%0d hits=%b,%b colors=%h,%h bcd=%h,%h slots=%h,%h",checks,x,y,ha,hb,ca,cb,ba,bb,sa,sb);$fatal(1);
 end
 if(ha)hits=hits+1;
 @(negedge clk);
end endtask
task boxset(input integer slot,input integer x0,y0,x1,y1,cl,conf);begin
 boxes[slot*128+:128]={32'd0,8'd0,conf[7:0],cl[15:0],y1[15:0],x1[15:0],y0[15:0],x0[15:0]};
end endtask
task publish;begin update=~update;repeat(8)tick();end endtask
task fullframe;begin
 frame_start=1;tick();frame_start=0;
 for(ty=0;ty<720;ty=ty+1)for(tx=0;tx<1280;tx=tx+1)begin x=tx;y=ty;tick();end
 frames=frames+1;
end endtask
initial begin
 repeat(4)tick();rst_n=1;valid=1;count=4;
 boxset(0,0,0,300,200,1,100);boxset(1,160,100,700,600,5,0);
 boxset(2,1000,650,1280,720,9,99);boxset(3,1240,700,1280,720,3,37);
 publish();fullframe();
 // Four fully overlapping target/badge layers exercise slot-zero priority.
 for(i=0;i<4;i=i+1)boxset(i,600,300,800,500,i+1,90+i);
 publish();online=1;frame_start=1;tick();frame_start=0;fullframe();
 // Extreme malformed source words retain default modulo equivalence.
 boxset(0,65535,65535,65535,65535,15,255);
 boxset(1,2047,1023,0,0,0,128);
 boxset(2,1136,16,1280,719,7,9);
 boxset(3,0,0,0,0,2,10);publish();fullframe();
 // Exhaust complete natural coordinate axes around randomized loaded badges.
 for(i=0;i<128;i=i+1)begin
  for(k=0;k<4;k=k+1)boxset(k,rnd(),rnd(),rnd(),rnd(),1+rnd()%9,rnd()%256);
  count=rnd()%8;valid=(i%9)!=0;publish();
  for(k=0;k<4;k=k+1)begin
   for(j=0;j<2048;j=j+1)begin x=j;y=a.badge_y[k]+((j%19)-2);tick();end
   for(j=0;j<1024;j=j+1)begin y=j;x=a.badge_x[k]+((j%147)-2);tick();end
  end
 end
 // Alias high input bits, resets, cancellations, update coalescing, link edges.
 for(i=0;i<100000;i=i+1)begin
  x=rnd();y=rnd();
  if(i%29==0)begin count=rnd()%8;valid=rnd()%2;update=~update;end
  if(i%89==0)for(k=0;k<4;k=k+1)boxset(k,rnd(),rnd(),rnd(),rnd(),rnd(),rnd());
  frame_start=i%701==0;if(i%409==0)online=~online;
  rst_n=i%7919!=0;tick();
 end
 rst_n=1;repeat(4)tick();
 $display("MULTIBOX_BADGE_EQUIVALENCE_PASS checks=%0d full_frames=%0d hit_cycles=%0d seed=20261113",checks,frames,hits);$finish;
end
endmodule
