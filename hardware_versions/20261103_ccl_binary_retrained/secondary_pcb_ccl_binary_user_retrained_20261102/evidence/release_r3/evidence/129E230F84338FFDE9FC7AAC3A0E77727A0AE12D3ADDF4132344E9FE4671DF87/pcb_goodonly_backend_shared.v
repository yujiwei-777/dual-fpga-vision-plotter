`timescale 1ns/1ps
// Independent actual good-only backend candidate. Not physically qualified.
// Coarse packet remains stable while O_busy. Raw frame remains locked through
// all capture, fine, corner, final-capture, outline/detail and abort drain work.
// The owner supplies ONE shared warp, ONE shared stats and ONE shared NCC;
// this module instantiates none of those arithmetic services.
// O_status:0 PASS within taught scope,1 FAIL,2 REVIEW. Only O_result_valid
// authorizes publishing a verdict. A cancel never publishes a verdict.
module pcb_goodonly_backend_shared #(
    parameter integer PIXEL_TIMEOUT=4096,
    parameter integer ABORT_TIMEOUT=100000,
    parameter [31:0] TOTAL_TIMEOUT=32'd2000000000
)(
    input wire I_clk,I_rst_n,I_start,I_cancel,
    input wire [16:0] I_job_id,
    input wire I_frame_valid,I_model_valid,I_initial_canonical_valid,
    input wire [239:0] I_coarse_packet,
    output wire O_busy,O_idle,O_frame_lock,
    output reg O_done,O_result_valid,
    output reg [1:0] O_status,
    output reg [15:0] O_error,
    output wire [4:0] O_phase,
    output reg [47:0] O_cycles,
    output reg O_bbox_valid,
    output reg [10:0] O_xmin,O_xmax,
    output reg [9:0] O_ymin,O_ymax,
    output reg [11:0] O_detail_score,
    output reg [15:0] O_outline_support,
    output reg O_registration_valid,O_outline_complete,
    output wire [255:0] O_fine_parameters,
    output wire [9:0] O_fine_evaluations,
    output wire [30:0] O_fine_score2_q30,
    // Original raw frame pixel service (existing production reader).
    output wire O_pixel_request,
    output wire [10:0] O_pixel_x,
    output wire [9:0] O_pixel_y,
    input wire I_pixel_ready,I_pixel_valid,
    input wire [7:0] I_pixel_y8,
    // One external warp service, including its pixel endpoint.
    output wire O_warp_start,O_warp_cancel,
    output wire [7:0] O_warp_x,
    output wire [6:0] O_warp_y,
    output wire O_warp_use_fine,O_warp_apply_coarse,O_warp_half_image,
    output wire [255:0] O_warp_fine,
    output wire [239:0] O_warp_coarse,
    input wire I_warp_busy,I_warp_done,I_warp_valid,I_warp_sample_complete,
    input wire [3:0] I_warp_error,
    input wire [7:0] I_warp_gray,
    input wire signed [31:0] I_warp_project_x_q16,I_warp_project_y_q16,
    input wire signed [63:0] I_warp_source_x_q28,I_warp_source_y_q28,
    input wire I_warp_pixel_request,
    input wire [10:0] I_warp_pixel_x,
    input wire [9:0] I_warp_pixel_y,
    output wire O_warp_pixel_ready,O_warp_pixel_valid,
    output wire [7:0] O_warp_pixel_y8,
    // One shared statistics and one shared exact positive NCC service.
    output wire O_stats_start,O_stats_cancel,
    output wire [3:0] O_stats_count_log2,
    output wire O_stats_sample_valid,
    output wire [7:0] O_stats_i,O_stats_t,
    input wire I_stats_ready,I_stats_busy,I_stats_done,I_stats_valid,
    input wire [3:0] I_stats_error,
    input wire signed [35:0] I_covariance,
    input wire [35:0] I_variance_i,I_variance_t,
    output wire O_ncc_start,O_ncc_cancel,
    output wire signed [35:0] O_ncc_covariance,
    output wire [35:0] O_ncc_variance_i,O_ncc_variance_t,
    input wire I_ncc_busy,I_ncc_done,I_ncc_valid,I_ncc_positive,
    input wire [30:0] I_ncc_score2_q30,
    input wire [3:0] I_ncc_error,
    // The existing single registered workspace read port and write port.
    output wire O_ws_we,O_ws_wbank,
    output wire [14:0] O_ws_waddr,
    output wire [15:0] O_ws_wdata,
    output wire O_ws_rd_bank,
    output wire [14:0] O_ws_rd_addr,
    input wire [15:0] I_ws_rd_data
);
    localparam IDLE=0,INITIAL_START=1,INITIAL_WAIT=2,HALF_START=3,HALF_WAIT=4,
        FINE_START=5,FINE_WAIT=6,CORNER_START=7,CORNER_WAIT=8,
        GEOMETRY_START=9,GEOMETRY_WAIT=10,FINAL_START=11,FINAL_WAIT=12,
        OUTLINE_START=13,OUTLINE_WAIT=14,DETAIL_START=15,DETAIL_WAIT=16,
        FINISH=17,DRAIN=18,LOCKED=19;
    reg [4:0] state;
    reg [16:0] job_id;
    reg frame_valid,canonical_valid,half_valid,final_canonical_valid;
    reg capture_final,raw_owner;
    reg [1:0] corner_index;
    reg [315:0] raw_corners;
    reg publish_abort_review;
    reg [15:0] pending_error;
    reg [31:0] drain_clocks;
    wire capture_phase=state==INITIAL_START||state==INITIAL_WAIT||state==FINAL_START||state==FINAL_WAIT;
    wire fine_phase=state==FINE_START||state==FINE_WAIT;
    wire outline_phase=state==OUTLINE_START||state==OUTLINE_WAIT;
    wire detail_phase=state==DETAIL_START||state==DETAIL_WAIT;
    wire aborting=state==DRAIN||state==LOCKED;
    wire external_abort=I_cancel||(I_start&&state!=IDLE)||
        (state!=IDLE&&state!=DRAIN&&state!=LOCKED&&O_cycles>=TOTAL_TIMEOUT-1);
    wire service_idle=!I_warp_busy&&!I_stats_busy&&!I_ncc_busy;

    wire cap_claim,cap_start,cap_cancel,cap_busy,cap_done,cap_commit,cap_fault,cap_we,cap_all;
    wire [3:0] cap_error;
    wire [7:0] cap_x;
    wire [6:0] cap_y;
    wire [14:0] cap_waddr,cap_pixels;
    wire [15:0] cap_wdata;
    wire half_busy,half_done,half_ok,half_fault,half_rd_bank,half_we,half_wbank;
    wire [3:0] half_error;
    wire [14:0] half_rd_addr,half_waddr;
    wire [15:0] half_wdata;
    wire search_req,search_div2,search_cancel,search_busy,search_done,search_valid,search_fault;
    wire [26:0] search_tag;
    wire [255:0] eval_fine;
    wire [3:0] search_error,search_objective_error;
    wire objective_ready,objective_idle,objective_done,objective_valid,objective_cancel;
    wire [26:0] objective_tag;
    wire [30:0] objective_score;
    wire [3:0] objective_error;
    wire fine_warp_start,fine_warp_half,fine_reference_request,fine_reference_bank;
    wire [7:0] fine_warp_x;
    wire [6:0] fine_warp_y;
    wire [14:0] fine_reference_addr;
    wire fine_stats_start,fine_stats_valid,fine_ncc_start;
    wire [3:0] fine_stats_log2;
    wire [7:0] fine_stats_i,fine_stats_t;
    wire signed [35:0] fine_ncc_cov;
    wire [35:0] fine_ncc_vi,fine_ncc_vt;
    wire gray_ready,gray_idle,gray_valid,gray_fault,gray_rd_bank;
    wire [3:0] gray_error;
    wire [7:0] gray_y8;
    wire [14:0] gray_rd_addr;
    wire word_request,word_request_bank,word_ready,word_idle,word_valid,word_fault,word_rd_bank;
    wire [3:0] word_error;
    wire [14:0] word_request_addr,word_rd_addr;
    wire [15:0] word_data;
    wire geometry_busy,geometry_done,geometry_valid,geometry_convex,geometry_inside;
    wire [3:0] geometry_error;
    wire outline_ready,outline_idle,outline_cancel,outline_done,outline_valid,outline_registration,outline_complete;
    wire [3:0] outline_error;
    wire [15:0] outline_mask;
    wire outline_ram_request,outline_ram_bank;
    wire [14:0] outline_ram_addr;
    wire outline_stats_start,outline_stats_valid,outline_ncc_start;
    wire [3:0] outline_stats_log2;
    wire [7:0] outline_stats_i,outline_stats_t;
    wire signed [35:0] outline_ncc_cov;
    wire [35:0] outline_ncc_vi,outline_ncc_vt;
    wire detail_busy,detail_done,detail_valid,detail_adapter_idle,detail_adapter_fault,detail_rd_bank;
    wire [1:0] detail_status;
    wire [7:0] detail_error;
    wire [3:0] detail_adapter_error;
    wire [11:0] detail_score;
    wire [14:0] detail_rd_addr;
    wire detail_gray_req,detail_gray_ready,detail_gray_valid,detail_rom_req,detail_rom_ready,detail_rom_valid,detail_rom_rsp_ready;
    wire [14:0] detail_gray_addr,detail_rom_index;
    wire [40:0] detail_gray_tag,detail_gray_rsp_tag;
    wire [15:0] detail_rom_tag,detail_rom_rsp_tag;
    wire [7:0] detail_gray_data;
    wire [23:0] detail_rom_data;
    wire all_idle=service_idle&&!cap_busy&&!half_busy&&!search_busy&&objective_idle&&
        !geometry_busy&&outline_idle&&!detail_busy&&gray_idle&&word_idle&&detail_adapter_idle;

    assign O_busy=state!=IDLE;
    assign O_idle=state==IDLE&&all_idle;
    assign O_frame_lock=O_busy;
    assign O_phase=state;
    assign O_warp_start=!external_abort&&!aborting&&
        (capture_phase?cap_start:fine_phase?fine_warp_start:state==CORNER_START&&!I_warp_busy);
    assign O_warp_cancel=aborting||external_abort||cap_cancel||objective_cancel;
    assign O_warp_x=capture_phase?cap_x:fine_phase?fine_warp_x:
        ((corner_index==1||corner_index==2)?8'd187:8'd4);
    assign O_warp_y=capture_phase?cap_y:fine_phase?fine_warp_y:(corner_index[1]?7'd87:7'd8);
    assign O_warp_use_fine=capture_phase?capture_final:1'b1;
    assign O_warp_apply_coarse=!fine_phase;
    assign O_warp_half_image=fine_phase&&fine_warp_half;
    assign O_warp_fine=fine_phase?eval_fine:O_fine_parameters;
    assign O_warp_coarse=I_coarse_packet;
    // raw_owner is latched whenever a warp starts and remains until the
    // transaction completes/drains; switching outer state cannot misroute a
    // late response. The local gray adapter always completes accepted reads.
    assign O_pixel_request=raw_owner&&I_warp_pixel_request&&!aborting;
    assign O_pixel_x=I_warp_pixel_x;
    assign O_pixel_y=I_warp_pixel_y;
    assign O_warp_pixel_ready=raw_owner?I_pixel_ready:gray_ready&&word_idle&&!word_request;
    assign O_warp_pixel_valid=raw_owner?I_pixel_valid:gray_valid;
    assign O_warp_pixel_y8=raw_owner?I_pixel_y8:gray_y8;
    assign O_stats_start=!external_abort&&!aborting&&(fine_phase?fine_stats_start:outline_phase&&outline_stats_start);
    assign O_stats_cancel=aborting||external_abort||objective_cancel||outline_cancel;
    assign O_stats_count_log2=fine_phase?fine_stats_log2:outline_stats_log2;
    assign O_stats_sample_valid=!external_abort&&!aborting&&(fine_phase?fine_stats_valid:outline_phase&&outline_stats_valid);
    assign O_stats_i=fine_phase?fine_stats_i:outline_stats_i;
    assign O_stats_t=fine_phase?fine_stats_t:outline_stats_t;
    assign O_ncc_start=!external_abort&&!aborting&&(fine_phase?fine_ncc_start:outline_phase&&outline_ncc_start);
    assign O_ncc_cancel=O_stats_cancel;
    assign O_ncc_covariance=fine_phase?fine_ncc_cov:outline_ncc_cov;
    assign O_ncc_variance_i=fine_phase?fine_ncc_vi:outline_ncc_vi;
    assign O_ncc_variance_t=fine_phase?fine_ncc_vt:outline_ncc_vt;
    assign word_request=(fine_phase&&fine_reference_request)||(outline_phase&&outline_ram_request);
    assign word_request_bank=fine_phase?fine_reference_bank:outline_ram_bank;
    assign word_request_addr=fine_phase?fine_reference_addr:outline_ram_addr;
    assign O_ws_we=!external_abort&&!aborting&&(capture_phase?cap_we:state==HALF_WAIT&&half_we);
    assign O_ws_wbank=capture_phase?1'b0:half_wbank;
    assign O_ws_waddr=capture_phase?cap_waddr:half_waddr;
    assign O_ws_wdata=capture_phase?cap_wdata:half_wdata;
    assign O_ws_rd_bank=(state==HALF_START||state==HALF_WAIT)?half_rd_bank:
        detail_phase?detail_rd_bank:(!word_idle||word_request)?word_rd_bank:gray_rd_bank;
    assign O_ws_rd_addr=(state==HALF_START||state==HALF_WAIT)?half_rd_addr:
        detail_phase?detail_rd_addr:(!word_idle||word_request)?word_rd_addr:gray_rd_addr;

    serial_integer_warp_capture_external #(.WAIT_TIMEOUT(PIXEL_TIMEOUT)) capture(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start((state==INITIAL_START||state==FINAL_START)&&!external_abort),
        .I_cancel(aborting||external_abort),.I_frame_valid(frame_valid),.I_use_fine(capture_final),
        .I_fine(O_fine_parameters),.I_coarse(I_coarse_packet),.O_sample_claim(cap_claim),
        .I_sample_grant(capture_phase&&!aborting),.O_sample_start(cap_start),.O_sample_cancel(cap_cancel),
        .O_sample_x(cap_x),.O_sample_y(cap_y),.O_sample_use_fine(),.O_sample_apply_coarse(),.O_sample_half_image(),
        .O_sample_fine(),.O_sample_coarse(),.I_sample_busy(I_warp_busy),.I_sample_done(I_warp_done),
        .I_sample_valid(I_warp_valid),.I_sample_complete(I_warp_sample_complete),.I_sample_error(I_warp_error),
        .I_sample_gray(I_warp_gray),.O_busy(cap_busy),.O_done(cap_done),.O_commit(cap_commit),
        .O_fault(cap_fault),.O_error(cap_error),.O_ws_we(cap_we),.O_ws_waddr(cap_waddr),
        .O_ws_wdata(cap_wdata),.O_pixels(cap_pixels),.O_all_samples_complete(cap_all));
    pcb_half_image_serial half_image(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(state==HALF_START&&!external_abort),
        .I_cancel(aborting||external_abort),.I_canonical_valid(canonical_valid),.O_busy(half_busy),
        .O_done(half_done),.O_valid(half_ok),.O_fault(half_fault),.O_error(half_error),
        .O_ws_rd_bank(half_rd_bank),.O_ws_rd_addr(half_rd_addr),.I_ws_rd_data(I_ws_rd_data),
        .O_ws_we(half_we),.O_ws_wbank(half_wbank),.O_ws_waddr(half_waddr),.O_ws_wdata(half_wdata),
        .O_pixels(),.O_reads());
    pcb_refinement_search_area_v3 search(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(state==FINE_START&&!external_abort),
        .I_cancel(aborting||external_abort),.I_job_id(job_id),.O_eval_valid(search_req),
        .I_eval_ready(objective_ready),.O_eval_tag(search_tag),.O_eval_div2(search_div2),
        .O_eval_parameters(eval_fine),.O_eval_cancel(search_cancel),.I_eval_idle(objective_idle),
        .I_eval_done(objective_done),.I_eval_score_valid(objective_valid),.I_eval_error(objective_error),
        .I_eval_tag(objective_tag),.I_eval_score2_q30(objective_score),.O_busy(search_busy),
        .O_done(search_done),.O_result_valid(search_valid),.O_fault(search_fault),.O_error(search_error),
        .O_objective_error(search_objective_error),.O_parameters(O_fine_parameters),
        .O_evaluations(O_fine_evaluations),.O_final_score2_q30(O_fine_score2_q30));
    pcb_refinement_objective_area_v4 objective(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_cancel(aborting||external_abort||search_cancel),
        .I_request_valid(search_req&&fine_phase),.O_request_ready(objective_ready),
        .I_request_tag(search_tag),.I_div2(search_div2),.O_idle(objective_idle),
        .O_done(objective_done),.O_score_valid(objective_valid),.O_response_tag(objective_tag),
        .O_score2_q30(objective_score),.O_error(objective_error),.O_engine_cancel(objective_cancel),
        .O_sample_start(fine_warp_start),.O_sample_x(fine_warp_x),.O_sample_y(fine_warp_y),.O_sample_half(fine_warp_half),
        .I_sample_busy(I_warp_busy),.I_sample_done(I_warp_done),.I_sample_valid(I_warp_valid),
        .I_sample_error(I_warp_error),.I_sample_gray(I_warp_gray),
        .I_project_x_q16(I_warp_project_x_q16),.I_project_y_q16(I_warp_project_y_q16),
        .O_reference_request(fine_reference_request),.O_reference_bank(fine_reference_bank),
        .O_reference_addr(fine_reference_addr),.I_reference_ready(word_ready&&gray_idle),
        .I_reference_valid(word_valid&&fine_phase),.I_memory_idle(word_idle&&gray_idle),.I_reference_data(word_data),
        .O_stats_start(fine_stats_start),.O_stats_count_log2(fine_stats_log2),.O_stats_sample_valid(fine_stats_valid),
        .O_stats_i(fine_stats_i),.O_stats_t(fine_stats_t),.I_stats_ready(I_stats_ready),
        .I_stats_busy(I_stats_busy),.I_stats_done(I_stats_done),.I_stats_valid(I_stats_valid),
        .I_covariance(I_covariance),.I_variance_i(I_variance_i),.I_variance_t(I_variance_t),
        .O_norm_start(fine_ncc_start),.O_norm_covariance(fine_ncc_cov),
        .O_norm_variance_i(fine_ncc_vi),.O_norm_variance_t(fine_ncc_vt),.I_norm_busy(I_ncc_busy),
        .I_norm_done(I_ncc_done),.I_norm_valid(I_ncc_valid),.I_norm_positive(I_ncc_positive),
        .I_norm_score2_q30(I_ncc_score2_q30),.I_norm_error(I_ncc_error));
    pcb_workspace_gray_adapter gray_adapter(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_cancel(aborting&&!I_warp_busy&&gray_idle),
        .I_request(!raw_owner&&I_warp_pixel_request&&word_idle&&!word_request),
        .I_half(O_warp_half_image),.I_canonical_valid(canonical_valid),.I_half_valid(half_valid),
        .I_x(I_warp_pixel_x),.I_y(I_warp_pixel_y),.O_ready(gray_ready),.O_idle(gray_idle),
        .O_pixel_valid(gray_valid),.O_pixel_y8(gray_y8),.O_fault(gray_fault),.O_error(gray_error),
        .O_ws_rd_bank(gray_rd_bank),.O_ws_rd_addr(gray_rd_addr),.I_ws_rd_data(I_ws_rd_data));
    pcb_workspace_word_adapter word_adapter(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_cancel(aborting),.I_request(word_request&&gray_idle),
        .I_bank(word_request_bank),.I_addr(word_request_addr),.O_ready(word_ready),.O_idle(word_idle),
        .O_valid(word_valid),.O_fault(word_fault),.O_error(word_error),.O_data(word_data),
        .O_ws_rd_bank(word_rd_bank),.O_ws_rd_addr(word_rd_addr),.I_ws_rd_data(I_ws_rd_data));
    pcb_raw_corner_geometry_serial geometry(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(state==GEOMETRY_START&&!external_abort),
        .I_cancel(aborting||external_abort),.I_corners(raw_corners),.O_busy(geometry_busy),
        .O_done(geometry_done),.O_valid(geometry_valid),.O_convex(geometry_convex),
        .O_inside(geometry_inside),.O_error(geometry_error));
    pcb_outline_geometry_controller outline(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(state==OUTLINE_START&&!external_abort),
        .I_cancel(aborting||external_abort),.I_board_convex(geometry_convex),
        .I_board_inside_safe_frame(geometry_inside),.O_ready(outline_ready),.O_idle(outline_idle),
        .O_engine_cancel(outline_cancel),.O_done(outline_done),.O_result_valid(outline_valid),
        .O_registration_valid(outline_registration),.O_outline_complete(outline_complete),
        .O_error(outline_error),.O_support_mask(outline_mask),.O_patch_done(),.O_patch_index(),
        .O_patch_best_valid(),.O_patch_supported(),.O_patch_best_score2_q30(),.O_patch_best_dx(),.O_patch_best_dy(),
        .O_ram_request(outline_ram_request),.O_ram_bank(outline_ram_bank),.O_ram_addr(outline_ram_addr),
        .I_ram_ready(word_ready&&gray_idle),.I_ram_valid(word_valid&&outline_phase),
        .I_ram_idle(word_idle&&gray_idle),.I_ram_data(word_data),.O_stats_start(outline_stats_start),
        .O_stats_count_log2(outline_stats_log2),.O_stats_sample_valid(outline_stats_valid),
        .O_stats_i(outline_stats_i),.O_stats_t(outline_stats_t),.I_stats_ready(I_stats_ready),
        .I_stats_busy(I_stats_busy),.I_stats_done(I_stats_done),.I_stats_valid(I_stats_valid),
        .I_covariance(I_covariance),.I_variance_i(I_variance_i),.I_variance_t(I_variance_t),
        .O_norm_start(outline_ncc_start),.O_norm_covariance(outline_ncc_cov),
        .O_norm_variance_i(outline_ncc_vi),.O_norm_variance_t(outline_ncc_vt),
        .I_norm_busy(I_ncc_busy),.I_norm_done(I_ncc_done),.I_norm_valid(I_ncc_valid),
        .I_norm_positive(I_ncc_positive),.I_norm_score2_q30(I_ncc_score2_q30),.I_norm_error(I_ncc_error));
    pcb_missing_feature_backend detail(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(state==DETAIL_START&&!external_abort),
        .I_cancel(aborting||external_abort),.I_job_id(job_id),.I_sparse_count(15'd2568),
        .I_threshold(16'd69),.I_frame_valid(final_canonical_valid),.I_registration_valid(O_registration_valid),
        .O_gray_req_valid(detail_gray_req),.I_gray_req_ready(detail_gray_ready),
        .O_gray_req_addr(detail_gray_addr),.O_gray_req_tag(detail_gray_tag),
        .I_gray_rsp_valid(detail_gray_valid),.I_gray_rsp_tag(detail_gray_rsp_tag),.I_gray_rsp_data(detail_gray_data),
        .O_rom_req_valid(detail_rom_req),.I_rom_req_ready(detail_rom_ready),.O_rom_req_index(detail_rom_index),
        .O_rom_req_tag(detail_rom_tag),.I_rom_rsp_valid(detail_rom_valid),.O_rom_rsp_ready(detail_rom_rsp_ready),
        .I_rom_rsp_data(detail_rom_data),.I_rom_rsp_tag(detail_rom_rsp_tag),.O_busy(detail_busy),
        .O_done(detail_done),.O_result_valid(detail_valid),.O_status(detail_status),.O_error(detail_error),
        .O_score(detail_score),.O_peak_tile(),.O_total_loss(),.O_changed_pixels(),.O_samples(),
        .O_gray_read_requests(),.O_feature_queries());
    pcb_workspace_detail_adapter detail_adapter(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_cancel(aborting),.I_canonical_valid(final_canonical_valid),
        .I_model_valid(I_model_valid),.I_gray_req_valid(detail_gray_req&&detail_phase),
        .O_gray_req_ready(detail_gray_ready),.I_gray_req_addr(detail_gray_addr),.I_gray_req_tag(detail_gray_tag),
        .O_gray_rsp_valid(detail_gray_valid),.O_gray_rsp_data(detail_gray_data),.O_gray_rsp_tag(detail_gray_rsp_tag),
        .I_rom_req_valid(detail_rom_req&&detail_phase),.O_rom_req_ready(detail_rom_ready),
        .I_rom_req_index(detail_rom_index),.I_rom_req_tag(detail_rom_tag),.O_rom_rsp_valid(detail_rom_valid),
        .I_rom_rsp_ready(detail_rom_rsp_ready),.O_rom_rsp_data(detail_rom_data),.O_rom_rsp_tag(detail_rom_rsp_tag),
        .O_idle(detail_adapter_idle),.O_fault(detail_adapter_fault),.O_error(detail_adapter_error),
        .O_ws_rd_bank(detail_rd_bank),.O_ws_rd_addr(detail_rd_addr),.I_ws_rd_data(I_ws_rd_data));

    wire raw_corner_safe=I_warp_source_x_q28>=64'sd268435456&&I_warp_source_x_q28<=64'sd343060512768&&
        I_warp_source_y_q28>=64'sd268435456&&I_warp_source_y_q28<=64'sd192736657408;
    wire [10:0] corner_floor_x=I_warp_source_x_q28[38:28];
    wire [9:0] corner_floor_y=I_warp_source_y_q28[37:28];
    wire [10:0] corner_ceil_x=corner_floor_x+(|I_warp_source_x_q28[27:0]);
    wire [9:0] corner_ceil_y=corner_floor_y+(|I_warp_source_y_q28[27:0]);
    task start_drain;
        input [15:0] code;input publish_review;
        begin
            pending_error<=code;publish_abort_review<=publish_review;drain_clocks<=0;
            O_result_valid<=0;O_status<=2;canonical_valid<=0;half_valid<=0;
            final_canonical_valid<=0;state<=DRAIN;
        end
    endtask
    task finish_review;
        input [15:0] code;
        begin O_done<=1;O_result_valid<=1;O_status<=2;O_error<=code;state<=IDLE;end
    endtask
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;job_id<=0;frame_valid<=0;canonical_valid<=0;half_valid<=0;final_canonical_valid<=0;
            capture_final<=0;raw_owner<=1;corner_index<=0;raw_corners<=0;
            publish_abort_review<=0;pending_error<=0;drain_clocks<=0;
            O_done<=0;O_result_valid<=0;O_status<=2;O_error<=0;O_cycles<=0;
            O_bbox_valid<=0;O_xmin<=0;O_xmax<=0;O_ymin<=0;O_ymax<=0;
            O_detail_score<=0;O_outline_support<=0;O_registration_valid<=0;O_outline_complete<=0;
        end else begin
            O_done<=0;
            // An explicit cancel/restart during a fault drain revokes even
            // the pending REVIEW publication. Remember a one-cycle pulse;
            // drain completion can be many clocks later.
            if(state==DRAIN&&(I_cancel||I_start))publish_abort_review<=0;
            if(state!=IDLE&&state!=LOCKED)O_cycles<=O_cycles+1'b1;
            if(O_warp_start)raw_owner<=O_warp_apply_coarse;
            if(state==LOCKED)state<=LOCKED;
            else if(external_abort&&state!=IDLE&&state!=DRAIN)begin
                start_drain(I_cancel?16'h0004:I_start?16'h0006:16'h0009,!I_cancel&&!I_start);
            end else if((fine_phase&&(gray_fault||word_fault))||(outline_phase&&word_fault)||
                        (detail_phase&&detail_adapter_fault))begin
                start_drain(16'h00e0|{12'd0,gray_fault?gray_error:word_fault?word_error:detail_adapter_error},1'b1);
            end else case(state)
                IDLE:if(I_start&&!I_cancel&&O_idle)begin
                    job_id<=I_job_id;frame_valid<=I_frame_valid;
                    O_result_valid<=0;O_status<=2;O_error<=0;O_cycles<=0;O_bbox_valid<=0;
                    O_xmin<=0;O_xmax<=0;O_ymin<=0;O_ymax<=0;
                    O_detail_score<=0;O_outline_support<=0;O_registration_valid<=0;O_outline_complete<=0;
                    canonical_valid<=I_initial_canonical_valid;half_valid<=0;final_canonical_valid<=0;
                    capture_final<=0;corner_index<=0;raw_corners<=0;
                    if(!I_frame_valid)finish_review(16'h0001);
                    else if(!I_model_valid)finish_review(16'h0002);
                    else state<=I_initial_canonical_valid?HALF_START:INITIAL_START;
                end
                INITIAL_START:state<=INITIAL_WAIT;
                INITIAL_WAIT:if(cap_done)begin
                    if(!cap_commit||cap_fault||cap_error!=0)start_drain({8'h10,4'd0,cap_error},1'b1);
                    else begin canonical_valid<=1;state<=HALF_START;end
                end
                HALF_START:state<=HALF_WAIT;
                HALF_WAIT:if(half_done)begin
                    if(!half_ok||half_fault||half_error!=0)start_drain({8'h20,4'd0,half_error},1'b1);
                    else begin half_valid<=1;state<=FINE_START;end
                end
                FINE_START:state<=FINE_WAIT;
                FINE_WAIT:if(search_done)begin
                    if(!search_valid||search_fault||search_error!=0)
                        start_drain({8'h30,search_objective_error,search_error},1'b1);
                    else begin corner_index<=0;state<=CORNER_START;end
                end
                CORNER_START:if(O_warp_start)state<=CORNER_WAIT;
                CORNER_WAIT:if(I_warp_done)begin
                    if(!I_warp_valid||I_warp_error!=0||I_warp_busy)
                        start_drain({8'h40,4'd0,I_warp_error},1'b1);
                    else if(!raw_corner_safe)finish_review(16'h4001);
                    else begin
                        raw_corners[79*corner_index+:79]<={I_warp_source_y_q28[38:0],I_warp_source_x_q28[39:0]};
                        if(corner_index==0)begin
                            O_xmin<=corner_floor_x;O_xmax<=corner_ceil_x;
                            O_ymin<=corner_floor_y;O_ymax<=corner_ceil_y;
                        end else begin
                            if(corner_floor_x<O_xmin)O_xmin<=corner_floor_x;
                            if(corner_ceil_x>O_xmax)O_xmax<=corner_ceil_x;
                            if(corner_floor_y<O_ymin)O_ymin<=corner_floor_y;
                            if(corner_ceil_y>O_ymax)O_ymax<=corner_ceil_y;
                        end
                        if(corner_index==3)begin O_bbox_valid<=1;state<=GEOMETRY_START;end
                        else begin corner_index<=corner_index+2'd1;state<=CORNER_START;end
                    end
                end
                GEOMETRY_START:state<=GEOMETRY_WAIT;
                GEOMETRY_WAIT:if(geometry_done)begin
                    if(!geometry_valid||geometry_error!=0)start_drain({8'h50,4'd0,geometry_error},1'b1);
                    else if(!geometry_convex||!geometry_inside)finish_review(16'h5001);
                    else begin capture_final<=1;canonical_valid<=0;half_valid<=0;state<=FINAL_START;end
                end
                FINAL_START:state<=FINAL_WAIT;
                FINAL_WAIT:if(cap_done)begin
                    if(!cap_commit||cap_fault||cap_error!=0)start_drain({8'h60,4'd0,cap_error},1'b1);
                    else begin final_canonical_valid<=1;state<=OUTLINE_START;end
                end
                OUTLINE_START:if(outline_ready)state<=OUTLINE_WAIT;
                OUTLINE_WAIT:if(outline_done)begin
                    O_outline_support<=outline_mask;
                    if(!outline_valid||outline_error!=0)start_drain({8'h70,4'd0,outline_error},1'b1);
                    else begin
                        O_registration_valid<=outline_registration;O_outline_complete<=outline_complete;
                        if(!outline_registration)finish_review(16'h7001);
                        else state<=DETAIL_START;
                    end
                end
                DETAIL_START:state<=DETAIL_WAIT;
                DETAIL_WAIT:if(detail_done)begin
                    O_detail_score<=detail_score;
                    if(!detail_valid||detail_error!=0)start_drain({8'h80,detail_error},1'b1);
                    else begin
                        O_status<=detail_status==2?2'd2:(!O_outline_complete||detail_status==1)?2'd1:2'd0;
                        O_error<=0;state<=FINISH;
                    end
                end
                FINISH:if(all_idle)begin O_done<=1;O_result_valid<=1;state<=IDLE;end
                DRAIN:begin
                    if(all_idle&&drain_clocks>=2)begin
                        O_done<=1;O_result_valid<=publish_abort_review&&!I_cancel&&!I_start;
                        O_status<=2;O_error<=pending_error;state<=IDLE;
                    end else if(drain_clocks>=ABORT_TIMEOUT-1)begin
                        O_done<=1;O_result_valid<=0;O_status<=2;O_error<=16'hffff;state<=LOCKED;
                    end else drain_clocks<=drain_clocks+1'b1;
                end
                default:start_drain(16'h00ff,1'b1);
            endcase
        end
    end
endmodule
