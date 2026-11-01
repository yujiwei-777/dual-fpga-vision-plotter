`timescale 1ns/1ps
module tb_real_pcb_core;
  localparam integer SAMPLE_COUNT=15, PIXELS=96*96, C1=4, C2=4,
                     F1=48*48*C1, F2=24*24*C2, POOL=C2*16,
                     MAX_CYCLES=2500000;
  reg clk=0; always #4 clk=~clk;
  reg rst_n=0,start=0,pixel_we=0; reg [13:0] pixel_addr=0; reg [7:0] pixel_gray=0;
  wire busy,done; wire [1:0] class_id; wire [7:0] score; wire [15:0] margin;
  wire [15:0] saturation_count; wire ws_we,ws_wbank; wire [14:0] ws_waddr;
  wire [15:0] ws_wdata; wire ws_rd_bank; wire [14:0] ws_rd_addr; wire [15:0] ws_rd_data;
  wire signed [15:0] mac_a; wire signed [7:0] mac_w; wire signed [23:0] mac_product_ext;

  reg [7:0] input_pixels [0:SAMPLE_COUNT*PIXELS-1];
  reg signed [31:0] expected_logits [0:SAMPLE_COUNT*2-1];
  reg [15:0] expected_f1 [0:SAMPLE_COUNT*F1-1];
  reg [15:0] expected_f2 [0:SAMPLE_COUNT*F2-1];
  reg [15:0] expected_pool [0:SAMPLE_COUNT*POOL-1];
  integer sample_index,pixel_index,verify_index,timeout_cycles;
  integer best_value,second_value,expected_class,expected_score,expected_margin;
  integer pool_seen_count;
  assign mac_product_ext=mac_a*mac_w;
  vision_workspace workspace(
    .clk(clk),.purpose(2'd1),
    .cnn_shape_we(1'b0),.cnn_shape_waddr(12'd0),.cnn_shape_wdata(16'd0),
    .cnn_f1_we(1'b0),.cnn_f1_waddr(13'd0),.cnn_f1_wdata(16'd0),
    .cnn_f2_we(1'b0),.cnn_f2_waddr(12'd0),.cnn_f2_wdata(16'd0),
    .cnn_rd_sel(2'd0),.cnn_rd_addr(13'd0),.cnn_rd_data(),
    .pcb_we(ws_we),.pcb_wbank(ws_wbank),.pcb_waddr(ws_waddr),.pcb_wdata(ws_wdata),
    .pcb_rd_bank(ws_rd_bank),.pcb_rd_addr(ws_rd_addr),.pcb_rd_data(ws_rd_data));
  always @(negedge clk) begin
    if(rst_n && busy && dut.state==9 && dut.phase==0) begin
      if(dut.hindex>=POOL) $fatal(1,"invalid pool index=%0d",dut.hindex);
      if(dut.pool_value !== expected_pool[sample_index*POOL+dut.hindex])
        $fatal(1,"pool mismatch sample=%0d index=%0d got=%0d expected=%0d",sample_index,dut.hindex,dut.pool_value,expected_pool[sample_index*POOL+dut.hindex]);
      pool_seen_count=pool_seen_count+1;
    end
  end
  pcb_fullboard_spatial96 #(.USE_SHARED_WORKSPACE(1),.EXTERNAL_MAC(1),.HEAD_CLASSES(2),.C1_CHANNELS(C1),.C2_CHANNELS(C2),
      .C1_SHIFT(7),.C2_SHIFT(7),.HEAD_SHIFT(8),
      .WEIGHTS_MEM("model/selected/weights.mem"),
      .BIASES_MEM("model/selected/biases.mem")) dut(
      .clk(clk),.rst_n(rst_n),.start(start),.pixel_we(pixel_we),.pixel_addr(pixel_addr),.pixel_gray(pixel_gray),
      .busy(busy),.done(done),.class_id(class_id),.score(score),.margin(margin),.saturation_count(saturation_count),
      .ws_we(ws_we),.ws_wbank(ws_wbank),.ws_waddr(ws_waddr),.ws_wdata(ws_wdata),.ws_rd_bank(ws_rd_bank),
      .ws_rd_addr(ws_rd_addr),.ws_rd_data(ws_rd_data),.mac_a(mac_a),.mac_w(mac_w),.mac_product_ext(mac_product_ext));
  initial begin
    $readmemh("rtl_vectors/input_pixels.mem",input_pixels);
    $readmemh("rtl_vectors/expected_logits.mem",expected_logits);
    $readmemh("rtl_vectors/expected_f1.mem",expected_f1);
    $readmemh("rtl_vectors/expected_f2.mem",expected_f2);
    $readmemh("rtl_vectors/expected_pool.mem",expected_pool);
    repeat(4) @(negedge clk); rst_n=1;
    for(sample_index=0;sample_index<SAMPLE_COUNT;sample_index=sample_index+1) begin
      pool_seen_count=0;
      for(pixel_index=0;pixel_index<PIXELS;pixel_index=pixel_index+1) begin
        @(negedge clk); pixel_addr=pixel_index[13:0]; pixel_gray=input_pixels[sample_index*PIXELS+pixel_index]; pixel_we=1;
      end
      @(negedge clk); pixel_we=0; start=1; @(negedge clk); start=0; timeout_cycles=0;
      while(done!==1'b1 && timeout_cycles<MAX_CYCLES) begin @(negedge clk); timeout_cycles=timeout_cycles+1; end
      #1; if(done!==1'b1) $fatal(1,"timeout sample=%0d state=%0d phase=%0d",sample_index,dut.state,dut.phase);
      for(verify_index=0;verify_index<F1;verify_index=verify_index+1)
        if(workspace.bank0[verify_index]!==expected_f1[sample_index*F1+verify_index]) $fatal(1,"f1 mismatch sample=%0d addr=%0d",sample_index,verify_index);
      for(verify_index=0;verify_index<F2;verify_index=verify_index+1)
        if(workspace.bank1[verify_index]!==expected_f2[sample_index*F2+verify_index]) $fatal(1,"f2 mismatch sample=%0d addr=%0d got=%0d exp=%0d",sample_index,verify_index,workspace.bank1[verify_index],expected_f2[sample_index*F2+verify_index]);
      if($signed(dut.logits[0])!==$signed(expected_logits[sample_index*2]) || $signed(dut.logits[1])!==$signed(expected_logits[sample_index*2+1]))
        $fatal(1,"logit mismatch sample=%0d got=(%0d,%0d) exp=(%0d,%0d)",sample_index,$signed(dut.logits[0]),$signed(dut.logits[1]),expected_logits[sample_index*2],expected_logits[sample_index*2+1]);
      best_value=expected_logits[sample_index*2]; second_value=expected_logits[sample_index*2+1]; expected_class=0;
      if(second_value>best_value) begin best_value=expected_logits[sample_index*2+1]; second_value=expected_logits[sample_index*2]; expected_class=1; end
      expected_score=best_value<=0?0:best_value>255?255:best_value; expected_margin=best_value-second_value; if(expected_margin>65535) expected_margin=65535;
      if(class_id!==expected_class[1:0] || score!==expected_score[7:0] || margin!==expected_margin[15:0])
        $fatal(1,"head mismatch sample=%0d class=%0d/%0d score=%0d/%0d margin=%0d/%0d",sample_index,class_id,expected_class,score,expected_score,margin,expected_margin);
      if(pool_seen_count!=POOL*2) $fatal(1,"pool count sample=%0d got=%0d expected=%0d",sample_index,pool_seen_count,POOL*2);
      if(saturation_count!==16'd0) $fatal(1,"unexpected activation saturation");
      $display("BINARY_C4_4_SAMPLE_PASS index=%0d class=%0d score=%0d margin=%0d logits=(%0d,%0d) cycles=%0d",sample_index,class_id,score,margin,$signed(dut.logits[0]),$signed(dut.logits[1]),timeout_cycles);
    end
    $display("BINARY_C4_4_GOLDEN_PASS samples=%0d sat=%0d",SAMPLE_COUNT,saturation_count); $finish;
  end
endmodule
