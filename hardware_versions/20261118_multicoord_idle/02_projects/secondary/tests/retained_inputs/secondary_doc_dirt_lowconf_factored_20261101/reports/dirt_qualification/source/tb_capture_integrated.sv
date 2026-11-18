`timescale 1ns/1ps
module tb_stroke_split;
reg clk=0; always #4 clk=~clk;
reg rst_n=0,start=0,cancel=0,emit_start=0;
wire load_valid,load_bit;wire [16:0] load_addr;
wire load_ready,busy,prepared,done,error,point_valid,point_start,point_end,point_dot,point_ready;
wire [8:0] point_x,point_y;
wire [7:0] error_code;
wire [15:0] edge_count; wire [11:0] path_count; wire [13:0] point_count;
wire [63:0] baseline_distance,planned_distance;
wire metric_start,metric_busy,metric_done,metric_a_origin;
wire [8:0] metric_ax,metric_ay,metric_bx,metric_by;
wire [31:0] metric_distance; wire [32:0] metric_squared;
`include "expected.vh"
doc_stroke_planner #(.OPT_PASSES(OPT_PASSES),.EXTERNAL_METRIC(1),.METRIC_DISTANCE_BOUND(32'd23164),
  .MAX_EDGES(LIMIT_EDGES),.MAX_PATHS(LIMIT_PATHS),.MAX_POINTS(LIMIT_POINTS)) dut(.*);
wire mapper_start,mapper_done;
wire [8:0] mapper_x,mapper_y;
wire [15:0] mapper_x_cmm,mapper_y_cmm;
doc_machine_map map(.clk(clk),.rst_n(rst_n),.cancel(cancel),
 .map_start(mapper_start),.map_x(mapper_x),.map_y(mapper_y),
 .map_x_cmm(mapper_x_cmm),.map_y_cmm(mapper_y_cmm),.map_done(mapper_done),
 .dist_start(metric_start),.dist_ax(metric_ax),.dist_ay(metric_ay),.dist_bx(metric_bx),.dist_by(metric_by),
 .dist_a_origin(metric_a_origin),.dist_busy(metric_busy),.dist_done(metric_done),
 .dist_distance(metric_distance),.dist_squared(metric_squared));
reg plot_start=0;
wire plot_busy,plot_done,plot_error,plot_cancelled,recovery_required;
wire [7:0] plot_error_code;wire [2:0] job_state;wire [31:0] acked_lines;
wire [7:0] tx_data,rt_data;wire tx_valid,rt_valid;
reg tx_done=0,rx_valid=0;reg [7:0] rx_data=0;
integer clocks=0;
wire tx_ready=(clocks%7!=1)&&(clocks%11!=2);
wire rt_ready=(clocks%7!=3);
doc_grbl_plotter #(.EXTERNAL_MAPPER(1)) plot(
 .clk(clk),.rst_n(rst_n),.start(plot_start),.cancel(cancel),.rearm(1'b0),.reset_job(1'b0),
 .point_valid(point_valid),.point_x(point_x),.point_y(point_y),.point_start(point_start),
 .point_end(point_end),.point_dot(point_dot),.points_done(done),.point_ready(point_ready),
 .busy(plot_busy),.done(plot_done),.error(plot_error),.cancelled(plot_cancelled),
 .recovery_required(recovery_required),.error_code(plot_error_code),.job_state(job_state),.acked_lines(acked_lines),
 .tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready),.tx_done(tx_done),
 .rx_data(rx_data),.rx_valid(rx_valid),.rx_error(1'b0),.link_ready(1'b1),
 .rt_data(rt_data),.rt_valid(rt_valid),.rt_ready(rt_ready),
 .mapper_start(mapper_start),.mapper_x(mapper_x),.mapper_y(mapper_y),
 .mapper_x_cmm(mapper_x_cmm),.mapper_y_cmm(mapper_y_cmm),.mapper_done(mapper_done));
reg image[0:102399],skeleton[0:102399];reg [20:0] expected[0:8191];
integer i,n=0,cycles=0,fh,rawfh,sk_checks=0;
integer reply_delay=0,reply_i=0,reply_len=0,queries=0;
reg [255:0] reply;
reg [20:0] got,held;reg stalled=0;

reg fe_start=0;
wire fe_busy,fe_done,fe_error,fe_request;
wire [7:0] fe_error_code;
wire [10:0] fe_x;
wire [9:0] fe_y;
reg fe_valid=0,fe_pending=0;
wire fe_ready=(clocks%13!=5)&&!fe_pending;
reg [7:0] fe_luma;
reg [7:0] source_y[0:921599];
integer fe_latency=0,fe_address=0,fe_count=0,fe_requests=0;
doc_image_frontend fe(.clk(clk),.rst_n(rst_n),.start(fe_start),.cancel(cancel),
 .busy(fe_busy),.done(fe_done),.error(fe_error),.error_code(fe_error_code),
 .pixel_request(fe_request),.pixel_invalidate(),.pixel_x(fe_x),.pixel_y(fe_y),
 .pixel_ready(fe_ready),.pixel_valid(fe_valid),.pixel_luma(fe_luma),
 .ink_valid(load_valid),.ink_addr(load_addr),.ink_bit(load_bit),
 .ink_ready(load_ready),.corners());
always @(posedge clk)begin
 fe_valid<=0;
 if(rst_n)begin
   if(fe_request&&fe_ready)begin
     if(fe_x>1279||fe_y>719)$fatal(1,"frontend out-of-range source");
     fe_address=fe_y*1280+fe_x;fe_latency=2;fe_pending<=1;fe_requests=fe_requests+1;
   end else if(fe_pending)begin
     if(fe_latency>0)fe_latency=fe_latency-1;
     else begin fe_valid<=1;fe_luma<=source_y[fe_address];fe_pending<=0;end
   end
   if(load_valid&&load_ready)begin
     if(load_addr!==fe_count||load_bit!==image[fe_count])
       $fatal(1,"frontend bit mismatch address %0d expected index %0d",load_addr,fe_count);
     fe_count=fe_count+1;
   end
 end
end

initial begin
 $readmemh("input.mem",image);$readmemh("skeleton.mem",skeleton);
 if(EXPECT_ERROR==0&&POINT_COUNT>0)$readmemh("expected.mem",expected,0,POINT_COUNT-1);
 fh=$fopen("gcode.txt","w");rawfh=$fopen("raw_paths.txt","w");
 repeat(5)@(negedge clk);rst_n=1;
 $readmemh("source_y.mem",source_y);
 @(negedge clk);fe_start=1;
 @(negedge clk);fe_start=0;
 while(!fe_done&&!fe_error)begin
   @(negedge clk);cycles=cycles+1;
   if(cycles>40000000)$fatal(1,"frontend watchdog");
 end
 if(fe_error||fe_count!=102400||fe_requests!=SOURCE_REQUESTS)
   $fatal(1,"frontend error/counts %0d %0d %0d",fe_error,fe_count,fe_requests);
 @(negedge clk);start=1;
 @(negedge clk);start=0;
 while(!prepared&&!error)begin
   @(negedge clk);cycles=cycles+1;
   if(cycles%10000000==0)$display("PROGRESS prep cycles=%0d state=%0d",cycles,dut.state);
   if(cycles>140000000)$fatal(1,"prep watchdog state=%0d",dut.state);
 end
 if(EXPECT_ERROR!=0)begin
   if(!error||error_code!=EXPECT_ERROR||prepared||point_valid)$fatal(1,"capacity release/error mismatch");
   if(n||queries)$fatal(1,"capacity failure released motion");
   $display("PASS capacity error=%0d before motion",error_code);$finish;
 end
 if(error)$fatal(1,"prepare error %0d",error_code);
 if(sk_checks!=57600)$fatal(1,"skeleton checks %0d",sk_checks);
 if(edge_count!=EDGE_COUNT||path_count!=PATH_COUNT||point_count!=POINT_COUNT)
   $fatal(1,"counts %0d/%0d/%0d expected %0d/%0d/%0d",edge_count,path_count,point_count,EDGE_COUNT,PATH_COUNT,POINT_COUNT);
 if(baseline_distance!=BASELINE_DISTANCE||planned_distance!=PLANNED_DISTANCE||planned_distance>baseline_distance)
   $fatal(1,"distance mismatch %0d/%0d expected %0d/%0d",baseline_distance,planned_distance,BASELINE_DISTANCE,PLANNED_DISTANCE);
 repeat(8)begin @(negedge clk);if(!prepared)$fatal(1,"prepared not retained");end
 plot_start=1;emit_start=1;
 @(negedge clk);plot_start=0;emit_start=0;
 while(!plot_done&&!plot_error)begin
   @(negedge clk);cycles=cycles+1;
   if(cycles>145000000)$fatal(1,"plot watchdog");
 end
 if(plot_error||recovery_required)$fatal(1,"plot error %0d",plot_error_code);
 if(n!=POINT_COUNT||acked_lines!=GCODE_LINES||queries!=1)$fatal(1,"emit/ACK/query counts %0d/%0d/%0d",n,acked_lines,queries);
 $fclose(fh);$fclose(rawfh);
 $display("PASS CAPTURE_INTEGRATED frontend thin graph paths mapper Gcode cycles=%0d edges=%0d paths=%0d points=%0d acked=%0d",cycles,edge_count,path_count,point_count,acked_lines);$finish;
end
always @(posedge clk)begin
 clocks<=clocks+1;
 if(rst_n)begin
   if(dut.state==25)begin
     if(dut.nb[8]!==skeleton[(dut.sy+70)*320+dut.sx])$fatal(1,"skeleton mismatch %0d %0d",dut.sx,dut.sy);
     sk_checks=sk_checks+1;
   end
   if(dut.state==58)$fdisplay(rawfh,"POINT %0d %0d",dut.append_x,dut.append_y+70);
   if(dut.state==56)$fdisplay(rawfh,"END %0d %0d",dut.closed_path,dut.path_len);
   got={point_dot,point_end,point_start,point_y,point_x};
   if(stalled&&(!point_valid||got!==held))$fatal(1,"point changed under backpressure");
   stalled=point_valid&&!point_ready;held=got;
   if(point_valid&&point_ready)begin
     if(n>=POINT_COUNT||got!==expected[n])$fatal(1,"point %0d mismatch %06h expected %06h",n,got,expected[n]);
     if(point_x>319||point_y<70||point_y>249)$fatal(1,"outside raster");
     n=n+1;
   end
 end
end
// Simulated stop-and-wait GRBL peer. Responses start well after the UART
// completion edge/response-parser clear. There is no end-of-job Idle reply.
always @(posedge clk)begin
 tx_done<=0;rx_valid<=0;
 if(rst_n)begin
   if(tx_valid&&tx_ready)begin
     tx_done<=1;
     if(tx_data==10)begin
       $fwrite(fh,"\n");
       if(reply_len)$fatal(1,"more than one command in flight");
       reply="";reply[7:0]="o";reply[15:8]="k";reply[23:16]=10;
       reply_i=0;reply_len=3;reply_delay=8;
     end else $fwrite(fh,"%c",tx_data);
   end
   if(rt_valid&&rt_ready)begin
     tx_done<=1;queries=queries+1;
     if(rt_data!=8'h3f||reply_len)$fatal(1,"unexpected realtime command");
     reply="";reply[7:0]="<";reply[15:8]="I";reply[23:16]="d";reply[31:24]="l";reply[39:32]="e";
     reply[47:40]="|";reply[55:48]=">";reply[63:56]=10;
     reply_i=0;reply_len=8;reply_delay=8;
   end
   if(reply_delay>0)reply_delay=reply_delay-1;
   else if(reply_len>0)begin
     rx_valid<=1;rx_data<=reply[reply_i*8+:8];reply_i=reply_i+1;reply_len=reply_len-1;reply_delay=2;
   end
 end
end
endmodule
