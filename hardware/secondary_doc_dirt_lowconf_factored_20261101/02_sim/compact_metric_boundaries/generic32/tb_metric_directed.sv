`timescale 1ns/1ps
module tb_metric_directed;
reg clk=0;always #4 clk=~clk;
reg  rst_n=0;
reg  start=0;
reg  cancel=0;
reg  load_valid=0;
reg [16:0] load_addr=0;
reg  load_bit=0;
wire  load_ready;
reg  emit_start=0;
wire  busy;
wire  prepared;
wire  done;
wire  error;
wire [7:0] error_code;
wire  point_valid;
wire [8:0] point_x;
wire [8:0] point_y;
wire  point_start;
wire  point_end;
wire  point_dot;
reg  point_ready=0;
wire [15:0] edge_count;
wire [11:0] path_count;
wire [13:0] point_count;
wire [63:0] baseline_distance;
wire [63:0] planned_distance;
wire  metric_start;
wire [8:0] metric_ax;
wire [8:0] metric_ay;
wire [8:0] metric_bx;
wire [8:0] metric_by;
wire  metric_a_origin;
reg  metric_busy=0;
reg  metric_done=0;
reg [31:0] metric_distance=0;
reg [32:0] metric_squared=0;
reg compare_enable=0;
doc_stroke_planner #(.EXTERNAL_METRIC(1),.OPT_PASSES(0)) dut(.*);

wire  ctrl_load_ready;
wire  ctrl_busy;
wire  ctrl_prepared;
wire  ctrl_done;
wire  ctrl_error;
wire [7:0] ctrl_error_code;
wire  ctrl_point_valid;
wire [8:0] ctrl_point_x;
wire [8:0] ctrl_point_y;
wire  ctrl_point_start;
wire  ctrl_point_end;
wire  ctrl_point_dot;
wire [15:0] ctrl_edge_count;
wire [11:0] ctrl_path_count;
wire [13:0] ctrl_point_count;
wire [63:0] ctrl_baseline_distance;
wire [63:0] ctrl_planned_distance;
wire  ctrl_metric_start;
wire [8:0] ctrl_metric_ax;
wire [8:0] ctrl_metric_ay;
wire [8:0] ctrl_metric_bx;
wire [8:0] ctrl_metric_by;
wire  ctrl_metric_a_origin;
doc_stroke_planner_baseline #(.EXTERNAL_METRIC(1),.OPT_PASSES(0)) control(.clk(clk),
.rst_n(rst_n),
.start(start),
.cancel(cancel),
.load_valid(load_valid),
.load_addr(load_addr),
.load_bit(load_bit),
.load_ready(ctrl_load_ready),
.emit_start(emit_start),
.busy(ctrl_busy),
.prepared(ctrl_prepared),
.done(ctrl_done),
.error(ctrl_error),
.error_code(ctrl_error_code),
.point_valid(ctrl_point_valid),
.point_x(ctrl_point_x),
.point_y(ctrl_point_y),
.point_start(ctrl_point_start),
.point_end(ctrl_point_end),
.point_dot(ctrl_point_dot),
.point_ready(point_ready),
.edge_count(ctrl_edge_count),
.path_count(ctrl_path_count),
.point_count(ctrl_point_count),
.baseline_distance(ctrl_baseline_distance),
.planned_distance(ctrl_planned_distance),
.metric_start(ctrl_metric_start),
.metric_ax(ctrl_metric_ax),
.metric_ay(ctrl_metric_ay),
.metric_bx(ctrl_metric_bx),
.metric_by(ctrl_metric_by),
.metric_a_origin(ctrl_metric_a_origin),
.metric_busy(metric_busy),
.metric_done(metric_done),
.metric_distance(metric_distance),
.metric_squared(metric_squared));
integer miter_cycles=0;
always @(posedge clk)begin
 #1;
 if(rst_n&&compare_enable)begin
  if({load_ready,busy,prepared,done,error,error_code,point_valid,point_x,point_y,point_start,point_end,point_dot,edge_count,path_count,point_count,baseline_distance,planned_distance,metric_start,metric_ax,metric_ay,metric_bx,metric_by,metric_a_origin} !== {ctrl_load_ready,ctrl_busy,ctrl_prepared,ctrl_done,ctrl_error,ctrl_error_code,ctrl_point_valid,ctrl_point_x,ctrl_point_y,ctrl_point_start,ctrl_point_end,ctrl_point_dot,ctrl_edge_count,ctrl_path_count,ctrl_point_count,ctrl_baseline_distance,ctrl_planned_distance,ctrl_metric_start,ctrl_metric_ax,ctrl_metric_ay,ctrl_metric_bx,ctrl_metric_by,ctrl_metric_a_origin})$fatal(1,"metric planner public cycle mismatch %0d state=%0d/%0d",miter_cycles,dut.state,control.state);
  if(dut.state !== control.state)$fatal(1,"metric planner state cycle mismatch");
  if({dut.awe,dut.bwe,dut.gwe,dut.pwe,dut.dwe,dut.awa,dut.bwa,dut.gwa,dut.pwa,dut.dwa,dut.awd,dut.bwd,dut.gwd,dut.pwd,dut.dwd,dut.ara,dut.bra,dut.gra,dut.pra,dut.dra} !== {control.awe,control.bwe,control.gwe,control.pwe,control.dwe,control.awa,control.bwa,control.gwa,control.pwa,control.dwa,control.awd,control.bwd,control.gwd,control.pwd,control.dwd,control.ara,control.bra,control.gra,control.pra,control.dra})$fatal(1,"metric planner RAM cycle mismatch");
  miter_cycles=miter_cycles+1;
 end
end
final $display("PASS METRIC_PUBLIC_CYCLE_MITER cycles=%0d public_ports=23 ram_signals=20",miter_cycles);

integer checks=0,rejects=0;
task reset_pair;
begin
 @(negedge clk);compare_enable=0;rst_n=0;start=0;cancel=0;emit_start=0;metric_done=0;
 repeat(2)@(negedge clk);rst_n=1;compare_enable=1;
end endtask
task stage;
 input [8:0] value;
begin
 @(negedge clk);dut.state=value;control.state=value;
 dut.busy=1;control.busy=1;dut.prepared=0;control.prepared=0;
 dut.point_valid=0;control.point_valid=0;
end endtask
task tick;begin @(negedge clk);end endtask
task capture_distance;
 input [31:0] value;input reject;
begin
 reset_pair;stage(75);compare_enable=!reject;
 dut.dist_return=171;control.dist_return=171;metric_distance=value;metric_squared=0;metric_done=1;
 tick;metric_done=0;
 if(reject)begin
  if(!error||error_code!=8'h05||busy||prepared||point_valid||dut.state!=0)
   $fatal(1,"invalid metric failed to reject value=%h",value);
  if(dut.dist_result!==0)$fatal(1,"invalid metric truncated/stored value=%h",value);
  emit_start=1;
  repeat(8)begin tick;if(prepared||point_valid||busy||metric_start)$fatal(1,"invalid metric released/replayed task");end
  emit_start=0;rejects=rejects+1;
 end else begin
  if(error||dut.state!=171||dut.dist_result!==value)$fatal(1,"metric capture mismatch value=%h",value);
 end
 checks=checks+1;
end endtask

reg [31:0] values[0:7];integer i;reg [31:0] random_value=32'h13579bdf;
initial begin
 if($bits(dut.dist_result)!=32||$bits(dut.old_cost)!=32||$bits(dut.new_cost)!=32||
    $bits(dut.seam_best)!=32||$bits(dut.seam_partial)!=32||$bits(dut.cost_sum)!=32||$bits(dut.cost_result)!=32)
  $fatal(1,"generic default changed width");
 values[0]=0;values[1]=1;values[2]=23164;values[3]=23165;values[4]=32'h7fffffff;
 values[5]=32'h80000000;values[6]=32'hfffffffe;values[7]=32'hffffffff;
 for(i=0;i<8;i=i+1)capture_distance(values[i],0);
 for(i=0;i<64;i=i+1)begin
  random_value=(random_value<<1)^((random_value[31])?32'h04c11db7:32'd0);
  capture_distance(random_value,0);
 end
 reset_pair;stage(94);dut.cost_sum=32'hfffffffe;control.cost_sum=32'hfffffffe;
 dut.dist_result=32'hffffffff;control.dist_result=32'hffffffff;
 tick;if(dut.cost_sum!==32'hfffffffd||control.cost_sum!==32'hfffffffd)$fatal(1,"generic route modulo32 changed");checks=checks+1;
 reset_pair;stage(132);dut.old_cost=32'hfffffffe;control.old_cost=32'hfffffffe;
 dut.dist_result=32'hffffffff;control.dist_result=32'hffffffff;
 tick;if(dut.old_cost!==32'hfffffffd)$fatal(1,"generic old cost modulo32 changed");checks=checks+1;
 reset_pair;stage(135);dut.new_cost=32'hfffffffe;control.new_cost=32'hfffffffe;
 dut.dist_result=32'hffffffff;control.dist_result=32'hffffffff;
 tick;if(dut.new_cost!==32'hfffffffd)$fatal(1,"generic new cost modulo32 changed");checks=checks+1;
 reset_pair;stage(136);dut.old_cost=8;control.old_cost=8;dut.new_cost=32'hfffffffe;control.new_cost=32'hfffffffe;
 tick;if(dut.state!==137)$fatal(1,"generic +32'd10 comparison wrap changed");checks=checks+1;
 reset_pair;stage(136);dut.old_cost=7;control.old_cost=7;dut.new_cost=32'hfffffffe;control.new_cost=32'hfffffffe;
 tick;if(dut.state!==120)$fatal(1,"generic +32'd10 comparison boundary changed");checks=checks+1;
 reset_pair;stage(108);dut.seam_best=32'hffffffff;control.seam_best=32'hffffffff;
 dut.seam_partial=32'hfffffffe;control.seam_partial=32'hfffffffe;
 dut.dist_result=32'hffffffff;control.dist_result=32'hffffffff;
 tick;if(dut.seam_best!==32'hfffffffd)$fatal(1,"generic seam modulo32 changed");checks=checks+1;
 reset_pair;stage(82);dut.cost_result=32'hffffffff;control.cost_result=32'hffffffff;
 tick;if(baseline_distance!==64'h00000000ffffffff)$fatal(1,"generic baseline64 changed");checks=checks+1;
 reset_pair;stage(170);dut.cost_result=32'hffffffff;control.cost_result=32'hffffffff;
 dut.baseline_distance=64'h100000000;control.baseline_distance=64'h100000000;
 tick;if(planned_distance!==64'h00000000ffffffff||!prepared)$fatal(1,"generic planned64 changed");checks=checks+1;
 if(checks!=80||rejects!=0)$fatal(1,"generic coverage mismatch %0d/%0d",checks,rejects);
 $display("PASS METRIC_GENERIC32 checks=%0d rejects=%0d high_value_captures=72 modulo32_cases=6 output64_cases=2",checks,rejects);
 $finish;
end
endmodule
