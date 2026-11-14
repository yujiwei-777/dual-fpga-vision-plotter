module isp_top_basic #(
    parameter EDGE_ENABLE = 1'b0,
    parameter STYLE_ENABLE = 1'b0,
    parameter CARTOON_ENABLE = 1'b1,
    parameter RAW_AWB_ENABLE = 1'b1,
    parameter RAW_AE_ENABLE  = 1'b1,
    parameter COLOR_LSC_ENABLE = 1'b0,
    // Fixed original-video diagnostic mode: force style 0 and bypass spatial style processing.
    parameter ORIGINAL_MODE_ENABLE = 1'b0
) (
    input axi4s_video_aclk,
    input I_rst_n,
    input I_tlast,
    input I_tuser,
    input [39:0] I_tdata,
    input I_tvalid,
    input [9:0] I_tdest,
    input [4:0] I_style_mode,
    input [7:0] I_den_strength,
    input I_det_en,
    input O_tready,
    output [127:0] O_tdata,
    output O_tlast,
    output O_tuser,
    output O_tvalid,
    output I_tready,
    output [95:0] O_clean_rgb,
    output O_clean_valid, O_clean_user, O_clean_last,
    output [8:0] O_avg_luma,
    output [8:0] O_clip_pct,
    output [8:0] O_roi_all,
    output O_frame_tgl,
    output O_tgt_valid,
    output [10:0] O_tgt_x_min,
    output [9:0] O_tgt_y_min,
    output [10:0] O_tgt_x_max,
    output [9:0] O_tgt_y_max,
    output [10:0] O_tgt_cx,
    output [9:0] O_tgt_cy,
    output [23:0] O_tgt_area,
    output [1:0] O_tgt_color,
    output [1:0] O_tgt_shape,
    output O_tgt_toggle,
    output O_mot_valid,
    output [10:0] O_mot_x_min,
    output [9:0] O_mot_y_min,
    output [10:0] O_mot_x_max,
    output [9:0] O_mot_y_max,
    output [15:0] O_mot_count
    ,output O_mot_toggle
    ,output [3:0] O_cnn_class_id
    ,output [7:0] O_cnn_confidence
    ,output [3:0] O_cnn_conf_tens
    ,output [3:0] O_cnn_conf_ones
    ,output O_cnn_valid
    ,output O_cnn_toggle
    ,output [223:0] O_awb_diag
);
    wire core_tlast, core_tuser, core_tvalid, core_tready;
    wire [127:0] core_tdata;
    isp_top_basic_core #(.STYLE_ENABLE(STYLE_ENABLE), .CARTOON_ENABLE(CARTOON_ENABLE),
                         .RAW_AWB_ENABLE(RAW_AWB_ENABLE), .RAW_AE_ENABLE(RAW_AE_ENABLE),
                         .COLOR_LSC_ENABLE(COLOR_LSC_ENABLE), .ORIGINAL_MODE_ENABLE(ORIGINAL_MODE_ENABLE)) u_core (
        .axi4s_video_aclk(axi4s_video_aclk),
        .I_rst_n(I_rst_n),
        .I_tlast(I_tlast), .I_tuser(I_tuser), .I_tdata(I_tdata),
        .I_tvalid(I_tvalid), .I_tdest(I_tdest), .I_det_en(I_det_en),
        .I_style_mode(I_style_mode), .I_den_strength(I_den_strength), .O_tready(O_tready),
        .O_tdata(core_tdata), .O_tlast(core_tlast), .O_tuser(core_tuser),
        .O_tvalid(core_tvalid), .I_tready(I_tready),
        .O_tgt_valid(O_tgt_valid), .O_tgt_x_min(O_tgt_x_min), .O_tgt_y_min(O_tgt_y_min),
        .O_tgt_x_max(O_tgt_x_max), .O_tgt_y_max(O_tgt_y_max), .O_tgt_cx(O_tgt_cx),
        .O_tgt_cy(O_tgt_cy), .O_tgt_area(O_tgt_area), .O_tgt_color(O_tgt_color),
        .O_tgt_shape(O_tgt_shape),
        .O_tgt_toggle(O_tgt_toggle), .O_mot_valid(O_mot_valid),
        .O_mot_x_min(O_mot_x_min), .O_mot_y_min(O_mot_y_min),
        .O_mot_x_max(O_mot_x_max), .O_mot_y_max(O_mot_y_max),
        .O_mot_count(O_mot_count), .O_mot_toggle(O_mot_toggle),
        .O_cnn_class_id(O_cnn_class_id), .O_cnn_confidence(O_cnn_confidence),
        .O_cnn_conf_tens(O_cnn_conf_tens), .O_cnn_conf_ones(O_cnn_conf_ones),
        .O_cnn_valid(O_cnn_valid), .O_cnn_toggle(O_cnn_toggle),
        .O_clean_rgb(O_clean_rgb), .O_clean_valid(O_clean_valid),
        .O_clean_user(O_clean_user), .O_clean_last(O_clean_last),
        .O_avg_luma(O_avg_luma), .O_clip_pct(O_clip_pct), .O_roi_all(O_roi_all),
        .O_frame_tgl(O_frame_tgl), .O_awb_diag(O_awb_diag)
    );
    assign O_tdata = core_tdata;
    assign O_tlast = core_tlast;
    assign O_tuser = core_tuser;
    assign O_tvalid = core_tvalid;
endmodule
