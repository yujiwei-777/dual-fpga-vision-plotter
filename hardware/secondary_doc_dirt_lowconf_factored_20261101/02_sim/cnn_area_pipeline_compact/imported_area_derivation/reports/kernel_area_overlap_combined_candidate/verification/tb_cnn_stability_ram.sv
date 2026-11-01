`timescale 1ns/1ps
module tb_cnn_stability_ram #(parameter AREA_BITS=32);
reg clk=0;always #5 clk=~clk;
reg rst_n=0,clear=0,start=0;
reg [2:0] input_count=0;
reg [511:0] input_boxes=0;
wire busy,done,uncertain,emit_begin,emit_valid;
wire [2:0] output_count;
wire [511:0] output_boxes;
wire [1:0] emit_slot;
wire [127:0] emit_box;
cnn_result_stabilizer #(.CONFIRM_RESULTS(1),.AREA_BITS(AREA_BITS),.AREA_SHIFT(6),.COORD_SHIFT(3)) dut(
 .input_candidate_box(128'd0),.candidate_read_index(),.*);
integer checks=0,aborts=0,writes=0,cycles,prior_writes,k;
reg [dut.PAYLOAD_BITS-1:0] saved[0:3];
reg [127:0] current_box;
function automatic [127:0] box(input [10:0] x,input [9:0] y,input [3:0] cls,input [31:0] area);
 box={10'd0,area[15:0],6'd0,8'd0,8'd70,12'd0,cls,6'd0,(y+10'd96),5'd0,(x+11'd96),6'd0,y,5'd0,x};
endfunction
function automatic [dut.PAYLOAD_BITS-1:0] word_for(input [127:0] b);
 word_for={b[102+:16],b[57:51],b[25:19],b[42:35],b[10:3]};
endfunction
always @(posedge clk)if(dut.payload_we)begin
 if(dut.payload_wdata!==word_for(dut.candidate_box))$fatal(1,"whole-word packing mismatch");
 writes=writes+1;
end
task launch(input integer count,input [127:0] b);begin
 @(negedge clk);input_count=count;input_boxes={384'd0,b};start=1;
 @(negedge clk);start=0;
 if(!busy)$fatal(1,"launch rejected");
end endtask
task wait_done;begin
 cycles=0;
 while(!done&&cycles<2000)begin @(negedge clk);cycles=cycles+1;end
 if(!done||busy)$fatal(1,"completion timeout");
end endtask
task clear_history;begin
 @(negedge clk);clear=1;start=1;
 #1;if(emit_begin||emit_valid||dut.payload_we)$fatal(1,"clear leaks write or serial record");
 @(negedge clk);clear=0;start=0;
 if(busy||done||output_count||output_boxes!==0)$fatal(1,"clear control invalid");
end endtask
task save_ram;begin
 for(k=0;k<4;k=k+1)saved[k]=dut.track_payload[k];
end endtask
task same_ram;begin
 for(k=0;k<4;k=k+1)if(saved[k]!==dut.track_payload[k])$fatal(1,"reset/clear changed RAM word %0d",k);
end endtask
task seed;begin
 clear_history;
 current_box=box(11'd96,10'd96,4'd2,32'hfedcba98);
 prior_writes=writes;launch(1,current_box);wait_done;
 if(writes!=prior_writes+1||output_count!==1||output_boxes[127:0]!==current_box||dut.track_payload[0]!==word_for(current_box))
  $fatal(1,"seed atomic word/serial mismatch");
 save_ram;checks=checks+1;
end endtask
task recover_and_check;begin
 repeat(8)begin @(negedge clk);if(busy||done||emit_begin||emit_valid)$fatal(1,"stale abort event");end
 // Every word may retain stale data. Valid bits must suppress all of it.
 launch(0,0);wait_done;
 if(output_count||output_boxes!==0)$fatal(1,"stale RAM ghost after abort");
 current_box=box(11'd960,10'd600,4'd7,32'h80706050);
 prior_writes=writes;launch(1,current_box);wait_done;
 if(writes!=prior_writes+1||output_count!==1||output_boxes[127:0]!==current_box||dut.track_payload[0]!==word_for(current_box))
  $fatal(1,"reuse did not atomically replace full payload");
 checks=checks+1;
end endtask
initial begin
 repeat(4)@(negedge clk);rst_n=1;
 // Abort before the write state, exactly on its write edge, and just after
 // its complete-word write. No field FSM or partially updated word exists.
 seed;launch(1,box(11'd104,10'd104,4'd3,32'h11223344));
 while(dut.state!=dut.S_UPDATE_LOAD)@(negedge clk);
 clear=1;@(negedge clk);clear=0;same_ram;aborts=aborts+1;recover_and_check;
 seed;launch(1,box(11'd104,10'd104,4'd3,32'h55667788));
 while(dut.state!=dut.S_UPDATE_APPLY)@(negedge clk);
 clear=1;#1;if(dut.payload_we)$fatal(1,"clear did not mask atomic write");
 @(negedge clk);clear=0;same_ram;aborts=aborts+1;recover_and_check;
 seed;current_box=box(11'd104,10'd104,4'd3,32'h90abcdef);launch(1,current_box);
 while(dut.state!=dut.S_UPDATE_APPLY)@(negedge clk);
 @(negedge clk);
 if(dut.track_payload[0]!==word_for(current_box))$fatal(1,"post-write word torn");
 save_ram;clear=1;@(negedge clk);clear=0;same_ram;aborts=aborts+1;recover_and_check;
 seed;launch(1,box(11'd104,10'd104,4'd3,32'h01234567));
 while(dut.state!=dut.S_UPDATE_APPLY)@(negedge clk);
 rst_n=0;#1;if(dut.payload_we)$fatal(1,"reset did not mask atomic write");
 repeat(2)@(negedge clk);rst_n=1;same_ram;aborts=aborts+1;recover_and_check;
 seed;launch(1,box(11'd104,10'd104,4'd3,32'hcdef0123));
 while(dut.state!=dut.S_PAIR_WAIT)@(negedge clk);
 clear=1;@(negedge clk);clear=0;same_ram;aborts=aborts+1;recover_and_check;
 $display("PASS WIDE_RAM_ATOMIC checks=%0d aborts=%0d",checks,aborts);$finish;
end
initial begin #10000000;$fatal(1,"atomic test timeout");end
endmodule
