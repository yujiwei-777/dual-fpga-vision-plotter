`timescale 1ns/1ps
// Proof-only production sampler interface around the complete shared service.
// One combined16x16 engine, shared ALU/ROM and private synchronous RF.
module serial_integer_warp_combined_service_wrapper #(
    parameter integer WAIT_TIMEOUT=4096,
    parameter ROM_FILE="combined_geometry_warp_outline_rom_2048.mem",
    parameter integer WATCHDOG=2000000
) (
    input wire I_clk,I_rst_n,I_start,I_cancel,
    input wire [7:0] I_x,input wire [6:0] I_y,
    input wire I_use_fine,I_apply_coarse,I_half_image,
    input wire [255:0] I_fine,input wire [239:0] I_coarse,
    output wire O_busy,output wire O_done,O_valid,output wire [3:0] O_error,
    output wire [7:0] O_gray,output wire O_sample_complete,
    output wire [3:0] O_tap_inside,output wire O_pixel_request,
    output wire [10:0] O_pixel_x,output wire [9:0] O_pixel_y,
    input wire I_pixel_ready,I_pixel_valid,input wire [7:0] I_pixel_y8,
    output wire signed [31:0] O_project_x_q16,O_project_y_q16,
    output wire signed [63:0] O_source_x_q28,O_source_y_q28
);

    pcb_combined_shared_service_candidate #(.ROM_FILE(ROM_FILE),.PIXEL_TIMEOUT(WAIT_TIMEOUT),.WATCHDOG(WATCHDOG)) service(
        .I_pose_start(1'b0),.I_affine_start(1'b0),.I_raw_start(1'b0),.I_outline_start(1'b0),
        .I_width_index(4'd0),.I_angle_index(4'd0),.I_center_x(7'd0),.I_center_y(7'd0),.I_corners(316'd0),
        .I_board_convex(1'b0),.I_board_inside(1'b0),.I_outline_ram_ready(1'b0),.I_outline_ram_valid(1'b0),.I_outline_ram_idle(1'b1),.I_outline_ram_data(16'd0),
        .I_stats_ready(1'b0),.I_stats_busy(1'b0),.I_stats_done(1'b0),.I_stats_valid(1'b0),.I_stats_error(4'd0),
        .I_covariance(36'd0),.I_variance_i(36'd0),.I_variance_t(36'd0),
        .I_ncc_busy(1'b0),.I_ncc_done(1'b0),.I_ncc_valid(1'b0),.I_ncc_positive(1'b0),.I_ncc_score(31'd0),.I_ncc_error(4'd0),
        .I_clk(I_clk),
        .I_rst_n(I_rst_n),
        .I_warp_start(I_start),
        .I_cancel(I_cancel),
        .I_x(I_x),
        .I_y(I_y),
        .I_use_fine(I_use_fine),
        .I_apply_coarse(I_apply_coarse),
        .I_half_image(I_half_image),
        .I_fine(I_fine),
        .I_coarse(I_coarse),
        .O_warp_busy(O_busy),
        .O_warp_done(O_done),
        .O_warp_valid(O_valid),
        .O_warp_error(O_error),
        .O_gray(O_gray),
        .O_sample_complete(O_sample_complete),
        .O_tap_inside(O_tap_inside),
        .O_pixel_request(O_pixel_request),
        .O_pixel_x(O_pixel_x),
        .O_pixel_y(O_pixel_y),
        .I_pixel_ready(I_pixel_ready),
        .I_pixel_valid(I_pixel_valid),
        .I_pixel_y8(I_pixel_y8),
        .O_project_x_q16(O_project_x_q16),
        .O_project_y_q16(O_project_y_q16),
        .O_source_x_q28(O_source_x_q28),
        .O_source_y_q28(O_source_y_q28));
endmodule
