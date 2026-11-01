// One frozen clean-AWB RGB frame in DDR; deterministic random-access YUYV
// packets. Camera capture is a passive tap and never back-pressures HDMI.
// Net request pulses are accepted only when the corresponding busy is low.
module hx_snapshot_service #(
    parameter integer FRAME_W=1280,FRAME_H=720,
    parameter [24:0] SNAP_BASE=25'd28000000,
    parameter integer NET_TIMEOUT=125000000,
    parameter integer PACKET_STALL_CYCLES=12500000,
    parameter integer PRESENCE_MIN=12,PRESENCE_STABLE_MAX=4,PRESENCE_CONFIRM=30
)(
    input wire I_clk_cam,I_rst_cam_n,I_clk_ddr,I_rst_ddr_n,I_clk_net,I_rst_net_n,
    input wire [95:0] I_rgb,input wire I_valid,I_user,I_last,I_frame_error,
    input wire I_capture_req,I_cancel,I_release,
    output wire O_busy,O_ready,output reg [31:0] O_frame_id,output reg O_capture_error,
    output reg [127:0] O_capture_diag,
    input wire I_packet_req,input wire [10:0] I_packet_index,
    output reg O_packet_busy,output wire O_packet_valid,input wire I_packet_ready,
    output wire [7:0] O_packet_data,output wire O_packet_last,output reg O_packet_error,
    input wire I_background_capture,
    input wire I_cfg_commit,output wire O_cfg_ready,
    input wire [10:0] I_cfg_roi_x0,I_cfg_roi_x1,
    input wire [9:0] I_cfg_roi_y0,I_cfg_roi_y1,
    input wire [7:0] I_cfg_background_th,I_cfg_stable_th,I_cfg_stable_frames,I_cfg_clear_frames,
    input wire [15:0] I_cfg_present_min,input wire [7:0] I_cfg_stable_max,
    input wire I_cfg_teach,
    output reg O_background_valid,O_pcb_present,O_pcb_stable,output reg O_pcb_trigger,
    output wire O_ddr_wr_valid,output wire [24:0] O_ddr_wr_addr,
    output wire [127:0] O_ddr_wr_data,input wire I_ddr_wr_ready,I_ddr_wr_retire,
    output wire O_ddr_rd_req,output wire [24:0] O_ddr_rd_addr,
    input wire I_ddr_rd_ready,I_ddr_rd_valid,input wire [127:0] I_ddr_rd_data,
    input wire [31:0] I_ddr_debug
);
    localparam integer GROUPS=FRAME_W/4;
    localparam integer FRAME_GROUPS=FRAME_W*FRAME_H/4;
    localparam integer FRAME_WORDS=FRAME_W*FRAME_H*3/16;
    localparam integer PACKET_BYTES=1440,PACKET_WORDS=135;
    localparam integer PACKET_COUNT=FRAME_W*FRAME_H*2/PACKET_BYTES;
    localparam N_IDLE=3'd0,N_PREP=3'd1,N_CAPTURE=3'd2,N_FROZEN=3'd3,N_ABORT=3'd4;
    reg [2:0] net_state;
    reg [5:0] prep_count;
    reg [27:0] timeout_count;
    reg capture_toggle,cancel_toggle,teach_toggle;
    reg cap_result_seen;
    reg cap_fifo_reset;
    reg [1:0] done_sync;
    reg done_seen;
    reg ddr_done_toggle,ddr_done_good;
    reg [31:0] ddr_frame_id;
    reg [127:0] ddr_done_diag;
    wire done_event=done_sync[1]!=done_seen;
    localparam integer STALL_BITS=(PACKET_STALL_CYCLES<2)?1:$clog2(PACKET_STALL_CYCLES);
    reg [STALL_BITS-1:0] packet_stall_count;
    reg packet_diag_req,packet_diag_ack;
    reg [1:0] packet_diag_req_sync,packet_diag_ack_sync;
    reg [1:0] packet_full_sync;
    reg packet_diag_wait,packet_stall_reported,packet_stall_error_pending;
    reg [47:0] packet_diag_ddr_hold;
    reg [47:0] packet_diag_net_hold;
    wire packet_diag_complete=packet_diag_wait&&(packet_diag_ack_sync[1]==packet_diag_req);
    // HXD1 bit 11 selects read-stall fields, not the old capture counters.
    // DDR data is held until another request, and the ACK crosses two FFs.
    wire [127:0] packet_read_diag={16'd0,packet_diag_net_hold[47:16],
                                  packet_diag_ddr_hold[31:0],
                                  packet_diag_ddr_hold[47:32],
                                  packet_diag_net_hold[15:0],16'h0880};
    wire abort_net=(net_state==N_ABORT)||I_cancel||I_release;
    reg cfg_toggle,cfg_ack_cam;
    reg [1:0] cfg_ack_sync,cfg_req_sync;
    reg [10:0] cfg_x0,cfg_x1;
    reg [9:0] cfg_y0,cfg_y1;
    reg [7:0] cfg_bg_th,cfg_st_th,cfg_st_frames,cfg_clear_frames,cfg_st_max;
    reg [15:0] cfg_present_min;
    wire cfg_apply_cam=(cfg_req_sync[1]!=cfg_ack_cam)&&I_valid&&I_user;
    assign O_cfg_ready=cfg_ack_sync[1]==cfg_toggle;
    always @(posedge I_clk_net or negedge I_rst_net_n) begin
      if(!I_rst_net_n) begin
        cfg_toggle<=0;cfg_ack_sync<=0;cfg_x0<=0;cfg_y0<=0;cfg_x1<=FRAME_W;cfg_y1<=FRAME_H;
        cfg_bg_th<=24;cfg_st_th<=8;cfg_st_frames<=PRESENCE_CONFIRM;cfg_clear_frames<=PRESENCE_CONFIRM;
        cfg_st_max<=PRESENCE_STABLE_MAX;cfg_present_min<=PRESENCE_MIN;
      end else begin
        cfg_ack_sync<={cfg_ack_sync[0],cfg_ack_cam};
        if(I_cfg_commit&&O_cfg_ready) begin
          cfg_x0<=I_cfg_roi_x0;cfg_x1<=I_cfg_roi_x1;cfg_y0<=I_cfg_roi_y0;cfg_y1<=I_cfg_roi_y1;
          cfg_bg_th<=I_cfg_background_th;cfg_st_th<=I_cfg_stable_th;
          cfg_st_frames<=I_cfg_stable_frames;cfg_clear_frames<=I_cfg_clear_frames;
          cfg_st_max<=I_cfg_stable_max;cfg_present_min<=I_cfg_present_min;
          // I_cfg_teach remains in the interface for old station headers.
          // Replaying a configuration must never teach a present workpiece.
          cfg_toggle<=~cfg_toggle;
        end
      end
    end
    always @(posedge I_clk_cam or negedge I_rst_cam_n) begin
      if(!I_rst_cam_n) begin cfg_req_sync<=0;cfg_ack_cam<=0;end
      else begin
        cfg_req_sync<={cfg_req_sync[0],cfg_toggle};
        if(cfg_apply_cam) cfg_ack_cam<=cfg_req_sync[1];
      end
    end
    assign O_busy=net_state!=N_IDLE;
    assign O_ready=(net_state==N_FROZEN)&&!abort_net;

    always @(posedge I_clk_net or negedge I_rst_net_n) begin
      if(!I_rst_net_n) begin
        net_state<=N_IDLE;prep_count<=0;timeout_count<=0;capture_toggle<=0;
        cancel_toggle<=0;cap_result_seen<=0;cap_fifo_reset<=1;
        done_sync<=0;done_seen<=0;O_capture_error<=0;O_frame_id<=0;O_capture_diag<=0;
      end else begin
        done_sync<={done_sync[0],ddr_done_toggle};O_capture_error<=0;
        // The DDR mailbox is stable before its existing done toggle arrives.
        // A NET-local timeout remains evidence-only: later abort completion
        // must not replace it with camera/DDR counters from another instant.
        if(done_event) begin
          done_seen<=done_sync[1];cap_result_seen<=1;
          if(!O_capture_diag[7]) O_capture_diag<=ddr_done_diag;
        end
        if(packet_diag_complete) O_capture_diag<=packet_read_diag;
        case(net_state)
          N_IDLE: begin
            cap_fifo_reset<=0;timeout_count<=0;
            if(I_capture_req&&!O_packet_busy&&!I_cancel) begin
              cap_fifo_reset<=1;prep_count<=0;cap_result_seen<=0;net_state<=N_PREP;
              O_capture_diag<=0;
            end
          end
          N_PREP: begin
            if(I_cancel||I_release) begin cap_fifo_reset<=0;net_state<=N_IDLE;end
            else if(prep_count==31) begin
              cap_fifo_reset<=0;prep_count<=prep_count+1'b1;
            end else if(prep_count==47) begin
              capture_toggle<=~capture_toggle;net_state<=N_CAPTURE;timeout_count<=0;
            end else prep_count<=prep_count+1'b1;
          end
          N_CAPTURE: begin
            timeout_count<=timeout_count+1'b1;
            if(I_cancel||I_release||timeout_count==NET_TIMEOUT-1) begin
              cancel_toggle<=~cancel_toggle;net_state<=N_ABORT;
              if(timeout_count==NET_TIMEOUT-1) begin
                O_capture_error<=1;
                // Neither source mailbox completed: all field-valid bits
                // and counters are zero; only the local timeout is known.
                O_capture_diag<=128'h80;
              end
            end else if(done_event) begin
              if(ddr_done_good) begin net_state<=N_FROZEN;O_frame_id<=ddr_frame_id;end
              else begin net_state<=N_IDLE;O_capture_error<=1;end
            end
          end
          N_FROZEN: if(I_cancel||I_release) net_state<=N_ABORT;
          N_ABORT: if(cap_result_seen&&!O_packet_busy) net_state<=N_IDLE;
          default: net_state<=N_IDLE;
        endcase
      end
    end

    // Camera request and result mailbox. Metadata remains stable until the
    // next request; the toggle synchronizers establish the sampling delay.
    reg [1:0] cap_req_cam_sync,cancel_cam_sync,teach_cam_sync;
    reg cap_req_cam_seen,cancel_cam_seen,teach_cam_seen;
    reg cap_pending,cap_active,cap_bad,cam_done_toggle,cam_done_good;
    reg [3:0] cam_flush;
    reg [31:0] camera_frame_id,cam_frozen_id;
    reg [8:0] cam_x;
    reg [9:0] cam_y;
    reg [17:0] cam_groups;
    reg [1:0] pack_phase;
    reg [95:0] pack_hold;
    reg cap_fifo_we;
    reg [127:0] cap_fifo_di;
    wire cap_fifo_full,cap_fifo_empty;
    wire [127:0] cap_fifo_dout;
    wire cap_fifo_re;
    wire [8:0] cap_fifo_level;
    wire start_cam=cap_pending&&I_valid&&I_user;
    wire cancel_cam=cancel_cam_sync[1]!=cancel_cam_seen;
    wire take_cam=(cap_active||start_cam)&&I_valid&&!cancel_cam;
    // Existing display packer/video_out consume bits 95:72 first. Store
    // the same left-to-right pixels in our little-endian DDR byte stream.
    wire [95:0] capture_rgb={I_rgb[23:0],I_rgb[47:24],I_rgb[71:48],I_rgb[95:72]};
    wire [8:0] capture_x=start_cam?9'd0:cam_x;
    wire [9:0] capture_y=start_cam?10'd0:cam_y;
    wire [1:0] capture_phase=start_cam?2'd0:pack_phase;
    wire teach_cam=teach_cam_sync[1]!=teach_cam_seen;
    wire pres_background,pres_present,pres_stable,pres_trigger;
    reg pres_toggle;
    reg [1:0] pres_toggle_sync;
    reg pres_toggle_seen;
    reg [2:0] pres_level_s1;
    reg [1:0] teach_ack_sync;
    reg teach_pending_net,teach_wait_net,teach_low_seen;
    wire teach_ack_idle=(teach_ack_sync[1]==teach_toggle);

    // Diagnostic observation only; none of these bits feed capture control.
    // flags: input error, mid-frame USER, LAST mismatch, FIFO full,
    // final count/phase, group overrun, cancellation, NET timeout.
    // Coordinates are the capture pointer at the first observed cause.
    wire [7:0] cam_diag_now={1'b0,
      cancel_cam&&(cap_pending||cap_active),
      take_cam&&!start_cam&&(cam_groups>=FRAME_GROUPS),
      take_cam&&I_last&&(capture_y==FRAME_H-1)&&
        (cam_groups!=FRAME_GROUPS-1||capture_x!=GROUPS-1||capture_phase!=3),
      cap_fifo_we&&cap_fifo_full,
      take_cam&&(I_last!=(capture_x==GROUPS-1)),
      take_cam&&I_user&&!start_cam,
      take_cam&&I_frame_error};
    wire cam_diag_new_req=cap_req_cam_sync[1]!=cap_req_cam_seen;
    reg [7:0] cam_diag_flags;
    reg [8:0] cam_diag_bad_x;
    reg [9:0] cam_diag_bad_y;
    reg [79:0] cam_diag_hold;
    reg [79:0] ddr_cam_diag;
    wire [7:0] cam_diag_next=(cam_diag_new_req?8'd0:cam_diag_flags)|cam_diag_now;
    wire cam_diag_first=((cam_diag_new_req?8'd0:cam_diag_flags)==0)&&(cam_diag_now!=0);
    wire [8:0] cam_diag_x_next=cam_diag_first?capture_x:(cam_diag_new_req?9'd0:cam_diag_bad_x);
    wire [9:0] cam_diag_y_next=cam_diag_first?capture_y:(cam_diag_new_req?10'd0:cam_diag_bad_y);
    always @(posedge I_clk_cam or negedge I_rst_cam_n) begin
      if(!I_rst_cam_n) begin
        cam_diag_flags<=0;cam_diag_bad_x<=0;cam_diag_bad_y<=0;cam_diag_hold<=0;
      end else begin
        cam_diag_flags<=cam_diag_next;
        cam_diag_bad_x<=cam_diag_x_next;cam_diag_bad_y<=cam_diag_y_next;
        // Freeze on the existing camera completion event. Hold until the
        // next completion; DDR samples only after the synchronized toggle.
        if(cam_flush==1) cam_diag_hold<={14'd0,cam_groups,
          6'd0,cam_diag_y_next,7'd0,cam_diag_x_next,7'd0,1'b1,cam_diag_next};
      end
    end

    always @(posedge I_clk_cam or negedge I_rst_cam_n) begin
      if(!I_rst_cam_n) begin
        cap_req_cam_sync<=0;cancel_cam_sync<=0;teach_cam_sync<=0;
        cap_req_cam_seen<=0;cancel_cam_seen<=0;teach_cam_seen<=0;
        cap_pending<=0;cap_active<=0;cap_bad<=0;cam_done_toggle<=0;cam_done_good<=0;
        cam_flush<=0;camera_frame_id<=0;cam_frozen_id<=0;cam_x<=0;cam_y<=0;
        cam_groups<=0;pack_phase<=0;pack_hold<=0;cap_fifo_we<=0;cap_fifo_di<=0;pres_toggle<=0;
      end else begin
        cap_req_cam_sync<={cap_req_cam_sync[0],capture_toggle};
        cancel_cam_sync<={cancel_cam_sync[0],cancel_toggle};
        teach_cam_sync<={teach_cam_sync[0],teach_toggle};
        teach_cam_seen<=teach_cam_sync[1];cap_fifo_we<=0;
        if(pres_trigger) pres_toggle<=~pres_toggle;
        if(I_valid&&I_user) camera_frame_id<=camera_frame_id+1'b1;
        if(cap_req_cam_sync[1]!=cap_req_cam_seen) begin
          cap_req_cam_seen<=cap_req_cam_sync[1];cap_pending<=1;cap_bad<=0;
          cam_groups<=0;pack_phase<=0;cam_x<=0;cam_y<=0;
        end
        if(cam_flush!=0) begin
          cam_flush<=cam_flush-1'b1;
          if(cam_flush==1) begin cam_done_good<=!cap_bad;cam_done_toggle<=~cam_done_toggle;end
        end
        if(cap_fifo_we&&cap_fifo_full) cap_bad<=1;
        if(start_cam) begin
          cap_pending<=0;cap_active<=1;cam_frozen_id<=camera_frame_id+1'b1;
          cam_groups<=0;pack_phase<=0;cam_x<=0;cam_y<=0;
        end
        if(take_cam) begin
          cam_groups<=start_cam?18'd1:cam_groups+1'b1;
          pack_phase<=capture_phase+1'b1;
          if(I_frame_error||(I_user&&!start_cam)||(I_last!=(capture_x==GROUPS-1))) cap_bad<=1;
          case(capture_phase)
            0: pack_hold<=capture_rgb;
            1: begin cap_fifo_di<={capture_rgb[31:0],pack_hold};pack_hold<={32'd0,capture_rgb[95:32]};cap_fifo_we<=1;end
            2: begin cap_fifo_di<={capture_rgb[63:0],pack_hold[63:0]};pack_hold<={64'd0,capture_rgb[95:64]};cap_fifo_we<=1;end
            3: begin cap_fifo_di<={capture_rgb,pack_hold[31:0]};cap_fifo_we<=1;end
          endcase
          if(I_last) begin
            cam_x<=0;cam_y<=capture_y+1'b1;
            if(capture_y==FRAME_H-1) begin
              cap_active<=0;cam_flush<=4;
              if(cam_groups!=FRAME_GROUPS-1||capture_x!=GROUPS-1||capture_phase!=3) cap_bad<=1;
            end
          end else cam_x<=capture_x+1'b1;
          if(!start_cam && cam_groups>=FRAME_GROUPS) begin cap_active<=0;cap_bad<=1;cam_flush<=4;end
        end
        if(cancel_cam) begin
          cancel_cam_seen<=cancel_cam_sync[1];
          if(cap_pending||cap_active) begin cap_pending<=0;cap_active<=0;cap_bad<=1;cam_flush<=4;end
        end
      end
    end

    hx_pcb_presence #(.FRAME_W(FRAME_W),.FRAME_H(FRAME_H),.PRESENT_MIN(PRESENCE_MIN),
      .STABLE_MAX(PRESENCE_STABLE_MAX),.CONFIRM_FRAMES(PRESENCE_CONFIRM)) u_presence (
      .I_clk(I_clk_cam),.I_rst_n(I_rst_cam_n),.I_teach(teach_cam),
      .I_rgb(I_rgb),.I_valid(I_valid),.I_user(I_user),.I_last(I_last),.I_frame_error(I_frame_error),
      .I_cfg_apply(cfg_apply_cam),.I_roi_x0(cfg_x0),.I_roi_x1(cfg_x1),.I_roi_y0(cfg_y0),.I_roi_y1(cfg_y1),
      .I_background_th(cfg_bg_th),.I_stable_th(cfg_st_th),.I_stable_frames(cfg_st_frames),
      .I_clear_frames(cfg_clear_frames),.I_present_min(cfg_present_min),.I_stable_max(cfg_st_max),
      .O_background_valid(pres_background),.O_present(pres_present),.O_stable(pres_stable),.O_trigger(pres_trigger));
    always @(posedge I_clk_net or negedge I_rst_net_n) begin
      if(!I_rst_net_n) begin
        pres_toggle_sync<=0;pres_toggle_seen<=0;pres_level_s1<=0;
        teach_toggle<=0;teach_ack_sync<=0;teach_pending_net<=0;
        teach_wait_net<=0;teach_low_seen<=0;
        O_background_valid<=0;O_pcb_present<=0;O_pcb_stable<=0;O_pcb_trigger<=0;
      end else begin
        pres_level_s1<={pres_background,pres_present,pres_stable};
        teach_ack_sync<={teach_ack_sync[0],teach_cam_seen};
        pres_toggle_sync<={pres_toggle_sync[0],pres_toggle};
        pres_toggle_seen<=pres_toggle_sync[1];
        // Only one request toggle may be in flight. Rapid mode changes are
        // coalesced in a pending bit, so two NET pulses cannot cancel across
        // the slower camera synchronizer. Camera's seen toggle is the ack.
        if(I_background_capture) begin
          teach_pending_net<=1;teach_wait_net<=1;teach_low_seen<=0;
        end
        if(teach_pending_net&&teach_ack_idle) begin
          teach_toggle<=~teach_toggle;teach_pending_net<=0;
          teach_wait_net<=1;teach_low_seen<=0;
        end else if(teach_wait_net&&teach_ack_idle&&!I_background_capture) begin
          // Do not interpret an old teaching frame's completion as the new
          // request. First see its camera acknowledgement and invalid level.
          if(!pres_level_s1[2]) teach_low_seen<=1;
          else if(teach_low_seen) teach_wait_net<=0;
        end
        if(I_background_capture||teach_pending_net||teach_wait_net) begin
          O_background_valid<=0;O_pcb_present<=0;O_pcb_stable<=0;O_pcb_trigger<=0;
        end else begin
          {O_background_valid,O_pcb_present,O_pcb_stable}<=pres_level_s1;
          O_pcb_trigger<=pres_toggle_sync[1]!=pres_toggle_seen;
        end
      end
    end

    soft_fifo_al_4057d6b76aa6 #(.DATA_WIDTH_W(128),.DATA_WIDTH_R(128),
      .ADDR_WIDTH_W(9),.ADDR_WIDTH_R(9),.AL_FULL_NUM(480),.AL_EMPTY_NUM(16),
      .SHOW_AHEAD_EN(1'b1),.OUTREG_EN("NOREG")) u_capture_fifo (
      .rst(!I_rst_cam_n||!I_rst_ddr_n||cap_fifo_reset),.clkw(I_clk_cam),.clkr(I_clk_ddr),
      .we(cap_fifo_we&&!cap_fifo_full),.di(cap_fifo_di),.re(cap_fifo_re),.dout(cap_fifo_dout),
      .valid(),.full_flag(cap_fifo_full),.empty_flag(cap_fifo_empty),.afull(),.aempty(),
      .wrusedw(),.rdusedw(cap_fifo_level));

    // Write completion includes MC retirement, not just enqueueing into
    // mc_to_user_interface's command FIFO. Thus ready is a real read fence.
    reg [1:0] cap_req_ddr_sync,cam_done_ddr_sync;
    reg cap_req_ddr_seen,cam_done_ddr_seen,ddr_capture_active,ddr_cam_done,ddr_cam_good;
    reg [17:0] writes_sent,writes_retired;
    reg [3:0] empty_settle;
    wire wr_fire=O_ddr_wr_valid&&I_ddr_wr_ready;
    wire drop_capture=ddr_cam_done&&!ddr_cam_good;
    assign O_ddr_wr_valid=ddr_capture_active&&!drop_capture&&!cap_fifo_empty&&(writes_sent<FRAME_WORDS);
    assign O_ddr_wr_addr=SNAP_BASE+{writes_sent,3'b000};
    assign O_ddr_wr_data=cap_fifo_dout;
    assign cap_fifo_re=wr_fire||(ddr_capture_active&&!cap_fifo_empty&&(drop_capture||writes_sent>=FRAME_WORDS));
    always @(posedge I_clk_ddr or negedge I_rst_ddr_n) begin
      if(!I_rst_ddr_n) begin
        cap_req_ddr_sync<=0;cam_done_ddr_sync<=0;cap_req_ddr_seen<=0;cam_done_ddr_seen<=0;
        ddr_capture_active<=0;ddr_cam_done<=0;ddr_cam_good<=0;
        writes_sent<=0;writes_retired<=0;empty_settle<=0;ddr_done_toggle<=0;
        ddr_done_good<=0;ddr_frame_id<=0;ddr_cam_diag<=0;ddr_done_diag<=0;
      end else begin
        cap_req_ddr_sync<={cap_req_ddr_sync[0],capture_toggle};
        cam_done_ddr_sync<={cam_done_ddr_sync[0],cam_done_toggle};
        if(cap_req_ddr_sync[1]!=cap_req_ddr_seen) begin
          cap_req_ddr_seen<=cap_req_ddr_sync[1];ddr_capture_active<=1;
          ddr_cam_done<=0;ddr_cam_good<=0;writes_sent<=0;writes_retired<=0;empty_settle<=0;
          ddr_cam_diag<=0;
        end
        if(cam_done_ddr_sync[1]!=cam_done_ddr_seen) begin
          cam_done_ddr_seen<=cam_done_ddr_sync[1];ddr_cam_done<=1;
          ddr_cam_good<=cam_done_good;ddr_frame_id<=cam_frozen_id;
          ddr_cam_diag<=cam_diag_hold;
        end
        if(ddr_capture_active) begin
          if(wr_fire) writes_sent<=writes_sent+1'b1;
          if(I_ddr_wr_retire) writes_retired<=writes_retired+1'b1;
          if(ddr_cam_done&&cap_fifo_empty&&writes_retired==writes_sent&&!wr_fire) begin
            if(empty_settle==12) begin
              ddr_capture_active<=0;ddr_done_good<=ddr_cam_good&&(writes_sent==FRAME_WORDS);
              ddr_done_toggle<=~ddr_done_toggle;
              // bits 8/9 validate coherent CAM/DDR snapshots. Bit 10
              // reports a completed DDR count mismatch. The count fields
              // are zero-extended rather than asynchronously sampled.
              ddr_done_diag<={6'd0,writes_retired,6'd0,writes_sent,
                ddr_cam_diag[79:16],5'd0,(writes_sent!=FRAME_WORDS),
                1'b1,ddr_cam_diag[8],ddr_cam_diag[7:0]};
            end else empty_settle<=empty_settle+1'b1;
          end else empty_settle<=0;
        end
      end
    end

    // Each packet reads exactly 135 RGB words =720 pixels =1440 YUYV bytes.
    // Packet index is held unchanged across the request mailbox crossing.
    reg packet_toggle;
    reg [10:0] packet_index_hold;
    reg packet_fifo_reset;
    reg [1:0] packet_req_ddr_sync;
    reg packet_req_ddr_seen,packet_ddr_active;
    reg [7:0] packet_reads_sent,packet_reads_returned;
    reg [24:0] packet_ddr_base;
    always @(posedge I_clk_ddr or negedge I_rst_ddr_n) begin
      if(!I_rst_ddr_n) begin
        packet_diag_req_sync<=0;packet_diag_ack<=0;packet_diag_ddr_hold<=0;
      end else begin
        packet_diag_req_sync<={packet_diag_req_sync[0],packet_diag_req};
        if(packet_diag_req_sync[1]!=packet_diag_ack) begin
          packet_diag_ddr_hold<={packet_reads_sent,packet_reads_returned,I_ddr_debug};
          packet_diag_ack<=packet_diag_req_sync[1];
        end
      end
    end
    wire packet_fifo_full,packet_fifo_empty;
    wire [127:0] packet_fifo_dout;
    wire packet_fifo_re;
    assign O_ddr_rd_req=packet_ddr_active&&(packet_reads_sent<PACKET_WORDS);
    assign O_ddr_rd_addr=packet_ddr_base+{packet_reads_sent,3'b000};
    always @(posedge I_clk_ddr or negedge I_rst_ddr_n) begin
      if(!I_rst_ddr_n) begin
        packet_req_ddr_sync<=0;packet_req_ddr_seen<=0;packet_ddr_active<=0;
        packet_reads_sent<=0;packet_reads_returned<=0;packet_ddr_base<=SNAP_BASE;
      end else begin
        packet_req_ddr_sync<={packet_req_ddr_sync[0],packet_toggle};
        if(packet_req_ddr_sync[1]!=packet_req_ddr_seen) begin
          packet_req_ddr_seen<=packet_req_ddr_sync[1];packet_ddr_active<=1;
          packet_reads_sent<=0;packet_reads_returned<=0;
          packet_ddr_base<=SNAP_BASE+({14'd0,packet_index_hold}<<10)+
            ({14'd0,packet_index_hold}<<5)+({14'd0,packet_index_hold}<<4)+({14'd0,packet_index_hold}<<3);
        end
        if(O_ddr_rd_req&&I_ddr_rd_ready) packet_reads_sent<=packet_reads_sent+1'b1;
        if(I_ddr_rd_valid&&packet_ddr_active) begin
          packet_reads_returned<=packet_reads_returned+1'b1;
          if(packet_reads_returned==PACKET_WORDS-1) packet_ddr_active<=0;
        end
      end
    end
    soft_fifo_al_4057d6b76aa6 #(.DATA_WIDTH_W(128),.DATA_WIDTH_R(128),
      .ADDR_WIDTH_W(8),.ADDR_WIDTH_R(8),.AL_FULL_NUM(240),.AL_EMPTY_NUM(4),
      .SHOW_AHEAD_EN(1'b1),.OUTREG_EN("NOREG")) u_packet_fifo (
      .rst(!I_rst_net_n||!I_rst_ddr_n||packet_fifo_reset),.clkw(I_clk_ddr),.clkr(I_clk_net),
      .we(I_ddr_rd_valid&&packet_ddr_active),.di(I_ddr_rd_data),.re(packet_fifo_re),
      .dout(packet_fifo_dout),.valid(),.full_flag(packet_fifo_full),.empty_flag(packet_fifo_empty),
      .afull(),.aempty(),.wrusedw(),.rdusedw());

    localparam P_IDLE=2'd0,P_PREP=2'd1,P_DATA=2'd2;
    localparam C_IDLE=3'd0,C_SUM=3'd1,C_QUANTIZE=3'd2,C_PAIR=3'd3,C_PACK=3'd4;
    reg [1:0] packet_state;
    reg [2:0] convert_state;
    reg [5:0] packet_prep;
    reg [151:0] reservoir;
    reg [7:0] reservoir_bits;
    reg pair_second;
    reg [23:0] yuv0,yuv_current;
    reg [15:0] yr66,yg129,yb25,ur38,ug74,vg94,vb18;
    reg [14:0] r112,b112;
    reg [15:0] y_acc,u_acc,v_acc;
    reg [7:0] u_average,v_average;
    // BT.601 limited range, matching HXA1's PC encoder and secondary reader.
    // Bit 7 implements the +128 numerator rounding without adding another
    // full-width adder to the product-sum stage. U/V use two's-complement bits.
    wire [7:0] y_quantized=y_acc[15:8]+8'd16+{7'd0,y_acc[7]};
    wire [7:0] u_quantized=u_acc[15:8]+8'd128+{7'd0,u_acc[7]};
    wire [7:0] v_quantized=v_acc[15:8]+8'd128+{7'd0,v_acc[7]};
    wire [8:0] u_sum={1'b0,yuv0[15:8]}+{1'b0,yuv_current[15:8]};
    wire [8:0] v_sum={1'b0,yuv0[23:16]}+{1'b0,yuv_current[23:16]};
    reg [31:0] output_word;
    reg word_valid;
    reg [1:0] output_byte;
    reg [10:0] bytes_sent;
    reg discard_packet;
    assign packet_fifo_re=(packet_state==P_DATA)&&(reservoir_bits<24)&&!packet_fifo_empty;
    assign O_packet_valid=word_valid&&!discard_packet&&!abort_net;
    assign O_packet_data=output_word[7:0];
    assign O_packet_last=word_valid&&(bytes_sent==PACKET_BYTES-1);
    always @(posedge I_clk_net or negedge I_rst_net_n) begin
      if(!I_rst_net_n) begin
        packet_state<=P_IDLE;packet_prep<=0;packet_toggle<=0;packet_index_hold<=0;
        packet_fifo_reset<=1;O_packet_busy<=0;O_packet_error<=0;
        reservoir<=0;reservoir_bits<=0;pair_second<=0;yuv0<=0;
        convert_state<=C_IDLE;yuv_current<=0;
        yr66<=0;yg129<=0;yb25<=0;ur38<=0;ug74<=0;vg94<=0;vb18<=0;r112<=0;b112<=0;
        y_acc<=0;u_acc<=0;v_acc<=0;u_average<=0;v_average<=0;
        output_word<=0;word_valid<=0;output_byte<=0;bytes_sent<=0;discard_packet<=0;
        packet_stall_count<=0;packet_diag_req<=0;packet_diag_ack_sync<=0;packet_full_sync<=0;
        packet_diag_wait<=0;packet_stall_reported<=0;packet_stall_error_pending<=0;
        packet_diag_net_hold<=0;
      end else begin
        O_packet_error<=0;
        packet_diag_ack_sync<={packet_diag_ack_sync[0],packet_diag_ack};
        packet_full_sync<={packet_full_sync[0],packet_fifo_full};
        // Observe a stalled packet before the one-second link lease expires.
        // Do not discard outstanding DDR responses or reset read ownership:
        // late snapshot data must never be delivered to the HDMI FIFO.
        if(packet_state!=P_DATA||!O_packet_busy||packet_fifo_re||
           (word_valid&&(I_packet_ready||discard_packet||abort_net)))
          packet_stall_count<=0;
        else if(!packet_stall_reported&&!packet_diag_wait) begin
          if(packet_stall_count==PACKET_STALL_CYCLES-1) begin
            packet_diag_req<=~packet_diag_req;packet_diag_wait<=1;
            packet_stall_reported<=1;
            packet_diag_net_hold<={5'd0,packet_index_hold,
              3'd0,packet_fifo_empty,packet_full_sync[1],discard_packet,word_valid,I_packet_ready,
              3'd0,convert_state,packet_state,5'd0,bytes_sent};
          end else packet_stall_count<=packet_stall_count+1'b1;
        end
        if(packet_diag_complete) begin
          packet_diag_wait<=0;packet_stall_error_pending<=1;
        end
        // The diagnostic register above has committed before error is seen
        // by hxa_main_link, so CANCEL contains this exact stalled request.
        if(packet_stall_error_pending) begin
          O_packet_error<=1;packet_stall_error_pending<=0;
        end
        if(O_packet_busy&&abort_net) discard_packet<=1;
        case(packet_state)
          P_IDLE: begin
            packet_fifo_reset<=0;
            if(I_packet_req) begin
              if(!O_ready||I_packet_index>=PACKET_COUNT) O_packet_error<=1;
              else begin
                packet_index_hold<=I_packet_index;packet_fifo_reset<=1;packet_prep<=0;
                O_packet_busy<=1;packet_state<=P_PREP;reservoir<=0;reservoir_bits<=0;
                pair_second<=0;word_valid<=0;bytes_sent<=0;output_byte<=0;discard_packet<=0;
                convert_state<=C_IDLE;
                packet_stall_count<=0;packet_stall_reported<=0;
              end
            end
          end
          P_PREP: begin
            if(packet_prep==31) begin packet_fifo_reset<=0;packet_prep<=packet_prep+1'b1;end
            else if(packet_prep==47) begin packet_toggle<=~packet_toggle;packet_state<=P_DATA;end
            else packet_prep<=packet_prep+1'b1;
          end
          P_DATA: begin
            if(packet_fifo_re) begin
              case(reservoir_bits)
                0: reservoir<={24'd0,packet_fifo_dout};
                8: reservoir<={16'd0,packet_fifo_dout,reservoir[7:0]};
                default: reservoir<={8'd0,packet_fifo_dout,reservoir[15:0]};
              endcase
              reservoir_bits<=reservoir_bits+128;
            end
            // HXA1 carries limited-range YUYV (Y=16..235, U/V=16..240).
            // Separate constant products, sums, rounding and pair averaging so
            // no multiplier/add/clamp/average chain spans one 125 MHz edge.
            case(convert_state)
              C_IDLE:if(!packet_fifo_re&&!word_valid&&reservoir_bits>=24)begin
                reservoir<=reservoir>>24;reservoir_bits<=reservoir_bits-24;
                yr66<=reservoir[23:16]*16'd66;yg129<=reservoir[15:8]*16'd129;yb25<=reservoir[7:0]*16'd25;
                ur38<=reservoir[23:16]*16'd38;ug74<=reservoir[15:8]*16'd74;
                vg94<=reservoir[15:8]*16'd94;vb18<=reservoir[7:0]*16'd18;
                r112<=reservoir[23:16]*15'd112;b112<=reservoir[7:0]*15'd112;
                convert_state<=C_SUM;
              end
              C_SUM:begin
                y_acc<=yr66+yg129+yb25;
                u_acc<={1'b0,b112}-ur38-ug74;
                v_acc<={1'b0,r112}-vg94-vb18;
                convert_state<=C_QUANTIZE;
              end
              C_QUANTIZE:begin
                // Y numerator is 0..56100, U/V are -28560..28560.
                // Rounded and offset values fit their legal byte ranges.
                yuv_current<={v_quantized,u_quantized,y_quantized};
                convert_state<=C_PAIR;
              end
              C_PAIR:begin
                if(!pair_second)begin yuv0<=yuv_current;pair_second<=1;convert_state<=C_IDLE;end
                else begin u_average<=u_sum[8:1];v_average<=v_sum[8:1];convert_state<=C_PACK;end
              end
              C_PACK:begin
                output_word<={v_average,yuv_current[7:0],u_average,yuv0[7:0]};
                word_valid<=1;output_byte<=0;pair_second<=0;convert_state<=C_IDLE;
              end
              default:convert_state<=C_IDLE;
            endcase
            if(word_valid&&(I_packet_ready||discard_packet||abort_net)) begin
              output_word<=output_word>>8;output_byte<=output_byte+1'b1;bytes_sent<=bytes_sent+1'b1;
              if(output_byte==3) word_valid<=0;
              if(bytes_sent==PACKET_BYTES-1) begin
                O_packet_busy<=0;packet_state<=P_IDLE;word_valid<=0;
              end
            end
          end
          default: packet_state<=P_IDLE;
        endcase
      end
    end
endmodule
