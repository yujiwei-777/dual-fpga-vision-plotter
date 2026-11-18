`timescale 1ns/1ps
module tb_uart_startup_retry;
parameter integer CASE_ID=0;
reg clk=0,rst_n=0,serial_rx=1,reply=0,tx_valid=0;
always #5 clk=~clk;
wire serial_tx,ready,txready;
integer holds=0,queries=0,resets=0,normal=0,checks=0;
localparam integer BT=4;
grbl_uart_port #(.CLK_HZ(4000),.BAUD(1000),.PROBE_INTERVAL_CYCLES(10000),
 .INITIAL_SILENCE_RETRY(1),.INITIAL_SAFE_RETRY(1)) dut(
 .I_clk(clk),.I_rst_n(rst_n),.I_uart_rx(serial_rx),.O_uart_tx(serial_tx),
 .I_esp_link_ready(1'b0),.O_link_ready(ready),.I_tx_data("G"),.I_tx_valid(tx_valid),
 .O_tx_ready(txready),.I_rt_data(8'd0),.I_rt_valid(1'b0),.I_idle_poll_allowed(1'b0));
task step(input integer n);begin repeat(n)begin @(posedge clk);#1;end end endtask
task send(input reg[7:0] x);begin
 @(negedge clk);serial_rx=0;repeat(BT)@(negedge clk);
 for(integer j=0;j<8;j++)begin serial_rx=x[j];repeat(BT)@(negedge clk);end
 serial_rx=1;repeat(BT)@(negedge clk);
end endtask
task receive(input string s);begin
 repeat(5)@(negedge clk);for(integer j=0;j<s.len();j++)send(s[j]);
end endtask
task noise;begin
 @(negedge clk);serial_rx=0;repeat(BT*11)@(negedge clk);
 serial_rx=1;repeat(BT*4)@(negedge clk);
end endtask
task check(input bit yes,input string s);begin
 checks++;if(!yes)$fatal(1,"case%0d %s state%0d ready%b hold%0d query%0d reset%0d normal%0d",CASE_ID,s,dut.guard_state,ready,holds,queries,resets,normal);
end endtask
task await_ready;integer n;begin
 n=0;while(!ready&&n<45000)begin step(1);n++;end
 check(ready&&resets>=1,"clean complete startup handshake without keys");
 check(normal==0,"no normal command admitted before readiness");
end endtask
reg[7:0] ch;
initial forever begin
 @(negedge serial_tx);repeat(BT+BT/2)@(negedge clk);
 for(integer j=0;j<8;j++)begin ch[j]=serial_tx;repeat(BT)@(negedge clk);end
 if(ch=="?")begin queries++;if(reply)receive("<Idle|MPos:0,0,0>\n");end
 else if(ch=="!")holds++;
 else if(ch==8'h18)resets++;
 else normal++;
end
integer h0,q0,r0;
initial begin
 step(4);rst_n=1;
 case(CASE_ID)
 0:begin
  step(400);noise();check(!ready,"startup framing error fences commands");
  step(17000);check(!ready&&resets==0,"silence cannot authorize reset or readiness");
  reply=1;await_ready;
 end
 1,2:begin
  wait(dut.guard_state==13);step(100);
  receive(CASE_ID==1?"<Idle|MPos:0,0,0>\n":"<Hold:0|MPos:0,0,0>\n");
  check(!ready&&resets==0,"late stopped report cannot directly authorize normal TX");
  reply=1;await_ready;
 end
 3,4,5,6,7:begin
  wait(dut.guard_state==13);step(100);
  if(CASE_ID==3)receive("<Run|MPos:0,0,0>\n");
  if(CASE_ID==4)receive("<Hold:1|MPos:0,0,0>\n");
  if(CASE_ID==5)receive("ALARM:1\n");
  if(CASE_ID==6)receive("<Alarm|MPos:0,0,0>\n");
  if(CASE_ID==7)receive("error:2\n");
  step(50);h0=holds;q0=queries;r0=resets;reply=1;step(35000);
  check(!ready&&dut.guard_state==8&&holds==h0&&queries==q0&&resets==r0&&normal==0,
    "moving/Alarm/error never auto-cleared");
 end
 8:begin
  reply=1;await_ready;reply=0;noise();step(35000);
  check(!ready&&dut.guard_state==8,"startup retry unavailable after any established epoch");
 end
 9:begin
  step(400);receive("Grbl 1.1h ['$' for help]\n");reply=1;await_ready;
 end
 endcase
 if(CASE_ID<=2||CASE_ID==9)begin
  tx_valid=1;step(1);tx_valid=0;step(60);
  check(normal==1,"first ordinary command accepted without KEY4 then KEY3");
 end
 $display("UART_STARTUP_RETRY_PASS case=%0d checks=%0d",CASE_ID,checks);$finish;
end
initial begin #3000000;$fatal(1,"startup retry watchdog");end
endmodule
