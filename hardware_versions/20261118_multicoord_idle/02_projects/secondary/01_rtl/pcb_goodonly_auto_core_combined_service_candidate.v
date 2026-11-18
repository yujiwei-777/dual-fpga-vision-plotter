`timescale 1ns/1ps
// Frame-owned GOOD-only PCB engine. One physical sampler, statistics engine
// and NCC engine serve both stages. No legacy classifier can publish here.
// Cancellation releases ownership only after all accepted reads have drained;
// a subordinate LOCKED fault deliberately keeps busy asserted until reset.
module pcb_goodonly_auto_core_affine6_sharedrf_ccl #(
    parameter GEOMETRY_ROM="combined_geometry_warp_outline_rom_2048.mem",
    parameter integer PIXEL_TIMEOUT=4096,
    parameter integer WIDTH_FIRST=0,WIDTH_LAST=13,
    parameter integer ANGLE_FIRST=0,ANGLE_LAST=9,
    parameter integer SEARCH_X_MIN=0,SEARCH_X_MAX=127,
    parameter integer SEARCH_Y_MIN=0,SEARCH_Y_MAX=71
)(
    input wire clk,rst_n,start,cancel,frame_valid,model_valid,
    input wire [2:0] I_ccl_count,
    input wire [255:0] I_ccl_boxes,
    input wire I_ccl_overflow,I_ccl_truncated,
    input wire [31:0] job_id,
    output wire busy,frame_lock,
    output reg done,result_valid,no_target,
    output reg [1:0] status,
    output reg [15:0] error,
    output reg bbox_valid,
    output reg [10:0] xmin,xmax,
    output reg [9:0] ymin,ymax,
    output reg [11:0] detail_score,
    output reg [15:0] outline_support,
    output wire pixel_request,
    output wire [10:0] pixel_x,
    output wire [9:0] pixel_y,
    input wire pixel_ready,pixel_valid,
    input wire [7:0] pixel_y8,
    output wire ws_we,ws_wbank,
    output wire [14:0] ws_waddr,
    output wire [15:0] ws_wdata,
    output wire ws_rd_bank,
    output wire [14:0] ws_rd_addr,
    input wire [15:0] ws_rd_data,
    output wire [7:0] phase,
    output reg [47:0] cycles
);
    localparam [2:0] IDLE=0,CSTART=1,CWAIT=2,BSTART=3,BWAIT=4,BLOCKED=5,COARSE_BLOCKED=6;
    reg [2:0] state;
    reg [31:0] job_q;
    reg cancelled;
    wire backend_owner=state==BSTART||state==BWAIT||state==BLOCKED;
    wire coarse_busy,coarse_idle,coarse_done,coarse_valid,coarse_none;
    wire [7:0] coarse_error;
    wire [2:0] coarse_phase;
    wire [239:0] coarse_packet;
    wire c_pixel_req,c_we,c_wbank,c_rbank;
    wire [10:0] c_pixel_x;
    wire [9:0] c_pixel_y;
    wire [14:0] c_waddr,c_raddr;
    wire [15:0] c_wdata;
    wire c_stats_start,c_stats_cancel,c_sample_valid,c_ncc_start,c_ncc_cancel;
    wire [3:0] c_stats_log2;
    wire [7:0] c_sample_i,c_sample_t;
    wire signed [35:0] c_cov;
    wire [35:0] c_vi,c_vt;
    wire backend_busy,backend_idle,backend_done,backend_valid,backend_bbox;
    wire [1:0] backend_status;
    wire [15:0] backend_error,b_outline;
    wire [4:0] backend_phase;
    wire [10:0] b_xmin,b_xmax,b_pixel_x;
    wire [9:0] b_ymin,b_ymax,b_pixel_y;
    wire [11:0] b_detail;
    wire b_pixel_req,b_we,b_wbank,b_rbank;
    wire [14:0] b_waddr,b_raddr;
    wire [15:0] b_wdata;
    wire b_stats_start,b_stats_cancel,b_sample_valid,b_ncc_start,b_ncc_cancel;
    wire [3:0] b_stats_log2;
    wire [7:0] b_sample_i,b_sample_t;
    wire signed [35:0] b_cov;
    wire [35:0] b_vi,b_vt;
    wire stats_busy,stats_ready,stats_done,stats_valid;
    wire [3:0] stats_error;
    wire signed [35:0] covariance;
    wire [35:0] variance_i,variance_t;
    wire ncc_busy,ncc_done,ncc_valid,ncc_positive;
    wire [3:0] ncc_error;
    wire [30:0] ncc_score;
    wire warp_start,warp_cancel,warp_busy,warp_done,warp_valid,warp_complete;
    wire [3:0] warp_error;
    wire [7:0] warp_x,warp_gray;
    wire [6:0] warp_y;
    wire warp_fine,warp_coarse,warp_half;
    wire [239:0] warp_packet;
    wire signed [31:0] warp_project_x,warp_project_y;
    wire signed [63:0] warp_source_x,warp_source_y;
    wire warp_pixel_request,warp_pixel_ready,warp_pixel_valid;
    wire [10:0] warp_pixel_x;
    wire [9:0] warp_pixel_y;
    wire [7:0] warp_pixel_y8;
    wire service_ready,service_busy,service_fault,dispatch_busy,dispatch_fault;
    wire [2:0] service_owner;
    wire [8:0] service_error,raw_diagnostic,ncc_diagnostic,coarse_diagnostic;
    wire [6:0] service_request,service_dispatch,service_pending,service_inflight;
    wire [6:0] service_done;
    wire shared_busy=service_busy||dispatch_busy||service_fault||dispatch_fault;
    wire c_pose_start,c_affine_start,c_geometry_cancel,c_pose_done,c_pose_valid,c_affine_done,c_affine_valid;
    wire [3:0] c_geometry_width,c_geometry_angle,c_pose_error,c_affine_error;
    wire [6:0] c_geometry_x,c_geometry_y,c_geometry_xmin,c_geometry_ymin;
    wire [239:0] service_coarse;
    wire service_ws_we;
    wire [14:0] service_ws_addr;
    wire [15:0] service_ws_data;
    wire b_geometry_start,b_geometry_cancel,b_geometry_done,b_geometry_valid,b_geometry_convex,b_geometry_inside;
    wire [315:0] b_geometry_corners;
    wire [3:0] b_geometry_error;
    wire c_geometry_busy=(service_busy&&service_owner==1)||(|(service_pending[1:0]|service_inflight[1:0]));
    wire b_geometry_busy=(service_busy&&service_owner==2)||service_pending[2]||service_inflight[2];
    wire outline_start,outline_cancel,outline_board_convex,outline_board_inside;
    wire outline_done,outline_valid,outline_registration,outline_complete,outline_busy;
    wire [3:0] outline_error;wire [15:0] outline_mask;
    wire outline_ram_request,outline_ram_bank,outline_ram_ready,outline_ram_valid,outline_ram_idle;
    wire [14:0] outline_ram_addr;wire [15:0] outline_ram_data;
    wire outline_stats_start,outline_stats_cancel,outline_sample_valid,outline_ncc_start,outline_ncc_cancel;
    wire [3:0] outline_stats_log2;wire [7:0] outline_sample_i,outline_sample_t;
    wire selected_outline=service_owner==4;
    wire warp_service_busy;
    assign warp_busy=(warp_service_busy||service_pending[3]||service_inflight[3])&&!warp_done;
    wire context_start,context_cancel,context_epoch,context_invalidate,context_busy,context_done;
    wire [2:0] context_command,context_slot;
    wire [1:0] context_choice,context_error;
    wire signed [25:0] context_increment;
    wire context_ready=service_ready&&!service_pending[6]&&!service_inflight[6]&&!dispatch_fault;
    wire abort_request=cancel||(start&&state!=IDLE)||dispatch_fault;
    wire service_cancel=abort_request||(backend_owner?b_geometry_cancel:c_geometry_cancel)||warp_cancel||outline_cancel||context_cancel;
    reg drain_busy_q,completion_pending;
    wire subordinate_busy=coarse_busy||backend_busy||shared_busy||stats_busy||ncc_busy;
    assign busy=state!=IDLE||drain_busy_q||completion_pending;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)drain_busy_q<=0;
        else drain_busy_q<=subordinate_busy;
    end
    assign frame_lock=busy;
    assign phase={backend_owner,2'd0,backend_owner?backend_phase:{2'd0,coarse_phase}};
    assign pixel_request=backend_owner?b_pixel_req:c_pixel_req;
    assign pixel_x=backend_owner?b_pixel_x:c_pixel_x;
    assign pixel_y=backend_owner?b_pixel_y:c_pixel_y;
    assign ws_we=backend_owner?b_we:c_we;
    assign ws_wbank=backend_owner?b_wbank:c_wbank;
    assign ws_waddr=backend_owner?b_waddr:c_waddr;
    assign ws_wdata=backend_owner?b_wdata:c_wdata;
    assign ws_rd_bank=backend_owner?b_rbank:c_rbank;
    assign ws_rd_addr=backend_owner?b_raddr:c_raddr;
    pcb_auto_coarse_stage_ccl_service_candidate #(.GEOMETRY_ROM(GEOMETRY_ROM),.PIXEL_TIMEOUT(PIXEL_TIMEOUT),
        .WIDTH_FIRST(WIDTH_FIRST),.WIDTH_LAST(WIDTH_LAST),.ANGLE_FIRST(ANGLE_FIRST),.ANGLE_LAST(ANGLE_LAST),
        .SEARCH_X_MIN(SEARCH_X_MIN),.SEARCH_X_MAX(SEARCH_X_MAX),.SEARCH_Y_MIN(SEARCH_Y_MIN),.SEARCH_Y_MAX(SEARCH_Y_MAX)) coarse(
        .I_clk(clk),.I_rst_n(rst_n),.I_start(state==CSTART&&!abort_request),
        .I_cancel(!backend_owner&&abort_request),.I_frame_valid(frame_valid),
        .I_ccl_count(I_ccl_count),.I_ccl_boxes(I_ccl_boxes),
        .I_ccl_overflow(I_ccl_overflow),.I_ccl_truncated(I_ccl_truncated),
        .I_shared_service_busy(shared_busy),.I_geometry_busy(c_geometry_busy),
        .O_geometry_pose_start(c_pose_start),.O_geometry_affine_start(c_affine_start),.O_geometry_cancel(c_geometry_cancel),
        .O_geometry_width_index(c_geometry_width),.O_geometry_angle_index(c_geometry_angle),
        .O_geometry_center_x(c_geometry_x),.O_geometry_center_y(c_geometry_y),
        .I_geometry_pose_done(c_pose_done),.I_geometry_pose_valid(c_pose_valid),.I_geometry_pose_error(c_pose_error),
        .I_geometry_xmin(c_geometry_xmin),.I_geometry_ymin(c_geometry_ymin),
        .I_geometry_affine_done(c_affine_done),.I_geometry_affine_valid(c_affine_valid),.I_geometry_affine_error(c_affine_error),
        .I_geometry_coarse(service_coarse),.I_geometry_ws_we(service_ws_we),
        .I_geometry_ws_waddr(service_ws_addr),.I_geometry_ws_wdata(service_ws_data),
        .O_busy(coarse_busy),.O_idle(coarse_idle),.O_frame_lock(),.O_done(coarse_done),.O_valid(coarse_valid),
        .O_no_target(coarse_none),.O_error(coarse_error),.O_phase(coarse_phase),.O_cycles(),
        .O_pixel_request(c_pixel_req),.O_pixel_x(c_pixel_x),.O_pixel_y(c_pixel_y),
        .I_pixel_ready(pixel_ready&&!backend_owner),.I_pixel_valid(pixel_valid&&!backend_owner),.I_pixel_y8(pixel_y8),
        .O_ws_we(c_we),.O_ws_wbank(c_wbank),.O_ws_waddr(c_waddr),.O_ws_wdata(c_wdata),
        .O_ws_rd_bank(c_rbank),.O_ws_rd_addr(c_raddr),.I_ws_rd_data(ws_rd_data),
        .O_stats_start(c_stats_start),.O_stats_cancel(c_stats_cancel),.O_stats_count_log2(c_stats_log2),
        .O_sample_valid(c_sample_valid),.I_sample_ready(stats_ready),.O_sample_i(c_sample_i),.O_sample_t(c_sample_t),
        .I_stats_done(stats_done),.I_stats_valid(stats_valid),.I_stats_busy(stats_busy),.I_stats_error(stats_error),
        .I_stats_covariance(covariance),.I_stats_variance_i(variance_i),.I_stats_variance_t(variance_t),
        .O_ncc_start(c_ncc_start),.O_ncc_cancel(c_ncc_cancel),.O_covariance(c_cov),.O_variance_i(c_vi),.O_variance_t(c_vt),
        .I_ncc_done(ncc_done),.I_ncc_valid(ncc_valid),.I_ncc_busy(ncc_busy),.I_ncc_score2_q30(ncc_score),.I_ncc_error(ncc_error),
        .O_ax(coarse_packet[39:0]),.O_bx(coarse_packet[79:40]),.O_tx(coarse_packet[119:80]),
        .O_ay(coarse_packet[159:120]),.O_by(coarse_packet[199:160]),.O_ty(coarse_packet[239:200]),
        .O_width_index(),.O_angle_index(),.O_pose_index(),.O_center_x(),.O_center_y(),.O_score2_q30(),
        .O_runner_score2_q30(),.O_coarse_candidates(),.O_capture_samples(),.O_capture_pixels());
    pcb_goodonly_backend_combined_external_candidate #(.PIXEL_TIMEOUT(PIXEL_TIMEOUT)) backend(
        .I_clk(clk),.I_rst_n(rst_n),.I_start(state==BSTART&&!abort_request),.I_cancel(backend_owner&&abort_request),
        .I_shared_service_busy(shared_busy),.I_raw_geometry_busy(b_geometry_busy),
        .O_context_start(context_start),.O_context_cancel(context_cancel),.O_context_epoch_start(context_epoch),
        .O_context_invalidate(context_invalidate),.O_context_command(context_command),.O_context_slot(context_slot),
        .O_context_choice(context_choice),.O_context_increment(context_increment),
        .I_context_ready(context_ready),.I_context_busy(context_busy||service_pending[6]||service_inflight[6]),
        .I_context_done(context_done),.I_context_error(context_error),
        .O_raw_geometry_start(b_geometry_start),.O_raw_geometry_cancel(b_geometry_cancel),.O_raw_geometry_corners(b_geometry_corners),
        .I_raw_geometry_done(b_geometry_done),.I_raw_geometry_valid(b_geometry_valid),
        .I_raw_geometry_convex(b_geometry_convex),.I_raw_geometry_inside(b_geometry_inside),.I_raw_geometry_error(b_geometry_error),
        .O_outline_start(outline_start),.O_outline_cancel(outline_cancel),
        .O_outline_board_convex(outline_board_convex),.O_outline_board_inside(outline_board_inside),
        .I_outline_ready(!outline_busy&&!service_pending[4]&&!service_inflight[4]),
        .I_outline_idle(!outline_busy&&!service_pending[4]&&!service_inflight[4]),
        .I_outline_done(outline_done),.I_outline_valid(outline_valid),.I_outline_registration(outline_registration),
        .I_outline_complete(outline_complete),.I_outline_error(outline_error),.I_outline_mask(outline_mask),
        .I_outline_ram_request(outline_ram_request),.I_outline_ram_bank(outline_ram_bank),.I_outline_ram_addr(outline_ram_addr),
        .O_outline_ram_ready(outline_ram_ready),.O_outline_ram_valid(outline_ram_valid),
        .O_outline_ram_idle(outline_ram_idle),.O_outline_ram_data(outline_ram_data),
        .I_job_id(job_q[16:0]),.I_frame_valid(frame_valid),.I_model_valid(model_valid),.I_initial_canonical_valid(1'b0),
        .I_coarse_packet(coarse_packet),.O_busy(backend_busy),.O_idle(backend_idle),.O_frame_lock(),
        .O_done(backend_done),.O_result_valid(backend_valid),.O_status(backend_status),.O_error(backend_error),
        .O_phase(backend_phase),.O_cycles(),.O_bbox_valid(backend_bbox),.O_xmin(b_xmin),.O_xmax(b_xmax),
        .O_ymin(b_ymin),.O_ymax(b_ymax),.O_detail_score(b_detail),.O_outline_support(b_outline),
        .O_registration_valid(),.O_outline_complete(),.O_fine_evaluations(),.O_fine_score2_q30(),
        .O_pixel_request(b_pixel_req),.O_pixel_x(b_pixel_x),.O_pixel_y(b_pixel_y),
        .I_pixel_ready(pixel_ready&&backend_owner),.I_pixel_valid(pixel_valid&&backend_owner),.I_pixel_y8(pixel_y8),
        .O_warp_start(warp_start),.O_warp_cancel(warp_cancel),.O_warp_x(warp_x),.O_warp_y(warp_y),
        .O_warp_use_fine(warp_fine),.O_warp_apply_coarse(warp_coarse),.O_warp_half_image(warp_half),
        .O_warp_coarse(warp_packet),.I_warp_busy(warp_busy),.I_warp_done(warp_done),
        .I_warp_valid(warp_valid),.I_warp_sample_complete(warp_complete),.I_warp_error(warp_error),.I_warp_gray(warp_gray),
        .I_warp_project_x_q16(warp_project_x),.I_warp_project_y_q16(warp_project_y),
        .I_warp_source_x_q28(warp_source_x),.I_warp_source_y_q28(warp_source_y),
        .I_warp_pixel_request(warp_pixel_request),.I_warp_pixel_x(warp_pixel_x),.I_warp_pixel_y(warp_pixel_y),
        .O_warp_pixel_ready(warp_pixel_ready),.O_warp_pixel_valid(warp_pixel_valid),.O_warp_pixel_y8(warp_pixel_y8),
        .O_stats_start(b_stats_start),.O_stats_cancel(b_stats_cancel),.O_stats_count_log2(b_stats_log2),
        .O_stats_sample_valid(b_sample_valid),.O_stats_i(b_sample_i),.O_stats_t(b_sample_t),
        .I_stats_ready(stats_ready),.I_stats_busy(stats_busy),.I_stats_done(stats_done),.I_stats_valid(stats_valid),
        .I_stats_error(stats_error),.I_covariance(covariance),.I_variance_i(variance_i),.I_variance_t(variance_t),
        .O_ncc_start(b_ncc_start),.O_ncc_cancel(b_ncc_cancel),.O_ncc_covariance(b_cov),.O_ncc_variance_i(b_vi),
        .O_ncc_variance_t(b_vt),.I_ncc_busy(ncc_busy),.I_ncc_done(ncc_done),.I_ncc_valid(ncc_valid),
        .I_ncc_positive(ncc_positive),.I_ncc_score2_q30(ncc_score),.I_ncc_error(ncc_error),
        .O_ws_we(b_we),.O_ws_wbank(b_wbank),.O_ws_waddr(b_waddr),.O_ws_wdata(b_wdata),
        .O_ws_rd_bank(b_rbank),.O_ws_rd_addr(b_raddr),.I_ws_rd_data(ws_rd_data));
    pcb_gray_ncc_statistics_dsp statistics(
        .I_clk(clk),.I_rst_n(rst_n),.I_start(selected_outline?outline_stats_start:(backend_owner?b_stats_start:c_stats_start)),
        .I_cancel(selected_outline?outline_stats_cancel:(backend_owner?b_stats_cancel:c_stats_cancel)),.I_count_log2(selected_outline?outline_stats_log2:(backend_owner?b_stats_log2:c_stats_log2)),
        .I_sample_valid(selected_outline?outline_sample_valid:(backend_owner?b_sample_valid:c_sample_valid)),.O_sample_ready(stats_ready),
        .I_sample_i(selected_outline?outline_sample_i:(backend_owner?b_sample_i:c_sample_i)),.I_sample_t(selected_outline?outline_sample_t:(backend_owner?b_sample_t:c_sample_t)),
        .O_mul_a(),.O_mul_b(),.I_mul_product(16'd0),.O_busy(stats_busy),.O_done(stats_done),.O_valid(stats_valid),
        .O_error(stats_error),.O_covariance(covariance),.O_variance_i(variance_i),.O_variance_t(variance_t),.O_samples());
    assign service_request={context_start,1'b0,outline_start,warp_start,b_geometry_start,c_affine_start,c_pose_start};
    assign service_done={context_done,1'b0,outline_done,warp_done,b_geometry_done,c_affine_done,c_pose_done};
    function [3:0] raw_error_map;
        input [8:0] code;
        begin case(code)
            0:raw_error_map=0;9'h104:raw_error_map=4;9'h108:raw_error_map=6;
            9'h109:raw_error_map=7;9'h10a:raw_error_map=8;default:raw_error_map=15;
        endcase end
    endfunction
    assign b_geometry_error=raw_error_map(raw_diagnostic);
    pcb_combined_service_dispatch_candidate dispatcher(
        .I_clk(clk),.I_rst_n(rst_n),.I_cancel(service_cancel),.I_request(service_request),.I_done(service_done),
        .I_service_ready(service_ready),.O_start(service_dispatch),.O_pending(service_pending),
        .O_inflight(service_inflight),.O_busy(dispatch_busy),.O_fault(dispatch_fault));
    pcb_combined_shared_service_candidate #(.ROM_FILE(GEOMETRY_ROM),.PIXEL_TIMEOUT(PIXEL_TIMEOUT)) arithmetic_service(
        .I_clk(clk),.I_rst_n(rst_n),.I_cancel(service_cancel),
        .I_context_start(service_dispatch[6]),.I_context_epoch_start(context_epoch),.I_context_invalidate(context_invalidate),
        .I_context_command(context_command),.I_context_slot(context_slot),.I_context_choice(context_choice),
        .I_context_increment(context_increment),.O_context_busy(context_busy),.O_context_done(context_done),.O_context_error(context_error),
        .I_pose_start(service_dispatch[0]),.I_affine_start(service_dispatch[1]),.I_raw_start(service_dispatch[2]),.I_warp_start(service_dispatch[3]),.I_outline_start(service_dispatch[4]),
        .I_width_index(c_geometry_width),.I_angle_index(c_geometry_angle),
        .I_center_x(c_geometry_x),.I_center_y(c_geometry_y),.I_corners(b_geometry_corners),
        .O_ready(service_ready),.O_busy(service_busy),.O_owner(service_owner),
        .O_pose_done(c_pose_done),.O_pose_valid(c_pose_valid),.O_pose_error(c_pose_error),
        .O_xmin(c_geometry_xmin),.O_ymin(c_geometry_ymin),
        .O_affine_done(c_affine_done),.O_affine_valid(c_affine_valid),.O_affine_error(c_affine_error),
        .O_coarse(service_coarse),.O_coarse_diagnostic_error(coarse_diagnostic),
        .O_raw_done(b_geometry_done),.O_raw_valid(b_geometry_valid),.O_raw_inside(b_geometry_inside),
        .O_raw_convex(b_geometry_convex),.O_raw_error(raw_diagnostic),
        .O_ws_we(service_ws_we),.O_ws_waddr(service_ws_addr),.O_ws_wdata(service_ws_data),
        .I_x(warp_x),.I_y(warp_y),.I_use_fine(warp_fine),.I_apply_coarse(warp_coarse),.I_half_image(warp_half),
        .I_coarse(warp_packet),.O_warp_busy(warp_service_busy),.O_warp_done(warp_done),
        .O_warp_valid(warp_valid),.O_warp_error(warp_error),.O_warp_diagnostic_error(),
        .O_gray(warp_gray),.O_sample_complete(warp_complete),.O_tap_inside(),
        .O_project_x_q16(warp_project_x),.O_project_y_q16(warp_project_y),.O_source_x_q28(warp_source_x),.O_source_y_q28(warp_source_y),
        .O_pixel_request(warp_pixel_request),.O_pixel_x(warp_pixel_x),.O_pixel_y(warp_pixel_y),
        .I_pixel_ready(warp_pixel_ready),.I_pixel_valid(warp_pixel_valid),.I_pixel_y8(warp_pixel_y8),
        .I_board_convex(outline_board_convex),.I_board_inside(outline_board_inside),.O_outline_busy(outline_busy),
        .O_outline_done(outline_done),.O_outline_valid(outline_valid),.O_registration(outline_registration),
        .O_outline_complete(outline_complete),.O_outline_mask(outline_mask),.O_outline_error(outline_error),.O_outline_diagnostic_error(),
        .O_outline_ram_request(outline_ram_request),.O_outline_ram_bank(outline_ram_bank),.O_outline_ram_addr(outline_ram_addr),
        .I_outline_ram_ready(outline_ram_ready),.I_outline_ram_valid(outline_ram_valid),.I_outline_ram_idle(outline_ram_idle),.I_outline_ram_data(outline_ram_data),
        .O_outline_stats_start(outline_stats_start),.O_outline_stats_cancel(outline_stats_cancel),.O_outline_stats_count_log2(outline_stats_log2),
        .O_outline_sample_valid(outline_sample_valid),.O_outline_sample_i(outline_sample_i),.O_outline_sample_t(outline_sample_t),
        .I_stats_ready(stats_ready),.I_stats_busy(stats_busy),.I_stats_done(stats_done),.I_stats_valid(stats_valid),.I_stats_error(stats_error),
        .I_covariance(covariance),.I_variance_i(variance_i),.I_variance_t(variance_t),
        .O_outline_ncc_start(outline_ncc_start),.O_outline_ncc_cancel(outline_ncc_cancel),
        .I_ncc_busy(ncc_busy),.I_ncc_done(ncc_done),.I_ncc_valid(ncc_valid),.I_ncc_positive(ncc_positive),.I_ncc_score(ncc_score),.I_ncc_error(ncc_error),.O_service_fault(service_fault),.O_service_error(service_error));
    pcb_ncc_normalize_1024_fraction_v4 normalization(
        .I_clk(clk),.I_rst_n(rst_n),.I_start(selected_outline?outline_ncc_start:(backend_owner?b_ncc_start:c_ncc_start)),
        .I_cancel(selected_outline?outline_ncc_cancel:(backend_owner?b_ncc_cancel:c_ncc_cancel)),.I_covariance(selected_outline?covariance:(backend_owner?b_cov:c_cov)),
        .I_variance_i(selected_outline?variance_i:(backend_owner?b_vi:c_vi)),.I_variance_t(selected_outline?variance_t:(backend_owner?b_vt:c_vt)),
        .O_busy(ncc_busy),.O_done(ncc_done),.O_result_valid(ncc_valid),.O_positive(ncc_positive),
        .O_score2_q30(ncc_score),.O_error(ncc_error),.O_cycles());

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;job_q<=0;cancelled<=0;done<=0;result_valid<=0;no_target<=0;
            completion_pending<=0;
            status<=2;error<=0;bbox_valid<=0;xmin<=0;xmax<=0;ymin<=0;ymax<=0;
            detail_score<=0;outline_support<=0;cycles<=0;
        end else begin
            done<=0;
            if(completion_pending&&state==IDLE&&!subordinate_busy)begin
                completion_pending<=0;done<=1;
            end
            if(state!=IDLE)cycles<=cycles+48'd1;
            if(state!=IDLE&&abort_request)begin cancelled<=1;result_valid<=0;bbox_valid<=0;end
            case(state)
                IDLE:if(start&&!cancel&&!completion_pending&&!drain_busy_q&&coarse_idle&&backend_idle)begin
                    job_q<=job_id;cancelled<=0;result_valid<=0;no_target<=0;
                    status<=2;error<=0;bbox_valid<=0;detail_score<=0;outline_support<=0;cycles<=0;
                    if(frame_valid&&model_valid)state<=CSTART;
                    else begin done<=1;error<=16'h0101;end
                end
                CSTART:if(abort_request)begin state<=IDLE;completion_pending<=1;error<=16'h0002;end else state<=CWAIT;
                CWAIT:if(coarse_done)begin
                    if(cancelled||abort_request||coarse_error||!coarse_valid)begin
                        if(coarse_phase==3'd7)begin state<=COARSE_BLOCKED;done<=1;end
                        else begin state<=IDLE;completion_pending<=1;end
                        status<=2;result_valid<=0;bbox_valid<=0;
                        no_target<=coarse_none&&!cancelled&&!abort_request;
                        error<=cancelled||abort_request?16'h0002:{8'd0,coarse_error};
                    end else state<=BSTART;
                end
                BSTART:if(abort_request)begin state<=IDLE;completion_pending<=1;error<=16'h0002;end else state<=BWAIT;
                BWAIT:if(backend_done)begin
                    state<=backend_idle?IDLE:BLOCKED;
                    if(backend_idle)completion_pending<=1;else done<=1;
                    status<=cancelled||abort_request?2'd2:backend_status;
                    error<=cancelled||abort_request?16'h0002:backend_error;
                    result_valid<=backend_valid&&!cancelled&&!abort_request;
                    bbox_valid<=backend_bbox&&backend_valid&&!cancelled&&!abort_request;
                    xmin<=b_xmin;xmax<=b_xmax;ymin<=b_ymin;ymax<=b_ymax;
                    detail_score<=b_detail;outline_support<=b_outline;
                end
                BLOCKED,COARSE_BLOCKED:begin result_valid<=0;bbox_valid<=0;end
                default:begin state<=IDLE;result_valid<=0;bbox_valid<=0;error<=16'hffff;done<=1;end
            endcase
        end
    end
endmodule
