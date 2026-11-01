`timescale 1ns/1ps
module tb_cnn_stability_pipeline;
reg clk=0,rst_n=0,start=0,cancel=0,history_clear=0,cfg_commit=0;
always #4 clk=~clk;
reg [1:0] purpose=0,shape=2,color=1;
reg [7:0] score=200;
reg [2:0] candidate_count=1;
reg [1:0] multi_case=0;
reg [255:0] candidate_boxes={192'd0,16'd60,16'd80,16'd20,16'd40};
reg overflow=0;
reg explicit_area_enable=0;
reg [63:0] explicit_areas=0;
reg [31:0] job=0;
wire request,busy,done,valid;
wire [1:0] color_id,shape_id;
wire [7:0] confidence,flags;
wire [2:0] count;
wire [511:0] boxes;
wire [10:0] x0,x1;
wire [9:0] y0,y1;
wire pcb_checked,pcb_good;
wire [2:0] pcb_status;
wire [31:0] result_job;
integer checks=0,errors=0,completions=0,stabilizer_starts=0;
wire [7:0] fixture_score=multi_case==0 ? score :
  multi_case==1 ? (dut.box_index==0 ? 100 : dut.box_index==1 ? 200 : dut.box_index==2 ? 150 : 250) :
                  (dut.box_index==0 ? 250 : dut.box_index==1 ? 190 : dut.box_index==2 ? 140 : 100);
vision_pipeline #(.EXTERNAL_READER(1),.SHARED_WORKSPACE(0),
 .PCB_ENABLE(1),.PCB_FULLBOARD_SPATIAL96(1),.PCB_FIXED_WINDOW_ONLY(1),
 .PCB_BINARY_CLASSES(1)) dut(
 .clk(clk),.rst_n(rst_n),.start(start),.purpose(purpose),.teach_good(1'b0),
 .cancel(cancel),.job_id(job),.word_ready(1'b0),.word_valid(1'b0),.word_data(128'd0),
 .cfg_we(1'b0),.cfg_addr(15'd0),.cfg_data(8'd0),.cfg_commit(cfg_commit),
 .busy(busy),.done(done),.result_job_id(result_job),.color_id(color_id),.shape_id(shape_id),
 .confidence(confidence),.valid(valid),.x0(x0),.x1(x1),.y0(y0),.y1(y1),
 .pcb_checked(pcb_checked),.pcb_good(pcb_good),.pcb_status(pcb_status),
 .multi_count(count),.multi_boxes(boxes),.multi_flags(flags),
 .ext_reader_ready(1'b1),.ext_reader_valid(request),.ext_reader_rgb(24'hc02020),
 .ext_reader_luma(8'd90),.ext_reader_request(request),.history_clear(history_clear),
 .word_req(),.byte_addr(),.config_version(),.area(),.defect_count(),.defect_boxes(),
 .defect_kinds(),.teach_success(),.teach_failed(),.teach_code(),.teach_commit(),
 .taught_station_header(),.ext_reader_invalidate(),.ext_pixel_x(),.ext_pixel_y(),
 .yolo_pixel_valid(),.yolo_pixel_rgb(),.yolo_pixel_last(),.color_word_active());
wire reference_request;
wire [7:0] fixture_score_reference=multi_case==0 ? score :
  multi_case==1 ? (reference.box_index==0 ? 100 : reference.box_index==1 ? 200 : reference.box_index==2 ? 150 : 250) :
                  (reference.box_index==0 ? 250 : reference.box_index==1 ? 190 : reference.box_index==2 ? 140 : 100);
vision_pipeline_baseline #(.EXTERNAL_READER(1),.SHARED_WORKSPACE(0),
 .PCB_ENABLE(1),.PCB_FULLBOARD_SPATIAL96(1),.PCB_FIXED_WINDOW_ONLY(1),
 .PCB_BINARY_CLASSES(1)) reference(
 .clk(clk),.rst_n(rst_n),.start(start),.purpose(purpose),.teach_good(1'b0),
 .cancel(cancel),.job_id(job),.word_ready(1'b0),.word_valid(1'b0),.word_data(128'd0),
 .cfg_we(1'b0),.cfg_addr(15'd0),.cfg_data(8'd0),.cfg_commit(cfg_commit),
 .busy(),.done(),.result_job_id(),.color_id(),.shape_id(),
 .confidence(),.valid(),.x0(),.x1(),.y0(),.y1(),
 .pcb_checked(),.pcb_good(),.pcb_status(),
 .multi_count(),.multi_boxes(),.multi_flags(),
 .ext_reader_ready(1'b1),.ext_reader_valid(reference_request),.ext_reader_rgb(24'hc02020),
 .ext_reader_luma(8'd90),.ext_reader_request(reference_request),.history_clear(history_clear),
 .word_req(),.byte_addr(),.config_version(),.area(),.defect_count(),.defect_boxes(),
 .defect_kinds(),.teach_success(),.teach_failed(),.teach_code(),.teach_commit(),
 .taught_station_header(),.ext_reader_invalidate(),.ext_pixel_x(),.ext_pixel_y(),
 .yolo_pixel_valid(),.yolo_pixel_rgb(),.yolo_pixel_last(),.color_word_active());
always @(posedge clk) if(rst_n)begin
 if(done)completions<=completions+1;
 if(dut.stable_start)stabilizer_starts<=stabilizer_starts+1;
end

integer miter_cycles=0;
always @(posedge clk)begin
 #2;
 if(rst_n)begin
  miter_cycles=miter_cycles+1;
  if(dut.word_req !== reference.word_req)$fatal(1,"CYCLE_MITER word_req cycle=%0d dut=%h reference=%h",miter_cycles,dut.word_req,reference.word_req);
  if(dut.byte_addr !== reference.byte_addr)$fatal(1,"CYCLE_MITER byte_addr cycle=%0d dut=%h reference=%h",miter_cycles,dut.byte_addr,reference.byte_addr);
  if(dut.busy !== reference.busy)$fatal(1,"CYCLE_MITER busy cycle=%0d dut=%h reference=%h",miter_cycles,dut.busy,reference.busy);
  if(dut.done !== reference.done)$fatal(1,"CYCLE_MITER done cycle=%0d dut=%h reference=%h",miter_cycles,dut.done,reference.done);
  if(dut.result_job_id !== reference.result_job_id)$fatal(1,"CYCLE_MITER result_job_id cycle=%0d dut=%h reference=%h",miter_cycles,dut.result_job_id,reference.result_job_id);
  if(dut.config_version !== reference.config_version)$fatal(1,"CYCLE_MITER config_version cycle=%0d dut=%h reference=%h",miter_cycles,dut.config_version,reference.config_version);
  if(dut.color_id !== reference.color_id)$fatal(1,"CYCLE_MITER color_id cycle=%0d dut=%h reference=%h",miter_cycles,dut.color_id,reference.color_id);
  if(dut.shape_id !== reference.shape_id)$fatal(1,"CYCLE_MITER shape_id cycle=%0d dut=%h reference=%h",miter_cycles,dut.shape_id,reference.shape_id);
  if(dut.confidence !== reference.confidence)$fatal(1,"CYCLE_MITER confidence cycle=%0d dut=%h reference=%h",miter_cycles,dut.confidence,reference.confidence);
  if(dut.valid !== reference.valid)$fatal(1,"CYCLE_MITER valid cycle=%0d dut=%h reference=%h",miter_cycles,dut.valid,reference.valid);
  if(dut.x0 !== reference.x0)$fatal(1,"CYCLE_MITER x0 cycle=%0d dut=%h reference=%h",miter_cycles,dut.x0,reference.x0);
  if(dut.x1 !== reference.x1)$fatal(1,"CYCLE_MITER x1 cycle=%0d dut=%h reference=%h",miter_cycles,dut.x1,reference.x1);
  if(dut.y0 !== reference.y0)$fatal(1,"CYCLE_MITER y0 cycle=%0d dut=%h reference=%h",miter_cycles,dut.y0,reference.y0);
  if(dut.y1 !== reference.y1)$fatal(1,"CYCLE_MITER y1 cycle=%0d dut=%h reference=%h",miter_cycles,dut.y1,reference.y1);
  if(dut.area !== reference.area)$fatal(1,"CYCLE_MITER area cycle=%0d dut=%h reference=%h",miter_cycles,dut.area,reference.area);
  if(dut.pcb_checked !== reference.pcb_checked)$fatal(1,"CYCLE_MITER pcb_checked cycle=%0d dut=%h reference=%h",miter_cycles,dut.pcb_checked,reference.pcb_checked);
  if(dut.pcb_good !== reference.pcb_good)$fatal(1,"CYCLE_MITER pcb_good cycle=%0d dut=%h reference=%h",miter_cycles,dut.pcb_good,reference.pcb_good);
  if(dut.pcb_status !== reference.pcb_status)$fatal(1,"CYCLE_MITER pcb_status cycle=%0d dut=%h reference=%h",miter_cycles,dut.pcb_status,reference.pcb_status);
  if(dut.defect_count !== reference.defect_count)$fatal(1,"CYCLE_MITER defect_count cycle=%0d dut=%h reference=%h",miter_cycles,dut.defect_count,reference.defect_count);
  if(dut.defect_boxes !== reference.defect_boxes)$fatal(1,"CYCLE_MITER defect_boxes cycle=%0d dut=%h reference=%h",miter_cycles,dut.defect_boxes,reference.defect_boxes);
  if(dut.defect_kinds !== reference.defect_kinds)$fatal(1,"CYCLE_MITER defect_kinds cycle=%0d dut=%h reference=%h",miter_cycles,dut.defect_kinds,reference.defect_kinds);
  if(dut.multi_count !== reference.multi_count)$fatal(1,"CYCLE_MITER multi_count cycle=%0d dut=%h reference=%h",miter_cycles,dut.multi_count,reference.multi_count);
  if(dut.multi_boxes !== reference.multi_boxes)$fatal(1,"CYCLE_MITER multi_boxes cycle=%0d dut=%h reference=%h",miter_cycles,dut.multi_boxes,reference.multi_boxes);
  if(dut.multi_flags !== reference.multi_flags)$fatal(1,"CYCLE_MITER multi_flags cycle=%0d dut=%h reference=%h",miter_cycles,dut.multi_flags,reference.multi_flags);
  if(dut.teach_success !== reference.teach_success)$fatal(1,"CYCLE_MITER teach_success cycle=%0d dut=%h reference=%h",miter_cycles,dut.teach_success,reference.teach_success);
  if(dut.teach_failed !== reference.teach_failed)$fatal(1,"CYCLE_MITER teach_failed cycle=%0d dut=%h reference=%h",miter_cycles,dut.teach_failed,reference.teach_failed);
  if(dut.teach_code !== reference.teach_code)$fatal(1,"CYCLE_MITER teach_code cycle=%0d dut=%h reference=%h",miter_cycles,dut.teach_code,reference.teach_code);
  if(dut.teach_commit !== reference.teach_commit)$fatal(1,"CYCLE_MITER teach_commit cycle=%0d dut=%h reference=%h",miter_cycles,dut.teach_commit,reference.teach_commit);
  if(dut.taught_station_header !== reference.taught_station_header)$fatal(1,"CYCLE_MITER taught_station_header cycle=%0d dut=%h reference=%h",miter_cycles,dut.taught_station_header,reference.taught_station_header);
  if(dut.ext_reader_request !== reference.ext_reader_request)$fatal(1,"CYCLE_MITER ext_reader_request cycle=%0d dut=%h reference=%h",miter_cycles,dut.ext_reader_request,reference.ext_reader_request);
  if(dut.ext_reader_invalidate !== reference.ext_reader_invalidate)$fatal(1,"CYCLE_MITER ext_reader_invalidate cycle=%0d dut=%h reference=%h",miter_cycles,dut.ext_reader_invalidate,reference.ext_reader_invalidate);
  if(dut.ext_pixel_x !== reference.ext_pixel_x)$fatal(1,"CYCLE_MITER ext_pixel_x cycle=%0d dut=%h reference=%h",miter_cycles,dut.ext_pixel_x,reference.ext_pixel_x);
  if(dut.ext_pixel_y !== reference.ext_pixel_y)$fatal(1,"CYCLE_MITER ext_pixel_y cycle=%0d dut=%h reference=%h",miter_cycles,dut.ext_pixel_y,reference.ext_pixel_y);
  if(dut.yolo_pixel_valid !== reference.yolo_pixel_valid)$fatal(1,"CYCLE_MITER yolo_pixel_valid cycle=%0d dut=%h reference=%h",miter_cycles,dut.yolo_pixel_valid,reference.yolo_pixel_valid);
  if(dut.yolo_pixel_rgb !== reference.yolo_pixel_rgb)$fatal(1,"CYCLE_MITER yolo_pixel_rgb cycle=%0d dut=%h reference=%h",miter_cycles,dut.yolo_pixel_rgb,reference.yolo_pixel_rgb);
  if(dut.yolo_pixel_last !== reference.yolo_pixel_last)$fatal(1,"CYCLE_MITER yolo_pixel_last cycle=%0d dut=%h reference=%h",miter_cycles,dut.yolo_pixel_last,reference.yolo_pixel_last);
  if(dut.color_word_active !== reference.color_word_active)$fatal(1,"CYCLE_MITER color_word_active cycle=%0d dut=%h reference=%h",miter_cycles,dut.color_word_active,reference.color_word_active);
  if(dut.state !== reference.state)$fatal(1,"CYCLE_MITER state cycle=%0d dut=%h reference=%h",miter_cycles,dut.state,reference.state);
  if(dut.box_index !== reference.box_index)$fatal(1,"CYCLE_MITER box_index cycle=%0d dut=%h reference=%h",miter_cycles,dut.box_index,reference.box_index);
  if(dut.box_total !== reference.box_total)$fatal(1,"CYCLE_MITER box_total cycle=%0d dut=%h reference=%h",miter_cycles,dut.box_total,reference.box_total);
  if(dut.sample_index !== reference.sample_index)$fatal(1,"CYCLE_MITER sample_index cycle=%0d dut=%h reference=%h",miter_cycles,dut.sample_index,reference.sample_index);
  if(dut.purpose_q !== reference.purpose_q)$fatal(1,"CYCLE_MITER purpose_q cycle=%0d dut=%h reference=%h",miter_cycles,dut.purpose_q,reference.purpose_q);
  if(dut.map_bits_left !== reference.map_bits_left)$fatal(1,"CYCLE_MITER map_bits_left cycle=%0d dut=%h reference=%h",miter_cycles,dut.map_bits_left,reference.map_bits_left);
  if(dut.area_bits_left !== reference.area_bits_left)$fatal(1,"CYCLE_MITER area_bits_left cycle=%0d dut=%h reference=%h",miter_cycles,dut.area_bits_left,reference.area_bits_left);
  if(dut.map_job !== reference.map_job)$fatal(1,"CYCLE_MITER map_job cycle=%0d dut=%h reference=%h",miter_cycles,dut.map_job,reference.map_job);
  if(dut.raw_slot_order !== reference.raw_slot_order)$fatal(1,"CYCLE_MITER raw_slot_order cycle=%0d dut=%h reference=%h",miter_cycles,dut.raw_slot_order,reference.raw_slot_order);
  if(dut.insert_physical_slot !== reference.insert_physical_slot)$fatal(1,"CYCLE_MITER insert_physical_slot cycle=%0d dut=%h reference=%h",miter_cycles,dut.insert_physical_slot,reference.insert_physical_slot);
  if(dut.stable_raw_released !== reference.stable_raw_released)$fatal(1,"CYCLE_MITER stable_raw_released cycle=%0d dut=%h reference=%h",miter_cycles,dut.stable_raw_released,reference.stable_raw_released);
 end
end

task grid_job(input [255:0] b,input [15:0] a,input string label_text);
 integer ex0,ey0,ex1,ey1,ea;
 begin
  clear_history;
  @(negedge clk);purpose=0;multi_case=0;shape=2;score=200;candidate_count=1;overflow=0;
  candidate_boxes=b;explicit_area_enable=1;explicit_areas={48'd0,a};
  ex0=(b[8:0]*8)%2048;ey0=(b[23:16]*8)%1024;
  ex1=(b[40:32]*8)%2048;ey1=(b[55:48]*8)%1024;ea=a*64;
  launch;wait(dut.state==9);#1;
  check(dut.x0==ex0&&dut.y0==ey0&&dut.x1==ex1&&dut.y1==ey1&&dut.area==ea,label_text);
  finish_job;
 end
endtask
task mapping_boundary(input integer boundary);
 begin
  case(boundary)
   0:wait(dut.state==8);
   1:wait(dut.state==43&&dut.map_job==1);
   2:wait(dut.state==44&&dut.map_job==1&&dut.map_bits_left==20);
   3:wait(dut.state==44&&dut.map_job==1&&dut.map_bits_left==1);
   4:wait(dut.state==45&&dut.map_job==1);
   5:wait(dut.state==43&&dut.map_job==2);
   6:wait(dut.state==44&&dut.map_job==2&&dut.map_bits_left==1);
   7:wait(dut.state==45&&dut.map_job==2);
   8:wait(dut.state==35);
   9:wait(dut.state==36);
   10:wait(dut.state==37&&dut.area_bits_left==37);
   11:wait(dut.state==37&&dut.area_bits_left==1);
  endcase
 end
endtask
integer edge_case,edge_action,prior_completions;

task step;begin @(posedge clk);#1;end endtask
task check(input bit ok,input string message);begin
 checks=checks+1;
 if(!ok)begin errors=errors+1;$display("FAIL %s",message);end
 else $display("PASS %s",message);
end endtask
task launch;begin
 @(negedge clk);job=job+1;start=1;step;@(negedge clk);start=0;
end endtask
task finish_job;integer ticks;begin
 ticks=0;
 while(!done&&ticks<200000)begin step;ticks=ticks+1;end
 check(done&&result_job==job,"exactly one completed current job");
 check(!busy,"publish retires pipeline busy");
 check(valid==(count!=0)&&flags[0]==valid&&flags[7]==!valid,"Type18 flags and compatibility validity agree");
 if(valid)begin
  check(boxes[79:64]==(color_id-1)*3+shape_id&&boxes[87:80]==confidence,
        "Type18 primary and compatibility class/confidence agree");
  check(boxes[15:0]==x0&&boxes[31:16]==y0&&boxes[47:32]==x1&&boxes[63:48]==y1,
        "Type18 primary and compatibility bbox agree");
 end
 step;
end endtask
task ordinary(input [1:0] s,input [7:0] margin);begin
 @(negedge clk);purpose=0;shape=s;score=margin;candidate_count=1;overflow=0;
 launch;finish_job;
end endtask
task empty_frame(input bit ov);begin
 @(negedge clk);purpose=0;candidate_count=0;overflow=ov;
 launch;finish_job;
end endtask
task clear_history;begin
 @(negedge clk);history_clear=1;step;@(negedge clk);history_clear=0;step;
end endtask
integer before_count,before_starts,boundary_case;
reg [511:0] raw_snapshot;
reg [7:0] order_snapshot;
initial begin
 force dut.cc_ready=1'b1;force reference.cc_ready=1'b1;force dut.cc_busy=1'b0;force reference.cc_busy=1'b0;force dut.cc_done=1'b1;force reference.cc_done=1'b1;
 force dut.cc_overflow=overflow;force reference.cc_overflow=overflow;force dut.cc_count=candidate_count;force reference.cc_count=candidate_count;
 force dut.cc_boxes=candidate_boxes;force reference.cc_boxes=candidate_boxes;
 force dut.cc_areas=explicit_area_enable ? explicit_areas : ((multi_case!=0 ? 64'h0190012c00c80064 : 64'd1000));force reference.cc_areas=explicit_area_enable ? explicit_areas : ((multi_case!=0 ? 64'h0190012c00c80064 : 64'd1000));force dut.cc_truncated=1'b0;force reference.cc_truncated=1'b0;
 force dut.cnn_busy=1'b0;force reference.cnn_busy=1'b0;force dut.cnn_done=dut.cnn_start;force reference.cnn_done=reference.cnn_start;
 force dut.cnn_background_reject=1'b0;force reference.cnn_background_reject=1'b0;force dut.cnn_color=color;force reference.cnn_color=color;force dut.cnn_shape=shape;force reference.cnn_shape=shape;
 force dut.cnn_color_conf=8'd255;force reference.cnn_color_conf=8'd255;force dut.cnn_shape_conf=fixture_score;force reference.cnn_shape_conf=fixture_score_reference;
 force dut.pcb_cnn_done=dut.pcb_start;force reference.pcb_cnn_done=reference.pcb_start;force dut.pcb_cnn_busy=1'b0;force reference.pcb_cnn_busy=1'b0;
 force dut.pcb_cnn_class=2'd0;force reference.pcb_cnn_class=2'd0;force dut.pcb_cnn_score=8'd90;force reference.pcb_cnn_score=8'd90;
 force dut.pcb_cnn_margin=16'd300;force reference.pcb_cnn_margin=16'd300;force dut.pcb_cnn_sat=16'd0;force reference.pcb_cnn_sat=16'd0;
 repeat(4)step;rst_n=1;repeat(3)step;
 ordinary(2,200);check(!valid&&count==0,"first reliable result remains unconfirmed");
 ordinary(2,200);check(!valid&&count==0,"second reliable result remains unconfirmed");
 ordinary(2,200);check(valid&&count==1&&shape_id==2&&confidence==78,"third reliable result confirms cylinder");
 check(x0==320&&x1==640&&y0==160&&y1==480,"actual CCL-to-native coordinate mapping preserved");
 ordinary(3,19);check(valid&&shape_id==2&&confidence==0&&flags[6],"rejected cube argmax holds confirmed cylinder at zero confidence");
 ordinary(2,200);check(valid&&shape_id==2&&confidence==78,"reliable result immediately ends ambiguity hold");
 ordinary(3,200);check(valid&&shape_id==2&&confidence==0,"first conflicting reliable result cannot switch class");
 ordinary(3,200);check(valid&&shape_id==2&&confidence==0,"second conflicting reliable result cannot switch class");
 ordinary(3,200);check(valid&&shape_id==3&&confidence==78,"third consecutive reliable result switches class");
 ordinary(2,0);check(valid&&shape_id==3&&confidence==0,"first low result keeps prior confirmed class");
 ordinary(2,0);check(valid&&shape_id==3&&confidence==0,"second low result keeps prior confirmed class");
 ordinary(2,0);check(!valid&&count==0&&color_id==0&&shape_id==0,"third low result clears prior class");
 ordinary(2,200);ordinary(2,200);ordinary(2,200);
 empty_frame(0);check(!valid,"empty frame never emits ghost bbox");
 empty_frame(1);check(!valid&&flags[2],"overflow fails closed and ages history");
 empty_frame(0);ordinary(2,200);check(!valid,"three missing results require fresh confirmation");
 clear_history;
 ordinary(3,19);ordinary(3,19);ordinary(3,19);
 check(!valid,"low-margin raw argmax cannot establish new class");
 // Clear in actual stable busy state must not strand the publish handshake.
 @(negedge clk);shape=2;score=200;candidate_count=1;
 launch;
 wait(dut.stable_busy);@(negedge clk);history_clear=1;repeat(3)step;
 @(negedge clk);history_clear=0;finish_job;
 check(!valid,"mid-filter history clear restarts against empty history");
 ordinary(2,200);ordinary(2,200);check(valid,"pipeline can confirm after clear/reentry");
 // Clear on either side of publish cannot refill a just-invalidated cache.
 launch;wait(dut.state==63);@(negedge clk);history_clear=1;step;
 @(negedge clk);history_clear=0;finish_job;
 check(!valid&&count==0&&boxes==0&&confidence==0&&shape_id==0,
       "clear exactly at publish discards old confirmed snapshot");
 ordinary(2,200);ordinary(2,200);ordinary(2,200);check(valid,"reconfirmed before finish-edge clear");
 launch;wait(dut.state==33);@(negedge clk);history_clear=1;step;
 check(done&&!valid&&count==0&&boxes==0&&confidence==0&&shape_id==0,
       "clear exactly at completion discards old confirmed snapshot");
 @(negedge clk);history_clear=0;step;
 ordinary(2,200);ordinary(2,200);ordinary(2,200);
 // Cancellation aborts in-flight work; it cannot publish or keep old votes.
 before_count=completions;launch;repeat(50)step;
 @(negedge clk);cancel=1;step;
 check(!busy&&!done,"cancel clears current processing without completion");
 @(negedge clk);cancel=0;repeat(4)step;
 check(completions==before_count,"canceled job emits no late completion");
 ordinary(2,200);check(!valid,"cancelled frame cannot retain old confirmation votes");
 // Config commit invalidates history even when no frame is in flight.
 ordinary(2,200);ordinary(2,200);check(valid,"reconfirmed before configuration clear");
 @(negedge clk);cfg_commit=1;step;@(negedge clk);cfg_commit=0;
 ordinary(2,200);check(!valid,"configuration commit invalidates ordinary history");
 ordinary(2,200);ordinary(2,200);check(valid,"confirmed before destructive result-bank reuse");
 launch;wait(dut.stable_emit_begin);step;
 check(dut.stable_raw_released&&dut.multi_boxes==0&&dut.multi_count==0,
       "serial begin releases raw input and clears destination bank");
 @(negedge clk);history_clear=1;step;@(negedge clk);history_clear=0;finish_job;
 check(!valid&&count==0&&boxes==0,"clear after bank reuse completes empty without restarting destroyed input");
 ordinary(2,200);check(!valid,"post-reuse clear cannot manufacture confirmation votes");
 ordinary(2,200);ordinary(2,200);check(valid,"fresh inference confirms after reuse clear");
 launch;wait(dut.stable_emit_valid);step;
 check(dut.multi_boxes[79:64]==2,"serial first slot is committed into parent bank");
 @(negedge clk);history_clear=1;step;@(negedge clk);history_clear=0;finish_job;
 check(!valid&&count==0&&boxes==0,"clear after first serial slot discards partial commit");
 // PCB uses its original FSM and never invokes the ordinary stabilizer.
 before_starts=stabilizer_starts;
 @(negedge clk);purpose=1;repeat(3)step;launch;
 begin: pcb_finish integer ticks; ticks=0;
 while(!done&&ticks<200000)begin step;ticks=ticks+1;end
 check(done&&pcb_checked&&pcb_good&&pcb_status==0,"PCB good decision bypasses ordinary confirmation");
 end
 check(stabilizer_starts==before_starts,"PCB does not start ordinary stabilizer");step;
 ordinary(2,200);check(!valid,"PCB mode transition clears ordinary history");
 // Four real pipeline ROI passes exercise shared insertion/serial writes.
 clear_history;
 @(negedge clk);multi_case=1;candidate_count=4;shape=2;
 candidate_boxes={16'd30,16'd150,16'd10,16'd130,
                  16'd30,16'd110,16'd10,16'd90,
                  16'd30,16'd70,16'd10,16'd50,
                  16'd30,16'd30,16'd10,16'd10};
 launch;finish_job;check(count==0,"four candidates first confirmation is empty");
 launch;finish_job;check(count==0,"four candidates second confirmation is empty");
 launch;finish_job;
 check(count==4&&x0==1040&&x1==1200&&confidence==98,"four candidates serial commit selects largest-area primary");
 check(boxes[143:128]==720&&boxes[271:256]==400&&boxes[399:384]==80,
       "all four parent slots retain exact native coordinate identities");
 @(negedge clk);multi_case=2;launch;finish_job;
 check(count==4&&x0==1040&&confidence==39,
       "confidence reorder cannot replace visible primary after shared insertion writes");
 check(boxes[159:144]==80&&boxes[191:176]==240&&boxes[255:224]==19200&&
       boxes[383:352]==12800&&boxes[511:480]==6400,
       "four serial slots keep geometry and area after raw confidence reorder");
 // Additional four-target clear boundaries use nonidentity confidence order.
 // Public results are checked in both real pipeline implementations; no state
 // or final result is forced. Inference/CCL leaves remain the existing fixtures.
 clear_history;
 @(negedge clk);purpose=0;multi_case=1;candidate_count=4;shape=2;score=200;
 launch;finish_job;launch;finish_job;launch;finish_job;
 check(count==4&&confidence==98,"boundary fixture confirms four reordered candidates");

 // Clear during the final STORE, during INSERT and while START is stalled.
 for(boundary_case=0;boundary_case<3;boundary_case=boundary_case+1)begin
  launch;
  if(boundary_case==0)wait(dut.state==60&&dut.box_index==3);
  else if(boundary_case==1)wait(dut.state==61&&dut.box_index==3&&dut.insert_index==3);
  else wait(dut.state==78);
  @(negedge clk);history_clear=1;
  while(dut.state!=78)step;
  raw_snapshot=dut.multi_boxes;
  order_snapshot=dut.raw_slot_order;
  repeat(4)step;
  check(dut.state==78&&!dut.stable_start&&!dut.stable_busy&&!dut.stable_raw_released,
        "held history clear stalls at START without releasing raw ownership");
  check(dut.multi_boxes==raw_snapshot&&dut.multi_count==4,
        "STORE/INSERT/START history clear preserves completed raw candidate bank");
  check(dut.raw_slot_order==order_snapshot&&dut.raw_slot_order==8'h27,"nonidentity pointer map remains stable through history clear");
  @(negedge clk);history_clear=0;finish_job;
  check(count==0&&!valid,"clear release restarts against empty history");
  launch;finish_job;launch;finish_job;
  check(count==4&&confidence==98&&x0==1040,
        "four reordered candidates confirm after STORE/INSERT/START clear");
 end

 // Clear while kernel owns only reads, before any emit pulse is pending.
 launch;wait(dut.stable_busy);step;
 @(negedge clk);history_clear=1;raw_snapshot=dut.multi_boxes;
 order_snapshot=dut.raw_slot_order;
 repeat(3)step;
 check(!dut.stable_raw_released&&dut.multi_boxes==raw_snapshot&&dut.multi_count==4,
       "four-target pre-emit clear preserves raw bank for restart");
 check(dut.raw_slot_order==order_snapshot&&dut.raw_slot_order==8'h27,"nonidentity pointer map remains stable through history clear");
 @(negedge clk);history_clear=0;finish_job;
 check(count==0&&!valid,"four-target pre-emit clear completes first fresh observation");
 launch;finish_job;launch;finish_job;
 check(count==4,"four targets reconfirm after pre-emit clear");

 // emit_begin is pending, but the parent has not consumed its next edge.
 launch;wait(dut.stable_emit_begin);
 @(negedge clk);history_clear=1;raw_snapshot=dut.multi_boxes;
 order_snapshot=dut.raw_slot_order;
 check(!dut.stable_raw_released,"pending emit_begin has not transferred raw ownership");
 step;
 check(!dut.stable_raw_released&&dut.multi_boxes==raw_snapshot&&dut.multi_count==4,
       "same-edge clear masks pending emit_begin and preserves source bank");
 check(dut.raw_slot_order==order_snapshot&&dut.raw_slot_order==8'h27,"nonidentity pointer map remains stable through history clear");
 @(negedge clk);history_clear=0;finish_job;
 check(count==0&&!valid,"pending-begin clear restarts without rereading serialized output");
 launch;finish_job;launch;finish_job;
 check(count==4,"four targets reconfirm after pending-begin clear");

 // The final serial slot has committed: source ownership is irreversibly gone.
 launch;wait(dut.stable_emit_valid&&dut.stable_emit_slot==3);step;
 check(dut.stable_raw_released&&dut.multi_boxes[399:384]==80,
       "last serial slot commits before post-release clear");
 before_starts=stabilizer_starts;
 @(negedge clk);history_clear=1;step;
 @(negedge clk);history_clear=0;finish_job;
 check(count==0&&!valid&&boxes==0&&stabilizer_starts==before_starts,
       "clear after last slot publishes empty without restarting destroyed source");
 launch;finish_job;launch;finish_job;launch;finish_job;
 check(count==4,"four targets reconfirm after last-slot clear");

 // Kernel done is pending, before the parent consumes the done/count handshake.
 launch;wait(dut.stable_done);
 before_starts=stabilizer_starts;
 @(negedge clk);history_clear=1;step;
 @(negedge clk);history_clear=0;finish_job;
 check(count==0&&!valid&&boxes==0&&stabilizer_starts==before_starts,
       "clear at pending done publishes empty and cannot restart committed output");
 launch;finish_job;launch;finish_job;launch;finish_job;
 check(count==4,"four targets reconfirm after pending-done clear");

 // Destructive processing cancellation and reset clear ownership and pointers.
 before_count=completions;launch;wait(dut.stable_busy);
 @(negedge clk);cancel=1;step;
 check(!busy&&!done&&dut.multi_boxes==0&&dut.multi_count==0&&!dut.stable_raw_released,
       "four-target cancel clears raw bank and source ownership");
 check(dut.raw_slot_order==0&&dut.insert_physical_slot==0,"destructive reset clears indirect slot identities");
 @(negedge clk);cancel=0;repeat(4)step;
 check(completions==before_count,"four-target canceled task has no late completion");
 launch;finish_job;check(count==0,"fresh task after cancel needs first confirmation");
 launch;finish_job;launch;finish_job;check(count==4,"four targets reconfirm after cancel");

 before_count=completions;launch;wait(dut.stable_busy);
 @(negedge clk);rst_n=0;step;
 check(!busy&&!done&&dut.multi_boxes==0&&dut.multi_count==0&&!dut.stable_raw_released,
       "four-target reset clears raw bank and source ownership");
 check(dut.raw_slot_order==0&&dut.insert_physical_slot==0,"destructive reset clears indirect slot identities");
 repeat(3)step;@(negedge clk);rst_n=1;repeat(3)step;
 check(completions==before_count,"four-target reset task has no late completion");
 launch;finish_job;check(count==0,"fresh task after reset needs first confirmation");
 launch;finish_job;launch;finish_job;check(count==4,"four targets reconfirm after reset");
 check(errors==0,"all real pipeline/stabilizer integration assertions");
 // The original formal integration program has now run without removal.
 if(completions!=81||checks!=374)$fatal(1,"Original program changed jobs=%0d checks=%0d",completions,checks);
 $display("PASS ORIGINAL_81_JOBS_374_ASSERTIONS_PRESERVED");
 grid_job({192'd0,16'd90,16'd160,16'd0,16'd0},16'd14400,"full image exclusive endpoints and maximum legal area");
 grid_job({192'd0,16'd4,16'd4,16'd0,16'd0},16'd16,"top left minimum accepted dimensions");
 grid_job({192'd0,16'd90,16'd160,16'd86,16'd156},16'd16,"bottom right minimum accepted dimensions");
 grid_job({192'd0,16'd90,16'd83,16'd0,16'd79},16'd360,"narrow full-height component preserves ROI mapping");
 grid_job({192'd0,16'd47,16'd160,16'd43,16'd0},16'd640,"wide thin component preserves ROI mapping");
 // These two are deliberately nonphysical CCL fixtures, proving the exact
 // old stored-quotient truncation and all16 area bits, not detection quality.
 grid_job({192'd0,16'd255,16'd511,16'd128,16'd256},16'hffff,"high endpoint bits reproduce old11/10bit quotient truncation");
 grid_job({192'd0,16'd128,16'd256,16'd0,16'd0},16'd0,"endpoint overflow thresholds and zero area remain equivalent");

 // Change controlled CCL outputs while busy: every capture edge must remain
 // the original edge rather than relying on the real CCL's stable outputs.
 clear_history;
 @(negedge clk);purpose=0;multi_case=0;candidate_count=1;shape=2;score=200;
 candidate_boxes={192'd0,16'd24,16'd24,16'd4,16'd4};explicit_areas=100;
 launch;wait(dut.state==43&&dut.map_job==1);
 @(negedge clk);candidate_boxes={192'd0,16'd30,16'd40,16'd8,16'd8};explicit_areas=200;
 wait(dut.state==44&&dut.map_job==1&&dut.map_bits_left==2);
 @(negedge clk);candidate_boxes={192'd0,16'd70,16'd50,16'd8,16'd8};explicit_areas=250;
 wait(dut.state==43&&dut.map_job==2);
 @(negedge clk);candidate_boxes={192'd0,16'd80,16'd100,16'd20,16'd20};explicit_areas=300;
 wait(dut.state==9);#1;
 check(dut.x0==32&&dut.y0==32&&dut.x1==400&&dut.y1==560&&dut.area==6400,
       "lower area and upper inputs retain their distinct original capture edges");
 finish_job;

 // Interrupt before/after each public mapping commit and the first/last
 // serial wait cycles. No pipeline state or final result is forced.
 for(edge_action=0;edge_action<4;edge_action=edge_action+1)begin
  for(edge_case=0;edge_case<12;edge_case=edge_case+1)begin
   @(negedge clk);purpose=0;multi_case=0;candidate_count=1;shape=2;score=200;
   candidate_boxes={192'd0,16'd90,16'd160,16'd0,16'd0};explicit_areas=14400;
   prior_completions=completions;launch;mapping_boundary(edge_case);
   @(negedge clk);
   if(edge_action==0)begin
    cancel=1;repeat(2)step;
    check(!busy&&!done&&count==0,"mapping cancel clears pipeline without late result");
    @(negedge clk);cancel=0;repeat(4)step;
    check(completions==prior_completions,"mapping cancel does not complete aborted job");
   end else if(edge_action==3)begin
    rst_n=0;repeat(2)step;
    check(!busy&&!done&&count==0,"mapping reset clears pipeline without late result");
    @(negedge clk);rst_n=1;repeat(4)step;
    check(completions==prior_completions,"mapping reset does not complete aborted job");
   end else begin
    if(edge_action==1)history_clear=1;else cfg_commit=1;
    repeat(2)step;
    @(negedge clk);history_clear=0;cfg_commit=0;
    finish_job;
   end
  end
 end
 check(errors==0,"all added fixed mapping edge assertions");
 $display("PASS FIXED_GRID_PUBLIC_CYCLE_MITER cycles=%0d public_ports=37 controls=11 completed_jobs=%0d assertions=%0d",miter_cycles,completions,checks);

 if(errors)$fatal(1,"PIPELINE_STABILITY_FAIL checks=%0d errors=%0d",checks,errors);
 $display("PASS CNN_STABILITY_PIPELINE_ALL checks=%0d jobs=%0d",checks,completions);$finish;
end
initial begin #360000000;$fatal(1,"pipeline stability timeout");end
endmodule
