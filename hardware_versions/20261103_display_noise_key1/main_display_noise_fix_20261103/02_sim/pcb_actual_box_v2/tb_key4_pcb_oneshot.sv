`timescale 1ns/1ps
module tb_key4_pcb_oneshot;
 reg clk=0,rst_n=0,key_n=0,mode_active=0;
 wire pulse,pressed,armed; integer pulses=0;
 always #4 clk=~clk;
 key4_pcb_oneshot #(.DEBOUNCE_CYCLES(5)) dut(.clk(clk),.rst_n(rst_n),.key_n(key_n),.mode_active(mode_active),.press_pulse(pulse),.pressed(pressed),.armed(armed));
 always @(posedge clk) begin #1;if(pulse)pulses=pulses+1;end
 task wait_cycles;input integer n;begin repeat(n)@(negedge clk);end endtask
 task expect_count;input integer n;begin wait_cycles(1);if(pulses!=n)$fatal(1,"pulse count=%0d expected=%0d",pulses,n);end endtask
 initial begin
  wait_cycles(4);rst_n=1;mode_active=1;wait_cycles(30);expect_count(0);
  if(armed)$fatal(1,"reset held key armed");
  key_n=1;wait_cycles(10);if(!armed)$fatal(1,"release did not arm");
  key_n=0;wait_cycles(2);key_n=1;wait_cycles(4);expect_count(0);
  key_n=0;wait_cycles(10);expect_count(1);wait_cycles(80);expect_count(1);
  key_n=1;wait_cycles(3);key_n=0;wait_cycles(10);expect_count(1);
  key_n=1;wait_cycles(10);key_n=0;wait_cycles(10);expect_count(2);
  mode_active=0;wait_cycles(10);mode_active=1;wait_cycles(30);expect_count(2);
  key_n=1;wait_cycles(10);key_n=0;wait_cycles(10);expect_count(3);
  rst_n=0;wait_cycles(4);rst_n=1;wait_cycles(20);expect_count(3);
  key_n=1;wait_cycles(10);key_n=0;wait_cycles(10);expect_count(4);
  $display("TB_KEY4_PCB_ONESHOT_PASS pulses=%0d reset_held=PASS mode_held=PASS bounce=PASS",pulses);$finish;
 end
 initial begin #100000;$fatal(1,"watchdog");end
endmodule
