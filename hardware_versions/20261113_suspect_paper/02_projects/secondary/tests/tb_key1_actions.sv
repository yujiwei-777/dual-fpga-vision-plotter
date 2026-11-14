`timescale 1ns/1ps
module tb_key1_actions;
reg clk=0,rst=0,key_n=1,ready=1,inhibit=0;
reg [1:0] purpose=0;
always #4 clk=~clk;
wire short_pulse,airwalk,press,held;
secondary_key1_action_ctrl #(.DEBOUNCE_CYCLES(3),.LONG_PRESS_CYCLES(32)) dut(
    .paper_confirm_armed(1'b1),.clk(clk),.rst_n(rst),.key_n(key_n),.can_start(ready),.inhibit(inhibit),.context_id(purpose),
    .short_pulse(short_pulse),.airwalk_pulse(airwalk),.press_pulse(press),.held(held));
integer shorts=0,airs=0,checks=0;
always @(posedge clk)begin
    if(short_pulse)shorts++;
    if(airwalk)airs++;
    if(short_pulse&&airwalk)$fatal(1,"mutually exclusive actions");
end
task tick(input integer n);repeat(n)begin @(negedge clk);end endtask
task check(input bit good,input string label);begin checks++;if(!good)$fatal(1,"KEY1 %s short=%0d air=%0d",label,shorts,airs);end endtask
initial begin
    tick(4);rst=1;tick(10);
    key_n=0;tick(12);check(shorts==0&&airs==0,"press does not write before release");
    key_n=1;tick(10);check(shorts==1&&airs==0,"short release writes once");
    key_n=0;tick(80);check(shorts==1&&airs==1,"armed long hold confirms paper exactly once");
    key_n=1;tick(10);check(shorts==1&&airs==1,"long release never starts real writing");
    ready=0;key_n=0;tick(14);ready=1;tick(40);key_n=1;tick(10);
    check(shorts==1&&airs==1,"press begun unavailable is discarded");
    key_n=0;tick(10);purpose=1;tick(35);key_n=1;tick(10);
    check(shorts==1&&airs==1,"mode switch discards held press");
    key_n=0;tick(12);key_n=1;tick(10);check(shorts==2,"new mode allows fresh short");
    key_n=0;tick(10);inhibit=1;tick(2);inhibit=0;tick(35);key_n=1;tick(10);
    check(shorts==2&&airs==1,"stop or cancellation cannot queue action");
    key_n=0;rst=0;tick(4);rst=1;tick(60);
    check(shorts==2&&airs==1,"held through reset stays disarmed");
    key_n=1;tick(10);key_n=0;tick(12);key_n=1;tick(10);
    check(shorts==3&&airs==1,"fresh release and press after reset works");
    $display("KEY1_ACTIONS_PASS checks=%0d",checks);$finish;
end
initial begin #100000;$fatal(1,"watchdog");end
endmodule
