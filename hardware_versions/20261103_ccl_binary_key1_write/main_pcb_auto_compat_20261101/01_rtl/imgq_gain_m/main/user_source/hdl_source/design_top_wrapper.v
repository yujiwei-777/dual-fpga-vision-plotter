

module design_top_wrapper (
    input wire        I_sys_clk,
    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,
      
    input wire [3:0]  I_button,      // KEY1=D5, KEY2=A9, KEY3=B9, KEY4=C7
    input wire        I_sw1,         // SW1 (A4): motion overlay display
    input wire        I_sw2,         // SW2 (B4): stage/recognition overlay display
    input wire        I_sw3,         // SW3 (E11): mode bit 0
    input wire        I_sw4,         // SW4 (D11): mode bit 1
    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p,

    input wire [3:0]  I_rgmii_rxd,
    input wire        I_rgmii_rx_ctl,
    input wire        I_rgmii_rxc,
    output wire [3:0] O_rgmii_txd,
    output wire       O_rgmii_tx_ctl,
    output wire       O_rgmii_txc,
    output wire       O_phy_rst,

    inout wire        IO_rx_clk_pad_n, 
    inout wire        IO_rx_clk_pad_p, 
    inout wire[3:0]   IO_rx_data_pad_n,
    inout wire[3:0]   IO_rx_data_pad_p,

    output wire[12:0] ddr_addr,
    output wire[ 1:0] ddr_ba,
    output wire[ 0:0] ddr_cke,
    output wire[ 0:0] ddr_odt,
    output wire[ 0:0] ddr_cs_n,
    output wire       ddr_ras_n,
    output wire       ddr_cas_n,
    output wire       ddr_we_n,
    output wire[ 0:0] ddr_ck_p,
    output wire[ 0:0] ddr_ck_n,
    inout wire[1:0]   ddr_dm,
    inout wire[15:0]  ddr_dq,
    inout wire[1:0]   ddr_dqs_p,
    inout wire[1:0]   ddr_dqs_n   
);


    wire        	S_100m_clk;
    wire        	S_24m_clk;
    wire        	S_aux_50m_clk;
	wire        	S_10m_clk;
		
	wire        	S_pll_lock;
    wire        	S_rst_n;
	
	wire [15:0] 	S_ae;
    wire [15:0] 	S_ag;
    wire [8:0] S_dg; // Sensor global digital gain command, Q7 (128..256).
    wire 			S_cam_cfg_done;
    wire 			S_ae_cfg_done;
    wire 			S_ae_req; 
	
	wire        	S_csi_rx_clk;  
    wire        	S_hs_rx_valid;  
    wire[15:0]  	S_hs_rx_data;   
	wire[1:0]   	S_lane_error;
	
	wire        	S_csi_frame_start;       
	wire        	S_csi_frame_end;         
	wire        	S_csi_valid;             
	wire[31:0]  	S_csi_data;  
		
	wire        	S_raw10_frame_start; 
	wire        	S_raw10_frame_end;   
	wire        	S_raw10_valid;       
	wire [39:0] 	S_raw10_data;
		
	wire 			S_axis_tlast;  
	wire 			S_axis_tuser;  
	wire [39:0]		S_axis_tdata;  
	wire 			S_axis_tvalid; 
	
	wire [39:0]		S_raw_tdata ;
	wire			S_raw_tlast ;
	wire 			S_raw_tvalid;
	wire 			S_raw_tuser ;
	wire [39:0]		S_guard_tdata;
	wire			S_guard_tlast;
	wire			S_guard_tvalid;
	wire			S_guard_tuser;
	wire [39:0]		S_blc_tdata;
	wire [9:0]		S_blc_tdest;
	wire			S_blc_tready;
	wire			S_blc_tlast;
	wire			S_blc_tvalid;
	wire			S_blc_tuser;
	wire			S_guard_frame_active;
	wire			S_guard_frame_error;
	wire [9:0]		S_guard_line_count;
	wire [15:0]		S_guard_group_count;
	wire			S_guard_frame_done;
	
	wire			S_ISP_O_tready;
	wire [127:0]	S_ISP_O_tdata ;
	wire 			S_ISP_O_tlast ;
	wire 			S_ISP_O_tuser ;
	wire 			S_ISP_O_tvalid; 
	// ISP statistics are produced in S_csi_rx_clk.  Keep a synchronized copy
	// for ae_auto in S_24m_clk; the source data is held until the toggle moves.
	wire [8:0] 	S_luma_raw_avg;
	wire [8:0] 	S_luma_raw_clip;
    wire [8:0] S_luma_raw_roi_all;
	wire 		S_luma_raw_get;
	reg  [8:0] 	S_luma_avg;
	reg  [8:0] 	S_luma_clip;
    reg [8:0] S_luma_roi_all;
    // Keep the frame-capture toggle as a physical stage.  Without this
    // attribute TD legally folds it into the equivalent delayed source edge,
    // which would remove the explicit stable-bus capture point audited below.
    (* keep = "true" *) reg 		S_luma_get;

    wire        S_ddr_clk;
    wire        S_hdmi_pixel_clk;
    wire        S_hdmi_serial_clk;
    wire        S_hdmi_rst_n;
    wire        S_video_out_rst_n;


    wire        S_vi_128b_frame_start;
    wire        S_vi_128b_valid;      
    wire[127:0] S_vi_128b_data;    
    
    wire        S_video_out_rd_busy;
    wire        S_video_in_wr_busy; 
    wire[1:0]   S_video_out_rp;     

    wire        S_ddr_user_wr_en;       
    wire        S_ddr_user_rd_en;       
    wire[24:0]  S_ddr_user_addr;        
    wire[127:0] S_ddr_user_wr_data;     
    wire        S_ddr_user_ready;       
    wire        S_ddr_user_rd_valid;    
    wire[127:0] S_ddr_user_rd_data;     

    wire        S_vi_ddr_wr_en;   
    wire[24:0]  S_vi_ddr_wr_addr; 
    wire[127:0] S_vi_ddr_wr_data;
    wire        S_vi_ddr_wr_ready;

    wire        S_vo_ddr_rd_en;   
    wire[24:0]  S_vo_ddr_rd_addr; 
    wire        S_vo_ddr_rd_ready;
    wire        S_vo_dbg_fifo_rst;
    wire        S_vo_dbg_ddr_rd_valid;
    wire        S_vo_dbg_fifo_rd_en;
    wire        S_vo_dbg_fifo_empty;

    wire        S_init_calib_complete; 
    wire[24:0]  S_mc_app_addr;          
    wire[2:0]   S_mc_app_cmd;           
    wire        S_mc_app_en;            
    wire[127:0] S_mc_app_wdf_data;      
    wire        S_mc_app_wdf_end;       
    wire[15:0]  S_mc_app_wdf_mask;      
    wire        S_mc_app_wdf_wren;      
    wire[127:0] S_mc_app_rd_data;       
    wire        S_mc_app_rd_data_end;   
    wire        S_mc_app_rd_data_valid; 
    wire        S_mc_app_rdy;           
    wire        S_mc_app_wdf_rdy;       
    wire        S_mc_dbg_fifo_afull;
    wire        S_mc_dbg_app_rdy;
    wire        S_mc_dbg_wdf_rdy;
    wire        S_mc_dbg_cmd_pop;

    wire        S_hdmi_vsync;
    wire        S_hdmi_hsync;
    wire        S_hdmi_de;
    wire        S_hdmi_user;
    wire        S_hdmi_last;
    wire        S_video_out_vsync;
    wire        S_hdmi_window_rd_en;
    wire        S_hdmi_out_vsync;
    wire        S_hdmi_out_hsync;
    wire        S_hdmi_out_de;
    wire[23:0]  S_hdmi_out_data;
    wire        S_badge_out_vsync;
    wire        S_badge_out_hsync;
    wire        S_badge_out_de;
    wire        S_badge_out_user;
    wire        S_badge_out_last;
    wire [23:0] S_badge_out_data;

    // Shared Ethernet control/HXA1 transport with an optional legacy preview.
    wire S_125m_clk, S_125m_90_clk, S_125m_90_clk_b, S_eth_pll_lock, S_eth_rst_n;
    wire [4:0] S_eth_mode;
    wire [7:0] S_eth_threshold, S_eth_brightness;
    wire [1:0] S_eth_target_color;
    wire S_eth_detect_en, S_eth_heq_en, S_eth_cnn_mode, S_eth_auto_quality;
    wire S_eth_awb_en, S_eth_ae_en, S_eth_ag_en, S_eth_quality_heq_en, S_eth_cfg_valid;
    wire [2:0] S_eth_app_mode; wire S_eth_app_mode_valid, S_eth_session_ready;
    wire [31:0] S_eth_cnn_frame_id, S_eth_cnn_inference_us;
    wire [3:0] S_eth_cnn_target_num; wire [383:0] S_eth_cnn_bbox;
    wire [127:0] S_eth_cnn_class_id; wire [63:0] S_eth_cnn_confidence, S_eth_cnn_flags;
    wire [511:0] S_eth_cnn_label; wire S_eth_cnn_valid, S_eth_cnn_heartbeat;
    wire [31:0] S_eth_action_sequence, S_eth_action_frame_id;
    wire [1:0] S_eth_action_app_mode; wire [7:0] S_eth_action_id, S_eth_action_confidence, S_eth_action_evidence;
    wire [15:0] S_eth_action_ttl_ms, S_eth_action_cooldown_ms, S_eth_action_flags;
    wire [63:0] S_eth_action_label; wire S_eth_action_valid;
    reg S_sw2_eth_s1, S_sw2_eth_s2;
    reg S_sw3_eth_s1, S_sw3_eth;
    reg S_sw4_eth_s1, S_sw4_eth_s2;
    // KEY1 is active-low. Synchronize it into the HXA1 clock domain and
    // emit one debounced pulse per press for ordinary-CNN result reporting.
    reg S_key1_eth_s1,S_key1_eth_s2,S_key1_eth_d;
    reg [21:0] S_key1_lock;
    reg S_key1_report_pulse, S_key1_text_pulse;
    // This variant has no PC control/preview role. Ethernet is permanently
    // assigned to the auxiliary vision board; SW2 is display-only.
    wire S_eth_host_mode = 1'b0;
    wire S_eth_link_rst_n = S_eth_rst_n;
    wire S_eth_preview_rst_n = S_eth_rst_n;
    wire [1:0] S_mode_sel_eth = {S_sw4_eth_s2,S_sw3_eth};
    wire S_mode_cnn_eth  = (S_mode_sel_eth==2'd0);
    wire S_mode_pcb_eth  = (S_mode_sel_eth==2'd1);
    wire S_mode_text_eth = (S_mode_sel_eth==2'd2);
    // Mode 11 is reserved: A4 distance capture was removed in this variant.
    // KEY4 only authorizes a single PCB task. Its stable press is synchronized
    // and debounced in the link clock domain; release never cancels a task.
    wire S_pcb_detect_en_eth = S_mode_pcb_eth;
    wire S_pcb_key4_press;
    wire [2:0] S_pcb_status_eth,S_pcb_status_px;
    key4_pcb_oneshot #(.DEBOUNCE_CYCLES(2500000)) u_key4_pcb_oneshot (
        .clk(S_125m_clk),.rst_n(S_eth_rst_n),.key_n(I_button[3]),
        .mode_active(S_mode_pcb_eth),.press_pulse(S_pcb_key4_press),
        .pressed(),.armed());
    always @(posedge S_125m_clk or negedge S_eth_rst_n) begin
        if(!S_eth_rst_n) begin
            S_sw2_eth_s1<=1'b0; S_sw2_eth_s2<=1'b0;
            S_sw3_eth_s1<=1'b0; S_sw3_eth<=1'b0;
            S_sw4_eth_s1<=1'b0; S_sw4_eth_s2<=1'b0;
            S_key1_eth_s1<=1'b1; S_key1_eth_s2<=1'b1; S_key1_eth_d<=1'b1;
            S_key1_lock<=22'd0; S_key1_report_pulse<=1'b0; S_key1_text_pulse<=1'b0;
        end else begin
            S_sw2_eth_s1<=I_sw2; S_sw2_eth_s2<=S_sw2_eth_s1;
            S_sw3_eth_s1<=I_sw3; S_sw3_eth<=S_sw3_eth_s1;
            S_sw4_eth_s1<=I_sw4; S_sw4_eth_s2<=S_sw4_eth_s1;
            S_key1_eth_s1<=I_button[0]; S_key1_eth_s2<=S_key1_eth_s1;
            S_key1_eth_d<=S_key1_eth_s2;
            S_key1_report_pulse<=1'b0;
            S_key1_text_pulse<=1'b0;
            if(S_key1_lock!=0) S_key1_lock<=S_key1_lock-1'b1;
            // Falling edge is a press. Twenty milliseconds of lockout
            // suppresses mechanical bounce without delaying the request.
            if(S_key1_eth_d && !S_key1_eth_s2 && S_key1_lock==0)begin
                if((S_sw4_eth_s2==1'b0)&&(S_sw3_eth==1'b0)) S_key1_report_pulse<=1'b1;
                else if((S_sw4_eth_s2==1'b1)&&(S_sw3_eth==1'b0)) S_key1_text_pulse<=1'b1;
                S_key1_lock<=22'd2500000;
            end
        end
    end

    // Network configuration is committed in udp_config_status' pixel clock
    // domain.  Keep a local shadow copy here and only apply it while SW2 is
    // in host mode.  The shadow registers make a CONFIG packet an atomic
    // update at the frame boundary instead of allowing individual fields to
    // change while a frame is being processed.
    reg        S_sw2_px_s1, S_sw2_px_s2;
    reg        S_sw3_px_s1, S_sw3_px_s2;
    wire [4:0] S_eth_mode_px;
    reg [7:0]  S_eth_threshold_px, S_eth_brightness_px;
    reg [1:0]  S_eth_target_color_px;
    reg        S_eth_detect_px, S_eth_heq_px, S_eth_awb_px, S_eth_ae_px, S_eth_ag_px;
    reg        S_eth_cfg_seen_px;
    wire       S_eth_host_mode_px = 1'b0;
    reg S_sw4_px_s1, S_sw4_px_s2;
    wire [1:0] S_mode_sel_px = {S_sw4_px_s2,S_sw3_px_s2};
    wire S_mode_cnn_px=(S_mode_sel_px==2'd0);
    wire S_mode_pcb_px=(S_mode_sel_px==2'd1);
    wire S_mode_text_px=(S_mode_sel_px==2'd2);
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_sw2_px_s1 <= 1'b0; S_sw2_px_s2 <= 1'b0;
            S_sw3_px_s1 <= 1'b0; S_sw3_px_s2 <= 1'b0;
            S_sw4_px_s1 <= 1'b0; S_sw4_px_s2 <= 1'b0;
            S_eth_threshold_px <= 8'd128;
            S_eth_brightness_px <= 8'd128; S_eth_target_color_px <= 2'd0;
            S_eth_detect_px <= 1'b0; S_eth_heq_px <= 1'b0;
            S_eth_awb_px <= 1'b0; S_eth_ae_px <= 1'b0; S_eth_ag_px <= 1'b0;
            S_eth_cfg_seen_px <= 1'b0;
        end else begin
            S_sw2_px_s1 <= I_sw2;
            S_sw2_px_s2 <= S_sw2_px_s1;
            S_sw3_px_s1 <= I_sw3;
            S_sw3_px_s2 <= S_sw3_px_s1;
            S_sw4_px_s1 <= I_sw4;
            S_sw4_px_s2 <= S_sw4_px_s1;
            if (S_eth_host_mode_px && S_eth_cfg_valid) begin
                S_eth_threshold_px <= S_eth_threshold;
                S_eth_brightness_px <= S_eth_brightness;
                S_eth_target_color_px <= S_eth_target_color;
                S_eth_detect_px <= S_eth_detect_en;
                S_eth_heq_px <= S_eth_heq_en;
                S_eth_awb_px <= S_eth_awb_en;
                S_eth_ae_px <= S_eth_ae_en;
                S_eth_ag_px <= S_eth_ag_en;
                S_eth_cfg_seen_px <= ~S_eth_cfg_seen_px;
            end
            // Leaving host mode invalidates the network shadow.  This avoids
            // stale PC settings taking effect after a later SW2 transition.
            if (!S_eth_host_mode_px)
                S_eth_cfg_seen_px <= 1'b0;
        end
    end

    // The camera/ISP clock is independent from the HDMI and Ethernet clocks.
    // Synchronise the stable shadow fields with two flip-flops.  Since fields
    // only change after a packet commit, the two-cycle settling interval is
    // sufficient and no per-pixel CDC is introduced.
    // SW1 synchronized into the CSI/ISP clock domain (declared here because
    // the effective detection enable below is used before the overlay block).
    reg       S_sw1_rx_s1, S_sw1_rx_s2;
    (* ASYNC_REG = "TRUE" *) reg S_eth_detect_csi_s1;
    reg       S_eth_detect_csi_s2;
    reg       S_host_csi_s1, S_host_csi_s2;
    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_eth_detect_csi_s1 <= 1'b0; S_eth_detect_csi_s2 <= 1'b0;
            S_host_csi_s1 <= 1'b0; S_host_csi_s2 <= 1'b0;
        end else begin
            // Reuse the existing two-stage CSI synchronizer for the shared
            // detection gate. PCB capture authorization stays in the Ethernet
            // domain and is independent of this local image detector enable.
            S_eth_detect_csi_s1 <= S_eth_detect_px | S_mode_cnn_eth | S_pcb_detect_en_eth;
            S_eth_detect_csi_s2 <= S_eth_detect_csi_s1;
            S_host_csi_s1 <= S_eth_host_mode_px;
            S_host_csi_s2 <= S_host_csi_s1;
        end
    end
    // KEY3 restores only the style selection; ISP quality and link state survive.
    // This diagnostic variant restores the existing runtime display style selection.
    // Keep existing style exclusions and independent clean CNN/Tone output.
    localparam integer ORIGINAL_MODE_ENABLE = 0;
    wire [4:0] S_style_mode_eff;
    wire [4:0] S_style_mode_isp = ORIGINAL_MODE_ENABLE ? 5'd0 : S_style_mode_eff;
    style_controls #(.CARTOON_ENABLE(1'b1)) u_style_controls(
        .I_clk(S_csi_rx_clk),.I_rst_n(S_rst_n),
        .I_key2_n(I_button[1]),.I_key3_n(I_button[2]),.I_host_mode(S_host_csi_s2),
        .I_host_clk(S_hdmi_pixel_clk),.I_host_rst_n(S_hdmi_rst_n),
        .I_host_valid(S_eth_host_mode_px && S_eth_cfg_valid),.I_host_style(S_eth_mode),
        .O_style(S_style_mode_eff),.O_restore_busy(),.O_host_shadow(S_eth_mode_px));
    // Detection is an OR of the two enables: SW1 can enable the local path
    // and the host can independently enable it, with frame-boundary latching
    // below keeping the overlay atomic.
    wire       S_detect_en_eff  = S_mode_cnn_eth | S_pcb_detect_en_eth;
    // The optional legacy preview taps S_mix_data, which is wired to the
    // DDR video read data below, before HDMI overlays. PC image capture in
    // this candidate uses the existing HXA1 snapshot path with SW2=0.
    localparam integer ENABLE_VIDEO_PREVIEW = 0;
    localparam integer ENABLE_HOST_HXA_PREVIEW = 0;
    wire [23:0] S_mix_data;
    wire S_mix_de;
    wire [23:0] S_net_pix;
    wire S_net_de,S_net_sof,S_net_eof;
    generate
      if (ENABLE_VIDEO_PREVIEW) begin : g_net_preview
        reg [10:0] net_x;
        reg [9:0] net_y;
        assign S_net_pix = S_mix_data;
        assign S_net_de = S_mix_de;
        assign S_net_sof = S_net_de && (net_x==11'd0) && (net_y==10'd0);
        assign S_net_eof = S_net_de && (net_x==11'd1279) && (net_y==10'd719);
        always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
          if(!S_hdmi_rst_n) begin net_x<=0; net_y<=0; end
          else if(S_net_de) begin
            if(S_net_eof) begin net_x<=0; net_y<=0; end
            else if(net_x==11'd1279) begin net_x<=0; net_y<=net_y+1'b1; end
            else net_x<=net_x+1'b1;
          end
        end
      end else begin : g_no_net_preview
        assign S_net_pix = 24'd0;
        assign S_net_de = 1'b0;
        assign S_net_sof = 1'b0;
        assign S_net_eof = 1'b0;
      end
    endgenerate

    wire[23:0]  S_video_rd_data;
    // Passive frame-identity/latency observations. These never feed the
    // camera, DDR arbitration, display timing, or network pixel paths.
    wire S_latency_capture_overflow;
    wire S_latency_vo_frame_start, S_latency_vo_reset, S_latency_vo_burst;
    wire S_latency_vo_underflow;
    wire [1:0] S_latency_vo_bank;
    wire [10:0] S_latency_vo_pending;
    wire S_latency_valid, S_latency_toggle;
    wire [15:0] S_latency_frame, S_latency_tenth_ms;
    reg         S_dbg_raw_seen;
    reg         S_dbg_isp_seen;
    reg         S_dbg_ddr_wr_seen;
    reg         S_dbg_ddr_rd_seen;
    reg         S_dbg_cam_cfg_seen;
    reg         S_dbg_hs_seen;
    reg         S_dbg_csi_seen;
    reg         S_dbg_raw10_seen;
    reg         S_dbg_isp_fs_seen;
    reg         S_dbg_isp_valid_seen;
    reg         S_dbg_ddr_req_seen;
    reg         S_dbg_ddr_ready_seen;
    reg [1:0]   S_dbg_raw_seen_sync;
    reg [1:0]   S_dbg_isp_seen_sync;
    reg [1:0]   S_dbg_ddr_wr_seen_sync;
    reg [1:0]   S_dbg_ddr_rd_seen_sync;
    reg [1:0]   S_dbg_cam_cfg_seen_sync;
    reg [1:0]   S_dbg_hs_seen_sync;
    reg [1:0]   S_dbg_csi_seen_sync;
    reg [1:0]   S_dbg_raw10_seen_sync;
    reg [1:0]   S_dbg_isp_fs_seen_sync;
    reg [1:0]   S_dbg_isp_valid_seen_sync;
    reg [1:0]   S_dbg_ddr_req_seen_sync;
    reg [1:0]   S_dbg_ddr_ready_seen_sync;
    reg         S_dbg_video_nonzero_seen;
    reg         S_dbg_rd_req_seen;
    reg         S_dbg_rd_valid_seen;
    reg         S_dbg_rd_nonzero_seen;
    reg [1:0]   S_dbg_rd_req_seen_sync;
    reg [1:0]   S_dbg_rd_valid_seen_sync;
    reg [1:0]   S_dbg_rd_nonzero_seen_sync;
    reg         S_dbg_mc_init_seen;
    reg         S_dbg_mc_app_rdy_seen;
    reg         S_dbg_mc_wdf_rdy_seen;
    reg         S_dbg_mc_cmd_pop_seen;
    reg [1:0]   S_dbg_mc_init_seen_sync;
    reg [1:0]   S_dbg_mc_app_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_wdf_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_cmd_pop_seen_sync;
    wire[3:0]   S_hdmi_debug_status;
    wire        S_lane_error_any;


    assign S_video_out_vsync = ~S_hdmi_vsync;
	
	
    // Asynchronous assert, synchronous release.  Assertion follows the PLL lock
    // immediately; release is aligned to a stable clock so each domain sees a
    // clean, glitch-free de-assert (avoids recovery/removal violations that the
    // previous "release straight from PLL lock" could cause on power-up/reset).
    // Keep both release stages visible in the mapped netlist.  The timing
    // tool previously collapsed the second HDMI stage into the first stage's
    // reset net, which made the reset audit unable to prove the intended
    // asynchronous-assert/synchronous-release chain.
    (* ASYNC_REG = "TRUE", keep = "true" *) reg S_rst_sync1, S_rst_sync2;
    always @(posedge S_24m_clk or negedge S_pll_lock) begin
        if (!S_pll_lock) begin S_rst_sync1 <= 1'b0; S_rst_sync2 <= 1'b0; end
        else begin S_rst_sync1 <= 1'b1; S_rst_sync2 <= S_rst_sync1; end
    end
    assign S_rst_n = S_rst_sync2;

    // Vendor PHY wrappers (MIPI D-PHY, DDR PHY) must be released from an
    // ASYNCHRONOUS reset.  Their internal flops sample the reset release with
    // pll_clk_100m / sys_clk_50m, and those clocks live in the SAME SDC clock
    // group as pll_clk_24m -- so a flop-launched reset becomes a timed
    // 24m -> 50m path inside the PHY (85 hold violations, WNS -955ps, all on
    // DDR PHY init/training registers, plus 3 near-budget D-PHY paths).
    // Feeding them the raw PLL lock keeps the release asynchronous (no launch
    // clock, hence un-timed) exactly as it was before the reset-ordering tweak,
    // while the user logic below still gets the glitch-free sync release.
    wire S_phy_rst_n;
    assign S_phy_rst_n = S_pll_lock;

    (* ASYNC_REG = "TRUE", keep = "true" *) reg S_hdmi_rst_sync1, S_hdmi_rst_sync2;
    always @(posedge S_hdmi_pixel_clk or negedge S_pll_lock) begin
        if (!S_pll_lock) begin S_hdmi_rst_sync1 <= 1'b0; S_hdmi_rst_sync2 <= 1'b0; end
        else begin S_hdmi_rst_sync1 <= 1'b1; S_hdmi_rst_sync2 <= S_hdmi_rst_sync1; end
    end
    assign S_hdmi_rst_n = S_hdmi_rst_sync2;

    // Cycle-identical copy of the existing pixel-domain second release stage.
    // Only serializer shift registers and ODDR reset pins use this branch.
    (* ASYNC_REG = "TRUE", dont_touch = "true" *) reg S_hdmi_serializer_rst_sync2;
    always @(posedge S_hdmi_pixel_clk or negedge S_pll_lock) begin
        if (!S_pll_lock) S_hdmi_serializer_rst_sync2 <= 1'b0;
        else S_hdmi_serializer_rst_sync2 <= S_hdmi_rst_sync1;
    end

    // Cross the serializer reset into the 375 MHz serial clock domain before
    // driving the lane ODDR reset pins.  The prior pixel-domain signal was
    // fanned out directly into all four lanes, creating a pixel-to-serial
    // setup path.  Keep asynchronous assertion from PLL lock, but release in
    // two serial-clock stages so the lane reset is local to its clock domain.
    (* ASYNC_REG = "TRUE", dont_touch = "true" *) reg S_hdmi_serializer_rst_serial_sync1;
    (* ASYNC_REG = "TRUE", dont_touch = "true" *) reg S_hdmi_serializer_rst_serial_sync2;
    always @(posedge S_hdmi_serial_clk or negedge S_pll_lock) begin
        if (!S_pll_lock) begin
            S_hdmi_serializer_rst_serial_sync1 <= 1'b0;
            S_hdmi_serializer_rst_serial_sync2 <= 1'b0;
        end else begin
            S_hdmi_serializer_rst_serial_sync1 <= S_hdmi_serializer_rst_sync2;
            S_hdmi_serializer_rst_serial_sync2 <= S_hdmi_serializer_rst_serial_sync1;
        end
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw_seen <= 1'b0;
        else if(S_raw10_frame_start | S_axis_tvalid)
            S_dbg_raw_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_seen <= 1'b0;
        else if(S_ISP_O_tuser | S_ISP_O_tvalid)
            S_dbg_isp_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_wr_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_wr_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_rd_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_ddr_rd_seen <= 1'b1;
    end

    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_cam_cfg_seen <= 1'b0;
        else if(S_cam_cfg_done)
            S_dbg_cam_cfg_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_hs_seen <= 1'b0;
        else if(S_hs_rx_valid)
            S_dbg_hs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_csi_seen <= 1'b0;
        else if(S_csi_frame_start | S_csi_valid)
            S_dbg_csi_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw10_seen <= 1'b0;
        else if(S_raw10_frame_start | S_raw10_valid)
            S_dbg_raw10_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_fs_seen <= 1'b0;
        else if(S_ISP_O_tuser)
            S_dbg_isp_fs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_valid_seen <= 1'b0;
        else if(S_ISP_O_tvalid)
            S_dbg_isp_valid_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_req_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_ready_seen <= 1'b0;
        else if(S_ddr_user_ready)
            S_dbg_ddr_ready_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_vo_ddr_rd_en)
            S_dbg_rd_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_rd_valid_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
            S_dbg_rd_nonzero_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_init_seen <= 1'b0;
        else if(S_init_calib_complete)
            S_dbg_mc_init_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_app_rdy_seen <= 1'b0;
        else if(S_mc_dbg_app_rdy)
            S_dbg_mc_app_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_wdf_rdy_seen <= 1'b0;
        else if(S_mc_dbg_wdf_rdy)
            S_dbg_mc_wdf_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_cmd_pop_seen <= 1'b0;
        else if(S_mc_dbg_cmd_pop)
            S_dbg_mc_cmd_pop_seen <= 1'b1;
    end

    // Keep both HDMI reset stages observable.  The combined condition is
    // equivalent to S_hdmi_rst_n during normal operation, while the first
    // stage remains a real asynchronous reset fanout for auditability.
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_sync1) begin
        if(!S_hdmi_rst_sync1) begin
            S_dbg_cam_cfg_seen_sync <= 2'b00;
            S_dbg_hs_seen_sync      <= 2'b00;
            S_dbg_csi_seen_sync     <= 2'b00;
            S_dbg_raw10_seen_sync   <= 2'b00;
            S_dbg_raw_seen_sync    <= 2'b00;
            S_dbg_isp_seen_sync    <= 2'b00;
            S_dbg_ddr_wr_seen_sync <= 2'b00;
            S_dbg_ddr_rd_seen_sync <= 2'b00;
            S_dbg_isp_fs_seen_sync  <= 2'b00;
            S_dbg_isp_valid_seen_sync <= 2'b00;
            S_dbg_ddr_req_seen_sync <= 2'b00;
            S_dbg_ddr_ready_seen_sync <= 2'b00;
            S_dbg_video_nonzero_seen <= 1'b0;
            S_dbg_rd_req_seen_sync <= 2'b00;
            S_dbg_rd_valid_seen_sync <= 2'b00;
            S_dbg_rd_nonzero_seen_sync <= 2'b00;
            S_dbg_mc_init_seen_sync <= 2'b00;
            S_dbg_mc_app_rdy_seen_sync <= 2'b00;
            S_dbg_mc_wdf_rdy_seen_sync <= 2'b00;
            S_dbg_mc_cmd_pop_seen_sync <= 2'b00;
        end
        else if(!S_hdmi_rst_sync2) begin
            // The one-cycle release gap is intentionally visible only in the
            // diagnostic status register, preventing reset-stage collapse.
            S_dbg_cam_cfg_seen_sync <= 2'b01;
            S_dbg_hs_seen_sync      <= 2'b00;
            S_dbg_csi_seen_sync     <= 2'b00;
            S_dbg_raw10_seen_sync   <= 2'b00;
            S_dbg_raw_seen_sync    <= 2'b00;
            S_dbg_isp_seen_sync    <= 2'b00;
            S_dbg_ddr_wr_seen_sync <= 2'b00;
            S_dbg_ddr_rd_seen_sync <= 2'b00;
            S_dbg_isp_fs_seen_sync  <= 2'b00;
            S_dbg_isp_valid_seen_sync <= 2'b00;
            S_dbg_ddr_req_seen_sync <= 2'b00;
            S_dbg_ddr_ready_seen_sync <= 2'b00;
            S_dbg_video_nonzero_seen <= 1'b0;
            S_dbg_rd_req_seen_sync <= 2'b00;
            S_dbg_rd_valid_seen_sync <= 2'b00;
            S_dbg_rd_nonzero_seen_sync <= 2'b00;
            S_dbg_mc_init_seen_sync <= 2'b00;
            S_dbg_mc_app_rdy_seen_sync <= 2'b00;
            S_dbg_mc_wdf_rdy_seen_sync <= 2'b00;
            S_dbg_mc_cmd_pop_seen_sync <= 2'b00;
        end
        else begin
            S_dbg_cam_cfg_seen_sync <= {S_dbg_cam_cfg_seen_sync[0], S_dbg_cam_cfg_seen};
            S_dbg_hs_seen_sync      <= {S_dbg_hs_seen_sync[0],      S_dbg_hs_seen};
            S_dbg_csi_seen_sync     <= {S_dbg_csi_seen_sync[0],     S_dbg_csi_seen};
            S_dbg_raw10_seen_sync   <= {S_dbg_raw10_seen_sync[0],   S_dbg_raw10_seen};
            S_dbg_raw_seen_sync    <= {S_dbg_raw_seen_sync[0],    S_dbg_raw_seen};
            S_dbg_isp_seen_sync    <= {S_dbg_isp_seen_sync[0],    S_dbg_isp_seen};
            S_dbg_ddr_wr_seen_sync <= {S_dbg_ddr_wr_seen_sync[0], S_dbg_ddr_wr_seen};
            S_dbg_ddr_rd_seen_sync <= {S_dbg_ddr_rd_seen_sync[0], S_dbg_ddr_rd_seen};
            S_dbg_isp_fs_seen_sync  <= {S_dbg_isp_fs_seen_sync[0],  S_dbg_isp_fs_seen};
            S_dbg_isp_valid_seen_sync <= {S_dbg_isp_valid_seen_sync[0], S_dbg_isp_valid_seen};
            S_dbg_ddr_req_seen_sync <= {S_dbg_ddr_req_seen_sync[0], S_dbg_ddr_req_seen};
            S_dbg_ddr_ready_seen_sync <= {S_dbg_ddr_ready_seen_sync[0], S_dbg_ddr_ready_seen};
            S_dbg_rd_req_seen_sync <= {S_dbg_rd_req_seen_sync[0], S_dbg_rd_req_seen};
            S_dbg_rd_valid_seen_sync <= {S_dbg_rd_valid_seen_sync[0], S_dbg_rd_valid_seen};
            S_dbg_rd_nonzero_seen_sync <= {S_dbg_rd_nonzero_seen_sync[0], S_dbg_rd_nonzero_seen};
            S_dbg_mc_init_seen_sync <= {S_dbg_mc_init_seen_sync[0], S_dbg_mc_init_seen};
            S_dbg_mc_app_rdy_seen_sync <= {S_dbg_mc_app_rdy_seen_sync[0], S_dbg_mc_app_rdy_seen};
            S_dbg_mc_wdf_rdy_seen_sync <= {S_dbg_mc_wdf_rdy_seen_sync[0], S_dbg_mc_wdf_rdy_seen};
            S_dbg_mc_cmd_pop_seen_sync <= {S_dbg_mc_cmd_pop_seen_sync[0], S_dbg_mc_cmd_pop_seen};
            if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
                S_dbg_video_nonzero_seen <= 1'b1;
        end
    end

    assign S_lane_error_any = |S_lane_error;

    // MIPI receive (lane) error -> video_in (ddr_clk domain), 2-FF synchronised.
    // A frame with a receive error does NOT advance the write pointer, so the
    // display keeps showing the previous complete frame (bad-frame protection).
    // NOTE: the framing word-count error is deliberately NOT merged in yet --
    // its absolute constant (115200) must first be confirmed on the board, else a
    // wrong value would freeze the picture.
    reg S_rxerr_s1, S_rxerr_s2;
    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin S_rxerr_s1 <= 1'b0; S_rxerr_s2 <= 1'b0; end
        else begin S_rxerr_s1 <= S_lane_error_any; S_rxerr_s2 <= S_rxerr_s1; end
    end

    assign S_vo_dbg_fifo_rst = 1'b0;
    assign S_vo_dbg_ddr_rd_valid = 1'b0;
    assign S_vo_dbg_fifo_rd_en = 1'b0;
    assign S_vo_dbg_fifo_empty = 1'b0;
    assign S_mc_dbg_fifo_afull = 1'b0;
    assign S_mc_dbg_app_rdy = 1'b0;
    assign S_mc_dbg_wdf_rdy = 1'b0;
    assign S_mc_dbg_cmd_pop = 1'b0;

    // ---- Style-path frame framing debug (watch on hdmi_mixer DEBUG_MODE=3) ----
    // Counts the 128-bit words per frame at the ISP output, checks (a) the word
    // count is stable frame-to-frame, and (b) the frame-start marker lands on a
    // valid data beat.  A violation => the style path mis-framed/shifted the
    // image (the "1234567 -> 2345671" left-rotation on the board).
    reg [31:0] S_spk_words;
    reg [31:0] S_spk_ref;
    reg        S_spk_framing_bad;
    reg        S_spk_fs_bad;

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if (!S_rst_n) begin
            S_spk_words      <= 32'd0;
            S_spk_ref        <= 32'd0;
            S_spk_framing_bad<= 1'b0;
            S_spk_fs_bad     <= 1'b0;
        end else begin
            if (S_ISP_O_tuser) begin
                // Frame start: the previous frame is complete.  Compare its
                // 128-bit word count against the ABSOLUTE value
                // 1280*720*24/128 = 172800 (a per-frame constant loss would
                // otherwise pass the old frame-to-frame check unnoticed).  The
                // beat that carries tuser also holds frame data, so it is
                // counted into the NEW frame below.
                //
                // These describe the frame that just ended, not the whole
                // power-on history: they are re-evaluated every frame.  Held
                // sticky they were useless -- after reset S_spk_words is 0, so
                // the very first tuser compared 0 against 115200 and latched
                // the "bad" flag for good, lighting the status corner red on
                // every boot no matter how healthy the stream was.
                // S_spk_ref is still 0 on that first frame, which is what
                // suppresses the comparison until there is a predecessor.
                S_spk_framing_bad <= (S_spk_ref != 32'd0) &&
                                     (S_spk_words != 32'd172800);
                // frame start landing on a non-data beat => marker shifted
                S_spk_fs_bad      <= (S_ISP_O_tvalid == 1'b0);
                S_spk_ref   <= S_spk_words;
                S_spk_words <= S_ISP_O_tvalid ? 32'd1 : 32'd0;
            end else if (S_ISP_O_tvalid) begin
                S_spk_words <= S_spk_words + 32'd1;
            end
        end
    end

    assign S_hdmi_debug_status = {
        (|S_ddr_user_rd_data),   // [3] DDR read data nonzero
        S_ddr_user_rd_valid,     // [2]
        S_spk_fs_bad,            // [1] frame start not on a data beat (shifted)
        S_spk_framing_bad        // [0] 128-bit word count differs per frame (framing)
    };
	
    // A bitstream reload does not power-cycle the sensor.  Assert its
    // active-low PWDNB pin, then wait for it to wake before starting I2C.
    wire S_cam_cfg_rst_n;
    wire S_pll_por;
    power_on_reset #(.HOLD_CYCLES(50000)) u_power_on_reset (
        .I_clk(I_sys_clk), .O_rst(S_pll_por)
    );
    camera_startup_reset u_camera_startup (
        .I_clk(S_24m_clk), .I_rst_n(S_rst_n),
        .O_cam_pwdn_n(O_cam_rst), .O_cfg_rst_n(S_cam_cfg_rst_n)
    );
    assign O_cam_24m 	= S_24m_clk;

    // Toggle-and-data CDC for RAW AE statistics.  The statistics registers
    // are written once per complete CSI frame and remain stable afterwards;
    // two synchronizer stages on the toggle provide the settling time before
    // the 24 MHz AE controller samples the accompanying data bus.
    reg       S_luma_get_s1, S_luma_get_s2, S_luma_get_d;
    reg [8:0] S_luma_avg_s1, S_luma_avg_s2;
    reg [8:0] S_luma_clip_s1, S_luma_clip_s2;
    reg [8:0] S_luma_roi_all_s1, S_luma_roi_all_s2;
    always @(posedge S_24m_clk or negedge S_cam_cfg_rst_n) begin
        if (!S_cam_cfg_rst_n) begin
            S_luma_get_s1  <= 1'b0;
            S_luma_get_s2  <= 1'b0;
            S_luma_get_d   <= 1'b0;
            S_luma_avg_s1  <= 9'd0;
            S_luma_avg_s2  <= 9'd0;
            S_luma_clip_s1 <= 9'd0;
            S_luma_clip_s2 <= 9'd0;
            S_luma_roi_all_s1 <= 9'd0;
            S_luma_roi_all_s2 <= 9'd0;
            S_luma_avg     <= 9'd0;
            S_luma_clip    <= 9'd0;
            S_luma_roi_all <= 9'd0;
            S_luma_get     <= 1'b0;
        end else begin
            S_luma_get_s1  <= S_luma_raw_get;
            S_luma_get_s2  <= S_luma_get_s1;
            S_luma_get_d   <= S_luma_get_s2;
            S_luma_avg_s1  <= S_luma_raw_avg;
            S_luma_avg_s2  <= S_luma_avg_s1;
            S_luma_clip_s1 <= S_luma_raw_clip;
            S_luma_clip_s2 <= S_luma_clip_s1;
            S_luma_roi_all_s1 <= S_luma_raw_roi_all;
            S_luma_roi_all_s2 <= S_luma_roi_all_s1;
            if (S_luma_get_s2 != S_luma_get_d) begin
                S_luma_avg  <= S_luma_avg_s2;
                S_luma_clip <= S_luma_clip_s2;
                S_luma_roi_all <= S_luma_roi_all_s2;
                S_luma_get  <= S_luma_get_s2;
            end
        end
    end
	
	
	
	
    PLL u_PLL(
        .refclk      ( I_sys_clk         ),
        .reset    	 ( S_pll_por         ),
        
        .clk0_out    ( S_100m_clk        ),
        .clk1_out    ( S_24m_clk         ),

        .clk4_out    ( S_hdmi_pixel_clk  ),
        .clk5_out    ( S_hdmi_serial_clk ),

        .lock        ( S_pll_lock        )

    );


	

  
  // Auto-exposure / analogue-gain feedback controller (replaces key-based ae_set).
  localparam integer SENSOR_DG_INIT_Q7 = 128;
  localparam integer SENSOR_DG_MAX_Q7  = 256; // 1.0x startup; automatic range 1.0x..2.0x.
  ae_auto #(
      .CLK_HZ      (24000000),
      // Raise the post-WB luma target so the displayed image is not
      // persistently under-exposed.  The dead band prevents hunting.
      // Raise the target a little further for dim indoor scenes.  Keep the
      // same 14-count dead band so the extra brightness does not make AE
      // hunt when the scene is steady.
      .Y_TARGET    (128),
      .Y_LO        (124),
      .Y_HI        (136),
      .CLIP_GATE   (4),
      .CLIP_HIGH   (16),
      .CLIP_LOCK_ENTER(5), .CLIP_LOCK_EXIT(3),
      .HOT_ENTER_FRAMES(3), .HOT_EXIT_FRAMES(6),
      .ROI_DARK_FLOOR(48), .ROI_DARK_RELEASE(64),
      .SOFT_DOWN_LIMIT(4), .RECOVERY_HOLD_FRAMES(6), .RECOVERY_QUAL_FRAMES(3), .DARK_RECOVERY_SHIFT(2),
      .AE_MIN      (3),
      .AE_MAX      (2529),         // not used by ae_auto (AE_SPORT_MAX governs)
      // SC500 exposure code is expressed in half-row units (datasheet
      // section 2.2.2).  VTS=1000 rows therefore permits about 1990 codes;
      // keep a 10-code guard while allowing the AE loop to reach ~995 rows in
      // genuinely dim scenes instead of clamping at only 495 rows.
      .AE_SPORT_MAX(1990),
      // Use 60-row (about 1 ms) quanta.  The 600-row anti-flicker quantum
      // leaves too little range below the 990-row VTS guard and can quantize
      // a correction back to the same value after clamp.  60 rows keeps the
      // exposure response visible while retaining fine banding suppression.
      .FLICKER_N   (60),
      .AG_MIN      (16),
      .AG_MAX      (143),          // SC500 table index 127: 15.75x ceiling
      .LOW_NOISE_GAIN_FIRST(0),
      .ADJ_FRAMES  (2),
      .DG_INIT_Q7  (SENSOR_DG_INIT_Q7),
      .DG_MIN_Q7   (128),
      .DG_MAX_Q7   (SENSOR_DG_MAX_Q7),
      .DG_STEP_Q7  (4)
  ) u_ae_auto (
      .I_clk(S_24m_clk),
      .I_rst(~S_cam_cfg_rst_n),
      .I_frame_tgl(S_luma_get),
      .I_avg_luma (S_luma_avg),
      .I_clip_pct (S_luma_clip),
      .I_roi_all  (S_luma_roi_all),
      .I_cam_cfg_done(S_cam_cfg_done),
      .I_ae_cfg_done(S_ae_cfg_done),
      .O_ae_req(S_ae_req),
      .O_ae(S_ae),
      .O_ag(S_ag),
      .O_dg(S_dg)
  );
  
    uicfgcs500_720p #(
      .CLK_DIV(24000000 / 100000 - 1),
      .DG_INIT_Q7(SENSOR_DG_INIT_Q7),
      .DG_MAX_Q7 (SENSOR_DG_MAX_Q7)
  ) u_uicfgcs500 (
      .I_clk(S_24m_clk),  //系统时钟输入
      .I_rst_n(S_cam_cfg_rst_n),  // sensor awake before I2C initialization
      .I_ae_req(S_ae_req),
      .I_ae(S_ae),
      .I_ag(S_ag),
      .I_dg(S_dg),
      .O_cam_scl(O_cam_scl),  //I2C总线，SCL时钟
      .IO_cam_sda(IO_cam_sda),  //I2C总线，SDA数据
      .O_cfg_done(S_cam_cfg_done),  //摄像头寄存器初始化完成
      .O_ae_cfg_done(S_ae_cfg_done)  //AE配置完成
  );
	
    mipi_dphy_rx_ph1p_mipiio_wrapper#(
        .DPHY_RX_LOCATION      ( "DPHY0" ),
        .HS_EQUALIZER          ( "0dB"   ),//"0dB","1.5dB","3dB","4.5dB","6dB","7.5dB","9dB","10.5dB"
        .HS_VGA_GAIN           ( "8dB" ),//"-3dB","-1.5dB","0dB","1.5dB","3dB","4.5dB","6dB","7.5dB"
        .LANE_NUM              ( 2       ),
        .BYTE_NUM              ( 1       )
    )u_mipi_dphy_rx_ph1p_mipiio_wrapper(
        .I_lp_clk              ( S_100m_clk       ),
        .I_rst                 ( ~S_phy_rst_n     ),

        .I_clk_lane_in_delay   ( 6'd0             ),
        .I_data_lane0_in_delay ( 6'd0             ),
        .I_data_lane1_in_delay ( 6'd0             ),
        .I_data_lane2_in_delay ( 6'd0             ),
        .I_data_lane3_in_delay ( 6'd0             ),

        .I_lane_invert         ( 4'b0000          ),
     
        .O_hs_rx_clk           ( S_csi_rx_clk     ),
        .O_hs_rx_valid         ( S_hs_rx_valid    ),
        .O_hs_rx_data          ( S_hs_rx_data     ),
      
        .O_lp_rx_lane0_p       (  ),
        .O_lp_rx_lane0_n       (  ),
      
        .I_lp_tx_en            ( 1'b0             ),
        .I_lp_tx_lane0_p       ( 1'b1             ),
        .I_lp_tx_lane0_n       ( 1'b1             ),
      
        .O_lane_match_error    (                  ),
        .O_lane_error          ( S_lane_error     ),
      
        .IO_rx_clk_pad_n       ( IO_rx_clk_pad_n  ),
        .IO_rx_clk_pad_p       ( IO_rx_clk_pad_p  ),
        .IO_rx_data_pad_n      ( IO_rx_data_pad_n ),
        .IO_rx_data_pad_p      ( IO_rx_data_pad_p )
    );
	
	
 //  cwc cwc_inst
 //(
 //    .probe0(S_hs_rx_valid),
 //    .probe1(S_hs_rx_data),
 //    .probe2(S_lane_error),
 //    .clk(S_csi_rx_clk)
 //);

 //csi 解码为RAW数据
csi_unpacket_2lane u_csi_unpacket(
.I_clk                 ( S_csi_rx_clk       ),
.I_rst_n               ( S_rst_n        	),
.I_hs_valid            ( S_hs_rx_valid     ),
.I_hs_data             ( S_hs_rx_data      ),

.O_csi_frame_start     ( S_csi_frame_start ),
.O_csi_frame_end       ( S_csi_frame_end   ),
.O_csi_valid           ( S_csi_valid       ),
.O_csi_data            ( S_csi_data        )
);


//解码为RAW8
raw10_unpacket_2lane u_raw10_unpacket (
.I_clk  (S_csi_rx_clk),
.I_rst_n(S_rst_n),

.I_csi_frame_start(S_csi_frame_start),
.I_csi_frame_end  (S_csi_frame_end),
.I_csi_valid      (S_csi_valid),
.I_csi_data       (S_csi_data),

.O_raw10_frame_start(S_raw10_frame_start),
.O_raw10_frame_end  (S_raw10_frame_end),
.O_raw10_valid      (S_raw10_valid),
.O_raw10_data       (S_raw10_data)
  );


//将数据转为stream流
uial2axis #(
.IMG_WIDTH(1280),
.IMG_HEIGHT(720),
.INPUT_DATA_WIDTH(40)
)
u_uial2axis (
.I_native_clk(S_csi_rx_clk),
.I_rst_n     (S_rst_n),
.I_data      (S_raw10_data       ),
.I_data_valid(S_raw10_valid      ),
.I_data_start(S_raw10_frame_start),
.I_data_end  (S_raw10_frame_end  ),
.axis_tvalid (S_axis_tvalid),
.axis_tdata  (S_axis_tdata ),
.axis_tuser  (S_axis_tuser ),
.axis_tlast  (S_axis_tlast )
 );
	

// Filter spurious frame markers before the ISP.  uial2axis data and line
// markers are preserved; only tuser is qualified by a frame-level state
// machine so a mid-frame marker cannot reset ISP/line-buffer pointers.
frame_guard #(
    .IMG_WIDTH(1280), .IMG_HEIGHT(720), .INPUT_DATA_WIDTH(40)
) u_frame_guard (
    .I_clk          (S_csi_rx_clk),
    .I_rst_n        (S_rst_n),
    .I_tdata        (S_axis_tdata),
    .I_tvalid       (S_axis_tvalid),
    .I_tuser        (S_axis_tuser),
    .I_tlast        (S_axis_tlast),
    .O_tdata        (S_guard_tdata),
    .O_tvalid       (S_guard_tvalid),
    .O_tuser        (S_guard_tuser),
    .O_tlast        (S_guard_tlast),
    .O_frame_active (S_guard_frame_active),
    .O_frame_error  (S_guard_frame_error),
    .O_line_count   (S_guard_line_count),
    .O_group_count  (S_guard_group_count),
    .O_frame_done   (S_guard_frame_done)
);

// The sensor is already configured for native 1280x720 output.  The old
// image_correction block is retained only as a legacy, uninstantiated helper;
// the active 720p path below uses 320 beats x 720 lines,
// so keeping it in this path produces diagonal repetition. Apply the
// measured RAW-domain black-level correction after frame-marker filtering,
// before demosaic. The production source is continuous and the ISP boundary
// is always-ready, so the elastic stage accepts one beat every cycle. Its
// ready/tdest signals are connected explicitly; the standalone BLC test
// covers future stalls.
raw10_bggr_blc #(
    .OFFSET_B (10'd64),
    .OFFSET_GR(10'd64),
    .OFFSET_GB(10'd64),
    .OFFSET_R (10'd64)
) u_raw10_bggr_blc (
    .I_clk    (S_csi_rx_clk),
    .I_rst_n  (S_rst_n),
    .I_tvalid (S_guard_tvalid),
    .I_tready (S_blc_tready),
    .I_tuser  (S_guard_tuser),
    .I_tlast  (S_guard_tlast),
    .I_tdest  (10'd0),
    .I_tdata  (S_guard_tdata),
    .O_tvalid (S_blc_tvalid),
    .O_tready (1'b1),
    .O_tuser  (S_blc_tuser),
    .O_tlast  (S_blc_tlast),
    .O_tdest  (S_blc_tdest),
    .O_tdata  (S_blc_tdata)
);

assign S_raw_tdata  = S_blc_tdata;
assign S_raw_tlast  = S_blc_tlast;
assign S_raw_tvalid = S_blc_tvalid;
assign S_raw_tuser  = S_blc_tuser;


//cwc1 cwc1_Inst
//  (
//      .probe0(S_axis_tuser),
//      .probe1(S_axis_tvalid),
//      .probe2(S_axis_tlast),
//      .probe3(S_axis_tdata),
//      .probe4(S_ISP_O_tuser),
//      .probe5(S_ISP_O_tvalid),
//      .probe6(S_ISP_O_tlast),
//      .probe7(S_ISP_O_tdata),
//      .probe8 (S_raw_tdata ),
//      .probe9 (S_raw_tlast ),
//      .probe10(S_raw_tvalid),
//      .probe11(S_raw_tuser ),
//      .clk(S_csi_rx_clk)
//  );


//ISP算法顶层模块
    // Denoise strength follows the analogue gain (S_ag); sync it into the ISP
    // clock domain.  gain 16..143 -> strength 0..254.
    reg [15:0] S_ag_den_s1, S_ag_den_s2;
    reg [7:0]  S_den_strength;
    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin S_ag_den_s1<=16'd0; S_ag_den_s2<=16'd0; S_den_strength<=8'd0; end
        else begin
            S_ag_den_s1 <= S_ag;
            S_ag_den_s2 <= S_ag_den_s1;
            S_den_strength <= (S_ag_den_s2 > 16'd16) ? ((S_ag_den_s2 - 16'd16) << 1) : 8'd0;
        end
    end

    // SW1 (pin A4) is the master switch for the target-detection overlay.
    // Two-FF synchronised into both clock domains; the pixel-domain copy is
    // additionally latched at the frame start so the overlay cannot appear or
    // vanish in the middle of a frame.
    //
    // SW1 is a SLIDE SWITCH, not one of the keys: the HX1P35A manual has it
    // read 1 when pushed up and 0 when pushed down, i.e. active HIGH.  The
    // inversion that used to be here was carried over from the KEY1/KEY2
    // convention (those are active low, which is why I_button below is still
    // used directly) and made the switch work backwards.
    //
    // KEY2 (I_button[1], A9) cycles the image styles. KEY1 is reserved; the
    // histogram path was removed from the production display chain.
    // S_sw1_rx_s1/S_sw1_rx_s2 are declared with the Ethernet CDC signals above.
    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin S_sw1_rx_s1 <= 1'b0; S_sw1_rx_s2 <= 1'b0; end
        else begin S_sw1_rx_s1 <= I_sw1; S_sw1_rx_s2 <= S_sw1_rx_s1; end
    end

    reg S_sw1_px_s1, S_sw1_px_s2;
    reg S_ovl_on;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_sw1_px_s1 <= 1'b0; S_sw1_px_s2 <= 1'b0;
            S_ovl_on <= 1'b0;
        end else begin
            S_sw1_px_s1 <= I_sw1;
            S_sw1_px_s2 <= S_sw1_px_s1;
            if (S_hdmi_user)
                S_ovl_on <= S_sw2_px_s2; // SW2: stage/recognition overlay
        end
    end

    // ---- target metadata -> HDMI pixel domain ----------------------------
    // Frame-rate data plus a toggle handshake.  The data is registered in the
    // camera domain and only the toggle goes through two pixel-clock flops, so
    // the data has settled well before the edge is seen here.
    wire        S_tgt_valid;
    wire [10:0] S_tgt_x_min, S_tgt_x_max;      // 1280 wide -> 11 bit
    wire [9:0]  S_tgt_y_min, S_tgt_y_max;
    wire [10:0] S_tgt_cx;
    wire [9:0]  S_tgt_cy;
    wire [23:0] S_tgt_area;
    wire [1:0]  S_tgt_color;
    wire [1:0]  S_tgt_shape;
    wire        S_tgt_toggle;
    wire [3:0]  S_cnn_class_id;
    wire [7:0]  S_cnn_confidence;
    wire [3:0]  S_cnn_conf_tens, S_cnn_conf_ones;
    wire        S_cnn_valid;
    wire        S_cnn_toggle;

    wire        S_mot_valid;
    wire [10:0] S_mot_x_min, S_mot_x_max;
    wire [9:0]  S_mot_y_min, S_mot_y_max;
    wire [15:0] S_mot_count;
    wire        S_post_mot_valid;
    wire [10:0] S_post_mot_x_min, S_post_mot_x_max;
    wire [9:0]  S_post_mot_y_min, S_post_mot_y_max;
    wire [15:0] S_post_mot_count;
    wire        S_post_mot_commit;
    wire        S_post_mot_empty;

    reg S_tgt_tgl_s1, S_tgt_tgl_s2, S_tgt_tgl_d;
    reg S_cnn_tgl_s1, S_cnn_tgl_s2, S_cnn_tgl_d;
    reg        S_ovl_valid;
    reg [10:0] S_ovl_x0, S_ovl_x1;
    reg [9:0]  S_ovl_y0, S_ovl_y1;
    reg [10:0] S_ovl_cx;
    reg [9:0]  S_ovl_cy;
    reg [23:0] S_ovl_area;
    reg [1:0]  S_ovl_color;
    reg [1:0]  S_ovl_shape;
    reg [3:0]  S_ovl_class_id;
    reg [7:0]  S_ovl_confidence;
    reg [3:0]  S_ovl_conf_tens, S_ovl_conf_ones;
    reg        S_ovl_commit_toggle;
    // Target metadata is captured first and committed only when the
    // classifier result arrives.  This keeps box and label information
    // frame-atomic across the two independent result toggles.
    reg        S_tgt_pending_valid;
    reg [10:0] S_tgt_pending_x0, S_tgt_pending_x1, S_tgt_pending_cx;
    reg [9:0]  S_tgt_pending_y0, S_tgt_pending_y1, S_tgt_pending_cy;
    reg [23:0] S_tgt_pending_area;
    reg [1:0]  S_tgt_pending_color, S_tgt_pending_shape;
    wire       S_tgt_frame_event = S_tgt_tgl_s2 ^ S_tgt_tgl_d;
    wire       S_cnn_frame_event = S_cnn_tgl_s2 ^ S_cnn_tgl_d;

    // Motion box, latched on the same edge as the target metadata.
    reg        S_mot_on;
    reg [10:0] S_mot_x0, S_mot_x1;
    reg [9:0]  S_mot_y0, S_mot_y1;
    reg [15:0] S_mot_cnt;
    // Keep incomplete/overrun frames from blanking the last good box.
    reg [1:0] S_mot_hold;
    reg S_post_mot_commit_d;
    wire S_post_mot_commit_event = S_post_mot_commit ^ S_post_mot_commit_d;

    // HDMI-domain motion metadata commits during vertical blanking. The
    // detector itself commits at USER; delaying the display by one frame
    // prevents even the first pixels from seeing mixed box coordinates.
    wire S_mot_on_eff = S_mot_on && S_sw1_px_s2;
    wire [10:0] S_mot_x0_eff = S_mot_x0, S_mot_x1_eff = S_mot_x1;
    wire [9:0]  S_mot_y0_eff = S_mot_y0, S_mot_y1_eff = S_mot_y1;
    wire [15:0] S_mot_cnt_eff = S_sw1_px_s2 ? S_mot_cnt : 16'd0;
    reg S_motion_vs_d;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_motion_vs_d <= 0;
            S_mot_on <= 0; S_mot_x0 <= 0; S_mot_x1 <= 0;
            S_mot_y0 <= 0; S_mot_y1 <= 0; S_mot_cnt <= 0; S_mot_hold <= 0;
            S_post_mot_commit_d <= 1'b0;
        end else begin
            S_motion_vs_d <= S_hdmi_vsync;
            if (S_hdmi_vsync && !S_motion_vs_d) begin
                if (S_post_mot_commit_event) begin
                    // A complete empty frame is authoritative and clears the
                    // overlay. A valid candidate replaces it immediately.
                    S_mot_on <= S_post_mot_valid;
                    S_mot_x0 <= S_post_mot_x_min; S_mot_x1 <= S_post_mot_x_max;
                    S_mot_y0 <= S_post_mot_y_min; S_mot_y1 <= S_post_mot_y_max;
                    S_mot_cnt <= S_post_mot_count;
                    S_mot_hold <= S_post_mot_valid ? 2'd2 : 2'd0;
                end else if (S_mot_on && (S_mot_hold != 0)) begin
                    // Incomplete/overrun frame: preserve the last good box
                    // for at most two frames, then clear it.
                    S_mot_hold <= S_mot_hold - 1'b1;
                end else begin
                    S_mot_on <= 1'b0;
                    S_mot_hold <= 0;
                end
                S_post_mot_commit_d <= S_post_mot_commit;
            end
        end
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_tgt_tgl_s1 <= 1'b0; S_tgt_tgl_s2 <= 1'b0; S_tgt_tgl_d <= 1'b0;
            S_cnn_tgl_s1 <= 1'b0; S_cnn_tgl_s2 <= 1'b0; S_cnn_tgl_d <= 1'b0;
            S_ovl_valid <= 1'b0;
            S_ovl_x0 <= 10'd0; S_ovl_y0 <= 10'd0;
            S_ovl_x1 <= 10'd0; S_ovl_y1 <= 10'd0;
            S_ovl_cx <= 10'd0; S_ovl_cy <= 10'd0;
            S_ovl_area <= 24'd0; S_ovl_color <= 2'd0; S_ovl_shape <= 2'd0;
            S_ovl_class_id <= 4'd0; S_ovl_confidence <= 8'd0;
            S_ovl_conf_tens <= 4'd0; S_ovl_conf_ones <= 4'd0;
            S_ovl_commit_toggle <= 1'b0;
            S_tgt_pending_valid <= 1'b0;
            S_tgt_pending_x0 <= 11'd0; S_tgt_pending_x1 <= 11'd0;
            S_tgt_pending_y0 <= 10'd0; S_tgt_pending_y1 <= 10'd0;
            S_tgt_pending_cx <= 11'd0; S_tgt_pending_cy <= 10'd0;
            S_tgt_pending_area <= 24'd0;
            S_tgt_pending_color <= 2'd0; S_tgt_pending_shape <= 2'd0;
        end else begin
            S_tgt_tgl_s1 <= S_tgt_toggle;
            S_tgt_tgl_s2 <= S_tgt_tgl_s1;
            S_tgt_tgl_d  <= S_tgt_tgl_s2;
            S_cnn_tgl_s1 <= S_cnn_toggle;
            S_cnn_tgl_s2 <= S_cnn_tgl_s1;
            S_cnn_tgl_d  <= S_cnn_tgl_s2;

            if (S_tgt_frame_event) begin
                S_tgt_pending_valid <= S_tgt_valid;
                S_tgt_pending_x0 <= S_tgt_x_min;
                S_tgt_pending_y0 <= S_tgt_y_min;
                S_tgt_pending_x1 <= S_tgt_x_max;
                S_tgt_pending_y1 <= S_tgt_y_max;
                S_tgt_pending_cx <= S_tgt_cx;
                S_tgt_pending_cy <= S_tgt_cy;
                S_tgt_pending_area <= S_tgt_area;
                S_tgt_pending_color <= S_tgt_color;
                S_tgt_pending_shape <= S_tgt_shape;
            end
            if (S_cnn_frame_event) begin
                S_ovl_valid <= (S_tgt_frame_event ? S_tgt_valid : S_tgt_pending_valid) && S_cnn_valid;
                S_ovl_x0 <= S_tgt_frame_event ? S_tgt_x_min : S_tgt_pending_x0;
                S_ovl_y0 <= S_tgt_frame_event ? S_tgt_y_min : S_tgt_pending_y0;
                S_ovl_x1 <= S_tgt_frame_event ? S_tgt_x_max : S_tgt_pending_x1;
                S_ovl_y1 <= S_tgt_frame_event ? S_tgt_y_max : S_tgt_pending_y1;
                S_ovl_cx <= S_tgt_frame_event ? S_tgt_cx : S_tgt_pending_cx;
                S_ovl_cy <= S_tgt_frame_event ? S_tgt_cy : S_tgt_pending_cy;
                S_ovl_area <= S_tgt_frame_event ? S_tgt_area : S_tgt_pending_area;
                S_ovl_color <= S_tgt_frame_event ? S_tgt_color : S_tgt_pending_color;
                S_ovl_shape <= S_tgt_frame_event ? S_tgt_shape : S_tgt_pending_shape;
                S_ovl_class_id <= S_cnn_class_id;
                S_ovl_confidence <= S_cnn_confidence;
                S_ovl_conf_tens <= S_cnn_conf_tens;
                S_ovl_conf_ones <= S_cnn_conf_ones;
                S_ovl_commit_toggle <= ~S_ovl_commit_toggle;
            end
        end
    end

    wire [95:0] S_clean_rgb;
    wire S_clean_valid,S_clean_user,S_clean_last;

    // A4 ranging, its KEY1 request and both CDC banks were removed. Document
    // copying still uses the existing independent full-frame scale contract.
 isp_top_basic #(.STYLE_ENABLE(1'b1), .CARTOON_ENABLE(1'b1),
                 .RAW_AWB_ENABLE(1'b1), .RAW_AE_ENABLE(1'b1),
                 .COLOR_LSC_ENABLE(1'b1), .ORIGINAL_MODE_ENABLE(ORIGINAL_MODE_ENABLE)) u_isp_top (
.O_awb_diag(),
.axi4s_video_aclk(S_csi_rx_clk),
.I_rst_n         (S_rst_n),
.I_tlast         (S_raw_tlast	),
.I_tuser         (S_raw_tuser	),
.I_tdata         (S_raw_tdata	),
.I_tvalid        (S_raw_tvalid	),
 .I_tdest         (),
 .I_style_mode    (S_style_mode_isp),
 .I_den_strength  (S_den_strength),
 .I_det_en        (S_eth_detect_csi_s2),
 .O_clean_rgb     (S_clean_rgb),
 .O_clean_valid   (S_clean_valid),
 .O_clean_user    (S_clean_user),
 .O_clean_last    (S_clean_last),
 .O_tgt_valid     (S_tgt_valid),
 .O_tgt_x_min     (S_tgt_x_min),
 .O_tgt_y_min     (S_tgt_y_min),
 .O_tgt_x_max     (S_tgt_x_max),
 .O_tgt_y_max     (S_tgt_y_max),
 .O_tgt_cx        (S_tgt_cx),
 .O_tgt_cy        (S_tgt_cy),
 .O_tgt_area      (S_tgt_area),
 .O_tgt_color     (S_tgt_color),
 .O_tgt_shape     (S_tgt_shape),
 .O_tgt_toggle    (S_tgt_toggle),
 .O_mot_valid     (S_mot_valid),
 .O_mot_x_min     (S_mot_x_min),
 .O_mot_y_min     (S_mot_y_min),
 .O_mot_x_max     (S_mot_x_max),
 .O_mot_y_max     (S_mot_y_max),
 .O_mot_count     (S_mot_count),
 .O_cnn_class_id  (S_cnn_class_id),
 .O_cnn_confidence(S_cnn_confidence),
 .O_cnn_conf_tens  (S_cnn_conf_tens),
 .O_cnn_conf_ones  (S_cnn_conf_ones),
 .O_cnn_valid     (S_cnn_valid),
 .O_cnn_toggle    (S_cnn_toggle),
// The DDR writer has no back-pressure signal at the ISP boundary; the
// video_in FIFO is always the consumer, so keep the stream flowing.
.O_tready        (1'b1),
.O_tdata         (S_ISP_O_tdata ),
.O_tlast         (S_ISP_O_tlast ),
.O_tuser         (S_ISP_O_tuser ),
.O_tvalid        (S_ISP_O_tvalid),
.I_tready        (),
.O_avg_luma      (S_luma_raw_avg ),
.O_clip_pct      (S_luma_raw_clip),
.O_roi_all       (S_luma_raw_roi_all),
.O_frame_tgl     (S_luma_raw_get )
  );


    // Snapshot network boundary: every S_snap_* control/byte signal below
    // is synchronous to S_125m_clk. The network controller owns requests.
    wire S_snap_capture_req, S_snap_cancel, S_snap_release, S_snap_background_capture;
    wire S_snap_busy, S_snap_ready, S_snap_capture_error;
    wire [31:0] S_snap_frame_id;
    wire S_snap_packet_req, S_snap_packet_busy, S_snap_packet_valid;
    wire S_snap_packet_ready, S_snap_packet_last, S_snap_packet_error;
    wire [10:0] S_snap_packet_index;
    wire [7:0] S_snap_packet_data;
    wire [255:0] S_station_header;
    wire S_station_commit,S_station_ready;
    wire S_snap_background_valid, S_snap_pcb_present, S_snap_pcb_stable, S_snap_pcb_trigger;
    // Manual good-template recording is retired. KEY3 belongs to style restore.
    wire S_teach_good_press = 1'b0;
    wire S_snapshot_bus_pause, S_vo_burst_active, S_legacy_ddr_ready, S_video_ddr_rd_valid;
    wire S_snap_ddr_wr_valid, S_snap_ddr_wr_ready, S_snap_ddr_rd_req;
    wire S_snap_ddr_rd_ready, S_snap_ddr_rd_valid;
    wire S_ddr_write_retire;
    wire [24:0] S_ddr_write_retire_addr;
    wire [24:0] S_snap_ddr_wr_addr, S_snap_ddr_rd_addr;
    wire [127:0] S_snap_ddr_wr_data;
    wire [127:0] S_snap_capture_diag;
    wire [23:0] S_snapshot_arb_debug;
    wire [31:0] S_snapshot_ddr_debug={S_init_calib_complete,S_mc_app_en,S_mc_app_cmd[0],
        S_mc_app_rdy,S_mc_app_wdf_wren,S_mc_app_wdf_rdy,S_mc_app_rd_data_valid,
        S_mc_app_rd_data_end,S_snapshot_arb_debug};
    hx_snapshot_service u_snapshot_service (
        .I_clk_cam(S_csi_rx_clk), .I_rst_cam_n(S_rst_n),
        .I_clk_ddr(S_ddr_clk), .I_rst_ddr_n(S_rst_n),
        .I_clk_net(S_125m_clk), .I_rst_net_n(S_eth_rst_n),
        .I_rgb(S_clean_rgb), .I_valid(S_clean_valid), .I_user(S_clean_user), .I_last(S_clean_last),
        .I_frame_error(S_guard_frame_error | S_rxerr_s2),
        .I_capture_req(S_snap_capture_req), .I_cancel(S_snap_cancel), .I_release(S_snap_release),
        .O_busy(S_snap_busy), .O_ready(S_snap_ready), .O_frame_id(S_snap_frame_id),
        .O_capture_error(S_snap_capture_error), .O_capture_diag(S_snap_capture_diag),
        .I_packet_req(S_snap_packet_req), .I_packet_index(S_snap_packet_index),
        .O_packet_busy(S_snap_packet_busy), .O_packet_valid(S_snap_packet_valid),
        .I_packet_ready(S_snap_packet_ready), .O_packet_data(S_snap_packet_data),
        .O_packet_last(S_snap_packet_last), .O_packet_error(S_snap_packet_error),
        .I_cfg_commit(S_station_commit), .O_cfg_ready(S_station_ready),
        .I_cfg_roi_x0(S_station_header[128+:11]),.I_cfg_roi_y0(S_station_header[144+:10]),
        .I_cfg_roi_x1(S_station_header[160+:11]),.I_cfg_roi_y1(S_station_header[176+:10]),
        .I_cfg_background_th(S_station_header[192+:8]),.I_cfg_stable_th(S_station_header[200+:8]),.I_cfg_stable_frames(S_station_header[88+:8]),
        .I_cfg_clear_frames(S_station_header[232+:8]),.I_cfg_present_min(S_station_header[208+:16]),.I_cfg_stable_max(S_station_header[224+:8]),.I_cfg_teach(S_station_header[240]),
        .I_background_capture(S_snap_background_capture),
        .O_background_valid(S_snap_background_valid), .O_pcb_present(S_snap_pcb_present),
        .O_pcb_stable(S_snap_pcb_stable), .O_pcb_trigger(S_snap_pcb_trigger),
        .O_ddr_wr_valid(S_snap_ddr_wr_valid), .O_ddr_wr_addr(S_snap_ddr_wr_addr),
        .O_ddr_wr_data(S_snap_ddr_wr_data), .I_ddr_wr_ready(S_snap_ddr_wr_ready),
        .I_ddr_wr_retire(S_ddr_write_retire && S_ddr_write_retire_addr >= 25'd28000000 && S_ddr_write_retire_addr < 25'd29382400),
        .O_ddr_rd_req(S_snap_ddr_rd_req), .O_ddr_rd_addr(S_snap_ddr_rd_addr),
        .I_ddr_rd_ready(S_snap_ddr_rd_ready), .I_ddr_rd_valid(S_snap_ddr_rd_valid),
        .I_ddr_rd_data(S_ddr_user_rd_data), .I_ddr_debug(S_snapshot_ddr_debug)
    );

    wire S_aux_tx_req,S_aux_tx_valid,S_aux_tx_busy,S_aux_stack_reset,S_aux_ready;
    wire S_aux_rx_valid,S_aux_rx_error,S_aux_online,S_aux_result_valid,S_aux_result_toggle;
    wire [7:0] S_aux_tx_data,S_aux_rx_data,S_aux_job_state;
    wire [15:0] S_aux_tx_len,S_aux_rx_len;
    wire [511:0] S_aux_result_data;
    wire [31:0] S_aux_result_frame,S_aux_sent_frames,S_aux_failed_frames;
    wire S_aux_multi_valid,S_aux_multi_toggle;
    wire [2:0] S_aux_multi_count;
    wire [511:0] S_aux_multi_data;
    wire [31:0] S_aux_multi_job;
    wire [2:0] S_copy_state_eth,S_copy_state_px;
    wire S_copy_toggle_eth;
    reg [1:0] S_aux_detect_sync;
    always @(posedge S_125m_clk or negedge S_eth_rst_n)
      if(!S_eth_rst_n) S_aux_detect_sync<=0;
      else S_aux_detect_sync<={S_aux_detect_sync[0],S_detect_en_eff};
    // Communication-speed candidate: 5,000 cycles at 125 MHz = 40 us.
    // The HXA1 packet format, CRC/NACK recovery, and secondary receiver are
    // unchanged; this only shortens the proven inter-DATA guard interval.
    localparam integer AUX_PACKET_GAP_CYCLES = 5000;
    // Ordinary CNN runs again after completion without an extra rate wait.
    // PCB requires one stable KEY4 press per capture. No background teaching
    // or automatic repeat; the existing 40 us receive guard remains in effect.
    // Capability bits: legacy/base, type18 multibox (bit6), and text trace
    // purpose=2 (bit7).  Older secondaries will therefore decline text jobs
    // during HELLO negotiation instead of interpreting them as teaching.
    // Display-only task/result latch: ordinary network invalidation cannot
    // erase the last accepted PCB verdict. Triggering/transport stay unchanged.
    key4_pcb_status u_pcb_status(
        .clk(S_125m_clk),.rst_n(S_eth_rst_n),.mode_active(S_mode_pcb_eth),
        .key_press(S_pcb_key4_press),.phy_ready(S_aux_ready),.online(S_aux_online),
        .capture_req(S_snap_capture_req),.capture_cancel(S_snap_cancel),
        .result_toggle(S_aux_result_toggle),.result_valid(S_aux_result_valid),
        .target_valid(S_aux_result_data[96]),.result_checked(S_aux_result_data[98]),
        .result_good(S_aux_result_data[97]),.status(S_pcb_status_eth));

    hxa_main_link #(.HELLO_CAPABILITIES(8'hC3),.PACKET_GAP_CYCLES(AUX_PACKET_GAP_CYCLES),
        .PCB_CONTINUOUS(0),.PCB_KEY_ONESHOT(1),.PCB_RESULT_TIMEOUT_MS(30000),
        .ORDINARY_MIN_INTERVAL_MS(0),.ORDINARY_GAP_PREFETCH(1)) u_main_link(
        .clk(S_125m_clk),.rst_n(S_eth_rst_n),.enable(S_aux_ready),
        .phy_ready(S_aux_ready),.pcb_mode(S_mode_pcb_eth),.text_mode(S_mode_text_eth),
        .text_trigger(S_key1_text_pulse),.maze_mode(1'b0),.maze_trigger(1'b0),
        .report_request(1'b0),
        .detect_enable(S_aux_detect_sync[1] && !S_mode_text_eth),
        .background_valid(S_snap_background_valid),.pcb_trigger(S_pcb_key4_press),.pcb_present(S_snap_pcb_present),
        .teach_good(S_teach_good_press),
        .capture_req(S_snap_capture_req),.capture_cancel(S_snap_cancel),.capture_release(S_snap_release),
        .background_capture(S_snap_background_capture),.snapshot_busy(S_snap_busy),.snapshot_ready(S_snap_ready),
        .snapshot_error(S_snap_capture_error),.snapshot_frame_id(S_snap_frame_id),
        .snapshot_diag(S_snap_capture_diag),
        .packet_req(S_snap_packet_req),.packet_index(S_snap_packet_index),.packet_busy(S_snap_packet_busy),
        .packet_valid(S_snap_packet_valid),.packet_last(S_snap_packet_last),.packet_error(S_snap_packet_error),
        .packet_data(S_snap_packet_data),.packet_ready(S_snap_packet_ready),
        .udp_req(S_aux_tx_req),.udp_valid(S_aux_tx_valid),.udp_data(S_aux_tx_data),.udp_len(S_aux_tx_len),.udp_busy(S_aux_tx_busy),
        .rx_valid(S_aux_rx_valid),.rx_data(S_aux_rx_data),.rx_len(S_aux_rx_len),.rx_error(S_aux_rx_error),
        .stack_reset(S_aux_stack_reset),.online(S_aux_online),.result_valid(S_aux_result_valid),
        .result_toggle(S_aux_result_toggle),.result_data(S_aux_result_data),.result_frame(S_aux_result_frame),
        .station_header(S_station_header),.station_commit(S_station_commit),.station_ready(S_station_ready),
        .sent_frames(S_aux_sent_frames),.failed_frames(S_aux_failed_frames),.job_state(S_aux_job_state),
        .multi_valid(S_aux_multi_valid),.multi_toggle(S_aux_multi_toggle),.multi_count(S_aux_multi_count),
        .multi_data(S_aux_multi_data),.multi_job(S_aux_multi_job),
        .copy_state(S_copy_state_eth),.copy_toggle(S_copy_toggle_eth)
    );

    video_in u_video_in(
        .I_rst_n              (  S_rst_n             ),

        .I_camera_clk         ( S_csi_rx_clk          ),
        // video_in uses this marker to hold its camera-domain FIFO in reset
        // for a few cycles before the first ISP word arrives.  The style
        // pipeline's tuser is intentionally delayed to the first output
        // word; using it here would reset the FIFO on top of live data and
        // drop the first groups of every frame.  Keep the early guard marker
        // used by the proven display path, while the actual ISP stream still
        // supplies the data and valid signals below.
        .I_camera_frame_start ( S_guard_tuser         ),
        .I_camera_valid       ( S_ISP_O_tvalid ),
        .I_camera_data        ( S_ISP_O_tdata  ),
        .I_mipi_rx_error      ( S_rxerr_s2 | S_guard_frame_error ),

        .I_ddr_clk            ( S_ddr_clk             ),
		.I_display_pause      ( 1'b0                  ),
        .I_bus_pause          ( S_snapshot_bus_pause ),
        .I_video_out_rd_busy  ( S_video_out_rd_busy   ),
        .O_video_in_wr_busy   ( S_video_in_wr_busy    ),
        .O_video_out_rp       ( S_video_out_rp        ),

        .O_ddr_user_wr_en     ( S_vi_ddr_wr_en        ),
        .O_ddr_user_addr      ( S_vi_ddr_wr_addr      ),
        .O_ddr_user_wr_data   ( S_vi_ddr_wr_data      ),
        .I_ddr_user_ready     ( S_legacy_ddr_ready    ),
        .O_mon_overflow       ( S_latency_capture_overflow )
    );



    hx_snapshot_ddr_arbiter u_snapshot_arbiter (
        .I_clk(S_ddr_clk), .I_rst_n(S_rst_n),
        .I_vi_active(S_video_in_wr_busy), .I_vo_active(S_vo_burst_active),
        .I_vi_wr_en(S_vi_ddr_wr_en), .I_vi_addr(S_vi_ddr_wr_addr), .I_vi_data(S_vi_ddr_wr_data),
        .I_vo_rd_en(S_vo_ddr_rd_en), .I_vo_addr(S_vo_ddr_rd_addr),
        .O_legacy_ready(S_legacy_ddr_ready), .O_bus_pause(S_snapshot_bus_pause),
        .O_video_rd_valid(S_video_ddr_rd_valid),
        .I_snap_wr_valid(S_snap_ddr_wr_valid), .I_snap_wr_addr(S_snap_ddr_wr_addr),
        .I_snap_wr_data(S_snap_ddr_wr_data), .O_snap_wr_ready(S_snap_ddr_wr_ready),
        .I_snap_rd_valid(S_snap_ddr_rd_req), .I_snap_rd_addr(S_snap_ddr_rd_addr),
        .O_snap_rd_ready(S_snap_ddr_rd_ready), .O_snap_rd_valid(S_snap_ddr_rd_valid),
        .I_mc_ready(S_ddr_user_ready), .I_mc_rd_valid(S_ddr_user_rd_valid),
        .O_mc_wr_en(S_ddr_user_wr_en), .O_mc_rd_en(S_ddr_user_rd_en),
        .O_mc_addr(S_ddr_user_addr), .O_mc_wr_data(S_ddr_user_wr_data),
        .O_debug(S_snapshot_arb_debug)
    );

    assign S_video_out_rst_n = S_hdmi_rst_n;

    video_out u_video_out(
        .I_rst_n             ( S_video_out_rst_n    ),
        .I_ddr_clk           ( S_ddr_clk            ),
 
        .O_video_out_rd_busy ( S_video_out_rd_busy  ),
        .I_bus_pause         ( S_snapshot_bus_pause ),
        .O_burst_active      ( S_vo_burst_active ),
        .I_video_in_wr_busy  ( S_video_in_wr_busy   ),
        .I_video_out_rp      ( S_video_out_rp       ),
 
        .O_ddr_user_rd_en    ( S_vo_ddr_rd_en       ),
        .O_ddr_user_addr     ( S_vo_ddr_rd_addr     ),
        .I_ddr_user_ready    ( S_legacy_ddr_ready   ),
        .I_ddr_user_rd_valid ( S_video_ddr_rd_valid ),
        .I_ddr_user_rd_data  ( S_ddr_user_rd_data   ),

        .I_dsi_clk           ( S_hdmi_pixel_clk     ),
        .I_video_vsync       ( S_video_out_vsync    ),
        .I_video_rd_en       ( S_hdmi_window_rd_en  ),
        .O_vdieo_data        ( S_video_rd_data      ),
        .O_mon_frame_start  ( S_latency_vo_frame_start ),
        .O_mon_bank         ( S_latency_vo_bank ),
        .O_mon_reset        ( S_latency_vo_reset ),
        .O_mon_burst        ( S_latency_vo_burst ),
        .O_mon_pending      ( S_latency_vo_pending ),
        .O_mon_underflow    ( S_latency_vo_underflow )
    );

    // RAW acceptance to the first pixel at the HDMI encoder input. A report
    // is published only after that display frame completes. The source frame
    // ID follows actual DDR bank transactions rather than a display counter.
    // The monitor contains one two-flop release synchronizer per destination
    // clock. Feed those synchronizers from the raw PLL lock so the passive
    // telemetry block does not create timed paths from the 23.8 MHz reset
    // controller into the 50/60/75 MHz domains. Functional ISP/DDR/HDMI
    // resets remain on S_rst_n/S_hdmi_rst_n elsewhere in this wrapper.
    video_latency_monitor u_video_latency_monitor (
        .I_sys_clk(I_sys_clk), .I_sys_rst_n(S_pll_lock),
        .I_cam_clk(S_csi_rx_clk), .I_cam_rst_n(S_pll_lock),
        .I_guard_sof(S_guard_tuser), .I_guard_done(S_guard_frame_done),
        .I_guard_error(S_guard_frame_error), .I_lane_error(S_lane_error_any),
        .I_isp_valid(S_ISP_O_tvalid), .I_isp_sof(S_ISP_O_tuser),
        .I_capture_overflow(S_latency_capture_overflow),
        .I_ddr_clk(S_ddr_clk), .I_ddr_rst_n(S_pll_lock),
        .I_vi_wr_en(S_vi_ddr_wr_en), .I_vi_addr(S_vi_ddr_wr_addr),
        .I_write_retire(S_ddr_write_retire),
        .I_write_retire_addr(S_ddr_write_retire_addr),
        .I_vo_frame_start(S_latency_vo_frame_start), .I_vo_bank(S_latency_vo_bank),
        .I_vo_reset(S_latency_vo_reset), .I_vo_burst(S_latency_vo_burst),
        .I_vo_rd_en(S_vo_ddr_rd_en), .I_vo_rd_return(S_video_ddr_rd_valid),
        .I_vo_pending(S_latency_vo_pending),
        .I_px_clk(S_hdmi_pixel_clk), .I_px_rst_n(S_pll_lock),
        .I_hdmi_vs(S_badge_out_vsync), .I_hdmi_de(S_badge_out_de),
        .I_vo_underflow(S_latency_vo_underflow),
        .O_report_valid(S_latency_valid), .O_report_frame(S_latency_frame),
        .O_report_tenth_ms(S_latency_tenth_ms), .O_report_toggle(S_latency_toggle)
    );



    mc_to_user_interface u_mc_to_user_interface(
        .I_clk                   ( S_ddr_clk               ),
        .I_rst_n                 ( S_rst_n                 ),

        .I_ddr_user_wr_en        ( S_ddr_user_wr_en        ),
        .I_ddr_user_rd_en        ( S_ddr_user_rd_en        ),
        .I_ddr_user_addr         ( S_ddr_user_addr         ),
        .I_ddr_user_wr_data      ( S_ddr_user_wr_data      ),
        .O_ddr_user_ready        ( S_ddr_user_ready        ),
        .O_ddr_user_rd_valid     ( S_ddr_user_rd_valid     ),
        .O_ddr_user_rd_data      ( S_ddr_user_rd_data      ),
        .O_write_retire          ( S_ddr_write_retire      ),
        .O_write_retire_addr     ( S_ddr_write_retire_addr ),
            
        .O_mc_app_en             ( S_mc_app_en             ),
        .O_mc_app_addr           ( S_mc_app_addr           ),
        .O_mc_app_cmd            ( S_mc_app_cmd            ),
        .I_mc_app_rdy            ( S_mc_app_rdy            ),
        .O_mc_app_wdf_wren       ( S_mc_app_wdf_wren       ),
        .O_mc_app_wdf_data       ( S_mc_app_wdf_data       ),
        .O_mc_app_wdf_end        ( S_mc_app_wdf_end        ),
        .O_mc_app_wdf_mask       ( S_mc_app_wdf_mask       ),
        .I_mc_app_wdf_rdy        ( S_mc_app_wdf_rdy        ),
        .I_mc_app_rd_data        ( S_mc_app_rd_data        ),
        .I_mc_app_rd_data_end    ( S_mc_app_rd_data_end    ),
        .I_mc_app_rd_data_valid  ( S_mc_app_rd_data_valid  )
    );



    ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper(
        // DDR IP was generated for a 100 MHz reference. Keep its refresh,
        // PHY calibration and controller timing at the configured frequency.
        .I_sys_clk              ( S_100m_clk             ),
        .I_sys_rst_n            ( S_phy_rst_n            ),

        .O_ddr_clk              ( S_ddr_clk              ),
        .O_init_calib_complete  ( S_init_calib_complete  ),
        .I_mc_app_addr          ( S_mc_app_addr          ),
        .I_mc_app_cmd           ( S_mc_app_cmd           ),
        .I_mc_app_en            ( S_mc_app_en            ),
        .I_mc_app_wdf_data      ( S_mc_app_wdf_data      ),
        .I_mc_app_wdf_end       ( S_mc_app_wdf_end       ),
        .I_mc_app_wdf_mask      ( S_mc_app_wdf_mask      ),
        .I_mc_app_wdf_wren      ( S_mc_app_wdf_wren      ),
        .O_mc_app_rd_data       ( S_mc_app_rd_data       ),
        .O_mc_app_rd_data_end   ( S_mc_app_rd_data_end   ),
        .O_mc_app_rd_data_valid ( S_mc_app_rd_data_valid ),
        .O_mc_app_rdy           ( S_mc_app_rdy           ),
        .O_mc_app_wdf_rdy       ( S_mc_app_wdf_rdy       ),

        .ddr_addr               ( ddr_addr               ),
        .ddr_ba                 ( ddr_ba                 ),
        .ddr_cke                ( ddr_cke                ),
        .ddr_odt                ( ddr_odt                ),
        .ddr_cs_n               ( ddr_cs_n               ),
        .ddr_ras_n              ( ddr_ras_n              ),
        .ddr_cas_n              ( ddr_cas_n              ),
        .ddr_we_n               ( ddr_we_n               ),
        .ddr_ck_p               ( ddr_ck_p               ),
        .ddr_ck_n               ( ddr_ck_n               ),
        .ddr_dm                 ( ddr_dm                 ),
        .ddr_dq                 ( ddr_dq                 ),
        .ddr_dqs_p              ( ddr_dqs_p              ),
        .ddr_dqs_n              ( ddr_dqs_n              )
    );



    uivtc #(
        .H_ActiveSize ( 1280 ),
        .H_FrameSize  ( 1650 ),
        .H_SyncStart  ( 1390 ),
        .H_SyncEnd    ( 1430 ),
        .V_ActiveSize ( 720  ),
        .V_FrameSize  ( 750  ),
        .V_SyncStart  ( 725  ),
        .V_SyncEnd    ( 730  )
    )u_hdmi_vtc(
        .I_vtc_rstn    ( S_hdmi_rst_n    ),
        .I_vtc_clk     ( S_hdmi_pixel_clk ),
        .O_vtc_vs      ( S_hdmi_vsync     ),
        .O_vtc_hs      ( S_hdmi_hsync     ),
        .O_vtc_de_valid( S_hdmi_de        ),
        .O_vtc_user    ( S_hdmi_user      ),
        .O_vtc_last    ( S_hdmi_last      )
    );

    // Algorithm mode for the OSD.  S_style_mode lives in the S_csi_rx_clk
    // domain; it only changes on a key press and then stays put for many
    // frames, so a plain per-bit 2-FF sync is enough (worst case: the OSD shows
    // the previous name for the ~2 pixel clocks the sync takes to settle).
    reg [4:0] S_mode_px_s1, S_mode_px_s2;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin S_mode_px_s1 <= 5'd0; S_mode_px_s2 <= 5'd0; end
        else begin S_mode_px_s1 <= S_style_mode_eff; S_mode_px_s2 <= S_mode_px_s1; end
    end

    // One motion detector is shared by both modes.  The adapter keeps the
    // 320x180 boundary, with 4x4 luma averaging confined to motion analysis.
    // It receives the direct HDMI stream; display/CNN data are untouched.
    wire S_motion_sample_vld, S_motion_sample_user, S_motion_sample_last;
    wire S_motion_frame_error;
    wire [23:0] S_motion_sample_pix;
    wire S_mix_user, S_mix_last;
    motion_post_hist_adapter u_motion_sample (
        .I_clk  ( S_hdmi_pixel_clk ),
        .I_rst_n( S_hdmi_rst_n ),
        .I_de   ( S_hdmi_de ),
        .I_user ( S_hdmi_user ),
        .I_last ( S_hdmi_last ),
        .I_data ( S_video_rd_data ),
        .O_vld  ( S_motion_sample_vld ),
        .O_user ( S_motion_sample_user ),
        .O_last ( S_motion_sample_last ),
        .O_pix  ( S_motion_sample_pix ),
        .O_frame_error( S_motion_frame_error )
    );
    motion_detect #(
        // Average sensor grain before using a six-count threshold throughout
        // dark/highlight regions. A lower component minimum and 1/32 density
        // retain small/slow moving edges; tile support and two confirmations
        // continue to reject isolated noise. No change to the CNN/ROI pixels.
        .MOTION_TH(8'd10), .DARK_DIFF_TH(8'd6), .DARK_MIN(8'd64),
        .LUMA_ADAPTIVE(1), .BRIGHT_MIN(8'd192), .BRIGHT_DIFF_TH(8'd6),
        .MIN_AREA(16'd48), .DENSITY_SHIFT(5),
        .CONFIRM(2), .INPUT_GRID(1), .LOCAL_FILTER(0), .TILE_MIN_COUNT(7'd4)
    ) u_motion_post_hist (
        .I_clk  ( S_hdmi_pixel_clk ),
        .I_rst_n( S_hdmi_rst_n ),
        .I_en   ( 1'b1 ),
        .I_vld  ( S_motion_sample_vld ),
        .I_tuser( S_motion_sample_user ),
        .I_tlast( S_motion_sample_last ),
        .I_pix  ( S_motion_sample_pix ),
        .I_frame_error( S_motion_frame_error ),
        .O_valid( S_post_mot_valid ),
        .O_x_min( S_post_mot_x_min ),
        .O_y_min( S_post_mot_y_min ),
        .O_x_max( S_post_mot_x_max ),
        .O_y_max( S_post_mot_y_max ),
        .O_count( S_post_mot_count ),
        .O_commit( S_post_mot_commit ),
        .O_empty( S_post_mot_empty )
    );

    pll u_eth_pll(
        .refclk(I_sys_clk), .reset(~S_pll_lock),
        .clk0_out(S_125m_clk), .clk1_out(S_125m_90_clk),
        .clk2_out(), .lock(S_eth_pll_lock));
    reset_sync u_rst_eth(
        .I_clk(S_125m_clk),
        .I_async_rst_n(S_pll_lock & S_eth_pll_lock),
        .O_rst_n(S_eth_rst_n));
    PH1P_LOGIC_BUFG u_eth_pll_90_bufg(.i(S_125m_90_clk),.o(S_125m_90_clk_b));

    // Direct HDMI path. Keeping the five timing markers and pixel data on the
    // same source preserves the original latency and frame alignment.
    wire        S_display_vsync;
    wire        S_display_hsync;
    wire        S_display_de;
    wire        S_display_user;
    wire        S_display_last;
    wire [23:0] S_display_data;
    a4_display_spatial_h1 #(.ENABLE(1), .EDGE_TH(24)) u_display_spatial_h1 (
        .I_clk   ( S_hdmi_pixel_clk ),
        .I_rst_n ( S_hdmi_rst_n ),
        .I_vsync ( S_hdmi_vsync ),
        .I_hsync ( S_hdmi_hsync ),
        .I_de    ( S_hdmi_de ),
        .I_user  ( S_hdmi_user ),
        .I_last  ( S_hdmi_last ),
        .I_data  ( S_video_rd_data ),
        .O_vsync ( S_display_vsync ),
        .O_hsync ( S_display_hsync ),
        .O_de    ( S_display_de ),
        .O_user  ( S_display_user ),
        .O_last  ( S_display_last ),
        .O_data  ( S_display_data )
    );

    wire        S_mix_vsync = S_display_vsync;
    wire        S_mix_hsync = S_display_hsync;
    assign      S_mix_de    = S_display_de;
    assign      S_mix_user  = S_display_user;
    assign      S_mix_last  = S_display_last;
    assign      S_mix_data  = S_display_data;

    reg S_show_vs_d;
    // Synchronise the stable peer-online indication into HDMI. SW2 gates it
    // so PC-host mode cannot display a stale secondary-board status.
    reg S_aux_online_px_s1, S_aux_online_px_s2;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
      if(!S_hdmi_rst_n) begin
        S_aux_online_px_s1 <= 1'b0; S_aux_online_px_s2 <= 1'b0;
      end else begin
        S_aux_online_px_s1 <= S_aux_online;
        S_aux_online_px_s2 <= S_aux_online_px_s1;
      end
    end
    wire S_aux_link_px = S_aux_online_px_s2;
    doc_copy_status_cdc u_copy_status_cdc(.src_clk(S_125m_clk),.src_rst_n(S_eth_rst_n),
        .src_state(S_copy_state_eth),.px_clk(S_hdmi_pixel_clk),.px_rst_n(S_hdmi_rst_n),
        .frame_start(S_hdmi_vsync&&!S_show_vs_d),.staged(S_copy_state_px));
    doc_copy_status_cdc u_pcb_status_cdc(.src_clk(S_125m_clk),.src_rst_n(S_eth_rst_n),
        .src_state(S_pcb_status_eth),.px_clk(S_hdmi_pixel_clk),.px_rst_n(S_hdmi_rst_n),
        .frame_start(S_hdmi_vsync&&!S_show_vs_d),.staged(S_pcb_status_px));
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
      if(!S_hdmi_rst_n) S_show_vs_d<=0;else S_show_vs_d<=S_hdmi_vsync;
    wire S_show_valid,S_show_remote,S_show_commit_toggle,S_show_pcb,S_show_pcb_checked,S_show_pcb_good;
    wire [10:0] S_show_x0,S_show_x1,S_show_cx;
    wire [9:0] S_show_y0,S_show_y1,S_show_cy;
    wire [23:0] S_show_area;
    wire [1:0] S_show_color,S_show_shape;
    wire [3:0] S_show_class_id,S_show_conf_tens,S_show_conf_ones;
    wire [7:0] S_show_confidence;
    hx_result_select u_result_select(
      .net_clk(S_125m_clk),.net_rst_n(S_eth_rst_n),.remote_enable(1'b1),.remote_online(S_aux_online),.remote_pcb(S_mode_pcb_eth),
      .remote_toggle(S_aux_result_toggle),.remote_valid(S_aux_result_valid),.remote_data(S_aux_result_data),
      .remote_clear(S_mode_pcb_eth && S_snap_capture_req),
      // Use the synchronized switch directly at the frame boundary.  The
      // registered S_ovl_on is updated on S_hdmi_user (the first active
      // pixel), which is later than frame_start; using it here could consume
      // a newly arrived result while overlay_enable was still zero.
      .px_clk(S_hdmi_pixel_clk),.px_rst_n(S_hdmi_rst_n),.frame_start(S_hdmi_vsync && !S_show_vs_d),
      .overlay_enable(S_sw2_px_s2 || S_mode_pcb_px),
      .local_valid(S_ovl_valid),.local_x0(S_ovl_x0),.local_x1(S_ovl_x1),.local_cx(S_ovl_cx),
      .local_y0(S_ovl_y0),.local_y1(S_ovl_y1),.local_cy(S_ovl_cy),.local_area(S_ovl_area),
      .local_color(S_ovl_color),.local_shape(S_ovl_shape),.local_class(S_ovl_class_id),
      .local_confidence(S_ovl_confidence),.local_tens(S_ovl_conf_tens),.local_ones(S_ovl_conf_ones),
      .valid(S_show_valid),.remote_source(S_show_remote),.toggle(S_show_commit_toggle),
      .pcb_mode(S_show_pcb),.pcb_checked(S_show_pcb_checked),.pcb_good(S_show_pcb_good),
      .x0(S_show_x0),.x1(S_show_x1),.cx(S_show_cx),.y0(S_show_y0),.y1(S_show_y1),.cy(S_show_cy),
      .area(S_show_area),.color(S_show_color),.shape(S_show_shape),.class_id(S_show_class_id),
      .confidence(S_show_confidence),.conf_tens(S_show_conf_tens),.conf_ones(S_show_conf_ones));

    // Type18 metadata crosses through a held request/ack mailbox and only
    // commits during HDMI blanking. Never feed the raw Ethernet bus to pixels.
    wire S_multi_px_valid,S_multi_px_toggle;
    wire [2:0] S_multi_px_count;
    wire [511:0] S_multi_px_boxes;
    wire [31:0] S_multi_px_job;
    hxa_multibox_cdc u_multibox_cdc(
      .I_src_clk(S_125m_clk),.I_src_rst_n(S_eth_rst_n),
      .I_src_online(S_aux_online && S_mode_cnn_eth),
      .I_src_valid(S_aux_multi_valid),
      .I_src_toggle(S_aux_multi_toggle),.I_src_count(S_aux_multi_count),
      .I_src_data(S_aux_multi_data),.I_src_job(S_aux_multi_job),
      .I_px_clk(S_hdmi_pixel_clk),.I_px_rst_n(S_hdmi_rst_n),
      .I_px_frame_start(S_hdmi_vsync && !S_show_vs_d),
      // S_ovl_on is frame-latched at the first active pixel.  The mailbox
      // commits at VSYNC, so gate it with the already synchronized SW2 value
      // to avoid dropping a Type18 update on the switch-transition frame.
      .I_px_enable(S_sw2_px_s2 && S_mode_cnn_px),
      .O_valid(S_multi_px_valid),.O_count(S_multi_px_count),
      .O_data(S_multi_px_boxes),.O_job(S_multi_px_job),.O_toggle(S_multi_px_toggle));

    // The fixed OSD summarizes the first (best-ranked) type18 box from the
    // same frame snapshot. Type8/PCB keep their established metadata path.
    reg S_multi_summary_toggle;
    reg [10:0] S_multi_cx;
    reg [9:0] S_multi_cy;
    reg [1:0] S_multi_color,S_multi_shape;
    reg [3:0] S_multi_tens,S_multi_ones;
    reg [7:0] S_multi_base;
    wire [7:0] S_multi_conf={1'b0,S_multi_px_boxes[86:80]};
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)begin
      if(!S_hdmi_rst_n)begin
        S_multi_summary_toggle<=0;S_multi_cx<=0;S_multi_cy<=0;
        S_multi_color<=0;S_multi_shape<=0;S_multi_tens<=0;S_multi_ones<=0;
      end else begin
        S_multi_summary_toggle<=S_multi_px_toggle;
        if(S_multi_summary_toggle!=S_multi_px_toggle)begin
          S_multi_cx<=({1'b0,S_multi_px_boxes[10:0]}+{1'b0,S_multi_px_boxes[42:32]})>>1;
          S_multi_cy<=({1'b0,S_multi_px_boxes[25:16]}+{1'b0,S_multi_px_boxes[57:48]})>>1;
          S_multi_color<=(S_multi_px_boxes[67:64]<=3)?1:(S_multi_px_boxes[67:64]<=6)?2:3;
          case(S_multi_px_boxes[67:64])
            1,4,7:S_multi_shape<=1;2,5,8:S_multi_shape<=2;3,6,9:S_multi_shape<=3;
            default:S_multi_shape<=0;
          endcase
          if(S_multi_conf>=100)begin S_multi_tens<=0;S_multi_base=100;end
          else if(S_multi_conf>=90)begin S_multi_tens<=9;S_multi_base=90;end
          else if(S_multi_conf>=80)begin S_multi_tens<=8;S_multi_base=80;end
          else if(S_multi_conf>=70)begin S_multi_tens<=7;S_multi_base=70;end
          else if(S_multi_conf>=60)begin S_multi_tens<=6;S_multi_base=60;end
          else if(S_multi_conf>=50)begin S_multi_tens<=5;S_multi_base=50;end
          else if(S_multi_conf>=40)begin S_multi_tens<=4;S_multi_base=40;end
          else if(S_multi_conf>=30)begin S_multi_tens<=3;S_multi_base=30;end
          else if(S_multi_conf>=20)begin S_multi_tens<=2;S_multi_base=20;end
          else if(S_multi_conf>=10)begin S_multi_tens<=1;S_multi_base=10;end
          else begin S_multi_tens<=0;S_multi_base=0;end
          S_multi_ones<=S_multi_conf-S_multi_base;
        end
      end
    end
    wire S_summary_valid=S_multi_px_valid?(S_multi_px_count!=0):S_show_valid;
    wire [1:0] S_summary_color=S_multi_px_valid?S_multi_color:S_show_color;
    wire [1:0] S_summary_shape=S_multi_px_valid?S_multi_shape:S_show_shape;
    wire [23:0] S_summary_area=S_multi_px_valid?{4'd0,S_multi_px_boxes[115:96]}:S_show_area;
    wire [7:0] S_summary_conf=S_multi_px_valid?S_multi_conf:S_show_confidence;
    wire [3:0] S_summary_tens=S_multi_px_valid?S_multi_tens:S_show_conf_tens;
    wire [3:0] S_summary_ones=S_multi_px_valid?S_multi_ones:S_show_conf_ones;

    // Automatic PCB localization displays only the current accepted Type8
    // workpiece, using the original-image coordinates committed by the CDC.
    // PCB remains visible with SW2 off, but has no fabricated placement box.
    // SCANNING/READY suppress the previous job and the PCB tag rejects a
    // pending ordinary-CNN result during a mode transition.
    wire S_pcb_window_on = S_mode_pcb_px;
    wire S_pcb_current_result = S_show_remote && S_show_pcb &&
        (S_pcb_status_px >= 3'd2) && (S_pcb_status_px <= 3'd4);
    wire S_box_valid = S_pcb_window_on ?
        (S_show_valid && S_pcb_current_result) : S_summary_valid;
    // Equivalent Boolean absorption: PCB ? show : (multi ? multi : show).
    // Make the single shared selector explicit for all coordinate bits.
    wire S_use_multi_box = S_multi_px_valid && !S_pcb_window_on;
    wire [10:0] S_box_x0 = S_use_multi_box ? S_multi_px_boxes[10:0] : S_show_x0;
    wire [10:0] S_box_x1 = S_use_multi_box ? S_multi_px_boxes[42:32]-11'd1 : S_show_x1;
    wire [10:0] S_box_cx = S_use_multi_box ? S_multi_cx : S_show_cx;
    wire [9:0] S_box_y0 = S_use_multi_box ? S_multi_px_boxes[25:16] : S_show_y0;
    wire [9:0] S_box_y1 = S_use_multi_box ? S_multi_px_boxes[57:48]-10'd1 : S_show_y1;
    wire [9:0] S_box_cy = S_use_multi_box ? S_multi_cy : S_show_cy;

    hdmi_mixer #(
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .DEBUG_MODE ( 0    ),
        // The upper-left colour/logo tiles are debug decoration and obscure
        // the CART image.  Keep the OSD text and recognition overlays.
        .LOGO_ENABLE( 1    ),
        .LATENCY_OSD_ENABLE( 1 )
    )u_hdmi_mixer(
        .I_clk           ( S_hdmi_pixel_clk   ),
        .I_rst_n         ( S_hdmi_rst_n       ),
        .I_video_vsync   ( S_mix_vsync         ),
        .I_video_hsync   ( S_mix_hsync         ),
        .I_video_de      ( S_mix_de            ),
        .I_video_user    ( S_mix_user          ),
        .I_video_last    ( S_mix_last          ),
        .I_debug_status  ( S_hdmi_debug_status),
        .I_algo_mode     ( S_mode_px_s2       ),
        .I_latency_valid( S_latency_valid ),
        .I_latency_frame( S_latency_frame ),
        .I_latency_tenth_ms( S_latency_tenth_ms ),
        .I_latency_toggle( S_latency_toggle ),
        .I_he_on         ( 1'b0                ),
        .I_ovl_on        ( S_pcb_window_on || (S_ovl_on && !S_mode_text_px) ),
        .I_ovl_valid     ( S_box_valid        ),
        .I_ovl_x0        ( S_box_x0           ),
        .I_ovl_y0        ( S_box_y0           ),
        .I_ovl_x1        ( S_box_x1           ),
        .I_ovl_y1        ( S_box_y1           ),
        .I_ovl_cx        ( S_box_cx           ),
        .I_ovl_cy        ( S_box_cy           ),
        .I_ovl_color     ( (S_summary_color == 2'd1) ? 2'd0 :
                           (S_summary_color == 2'd2) ? 2'd1 :
                           (S_summary_color == 2'd3) ? 2'd2 : 2'd3 ),
        .I_ovl_shape     ( S_summary_shape == 2'd2 ),
        .I_ovl_remote(S_pcb_window_on || S_show_remote || S_aux_link_px),.I_ovl_shape3(S_summary_shape),
        .I_ovl_pcb(S_pcb_window_on || S_show_pcb),
        .I_pcb_checked(S_show_pcb && S_show_valid && S_show_pcb_checked),
        .I_pcb_good(S_show_pcb && S_show_valid && S_show_pcb_good),
        .I_pcb_status(S_pcb_status_px),
        .I_ovl_area      ( S_summary_area           ),
        .I_ovl_confidence( S_summary_conf     ),
        .I_ovl_conf_tens ( S_summary_tens      ),
        .I_ovl_conf_ones ( S_summary_ones      ),
        .I_multi_valid   ( S_multi_px_valid && !S_pcb_window_on ),
        .I_multi_count   ( S_multi_px_count ),
        .I_multi_boxes   ( S_multi_px_boxes ),
        .I_multi_toggle  ( S_multi_px_toggle ),
        .I_aux_online    ( S_aux_link_px ),
        .I_copy_mode     ( S_mode_text_px ),.I_copy_state(S_copy_state_px),
        .I_mot_on        ( S_mot_on_eff       ),
        .I_mot_x0        ( S_mot_x0_eff       ),
        .I_mot_y0        ( S_mot_y0_eff       ),
        .I_mot_x1        ( S_mot_x1_eff       ),
        .I_mot_y1        ( S_mot_y1_eff       ),
        .I_motion_count  ( S_mot_cnt_eff      ),
        .I_motion_enable ( S_sw1_px_s2        ),
        .O_video_rd_en   ( S_hdmi_window_rd_en),
        .I_video_rd_req  ( S_hdmi_de          ),
        .I_video_rd_data ( S_mix_data         ),
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    )
    );

    // Recognition badge is deliberately placed after the proven mixer path.
    // It adds one output stage only and never feeds back into DDR read timing.
    // The classifier emits zero BCD digits for 100%; derive the hundreds
    // digit from the already registered confidence without division.
    wire [3:0] S_ovl_conf_hundreds = (S_show_confidence >= 8'd100) ? 4'd1 : 4'd0;
    result_overlay #(
        .IMG_WIDTH  (1280),
        .IMG_HEIGHT (720),
        .BADGE_W    (128),
        .BADGE_H    (16),
        // The lower-left pipeline squares were a bring-up aid.  Keep the
        // diagnostic input wired for optional debug builds, but remove the
        // green status marker from the normal HDMI image.
        .DIAGNOSTIC_ENABLE(0),.HIDE_PCB_BADGE(1)
    ) u_result_overlay (
        .I_clk            ( S_hdmi_pixel_clk ),
        .I_rst_n          ( S_hdmi_rst_n     ),
        // Left to right: config sent, MIPI HS, RAW, ISP, DDR calibrated,
        // write request, read response, nonzero display pixel.  Sticky
        // milestones locate a stalled camera path without an ILA rebuild.
        .I_pipeline_status({S_dbg_video_nonzero_seen,
                            S_dbg_ddr_rd_seen_sync[1],
                            S_dbg_ddr_wr_seen_sync[1],
                            S_dbg_mc_init_seen_sync[1],
                            S_dbg_isp_valid_seen_sync[1],
                            S_dbg_raw10_seen_sync[1],
                            S_dbg_hs_seen_sync[1],
                            S_dbg_cam_cfg_seen_sync[1]}),
        .I_distance_mode  ( 1'b0              ),
        .I_distance_valid ( 1'b0              ),
        .I_distance_bcd   ( 16'd0             ),
        .I_distance_toggle( 1'b0              ),
        .I_video_rgb      ( S_hdmi_out_data  ),
        .I_video_de       ( S_hdmi_out_de    ),
        .I_video_hs       ( S_hdmi_out_hsync ),
        .I_video_vs       ( S_hdmi_out_vsync ),
        .I_video_user     ( 1'b0             ),
        .I_video_last     ( 1'b0             ),
        .I_enable         ( S_ovl_on && !S_mode_text_px && !S_multi_px_valid && !S_pcb_window_on ),
        .I_valid          ( S_show_valid      ),
        .I_x0             ( S_show_x0          ),
        .I_x1             ( S_show_x1          ),
        .I_cx             ( S_show_cx          ),
        .I_y0             ( S_show_y0          ),
        .I_y1             ( S_show_y1          ),
        .I_cy             ( S_show_cy          ),
        .I_remote(S_show_remote | S_aux_link_px),.I_color(S_show_color),.I_shape(S_show_shape),
        .I_pcb_mode(S_pcb_window_on || S_show_pcb),.I_pcb_checked(S_show_pcb_checked),.I_pcb_good(S_show_pcb_good),
        .I_class_id       ( S_show_class_id    ),
        .I_confidence     ( S_show_confidence  ),
        .I_conf_hundreds  ( S_ovl_conf_hundreds ),
        .I_conf_tens      ( S_show_conf_tens   ),
        .I_conf_ones      ( S_show_conf_ones   ),
        .I_toggle         ( S_show_commit_toggle ),
        .O_video_rgb      ( S_badge_out_data  ),
        .O_video_de       ( S_badge_out_de    ),
        .O_video_hs       ( S_badge_out_hsync ),
        .O_video_vs       ( S_badge_out_vsync ),
        .O_video_user     ( S_badge_out_user  ),
        .O_video_last     ( S_badge_out_last  )
    );

    // Actual display status is captured by the network mailbox in the
    // pixel domain. DDR calibration is the only new asynchronous input.
    // Keep the DDR calibration synchronizer as an explicit two-register CDC.
    // The physical optimizer may otherwise repack the first-stage D input into
    // an unrelated DDR-init LUT when the RAW-domain logic changes placement.
    (* ASYNC_REG = "TRUE", dont_touch = "true" *) reg S_board_ddr_px_s1, S_board_ddr_px_s2;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if (!S_hdmi_rst_n) begin
            S_board_ddr_px_s1 <= 1'b0;
            S_board_ddr_px_s2 <= 1'b0;
        end else begin
            S_board_ddr_px_s1 <= S_init_calib_complete;
            S_board_ddr_px_s2 <= S_board_ddr_px_s1;
        end
    end
    wire [63:0] S_board_status_pix = {
        16'd0, S_latency_tenth_ms, S_latency_frame, 1'b0,
        S_latency_valid, S_board_ddr_px_s2, S_hdmi_debug_status,
        S_sw4_px_s2, S_sw3_px_s2, S_sw2_px_s2, S_sw1_px_s2, S_ovl_on, S_mode_px_s2
    };

    // One snapshot/HXA1/MAC/ARP/IP/UDP/RGMII path serves both modes.
    // SW2=0: PC .1:6003 video, .1:6001 CONFIG/status. SW2=1: secondary
    // .3:6003 CNN/PCB. The transport flushes in-flight work on mode changes.
    udp_config_status #(
        .ENABLE_VIDEO_PREVIEW(ENABLE_VIDEO_PREVIEW),
        .ENABLE_HOST_HXA_PREVIEW(ENABLE_HOST_HXA_PREVIEW),
        .VIDEO_FRAME_DIV(4),
        .ENABLE_EXTENDED_RESULTS(0),
        .ENABLE_AWB_DIAG(0)
    ) u_udp_cfg (
        // Type11 observation is removed at compile time.
        .I_awb_diag_data(224'd0), .I_awb_diag_ack(1'b0),
        .I_awb_diag_source_rst_n(1'b0),
        .O_awb_diag_req(), .O_awb_diag_rst_n(),
        .I_aux_mode(1'b1),.I_aux_tx_req(S_aux_tx_req),.I_aux_tx_valid(S_aux_tx_valid),
        .I_aux_stack_reset(S_aux_stack_reset),.I_aux_tx_data(S_aux_tx_data),.I_aux_tx_len(S_aux_tx_len),
        .I_aux_peer_ip(32'hc0a8a003),.I_aux_peer_port(16'd6003),
        .O_aux_tx_busy(S_aux_tx_busy),.O_aux_rx_valid(S_aux_rx_valid),.O_aux_rx_error(S_aux_rx_error),
        .O_aux_ready(S_aux_ready),.O_aux_rx_data(S_aux_rx_data),.O_aux_rx_len(S_aux_rx_len),
        .I_clk125         ( S_125m_clk       ),
        .I_clk125_90      ( S_125m_90_clk_b   ),
        .I_clk_pix        ( S_hdmi_pixel_clk ),
        .I_rst_n          ( S_eth_link_rst_n ),
        .I_rst_pix_n      ( S_eth_preview_rst_n ),
        .I_rgmii_rxd      ( I_rgmii_rxd       ),
        .I_rgmii_rx_ctl   ( I_rgmii_rx_ctl    ),
        .I_rgmii_rxc      ( I_rgmii_rxc       ),
        .O_rgmii_txd      ( O_rgmii_txd       ),
        .O_rgmii_tx_ctl   ( O_rgmii_tx_ctl    ),
        .O_rgmii_txc      ( O_rgmii_txc       ),
        .O_phy_rst        ( O_phy_rst         ),
        .I_pix            ( S_net_pix         ),
        .I_pix_de         ( S_net_de          ),
        .I_pix_sof        ( S_net_sof         ),
        .I_pix_eof        ( S_net_eof         ),
        .I_frame_period   ( 32'd1250000       ),
        .I_target_count   ( {19'd0,S_ovl_valid} ),
        .I_motion_count   ( {4'd0,S_mot_cnt_eff}  ),
        .I_latency_us     ( 32'd0             ),
        .I_status_flags   ( {4'd0,S_hdmi_debug_status} ),
        .I_app_mode       ( {1'b0,S_mode_sel_eth} ),
        .I_app_armed      ( 1'b0             ),
        .I_peer_online    ( 1'b0  ),
        .I_last_action    ( 8'd0             ),
        .I_action_result  ( 8'd0             ),
        .I_action_retries ( 2'd0             ),
        .I_uart_errors    ( 16'd0            ),
        .I_board_status_pix(S_board_status_pix),
        .I_hxa_sent_frames(S_aux_sent_frames),.I_hxa_failed_frames(S_aux_failed_frames),
        .I_snapshot_frame_id(S_snap_frame_id),.I_hxa_online(S_aux_online),.I_hxa_job_state(S_aux_job_state),
        .O_cfg_mode       ( S_eth_mode       ),
        .O_cfg_threshold  ( S_eth_threshold  ),
        .O_cfg_brightness ( S_eth_brightness ),
        .O_cfg_target_color( S_eth_target_color ),
        .O_cfg_detect_en  ( S_eth_detect_en  ),
        .O_cfg_heq_en     ( S_eth_heq_en     ),
        .O_cfg_cnn_mode   ( S_eth_cnn_mode   ),
        .O_cfg_auto_quality( S_eth_auto_quality ),
        .O_cfg_awb_enable ( S_eth_awb_en     ),
        .O_cfg_ae_enable  ( S_eth_ae_en      ),
        .O_cfg_ag_enable  ( S_eth_ag_en      ),
        .O_cfg_quality_heq_enable( S_eth_quality_heq_en ),
        .O_cfg_app_mode   ( S_eth_app_mode   ),
        .O_cfg_app_mode_valid( S_eth_app_mode_valid ),
        .O_cfg_valid      ( S_eth_cfg_valid  ),
        .O_cnn_frame_id   ( S_eth_cnn_frame_id ),
        .O_cnn_inference_us( S_eth_cnn_inference_us ),
        .O_cnn_target_num ( S_eth_cnn_target_num ),
        .O_cnn_bbox       ( S_eth_cnn_bbox ),
        .O_cnn_class_id   ( S_eth_cnn_class_id ),
        .O_cnn_confidence ( S_eth_cnn_confidence ),
        .O_cnn_flags      ( S_eth_cnn_flags ),
        .O_cnn_label      ( S_eth_cnn_label ),
        .O_cnn_valid      ( S_eth_cnn_valid ),
        .O_cnn_heartbeat  ( S_eth_cnn_heartbeat ),
        .O_action_sequence( S_eth_action_sequence ),
        .O_action_frame_id( S_eth_action_frame_id ),
        .O_action_app_mode( S_eth_action_app_mode ),
        .O_action_id      ( S_eth_action_id ),
        .O_action_confidence( S_eth_action_confidence ),
        .O_action_evidence( S_eth_action_evidence ),
        .O_action_ttl_ms  ( S_eth_action_ttl_ms ),
        .O_action_cooldown_ms( S_eth_action_cooldown_ms ),
        .O_action_flags   ( S_eth_action_flags ),
        .O_action_label   ( S_eth_action_label ),
        .O_action_valid   ( S_eth_action_valid ),
        .O_session_ready  ( S_eth_session_ready )
    );

    hdmi_tx u_hdmi_tx(
        .I_pixel_clk        ( S_hdmi_pixel_clk  ),
        .I_serial_clk       ( S_hdmi_serial_clk ),
        .I_rst              ( ~S_hdmi_rst_n     ),
        .I_serializer_rst   ( ~S_hdmi_serializer_rst_serial_sync2 ),
        .I_key_in           ( 1'b0              ),
        .I_edid_read_trig   ( 1'b0              ),
        .O_edid_read_valid  (                   ),
        .O_edid_read_data   (                   ),
        .I_video_rgb_enable ( 1'b1              ),
        .I_video_in_vs      ( S_badge_out_vsync  ),
        .I_video_in_de      ( S_badge_out_de     ),
        .I_video_in_user    ( 1'b0              ),
        .I_video_in_valid   ( 1'b0              ),
        .I_video_in_last    ( 1'b0              ),
        .O_video_in_ready   (                   ),
        .I_video_in_data    ( S_badge_out_data   ),
        .I_audio_valid      ( 1'b0              ),
        .I_audio_left_data  ( 24'd0             ),
        .I_audio_right_data ( 24'd0             ),
        .I_i2s_BCLK         ( 1'b0              ),
        .I_i2s_LRCK         ( 1'b0              ),
        .I_i2s_DOUT         ( 1'b0              ),
        .O_ddc_scl          (                   ),
        .O_hdmi_clk_p       (                   ),
        .O_hdmi_tx_p        (                   ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p      ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p      ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p      ),
        .O_tmds_clk_p       ( O_tmds_clk_p      )
    );


    
endmodule
