`timescale 1ns/1ps
module tb_grbl_key1_job_guard;
    reg clk=0,rst_n=0,accept=0,explicit_cancel=0,done=0,error=0;
    wire active,protected_job;
    always #5 clk=~clk;

    grbl_key1_job_guard dut(.I_clk(clk),.I_rst_n(rst_n),.I_accept(accept),
        .I_explicit_cancel(explicit_cancel),.I_done(done),.I_error(error),
        .O_active(active),.O_protected(protected_job));

    task tick;begin @(posedge clk);#1;end endtask

    initial begin
        tick();rst_n=1;tick();
        if(active||protected_job)$fatal(1,"owner must start inactive");
        accept=1;#1;
        if(!protected_job)$fatal(1,"accept cycle must already protect the pending job");
        tick();accept=0;
        if(!active||!protected_job)$fatal(1,"accepted job owner was not latched");
        repeat(8)begin tick();if(!active||!protected_job)$fatal(1,"network-independent owner dropped before terminal event");end
        done=1;tick();done=0;#1;
        if(active||protected_job)$fatal(1,"GRBL done must release the owner");
        accept=1;tick();accept=0;#1;
        if(!active)$fatal(1,"second accepted job did not latch");
        explicit_cancel=1;tick();explicit_cancel=0;#1;
        if(active||protected_job)$fatal(1,"explicit cancel must release the owner");
        accept=1;tick();accept=0;error=1;tick();error=0;#1;
        if(active||protected_job)$fatal(1,"GRBL error must release the owner");
        $display("PASS KEY1 job guard: accept protection, network-independent hold, done/error/cancel release");
        $finish;
    end
endmodule
