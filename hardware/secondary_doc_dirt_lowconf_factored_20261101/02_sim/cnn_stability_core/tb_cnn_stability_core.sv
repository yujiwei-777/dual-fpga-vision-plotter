
`timescale 1ns/1ps
module tb_cnn_stability_core;
    localparam integer CASES = 27;
    reg clk=0; always #4 clk=~clk;
    reg rst_n=0, pixel_we=0, start=0;
    reg [11:0] pixel_addr=0;
    reg [23:0] pixel_rgb=0;
    wire busy,done,bg; wire [1:0] color_id,shape_id; wire [7:0] cc,sc;
    wire sw,f1w,f2w; wire [11:0] sa,f2a; wire [12:0] f1a,ra;
    wire [15:0] sd,f1d,f2d; wire [1:0] rs; wire [7:0] rd;
    wire signed [15:0] ma; wire signed [7:0] mw; wire signed [23:0] mp;
    cnn_core #(.WEIGHTS_MEM("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_doc_dirt_lowconf_factored_20261101/model/export/weights.mem"), .BIASES_MEM("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_doc_dirt_lowconf_factored_20261101/model/export/biases.mem"),
      .FC_CONF_SHIFT(8), .USE_SHARED_WORKSPACE(1), .EXTERNAL_MAC(1)) dut(
      .clk(clk),.rst_n(rst_n),.pixel_we(pixel_we),.pixel_addr(pixel_addr),.pixel_rgb(pixel_rgb),.start(start),
      .busy(busy),.done(done),.color_id(color_id),.shape_id(shape_id),.color_conf(cc),.shape_conf(sc),.background_reject(bg),
      .ws_shape_we(sw),.ws_shape_waddr(sa),.ws_shape_wdata(sd),.ws_f1_we(f1w),.ws_f1_waddr(f1a),.ws_f1_wdata(f1d),
      .ws_f2_we(f2w),.ws_f2_waddr(f2a),.ws_f2_wdata(f2d),.ws_rd_sel(rs),.ws_rd_addr(ra),.ws_rd_data(rd),
      .mac_a(ma),.mac_w(mw),.mac_product_ext(mp));
    vision_workspace workspace(.clk(clk),.purpose(2'd0),
      .cnn_shape_we(sw),.cnn_shape_waddr(sa),.cnn_shape_wdata(sd),.cnn_f1_we(f1w),.cnn_f1_waddr(f1a),.cnn_f1_wdata(f1d),
      .cnn_f2_we(f2w),.cnn_f2_waddr(f2a),.cnn_f2_wdata(f2d),.cnn_rd_sel(rs),.cnn_rd_addr(ra),.cnn_rd_data(rd),
      .pcb_we(1'b0),.pcb_wbank(1'b0),.pcb_waddr(15'd0),.pcb_wdata(16'd0),.pcb_rd_bank(1'b0),.pcb_rd_addr(15'd0),.pcb_rd_data());
    vision_shared_mac mac(.pcb_select(1'b0),.cnn_a(ma),.cnn_w(mw),.pcb_a(16'sd0),.pcb_w(8'sd0),
      .product(),.cnn_product(mp),.pcb_product());
    reg [23:0] pixels[0:CASES*4096-1];
    reg [7:0] shape_ref[0:CASES*4096-1],f1_ref[0:CASES*8192-1],f2_ref[0:CASES*4096-1];
    reg [31:0] results[0:CASES*10-1];
    integer c=0,i,cycles,f1count=0,f2count=0;
    initial begin
      $readmemh("pixels.mem",pixels); $readmemh("shape.mem",shape_ref);
      $readmemh("feature1.mem",f1_ref); $readmemh("feature2.mem",f2_ref); $readmemh("results.mem",results);
      repeat(5) @(negedge clk); rst_n=1;
      for(c=0;c<CASES;c=c+1) begin
        f1count=0;f2count=0; if(c==13) begin rst_n=0; repeat(3) @(negedge clk); rst_n=1; end
        for(i=0;i<4096;i=i+1) begin
          @(negedge clk); pixel_we=1;pixel_addr=i;pixel_rgb=pixels[c*4096+i];
        end
        @(negedge clk);pixel_we=0;
        @(negedge clk);start=1;
        @(negedge clk);start=0;
        cycles=0;
        while(!done&&cycles<3000000) begin @(negedge clk);cycles=cycles+1;end
        if(!done) $fatal(1,"TIMEOUT case=%0d state=%0d",c,dut.state);
        if(f1count!=4096||f2count!=2048) $fatal(1,"Feature write count case=%0d f1=%0d f2=%0d",c,f1count,f2count);
        for(i=0;i<3;i=i+1) begin
          if(dut.scores[i]!==results[c*10+i]) $fatal(1,"LOGIT case=%0d index=%0d rtl=%0d expected=%0d",c,i,$signed(dut.scores[i]),$signed(results[c*10+i]));
          if(dut.color_sum[i]!==results[c*10+3+i][18:0]) $fatal(1,"COLOR SUM case=%0d index=%0d",c,i);
        end
        if(color_id!==results[c*10+6][1:0]||shape_id!==results[c*10+7][1:0]||cc!==results[c*10+8][7:0]||sc!==results[c*10+9][7:0]||bg!==0)
          $fatal(1,"CLASS/CONF case=%0d got=%0d,%0d,%0d,%0d expected=%0d,%0d,%0d,%0d",c,color_id,shape_id,cc,sc,results[c*10+6],results[c*10+7],results[c*10+8],results[c*10+9]);
        $display("PASS CNN CASE %0d cycles=%0d logits=%0d,%0d,%0d class=%0d color_conf=%0d shape_conf=%0d",c,cycles,
          $signed(dut.scores[0]),$signed(dut.scores[1]),$signed(dut.scores[2]),(color_id-1)*3+shape_id,cc,sc);
      end
      $display("PASS ALL CNN REMOTE DETAIL cases=%0d",CASES);$finish;
    end
    always @(posedge clk) if(rst_n) begin
      if(sw && sd!=={shape_ref[c*4096+sa],shape_ref[c*4096+sa-1]}) $fatal(1,"SHAPE INPUT case=%0d address=%0d",c,sa);
      if(f1w) begin
        if(f1d!=={f1_ref[c*8192+f1a],f1_ref[c*8192+f1a-1]})
          $fatal(1,"FEATURE1 case=%0d address=%0d rtl=%h expected=%h",c,f1a,f1d,{f1_ref[c*8192+f1a],f1_ref[c*8192+f1a-1]});
        f1count=f1count+1;
      end
      if(f2w) begin
        if(f2d!=={f2_ref[c*4096+f2a],f2_ref[c*4096+f2a-1]})
          $fatal(1,"FEATURE2 case=%0d address=%0d rtl=%h expected=%h",c,f2a,f2d,{f2_ref[c*4096+f2a],f2_ref[c*4096+f2a-1]});
        f2count=f2count+1;
      end
    end
endmodule
