module isp_top_basic_core #(
    // Keep the stable AWB -> packer path as the default.  The display style
    // stage is selected explicitly by the top-level wrapper.
    parameter STYLE_ENABLE = 1'b0,
    // Keep the display Tone stage available while allowing the cartoon
    // transfer block to be compiled out for the main-board camera build.
    parameter CARTOON_ENABLE = 1'b1,
    // RAW-domain calibration is the production path.  Keeping these as
    // parameters leaves a deterministic RGB-AWB/post-AWB-AE fallback for
    // A/B diagnosis without changing the external interface.
    parameter RAW_AWB_ENABLE = 1'b1,
    parameter RAW_AE_ENABLE  = 1'b1,
    parameter COLOR_LSC_ENABLE = 1'b0,
    // Fixed original-video diagnostic mode: force style 0 and bypass spatial style processing.
    parameter ORIGINAL_MODE_ENABLE = 1'b0
) (
    input 			axi4s_video_aclk,
    input 			I_rst_n			,
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,
    input           I_det_en,
    input [4:0]     I_style_mode,
    input [7:0]     I_den_strength,
    input 			O_tready		,
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready,
    output          O_tgt_valid,
    output [10:0]   O_tgt_x_min,
    output [9:0]    O_tgt_y_min,
    output [10:0]   O_tgt_x_max,
    output [9:0]    O_tgt_y_max,
    output [10:0]   O_tgt_cx,
    output [9:0]    O_tgt_cy,
    output [23:0]   O_tgt_area,
    output [1:0]    O_tgt_color,
    output [1:0]    O_tgt_shape,
    output          O_tgt_toggle,
    output          O_mot_valid,
    output [10:0]   O_mot_x_min,
    output [9:0]    O_mot_y_min,
    output [10:0]   O_mot_x_max,
    output [9:0]    O_mot_y_max,
    output [15:0]   O_mot_count,
    output          O_mot_toggle,
    output [3:0]    O_cnn_class_id,
    output [7:0]    O_cnn_confidence,
    output [3:0]    O_cnn_conf_tens,
    output [3:0]    O_cnn_conf_ones,
    output          O_cnn_valid,
    output          O_cnn_toggle,
    output [95:0]   O_clean_rgb,
    output          O_clean_valid, O_clean_user, O_clean_last,
    output [8:0]    O_avg_luma,
    output [8:0]    O_clip_pct,
    output [8:0] O_roi_all,
    output          O_frame_tgl,
    output [223:0] O_awb_diag
);
 
wire         m_aixs_tvalid;  //synthesis keep 
  wire [127:0] m_aixs_tdata;  //synthesis keep 
  wire         m_aixs_tuser;  //synthesis keep 
  wire         m_aixs_tlast;  //synthesis keep 
  wire         m_aixs_tready;  //synthesis keep 
  
  wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 

  wire         raw_awb_tlast;
  wire         raw_awb_tuser;
  wire [39:0]  raw_awb_tdata;
  wire         raw_awb_tvalid;
  wire         raw_awb_tready;
  wire         demosaic_I_tready;


  wire         awb_O_tlast;  //synthesis keep 
  wire         awb_O_tuser;  //synthesis keep 
  wire [ 95:0] awb_O_tdata;  //synthesis keep 
  wire         awb_O_tvalid;  //synthesis keep 
  wire         awb_O_tready;  //synthesis keep 
  // Compile-time original mode keeps the video style at mode 0 regardless of host/key controls.
  wire [4:0]   style_mode_i = ORIGINAL_MODE_ENABLE ? 5'd0 : I_style_mode;

  // Fixed RGB8 equivalent CCM. It is intentionally after AWB and before
  // Tone; both HDMI and the fixed Tone/CNN/Snapshot tap see its output.
  wire [95:0] ccm_O_tdata;
  wire ccm_O_tvalid, ccm_O_tuser, ccm_O_tlast, ccm_O_tready;
  ccm8_4x u_ccm8_4x (
      .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
      .I_tdata(awb_O_tdata), .I_tvalid(awb_O_tvalid),
      .I_tuser(awb_O_tuser), .I_tlast(awb_O_tlast),
      .I_tready(awb_O_tready), .O_tready(ccm_O_tready),
      .O_tdata(ccm_O_tdata), .O_tvalid(ccm_O_tvalid),
      .O_tuser(ccm_O_tuser), .O_tlast(ccm_O_tlast)
  );

  wire [8:0]   st_avg_luma;
  wire [8:0]   st_clip_pct;
    wire [8:0] st_roi_all;
  wire         st_frame_tgl;
  // The RAW monitor is a side-band tap.  Qualifying valid with the actual
  // core input handshake keeps its counters aligned if the elastic AWB or
  // demosaic boundary ever stalls.
  wire         raw_ae_in_valid = raw_lsc_tvalid && raw_awb_tready;
  wire         raw_ae_in_user  = raw_ae_in_valid && raw_lsc_tuser;

  wire         awb_O_tuser_128;  //synthesis keep 
  wire         awb_O_tvalid_128;  //synthesis keep 
  wire [127:0] awb_O_tdata_128;  //synthesis keep 
  wire         awb_O_tlast_128;   //synthesis keep

  wire         style_I_tready;
  wire         tone_I_tready;
  wire         tone_O_tlast;
  wire         tone_O_tuser;
  wire [95:0]  tone_O_tdata;
  wire         tone_O_tvalid;
  wire         style_O_tlast;
  wire         style_O_tuser;
  wire [95:0]  style_O_tdata;
  wire         style_O_tvalid;
  wire [95:0]  tone_fixed_O_tdata;
  wire         tone_fixed_O_tvalid;
  wire         tone_fixed_O_tuser;
  wire         tone_fixed_O_tlast;

  wire         video_96_tlast;
  wire         video_96_tuser;
  wire [95:0]  video_96_tdata;
  wire         video_96_tvalid;

  // The display style path is one-for-one with the camera stream.  Keep the
  // direct style-transfer handshake so AWB and the style pipeline advance
  // together; the former external FIFO/synthetic-row drain changed live
  // frame cadence and was the source of CART-only roll on the board.
  assign O_tdata  = awb_O_tdata_128;
  assign O_tlast  = awb_O_tlast_128;
  assign O_tuser  = awb_O_tuser_128;
  assign O_tvalid = awb_O_tvalid_128;

  generate
    if (STYLE_ENABLE) begin : g_style
      display_tone_96 u_display_tone (
          .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
          .I_tdata(ccm_O_tdata), .I_tvalid(ccm_O_tvalid),
          .I_tuser(ccm_O_tuser), .I_tlast(ccm_O_tlast),
          .I_tone_enable(style_mode_i == 5'd0), .I_tready(tone_I_tready),
          .O_tready(style_I_tready), .O_tdata(tone_O_tdata),
          .O_tvalid(tone_O_tvalid), .O_tuser(tone_O_tuser), .O_tlast(tone_O_tlast),
          .O_fixed_tdata(tone_fixed_O_tdata), .O_fixed_tvalid(tone_fixed_O_tvalid),
          .O_fixed_tuser(tone_fixed_O_tuser), .O_fixed_tlast(tone_fixed_O_tlast));
      style_transfer_96 #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.NUM_STYLES(19),
                           .CART_EDGE_THRESHOLD(32), .CART_QUANT_MASK(8'he0),
                           .CARTOON_ENABLE(CARTOON_ENABLE), .SIMPLE_BYPASS(ORIGINAL_MODE_ENABLE),
                           .FIXED_STYLE_MODE(0)) u_style_transfer(
          .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
          .I_tdata(tone_O_tdata), .I_tvalid(tone_O_tvalid),
          .I_tuser(tone_O_tuser), .I_tlast(tone_O_tlast),
          .I_style_mode(style_mode_i), .O_tready(O_tready),
          .I_tready(style_I_tready), .O_tdata(style_O_tdata),
          .O_tvalid(style_O_tvalid), .O_tuser(style_O_tuser), .O_tlast(style_O_tlast));
      assign ccm_O_tready = tone_I_tready;
      assign video_96_tlast = style_O_tlast;
      assign video_96_tuser = style_O_tuser;
      assign video_96_tdata = style_O_tdata;
      assign video_96_tvalid = style_O_tvalid;
      // Feed the fixed tone curve to the secondary CNN independently of the
      // HDMI style selection.  The display output remains mode-dependent,
      // while the fixed tap always applies tone_group().  Use the same
      // accepted transaction and markers so ready/valid stalls cannot repeat
      // or misalign a CNN pixel.
      assign O_clean_rgb   = tone_fixed_O_tdata;
      assign O_clean_valid = tone_fixed_O_tvalid && style_I_tready;
      assign O_clean_user  = O_clean_valid && tone_fixed_O_tuser;
      assign O_clean_last  = O_clean_valid && tone_fixed_O_tlast;
    end else begin : g_no_style
      assign ccm_O_tready = O_tready;
      assign style_I_tready = O_tready;
      assign video_96_tlast = ccm_O_tlast;
      assign video_96_tuser = ccm_O_tuser;
      assign video_96_tdata = ccm_O_tdata;
      assign video_96_tvalid = ccm_O_tvalid;
      wire clean_accept_no_style = ccm_O_tvalid && O_tready;
      assign O_clean_rgb = ccm_O_tdata;
      assign O_clean_valid = clean_accept_no_style;
      assign O_clean_user = clean_accept_no_style && ccm_O_tuser;
      assign O_clean_last = clean_accept_no_style && ccm_O_tlast;
    end
  endgenerate
  
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;
 
 
// Shared two-stage RAW pipeline: fixed BLC -> optional color LSC.
// Saturation is tagged before attenuation (raw1000 minus BLC64 = 936).
wire [39:0] raw_lsc_tdata;
wire [3:0] raw_lsc_sat_mask;
wire raw_lsc_tvalid, raw_lsc_tuser, raw_lsc_tlast;
wire [3:0] raw_pre_lsc_sat = {
    (I_tdata[39:30] >= 10'd936), (I_tdata[29:20] >= 10'd936),
    (I_tdata[19:10] >= 10'd936), (I_tdata[9:0] >= 10'd936)};
raw10_color_lsc_grid9x7 #(.IMG_WIDTH(1280), .IMG_HEIGHT(720),
                         .LSC_ENABLE(COLOR_LSC_ENABLE)) u_raw10_color_lsc_grid9x7 (
    .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
    .I_tvalid(I_tvalid), .I_tready(I_tready),
    .I_tuser(I_tuser), .I_tlast(I_tlast), .I_tdata(I_tdata), .I_sat_mask(raw_pre_lsc_sat),
    .O_tvalid(raw_lsc_tvalid), .O_tready(raw_awb_tready),
    .O_tuser(raw_lsc_tuser), .O_tlast(raw_lsc_tlast),
    .O_tdata(raw_lsc_tdata), .O_sat_mask(raw_lsc_sat_mask)
);
generate
  if (RAW_AWB_ENABLE) begin : g_raw_awb_input
    awb_raw10_bggr_grayworld #(
        .IMG_WIDTH(1280), .IMG_HEIGHT(720),
        .DARK_MIN(32), .MIN_BLOCKS(128), .STAT_DECIM(8),
        .AWB_STEP(20'h00200), .AWB_DEADBAND(20'h00100)
    ) u_awb_raw10_bggr_grayworld (
        .I_clk(axi4s_video_aclk), .I_rst_n(I_rst_n),
        .I_tvalid(raw_lsc_tvalid), .I_tready(raw_awb_tready),
        .I_tuser(raw_lsc_tuser), .I_tlast(raw_lsc_tlast), .I_tdata(raw_lsc_tdata),
        .I_sat_mask(raw_lsc_sat_mask),
        .O_tvalid(raw_awb_tvalid), .O_tready(demosaic_I_tready),
        .O_tuser(raw_awb_tuser), .O_tlast(raw_awb_tlast),
        .O_tdata(raw_awb_tdata), .O_awb_diag(O_awb_diag)
    );
  end else begin : g_raw_awb_bypass
    assign raw_awb_tvalid = raw_lsc_tvalid;
    assign raw_awb_tuser  = raw_lsc_tuser;
    assign raw_awb_tlast  = raw_lsc_tlast;
    assign raw_awb_tdata  = raw_lsc_tdata;
    assign raw_awb_tready = demosaic_I_tready;
    assign O_awb_diag = 224'd0;
  end
endgenerate

demosaic #(
    .IMG_HEIGHT          (720 ), // 图像高度
    .IMG_WIDTH           (1280), // 图像宽度
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR")
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk)	,   // 时钟信号
    .I_rst_n 			(I_rst_n)	,   // 复位信号，低有效
    .axi4s_video_tdata 	(raw_awb_tdata)	,  // RAW/Bayer stream after optional RAW AWB
    .axi4s_video_tdest 	(I_tdest)	,
    .axi4s_video_tlast 	(raw_awb_tlast)	,  // 行结束信号
    .axi4s_video_tvalid	(raw_awb_tvalid)	,  // 数据有效信号
    .axi4s_video_tuser 	(raw_awb_tuser)	,  // 帧开始信号
    .axi4s_video_tready	(demosaic_I_tready)	,  // 从模块准备好接受数据
    .O_tlast  			(m_aixs_tlast)	,  // 输出行结束信号
    .O_tuser  			(m_aixs_tuser)	,  // 输出帧开始信号
    .O_tdata  			(m_aixs_tdata)	,  // 输出数据
    .O_tvalid 			(m_aixs_tvalid)	,  // 输出数据有效信号
    .O_tready   		(m_aixs_tready)	   // 输出数据准备好信号
);
 
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
);

    // The legacy demosaic-domain RGB AWB remains available as the fallback
    // comparison path.  In the RAW-domain build the demosaic output is
    // already corrected, so bypassing this block avoids a second, unrelated
    // gain estimator changing the colour seen by HDMI and CNN.
    generate
      if (RAW_AWB_ENABLE) begin : g_rgb_awb_bypass
        assign awb_O_tlast  = m_aixs_tlast;
        assign awb_O_tuser  = m_aixs_tuser;
        assign awb_O_tdata  = m_aixs_tdata_96;
        assign awb_O_tvalid = m_aixs_tvalid;
        assign m_aixs_tready = awb_O_tready;
      end else begin : g_rgb_awb_legacy
        awb #(
        .IMG_HEIGHT(720 ),
        .IMG_WIDTH (1280),
        .LUM_MIN   (8),
        .LUM_MAX   (245),
        .ROI_X0    (64),
        .ROI_X1    (1216),
        .ROI_Y0    (36),
        .ROI_Y1    (684),
        .CHROMA_MAX(255),
        .REL_CHROMA_MAX(255)) u_awb (
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
        .O_tready(awb_O_tready)
        );
      end
    endgenerate
    // RAW-domain AE is fed after BLC/LSC and before AWB and
    // demosaic.  The legacy post-RGB statistic remains in the fallback build.
    generate
      if (RAW_AE_ENABLE) begin : g_raw_ae_stat
        raw10_ae_stat #(.IMG_WIDTH(1280), .IMG_HEIGHT(720),
                        .PIX_PER_BEAT(4), .CLIP_TH(10'd944)) u_raw10_ae_stat (
            .I_clk       (axi4s_video_aclk),
            .I_rst_n     (I_rst_n),
            .I_tvalid    (raw_ae_in_valid),
            .I_tuser     (raw_ae_in_user),
            .I_tlast     (raw_lsc_tlast),
            .I_tdata     (raw_lsc_tdata),
            .O_avg_luma  (st_avg_luma),
            .O_clip_pct  (st_clip_pct),
            .O_roi_all   (st_roi_all),
            .O_frame_tgl (st_frame_tgl)
        );
      end else begin : g_rgb_ae_stat
        assign st_roi_all = st_avg_luma;
        isp_luma_stat #(.CLIP_TH(248), .PIX_PER_BEAT(4),
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
      end
    endgenerate
    assign O_avg_luma  = st_avg_luma;
    assign O_clip_pct  = st_clip_pct;
    assign O_roi_all   = st_roi_all;
    assign O_frame_tgl = st_frame_tgl;

    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        .I_96b_frame_start  ( video_96_tuser ),
        .I_96b_tlast        ( video_96_tlast ),
        .I_96b_valid        ( video_96_tvalid ),
        .I_96b_data         ( video_96_tdata ),
	
        .O_128b_frame_start ( awb_O_tuser_128 ),
        .O_128b_tlast       ( awb_O_tlast_128 ),
        .O_128b_valid       ( awb_O_tvalid_128 ),
        .O_128b_data        ( awb_O_tdata_128 )
    );

    // Object recognition is owned by the secondary FPGA in both the CNN and
    // YOLO branches.  Keep these legacy output ports at a deterministic zero
    // so the main-board build contains no local colour/shape detector and the
    // HDMI overlay cannot accidentally display a stale local result.  Motion
    // and PCB presence continue on their independent paths in the wrapper.
    assign O_tgt_valid = 1'b0;
    assign O_tgt_x_min = 11'd0;
    assign O_tgt_y_min = 10'd0;
    assign O_tgt_x_max = 11'd0;
    assign O_tgt_y_max = 10'd0;
    assign O_tgt_cx    = 11'd0;
    assign O_tgt_cy    = 10'd0;
    assign O_tgt_area  = 24'd0;
    assign O_tgt_color = 2'd0;
    assign O_tgt_shape = 2'd0;
    assign O_tgt_toggle= 1'b0;

    // Restore the user-verified 20260918_182713 HDMI-domain motion path.
    // The single frame store lives in design_top_wrapper.u_motion_post_hist.
    // Keep these legacy outputs quiet; colour/shape detection still uses AWB.
    assign O_mot_valid = 1'b0;
    assign O_mot_x_min = 11'd0;
    assign O_mot_y_min = 10'd0;
    assign O_mot_x_max = 11'd0;
    assign O_mot_y_max = 10'd0;
    assign O_mot_count = 16'd0;
    assign O_mot_toggle = 1'b0;

    // Ordinary object recognition runs on the external YOLO board. Keep the
    // legacy result ports quiet until the HXA1 result is committed in the
    // HDMI domain; this removes the local CNN frame classifier and its
    // associated BRAM/control logic from the main-board build.
    assign O_cnn_class_id   = 4'd0;
    assign O_cnn_confidence = 8'd0;
    assign O_cnn_conf_tens  = 4'd0;
    assign O_cnn_conf_ones  = 4'd0;
    assign O_cnn_valid      = 1'b0;
    assign O_cnn_toggle     = 1'b0;



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);
	
endmodule



