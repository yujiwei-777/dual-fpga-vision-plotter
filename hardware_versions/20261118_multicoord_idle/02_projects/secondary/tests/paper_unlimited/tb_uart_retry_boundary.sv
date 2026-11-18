`timescale 1ns/1ps
module tb_uart_retry_boundary;
parameter integer CASE_ID=0;
parameter integer SEND_TIMER=7755;
reg clk=0,rst_n=0,rx=1;always #5 clk=~clk;
wire tx,ready;
integer holds=0,queries=0,resets=0,ordinary=0,matched_status_timer=-1,matched_status_state=-1;
localparam integer BT=4;
grbl_uart_port #(.CLK_HZ(4000),.BAUD(1000),.PROBE_INTERVAL_CYCLES(10000),.INITIAL_SILENCE_RETRY(1)) dut(
 .I_clk(clk),.I_rst_n(rst_n),.I_uart_rx(rx),.O_uart_tx(tx),.I_esp_link_ready(1'b1),.O_link_ready(ready),
 .I_tx_data(8'h47),.I_tx_valid(1'b0),.I_rt_data(8'd0),.I_rt_valid(1'b0));
task step(input integer n);begin repeat(n)begin @(posedge clk);#1;end end endtask
task send(input reg[7:0] x);begin
 @(negedge clk);rx=0;repeat(BT)@(negedge clk);
 for(integer j=0;j<8;j++)begin rx=x[j];repeat(BT)@(negedge clk);end
 rx=1;repeat(BT)@(negedge clk);
end endtask
task receive(input string s);begin
 repeat(5)@(negedge clk);
 for(integer j=0;j<s.len();j++)send(s[j]);
end endtask
always @(posedge clk)if(rst_n&&dut.parser_status)begin
 matched_status_timer=dut.probe_timer;matched_status_state=dut.guard_state;
 $display("STATUS state=%0d timer=%0d status_seen=%b retry=%b",dut.guard_state,dut.probe_timer,dut.startup_status_seen,dut.retry_initial_silence);
end
reg[7:0] ch;
initial forever begin
 @(negedge tx);repeat(BT+BT/2)@(negedge clk);
 for(integer j=0;j<8;j++)begin ch[j]=tx;repeat(BT)@(negedge clk);end
 if(ch==8'h21)holds++;
 else if(ch==8'h3f)queries++;
 else if(ch==8'h18)resets++;
 else ordinary++;
 $display("TX byte=%02x state=%0d time=%0t",ch,dut.guard_state,$time);
end
integer h0,q0,r0,s0;
initial begin
 step(4);rst_n=1;
 if(CASE_ID<3)begin
  wait(dut.guard_state==13);step(100);h0=holds;q0=queries;r0=resets;
  case(CASE_ID)
   0:receive("<Run|MPos:0,0,0>\n");
   1:receive("<Jog|MPos:0,0,0>\n");
   2:receive("<Hold:1|MPos:0,0,0>\n");
  endcase
  step(24000);
  if(holds!=h0||queries!=q0||resets!=r0||ready||ordinary!=0||dut.guard_state!=8)$fatal(1,"late retry status escaped safety lock");
  $display("BOUNDARY_RESULT case=%0d initial_holds=%0d initial_queries=%0d initial_resets=%0d final_holds=%0d final_queries=%0d final_resets=%0d seen=%b ready=%b violation=%b",CASE_ID,h0,q0,r0,holds,queries,resets,dut.startup_status_seen,ready,(holds!=h0||queries!=q0||resets!=r0));
 end else begin
  wait(dut.guard_state==4&&dut.probe_timer==SEND_TIMER);
  receive(CASE_ID==3?"<Run>\n":"<Idle>\n");
  step(20000);
  if(holds!=1||queries!=1||resets!=0||ready||ordinary!=0||dut.guard_state!=8)$fatal(1,"timeout status escaped safety lock");
  $display("TIMEOUT_BOUNDARY_RESULT case=%0d send_timer=%0d status_timer=%0d status_state=%0d holds=%0d queries=%0d resets=%0d ready=%b state=%0d",CASE_ID,SEND_TIMER,matched_status_timer,matched_status_state,holds,queries,resets,ready,dut.guard_state);
 end
 $display("UART_RETRY_BOUNDARY_PASS case=%0d send_timer=%0d status_timer=%0d status_state=%0d",CASE_ID,SEND_TIMER,matched_status_timer,matched_status_state);
 $finish;
end
initial begin #1500000;$fatal(1,"watchdog");end
endmodule
