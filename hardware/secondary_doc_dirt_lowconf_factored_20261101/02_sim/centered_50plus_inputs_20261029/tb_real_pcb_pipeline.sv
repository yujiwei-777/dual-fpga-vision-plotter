`timescale 1ns/1ps
`define CORE dut.g_pcb_fullboard_classifier.pcb_classifier
`define WS dut.g_shared_workspace.workspace
module tb_real_pcb_pipeline;
  localparam integer SAMPLES=9, PIXELS=9216, RAW_BYTES=1280*720*2;
  localparam integer F1=48*48*4, F2=24*24*4, POOL=64, MAX_CYCLES=2500000;
  reg clk=0; always #4 clk=~clk;
  reg rst_n=0,start=0;
  reg [31:0] job_id=0;
  wire word_req; wire [20:0] byte_addr;
  reg word_ready=0,word_valid=0;
  reg [127:0] word_data=0,pending_data=0;
  wire busy,done,valid,pcb_checked,pcb_good;
  wire [2:0] pcb_status,defect_count;
  wire [255:0] defect_boxes;
  wire [7:0] defect_kinds,confidence;
  wire [31:0] result_job_id;
  reg [7:0] raw_bytes [0:RAW_BYTES-1];
  reg [7:0] input_pixels [0:15*PIXELS-1];
  reg signed [31:0] expected_logits [0:29];
  reg [15:0] expected_f1 [0:15*F1-1],expected_f2 [0:15*F2-1],expected_pool [0:15*POOL-1];
  integer sample_index,pixel_count,loaded_count,pool_count,word_count,cycle_count=0;
  integer pending_delay=0,fd,bytes_read,k,a,expected_x,expected_y,elapsed_cycles;
  integer best_logit,runner,expected_class,expected_margin,expected_score,expected_status,verify_index;
  reg [127:0] response;

  vision_pipeline #(.EXTERNAL_READER(0),.LOCAL_CNN_ENABLE(0),.SHARED_WORKSPACE(1),
    .PCB_ENABLE(1),.PCB_FULLBOARD_SPATIAL96(1),.PCB_BINARY_CLASSES(1),.PCB_BINARY_MARGIN_MIN(32),
    .PCB_FULLBOARD_C1_CHANNELS(4),.PCB_FULLBOARD_C2_CHANNELS(4),
    .PCB_FULLBOARD_C1_SHIFT(7),.PCB_FULLBOARD_C2_SHIFT(7),.PCB_FULLBOARD_HEAD_SHIFT(8),
    .PCB_FIXED_WINDOW_ONLY(1),.PCB_FULL_X(158),.PCB_FULL_Y(140),.PCB_FULL_W(956),.PCB_FULL_H(412),
    .PCB_FULLBOARD_WEIGHTS_MEM("model/selected/weights.mem"),
    .PCB_FULLBOARD_BIASES_MEM("model/selected/biases.mem")) dut(
    .clk(clk),.rst_n(rst_n),.start(start),.purpose(2'd1),.teach_good(1'b0),.cancel(1'b0),.job_id(job_id),
    .word_req(word_req),.byte_addr(byte_addr),.word_ready(word_ready),.word_valid(word_valid),.word_data(word_data),
    .cfg_we(1'b0),.cfg_addr(15'd0),.cfg_data(8'd0),.cfg_commit(1'b0),
    .busy(busy),.done(done),.result_job_id(result_job_id),.config_version(),.color_id(),.shape_id(),
    .confidence(confidence),.valid(valid),.x0(),.x1(),.y0(),.y1(),.area(),
    .pcb_checked(pcb_checked),.pcb_good(pcb_good),.pcb_status(pcb_status),
    .defect_count(defect_count),.defect_boxes(defect_boxes),.defect_kinds(defect_kinds),
    .multi_count(),.multi_boxes(),.multi_flags(),.teach_success(),.teach_failed(),.teach_code(),.teach_commit(),.taught_station_header(),
    .ext_reader_ready(1'b0),.ext_reader_valid(1'b0),.ext_reader_rgb(24'd0),.ext_reader_luma(8'd0),
    .ext_reader_request(),.ext_reader_invalidate(),.ext_pixel_x(),.ext_pixel_y(),
    .yolo_pixel_valid(),.yolo_pixel_rgb(),.yolo_pixel_last(),.color_word_active());

  // Model only the 128-bit DDR user port. Acceptance can stall and data may
  // arrive with ready or several cycles later. No replacement pixel sampler.
  always @(negedge clk) begin
    cycle_count=cycle_count+1;
    word_ready=0;word_valid=0;
    if(rst_n) begin
      if(pending_delay>0) begin
        pending_delay=pending_delay-1;
        if(pending_delay==0) begin word_data=pending_data;word_valid=1;end
      end else if(word_req && (cycle_count%5)!=0) begin
        if(byte_addr[3:0]!=0 || byte_addr+15>=RAW_BYTES) $fatal(1,"bad DDR address=%0d",byte_addr);
        response=0;
        for(k=0;k<16;k=k+1) response[k*8+:8]=raw_bytes[byte_addr+k];
        word_ready=1;
        if((word_count%3)==0) begin word_valid=1;word_data=response;end
        else begin pending_data=response;pending_delay=(word_count%4)+1;end
        word_count=word_count+1;
      end
    end
  end

  always @(posedge clk) begin
    if(rst_n && dut.reader_request && dut.reader_ready) begin
      expected_x=158+((2*(pixel_count%96)+1)*956)/192;
      expected_y=140+((2*(pixel_count/96)+1)*412)/192;
      if(pixel_count>=PIXELS || dut.sample_x!==expected_x[10:0] || dut.sample_y!==expected_y[9:0])
        $fatal(1,"sampler mismatch case=%0d index=%0d x=%0d/%0d y=%0d/%0d",sample_index,pixel_count,dut.sample_x,expected_x,dut.sample_y,expected_y);
      a=(expected_y*1280+expected_x)*2;
      if(raw_bytes[a]!==input_pixels[sample_index*PIXELS+pixel_count]) $fatal(1,"source/reference input mismatch");
      pixel_count=pixel_count+1;
    end
    if(rst_n && dut.pcb_pixel_we) begin
      if(loaded_count>=PIXELS || dut.pcb_pixel_addr!==loaded_count[13:0] ||
         dut.pcb_pixel_gray!==input_pixels[sample_index*PIXELS+loaded_count])
        $fatal(1,"YUYV loader mismatch case=%0d index=%0d",sample_index,loaded_count);
      loaded_count=loaded_count+1;
    end
    if(rst_n && `CORE.busy && `CORE.state==9 && `CORE.phase==0) begin
      if(`CORE.pool_value!==expected_pool[sample_index*POOL+`CORE.hindex])
        $fatal(1,"pipeline pool mismatch sample=%0d index=%0d",sample_index,`CORE.hindex);
      pool_count=pool_count+1;
    end
  end

  initial begin
    $readmemh("rtl_vectors/input_pixels.mem",input_pixels);
    $readmemh("rtl_vectors/expected_logits.mem",expected_logits);
    $readmemh("rtl_vectors/expected_f1.mem",expected_f1);
    $readmemh("rtl_vectors/expected_f2.mem",expected_f2);
    $readmemh("rtl_vectors/expected_pool.mem",expected_pool);
    fd=$fopen("rtl_vectors/raw_frames.bin","rb");
    if(fd==0) $fatal(1,"cannot read source raw frames");
    repeat(4) @(negedge clk);rst_n=1;
    for(sample_index=0;sample_index<SAMPLES;sample_index=sample_index+1) begin
      bytes_read=$fread(raw_bytes,fd);
      if(bytes_read!=RAW_BYTES) $fatal(1,"short raw frame");
      pixel_count=0;loaded_count=0;pool_count=0;word_count=0;
      @(negedge clk);job_id=32'h10280000+sample_index;start=1;
      @(negedge clk);start=0;elapsed_cycles=0;
      while(done!==1'b1 && elapsed_cycles<MAX_CYCLES) begin @(negedge clk);elapsed_cycles=elapsed_cycles+1;end
      #1;
      if(done!==1'b1 || busy!==1'b0 || !valid || !pcb_checked || result_job_id!==job_id)
        $fatal(1,"pipeline timeout/invalid result sample=%0d state=%0d",sample_index,dut.state);
      if(pixel_count!=PIXELS || loaded_count!=PIXELS || pool_count!=POOL*2 || pending_delay!=0)
        $fatal(1,"count mismatch samples=%0d loaded=%0d pool=%0d",pixel_count,loaded_count,pool_count);
      for(verify_index=0;verify_index<F1;verify_index=verify_index+1)
        if(`WS.bank0[verify_index]!==expected_f1[sample_index*F1+verify_index]) $fatal(1,"pipeline f1 mismatch case=%0d index=%0d",sample_index,verify_index);
      for(verify_index=0;verify_index<F2;verify_index=verify_index+1)
        if(`WS.bank1[verify_index]!==expected_f2[sample_index*F2+verify_index]) $fatal(1,"pipeline f2 mismatch case=%0d index=%0d",sample_index,verify_index);
      if($signed(`CORE.logits[0])!==expected_logits[sample_index*2] || $signed(`CORE.logits[1])!==expected_logits[sample_index*2+1])
        $fatal(1,"pipeline logits mismatch sample=%0d",sample_index);
      best_logit=expected_logits[sample_index*2];runner=expected_logits[sample_index*2+1];expected_class=0;
      if(runner>best_logit) begin expected_class=1;runner=best_logit;best_logit=expected_logits[sample_index*2+1];end
      expected_margin=best_logit-runner;if(expected_margin>65535) expected_margin=65535;
      expected_score=best_logit<0?0:best_logit>255?255:best_logit;
      expected_status=expected_margin<32?2:expected_class;
      if(dut.pcb_cnn_class!==expected_class[1:0] || dut.pcb_cnn_score!==expected_score[7:0] || dut.pcb_cnn_margin!==expected_margin[15:0])
        $fatal(1,"pipeline class/score/margin mismatch");
      if(pcb_status!==expected_status[2:0] || pcb_good!==(expected_status==0) || confidence!==((expected_score*100+127)/255))
        $fatal(1,"publish mismatch status=%0d/%0d good=%0d conf=%0d",pcb_status,expected_status,pcb_good,confidence);
      if(defect_count!==(expected_status==1?3'd1:3'd0)) $fatal(1,"defect count mismatch");
      if(expected_status==1 && (defect_boxes[63:0]!=={16'd552,16'd1114,16'd140,16'd158} || defect_kinds[1:0]!==2'd1))
        $fatal(1,"defect box mismatch");
      $display("PCB_RAW_PIPELINE_SAMPLE_PASS sample=%0d class=%0d status=%0d margin=%0d samples=%0d words=%0d cycles=%0d",sample_index,expected_class,pcb_status,expected_margin,loaded_count,word_count,elapsed_cycles);
      repeat(3) @(negedge clk);
    end
    $fclose(fd);
    $display("PCB_RAW_PIPELINE_GOLDEN_PASS samples=%0d",SAMPLES);
    $finish;
  end
endmodule
`undef CORE
`undef WS
