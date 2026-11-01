`timescale 1ns/1ps
module tb_overlap_equivalence;
parameter integer COORD_SHIFT=0,AREA_BITS=32,EXTERNAL_CANDIDATE_READER=0;
parameter integer CONFIRM_RESULTS=3,HOLD_RESULTS=2,LOST_RESULTS=3;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,clear=0,start=0,load=0;
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
 assign input_candidate_box[k]=(EXTERNAL_CANDIDATE_READER!=0)?bank[k][{read_index[k],7'b0}+:128]:128'hdeadbeef;
 assign kernel_bank[k]=(EXTERNAL_CANDIDATE_READER!=0)?512'd0:bank[k];
 always @(posedge clk)begin
  if(!rst_n||clear)begin
   bank[k]<=0;received[k]<=0;received_mask[k]<=0;received_count[k]<=0;
  end else if(load)begin
   bank[k]<=source_boxes;received[k]<=0;received_mask[k]<=0;received_count[k]<=0;
  end else if(emit_begin[k])begin
   bank[k]<=0;received[k]<=0;received_mask[k]<=0;received_count[k]<=0;
  end else if(emit_valid[k])begin
   if(received_mask[k][emit_slot[k]]||emit_slot[k]!==received_count[k][1:0])
    $fatal(1,"bad serial ordering instance%0d",k);
   if(^emit_box[k]===1'bx)$fatal(1,"unknown serial record instance%0d",k);
   received[k][{emit_slot[k],7'b0}+:128]<=emit_box[k];
   received_mask[k][emit_slot[k]]<=1;received_count[k]<=received_count[k]+1;
  end
 end
end endgenerate
cnn_result_stabilizer_baseline #(.AREA_BITS(AREA_BITS),.COORD_SHIFT(COORD_SHIFT),
 .EXTERNAL_CANDIDATE_READER(EXTERNAL_CANDIDATE_READER),.CONFIRM_RESULTS(CONFIRM_RESULTS),
 .HOLD_RESULTS(HOLD_RESULTS),.LOST_RESULTS(LOST_RESULTS)) baseline(
 .clk(clk),.rst_n(rst_n),.clear(clear),.start(start),.input_count(input_count),
 .input_boxes(kernel_bank[0]),.input_candidate_box(input_candidate_box[0]),.candidate_read_index(read_index[0]),
 .busy(busy[0]),.done(done[0]),.output_count(output_count[0]),.output_boxes(output_boxes[0]),.uncertain(uncertain[0]),
 .emit_begin(emit_begin[0]),.emit_valid(emit_valid[0]),.emit_slot(emit_slot[0]),.emit_box(emit_box[0]));
cnn_result_stabilizer #(.AREA_BITS(AREA_BITS),.COORD_SHIFT(COORD_SHIFT),
 .EXTERNAL_CANDIDATE_READER(EXTERNAL_CANDIDATE_READER),.CONFIRM_RESULTS(CONFIRM_RESULTS),
 .HOLD_RESULTS(HOLD_RESULTS),.LOST_RESULTS(LOST_RESULTS)) candidate(
 .clk(clk),.rst_n(rst_n),.clear(clear),.start(start),.input_count(input_count),
 .input_boxes(kernel_bank[1]),.input_candidate_box(input_candidate_box[1]),.candidate_read_index(read_index[1]),
 .busy(busy[1]),.done(done[1]),.output_count(output_count[1]),.output_boxes(output_boxes[1]),.uncertain(uncertain[1]),
 .emit_begin(emit_begin[1]),.emit_valid(emit_valid[1]),.emit_slot(emit_slot[1]),.emit_box(emit_box[1]));
integer cycle_checks=0,serial_checks=0,bank_reuses=0,jobs=0,aborts=0,gold_checks=0;
always @(negedge clk)begin
 #1;
 if({busy[0],done[0],uncertain[0],emit_begin[0],emit_valid[0],output_count[0],output_boxes[0],read_index[0]}!==
    {busy[1],done[1],uncertain[1],emit_begin[1],emit_valid[1],output_count[1],output_boxes[1],read_index[1]})
   $fatal(1,"public cycle mismatch job%0d state%0d/%0d",jobs,baseline.state,candidate.state);
 if(baseline.state!==candidate.state)$fatal(1,"FSM cadence mismatch");
 if(emit_valid[0])begin
  if(emit_slot[0]!==emit_slot[1]||emit_box[0]!==emit_box[1])$fatal(1,"serial mismatch");
  serial_checks=serial_checks+1;
 end
 if(emit_begin[0])bank_reuses=bank_reuses+1;
 if(!rst_n||clear)begin
  if(baseline.payload_we||candidate.payload_we||baseline.metadata_we||candidate.metadata_we||emit_begin||emit_valid)
   $fatal(1,"reset/clear leaked write or emit");
 end
 cycle_checks=cycle_checks+1;
end
task wipe(input integer reset_it);begin
 @(negedge clk);start=1;load=0;
 if(reset_it)rst_n=0;else clear=1;
 repeat(2)@(negedge clk);
 if(busy||done||output_count[0]||output_count[1]||output_boxes[0]||output_boxes[1])$fatal(1,"clear/reset stale output");
 rst_n=1;clear=0;start=0;
 repeat(2)@(negedge clk);
end endtask
task launch(input integer count,input [511:0] boxes);begin
 @(negedge clk);input_count=count;source_boxes=boxes;load=1;
 @(negedge clk);load=0;start=1;
 @(negedge clk);start=0;
 if(busy!==2'b11)$fatal(1,"not accepted");
end endtask
task finish_frame;integer n;begin
 n=0;while(done!==2'b11&&n<2000)begin @(negedge clk);n=n+1;end
 if(n>=2000||busy)$fatal(1,"frame timeout");
 if(received[0]!==output_boxes[0]||received[1]!==output_boxes[1]||
    received_count[0]!==output_count[0]||received_count[1]!==output_count[1])$fatal(1,"serial/mailbox mismatch");
 jobs=jobs+1;repeat(3)@(negedge clk);
end endtask
function [511:0] four_boxes;
 integer i;reg [15:0] a,b;begin
  four_boxes=0;for(i=0;i<4;i=i+1)begin
   a=96+256*i;b=a+96;
   four_boxes[128*i+:128]={32'd10000,8'd0,8'd80,16'd2,16'd304,b,16'd208,a};
  end
 end
endfunction
integer fd,scan,op,n,exp_count,exp_uncertain,index=0,t,r,j,waits;
reg [511:0] boxes,exp_boxes;
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 fd=$fopen("vectors.txt","r");if(!fd)$fatal(1,"missing vectors");
 while(!$feof(fd))begin
  scan=$fscanf(fd,"%d %d %h %d %h %d\n",op,n,boxes,exp_count,exp_boxes,exp_uncertain);
  if(scan!=6)$fatal(1,"parse index%0d",index);
  if(op==1||op==2)wipe(op==2);
  else begin
   launch(n,boxes);
   if(op==4)begin repeat(10)@(negedge clk);wipe(0);end
   else begin
    if(op==3)begin repeat(6)@(negedge clk);start=1;@(negedge clk);start=0;end
    finish_frame;
    if(output_count[1]!==exp_count[2:0]||output_boxes[1]!==exp_boxes||uncertain[1]!==exp_uncertain[0])begin
     $display("expected %0d %h %0d",exp_count,exp_boxes,exp_uncertain);
     $display("actual %0d %h %0d",output_count[1],output_boxes[1],uncertain[1]);
     $fatal(1,"fresh integer gold mismatch index%0d",index);
    end
    gold_checks=gold_checks+1;
   end
  end
  index=index+1;
 end
 $fclose(fd);
 // Every reachable FSM state: clear and asynchronous reset both win over
 // simultaneous start, including before/at ownership transfer and RAM writes.
 for(r=0;r<2;r=r+1)for(t=0;t<28;t=t+1)begin
  wipe(1);
  if(t!=15&&t!=0)begin
   for(j=0;j<CONFIRM_RESULTS;j=j+1)begin launch(4,four_boxes());finish_frame;end
  end
  if(t!=0)begin
   launch(4,four_boxes());waits=0;
   while(baseline.state!=t&&waits<2000)begin @(negedge clk);waits=waits+1;end
   if(waits>=2000)$fatal(1,"state%0d not reached for abort",t);
  end
  // Assert now, before the next active edge of the selected state.
  start=1;if(r)rst_n=0;else clear=1;
  #1;if(emit_begin||emit_valid||baseline.payload_we||candidate.payload_we||
         baseline.metadata_we||candidate.metadata_we)$fatal(1,"abort edge not masked state%0d",t);
  repeat(2)@(negedge clk);rst_n=1;clear=0;start=0;
  repeat(3)@(negedge clk);
  if(busy||done||output_count[0]||output_count[1]||output_boxes[0]||output_boxes[1])$fatal(1,"abort stale output");
  aborts=aborts+1;
  launch(4,four_boxes());finish_frame;
 end
 $display("PASS OVERLAP_EQUIVALENCE coord=%0d area=%0d reader=%0d params=%0d/%0d/%0d vectors=%0d gold=%0d jobs=%0d cycles=%0d serial=%0d reuses=%0d aborts=%0d",COORD_SHIFT,AREA_BITS,EXTERNAL_CANDIDATE_READER,CONFIRM_RESULTS,HOLD_RESULTS,LOST_RESULTS,index,gold_checks,jobs,cycle_checks,serial_checks,bank_reuses,aborts);
 $finish;
end
initial begin #1000000000;$fatal(1,"global timeout");end
endmodule
