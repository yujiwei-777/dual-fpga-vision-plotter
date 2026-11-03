    key4_pcb_status u_pcb_status(
        .clk(S_125m_clk),.rst_n(S_eth_rst_n),.mode_active(S_mode_pcb_eth),
        .key_press(S_pcb_key4_press),.phy_ready(S_aux_ready),.online(S_aux_online),
        .capture_req(S_snap_capture_req),.capture_cancel(S_snap_cancel),
        .result_toggle(S_aux_result_toggle),.result_valid(S_aux_result_valid),
        .target_valid(S_aux_result_data[96]),.result_checked(S_aux_result_data[98]),
        .result_good(S_aux_result_data[97]),.status(S_pcb_status_eth));
    doc_copy_status_cdc u_pcb_status_cdc(.src_clk(S_125m_clk),.src_rst_n(S_eth_rst_n),
        .src_state(S_pcb_status_eth),.px_clk(S_hdmi_pixel_clk),.px_rst_n(S_hdmi_rst_n),
        .frame_start(S_hdmi_vsync&&!S_show_vs_d),.staged(S_pcb_status_px));
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
