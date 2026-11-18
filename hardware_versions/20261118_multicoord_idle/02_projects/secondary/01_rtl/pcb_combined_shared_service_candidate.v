`timescale 1ns/1ps
// Integrated six-request candidate service: one geometry/warp/outline engine and private RF.
// Hold raw corners until O_busy falls. Requests are accepted only at O_ready.
// Same-client busy restart retains the original host's diagnostic. Cross-client
// or simultaneous starts fence all writes and complete affected jobs with 108.
module pcb_combined_shared_service_candidate #(
    parameter ROM_FILE="combined_geometry_warp_outline_rom_2048.mem",
    parameter integer PROGRAM_WORDS=1242,
    parameter integer CONSTANT_WORDS=486,
    parameter integer POSE_ENTRY=0,
    parameter integer AFFINE_ENTRY=381,
    parameter integer GEOMETRY_ENTRY=531,
    parameter [14:0] OFFSET_BASE=15'd12800,
    parameter integer PIXEL_TIMEOUT=4096,
    parameter integer OUTLINE_TIMEOUT=2000000000,
    parameter integer WATCHDOG=2000000
)(
    input wire I_clk,I_rst_n,I_cancel,
    input wire I_pose_start,I_affine_start,I_raw_start,I_warp_start,I_outline_start,
    input wire I_context_start,I_context_epoch_start,I_context_invalidate,
    input wire [2:0] I_context_command,I_context_slot,
    input wire [1:0] I_context_choice,
    input wire signed [25:0] I_context_increment,
    output wire O_context_busy,O_context_done,
    output wire [1:0] O_context_error,
    input wire [3:0] I_width_index,I_angle_index,
    input wire [6:0] I_center_x,I_center_y,
    input wire [315:0] I_corners,
    output wire O_ready,O_busy,
    output wire [2:0] O_owner,
    output wire O_pose_done,O_pose_valid,
    output wire [3:0] O_pose_error,
    output wire [6:0] O_xmin,O_ymin,
    output wire O_affine_done,O_affine_valid,
    output wire [3:0] O_affine_error,
    output wire [239:0] O_coarse,
    output wire [8:0] O_coarse_diagnostic_error,
    output wire O_raw_done,O_raw_valid,O_raw_inside,O_raw_convex,
    output wire [8:0] O_raw_error,
    output wire O_ws_we,
    output wire [14:0] O_ws_waddr,
    output wire [15:0] O_ws_wdata,
    input wire [7:0] I_x,input wire [6:0] I_y,
    input wire I_use_fine,I_apply_coarse,I_half_image,
    input wire [239:0] I_coarse,
    output wire O_warp_busy,O_warp_done,O_warp_valid,O_sample_complete,
    output wire [3:0] O_warp_error,O_tap_inside,
    output wire [8:0] O_warp_diagnostic_error,
    output wire [7:0] O_gray,
    output wire signed [31:0] O_project_x_q16,O_project_y_q16,
    output wire signed [63:0] O_source_x_q28,O_source_y_q28,
    output wire O_pixel_request,output wire [10:0] O_pixel_x,output wire [9:0] O_pixel_y,
    input wire I_pixel_ready,I_pixel_valid,input wire [7:0] I_pixel_y8,
    input wire I_board_convex,I_board_inside,
    output wire O_outline_busy,O_outline_done,O_outline_valid,O_registration,O_outline_complete,
    output wire [15:0] O_outline_mask,
    output wire [3:0] O_outline_error,
    output wire [8:0] O_outline_diagnostic_error,
    output wire O_outline_ram_request,O_outline_ram_bank,
    output wire [14:0] O_outline_ram_addr,
    input wire I_outline_ram_ready,I_outline_ram_valid,I_outline_ram_idle,
    input wire [15:0] I_outline_ram_data,
    output wire O_outline_stats_start,O_outline_stats_cancel,
    output wire [3:0] O_outline_stats_count_log2,
    output wire O_outline_sample_valid,output wire [7:0] O_outline_sample_i,O_outline_sample_t,
    input wire I_stats_ready,I_stats_busy,I_stats_done,I_stats_valid,
    input wire [3:0] I_stats_error,
    input wire signed [35:0] I_covariance,
    input wire [35:0] I_variance_i,I_variance_t,
    output wire O_outline_ncc_start,O_outline_ncc_cancel,
    input wire I_ncc_busy,I_ncc_done,I_ncc_valid,I_ncc_positive,
    input wire [30:0] I_ncc_score,input wire [3:0] I_ncc_error,
    output reg O_service_fault,
    output reg [8:0] O_service_error
);

    localparam OWNER_NONE=0,OWNER_COARSE=1,OWNER_RAW=2,OWNER_WARP=3,OWNER_OUTLINE=4,OWNER_CONTEXT=6;
    reg [2:0] owner;
    reg owner_affine,fault_pending;
    reg [6:0] affected,invalid,fault_done;
    wire c_ready,c_active,c_pose_done,c_pose_valid,c_affine_done,c_affine_valid;
    wire [3:0] c_pose_error,c_affine_error;
    wire [8:0] c_diagnostic_error;
    wire r_ready,r_busy,r_done,r_valid,r_inside,r_convex;
    wire [8:0] r_error;
    wire c_cancel,c_host_write,c_start,c_emit_ready;
    wire [5:0] c_host_index;
    wire [31:0] c_host_data;
    wire [15:0] c_entry;
    wire r_cancel,r_host_write,r_start,r_emit_ready;
    wire [5:0] r_host_index;
    wire [31:0] r_host_data;
    wire [15:0] r_entry;
    wire c_offset_we;
    wire [14:0] c_offset_waddr;
    wire [15:0] c_offset_wdata;
    wire engine_busy,engine_done,engine_valid,host_ready,host_done,emit_valid;
    wire [8:0] engine_status,engine_error,emit_tag;
    wire [31:0] emit_d,emit_a,emit_b;
    wire [6:0] rf_addr,rf_baddr;
    wire rf_we;
    wire [15:0] rf_wdata,rf_rdata,rf_brdata;

    wire w_busy,w_retiring,w_done,w_valid,w_complete;
    wire [3:0] w_error,w_taps;wire [8:0] w_diagnostic;wire [7:0] w_gray;
    wire w_cancel,w_host_write,w_start,w_emit_ready;
    wire [5:0] w_host_index;wire [31:0] w_host_data;wire [15:0] w_entry;
    wire o_busy,o_retiring,o_done,o_valid,o_registration,o_complete,o_begin;
    wire [15:0] o_mask;wire [3:0] o_error;wire [8:0] o_diagnostic;
    wire o_cancel,o_host_write,o_start,o_emit_ready;
    wire [5:0] o_host_index;wire [31:0] o_host_data;wire [15:0] o_entry;
    wire uop_busy,uop_done,uop_valid,uop_complete;
    wire [3:0] uop_error,uop_taps;wire [7:0] uop_gray;
    wire ep_busy,ep_idle,ep_locked,ep_fault;wire [3:0] ep_error;
    wire io_valid,io_ready,io_response_valid,io_response_ready,io_abort;
    wire [8:0] io_command;wire [31:0] io_a,io_b,io_return;
    reg context_live;
    wire ctx_ready,ctx_busy,ctx_retiring,ctx_done,ctx_fine,ctx_coarse,ctx_spilled,ctx_dirty;
    wire [1:0] ctx_error;
    wire [6:0] ctx_a_addr,ctx_b_addr;
    wire ctx_we,ctx_r_we;
    wire [15:0] ctx_wdata;
    wire [31:0] ctx_r_data,ctx_alu_a,ctx_alu_b,engine_r;
    wire [32:0] engine_alu_sum;
    wire ctx_alu_carry,engine_context_available,w_loaded_coarse;
    wire selected_context=owner==OWNER_CONTEXT;
    wire load_coarse_now=I_apply_coarse&&!ctx_coarse;
    wire warp_metadata_ok=context_live&&!I_context_invalidate&&!ctx_dirty&&!ctx_spilled&&!ctx_busy&&
        (!I_use_fine||ctx_fine)&&(!I_apply_coarse||ctx_coarse||load_coarse_now);
    wire metadata_violation=(I_warp_start&&!warp_metadata_ok)||
        ((I_pose_start||I_affine_start)&&context_live)||
        (I_raw_start&&context_live&&!ctx_spilled)||
        (I_outline_start&&context_live)||
        (I_context_start&&(!context_live||I_context_invalidate||ctx_busy));
    wire selected_coarse=owner==OWNER_COARSE,selected_raw=owner==OWNER_RAW;
    wire selected_warp=owner==OWNER_WARP,selected_outline=owner==OWNER_OUTLINE;
    // Bit5 is reserved for the unchanged standalone DETAIL stage; owner6 is context.
    wire [6:0] request={I_context_start,1'b0,I_outline_start,I_warp_start,I_raw_start,I_affine_start,I_pose_start};
    wire [6:0] active_request=selected_context?7'b1000000:
        selected_coarse?(owner_affine?7'b0000010:7'b0000001):
        selected_raw?7'b0000100:selected_warp?7'b0001000:selected_outline?7'b0010000:7'b0000000;
    wire host_active=selected_coarse?c_active:selected_raw?r_busy:selected_warp?w_busy:selected_outline?o_busy:selected_context?ctx_busy:1'b0;
    wire primitive_idle=!engine_busy&&!uop_busy&&ep_idle;
    wire all_idle=!c_active&&!r_busy&&!w_busy&&!o_busy&&!ctx_busy&&primitive_idle;
    wire can_accept=owner==OWNER_NONE&&all_idle&&!fault_pending&&!I_cancel&&!I_context_invalidate;
    wire multiple_requests=|(request&(request-1'b1));
    wire conflict_now=!I_cancel&&!fault_pending&&|request&&
        (metadata_violation||multiple_requests||(owner==OWNER_NONE?!can_accept:(!host_active|||(request&~active_request))));
    wire fence=I_cancel||fault_pending||conflict_now||(I_context_invalidate&&owner!=OWNER_NONE);
    wire c_event_owner=selected_coarse&&!fence,r_event_owner=selected_raw&&!fence;
    wire w_event_owner=selected_warp&&!fence,o_event_owner=selected_outline&&!fence;
    wire c_pose_start=I_pose_start&&!fence&&(can_accept||(selected_coarse&&c_active));
    wire c_affine_start=I_affine_start&&!fence&&(can_accept||(selected_coarse&&c_active));
    wire raw_start=I_raw_start&&!fence&&(can_accept||(selected_raw&&r_busy));
    wire warp_start=I_warp_start&&!fence&&(can_accept||(selected_warp&&w_busy));
    wire outline_start=I_outline_start&&!fence&&(can_accept||(selected_outline&&o_busy));
    wire engine_cancel=fence||I_context_invalidate||(selected_coarse?c_cancel:selected_raw?r_cancel:selected_warp?w_cancel:selected_outline?o_cancel:1'b0);
    wire context_start=I_context_start&&!fence&&(can_accept||selected_context);
    wire context_grant=(selected_context||(context_start&&can_accept))&&primitive_idle&&!fence&&!I_context_invalidate;
    wire epoch_accept=I_context_epoch_start&&owner==OWNER_NONE&&all_idle&&!fence&&!I_context_invalidate&&request==0;
    wire context_fault=fault_pending||conflict_now||I_context_invalidate||(selected_context&&!primitive_idle);
    wire release_context=owner==OWNER_NONE||(fault_pending&&primitive_idle);
    wire [6:0] physical_rf_addr=selected_context?ctx_a_addr:rf_addr;
    wire [6:0] physical_rf_baddr=selected_context?ctx_b_addr:rf_baddr;
    wire [15:0] physical_rf_wdata=selected_context?ctx_wdata:rf_wdata;
    wire private_rf_we=(selected_context?ctx_we:rf_we)&&owner!=OWNER_NONE&&!fence&&
        (!selected_context||context_grant);
    assign O_context_busy=ctx_busy||selected_context;
    assign O_context_done=fault_done[6]||(ctx_done&&!fault_pending&&!conflict_now);
    assign O_context_error=invalid[6]?2'd3:ctx_error;
    wire release_warp=owner==OWNER_NONE||(fault_pending&&primitive_idle);
    wire release_outline=owner==OWNER_NONE||(fault_pending&&primitive_idle);
    assign O_owner=owner;assign O_ready=can_accept&&!conflict_now;
    assign O_busy=owner!=OWNER_NONE||!all_idle||fault_pending||conflict_now;
    assign O_pose_done=fault_done[0]||(c_pose_done&&!fault_pending&&!conflict_now);
    assign O_affine_done=fault_done[1]||(c_affine_done&&!fault_pending&&!conflict_now);
    assign O_raw_done=fault_done[2]||(r_done&&!fault_pending&&!conflict_now);
    assign O_warp_done=fault_done[3]||(w_done&&!fault_pending&&!conflict_now);
    assign O_outline_done=fault_done[4]||(o_done&&!fault_pending&&!conflict_now);
    assign O_pose_valid=c_pose_valid&&!invalid[0]&&!fence;
    assign O_affine_valid=c_affine_valid&&!invalid[1]&&!fence;
    assign O_raw_valid=r_valid&&!invalid[2]&&!fence;
    assign O_warp_valid=w_valid&&!invalid[3]&&!fence;
    assign O_outline_valid=o_valid&&!invalid[4]&&!fence;
    assign O_pose_error=invalid[0]?4'd5:c_pose_error;
    assign O_affine_error=invalid[1]?4'd5:c_affine_error;
    assign O_raw_error=invalid[2]?9'h108:r_error;
    assign O_coarse_diagnostic_error=|(invalid[1:0])?9'h108:c_diagnostic_error;
    assign O_warp_error=invalid[3]?4'd6:w_error;
    assign O_warp_diagnostic_error=invalid[3]?9'h108:w_diagnostic;
    assign O_outline_error=invalid[4]?4'd2:o_error;
    assign O_outline_diagnostic_error=invalid[4]?9'h108:o_diagnostic;
    assign O_raw_inside=r_inside&&!invalid[2]&&!fence;
    assign O_raw_convex=r_convex&&!invalid[2]&&!fence;
    assign O_warp_busy=w_busy||selected_warp;
    assign O_outline_busy=o_busy||selected_outline;
    assign O_sample_complete=w_complete&&!invalid[3]&&!fence;
    assign O_tap_inside=w_taps;assign O_gray=w_gray;
    assign O_registration=o_registration&&!invalid[4]&&!fence;
    assign O_outline_complete=o_complete&&!invalid[4]&&!fence;
    assign O_outline_mask=o_mask;
    assign O_ws_we=c_offset_we&&c_event_owner;
    assign O_ws_waddr=c_offset_waddr;assign O_ws_wdata=c_offset_wdata;
    pcb_coarse_geometry_host_external_candidate #(
        .POSE_ENTRY(POSE_ENTRY),.AFFINE_ENTRY(AFFINE_ENTRY),
        .OFFSET_BASE(OFFSET_BASE),.WATCHDOG(WATCHDOG)) u_coarse(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_cancel(fence),
        .I_pose_start(c_pose_start),.I_affine_start(c_affine_start),
        .I_width_index(I_width_index),.I_angle_index(I_angle_index),
        .I_center_x(I_center_x),.I_center_y(I_center_y),
        .O_ready(c_ready),.O_active(c_active),
        .O_pose_done(c_pose_done),.O_pose_valid(c_pose_valid),.O_pose_error(c_pose_error),
        .O_xmin(O_xmin),.O_ymin(O_ymin),
        .O_affine_done(c_affine_done),.O_affine_valid(c_affine_valid),.O_affine_error(c_affine_error),
        .O_coarse(O_coarse),.O_diagnostic_error(c_diagnostic_error),
        .O_offset_we(c_offset_we),.O_offset_waddr(c_offset_waddr),.O_offset_wdata(c_offset_wdata),
        .I_engine_rf_addr(rf_addr),.I_engine_rf_we(private_rf_we&&selected_coarse),
        .I_engine_rf_wdata(rf_wdata),
        .O_engine_cancel(c_cancel),.O_engine_host_write(c_host_write),.O_engine_start(c_start),
        .O_engine_emit_ready(c_emit_ready),.O_engine_host_index(c_host_index),
        .O_engine_host_data(c_host_data),.O_engine_entry(c_entry),
        .I_engine_busy(engine_busy&&selected_coarse),.I_engine_done(engine_done&&c_event_owner),
        .I_engine_valid(engine_valid&&c_event_owner),.I_engine_host_ready(host_ready&&c_event_owner),
        .I_engine_host_done(host_done&&c_event_owner),.I_engine_status(engine_status),
        .I_engine_error(engine_error),.I_engine_emit_valid(emit_valid&&c_event_owner),
        .I_engine_emit_tag(emit_tag),.I_engine_emit_d(emit_d),.I_engine_emit_a(emit_a),.I_engine_emit_b(emit_b));

    pcb_raw_geometry_host_external_candidate #(
        .GEOMETRY_ENTRY(GEOMETRY_ENTRY),.WATCHDOG(WATCHDOG)) u_raw(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_cancel(fence),.I_start(raw_start),.I_corners(I_corners),
        .O_ready(r_ready),.O_busy(r_busy),.O_done(r_done),.O_valid(r_valid),
        .O_inside(r_inside),.O_convex(r_convex),.O_error(r_error),
        .O_engine_cancel(r_cancel),.O_engine_host_write(r_host_write),.O_engine_start(r_start),
        .O_engine_emit_ready(r_emit_ready),.O_engine_host_index(r_host_index),
        .O_engine_host_data(r_host_data),.O_engine_entry(r_entry),
        .I_engine_busy(engine_busy&&selected_raw),.I_engine_done(engine_done&&r_event_owner),
        .I_engine_valid(engine_valid&&r_event_owner),.I_engine_host_ready(host_ready&&r_event_owner),
        .I_engine_host_done(host_done&&r_event_owner),.I_engine_status(engine_status),
        .I_engine_error(engine_error),.I_engine_emit_valid(emit_valid&&r_event_owner),
        .I_engine_emit_tag(emit_tag),.I_engine_emit_d(emit_d),.I_engine_emit_a(emit_a),.I_engine_emit_b(emit_b));


    pcb_warp_host_persistent_context_candidate #(.WATCHDOG(WATCHDOG)) u_warp(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(warp_start),.I_cancel(fence),.I_released(release_warp),
        .I_x(I_x),.I_y(I_y),.I_use_fine(I_use_fine),.I_apply_coarse(I_apply_coarse),.I_half_image(I_half_image),
        .I_load_coarse(load_coarse_now),.I_coarse(I_coarse),
        .I_fine_present(ctx_fine),.I_coarse_present(ctx_coarse),.I_context_spilled(ctx_spilled),
        .I_context_dirty(ctx_dirty||!context_live),.I_context_busy(ctx_busy),
        .O_loaded_coarse(w_loaded_coarse),.O_ready(),.O_busy(w_busy),.O_retiring(w_retiring),
        .O_done(w_done),.O_valid(w_valid),.O_sample_complete(w_complete),.O_error(w_error),
        .O_tap_inside(w_taps),.O_diagnostic_error(w_diagnostic),.O_gray(w_gray),
        .O_project_x_q16(O_project_x_q16),.O_project_y_q16(O_project_y_q16),
        .O_source_x_q28(O_source_x_q28),.O_source_y_q28(O_source_y_q28),
        .O_engine_cancel(w_cancel),.O_engine_host_write(w_host_write),.O_engine_start(w_start),
        .O_engine_emit_ready(w_emit_ready),.O_engine_host_index(w_host_index),.O_engine_host_data(w_host_data),.O_engine_entry(w_entry),
        .I_engine_busy(engine_busy&&selected_warp),.I_engine_done(engine_done&&w_event_owner),
        .I_engine_valid(engine_valid&&w_event_owner),.I_engine_host_ready(host_ready&&w_event_owner),
        .I_engine_host_done(host_done&&w_event_owner),.I_engine_status(engine_status),.I_engine_error(engine_error),
        .I_engine_emit_valid(emit_valid&&w_event_owner),.I_engine_emit_tag(emit_tag),
        .I_engine_emit_d(emit_d),.I_engine_emit_a(emit_a),.I_engine_emit_b(emit_b),
        .I_uop_busy(uop_busy&&selected_warp),.I_uop_done(uop_done&&w_event_owner),.I_uop_valid(uop_valid),
        .I_uop_complete(uop_complete),.I_uop_error(uop_error),.I_uop_taps(uop_taps),.I_uop_gray(uop_gray));
    pcb_outline_host_external_candidate #(.WATCHDOG(OUTLINE_TIMEOUT)) u_outline(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_start(outline_start),.I_cancel(fence),.I_released(release_outline),
        .I_board_convex(I_board_convex),.I_board_inside(I_board_inside),.O_ready(),.O_busy(o_busy),.O_retiring(o_retiring),
        .O_endpoint_begin(o_begin),.O_done(o_done),.O_valid(o_valid),.O_registration(o_registration),
        .O_complete(o_complete),.O_mask(o_mask),.O_error(o_error),.O_diagnostic_error(o_diagnostic),
        .O_engine_cancel(o_cancel),.O_engine_host_write(o_host_write),.O_engine_start(o_start),
        .O_engine_emit_ready(o_emit_ready),.O_engine_host_index(o_host_index),.O_engine_host_data(o_host_data),.O_engine_entry(o_entry),
        .I_engine_busy(engine_busy&&selected_outline),.I_engine_done(engine_done&&o_event_owner),
        .I_engine_valid(engine_valid&&o_event_owner),.I_engine_host_ready(host_ready&&o_event_owner),
        .I_engine_host_done(host_done&&o_event_owner),.I_engine_status(engine_status),.I_engine_error(engine_error),
        .I_engine_emit_valid(emit_valid&&o_event_owner),.I_engine_emit_tag(emit_tag),
        .I_engine_emit_d(emit_d),.I_engine_emit_a(emit_a),.I_engine_emit_b(emit_b),
        .I_endpoint_idle(ep_idle),.I_endpoint_fault(ep_fault),.I_endpoint_locked(ep_locked),.I_endpoint_error(ep_error));
    pcb_fine_persistent_rf_context_candidate u_context(
        .clk(I_clk),.rst_n(I_rst_n),.I_cancel(I_cancel),.I_fault(context_fault),
        .I_grant(context_grant),.I_cmd_valid(context_start),.I_epoch_start(epoch_accept),
        .I_coarse_loaded(w_loaded_coarse&&!fence),.I_released(release_context),
        .I_command(I_context_command),.I_slot(I_context_slot),.I_choice(I_context_choice),
        .I_increment(I_context_increment),.O_cmd_ready(ctx_ready),.O_busy(ctx_busy),
        .O_retiring(ctx_retiring),.O_done(ctx_done),.O_error(ctx_error),
        .O_fine_present(ctx_fine),.O_coarse_present(ctx_coarse),.O_spilled(ctx_spilled),.O_dirty(ctx_dirty),
        .O_rf_a_addr(ctx_a_addr),.O_rf_b_addr(ctx_b_addr),.O_rf_we(ctx_we),.O_rf_wdata(ctx_wdata),
        .I_rf_a_data(rf_rdata),.I_rf_b_data(rf_brdata),.I_r(engine_r),
        .O_r_we(ctx_r_we),.O_r_data(ctx_r_data),.O_alu_a(ctx_alu_a),.O_alu_b(ctx_alu_b),
        .O_alu_carry(ctx_alu_carry),.I_alu_sum(engine_alu_sum));
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)context_live<=0;
        else if(fence||I_context_invalidate)context_live<=0;
        else if(epoch_accept)context_live<=1;
    end
    pcb_combined_microcode_engine_candidate #(.ROM_FILE(ROM_FILE),.ROM_BITS(11),.ENABLE_NCC(0),
        .PROGRAM_WORDS(PROGRAM_WORDS),.CONSTANT_WORDS(CONSTANT_WORDS),.PIXEL_TIMEOUT(PIXEL_TIMEOUT)) u_engine(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_cancel(engine_cancel),
        .I_context_grant(selected_context&&context_grant),
        .I_context_r_we(ctx_r_we&&selected_context&&!fence),.I_context_r_data(ctx_r_data),
        .I_context_alu_a(ctx_alu_a),.I_context_alu_b(ctx_alu_b),.I_context_alu_carry(ctx_alu_carry),
        .O_context_r(engine_r),.O_context_alu_sum(engine_alu_sum),.O_context_available(engine_context_available),
        .I_host_write(!fence&&(selected_coarse?c_host_write:selected_raw?r_host_write:selected_warp?w_host_write:selected_outline?o_host_write:1'b0)),
        .I_host_index(selected_coarse?c_host_index:selected_raw?r_host_index:selected_warp?w_host_index:o_host_index),
        .I_host_data(selected_coarse?c_host_data:selected_raw?r_host_data:selected_warp?w_host_data:o_host_data),
        .O_host_ready(host_ready),.O_host_done(host_done),
        .I_start(!fence&&(selected_coarse?c_start:selected_raw?r_start:selected_warp?w_start:selected_outline?o_start:1'b0)),
        .I_entry(selected_coarse?c_entry:selected_raw?r_entry:selected_warp?w_entry:o_entry),
        .O_busy(engine_busy),.O_done(engine_done),.O_valid(engine_valid),.O_status(engine_status),.O_error(engine_error),
        .O_emit_valid(emit_valid),.I_emit_ready(!fence&&(selected_coarse?c_emit_ready:selected_raw?r_emit_ready:selected_warp?w_emit_ready:selected_outline?o_emit_ready:1'b0)),
        .O_emit_tag(emit_tag),.O_emit_d(emit_d),.O_emit_a(emit_a),.O_emit_b(emit_b),
        .O_io_valid(io_valid),.I_io_ready(io_ready&&selected_outline),.O_io_command(io_command),.O_io_a(io_a),.O_io_b(io_b),
        .I_io_response_valid(io_response_valid&&selected_outline),.O_io_response_ready(io_response_ready),.I_io_return_data(io_return),.O_io_abort(io_abort),
        .O_pixel_request(O_pixel_request),.O_pixel_x(O_pixel_x),.O_pixel_y(O_pixel_y),
        .I_pixel_ready(I_pixel_ready&&selected_warp),.I_pixel_valid(I_pixel_valid&&selected_warp),.I_pixel_y8(I_pixel_y8),
        .O_warp_busy(uop_busy),.O_warp_done(uop_done),.O_warp_valid(uop_valid),.O_warp_error(uop_error),
        .O_warp_gray(uop_gray),.O_warp_complete(uop_complete),.O_warp_taps(uop_taps),
        .O_ws_addr(rf_addr),.O_ws_baddr(rf_baddr),.O_ws_we(rf_we),.O_ws_wdata(rf_wdata),
        .I_ws_rdata(rf_rdata),.I_ws_brdata(rf_brdata),.O_pc(),.O_opcode());
    pcb_shared_service_rf_candidate u_private_rf(
        .I_clk(I_clk),.I_a_addr(physical_rf_addr),.I_a_we(private_rf_we),.I_a_wdata(physical_rf_wdata),.O_a_rdata(rf_rdata),
        .I_b_addr(physical_rf_baddr),.O_b_rdata(rf_brdata));
    wire ep_stats_cancel,ep_ncc_cancel;
    assign O_outline_stats_cancel=selected_outline&&ep_stats_cancel;
    assign O_outline_ncc_cancel=selected_outline&&ep_ncc_cancel;
    pcb_outline_io_endpoint_external_ncc_candidate u_outline_endpoint(
        .clk(I_clk),.rst_n(I_rst_n),.begin_job(o_begin),.cancel(fence||(selected_outline&&(io_abort||o_cancel))),
        .request_valid(io_valid&&o_event_owner),.request_ready(io_ready),.command(io_command),.arg_a(io_a),.arg_b(io_b),
        .response_valid(io_response_valid),.response_ready(io_response_ready&&selected_outline),.return_data(io_return),
        .busy(ep_busy),.idle(ep_idle),.locked(ep_locked),.fault(ep_fault),.error(ep_error),
        .ram_request(O_outline_ram_request),.ram_bank(O_outline_ram_bank),.ram_address(O_outline_ram_addr),
        .ram_ready(I_outline_ram_ready&&selected_outline),.ram_valid(I_outline_ram_valid&&selected_outline),
        .ram_idle(selected_outline?I_outline_ram_idle:1'b1),.ram_data(I_outline_ram_data),
        .stats_start(O_outline_stats_start),.stats_cancel(ep_stats_cancel),.stats_count_log2(O_outline_stats_count_log2),
        .sample_valid(O_outline_sample_valid),.sample_i(O_outline_sample_i),.sample_t(O_outline_sample_t),
        .sample_ready(I_stats_ready&&selected_outline),.stats_busy(I_stats_busy&&selected_outline),
        .stats_done(I_stats_done&&selected_outline),.stats_valid(I_stats_valid),.stats_error(I_stats_error),
        .covariance(I_covariance),.variance_i(I_variance_i),.variance_t(I_variance_t),
        .ncc_start(O_outline_ncc_start),.ncc_cancel(ep_ncc_cancel),.ncc_busy(I_ncc_busy&&selected_outline),
        .ncc_done(I_ncc_done&&selected_outline),.ncc_valid(I_ncc_valid),.ncc_positive(I_ncc_positive),.ncc_score(I_ncc_score),.ncc_error(I_ncc_error));
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin owner<=OWNER_NONE;owner_affine<=0;fault_pending<=0;affected<=0;invalid<=0;fault_done<=0;O_service_fault<=0;O_service_error<=0;end
        else begin
            fault_done<=0;O_service_fault<=0;
            if(fault_pending)begin
                affected<=affected|request;invalid<=invalid|request;
                if(all_idle)begin fault_done<=affected|request;fault_pending<=0;affected<=0;owner<=OWNER_NONE;end
            end else if(conflict_now)begin
                fault_pending<=1;O_service_fault<=1;O_service_error<=9'h108;
                affected<=request|active_request;invalid<=invalid|request|active_request;
            end else if(owner==OWNER_NONE)begin
                if(can_accept&&|request)begin
                    O_service_error<=0;invalid<=invalid&~request;
                    if(I_context_start)owner<=OWNER_CONTEXT;
                    else if(I_outline_start)owner<=OWNER_OUTLINE;
                    else if(I_warp_start)owner<=OWNER_WARP;
                    else if(I_raw_start)owner<=OWNER_RAW;
                    else begin owner<=OWNER_COARSE;owner_affine<=I_affine_start;end
                end
            end else if(primitive_idle&&((selected_coarse&&!c_active)||(selected_raw&&!r_busy)||
                (selected_warp&&w_retiring)||(selected_outline&&o_retiring)||(selected_context&&ctx_retiring)))owner<=OWNER_NONE;
        end
    end
endmodule
