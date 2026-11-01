
`timescale 1ns/1ps
module tb_factored_cones;
reg clk=0,rst_n=0,seed=0,enable=0;
always #5 clk=~clk;
reg reject=0,low=0,cb=0,sb=0;
reg [7:0] margin=0,flags=0;
reg [19:0] samples=0;
reg [1:0] shape=0;
reg [7:0] cm=0,sm=0;
wire [7:0] am0,af0,bm0,bf0,am1,af1,bm1,bf1;
wire [7:0] nm0,nf0,om0,of0,nm1,nf1,om1,of1;
abstract_parent #(.CNN_LOWCONF_OUTPUT(0)) ap0(clk,rst_n,seed,enable,reject,low,cb,sb,margin,flags,am0,af0);
abstract_factored #(.CNN_LOWCONF_OUTPUT(0)) bp0(clk,rst_n,seed,enable,reject,low,cb,sb,margin,flags,bm0,bf0);
abstract_parent #(.CNN_LOWCONF_OUTPUT(1)) ap1(clk,rst_n,seed,enable,reject,low,cb,sb,margin,flags,am1,af1);
abstract_factored #(.CNN_LOWCONF_OUTPUT(1)) bp1(clk,rst_n,seed,enable,reject,low,cb,sb,margin,flags,bm1,bf1);
numeric_parent #(.CNN_LOWCONF_OUTPUT(0)) np0(clk,rst_n,seed,enable,reject,samples,shape,cm,sm,flags,nm0,nf0);
numeric_factored #(.CNN_LOWCONF_OUTPUT(0)) op0(clk,rst_n,seed,enable,reject,samples,shape,cm,sm,flags,om0,of0);
numeric_parent #(.CNN_LOWCONF_OUTPUT(1)) np1(clk,rst_n,seed,enable,reject,samples,shape,cm,sm,flags,nm1,nf1);
numeric_factored #(.CNN_LOWCONF_OUTPUT(1)) op1(clk,rst_n,seed,enable,reject,samples,shape,cm,sm,flags,om1,of1);
integer c,m,s,r,i,j,k;
integer abstract_checks=0,numeric_checks=0,hold_checks=0;
task check_equal;
begin
 if({am0,af0,am1,af1}!={bm0,bf0,bm1,bf1} ||
    {nm0,nf0,nm1,nf1}!={om0,of0,om1,of1})
  $fatal(1,"FAIL FACTORED_CONE_MITER c=%0d margin=%0d shape=%0d reject=%0d cm=%0d sm=%0d samples=%0d",c,m,s,r,i,j,samples);
end
endtask
initial begin
 #2; rst_n=0; @(negedge clk);rst_n=1;
 // Independent Boolean predicates prove a superset of every binary numeric input.
 for(c=0;c<32;c=c+1) begin
  for(m=0;m<256;m=m+1) begin
   @(negedge clk);seed=1;enable=0;flags=(c[4] ? 8'hD5:8'h95);
   @(negedge clk);seed=0;enable=1;
   reject=c[0];low=c[1];cb=c[2];sb=c[3];margin=m;
   @(posedge clk);#1;check_equal;abstract_checks=abstract_checks+2;
   @(negedge clk);enable=0;reject=~reject;margin=~margin;
   @(posedge clk);#1;check_equal;hold_checks=hold_checks+2;
  end
 end
 // Exhaust all actual color/shape margin pairs, each shape lookup, both sides
 // of sample-count eligibility, and both hard-background states.
 for(s=0;s<4;s=s+1) begin
  for(k=0;k<2;k=k+1)begin
   for(r=0;r<2;r=r+1)begin
    for(i=0;i<256;i=i+1)begin
     for(j=0;j<256;j=j+1)begin
      @(negedge clk);seed=0;enable=1;shape=s;samples=(k ? 20'd8:20'd7);reject=r;cm=i;sm=j;
      @(posedge clk);#1;check_equal;numeric_checks=numeric_checks+2;
     end
    end
   end
  end
 end
 // The full 20-bit sample domain only enters through <8 / >=8. These raw
 // endpoints cover zero, largest eligible count, and under/over the boundary.
 for(k=0;k<4;k=k+1)begin
  @(negedge clk);samples=(k==0 ? 20'd0 : k==1 ? 20'd1 : k==2 ? 20'd9 : 20'hFFFFF);
  @(posedge clk);#1;check_equal;numeric_checks=numeric_checks+2;
 end
 $display("PASS FACTORED_EXACT_SOURCE_CONE abstract=%0d numeric=%0d hold=%0d params=0,1",abstract_checks,numeric_checks,hold_checks);
 $finish;
end
endmodule
