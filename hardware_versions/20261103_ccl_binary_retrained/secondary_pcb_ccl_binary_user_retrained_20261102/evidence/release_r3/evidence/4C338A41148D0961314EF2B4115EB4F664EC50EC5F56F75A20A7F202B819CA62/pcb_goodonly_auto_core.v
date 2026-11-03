`timescale 1ns/1ps
// Frame-owned GOOD-only PCB engine. One physical sampler, statistics engine
// and NCC engine serve both stages. No legacy classifier can publish here.
// Cancellation releases ownership only after all accepted reads have drained;
// a subordinate LOCKED fault deliberately keeps busy asserted until reset.
module pcb_goodonly_auto_core #(
    parameter GEOMETRY_ROM="coarse_engine_rom.mem",
    parameter integer PIXEL_TIMEOUT=4096,
    parameter integer WIDTH_FIRST=0,WIDTH_LAST=13,
    parameter integer ANGLE_FIRST=0,ANGLE_LAST=9,
    parameter integer SEARCH_X_MIN=0,SEARCH_X_MAX=127,
    parameter integer SEARCH_Y_MIN=0,SEARCH_Y_MAX=71
)(
    input wire clk,rst_n,start,cancel,frame_valid,model_valid,
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
    localparam [2:0] IDLE=0,CSTART=1,CWAIT=2,BSTART=3,BWAIT=4,BLOCKED=5;
    reg [2:0] state;
    reg [31:0] job_q;
    reg [239:0] coarse_q;
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
    wire [255:0] fine_parameters;
    wire [239:0] warp_packet;
    wire signed [31:0] warp_project_x,warp_project_y;
    wire signed [63:0] warp_source_x,warp_source_y;
    wire warp_pixel_request,warp_pixel_ready,warp_pixel_valid;
    wire [10:0] warp_pixel_x;
    wire [9:0] warp_pixel_y;
    wire [7:0] warp_pixel_y8;
    wire abort_request=cancel||(start&&state!=IDLE);
    assign busy=state!=IDLE||coarse_busy||backend_busy;
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
    pcb_auto_coarse_stage_shared #(.GEOMETRY_ROM(GEOMETRY_ROM),.PIXEL_TIMEOUT(PIXEL_TIMEOUT),
        .WIDTH_FIRST(WIDTH_FIRST),.WIDTH_LAST(WIDTH_LAST),.ANGLE_FIRST(ANGLE_FIRST),.ANGLE_LAST(ANGLE_LAST),
        .SEARCH_X_MIN(SEARCH_X_MIN),.SEARCH_X_MAX(SEARCH_X_MAX),.SEARCH_Y_MIN(SEARCH_Y_MIN),.SEARCH_Y_MAX(SEARCH_Y_MAX)) coarse(
        .I_clk(clk),.I_rst_n(rst_n),.I_start(state==CSTART&&!abort_request),
        .I_cancel(!backend_owner&&abort_request),.I_frame_valid(frame_valid),
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
    pcb_goodonly_backend_shared #(.PIXEL_TIMEOUT(PIXEL_TIMEOUT)) backend(
        .I_clk(clk),.I_rst_n(rst_n),.I_start(state==BSTART&&!abort_request),.I_cancel(backend_owner&&abort_request),
        .I_job_id(job_q[16:0]),.I_frame_valid(frame_valid),.I_model_valid(model_valid),.I_initial_canonical_valid(1'b0),
        .I_coarse_packet(coarse_q),.O_busy(backend_busy),.O_idle(backend_idle),.O_frame_lock(),
        .O_done(backend_done),.O_result_valid(backend_valid),.O_status(backend_status),.O_error(backend_error),
        .O_phase(backend_phase),.O_cycles(),.O_bbox_valid(backend_bbox),.O_xmin(b_xmin),.O_xmax(b_xmax),
        .O_ymin(b_ymin),.O_ymax(b_ymax),.O_detail_score(b_detail),.O_outline_support(b_outline),
        .O_registration_valid(),.O_outline_complete(),.O_fine_parameters(),.O_fine_evaluations(),.O_fine_score2_q30(),
        .O_pixel_request(b_pixel_req),.O_pixel_x(b_pixel_x),.O_pixel_y(b_pixel_y),
        .I_pixel_ready(pixel_ready&&backend_owner),.I_pixel_valid(pixel_valid&&backend_owner),.I_pixel_y8(pixel_y8),
        .O_warp_start(warp_start),.O_warp_cancel(warp_cancel),.O_warp_x(warp_x),.O_warp_y(warp_y),
        .O_warp_use_fine(warp_fine),.O_warp_apply_coarse(warp_coarse),.O_warp_half_image(warp_half),
        .O_warp_fine(fine_parameters),.O_warp_coarse(warp_packet),.I_warp_busy(warp_busy),.I_warp_done(warp_done),
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
    serial_integer_warp_gray_shared_dsp #(.WAIT_TIMEOUT(PIXEL_TIMEOUT)) sampler(
        .I_clk(clk),.I_rst_n(rst_n),.I_start(warp_start),.I_cancel(warp_cancel),.I_x(warp_x),.I_y(warp_y),
        .I_use_fine(warp_fine),.I_apply_coarse(warp_coarse),.I_half_image(warp_half),.I_fine(fine_parameters),.I_coarse(warp_packet),
        .O_busy(warp_busy),.O_done(warp_done),.O_valid(warp_valid),.O_error(warp_error),.O_gray(warp_gray),
        .O_sample_complete(warp_complete),.O_tap_inside(),.O_pixel_request(warp_pixel_request),
        .O_pixel_x(warp_pixel_x),.O_pixel_y(warp_pixel_y),.I_pixel_ready(warp_pixel_ready),
        .I_pixel_valid(warp_pixel_valid),.I_pixel_y8(warp_pixel_y8),.O_project_x_q16(warp_project_x),
        .O_project_y_q16(warp_project_y),.O_source_x_q28(warp_source_x),.O_source_y_q28(warp_source_y));
    pcb_gray_ncc_statistics_dsp statistics(
        .I_clk(clk),.I_rst_n(rst_n),.I_start(backend_owner?b_stats_start:c_stats_start),
        .I_cancel(backend_owner?b_stats_cancel:c_stats_cancel),.I_count_log2(backend_owner?b_stats_log2:c_stats_log2),
        .I_sample_valid(backend_owner?b_sample_valid:c_sample_valid),.O_sample_ready(stats_ready),
        .I_sample_i(backend_owner?b_sample_i:c_sample_i),.I_sample_t(backend_owner?b_sample_t:c_sample_t),
        .O_mul_a(),.O_mul_b(),.I_mul_product(16'd0),.O_busy(stats_busy),.O_done(stats_done),.O_valid(stats_valid),
        .O_error(stats_error),.O_covariance(covariance),.O_variance_i(variance_i),.O_variance_t(variance_t),.O_samples());
    pcb_ncc_normalize_1024_fraction_v4 normalization(
        .I_clk(clk),.I_rst_n(rst_n),.I_start(backend_owner?b_ncc_start:c_ncc_start),
        .I_cancel(backend_owner?b_ncc_cancel:c_ncc_cancel),.I_covariance(backend_owner?b_cov:c_cov),
        .I_variance_i(backend_owner?b_vi:c_vi),.I_variance_t(backend_owner?b_vt:c_vt),
        .O_busy(ncc_busy),.O_done(ncc_done),.O_result_valid(ncc_valid),.O_positive(ncc_positive),
        .O_score2_q30(ncc_score),.O_error(ncc_error),.O_cycles());
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;job_q<=0;coarse_q<=0;cancelled<=0;done<=0;result_valid<=0;no_target<=0;
            status<=2;error<=0;bbox_valid<=0;xmin<=0;xmax<=0;ymin<=0;ymax<=0;
            detail_score<=0;outline_support<=0;cycles<=0;
        end else begin
            done<=0;
            if(state!=IDLE)cycles<=cycles+48'd1;
            if(state!=IDLE&&abort_request)begin cancelled<=1;result_valid<=0;bbox_valid<=0;end
            case(state)
                IDLE:if(start&&!cancel&&coarse_idle&&backend_idle)begin
                    job_q<=job_id;coarse_q<=0;cancelled<=0;result_valid<=0;no_target<=0;
                    status<=2;error<=0;bbox_valid<=0;detail_score<=0;outline_support<=0;cycles<=0;
                    if(frame_valid&&model_valid)state<=CSTART;
                    else begin done<=1;error<=16'h0101;end
                end
                CSTART:if(abort_request)begin state<=IDLE;done<=1;error<=16'h0002;end else state<=CWAIT;
                CWAIT:if(coarse_done)begin
                    if(cancelled||abort_request||coarse_error||!coarse_valid)begin
                        state<=IDLE;done<=1;status<=2;result_valid<=0;bbox_valid<=0;
                        no_target<=coarse_none&&!cancelled&&!abort_request;
                        error<=cancelled||abort_request?16'h0002:{8'd0,coarse_error};
                    end else begin coarse_q<=coarse_packet;state<=BSTART;end
                end
                BSTART:if(abort_request)begin state<=IDLE;done<=1;error<=16'h0002;end else state<=BWAIT;
                BWAIT:if(backend_done)begin
                    state<=backend_idle?IDLE:BLOCKED;done<=1;
                    status<=cancelled||abort_request?2'd2:backend_status;
                    error<=cancelled||abort_request?16'h0002:backend_error;
                    result_valid<=backend_valid&&!cancelled&&!abort_request;
                    bbox_valid<=backend_bbox&&backend_valid&&!cancelled&&!abort_request;
                    xmin<=b_xmin;xmax<=b_xmax;ymin<=b_ymin;ymax<=b_ymax;
                    detail_score<=b_detail;outline_support<=b_outline;
                end
                BLOCKED:begin result_valid<=0;bbox_valid<=0;end
                default:begin state<=IDLE;result_valid<=0;bbox_valid<=0;error<=16'hffff;done<=1;end
            endcase
        end
    end
endmodule
