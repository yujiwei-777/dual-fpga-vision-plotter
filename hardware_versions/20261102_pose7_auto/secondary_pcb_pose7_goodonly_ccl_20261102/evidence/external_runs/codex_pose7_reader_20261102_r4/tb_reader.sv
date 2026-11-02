`timescale 1ns/1ps
module tb_pose7_real_reader;
 reg clk125=0;always #4 clk125=~clk125;
 reg ddr_clk=0;always #7 ddr_clk=~ddr_clk;
 reg rst125_n=0,ddr_rst_n=0,calibrated=0;
 reg vision_start=0,vision_cancel=0,vision_done=0,vision_job_cancel=0;
 reg [1:0] vision_purpose=0;
 reg normal_busy=0,copy_busy=0,copy_image_lock=0,pcb_frame_lock=0,key4_copy_reset=0;
 reg copy_reader_request=0,copy_reader_invalidate=0,normal_reader_request=0,normal_reader_invalidate=0;
 reg [10:0] copy_pixel_x=0,normal_pixel_x=0;
 reg [9:0] copy_pixel_y=0,normal_pixel_y=0;
 reg color_word_active=0,normal_rd_req=0;
 reg [20:0] normal_rd_addr=0;
 wire v_rd_req,v_rd_ready,v_rd_valid;
 wire [20:0] v_rd_addr;
 wire [127:0] v_rd_data;
 wire pixel_ready,pixel_valid,owner_copy,frame_locked,pixel_pending,vision_busy;
 wire [23:0] pixel_rgb;wire [7:0] pixel_y8;
 pose7_read_route_probe top_route(.*);

 reg vision_active=1,scanning=0,scan_outstanding=0,crc_read_request=0;
 reg [17:0] scan_word=0;
 wire rd_req,rd_ready,rd_valid,admission_safe,vision_pending;
 wire [20:0] rd_byte_addr;wire [127:0] rd_data;
 pose7_hxa_read_route_probe link_route(.clk(clk125),.rst_n(rst125_n),
  .vision_active(vision_active),.v_drain_lock(frame_locked),.scanning(scanning),
  .scan_outstanding(scan_outstanding),.crc_read_request(crc_read_request),.scan_word(scan_word),
  .v_rd_req(v_rd_req),.v_rd_byte_addr(v_rd_addr),.v_rd_ready(v_rd_ready),.v_rd_valid(v_rd_valid),.v_rd_data(v_rd_data),
  .rd_req(rd_req),.rd_byte_addr(rd_byte_addr),.rd_ready(rd_ready),.rd_valid(rd_valid),.rd_data(rd_data),
  .admission_safe(admission_safe),.vision_pending(vision_pending));
 wire [24:0] app_addr;wire [2:0] app_cmd;wire app_en,app_wdf_end,app_wdf_wren;
 wire [127:0] app_wdf_data;wire [15:0] app_wdf_mask;
 reg allow_command=1,allow_response=1,immediate=0;
 wire app_rdy=calibrated&&allow_command;
 reg delayed_valid=0;reg [127:0] delayed_data=0;
 integer generation=0,delay_left=0,held_generation=0;
 reg app_pending=0;reg [20:0] held_address=0;
 function automatic [127:0] word_for(input integer addr,input integer gen);
  begin for(integer k=0;k<16;k=k+1)word_for[k*8+:8]=(13*(addr+k)+17+47*gen)&255;end
 endfunction
 wire app_rd_valid=(immediate&&app_en&&app_rdy&&app_cmd==1)||delayed_valid;
 wire [127:0] app_rd_data=(immediate&&app_en&&app_rdy&&app_cmd==1)?word_for(app_addr*2,generation):delayed_data;
 hxa_ddr_store store(.clk(clk125),.rst_n(rst125_n),
  .wr_valid(1'b0),.wr_byte_addr(21'd0),.wr_data(128'd0),.wr_ready(),.wr_idle(),
  .rd_req(rd_req),.rd_byte_addr(rd_byte_addr),.rd_ready(rd_ready),.rd_valid(rd_valid),.rd_data(rd_data),
  .ddr_clk(ddr_clk),.ddr_rst_n(ddr_rst_n),.calibrated(calibrated),
  .app_addr(app_addr),.app_cmd(app_cmd),.app_en(app_en),.app_wdf_data(app_wdf_data),.app_wdf_end(app_wdf_end),
  .app_wdf_mask(app_wdf_mask),.app_wdf_wren(app_wdf_wren),.app_rdy(app_rdy),.app_wdf_rdy(1'b1),
  .app_rd_data_valid(app_rd_valid),.app_rd_data(app_rd_data));

 integer checks=0,cases=0,pixels=0,app_reads=0,client_reads=0,app_total=0,client_total=0;
 integer expected_addresses[0:255];
 integer saved_reads,saved_total,n;
 string case_name="initial";
 task fail(input string text);begin
  $display("POSE7_REAL_READER_FAIL case=%s t=%0t reader=%0d store=%0d %s",case_name,$time,top_route.u_shared_reader.state,store.state,text);
  $fatal(1,"real reader regression");
 end endtask
 task check(input bit condition,input string text);begin checks++;if(!condition)fail(text);end endtask
 task tick(input integer count);begin repeat(count)@(negedge clk125);end endtask
 task pass;begin cases++;$display("POSE7_REAL_READER_CASE_PASS name=%s",case_name);end endtask

 // This scoreboard crosses the two simulated clocks only in the bench.
 // The actual mailbox synchronizers/held data path run without replacement.
 always @(posedge clk125)begin
  if(!rst125_n)client_reads=0;
  else if(rd_req&&rd_ready)begin
   check(rd_byte_addr[3:0]==0&&rd_byte_addr<1843200,"client word address alignment/range");
   check(client_reads<256,"bench queue capacity");
   expected_addresses[client_reads]=rd_byte_addr;client_reads++;client_total++;
  end
 end
 always @(posedge ddr_clk)begin
  if(!ddr_rst_n)begin app_reads=0;app_pending=0;end
  else begin
   if(delayed_valid)app_pending=0;
   if(app_en&&app_rdy)begin
    check(app_cmd==1&&!app_wdf_wren,"read-only test emitted write");
    check(!app_pending,"more than one app request outstanding");
    check(app_reads<client_reads,"app command without accepted client request");
    check(app_addr*2==expected_addresses[app_reads],"byte to 16-bit vendor address conversion/order");
    app_reads++;app_total++;
    if(!immediate)begin
     held_address=app_addr*2;held_generation=generation;delay_left=3+(app_reads%5);app_pending=1;
    end
   end
  end
 end
 always @(negedge ddr_clk)begin
  delayed_valid=0;
  if(ddr_rst_n&&app_pending&&allow_response)begin
   if(delay_left==0)begin delayed_data=word_for(held_address,held_generation);delayed_valid=1;end
   else delay_left--;
  end
 end
 function automatic [7:0] clip(input integer value);
  begin if(value<0)clip=0;else if(value>255)clip=255;else clip=value;end
 endfunction
 task check_pixel(input integer xx,input integer yy);
  integer addr,base,lum,uu,vv,c,d,e;reg [23:0] rgb;
  begin
   addr=yy*2560+xx*2;base=(addr/4)*4;
   lum=(13*addr+17+47*generation)&255;
   uu=(13*(base+1)+17+47*generation)&255;vv=(13*(base+3)+17+47*generation)&255;
   c=lum-16;d=uu-128;e=vv-128;
   rgb={clip((298*c+409*e+128)>>>8),clip((298*c-100*d-208*e+128)>>>8),clip((298*c+516*d+128)>>>8)};
   check(pixel_valid&&pixel_y8==lum&&pixel_rgb===rgb,$sformatf("YUYV byte/odd RGB gotY=%0d wantY=%0d gotRGB=%h wantRGB=%h x=%0d y=%0d",pixel_y8,lum,pixel_rgb,rgb,xx,yy));
   $display("POSE7_REAL_READER_PIXEL generation=%0d x=%0d y=%0d actual_Y=%0d expected_Y=%0d actual_RGB=%06h expected_RGB=%06h",generation,xx,yy,pixel_y8,lum,pixel_rgb,rgb);
   pixels++;
  end
 endtask
 task request_pixel(input bit copy,input integer xx,input integer yy);
  begin
   n=0;while(!pixel_ready&&n<500)begin tick(1);n++;end
   check(pixel_ready,"reader ready watchdog");
   if(copy)begin copy_pixel_x=xx;copy_pixel_y=yy;copy_reader_request=1;end
   else begin normal_pixel_x=xx;normal_pixel_y=yy;normal_reader_request=1;end
   tick(1);copy_reader_request=0;normal_reader_request=0;
  end
 endtask
 task get_pixel(input bit copy,input integer xx,input integer yy);
  begin
   request_pixel(copy,xx,yy);n=0;
   while(!pixel_valid&&n<500)begin tick(1);n++;end
   check_pixel(xx,yy);tick(1);check(!pixel_valid,"pixel_valid not one cycle");
  end
 endtask
 task invalidate_reader(input bit copy);
  begin
   if(copy)copy_reader_invalidate=1;else normal_reader_invalidate=1;
   tick(1);copy_reader_invalidate=0;normal_reader_invalidate=0;
  end
 endtask
 task claim_doc;
  begin
   vision_cancel=0;vision_job_cancel=0;key4_copy_reset=0;vision_done=0;
   vision_purpose=2;vision_start=1;tick(1);vision_start=0;copy_busy=1;copy_image_lock=1;normal_busy=0;
   check(owner_copy,"document did not claim shared reader");
  end
 endtask
 task finish_doc;
  begin copy_busy=0;copy_image_lock=0;vision_done=1;tick(2);vision_done=0;check(!owner_copy&&!frame_locked,"document owner not released");end
 endtask
 task wait_app_pending;
  begin n=0;while(!app_pending&&n<500)begin tick(1);n++;end check(app_pending,"app pending watchdog");end
 endtask
 task doc_cancel_drain(input bit key4);
  begin
   case_name=key4?"KEY4_doc_drain_and_reentry":"explicit_doc_cancel_drain_and_reentry";
   claim_doc;invalidate_reader(1);allow_response=0;
   request_pixel(1,37,29);wait_app_pending;
   check(pixel_pending&&frame_locked,"doc accepted read not locked");
   saved_total=client_total;
   vision_cancel=1;vision_active=0;vision_job_cancel=!key4;key4_copy_reset=key4;
   copy_busy=0;copy_image_lock=0;vision_done=1;copy_reader_request=1;
   vision_purpose=0;vision_start=1;normal_reader_request=1;normal_pixel_x=57;normal_pixel_y=65;
   repeat(12)begin
    tick(1);check(owner_copy&&frame_locked&&vision_busy&&!admission_safe,"cancel released pending owner/frame");
    check(client_total==saved_total&&!pixel_valid,"cancel replayed request or fabricated response");
   end
   vision_start=0;vision_done=0;allow_response=1;
   n=0;while(!pixel_valid&&n<500)begin
    tick(1);n++;
    check(owner_copy&&frame_locked&&pixel_pending&&top_route.vision_purpose_q==2,
          "late response changed owner before old pixel retired");
   end
   check(owner_copy&&frame_locked&&pixel_pending&&top_route.vision_purpose_q==2,
         "late old pixel was delivered to a new owner/task");
   check(client_total==saved_total,"new normal owner read admitted before old pixel retired");
   check_pixel(37,29);copy_reader_request=0;normal_reader_request=0;
   tick(4);check(!owner_copy&&!frame_locked&&!pixel_pending&&!vision_pending,"drained response did not release owner");
   vision_cancel=0;vision_job_cancel=0;key4_copy_reset=0;vision_active=1;normal_busy=1;
   generation++;invalidate_reader(0);get_pixel(0,37,29);pass;
  end
 endtask

 initial begin
  tick(4);rst125_n=1;ddr_rst_n=1;tick(6);
  case_name="calibration_fences_requests";
  normal_busy=1;request_pixel(0,0,0);tick(12);
  check(client_total==0&&app_total==0&&!pixel_valid,"uncalibrated mailbox accepted request");
  calibrated=1;n=0;while(!pixel_valid&&n<500)begin tick(1);n++;end
  check_pixel(0,0);tick(2);pass;

  case_name="all_eight_Y_lanes_odd_even_cache";
  saved_reads=app_total;for(integer x=0;x<8;x++)get_pixel(0,x,0);
  check(app_total==saved_reads,"same-word pixels missed cache");pass;
  case_name="miss_boundaries_last_address_and_variable_latency";
  get_pixel(0,8,0);get_pixel(0,1279,719);get_pixel(0,0,1);
  for(integer i=0;i<20;i++)get_pixel(0,(i*61+3)%1280,(i*37+1)%720);
  check(app_reads==client_reads,"mailbox duplicated/lost command");pass;
  case_name="frame_invalidate_changes_same_word";
  generation++;saved_reads=app_total;invalidate_reader(0);get_pixel(0,1162,704);
  check(app_total==saved_reads+1,"frame invalidate kept stale cache");pass;

  case_name="app_command_backpressure_and_samecycle_app_response";
  immediate=1;allow_command=0;invalidate_reader(0);request_pixel(0,71,19);
  saved_reads=app_total;tick(18);check(app_total==saved_reads&&!pixel_valid,"command accepted despite backpressure");
  allow_command=1;n=0;while(!pixel_valid&&n<500)begin tick(1);n++;end check_pixel(71,19);tick(2);immediate=0;pass;

  case_name="ordinary_color_word_port_masks_pixel_reply";
  check(pixel_ready,"color owner switched with pixel pending");color_word_active=1;normal_rd_addr=320;normal_rd_req=1;
  n=0;while(!v_rd_ready&&n<500)begin tick(1);n++;end
  tick(1);normal_rd_req=0;n=0;while(!v_rd_valid&&n<500)begin tick(1);n++;end
  check(v_rd_valid&&v_rd_data===word_for(320,generation),"color direct word contents");
  check(!pixel_valid&&pixel_ready,"color word leaked into pixel decoder");tick(2);color_word_active=0;
  get_pixel(0,72,19);pass;

  case_name="document_owns_reader_ignores_live_purpose_and_color";
  claim_doc;color_word_active=1;normal_rd_req=1;normal_rd_addr=512;
  vision_purpose=0;vision_start=1;tick(1);vision_start=0;
  check(owner_copy,"busy document owner followed live purpose");
  invalidate_reader(1);get_pixel(1,91,45);normal_rd_req=0;color_word_active=0;finish_doc;pass;

  case_name="PCB_network_cancel_retains_inflight_response";
  pcb_frame_lock=1;normal_busy=1;invalidate_reader(0);allow_response=0;
  request_pixel(0,73,27);wait_app_pending;vision_cancel=1;vision_active=0;saved_total=client_total;
  repeat(12)begin tick(1);check(frame_locked&&vision_busy&&!admission_safe,"network cancel lost PCB lock");end
  allow_response=1;n=0;while(!pixel_valid&&n<500)begin tick(1);n++;end check_pixel(73,27);
  check(client_total==saved_total,"network cancel replayed read");tick(2);pcb_frame_lock=0;vision_cancel=0;vision_active=1;
  get_pixel(0,74,27);pass;

  doc_cancel_drain(0);doc_cancel_drain(1);

  case_name="CRC_read_owner_never_publishes_pixel";
  normal_busy=0;vision_active=0;scanning=1;scan_word=7;crc_read_request=1;
  n=0;while(!rd_ready&&n<500)begin tick(1);n++;end
  tick(1);crc_read_request=0;scan_outstanding=1;
  n=0;while(!rd_valid&&n<500)begin tick(1);n++;end
  check(rd_valid&&rd_data===word_for(112,generation),"CRC direct mailbox word");
  check(!v_rd_valid&&!pixel_valid,"CRC response leaked to vision");tick(2);scan_outstanding=0;scanning=0;vision_active=1;normal_busy=1;
  invalidate_reader(0);get_pixel(0,75,27);pass;

  case_name="unreturned_doc_response_locks_until_raw_reset";
  claim_doc;invalidate_reader(1);allow_response=0;request_pixel(1,99,49);wait_app_pending;
  vision_cancel=1;vision_job_cancel=1;vision_active=0;copy_busy=0;copy_image_lock=0;vision_done=1;
  repeat(32)begin tick(1);check(owner_copy&&frame_locked&&pixel_pending&&!admission_safe&&!pixel_valid,"missing response incorrectly released owner");end
  rst125_n=0;ddr_rst_n=0;vision_done=0;copy_reader_request=0;tick(5);
  check(!owner_copy&&!frame_locked&&!pixel_pending,"raw reset failed to clear owner");
  vision_cancel=0;vision_job_cancel=0;vision_purpose=0;vision_active=1;normal_busy=1;allow_response=1;generation++;
  rst125_n=1;ddr_rst_n=1;tick(8);get_pixel(0,99,49);pass;
  check(app_reads==client_reads,"final mailbox request/command totals differ");
  $display("POSE7_REAL_READER_PASS cases=%0d checks=%0d pixels=%0d client_words=%0d app_words=%0d clocks=8ns_14ns",cases,checks,pixels,client_total,app_total);
  $finish;
 end
 initial begin #10000000;$fatal(1,"real reader global watchdog");end
endmodule
