`timescale 1ns/1ps
module tb_cnn_stability_metadata_atomic;
parameter integer AREA_BITS=32;
parameter integer EXTERNAL_CANDIDATE_READER=0;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,clear=0,start=0;
reg [2:0] input_count=0;
reg [511:0] input_boxes=0;
wire busy,done,uncertain,emit_begin,emit_valid;
wire [1:0] emit_slot;
wire [127:0] emit_box;
wire [2:0] output_count;
wire [511:0] output_boxes;
wire [1:0] candidate_read_index;
wire [127:0] input_candidate_box=(EXTERNAL_CANDIDATE_READER!=0)?
 input_boxes[{candidate_read_index,7'b0}+:128]:128'hdeadbeefcafef00d0123456789abcdef;
// External mode must work without the legacy bank input, exactly as a
// production shared reader. Default mode ignores the poisoned external word.
wire [511:0] kernel_bank=(EXTERNAL_CANDIDATE_READER!=0)?512'd0:input_boxes;
cnn_result_stabilizer #(.AREA_BITS(AREA_BITS),.AREA_SHIFT(6),.COORD_SHIFT(3),.EXTERNAL_CANDIDATE_READER(EXTERNAL_CANDIDATE_READER)) dut(
 .clk(clk),.rst_n(rst_n),.clear(clear),.start(start),
 .input_candidate_box(input_candidate_box),.candidate_read_index(candidate_read_index),
 .input_count(input_count),.input_boxes(kernel_bank),.busy(busy),.done(done),
 .output_count(output_count),.output_boxes(output_boxes),.uncertain(uncertain),
 .emit_begin(emit_begin),.emit_valid(emit_valid),.emit_slot(emit_slot),.emit_box(emit_box));
integer checks=0,boundaries=0,publications=0,max_cycles=0;
integer kind,target,reset_abort,j;
reg [dut.META_BITS-1:0] old_meta;
reg [dut.PAYLOAD_BITS-1:0] old_payload;
function [127:0] box(input integer i,input integer changed);
 reg [15:0] x0,x1,y0,y1,cls;
 reg [31:0] area;
 reg [7:0] confidence;
 begin
  x0=96+256*i;x1=x0+96;y0=208;y1=304;
  cls=2+2*i+changed;area=(1000+i+100*changed)<<6;confidence=72+changed;
  box={area,8'd0,confidence,cls,y1,x1,y0,x0};
 end
endfunction
function [511:0] four_boxes(input integer changed);
 integer i;begin
  four_boxes=0;for(i=0;i<4;i=i+1)four_boxes[128*i+:128]=box(i,changed);
 end
endfunction
always @(posedge clk)begin
 if(emit_valid)begin
  if(^emit_box===1'bx)$fatal(1,"unknown published word width=%0d",AREA_BITS);
  publications=publications+1;
 end
 if(!rst_n||clear)begin
  if(dut.metadata_we||dut.payload_we||emit_begin||emit_valid)
   $fatal(1,"reset/clear edge leaked RAM write or publication");
 end
end
task clear_history;begin
 @(negedge clk);clear=1;start=1;
 @(negedge clk);clear=0;start=0;
 if(busy||done||dut.track_used||output_count||output_boxes||uncertain)
  $fatal(1,"clear did not invalidate history");
end endtask
task launch(input integer count,input integer changed);begin
 @(negedge clk);input_count=count;input_boxes=four_boxes(changed);start=1;
 @(negedge clk);start=0;
 if(!busy)$fatal(1,"transaction was not accepted");
end endtask
task finish_frame(input integer expected);integer cycles,k;begin
 cycles=0;
 while(!done&&cycles<1500)begin @(negedge clk);cycles=cycles+1;end
 if(cycles>=1500)$fatal(1,"timeout waiting frame");
 if(cycles>max_cycles)max_cycles=cycles;
 if(output_count!==expected[2:0]||busy)$fatal(1,"stale streak expected%0d got%0d",expected,output_count);
 if(expected==0 && output_boxes!==0)$fatal(1,"empty observation leaked mailbox");
 if(expected==4)begin
  for(k=0;k<4;k=k+1)if(output_boxes[128*k+:128]!==box(3-k,0))
   $fatal(1,"wrong recovered class/geometry/confidence slot%0d got%h expected%h",k,output_boxes[128*k+:128],box(3-k,0));
 end
 checks=checks+1;
end endtask
task acquire_fresh;integer k;begin
 for(k=0;k<3;k=k+1)begin launch(4,0);finish_frame(k==2?4:0);end
end endtask
task wait_boundary(input integer mode,input integer track);integer cycles;begin
 cycles=0;
 while(!((dut.track_index==track)&&
  ((mode==0&&dut.state==dut.S_UPDATE_APPLY&&dut.update_is_new)||
   (mode==1&&dut.state==dut.S_UPDATE_APPLY&&!dut.update_is_new)||
   (mode==2&&dut.state==dut.S_UPDATE_SELECT&&dut.track_used[track]&&!dut.track_matched[track]))))begin
  @(negedge clk);cycles=cycles+1;
  if(cycles>=1500)$fatal(1,"missing atomic boundary mode%0d track%0d",mode,track);
 end
 if(!dut.metadata_we)$fatal(1,"target metadata write was not armed");
 if(mode!=2&&!dut.payload_we)$fatal(1,"target payload write was not armed");
 if(mode==2&&dut.payload_we)$fatal(1,"missing update unexpectedly wrote payload");
end endtask
task abort_at_boundary(input integer use_reset,input integer track);begin
 old_meta=dut.metadata_ram[track];old_payload=dut.track_payload[track];
 if(use_reset)rst_n=0;else clear=1;
 start=1;#1;
 if(dut.metadata_we||dut.payload_we||emit_begin||emit_valid)$fatal(1,"abort failed to mask atomic side effects");
 @(posedge clk);#1;
 if(dut.metadata_ram[track]!==old_meta||dut.track_payload[track]!==old_payload)
  $fatal(1,"abort changed a RAM word reset%0d track%0d",use_reset,track);
 if(busy||done||dut.track_used||dut.visible||output_count||output_boxes||uncertain)
  $fatal(1,"abort did not invalidate output metadata");
 @(negedge clk);rst_n=1;clear=0;start=0;
 repeat(3)begin @(negedge clk);if(busy||done||emit_begin||emit_valid)$fatal(1,"spurious post-abort event");end
 boundaries=boundaries+1;
end endtask
initial begin
 repeat(3)@(negedge clk);rst_n=1;
 // Actual power-up RAM is unknown; validity must hide it until three NEW results.
 acquire_fresh;
 for(kind=0;kind<3;kind=kind+1)begin
  for(target=0;target<4;target=target+1)begin
   for(reset_abort=0;reset_abort<2;reset_abort=reset_abort+1)begin
    clear_history;acquire_fresh;
    if(kind==0)begin clear_history;launch(4,1);end
    else if(kind==1)launch(4,1);
    else launch(0,0);
    wait_boundary(kind,target);abort_at_boundary(reset_abort,target);
    acquire_fresh;
   end
  end
 end
 $display("PASS METADATA_ATOMIC area_bits=%0d boundaries=%0d fresh_checks=%0d publications=%0d max_latency_cycles=%0d external_reader=%0d",AREA_BITS,boundaries,checks,publications,max_cycles,EXTERNAL_CANDIDATE_READER);
 $finish;
end
initial begin #100000000;$fatal(1,"global timeout");end
endmodule
