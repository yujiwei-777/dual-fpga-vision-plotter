`timescale 1ns/1ps
module tb_key3_debounce_case #(
    parameter integer N=4
)(output reg done=0,output integer errors=0,output integer checks=0);
    reg clk=0,por_n=0,key_n=1;
    wire release_n;
    localparam integer SHORT=(N>1)?N-1:1;
    secondary_key3_board_reset #(.DEBOUNCE_CYCLES(N)) dut(
        .I_clk(clk),.I_por_n(por_n),.I_key_n(key_n),.O_release(release_n));
    initial while(!done) #10 clk=~clk;
    task tick;begin @(posedge clk);#1;end endtask
    task check(input bit good,input string message);begin
        checks=checks+1;
        if(!good)begin
            errors=errors+1;
            if(errors<=12)$display("FAIL KEY3 N=%0d t=%0t %s release=%b",N,$time,message,release_n);
        end
    end endtask
    task stay(input integer cycles,input bit value,input string message);begin
        repeat(cycles)begin tick;check(release_n===value,message);end
    end endtask
    task drive(input bit value);begin @(negedge clk);key_n=value;end endtask
    // The interface includes two synchronizer stages and one transition
    // capture cycle. A running-key transition is committed on edge N+3.
    task transition(input bit value,input string message);begin
        drive(value);
        stay(N+2,!value,{message," before debounce threshold"});
        tick;check(release_n===value,{message," at debounce threshold"});
    end endtask
    task por_released_boot;begin
        @(negedge clk);por_n=1;
        // With an initially released key there is no transition capture:
        // sample-valid takes two edges, followed by N stable edges.
        stay(N+1,0,"released cold boot remains reset before threshold");
        tick;check(release_n===1,"released cold boot exits at N+2");
    end endtask
    initial begin
        // Force an actual POR assertion event, including at time zero.
        por_n=1;#1;por_n=0;#1;
        check(release_n===0,"POR asserts without waiting for clock");
        stay(4,0,"POR held");
        por_released_boot;
        stay(5,1,"released boot stable");

        // Less than the configured debounce interval must not reset.
        drive(0);stay(SHORT,1,"short press rejected");
        drive(1);stay(N+5,1,"short press recovery does not reset");
        drive(0);stay(1,1,"one-cycle press bounce rejected");
        drive(1);stay(N+5,1,"press bounce does not accumulate");

        transition(0,"stable press");
        stay(N+8,0,"held KEY3 never restarts application");
        // A release bounce must not restart clocks or application state.
        drive(1);stay(SHORT,0,"short release rejected");
        drive(0);stay(N+5,0,"release bounce returns to held reset");
        drive(1);stay(1,0,"one-cycle release bounce rejected");
        drive(0);stay(N+5,0,"release bounce does not accumulate");
        transition(1,"stable release");
        stay(5,1,"stable release remains released");

        transition(0,"second independent press");
        stay(7,0,"second held press");
        transition(1,"second independent release");

        // Reassert POR between edges after the board has already run.
        @(negedge clk);#3;por_n=0;#1;
        check(release_n===0,"POR reassertion is asynchronous");
        stay(3,0,"reasserted POR held");
        por_released_boot;

        // Cold start with KEY3 held never produces a release pulse.
        @(negedge clk);key_n=0;#3;por_n=0;#1;
        check(release_n===0,"POR with KEY3 held asserts reset");
        stay(4,0,"held-key cold POR");
        @(negedge clk);por_n=1;
        stay(N+8,0,"held-key cold boot cannot release");
        transition(1,"held-key cold boot stable release");

        $display("KEY3_CASE_RESULT N=%0d checks=%0d errors=%0d",N,checks,errors);
        if(N==1000000)$display("KEY3_PRODUCTION_THRESHOLD cycles=%0d clk_ns=20 debounce_ns=20000000 transition_edges=1000003",N);
        done=1;
    end
endmodule

module tb_reset_sync_domains(output reg done=0,output integer errors=0,output integer checks=0);
    reg clk_a=0,clk_b=0,run_a=1,run_b=1,async_n=1;
    wire rst_a_n,rst_b_n;
    reset_sync a(.I_clk(clk_a),.I_async_rst_n(async_n),.O_rst_n(rst_a_n));
    reset_sync b(.I_clk(clk_b),.I_async_rst_n(async_n),.O_rst_n(rst_b_n));
    initial while(!done)begin #4;if(run_a)clk_a=~clk_a;else clk_a=0;end
    initial while(!done)begin #7;if(run_b)clk_b=~clk_b;else clk_b=0;end
    task check(input bit good,input string message);begin
        checks=checks+1;
        if(!good)begin errors=errors+1;$display("FAIL RESET_SYNC t=%0t %s A=%b B=%b",$time,message,rst_a_n,rst_b_n);end
    end endtask
    task release_a;begin
        @(posedge clk_a);#0.001;check(rst_a_n===0,"A remains reset after first release edge");
        @(posedge clk_a);#0.001;check(rst_a_n===1,"A releases at second local edge");
    end endtask
    task release_b;begin
        @(posedge clk_b);#0.001;check(rst_b_n===0,"B remains reset after first release edge");
        @(posedge clk_b);#0.001;check(rst_b_n===1,"B releases at second local edge");
    end endtask
    initial begin
        #1;async_n=0;#0.001;
        check(rst_a_n===0&&rst_b_n===0,"initial asynchronous assertion");
        #2;async_n=1;
        fork release_a;release_b;join
        @(negedge clk_a);run_a=0;
        @(negedge clk_b);run_b=0;
        #3;check(clk_a===0&&clk_b===0,"both consumer clocks stopped low");
        async_n=0;#0.001;
        check(rst_a_n===0&&rst_b_n===0,"stopped clocks still asynchronously reset both domains");
        #31;async_n=1;#31;
        check(rst_a_n===0&&rst_b_n===0,"no local clock means no asynchronous release");
        run_a=1;release_a;
        check(rst_b_n===0,"B stays reset while only A clocks");
        run_b=1;release_b;

        // An assertion between release edges cancels the partial release.
        @(negedge clk_a);run_a=0;
        @(negedge clk_b);run_b=0;
        #3;async_n=0;#0.001;
        check(rst_a_n===0&&rst_b_n===0,"second stopped-clock assertion");
        #3;async_n=1;run_a=1;
        @(posedge clk_a);#0.001;
        check(rst_a_n===0,"partial release only one edge");
        #1;async_n=0;#0.001;
        check(rst_a_n===0&&rst_b_n===0,"reassertion cancels partial release");
        #1;async_n=1;
        release_a;
        check(rst_b_n===0,"B still needs own two release edges");
        run_b=1;release_b;
        $display("RESET_SYNC_CASE_RESULT checks=%0d errors=%0d",checks,errors);
        done=1;
    end
endmodule

module tb_key3_reset_unit;
    wire [4:0] done;
    wire [31:0] errors[0:4],checks[0:4];
    tb_key3_debounce_case #(.N(1)) c1(done[0],errors[0],checks[0]);
    tb_key3_debounce_case #(.N(4)) c4(done[1],errors[1],checks[1]);
    tb_key3_debounce_case #(.N(17)) c17(done[2],errors[2],checks[2]);
    tb_key3_debounce_case #(.N(1000000)) production(done[3],errors[3],checks[3]);
    tb_reset_sync_domains domains(done[4],errors[4],checks[4]);
    initial begin
        wait(&done);#1;
        if((errors[0]+errors[1]+errors[2]+errors[3]+errors[4])==0)
            $display("KEY3_RESET_UNIT_PASS cases=5");
        else $display("KEY3_RESET_UNIT_FAIL errors=%0d",errors[0]+errors[1]+errors[2]+errors[3]+errors[4]);
        $finish;
    end
    initial begin #2000000000;$display("KEY3_RESET_UNIT_FAIL watchdog");$finish;end
endmodule
