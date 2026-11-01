// One frozen image at a time. Images and retransmits are sourced by packet
// index from hx_snapshot_service; no HDMI timing or pixels enter this module.
module hxa_main_link #(
    parameter integer CLK_HZ=125000000,
    parameter integer PACKET_GAP_CYCLES=CLK_HZ/12500,
    // Capture-to-capture limit for ordinary CNN only (0..200 ms). The
    // compatibility default remains 200 ms; zero starts the next job as
    // soon as the prior result ACK and snapshot ownership permit it.
    parameter integer ORDINARY_MIN_INTERVAL_MS=200,
    // Ordinary first-send DATA may fill the now-idle TX RAM during the
    // preceding DATA gap. The gap itself and all retry/PCB timing are kept.
    parameter integer ORDINARY_GAP_PREFETCH=0,
    // HELLO byte 1 is the capability bitmap advertised by the main board.
    // Keep the historical value as the default so old instantiations and
    // old secondary boards continue to interoperate.  CNN/multibox builds
    // set bit 6 in their top-level instance.
    parameter [7:0] HELLO_CAPABILITIES=8'h03,
    // Continuous PCB mode keeps one Type8 result in flight at a time, then
    // returns to IDLE for the next frame.  The default preserves the legacy
    // background/trigger/WAIT_CLEAR behavior for existing builds.
    parameter integer PCB_CONTINUOUS=0,
    // KEY4 PCB profile: consume a one-cycle trigger only while idle/online.
    // No background teaching or held-key recapture. An idle heartbeat/ACK
    // may retain one press until its control packet finishes.
    parameter integer PCB_KEY_ONESHOT=0
)(
    input wire clk,rst_n,enable,phy_ready,pcb_mode,detect_enable,
    // Text-trace mode is a one-shot capture selected by SW4:SW3=10.
    // It deliberately shares the normal snapshot/packet path, but uses
    // purpose=2 and waits for the secondary's Type15 completion report.
    input wire text_mode,text_trigger,
    input wire maze_mode,maze_trigger,
    // One-clock pulse from KEY1 in the ordinary CNN mode. The link emits a
    // Type20 command with command id 2; PCB and text modes ignore it.
    input wire report_request,
    input wire background_valid,pcb_trigger,pcb_present,teach_good,
    output reg capture_req,capture_cancel,capture_release,background_capture,
    input wire snapshot_busy,snapshot_ready,snapshot_error,
    input wire [31:0] snapshot_frame_id,
    input wire [127:0] snapshot_diag,
    output reg packet_req,output reg [10:0] packet_index,
    input wire packet_busy,packet_valid,packet_last,packet_error,
    input wire [7:0] packet_data,output wire packet_ready,
    output wire udp_req,udp_valid,output wire [7:0] udp_data,
    output wire [15:0] udp_len,input wire udp_busy,
    input wire rx_valid,input wire [7:0] rx_data,input wire [15:0] rx_len,
    input wire rx_error,output wire stack_reset,
    output reg online,output reg result_valid,output reg result_toggle,
    output wire [511:0] result_data,output reg [31:0] result_frame,
    output reg [31:0] sent_frames,failed_frames,
    output reg [255:0] station_header,output reg station_commit,input wire station_ready,
    output wire [7:0] job_state,
    output reg multi_valid, output reg multi_toggle,
    output reg [2:0] multi_count, output wire [511:0] multi_data,
    output reg [31:0] multi_job,
    output reg [2:0] copy_state,output reg copy_toggle
);
    localparam OFF=0,DISCOVER=1,IDLE=2,CAPTURE=3,WAIT_READY=4,
        NEXT_PACKET=5,LOAD_IMAGE=6,WAIT_ACK=7,WAIT_RESULT=8,
        LOAD_CONTROL=9,TX_START=10,TX_WAIT=11,NACK_PRIME=12,
        NACK_CHECK=13,NACK_NEXT=14,JOB_WAIT=15,WAIT_CLEAR=16,CANCEL=17,PACKET_GAP=18,
        PREFETCH_READY=19;
    reg [4:0] state,return_state;
    reg [7:0] tx_type;
    reg [15:0] tx_payload_len;
    reg [10:0] load_at;
    reg tx_start;
    wire tx_busy,tx_done,tx_error;
    reg [63:0] session;
    reg [31:0] cycles,frame_id,job_id,report_id;
    reg report_pending;
    reg [31:0] frame_crc;
    // These timers saturate at the values below. Size the carry chains for
    // those limits rather than implementing seven general 16/32-bit timers.
    localparam integer MS_DIV_BITS=(CLK_HZ/1000>1)?$clog2(CLK_HZ/1000):1;
    localparam integer GAP_BITS=(PACKET_GAP_CYCLES>1)?$clog2(PACKET_GAP_CYCLES):1;
    // A frame/packet failure is recoverable while the peer session is alive.
    // Keep the lease long enough to cover a slow frame without turning a
    // transient image error into a reconnect.
    localparam integer LINK_LEASE_TIMEOUT_MS=3000;
    localparam integer RESULT_ERROR_HOLD_MS=300;
    reg [11:0] lease_ms;
    reg [11:0] control_ms,transfer_ms;
    reg [7:0] rate_ms,heartbeat_ms;
    reg [9:0] result_ms;
    reg [8:0] error_hold_ms;
    reg error_hold_active;
    reg cancel_reconnect;
    reg [MS_DIV_BITS-1:0] ms_div;
    wire tick_ms=(ms_div==CLK_HZ/1000-1);
    reg enable_d,mode_d,maze_mode_d,text_mode_d,resend,ready_seen,ack_seen,nack_seen,result_seen;
    reg [1:0] purpose;
    reg [1:0] retry;
    // Type8 and type18 are mutually exclusive results for a frame. Preserve
    // their original wire offsets in one bank: no duplicated pending box
    // registers and no 512-bit type-dependent input mux are needed.
    // Both result views commit from the same payload on the same edge.
    // Their overlapping 384 bits share storage; invalidation hides only the
    // multibox view and preserves the legacy result payload. Keep visibility
    // independent of multi_valid so existing clear/commit priority is exact.
    reg [639:0] committed_payload;
    reg multi_payload_visible;
    assign result_data=committed_payload[511:0];
    assign multi_data=multi_payload_visible?committed_payload[639:128]:512'd0;
    reg [639:0] pending_payload;
    wire [511:0] pending_result=pending_payload[511:0];
    reg pending_maze_result,completed_result_maze;
    reg pending_multibox,completed_result_multibox;
    reg [2:0] pending_multi_count;
    wire [511:0] pending_multi_data=pending_payload[639:128];
    reg [31:0] pending_frame;
    reg job_finished,job_failed;
    reg [20:0] copy_elapsed_ms;
    reg [14:0] copy_prepare_ms;
    reg copy_drawing,copy_requires_cycle;
    reg job_active,pcb_trigger_pending,maze_trigger_pending,text_trigger_pending;
    // Background lifetime follows the physical operating mode, not a UDP
    // lease. Reconnecting with a workpiece present must not teach it as empty.
    reg pcb_mode_active_d,bg_refresh_wait,bg_low_seen;
    reg teach_pending,teach_active;
    reg [7:0] peer_caps;
    wire maze_active=(maze_mode===1'b1)&&pcb_mode;
    wire maze_press=(maze_trigger===1'b1);
    wire text_run=(text_mode===1'b1);
    wire text_press=(text_trigger===1'b1);
    wire pcb_run=pcb_mode&&!maze_active;
    wire [1:0] capture_purpose=text_run?2'd2:(teach_pending&&pcb_run)?2'd2:maze_active?2'd3:pcb_run?2'd1:2'd0;
    wire pcb_continuous_run=(PCB_CONTINUOUS!=0)&&pcb_run;
    wire pcb_key_run=(PCB_KEY_ONESHOT!=0)&&pcb_run;
    wire pcb_fast_run=pcb_continuous_run||pcb_key_run;
    // In the continuous variant background/trigger are status-only inputs.
    // Keep the legacy expression intact when the parameter is zero.
    wire pcb_background_ready=pcb_fast_run ? 1'b1 :
        (pcb_mode_active_d&&!maze_active&&!bg_refresh_wait&&background_valid);
    wire continuous_pcb_job=pcb_fast_run&&(purpose==2'd1);
    wire link_idle=(state==IDLE)||(state==WAIT_CLEAR)||
        (((state==LOAD_CONTROL)||(state==TX_START)||(state==TX_WAIT))&&
         ((return_state==IDLE)||(return_state==WAIT_CLEAR)));
    wire accept_teach=!pcb_fast_run&&teach_good&&enable&&pcb_run&&phy_ready&&online&&peer_caps[4]&&
        link_idle&&!job_active&&!snapshot_busy&&!teach_pending;
    reg result_ack_pending,completed_result_valid;
    reg [31:0] completed_result_frame,completed_result_job,tx_frame_id,tx_job_id;
    reg station_seen,station_pending,station_wait,station_busy_seen;
    reg [31:0] station_version;
    wire pcb_key_idle_window=(state==IDLE)||
        (((state==LOAD_CONTROL)||(state==TX_START)||(state==TX_WAIT))&&
         return_state==IDLE&&(tx_type==10||tx_type==9||tx_type==19));
    reg [GAP_BITS-1:0] packet_gap_count;
    reg ordinary_gap_pending;
    // Optional HXD1 CANCEL detail. Old peers ignore its payload and retain
    // their normal lease isolation; no image error is suppressed here.
    reg [7:0] cancel_reason;
    reg [4:0] cancel_state;
    reg [127:0] cancel_snapshot_diag;
    wire [223:0] cancel_body={32'h09160003,cancel_snapshot_diag,
                              8'd0,3'd0,cancel_state,cancel_reason,8'd1,32'h31445848};
    wire codec_rst_n=rst_n && enable && phy_ready;
    wire r_packet_valid,r_error;
    reg r_take;
    wire [7:0] r_type,r_body_data;
    wire [15:0] r_flags,r_index,r_count,r_length;
    wire [63:0] r_session;
    wire [31:0] r_frame,dropped;
    reg [10:0] r_addr;
    reg [1:0] r_state;
    reg [7:0] r_at;
    reg [639:0] r_body;
    // One rolling 16-byte box is validated at a time while copying RX bytes.
    // Its first 15 bytes need no reset: a complete slot always overwrites all
    // of them before the shared comparator is sampled on byte 16.
    reg [119:0] r_box_shift;
    wire [127:0] r_box={r_body_data,r_box_shift};
    reg r_multibox_valid;
    (* ram_style="dram" *) reg [7:0] nack_mem[0:159];
    reg [7:0] nack_byte;
    reg [7:0] saved_type;
    reg [31:0] saved_frame;
    reg [15:0] saved_len;
    reg [15:0] saved_index;
    reg [2:0] nack_rounds_seen;
    wire duplicate_nack_round=(r_index==1&&nack_rounds_seen[0])||
        (r_index==2&&nack_rounds_seen[1])||(r_index==3&&nack_rounds_seen[2]);
    // Do not expire a visible result on the same clock as a transient frame
    // fault.  The fault path below starts the short display hold instead.
    wire frame_fault_now=r_error||packet_error||tx_error||snapshot_error;
    reg r_event;
    assign job_state={3'd0,state};
    function [31:0] crc_byte;
        input [31:0] c;input [7:0] d;integer j;reg [31:0] t;
        begin t=c^{24'd0,d};for(j=0;j<8;j=j+1)t=t[0]?((t>>1)^32'hedb88320):(t>>1);crc_byte=t;end
    endfunction
    function [7:0] control_byte;
        input [7:0] typ;input [10:0] a;input [1:0] frame_purpose;
        input [31:0] job_number,image_crc;
        input [223:0] failure_body;
        begin
            control_byte=0;
            case(typ)
                1:case(a)
                    0:control_byte=1;1:control_byte=HELLO_CAPABILITIES;default:control_byte=0;
                  endcase
                3:case(a)
                    0:control_byte=8'h00;1:control_byte=8'h05;
                    2:control_byte=8'hd0;3:control_byte=8'h02;
                    4:control_byte=1;5:control_byte={6'd0,frame_purpose};
                    8:control_byte=8'h00;9:control_byte=8'h20;10:control_byte=8'h1c;11:control_byte=0;
                    12:control_byte=job_number[7:0];13:control_byte=job_number[15:8];
                    14:control_byte=job_number[23:16];15:control_byte=job_number[31:24];
                    default:control_byte=0;
                  endcase
                5:case(a)
                    0:control_byte=~image_crc[7:0];1:control_byte=~image_crc[15:8];
                    2:control_byte=~image_crc[23:16];3:control_byte=~image_crc[31:24];
                    default:control_byte=0;
                  endcase
                11:control_byte=failure_body[a*8+:8];
                19:case(a)
                    0:control_byte=job_number[7:0];
                    1:control_byte=job_number[15:8];
                    2:control_byte=job_number[23:16];
                    3:control_byte=job_number[31:24];
                    default:control_byte=0;
                  endcase
                20:case(a)
                    0:control_byte=8'h02;
                    1:control_byte=8'h00;
                    2:control_byte=8'h00;
                    3:control_byte=8'h00;
                    default:control_byte=0;
                  endcase
                default:control_byte=0;
            endcase
        end
    endfunction
    // This single comparator is sampled at each 16-byte slot boundary. The
    // original four-box unroll replicated these wide compares in the already
    // crowded main FPGA. Header and zero-padding checks are accumulated by
    // the RX copier below; CNN need not set the NMS flag.
    function multibox_slot_valid;
        input [127:0] p;
        begin
            multibox_slot_valid=(p[15:0]<p[47:32] && p[31:16]<p[63:48] &&
                p[47:32]<=16'd1280 && p[63:48]<=16'd720 &&
                p[79:64]>=16'd1 && p[79:64]<=16'd9 && p[87:80]<=8'd100 &&
                p[95:88]==0 && p[127:96]!=0 && p[127:96]<=32'd921600);
        end
    endfunction
    wire load_control=(state==LOAD_CONTROL);
    assign packet_ready=(state==LOAD_IMAGE)&&!tx_busy;
    hxa_packet_tx tx(
        .clk(clk),.rst_n(codec_rst_n),
        .load_we(load_control || (packet_valid&&packet_ready)),.load_addr(load_at),
        .load_data(load_control?control_byte(tx_type,load_at,purpose,tx_job_id,frame_crc,cancel_body):packet_data),
        .start(tx_start),.msg_type(tx_type),.flags(16'd0),.session_id(session),
        .frame_id(tx_frame_id),.packet_index(tx_type==4?{5'd0,packet_index}:16'd0),
        .packet_count((tx_type==3||tx_type==4||tx_type==5)?16'd1280:16'd0),
        .payload_len(tx_payload_len),.busy(tx_busy),.done(tx_done),.error(tx_error),
        .stack_reset(stack_reset),.udp_req(udp_req),.udp_valid(udp_valid),
        .udp_data(udp_data),.udp_len(udp_len),.udp_busy(udp_busy));
    hxa_packet_rx #(.MAX_PAYLOAD(224)) rx(
        .clk(clk),.rst_n(codec_rst_n),.udp_valid(rx_valid),.udp_data(rx_data),.udp_len(rx_len),
        .udp_error(rx_error),.packet_valid(r_packet_valid),.packet_take(r_take),
        .msg_type(r_type),.flags(r_flags),.session_id(r_session),.frame_id(r_frame),
        .packet_index(r_index),.packet_count(r_count),.payload_len(r_length),
        .payload_addr(r_addr),.payload_data(r_body_data),.packet_error(r_error),.dropped_packets(dropped));
    always @(posedge clk)begin
        if(r_state==2 && saved_type==6 && r_at<160)nack_mem[r_at]<=r_body_data;
        if(r_state==2 && saved_type==18)r_box_shift<={r_body_data,r_box_shift[119:8]};
        // Every accepted control/result length overwrites all fields read by
        // its decoder. Unused bytes never participate in an accepted result,
        // so this byte bank needs neither reset nor a per-packet bulk clear.
        if(r_state==2 && r_at<80)r_body[r_at*8+:8]<=r_body_data;
        nack_byte<=nack_mem[packet_index[10:3]];
    end
    // Copy only small control/result bodies. NACK has a separate small RAM.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin r_state<=0;r_take<=0;r_addr<=0;r_at<=0;r_event<=0;saved_type<=0;saved_frame<=0;saved_len<=0;saved_index<=0;r_multibox_valid<=0;end
        else begin
            r_take<=0;r_event<=0;
            if(!codec_rst_n)r_state<=0;
            else case(r_state)
                0:if(r_packet_valid&&!r_take)begin
                    if(r_session!=session || r_flags!=0 || r_length>224 ||
                       ((r_type==8||r_type==18) && (r_index!=0||r_count!=0)) ||
                       (r_type==6 && (state!=WAIT_ACK||r_frame!=frame_id||r_length!=160||
                        r_count!=1280||r_index>3||duplicate_nack_round)))r_take<=1;
                    else begin
                        saved_type<=r_type;saved_frame<=r_frame;saved_len<=r_length;saved_index<=r_index;
                        r_multibox_valid<=(r_type==18 && r_length==80);
                        r_at<=0;r_addr<=0;
                        if(r_length==0)begin r_take<=1;r_state<=3;end else r_state<=1;
                    end
                end
                1:begin r_addr<=1;r_state<=2;end
                2:begin
                    if(saved_type==18)begin
                        if(r_at==15)begin
                            // The current byte is header reserved byte 15;
                            // flags/count/byte14 have already been copied.
                            if((r_body[103:96]&8'h38)!=0 || r_body[111:104]>4 ||
                               (r_body[103] && r_body[111:104]!=0) ||
                               (!r_body[103] && !r_body[96]) ||
                               r_body[119:112]!=0 || r_body_data!=0)
                                r_multibox_valid<=0;
                        end else if(r_at>=31 && r_at<=79 && r_at[3:0]==15)begin
                            // Slot numbers 1..4 correspond to byte31,47,63,79.
                            // Count selects active slots; the rest are zero.
                            if({5'd0,r_at[6:4]}<=r_body[111:104])begin
                                if(!multibox_slot_valid(r_box))r_multibox_valid<=0;
                            end else if(r_box!=0)r_multibox_valid<=0;
                        end
                    end
                    if({8'd0,r_at}==saved_len-1'b1)begin r_take<=1;r_state<=3;end
                    else begin r_at<=r_at+1'b1;r_addr<=r_addr+1'b1;end
                end
                3:begin r_event<=1;r_state<=0;end
            endcase
        end
    end
    task send_control;
        input [7:0] typ;input [15:0] len;input [4:0] after_state;
        begin tx_type<=typ;tx_payload_len<=len;load_at<=0;return_state<=after_state;tx_frame_id<=frame_id;
            tx_job_id<=job_id;
            state<=(len==0)?TX_START:LOAD_CONTROL;end
    endtask
    task invalidate_multibox;
        begin
            if(multi_valid || multi_count!=0)multi_toggle<=~multi_toggle;
            multi_valid<=0;multi_count<=0;multi_payload_visible<=0;
            error_hold_active<=0;error_hold_ms<=0;
        end
    endtask
    task invalidate_singlebox;
        begin
            if(result_valid || ((PCB_CONTINUOUS||PCB_KEY_ONESHOT) && purpose==1 &&
               (committed_payload[98] || committed_payload[97])))
                result_toggle<=~result_toggle;
            result_valid<=0;
            // The selector decodes CHECKED/GOOD independently of box valid.
            // Clear this metadata too, including stale no-target results.
            if((PCB_CONTINUOUS||PCB_KEY_ONESHOT) && purpose==1)committed_payload[255:0]<=0;
            error_hold_active<=0;error_hold_ms<=0;
        end
    endtask
    task cancel_with_reason;
        input [7:0] reason;
        begin
            state<=CANCEL;
            ordinary_gap_pending<=0;
            if(PCB_KEY_ONESHOT)pcb_trigger_pending<=0;
            // Preserve an established session on a frame fault. Before the
            // first READY, however, IDLE has no peer: restart discovery as
            // well as on lease expiry so startup faults cannot strand it.
            cancel_reconnect<=(reason==8'd4)||!online;
            if(purpose==2&&job_active)begin
                copy_state<=4;copy_toggle<=~copy_toggle;copy_requires_cycle<=1;
            end
            if(cancel_reason==0) begin
                cancel_reason<=reason;cancel_state<=state;
                cancel_snapshot_diag<=snapshot_diag;
            end
        end
    endtask
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=OFF;return_state<=OFF;tx_type<=0;tx_payload_len<=0;load_at<=0;tx_start<=0;
            cancel_reason<=0;cancel_state<=0;cancel_snapshot_diag<=0;
            session<=64'h4858413100000001;cycles<=0;frame_id<=0;job_id<=0;report_id<=0;report_pending<=0;frame_crc<=32'hffffffff;
            ms_div<=0;lease_ms<=0;control_ms<=0;transfer_ms<=0;rate_ms<=200;
            heartbeat_ms<=0;result_ms<=0;enable_d<=0;mode_d<=0;maze_mode_d<=0;text_mode_d<=0;purpose<=0;resend<=0;
            error_hold_ms<=0;error_hold_active<=0;cancel_reconnect<=0;
            ready_seen<=0;ack_seen<=0;nack_seen<=0;result_seen<=0;retry<=0;pending_maze_result<=0;completed_result_maze<=0;
            pending_multibox<=0;completed_result_multibox<=0;pending_multi_count<=0;
            capture_req<=0;capture_cancel<=0;capture_release<=0;background_capture<=0;
            packet_req<=0;packet_index<=0;online<=0;result_valid<=0;result_toggle<=0;
            multi_valid<=0;multi_toggle<=0;multi_count<=0;multi_payload_visible<=0;multi_job<=0;
            committed_payload<=0;result_frame<=0;pending_payload<=0;pending_frame<=0;
            sent_frames<=0;failed_frames<=0;job_finished<=0;job_failed<=0;peer_caps<=0;
            job_active<=0;pcb_trigger_pending<=0;maze_trigger_pending<=0;text_trigger_pending<=0;result_ack_pending<=0;
            pcb_mode_active_d<=0;bg_refresh_wait<=0;bg_low_seen<=0;
            teach_pending<=0;teach_active<=0;
            completed_result_valid<=0;completed_result_frame<=0;completed_result_job<=0;tx_frame_id<=0;tx_job_id<=0;
            station_header<=0;station_commit<=0;station_seen<=0;station_pending<=0;
            station_wait<=0;station_busy_seen<=0;station_version<=0;
            packet_gap_count<=0;
            ordinary_gap_pending<=0;
            nack_rounds_seen<=0;
            copy_state<=0;copy_toggle<=0;copy_elapsed_ms<=0;copy_prepare_ms<=0;
            copy_drawing<=0;copy_requires_cycle<=0;
        end else begin
            cycles<=cycles+1'b1;enable_d<=enable;mode_d<=pcb_mode;maze_mode_d<=maze_active;text_mode_d<=text_run;
            tx_start<=0;capture_req<=0;capture_cancel<=0;capture_release<=0;
            background_capture<=0;packet_req<=0;
            // Continue the preceding DATA gap while loading, or while a
            // cached result ACK uses the empty RAM before loading starts.
            // Saturate: a delayed DDR response cannot wrap the gap timer.
            if(ordinary_gap_pending && PACKET_GAP_CYCLES!=0 &&
               packet_gap_count<PACKET_GAP_CYCLES-1)
                packet_gap_count<=packet_gap_count+1'b1;
            station_commit<=0;
            // KEY1 can be pressed while a frame is in flight. Retain one
            // request until the ordinary-CNN link returns to IDLE; a mode
            // change cancels it so PCB/text never inherit a stale report.
            if(!enable||pcb_run) report_pending<=0;
            else if(report_request) report_pending<=1;
            // Text mode is explicitly one-shot.  Latch a KEY1 pulse whenever
            // no frame is active; this also tolerates a press during HELLO or
            // a control-packet turnaround while a capture is not yet owned.
            // A second press is a cancellation; failed/cancelled copies require
            // an explicit mode cycle before a new page can be admitted.
            if(!enable||!text_run) text_trigger_pending<=0;
            else if(text_press && peer_caps[7] && !job_active && !snapshot_busy && !copy_requires_cycle &&
                state!=CANCEL)
                text_trigger_pending<=1;
            if(!text_run)begin
                copy_requires_cycle<=0;
                if(copy_state!=0)begin copy_state<=0;copy_toggle<=~copy_toggle;end
            end
            pcb_mode_active_d<=enable&&pcb_run;
            if(!enable||!pcb_run)begin
                bg_refresh_wait<=0;bg_low_seen<=0;
            end else if(!PCB_CONTINUOUS && !PCB_KEY_ONESHOT && !pcb_mode_active_d)begin
                background_capture<=1;bg_refresh_wait<=1;bg_low_seen<=0;
            end else if(!PCB_CONTINUOUS && !PCB_KEY_ONESHOT && bg_refresh_wait)begin
                if(!background_valid)bg_low_seen<=1;
                if(bg_low_seen&&background_valid)bg_refresh_wait<=0;
            end
            if(accept_teach)teach_pending<=1;
            if(station_pending&&station_ready)begin
                station_commit<=1;station_pending<=0;station_wait<=1;station_busy_seen<=0;
            end
            if(station_wait)begin
                if(!station_ready)station_busy_seen<=1;
                if(station_busy_seen&&station_ready)station_wait<=0;
            end
            if(maze_active&&maze_press&&(state==IDLE ||
                ((state==LOAD_CONTROL||state==TX_START||state==TX_WAIT)&&return_state==IDLE)))
                maze_trigger_pending<=1;
            if(!maze_active)maze_trigger_pending<=0;
            if(!PCB_CONTINUOUS && !PCB_KEY_ONESHOT && pcb_run&&pcb_background_ready&&pcb_trigger&&!teach_pending&&!accept_teach&&(state==IDLE ||
                ((state==LOAD_CONTROL||state==TX_START||state==TX_WAIT)&&return_state==IDLE)))
                pcb_trigger_pending<=1;
            if(PCB_KEY_ONESHOT)begin
                // A heartbeat or cached result ACK is link maintenance, not
                // a vision job. Retain one press only across that idle send.
                // Real busy/offline/fault conditions discard it, including
                // a mode/lease change on the very same edge as the press.
                if(!enable||!phy_ready||!pcb_run||!online||
                   lease_ms>=LINK_LEASE_TIMEOUT_MS||state==CANCEL||
                   pcb_mode!=mode_d||maze_active!=maze_mode_d||text_run!=text_mode_d||
                   job_active||snapshot_busy||station_pending||station_wait||
                   snapshot_error||packet_error||tx_error)
                    pcb_trigger_pending<=0;
                else if(pcb_trigger&&pcb_key_idle_window)pcb_trigger_pending<=1;
            end else if(!PCB_CONTINUOUS && pcb_run&&!pcb_background_ready)pcb_trigger_pending<=0;
            if(tick_ms)begin
                ms_div<=0;
                if(lease_ms<LINK_LEASE_TIMEOUT_MS)lease_ms<=lease_ms+1'b1;
                if(control_ms<3000)control_ms<=control_ms+1'b1;
                if(transfer_ms<3000)transfer_ms<=transfer_ms+1'b1;
                if(rate_ms<200)rate_ms<=rate_ms+1'b1;
                if(heartbeat_ms<250)heartbeat_ms<=heartbeat_ms+1'b1;
                if(result_ms<1000)result_ms<=result_ms+1'b1;
                if(job_active&&purpose==2)begin
                    if(copy_elapsed_ms<1800000)copy_elapsed_ms<=copy_elapsed_ms+1'b1;
                    if(!copy_drawing&&copy_prepare_ms<30000)copy_prepare_ms<=copy_prepare_ms+1'b1;
                end
                if(error_hold_active&&error_hold_ms<RESULT_ERROR_HOLD_MS)
                    error_hold_ms<=error_hold_ms+1'b1;
            end else ms_div<=ms_div+1'b1;
            // Ordinary detection expires after a second without a refresh.
            // A PCB result remains visible throughout writing and while the
            // same workpiece is present, including heartbeat TX substates.
            // A recoverable frame fault owns the result for a short grace
            // period.  Normal one-second expiry is suppressed while that
            // grace period is active.
            if((result_valid || (PCB_CONTINUOUS && purpose==1 &&
                (committed_payload[98] || committed_payload[97])))&&
                !error_hold_active&&!frame_fault_now&&
                ((purpose==0&&result_ms>=1000)||
                (purpose==1&&((PCB_CONTINUOUS!=0&&result_ms>=1000)||
                              (PCB_CONTINUOUS==0&&PCB_KEY_ONESHOT==0&&!pcb_present)))))begin
                invalidate_singlebox();
            end
            if(multi_valid&&!error_hold_active&&!frame_fault_now&&result_ms>=1000)
                invalidate_multibox();
            // Keep the previous overlay through a malformed packet or a
            // failed frame.  It is cleared after RESULT_ERROR_HOLD_MS unless
            // a valid result, count=0, mode change, or disable arrives first.
            if(error_hold_active&&error_hold_ms>=RESULT_ERROR_HOLD_MS)begin
                if(result_valid)invalidate_singlebox();
                if(multi_valid)invalidate_multibox();
                error_hold_active<=0;error_hold_ms<=0;
            end
            if(r_error)begin
                if(result_valid||multi_valid)begin
                    error_hold_active<=1;error_hold_ms<=0;
                end
            end
            if(r_event)begin
                lease_ms<=0;
                if((saved_type==1||saved_type==2) && (saved_len==8||saved_len==40) &&
                    r_body[7:0]==2 && r_body[31:16]==0)begin
                    online<=1;peer_caps<=r_body[15:8];
                    if(saved_len==40&&(!station_seen||station_version!=r_body[63:32])&&
                        r_body[95:64]==32'h314c5054&&r_body[127:96]==r_body[63:32])begin
                        station_header<=r_body[319:64];station_version<=r_body[63:32];
                        station_seen<=1;station_pending<=1;
                    end
                end
                if(completed_result_valid&&saved_frame==completed_result_frame&&
                   ((!completed_result_maze&&!completed_result_multibox&&saved_type==8&&saved_len==64&&r_body[31:0]==completed_result_job)||
                    (completed_result_maze&&saved_type==16&&saved_len==224&&r_body[31:0]==32'h31525a4d)||
                    // A lost type19 ACK causes the secondary to retransmit
                    // type18.  A duplicate type18 is acknowledged again;
                    // type19 is our outgoing ACK and must never be expected
                    // as an incoming message here.
                    (completed_result_multibox&&saved_type==18&&saved_len==80&&
                     r_body[31:0]==completed_result_job&&r_multibox_valid)))
                    result_ack_pending<=1;
                if(saved_frame==frame_id)begin
                    if(saved_type==2 && saved_len==0)ready_seen<=1;
                    if(saved_type==7 && saved_len==4 && r_body[31:0]==~frame_crc)ack_seen<=1;
                    if(saved_type==6 && saved_len==160)begin
                        nack_seen<=1;
                        case(saved_index)
                            1:nack_rounds_seen[0]<=1;
                            2:nack_rounds_seen[1]<=1;
                            3:nack_rounds_seen[2]<=1;
                            default:; // index=0 remains a fresh legacy request
                        endcase
                    end
                    // Type8 is the legacy single-box result for ordinary CNN
                    // and PCB jobs only.  A text-trace purpose=2 frame is
                    // completed exclusively by Type15; accepting a stray
                    // Type8 here could move the link into JOB_WAIT before
                    // the plotter completion arrives.
                    if(saved_type==8 && saved_len==64 && job_active &&
                       (purpose==2'd0 || purpose==2'd1) &&
                       r_body[31:0]==job_id && r_body[111:104]<=3 && r_body[119:112]<=3 &&
                       r_body[127:120]<=100 && r_body[247:240]<=4 && r_body[255:248]==0)begin
                        pending_payload<=r_body;pending_frame<=saved_frame;result_seen<=1;pending_maze_result<=0;pending_multibox<=0;
                    end
                    // type18: fixed 80-byte multi-box result.  The four box
                    // slots are copied verbatim and committed at WAIT_RESULT,
                    // so the pixel clock never observes a partial update.
                    if(saved_type==18 && saved_len==80 && job_active && purpose==0 &&
                        HELLO_CAPABILITIES[6] && peer_caps[6] &&
                        r_body[31:0]==job_id &&
                        // Accept a valid result or an explicit no-target
                        // result (flags bit7 with zero boxes). The latter
                        // must be committed so the HDMI side clears boxes
                        // from the previous frame and still sends type19.
                        r_multibox_valid)begin
                        pending_multi_count<=r_body[106:104];
                        pending_payload<=r_body;
                        pending_frame<=saved_frame;result_seen<=1;pending_multibox<=1;pending_maze_result<=0;
                    end
                    else if(saved_type==18 && job_active && purpose==0) begin
                        // A malformed or stale Type18 is a frame-level fault.
                        // Keep the last committed overlay for the short error
                        // grace period; only a CRC-valid Type18 count=0 is an
                        // explicit request to clear it immediately.
                        if(result_valid||multi_valid)begin
                            error_hold_active<=1;error_hold_ms<=0;
                        end
                    end
                    // MZR1 is a separate result type. It must never enter the
                    // color/shape overlay decoder. The packet CRC protects all
                    // 224 bytes; only the fixed header is retained on main.
                    if(saved_type==16 && saved_len==224 && job_active && purpose==3 &&
                       r_body[31:0]==32'h31525a4d && r_body[63:32]==job_id &&
                       r_body[103:96]<=2 && r_body[143:128]<=255 &&
                       r_body[175:160]<=r_body[207:192] && r_body[191:176]<=r_body[223:208] &&
                       r_body[207:192]<=1280 && r_body[223:208]<=720)begin
                        pending_payload<=r_body;pending_frame<=saved_frame;result_seen<=1;pending_maze_result<=1;
                    end
                    if(saved_type==15 && saved_len==12 && job_active && r_body[31:0]==job_id &&
                        r_body[63:48]==0 && r_body[39:32]>=1 && r_body[39:32]<=6)begin
                        if(purpose==2)begin
                            if(r_body[39:32]==2||r_body[39:32]==3)begin
                                copy_drawing<=1;
                                if(copy_state!=2)begin copy_state<=2;copy_toggle<=~copy_toggle;end
                            end else if(r_body[39:32]>=4)begin
                                copy_state<=(r_body[39:32]==4)?3'd3:3'd4;
                                copy_toggle<=~copy_toggle;
                                if(r_body[39:32]!=4)copy_requires_cycle<=1;
                            end
                        end
                        if(r_body[39:32]>=4)begin
                            job_finished<=1;job_failed<=r_body[39:32]!=4;
                        end
                    end
                end
            end
            if(!enable||!phy_ready)begin
                ordinary_gap_pending<=0;
                state<=OFF;online<=0;capture_cancel<=enable_d;invalidate_singlebox();invalidate_multibox();
                cancel_reason<=0;cancel_state<=0;cancel_snapshot_diag<=0;cancel_reconnect<=0;
                job_active<=0;pcb_trigger_pending<=0;completed_result_valid<=0;result_ack_pending<=0;
                text_trigger_pending<=0;
                teach_pending<=0;teach_active<=0;
                ready_seen<=0;ack_seen<=0;nack_seen<=0;result_seen<=0;
                station_seen<=0;station_pending<=0;station_wait<=0;station_busy_seen<=0;
                nack_rounds_seen<=0;
            end else if(enable!=enable_d || state==OFF)begin
                ordinary_gap_pending<=0;
                cancel_reason<=0;cancel_state<=0;cancel_snapshot_diag<=0;cancel_reconnect<=0;
                session<={32'h48583101,cycles};state<=DISCOVER;control_ms<=100;heartbeat_ms<=0;
                online<=0;invalidate_singlebox();invalidate_multibox();capture_cancel<=1;
                pcb_trigger_pending<=0;completed_result_valid<=0;result_ack_pending<=0;text_trigger_pending<=0;
                teach_pending<=0;teach_active<=0;
                station_seen<=0;station_pending<=0;station_wait<=0;station_busy_seen<=0;
                nack_rounds_seen<=0;
            end else if(state!=CANCEL&&text_run&&purpose==2&&job_active&&text_press)begin
                text_trigger_pending<=0;cancel_with_reason(8'd14);capture_cancel<=1;
            end else if(state!=CANCEL&&purpose==2&&job_active&&
                       (copy_elapsed_ms>=1800000||(!copy_drawing&&copy_prepare_ms>=30000)))begin
                cancel_with_reason(8'd15);capture_cancel<=1;
            end else if(state!=CANCEL &&
                        (pcb_mode!=mode_d || maze_active!=maze_mode_d || text_run!=text_mode_d ||
                         tx_error || packet_error || snapshot_error))begin
                // A mode transition or image/packet fault cancels only the
                // active job.  Keep the established session and CONNECTED
                // state so the next frame can start without rediscovery.
                cancel_with_reason(snapshot_error?8'd1:packet_error?8'd2:tx_error?8'd3:8'd5);
                capture_cancel<=1;
                if(result_valid||multi_valid)begin
                    error_hold_active<=1;error_hold_ms<=0;
                end
                if(pcb_mode!=mode_d || maze_active!=maze_mode_d || text_run!=text_mode_d)begin
                    invalidate_singlebox();invalidate_multibox();
                end
            end else if(online&&lease_ms>=LINK_LEASE_TIMEOUT_MS&&!r_event)begin
                // Only a real lease expiry causes reconnection and clears
                // the session-visible state.
                cancel_with_reason(8'd4);
                online<=0;invalidate_singlebox();invalidate_multibox();capture_cancel<=1;
            end else if(r_event&&saved_type==11&&saved_frame==frame_id)begin
                // A peer CANCEL is a per-frame cancellation.  Keep the
                // session alive and let the next IDLE transaction recover.
                cancel_with_reason(8'd13);capture_cancel<=1;
                if(result_valid||multi_valid)begin
                    error_hold_active<=1;error_hold_ms<=0;
                end
            end else if(result_ack_pending&&!tx_busy&&
                (state==CAPTURE||state==WAIT_READY||state==WAIT_ACK||
                 state==WAIT_RESULT||state==NEXT_PACKET||state==PACKET_GAP))begin
                // The prior result ACK may have been lost after the main
                // already began the next capture. Service the cached ACK
                // in these safe idle substates, rather than waiting for
                // IDLE while the secondary refuses a new FRAME_BEGIN.
                // LOAD_IMAGE and PREFETCH_READY own the single TX RAM:
                // pending ACKs must wait until that DATA has completed.
                result_ack_pending<=0;
                if(completed_result_multibox)send_control(19,4,state);
                else send_control(completed_result_maze?17:9,0,state);
                tx_frame_id<=completed_result_frame;
                tx_job_id<=completed_result_job;
            end else case(state)
                DISCOVER:begin
                    if(online)begin state<=(pcb_run&&!pcb_fast_run)?WAIT_CLEAR:IDLE;rate_ms<=200;end
                    else if(control_ms>=100&&!tx_busy)begin control_ms<=0;send_control(1,8,DISCOVER);end
                end
                IDLE:begin
                    if(!detect_enable)begin
                        invalidate_singlebox();pcb_trigger_pending<=0;
                        invalidate_multibox();
                    end
                    if(!online)begin
                        // Defensive recovery: no capture or heartbeat may
                        // replace the initial HELLO/READY handshake.
                        state<=DISCOVER;control_ms<=100;
                    end else if(result_ack_pending&&!tx_busy)begin
                        result_ack_pending<=0;
                        if(completed_result_multibox)send_control(19,4,IDLE);
                        else send_control(completed_result_maze?17:9,0,IDLE);
                        tx_frame_id<=completed_result_frame;
                        tx_job_id<=completed_result_job;
                    end else if((report_request||report_pending)&&!pcb_run&&!snapshot_busy&&!tx_busy&&!job_active&&online)begin
                        // KEY1 report command is independent of a new image
                        // capture. Use a monotonically increasing packet
                        // frame id so the secondary can key its JOB_STATUS
                        // without colliding with the last image frame.
                        report_id<=report_id+1'b1;report_pending<=0;
                        tx_type<=8'd20;tx_payload_len<=16'd4;load_at<=0;
                        tx_frame_id<=report_id+1'b1;return_state<=IDLE;state<=LOAD_CONTROL;
                    end else if(!station_pending&&!station_wait&&!snapshot_busy&&
                       ((text_run&&peer_caps[7]&&!copy_requires_cycle&&(text_trigger_pending||text_press))||
                        (teach_pending&&pcb_run&&peer_caps[4])||
                        (detect_enable&&!maze_active&&!accept_teach&&
                         (pcb_run ? (pcb_fast_run ? 1'b1 : rate_ms>=200) : rate_ms>=ORDINARY_MIN_INTERVAL_MS)&&
                         (!pcb_run||(pcb_key_run ?
                             ((pcb_trigger_pending||pcb_trigger)&&!job_active&&!tx_busy) :
                             (PCB_CONTINUOUS!=0 ? 1'b1 :
                             (pcb_background_ready&&(pcb_trigger_pending||pcb_trigger)))))) ||
                        (maze_active&&peer_caps[5]&&(maze_trigger_pending||maze_press))))begin
                        capture_req<=1;purpose<=capture_purpose;state<=CAPTURE;rate_ms<=0;transfer_ms<=0;
                        teach_active<=teach_pending&&pcb_run;teach_pending<=0;
                        job_active<=1;pcb_trigger_pending<=0;maze_trigger_pending<=0;text_trigger_pending<=0;
                        ready_seen<=0;ack_seen<=0;nack_seen<=0;result_seen<=0;pending_multibox<=0;job_finished<=0;job_failed<=0;retry<=0;
                        nack_rounds_seen<=0;
                        if(text_run)begin
                            copy_state<=1;copy_toggle<=~copy_toggle;
                            copy_elapsed_ms<=0;copy_prepare_ms<=0;copy_drawing<=0;
                        end
                        // Every capture receives a fresh job id, including
                        // ordinary purpose=0 CNN frames.  Keeping job ids
                        // constant made a delayed result from an older frame
                        // indistinguishable from the current job.
                        job_id<=job_id+1'b1;
                    end else if(heartbeat_ms>=250&&!tx_busy)begin heartbeat_ms<=0;send_control(10,0,IDLE);end
                end
                CAPTURE:begin
                    if(snapshot_ready)begin frame_id<=snapshot_frame_id;frame_crc<=32'hffffffff;
                        packet_index<=0;resend<=0;control_ms<=0;send_control(3,16,WAIT_READY);tx_frame_id<=snapshot_frame_id;end
                    else if(heartbeat_ms>=250&&!tx_busy)begin heartbeat_ms<=0;send_control(10,0,CAPTURE);end
                    else if(transfer_ms>=2000)cancel_with_reason(8'd6);
                end
                WAIT_READY:begin
                    if(ready_seen)begin ready_seen<=0;state<=NEXT_PACKET;end
                    else if(heartbeat_ms>=250&&!tx_busy)begin heartbeat_ms<=0;send_control(10,0,WAIT_READY);end
                    else if(control_ms>=100)begin
                        if(retry==3)cancel_with_reason(8'd7);
                        else begin retry<=retry+1'b1;control_ms<=0;send_control(3,16,WAIT_READY);end
                    end
                end
                NEXT_PACKET:if(!packet_busy&&!tx_busy)begin
                    packet_req<=1;load_at<=0;tx_type<=4;tx_payload_len<=1440;
                    tx_frame_id<=frame_id;
                    return_state<=resend?NACK_NEXT:NEXT_PACKET;state<=LOAD_IMAGE;
                end
                LOAD_IMAGE:begin
                    if(packet_valid&&packet_ready)begin
                        if(!resend)frame_crc<=crc_byte(frame_crc,packet_data);
                        if(packet_last)begin
                            if(load_at!=1439)cancel_with_reason(8'd8);
                            else state<=ordinary_gap_pending?PREFETCH_READY:TX_START;
                        end else if(load_at==1439)cancel_with_reason(8'd8);
                        else load_at<=load_at+1'b1;
                    end
                    if(transfer_ms>=2000)cancel_with_reason(8'd9);
                end
                LOAD_CONTROL:if(load_at==tx_payload_len-1'b1)state<=TX_START;else load_at<=load_at+1'b1;
                PREFETCH_READY:begin
                    if(PACKET_GAP_CYCLES==0||packet_gap_count>=PACKET_GAP_CYCLES-1)
                        state<=TX_START;
                    if(transfer_ms>=2000)cancel_with_reason(8'd9);
                end
                TX_START:if(!tx_busy)begin
                    tx_start<=1;state<=TX_WAIT;
                    if(tx_type==4)ordinary_gap_pending<=0;
                end
                TX_WAIT:if(tx_done)begin
                    if(tx_type==4)begin
                        packet_gap_count<=0;
                        if(ORDINARY_GAP_PREFETCH && purpose==0 && !resend && packet_index!=1279)begin
                            // DATA completion releases the RAM. Advance once
                            // and prepare the next payload while the gap runs.
                            ordinary_gap_pending<=1;
                            packet_index<=packet_index+1'b1;state<=NEXT_PACKET;
                        end else state<=PACKET_GAP;
                    end
                    else begin
                        if(tx_type==11)begin
                            // The cancel body is now on the wire; allow the
                            // next per-frame failure to carry fresh detail.
                            cancel_reason<=0;cancel_state<=0;
                            cancel_snapshot_diag<=0;cancel_reconnect<=0;
                        end
                        state<=return_state;
                    end
                end
                // The receive MAC has no backpressure.  Leave time for the
                // secondary to copy all 90 words through its DDR mailbox.
                // Default is 80 us after every DATA packet, including retry
                // and the final fragment before FRAME_END.
                PACKET_GAP:if(PACKET_GAP_CYCLES==0||packet_gap_count>=PACKET_GAP_CYCLES-1)begin
                    if(resend)state<=NACK_NEXT;
                    else if(packet_index==1279)begin control_ms<=0;retry<=0;send_control(5,4,WAIT_ACK);end
                    else begin packet_index<=packet_index+1'b1;state<=NEXT_PACKET;end
                end else packet_gap_count<=packet_gap_count+1'b1;
                WAIT_ACK:begin
                    if(ack_seen)begin
                        ack_seen<=0;capture_release<=(purpose!=2);sent_frames<=sent_frames+1'b1;
                        state<=(purpose==2)?JOB_WAIT:WAIT_RESULT;control_ms<=0;
                    end else if(nack_seen)begin
                        nack_seen<=0;
                        if(retry==3)cancel_with_reason(8'd10);
                        else begin retry<=retry+1'b1;resend<=1;packet_index<=0;state<=NACK_PRIME;end
                    end else if(heartbeat_ms>=250&&!tx_busy)begin heartbeat_ms<=0;send_control(10,0,WAIT_ACK);end
                    else if(control_ms>=100)begin
                        if(retry==3||transfer_ms>=2000)cancel_with_reason(8'd11);
                        else begin retry<=retry+1'b1;control_ms<=0;send_control(5,4,WAIT_ACK);end
                    end
                end
                NACK_PRIME:state<=NACK_CHECK;
                NACK_CHECK:if(nack_byte[packet_index[2:0]])state<=NEXT_PACKET;else state<=NACK_NEXT;
                NACK_NEXT:begin
                    if(packet_index==1279)begin control_ms<=0;send_control(5,4,WAIT_ACK);end
                    else begin packet_index<=packet_index+1'b1;state<=NACK_PRIME;end
                end
                WAIT_RESULT:begin
                    // Inference and PCB reporting are separate outcomes.
                    // Continuous detection commits Type8 even if a peer's
                    // optional reporting/plotter job reports Type15 failure.
                    // Text tracing has no CNN result packet.  The secondary
                    // reports completion/failure with Type15; consume it as
                    // the terminal event and return to IDLE so the next
                    // KEY1 press can capture another page.
                    if(purpose==2 && job_finished)begin
                        job_finished<=0;
                        if(job_failed)failed_frames<=failed_frames+1'b1;
                        job_active<=0;state<=IDLE;control_ms<=0;result_ms<=0;
                    end else if(job_finished&&job_failed&&!teach_active&&!continuous_pcb_job)begin
                        state<=WAIT_CLEAR;result_seen<=0;result_valid<=0;
                        if(result_valid)result_toggle<=~result_toggle;
                        if(job_active)begin failed_frames<=failed_frames+1'b1;job_active<=0;end
                    end else if(result_seen)begin
                        result_seen<=0;committed_payload<=pending_payload;result_frame<=pending_frame;
                        error_hold_active<=0;error_hold_ms<=0;
                        result_valid<=!pending_multibox&&!pending_maze_result&&!teach_active&&pending_result[96] &&
                            (((purpose!=1)||pcb_fast_run||pcb_present)) && pending_result[127:120]<=100 &&
                            pending_result[175:160]>pending_result[143:128] &&
                            pending_result[191:176]>pending_result[159:144] &&
                            pending_result[175:160]<=1280 && pending_result[191:176]<=720;
                        result_toggle<=~result_toggle;result_ms<=0;
                        if(pending_multibox&&pending_multi_count!=0)begin
                            multi_valid<=1;multi_toggle<=~multi_toggle;multi_count<=pending_multi_count;
                            multi_payload_visible<=1;multi_job<=job_id;
                        end else if(pending_multibox)begin
                            // A legal Type18 count=0 is an explicit empty
                            // result and must clear the previous overlay now.
                            invalidate_multibox();
                        end else invalidate_multibox();
                        completed_result_valid<=1;completed_result_frame<=pending_frame;completed_result_job<=job_id;
                        completed_result_maze<=pending_maze_result;completed_result_multibox<=pending_multibox;
                        if(!purpose||teach_active||continuous_pcb_job)job_active<=0;
                        if(teach_active)begin
                            pcb_trigger_pending<=0;
                            if(!pending_result[100]||pending_result[101])failed_frames<=failed_frames+1'b1;
                        end
                        if(pending_multibox)
                            send_control(19,4,teach_active?WAIT_CLEAR:
                                ((purpose!=0&&!continuous_pcb_job)?JOB_WAIT:IDLE));
                        else
                            send_control(pending_maze_result?17:9,0,teach_active?WAIT_CLEAR:
                                ((purpose!=0&&!continuous_pcb_job)?JOB_WAIT:IDLE));
                        pending_multibox<=0;
                    end else if(control_ms>=2000)cancel_with_reason(8'd12);
                    else if(heartbeat_ms>=250&&!tx_busy)begin heartbeat_ms<=0;send_control(10,0,WAIT_RESULT);end
                end
                JOB_WAIT:begin
                    if(job_finished)begin
                        state<=(purpose==2)?IDLE:WAIT_CLEAR;job_active<=0;
                        if(purpose==2)begin capture_release<=1;job_finished<=0;end
                        if(job_failed)begin
                            result_valid<=0;
                            if(result_valid)result_toggle<=~result_toggle;
                            if(job_active)failed_frames<=failed_frames+1'b1;
                        end
                    end
                    else if(result_ack_pending&&!tx_busy)begin
                        result_ack_pending<=0;
                        if(completed_result_multibox)send_control(19,4,JOB_WAIT);
                        else send_control(completed_result_maze?17:9,0,JOB_WAIT);
                        tx_frame_id<=completed_result_frame;
                        tx_job_id<=completed_result_job;
                    end
                    else if(heartbeat_ms>=250&&!tx_busy)begin heartbeat_ms<=0;send_control(10,0,JOB_WAIT);end
                end
                WAIT_CLEAR:begin
                    if(pcb_fast_run)state<=IDLE;
                    else if(!pcb_run||teach_pending||(!pcb_present&&pcb_background_ready))state<=IDLE;
                    else if(result_ack_pending&&!tx_busy)begin
                        result_ack_pending<=0;
                        if(completed_result_multibox)send_control(19,4,WAIT_CLEAR);
                        else send_control(completed_result_maze?17:9,0,WAIT_CLEAR);
                        tx_frame_id<=completed_result_frame;
                        tx_job_id<=completed_result_job;
                    end
                    else if(heartbeat_ms>=250&&!tx_busy)begin heartbeat_ms<=0;send_control(10,0,WAIT_CLEAR);end
                end
                CANCEL:begin
                    capture_cancel<=1;result_seen<=0;pcb_trigger_pending<=0;
                    // Per-frame cancellation preserves the previous result
                    // during its short hold.  Lease expiry has already
                    // invalidated it and requests a fresh discovery.
                    if(cancel_reconnect)begin
                        online<=0;invalidate_singlebox();invalidate_multibox();
                    end
                    teach_pending<=0;
                    if(job_active)begin failed_frames<=failed_frames+1'b1;job_active<=0;end
                    if(!tx_busy)begin
                        control_ms<=0;
                        send_control(11,28,cancel_reconnect?OFF:IDLE);
                    end
                end
                default:state<=OFF;
            endcase
        end
    end
endmodule
