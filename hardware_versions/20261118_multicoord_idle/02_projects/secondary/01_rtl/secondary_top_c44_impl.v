// PH1P35 secondary board: complete-frame HXA1 -> DDR -> CNN/PCB -> GRBL.
// Both SW2 positions use the production main-board link (.2:6002).  I_sw2 is
// retained as a physical/pin-compatible input, but is deliberately ignored.
// Plotter motion uses the fixed board A4 profile; only the ESP32 LINK_READY
// input and the reporter's transport checks can admit a job.
module secondary_top #(
    // This independent PCB variant defaults to the resource-reduced GOOD/BAD
    // head.  The legacy three-class path remains available by overriding the
    // parameters; ordinary CNN, document-copy, HXA1 and GRBL paths are unchanged.
    parameter integer PCB_BINARY_CLASSES=1,
    parameter integer PCB_BINARY_C1_CHANNELS=4,
    parameter integer PCB_BINARY_C2_CHANNELS=4
)(
    input wire I_sys_clk,I_sw2,I_key1_n,I_key2_n,I_key3_n,I_key4_n,
    input wire [3:0] I_rgmii_rxd,
    input wire I_rgmii_rx_ctl,I_rgmii_rxc,
    output wire [3:0] O_rgmii_txd,
    output wire O_rgmii_tx_ctl,O_rgmii_txc,O_phy_rst,
    input wire I_uart_rx,I_esp_link_ready,
    output wire O_uart_tx,
    output wire [12:0] ddr_addr,
    output wire [1:0] ddr_ba,
    output wire [0:0] ddr_cke,ddr_odt,ddr_cs_n,ddr_ck_p,ddr_ck_n,
    output wire ddr_ras_n,ddr_cas_n,ddr_we_n,
    inout wire [1:0] ddr_dm,ddr_dqs_p,ddr_dqs_n,
    inout wire [15:0] ddr_dq,
    output wire [3:0] O_led
);
    // Configuration initializes the POR counter; release after 20.97 ms at 50M.
    reg [19:0] por_count=0;
    always @(posedge I_sys_clk)if(!(&por_count))por_count<=por_count+1'b1;
    wire por_release=&por_count;
    wire clk125,clk125_90_raw,clk125_90,pll_locked,rst125_n;
    pll u_eth_pll(.refclk(I_sys_clk),.reset(!por_release),.clk0_out(clk125),
        .clk1_out(clk125_90_raw),.clk2_out(),.lock(pll_locked));
    PH1P_LOGIC_BUFG u_eth_pll_90_bufg(.i(clk125_90_raw),.o(clk125_90));
    // Keep PLL lock out of the asynchronous reset release.  Lock is generated
    // in another clock domain and creates a recovery path into eth125.
    // The Ethernet/DDR blocks already gate traffic with their synchronized
    // ready and calibration handshakes.
    reset_sync u_reset125(.I_clk(clk125),.I_async_rst_n(por_release),.O_rst_n(rst125_n));
    // The secondary board has the same active-low KEY1 pin as the main board
    // (D5). A local press reports the latest ordinary-CNN result directly to
    // the plotter; it does not inject a packet into HXA1 or alter Type18.
    reg key1_meta,key1_sync,key1_d;
    reg [21:0] key1_lock;
    reg key1_report_pulse;
    always @(posedge clk125 or negedge rst125_n) begin
        if(!rst125_n) begin
            key1_meta<=1'b1; key1_sync<=1'b1; key1_d<=1'b1;
            key1_lock<=22'd0; key1_report_pulse<=1'b0;
        end else begin
            key1_meta<=I_key1_n; key1_sync<=key1_meta; key1_d<=key1_sync;
            key1_report_pulse<=1'b0;
            if(key1_lock!=0) key1_lock<=key1_lock-1'b1;
            // One report per press; holding the key does not retrigger while
            // the debounce lock is active. This matches the main-board KEY1
            // electrical behavior and prevents duplicate plotter jobs.
            if(key1_d && !key1_sync && key1_lock==0) begin
                key1_report_pulse<=1'b1;
                key1_lock<=22'd2500000; // 20 ms at 125 MHz
            end
        end
    end
    reg [20:0] phy_reset_count;
    reg phy_up;
    always @(posedge clk125 or negedge rst125_n)begin
        if(!rst125_n)begin phy_reset_count<=0;phy_up<=0;end
        else if(!phy_up)begin
            if(phy_reset_count==1250000-1)phy_up<=1;
            else phy_reset_count<=phy_reset_count+1'b1;
        end
    end
    assign O_phy_rst=phy_up;
    // SW2 used to select the retired PC configuration path.  The production
    // image has one network mode only, so remove the synchronizer/debounce
    // logic and make the mode a constant.  Keeping I_sw2 in the module
    // interface preserves the existing pin map and out-of-tree wrappers.
    wire board_mode = 1'b1;

    wire ddr_clk,calibrated,store_rst125_n,store_rstddr_n;
    wire ddr_ref100,ddr_ref_locked;
    // Original DDR IP was generated for a 100 MHz reference (tCK=1876 ps).
    // Reuse the existing 50 -> 100 MHz PLL source without regenerating IP.
    PLL u_ddr_ref_pll(.refclk(I_sys_clk),.reset(!por_release),.clk0_out(ddr_ref100),
        .clk1_out(),.clk4_out(),.clk5_out(),.lock(ddr_ref_locked));
    wire [24:0] app_addr;wire [2:0] app_cmd;wire app_en,app_wdf_end,app_wdf_wren;
    wire [127:0] app_wdf_data,app_rd_data;wire [15:0] app_wdf_mask;
    wire app_rdy,app_wdf_rdy,app_rd_valid;
    secondary_ddr_wrapper u_ddr(.I_sys_clk(ddr_ref100),.I_sys_rst_n(por_release&&ddr_ref_locked),
        .O_ddr_clk(ddr_clk),.O_init_calib_complete(calibrated),
        .I_mc_app_addr(app_addr),.I_mc_app_cmd(app_cmd),.I_mc_app_en(app_en),
        .I_mc_app_wdf_data(app_wdf_data),.I_mc_app_wdf_end(app_wdf_end),.I_mc_app_wdf_mask(app_wdf_mask),.I_mc_app_wdf_wren(app_wdf_wren),
        .O_mc_app_rd_data(app_rd_data),.O_mc_app_rd_data_end(),.O_mc_app_rd_data_valid(app_rd_valid),
        .O_mc_app_rdy(app_rdy),.O_mc_app_wdf_rdy(app_wdf_rdy),
        .ddr_addr(ddr_addr),.ddr_ba(ddr_ba),.ddr_cke(ddr_cke),.ddr_odt(ddr_odt),.ddr_cs_n(ddr_cs_n),
        .ddr_ras_n(ddr_ras_n),.ddr_cas_n(ddr_cas_n),.ddr_we_n(ddr_we_n),.ddr_ck_p(ddr_ck_p),.ddr_ck_n(ddr_ck_n),
        .ddr_dm(ddr_dm),.ddr_dq(ddr_dq),.ddr_dqs_p(ddr_dqs_p),.ddr_dqs_n(ddr_dqs_n));
    // DDR calibration is asynchronous to the mailbox DDR clock. Do not feed
    // the raw signal into an async-reset pin: that creates a recovery path
    // from the DDR init state machine into clk125 (the former -3.5 ns path).
    // The 125 MHz mailbox clock already has the identical POR synchronizer
    // above, so share that reset explicitly instead of instantiating a second
    // equivalent reset_sync. This prevents synthesis from silently merging
    // two logical instances and keeps the reset audit deterministic.
    wire store_async_ddr_n=por_release;
    assign store_rst125_n=rst125_n;
    reset_sync u_store_resetddr(.I_clk(ddr_clk),.I_async_rst_n(store_async_ddr_n),.O_rst_n(store_rstddr_n));
    wire wr_valid,wr_ready,wr_idle,rd_req,rd_ready,rd_valid;
    wire [20:0] wr_byte_addr,rd_byte_addr;wire [127:0] wr_data,rd_data;
    hxa_ddr_store u_store(.clk(clk125),.rst_n(store_rst125_n),.wr_valid(wr_valid),.wr_byte_addr(wr_byte_addr),.wr_data(wr_data),
        .wr_ready(wr_ready),.wr_idle(wr_idle),.rd_req(rd_req),.rd_byte_addr(rd_byte_addr),.rd_ready(rd_ready),.rd_valid(rd_valid),.rd_data(rd_data),
        .ddr_clk(ddr_clk),.ddr_rst_n(store_rstddr_n),.calibrated(calibrated),
        .app_addr(app_addr),.app_cmd(app_cmd),.app_en(app_en),.app_wdf_data(app_wdf_data),.app_wdf_end(app_wdf_end),
        .app_wdf_mask(app_wdf_mask),.app_wdf_wren(app_wdf_wren),.app_rdy(app_rdy),.app_wdf_rdy(app_wdf_rdy),
        .app_rd_data_valid(app_rd_valid),.app_rd_data(app_rd_data));

    wire udp_req,udp_valid,udp_busy,rx_valid,ip_error,mac_error,link_stack_reset;
    wire [7:0] udp_data,rx_data;wire [15:0] udp_len,rx_len,rx_source_port;
    wire gmii_rx_clk,gmii_rx_valid,gmii_tx_valid;wire [7:0] gmii_rx_data,gmii_tx_data;
    // PHY release originates in eth125; release the receive interface in its
    // own RXC-derived GMII clock domain. The related BUFG/IDDR reset path is
    // retained for recovery/removal checking by the implementation tools.
    wire rgmii_rx_async_n=phy_up;
    wire rgmii_rx_rst_n;
    reset_sync u_rgmii_rx_reset(.I_clk(gmii_rx_clk),
        .I_async_rst_n(rgmii_rx_async_n),.O_rst_n(rgmii_rx_rst_n));
    wire stack_reset=!rst125_n||!phy_up||link_stack_reset;
    uiudp_stack #(.CRC_GEN_EN(1'b1),.INTER_FRAME_GAP(4'd12)) u_udp_stack(
        .I_uclk(clk125),.I_reset(stack_reset),.I_mac_local_addr(48'h000a35010204),
        .I_udp_local_port(16'd6003),.I_ip_local_addr(32'hc0a8a003),
        .I_udp_dest_port(16'd6002),.I_ip_dest_addr(32'hc0a8a002),
        .O_W_udp_busy(udp_busy),.I_W_udp_req(udp_req),.I_W_udp_valid(udp_valid),.I_W_udp_data(udp_data),.I_W_udp_len(udp_len),
        .O_R_udp_valid(rx_valid),.O_R_udp_data(rx_data),.O_R_udp_len(rx_len),.O_R_udp_src_port(rx_source_port),
        .I_gmii_rclk(gmii_rx_clk),.I_gmii_rvalid(gmii_rx_valid),.I_gmii_rdata(gmii_rx_data),
        .I_gmii_tclk(clk125),.O_gmii_tvalid(gmii_tx_valid),.O_gmii_tdata(gmii_tx_data),.O_ip_rerror(ip_error),.O_mac_rerror(mac_error));
    wire phy_link_raw;
    // Production RGMII receive path: keep RXD/RX_CTL on the same PH1P HDIO
    // delay code and sample through the legacy BUFG/PHY_LCLK clocking that is
    // already legal for these fixed board pins.  The delay-off and IOCLK
    // variants are isolated timing experiments only and are not this source
    // configuration.
    rgmii_interface #(.TXC_DELAY_ENABLE(1'b0), .TXC_DELAY_VALUE(5'd0),
        // Production RGMII path: the PHY is expected to be edge-aligned and
        // the FPGA moves RXD/RX_CTL into the RXC sampling window with the
        // same HDIO delay code on all five inputs.  The PH1P_PHY_IOCLK
        // candidate is intentionally disabled in the release configuration
        // because isolated TD placement rejected it with PHY-8033 (illegal
        // fabric sink) and PHY-9175 (clock-driver/sink legality).  The DS1300
        // pin table places these RGMII pads in HD BANK22; do not describe the
        // failure as a cross-bank pin assignment without a new placement proof.
        .RXC_USE_IOCLK(1'b0),
        .RX_DELAY_ENABLE(1'b1),
        .RX_DELAY_VALUE(5'd31)) u_rgmii(.speed_10_100(1'b0),.gmii_tx_clk_d(clk125_90),.gmii_tx_reset_d(!phy_up),
        .gmii_tx_reset(!phy_up),.gmii_tx_clk(clk125),.gmii_txd(gmii_tx_data),.gmii_tx_en(gmii_tx_valid),.gmii_tx_er(1'b0),
        .gmii_rx_reset(!rgmii_rx_rst_n),.gmii_rx_clk(gmii_rx_clk),.gmii_rxd(gmii_rx_data),.gmii_rx_dv(gmii_rx_valid),.gmii_rx_er(),
        .rgmii_txd(O_rgmii_txd),.rgmii_tx_ctl(O_rgmii_tx_ctl),.rgmii_txc(O_rgmii_txc),
        .rgmii_rxd(I_rgmii_rxd),.rgmii_rx_ctl(I_rgmii_rx_ctl),.rgmii_rxc(I_rgmii_rxc),.gmii_crs(),.gmii_col(),.link_status(phy_link_raw),.clock_speed(),.duplex_status());

    wire vision_start,vision_cancel,vision_job_cancel,vision_busy,vision_done,vision_teach_good;
    wire [1:0] vision_purpose;
    wire [15:0] vision_paper_width_px;
    wire [31:0] vision_frame_id,vision_job_id,result_job_id,vision_config_version;
    reg [31:0] inference_us;
    wire v_rd_req,v_rd_ready,v_rd_valid;wire [20:0] v_rd_addr;wire [127:0] v_rd_data;
    wire normal_busy,normal_done,normal_rd_req;
    wire copy_task=(vision_purpose==2'd2);
    wire copy_busy,copy_done,copy_recovery,copy_rearm,copy_uart_owner;
    wire copy_reader_request,copy_reader_invalidate;
    wire [10:0] copy_pixel_x;wire [9:0] copy_pixel_y;
    wire copy_status_valid,copy_status_ready;
    wire [95:0] copy_status_data;
    wire [7:0] copy_tx_data,copy_rt_data;
    wire copy_tx_valid,copy_rt_valid,copy_rt_ready;
    wire [20:0] normal_rd_addr;
    // purpose=3/maze is retired in the three-board release. The legacy
    // pipeline remains in the archive only and is not instantiated here.
    wire maze_task=1'b0;
    wire maze_busy=1'b0,maze_done=1'b0,maze_rd_req=1'b0;
    wire [20:0] maze_rd_addr=21'd0;
    wire [1791:0] maze_result=1792'd0;
    wire [1:0] maze_status=2'd0;wire [8:0] maze_steps=9'd0;
    wire [7:0] maze_start_cell=8'd0,maze_goal_cell=8'd0,maze_endpoint=8'd0;
    wire [511:0] maze_directions=512'd0;wire [1023:0] maze_walls=1024'd0;
    // CNN branch: one time-shared classifier processes up to four colour
    // connected components. There is no third-board/SPI dependency.
    wire [639:0] cnn_type18_payload;
    wire [2:0] multi_count;wire [511:0] multi_boxes;wire [7:0] multi_flags;
    assign cnn_type18_payload={multi_boxes,16'd0,{5'd0,multi_count},multi_flags,vision_config_version,inference_us,result_job_id};
    assign vision_busy=normal_busy||copy_busy;
    assign vision_done=copy_task?copy_done:normal_done;
    // Both processing pipelines are mutually exclusive.  A single reader is
    // shared between them so the DDR/YUYV conversion logic and its DSPs are
    // instantiated only once.  The active pipeline supplies the request and
    // coordinates; the inactive pipeline is held idle by vision_start.
    wire normal_reader_ready,normal_reader_valid;
    wire [23:0] normal_reader_rgb;
    wire [7:0] normal_reader_luma;
    wire normal_reader_request;
    wire normal_reader_invalidate;
    wire [10:0] normal_pixel_x;
    wire [9:0] normal_pixel_y;
    // The HXA purpose register drives several mux levels before the shared
    // reader address register. Lock the reader owner for the lifetime of one
    // transaction instead of propagating the mode register continuously.
    // Each pipeline asserts requests after its start edge, so the owner is
    // settled before the first shared DDR read.
    reg copy_reader_select;
    reg [1:0] vision_purpose_q;
    always @(posedge clk125 or negedge rst125_n) begin
        if(!rst125_n) begin
            copy_reader_select<=1'b0;
            vision_purpose_q<=2'd0;
        end else if(vision_cancel || vision_done) begin
            copy_reader_select<=1'b0;
            vision_purpose_q<=2'd0;
        end else if(vision_start) begin
            copy_reader_select<=copy_task;
            vision_purpose_q<=vision_purpose;
        end
    end
    wire [1:0] vision_purpose_locked=vision_busy ? vision_purpose_q : vision_purpose;
    wire shared_reader_request=copy_reader_select?copy_reader_request:normal_reader_request;
    wire shared_reader_invalidate=copy_reader_select?copy_reader_invalidate:normal_reader_invalidate;
    wire [10:0] shared_pixel_x=copy_reader_select?copy_pixel_x:normal_pixel_x;
    wire [9:0] shared_pixel_y=copy_reader_select?copy_pixel_y:normal_pixel_y;
    wire shared_reader_ready,shared_reader_valid;
    wire color_word_active,shared_word_req;
    wire [20:0] shared_byte_addr;
    wire [23:0] shared_reader_rgb;
    wire [7:0] shared_reader_luma;
    vision_pixel_reader u_shared_reader(.clk(clk125),.rst_n(rst125_n&&!vision_cancel),
        .invalidate(shared_reader_invalidate),.request(shared_reader_request),
        .pixel_x(shared_pixel_x),.pixel_y(shared_pixel_y),
        .ready(shared_reader_ready),.pixel_valid(shared_reader_valid),.pixel_rgb(shared_reader_rgb),
        .pixel_y8(shared_reader_luma),.word_req(shared_word_req),.byte_addr(shared_byte_addr),
        .word_ready(v_rd_ready&&(copy_reader_select||!color_word_active)),.word_valid(v_rd_valid&&(copy_reader_select||!color_word_active)),.word_data(v_rd_data));
    // The ordinary CNN reads only on-chip RAM while colour statistics own
    // the DDR word port. Ownership switches only with no pixel read pending.
    assign v_rd_req=(!copy_reader_select&&color_word_active) ? normal_rd_req : shared_word_req;
    assign v_rd_addr=(!copy_reader_select&&color_word_active) ? normal_rd_addr : shared_byte_addr;
    wire cfg_we,cfg_begin,cfg_commit,cfg_abort,cfg_ready,cfg_byte_ready,cfg_idle,cfg_apply,cfg_ack,cfg_error;
    wire [14:0] cfg_addr,cfg_total;wire [7:0] cfg_data;wire [2:0] cfg_good,cfg_bad;
    wire [31:0] cfg_version,cfg_pending_version,cfg_crc;
    wire [255:0] station_header;wire station_valid;
    wire [63:0] session_id;wire online;
    wire [1:0] color_id,shape_id;wire [7:0] confidence;wire target_valid,pcb_checked,pcb_good;wire [2:0] pcb_status;
    wire [10:0] x0,x1;wire [9:0] y0,y1;wire [23:0] area;wire [2:0] defect_count;wire [255:0] defect_boxes;
    wire [7:0] defect_kinds;
    reg [6:0] inference_subcycle;
    always @(posedge clk125 or negedge rst125_n)begin
        if(!rst125_n)begin inference_us<=0;inference_subcycle<=0;end
        else if(vision_start)begin inference_us<=0;inference_subcycle<=0;end
        else if(vision_busy)begin
            if(inference_subcycle==124)begin inference_subcycle<=0;inference_us<=inference_us+1'b1;end
            else inference_subcycle<=inference_subcycle+1'b1;
        end
    end
    wire teach_success,teach_failed,teach_commit;wire [15:0] teach_code;wire [255:0] taught_station_header;
    wire [15:0] detected_class_id=(color_id!=0&&shape_id!=0) ? (color_id-1)*3+shape_id : 0;
    // For PCB purpose class_id 1..4 carries the explicit status so UNKNOWN,
    // empty and overflow are distinguishable from a normal BAD judgement.
    // PCB CNN status encoding: 1 GOOD, 2 BAD, 3 REVIEW, 0 UNKNOWN.
    wire [15:0] pcb_class_status = PCB_BINARY_CLASSES != 0 ?
        ((pcb_status==3'd0)?16'd0:(pcb_status==3'd1)?16'd1:(pcb_status==3'd2)?16'd2:16'd3) :
        ((pcb_status==3'd0)?16'd1:(pcb_status==3'd1)?16'd2:(pcb_status==3'd2)?16'd3:16'd0);
    wire [15:0] class_id=vision_teach_good ? teach_code : ((vision_purpose == 2'd1) ? pcb_class_status : detected_class_id);
    // The main board's KEY1 report request is intentionally decoupled from
    // the frame result ACK path. Cache the most recent ordinary-CNN result so
    // a request can be serviced while the next frame is being transferred.
    reg cnn_cache_valid;
    reg [15:0] cnn_cache_class;
    reg [10:0] cnn_cache_x0,cnn_cache_x1;
    reg [9:0] cnn_cache_y0,cnn_cache_y1;
    wire [255:0] cnn_cache_box={192'd0,{6'd0,cnn_cache_y1},{5'd0,cnn_cache_x1},
                                {6'd0,cnn_cache_y0},{5'd0,cnn_cache_x0}};
    wire [511:0] vision_result={defect_boxes,8'd0,{5'd0,defect_count},class_id,{8'd0,area},
        {6'd0,y1},{5'd0,x1},{6'd0,y0},{5'd0,x0},confidence,{6'd0,shape_id},{6'd0,color_id},
        {2'd0,teach_failed,teach_success,1'b0,pcb_checked,pcb_good,target_valid},vision_config_version,inference_us,result_job_id};
    wire job_status_ready,grbl_test_start,grbl_current_start;
    wire [31:0] grbl_test_job_id,grbl_current_job_id;
    reg job_status_valid;reg [95:0] job_status_data;
    wire report_busy,report_ready,report_done,report_error,key2_local_active;reg report_pending,report_clear;
    // Validate the same frozen frame and polynomial four bytes per cycle.
    // DDR retirement and one-outstanding-read ownership remain unchanged.
    hxa_secondary_link #(.CLK_HZ(125000000),.CAPABILITIES(8'hdf),
        .FRAME_CRC_BYTES_PER_CYCLE(4)) u_link(
        .clk(clk125),.rst_n(rst125_n),.enable(store_rst125_n),.phy_ready(phy_up),.board_mode(board_mode),
        .udp_req(udp_req),.udp_valid(udp_valid),.udp_data(udp_data),.udp_len(udp_len),.udp_busy(udp_busy),
        .rx_valid(rx_valid && rx_source_port==16'd6002),.rx_data(rx_data),.rx_len(rx_len),.rx_error(ip_error||mac_error),.stack_reset(link_stack_reset),
        .wr_valid(wr_valid),.wr_byte_addr(wr_byte_addr),.wr_data(wr_data),.wr_ready(wr_ready),.wr_idle(wr_idle),
        .rd_req(rd_req),.rd_byte_addr(rd_byte_addr),.rd_ready(rd_ready),.rd_valid(rd_valid),.rd_data(rd_data),
        .vision_start(vision_start),.vision_cancel(vision_cancel),.vision_job_cancel(vision_job_cancel),.vision_frame_id(vision_frame_id),.vision_job_id(vision_job_id),.vision_purpose(vision_purpose),.vision_paper_width_px(vision_paper_width_px),.vision_teach_good(vision_teach_good),
        .grbl_test_start(grbl_test_start),.grbl_test_job_id(grbl_test_job_id),
        .grbl_current_start(grbl_current_start),.grbl_current_job_id(grbl_current_job_id),
        .vision_busy(vision_busy),.vision_done(vision_done),.vision_result(vision_result),
        .vision_result_type((vision_purpose==2'd0&&!vision_teach_good)?8'd18:8'd8),.vision_result_multibox(cnn_type18_payload),.vision_maze_result(maze_result),
        .v_rd_req(v_rd_req),.v_rd_byte_addr(v_rd_addr),.v_rd_ready(v_rd_ready),.v_rd_valid(v_rd_valid),.v_rd_data(v_rd_data),
        .cfg_we(cfg_we),.cfg_addr(cfg_addr),.cfg_data(cfg_data),.cfg_commit(cfg_commit),.cfg_version(cfg_version),.cfg_ready(cfg_ready),
        .cfg_begin(cfg_begin),.cfg_abort(cfg_abort),.cfg_total_bytes(cfg_total),.cfg_pending_version(cfg_pending_version),.cfg_expected_crc32(cfg_crc),
        .cfg_good_count(cfg_good),.cfg_bad_count(cfg_bad),.cfg_apply_ack(cfg_ack),.cfg_apply_error(cfg_error),
        .station_header(station_header),.station_valid(station_valid),.station_config_version(station_header[63:32]),
        .job_status_valid(key2_local_active?1'b0:(copy_task?copy_status_valid:job_status_valid)),
        .job_status_data(copy_task?copy_status_data:job_status_data),.job_status_ready(job_status_ready),
        .job_busy(report_busy||report_pending||key2_local_active||copy_busy),
        .session_id(session_id),.online(online),.good_frames(),.bad_frames(),.copy_rearm(copy_rearm));
    assign copy_status_ready=job_status_ready&&copy_task;
    // Retired template writes are rejected by the link. Keep its compatibility
    // ready live, but never forward an external configuration byte to vision.
    assign cfg_ready=1'b1;
    wire accepted_cfg_byte=1'b0;
    wire yolo_pixel_valid,yolo_pixel_last;
    wire [23:0] yolo_pixel_rgb;
    // Ordinary CNN and PCB jobs are mutually exclusive.  Enable the
    // lifecycle-shared activation workspace so both classifiers use the
    // same physical ERAM banks; the model ROMs and numerical datapaths stay
    // independent.
    // PCB and ordinary CNN jobs are mutually exclusive and share activation
    // workspace; each classifier keeps its own weights and datapath.
    vision_pipeline #(.EXTERNAL_READER(1),.LOCAL_CNN_ENABLE(1),.PCB_ENABLE(1),.PCB_COMPACT_ROM(0),.PCB_FULLBOARD_SPATIAL96(1),.PCB_BINARY_CLASSES(PCB_BINARY_CLASSES),.PCB_FULLBOARD_C1_CHANNELS(PCB_BINARY_C1_CHANNELS),.PCB_FULLBOARD_C2_CHANNELS(PCB_BINARY_C2_CHANNELS),.PCB_FULLBOARD_C2_SHIFT(PCB_BINARY_CLASSES != 0 ? 7 : 6),.PCB_FULLBOARD_HEAD_SHIFT(PCB_BINARY_CLASSES != 0 ? 8 : 7),.PCB_FULL_X(158),.PCB_FULL_Y(140),.PCB_FULL_W(956),.PCB_FULL_H(412),.PCB_FIXED_WINDOW_ONLY(1),.SHARED_WORKSPACE(1),.PCB_FULLBOARD_WEIGHTS_MEM(PCB_BINARY_CLASSES != 0 ? ((PCB_BINARY_C1_CHANNELS == 4 && PCB_BINARY_C2_CHANNELS == 4) ? "../model/experiments/conv4_4/weights.mem" : (PCB_BINARY_C2_CHANNELS == 8 ? "../model/experiments/conv2_8/weights.mem" : "../model/binary/weights.mem")) : "../model/fullboard/weights.mem"),.PCB_FULLBOARD_BIASES_MEM(PCB_BINARY_CLASSES != 0 ? ((PCB_BINARY_C1_CHANNELS == 4 && PCB_BINARY_C2_CHANNELS == 4) ? "../model/experiments/conv4_4/biases.mem" : (PCB_BINARY_C2_CHANNELS == 8 ? "../model/experiments/conv2_8/biases.mem" : "../model/binary/biases.mem")) : "../model/fullboard/biases.mem")) u_vision(.clk(clk125),.rst_n(rst125_n),.cancel(vision_cancel),.start(vision_start&&!maze_task&&!copy_task),.purpose(vision_purpose_locked),.teach_good(vision_teach_good),.job_id(vision_job_id),
        .word_req(normal_rd_req),.byte_addr(normal_rd_addr),.word_ready(v_rd_ready&&!maze_task),.word_valid(v_rd_valid&&!maze_task),.word_data(v_rd_data),
        .cfg_we(accepted_cfg_byte),.cfg_addr(cfg_addr),.cfg_data(cfg_data),.cfg_commit(cfg_apply),
        .busy(normal_busy),.done(normal_done),.result_job_id(result_job_id),.config_version(vision_config_version),
        .color_id(color_id),.shape_id(shape_id),.confidence(confidence),.valid(target_valid),.multi_count(multi_count),.multi_boxes(multi_boxes),.multi_flags(multi_flags),
        .x0(x0),.y0(y0),.x1(x1),.y1(y1),.area(area),.pcb_checked(pcb_checked),.pcb_good(pcb_good),.pcb_status(pcb_status),.defect_count(defect_count),.defect_boxes(defect_boxes),
        .defect_kinds(defect_kinds),
        .teach_success(teach_success),.teach_failed(teach_failed),.teach_code(teach_code),.teach_commit(teach_commit),.taught_station_header(taught_station_header),
        .ext_reader_ready(shared_reader_ready),.ext_reader_valid(shared_reader_valid),.ext_reader_rgb(shared_reader_rgb),.ext_reader_luma(shared_reader_luma),
        .ext_reader_request(normal_reader_request),.ext_reader_invalidate(normal_reader_invalidate),.ext_pixel_x(normal_pixel_x),.ext_pixel_y(normal_pixel_y),
        .yolo_pixel_valid(yolo_pixel_valid),.yolo_pixel_rgb(yolo_pixel_rgb),.yolo_pixel_last(yolo_pixel_last),
        .color_word_active(color_word_active));

    // The plotter profile is a board constant. hxa_config_store is now only a
    // compatibility stub; no network template/profile can block a report or
    // a host test command. Values are hundredths of a millimetre
    // (cmm), matching the historical A4 preset used by the GUI.
    localparam [15:0] FIXED_ORIGIN_X=16'd1000, FIXED_ORIGIN_Y=16'd1000,
                       FIXED_WORK_X=16'd21000, FIXED_WORK_Y=16'd29700,
                       FIXED_UP_PWM=16'd0, FIXED_DOWN_PWM=16'd0,
                       FIXED_TRAVEL_FEED=16'd7000, FIXED_DRAW_FEED=16'd3000,
                       FIXED_PEN_FEED=16'd1200;
    localparam [7:0] FIXED_STEP=8'd60;
    localparam signed [15:0] FIXED_PEN_UP=-16'sd120,
                              FIXED_PEN_DOWN=16'sd500;
    wire cfg_profile_valid,cfg_profile_pwm;wire [7:0] cfg_profile_step;
    wire [15:0] cfg_origin_x,cfg_origin_y,cfg_work_x,cfg_work_y,cfg_up_pwm,cfg_down_pwm,
                cfg_travel_feed,cfg_draw_feed,cfg_pen_feed;
    wire signed [15:0] cfg_pen_up,cfg_pen_down;
    wire profile_valid=1'b1,profile_pwm=1'b0;
    wire [7:0] profile_step=FIXED_STEP;
    wire [15:0] origin_x=FIXED_ORIGIN_X,origin_y=FIXED_ORIGIN_Y,
                work_x=FIXED_WORK_X,work_y=FIXED_WORK_Y,
                up_pwm=FIXED_UP_PWM,down_pwm=FIXED_DOWN_PWM,
                travel_feed=FIXED_TRAVEL_FEED,draw_feed=FIXED_DRAW_FEED,
                pen_feed=FIXED_PEN_FEED;
    wire signed [15:0] pen_up=FIXED_PEN_UP,pen_down=FIXED_PEN_DOWN;
    hxa_config_store u_configuration(.I_clk(clk125),.I_rst_n(rst125_n),.I_begin(cfg_begin),.I_abort(cfg_abort),
        .I_local_apply(teach_commit),.I_local_header(taught_station_header),
        .I_total_bytes(cfg_total),.I_version(cfg_pending_version),.I_good_count(cfg_good),.I_bad_count(cfg_bad),.I_expected_crc32(cfg_crc),
        .I_byte_valid(accepted_cfg_byte),.I_byte_addr(cfg_addr),.I_byte_data(cfg_data),.O_byte_ready(cfg_byte_ready),
        .I_commit(cfg_commit),.I_job_idle(!vision_busy&&!report_busy&&!report_pending&&!key2_local_active),.O_cfg_ready(cfg_idle),
        .O_commit_ack(cfg_ack),.O_commit_error(cfg_error),.O_apply(cfg_apply),.O_station_header(station_header),.O_station_valid(station_valid),
        .O_profile_valid(cfg_profile_valid),.O_profile_pwm_mode(cfg_profile_pwm),.O_profile_step_cmm(cfg_profile_step),
        .O_origin_x_cmm(cfg_origin_x),.O_origin_y_cmm(cfg_origin_y),.O_work_x_cmm(cfg_work_x),.O_work_y_cmm(cfg_work_y),
        .O_pen_up_cmm(cfg_pen_up),.O_pen_down_cmm(cfg_pen_down),.O_pen_up_pwm(cfg_up_pwm),.O_pen_down_pwm(cfg_down_pwm),
        .O_travel_feed(cfg_travel_feed),.O_draw_feed(cfg_draw_feed),.O_pen_feed(cfg_pen_feed),.O_profile_id());

    wire uart_link_ready,uart_tx_ready,uart_tx_done,uart_tx_valid,uart_rx_valid,uart_rx_error;
    wire [7:0] uart_tx_data,uart_rx_data,report_error_code,report_tx_data;
    wire report_tx_valid;
    wire [7:0] uart_rt_data;
    wire uart_rt_valid,uart_rt_ready,uart_idle_pulse,uart_rt_done;
    wire key2_rt_valid,key2_report_start,key2_report_fail;
    wire [31:0] key2_report_job;
    reg key2_report_pending;
    wire key2_report_accept=key2_report_pending&&report_ready;
    wire report_job_valid=report_pending||key2_report_pending;
    wire report_test_mode=key2_report_pending;
    assign uart_tx_data=copy_uart_owner?copy_tx_data:report_tx_data;
    assign uart_tx_valid=copy_uart_owner?copy_tx_valid:report_tx_valid;
    assign uart_rt_data=key2_rt_valid?8'h3f:copy_rt_data;
    assign uart_rt_valid=key2_rt_valid||copy_rt_valid;
    assign copy_rt_ready=uart_rt_ready&&!key2_rt_valid;
    doc_copy_pipeline #(.PLANNER_OPT_PASSES(0)) u_copy(.clk(clk125),.rst_n(rst125_n),.start(vision_start&&copy_task),
        .cancel(vision_cancel),.rearm(copy_rearm),.job_id(vision_job_id),.paper_width_px(vision_paper_width_px),
        .busy(copy_busy),.done(copy_done),.recovery_required(copy_recovery),
        .status_valid(copy_status_valid),.status_data(copy_status_data),.status_ready(copy_status_ready),
        .pixel_request(copy_reader_request),.pixel_invalidate(copy_reader_invalidate),
        .pixel_x(copy_pixel_x),.pixel_y(copy_pixel_y),
        .pixel_ready(shared_reader_ready&&copy_reader_select),.pixel_valid(shared_reader_valid&&copy_reader_select),
        .pixel_luma(shared_reader_luma),
        .tx_data(copy_tx_data),.tx_valid(copy_tx_valid),.tx_ready(uart_tx_ready&&copy_uart_owner),
        .tx_done(uart_tx_done&&copy_uart_owner),.rx_data(uart_rx_data),.rx_valid(uart_rx_valid),
        .rx_error(uart_rx_error),.link_ready(uart_link_ready),
        .rt_data(copy_rt_data),.rt_valid(copy_rt_valid),.rt_ready(copy_rt_ready),.uart_owner(copy_uart_owner),
        .paper_corners(),.edge_count(),.path_count(),.point_count(),.baseline_distance(),.planned_distance());
    wire [31:0] report_lines;wire [2:0] report_state;
    reg [31:0] report_job;reg [63:0] report_session;reg [1:0] report_judgement;
    reg [2:0] report_defect_count;reg [255:0] report_defect_boxes;
    reg [7:0] report_defect_kinds;
    reg report_maze;reg report_cnn_mode;reg [15:0] report_cnn_class;reg [2:0] report_admit_age;
    reg [31:0] key1_report_id;
    wire key1_job_active,key1_job_protected;
    wire key1_local_admit=key1_report_pulse&&(vision_purpose==2'd0)&&!report_busy&&!report_pending&&!key2_local_active&&!key1_job_active&&!copy_busy&&!copy_recovery;
    wire key1_local_job_accept=key1_local_admit&&profile_valid&&uart_link_ready;
    grbl_key1_job_guard u_key1_job_guard(.I_clk(clk125),.I_rst_n(rst125_n),
        .I_accept(key1_local_job_accept),.I_explicit_cancel(vision_job_cancel),
        .I_done(report_done),.I_error(report_error),.O_active(key1_job_active),
        .O_protected(key1_job_protected));
    grbl_key2_test_ctrl #(.CLK_HZ(125000000)) u_key2_test(
        .I_clk(clk125),.I_rst_n(rst125_n),.I_key_n(I_key2_n),
        .I_busy(vision_busy||report_busy||report_pending||copy_busy||copy_recovery||copy_uart_owner||cfg_apply),
        .I_uart_ready(uart_link_ready),.I_rt_ready(uart_rt_ready&&!copy_uart_owner),
        .I_rt_done(uart_rt_done),.I_idle_pulse(uart_idle_pulse),.I_job_accept(key2_report_accept),
        .I_job_done(report_done),.I_job_error(report_error),
        .O_rt_valid(key2_rt_valid),.O_job_start(key2_report_start),
        .O_job_fail(key2_report_fail),.O_job_id(key2_report_job),.O_active(key2_local_active));
    grbl_uart_port #(.CLK_HZ(125000000)) u_uart(.I_clk(clk125),.I_rst_n(rst125_n),
        .I_uart_rx(I_uart_rx),.O_uart_tx(O_uart_tx),.I_esp_link_ready(I_esp_link_ready),.O_link_ready(uart_link_ready),
        .I_tx_data(uart_tx_data),.I_tx_valid(uart_tx_valid),.O_tx_ready(uart_tx_ready),.O_tx_done(uart_tx_done),
        .O_rx_data(uart_rx_data),.O_rx_valid(uart_rx_valid),.O_rx_error(uart_rx_error),
        .I_rt_data(uart_rt_data),.I_rt_valid(uart_rt_valid),.O_rt_ready(uart_rt_ready),
        .O_idle_pulse(uart_idle_pulse),.O_rt_done(uart_rt_done));
    grbl_reporter #(.CLK_HZ(125000000),.MAZE_ENABLE(0)) u_reporter(.I_clk(clk125),.I_rst_n(rst125_n),.I_clear(cfg_apply||report_clear),.I_abort(vision_job_cancel||(!key2_local_active&&!key1_job_protected&&(vision_cancel||!online))),
        .I_job_valid(report_job_valid),.I_local_test(report_test_mode),.I_job_id(report_job),.I_session_id(report_session),.I_judgement(report_judgement),
        .I_defect_count(report_defect_count),.I_defect_boxes(report_defect_boxes),
        .I_defect_kinds(report_defect_kinds),.I_cnn_mode(report_cnn_mode),.I_cnn_class(report_cnn_class),
        .I_maze_mode(report_maze),.I_maze_status(maze_status),.I_maze_steps(maze_steps),
        .I_maze_start(maze_start_cell),.I_maze_goal(maze_goal_cell),.I_maze_endpoint(maze_endpoint),
        .I_maze_directions(maze_directions),.I_maze_walls(maze_walls),
        .O_job_ready(report_ready),.O_busy(report_busy),.O_done(report_done),.O_error(report_error),.O_error_code(report_error_code),.O_acked_lines(report_lines),.O_job_state(report_state),
        .I_link_ready(uart_link_ready),.I_profile_valid(profile_valid),.I_pen_pwm_mode(profile_pwm),
        .I_origin_x_cmm(origin_x),.I_origin_y_cmm(origin_y),.I_work_x_cmm(work_x),.I_work_y_cmm(work_y),.I_step_cmm(profile_step),
        .I_pen_up_cmm(pen_up),.I_pen_down_cmm(pen_down),.I_pen_up_pwm(up_pwm),.I_pen_down_pwm(down_pwm),
        .I_travel_feed(travel_feed),.I_draw_feed(draw_feed),.I_pen_feed(pen_feed),
        .O_tx_data(report_tx_data),.O_tx_valid(report_tx_valid),.I_tx_ready(uart_tx_ready&&!copy_uart_owner),.I_tx_done(uart_tx_done&&!copy_uart_owner),
        .I_rx_data(uart_rx_data),.I_rx_valid(uart_rx_valid&&!copy_uart_owner),.I_rx_error(uart_rx_error&&!copy_uart_owner));
    reg [2:0] report_state_d;reg report_error_d;reg [31:0] report_lines_d;
    always @(posedge clk125 or negedge rst125_n)begin
        if(!rst125_n)begin
            report_pending<=0;key2_report_pending<=0;report_clear<=0;report_job<=0;report_session<=0;report_judgement<=0;report_defect_count<=0;report_defect_boxes<=0;
            report_defect_kinds<=0;
            report_maze<=0;report_cnn_mode<=0;report_cnn_class<=0;report_admit_age<=0;key1_report_id<=0;
            cnn_cache_valid<=0;cnn_cache_class<=0;cnn_cache_x0<=0;cnn_cache_x1<=0;cnn_cache_y0<=0;cnn_cache_y1<=0;
            job_status_valid<=0;job_status_data<=0;report_state_d<=0;report_error_d<=0;report_lines_d<=0;
        end else begin
            report_state_d<=report_state;report_error_d<=report_error;report_lines_d<=report_lines;
            if(normal_done&&vision_purpose==2'd0)begin
                cnn_cache_valid<=target_valid;
                cnn_cache_class<=detected_class_id;
                cnn_cache_x0<=x0;cnn_cache_x1<=x1;cnn_cache_y0<=y0;cnn_cache_y1<=y1;
            end
            report_clear<=0;
            if(job_status_valid&&job_status_ready)job_status_valid<=0;
            if(report_pending&&report_ready)report_pending<=0;
            if(key2_report_pending&&report_ready)key2_report_pending<=0;
            if(!report_pending)report_admit_age<=0;
            else if(report_admit_age<7)report_admit_age<=report_admit_age+1'b1;
            if(vision_job_cancel||((vision_cancel||!online)&&!key2_local_active&&!key1_job_protected))begin report_pending<=0;job_status_valid<=0;end
            else begin
                // Payload is latched before this admission check. An invalid
                // geometry, duplicate job, or lost UART link must terminate,
                // rather than leave pending asserted forever.
                if(report_pending&&report_admit_age>=3&&!report_busy&&!report_ready)begin
                    report_pending<=0;
                    job_status_data<={32'd0,16'd0,(!profile_valid?8'd1:!uart_link_ready?8'd2:report_error?report_error_code:8'd10),8'd5,report_job};
                    job_status_valid<=1;
                end
                if(vision_start&&(vision_purpose==1||maze_task))begin job_status_data<={32'd0,16'd0,8'd0,8'd1,vision_job_id};job_status_valid<=1;end
                // Type 20 command id 1 asks for a deterministic, short PASS
                // report.  It bypasses MPF1/profile admission but still uses
                // the normal reporter/streamer, so every line waits for GRBL
                // ok and the final fresh Idle response is required.
                if(grbl_test_start)begin
                    report_maze<=0;report_cnn_mode<=0;report_cnn_class<=0;report_job<=grbl_test_job_id;report_session<=session_id;
                    report_judgement<=1;report_defect_count<=0;report_defect_boxes<=0;
                    report_defect_kinds<=0;
                    if(uart_link_ready)begin
                        // A previous GRBL fault is latched by the streamer.
                        // Clear it only while the reporter is idle, then let
                        // the pending job start on the following clock.
                        report_clear<=1;
                        report_pending<=1;
                        job_status_data<={32'd0,16'd0,8'd0,8'd2,grbl_test_job_id};job_status_valid<=1;
                    end else begin
                        job_status_data<={32'd0,16'd0,8'd2,8'd5,grbl_test_job_id};job_status_valid<=1;
                    end
                end
                if(key2_report_start)begin
                    report_maze<=0;report_cnn_mode<=0;report_cnn_class<=0;
                    report_job<=key2_report_job;report_session<=session_id;
                    report_judgement<=1;report_defect_count<=0;
                    report_defect_boxes<=0;report_defect_kinds<=0;
                    report_clear<=1;key2_report_pending<=1;
                end
                if(key2_report_fail)key2_report_pending<=0;
                // KEY1 ordinary-CNN report: write the cached class and its
                // last bounding box through the same stop-and-wait reporter.
                // A missing cached target is still a valid no-target report.
                if(grbl_current_start||key1_local_admit)begin
                    report_maze<=0;report_cnn_mode<=1;report_cnn_class<=cnn_cache_class;
                    report_job<=key1_local_admit?(key1_report_id+1'b1):grbl_current_job_id;
                    report_session<=session_id;
                    report_judgement<=cnn_cache_valid?2'd2:2'd0;
                    report_defect_count<=cnn_cache_valid?3'd1:3'd0;
                    report_defect_boxes<=cnn_cache_box;report_defect_kinds<=0;
                    if(key1_local_admit)key1_report_id<=key1_report_id+1'b1;
                    if(profile_valid&&uart_link_ready)begin
                        report_clear<=1;report_pending<=1;
                        job_status_data<={32'd0,16'd0,8'd0,8'd2,
                            key1_local_admit?(key1_report_id+1'b1):grbl_current_job_id};job_status_valid<=1;
                    end else begin
                        job_status_data<={32'd0,16'd0,uart_link_ready?8'd1:8'd2,8'd5,
                            key1_local_admit?(key1_report_id+1'b1):grbl_current_job_id};job_status_valid<=1;
                    end
                end
                if(normal_done&&vision_purpose==1&&!vision_teach_good)begin
                    report_cnn_mode<=0;report_cnn_class<=0;
                    report_maze<=0;
                    report_job<=result_job_id;report_session<=session_id;
                    report_judgement<=!pcb_checked?0:((pcb_status==3'd2)?0:(pcb_good?1:2));
                    report_defect_count<=defect_count;report_defect_boxes<=defect_boxes;
                    report_defect_kinds<=defect_kinds;
                    if(profile_valid&&uart_link_ready&&target_valid)begin
                        report_clear<=1;report_pending<=1;
                    end
                    else begin
                        job_status_data<={32'd0,16'd0,(!profile_valid?8'd1:!uart_link_ready?8'd2:!target_valid?8'd9:report_error_code),8'd5,result_job_id};job_status_valid<=1;
                    end
                end
                if(maze_done&&maze_task)begin
                    report_maze<=1;report_cnn_mode<=0;report_cnn_class<=0;report_job<=vision_job_id;report_session<=session_id;
                    report_defect_count<=0;report_defect_boxes<=0;report_judgement<=0;
                    report_defect_kinds<=0;
                    if(profile_valid&&uart_link_ready&&(maze_status==1||maze_status==2))begin
                        report_clear<=1;report_pending<=1;
                    end
                    else begin
                        job_status_data<={32'd0,16'd0,(!profile_valid?8'd1:!uart_link_ready?8'd2:maze_status==0?8'd11:report_error_code),8'd5,vision_job_id};
                        job_status_valid<=1;
                    end
                end
                if(!key2_local_active&&report_session==session_id)begin
                    // A clear pulse can move a previous FAULT back to IDLE
                    // while a new report is still waiting for admission. That
                    // intermediate state is not completion for this job.
                    if(!report_pending && (report_state!=report_state_d || report_lines!=report_lines_d))begin
                        job_status_data<={report_lines,16'd0,report_error_code,{5'd0,report_state},report_job};job_status_valid<=1;
                    end
                    if(report_error&&!report_error_d)begin job_status_data<={report_lines,16'd0,report_error_code,8'd5,report_job};job_status_valid<=1;end
                    if(report_done)begin job_status_data<={report_lines,16'd0,8'd0,8'd4,report_job};job_status_valid<=1;end
                end
            end
        end
    end

    // Board diagnostics. All indicators are generated in the 125 MHz domain:
    // LED0 is a free-running heartbeat, LED1 is the synchronized PHY in-band
    // link state, LED2 means a valid HXA session with the selected peer, and
    // LED3 reports inference/result state. A one-clock vision pulse is never
    // connected directly to an LED; timers stretch it for human observation.
    reg phy_link_meta,phy_link_sync;
    reg online_d;
    reg [26:0] heartbeat_count;
    reg [25:0] activity_count;
    reg [27:0] result_count;
    reg [1:0] result_code;
    reg led3_phase,status_fast_phase;
    reg [25:0] status_fast_count;
    localparam [26:0] HEARTBEAT_HALF = 27'd62500000;
    localparam [25:0] ACTIVITY_TICKS = 26'd31250000;
    localparam [27:0] RESULT_TICKS = 28'd250000000;
    always @(posedge clk125 or negedge rst125_n)begin
        if(!rst125_n)begin
            phy_link_meta<=0;phy_link_sync<=0;online_d<=0;
            heartbeat_count<=0;activity_count<=0;result_count<=0;
            result_code<=0;led3_phase<=0;status_fast_count<=0;status_fast_phase<=0;
        end else begin
            phy_link_meta<=phy_link_raw;
            phy_link_sync<=phy_link_meta;
            online_d<=online;
            if(heartbeat_count==HEARTBEAT_HALF-1)begin heartbeat_count<=0;led3_phase<=~led3_phase;end
            else heartbeat_count<=heartbeat_count+1'b1;
            if(status_fast_count==ACTIVITY_TICKS-1)begin status_fast_count<=0;status_fast_phase<=~status_fast_phase;end
            else status_fast_count<=status_fast_count+1'b1;
            if(activity_count!=0)activity_count<=activity_count-1'b1;
            if(result_count!=0)result_count<=result_count-1'b1;
            if(vision_start || vision_done)activity_count<=ACTIVITY_TICKS;
            if(vision_done)begin
                result_count<=RESULT_TICKS;
                if(maze_task)begin
                    result_code<=maze_status==1?2'd1:maze_status==2?2'd2:2'd3;
                end else if(vision_purpose==2)begin
                    result_code<=teach_success?2'd1:2'd3;
                end else if(vision_purpose==1)begin
                    if(pcb_checked && pcb_good)result_code<=2'd1;       // PCB GOOD
                    else if(pcb_checked && !pcb_good)result_code<=2'd2;  // PCB BAD
                    else result_code<=2'd3;                              // PCB UNKNOWN
                end else begin
                    result_code<=target_valid ? 2'd1 : 2'd0;             // CNN LOCK/NONE
                end
            end
            if(vision_cancel || (online_d && !online))begin
                result_count<=0;result_code<=0;activity_count<=0;
            end
        end
    end
    wire led3_activity=(activity_count!=0) ? led3_phase :
                       (result_count==0 || result_code==0) ? 1'b0 :
                       (result_code==1) ? 1'b1 :
                       (result_code==2) ? status_fast_phase : led3_phase;
    assign O_led[0]=led3_phase;                         // FPGA heartbeat
    assign O_led[1]=phy_link_sync;                      // physical Ethernet link
    assign O_led[2]=phy_link_sync && online;            // HXA peer session
    assign O_led[3]=led3_activity;                      // inference/result status
endmodule

module grbl_key2_test_ctrl #(
    parameter integer CLK_HZ=125000000
)(
    input wire I_clk,input wire I_rst_n,input wire I_key_n,
    input wire I_busy,input wire I_uart_ready,input wire I_rt_ready,
    input wire I_rt_done,input wire I_idle_pulse,input wire I_job_accept,input wire I_job_done,input wire I_job_error,
    output wire O_rt_valid,output reg O_job_start,output reg O_job_fail,
    output reg [31:0] O_job_id,output wire O_active
);
    localparam integer DEBOUNCE_CYCLES=(CLK_HZ/50)<1?1:(CLK_HZ/50);
    localparam integer WAIT_TIMEOUT_CYCLES=CLK_HZ*2;
    localparam integer DEBOUNCE_W=(DEBOUNCE_CYCLES<2)?1:$clog2(DEBOUNCE_CYCLES+1);
    localparam integer WAIT_TIMEOUT_W=(WAIT_TIMEOUT_CYCLES<2)?1:$clog2(WAIT_TIMEOUT_CYCLES+1);
    localparam [2:0] K_IDLE=0,K_WAIT_READY=1,K_QUERY=2,K_WAIT_TX=3,
                     K_WAIT_IDLE=4,K_WAIT_ACCEPT=5,K_WAIT_JOB=6;
    reg [2:0] state;
    reg key_meta,key_sync,key_sample,key_debounced,key_press;
    reg [DEBOUNCE_W-1:0] debounce_count;
    reg [WAIT_TIMEOUT_W-1:0] wait_count;
    assign O_rt_valid=(state==K_QUERY);
    assign O_active=(state!=K_IDLE);
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            key_meta<=1'b1;key_sync<=1'b1;key_sample<=1'b1;key_debounced<=1'b1;
            key_press<=1'b0;debounce_count<=0;wait_count<=0;
            state<=K_IDLE;O_job_start<=0;O_job_fail<=0;O_job_id<=0;
        end else begin
            key_meta<=I_key_n;key_sync<=key_meta;
            key_press<=0;O_job_start<=0;O_job_fail<=0;
            if(key_sync!=key_sample)begin
                key_sample<=key_sync;debounce_count<=0;
            end else if(debounce_count<DEBOUNCE_CYCLES)begin
                debounce_count<=debounce_count+1'b1;
            end else if(key_debounced!=key_sample)begin
                key_debounced<=key_sample;
                if(key_debounced&&!key_sample)key_press<=1'b1;
            end
            case(state)
                K_IDLE:if(key_press&&!I_busy)begin
                    state<=K_WAIT_READY;wait_count<=0;
                end
                K_WAIT_READY:begin
                    if(I_uart_ready)begin state<=K_QUERY;wait_count<=0;end
                    else if(wait_count>=WAIT_TIMEOUT_CYCLES-1)begin
                        state<=K_IDLE;O_job_fail<=1;wait_count<=0;
                    end else wait_count<=wait_count+1'b1;
                end
                K_QUERY:if(I_rt_ready)begin state<=K_WAIT_TX;wait_count<=0;end
                K_WAIT_TX:begin
                    if(I_rt_done)begin state<=K_WAIT_IDLE;wait_count<=0;end
                    else if(wait_count>=WAIT_TIMEOUT_CYCLES-1)begin
                        state<=K_IDLE;O_job_fail<=1;wait_count<=0;
                    end else wait_count<=wait_count+1'b1;
                end
                K_WAIT_IDLE:begin
                    if(I_idle_pulse)begin
                        O_job_start<=1;O_job_id<=O_job_id+1'b1;
                        state<=K_WAIT_ACCEPT;wait_count<=0;
                    end else if(wait_count>=WAIT_TIMEOUT_CYCLES-1)begin
                        state<=K_IDLE;O_job_fail<=1;wait_count<=0;
                    end else wait_count<=wait_count+1'b1;
                end
                K_WAIT_ACCEPT:begin
                    if(I_job_accept)begin state<=K_WAIT_JOB;wait_count<=0;end
                    else if(wait_count>=WAIT_TIMEOUT_CYCLES-1)begin
                        state<=K_IDLE;O_job_fail<=1;wait_count<=0;
                    end else wait_count<=wait_count+1'b1;
                end
                K_WAIT_JOB:if(I_job_done||I_job_error)begin state<=K_IDLE;wait_count<=0;end
                default:begin state<=K_IDLE;O_job_fail<=1;wait_count<=0;end
            endcase
        end
    end
endmodule

// Own an accepted local KEY1 job independently of the HXA network session.
// Only an explicit cancel or a terminal GRBL result releases the owner.
module grbl_key1_job_guard(
    input wire I_clk,input wire I_rst_n,
    input wire I_accept,input wire I_explicit_cancel,input wire I_done,input wire I_error,
    output reg O_active,output wire O_protected
);
    assign O_protected=O_active||I_accept;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)O_active<=1'b0;
        else if(I_explicit_cancel)O_active<=1'b0;
        else if(I_accept)O_active<=1'b1;
        else if(O_active&&(I_done||I_error))O_active<=1'b0;
    end
endmodule
