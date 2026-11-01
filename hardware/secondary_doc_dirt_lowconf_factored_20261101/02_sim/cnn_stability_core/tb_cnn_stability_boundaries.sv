
`timescale 1ns/1ps
module tb_cnn_stability_boundaries;
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

    integer checks=0, ticks;
    task classify;
      input signed [31:0] a,b,c;
      input [18:0] red,green,blue;
      input [1:0] ec,es;
      input [7:0] ecc,esc;
      begin
        @(negedge clk);
        dut.scores[0]=a;dut.scores[1]=b;dut.scores[2]=c;
        dut.color_sum[0]=red;dut.color_sum[1]=green;dut.color_sum[2]=blue;
        dut.state=4'd13;dut.busy=1;
        ticks=0;
        while(!done&&ticks<8) begin @(negedge clk);ticks=ticks+1;end
        if(!done||color_id!==ec||shape_id!==es||cc!==ecc||sc!==esc)
          $fatal(1,"Directed check %0d got color=%0d shape=%0d cc=%0d sc=%0d expected=%0d,%0d,%0d,%0d",checks,color_id,shape_id,cc,sc,ec,es,ecc,esc);
        checks=checks+1;
        $display("PASS CLASSIFY BOUNDARY %0d",checks);
        @(negedge clk);
      end
    endtask
    initial begin
      repeat(5) @(negedge clk);rst_n=1;
      // Exact public contracts: colors favor highest index, shapes lowest.
      classify(0,0,0, 0,0,0, 3,1,0,0);
      classify(-1,512,512, 100,100,0, 2,2,0,0);
      classify(-300,-20,-20, 0,256,256, 3,2,0,0);
      // Independent numeric expectations for shift8 and saturation, not a copy
      // of the implementation's sorting or shifting code.
      classify(511,0,-1, 256,0,0, 1,1,1,1);
      classify(512,0,-1, 0,512,0, 2,1,2,2);
      classify(130559,0,-1, 0,0,65279, 3,1,254,255);
      classify(130560,0,-1, 65280,0,0, 1,1,255,255);
      classify(131072,0,-1, 0,70000,0, 2,1,255,255);
      classify(-1,-513,-2000, 0,0,256, 3,1,1,2);
      classify(-2147483647,-2147483135,-2147483647, 20,20,20, 3,2,0,2);
      // Restore reset and classify again to check output-state recovery.
      @(negedge clk);rst_n=0;repeat(3) @(negedge clk);rst_n=1;
      classify(0,0,0, 0,0,0, 3,1,0,0);
      $display("PASS ALL CLASSIFY BOUNDARIES checks=%0d",checks);$finish;
    end
endmodule
