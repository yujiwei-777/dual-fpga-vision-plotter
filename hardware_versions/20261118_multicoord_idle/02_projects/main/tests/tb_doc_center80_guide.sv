`timescale 1ns/1ps
module tb_doc_center80_guide;
reg clk=0,rst_n=0,enable=0;reg[2:0]state=0;reg[11:0]x=0,y=0;
always #5 clk=~clk;
wire hit,old_hit;wire[23:0]color,old_color;
doc_copy_overlay dut(.*);
doc_copy_overlay_control control(.clk(clk),.rst_n(rst_n),.enable(enable),.state(state),.x(x),.y(y),.hit(old_hit),.color(old_color));
integer checks=0,borders=0,preserved=0,hidden=0,st,e,ix,iy;
reg prior_guide=0,prior_label=0,prior_oldguide=0;
task sample;
begin
 @(posedge clk);#1;
 if(hit!==(prior_guide||prior_label))$fatal(1,"guide hit mismatch x%0d y%0d expected%0d hit%0d",x,y,(prior_guide||prior_label),hit);
 if(prior_guide)begin
  if(color!==24'h60ffff)$fatal(1,"guide color mismatch");borders++;
 end else if(!prior_oldguide)begin
  if(hit!==old_hit||color!==old_color)$fatal(1,"unrelated label/status/color changed");preserved++;
 end
 if(!enable&&!prior_guide&&!prior_label)begin if(hit)$fatal(1,"disabled guide visible");hidden++;end
 checks++;
 prior_guide=enable && x>=128 && x<=1151 && y>=72 && y<=647 &&
       (x==128||x==129||x==1150||x==1151||y==72||y==73||y==646||y==647);
 prior_label=enable && x>=32&&x<=111&&y>=96&&y<=111;
 prior_oldguide=enable&&x>=430&&x<850&&y>=64&&y<658&&(x<432||x>=848||y<66||y>=656);
end endtask
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 for(st=0;st<8;st++)for(e=0;e<2;e++)begin
  for(iy=0;iy<720;iy++)for(ix=0;ix<1280;ix++)begin
   @(negedge clk);state=st;enable=e;x=ix;y=iy;sample();
  end
 end
 @(negedge clk);enable=0;x=4095;y=4095;sample();
 @(negedge clk);sample();
 if(!borders||!preserved||!hidden)$fatal(1,"missing coverage");
 $display("DOC_CENTER80_GUIDE_PASS checks=%0d borders=%0d preserved=%0d hidden=%0d all_pixels_all_states",checks,borders,preserved,hidden);$finish;
end
initial begin #200000000;$fatal(1,"watchdog");end
endmodule
