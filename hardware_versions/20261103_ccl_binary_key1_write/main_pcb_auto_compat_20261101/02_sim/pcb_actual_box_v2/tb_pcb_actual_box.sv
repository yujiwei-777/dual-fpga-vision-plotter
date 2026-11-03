`timescale 1ns/1ps
module tb_pcb_actual_box;
 reg S_125m_clk=0,S_hdmi_pixel_clk=0,S_eth_rst_n=0,S_hdmi_rst_n=0;
 // Slower simulation clocks permit an actual >2 s status hold without RTL edits.
 always #500 S_125m_clk=~S_125m_clk;
 always #1000 S_hdmi_pixel_clk=~S_hdmi_pixel_clk;
 reg S_mode_pcb_eth=0,S_mode_pcb_px=0,S_sw2_px_s2=1;
 reg S_aux_online=0,S_aux_ready=0,S_snap_capture_req=0,S_snap_cancel=0;
 reg S_aux_result_toggle=0,S_aux_result_valid=0;reg [511:0] S_aux_result_data=0;
 wire [2:0] S_pcb_status_eth,S_pcb_status_px;
 reg S_hdmi_vsync=0,S_show_vs_d=0;integer px_count=0;
 always @(posedge S_hdmi_pixel_clk)begin
   S_show_vs_d<=S_hdmi_vsync;
   if(px_count==39)begin px_count<=0;S_hdmi_vsync<=1;end
   else begin px_count<=px_count+1;S_hdmi_vsync<=0;end
 end
 reg key_n=1;wire S_pcb_key4_press,key_pressed,key_armed;integer presses=0;
 key4_pcb_oneshot #(.DEBOUNCE_CYCLES(5)) u_key(.clk(S_125m_clk),.rst_n(S_eth_rst_n),.key_n(key_n),.mode_active(S_mode_pcb_eth),.press_pulse(S_pcb_key4_press),.pressed(key_pressed),.armed(key_armed));
 always @(posedge S_125m_clk)if(S_pcb_key4_press)presses=presses+1;
 reg S_ovl_valid=0;reg [10:0] S_ovl_x0=0,S_ovl_x1=0,S_ovl_cx=0;
 reg [9:0] S_ovl_y0=0,S_ovl_y1=0,S_ovl_cy=0;reg [23:0] S_ovl_area=0;
 reg [1:0] S_ovl_color=0,S_ovl_shape=0;reg [3:0] S_ovl_class_id=0,S_ovl_conf_tens=0,S_ovl_conf_ones=0;reg [7:0] S_ovl_confidence=0;
 wire S_show_valid,S_show_remote,S_show_commit_toggle,S_show_pcb,S_show_pcb_checked,S_show_pcb_good;
 wire [10:0] S_show_x0,S_show_x1,S_show_cx;wire [9:0] S_show_y0,S_show_y1,S_show_cy;wire [23:0] S_show_area;
 wire [1:0] S_show_color,S_show_shape;wire [3:0] S_show_class_id,S_show_conf_tens,S_show_conf_ones;wire [7:0] S_show_confidence;
 // A stale Type18 is deliberately present while PCB uses Type8 coordinates.
 reg use_stale_multi=0;
 wire S_multi_px_valid=use_stale_multi;
 wire [511:0] S_multi_px_boxes={454'd0,10'd720,5'd0,11'd1280,6'd0,10'd0,5'd0,11'd0};
 wire [10:0] S_multi_cx=11'd640;
 wire [9:0] S_multi_cy=10'd360;
 wire S_summary_valid=use_stale_multi?1'b1:S_show_valid;
 wire [10:0] S_summary_x0=use_stale_multi?11'd0:S_show_x0,S_summary_x1=use_stale_multi?11'd1279:S_show_x1,S_summary_cx=use_stale_multi?11'd640:S_show_cx;
 wire [9:0] S_summary_y0=use_stale_multi?10'd0:S_show_y0,S_summary_y1=use_stale_multi?10'd719:S_show_y1,S_summary_cy=use_stale_multi?10'd360:S_show_cy;
`include "actual_top.vh"
 integer checks=0;
 task settle;begin repeat(250)@(negedge S_hdmi_pixel_clk);end endtask
 task expect_box(input bit v,input integer x0,y0,x1,y1);begin
  settle();checks=checks+1;
  if(S_box_valid!==v)$fatal(1,"valid expected=%0d actual=%0d status=%0d showpcb=%0d",v,S_box_valid,S_pcb_status_px,S_show_pcb);
  if(v&&{S_box_x0,S_box_y0,S_box_x1,S_box_y1}!={11'(x0),10'(y0),11'(x1),10'(y1)})
   $fatal(1,"actual coordinates mismatch %0d,%0d-%0d,%0d",S_box_x0,S_box_y0,S_box_x1,S_box_y1);
 end endtask
 task result(input bit valid,target,checked,good,input integer x0,y0,x1,y1);begin
  @(negedge S_125m_clk);S_aux_result_data=0;
  S_aux_result_data[96]=target;S_aux_result_data[97]=good;S_aux_result_data[98]=checked;
  S_aux_result_data[111:104]=1;S_aux_result_data[119:112]=1;S_aux_result_data[127:120]=80;
  S_aux_result_data[143:128]=x0;S_aux_result_data[159:144]=y0;S_aux_result_data[175:160]=x1;S_aux_result_data[191:176]=y1;
  S_aux_result_valid=valid;S_aux_result_toggle=~S_aux_result_toggle;
 end endtask
 task capture;begin @(negedge S_125m_clk);S_snap_capture_req=1;@(negedge S_125m_clk);S_snap_capture_req=0;end endtask
 task press;begin key_n=0;repeat(20)@(negedge S_125m_clk);end endtask
 task release_key;begin key_n=1;repeat(20)@(negedge S_125m_clk);end endtask
 initial begin
  repeat(10)@(negedge S_125m_clk);S_eth_rst_n=1;S_hdmi_rst_n=1;S_aux_online=1;S_aux_ready=1;settle();
  result(1,1,0,0,100,120,300,320);expect_box(1,100,120,299,319);
  S_mode_pcb_eth=1;S_mode_pcb_px=1;S_sw2_px_s2=0;use_stale_multi=1;
  expect_box(0,0,0,0,0);if(S_pcb_status_eth!=0)$fatal(1,"mode entry not READY");
  press();if(presses!=1)$fatal(1,"KEY4 first press missing");capture();expect_box(0,0,0,0,0);
  #2100000000;
  if(S_pcb_status_eth!=1||S_pcb_status_px!=1||presses!=1)$fatal(1,"SCANNING did not survive >2s/held KEY4");
  release_key();press();settle();if(S_pcb_status_eth!=1||S_pcb_status_px!=1)$fatal(1,"busy repress erased SCANNING");
  result(1,1,1,1,240,180,860,500);expect_box(1,240,180,859,499);if(S_pcb_status_px!=2)$fatal(1,"PASS missing");
  release_key();capture();expect_box(0,0,0,0,0);
  result(1,1,1,0,410,210,1010,610);expect_box(1,410,210,1009,609);if(S_pcb_status_px!=3)$fatal(1,"FAIL missing");
  capture();result(1,1,0,0,320,160,800,420);expect_box(1,320,160,799,419);if(S_pcb_status_px!=4)$fatal(1,"REVIEW missing");
  capture();result(0,0,0,0,0,0,0,0);expect_box(0,0,0,0,0);if(S_pcb_status_px!=5)$fatal(1,"NO TARGET missing");
  // Capture and new result on the same edge: clear first, latest payload retained.
  @(negedge S_125m_clk);S_snap_capture_req=1;
  S_aux_result_data[96]=1;S_aux_result_data[98]=1;S_aux_result_data[97]=1;
  S_aux_result_data[143:128]=90;S_aux_result_data[159:144]=80;S_aux_result_data[175:160]=450;S_aux_result_data[191:176]=360;
  S_aux_result_valid=1;S_aux_result_toggle=~S_aux_result_toggle;
  @(negedge S_125m_clk);S_snap_capture_req=0;
  settle();if(!S_show_valid||S_show_x0!=90||S_show_x1!=449)$fatal(1,"clear+result lost latest mailbox payload");
  result(1,1,1,1,90,80,450,360);expect_box(1,90,80,449,359);
  capture();repeat(3)@(negedge S_125m_clk);capture();result(1,1,1,1,530,270,920,590);expect_box(1,530,270,919,589);
  S_aux_online=0;expect_box(0,0,0,0,0);
  S_mode_pcb_eth=0;S_mode_pcb_px=0;use_stale_multi=0;S_sw2_px_s2=1;S_aux_online=1;settle();
  result(1,1,0,0,45,50,220,240);expect_box(1,45,50,219,239);
  S_sw2_px_s2=0;expect_box(0,0,0,0,0);
  $display("PASS PCB actual-box integration checks=%0d held/repress/2.1s/NO_TARGET/CDC_clear/mode/CNN/SW2",checks);$finish;
 end
 initial begin #(64'd2300000000);$fatal(1,"watchdog");end
endmodule
