`timescale 1ns/1ps
module tb_stroke_lifecycle;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,start=0,cancel=0;wire busy,prepared,point_valid,error;
doc_stroke_planner dut(.clk(clk),.rst_n(rst_n),.start(start),.cancel(cancel),
 .load_valid(1'b0),.load_addr(17'd0),.load_bit(1'b0),.load_ready(),.emit_start(1'b0),
 .busy(busy),.prepared(prepared),.done(),.error(error),.error_code(),.point_valid(point_valid),
 .point_x(),.point_y(),.point_start(),.point_end(),.point_dot(),.point_ready(1'b0),
 .edge_count(),.path_count(),.point_count(),.baseline_distance(),.planned_distance(),
 .metric_start(),.metric_ax(),.metric_ay(),.metric_bx(),.metric_by(),.metric_a_origin(),
 .metric_busy(1'b0),.metric_done(1'b0),.metric_distance(32'd0),.metric_squared(33'd0));
integer states[0:8];integer i,k,checks=0;
initial begin
 states[0]=40;states[1]=43;states[2]=52;states[3]=59;states[4]=53;
 states[5]=54;states[6]=56;states[7]=171;states[8]=186;
 repeat(3)@(negedge clk);rst_n=1;
 for(k=0;k<2;k=k+1)for(i=0;i<9;i=i+1)begin
   @(negedge clk);dut.state=states[i];dut.busy=1;dut.prepared=1;dut.point_valid=1;
   if(k==0)cancel=1;else rst_n=0;
   @(negedge clk);
   if(busy||prepared||point_valid||dut.state!=0)$fatal(1,"abort failed %0d %0d",k,states[i]);
   if(dut.gwe||dut.pwe||dut.dwe)$fatal(1,"abort left writes pending");
   checks=checks+1;cancel=0;rst_n=1;
   @(negedge clk);if(busy||point_valid)$fatal(1,"abort auto-restarted old task");
 end
 $display("PASS STROKE_LIFECYCLE cancel/reset priority and no replay checks=%0d",checks);$finish;
end
endmodule
