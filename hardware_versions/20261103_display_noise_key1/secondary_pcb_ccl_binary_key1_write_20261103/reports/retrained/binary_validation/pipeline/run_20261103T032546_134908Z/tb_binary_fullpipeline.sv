
`timescale 1ns/1ps
`define AD dut.g_pcb_ccl_binary.pcb_auto
`define CORE dut.g_pcb_ccl_binary.pcb_auto.classifier
`define WS dut.g_shared_workspace.workspace
module tb_binary_fullpipeline;
    localparam WEIGHTS="E:/codex_pcb_binary_ccl_retrained_20261103_key1/model/experiments/conv4_4/weights.mem",BIASES="E:/codex_pcb_binary_ccl_retrained_20261103_key1/model/experiments/conv4_4/biases.mem",CNN_WEIGHTS="E:/codex_pcb_binary_ccl_retrained_20261103_key1/model/export/weights.mem",CNN_BIASES="E:/codex_pcb_binary_ccl_retrained_20261103_key1/model/export/biases.mem";
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,start=0,cancel=0;reg[1:0] purpose=1;reg[31:0] job_id=0;
    wire busy,done,valid,checked,good,frame_lock;wire[2:0] status,defect_count,multi_count;
    wire[255:0] defect_boxes;wire[7:0] defect_kinds,confidence;wire[511:0] multi_boxes;
    wire[10:0] x0,x1,pixel_x;wire[9:0]y0,y1,pixel_y;wire request,invalidate;
    wire[31:0]result_job_id,version;
    reg pending=0,pixel_valid=0,response_enable=1;reg[7:0]pixel_luma=0,response_data=0;
    wire pixel_ready=!pending;wire[23:0]pixel_rgb={pixel_luma,pixel_luma,pixel_luma};
    integer delay_left=0,accepts=0,replies=0,cycles=0,launch_cycle=0;
    integer scan_reads=0,roi_reads=0,stored_mask=0,streamed_mask=0,ccl_commits=0,roi_stores=0,f1_writes=0,f2_writes=0,pool_count=0;
    integer expected_count,expected_overflow,expected_truncated,expected_status,expected_score,expected_margin,expected_class,expected_valid;
    integer expected_x0,expected_y0,expected_x1,expected_y1,frame_cases=0,cancel_cases=0,i;
    reg checks=0,active_job=0,cancel_job=0;
    reg[7:0]source_y[0:921599],roi[0:9215];reg[15:0]f1[0:9215],f2[0:2303],pool[0:63],sample_x[0:95],sample_y[0:95],areas[0:3];
    reg signed[31:0]logits[0:1];reg[63:0]boxes[0:3];reg mask[0:14399];
    string fixtures,case_name;
    vision_pipeline #(.EXTERNAL_READER(1),.LOCAL_CNN_ENABLE(1),.SHARED_WORKSPACE(1),.PCB_ENABLE(1),.PCB_GOODONLY_AUTO(1),.PCB_BINARY_WEIGHTS_MEM(WEIGHTS),.PCB_BINARY_BIASES_MEM(BIASES))dut(
      .clk(clk),.rst_n(rst_n),.start(start),.purpose(purpose),.teach_good(1'b0),.cancel(cancel),.job_id(job_id),
      .word_req(),.byte_addr(),.word_ready(1'b0),.word_valid(1'b0),.word_data(128'd0),
      .cfg_we(1'b0),.cfg_addr(15'd0),.cfg_data(8'd0),.cfg_commit(1'b0),.busy(busy),.done(done),.result_job_id(result_job_id),.config_version(version),
      .color_id(),.shape_id(),.confidence(confidence),.valid(valid),.x0(x0),.x1(x1),.y0(y0),.y1(y1),.area(),
      .pcb_checked(checked),.pcb_good(good),.pcb_status(status),.defect_count(defect_count),.defect_boxes(defect_boxes),.defect_kinds(defect_kinds),
      .multi_count(multi_count),.multi_boxes(multi_boxes),.multi_flags(),.teach_success(),.teach_failed(),.teach_code(),.teach_commit(),.taught_station_header(),
      .ext_reader_ready(pixel_ready),.ext_reader_valid(pixel_valid),.ext_reader_rgb(pixel_rgb),.ext_reader_luma(pixel_luma),.ext_reader_request(request),.ext_reader_invalidate(invalidate),
      .ext_pixel_x(pixel_x),.ext_pixel_y(pixel_y),.yolo_pixel_valid(),.yolo_pixel_rgb(),.yolo_pixel_last(),.color_word_active(),.history_clear(1'b0),.pcb_frame_lock(frame_lock));
    defparam dut.g_local_cnn.classifier.WEIGHTS_MEM=CNN_WEIGHTS;
    defparam dut.g_local_cnn.classifier.BIASES_MEM=CNN_BIASES;
    task fail(input string why);begin $display("BINARY_FULLPIPELINE_FAIL case=%s cycle=%0d state=%0d adapter=%0d %s",case_name,cycles,dut.state,`AD.state,why);$fatal(1,"integrated regression failed");end endtask
    always@(posedge clk)begin
      cycles=cycles+1;
      if(!rst_n)begin pending<=0;delay_left<=0;accepts=0;replies=0;end
      else begin
        if(pixel_valid)begin pending<=0;replies=replies+1;end
        if(pending&&delay_left>0)delay_left<=delay_left-1;
        if(request&&pixel_ready)begin
          if(pixel_x>=1280||pixel_y>=720)fail("out of source coordinate");
          if(cancel_job)fail("new request after cancel");
          if(checks)begin
            if(dut.auto_owner)begin
              if(!expected_valid||roi_reads>=9216)fail("unexpected ROI read");
              if(pixel_x!==sample_x[roi_reads%96]||pixel_y!==sample_y[roi_reads/96])fail($sformatf("ROI address index=%0d got=%0d,%0d expected=%0d,%0d",roi_reads,pixel_x,pixel_y,sample_x[roi_reads%96],sample_y[roi_reads/96]));
              roi_reads=roi_reads+1;
            end else begin
              if(scan_reads>=14400||pixel_x!==(8*(scan_reads%160)+4)||pixel_y!==(8*(scan_reads/160)+4))fail("CCL scan address/order");
              scan_reads=scan_reads+1;
            end
          end
          response_data<=source_y[pixel_y*1280+pixel_x];pending<=1;delay_left<=1+(accepts%3);accepts=accepts+1;
        end
        if(pending&&purpose==1&&!frame_lock)fail("frame ownership released before response");
        if(active_job&&purpose==1&&busy&&!frame_lock)fail("active PCB frame not locked");
        if(cancel&&request)fail("same-cycle cancel admitted request");
        if(cancel_job&&done)fail("cancelled job published done");
        if(purpose==1&&(defect_count!==0||defect_boxes!==0||defect_kinds!==0))fail("unvalidated localized defects published");
        if(checks)begin
          if(dut.edge_components.state==dut.edge_components.S_STORE&&dut.cc_pixel_valid&&dut.cc_ready)begin
            if(stored_mask>=14400||(dut.sampled_source_y<=112)!==mask[stored_mask])fail("CCL stored source-Y mask");
            stored_mask=stored_mask+1;
          end
          if(dut.edge_components.ccl_pixel_valid&&dut.edge_components.ccl_ready)begin
            if(streamed_mask>=14400||dut.edge_components.mask_pending!==mask[streamed_mask])fail("CCL streamed mask");
            streamed_mask=streamed_mask+1;
          end
          if(dut.cc_done)begin
            if(dut.cc_count!==expected_count||dut.cc_overflow!==expected_overflow[0]||dut.cc_truncated!==expected_truncated[0])fail("CCL flags");
            for(i=0;i<4;i=i+1)begin if(dut.cc_boxes[64*i+:64]!==boxes[i])fail("CCL bbox");if(dut.cc_areas[16*i+:16]!==areas[i])fail("CCL area");end
            ccl_commits=ccl_commits+1;
          end
          if(`AD.core_pixel_we)begin
            if(roi_stores>=9216||`AD.roi_index!==roi_stores||`AD.captured_pixel!==roi[roi_stores])fail("ROI byte/load index");
            roi_stores=roi_stores+1;
          end
          if(dut.ws_pcb_we&&`CORE.state==3)begin if(dut.ws_pcb_waddr>=9216||dut.ws_pcb_wdata!==f1[dut.ws_pcb_waddr])fail("Conv1 workspace write");f1_writes=f1_writes+1;end
          if(dut.ws_pcb_we&&`CORE.state==6)begin if(dut.ws_pcb_waddr>=2304||dut.ws_pcb_wdata!==f2[dut.ws_pcb_waddr])fail("Conv2 workspace write");f2_writes=f2_writes+1;end
          if(`CORE.busy&&`CORE.state==9&&`CORE.phase==0)begin if(`CORE.pool_value!==pool[`CORE.hindex])fail("spatial pool value");pool_count=pool_count+1;end
          if(`CORE.done)begin
            if($signed(`CORE.logits[0])!==logits[0]||$signed(`CORE.logits[1])!==logits[1])fail("final logits");
            if(`CORE.class_id!==expected_class||`CORE.score!==expected_score||`CORE.margin!==expected_margin)fail("core class/score/margin");
          end
        end
      end
    end
    always@(negedge clk)begin pixel_valid<=0;if(rst_n&&pending&&delay_left==0&&response_enable)begin pixel_valid<=1;pixel_luma<=response_data;end end
    task load(input string name);string path;begin
      case_name=name;path={fixtures,"/",name,"/"};
      `include "binary_pipeline_config.svh"
      $readmemh({path,"source_y.mem"},source_y);$readmemh({path,"mask.mem"},mask);$readmemh({path,"boxes.mem"},boxes);$readmemh({path,"areas.mem"},areas);
      if(expected_valid)begin $readmemh({path,"roi.mem"},roi);$readmemh({path,"sample_x.mem"},sample_x);$readmemh({path,"sample_y.mem"},sample_y);$readmemh({path,"conv1.mem"},f1);$readmemh({path,"conv2.mem"},f2);$readmemh({path,"pool.mem"},pool);$readmemh({path,"logits.mem"},logits);end
    end endtask
    task launch;begin if(busy||frame_lock||pending)fail("reentry before owner clear");@(negedge clk);start=1;job_id=job_id+1;active_job=1;launch_cycle=cycles;@(negedge clk);start=0;end endtask
    task run_frame(input string name);integer timeout;begin
      purpose=1;checks=0;cancel_job=0;response_enable=1;load(name);scan_reads=0;roi_reads=0;stored_mask=0;streamed_mask=0;ccl_commits=0;roi_stores=0;f1_writes=0;f2_writes=0;pool_count=0;
      checks=1;launch();timeout=0;while(!done&&timeout<3000000)begin@(negedge clk);timeout=timeout+1;end
      if(!done)fail("timeout");
      if(valid!==expected_valid[0]||status!==expected_status||checked!==(expected_valid&&expected_status<2)||good!==(expected_valid&&expected_status==0))fail("result verdict/checked/valid");
      if(x0!==expected_x0||x1!==expected_x1||y0!==expected_y0||y1!==expected_y1)fail("published original bbox");
      if(result_job_id!==job_id||version!==32'h50434233||confidence!==expected_score)fail("result metadata/confidence");
      if(scan_reads!=14400||stored_mask!=14400||streamed_mask!=14400||ccl_commits!=1)fail("CCL coverage counts");
      if(expected_valid&&(roi_reads!=9216||roi_stores!=9216||f1_writes!=9216||f2_writes!=2304||pool_count!=128))fail("inference coverage counts");
      if(!expected_valid&&(roi_reads!=0||roi_stores!=0||f1_writes!=0||f2_writes!=0))fail("gated frame entered CNN");
      if(busy||frame_lock||pending||accepts!=replies)fail("completion retains read/owner");
      $display("BINARY_FULLPIPELINE_FRAME_PASS name=%s status=%0d valid=%0d ROI=%0d cycles=%0d",name,status,valid,roi_reads,cycles-launch_cycle);frame_cases=frame_cases+1;checks=0;active_job=0;repeat(3)@(negedge clk);
    end endtask
    task run_cancel(input integer mode);integer timeout;begin
      purpose=1;checks=0;cancel_job=0;load("real_00_current_good");response_enable=(mode!=0);launch();timeout=0;
      if(mode==0)begin while(!pending&&timeout<1000)begin@(negedge clk);timeout=timeout+1;end if(!pending)fail("no CCL pending cancel trigger");end
      else if(mode==1)begin while(!(dut.auto_owner&&pending)&&timeout<1000000)begin@(negedge clk);timeout=timeout+1;end if(timeout>=1000000)fail("no ROI cancel trigger");response_enable=0;end
      else begin while(!(`CORE.busy&&`CORE.state==5)&&timeout<2000000)begin@(negedge clk);timeout=timeout+1;end if(timeout>=2000000)fail("no Conv2 cancel trigger");end
      @(negedge clk);cancel=1;cancel_job=1;repeat(5)@(negedge clk);response_enable=1;repeat(2)@(negedge clk);cancel=0;
      timeout=0;while((busy||frame_lock||pending)&&timeout<100000)begin@(negedge clk);timeout=timeout+1;end
      if(busy||frame_lock||pending||valid||accepts!=replies)fail("cancel did not drain/invalidate");
      active_job=0;cancel_job=0;$display("BINARY_FULLPIPELINE_CANCEL_PASS mode=%0d",mode);cancel_cases=cancel_cases+1;repeat(4)@(negedge clk);
    end endtask
    task run_ordinary_empty;integer timeout;begin
      purpose=0;checks=0;cancel_job=0;load("synthetic_blank");launch();timeout=0;while(!done&&timeout<2000000)begin@(negedge clk);timeout=timeout+1;end
      if(!done||valid||multi_count!==0||multi_boxes!==0||frame_lock||pending)fail("ordinary empty after PCB retained stale target");
      $display("BINARY_FULLPIPELINE_ORDINARY_EMPTY_PASS");active_job=0;repeat(3)@(negedge clk);
    end endtask
    initial begin
      if(!$value$plusargs("FIXTURES=%s",fixtures))$fatal(1,"missing FIXTURES");repeat(5)@(negedge clk);rst_n=1;
      `include "binary_pipeline_calls.svh"
      run_ordinary_empty();run_frame("real_00_current_good");
      $display("BINARY_FULLPIPELINE_GOLDEN_PASS frames=%0d cancels=%0d",frame_cases,cancel_cases);$finish;
    end
endmodule
