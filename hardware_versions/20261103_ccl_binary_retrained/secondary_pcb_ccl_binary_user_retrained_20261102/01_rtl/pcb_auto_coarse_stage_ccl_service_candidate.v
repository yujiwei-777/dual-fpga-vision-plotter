// Independent area candidate; full integration qualification pending.
// Frame-owned CCL proposals -> exact coarse scoring -> Q28 affine packet.
// Cancellation drains an accepted raw request before releasing ownership. A
// capture timeout leaves this stage locked until reset. No proposal is NO_TARGET,
// never PCB PASS; downstream fine/spatial/outline/detail gates remain mandatory.
module pcb_auto_coarse_stage_ccl_service_candidate #(
    parameter GEOMETRY_ROM="coarse_engine_rom.mem",
    parameter integer PIXEL_TIMEOUT=4096,
    parameter integer WIDTH_FIRST=0,WIDTH_LAST=13,
    parameter integer ANGLE_FIRST=0,ANGLE_LAST=9,
    parameter integer SEARCH_X_MIN=0,SEARCH_X_MAX=127,
    parameter integer SEARCH_Y_MIN=0,SEARCH_Y_MAX=71,
    parameter integer CENTER_RADIUS=2,
    parameter [31:0] COARSE_TIMEOUT=32'd2000000000
)(
    input wire I_clk,I_rst_n,I_start,I_cancel,I_frame_valid,
    input wire [2:0] I_ccl_count,
    input wire [255:0] I_ccl_boxes,
    input wire I_ccl_overflow,I_ccl_truncated,
    input wire I_shared_service_busy,I_geometry_busy,
    output wire O_geometry_pose_start,O_geometry_affine_start,O_geometry_cancel,
    output wire [3:0] O_geometry_width_index,O_geometry_angle_index,
    output wire [6:0] O_geometry_center_x,O_geometry_center_y,
    input wire I_geometry_pose_done,I_geometry_pose_valid,
    input wire [3:0] I_geometry_pose_error,
    input wire [6:0] I_geometry_xmin,I_geometry_ymin,
    input wire I_geometry_affine_done,I_geometry_affine_valid,
    input wire [3:0] I_geometry_affine_error,
    input wire [239:0] I_geometry_coarse,
    input wire I_geometry_ws_we,
    input wire [14:0] I_geometry_ws_waddr,
    input wire [15:0] I_geometry_ws_wdata,
    output wire O_busy,O_idle,O_frame_lock,
    output reg O_done,O_valid,O_no_target,
    output reg [7:0] O_error,
    output wire [2:0] O_phase,
    output reg [47:0] O_cycles,
    output wire O_pixel_request,
    output wire [10:0] O_pixel_x,
    output wire [9:0] O_pixel_y,
    input wire I_pixel_ready,I_pixel_valid,
    input wire [7:0] I_pixel_y8,
    output wire O_ws_we,O_ws_wbank,
    output wire [14:0] O_ws_waddr,
    output wire [15:0] O_ws_wdata,
    output wire O_ws_rd_bank,
    output wire [14:0] O_ws_rd_addr,
    input wire [15:0] I_ws_rd_data,
    output wire O_stats_start,O_stats_cancel,
    output wire [3:0] O_stats_count_log2,
    output wire O_sample_valid,
    input wire I_sample_ready,
    output wire [7:0] O_sample_i,O_sample_t,
    input wire I_stats_done,I_stats_valid,I_stats_busy,
    input wire [3:0] I_stats_error,
    input wire signed [35:0] I_stats_covariance,
    input wire [35:0] I_stats_variance_i,I_stats_variance_t,
    output wire O_ncc_start,O_ncc_cancel,
    output wire signed [35:0] O_covariance,
    output wire [35:0] O_variance_i,O_variance_t,
    input wire I_ncc_done,I_ncc_valid,I_ncc_busy,
    input wire [30:0] I_ncc_score2_q30,
    input wire [3:0] I_ncc_error,
    output wire signed [39:0] O_ax,O_bx,O_tx,O_ay,O_by,O_ty,
    output wire [3:0] O_width_index,O_angle_index,
    output wire [7:0] O_pose_index,
    output wire [6:0] O_center_x,O_center_y,
    output wire [30:0] O_score2_q30,O_runner_score2_q30,
    output wire [31:0] O_coarse_candidates,
    output wire [19:0] O_capture_samples,
    output wire [13:0] O_capture_pixels
);
    localparam [2:0] IDLE=0,CAPSTART=1,CAPWAIT=2,LOCSTART=3,LOCWAIT=4,
                     AFFSTART=5,AFFWAIT=6,CANCEL_WAIT=7;
    reg [2:0] state;
    reg locked,cancel_seen;
    reg [7:0] cancel_error;
    wire capture_active=state==CAPSTART || state==CAPWAIT || state==CANCEL_WAIT;
    // Cancellation qualification uses local phase state, never shared-service busy.
    wire cap_busy,cap_done,cap_fault,cap_we;
    wire [3:0] cap_error;
    wire [14:0] cap_addr;
    wire [15:0] cap_data;
    wire loc_busy,loc_done,loc_valid,loc_we,loc_wbank;
    wire [3:0] loc_error;
    wire [14:0] loc_waddr;
    wire [15:0] loc_wdata;
    wire aff_busy,aff_done,aff_valid;
    wire geometry_active,pose_start,pose_cancel,pose_done,pose_valid;
    wire [3:0] pose_width,pose_angle,pose_error;
    wire [6:0] pose_xmin,pose_ymin;
    wire locator_rd_bank;
    wire [14:0] locator_rd_addr,geometry_rd_addr;
    wire [239:0] coarse_packet;
    reg [31:0] drain_clocks;
    wire locator_stats_cancel,locator_ncc_cancel;
    wire local_active=state!=IDLE || cap_busy || loc_busy;
    wire cancel_pulse=local_active && !locked && !cancel_seen && (I_cancel || I_start);
    wire cleanup=state==CANCEL_WAIT;
    assign O_stats_cancel=locator_stats_cancel||cleanup;
    assign O_ncc_cancel=locator_ncc_cancel||cleanup;
    assign {O_ty,O_by,O_ay,O_tx,O_bx,O_ax}=coarse_packet;
    assign aff_busy=geometry_active;
    assign O_ws_rd_bank=locator_rd_bank;
    assign O_ws_rd_addr=locator_rd_addr;
    wire [3:0] aff_error;
    wire [31:0] unused_loc_cycles;
    assign O_busy=state!=IDLE || locked || geometry_active || cap_busy || loc_busy;
    assign O_idle=state==IDLE && !locked && !cap_busy && !loc_busy && !aff_busy && !I_stats_busy && !I_ncc_busy && !I_shared_service_busy;
    assign O_frame_lock=O_busy;
    assign O_phase=locked?3'd7:state;
    assign O_ws_we=!cancel_pulse && (capture_active?cap_we:loc_we);
    assign O_ws_wbank=capture_active?1'b0:loc_wbank;
    assign O_ws_waddr=capture_active?cap_addr:loc_waddr;
    assign O_ws_wdata=capture_active?cap_data:loc_wdata;

    pcb_gray_coarse_capture #(.WAIT_TIMEOUT(PIXEL_TIMEOUT)) capture(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(state==CAPSTART && !cancel_pulse),
        .I_cancel(cancel_pulse && capture_active),.I_frame_valid(I_frame_valid),
        .O_pixel_request(O_pixel_request),.O_pixel_x(O_pixel_x),.O_pixel_y(O_pixel_y),
        .I_pixel_ready(I_pixel_ready),.I_pixel_valid(I_pixel_valid),.I_pixel_y8(I_pixel_y8),
        .O_ws_we(cap_we),.O_ws_waddr(cap_addr),.O_ws_wdata(cap_data),.O_busy(cap_busy),.O_done(cap_done),
        .O_fault(cap_fault),.O_error(cap_error),.O_samples(O_capture_samples),.O_pixels_written(O_capture_pixels));
    pcb_gray_coarse_locator_ccl_pose_candidate #(.WIDTH_FIRST(WIDTH_FIRST),.WIDTH_LAST(WIDTH_LAST),.ANGLE_FIRST(ANGLE_FIRST),.ANGLE_LAST(ANGLE_LAST),
        .SEARCH_X_MIN(SEARCH_X_MIN),.SEARCH_X_MAX(SEARCH_X_MAX),.SEARCH_Y_MIN(SEARCH_Y_MIN),.SEARCH_Y_MAX(SEARCH_Y_MAX),
        .CENTER_RADIUS(CENTER_RADIUS),.TOTAL_TIMEOUT(COARSE_TIMEOUT)) locator(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(state==LOCSTART && !cancel_pulse),.I_cancel(cancel_pulse),
        .I_ccl_count(I_ccl_count),.I_ccl_boxes(I_ccl_boxes),
        .I_ccl_overflow(I_ccl_overflow),.I_ccl_truncated(I_ccl_truncated),
        .O_busy(loc_busy),.O_done(loc_done),.O_proposal_valid(loc_valid),.O_error(loc_error),
        .O_width_index(O_width_index),.O_angle_index(O_angle_index),.O_pose_index(O_pose_index),
        .O_center_x(O_center_x),.O_center_y(O_center_y),.O_score2_q30(O_score2_q30),.O_runner_score2_q30(O_runner_score2_q30),
        .O_runner_width_index(),.O_runner_angle_index(),.O_runner_center_x(),.O_runner_center_y(),.O_cycles(unused_loc_cycles),.O_candidates(O_coarse_candidates),
        .O_rd_bank(locator_rd_bank),.O_rd_addr(locator_rd_addr),.I_rd_data(I_ws_rd_data),
        .O_pose_start(pose_start),.O_pose_cancel(pose_cancel),.O_pose_width_index(pose_width),.O_pose_angle_index(pose_angle),
        .I_pose_done(pose_done),.I_pose_valid(pose_valid),.I_pose_error(pose_error),.I_pose_xmin(pose_xmin),.I_pose_ymin(pose_ymin),
        .O_stats_start(O_stats_start),.O_stats_cancel(locator_stats_cancel),.O_stats_count_log2(O_stats_count_log2),
        .O_sample_valid(O_sample_valid),.I_sample_ready(I_sample_ready),.O_sample_i(O_sample_i),.O_sample_t(O_sample_t),
        .I_stats_done(I_stats_done),.I_stats_valid(I_stats_valid),.I_stats_error(I_stats_error),.I_stats_covariance(I_stats_covariance),
        .I_stats_variance_i(I_stats_variance_i),.I_stats_variance_t(I_stats_variance_t),.O_ncc_start(O_ncc_start),.O_ncc_cancel(locator_ncc_cancel),
        .O_covariance(O_covariance),.O_variance_i(O_variance_i),.O_variance_t(O_variance_t),
        .I_ncc_done(I_ncc_done),.I_ncc_valid(I_ncc_valid),.I_ncc_score2_q30(I_ncc_score2_q30),.I_ncc_error(I_ncc_error),
        .O_candidate_valid(),.O_candidate_pass(),.O_candidate_width_index(),.O_candidate_angle_index(),.O_candidate_x(),.O_candidate_y(),.O_candidate_score2_q30());
    assign loc_wbank=1'b0;
    assign geometry_active=I_geometry_busy;
    assign O_geometry_pose_start=pose_start;
    assign O_geometry_affine_start=state==AFFSTART&&!cancel_pulse;
    assign O_geometry_cancel=cancel_pulse||pose_cancel||cleanup;
    assign O_geometry_width_index=(state==AFFSTART||state==AFFWAIT)?O_width_index:pose_width;
    assign O_geometry_angle_index=(state==AFFSTART||state==AFFWAIT)?O_angle_index:pose_angle;
    assign O_geometry_center_x=O_center_x;
    assign O_geometry_center_y=O_center_y;
    assign pose_done=I_geometry_pose_done;assign pose_valid=I_geometry_pose_valid;
    assign pose_error=I_geometry_pose_error;assign pose_xmin=I_geometry_xmin;assign pose_ymin=I_geometry_ymin;
    assign aff_done=I_geometry_affine_done;assign aff_valid=I_geometry_affine_valid;
    assign aff_error=I_geometry_affine_error;assign coarse_packet=I_geometry_coarse;
    assign loc_we=I_geometry_ws_we;assign loc_waddr=I_geometry_ws_waddr;assign loc_wdata=I_geometry_ws_wdata;


    task complete_error;
        input [7:0] code;
        begin state<=IDLE;O_done<=1;O_valid<=0;O_no_target<=0;O_error<=code;end
    endtask
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;locked<=0;cancel_seen<=0;cancel_error<=0;drain_clocks<=0;
            O_done<=0;O_valid<=0;O_no_target<=0;O_error<=0;O_cycles<=0;
        end else begin
            O_done<=0;
            if(O_busy)O_cycles<=O_cycles+48'd1;
            if(locked)begin locked<=1;end
            else if(cancel_pulse)begin
                cancel_seen<=1;cancel_error<=I_cancel?8'd2:8'd3;
                O_valid<=0;O_no_target<=0;
                drain_clocks<=0;state<=CANCEL_WAIT;
            end else case(state)
                IDLE:begin
                    cancel_seen<=0;
                    if(I_cancel)O_valid<=0;
                    if(I_start && !I_cancel && O_idle)begin
                        O_valid<=0;O_no_target<=0;O_error<=0;O_cycles<=0;
                        // These outputs are owned by the single shared CCL
                        // through task completion; do not overwrite them early.
                        if(I_ccl_overflow) complete_error(8'h28);
                        else if(I_ccl_truncated) complete_error(8'h29);
                        else if(I_ccl_count>4) complete_error(8'h2a);
                        else if(I_ccl_count==0)begin
                            state<=IDLE;O_done<=1;O_no_target<=1;
                        end else state<=CAPSTART;
                    end
                end
                CAPSTART:state<=CAPWAIT;
                CAPWAIT:if(cap_done)begin
                    if(cap_fault)begin
                        if(cap_busy)locked<=1;
                        complete_error({4'h1,cap_error});
                    end else state<=LOCSTART;
                end
                LOCSTART:state<=LOCWAIT;
                LOCWAIT:if(loc_done)begin
                    if(loc_error)begin
                        cancel_error<={4'h2,loc_error};drain_clocks<=0;state<=CANCEL_WAIT;
                    end
                    else if(!loc_valid)begin state<=IDLE;O_done<=1;O_valid<=0;O_no_target<=1;O_error<=0;end
                    else state<=AFFSTART;
                end
                AFFSTART:state<=AFFWAIT;
                AFFWAIT:if(aff_done)begin
                    if(!aff_valid || aff_error)complete_error({4'h3,aff_error});
                    else begin state<=IDLE;O_done<=1;O_valid<=1;O_no_target<=0;O_error<=0;end
                end
                CANCEL_WAIT:begin
                    // Cancel may coincide with the timeout done pulse. The
                    // sticky locked-fault code still proves ownership is lost.
                    if(cap_fault && cap_busy && (cap_error==4 || cap_error==5 || cap_error==15))begin
                        locked<=1;complete_error({4'h1,cap_error});
                    end else if(!cap_busy && !loc_busy && !geometry_active && !I_stats_busy && !I_ncc_busy && !I_shared_service_busy)complete_error(cancel_error);
                    else if(drain_clocks>=2*PIXEL_TIMEOUT+32)begin
                        locked<=1;complete_error(8'hfe);
                    end else drain_clocks<=drain_clocks+1'b1;
                end
                default:complete_error(8'hff);
            endcase
        end
    end
endmodule
