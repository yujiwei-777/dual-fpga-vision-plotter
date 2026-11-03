// One immutable DDR frame -> validated A4 bitmap -> complete path plan -> GRBL.
// No UART motion is admitted until the entire plan and all capacity checks pass.
module doc_copy_pipeline_shared_candidate #(
    parameter integer CLK_HZ=125000000,
    parameter integer PREP_TIMEOUT_MS=30000,
    parameter integer PLANNER_OPT_PASSES=2,
    // 1 selects the no-corner frame-as-A4-width fallback. The parameter is
    // exposed at the pipeline boundary so a calibrated fixed-centre build can
    // be generated without changing the HXA1/Type15 interfaces.
    parameter integer FRAME_AS_A4_WIDTH=1,
    // The board shares one UART with the report path. Standalone callers keep
    // historical admission unless this explicit guard is enabled.
    parameter integer EXTERNAL_ADMISSION_GUARD=0
)(
    input wire clk,rst_n,start,cancel,rearm,reset_job,
    input wire admission_inhibit,
    input wire [31:0] job_id,
    // Width reported by the distance/calibration path.  A zero value means
    // that no calibration is available; this fallback build deliberately
    // keeps using the deterministic full-frame-as-A4-width mapping.
    input wire [15:0] paper_width_px,
    output wire busy,output reg done,
    output wire recovery_required,
    output reg status_valid,output reg [95:0] status_data,input wire status_ready,
    output wire pixel_request,pixel_invalidate,
    output wire [10:0] pixel_x,output wire [9:0] pixel_y,
    input wire pixel_ready,pixel_valid,input wire [7:0] pixel_luma,
    output wire [7:0] tx_data,output wire tx_valid,
    input wire tx_ready,tx_done,
    input wire [7:0] rx_data,input wire rx_valid,rx_error,link_ready,
    output wire [7:0] rt_data,output wire rt_valid,input wire rt_ready,
    output wire uart_owner,
    output wire [127:0] paper_corners,
    output wire [15:0] edge_count,output wire [11:0] path_count,
    output wire [13:0] point_count,
    output wire [63:0] baseline_distance,planned_distance,
    output wire S_start,
    output wire S_clear,
    output wire S_abort,
    output wire S_stop,
    output wire S_rearm,
    output wire S_cancel,
    output wire S_fault,
    output wire S_reset_job,
    output wire S_profile_valid,
    output wire [7:0] S_fault_code,
    output wire [511:0] S_line,
    output wire [6:0] S_length,
    output wire S_line_valid,
    output wire S_line_last,
    output wire S_finish,
    input wire S_available,
    input wire S_line_ready,
    input wire S_line_done,
    input wire S_busy,
    input wire S_done,
    input wire S_error,
    input wire S_cancelled,
    input wire S_recovery_required,
    input wire [7:0] S_error_code,
    input wire [31:0] S_acked_lines,
    input wire [2:0] S_job_state,
    input wire S_rt_done,
    output wire X_start,
    output wire [1:0] X_kind,
    output wire [15:0] X_x,
    output wire [15:0] X_y,
    output wire [15:0] X_z,
    output wire [15:0] X_feed,
    output wire [15:0] X_pwm,
    input wire [511:0] X_line,
    input wire [6:0] X_length,
    input wire X_done,
    input wire X_busy,
    // Accepted image acquisition owns its immutable DDR frame. The parent
    // additionally holds an outstanding pixel read through cancellation drain.
    output wire frame_lock
);
    localparam IDLE=0,IMAGE=1,PLAN=2,DRAW=3,ABORT=4;
    reg [2:0] state;
    reg image_start,plan_start,emit_start,plot_start,abort_pulse;
    reg [31:0] active_job;
    reg [2:0] public_state;
    reg [7:0] public_error;
    reg [16:0] ms_div;
    reg [14:0] prep_ms;
    reg [7:0] status_ms;
    reg status_dirty,cancel_is_error;
    reg rearm_pending,plot_rearm;
    wire tick_ms=ms_div==CLK_HZ/1000-1;
    wire image_busy,image_done,image_error,ink_valid,ink_ready,ink_bit;
    wire [16:0] ink_addr;
    wire [7:0] image_error_code,plan_error_code,plot_error_code;
    wire plan_busy,plan_prepared,plan_done,plan_error;
    wire point_valid,point_ready,point_start,point_end,point_dot;
    wire [8:0] point_x,point_y;
    wire plot_busy,plot_done,plot_error,plot_cancelled;
    wire [2:0] plot_state;
    wire [31:0] acked_lines;
    wire metric_start,metric_a_origin,metric_busy,metric_done;
    wire [8:0] metric_ax,metric_ay,metric_bx,metric_by;
    wire [31:0] metric_distance;wire [32:0] metric_squared;
    wire mapper_start;wire [8:0] mapper_x,mapper_y;
    wire [15:0] mapper_x_cmm,mapper_y_cmm;wire mapper_done;
    wire reset_request=(reset_job===1'b1);
    wire admission_blocked=!S_available || ((EXTERNAL_ADMISSION_GUARD!=0)&&admission_inhibit);
    wire children_cancel=cancel||abort_pulse||reset_request;
    assign busy=(state!=IDLE);
    assign frame_lock=(state==IMAGE)||image_start;
    assign uart_owner=(state==DRAW||state==ABORT)||plot_busy||recovery_required;
    doc_image_frontend #(.FRAME_AS_A4_WIDTH(FRAME_AS_A4_WIDTH)) u_image(.clk(clk),.rst_n(rst_n),.start(image_start),.cancel(children_cancel),
        .busy(image_busy),.done(image_done),.error(image_error),.error_code(image_error_code),
        .pixel_request(pixel_request),.pixel_invalidate(pixel_invalidate),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .pixel_ready(pixel_ready),.pixel_valid(pixel_valid),.pixel_luma(pixel_luma),
        .ink_valid(ink_valid),.ink_addr(ink_addr),.ink_bit(ink_bit),.ink_ready(ink_ready),.corners(paper_corners));
    doc_stroke_planner #(.OPT_PASSES(PLANNER_OPT_PASSES),.EXTERNAL_METRIC(1),.METRIC_DISTANCE_BOUND(32'd23164)) u_planner(.clk(clk),.rst_n(rst_n),.start(plan_start),.cancel(children_cancel),
        .busy(plan_busy),.prepared(plan_prepared),.done(plan_done),.error(plan_error),.error_code(plan_error_code),
        .load_valid(ink_valid),.load_ready(ink_ready),.load_addr(ink_addr),.load_bit(ink_bit),.emit_start(emit_start),
        .point_valid(point_valid),.point_ready(point_ready),.point_x(point_x),.point_y(point_y),
        .point_start(point_start),.point_end(point_end),.point_dot(point_dot),
        .edge_count(edge_count),.path_count(path_count),.point_count(point_count),
        .baseline_distance(baseline_distance),.planned_distance(planned_distance),
        .metric_start(metric_start),.metric_ax(metric_ax),.metric_ay(metric_ay),
        .metric_bx(metric_bx),.metric_by(metric_by),.metric_a_origin(metric_a_origin),
        .metric_busy(metric_busy),.metric_done(metric_done),.metric_distance(metric_distance),
        .metric_squared(metric_squared));
    doc_grbl_plotter_shared_candidate #(.CLK_HZ(CLK_HZ),.EXTERNAL_MAPPER(1)) u_plotter(.clk(clk),.rst_n(rst_n),.start(plot_start),
        .cancel(children_cancel),.rearm(plot_rearm),.reset_job(reset_request),.busy(plot_busy),.done(plot_done),.error(plot_error),
        .cancelled(plot_cancelled),.recovery_required(recovery_required),.error_code(plot_error_code),
        .job_state(plot_state),.acked_lines(acked_lines),.point_valid(point_valid),.point_ready(point_ready),
        .point_x(point_x),.point_y(point_y),.point_start(point_start),.point_end(point_end),.point_dot(point_dot),
        .points_done(plan_done),.tx_data(tx_data),.tx_valid(tx_valid),.tx_ready(tx_ready),.tx_done(tx_done),
        .rx_data(rx_data),.rx_valid(rx_valid),.rx_error(rx_error),.link_ready(link_ready),
        .rt_data(rt_data),.rt_valid(rt_valid),.rt_ready(rt_ready),
        .mapper_start(mapper_start),.mapper_x(mapper_x),.mapper_y(mapper_y),
        .mapper_x_cmm(mapper_x_cmm),.mapper_y_cmm(mapper_y_cmm),.mapper_done(mapper_done),
        .S_start(S_start),
        .S_clear(S_clear),
        .S_abort(S_abort),
        .S_stop(S_stop),
        .S_rearm(S_rearm),
        .S_cancel(S_cancel),
        .S_fault(S_fault),
        .S_reset_job(S_reset_job),
        .S_profile_valid(S_profile_valid),
        .S_fault_code(S_fault_code),
        .S_line(S_line),
        .S_length(S_length),
        .S_line_valid(S_line_valid),
        .S_line_last(S_line_last),
        .S_finish(S_finish),
        .S_available(S_available),
        .S_line_ready(S_line_ready),
        .S_line_done(S_line_done),
        .S_busy(S_busy),
        .S_done(S_done),
        .S_error(S_error),
        .S_cancelled(S_cancelled),
        .S_recovery_required(S_recovery_required),
        .S_error_code(S_error_code),
        .S_acked_lines(S_acked_lines),
        .S_job_state(S_job_state),
        .S_rt_done(S_rt_done),
        .X_start(X_start),
        .X_kind(X_kind),
        .X_x(X_x),
        .X_y(X_y),
        .X_z(X_z),
        .X_feed(X_feed),
        .X_pwm(X_pwm),
        .X_line(X_line),
        .X_length(X_length),
        .X_done(X_done),
        .X_busy(X_busy));
    // Planning and drawing are disjoint pipeline states, so one serial mapper
    // serves both consumers without changing either protocol or coordinates.
    doc_machine_map u_machine_map(.clk(clk),.rst_n(rst_n),.cancel(children_cancel),
        .map_start(mapper_start),.map_x(mapper_x),.map_y(mapper_y),
        .map_x_cmm(mapper_x_cmm),.map_y_cmm(mapper_y_cmm),.map_done(mapper_done),
        .dist_start(metric_start),.dist_ax(metric_ax),.dist_ay(metric_ay),
        .dist_bx(metric_bx),.dist_by(metric_by),.dist_a_origin(metric_a_origin),
        .dist_busy(metric_busy),.dist_done(metric_done),.dist_distance(metric_distance),
        .dist_squared(metric_squared));
    task terminal;
        input [2:0] code;input [7:0] detail;
        begin state<=IDLE;done<=1;public_state<=code;public_error<=detail;status_dirty<=1;end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;done<=0;active_job<=0;public_state<=0;public_error<=0;
            image_start<=0;plan_start<=0;emit_start<=0;plot_start<=0;abort_pulse<=0;
            ms_div<=0;prep_ms<=0;status_ms<=0;status_dirty<=0;cancel_is_error<=0;
            status_valid<=0;status_data<=0;
            rearm_pending<=0;plot_rearm<=0;
        end else begin
            done<=0;image_start<=0;plan_start<=0;emit_start<=0;plot_start<=0;abort_pulse<=0;
            plot_rearm<=0;
            if(rearm)rearm_pending<=1;
            if(rearm_pending&&state==IDLE&&!plot_busy)begin
                plot_rearm<=1;rearm_pending<=0;
            end
            if(tick_ms)begin
                ms_div<=0;
                if((state==IMAGE||state==PLAN)&&prep_ms<PREP_TIMEOUT_MS)prep_ms<=prep_ms+1'b1;
                if(status_ms<250)status_ms<=status_ms+1'b1;
            end else ms_div<=ms_div+1'b1;
            if(status_valid&&status_ready)status_valid<=0;
            if((!status_valid||status_ready)&&(status_dirty||status_ms>=250)&&active_job!=0)begin
                // Existing Type15 layout: u32 job, u8 state,error,u16 reserved,u32 lines.
                status_data<={acked_lines,16'd0,public_error,5'd0,public_state,active_job};
                status_valid<=1;status_dirty<=0;status_ms<=0;
            end
            if(start&&state==IDLE)begin
                active_job<=job_id;public_state<=1;public_error<=0;prep_ms<=0;
                status_dirty<=1;cancel_is_error<=0;
                if(recovery_required||admission_blocked)terminal(5,8'h61);
                else begin image_start<=1;state<=IMAGE;end
            end else if(admission_blocked&&(state==IMAGE||state==PLAN||(state==DRAW&&!plot_busy)))begin
                // An already received frame must retire with an explicit
                // recovery error, never hang or start motion through the
                // other UART consumer's Alarm/Reset recovery lock.
                abort_pulse<=1;terminal(5,8'h61);
            end else if((cancel||reset_request)&&state!=IDLE&&state!=ABORT)begin
                if(state==DRAW||plot_busy)begin
                    state<=ABORT;cancel_is_error<=0;
                end else terminal(6,0);
            end else if((state==IMAGE||state==PLAN)&&prep_ms>=PREP_TIMEOUT_MS)begin
                abort_pulse<=1;terminal(5,8'h62);
            end else case(state)
                IMAGE:begin
                    if(image_error)terminal(5,image_error_code);
                    else if(image_done)begin plan_start<=1;state<=PLAN;end
                end
                PLAN:begin
                    if(plan_error)terminal(5,plan_error_code);
                    else if(plan_prepared)begin
                        // Both consumers see the first point only after preparation.
                        emit_start<=1;plot_start<=1;state<=DRAW;public_state<=2;status_dirty<=1;
                    end
                end
                DRAW:begin
                    if(plot_state==3&&public_state!=3)begin public_state<=3;status_dirty<=1;end
                    if(plot_done)terminal(4,0);
                    else if(plot_error)begin
                        // Plotter owns realtime recovery. Do not release the UART
                        // to the legacy reporter before it has stopped the machine.
                        if(plot_busy)begin state<=ABORT;cancel_is_error<=1;public_error<=plot_error_code;abort_pulse<=1;end
                        else terminal(5,plot_error_code);
                    end else if(plot_cancelled)terminal(6,plot_error_code);
                end
                ABORT:begin
                    if(plot_cancelled||(!plot_busy&&plot_error))
                        terminal(cancel_is_error?3'd5:3'd6,public_error);
                end
                default:;
            endcase
        end
    end
endmodule
