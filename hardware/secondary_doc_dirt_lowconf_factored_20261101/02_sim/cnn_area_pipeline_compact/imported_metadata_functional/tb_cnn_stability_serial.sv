`timescale 1ns/1ps
module tb_cnn_stability_serial;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,clear=0,start=0,load=0;
reg [2:0] input_count=0;
reg [511:0] load_boxes=0;
reg [511:0] shared_bank=0;
wire busy,done,uncertain,emit_begin,emit_valid;
wire [1:0] emit_slot;
wire [127:0] emit_box;
wire [2:0] output_count;
wire [511:0] output_boxes;
reg receiver_started=0;
reg [3:0] received_mask=0;
integer received_count=0,begin_edges=0,emit_edges=0,bank_reuse_checks=0;
wire [1:0] candidate_read_index;
wire [127:0] input_candidate_box=shared_bank[{candidate_read_index,7'b0}+:128];
cnn_result_stabilizer #(.AREA_BITS(22),.AREA_SHIFT(6),.COORD_SHIFT(3),.EXTERNAL_CANDIDATE_READER(1)) dut(.clk(clk),.rst_n(rst_n),.clear(clear),.start(start),
 .input_candidate_box(input_candidate_box),.candidate_read_index(candidate_read_index),
 .input_count(input_count),.input_boxes(512'd0),.busy(busy),.done(done),
 .output_count(output_count),.output_boxes(output_boxes),.uncertain(uncertain),
 .emit_begin(emit_begin),.emit_valid(emit_valid),.emit_slot(emit_slot),.emit_box(emit_box));
always @(posedge clk)begin
 if(!rst_n||clear)begin
  shared_bank<=0;receiver_started<=0;received_mask<=0;received_count<=0;begin_edges<=0;
 end else if(load)begin
  shared_bank<=load_boxes;receiver_started<=0;received_mask<=0;received_count<=0;begin_edges<=0;
 end else if(emit_begin)begin
  if(receiver_started||emit_valid)$fatal(1,"duplicate begin or begin/write overlap");
  // This is the production ownership transfer: destroy the raw candidates
  // before the kernel has finished selecting or publishing output records.
  shared_bank<=0;receiver_started<=1;received_mask<=0;received_count<=0;
  begin_edges<=begin_edges+1;bank_reuse_checks<=bank_reuse_checks+1;
 end else if(emit_valid)begin
  if(!receiver_started||received_mask[emit_slot]||emit_slot!==received_count[1:0])
   $fatal(1,"invalid serial ordering slot=%0d expected=%0d mask=%b",emit_slot,received_count,received_mask);
  case(emit_slot)
   0:shared_bank[127:0]<=emit_box;
   1:shared_bank[255:128]<=emit_box;
   2:shared_bank[383:256]<=emit_box;
   3:shared_bank[511:384]<=emit_box;
  endcase
  received_mask[emit_slot]<=1;received_count<=received_count+1;emit_edges<=emit_edges+1;
 end
end
integer fd,status,id,op,in_count,exp_count,exp_uncertain,n=0,cycles,checks=0,max_cycles=0;
reg [511:0] in_boxes,exp_boxes;
task clear_history;begin
 @(negedge clk);clear=1;start=1;
 // Payload has no meaning without emit_valid; clear must prevent every write.
 #1;if(emit_begin||emit_valid)$fatal(1,"clear did not mask serial strobes");
 @(negedge clk);clear=0;start=0;
 if(busy||done||output_count!=0||output_boxes!=0||uncertain||shared_bank!=0)
  $fatal(1,"clear failed vector %0d",id);
end endtask
task launch(input integer count,input [511:0] packed_boxes);begin
 @(negedge clk);input_count=count;load_boxes=packed_boxes;load=1;
 @(negedge clk);load=0;start=1;
 @(negedge clk);start=0;
 if(!busy)$fatal(1,"start not accepted");
end endtask
task wait_done;begin
 cycles=0;
 while(!done&&cycles<1500)begin @(negedge clk);cycles=cycles+1;end
 if(cycles>=1500)$fatal(1,"timeout %0d",id);
 if(cycles>max_cycles)max_cycles=cycles;
 if(begin_edges!=1||!receiver_started||received_count!==output_count||shared_bank!==output_boxes)
  $fatal(1,"serial receiver/mailbox mismatch vector%0d begin%0d count%0d/%0d serial%h mailbox%h",id,begin_edges,received_count,output_count,shared_bank,output_boxes);
end endtask
task seed;integer j;begin
 clear_history;
 for(j=0;j<3;j=j+1)begin
  launch(1,{384'd0,32'd10048,8'd0,8'd70,16'd2,16'd192,16'd192,16'd96,16'd96});wait_done;
 end
end endtask
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 fd=$fopen("vectors.txt","r");if(!fd)$fatal(1,"missing vectors");
 while(!$feof(fd))begin
  status=$fscanf(fd,"%d %d %d %h %d %h %d\n",id,op,in_count,in_boxes,exp_count,exp_boxes,exp_uncertain);
  if(status!=7)$fatal(1,"vector parse");
  if(op==1)clear_history;
  else if(op==2)begin
   @(negedge clk);rst_n=0;start=1;
   repeat(2)@(negedge clk);rst_n=1;start=0;
   if(busy||done||output_count!=0||output_boxes!=0||uncertain||shared_bank!=0)$fatal(1,"reset failed");
  end else begin
   launch(in_count,in_boxes);
   if(op==4)begin
    repeat(10)@(negedge clk);clear_history;
    repeat(8)@(negedge clk);
    if(done||busy||emit_begin||emit_valid)$fatal(1,"clear-busy stale event");
   end else begin
    if(op==3)begin repeat(6)@(negedge clk);start=1;@(negedge clk);start=0;end
    wait_done;
    if(busy||output_count!==exp_count[2:0]||output_boxes!==exp_boxes||uncertain!==exp_uncertain[0])
     $fatal(1,"integer gold mismatch vector %0d",id);
    checks=checks+1;
    repeat(8)begin @(negedge clk);if(done||busy||emit_begin||emit_valid)$fatal(1,"extra transaction %0d",id);end
   end
  end
  n=n+1;
 end
 $fclose(fd);
 // Abort at each side of the ownership transfer. No serial write is
 // allowed on an edge where clear wins, and an aborted task has no done.
 seed;launch(1,{384'd0,32'd10048,8'd0,8'd70,16'd2,16'd192,16'd192,16'd96,16'd96});
 while(!emit_begin)@(negedge clk);
 clear=1;#1;
 if(emit_begin||emit_valid)$fatal(1,"begin-edge clear leakage");
 @(negedge clk);clear=0;
 if(busy||done||shared_bank!=0||output_boxes!=0)$fatal(1,"begin-edge clear result");
 seed;launch(1,{384'd0,32'd10048,8'd0,8'd70,16'd2,16'd192,16'd192,16'd96,16'd96});
 while(!emit_valid)@(negedge clk);
 clear=1;#1;
 if(emit_begin||emit_valid)$fatal(1,"write-edge clear leakage");
 @(negedge clk);clear=0;
 if(busy||done||shared_bank!=0||output_boxes!=0)$fatal(1,"write-edge clear result");
 repeat(10)begin @(negedge clk);if(done||busy||emit_begin||emit_valid)$fatal(1,"post-clear stale event");end
 $display("PASS SERIAL_GOLD checks=%0d vectors=%0d emitted=%0d bank_reuses=%0d clear_boundaries=2 max_latency_cycles=%0d",checks,n,emit_edges,bank_reuse_checks,max_cycles);$finish;
end
initial begin #100000000;$fatal(1,"global timeout");end
endmodule
