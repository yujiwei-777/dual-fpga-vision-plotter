`timescale 1ns/1ps
module tb_key1_min_safety;
reg clk=0,rst=0,key_n=1,ready=1,inhibit=0,paper=0;reg [1:0] mode=0;
always #4 clk=~clk;
wire short_pulse,long_pulse,press,held;
secondary_key1_action_ctrl #(.DEBOUNCE_CYCLES(3),.LONG_PRESS_CYCLES(32)) dut(.clk(clk),.rst_n(rst),.key_n(key_n),.can_start(ready),.inhibit(inhibit),.paper_confirm_armed(paper),.context_id(mode),.short_pulse(short_pulse),.airwalk_pulse(long_pulse),.press_pulse(press),.held(held));
integer ns=0,nl=0,np=0,checks=0,base_s,base_l;
always @(posedge clk)begin
 if(short_pulse)ns++;if(long_pulse)nl++;if(press)np++;
 if(short_pulse&&long_pulse)$fatal(1,"exclusive action violation");
 if(long_pulse&&!paper)$fatal(1,"long action outside paper armed");
 if((short_pulse||long_pulse)&&(!ready||inhibit))$fatal(1,"action while blocked");
end
task tick(input integer n);repeat(n)@(negedge clk);endtask
task check(input bit pass,input string label);begin checks++;if(!pass)$fatal(1,"%s short=%0d long=%0d",label,ns,nl);end endtask
task fresh;begin key_n=1;ready=1;inhibit=0;mode=0;tick(10);base_s=ns;base_l=nl;end endtask
task noaction(input string label);begin key_n=1;tick(10);check(ns==base_s&&nl==base_l,label);end endtask
initial begin
 tick(4);rst=1;tick(10);
 paper=0;fresh;key_n=0;tick(12);check(held,"held immediately fences prepare");check(ns==base_s&&nl==base_l,"short waits release");key_n=1;tick(10);check(ns==base_s+1&&nl==base_l,"ordinary short release");
 fresh;key_n=0;tick(80);check(nl==base_l,"ordinary long disabled");noaction("ordinary long release is not short write");
 paper=1;fresh;key_n=0;tick(20);check(nl==base_l,"paper threshold not early");tick(60);check(nl==base_l+1,"paper long exactly once");key_n=1;tick(10);check(ns==base_s&&nl==base_l+1,"paper long release not write");
 fresh;key_n=0;tick(10);paper=0;tick(50);noaction("paper armed falling does not become write");
 fresh;key_n=0;tick(10);paper=1;tick(50);noaction("paper armed rising cannot convert held press");
 fresh;key_n=0;tick(10);paper=0;tick(2);paper=1;tick(50);noaction("paper armed toggled back still invalidates press");
 fresh;ready=0;key_n=0;tick(10);ready=1;tick(50);noaction("busy press does not queue when available");
 fresh;key_n=0;tick(10);ready=0;tick(2);ready=1;tick(50);noaction("mid-hold busy remains invalid after recovery");
 fresh;key_n=0;tick(10);mode=1;tick(2);mode=0;tick(50);noaction("mode roundtrip cannot queue");
 fresh;inhibit=1;key_n=0;tick(10);inhibit=0;tick(50);noaction("inhibited press never queues");
 fresh;key_n=0;tick(10);inhibit=1;tick(2);inhibit=0;tick(50);noaction("inhibit interrupts hold permanently");
 fresh;key_n=0;tick(10);rst=0;tick(4);rst=1;tick(60);check(ns==base_s&&nl==base_l,"held across reset no action");noaction("reset held release no action");
 fresh;key_n=0;tick(12);key_n=1;tick(10);check(ns==base_s+1&&nl==base_l,"fresh post-reset press works");
 fresh;repeat(4)begin key_n=0;tick(1);key_n=1;tick(1);end key_n=0;tick(50);noaction("press bounce conservatively discards transaction");
 fresh;key_n=0;tick(12);key_n=1;tick(1);key_n=0;tick(1);key_n=1;tick(10);check(ns==base_s&&nl==base_l,"release bounce cannot duplicate or queue");
 fresh;key_n=0;tick(30);inhibit=1;tick(10);inhibit=0;noaction("threshold cancellation blocks long and release");
 if(np<8)$fatal(1,"insufficient debounced press coverage");
 $display("KEY1_MIN_SAFETY_PASS checks=%0d shorts=%0d longs=%0d presses=%0d",checks,ns,nl,np);$finish;
end
initial begin #1000000;$fatal(1,"watchdog");end
endmodule
