`timescale 1ns/1ps
// Exercises the actual HXA decoded DISPATCH admission. Header and body CRC
// validation is upstream of this focused bench and is not bypassed in RTL.
module hxa_admission_case #(parameter PRESERVE=1)(output reg finished=0);
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,drain_lock=0,blocked_vision=0,blocked_scan=0;
 reg [511:0] body_value=0;reg [7:0] decoded_type=3;
 reg [15:0] decoded_count=1280,decoded_length=16;
 wire grbl_test_start;integer bits_mask,checks=0;
 hxa_secondary_link #(.PRESERVE_VISION_DRAIN(PRESERVE),.CAPABILITIES(8'hdf)) dut(
  .clk(clk),.rst_n(rst_n),.enable(1'b1),.phy_ready(1'b1),.board_mode(1'b0),
  .udp_busy(1'b0),.rx_valid(1'b0),.rx_data(8'd0),.rx_len(16'd0),.rx_error(1'b0),
  .wr_ready(1'b1),.wr_idle(1'b1),.rd_ready(1'b1),.rd_valid(1'b0),.rd_data(128'd0),
  .vision_busy(1'b0),.vision_done(1'b0),.vision_result(512'd0),.vision_result_type(8'd8),
  .vision_result_multibox(640'd0),.vision_maze_result(1792'd0),.v_rd_req(1'b0),.v_rd_byte_addr(21'd0),.v_drain_lock(drain_lock),
  .cfg_ready(1'b1),.cfg_apply_ack(1'b0),.cfg_apply_error(1'b0),.station_header(256'd0),.station_valid(1'b0),.station_config_version(32'd0),
  .job_status_valid(1'b0),.job_status_data(96'd0),.job_busy(1'b0),.grbl_test_start(grbl_test_start));
 task tick;begin @(posedge clk);#1;end endtask
 task check;input ok;input [255:0] msg;begin checks=checks+1;if(ok!==1'b1)begin $display("HXA_FAIL preserve=%0d mask=%0d type=%0d %0s",PRESERVE,bits_mask,decoded_type,msg);$fatal(1);end end endtask
 task reset_case;begin
  release dut.state;release dut.online;release dut.vision_read_outstanding;release dut.scan_outstanding;
  rst_n=0;repeat(3)tick;rst_n=1;repeat(3)tick;
  force dut.online=1'b1;
  force dut.vision_read_outstanding=blocked_vision;
  force dut.scan_outstanding=blocked_scan;
 end endtask
 task dispatch_case;begin
  force dut.saved_type=decoded_type;force dut.saved_flags=16'd0;force dut.saved_index=16'd0;
  force dut.saved_count=decoded_count;force dut.saved_length=decoded_length;
  force dut.saved_frame=32'd777;force dut.saved_ctrl=1'b0;force dut.body=body_value;
  @(negedge clk);force dut.state=6'd3;tick;
  if(decoded_type==3)check(dut.frame_active==(PRESERVE==0 || bits_mask==0),"FRAME_BEGIN admission gate");
  else check(grbl_test_start==(PRESERVE==0 || bits_mask==0),"Type20 admission gate");
  release dut.state;
 end endtask
 initial begin
  for(bits_mask=0;bits_mask<8;bits_mask=bits_mask+1)begin
   drain_lock=bits_mask[0];blocked_vision=bits_mask[1];blocked_scan=bits_mask[2];
   body_value=0;body_value[15:0]=1280;body_value[31:16]=720;body_value[39:32]=1;
   body_value[47:40]=1;body_value[95:64]=1843200;body_value[127:96]=42;
   decoded_type=3;decoded_count=1280;decoded_length=16;
   reset_case;dispatch_case;
   body_value=1;decoded_type=20;decoded_count=0;decoded_length=4;
   reset_case;dispatch_case;
  end
  $display("POSE7_HXA_ADMISSION_CASE_PASS preserve=%0d checks=%0d",PRESERVE,checks);finished=1;
 end
endmodule
module tb_pose7_hxa_admission;
 wire finished0,finished1;
 hxa_admission_case #(.PRESERVE(0)) legacy(finished0);
 hxa_admission_case #(.PRESERVE(1)) protected_case(finished1);
 initial begin wait(finished0&&finished1);$display("POSE7_HXA_ADMISSION_PASS cases=32");$finish;end
 initial begin #100000;$fatal(1,"HXA watchdog");end
endmodule
