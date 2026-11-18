`timescale 1ns/1ps
module tb_uart_idle_monitor;
parameter integer CASE_ID=0;
reg clk=0,rst_n=0,serial_rx=1,idle_allowed=0,tx_valid=0;
always #5 clk=~clk;
wire serial_tx,ready,txready,txdone;
reg peer_reply=1;
integer holds=0,queries=0,resets=0,normal=0,checks=0;
localparam integer BT=4;
grbl_uart_port #(.CLK_HZ(4000),.BAUD(1000),.INITIAL_SILENCE_RETRY(1),
 .IDLE_POLL_INTERVAL_CYCLES(2000)) dut(
 .I_clk(clk),.I_rst_n(rst_n),.I_uart_rx(serial_rx),.O_uart_tx(serial_tx),
 .I_esp_link_ready(1'b0),.O_link_ready(ready),.I_tx_data("G"),.I_tx_valid(tx_valid),
 .O_tx_ready(txready),.O_tx_done(txdone),.I_rt_data(8'd0),.I_rt_valid(1'b0),
 .I_idle_poll_allowed(idle_allowed));
task step(input integer n);begin repeat(n)begin @(posedge clk);#1;end end endtask
task send_byte(input reg [7:0] value);begin
 @(negedge clk);serial_rx=0;repeat(BT)@(negedge clk);
 for(integer j=0;j<8;j++)begin serial_rx=value[j];repeat(BT)@(negedge clk);end
 serial_rx=1;repeat(BT)@(negedge clk);
end endtask
task receive(input string message);begin
 repeat(5)@(negedge clk);
 for(integer k=0;k<message.len();k++)send_byte(message[k]);
end endtask
task malformed;begin
 @(negedge clk);serial_rx=0;repeat(BT*11)@(negedge clk);
 serial_rx=1;repeat(BT*4)@(negedge clk);
end endtask
task check(input bit yes,input string message);begin
 checks++;
 if(!yes)$fatal(1,"case%0d %s state%0d ready%b cert%b q%0d hold%0d reset%0d normal%0d",CASE_ID,message,dut.guard_state,ready,dut.idle_certified,queries,holds,resets,normal);
end endtask
task await_ready;integer n;begin
 n=0;while(!ready&&n<16000)begin step(1);n++;end
 check(ready,"fresh query establishes readiness");
end endtask
task await_certified;integer n;begin
 n=0;while(!dut.idle_certified&&n<16000)begin step(1);n++;end
 check(dut.idle_certified,"fresh Idle certifies no outstanding motion");
end endtask
reg[7:0] incoming;
initial forever begin
 @(negedge serial_tx);repeat(BT+BT/2)@(negedge clk);
 for(integer i=0;i<8;i++)begin incoming[i]=serial_tx;repeat(BT)@(negedge clk);end
 if(serial_tx!==1)$fatal(1,"missing stop bit");
 if(incoming=="?")begin queries++;if(peer_reply)receive("<Idle|MPos:0,0,0>\n");end
 else if(incoming=="!")holds++;
 else if(incoming==8'h18)resets++;
 else normal++;
end
integer before_q,before_normal;
initial begin
 step(4);rst_n=1;await_ready;
 check(holds==1&&resets==1,"unchanged boot epoch");
 idle_allowed=1;await_certified;peer_reply=0;step(100);
 case(CASE_ID)
 0:begin
  malformed();step(2);check(!ready,"idle RX framing fault fences writes");
  step(9000);check(!ready,"silence cannot clear idle fault");
  check(holds==1&&resets==1&&normal==0,"read-only requalification never resets or moves");
  peer_reply=1;await_ready;await_certified;
  idle_allowed=0;step(2);tx_valid=1;step(1);tx_valid=0;step(60);
  check(normal==1,"first command accepted after idle recovery without KEY3/4");
 end
 1:begin
  idle_allowed=0;step(2);tx_valid=1;step(1);tx_valid=0;step(60);
  idle_allowed=1;step(2);check(!dut.idle_certified,"new normal byte revokes stopped proof");
  malformed();step(12000);check(!ready&&dut.guard_state==8,"unknown queued command fault stays locked");
 end
 2,3,4:begin
  if(CASE_ID==2)receive("ALARM:1\n");
  if(CASE_ID==3)receive("Grbl 1.1h ['$' for help]\n");
  if(CASE_ID==4)receive("<Alarm|MPos:0,0,0>\n");
  step(12000);check(!ready&&dut.guard_state==8,"Alarm or Reset never auto-cleared");
 end
 5:begin
  idle_allowed=0;step(2);before_q=queries;
  step(12000);check(queries==before_q,"no background polling while owner reserves path");
  malformed();step(100);check(!ready,"active-owner RX fault remains manual recovery");
 end
 6:begin
  peer_reply=1;step(160000);check(ready,"healthy long idle remains ready");
  check(queries>20&&holds==1&&resets==1&&normal==0,"long idle sends only read-only status probes");
 end
 7:begin
  // Status beginning before current query completion cannot requalify.
  malformed();step(2);check(!ready,"requalification starts fenced");
  receive("<Idle|MPos:0,0,0>\n");step(100);
  // It may be fresh only if it started after the query drained; prove any
  // explicit Reset still dominates an immediately following complete Idle.
  receive("Grbl 1.1h\n");receive("<Idle|MPos:0,0,0>\n");step(10000);
  check(!ready&&dut.guard_state==8,"fresh Idle cannot erase Reset");
 end
 endcase
 check(holds==1&&resets==1,"runtime monitor never sends hold or Ctrl-X");
 $display("UART_IDLE_MONITOR_PASS case=%0d checks=%0d queries=%0d",CASE_ID,checks,queries);$finish;
end
initial begin #8000000;$fatal(1,"watchdog");end
endmodule
