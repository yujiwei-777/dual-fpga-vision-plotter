// HX1P35A monitor transport. HDMI is never back-pressured by this module.
module udp_config_status #(
    // HDMI stays 1280x720@60; Ethernet uses a quarter-resolution preview
    // so the existing UDP/GMII path can drain every frame reliably.
    // 320x180 preview keeps each frame to 80 MTU packets.
    parameter integer VIDEO_WIDTH = 320,
    parameter integer VIDEO_HEIGHT = 180,
    parameter integer VIDEO_PIXEL_BYTES = 2,
    parameter integer VIDEO_PAYLOAD_BYTES = 1440,
    // HDMI/camera pixel stream is 60 fps; keep one of every four frames for
    // the monitor branch so the advertised preview rate is 15 fps.
    parameter integer VIDEO_FRAME_DIV = 4,
    parameter integer CNN_SESSION_TIMEOUT_CYCLES = 62500000,
    parameter integer MAX_CNN_FRAME_LAG = 64,
    parameter integer UDP_REQUEST_TIMEOUT_CYCLES = 12500000
    ,parameter integer SESSION_LEASE_CYCLES = 125000000,
    // The lite monitor build accepts CONFIG packets directly.  The optional
    // store-and-forward session guard is retained in the source for builds
    // that need replay protection, but is disabled here to save LUTL/BRAM
    // pressure during placement.
    parameter integer ENABLE_SESSION_GUARD = 0,
    // The monitor build keeps CONFIG_V2 and video/status packets in the
    // released image.  CNN_RESULT/ACTION packet parsing is optional because
    // the classifier already runs locally in the FPGA and this parser costs
    // several thousand LUTs.
    parameter integer ENABLE_EXTENDED_RESULTS = 0,
    // Compile-time legacy preview switch. CONFIG/status, sessions and the
    // shared HXA1/MAC/ARP/IP/UDP/RGMII transport remain active when disabled.
    parameter integer ENABLE_VIDEO_PREVIEW = 1,
    // SW2=0 shares the existing HXA1 peer stream with PC CONFIG/status.
    // Disabled by default for released legacy instantiations.
    parameter integer ENABLE_HOST_HXA_PREVIEW = 0,
    // Read-only RAW AWB observation; absent in all existing builds.
    parameter integer ENABLE_AWB_DIAG = 0
) (
    input wire I_clk125, input wire I_clk125_90, input wire I_clk_pix,
    input wire I_rst_n, input wire I_rst_pix_n,
    input wire [3:0] I_rgmii_rxd, input wire I_rgmii_rx_ctl, input wire I_rgmii_rxc,
    output wire [3:0] O_rgmii_txd, output wire O_rgmii_tx_ctl,
    output wire O_rgmii_txc, output wire O_phy_rst,
    input wire [23:0] I_pix, input wire I_pix_de, input wire I_pix_sof, input wire I_pix_eof,
    input wire [31:0] I_frame_period, input wire [19:0] I_target_count,
    input wire [19:0] I_motion_count, input wire [31:0] I_latency_us,
    input wire [7:0] I_status_flags,
    input wire [2:0] I_app_mode,input wire I_app_armed,input wire I_peer_online,
    input wire [7:0] I_last_action,input wire [7:0] I_action_result,
    input wire [1:0] I_action_retries,input wire [15:0] I_uart_errors,
    input wire [63:0] I_board_status_pix,
    input wire [31:0] I_hxa_sent_frames,I_hxa_failed_frames,I_snapshot_frame_id,
    input wire I_hxa_online,input wire [7:0] I_hxa_job_state,
    output wire [4:0] O_cfg_mode, output wire [7:0] O_cfg_threshold,
    output wire [7:0] O_cfg_brightness, output wire [1:0] O_cfg_target_color,
    output wire O_cfg_detect_en, output wire O_cfg_heq_en, output wire O_cfg_cnn_mode,
    output wire O_cfg_auto_quality,
    output wire O_cfg_awb_enable, output wire O_cfg_ae_enable,
    output wire O_cfg_ag_enable, output wire O_cfg_quality_heq_enable,
    output wire [2:0] O_cfg_app_mode, output wire O_cfg_app_mode_valid,
    output reg O_cfg_valid,
    output wire [31:0] O_cnn_frame_id, output wire [31:0] O_cnn_inference_us,
    output wire [3:0] O_cnn_target_num, output wire [383:0] O_cnn_bbox,
    output wire [127:0] O_cnn_class_id, output wire [63:0] O_cnn_confidence,
    output wire [63:0] O_cnn_flags, output wire [511:0] O_cnn_label,
    output reg O_cnn_valid, output reg O_cnn_heartbeat,
    output wire [31:0] O_action_sequence, output wire [31:0] O_action_frame_id,
    output wire [1:0] O_action_app_mode, output wire [7:0] O_action_id,
    output wire [7:0] O_action_confidence, output wire [7:0] O_action_evidence,
    output wire [15:0] O_action_ttl_ms, output wire [15:0] O_action_cooldown_ms,
    output wire [15:0] O_action_flags, output wire [63:0] O_action_label,
    output reg O_action_valid,
    output wire O_session_ready,
    // Share the established MAC/ARP/IP/UDP and physical IO with HXA1.
    // Mode is synchronised and held in the 125 MHz domain by the top level.
    input wire I_aux_mode,
    input wire I_aux_tx_req,I_aux_tx_valid,I_aux_stack_reset,
    input wire [7:0] I_aux_tx_data,input wire [15:0] I_aux_tx_len,
    input wire [31:0] I_aux_peer_ip,input wire [15:0] I_aux_peer_port,
    output wire O_aux_tx_busy,O_aux_rx_valid,O_aux_rx_error,O_aux_ready,
    output wire [7:0] O_aux_rx_data,output wire [15:0] O_aux_rx_len,
    // Bundled-data request/ack mailbox from the camera clock domain.
    // The source holds the 224-bit payload until the next request.
    input wire [223:0] I_awb_diag_data,input wire I_awb_diag_ack,
    input wire I_awb_diag_source_rst_n,
    output wire O_awb_diag_req,output wire O_awb_diag_rst_n
);
    localparam [7:0] V2_VERSION=8'd2, V2_VIDEO=8'd1, V2_STATUS=8'd2,
                     V2_CNN_RESULT=8'd3, V2_CONFIG=8'd4, V2_ACTION=8'd5,
                     V2_APP_STATUS=8'd6;
    localparam integer FRAME_BYTES_INT=VIDEO_WIDTH*VIDEO_HEIGHT*VIDEO_PIXEL_BYTES;
    localparam integer VIDEO_PKT_COUNT_INT=(FRAME_BYTES_INT+VIDEO_PAYLOAD_BYTES-1)/VIDEO_PAYLOAD_BYTES;
    localparam [15:0] VIDEO_PKT_COUNT=VIDEO_PKT_COUNT_INT, FULL_PAYLOAD=VIDEO_PAYLOAD_BYTES,
                      LAST_PAYLOAD=(FRAME_BYTES_INT%VIDEO_PAYLOAD_BYTES==0)?VIDEO_PAYLOAD_BYTES:(FRAME_BYTES_INT%VIDEO_PAYLOAD_BYTES), VIDEO_HEADER=16'd32;
    localparam [31:0] FRAME_BYTES=FRAME_BYTES_INT[31:0];
    wire phy_rst;
    wire reset = ~phy_rst;
    reg [1:0] stack_reset_count;
    reg aux_mode_d;
    reg [1:0] mode_flush;
    always @(posedge I_clk125 or posedge reset) begin
        if(reset) begin aux_mode_d<=0;mode_flush<=3;end
        else begin
            aux_mode_d<=I_aux_mode;
            if(aux_mode_d!=I_aux_mode) mode_flush<=3;
            else if(mode_flush!=0) mode_flush<=mode_flush-1'b1;
        end
    end
    wire shared_stack_reset;
    wire stack_reset = reset | (mode_flush!=0) | (aux_mode_d!=I_aux_mode) |
        (ENABLE_HOST_HXA_PREVIEW ? shared_stack_reset :
         ((stack_reset_count != 0) | (I_aux_mode && I_aux_stack_reset)));
    wire legacy_reset = reset | I_aux_mode;
    reg [31:0] video_frame_id;
    reg have_video_frame;
    uiphyrst #(.CLK_FREQ(32'd125_000_000)) u_phyrst(
        .I_CLK(I_clk125),.I_rstn(I_rst_n),.I_phyrst(I_rst_n),.O_phyrst(phy_rst));
    assign O_phy_rst=phy_rst;

    wire [7:0] gmii_tdata,gmii_rdata,R_udp_data;
    wire gmii_tvalid,gmii_rvalid,gmii_rclk,R_udp_valid,W_udp_busy,stack_udp_busy;
    wire [15:0] R_udp_len,R_udp_src_port;
    wire [7:0] raw_udp_data;
    wire raw_udp_valid;
    wire [15:0] raw_udp_len;
    wire [31:0] raw_udp_src_ip;
    wire W_udp_req,W_udp_valid;
    wire [7:0] W_udp_data;
    reg [15:0] W_udp_len;
    wire ip_rerror,mac_rerror;
    wire stack_udp_req,stack_udp_valid;
    wire [7:0] stack_udp_data;
    wire [15:0] stack_udp_len,stack_peer_port;
    wire [31:0] stack_peer_ip;
    wire legacy_rx_valid,legacy_rx_error,legacy_tx_selected;
    uiudp_stack #(.CRC_GEN_EN(1'b1),.INTER_FRAME_GAP(4'd12)) u_udp_stack(
        .I_uclk(I_clk125),.I_reset(stack_reset),.I_mac_local_addr(48'h000a35010203),
        .I_udp_local_port(16'd6002),.I_ip_local_addr(32'hc0a8a002),
        .I_udp_dest_port(stack_peer_port),.I_ip_dest_addr(stack_peer_ip),
        .O_W_udp_busy(stack_udp_busy),.I_W_udp_req(stack_udp_req),.I_W_udp_valid(stack_udp_valid),
        .I_W_udp_data(stack_udp_data),.I_W_udp_len(stack_udp_len),.O_R_udp_valid(raw_udp_valid),
        .O_R_udp_data(raw_udp_data),.O_R_udp_len(raw_udp_len),.O_R_udp_src_port(R_udp_src_port),
        .O_R_udp_src_ip(raw_udp_src_ip),
        .I_gmii_rclk(gmii_rclk),.I_gmii_rvalid(gmii_rvalid),.I_gmii_rdata(gmii_rdata),
        .I_gmii_tclk(I_clk125),.O_gmii_tvalid(gmii_tvalid),.O_gmii_tdata(gmii_tdata),
        .O_ip_rerror(ip_rerror),.O_mac_rerror(mac_rerror));
    assign O_aux_rx_data=raw_udp_data;
    assign O_aux_rx_len=raw_udp_len;
    assign O_aux_ready=phy_rst && !stack_reset;
    generate
      if (ENABLE_HOST_HXA_PREVIEW) begin : g_host_hxa
        localparam [1:0] NONE=0,LEGACY=1,AUX=2;
        localparam integer WATCH_BITS=(UDP_REQUEST_TIMEOUT_CYCLES>1)?$clog2(UDP_REQUEST_TIMEOUT_CYCLES):1;
        reg [1:0] owner;
        reg last_aux,seen_busy;
        reg [31:0] peer_ip;
        reg [15:0] peer_port,packet_len;
        reg [WATCH_BITS-1:0] owner_wait;
        reg [1:0] abort_count;
        wire want_legacy=W_udp_req && !I_aux_mode;
        wire choose_aux=I_aux_tx_req && (!want_legacy || !last_aux);
        wire owner_abort=(owner==LEGACY && stack_reset_count!=0) ||
                         (owner==AUX && I_aux_stack_reset);
        // Alternate packet grants when both clients wait. Only the owner
        // observes acceptance; the other client keeps its request pending.
        assign shared_stack_reset=(abort_count!=0) || owner_abort;
        assign legacy_tx_selected=(owner==LEGACY);
        assign W_udp_busy=(owner==LEGACY) && stack_udp_busy && !stack_reset;
        assign O_aux_tx_busy=(owner==AUX) && stack_udp_busy && !stack_reset;
        assign stack_udp_req=!stack_reset && ((owner==AUX)?I_aux_tx_req:
                                             (owner==LEGACY)?W_udp_req:1'b0);
        assign stack_udp_valid=!stack_reset && ((owner==AUX)?I_aux_tx_valid:
                                               (owner==LEGACY)?W_udp_valid:1'b0);
        assign stack_udp_data=(owner==AUX)?I_aux_tx_data:W_udp_data;
        assign stack_udp_len=packet_len;
        assign stack_peer_ip=peer_ip;
        assign stack_peer_port=peer_port;
        always @(posedge I_clk125 or posedge reset) begin
          if(reset) begin
            owner<=NONE;last_aux<=0;seen_busy<=0;peer_ip<=0;peer_port<=0;
            packet_len<=0;owner_wait<=0;abort_count<=0;
          end else begin
            if(abort_count!=0)abort_count<=abort_count-1'b1;
            if(owner_abort)abort_count<=3;
            if(stack_reset)begin owner<=NONE;seen_busy<=0;owner_wait<=0;end
            else if(owner==NONE) begin
              seen_busy<=0;owner_wait<=0;
              if(!stack_udp_busy && (I_aux_tx_req || want_legacy)) begin
                owner<=choose_aux?AUX:LEGACY;last_aux<=choose_aux;
                peer_ip<=choose_aux?I_aux_peer_ip:32'hc0a8a001;
                peer_port<=choose_aux?I_aux_peer_port:16'd6001;
                packet_len<=choose_aux?I_aux_tx_len:W_udp_len;
              end
            end else if(seen_busy && !stack_udp_busy)begin
              owner<=NONE;seen_busy<=0;owner_wait<=0;
            end else if(owner_wait==UDP_REQUEST_TIMEOUT_CYCLES-1)begin
              // Also cancel a stuck ARP request or a producer that stops in
              // the middle of a packet. No fragment is resumed for a new peer.
              abort_count<=3;owner<=NONE;seen_busy<=0;owner_wait<=0;
            end else begin
              owner_wait<=owner_wait+1'b1;
              if(stack_udp_busy)seen_busy<=1;
            end
          end
        end
        reg rx_active,rx_drain;
        reg [1:0] rx_owner;
        wire [1:0] incoming_owner=(R_udp_src_port==I_aux_peer_port &&
             raw_udp_src_ip==I_aux_peer_ip)?AUX:
             (!I_aux_mode && raw_udp_src_ip==32'hc0a8a001 && R_udp_src_port!=16'd6003)?LEGACY:NONE;
        wire [1:0] packet_owner=rx_active?rx_owner:incoming_owner;
        // Metadata precedes UDP payload. Use it on byte zero, then hold the
        // route through the packet and its trailing error indication.
        assign O_aux_rx_valid=raw_udp_valid && !stack_reset && !rx_drain && packet_owner==AUX;
        assign legacy_rx_valid=raw_udp_valid && !stack_reset && !rx_drain && packet_owner==LEGACY;
        assign O_aux_rx_error=!stack_reset && !rx_drain &&
             (raw_udp_valid?packet_owner:rx_owner)==AUX && (ip_rerror|mac_rerror);
        assign legacy_rx_error=!stack_reset && !rx_drain &&
             (raw_udp_valid?packet_owner:rx_owner)==LEGACY && (ip_rerror|mac_rerror);
        always @(posedge I_clk125 or posedge reset) begin
          if(reset)begin rx_active<=0;rx_owner<=NONE;rx_drain<=1;end
          else if(stack_reset)begin rx_active<=raw_udp_valid;rx_owner<=NONE;rx_drain<=1;end
          else if(!raw_udp_valid)begin rx_active<=0;rx_drain<=0;end
          else begin
            rx_active<=1;
            if(!rx_active && !rx_drain)rx_owner<=incoming_owner;
          end
        end
      end else begin : g_legacy_network
        assign shared_stack_reset=1'b0;
        assign legacy_tx_selected=1'b1;
        assign stack_peer_ip=I_aux_mode?I_aux_peer_ip:32'hc0a8a001;
        assign stack_peer_port=I_aux_mode?I_aux_peer_port:16'd6001;
        assign stack_udp_req=I_aux_mode?I_aux_tx_req:W_udp_req;
        assign stack_udp_valid=I_aux_mode?I_aux_tx_valid:W_udp_valid;
        assign stack_udp_data=I_aux_mode?I_aux_tx_data:W_udp_data;
        assign stack_udp_len=I_aux_mode?I_aux_tx_len:W_udp_len;
        assign W_udp_busy=stack_udp_busy;
        assign O_aux_tx_busy=stack_udp_busy;
        assign O_aux_rx_valid=raw_udp_valid && I_aux_mode;
        assign O_aux_rx_error=ip_rerror|mac_rerror;
        assign legacy_rx_valid=raw_udp_valid;
        assign legacy_rx_error=ip_rerror|mac_rerror;
      end
    endgenerate
    rgmii_interface #(
        .RGMII_ID          (1'b0),
        .TXC_DELAY_ENABLE  (1'b0),
        .TXC_DELAY_VALUE   (5'd0),
        .RX_DELAY_ENABLE   (1'b1),
        .RX_DELAY_VALUE    (5'd31),
        .RXC_USE_IOCLK     (1'b0)
    ) u_rgmii(
        .speed_10_100(1'b0),.gmii_tx_clk_d(I_clk125_90),.gmii_tx_reset_d(reset),
        .gmii_tx_reset(reset),.gmii_tx_clk(I_clk125),.gmii_txd(gmii_tdata),
        .gmii_tx_en(gmii_tvalid),.gmii_tx_er(1'b0),.gmii_rx_reset(reset),
        .gmii_rx_clk(gmii_rclk),.gmii_rxd(gmii_rdata),.gmii_rx_dv(gmii_rvalid),
        .gmii_rx_er(),.rgmii_txd(O_rgmii_txd),.rgmii_tx_ctl(O_rgmii_tx_ctl),
        .rgmii_txc(O_rgmii_txc),.rgmii_rxd(I_rgmii_rxd),
        .rgmii_rx_ctl(I_rgmii_rx_ctl),.rgmii_rxc(I_rgmii_rxc),
        .gmii_crs(),.gmii_col(),.link_status(),.clock_speed(),.duplex_status());

    wire session_safe,session_changed,session_epoch;
    wire session_idle;
    wire [31:0] session_timestamp;
    wire [13:0] session_tag;
    wire [255:0] session_reply;
    wire session_reply_valid;
    reg session_reply_take;
    reg [255:0] session_reply_tx;
    reg [13:0] frame_session_tag;
    reg [1:0] session_epoch_sync,session_safe_sync;
    reg session_epoch_seen;
    reg [1:0] session_ack_sync;
    assign O_session_ready=session_safe_sync[1] &&
                           (session_epoch_sync[1]==session_epoch_seen);
    always @(posedge I_clk_pix or negedge I_rst_pix_n) begin
      if(!I_rst_pix_n) begin
        session_epoch_sync<=0;session_safe_sync<=0;session_epoch_seen<=0;
      end else begin
        session_epoch_sync<={session_epoch_sync[0],session_epoch};
        session_safe_sync<={session_safe_sync[0],session_safe};
        session_epoch_seen<=session_epoch_sync[1];
      end
    end
    always @(posedge I_clk125 or posedge reset) begin
      if(reset) session_ack_sync<=0;
      else session_ack_sync<={session_ack_sync[0],session_epoch_seen};
    end
    generate
      if (ENABLE_SESSION_GUARD) begin : g_session_guard
        udp_session_guard #(.LEASE_CYCLES(SESSION_LEASE_CYCLES)) u_session(
          .I_clk(I_clk125),.I_reset(reset),.I_data(raw_udp_data),
          .I_valid(legacy_rx_valid),.I_len(raw_udp_len),.I_error(legacy_rx_error),
          .I_idle(session_idle),
          .I_epoch_ack(session_ack_sync[1]),.I_frame_id(video_frame_id),
          .I_timestamp(session_timestamp),.O_data(R_udp_data),.O_valid(R_udp_valid),
          .O_len(R_udp_len),.O_safe(session_safe),.O_changed(session_changed),
          .O_epoch(session_epoch),.O_tag(session_tag),
          .O_reply(session_reply),.O_reply_valid(session_reply_valid),
          .I_reply_take(session_reply_take));
      end else begin : g_session_bypass
        // CONFIG is already protected by packet length/magic checks below.
        // Bypassing the optional session RAM keeps the video/control path
        // functional while removing a large placement hotspot.
        assign R_udp_data       = raw_udp_data;
        assign R_udp_valid      = legacy_rx_valid;
        assign R_udp_len        = raw_udp_len;
        assign session_safe     = 1'b1;
        assign session_changed  = 1'b0;
        assign session_epoch    = 1'b0;
        assign session_tag      = 14'd0;
        assign session_reply    = 256'd0;
        assign session_reply_valid = 1'b0;
      end
    endgenerate

    // RX payload parser. Results are kept in stable shadow registers until
    // the pixel-domain acknowledgement returns.
    reg rudp_valid_d;
    wire rx_sop=R_udp_valid&~rudp_valid_d;
    wire rx_eop=~R_udp_valid&rudp_valid_d;
    reg [8:0] rx_pos;
    reg [15:0] rx_len_hold,rx_byte_count,cnn_record_size_tmp;
    reg rx_magic_ok,rx_error_latch;
    reg [7:0] rx_version,rx_type;
    reg [4:0] cfg_mode_tmp;
    reg [7:0] cfg_threshold_tmp,cfg_brightness_tmp;
    reg [1:0] cfg_color_tmp;
    reg cfg_detect_tmp,cfg_heq_tmp,cfg_cnn_tmp,cfg_auto_tmp;
    reg [2:0] cfg_app_mode_tmp;
    reg cfg_app_valid_tmp;
    reg [15:0] rx_flags_tmp;
    reg [31:0] cfg_sequence_tmp,cnn_sequence_tmp,cnn_frame_tmp,cnn_inference_tmp;
    reg [15:0] cnn_count_tmp;
    reg [127:0] cnn_xmin_tmp,cnn_ymin_tmp,cnn_xmax_tmp,cnn_ymax_tmp,cnn_class_tmp;
    reg [63:0] cnn_conf_tmp,cnn_flags_tmp;
    reg [511:0] cnn_label_tmp;
    reg [3:0] cnn_record_index;
    reg [4:0] cnn_record_byte;
    reg [31:0] action_sequence_tmp,action_frame_tmp;
    reg [1:0] action_app_mode_tmp;
    reg [7:0] action_id_tmp,action_conf_tmp,action_evidence_tmp;
    reg [15:0] action_ttl_tmp,action_cooldown_tmp;
    reg [63:0] action_label_tmp;
    reg rx_commit_pending;
    reg [5:0] rx_commit_delay;
    reg [1:0] rx_commit_kind;
    reg [31:0] last_cfg_sequence,last_cnn_sequence,last_cnn_frame,last_action_sequence;
    reg have_cfg_sequence,have_cnn_sequence,have_cnn_frame,have_action_sequence;
    reg [25:0] cnn_session_timer;
    reg validate_ok;
    reg validation_active;
    reg [3:0] validate_index;
    integer validate_i;

    function [15:0] cnn_expected_len;
      input [3:0] count;
      begin case(count)
        0:cnn_expected_len=16'd24;1:cnn_expected_len=16'd44;
        2:cnn_expected_len=16'd64;3:cnn_expected_len=16'd84;
        4:cnn_expected_len=16'd104;5:cnn_expected_len=16'd124;
        6:cnn_expected_len=16'd144;7:cnn_expected_len=16'd164;
        8:cnn_expected_len=16'd184;default:cnn_expected_len=16'hffff;
      endcase end
    endfunction
    wire [15:0] validate_xmin=cnn_xmin_tmp[validate_index*16+:16];
    wire [15:0] validate_ymin=cnn_ymin_tmp[validate_index*16+:16];
    wire [15:0] validate_xmax=cnn_xmax_tmp[validate_index*16+:16];
    wire [15:0] validate_ymax=cnn_ymax_tmp[validate_index*16+:16];
    wire validate_coord_ok=(validate_xmin<validate_xmax)&&(validate_ymin<validate_ymax)&&
                           (validate_xmax<=VIDEO_WIDTH)&&(validate_ymax<=VIDEO_HEIGHT);

    reg [4:0] cfg_mode_shadow;
    reg [7:0] cfg_threshold_shadow,cfg_brightness_shadow;
    reg [1:0] cfg_color_shadow;
    reg cfg_detect_shadow,cfg_heq_shadow,cfg_cnn_shadow,cfg_auto_shadow;
    reg cfg_awb_shadow,cfg_ae_shadow,cfg_ag_shadow,cfg_quality_heq_shadow,cfg_req_toggle;
    reg [2:0] cfg_app_mode_shadow;
    reg cfg_app_valid_shadow;
    reg [1:0] cfg_ack_sync;
    reg [31:0] cnn_frame_shadow,cnn_inference_shadow;
    reg [3:0] cnn_count_shadow;
    reg [383:0] cnn_bbox_shadow;
    reg [127:0] cnn_class_shadow;
    reg [63:0] cnn_conf_shadow,cnn_flags_shadow;
    reg [511:0] cnn_label_shadow;
    reg cnn_heartbeat_shadow,cnn_req_toggle;
    reg [31:0] action_sequence_shadow,action_frame_shadow;
    reg [1:0] action_app_mode_shadow;
    reg [7:0] action_id_shadow,action_conf_shadow,action_evidence_shadow;
    reg [15:0] action_ttl_shadow,action_cooldown_shadow,action_flags_shadow;
    reg [63:0] action_label_shadow;
    reg action_req_toggle;
    reg [1:0] cnn_ack_sync,action_ack_sync;
    reg cfg_ack_toggle_pix,cnn_ack_toggle_pix,action_ack_toggle_pix;
    assign session_idle=!rx_commit_pending&&!validation_active&&
        cfg_ack_sync[1]==cfg_req_toggle&&cnn_ack_sync[1]==cnn_req_toggle&&
        action_ack_sync[1]==action_req_toggle;

    assign O_cfg_mode=cfg_mode_shadow;
    assign O_cfg_threshold=cfg_threshold_shadow;
    assign O_cfg_brightness=cfg_brightness_shadow;
    assign O_cfg_target_color=cfg_color_shadow;
    assign O_cfg_detect_en=cfg_detect_shadow;
    assign O_cfg_heq_en=cfg_heq_shadow;
    assign O_cfg_cnn_mode=cfg_cnn_shadow;
    assign O_cfg_auto_quality=cfg_auto_shadow;
    assign O_cfg_awb_enable=cfg_awb_shadow;
    assign O_cfg_ae_enable=cfg_ae_shadow;
    assign O_cfg_ag_enable=cfg_ag_shadow;
    assign O_cfg_quality_heq_enable=cfg_quality_heq_shadow;
    assign O_cfg_app_mode=cfg_app_mode_shadow;
    assign O_cfg_app_mode_valid=cfg_app_valid_shadow;
    generate if (ENABLE_EXTENDED_RESULTS) begin : g_extended_outputs
      assign O_cnn_frame_id=cnn_frame_shadow;
      assign O_cnn_inference_us=cnn_inference_shadow;
      assign O_cnn_target_num=cnn_count_shadow;
      assign O_cnn_bbox=cnn_bbox_shadow;
      assign O_cnn_class_id=cnn_class_shadow;
      assign O_cnn_confidence=cnn_conf_shadow;
      assign O_cnn_flags=cnn_flags_shadow;
      assign O_cnn_label=cnn_label_shadow;
      assign O_action_sequence=action_sequence_shadow;
      assign O_action_frame_id=action_frame_shadow;
      assign O_action_app_mode=action_app_mode_shadow;
      assign O_action_id=action_id_shadow;
      assign O_action_confidence=action_conf_shadow;
      assign O_action_evidence=action_evidence_shadow;
      assign O_action_ttl_ms=action_ttl_shadow;
      assign O_action_cooldown_ms=action_cooldown_shadow;
      assign O_action_flags=action_flags_shadow;
      assign O_action_label=action_label_shadow;
    end else begin : g_basic_outputs
      assign O_cnn_frame_id=0; assign O_cnn_inference_us=0; assign O_cnn_target_num=0;
      assign O_cnn_bbox=0; assign O_cnn_class_id=0; assign O_cnn_confidence=0;
      assign O_cnn_flags=0; assign O_cnn_label=0;
      assign O_action_sequence=0; assign O_action_frame_id=0; assign O_action_app_mode=0;
      assign O_action_id=0; assign O_action_confidence=0; assign O_action_evidence=0;
      assign O_action_ttl_ms=0; assign O_action_cooldown_ms=0; assign O_action_flags=0;
      assign O_action_label=0;
    end endgenerate

    always @(posedge I_clk125 or posedge legacy_reset) begin
      if(legacy_reset) begin
        rudp_valid_d<=0; rx_pos<=0; rx_len_hold<=0;rx_byte_count<=0;cnn_record_size_tmp<=0;
        rx_magic_ok<=0; rx_version<=0; rx_type<=0;
        rx_error_latch<=0; cfg_mode_tmp<=0; cfg_threshold_tmp<=128; cfg_brightness_tmp<=128;
        cfg_color_tmp<=0; cfg_detect_tmp<=0; cfg_heq_tmp<=0; cfg_cnn_tmp<=0; cfg_auto_tmp<=0;
        cfg_app_mode_tmp<=0;cfg_app_valid_tmp<=0;rx_flags_tmp<=0; cfg_sequence_tmp<=0;
        cnn_sequence_tmp<=0; cnn_frame_tmp<=0; cnn_inference_tmp<=0; cnn_count_tmp<=0;
        cnn_xmin_tmp<=0; cnn_ymin_tmp<=0; cnn_xmax_tmp<=0; cnn_ymax_tmp<=0;
        cnn_class_tmp<=0; cnn_conf_tmp<=0; cnn_flags_tmp<=0; cnn_label_tmp<=0;
        action_sequence_tmp<=0;action_frame_tmp<=0;action_app_mode_tmp<=0;action_id_tmp<=0;
        action_conf_tmp<=0;action_evidence_tmp<=0;action_ttl_tmp<=0;action_cooldown_tmp<=0;action_label_tmp<=0;
        cnn_record_index<=0; cnn_record_byte<=0; rx_commit_pending<=0; rx_commit_delay<=0;
        rx_commit_kind<=0; last_cfg_sequence<=0; last_cnn_sequence<=0;last_cnn_frame<=0;last_action_sequence<=0;
        have_cfg_sequence<=0;have_cnn_sequence<=0;have_cnn_frame<=0;have_action_sequence<=0;cnn_session_timer<=0;
        validate_ok<=0;validation_active<=0;validate_index<=0;
        cfg_mode_shadow<=0; cfg_threshold_shadow<=128; cfg_brightness_shadow<=128;
        cfg_color_shadow<=0; cfg_detect_shadow<=0; cfg_heq_shadow<=0;cfg_cnn_shadow<=0;cfg_auto_shadow<=0;
        cfg_awb_shadow<=0; cfg_ae_shadow<=0; cfg_ag_shadow<=0; cfg_quality_heq_shadow<=0; cfg_req_toggle<=0;
        cfg_app_mode_shadow<=0;cfg_app_valid_shadow<=0;
        cfg_ack_sync<=0; cnn_frame_shadow<=0; cnn_inference_shadow<=0; cnn_count_shadow<=0;
        cnn_bbox_shadow<=0; cnn_class_shadow<=0; cnn_conf_shadow<=0; cnn_flags_shadow<=0;
        cnn_label_shadow<=0;cnn_heartbeat_shadow<=0;cnn_req_toggle<=0;cnn_ack_sync<=0;
        action_sequence_shadow<=0;action_frame_shadow<=0;action_app_mode_shadow<=0;action_id_shadow<=0;
        action_conf_shadow<=0;action_evidence_shadow<=0;action_ttl_shadow<=0;action_cooldown_shadow<=0;
        action_flags_shadow<=0;action_label_shadow<=0;action_req_toggle<=0;action_ack_sync<=0;
      end else begin
        rudp_valid_d<=R_udp_valid;
        cfg_ack_sync<={cfg_ack_sync[0],cfg_ack_toggle_pix};
        cnn_ack_sync<={cnn_ack_sync[0],cnn_ack_toggle_pix};
        action_ack_sync<={action_ack_sync[0],action_ack_toggle_pix};
        if(ENABLE_EXTENDED_RESULTS && have_cnn_sequence) begin
          if(cnn_session_timer>=CNN_SESSION_TIMEOUT_CYCLES-1) begin
            // Legacy peers recover by timeout. Session peers must retain
            // replay baselines until the negotiated session actually changes.
            if(session_tag==0) begin
              cnn_session_timer<=0;have_cnn_sequence<=0;have_cnn_frame<=0;
            end
          end else cnn_session_timer<=cnn_session_timer+1'b1;
        end else cnn_session_timer<=0;
        // The guard has already bound MAC/IP errors to this replayed packet.
        if(rx_sop) begin
          rx_pos<=0;rx_byte_count<=1;rx_len_hold<=R_udp_len;rx_magic_ok<=(R_udp_data==8'h48);
          rx_version<=0;rx_type<=0;rx_flags_tmp<=0;rx_error_latch<=0;
          cfg_app_mode_tmp<=0;cfg_app_valid_tmp<=0;
          rx_commit_pending<=0;rx_commit_delay<=0;cnn_record_index<=0;cnn_record_byte<=0;
          cnn_record_size_tmp<=0;
          cnn_xmin_tmp<=0; cnn_ymin_tmp<=0; cnn_xmax_tmp<=0; cnn_ymax_tmp<=0;
          cnn_class_tmp<=0; cnn_conf_tmp<=0; cnn_flags_tmp<=0; cnn_label_tmp<=0;
          action_sequence_tmp<=0;action_frame_tmp<=0;action_app_mode_tmp<=0;action_id_tmp<=0;
          action_conf_tmp<=0;action_evidence_tmp<=0;action_ttl_tmp<=0;action_cooldown_tmp<=0;action_label_tmp<=0;
          if(R_udp_len==16'd4) cfg_mode_tmp<=R_udp_data[4:0];
        end else if(R_udp_valid) begin
          rx_pos<=rx_pos+1'b1;rx_byte_count<=rx_byte_count+1'b1;
          if(R_udp_len==16'd4) begin
            case(rx_pos+1'b1)
              1:cfg_threshold_tmp<=R_udp_data; 2:cfg_brightness_tmp<=R_udp_data;
              3:begin cfg_color_tmp<=R_udp_data[1:0];cfg_detect_tmp<=R_udp_data[2];
                cfg_heq_tmp<=R_udp_data[3];cfg_cnn_tmp<=R_udp_data[4];cfg_auto_tmp<=R_udp_data[5];end
              default:;
            endcase
          end else begin
            case(rx_pos+1'b1)
              1:rx_magic_ok<=rx_magic_ok&&(R_udp_data==8'h58);
              2:rx_magic_ok<=rx_magic_ok&&(R_udp_data==8'h56);
              3:rx_magic_ok<=rx_magic_ok&&(R_udp_data==8'h32);
              4:rx_version<=R_udp_data;5:rx_type<=R_udp_data;
              6:rx_flags_tmp[7:0]<=R_udp_data;7:rx_flags_tmp[15:8]<=R_udp_data;
              8:begin cnn_sequence_tmp[7:0]<=R_udp_data;action_sequence_tmp[7:0]<=R_udp_data;end
              9:begin cnn_sequence_tmp[15:8]<=R_udp_data;action_sequence_tmp[15:8]<=R_udp_data;end
              10:begin cnn_sequence_tmp[23:16]<=R_udp_data;action_sequence_tmp[23:16]<=R_udp_data;end
              11:begin cnn_sequence_tmp[31:24]<=R_udp_data;action_sequence_tmp[31:24]<=R_udp_data;end
              12:begin cnn_frame_tmp[7:0]<=R_udp_data;action_frame_tmp[7:0]<=R_udp_data;cfg_sequence_tmp[7:0]<=R_udp_data;end
              13:begin cnn_frame_tmp[15:8]<=R_udp_data;action_frame_tmp[15:8]<=R_udp_data;cfg_sequence_tmp[15:8]<=R_udp_data;end
              14:begin cnn_frame_tmp[23:16]<=R_udp_data;action_frame_tmp[23:16]<=R_udp_data;cfg_sequence_tmp[23:16]<=R_udp_data;end
              15:begin cnn_frame_tmp[31:24]<=R_udp_data;action_frame_tmp[31:24]<=R_udp_data;cfg_sequence_tmp[31:24]<=R_udp_data;end
              16:begin cnn_inference_tmp[7:0]<=R_udp_data;action_app_mode_tmp<=R_udp_data[1:0];end
              17:begin cnn_inference_tmp[15:8]<=R_udp_data;action_id_tmp<=R_udp_data;end
              18:begin cnn_inference_tmp[23:16]<=R_udp_data;action_conf_tmp<=R_udp_data;end
              19:begin cnn_inference_tmp[31:24]<=R_udp_data;action_evidence_tmp<=R_udp_data;end
              20:begin cnn_count_tmp[7:0]<=R_udp_data;action_ttl_tmp[7:0]<=R_udp_data;end
              21:begin cnn_count_tmp[15:8]<=R_udp_data;action_ttl_tmp[15:8]<=R_udp_data;end
              22:begin cnn_record_size_tmp[7:0]<=R_udp_data;action_cooldown_tmp[7:0]<=R_udp_data;end
              23:begin cnn_record_size_tmp[15:8]<=R_udp_data;action_cooldown_tmp[15:8]<=R_udp_data;end
              24:action_label_tmp[7:0]<=R_udp_data;25:action_label_tmp[15:8]<=R_udp_data;
              26:action_label_tmp[23:16]<=R_udp_data;27:action_label_tmp[31:24]<=R_udp_data;
              28:action_label_tmp[39:32]<=R_udp_data;29:action_label_tmp[47:40]<=R_udp_data;
              30:action_label_tmp[55:48]<=R_udp_data;31:action_label_tmp[63:56]<=R_udp_data;
              default:;
            endcase
            if((rx_pos+1'b1)>=24&&cnn_record_index<8) begin
              case(cnn_record_byte)
                0:cnn_xmin_tmp[cnn_record_index*16+:8]<=R_udp_data;
                1:cnn_xmin_tmp[cnn_record_index*16+8+:8]<=R_udp_data;
                2:cnn_ymin_tmp[cnn_record_index*16+:8]<=R_udp_data;
                3:cnn_ymin_tmp[cnn_record_index*16+8+:8]<=R_udp_data;
                4:cnn_xmax_tmp[cnn_record_index*16+:8]<=R_udp_data;
                5:cnn_xmax_tmp[cnn_record_index*16+8+:8]<=R_udp_data;
                6:cnn_ymax_tmp[cnn_record_index*16+:8]<=R_udp_data;
                7:cnn_ymax_tmp[cnn_record_index*16+8+:8]<=R_udp_data;
                8:cnn_class_tmp[cnn_record_index*16+:8]<=R_udp_data;
                9:cnn_class_tmp[cnn_record_index*16+8+:8]<=R_udp_data;
                10:cnn_conf_tmp[cnn_record_index*8+:8]<=R_udp_data;
                11:cnn_flags_tmp[cnn_record_index*8+:8]<=R_udp_data;
                12:cnn_label_tmp[cnn_record_index*64+:8]<=R_udp_data;
                13:cnn_label_tmp[cnn_record_index*64+8+:8]<=R_udp_data;
                14:cnn_label_tmp[cnn_record_index*64+16+:8]<=R_udp_data;
                15:cnn_label_tmp[cnn_record_index*64+24+:8]<=R_udp_data;
                16:cnn_label_tmp[cnn_record_index*64+32+:8]<=R_udp_data;
                17:cnn_label_tmp[cnn_record_index*64+40+:8]<=R_udp_data;
                18:cnn_label_tmp[cnn_record_index*64+48+:8]<=R_udp_data;
                19:cnn_label_tmp[cnn_record_index*64+56+:8]<=R_udp_data;
                default:;
              endcase
              if(cnn_record_byte==19) begin cnn_record_byte<=0; if(cnn_record_index!=15) cnn_record_index<=cnn_record_index+1'b1; end
              else cnn_record_byte<=cnn_record_byte+1'b1;
            end
            if(R_udp_len==16'd16) case(rx_pos+1'b1)
              8:cfg_mode_tmp<=R_udp_data[4:0];9:cfg_threshold_tmp<=R_udp_data;
              10:cfg_brightness_tmp<=R_udp_data;
              11:begin cfg_color_tmp<=rx_flags_tmp[1:0];cfg_detect_tmp<=rx_flags_tmp[2];
                cfg_heq_tmp<=rx_flags_tmp[3];cfg_cnn_tmp<=rx_flags_tmp[4];cfg_auto_tmp<=rx_flags_tmp[5];
                cfg_app_mode_tmp<=R_udp_data[2:0];cfg_app_valid_tmp<=rx_flags_tmp[15]&&(R_udp_data[2:0]<=3'd1);end
              default:;
            endcase
          end
        end
        if(rx_eop) begin
          rx_commit_delay<=0;
          if(rx_byte_count!=rx_len_hold) rx_error_latch<=1;
          else if(rx_len_hold==4) begin rx_commit_pending<=1;rx_commit_kind<=1;end
          else if(rx_magic_ok&&rx_version==V2_VERSION&&rx_type==V2_CONFIG&&rx_len_hold==16) begin rx_commit_pending<=1;rx_commit_kind<=1;end
          // CNN and remote action packets are disabled in the released
          // two-mode design.  Drop them at the packet boundary.
          else if(ENABLE_EXTENDED_RESULTS && rx_magic_ok&&rx_version==V2_VERSION&&rx_type==V2_CNN_RESULT) begin
            rx_commit_pending<=0;
          end
          else if(ENABLE_EXTENDED_RESULTS && rx_magic_ok&&rx_version==V2_VERSION&&rx_type==V2_ACTION) begin
            rx_commit_pending<=0;
          end
        end
        if(rx_commit_pending) begin
          if(rx_commit_delay!=63) rx_commit_delay<=rx_commit_delay+1'b1;
          if(rx_commit_delay>=24) begin
            if(rx_error_latch||!session_safe||
               (ENABLE_HOST_HXA_PREVIEW && (legacy_rx_error||stack_reset))) begin
              rx_commit_pending<=0;
            end else if(rx_commit_kind==1&&cfg_ack_sync[1]==cfg_req_toggle) begin
              if(rx_len_hold==4||!have_cfg_sequence||
                 ((cfg_sequence_tmp-last_cfg_sequence)<32'h80000000&&cfg_sequence_tmp!=last_cfg_sequence)) begin
                cfg_mode_shadow<=cfg_mode_tmp;cfg_threshold_shadow<=cfg_threshold_tmp;
                cfg_brightness_shadow<=cfg_brightness_tmp;cfg_color_shadow<=cfg_color_tmp;
                cfg_detect_shadow<=cfg_detect_tmp;cfg_heq_shadow<=cfg_heq_tmp;cfg_auto_shadow<=cfg_auto_tmp;
                if((rx_len_hold!=4)&&cfg_app_valid_tmp&&
                   (cfg_app_mode_tmp<=3'd1)) begin
                  cfg_app_mode_shadow<=cfg_app_mode_tmp;
                  cfg_app_valid_shadow<=1'b1;
                end else begin
                  // Keep the last legal mode value, but do not publish an
                  // application-mode update for legacy or rejected values.
                  cfg_app_valid_shadow<=1'b0;
                end
                if (rx_len_hold==4) begin
                  cfg_awb_shadow<=cfg_auto_tmp; cfg_ae_shadow<=cfg_auto_tmp; cfg_ag_shadow<=cfg_auto_tmp;
                  cfg_quality_heq_shadow<=cfg_heq_tmp;
                end else begin
                  cfg_awb_shadow<=rx_flags_tmp[8]; cfg_ae_shadow<=rx_flags_tmp[9]; cfg_ag_shadow<=rx_flags_tmp[10];
                  cfg_quality_heq_shadow<=rx_flags_tmp[11];
                end
                cfg_cnn_shadow<=cfg_cnn_tmp;cfg_req_toggle<=~cfg_req_toggle;
                if(rx_len_hold!=4)begin last_cfg_sequence<=cfg_sequence_tmp;have_cfg_sequence<=1;end
              end
              rx_commit_pending<=0;
            end else if(ENABLE_EXTENDED_RESULTS && rx_commit_kind==2&&cnn_ack_sync[1]==cnn_req_toggle) begin
              if(cnn_count_tmp>8||cnn_record_size_tmp!=16'd20||
                 rx_len_hold!=cnn_expected_len(cnn_count_tmp[3:0])||
                 (have_cnn_sequence&&!((cnn_sequence_tmp-last_cnn_sequence)<32'h80000000&&cnn_sequence_tmp!=last_cnn_sequence))||
                 (!rx_flags_tmp[0]&&have_cnn_frame&&
                   !((cnn_frame_tmp-last_cnn_frame)<32'h80000000&&cnn_frame_tmp!=last_cnn_frame))||
                 (!rx_flags_tmp[0]&&have_video_frame&&
                   (((video_frame_id-cnn_frame_tmp)>=32'h80000000)||
                    ((video_frame_id-cnn_frame_tmp)>MAX_CNN_FRAME_LAG))))
                validate_ok<=0;
              else validate_ok<=1;
              validate_index<=0;validation_active<=1;
              rx_commit_pending<=0;
            end else if(ENABLE_EXTENDED_RESULTS && rx_commit_kind==3&&action_ack_sync[1]==action_req_toggle) begin
              if((!have_action_sequence||
                  ((action_sequence_tmp-last_action_sequence)<32'h80000000&&
                   action_sequence_tmp!=last_action_sequence))&&
                 action_app_mode_tmp>=2'd1&&action_app_mode_tmp<=2'd3&&
                 action_conf_tmp<=100&&action_ttl_tmp!=0&&
                  ((rx_flags_tmp & 16'h001b)!=0)&&
                  ((rx_flags_tmp & ~16'h001b)==0)&&
                 (!rx_flags_tmp[0]||!have_video_frame||
                  ((video_frame_id-action_frame_tmp)<32'h80000000&&
                   (video_frame_id-action_frame_tmp)<=MAX_CNN_FRAME_LAG))) begin
                action_sequence_shadow<=action_sequence_tmp;action_frame_shadow<=action_frame_tmp;
                action_app_mode_shadow<=action_app_mode_tmp;action_id_shadow<=action_id_tmp;
                action_conf_shadow<=action_conf_tmp;action_evidence_shadow<=action_evidence_tmp;
                action_ttl_shadow<=action_ttl_tmp;action_cooldown_shadow<=action_cooldown_tmp;
                action_flags_shadow<=rx_flags_tmp;action_label_shadow<=action_label_tmp;
                action_req_toggle<=~action_req_toggle;last_action_sequence<=action_sequence_tmp;
                have_action_sequence<=1;
              end
              rx_commit_pending<=0;
            end
          end
        end
        if(ENABLE_EXTENDED_RESULTS && validation_active) begin
          if(validate_index<cnn_count_tmp && !validate_coord_ok) validate_ok<=0;
          if(validate_index==7) begin
            validation_active<=0;
            if(validate_ok&&((validate_index>=cnn_count_tmp)||validate_coord_ok)) begin
                cnn_heartbeat_shadow<=rx_flags_tmp[0];
                if(!rx_flags_tmp[0]) begin
                  cnn_frame_shadow<=cnn_frame_tmp;cnn_inference_shadow<=cnn_inference_tmp;
                  cnn_count_shadow<=cnn_count_tmp[3:0];
                  for(validate_i=0;validate_i<8;validate_i=validate_i+1)
                    cnn_bbox_shadow[validate_i*48+:48]<={cnn_ymax_tmp[validate_i*16+:12],
                      cnn_xmax_tmp[validate_i*16+:12],cnn_ymin_tmp[validate_i*16+:12],
                      cnn_xmin_tmp[validate_i*16+:12]};
                  cnn_class_shadow<=cnn_class_tmp;cnn_conf_shadow<=cnn_conf_tmp;
                  cnn_flags_shadow<=cnn_flags_tmp;cnn_label_shadow<=cnn_label_tmp;
                  last_cnn_frame<=cnn_frame_tmp;have_cnn_frame<=1;
                end
                cnn_req_toggle<=~cnn_req_toggle;last_cnn_sequence<=cnn_sequence_tmp;
                have_cnn_sequence<=1;cnn_session_timer<=0;
            end
          end else validate_index<=validate_index+1'b1;
        end
        // A packet may report CRC failure after its final payload byte.
        // Cancel only transient parser state on shared-stack abort; the
        // live CONFIG request/ack toggles must remain paired across domains.
        if(ENABLE_HOST_HXA_PREVIEW && legacy_rx_error) rx_error_latch<=1;
        if(ENABLE_HOST_HXA_PREVIEW && stack_reset) begin
          rudp_valid_d<=0;rx_commit_pending<=0;validation_active<=0;
          rx_error_latch<=1;
        end
        if(session_changed||!session_safe) begin
          rx_commit_pending<=0;validation_active<=0;
          have_cfg_sequence<=0;have_cnn_sequence<=0;have_cnn_frame<=0;have_action_sequence<=0;
        end
      end
    end

    reg [1:0] cfg_req_sync_pix,cnn_req_sync_pix,action_req_sync_pix;
    reg cfg_req_seen_pix,cnn_req_seen_pix,action_req_seen_pix;
    always @(posedge I_clk_pix or negedge I_rst_pix_n) begin
      if(!I_rst_pix_n) begin
        cfg_req_sync_pix<=0;cfg_req_seen_pix<=0;cfg_ack_toggle_pix<=0;
        O_cfg_valid<=0;
        cnn_req_sync_pix<=0;cnn_req_seen_pix<=0;cnn_ack_toggle_pix<=0;
        action_req_sync_pix<=0;action_req_seen_pix<=0;action_ack_toggle_pix<=0;
        O_cnn_valid<=0;O_cnn_heartbeat<=0;O_action_valid<=0;
      end else begin
        cfg_req_sync_pix<={cfg_req_sync_pix[0],cfg_req_toggle};
        cnn_req_sync_pix<={cnn_req_sync_pix[0],cnn_req_toggle};
        action_req_sync_pix<={action_req_sync_pix[0],action_req_toggle};
        cfg_ack_toggle_pix<=cfg_req_seen_pix;
        O_cfg_valid<=0;O_cnn_valid<=0;O_cnn_heartbeat<=0;O_action_valid<=0;
        if(cfg_req_sync_pix[1]!=cfg_req_seen_pix) begin
          O_cfg_valid<=1;
          cfg_req_seen_pix<=cfg_req_sync_pix[1];cfg_ack_toggle_pix<=cfg_req_sync_pix[1];
        end
        if(ENABLE_EXTENDED_RESULTS && cnn_req_sync_pix[1]!=cnn_req_seen_pix) begin
          if(cnn_heartbeat_shadow) O_cnn_heartbeat<=1;
          else begin
            O_cnn_valid<=1;
          end
          cnn_req_seen_pix<=cnn_req_sync_pix[1];cnn_ack_toggle_pix<=cnn_req_sync_pix[1];
        end
        if(ENABLE_EXTENDED_RESULTS && action_req_sync_pix[1]!=action_req_seen_pix) begin
          O_action_valid<=1;
          action_req_seen_pix<=action_req_sync_pix[1];
          action_ack_toggle_pix<=action_req_sync_pix[1];
        end
      end
    end

    // ------------------------------------------------------------------
    // Pixel-domain BT.601 full-range RGB888 -> YUYV422 conversion.
    // The monitor FIFO is a side branch and cannot stall HDMI.
    // ------------------------------------------------------------------
    // Keep only this static boundary when the legacy preview is disabled.
    // In particular, no preview FIFO instance is elaborated in that build.
    wire [31:0] captured_frames_pix,fifo_overflow_pix;
    wire overflow_toggle_pix;
    wire fifo_we;
    wire [33:0] fifo_di,fifo_dout;
    wire fifo_valid,fifo_full,fifo_empty,fifo_afull,fifo_aempty;
    wire [12:0] fifo_wrusedw,fifo_rdusedw;
    reg fifo_re;
    generate
      if (ENABLE_VIDEO_PREVIEW) begin : g_video_preview
        function [7:0] clamp_s11;
          input signed [10:0] value;
          begin
            if(value<0) clamp_s11=0;
            else if(value>255) clamp_s11=255;
            else clamp_s11=value[7:0];
          end
        endfunction
        wire [7:0] pix_r=I_pix[23:16],pix_g=I_pix[15:8],pix_b=I_pix[7:0];
        // Exact factorization around G: preserve coefficients and floor rounding.
        wire signed [8:0] delta_r=$signed({1'b0,pix_r})-$signed({1'b0,pix_g});
        wire signed [8:0] delta_b=$signed({1'b0,pix_b})-$signed({1'b0,pix_g});
        wire signed [15:0] y_delta=delta_r*8'sd77+delta_b*6'sd29;
        wire signed [16:0] y_sum=$signed({1'b0,pix_g,8'd0})+$signed(y_delta);
        wire [15:0] y_calc=y_sum[15:0];
        wire signed [15:0] u_calc=$signed({delta_b,7'd0})-delta_r*7'sd43;
        wire signed [15:0] v_calc=$signed({delta_r,7'd0})-delta_b*6'sd21;
        reg [7:0] y_pipe,u_pipe,v_pipe;
        reg cvt_valid,cvt_even,cvt_sof,cvt_eof,pix_even;
        // Track source coordinates before packing. The default 4:1 horizontal
        // and vertical decimation produces 320x180; HDMI is unchanged.
        localparam integer SRC_WIDTH = 1280;
        localparam integer SRC_HEIGHT = 720;
        reg [10:0] src_x;
        reg [9:0]  src_y;
        reg [10:0] cvt_x;
        reg [9:0]  cvt_y;
        localparam integer X_DECIM = SRC_WIDTH / VIDEO_WIDTH;
        localparam integer Y_DECIM = SRC_HEIGHT / VIDEO_HEIGHT;
        // Keep one source YUYV pair every X_DECIM pairs and one line every
        // Y_DECIM lines.  The pair packer emits odd source pixels (x=1 mod
        // 2*X_DECIM), so the final retained pixel is SRC_WIDTH-(2*X_DECIM-1).
        wire sample_pair = ((cvt_y & (Y_DECIM-1)) == 0) &&
                           ((cvt_x & ((X_DECIM*2)-1)) == 1);
        wire sample_eof = (cvt_y == SRC_HEIGHT-Y_DECIM) &&
                          (cvt_x == SRC_WIDTH-(X_DECIM*2-1));
        wire [7:0] y_clamped=y_pipe;
        wire [7:0] u_clamped=u_pipe;
        wire [7:0] v_clamped=v_pipe;
        reg [7:0] pair_y0,pair_u0,pair_v0;
        reg pair_sof;
        wire [8:0] pair_u_sum={1'b0,pair_u0}+{1'b0,u_clamped};
        wire [8:0] pair_v_sum={1'b0,pair_v0}+{1'b0,v_clamped};
        reg [31:0] captured_frames_r,fifo_overflow_r;
        reg drop_frame_pix,overflow_toggle_r;
        // Admission is decided once per SOF and held for the complete frame.
        reg frame_keep_pix;
        reg [1:0] frame_div_pix;
        reg fifo_we_r;
        reg [33:0] fifo_di_r;
        assign captured_frames_pix = captured_frames_r;
        assign fifo_overflow_pix = fifo_overflow_r;
        assign overflow_toggle_pix = overflow_toggle_r;
        assign fifo_we = fifo_we_r;
        assign fifo_di = fifo_di_r;

        always @(posedge I_clk_pix or negedge I_rst_pix_n) begin
          if(!I_rst_pix_n) begin
            y_pipe<=0;u_pipe<=128;v_pipe<=128;cvt_valid<=0;cvt_even<=0;cvt_sof<=0;cvt_eof<=0;
            src_x<=0; src_y<=0; cvt_x<=0; cvt_y<=0;
            pix_even<=0;pair_y0<=0;pair_u0<=128;pair_v0<=128;pair_sof<=0;
            captured_frames_r<=0;fifo_overflow_r<=0;drop_frame_pix<=0;
            frame_div_pix<=0;frame_keep_pix<=1'b1;
            overflow_toggle_r<=0;fifo_we_r<=0;fifo_di_r<=0;
          end else begin
            fifo_we_r<=0;cvt_valid<=I_pix_de;cvt_even<=pix_even;cvt_sof<=I_pix_sof;cvt_eof<=I_pix_eof;
            cvt_x <= I_pix_sof ? 11'd0 : src_x;
            cvt_y <= src_y;
            if(I_pix_sof) begin
              // SOF itself is pixel x=0.  Advance the source coordinate here so
              // the delayed x register labels the following odd pixel as x=1;
              // otherwise the first line emits only 319 YUYV words.
              src_x <= 11'd1;
              src_y <= 10'd0;
            end else if(I_pix_de) begin
              if(src_x == SRC_WIDTH-1) begin
                src_x <= 11'd0;
                if(src_y < SRC_HEIGHT-1) src_y <= src_y + 1'b1;
              end else begin
                src_x <= src_x + 1'b1;
              end
            end
            if(I_pix_sof) begin
              // The delayed pair stage treats cvt_even=1 as the second sample.
              // Seed the phase high so the first emitted pair is x=0/1 (the
              // delayed coordinate is x=1); seeding low skips that pair and
              // produces only 319 words per line, losing SOF alignment.
              pix_even<=1'b1;captured_frames_r<=captured_frames_r+1'b1;
              // Keep the first frame, then every VIDEO_FRAME_DIV-th frame.  The
              // decision is made before delayed pixels reach the FIFO.
              if(VIDEO_FRAME_DIV <= 1) begin
                frame_keep_pix <= 1'b1;
                frame_div_pix  <= 0;
              end else if(frame_div_pix == 0) begin
                frame_keep_pix <= 1'b1;
                frame_div_pix  <= VIDEO_FRAME_DIV-1;
              end else begin
                frame_keep_pix <= 1'b0;
                frame_div_pix  <= frame_div_pix - 1'b1;
              end
              drop_frame_pix <= 1'b0;
            end else if(I_pix_de) pix_even<=~pix_even;
            if(I_pix_de) begin
              // Adding 128 to a signed high byte flips bit 7 modulo 256.
              // U/V bounds prove the result is already in 0..255.
              y_pipe<=y_calc[15:8];
              u_pipe<={~u_calc[15],u_calc[14:8]};
              v_pipe<={~v_calc[15],v_calc[14:8]};
            end
            if(cvt_valid) begin
              if(!cvt_even) begin
                pair_y0<=y_clamped;pair_u0<=u_clamped;pair_v0<=v_clamped;pair_sof<=cvt_sof;
              end else if(frame_keep_pix && !drop_frame_pix && sample_pair) begin
                if(fifo_full) begin
                  drop_frame_pix<=1;fifo_overflow_r<=fifo_overflow_r+1'b1;
                  overflow_toggle_r<=~overflow_toggle_r;
                end else begin
                  fifo_di_r<={sample_eof,pair_sof,pair_v_sum[8:1],y_clamped,pair_u_sum[8:1],pair_y0};
                  fifo_we_r<=1;
                end
              end
            end
          end
        end

        // The existing generated asynchronous FIFO implementation is safely
        // parameterized here to 34 x 8192 (~34 KiB). SHOW_AHEAD allows the
        // packetizer to emit four bytes without bubbles for each FIFO word.
        soft_fifo_al_4057d6b76aa6 #(
          .DATA_WIDTH_W(34),.DATA_WIDTH_R(34),.ADDR_WIDTH_W(13),.ADDR_WIDTH_R(13),
          .AL_FULL_NUM(13'd8000),.AL_EMPTY_NUM(13'd360),.SHOW_AHEAD_EN(1'b1),.OUTREG_EN("NOREG")
        ) u_video_fifo(
          .rst(~I_rst_n | ~I_rst_pix_n),.clkw(I_clk_pix),.clkr(I_clk125),.we(fifo_we_r),.di(fifo_di_r),
          .re(fifo_re),.dout(fifo_dout),.valid(fifo_valid),.full_flag(fifo_full),
          .empty_flag(fifo_empty),.afull(fifo_afull),.aempty(fifo_aempty),
          .wrusedw(fifo_wrusedw),.rdusedw(fifo_rdusedw));
      end else begin : g_no_video_preview
        assign captured_frames_pix = 32'd0;
        assign fifo_overflow_pix = 32'd0;
        assign overflow_toggle_pix = 1'b0;
        assign fifo_we = 1'b0;
        assign fifo_di = 34'd0;
        assign fifo_dout = 34'd0;
        assign fifo_valid = 1'b0;
        assign fifo_full = 1'b0;
        assign fifo_empty = 1'b1;
        assign fifo_afull = 1'b0;
        assign fifo_aempty = 1'b1;
        assign fifo_wrusedw = 13'd0;
        assign fifo_rdusedw = 13'd0;
      end
    endgenerate

    // Atomic status snapshot. The source registers remain stable until the
    // acknowledgement is observed back in the network domain.
    reg status_req_toggle;
    reg [1:0] status_req_sync_pix;
    reg status_req_seen_pix,status_ack_toggle_pix;
    reg [31:0] status_fp_pix,status_target_pix,status_motion_pix,status_latency_pix;
    reg [7:0] status_flags_pix;
    reg [31:0] status_captured_pix,status_overflow_pix;
    reg [2:0] status_app_mode_pix;
    reg [1:0] status_retries_pix;
    reg status_armed_pix,status_peer_pix;
    reg [7:0] status_last_action_pix,status_action_result_pix;
    reg [15:0] status_uart_errors_pix;
    always @(posedge I_clk_pix or negedge I_rst_pix_n) begin
      if(!I_rst_pix_n) begin
        status_req_sync_pix<=0;status_req_seen_pix<=0;status_ack_toggle_pix<=0;
        status_fp_pix<=0;status_target_pix<=0;status_motion_pix<=0;status_latency_pix<=0;
        status_flags_pix<=0;
        status_captured_pix<=0;status_overflow_pix<=0;
        status_app_mode_pix<=0;status_retries_pix<=0;status_armed_pix<=0;status_peer_pix<=0;
        status_last_action_pix<=0;status_action_result_pix<=0;status_uart_errors_pix<=0;
      end else begin
        status_req_sync_pix<={status_req_sync_pix[0],status_req_toggle};
        if(status_req_sync_pix[1]!=status_req_seen_pix) begin
          status_fp_pix<=I_frame_period;status_target_pix<={12'd0,I_target_count};
          status_motion_pix<={12'd0,I_motion_count};status_latency_pix<=I_latency_us;
          // Reuse the preview-only words; no extra pixel CDC payload bank.
          status_captured_pix<=(ENABLE_HOST_HXA_PREVIEW && !ENABLE_VIDEO_PREVIEW)?I_board_status_pix[31:0]:captured_frames_pix;
          status_overflow_pix<=(ENABLE_HOST_HXA_PREVIEW && !ENABLE_VIDEO_PREVIEW)?I_board_status_pix[63:32]:fifo_overflow_pix;
          status_flags_pix<=I_status_flags;
          status_app_mode_pix<=I_app_mode;status_armed_pix<=I_app_armed;status_peer_pix<=I_peer_online;
          status_last_action_pix<=I_last_action;status_action_result_pix<=I_action_result;
          status_retries_pix<=I_action_retries;status_uart_errors_pix<=I_uart_errors;
          status_req_seen_pix<=status_req_sync_pix[1];status_ack_toggle_pix<=status_req_sync_pix[1];
        end
      end
    end

    // ------------------------------------------------------------------
    // Standard-MTU UDP packetizer. A timed-out request briefly resets only
    // the network stack so that a latched unresolved-ARP transaction is
    // actually cancelled; HDMI keeps running. With preview disabled the
    // status/session scheduler never waits for a video FIFO or frame.
    // ------------------------------------------------------------------
    localparam [2:0] T_IDLE=0,T_REQ=1,T_SEND=2,T_DONE=3,T_GAP=4;
    localparam [2:0] K_VIDEO=0,K_LEGACY_STATUS=1,K_V2_STATUS=2,K_APP_STATUS=3,K_SESSION=4,K_BOARD_STATUS=5,K_AWB=6;
    localparam integer HOST_STATUS=ENABLE_HOST_HXA_PREVIEW;
    reg [2:0] tx_state;
    reg [2:0] tx_kind;
    reg [15:0] tx_byte,tx_packet_index,tx_payload_len;
    reg [23:0] req_timeout;
    reg [31:0] frame_timestamp_ms,timestamp_ms,status_timer;
    assign session_timestamp=timestamp_ms;
    reg [16:0] ms_divider;
    reg status_due,status_wait_ack,status_ready,status_v2_pending,status_app_pending,status_board_pending;
    // Keep both synchronizer stages as distinct registers.  The physical CDC
    // audit relies on equal clock/reset attributes for the two stages; a
    // vector without these hints may be retimed or packed asymmetrically when
    // unrelated RAW-domain logic changes the optimization pressure.
    (* async_reg = "true", keep = "true" *) reg [1:0] status_ack_sync;
    reg [1:0] status_settle;
    // The bundled payload can arrive one receiver cycle after its toggle.
    // Host snapshots wait two additional clocks after observing ack before
    // committing s2, with source data held until the next request.
    wire status_snapshot_commit=status_wait_ack && status_ack_sync[1]==status_req_toggle &&
                                (!HOST_STATUS || status_settle==2);
    reg [31:0] status_fp_s1,status_fp_s2,status_target_s1,status_target_s2;
    reg [7:0] status_flags_s1,status_flags_s2,st_flags;
    reg [31:0] status_motion_s1,status_motion_s2,status_latency_s1,status_latency_s2;
    reg [31:0] status_captured_s1,status_captured_s2,status_overflow_s1,status_overflow_s2;
    reg [31:0] st_frame_period,st_target,st_motion,st_latency,st_captured,st_overflow;
    reg [2:0] status_app_mode_s1,status_app_mode_s2,st_app_mode;
    reg status_armed_s1,status_armed_s2,st_armed,status_peer_s1,status_peer_s2,st_peer;
    reg [7:0] status_last_action_s1,status_last_action_s2,st_last_action;
    reg [7:0] status_action_result_s1,status_action_result_s2,st_action_result;
    reg [1:0] status_retries_s1,status_retries_s2,st_retries;
    reg [15:0] status_uart_errors_s1,status_uart_errors_s2,st_uart_errors;
    reg [31:0] complete_frames,network_drop_frames,sent_packet_count,status_sequence;
    // Already synchronous to I_clk125; latched on the same acknowledged
    // snapshot boundary as the held pixel-domain status words.
    reg [31:0] st_hxa_sent,st_hxa_failed,st_snapshot_frame,st_snapshot_ms;
    reg st_hxa_online;
    reg [7:0] st_hxa_job;
    reg frame_active,drop_until_next_sof,dropped_first_sof,tx_abort;
    reg recovery_read_wait;
    reg abort_sof_consumed;
    reg [1:0] overflow_sync;
    reg overflow_seen;
    wire overflow_event=ENABLE_VIDEO_PREVIEW && (overflow_sync[1]^overflow_seen);
    wire current_sof_consumed=ENABLE_VIDEO_PREVIEW && ((tx_packet_index!=0)||
      (tx_state==T_SEND&&tx_kind==K_VIDEO&&tx_byte>=VIDEO_HEADER+3)||
      (tx_state==T_DONE&&tx_kind==K_VIDEO));
    wire [12:0] packet_words_needed=(tx_packet_index==VIDEO_PKT_COUNT-1)?((LAST_PAYLOAD+3)/4):((FULL_PAYLOAD+3)/4);
    wire video_packet_ready=ENABLE_VIDEO_PREVIEW && fifo_valid&&(fifo_rdusedw>=packet_words_needed);
    wire [15:0] tx_total_len=(ENABLE_VIDEO_PREVIEW && tx_kind==K_VIDEO)?(VIDEO_HEADER+tx_payload_len):
                             (tx_kind==K_LEGACY_STATUS)?16'd16:
                             (tx_kind==K_APP_STATUS||tx_kind==K_SESSION)?16'd32:
                             (tx_kind==K_BOARD_STATUS)?16'd48:
                             (ENABLE_AWB_DIAG && tx_kind==K_AWB)?16'd44:16'd56;

    wire awb_diag_ready;
    wire [223:0] awb_diag_payload;
    wire [31:0] awb_diag_sequence,awb_diag_timestamp;
    // There is only one destination payload register. It remains stable
    // from acknowledgement capture until the packet is sent or cancelled.
    generate
      if(ENABLE_AWB_DIAG) begin : g_awb_diag
        reg req_toggle,armed,ready;
        (* async_reg = "true", ASYNC_REG = "TRUE", keep = "true", dont_touch = "true" *) reg [1:0] ack_sync;
        (* async_reg = "true", ASYNC_REG = "TRUE", keep = "true", dont_touch = "true" *) reg reset_n_s1,reset_n_s2;
        reg [1:0] baseline_settle,payload_settle;
        reg [223:0] captured_payload;
        reg [31:0] captured_sequence,captured_timestamp;
        wire transmitting=(tx_kind==K_AWB && tx_state!=T_IDLE && tx_state!=T_GAP);
        wire transport_cancel=ENABLE_HOST_HXA_PREVIEW && stack_reset;
        wire request_timeout=(tx_state==T_REQ && tx_kind==K_AWB && !W_udp_busy &&
            (!ENABLE_HOST_HXA_PREVIEW || legacy_tx_selected) &&
            req_timeout>=UDP_REQUEST_TIMEOUT_CYCLES-1);
        wire source_reset=legacy_reset || !I_awb_diag_source_rst_n;
        wire launch=status_snapshot_commit && reset_n_s2 && !armed && !ready && !transmitting &&
                    baseline_settle==2 && ack_sync[1]==req_toggle && !transport_cancel;
        wire capture=reset_n_s2 && armed && ack_sync[1]==req_toggle && payload_settle==2 &&
                     !transmitting && !transport_cancel;
        assign O_awb_diag_req=req_toggle;
        // Also reset the camera-side held mailbox on network/AUX reset.
        // Its local release is synchronized in the source domain.
        assign O_awb_diag_rst_n=~legacy_reset;
        assign awb_diag_ready=ready;
        assign awb_diag_payload=captured_payload;
        assign awb_diag_sequence=captured_sequence;
        assign awb_diag_timestamp=captured_timestamp;
        always @(posedge I_clk125 or posedge source_reset) begin
          if(source_reset)begin reset_n_s1<=0;reset_n_s2<=0;end
          else begin reset_n_s1<=1;reset_n_s2<=reset_n_s1;end
        end
        // A camera-only reset cancels the handshake epoch, but must not
        // overwrite bytes of an already transmitting UDP packet. Keep the
        // captured bank until a new acknowledged transaction replaces it.
        always @(posedge I_clk125 or posedge legacy_reset)begin
          if(legacy_reset)begin captured_payload<=0;captured_sequence<=0;captured_timestamp<=0;end
          else begin
            if(launch)begin captured_sequence<=status_sequence+1'b1;captured_timestamp<=timestamp_ms;end
            if(capture)captured_payload<=I_awb_diag_data;
          end
        end
        always @(posedge I_clk125 or negedge reset_n_s2) begin
          if(!reset_n_s2) begin
            req_toggle<=0;armed<=0;ready<=0;ack_sync<=0;
            baseline_settle<=0;payload_settle<=0;
          end else begin
            ack_sync<={ack_sync[0],I_awb_diag_ack};
            if(!armed && !ready && !transmitting && ack_sync[1]==req_toggle) begin
              if(baseline_settle!=2)baseline_settle<=baseline_settle+1'b1;
            end else baseline_settle<=0;
            if(armed) begin
              if(ack_sync[1]==req_toggle) begin
                if(capture) begin
                  ready<=1;armed<=0;payload_settle<=0;
                end else payload_settle<=payload_settle+1'b1;
              end else payload_settle<=0;
            end
            // The existing status scheduler never waits for this mailbox.
            // Baseline matching before toggling prevents an old reset ack
            // from being accepted as the response to a new request.
            if(launch) begin
              req_toggle<=~req_toggle;armed<=1;payload_settle<=0;
              baseline_settle<=0;
            end
            if((tx_state==T_DONE && tx_kind==K_AWB && !W_udp_busy) || request_timeout)
              ready<=0;
            if(transport_cancel) begin
              armed<=0;ready<=0;payload_settle<=0;baseline_settle<=0;
            end
          end
        end
      end else begin : g_no_awb_diag
        assign O_awb_diag_req=1'b0;
        assign O_awb_diag_rst_n=1'b0;
        assign awb_diag_ready=1'b0;
        assign awb_diag_payload=224'd0;
        assign awb_diag_sequence=32'd0;
        assign awb_diag_timestamp=32'd0;
      end
    endgenerate

    function [7:0] byte32;
      input [31:0] value;input [1:0] index;
      begin case(index) 0:byte32=value[7:0];1:byte32=value[15:8];
        2:byte32=value[23:16];default:byte32=value[31:24];endcase end
    endfunction
    function [7:0] awb_diagnostic_byte;
      input [5:0] index;
      begin case(index)
        0:awb_diagnostic_byte=8'h48;1:awb_diagnostic_byte=8'h58;
        2:awb_diagnostic_byte=8'h56;3:awb_diagnostic_byte=8'h32;
        4:awb_diagnostic_byte=8'd2;5:awb_diagnostic_byte=8'd11;
        6:awb_diagnostic_byte=8'd44;7:awb_diagnostic_byte=8'd1;
        8:awb_diagnostic_byte=awb_diag_sequence[7:0];
        9:awb_diagnostic_byte=awb_diag_sequence[15:8];
        10:awb_diagnostic_byte=awb_diag_sequence[23:16];
        11:awb_diagnostic_byte=awb_diag_sequence[31:24];
        12:awb_diagnostic_byte=awb_diag_timestamp[7:0];
        13:awb_diagnostic_byte=awb_diag_timestamp[15:8];
        14:awb_diagnostic_byte=awb_diag_timestamp[23:16];
        15:awb_diagnostic_byte=awb_diag_timestamp[31:24];
        16:awb_diagnostic_byte=awb_diag_payload[7:0];
        17:awb_diagnostic_byte=awb_diag_payload[15:8];
        18:awb_diagnostic_byte=awb_diag_payload[23:16];
        19:awb_diagnostic_byte=awb_diag_payload[31:24];
        20:awb_diagnostic_byte=awb_diag_payload[39:32];
        21:awb_diagnostic_byte=awb_diag_payload[47:40];
        22:awb_diagnostic_byte=awb_diag_payload[55:48];
        23:awb_diagnostic_byte=awb_diag_payload[63:56];
        24:awb_diagnostic_byte=awb_diag_payload[71:64];
        25:awb_diagnostic_byte=awb_diag_payload[79:72];
        26:awb_diagnostic_byte=awb_diag_payload[87:80];
        27:awb_diagnostic_byte=awb_diag_payload[95:88];
        28:awb_diagnostic_byte=awb_diag_payload[103:96];
        29:awb_diagnostic_byte=awb_diag_payload[111:104];
        30:awb_diagnostic_byte=awb_diag_payload[119:112];
        31:awb_diagnostic_byte=awb_diag_payload[127:120];
        32:awb_diagnostic_byte=awb_diag_payload[135:128];
        33:awb_diagnostic_byte=awb_diag_payload[143:136];
        34:awb_diagnostic_byte=awb_diag_payload[151:144];
        35:awb_diagnostic_byte=awb_diag_payload[159:152];
        36:awb_diagnostic_byte=awb_diag_payload[167:160];
        37:awb_diagnostic_byte=awb_diag_payload[175:168];
        38:awb_diagnostic_byte=awb_diag_payload[183:176];
        39:awb_diagnostic_byte=awb_diag_payload[191:184];
        40:awb_diagnostic_byte=awb_diag_payload[199:192];
        41:awb_diagnostic_byte=awb_diag_payload[207:200];
        42:awb_diagnostic_byte=awb_diag_payload[215:208];
        43:awb_diagnostic_byte=awb_diag_payload[223:216];
        default:awb_diagnostic_byte=8'd0;
      endcase end
    endfunction
    function [7:0] video_header_byte;
      input [5:0] index;
      begin case(index)
        0:video_header_byte=8'h48;1:video_header_byte=8'h58;2:video_header_byte=8'h56;3:video_header_byte=8'h32;
        4:video_header_byte=V2_VERSION;5:video_header_byte=V2_VIDEO;
        6:video_header_byte={frame_session_tag[5:0],
                            (tx_packet_index==VIDEO_PKT_COUNT-1),(tx_packet_index==0)};
        7:video_header_byte=frame_session_tag[13:6];
        8,9,10,11:video_header_byte=byte32(video_frame_id,index-8);
        12,13,14,15:video_header_byte=byte32(frame_timestamp_ms,index-12);
        16:video_header_byte=tx_packet_index[7:0];17:video_header_byte=tx_packet_index[15:8];
        18:video_header_byte=VIDEO_PKT_COUNT[7:0];19:video_header_byte=VIDEO_PKT_COUNT[15:8];
        20:video_header_byte=VIDEO_WIDTH[7:0];21:video_header_byte=VIDEO_WIDTH[15:8];
        22:video_header_byte=VIDEO_HEIGHT[7:0];23:video_header_byte=VIDEO_HEIGHT[15:8];
        24,25,26,27:video_header_byte=byte32(FRAME_BYTES,index-24);
        28:video_header_byte=tx_payload_len[7:0];29:video_header_byte=tx_payload_len[15:8];
        30:video_header_byte=8'h01;31:video_header_byte=0;
        default:video_header_byte=0;
      endcase end
    endfunction
    function [7:0] legacy_status_byte;
      input [4:0] index;
      begin case(index)
        0,1,2,3:legacy_status_byte=byte32(st_frame_period,index);
        4:legacy_status_byte=st_target[7:0];5:legacy_status_byte=st_target[15:8];
        6:legacy_status_byte=st_motion[7:0];7:legacy_status_byte=st_motion[15:8];
        8:legacy_status_byte=network_drop_frames[7:0];9:legacy_status_byte=network_drop_frames[15:8];
        10,11,12,13:legacy_status_byte=byte32(st_latency,index-10);
        14:legacy_status_byte=8'h55;15:legacy_status_byte=8'hAA;default:legacy_status_byte=0;
      endcase end
    endfunction
    function [7:0] v2_status_byte;
      input [5:0] index;
      begin case(index)
        0:v2_status_byte=8'h48;1:v2_status_byte=8'h58;2:v2_status_byte=8'h56;3:v2_status_byte=8'h32;
        4:v2_status_byte=V2_VERSION;5:v2_status_byte=V2_STATUS;6:v2_status_byte=8'd56;7:v2_status_byte=st_flags;
        8,9,10,11:v2_status_byte=byte32(status_sequence,index-8);
        12,13,14,15:v2_status_byte=byte32(timestamp_ms,index-12);
        16,17,18,19:v2_status_byte=byte32(st_frame_period,index-16);
        20,21,22,23:v2_status_byte=HOST_STATUS?8'd0:byte32(st_captured,index-20);
        24,25,26,27:v2_status_byte=byte32(complete_frames,index-24);
        28,29,30,31:v2_status_byte=byte32(network_drop_frames,index-28);
        32,33,34,35:v2_status_byte=HOST_STATUS?8'd0:byte32(st_overflow,index-32);
        36,37,38,39:v2_status_byte=byte32(sent_packet_count,index-36);
        40,41,42,43:v2_status_byte=byte32(video_frame_id,index-40);
        44,45,46,47:v2_status_byte=byte32(st_latency,index-44);
        48,49,50,51:v2_status_byte=byte32(st_target,index-48);
        52,53,54,55:v2_status_byte=byte32(st_motion,index-52);
        default:v2_status_byte=0;
      endcase end
    endfunction

    // The production preview-off build reuses the two old preview words.
    // A preview-on resource control keeps its original counters AND this
    // separate held payload, so both configurations still emit type 10.
    wire [47:0] board_snapshot;
    generate if(ENABLE_HOST_HXA_PREVIEW && ENABLE_VIDEO_PREVIEW) begin : g_preview_host_status
      reg [47:0] board_pix,board_s1,board_s2,board_st;
      always @(posedge I_clk_pix or negedge I_rst_pix_n) begin
        if(!I_rst_pix_n)board_pix<=0;
        else if(status_req_sync_pix[1]!=status_req_seen_pix)board_pix<=I_board_status_pix[47:0];
      end
      always @(posedge I_clk125 or posedge legacy_reset) begin
        if(legacy_reset)begin board_s1<=0;board_s2<=0;board_st<=0;end
        else begin
          board_s1<=board_pix;board_s2<=board_s1;
          if(status_snapshot_commit)board_st<=board_s2;
        end
      end
      assign board_snapshot=board_st;
    end else begin : g_reused_host_status
      assign board_snapshot={st_overflow[15:0],st_captured};
    end endgenerate

    function [7:0] board_status_byte;
      input [5:0] index;
      begin case(index)
        0:board_status_byte=8'h48;1:board_status_byte=8'h58;
        2:board_status_byte=8'h56;3:board_status_byte=8'h32;
        4:board_status_byte=2;5:board_status_byte=10;
        6:board_status_byte=48;7:board_status_byte=1;
        8,9,10,11:board_status_byte=byte32(status_sequence,index-8);
        12,13,14,15:board_status_byte=byte32(st_snapshot_ms,index-12);
        16,17,18,19:board_status_byte=byte32(st_hxa_sent,index-16);
        20,21,22,23:board_status_byte=byte32(st_hxa_failed,index-20);
        24,25,26,27:board_status_byte=byte32(st_snapshot_frame,index-24);
        28:board_status_byte=board_snapshot[23:16];29:board_status_byte=board_snapshot[31:24];
        30:board_status_byte=board_snapshot[39:32];31:board_status_byte=board_snapshot[47:40];
        32:board_status_byte={3'd0,board_snapshot[4:0]};
        33:board_status_byte={5'd0,board_snapshot[8:6]};
        34:board_status_byte={4'd0,st_hxa_online,board_snapshot[13],board_snapshot[14],board_snapshot[5]};
        35:board_status_byte={4'd0,board_snapshot[12:9]};
        36,37,38,39:board_status_byte=byte32(st_target,index-36);
        40,41,42,43:board_status_byte=byte32(st_motion,index-40);
        44:board_status_byte=st_hxa_job;
        default:board_status_byte=0;
      endcase end
    endfunction
    function [7:0] app_status_byte;
      input [5:0] index;
      begin case(index)
        0:app_status_byte=8'h48;1:app_status_byte=8'h58;2:app_status_byte=8'h56;3:app_status_byte=8'h32;
        4:app_status_byte=V2_VERSION;5:app_status_byte=V2_APP_STATUS;6:app_status_byte=8'd32;7:app_status_byte=0;
        8,9,10,11:app_status_byte=byte32(status_sequence,index-8);
        12:app_status_byte={5'd0,st_app_mode};13:app_status_byte={7'd0,st_armed};
        14:app_status_byte={7'd0,st_peer};15:app_status_byte=st_last_action;
        16,17,18,19:app_status_byte=(index==16)?st_action_result:0;
        20,21,22,23:app_status_byte=(index==20)?{6'd0,st_retries}:0;
        24,25,26,27:app_status_byte=(index==24)?st_uart_errors[7:0]:(index==25)?st_uart_errors[15:8]:0;
        28,29,30,31:app_status_byte=st_peer?0:8'hff;
        default:app_status_byte=0;
      endcase end
    endfunction

    assign W_udp_req=(tx_state==T_REQ);
    assign W_udp_valid=(tx_state==T_SEND);
    assign W_udp_data=(ENABLE_VIDEO_PREVIEW && tx_kind==K_VIDEO)?
      ((tx_byte<VIDEO_HEADER)?video_header_byte(tx_byte[5:0]):
       (tx_abort?8'h00:((tx_byte[1:0]==0)?fifo_dout[7:0]:
         (tx_byte[1:0]==1)?fifo_dout[15:8]:(tx_byte[1:0]==2)?fifo_dout[23:16]:fifo_dout[31:24]))):
      (tx_kind==K_LEGACY_STATUS)?legacy_status_byte(tx_byte[4:0]):
      (tx_kind==K_SESSION)?session_reply_tx[tx_byte[4:0]*8+:8]:
       (tx_kind==K_APP_STATUS)?app_status_byte(tx_byte[5:0]):
       (ENABLE_AWB_DIAG && tx_kind==K_AWB)?awb_diagnostic_byte(tx_byte[5:0]):
       (tx_kind==K_BOARD_STATUS)?board_status_byte(tx_byte[5:0]):v2_status_byte(tx_byte[5:0]);

    always @(posedge I_clk125 or posedge legacy_reset) begin
      if(legacy_reset) begin
        session_reply_take<=0;session_reply_tx<=0;frame_session_tag<=0;
        // Preserve the original first-status kind transition. No video
        // request is reachable when ENABLE_VIDEO_PREVIEW is zero.
        tx_state<=T_IDLE;tx_kind<=K_VIDEO;
        tx_byte<=0;tx_packet_index<=0;tx_payload_len<=ENABLE_VIDEO_PREVIEW?FULL_PAYLOAD:16'd0;
        W_udp_len<=0;req_timeout<=0;fifo_re<=0;video_frame_id<=0;frame_timestamp_ms<=0;
        timestamp_ms<=0;ms_divider<=0;status_timer<=0;status_due<=0;status_req_toggle<=0;
        status_wait_ack<=0;status_ready<=0;status_v2_pending<=0;status_app_pending<=0;status_board_pending<=0;status_ack_sync<=0;status_settle<=0;
        status_fp_s1<=0;status_fp_s2<=0;status_target_s1<=0;status_target_s2<=0;
        status_flags_s1<=0;status_flags_s2<=0;st_flags<=0;
        status_motion_s1<=0;status_motion_s2<=0;status_latency_s1<=0;status_latency_s2<=0;
        status_captured_s1<=0;status_captured_s2<=0;status_overflow_s1<=0;status_overflow_s2<=0;
        st_frame_period<=0;st_target<=0;st_motion<=0;st_latency<=0;st_captured<=0;st_overflow<=0;
        status_app_mode_s1<=0;status_app_mode_s2<=0;st_app_mode<=0;
        status_armed_s1<=0;status_armed_s2<=0;st_armed<=0;status_peer_s1<=0;status_peer_s2<=0;st_peer<=0;
        status_last_action_s1<=0;status_last_action_s2<=0;st_last_action<=0;
        status_action_result_s1<=0;status_action_result_s2<=0;st_action_result<=0;
        status_retries_s1<=0;status_retries_s2<=0;st_retries<=0;
        status_uart_errors_s1<=0;status_uart_errors_s2<=0;st_uart_errors<=0;
        complete_frames<=0;network_drop_frames<=0;sent_packet_count<=0;status_sequence<=0;
        st_hxa_sent<=0;st_hxa_failed<=0;st_snapshot_frame<=0;st_snapshot_ms<=0;st_hxa_online<=0;st_hxa_job<=0;
        frame_active<=0;have_video_frame<=0;drop_until_next_sof<=0;dropped_first_sof<=0;
        recovery_read_wait<=0;
        tx_abort<=0;abort_sof_consumed<=0;overflow_sync<=0;overflow_seen<=0;
        stack_reset_count<=0;
      end else begin
        session_reply_take<=0;
        fifo_re<=0;overflow_sync<={overflow_sync[0],overflow_toggle_pix};
        if(stack_reset_count!=0)stack_reset_count<=stack_reset_count-1'b1;
        status_ack_sync<={status_ack_sync[0],status_ack_toggle_pix};
        status_fp_s1<=status_fp_pix;status_fp_s2<=status_fp_s1;
        status_target_s1<=status_target_pix;status_target_s2<=status_target_s1;
        status_flags_s1<=status_flags_pix;status_flags_s2<=status_flags_s1;
        status_motion_s1<=status_motion_pix;status_motion_s2<=status_motion_s1;
        status_latency_s1<=status_latency_pix;status_latency_s2<=status_latency_s1;
        status_captured_s1<=status_captured_pix;status_captured_s2<=status_captured_s1;
        status_overflow_s1<=status_overflow_pix;status_overflow_s2<=status_overflow_s1;
        status_app_mode_s1<=status_app_mode_pix;status_app_mode_s2<=status_app_mode_s1;
        status_armed_s1<=status_armed_pix;status_armed_s2<=status_armed_s1;
        status_peer_s1<=status_peer_pix;status_peer_s2<=status_peer_s1;
        status_last_action_s1<=status_last_action_pix;status_last_action_s2<=status_last_action_s1;
        status_action_result_s1<=status_action_result_pix;status_action_result_s2<=status_action_result_s1;
        status_retries_s1<=status_retries_pix;status_retries_s2<=status_retries_s1;
        status_uart_errors_s1<=status_uart_errors_pix;status_uart_errors_s2<=status_uart_errors_s1;
        if(ms_divider==124999) begin ms_divider<=0;timestamp_ms<=timestamp_ms+1'b1;end
        else ms_divider<=ms_divider+1'b1;
        if(status_timer==124999999) begin status_timer<=0;status_due<=1;end
        else status_timer<=status_timer+1'b1;
        if(status_due&&!status_wait_ack&&!status_ready&&!status_v2_pending&&!status_app_pending&&!status_board_pending&&
           (!HOST_STATUS || tx_state==T_IDLE)) begin
          status_req_toggle<=~status_req_toggle;status_wait_ack<=1;
        end
        if(HOST_STATUS && status_wait_ack && status_ack_sync[1]==status_req_toggle) begin
          if(status_settle!=2)status_settle<=status_settle+1'b1;
        end else status_settle<=0;
        if(status_snapshot_commit) begin
          status_settle<=0;
          status_wait_ack<=0;status_ready<=1;st_frame_period<=status_fp_s2;
          st_target<=status_target_s2;st_motion<=status_motion_s2;st_latency<=status_latency_s2;
          st_flags<=status_flags_s2;
          st_captured<=status_captured_s2;st_overflow<=status_overflow_s2;status_sequence<=status_sequence+1'b1;
          st_app_mode<=status_app_mode_s2;st_armed<=status_armed_s2;st_peer<=status_peer_s2;
          st_last_action<=status_last_action_s2;st_action_result<=status_action_result_s2;
          st_retries<=status_retries_s2;st_uart_errors<=status_uart_errors_s2;
          if(HOST_STATUS)begin
            st_hxa_sent<=I_hxa_sent_frames;st_hxa_failed<=I_hxa_failed_frames;
            st_snapshot_frame<=I_snapshot_frame_id;st_snapshot_ms<=timestamp_ms;
            st_hxa_online<=I_hxa_online;st_hxa_job<=I_hxa_job_state;
          end
        end
        if(ENABLE_VIDEO_PREVIEW && overflow_event) begin
          overflow_seen<=overflow_sync[1];network_drop_frames<=network_drop_frames+1'b1;
          drop_until_next_sof<=1;dropped_first_sof<=current_sof_consumed;
          recovery_read_wait<=0;
          if(tx_state==T_SEND&&tx_kind==K_VIDEO) begin
            tx_abort<=1;abort_sof_consumed<=current_sof_consumed;
          end else if(tx_state==T_DONE&&tx_kind==K_VIDEO) begin
            tx_abort<=1;abort_sof_consumed<=1;
          end else begin
            frame_active<=0;
            if(tx_state==T_REQ) begin
              stack_reset_count<=3;tx_state<=T_GAP;
              if(tx_kind!=K_VIDEO) begin status_due<=1;status_v2_pending<=0;status_app_pending<=0;end
            end
          end
        end
        if(!(overflow_event&&(tx_state==T_IDLE||tx_state==T_REQ||
             (tx_state==T_DONE&&tx_kind==K_VIDEO)))) case(tx_state)
          T_IDLE:begin
            req_timeout<=0;tx_byte<=0;
            if(session_reply_valid&&!session_reply_take) begin
              session_reply_tx<=session_reply;session_reply_take<=1;
              tx_kind<=K_SESSION;W_udp_len<=32;tx_state<=T_REQ;
            end else if((!ENABLE_VIDEO_PREVIEW || !frame_active)&&status_ready) begin
              tx_kind<=K_LEGACY_STATUS;W_udp_len<=16;status_ready<=0;status_v2_pending<=1;tx_state<=T_REQ;
            end else if((!ENABLE_VIDEO_PREVIEW || !frame_active)&&status_v2_pending) begin
              tx_kind<=K_V2_STATUS;W_udp_len<=56;status_v2_pending<=0;status_app_pending<=1;tx_state<=T_REQ;
            end else if((!ENABLE_VIDEO_PREVIEW || !frame_active)&&status_app_pending) begin
              tx_kind<=K_APP_STATUS;W_udp_len<=32;status_app_pending<=0;
              status_board_pending<=HOST_STATUS;status_due<=HOST_STATUS;tx_state<=T_REQ;
            end else if(HOST_STATUS && status_board_pending)begin
              tx_kind<=K_BOARD_STATUS;W_udp_len<=48;status_board_pending<=0;status_due<=0;tx_state<=T_REQ;
            end else if(ENABLE_AWB_DIAG && awb_diag_ready && (!ENABLE_VIDEO_PREVIEW || !frame_active))begin
              tx_kind<=K_AWB;W_udp_len<=44;tx_state<=T_REQ;
            end else if(ENABLE_VIDEO_PREVIEW && !frame_active) begin
              if(fifo_valid) begin
                if(drop_until_next_sof) begin
                  // SHOW_AHEAD advances after the read edge. Leave one full
                  // clock without reasserting re so the new marker can be
                  // observed before it is consumed.
                  if(recovery_read_wait) begin
                    recovery_read_wait<=0;
                  end else if(fifo_dout[32]) begin
                    if(dropped_first_sof) begin
                      drop_until_next_sof<=0;dropped_first_sof<=0;
                    end else begin
                      dropped_first_sof<=1;fifo_re<=1;recovery_read_wait<=1;
                    end
                  end else begin
                    fifo_re<=1;recovery_read_wait<=1;
                  end
                end else if(!fifo_dout[32])fifo_re<=1;
                else if(fifo_rdusedw>=360) begin
                  frame_active<=1;have_video_frame<=1;video_frame_id<=video_frame_id+1'b1;
                  frame_timestamp_ms<=timestamp_ms;
                  frame_session_tag<=session_tag;
                  tx_packet_index<=0;tx_payload_len<=FULL_PAYLOAD;tx_kind<=K_VIDEO;
                  W_udp_len<=VIDEO_HEADER+FULL_PAYLOAD;tx_abort<=0;abort_sof_consumed<=0;
                  tx_state<=T_REQ;
                end
              end
            end else if(ENABLE_VIDEO_PREVIEW && video_packet_ready) begin
              tx_kind<=K_VIDEO;tx_payload_len<=(tx_packet_index==VIDEO_PKT_COUNT-1)?LAST_PAYLOAD:FULL_PAYLOAD;
              W_udp_len<=VIDEO_HEADER+((tx_packet_index==VIDEO_PKT_COUNT-1)?LAST_PAYLOAD:FULL_PAYLOAD);
              tx_state<=T_REQ;
            end
          end
          T_REQ:begin
            if(W_udp_busy) begin req_timeout<=0;tx_byte<=0;tx_state<=T_SEND;end
            else if(ENABLE_HOST_HXA_PREVIEW && !legacy_tx_selected)req_timeout<=0;
            else if(req_timeout>=UDP_REQUEST_TIMEOUT_CYCLES-1) begin
              req_timeout<=0;
              if(ENABLE_VIDEO_PREVIEW && tx_kind==K_VIDEO) begin
                network_drop_frames<=network_drop_frames+1'b1;frame_active<=0;
                drop_until_next_sof<=1;dropped_first_sof<=(tx_packet_index!=0);
                recovery_read_wait<=0;
              end else begin status_due<=1;status_v2_pending<=0;status_app_pending<=0;end
              stack_reset_count<=3;tx_state<=T_GAP;
            end else req_timeout<=req_timeout+1'b1;
          end
          T_SEND:begin
            if(ENABLE_VIDEO_PREVIEW && tx_kind==K_VIDEO&&tx_byte>=VIDEO_HEADER&&tx_byte[1:0]==3&&!tx_abort) begin
              fifo_re<=1;
              if(!overflow_event&&
                 ((fifo_dout[32]!=((tx_packet_index==0)&&(tx_byte==VIDEO_HEADER+3)))||
                  (fifo_dout[33]!=((tx_packet_index==VIDEO_PKT_COUNT-1)&&
                                    (tx_byte==tx_total_len-1))))) begin
                tx_abort<=1;abort_sof_consumed<=1;
                network_drop_frames<=network_drop_frames+1'b1;
              end
            end
            if(tx_byte==tx_total_len-1)tx_state<=T_DONE;else tx_byte<=tx_byte+1'b1;
          end
          T_DONE:if(!W_udp_busy) begin
            sent_packet_count<=sent_packet_count+1'b1;
            if(ENABLE_VIDEO_PREVIEW && tx_kind==K_VIDEO) begin
              if(tx_abort) begin
                frame_active<=0;drop_until_next_sof<=1;
                dropped_first_sof<=abort_sof_consumed;tx_abort<=0;abort_sof_consumed<=0;
                recovery_read_wait<=0;
              end
              else if(tx_packet_index==VIDEO_PKT_COUNT-1) begin complete_frames<=complete_frames+1'b1;frame_active<=0;end
              else tx_packet_index<=tx_packet_index+1'b1;
            end
            tx_state<=T_GAP;
          end
          T_GAP:tx_state<=T_IDLE;
          default:tx_state<=T_IDLE;
        endcase
        if(ENABLE_HOST_HXA_PREVIEW && stack_reset)begin
          // Drop a cancelled packet without resetting the CONFIG mailbox.
          tx_state<=T_IDLE;req_timeout<=0;status_due<=1;status_ready<=0;status_settle<=0;
          status_v2_pending<=0;status_app_pending<=0;status_board_pending<=0;
        end
      end
    end

endmodule

// Small store-and-forward control filter. Video remains on the independent
// transmit FIFO. A bad or busy input packet is dropped, never partially replayed.
module udp_session_guard #(
    parameter integer LEASE_CYCLES=125000000
) (
    input wire I_clk,I_reset,input wire [7:0] I_data,
    input wire I_valid,input wire [15:0] I_len,input wire I_error,
    input wire I_idle,I_epoch_ack,input wire [31:0] I_frame_id,I_timestamp,
    output reg [7:0] O_data,output reg O_valid,output reg [15:0] O_len,
    output wire O_safe,output reg O_changed,output reg O_epoch,
    output reg [13:0] O_tag,output reg [255:0] O_reply,
    output reg O_reply_valid,input wire I_reply_take
);
    localparam [2:0] WAIT=0,RECEIVE=1,CHECK=2,REPLAY=3,ACK_WAIT=4;
    reg [2:0] state;
    (* ram_style="bram" *) reg [7:0] packet_mem[0:255];
    reg [255:0] header;
    reg [8:0] count;
    reg [15:0] packet_len;
    reg [7:0] replay_at,replay_last;
    reg bad,valid_d,locked,active;
    reg [4:0] settle;
    reg [63:0] session_id;
    reg [31:0] lease,reply_request;
    reg [63:0] reply_id;
    wire [63:0] incoming_id=header[127:64];
    wire magic_ok=header[31:0]==32'h32565848&&header[39:32]==8'd2;
    wire [7:0] message_type=header[47:40];
    wire [7:0] operation=header[55:48];
    wire [13:0] requested_tag=incoming_id[13:0]==0?14'd1:incoming_id[13:0];
    assign O_safe=!locked||(active&&I_epoch_ack==O_epoch);
    wire packet_start=state==WAIT&&I_valid&&!valid_d;
    wire packet_write=packet_start||(state==RECEIVE&&I_valid&&count<256);
    wire [7:0] packet_addr=packet_start?8'd0:count[7:0];
    // One canonical write port and a registered read port allow RAM inference.
    // The RAM is not reset; validity/count prevent reads of unwritten bytes.
    always @(posedge I_clk) begin
      if(packet_write)packet_mem[packet_addr]<=I_data;
      O_data<=packet_mem[replay_at];
    end

    task reply;
      input [7:0] result;
      input [63:0] sid;
      input [31:0] request;
      begin
        O_reply<={18'd0,O_tag,I_timestamp,I_frame_id,request,sid,
                   8'd32,result,8'd8,8'd2,32'h32565848};
        O_reply_valid<=1;
      end
    endtask

    always @(posedge I_clk or posedge I_reset) begin
      if(I_reset) begin
        state<=WAIT;header<=0;count<=0;packet_len<=0;replay_at<=0;replay_last<=0;
        bad<=0;valid_d<=0;locked<=0;active<=0;settle<=0;session_id<=0;lease<=0;
        O_valid<=0;O_len<=0;O_changed<=0;O_epoch<=0;O_tag<=0;
        O_reply<=0;O_reply_valid<=0;reply_request<=0;reply_id<=0;
      end else begin
        valid_d<=I_valid;O_valid<=0;O_changed<=0;
        if(I_reply_take) O_reply_valid<=0;
        if(active&&I_epoch_ack==O_epoch) begin
          if(lease>=LEASE_CYCLES-1) begin
            active<=0;lease<=0;O_epoch<=~O_epoch;O_changed<=1;
          end else lease<=lease+1'b1;
        end
        case(state)
          WAIT:if(I_valid&&!valid_d) begin
            header<={I_data,248'd0};
            packet_len<=I_len;count<=1;bad<=I_error||(I_len>256)||(I_len<4);
            state<=RECEIVE;
          end
          RECEIVE:begin
            if(I_error)bad<=1;
            if(I_valid) begin
              if(count<256) begin
                if(count<32)header<={I_data,header[255:8]};
                count<=count+1'b1;
              end else bad<=1;
            end else begin
              if(count!=packet_len)bad<=1;
              settle<=0;state<=CHECK;
            end
          end
          CHECK:begin
            if(I_error)bad<=1;
            if(settle<24) begin settle<=settle+1'b1;end
            else if(bad||I_error) state<=WAIT;
            else if(magic_ok&&message_type==7&&packet_len==32&&header[63:56]==32) begin
              if(O_reply_valid||!I_idle||I_epoch_ack!=O_epoch) state<=WAIT;
              else if(incoming_id==0||(operation!=1&&operation!=2))state<=WAIT;
              else if(active&&incoming_id==session_id&&lease<LEASE_CYCLES-1) begin
                lease<=0;reply(1,incoming_id,header[159:128]);state<=WAIT;
              end else if(active) begin
                reply(2,incoming_id,header[159:128]);state<=WAIT;
              end else if(operation==2||incoming_id==session_id) begin
                reply(3,incoming_id,header[159:128]);state<=WAIT;
              end else begin
                session_id<=incoming_id;locked<=1;active<=1;lease<=0;
                O_tag<=(requested_tag==O_tag)?((O_tag==16383)?14'd1:O_tag+1'b1):requested_tag;
                O_epoch<=~O_epoch;O_changed<=1;
                reply_id<=incoming_id;reply_request<=header[159:128];state<=ACK_WAIT;
              end
            end else if(magic_ok&&message_type==9) begin
              if(O_safe&&active&&incoming_id==session_id&&packet_len>=32&&
                 packet_len<=200&&header[63:48]==packet_len-16&&
                 header[159:128]==32'h32565848&&header[167:160]==2&&
                 (header[175:168]==3||header[175:168]==4||header[175:168]==5)) begin
                replay_at<=16;replay_last<=packet_len-1;
                O_len<=packet_len-16;state<=REPLAY;
              end else state<=WAIT;
            end else if(!locked&&packet_len<=184) begin
              replay_at<=0;replay_last<=packet_len-1;O_len<=packet_len;state<=REPLAY;
            end else state<=WAIT;
          end
          ACK_WAIT:if(I_epoch_ack==O_epoch) begin
            reply(1,reply_id,reply_request);state<=WAIT;
          end
          REPLAY:begin
            if(O_safe) begin
              O_valid<=1;
              if(replay_at==replay_last)state<=WAIT;
              else replay_at<=replay_at+1'b1;
            end else state<=WAIT;
          end
          default:state<=WAIT;
        endcase
      end
    end
endmodule

