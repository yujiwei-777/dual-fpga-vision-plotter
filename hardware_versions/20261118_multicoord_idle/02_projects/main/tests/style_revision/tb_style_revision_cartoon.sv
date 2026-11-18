`timescale 1ns/1ps
module tb_style_revision_cartoon;
 localparam W=16,H=5,N=8*(W/4)*H;
 reg clk=0,rst=0,iv=0,iu=0,il=0,cart=0,ready=1;reg[95:0]idata=0;wire ir,ov,ou,ol;wire[95:0]odata;
 always #5 clk=~clk;
 cartoon_96 #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.EDGE_THRESHOLD(20),.QUANT_MASK(8'he0),.FULL_RANGE_PALETTE(1),.PALETTE_BITS(2)) dut(.I_clk(clk),.I_rst_n(rst),.I_tdata(idata),.I_tvalid(iv),.I_tuser(iu),.I_tlast(il),.I_cart(cart),.I_tready(ir),.O_tready(ready),.O_tdata(odata),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol));
 reg[95:0] exp[0:N-1];reg eu[0:N-1],el[0:N-1];integer gray[0:W*H-1];integer sent=0,got=0,cycles=0;
 reg[95:0]tx;reg[23:0]p,q;integer frame,x,y,cg,lg,pg,hd,vd,r,g,b;reg ec;
 function integer lum(input integer r,g,b);lum=(r>>2)+(g>>1)+(g>>4)+(b>>3);endfunction
 function integer pal(input integer v);pal=(v/64)*85;endfunction
 task make(input integer n);
 begin
  frame=n/((W/4)*H);y=(n%((W/4)*H))/(W/4);x=(n%(W/4))*4;tx=0;
  for(integer lane=0;lane<4;lane=lane+1)begin
   r=(x+lane)*17;g=(y*51+frame*23)%256;b=(frame*31+(x+lane)*5)%256;
   if(frame==0)begin r=255;g=255;b=255;end
   if(frame==1)begin r=(x+lane<8)?40:65;g=r;b=r;end
   p={r[7:0],g[7:0],b[7:0]};tx[95-lane*24-:24]=p;cg=lum(r,g,b);
   lg=(x+lane==0)?cg:gray[y*W+x+lane-1];pg=(y==0)?cg:gray[(y-1)*W+x+lane];
   hd=(cg>lg)?cg-lg:lg-cg;vd=(cg>pg)?cg-pg:pg-cg;
   if(frame%3==2)q=p;
   else if(y!=0&&(x+lane)!=0&&(hd+vd)>=20)q=0;
   else q={8'(pal(r)),8'(pal(g)),8'(pal(b))};
   exp[n][95-lane*24-:24]=q;gray[y*W+x+lane]=cg;
  end
  eu[n]=(x==0&&y==0);el[n]=(x==W-4);
 end endtask
 reg stalled=0;reg[97:0] held;
 reg accepted=0;
 always@(posedge clk)if(rst)begin
  accepted=iv&&ir;
  if(stalled&&{ou,ol,odata}!==held)$fatal(1,"backpressure instability");
  stalled=ov&&!ready;held={ou,ol,odata};
  if(iv&&ir)sent=sent+1;
  if(ov&&ready)begin
   if(got>=sent||odata!==exp[got]||ou!==eu[got]||ol!==el[got])$fatal(1,"cart data/markers %d got%h exp%h",got,odata,exp[got]);
   got=got+1;
  end
 end
 initial begin
  repeat(5)@(negedge clk);rst=1;
  while(got<N)begin
   @(negedge clk);cycles=cycles+1;ready=($urandom_range(0,4)!=0);
   if(!iv||accepted)begin
    if(sent<N&&$urandom_range(0,3)!=0)begin make(sent);idata=tx;iu=eu[sent];il=el[sent];cart=(sent/((W/4)*H))%3!=2;iv=1;end
    else begin iv=0;iu=0;il=0;end
   end
   if(cycles>3000)$fatal(1,"timeout");
  end
  $display("STYLE_REVISION_CARTOON_PASS beats=%d frames=8 palette border edges bypass stalls",got);$finish;
 end
endmodule
