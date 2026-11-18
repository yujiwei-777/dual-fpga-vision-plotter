`timescale 1ns/1ps
module tb_uart_safety_review;
parameter integer CASE_ID=0;
reg clk=0,rst_n=0,serial_rx=1;
always #5 clk=~clk;
wire serial_tx,ready,txready;
reg tx_valid=0;
reg [1:0] peer_mode=0;
integer holds=0,queries=0,resets=0,normal=0,checks=0;
localparam integer BT=4;
grbl_uart_port #(.CLK_HZ(4000),.BAUD(1000),.PROBE_INTERVAL_CYCLES(10000),.INITIAL_SILENCE_RETRY(CASE_ID==8?0:1)) dut(
 .I_clk(clk),.I_rst_n(rst_n),.I_uart_rx(serial_rx),.O_uart_tx(serial_tx),
 .I_esp_link_ready(1'b1),.O_link_ready(ready),.I_tx_data("G"),.I_tx_valid(tx_valid),
 .O_tx_ready(txready),.I_rt_data(8'd0),.I_rt_valid(1'b0));
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
 if(!yes)$fatal(1,"case=%0d %s state=%0d ready=%b hold=%0d query=%0d reset=%0d ordinary=%0d",CASE_ID,message,dut.guard_state,ready,holds,queries,resets,normal);
end endtask
task await_ready;integer n;begin
 n=0;while(!ready&&n<10000)begin step(1);n++;end
 check(ready,"clean handshake did not become ready");
 check(resets==1,"handshake must send exactly one cleanup Ctrl-X");
 check(holds==1,"handshake must start exactly once with hold");
end endtask
task locked_for_window;integer saved_queries,saved_resets,saved_holds;begin
 step(10000);
 saved_queries=queries;saved_resets=resets;saved_holds=holds;
 tx_valid=1;step(20000);tx_valid=0;
 check(!ready&&!txready,"unsafe session became ready");
 check(queries==saved_queries&&resets==saved_resets&&holds==saved_holds,"safety lock unexpectedly retried");
 check(normal==0,"ordinary G-code byte escaped lock");
end endtask
reg [7:0] incoming;
initial forever begin
 @(negedge serial_tx);
 repeat(BT+BT/2)@(negedge clk);
 for(integer i=0;i<8;i++)begin incoming[i]=serial_tx;repeat(BT)@(negedge clk);end
 if(serial_tx!==1)$fatal(1,"missing UART stop bit");
 if(incoming=="?")begin
  queries++;
  case(peer_mode)
   1:receive("<Idle|MPos:0,0,0>\n");
   2:receive("<Run|MPos:0,0,0>\n");
   3:receive("ALARM:1\n");
  endcase
 end else if(incoming=="!")holds++;
 else if(incoming==8'h18)resets++;
 else normal++;
end
integer before_q;
initial begin
 if(CASE_ID==1)peer_mode=2;
 if(CASE_ID==2)peer_mode=3;
 if(CASE_ID>=4&&CASE_ID<=7)peer_mode=1;
 step(4);rst_n=1;
 case(CASE_ID)
  0:begin
   step(10000);check(!ready,"silent controller unexpectedly ready");
   check(resets==0,"unresponsive controller must not receive Ctrl-X without stopped status");
   peer_mode=1;
   begin integer n;n=0;while(!ready&&n<22000)begin step(1);n++;end end
   check(ready,"late online controller failed automatic clean connect");
   check(holds>=2&&queries>=3&&resets==1,"retry omitted complete hold/query/reset/query sequence");
   check(normal==0,"initial retry emitted ordinary motion data");
  end
  1:begin
   locked_for_window();
   check(dut.startup_status_seen,"valid Run status was not retained");
   check(resets==0,"Run controller must not be reset as stopped");
  end
  2:begin locked_for_window();check(resets==0,"Alarm controller was reset automatically");end
  3:begin
   step(400);malformed();locked_for_window();
   check(resets==0,"initial UART framing failure was auto-cleared");
  end
  4:begin
   await_ready();peer_mode=0;receive("ALARM:1\n");locked_for_window();
  end
  5:begin
   await_ready();peer_mode=0;receive("Grbl 1.1h ['$' for help]\n");locked_for_window();
  end
  6:begin await_ready();peer_mode=0;malformed();locked_for_window();end
  7:begin
   await_ready();peer_mode=0;
   receive("<Run|MPos:0,0,0>\n");step(30000);
   check(ready,"ordinary runtime Run incorrectly locks UART");
   check(holds==1&&resets==1,"ordinary runtime Run initiated bootstrap retry");
  end
  8:begin
   step(10000);peer_mode=1;receive("<Idle|MPos:0,0,0>\n");locked_for_window();
   check(holds==1&&resets==0,"default retry-disabled behavior changed");
  end
  9:begin
   step(400);receive("error:2\n");locked_for_window();
   check(resets==0,"initial parser error was auto-cleared");
  end
 endcase
 $display("UART_SAFETY_REVIEW_PASS case=%0d checks=%0d holds=%0d queries=%0d resets=%0d ordinary=%0d",CASE_ID,checks,holds,queries,resets,normal);
 $finish;
end
initial begin #3000000;$fatal(1,"watchdog");end
endmodule
