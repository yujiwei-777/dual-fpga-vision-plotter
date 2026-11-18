`timescale 1ns/1ps
module tb_key2_operator;
reg clk=0;always #5 clk=~clk;
reg rst=0,key_n=1,reset=0,busy=0,ready=1,accept=0,done=0,err=0;
wire start,fail,active,newpage;wire[31:0]id;wire rt;
integer starts=0,pages=0,checks=0;
grbl_key2_test_ctrl #(.CLK_HZ(100),.DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(30)) dut(
.I_clk(clk),.I_rst_n(rst),.I_key_n(key_n),.I_reset(reset),.I_busy(busy),.I_uart_ready(ready),
.I_rt_ready(1'b1),.I_rt_done(1'b0),.I_idle_pulse(1'b0),.I_job_accept(accept),.I_job_done(done),.I_job_error(err),
.O_rt_valid(rt),.O_job_start(start),.O_job_fail(fail),.O_job_id(id),.O_active(active),.O_new_page(newpage));
always @(posedge clk)begin if(start)starts++;if(newpage)pages++;if(rt)$fatal(1,"normal button emitted safety query");end
task tick(input integer n);repeat(n)@(negedge clk);endtask
task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"KEY2_OPERATOR %s starts=%0d pages=%0d state=%0d",why,starts,pages,dut.state);end endtask
task restart(input bit held);begin rst=0;key_n=!held;busy=0;ready=1;reset=0;accept=0;done=0;err=0;tick(3);rst=1;tick(12);end endtask
task finish;begin accept=1;tick(1);accept=0;tick(3);done=1;tick(1);done=0;tick(3);end endtask
initial begin
 restart(1);tick(100);check(starts==0&&pages==0,"held through reset inert");key_n=1;tick(10);check(starts==0&&pages==0,"initial release inert");
 key_n=0;tick(12);check(starts==0&&pages==0,"press must wait for release");key_n=1;tick(10);check(starts==1&&pages==0,"short release starts once");finish();
 key_n=0;tick(60);check(starts==1&&pages==1,"long hold produces only new-page");tick(80);check(starts==1&&pages==1,"held new-page one shot");key_n=1;tick(10);check(starts==1,"long release never square");
 busy=1;key_n=0;tick(12);busy=0;tick(70);key_n=1;tick(10);check(starts==1&&pages==1,"busy press discarded through later idle");
 ready=0;key_n=0;tick(12);ready=1;tick(70);key_n=1;tick(10);check(starts==1&&pages==1,"unsafe press discarded through ready");
 key_n=0;tick(12);busy=1;tick(4);busy=0;tick(60);key_n=1;tick(10);check(starts==1&&pages==1,"busy during hold cancels rather than defers");
 key_n=0;tick(12);reset=1;tick(2);reset=0;tick(60);check(starts==1&&pages==1,"task reset held key cannot trigger");key_n=1;tick(10);
 key_n=0;tick(12);key_n=1;tick(10);check(starts==2&&pages==1,"rearmed fresh release starts square");err=1;tick(2);err=0;tick(4);
 key_n=0;tick(12);key_n=1;tick(10);check(starts==3,"new press after report error supported");finish();
 check(!active,"completed square returns idle without fresh Idle reply");
 $display("KEY2_OPERATOR_PASS checks=%0d",checks);$finish;
end
initial begin #200000;$fatal(1,"KEY2 operator timeout");end
endmodule
