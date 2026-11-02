`timescale 1ns/1ps
module tb_pose7_core;
    `include "pose7_paths.svh"
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,start=0,cancel=0,frame_valid=1,model_valid=1;
    reg [31:0] job_id=0;
    reg [2:0] ccl_count=1;
    reg [255:0] ccl_boxes=0;
    reg ccl_overflow=0,ccl_truncated=0;
    wire busy,frame_lock,done,result_valid,no_target,bbox_valid;
    wire [1:0] status;
    wire [15:0] error,outline_support;
    wire [10:0] xmin,xmax,pixel_x;
    wire [9:0] ymin,ymax,pixel_y;
    wire [11:0] detail_score;
    wire pixel_request;
    reg pixel_ready=1,pixel_valid=0;
    reg [7:0] pixel_y8=0;
    wire ws_we,ws_wbank,ws_rd_bank;
    wire [14:0] ws_waddr,ws_rd_addr;
    wire [15:0] ws_wdata;
    reg [15:0] ws_rd_data;
    wire signed [15:0] mac_a;
    wire signed [7:0] mac_w;
    wire signed [23:0] mac_product_ext=mac_a*mac_w;
    wire [7:0] phase;
    wire [47:0] cycles;
    pcb_pose7_core #(.WEIGHTS_MEM(WEIGHTS_PATH),.BIASES_MEM(BIASES_PATH),
        .CENTRE_MEM(CENTRE_PATH),.TOLERANCE_MEM(TOLERANCE_PATH),.ORIENTATION_MEM(ORIENTATION_PATH),
        .PIXEL_TIMEOUT(64),.ABORT_TIMEOUT(128)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.cancel(cancel),.frame_valid(frame_valid),.model_valid(model_valid),
        .job_id(job_id),.I_ccl_count(ccl_count),.I_ccl_boxes(ccl_boxes),.I_ccl_overflow(ccl_overflow),.I_ccl_truncated(ccl_truncated),
        .busy(busy),.frame_lock(frame_lock),.done(done),.result_valid(result_valid),.no_target(no_target),
        .status(status),.error(error),.bbox_valid(bbox_valid),.xmin(xmin),.xmax(xmax),.ymin(ymin),.ymax(ymax),
        .detail_score(detail_score),.outline_support(outline_support),.pixel_request(pixel_request),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .pixel_ready(pixel_ready),.pixel_valid(pixel_valid),.pixel_y8(pixel_y8),
        .ws_we(ws_we),.ws_wbank(ws_wbank),.ws_waddr(ws_waddr),.ws_wdata(ws_wdata),
        .ws_rd_bank(ws_rd_bank),.ws_rd_addr(ws_rd_addr),.ws_rd_data(ws_rd_data),
        .mac_a(mac_a),.mac_w(mac_w),.mac_product_ext(mac_product_ext),.phase(phase),.cycles(cycles));

    reg [15:0] bank0[0:8191],bank1[0:8191];
    reg [7:0] roi[0:9215],expected_c1[0:9215],expected_c2[0:2303],expected_p[0:575];
    reg [31:0] expected_a1[0:9215],expected_a2[0:2303];
    reg check_enable=0,head_enable=0,reader_enable=1,response_enable=1;
    reg use_source_frame=0;
    reg [7:0] source_y[0:921599];
    reg source_pending=0;
    reg [7:0] response_data;
    integer response_delay=0,read_requests=0,write_words=0,c1_points=0,c2_points=0,p_points=0;
    integer last_read_count=0,scenario_count=0,roi_cases=0,head_cases=0;
    integer expected_flip,expected_mean0,expected_mean180,expected_cost0,expected_cost180;
    integer expected_score,expected_peak_x,expected_peak_y,expected_status;
    integer i;
    string vectors,case_name;

    task fail(input string message);
        begin
            $display("POSE7_FAIL case=%s time=%0t phase=%0d %s",case_name,$time,phase,message);
            $fatal(1,"pose7 regression failed");
        end
    endtask

    // The external workspace is exactly one synchronous read port and one
    // synchronous packed-word write port. There is no combinational RAM bypass.
    always @(posedge clk) begin
        if(ws_rd_bank) ws_rd_data<=bank1[ws_rd_addr];
        else ws_rd_data<=bank0[ws_rd_addr];
        if(ws_we) begin
            if(ws_waddr>=8192) fail("workspace write outside modeled bank");
            if(ws_wbank) bank1[ws_waddr]<=ws_wdata;
            else bank0[ws_waddr]<=ws_wdata;
            write_words=write_words+1;
            if(check_enable) begin
                if(dut.state==dut.PIXEL_STORE) begin
                    if(ws_wbank!==1'b1 || ws_waddr!==dut.roi_index/2 ||
                        ws_wdata!=={roi[dut.roi_index],roi[dut.roi_index-1]})
                        fail($sformatf("ROI packed word mismatch index=%0d data=%h",dut.roi_index,ws_wdata));
                end
            end
        end
        if(check_enable && dut.state==dut.FEATURE_WRITE) begin
            if(!dut.layer) begin
                if(dut.activation!==expected_c1[dut.output_index])
                    fail($sformatf("Conv1 mismatch index=%0d got=%0d expected=%0d",dut.output_index,dut.activation,expected_c1[dut.output_index]));
                if(dut.accumulator!==expected_a1[dut.output_index])
                    fail($sformatf("Conv1 accumulator mismatch index=%0d got=%0d expected=%0d",dut.output_index,$signed(dut.accumulator),$signed(expected_a1[dut.output_index])));
                c1_points=c1_points+1;
            end else begin
                if(dut.activation!==expected_c2[dut.output_index])
                    fail($sformatf("Conv2 mismatch index=%0d got=%0d expected=%0d",dut.output_index,dut.activation,expected_c2[dut.output_index]));
                if(dut.accumulator!==expected_a2[dut.output_index])
                    fail($sformatf("Conv2 accumulator mismatch index=%0d",dut.output_index));
                c2_points=c2_points+1;
            end
        end
        if((check_enable||head_enable) && dut.state==dut.ANOMALY_WRITE) begin
            if(dut.anomaly_value!==expected_p[dut.spatial_index])
                fail($sformatf("spatial residual mismatch index=%0d got=%0d expected=%0d",dut.spatial_index,dut.anomaly_value,expected_p[dut.spatial_index]));
            p_points=p_points+1;
        end
        if(rst_n && busy && !frame_lock) fail("busy job lost frame lock");
        if(rst_n && cancel && pixel_request) fail("cancel allowed a new source request");
        if(rst_n && dut.state==dut.DRAIN && pixel_request) fail("drain issued new source read");
    end

    // Variable delay source model holds accepted requests until their response.
    // Drives at negedge, so all DUT reads see stable valid/data at posedge.
    always @(posedge clk) begin
        if(!rst_n) begin source_pending<=0;response_delay<=0;read_requests=0;end
        else begin
            if(pixel_valid) source_pending<=0;
            if(source_pending && response_delay>0) response_delay<=response_delay-1;
            if(pixel_request && pixel_ready) begin
                if(source_pending) fail("second source request before prior response");
                if(!reader_enable) fail("unexpected source request while reader disabled");
                if(use_source_frame) begin
                    if(pixel_x>=1280 || pixel_y>=720) fail("source coordinate outside frame");
                    response_data<=source_y[pixel_y*1280+pixel_x];
                end else begin
                    if(pixel_x<8 || pixel_x>=104 || pixel_y<8 || pixel_y>=104)
                        fail($sformatf("ROI source coordinate (%0d,%0d) outside [8,104)",pixel_x,pixel_y));
                    if(check_enable && (pixel_x!==(8+(read_requests%96)) || pixel_y!==(8+(read_requests/96))))
                        fail("identity96 source sampling order mismatch");
                    response_data<=roi[(pixel_y-8)*96+pixel_x-8];
                end
                source_pending<=1;response_delay<=2+(read_requests%3);read_requests=read_requests+1;
            end
        end
    end
    always @(negedge clk) begin
        pixel_valid<=0;
        if(rst_n && source_pending && response_delay==0 && response_enable) begin
            pixel_valid<=1;pixel_y8<=response_data;
        end
    end

    task reset_core;
        begin
            check_enable=0;head_enable=0;
            @(negedge clk);rst_n=0;start=0;cancel=0;
            frame_valid=1;model_valid=1;ccl_count=1;ccl_overflow=0;ccl_truncated=0;
            ccl_boxes=0;ccl_boxes[63:0]={16'd13,16'd13,16'd1,16'd1};
            pixel_ready=1;reader_enable=1;response_enable=1;use_source_frame=0;
            repeat(3) @(negedge clk);rst_n=1;
            repeat(2) @(negedge clk);
        end
    endtask
    task launch;
        begin
            @(negedge clk);start=1;job_id=job_id+1;
            @(negedge clk);start=0;
        end
    endtask
    task await_done(input integer limit);
        integer n;
        begin
            n=0;
            while(!done && n<limit) begin @(negedge clk);n=n+1;end
            if(!done)fail($sformatf("task completion timeout limit=%0d",limit));
        end
    endtask
    task check_result;
        begin
            if(result_valid!==1 || bbox_valid!==1 || error!==0 || no_target!==0)
                fail($sformatf("invalid normal result valid=%b box=%b error=%h no_target=%b",result_valid,bbox_valid,error,no_target));
            if(status!==expected_status[1:0] || detail_score!==expected_score[11:0])
                fail($sformatf("status/score got %0d/%0d expected %0d/%0d",status,detail_score,expected_status,expected_score));
            if(dut.peak_x!==expected_peak_x[4:0] || dut.peak_y!==expected_peak_y[4:0]) fail("peak location mismatch");
            if(busy || frame_lock) fail("completed task retains ownership");
            if(outline_support!==0)fail("unvalidated defect marker nonzero");
        end
    endtask

    task run_roi(input string name,input integer flip,mean0,mean180,cost0,cost180,score,peakx,peaky,st);
        string path;
        begin
            case_name=name;reset_core();path={vectors,"/",name,"/"};
            $readmemh({path,"roi.mem"},roi);
            $readmemh({path,"conv1.mem"},expected_c1);$readmemh({path,"conv2.mem"},expected_c2);
            $readmemh({path,"conv1_acc.mem"},expected_a1);$readmemh({path,"conv2_acc.mem"},expected_a2);
            $readmemh({path,"residual.mem"},expected_p);
            expected_flip=flip;expected_mean0=mean0;expected_mean180=mean180;
            expected_cost0=cost0;expected_cost180=cost180;expected_score=score;
            expected_peak_x=peakx;expected_peak_y=peaky;expected_status=st;
            c1_points=0;c2_points=0;p_points=0;write_words=0;check_enable=1;
            launch();await_done(1500000);check_result();
            if(xmin!==8 || ymin!==8 || xmax!==104 || ymax!==104)fail("published source bbox mismatch");
            if(read_requests!=9216 || c1_points!=9216 || c2_points!=2304 || p_points!=576)
                fail($sformatf("counts source=%0d c1=%0d c2=%0d residual=%0d",read_requests,c1_points,c2_points,p_points));
            if(dut.orientation_flip!==flip[0] || dut.thumb_mean0!==mean0 || dut.thumb_mean180!==mean180 ||
                dut.thumb_cost0!==cost0 || dut.thumb_cost180!==cost180) fail("orientation phase/means/costs mismatch");
            $display("POSE7_ROI_PASS name=%s cycles=%0d source=%0d conv1=%0d conv2=%0d score=%0d flip=%0d",name,cycles,read_requests,c1_points,c2_points,detail_score,dut.orientation_flip);
            check_enable=0;roi_cases=roi_cases+1;
        end
    endtask

    task run_head(input integer score,input integer st,input integer peakx,input integer peaky);
        string path;
        begin
            case_name=$sformatf("head_score_%0d",score);reset_core();path={vectors,"/",case_name,"/"};
            $readmemh({path,"conv2.mem"},expected_c2);$readmemh({path,"residual.mem"},expected_p);
            for(i=0;i<1152;i=i+1)bank1[4608+i]={expected_c2[2*i+1],expected_c2[2*i]};
            expected_score=score;expected_status=st;expected_peak_x=peakx;expected_peak_y=peaky;
            head_enable=1;p_points=0;
            // Head-only injection avoids changing frozen ROM data or adding a
            // synthesis/debug port. All read latency and scoring RTL runs.
            @(negedge clk);dut.state=dut.ANOMALY_ADDR;dut.spatial_index=0;dut.anomaly_channel=0;dut.anomaly_max=0;
            await_done(30000);check_result();
            if(p_points!=576)fail("head residual count mismatch");
            $display("POSE7_HEAD_PASS score=%0d status=%0d",detail_score,status);
            head_enable=0;head_cases=head_cases+1;
        end
    endtask

    task run_quality(input integer which);
        begin
            case_name=$sformatf("quality_%0d",which);reset_core();reader_enable=0;
            case(which)
                0:ccl_count=0;
                1:ccl_overflow=1;
                2:ccl_boxes[63:0]={16'd13,16'd13,16'd1,16'd0};
                3:ccl_boxes[63:0]={16'd13,16'd160,16'd1,16'd1};
                4:ccl_boxes[63:0]={16'd90,16'd13,16'd1,16'd1};
                5:ccl_boxes[63:0]={16'd13,16'd13,16'd0,16'd1};
                6:ccl_boxes[63:0]={16'd13,16'd1,16'd1,16'd13};
                7:ccl_count=5;
                8:frame_valid=0;
                9:model_valid=0;
            endcase
            launch();await_done(20);
            if(which<8)begin
                if(result_valid!==1 || status!==2 || bbox_valid!==0)fail("quality reject did not REVIEW and clear box");
            end else if(result_valid!==0 || status!==3 || bbox_valid!==0)fail("bad frame/model not rejected");
            if(read_requests!=0 || busy || frame_lock)fail("quality reject read source or retained lock");
            $display("POSE7_SAFETY_PASS name=%s error=%h",case_name,error);scenario_count=scenario_count+1;
        end
    endtask

    task run_cancel(input integer which);
        integer writes_at_cancel,reads_at_cancel;
        begin
            case_name=$sformatf("cancel_%0d",which);reset_core();
            $readmemh({vectors,"/golden_good/roi.mem"},roi);
            if(which==0)pixel_ready=0;
            if(which==1 || which==2 || which==3)response_enable=0;
            launch();
            if(which==0)wait(pixel_request);
            else if(which<=3)wait(source_pending);
            else if(which==4)wait(dut.state==dut.THUMB_ADDR);
            else if(which==5)wait(dut.state==dut.ACCUMULATE && !dut.layer);
            else if(which==6)wait(dut.state==dut.ACCUMULATE && dut.layer);
            else if(which==7)wait(dut.state==dut.ANOMALY_ADDR);
            else if(which==8)wait(dut.state==dut.CONV_OPERAND);
            else if(which==9)wait(dut.state==dut.THUMB_OPERAND);
            else wait(dut.state==dut.HEAD_OPERAND);
            @(negedge clk);cancel=which!=2;start=which==2;
            writes_at_cancel=write_words;reads_at_cancel=read_requests;
            @(negedge clk);cancel=0;start=0;
            if(which==1 || which==2) begin
                repeat(5)begin
                    @(negedge clk);
                    if(!busy || !frame_lock || dut.state!=dut.DRAIN)fail("pending cancellation failed to retain drain ownership");
                end
                response_enable=1;
            end
            await_done(200);
            if(result_valid!==0 || bbox_valid!==0 || status!==3)fail("cancel published result");
            if(read_requests!=reads_at_cancel || write_words!=writes_at_cancel)fail("cancel emitted a new read/write");
            if(which==3)begin
                if(!busy || !frame_lock || dut.state!=dut.LOCKED || error!==16'h1003)fail("drain timeout failed to lock");
                repeat(4)@(negedge clk);
                if(!busy)fail("locked drain timeout self-released");
            end else if(busy || frame_lock)fail("cancel did not release after safe drain");
            $display("POSE7_SAFETY_PASS name=%s error=%h",case_name,error);scenario_count=scenario_count+1;
        end
    endtask

    task run_source_timeout(input integer which);
        begin
            case_name=$sformatf("source_timeout_%0d",which);reset_core();
            $readmemh({vectors,"/golden_good/roi.mem"},roi);
            if(which==0)pixel_ready=0;else response_enable=0;
            launch();await_done(200);
            if(!busy || !frame_lock || dut.state!=dut.LOCKED || result_valid!==0 || bbox_valid!==0 || status!==3)
                fail("source timeout failed to lock");
            if(error!==(which==0?16'h1001:16'h1002))fail("source timeout cause mismatch");
            @(negedge clk);start=1;cancel=1;
            repeat(3)@(negedge clk);
            if(!busy || !frame_lock || pixel_request)fail("locked source timeout accepted command");
            $display("POSE7_SAFETY_PASS name=%s error=%h",case_name,error);scenario_count=scenario_count+1;
        end
    endtask

    initial begin
        if(!$value$plusargs("VECTORS=%s",vectors))$fatal(1,"VECTORS plusarg required");
        case_name="initial";
        for(i=0;i<8192;i=i+1)begin bank0[i]=16'hxxxx;bank1[i]=16'hxxxx;end
        `include "pose7_case_calls.svh"
        for(integer quality=0;quality<10;quality=quality+1)run_quality(quality);
        for(integer scenario=0;scenario<11;scenario=scenario+1)run_cancel(scenario);
        run_source_timeout(0);run_source_timeout(1);
        // Successful complete inference after the final locked timeout proves
        // raw-reset reentry and discarded stale RAM cannot poison a new task.
        run_roi("golden_good",0,101,100,9697,17509,6,21,12,0);
        $display("POSE7_CORE_REGRESSION_PASS roi_cases=%0d head_cases=%0d safety_cases=%0d",roi_cases,head_cases,scenario_count);
        $finish;
    end
    initial begin #2000000000; $fatal(1,"global simulation timeout");end
endmodule
