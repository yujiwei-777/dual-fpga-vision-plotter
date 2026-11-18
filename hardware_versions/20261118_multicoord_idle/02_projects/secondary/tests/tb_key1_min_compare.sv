`timescale 1ns/1ps
module tb_key1_min_compare;
reg clk=0,rst=0,key_n=1,ready=1,inhibit=0;reg [1:0] purpose=0;
always #4 clk=~clk;
wire a_short,a_long,a_press,a_held,b_short,b_long,b_press,b_held;
secondary_key1_action_ctrl_reference #(.DEBOUNCE_CYCLES(3),.LONG_PRESS_CYCLES(32)) old_dut(.clk(clk),.rst_n(rst),.key_n(key_n),.can_start(ready),.inhibit(inhibit),.context_id(purpose),.short_pulse(a_short),.airwalk_pulse(a_long),.press_pulse(a_press),.held(a_held));
secondary_key1_action_ctrl #(.DEBOUNCE_CYCLES(3),.LONG_PRESS_CYCLES(32)) dut(.clk(clk),.rst_n(rst),.key_n(key_n),.can_start(ready),.inhibit(inhibit),.paper_confirm_armed(1'b1),.context_id(purpose),.short_pulse(b_short),.airwalk_pulse(b_long),.press_pulse(b_press),.held(b_held));
integer cycles=0,shorts=0,longs=0,presses=0,mismatches=0,k,n,seed=19773;
always @(negedge clk)begin
 cycles++;if(a_short)shorts++;if(a_long)longs++;if(a_press)presses++;
 if({a_short,a_long,a_press,a_held}!=={b_short,b_long,b_press,b_held})begin
  mismatches++;if(mismatches<10)$display("TIMING_DIFFERENCE cycle=%0d old=%b new=%b",cycles,{a_short,a_long,a_press,a_held},{b_short,b_long,b_press,b_held});
 end
end
task tick(input integer n);repeat(n)@(negedge clk);endtask
initial begin
 n=$urandom(seed);tick(4);rst=1;tick(10);
 for(k=0;k<500;k=k+1)begin
  @(posedge clk);#1;key_n=~key_n;
  if(k%7==0)ready=~ready;
  if(k%19==0)inhibit=~inhibit;
  if(k%29==0)purpose=purpose+1'b1;
  if(k%73==0)rst=0;else rst=1;
  n=$urandom_range(1,90);tick(n);
 end
 ready=1;inhibit=0;rst=1;key_n=1;tick(12);
 repeat(20)begin key_n=0;tick(10);key_n=1;tick(10);key_n=0;tick(50);key_n=1;tick(10);end
 if(mismatches!=0)$fatal(1,"key1 timing comparison differences=%0d",mismatches);
 if(shorts<10||longs<10||presses<20)$fatal(1,"insufficient action coverage");
 $display("KEY1_MIN_COMPARE_PASS cycles=%0d shorts=%0d longs=%0d presses=%0d mismatches=%0d",cycles,shorts,longs,presses,mismatches);$finish;
end
initial begin #1000000;$fatal(1,"timeout");end
endmodule
