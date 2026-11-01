module isp_top #(
    // Video-only ISP path. The stream is passed through after AWB.
    parameter EDGE_ENABLE = 1'b0
) (
    input             axi4s_video_aclk,
    input             I_rst_n            ,
    input             I_tlast            ,
    input             I_tuser            ,
    input [39:0]     I_tdata            ,
    input             I_tvalid        ,
    input [9:0]     I_tdest            ,
    input [4:0]  I_style_mode,
    input [7:0]  I_den_strength,   // denoise strength (follows analogue gain)
    input        I_det_en,         // SW1: colour-blob detection enable
    input             O_tready        ,
    output [127:0]     O_tdata            ,
    output             O_tlast            ,
    output             O_tuser            ,
    output             O_tvalid        ,
    output             I_tready        ,
    // Auto-exposure feedback stats (pre-WB, pre-style), for the AE controller.
    output [8:0]       O_avg_luma,
    output [8:0]       O_clip_pct,
    output             O_frame_tgl,

    // Colour-blob detection metadata (SW1).  Frame rate, stable for a whole
    // frame; O_tgt_toggle is the CDC handshake to the display domain.
    output             O_tgt_valid,
    output [9:0]       O_tgt_x_min,
    output [9:0]       O_tgt_y_min,
    output [9:0]       O_tgt_x_max,
    output [9:0]       O_tgt_y_max,
    output [9:0]       O_tgt_cx,
    output [9:0]       O_tgt_cy,
    output [23:0]      O_tgt_area,
    output [1:0]       O_tgt_color,
    output             O_tgt_toggle,

    // Motion metadata.  Updated on the same frame boundary as the target
    // metadata, so the display side latches both on the single O_tgt_toggle
    // edge -- one CDC handshake for the lot.
    output             O_mot_valid,
    output [9:0]       O_mot_x_min,
    output [9:0]       O_mot_y_min,
    output [9:0]       O_mot_x_max,
    output [9:0]       O_mot_y_max,
    output [15:0]      O_mot_count
);

    wire [8:0] st_avg_luma;
    wire [8:0] st_clip_pct;
    wire       st_frame_tgl;

    wire         m_aixs_tvalid;
    wire [127:0] m_aixs_tdata;
    wire         m_aixs_tuser;
    wire         m_aixs_tlast;
    wire         m_aixs_tready;

    wire [95:0] m_aixs_tdata_96;

    wire         awb_O_tlast;
    wire         awb_O_tuser;
    wire [95:0] awb_O_tdata;
    wire         awb_O_tvalid;
    wire         awb_O_tready;

    wire         S_den_tready;                 // denoise input-ready (to awb)
    wire         den_O_tlast, den_O_tuser, den_O_tvalid;
    wire [95:0]  den_O_tdata;

    wire         style_O_tlast, style_O_tuser, style_O_tvalid, style_O_tready;
    wire [95:0]  style_O_tdata;

    wire         out_96_tlast;
    wire         out_96_tuser;
    wire         out_96_tvalid;
    wire [95:0]  out_96_tdata;

    wire         O_128_tlast;
    wire         O_128_tuser;
    wire         O_128_tvalid;
    wire [127:0] O_128_tdata;

    // 顶层输出直接来自 96->128 转换器（方案A：不再做 style=0 顶层 MUX，
    // style 模块内部 style=0 直通，整条握手链 demosaic->awb->style->packer 完整）。
    assign O_tdata  = O_128_tdata;
    assign O_tlast  = O_128_tlast;
    assign O_tuser  = O_128_tuser;
    assign O_tvalid = O_128_tvalid;

    demosaic #(
        .IMG_HEIGHT          (720),
        .IMG_WIDTH           (1280),
        .data_complete_delay (50  ),
        .BAYER_MODE          ("BGGR")
    )
    u_demosaic
    (
        .I_clk               (axi4s_video_aclk),
        .I_rst_n             (I_rst_n),
        .axi4s_video_tdata   (I_tdata),
        .axi4s_video_tdest   (I_tdest),
        .axi4s_video_tlast   (I_tlast),
        .axi4s_video_tvalid  (I_tvalid),
        .axi4s_video_tuser   (I_tuser),
        .axi4s_video_tready  (I_tready),
        .O_tlast             (m_aixs_tlast),
        .O_tuser             (m_aixs_tuser),
        .O_tdata             (m_aixs_tdata),
        .O_tvalid            (m_aixs_tvalid),
        .O_tready            (m_aixs_tready)
    );

    data128_96 u_data128_96 (
        .I_tdata(m_aixs_tdata),
        .O_tdata(m_aixs_tdata_96)
    );

    // Post-WB luma / clip stats for the auto-exposure controller.  Sampling
    // AFTER white balance so the stats reflect the displayed highlights, and
    // measuring the centre rows so a bright background does not starve an
    // otherwise-dark subject.
    isp_luma_stat #(.CLIP_TH(250), .PIX_PER_BEAT(4),
                    .IMG_HEIGHT(720), .IMG_WIDTH(1280)) u_luma_stat (
        .I_clk       (axi4s_video_aclk),
        .I_rst_n     (I_rst_n),
        .I_tvalid    (awb_O_tvalid),
        .I_tuser     (awb_O_tuser),
        .I_tlast     (awb_O_tlast),
        .I_tdata     (awb_O_tdata),
        .O_avg_luma  (st_avg_luma),
        .O_clip_pct  (st_clip_pct),
        .O_frame_tgl (st_frame_tgl)
    );
    assign O_avg_luma  = st_avg_luma;
    assign O_clip_pct  = st_clip_pct;
    assign O_frame_tgl = st_frame_tgl;

    // Colour-blob detection.  Snoops the post-WB stream so KEY2 style modes
    // cannot disturb the colour thresholds; consumed when awb is accepted.
    target_detect_96 #(
        .DOM_MIN (8'd96),
        .DOM_OTH (8'd80),
        .DOM_DELTA(8'd40),
        .MIN_AREA(24'd1200),
        .MAX_BOX_W(11'd800),
        .MAX_BOX_H(10'd600)
    ) u_target_detect (
        .I_clk   (axi4s_video_aclk),
        .I_rst_n (I_rst_n),
        .I_en    (I_det_en),
        .I_vld   (awb_O_tvalid & S_den_tready),
        .I_tuser (awb_O_tuser),
        .I_tlast (awb_O_tlast),
        .I_tdata (awb_O_tdata),
        .O_valid (O_tgt_valid),
        .O_x_min (O_tgt_x_min),
        .O_y_min (O_tgt_y_min),
        .O_x_max (O_tgt_x_max),
        .O_y_max (O_tgt_y_max),
        .O_cx    (O_tgt_cx),
        .O_cy    (O_tgt_cy),
        .O_area  (O_tgt_area),
        .O_color (O_tgt_color),
        .O_toggle(O_tgt_toggle)
    );

    // Frame-difference motion detection, same tap point as the colour detector.
    // Medium sensitivity profile: 48-count difference, 64-count dark gate,
    // 800-sample minimum and three-frame confirmation.  The detector still
    // checks that the reported box is at least 12.5% occupied.
    motion_detect #(
        .MOTION_TH(8'd48),
        .DARK_MIN (8'd64),
        .MIN_AREA (16'd800),
        .CONFIRM  (3)
    ) u_motion_detect (
        .I_clk   (axi4s_video_aclk),
        .I_rst_n (I_rst_n),
        .I_en    (I_det_en),
        .I_vld   (awb_O_tvalid & S_den_tready),
        .I_tuser (awb_O_tuser),
        .I_tlast (awb_O_tlast),
        .I_pix   (awb_O_tdata[23:0]),
        .O_valid (O_mot_valid),
        .O_x_min (O_mot_x_min),
        .O_y_min (O_mot_y_min),
        .O_x_max (O_mot_x_max),
        .O_y_max (O_mot_y_max),
        .O_count (O_mot_count)
    );

    awb #(
        .IMG_HEIGHT(720),
        .IMG_WIDTH (1280)
    ) u_awb (
        .I_clk   (axi4s_video_aclk),
        .I_rst_n (I_rst_n),
        .I_tlast (m_aixs_tlast),
        .I_tuser (m_aixs_tuser),
        .I_tdata (m_aixs_tdata_96),
        .I_tvalid(m_aixs_tvalid),
        .I_tready(m_aixs_tready),
        .O_tlast (awb_O_tlast ),
        .O_tuser (awb_O_tuser ),
        .O_tdata (awb_O_tdata ),
        .O_tvalid(awb_O_tvalid),
        .O_tready(S_den_tready)
    );

    // Light edge-preserving denoise between AWB and the style stage.  Strength
    // follows the analogue gain (higher gain -> more noise -> more smoothing).
    denoise_96 #(
        .IMG_WIDTH (1280),
        .IMG_HEIGHT(720)
    ) u_denoise (
        .I_clk     (axi4s_video_aclk),
        .I_rst_n   (I_rst_n),
        .I_tlast   (awb_O_tlast ),
        .I_tuser   (awb_O_tuser ),
        .I_tdata   (awb_O_tdata ),
        .I_tvalid  (awb_O_tvalid),
        .O_tready  (awb_O_tready),     // downstream (style) accept
        .I_tready  (S_den_tready),     // tell awb we accept
        .I_strength(I_den_strength),
        .O_tlast   (den_O_tlast ),
        .O_tuser   (den_O_tuser ),
        .O_tdata   (den_O_tdata ),
        .O_tvalid  (den_O_tvalid)
    );

    style_transfer_96 #(
        .IMG_WIDTH  (1280),
        .IMG_HEIGHT (720),
        .NUM_STYLES (19)
    ) u_style_transfer_96 (
        .I_clk        (axi4s_video_aclk),
        .I_rst_n      (I_rst_n),
        .I_style_mode (I_style_mode),
        .I_tlast      (den_O_tlast),
        .I_tuser      (den_O_tuser),
        .I_tdata      (den_O_tdata),
        .I_tvalid     (den_O_tvalid),
        .O_tready     (O_tready),
        .I_tready     (awb_O_tready),
        .O_tlast      (style_O_tlast),
        .O_tuser      (style_O_tuser),
        .O_tdata      (style_O_tdata),
        .O_tvalid     (style_O_tvalid)
    );

    assign out_96_tlast  = style_O_tlast;
    assign out_96_tuser  = style_O_tuser;
    assign out_96_tvalid = style_O_tvalid;
    assign out_96_tdata  = style_O_tdata;

    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),

        .I_96b_frame_start  ( out_96_tuser  ),
        .I_96b_tlast        ( out_96_tlast  ),
        .I_96b_valid        ( out_96_tvalid ),
        .I_96b_data         ( out_96_tdata  ),

        .O_128b_frame_start ( O_128_tuser      ),
        .O_128b_tlast       ( O_128_tlast      ),
        .O_128b_valid       ( O_128_tvalid     ),
        .O_128b_data        ( O_128_tdata      )
    );

endmodule
