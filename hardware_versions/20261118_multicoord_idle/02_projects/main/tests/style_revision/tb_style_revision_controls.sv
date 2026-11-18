`timescale 1ns/1ps
module tb_style_revision_controls;
 reg clk=0,hclk=0,rst=0,hrst=0,k2=1,k3=1,host=0,hv=0;reg[4:0]hm=0;
 wire[4:0]mode,shadow;wire busy;
 always #5 clk=~clk;always #7 hclk=~hclk;
 style_controls #(.DEBOUNCE_CYCLES(4)) dut(.I_clk(clk),.I_rst_n(rst),.I_key2_n(k2),.I_key3_n(k3),.I_host_mode(host),.I_host_clk(hclk),.I_host_rst_n(hrst),.I_host_valid(hv),.I_host_style(hm),.O_style(mode),.O_restore_busy(busy),.O_host_shadow(shadow));
 function integer mid(input integer idx);begin if(idx<5)mid=idx;else if(idx<14)mid=idx+1;else mid=idx+3;end endfunction
 function integer mix(input integer id);begin if(id<5)mix=id;else if(id>=6&&id<=14)mix=id-1;else if(id==17)mix=14;else if(id==18)mix=15;else mix=0;end endfunction
 task check(input integer expected);begin repeat(25)@(negedge clk);if(mode!==expected)$fatal(1,"mode %d expected %d",mode,expected);if(mode==5||mode==15||mode==16||mode>18)$fatal(1,"retired mode published");end endtask
 task press2;begin @(negedge clk);k2=0;repeat(10)@(negedge clk);k2=1;repeat(10)@(negedge clk);end endtask
 task command(input integer value);begin @(negedge hclk);hm=value;hv=1;@(negedge hclk);hv=0;end endtask
 task restore;begin @(negedge clk);k3=0;repeat(15)@(negedge clk);k3=1;check(0);if(shadow!==0||busy)$fatal(1,"restore CDC/shadow failed");end endtask
 initial begin
  repeat(4)@(negedge clk);rst=1;hrst=1;
  k2=0;@(negedge clk);k2=1;check(0);
  for(integer i=1;i<=32;i=i+1)begin press2();check(mid(i%16));end
  host=1;
  // Every local ordinal x every five-bit host ID, including retired IDs.
  for(integer loc=0;loc<16;loc=loc+1)begin
   for(integer id=0;id<32;id=id+1)begin command(id);check(mid((loc+mix(id))%16));if(shadow!==mid(mix(id)))$fatal(1,"shadow normalization failed");end
   press2();
  end
  restore();press2();check(1);
  k3=0;command(18);check(0);k3=1;check(0);
  $display("STYLE_REVISION_CONTROLS_PASS local16 host32 cross512 debounce restore stale-epoch");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
