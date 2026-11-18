`timescale 1ns/1ps
module tb_pcb_reason;
reg clk=0;always #5 clk=~clk;
reg rst=0,start=0,cancel=0,frame_valid=1,model_valid=1;
reg[2:0] count=1;reg[255:0]boxes={192'd0,16'd70,16'd120,16'd20,16'd30};
reg overflow=0,truncated=0,ready=1,respond=1;
reg reply=0;reg[1:0]cls=0;reg[7:0]score=80;reg[15:0]margin=64;
wire busy,done,valid,no_target,bbox,pxreq;wire[1:0]status;wire[15:0]error;wire[7:0]reason,actual_score;
integer checks=0;
pcb_ccl_binary_core #(.PIXEL_TIMEOUT(5),.ABORT_TIMEOUT(7),.INFER_TIMEOUT(15)) dut(
.clk(clk),.rst_n(rst),.start(start),.cancel(cancel),.frame_valid(frame_valid),.model_valid(model_valid),
.job_id(32'd1),.I_ccl_count(count),.I_ccl_boxes(boxes),.I_ccl_overflow(overflow),.I_ccl_truncated(truncated),
.busy(busy),.done(done),.result_valid(valid),.no_target(no_target),.status(status),.error(error),.reason(reason),
.bbox_valid(bbox),.pixel_request(pxreq),.pixel_ready(ready),.pixel_valid(pxreq&&ready&&respond),.pixel_y8(8'd128),
.ws_rd_data(16'd0),.mac_product_ext(24'd0),.classifier_score(actual_score));
task tick(input integer n);repeat(n)@(negedge clk);endtask
task check(input bit ok,input string why);begin checks++;if(!ok)$fatal(1,"PCB_REASON %s reason=%0d error=%h status=%0d",why,reason,error,status);end endtask
task init;begin rst=0;start=0;cancel=0;frame_valid=1;model_valid=1;count=1;overflow=0;truncated=0;ready=1;respond=1;reply=0;cls=0;score=80;margin=64;
 boxes={192'd0,16'd70,16'd120,16'd20,16'd30};tick(3);rst=1;tick(3);end endtask
task run;begin start=1;tick(1);start=0;wait(done);tick(1);end endtask
task classify(input[1:0]c,input[15:0]m);begin
 cls=c;margin=m;start=1;tick(1);start=0;wait(dut.state==12);tick(1);reply=1;tick(1);reply=0;wait(done);tick(1);
end endtask
initial begin
 force dut.core_done=reply;force dut.core_class=cls;force dut.core_score=score;force dut.core_margin=margin;
 force dut.core_sat=16'd0;force dut.core_suspect_valid=0;force dut.core_ws_we=0;
 init();frame_valid=0;run();check(reason==8&&error==16'h0101&&!valid,"invalid immutable input");
 init();count=0;run();check(reason==4&&no_target&&status==2&&!bbox,"no candidate REVIEW");
 init();overflow=1;run();check(reason==5&&status==2&&!bbox,"label overflow REVIEW");
 init();count=5;run();check(reason==5,"count overflow");
 init();boxes[15:0]=0;run();check(reason==6&&error==16'h0202,"source border");
 init();boxes[47:32]=30;run();check(reason==7,"malformed zero width box");
 init();ready=0;run();check(reason==9&&error==16'h1001&&busy,"request wait lock retains source owner");
 init();respond=0;run();check(reason==10&&error==16'h1002&&busy,"reply timeout lock retains source owner");
 init();start=1;tick(1);start=0;wait(dut.state==12);wait(done);tick(1);check(reason==11&&error==16'h1004,"inference timeout");
 init();classify(0,64);check(reason==1&&status==0&&bbox&&valid&&actual_score==80,"PASS arithmetic unchanged");
 init();classify(1,64);check(reason==2&&status==1&&bbox&&valid&&actual_score==80,"FAIL arithmetic unchanged");
 init();classify(1,31);check(reason==3&&status==2&&bbox&&valid&&actual_score==80,"low margin REVIEW retains actual score");
 init();classify(3,64);check(reason==12&&status==3&&!valid,"invalid numeric head output");
 init();start=1;tick(1);start=0;tick(2);cancel=1;tick(1);cancel=0;tick(1);check(reason==13&&error==2&&!valid,"explicit cancel");
 init();start=1;tick(1);start=0;tick(2);start=1;tick(1);start=0;tick(1);check(reason==14&&error==3&&!valid,"reentry abort");
 init();respond=0;start=1;tick(1);start=0;wait(dut.state==9);tick(1);cancel=1;tick(1);cancel=0;wait(done);tick(1);
 check(reason==15&&error==16'h1003&&busy,"cancel drain timeout preserves owner");
 $display("PCB_REASON_PASS checks=%0d",checks);$finish;
end
initial begin #20000000;$fatal(1,"PCB reason timeout");end
endmodule
