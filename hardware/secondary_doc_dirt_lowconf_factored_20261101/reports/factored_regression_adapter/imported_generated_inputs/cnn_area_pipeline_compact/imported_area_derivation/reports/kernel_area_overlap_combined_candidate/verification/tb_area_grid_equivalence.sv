`timescale 1ns/1ps
module tb_area_grid_equivalence;
parameter integer AREA_BITS=24;
parameter integer BASE_AREA_BITS=AREA_BITS;
parameter integer AREA_SHIFT=0,COORD_SHIFT=0;
parameter integer EXTERNAL_CANDIDATE_READER=1;
parameter integer CONFIRM_RESULTS=3,HOLD_RESULTS=2,LOST_RESULTS=3;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,clear=0,start=0,compare_enable=0;
reg [2:0] input_count=0;
reg [511:0] source_boxes=0;
reg [511:0] bank[0:1],received[0:1];
reg [3:0] received_mask[0:1];
integer received_count[0:1];
wire [1:0] busy,done,uncertain,emit_begin,emit_valid;
wire [2:0] output_count[0:1];
wire [511:0] output_boxes[0:1];
wire [1:0] read_index[0:1],emit_slot[0:1];
wire [127:0] input_candidate_box[0:1],emit_box[0:1];
wire [511:0] kernel_bank[0:1];
genvar k;
generate for(k=0;k<2;k=k+1)begin:g_ports
 assign input_candidate_box[k]=bank[k][{read_index[k],7'b0}+:128];
 assign kernel_bank[k]=(EXTERNAL_CANDIDATE_READER!=0)?512'd0:bank[k];
 always @(posedge clk)begin
  if(!rst_n||clear)begin
   bank[k]<=0;received[k]<=0;received_mask[k]<=0;received_count[k]<=0;
  end else if(start&&!busy[k])begin
   bank[k]<=source_boxes;received[k]<=0;received_mask[k]<=0;received_count[k]<=0;
  end else if(emit_begin[k])begin
   // Independent destructive reuse verifies neither kernel rereads raw input.
   bank[k]<=0;received[k]<=0;received_mask[k]<=0;received_count[k]<=0;
  end else if(emit_valid[k])begin
   if(received_mask[k][emit_slot[k]]||emit_slot[k]!==received_count[k][1:0])
    $fatal(1,"bad serialized ordering instance%0d",k);
   if(^emit_box[k]===1'bx)$fatal(1,"unknown serial record instance%0d",k);
   received[k][{emit_slot[k],7'b0}+:128]<=emit_box[k];
   received_mask[k][emit_slot[k]]<=1;received_count[k]<=received_count[k]+1;
  end
 end
end endgenerate
cnn_result_stabilizer_baseline #(.AREA_BITS(BASE_AREA_BITS),.COORD_SHIFT(COORD_SHIFT),
 .EXTERNAL_CANDIDATE_READER(EXTERNAL_CANDIDATE_READER),
 .CONFIRM_RESULTS(CONFIRM_RESULTS),.HOLD_RESULTS(HOLD_RESULTS),.LOST_RESULTS(LOST_RESULTS)) baseline(
 .clk(clk),.rst_n(rst_n),.clear(clear),.start(start),.input_count(input_count),
 .input_boxes(kernel_bank[0]),.input_candidate_box(input_candidate_box[0]),.candidate_read_index(read_index[0]),
 .busy(busy[0]),.done(done[0]),.output_count(output_count[0]),.output_boxes(output_boxes[0]),.uncertain(uncertain[0]),
 .emit_begin(emit_begin[0]),.emit_valid(emit_valid[0]),.emit_slot(emit_slot[0]),.emit_box(emit_box[0]));
cnn_result_stabilizer #(.AREA_BITS(AREA_BITS),.AREA_SHIFT(AREA_SHIFT),.COORD_SHIFT(COORD_SHIFT),
 .EXTERNAL_CANDIDATE_READER(EXTERNAL_CANDIDATE_READER),
 .CONFIRM_RESULTS(CONFIRM_RESULTS),.HOLD_RESULTS(HOLD_RESULTS),.LOST_RESULTS(LOST_RESULTS)) candidate(
 .clk(clk),.rst_n(rst_n),.clear(clear),.start(start),.input_count(input_count),
 .input_boxes(kernel_bank[1]),.input_candidate_box(input_candidate_box[1]),.candidate_read_index(read_index[1]),
 .busy(busy[1]),.done(done[1]),.output_count(output_count[1]),.output_boxes(output_boxes[1]),.uncertain(uncertain[1]),
 .emit_begin(emit_begin[1]),.emit_valid(emit_valid[1]),.emit_slot(emit_slot[1]),.emit_box(emit_box[1]));
integer cycle_checks=0,serial_checks=0,bank_reuses=0,jobs=0,rejections=0;
reg rejection_active=0;
always @(negedge clk)begin
 #1;
 if(rst_n&&!clear&&compare_enable)begin
  if({busy[0],done[0],uncertain[0],emit_begin[0],emit_valid[0]}!==
     {busy[1],done[1],uncertain[1],emit_begin[1],emit_valid[1]})
   $fatal(1,"public handshake mismatch job%0d oldstate%0d newstate%0d",jobs,baseline.state,candidate.state);
  if(output_count[0]!==output_count[1]||output_boxes[0]!==output_boxes[1])
   $fatal(1,"public output mismatch job%0d",jobs);
  if(emit_valid[0])begin
   if(emit_slot[0]!==emit_slot[1]||emit_box[0]!==emit_box[1])$fatal(1,"serial output mismatch job%0d",jobs);
   serial_checks=serial_checks+1;
  end
  if(emit_begin[0])bank_reuses=bank_reuses+1;
  cycle_checks=cycle_checks+1;
 end
 if(rejection_active&&candidate.payload_we)$fatal(1,"malformed area wrote payload");
 if(!rst_n||clear)begin
  if(baseline.payload_we||candidate.payload_we||baseline.metadata_we||candidate.metadata_we||
     emit_begin||emit_valid)$fatal(1,"reset/clear leaked write or public emission");
 end
end
integer fd,scan,op,n,cycles,index=0;
reg [511:0] vector_boxes;
reg [1:0] done_seen;
task clear_history(input integer reset_it);begin
 @(negedge clk);compare_enable=0;start=1;
 if(reset_it)rst_n=0;else clear=1;
 repeat(2)@(negedge clk);
 if(busy||done||output_count[0]||output_count[1]||output_boxes[0]||output_boxes[1])
  $fatal(1,"history clear/reset did not hide stale output");
 rst_n=1;clear=0;start=0;
 repeat(2)@(negedge clk);
end endtask
task frame(input integer count,input [511:0] boxes,input integer reject_expected);begin
 @(negedge clk);compare_enable=!reject_expected;rejection_active=reject_expected;input_count=count;source_boxes=boxes;start=1;
 @(negedge clk);start=0;
 if(busy!==2'b11)$fatal(1,"frame not accepted");
 cycles=0;done_seen=0;
 while(done_seen!==2'b11&&cycles<2000)begin
  @(negedge clk);cycles=cycles+1;done_seen=done_seen|done;
 end
 if(cycles>=2000)$fatal(1,"frame timeout job%0d oldstate%0d newstate%0d",jobs,baseline.state,candidate.state);
 if(busy)$fatal(1,"done still busy");
 if(received[0]!==output_boxes[0]||received[1]!==output_boxes[1]||
    received_count[0]!==output_count[0]||received_count[1]!==output_count[1])
  $fatal(1,"serialized mailbox differs from final mailbox");
 if(reject_expected)begin
  if(output_count[1]!==0||output_boxes[1]!==0||!uncertain[1])
   $fatal(1,"malformed area was not explicitly rejected");
  rejections=rejections+1;
 end else jobs=jobs+1;
 rejection_active=0;repeat(3)@(negedge clk);
end endtask
reg [2047:0] vector_file;
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 if(candidate.PAYLOAD_BITS!==AREA_BITS-AREA_SHIFT+42-4*COORD_SHIFT||
    candidate.METRIC_BITS!==((AREA_BITS-AREA_SHIFT>13-COORD_SHIFT)?AREA_BITS-AREA_SHIFT:13-COORD_SHIFT))
  $fatal(1,"candidate area/metric width specialization wrong");
 if(!$value$plusargs("vectors=%s",vector_file))$fatal(1,"missing vector selector");
 fd=$fopen(vector_file,"r");if(!fd)$fatal(1,"missing vectors");
 while(!$feof(fd))begin
  scan=$fscanf(fd,"%d %d %h\n",op,n,vector_boxes);
  if(scan!=3)$fatal(1,"vector parse index%0d",index);
  if(op==1||op==2)clear_history(op==2);
  else frame(n,vector_boxes,op==3);
  index=index+1;
 end
 $fclose(fd);
 $display("PASS AREA_GRID_EQUIVALENCE area_bits=%0d shift=%0d coord=%0d external=%0d params=%0d/%0d/%0d vectors=%0d jobs=%0d rejected=%0d cycle_checks=%0d serial=%0d bank_reuses=%0d",AREA_BITS,AREA_SHIFT,COORD_SHIFT,EXTERNAL_CANDIDATE_READER,CONFIRM_RESULTS,HOLD_RESULTS,LOST_RESULTS,index,jobs,rejections,cycle_checks,serial_checks,bank_reuses);
 $finish;
end
initial begin #500000000;$fatal(1,"grid miter global timeout");end
endmodule
