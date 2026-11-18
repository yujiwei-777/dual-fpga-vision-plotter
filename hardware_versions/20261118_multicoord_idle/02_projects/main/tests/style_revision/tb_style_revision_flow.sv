`timescale 1ns/1ps
module tb_style_revision_flow;
 localparam W=16,H=5,N=32*(W/4)*H;
 reg clk=0,rst=0,iv=0,iu=0,il=0,ready=1;reg[95:0]data=0;reg[4:0]mode=0;
 wire ir,br,ov,bv,ou,bu,ol,bl;wire[95:0]out,base;
 always #5 clk=~clk;
 wire[4:0]bm=(mode==5||mode==15||mode==16||mode>=19)?0:mode;
 style_transfer_96 #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.CART_EDGE_THRESHOLD(20),.CART_QUANT_MASK(8'he0),.CART_FULL_RANGE_PALETTE(1),.CART_PALETTE_BITS(2),.FIXED_STYLE_MODE(0)) dut(.I_clk(clk),.I_rst_n(rst),.I_style_mode(mode),.I_tlast(il),.I_tuser(iu),.I_tdata(data),.I_tvalid(iv),.O_tready(ready),.I_tready(ir),.O_tlast(ol),.O_tuser(ou),.O_tdata(out),.O_tvalid(ov));
 style_transfer_96_control #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.CART_EDGE_THRESHOLD(20),.CART_QUANT_MASK(8'he0),.CART_FULL_RANGE_PALETTE(1),.CART_PALETTE_BITS(2),.FIXED_STYLE_MODE(0)) refdut(.I_clk(clk),.I_rst_n(rst),.I_style_mode(bm),.I_tlast(il),.I_tuser(iu),.I_tdata(data),.I_tvalid(iv),.O_tready(ready),.I_tready(br),.O_tlast(bl),.O_tuser(bu),.O_tdata(base),.O_tvalid(bv));
 integer sent=0,got=0,cycles=0,frame;reg[4:0]em[0:N-1];integer comparisons=0;
 reg accepted=0;
 always@(posedge clk)if(rst)begin
  accepted=iv&&ir;
  if({ir,ov,ou,ol}!=={br,bv,bu,bl})$fatal(1,"stream control changed");
  if(ov&&{ou,ol,out}!=={bu,bl,base})$fatal(1,"retained mode arithmetic changed frame%0d beat%0d got%h exp%h",em[got],got,out,base);
  if(iv&&ir)begin em[sent]=mode;sent=sent+1;end
  if(ov&&ready)begin got=got+1;comparisons=comparisons+1;end
 end
 initial begin
  repeat(5)@(negedge clk);rst=1;
  while(got<N)begin
   @(negedge clk);cycles=cycles+1;ready=($urandom_range(0,4)!=0);
   if(!iv||accepted)begin
    if(sent<N&&$urandom_range(0,3)!=0)begin
     mode=sent/((W/4)*H);data={$urandom,$urandom,$urandom};iv=1;iu=(sent%((W/4)*H)==0);il=(sent%(W/4)==W/4-1);
    end else begin iv=0;iu=0;il=0;end
   end
   if(cycles>10000)$fatal(1,"timeout");
  end
  $display("STYLE_REVISION_FLOW_PASS comparisons=%0d 32 modes normalized per-frame random stalls",comparisons);$finish;
 end
endmodule
