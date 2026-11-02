`timescale 1ns/1ps
`define CORE dut.g_pcb_goodonly_auto.pcb_auto
module tb_pose7_fullpipeline;
    `include "pose7_fullpipeline_paths.svh"
    reg clk=0; always #4 clk=~clk;
    reg rst_n=0,start=0,cancel=0;
    reg [31:0] job_id=0;
    wire busy,done,valid,pcb_checked,pcb_good,frame_lock;
    wire [2:0] pcb_status,defect_count;
    wire [255:0] defect_boxes;
    wire [7:0] defect_kinds,confidence;
    wire [10:0] x0,x1,pixel_x;
    wire [9:0] y0,y1,pixel_y;
    wire request,invalidate;
    wire [31:0] result_job_id,config_version;
    reg source_pending=0,pixel_valid=0,response_enable=1;
    reg [7:0] pixel_luma=0,response_data=0;
    wire pixel_ready=!source_pending;
    wire [23:0] pixel_rgb={pixel_luma,pixel_luma,pixel_luma};
    integer response_delay=0,accepts=0,replies=0;
    integer total_cycles=0,launch_cycle=0,scan_cycles=0,auto_launch_cycle=0;
    integer scan_reads=0,roi_reads=0,stored_mask=0,streamed_mask=0,roi_points=0;
    integer c1_points=0,c2_points=0,p_points=0,ccl_commits=0;
    integer frame_cases=0,cancel_cases=0;
    integer expected_count,expected_overflow,expected_truncated,expected_status,expected_score;
    integer expected_flip,expected_mean0,expected_mean180,expected_cost0,expected_cost180;
    integer expected_peak_x,expected_peak_y,expected_x0,expected_y0,expected_x1,expected_y1;
    reg check_enable=0,job_active=0,cancel_job=0;
    reg [7:0] source_y[0:921599],roi[0:9215],expected_c1[0:9215],expected_c2[0:2303],expected_p[0:575];
    reg [31:0] expected_a1[0:9215],expected_a2[0:2303];
    reg [15:0] sample_x[0:95],sample_y[0:95],expected_areas[0:3];
    reg [63:0] expected_boxes[0:3];
    reg expected_mask[0:14399];
    string fixtures,case_name;
    integer i;

    vision_pipeline #(.EXTERNAL_READER(1),.LOCAL_CNN_ENABLE(1),.SHARED_WORKSPACE(1),
        .PCB_ENABLE(1),.PCB_GOODONLY_AUTO(1),
        .PCB_POSE7_WEIGHTS_MEM(WEIGHTS_PATH),.PCB_POSE7_BIASES_MEM(BIASES_PATH),
        .PCB_POSE7_CENTRE_MEM(CENTRE_PATH),.PCB_POSE7_TOLERANCE_MEM(TOLERANCE_PATH),
        .PCB_POSE7_ORIENTATION_MEM(ORIENTATION_PATH)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.purpose(2'd1),.teach_good(1'b0),.cancel(cancel),.job_id(job_id),
        .word_req(),.byte_addr(),.word_ready(1'b0),.word_valid(1'b0),.word_data(128'd0),
        .cfg_we(1'b0),.cfg_addr(15'd0),.cfg_data(8'd0),.cfg_commit(1'b0),
        .busy(busy),.done(done),.result_job_id(result_job_id),.config_version(config_version),
        .color_id(),.shape_id(),.confidence(confidence),.valid(valid),
        .x0(x0),.x1(x1),.y0(y0),.y1(y1),.area(),.pcb_checked(pcb_checked),.pcb_good(pcb_good),
        .pcb_status(pcb_status),.defect_count(defect_count),.defect_boxes(defect_boxes),.defect_kinds(defect_kinds),
        .multi_count(),.multi_boxes(),.multi_flags(),.teach_success(),.teach_failed(),.teach_code(),
        .teach_commit(),.taught_station_header(),.ext_reader_ready(pixel_ready),.ext_reader_valid(pixel_valid),
        .ext_reader_rgb(pixel_rgb),.ext_reader_luma(pixel_luma),.ext_reader_request(request),
        .ext_reader_invalidate(invalidate),.ext_pixel_x(pixel_x),.ext_pixel_y(pixel_y),
        .yolo_pixel_valid(),.yolo_pixel_rgb(),.yolo_pixel_last(),.color_word_active(),
        .history_clear(1'b0),.pcb_frame_lock(frame_lock));
    // Keep the real ordinary CNN and stabilizer elaborated, but resolve its
    // unused model paths without editing the frozen pipeline's parameters.
    defparam dut.g_local_cnn.classifier.WEIGHTS_MEM=CNN_WEIGHTS_PATH;
    defparam dut.g_local_cnn.classifier.BIASES_MEM=CNN_BIASES_PATH;

    task fail(input string message);
        begin
            $display("POSE7_FULLPIPELINE_FAIL case=%s cycle=%0d pipeline=%0d core=%0d %s",case_name,total_cycles,dut.state,`CORE.state,message);
            $fatal(1,"fullpipeline regression failed");
        end
    endtask

    always @(posedge clk)begin
        total_cycles=total_cycles+1;
        if(!rst_n)begin source_pending<=0;response_delay<=0;accepts=0;replies=0;end
        else begin
            if(pixel_valid)begin source_pending<=0;replies=replies+1;end
            if(source_pending && response_delay>0)response_delay<=response_delay-1;
            if(request && pixel_ready)begin
                if(source_pending)fail("second accepted pixel before previous reply");
                if(pixel_x>=1280 || pixel_y>=720)fail("source coordinate outside frame");
                if(cancel_job)fail("cancelled transaction admitted a new pixel");
                if(check_enable)begin
                    if(dut.auto_owner)begin
                        if(roi_reads>=9216)fail("too many ROI pixel reads");
                        if(pixel_x!==sample_x[roi_reads%96] || pixel_y!==sample_y[roi_reads/96])
                            fail($sformatf("ROI mapping mismatch index=%0d xy=%0d,%0d",roi_reads,pixel_x,pixel_y));
                        roi_reads=roi_reads+1;
                    end else begin
                        if(scan_reads>=14400)fail("too many CCL scan reads");
                        if(pixel_x!==(8*(scan_reads%160)+4) || pixel_y!==(8*(scan_reads/160)+4))
                            fail($sformatf("CCL scan order mismatch index=%0d xy=%0d,%0d",scan_reads,pixel_x,pixel_y));
                        scan_reads=scan_reads+1;
                    end
                end
                response_data<=source_y[pixel_y*1280+pixel_x];
                source_pending<=1;response_delay<=1+(accepts%3);accepts=accepts+1;
            end
            if(source_pending && !frame_lock)fail("frame lock released before accepted source pixel replied");
            if(job_active && busy && !frame_lock)fail("active PCB lost frame ownership");
            if(cancel && request)fail("same-cycle cancel did not fence pixel admission");
            if(cancel_job && done)fail("cancelled PCB published done/report");
            if(defect_count!==0 || defect_boxes!==0 || defect_kinds!==0)fail("unvalidated localized defect output nonzero");
            if(check_enable)begin
                if(dut.edge_components.state==dut.edge_components.S_STORE && dut.cc_pixel_valid && dut.cc_ready)begin
                    if(stored_mask>=14400)fail("too many stored mask pixels");
                    if((dut.sampled_source_y<=112)!==expected_mask[stored_mask])fail("source-Y gray mask mismatch");
                    if(dut.sampled_source_y!==source_y[(8*(stored_mask/160)+4)*1280+8*(stored_mask%160)+4])fail("CCL luma sample mismatch");
                    stored_mask=stored_mask+1;
                end
                if(dut.edge_components.ccl_pixel_valid && dut.edge_components.ccl_ready)begin
                    if(streamed_mask>=14400)fail("too many streamed CCL pixels");
                    if(dut.edge_components.mask_pending!==expected_mask[streamed_mask])fail("synchronous mask RAM stream mismatch");
                    streamed_mask=streamed_mask+1;
                end
                if(dut.cc_done)begin
                    if(dut.cc_count!==expected_count || dut.cc_overflow!==expected_overflow[0] || dut.cc_truncated!==expected_truncated[0])
                        fail($sformatf("CCL flags count=%0d overflow=%b truncated=%b",dut.cc_count,dut.cc_overflow,dut.cc_truncated));
                    for(i=0;i<4;i=i+1)begin
                        if(dut.cc_boxes[i*64+:64]!==expected_boxes[i])fail($sformatf("CCL bbox mismatch slot=%0d got=%h expected=%h",i,dut.cc_boxes[i*64+:64],expected_boxes[i]));
                        if(dut.cc_areas[i*16+:16]!==expected_areas[i])fail($sformatf("CCL area mismatch slot=%0d",i));
                    end
                    ccl_commits=ccl_commits+1;scan_cycles=total_cycles-launch_cycle;
                end
                if(dut.state==dut.PCB_AUTO_START)auto_launch_cycle=total_cycles;
                if(`CORE.state==`CORE.PIXEL_STORE)begin
                    if(`CORE.roi_index!==roi_points)fail("ROI store sequence mismatch");
                    if(`CORE.captured_pixel!==roi[roi_points])fail($sformatf("ROI source byte mismatch index=%0d",roi_points));
                    roi_points=roi_points+1;
                end
                if(`CORE.state==`CORE.FEATURE_WRITE)begin
                    if(!`CORE.layer)begin
                        if(`CORE.activation!==expected_c1[`CORE.output_index] || `CORE.accumulator!==expected_a1[`CORE.output_index])
                            fail($sformatf("shared MAC/workspace Conv1 mismatch index=%0d",`CORE.output_index));
                        c1_points=c1_points+1;
                    end else begin
                        if(`CORE.activation!==expected_c2[`CORE.output_index] || `CORE.accumulator!==expected_a2[`CORE.output_index])
                            fail($sformatf("shared MAC/workspace Conv2 mismatch index=%0d",`CORE.output_index));
                        c2_points=c2_points+1;
                    end
                end
                if(`CORE.state==`CORE.ANOMALY_WRITE)begin
                    if(`CORE.anomaly_value!==expected_p[`CORE.spatial_index])fail("spatial residual mismatch");
                    p_points=p_points+1;
                end
                if(dut.ws_pcb_we && dut.ws_pcb_waddr>=8192)fail("workspace bank address out of range");
            end
        end
    end
    always @(negedge clk)begin
        pixel_valid<=0;
        if(rst_n && source_pending && response_delay==0 && response_enable)begin
            pixel_valid<=1;pixel_luma<=response_data;
        end
    end

    task load_fixture(input string name);
        string path;
        begin
            path={fixtures,"/",name,"/"};
            `include "pose7_fullpipeline_config.svh"
            $readmemh({path,"source_y.mem"},source_y);$readmemh({path,"roi.mem"},roi);
            $readmemh({path,"sample_x.mem"},sample_x);$readmemh({path,"sample_y.mem"},sample_y);
            $readmemh({path,"mask.mem"},expected_mask);$readmemh({path,"boxes.mem"},expected_boxes);$readmemh({path,"areas.mem"},expected_areas);
            $readmemh({path,"conv1.mem"},expected_c1);$readmemh({path,"conv2.mem"},expected_c2);
            $readmemh({path,"conv1_acc.mem"},expected_a1);$readmemh({path,"conv2_acc.mem"},expected_a2);
            $readmemh({path,"residual.mem"},expected_p);
        end
    endtask
    task launch;
        begin
            if(busy || frame_lock || source_pending)fail("new job admitted before safe owner release");
            @(negedge clk);start=1;job_id=job_id+1;job_active=1;launch_cycle=total_cycles;
            @(negedge clk);start=0;
        end
    endtask
    task run_frame(input string name);
        integer guard;
        begin
            case_name=name;check_enable=0;cancel_job=0;response_enable=1;
            load_fixture(name);scan_reads=0;roi_reads=0;stored_mask=0;streamed_mask=0;roi_points=0;
            c1_points=0;c2_points=0;p_points=0;ccl_commits=0;scan_cycles=0;auto_launch_cycle=0;
            check_enable=1;launch();guard=0;
            while(!done && guard<3000000)begin @(negedge clk);guard=guard+1;end
            if(!done)fail("full frame completion timeout");
            if(!valid || !pcb_checked || pcb_status!==expected_status || pcb_good!==(expected_status==0))fail("published PCB verdict/checked mismatch");
            if(x0!==expected_x0 || y0!==expected_y0 || x1!==expected_x1 || y1!==expected_y1)fail("published source bbox mismatch");
            if(result_job_id!==job_id || config_version!==32'h50533731 || confidence!==0)fail("fresh job metadata mismatch");
            if(`CORE.detail_score!==expected_score || `CORE.orientation_flip!==expected_flip[0] ||
               `CORE.thumb_mean0!==expected_mean0 || `CORE.thumb_mean180!==expected_mean180 ||
               `CORE.thumb_cost0!==expected_cost0 || `CORE.thumb_cost180!==expected_cost180 ||
               `CORE.peak_x!==expected_peak_x || `CORE.peak_y!==expected_peak_y)fail("orientation/score mismatch");
            if(scan_reads!=14400 || stored_mask!=14400 || streamed_mask!=14400 || ccl_commits!=1 ||
               roi_reads!=9216 || roi_points!=9216 || c1_points!=9216 || c2_points!=2304 || p_points!=576)
                fail($sformatf("coverage counts scan=%0d stored=%0d stream=%0d ccl=%0d roi=%0d/%0d c1=%0d c2=%0d p=%0d",scan_reads,stored_mask,streamed_mask,ccl_commits,roi_reads,roi_points,c1_points,c2_points,p_points));
            if(busy || frame_lock || source_pending || accepts!=replies)fail("completion retained frame/read owner");
            $display("POSE7_FULLPIPELINE_FRAME_PASS name=%s total_cycles=%0d scan_ccl_cycles=%0d auto_cycles=%0d abstract_us=%0f score=%0d status=%0d flip=%0d ccl_count=%0d",name,total_cycles-launch_cycle,scan_cycles,total_cycles-auto_launch_cycle,(total_cycles-launch_cycle)*0.008,`CORE.detail_score,pcb_status,`CORE.orientation_flip,dut.cc_count);
            frame_cases=frame_cases+1;check_enable=0;job_active=0;
            repeat(3)@(negedge clk);
        end
    endtask
    task run_cancel(input integer mode);
        integer guard,accepted_at_cancel;
        begin
            case_name=$sformatf("cancel_%0d",mode);check_enable=0;cancel_job=0;
            load_fixture("golden_good");response_enable=(mode!=0);launch();guard=0;
            if(mode==0)begin
                while(!source_pending && guard<1000)begin @(negedge clk);guard=guard+1;end
                if(!source_pending || dut.auto_owner)fail("CCL pending cancellation trigger missing");
            end else if(mode==1)begin
                while(!(dut.auto_owner && request && pixel_ready) && guard<1000000)begin @(negedge clk);guard=guard+1;end
                if(guard>=1000000)fail("ROI cancellation trigger timeout");
                response_enable=0;
                while(!source_pending)@(negedge clk);
            end else begin
                while(!(`CORE.layer==1 && `CORE.state==`CORE.TAP_READ) && guard<2000000)begin @(negedge clk);guard=guard+1;end
                if(guard>=2000000 || source_pending)fail("inference cancellation trigger missing");
            end
            // Wait a delta so the negedge response driver has already observed
            // the hold. A pulse that was presented before this point is valid.
            #1;cancel=1;cancel_job=1;accepted_at_cancel=accepts;
            repeat(8)begin @(negedge clk);#1;
                if(mode<2 && source_pending && (!busy || !frame_lock))fail("pending cancelled read released early");
                if(accepts!=accepted_at_cancel)fail("new read after cancellation fence");
            end
            response_enable=1;guard=0;
            while((busy || frame_lock || source_pending) && guard<1000)begin @(negedge clk);#1;guard=guard+1;end
            if(busy || frame_lock || source_pending)fail("safe cancellation drain did not release owner");
            if(done || valid || pcb_checked || pcb_good)fail("cancelled PCB exposed successful result");
            if(accepts!=replies)fail("cancelled reader accept/reply imbalance");
            cancel=0;cancel_job=0;job_active=0;
            repeat(3)@(negedge clk);
            $display("POSE7_FULLPIPELINE_CANCEL_PASS mode=%0d accepts=%0d replies=%0d drain_cycles=%0d",mode,accepts,replies,guard);
            cancel_cases=cancel_cases+1;
        end
    endtask
    initial begin
        case_name="reset";
        if(!$value$plusargs("FIXTURES=%s",fixtures))fail("missing +FIXTURES");
        repeat(4)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
        `include "pose7_fullpipeline_calls.svh"
        $display("POSE7_FULLPIPELINE_REGRESSION_PASS frames=%0d cancellation=%0d accepts=%0d replies=%0d latency=abstract_pixel_reader_NOT_DDR",frame_cases,cancel_cases,accepts,replies);
        $finish;
    end
endmodule
`undef CORE
