// Reliable one-frame HXA1 receiver. No incomplete image reaches inference.
// DDR byte addresses are 16-byte aligned and YUYV bytes occupy low bits first.
module hxa_secondary_link #(
    parameter integer CLK_HZ=125000000,
    parameter [7:0] CAPABILITIES=8'h01,
    parameter integer FRAME_CRC_BYTES_PER_CYCLE=1
)(
    input wire clk,rst_n,enable,phy_ready,board_mode,
    output wire udp_req,udp_valid,output wire [7:0] udp_data,
    output wire [15:0] udp_len,input wire udp_busy,
    input wire rx_valid,input wire [7:0] rx_data,input wire [15:0] rx_len,
    input wire rx_error,output wire stack_reset,
    output wire wr_valid,output wire [20:0] wr_byte_addr,output wire [127:0] wr_data,
    input wire wr_ready,wr_idle,
    output wire rd_req,output wire [20:0] rd_byte_addr,
    input wire rd_ready,rd_valid,input wire [127:0] rd_data,
    output reg vision_start,vision_cancel,vision_job_cancel,
    output reg [31:0] vision_frame_id,vision_job_id,output reg [1:0] vision_purpose,
    output reg [15:0] vision_paper_width_px,output wire vision_teach_good,
    // Type 20 host-controlled G-code request. Payload is little-endian u32:
    // command 1 selects the fixed safe report, command 2 asks the secondary
    // to report its most recent ordinary-CNN result. The latter is deliberately
    // kept on the existing control type so old peers continue to ignore it.
    output reg grbl_test_start,output reg [31:0] grbl_test_job_id,
    output reg grbl_current_start,output reg [31:0] grbl_current_job_id,
    input wire vision_busy,vision_done,input wire [511:0] vision_result,
    // Optional multi-box producer.  Set vision_result_type=8 for legacy
    // single-box results or 18 for the fixed 80-byte multi-object result.
    input wire [7:0] vision_result_type,
    input wire [639:0] vision_result_multibox,
    input wire [1791:0] vision_maze_result,
    input wire v_rd_req,input wire [20:0] v_rd_byte_addr,
    output wire v_rd_ready,v_rd_valid,output wire [127:0] v_rd_data,
    output wire cfg_we,output wire [14:0] cfg_addr,output wire [7:0] cfg_data,
    output wire cfg_commit,output wire [31:0] cfg_version,input wire cfg_ready,
    output wire cfg_begin,output wire cfg_abort,output wire [14:0] cfg_total_bytes,
    output wire [31:0] cfg_pending_version,cfg_expected_crc32,
    output wire [2:0] cfg_good_count,cfg_bad_count,
    input wire cfg_apply_ack,cfg_apply_error,
    input wire [255:0] station_header,input wire station_valid,
    input wire [31:0] station_config_version,
    input wire job_status_valid,input wire [95:0] job_status_data,
    output wire job_status_ready,input wire job_busy,
    output reg [63:0] session_id,output reg online,
    output reg [31:0] good_frames,bad_frames,
    output reg copy_rearm
);
    localparam IDLE=0,BODY_PRIME=1,BODY_READ=2,DISPATCH=3,CLEAR_MAP=4,
      MAP_PRIME=5,MAP_CHECK=6,COPY_PRIME=7,COPY_BYTE=8,COPY_DELAY=9,
      WRITE_WORD=10,WRITE_DRAIN=11,MARK_PACKET=12,
      CRC_INIT=13,CRC_REQUEST=14,CRC_WAIT=15,CRC_BYTE=16,
      TX_LOAD=17,TX_GAP=18,TX_START=19,TX_WAIT=20;
    localparam [7:0] TYPE_GCODE_TEST=8'd20;
    localparam [31:0] GCODE_TEST_COMMAND_ID=32'd1;
    localparam [31:0] GCODE_CURRENT_COMMAND_ID=32'd2;
    reg [5:0] state,after_tx;
    reg [7:0] tx_type;reg [15:0] tx_flags,tx_length,tx_index,tx_count;
    reg [31:0] tx_frame,tx_ack_crc;
    reg tx_start;
    reg [10:0] tx_at;
    wire tx_busy,tx_done,tx_error;
    wire link_ok=enable&&phy_ready;
    // Release the packet codecs from a registered link state.  Driving their
    // asynchronous reset directly from rst_n created a high-fanout reset-to-
    // state path through tx_error/stack_reset in the 125 MHz timing graph.
    // One clock of delayed codec reset assertion/deassertion is harmless here:
    // the link FSM already gates traffic with link_ok and cancels on PHY loss.
    reg codec_rst_n_q;
    wire codec_rst_n=codec_rst_n_q;
    always @(posedge clk or negedge rst_n) begin
      if(!rst_n) codec_rst_n_q<=1'b0;
      else codec_rst_n_q<=link_ok;
    end
    wire packet_valid,packet_error;
    reg packet_take;
    wire ctrl_valid,ctrl_event;
    reg ctrl_take,saved_ctrl;
    wire [7:0] ctrl_type;
    wire [63:0] ctrl_session,ctrl_body,ctrl_event_session;
    wire [31:0] ctrl_frame;
    wire [15:0] ctrl_payload_len;
    reg control_cancel_pending,hb_reply_pending;
    reg [31:0] hb_reply_frame;
    reg [63:0] hb_reply_session;
    wire tx_active_state=(state==TX_LOAD||state==TX_GAP||state==TX_START||state==TX_WAIT);
    wire ctrl_heartbeat_take=ctrl_valid&&!ctrl_take&&ctrl_type==8'd10&&
                             online&&ctrl_session==session_id;
    wire ctrl_cancel_take=ctrl_valid&&!ctrl_take&&ctrl_type==8'd11&&
                          online&&ctrl_session==session_id;
    // Type11 without a task reason cancels only the current image transaction.
    // An accepted local printer task survives a network drop and ordinary
    // frame cancel; only the reserved task-id form can stop it explicitly.
    wire ctrl_explicit_job_cancel_take=ctrl_cancel_take&&ctrl_payload_len==28&&
         ctrl_body[31:0]==32'h31445848&&ctrl_body[39:32]==8'd1&&ctrl_body[47:40]==8'h80;
    wire ctrl_job_cancel_take=ctrl_cancel_take&&
        (ctrl_explicit_job_cancel_take || (ctrl_payload_len==0&&!job_busy));
    wire ctrl_hello_preempt=ctrl_valid&&!ctrl_take&&ctrl_type==8'd1&&
                            (!online||ctrl_session!=session_id)&&!tx_active_state;
    wire ctrl_drop=(ctrl_valid&&!ctrl_take)&&
                   ((ctrl_type==8'd10&&(!online||ctrl_session!=session_id))||
                    (ctrl_type==8'd11&&(!online||ctrl_session!=session_id))||
                    (ctrl_type!=8'd1&&ctrl_type!=8'd10&&ctrl_type!=8'd11));
    wire [7:0] packet_type,payload_data;
    wire [15:0] packet_flags,packet_index,packet_count,payload_length;
    wire [63:0] packet_session;
    wire [31:0] packet_frame,dropped;
    reg [10:0] payload_addr;
    reg [7:0] saved_type;
    reg [15:0] saved_flags,saved_index,saved_count,saved_length;
    reg [63:0] saved_session;
    reg [31:0] saved_frame;
    reg [6:0] body_at;
    reg [511:0] body;
    reg [31:0] ms_div;
    reg [15:0] lease_ms,transfer_ms,result_ms;
    wire tick_ms=ms_div==CLK_HZ/1000-1;
    reg frame_active,end_seen,vision_active,result_pending,result_acked;
    // One response cache covers the 64-byte ordinary result and 224-byte
    // maze result. The producer holds its result until start/cancel. Admission
    // below blocks the next job/configuration until this byte copy completes.
    // Arrays and their synchronous read register have no asynchronous reset,
    // allowing a single BRAM rather than parallel result FFs and read muxes.
    (* ram_style="bram" *) reg [7:0] result_ram [0:639] /* synthesis syn_ramstyle="block_ram" */;
    reg result_copy_pending;
    reg [10:0] result_copy_at;
    reg [7:0] result_ram_q;
    reg result_is_maze,result_is_multibox;
    reg [1:0] result_retries,nack_round;
    reg [31:0] expected_crc,completed_crc,completed_frame;
    reg completed_valid;
    reg [10:0] received_count;
    reg [7:0] bitmap[0:159];
    reg [7:0] map_addr,map_q,clear_at;
    reg [10:0] copy_at;
    reg [20:0] fragment_base;
    reg [127:0] word_hold;
    reg [6:0] word_at;
    reg [17:0] scan_word;
    reg [3:0] scan_byte;
    reg [127:0] scan_data;
    reg [31:0] scan_crc;
    reg scan_outstanding;
    reg [95:0] job_hold;
    reg job_pending,job_cached;
    reg [7:0] job_replay_ms;
    // Latches acceptance of the current Type20 job immediately, before the
    // first JOB_STATUS has had a chance to reach this link.  This closes the
    // one-cycle duplicate window after a lost READY response.
    reg grbl_test_active;
    // Distinguishes command 1 (fixed test) from command 2 (cached CNN
    // result) while sharing the existing JOB_STATUS cache and retry path.
    reg grbl_test_kind;
    reg [31:0] job_frame;
    // Capability bitmap received in the main-board HELLO. Bit 6 is the
    // fixed type18 multi-box result capability. Older main boards advertise
    // the historical 0x03 bitmap and therefore receive legacy type8.
    reg [7:0] peer_capabilities;

    // The production PCB-CNN image has no network configuration path.  These
    // ports remain for source compatibility with the old template wrappers,
    // but are hard-wired below to an idle/empty interface.
    localparam [31:0] PCB_MODEL_VERSION=32'h50434231; // "PCB1"
    // Template transfer (bit 1) and KEY3 teaching (bit 4) are retired.  Keep
    // all other configured capabilities, including the type18 negotiation.
    localparam [7:0] PRODUCTION_CAPABILITIES=CAPABILITIES & 8'hed;
    wire scanning=(state==CRC_INIT||state==CRC_REQUEST||state==CRC_WAIT||state==CRC_BYTE);
    function [31:0] crc_byte;
      input [31:0] c;input [7:0] d;integer j;reg [31:0] t;
      begin t=c^{24'd0,d};for(j=0;j<8;j=j+1)t=t[0]?((t>>1)^32'hedb88320):(t>>1);crc_byte=t;end
    endfunction
    // A frozen DDR word is consumed low byte first. The only supported
    // steps divide 16 exactly; no extra read or prefetch is introduced.
    localparam integer FRAME_CRC_STEP=(FRAME_CRC_BYTES_PER_CYCLE==4)?4:1;
    function [31:0] frame_crc_chunk;
      input [31:0] c;input [31:0] d;integer k;reg [31:0] t;
      begin
        t=c;
        for(k=0;k<FRAME_CRC_STEP;k=k+1)t=crc_byte(t,d[k*8+:8]);
        frame_crc_chunk=t;
      end
    endfunction
    wire [31:0] frame_crc_next=frame_crc_chunk(scan_crc,scan_data[31:0]);
    // synthesis translate_off
    initial if(FRAME_CRC_BYTES_PER_CYCLE!=1&&FRAME_CRC_BYTES_PER_CYCLE!=4)
      $fatal(1,"FRAME_CRC_BYTES_PER_CYCLE must be 1 or 4");
    // synthesis translate_on
    function [20:0] offset_1440;
      input [10:0] index;
      reg [20:0] wide;
      begin
        wide={10'd0,index};
        // Balance the constant multiply tree (1440 = 1024+256+128+32).
        // The previous left-associated expression created three serial
        // adders on the 125 MHz packet-accept path.
        offset_1440=((wide<<10)+(wide<<8))+((wide<<7)+(wide<<5));
      end
    endfunction
    function [7:0] tx_payload;
      input [7:0] typ;input [10:0] a;
      input [7:0] bitmap_byte;input [31:0] ack_crc;
      input [7:0] result_byte;input [95:0] job_bytes;
      input [255:0] station_bytes;input [31:0] station_version;
      input [15:0] packet_limit;integer k;
      begin
        tx_payload=0;
        case(typ)
          1,2:if(a<8)begin
            case(a)0:tx_payload=2;1:tx_payload=PRODUCTION_CAPABILITIES;
              4:tx_payload=station_version[7:0];5:tx_payload=station_version[15:8];
              6:tx_payload=station_version[23:16];7:tx_payload=station_version[31:24];default:;endcase
            end else if(a<40)tx_payload=station_bytes[(a-8)*8+:8];
          6:for(k=0;k<8;k=k+1)
            if(({5'd0,a}<<3)+k<packet_limit)tx_payload[k]=!bitmap_byte[k];
          7:case(a)0:tx_payload=ack_crc[7:0];1:tx_payload=ack_crc[15:8];
            2:tx_payload=ack_crc[23:16];3:tx_payload=ack_crc[31:24];default:;endcase
          8,16,18:tx_payload=result_byte;
          15:tx_payload=job_bytes[a*8+:8];
          default:;
        endcase
      end
    endfunction
    task send_reply;
      input [7:0] typ;input [15:0] len,flags_in;input [31:0] fid;input [5:0] next_state;
      begin
        tx_type<=typ;tx_length<=len;tx_flags<=flags_in;tx_frame<=fid;tx_at<=0;
        tx_index<=0;tx_count<=0;after_tx<=next_state;map_addr<=0;
        state<=(len==0)?TX_START:TX_GAP;
      end
    endtask
    task cancel_frame;
      begin
        if(frame_active)bad_frames<=bad_frames+1'b1;
        frame_active<=0;end_seen<=0;vision_active<=0;result_pending<=0;result_copy_pending<=0;
        job_pending<=0;job_cached<=0;
        vision_cancel<=1;packet_take<=1;
        send_reply(11,0,0,vision_frame_id,IDLE);
      end
    endtask

    hxa_packet_tx tx(.clk(clk),.rst_n(codec_rst_n),.load_we(state==TX_LOAD),.load_addr(tx_at),
      .load_data(tx_payload(tx_type,tx_at,map_q,tx_ack_crc,result_ram_q,job_hold,station_header,PCB_MODEL_VERSION,tx_count)),.start(tx_start),.msg_type(tx_type),.flags(tx_flags),
      .session_id(session_id),.frame_id(tx_frame),.packet_index(tx_index),.packet_count(tx_count),
      .payload_len(tx_length),.busy(tx_busy),.done(tx_done),.error(tx_error),.stack_reset(stack_reset),
      .udp_req(udp_req),.udp_valid(udp_valid),.udp_data(udp_data),.udp_len(udp_len),.udp_busy(udp_busy));
    // Four-slot BRAM packet queue decouples UDP capture from DDR writes.
    hxa_packet_rx_fifo4 rx(.clk(clk),.rst_n(codec_rst_n),
      .flush(vision_cancel||ctrl_cancel_take||control_cancel_pending||ctrl_hello_preempt),
      .udp_valid(rx_valid),.udp_data(rx_data),.udp_len(rx_len),
      .udp_error(rx_error),.packet_valid(packet_valid),.packet_take(packet_take),
      .msg_type(packet_type),.flags(packet_flags),.session_id(packet_session),.frame_id(packet_frame),
      .packet_index(packet_index),.packet_count(packet_count),.payload_len(payload_length),
      .payload_addr(payload_addr),.payload_data(payload_data),.packet_error(packet_error),.dropped_packets(dropped),
      .ctrl_valid(ctrl_valid),.ctrl_take(ctrl_take),.ctrl_type(ctrl_type),.ctrl_session(ctrl_session),
      .ctrl_frame(ctrl_frame),.ctrl_payload_len(ctrl_payload_len),.ctrl_body(ctrl_body),
      .ctrl_event(ctrl_event),.ctrl_event_session(ctrl_event_session));

    assign wr_valid=state==WRITE_WORD&&link_ok&&
                    !ctrl_cancel_take&&!control_cancel_pending&&!ctrl_hello_preempt;
    assign wr_byte_addr=fragment_base+{10'd0,word_at,4'd0};
    assign wr_data=word_hold;
    // A cancelled read cannot be withdrawn at the DDR endpoint. Retain its
    // outstanding tag until rd_valid drains, and never issue a request on the
    // same edge that cancels/preempts the frame or drops its link/session.
    wire crc_read_request=(state==CRC_REQUEST)&&link_ok&&online&&
                          !scan_outstanding&&!ctrl_cancel_take&&
                          !control_cancel_pending&&!ctrl_hello_preempt&&
                          transfer_ms<2000&&lease_ms<3000;
    assign rd_req=scanning?crc_read_request:
                  (vision_active&&!scan_outstanding?v_rd_req:1'b0);
    // CRC scanner addresses 16-byte words.  scan_word is 18 bits for the
    // 115,200-word frame, but only the low 17 bits are needed (the highest
    // value is 115,199).  Keep the externally visible address at 21 bits
    // and avoid an accidental 22-bit concatenation/truncation.
    assign rd_byte_addr=scanning?{scan_word[16:0],4'd0}:v_rd_byte_addr;
    assign v_rd_ready=vision_active&&!scanning&&!scan_outstanding&&rd_ready;
    assign v_rd_valid=vision_active&&!scan_outstanding&&rd_valid;
    assign v_rd_data=rd_data;
    // Legacy configuration writes are retired in production builds.
    assign cfg_we=1'b0;
    assign cfg_addr=15'd0;
    assign cfg_data=8'd0;
    assign cfg_total_bytes=15'd0;
    assign cfg_commit=1'b0;
    assign cfg_version=PCB_MODEL_VERSION;
    assign cfg_begin=1'b0;
    assign cfg_abort=1'b0;
    assign cfg_pending_version=PCB_MODEL_VERSION;
    assign cfg_expected_crc32=32'd0;
    assign cfg_good_count=3'd0;
    assign cfg_bad_count=3'd0;
    assign vision_teach_good=1'b0;
    // Keep the status body frozen until the whole packet is serialized.
    assign job_status_ready=!job_pending&&!((state==TX_LOAD||state==TX_GAP||state==TX_START||state==TX_WAIT)&&tx_type==15);

    always @(posedge clk) begin
      map_q<=bitmap[map_addr];
      if(state==CLEAR_MAP)bitmap[clear_at]<=0;
      if(state==MARK_PACKET)bitmap[map_addr]<=map_q|(8'b1<<saved_index[2:0]);
      // No configuration RAM is present in this build.
    end

    always @(posedge clk) begin
      if(result_copy_pending)
        result_ram[result_copy_at]<=result_is_multibox ?
          vision_result_multibox[{result_copy_at,3'b000} +: 8] :
          (result_is_maze ? vision_maze_result[{result_copy_at,3'b000} +: 8] :
           vision_result[{result_copy_at[5:0],3'b000} +: 8]);
      // Every result byte uses TX_GAP -> TX_LOAD, including byte zero. The
      // one-cycle BRAM read is therefore aligned with the packet-codec write.
      if(state==TX_GAP&&(tx_type==8||tx_type==16||tx_type==18))
        result_ram_q<=result_ram[tx_at];
    end

    always @(posedge clk or negedge rst_n) begin
      if(!rst_n) begin
        state<=IDLE;after_tx<=IDLE;tx_type<=0;tx_flags<=0;tx_length<=0;tx_index<=0;tx_count<=0;
        tx_frame<=0;tx_ack_crc<=0;tx_start<=0;tx_at<=0;packet_take<=0;payload_addr<=0;
        ctrl_take<=0;saved_ctrl<=0;control_cancel_pending<=0;
        hb_reply_pending<=0;hb_reply_frame<=0;hb_reply_session<=0;
        saved_type<=0;saved_flags<=0;saved_index<=0;saved_count<=0;saved_length<=0;saved_session<=0;saved_frame<=0;
        body_at<=0;body<=0;ms_div<=0;lease_ms<=0;transfer_ms<=0;result_ms<=0;
        frame_active<=0;end_seen<=0;vision_active<=0;result_pending<=0;result_acked<=0;result_is_maze<=0;
        result_copy_pending<=0;result_copy_at<=0;result_is_multibox<=0;peer_capabilities<=0;
        result_retries<=0;nack_round<=0;expected_crc<=0;completed_crc<=0;completed_frame<=0;completed_valid<=0;
        received_count<=0;map_addr<=0;clear_at<=0;copy_at<=0;fragment_base<=0;word_hold<=0;word_at<=0;
        scan_word<=0;scan_byte<=0;scan_data<=0;scan_crc<=32'hffffffff;scan_outstanding<=0;
        job_hold<=0;job_pending<=0;job_cached<=0;job_frame<=0;grbl_test_active<=0;grbl_test_kind<=0;
        vision_start<=0;vision_cancel<=0;vision_job_cancel<=0;vision_frame_id<=0;vision_job_id<=0;vision_purpose<=0;vision_paper_width_px<=0;
        grbl_test_start<=0;grbl_test_job_id<=0;grbl_current_start<=0;grbl_current_job_id<=0;
        session_id<=0;online<=0;good_frames<=0;bad_frames<=0;copy_rearm<=0;job_replay_ms<=0;
      end else begin
        tx_start<=0;packet_take<=0;vision_start<=0;vision_cancel<=0;vision_job_cancel<=0;copy_rearm<=0;
        ctrl_take<=0;
        grbl_test_start<=0;grbl_current_start<=0;
        if(tick_ms)begin
          ms_div<=0;
          if(lease_ms<3000)lease_ms<=lease_ms+1'b1;
          if(transfer_ms<3000)transfer_ms<=transfer_ms+1'b1;
          if(result_ms<2000)result_ms<=result_ms+1'b1;
          if(job_replay_ms<250)job_replay_ms<=job_replay_ms+1'b1;
        end else ms_div<=ms_div+1'b1;
        if(crc_read_request&&rd_ready)scan_outstanding<=1;
        if(rd_valid&&scan_outstanding)scan_outstanding<=0;
        // A CRC-checked HELLO/heartbeat has its own control queue. Renew only
        // on arrival, never from the level of a stalled packet at the head.
        // This remains live while DDR writes, CRC scanning or CNN are busy.
        if(ctrl_event&&online&&ctrl_event_session==session_id)
          lease_ms<=0;
        // Drain authenticated control traffic independently of the image FSM.
        // Multiple heartbeats coalesce to one deferred reply while DDR/CRC is
        // blocked, but every accepted heartbeat renews the lease exactly once.
        if(ctrl_cancel_take)begin
          ctrl_take<=1;
          if(ctrl_job_cancel_take)vision_job_cancel<=1;
          // An explicit job cancel is a manual recovery boundary. Clear the
          // queued job immediately and let the reporter consume the cancel
          // pulse; ordinary Type11 remains frame-only while a job is busy.
          if(ctrl_explicit_job_cancel_take)begin
            job_pending<=0;job_cached<=0;grbl_test_active<=0;grbl_test_kind<=0;
            grbl_test_job_id<=0;grbl_current_job_id<=0;
          end
          // A mode-change CANCEL is the explicit manual recovery boundary.
          // Other cancellations and repeated KEY1 presses cannot rearm motion.
          if(ctrl_body[31:0]==32'h31445848&&ctrl_body[39:32]==1&&ctrl_body[47:40]==5)
            copy_rearm<=1;
          if(tx_active_state&&(!job_busy||ctrl_explicit_job_cancel_take))
            control_cancel_pending<=1;
        end else if(ctrl_heartbeat_take)begin
          ctrl_take<=1;lease_ms<=0;
          if(job_cached&&job_replay_ms>=250)begin job_pending<=1;job_replay_ms<=0;end
          if(!hb_reply_pending)begin
            hb_reply_pending<=1;hb_reply_frame<=ctrl_frame;hb_reply_session<=ctrl_session;
          end
        end else if(ctrl_hello_preempt)begin
          ctrl_take<=1;saved_ctrl<=1;saved_type<=ctrl_type;saved_flags<=0;
          saved_index<=0;saved_count<=0;saved_length<=8;
          saved_session<=ctrl_session;saved_frame<=ctrl_frame;
          body<={448'd0,ctrl_body};state<=DISPATCH;
          hb_reply_pending<=0;hb_reply_frame<=0;hb_reply_session<=0;
        end else if(ctrl_drop)ctrl_take<=1;
        if(job_status_valid&&job_status_ready&&online&&
           (job_status_data[31:0]==vision_job_id||
            (grbl_test_active&&job_status_data[31:0]==grbl_test_job_id)))begin
          job_hold<=job_status_data;
          // Vision status is keyed by the image frame, while type20 uses its
          // packet frame id directly as the standalone printer job id.
          job_frame<=((grbl_test_active&&job_status_data[31:0]==grbl_test_job_id) ?
                      grbl_test_job_id : vision_frame_id);
          job_pending<=1;job_cached<=1;
          job_replay_ms<=0;
        end
        if(vision_done&&vision_active)begin
          vision_active<=0;result_acked<=0;
          result_is_maze<=(vision_purpose==3);
          // The same CNN core can provide a legacy best result and the new
          // 4-box result.  Select type18 only after capability negotiation;
          // old main boards continue to receive type8 without any protocol
          // change or duplicate result packet.
          result_is_multibox<=(vision_result_type==8'd18)&&
                              CAPABILITIES[6]&&peer_capabilities[6]&&vision_purpose==0;
          result_retries<=0;
          // purpose=2 completes through the unchanged 12-byte Type15 only.
          // Keep DDR ownership until doc_copy_pipeline reports terminal state.
          result_copy_pending<=(vision_purpose!=2);result_copy_at<=0;result_pending<=0;
        end
        if(result_copy_pending)begin
          if(result_copy_at<=(result_is_multibox?11'd79:(result_is_maze?11'd223:11'd63)) &&
             result_copy_at==(result_is_multibox?11'd79:(result_is_maze?11'd223:11'd63)))begin
            // The final BRAM write happens on this same edge. TX_GAP then
            // supplies the first registered read before any TX_LOAD byte.
            result_copy_pending<=0;result_pending<=1;result_ms<=100;
          end else result_copy_at<=result_copy_at+1'b1;
        end
        // board_mode is a retired compatibility input.  Only production
        // role-1 sources can open a session; toggling SW2 cannot cancel it.
        // A packet/response error cancels only the current transaction. Keep
        // the HELLO session alive until PHY loss or the 3 s lease expires.
        // Lease expiry clears the image queue, but preserves the separate
        // validated control queue so a new HELLO can take over immediately.
        if(!link_ok||(online&&lease_ms>=3000&&
           !(ctrl_event&&ctrl_event_session==session_id)))begin
          state<=IDLE;online<=0;session_id<=0;frame_active<=0;
          peer_capabilities<=0;
          completed_valid<=0;vision_active<=0;result_pending<=0;result_copy_pending<=0;
          if(!job_busy)begin
            job_pending<=0;job_cached<=0;grbl_test_active<=0;grbl_test_kind<=0;grbl_test_job_id<=0;grbl_current_job_id<=0;vision_cancel<=1;
          end
          control_cancel_pending<=0;hb_reply_pending<=0;hb_reply_frame<=0;hb_reply_session<=0;
        end else if(tx_error)begin
          if(frame_active||vision_active||result_pending||result_copy_pending)
            bad_frames<=bad_frames+1'b1;
          state<=IDLE;frame_active<=0;end_seen<=0;vision_active<=0;
          result_pending<=0;result_copy_pending<=0;
          if(!job_busy)begin
            job_pending<=0;job_cached<=0;
            grbl_test_active<=0;grbl_test_kind<=0;grbl_test_job_id<=0;grbl_current_job_id<=0;
            vision_cancel<=1;
          end
          packet_take<=1;
          control_cancel_pending<=0;hb_reply_pending<=0;hb_reply_frame<=0;hb_reply_session<=0;
        end else if((ctrl_cancel_take||control_cancel_pending)&&!tx_active_state)begin
          if(ctrl_cancel_take)ctrl_take<=1;
          control_cancel_pending<=0;
          if(job_busy&&!ctrl_job_cancel_take)begin
            // Ordinary Type11 is consumed, but the accepted printer task keeps
            // its owner, path and in-flight G-code state.
            packet_take<=1;state<=IDLE;
          end else begin
            frame_active<=0;end_seen<=0;vision_active<=0;result_pending<=0;result_copy_pending<=0;
            job_pending<=0;job_cached<=0;grbl_test_active<=0;grbl_test_kind<=0;
            grbl_test_job_id<=0;grbl_current_job_id<=0;
            vision_cancel<=1;packet_take<=1;transfer_ms<=0;state<=IDLE;
          end
        end else if(ctrl_hello_preempt)begin
          // The staged control packet is dispatched on the next cycle. This
          // preempts a stalled DDR write/CRC read without touching an active TX.
        end else if(frame_active&&transfer_ms>=2000&&!tx_active_state)begin
          // Bound the whole frame transaction, including WRITE_WORD,
          // WRITE_DRAIN and CRC_WAIT. scan_outstanding is deliberately kept
          // until rd_valid drains, so a late DDR response cannot feed a new scan.
          cancel_frame();
        end else case(state)
          IDLE:begin
            if(ctrl_valid&&!ctrl_take&&ctrl_type==8'd1)begin
              ctrl_take<=1;
              if(ctrl_type==1)begin
                saved_ctrl<=1;saved_type<=ctrl_type;saved_flags<=0;
                saved_index<=0;saved_count<=0;saved_length<=(ctrl_type==1)?8:0;
                saved_session<=ctrl_session;saved_frame<=ctrl_frame;
                body<={448'd0,ctrl_body};state<=DISPATCH;
              end
            end else if(packet_valid&&!packet_take)begin
              saved_ctrl<=0;
              if(packet_type!=1&&(packet_session!=session_id||!online))packet_take<=1;
              else begin
                saved_type<=packet_type;saved_flags<=packet_flags;saved_index<=packet_index;
                saved_count<=packet_count;saved_length<=payload_length;saved_session<=packet_session;saved_frame<=packet_frame;
                // HELLO may name a different live session or contain an
                // invalid role/body. Refresh its lease only after DISPATCH
                // accepts it; rejected HELLOs must let the old lease expire.
                if(packet_type!=1)lease_ms<=0;
                payload_addr<=0;body_at<=0;body<=0;
                // Type 12/13/14 were the PC template/configuration protocol.
                // They remain recognized so old hosts receive a deterministic
                // compatibility NACK, but no payload is staged or validated.
                if(packet_type==12 || packet_type==13 || packet_type==14)begin
                  packet_take<=1;
                  send_reply(11,0,1,packet_frame,IDLE);
                end else if(packet_type==4)begin
                  if(frame_active&&packet_flags==0&&packet_frame==vision_frame_id&&
                     packet_index<1280&&packet_count==1280&&payload_length==1440)begin
                    map_addr<=packet_index[10:3];fragment_base<=offset_1440(packet_index[10:0]);state<=MAP_PRIME;
                  end else packet_take<=1;
                end else if(payload_length>64)packet_take<=1;
                else if(payload_length==0)state<=DISPATCH;
                else state<=BODY_PRIME;
              end
            end else if(hb_reply_pending&&!tx_busy)begin
              hb_reply_pending<=0;hb_reply_frame<=0;hb_reply_session<=0;
              if(online&&hb_reply_session==session_id)
                send_reply(10,0,0,hb_reply_frame,IDLE);
            end
            else if(result_pending&&result_ms>=100&&!tx_busy)begin
              if(result_retries==3)cancel_frame();
              else begin result_retries<=result_retries+1'b1;result_ms<=0;
                send_reply(result_is_multibox?18:(result_is_maze?16:8),
                           result_is_multibox?80:(result_is_maze?224:64),0,vision_frame_id,IDLE);end
            end else if(job_pending&&!tx_busy)begin job_pending<=0;job_replay_ms<=0;send_reply(15,12,0,job_frame,IDLE);end
            else if(job_cached&&job_replay_ms>=250)begin job_pending<=1;end
          end
          BODY_PRIME:begin payload_addr<=1;state<=BODY_READ;end
          BODY_READ:begin
            body[body_at*8+:8]<=payload_data;
            if(body_at==saved_length-1)state<=DISPATCH;
            else begin body_at<=body_at+1'b1;payload_addr<=payload_addr+1'b1;end
          end
          DISPATCH:begin
            if(!saved_ctrl)packet_take<=1;
            state<=IDLE;
            case(saved_type)
              // HELLO is the explicit session handover point.  A new valid
              // HELLO is allowed to replace an old live session immediately;
              // waiting for the old lease would leave the link stuck after a
              // main-board restart or a per-frame CANCEL.
              1:if(saved_flags==0&&saved_length==8&&saved_session!=0&&body[31:16]==0&&
                  body[7:0]==1)begin
                if(saved_session!=session_id)begin
                  frame_active<=0;completed_valid<=0;
                  result_pending<=0;result_copy_pending<=0;
                  if(!job_busy)begin
                    vision_active<=0;job_pending<=0;job_cached<=0;grbl_test_active<=0;grbl_test_kind<=0;grbl_test_job_id<=0;grbl_current_job_id<=0;vision_cancel<=1;
                  end
                  hb_reply_pending<=0;hb_reply_frame<=0;hb_reply_session<=0;control_cancel_pending<=0;
                end
                session_id<=saved_session;online<=1;lease_ms<=0;
                peer_capabilities<=body[15:8];
                send_reply(2,station_valid?40:8,0,saved_frame,IDLE);
              end
              10:if(saved_length==0&&saved_flags==0)begin
                send_reply(10,0,0,saved_frame,IDLE);
                if(job_cached)job_pending<=1;
              end
              11:begin
                if((saved_length==0&&!job_busy) ||
                   (saved_length==28&&body[31:0]==32'h31445848&&
                    body[39:32]==8'd1&&body[47:40]==8'h80))
                  vision_job_cancel<=1;
                if(body[31:0]==32'h31445848&&body[39:32]==1&&body[47:40]==5)copy_rearm<=1;
                frame_active<=0;end_seen<=0;result_pending<=0;result_copy_pending<=0;
                if(!job_busy || (saved_length==28&&body[31:0]==32'h31445848&&body[39:32]==8'd1&&body[47:40]==8'h80))begin
                  vision_active<=0;job_pending<=0;job_cached<=0;grbl_test_active<=0;grbl_test_kind<=0;grbl_test_job_id<=0;grbl_current_job_id<=0;vision_cancel<=1;
                end
                control_cancel_pending<=0;hb_reply_pending<=0;hb_reply_frame<=0;hb_reply_session<=0;
              end
              // Type 20 is intentionally separate from image/config traffic.
              // The host sends payload u32=1 and uses the packet frame id as
              // the report job id.  Reject it while any frame, inference,
              // result or printer transaction is active.
              TYPE_GCODE_TEST:if(saved_flags==0&&saved_index==0&&saved_count==0&&
                    saved_length==4&&saved_frame!=0&&
                    (body[31:0]==GCODE_TEST_COMMAND_ID||body[31:0]==GCODE_CURRENT_COMMAND_ID)&&
                    (((!frame_active&&!vision_busy&&!vision_active&&
                       !job_busy&&!result_pending&&!result_copy_pending&&!job_pending))||
                     (grbl_test_active&&saved_frame==grbl_test_job_id)))begin
                // A retransmitted command may arrive after its READY reply
                // was lost.  Replay READY and the cached JOB_STATUS without
                // starting a second printer transaction.
                if(!(grbl_test_active&&saved_frame==grbl_test_job_id))begin
                  grbl_test_job_id<=saved_frame;
                  grbl_current_job_id<=saved_frame;
                  grbl_test_active<=1;
                  grbl_test_kind<=(body[31:0]==GCODE_CURRENT_COMMAND_ID);
                  // A new printer job must not inherit a cached JOB_STATUS
                  // from the previous job.  The first status generated by
                  // secondary_top will populate the cache again.
                  job_pending<=0;
                  job_cached<=0;
                  // Type20 is a standalone printer transaction.
                  vision_frame_id<=saved_frame;
                  vision_job_id<=saved_frame;
                  vision_purpose<=0;
                  if(body[31:0]==GCODE_CURRENT_COMMAND_ID)
                    grbl_current_start<=1;
                  else
                    grbl_test_start<=1;
                end else if(job_cached)begin
                  // READY may have reached the host while the cached status
                  // packet was lost.  Re-queue the latest status for the
                  // duplicate command without starting the plotter again.
                  job_pending<=1;
                end
                send_reply(2,0,0,saved_frame,IDLE);
              end
              3:if(saved_flags==0&&saved_length==16)begin
                // Copy mode is explicitly negotiated. An old peer must never
                // accidentally start a long document/plotter transaction.
                if(body[47:40]==2&&!(CAPABILITIES[7]&&peer_capabilities[7]))begin
                  send_reply(11,0,0,saved_frame,IDLE);
                end else if(completed_valid&&saved_frame==completed_frame)begin
                  tx_ack_crc<=completed_crc;send_reply(7,4,0,saved_frame,IDLE);
                end else if(frame_active&&saved_frame==vision_frame_id)send_reply(2,0,0,saved_frame,IDLE);
                else if(!frame_active&&!vision_busy&&!vision_active&&!job_busy&&!result_pending&&!result_copy_pending&&wr_idle&&
                    body[15:0]==1280&&body[31:16]==720&&body[39:32]==1&&body[47:40]<=3&&
                    ((body[41:40]!=2&&body[63:48]==0)||body[41:40]==2)&&
                    body[95:64]==1843200&&saved_count==1280&&
                    (body[47:40]!=3||CAPABILITIES[5])&&
                    (!completed_valid||((saved_frame-completed_frame)!=0&&!((saved_frame-completed_frame)&32'h80000000))))begin
                  vision_frame_id<=saved_frame;vision_job_id<=body[127:96];vision_purpose<=body[41:40];
                  vision_paper_width_px<=body[63:48];
                  job_pending<=0;job_cached<=0;grbl_test_active<=0;grbl_test_kind<=0;grbl_test_job_id<=0;grbl_current_job_id<=0;
                  frame_active<=1;end_seen<=0;received_count<=0;transfer_ms<=0;nack_round<=0;
                  clear_at<=0;state<=CLEAR_MAP;
                end
              end
              5:if(saved_flags==0&&saved_length==4)begin
                if(completed_valid&&saved_frame==completed_frame&&body[31:0]==completed_crc)begin
                  tx_ack_crc<=completed_crc;send_reply(7,4,0,saved_frame,IDLE);
                end else if(frame_active&&saved_frame==vision_frame_id)begin
                  if(end_seen&&body[31:0]!=expected_crc)cancel_frame();
                  else begin
                    expected_crc<=body[31:0];end_seen<=1;
                    if(received_count==1280)state<=CRC_INIT;
                    else if(nack_round==3)cancel_frame();
                    else begin
                      nack_round<=nack_round+1'b1;send_reply(6,160,0,saved_frame,IDLE);
                      tx_index<={14'd0,nack_round}+1'b1;tx_count<=1280;
                    end
                  end
                end
              end
              9:if(result_pending&&!result_copy_pending&&!result_is_maze&&!result_is_multibox&&saved_flags==0&&saved_index==0&&saved_count==0&&saved_length==0&&saved_frame==vision_frame_id)begin result_pending<=0;result_acked<=1;end
              17:if(result_pending&&!result_copy_pending&&result_is_maze&&saved_flags==0&&saved_length==0&&saved_frame==vision_frame_id)begin result_pending<=0;result_acked<=1;end
              19:if(result_pending&&!result_copy_pending&&result_is_multibox&&saved_flags==0&&saved_index==0&&saved_count==0&&saved_length==4&&saved_frame==vision_frame_id&&body[31:0]==vision_job_id)begin result_pending<=0;result_acked<=1;end
              default:;
            endcase
          end
          CLEAR_MAP:if(clear_at==159)begin
            send_reply(2,0,0,vision_frame_id,IDLE);
          end else clear_at<=clear_at+1'b1;
          MAP_PRIME:state<=MAP_CHECK;
          MAP_CHECK:if(map_q[saved_index[2:0]])begin packet_take<=1;state<=IDLE;end
            else begin copy_at<=0;word_at<=0;word_hold<=0;payload_addr<=0;state<=COPY_PRIME;end
          COPY_PRIME:state<=COPY_BYTE;
          COPY_BYTE:begin
            payload_addr<=payload_addr+1'b1;copy_at<=copy_at+1'b1;
            word_hold[copy_at[3:0]*8+:8]<=payload_data;
            state<=(copy_at[3:0]==15)?WRITE_WORD:COPY_DELAY;
          end
          COPY_DELAY:state<=COPY_BYTE;
          WRITE_WORD:if(wr_ready)begin
            if(copy_at==1440)state<=WRITE_DRAIN;
            else begin word_at<=word_at+1'b1;state<=COPY_BYTE;end
          end
          WRITE_DRAIN:if(wr_idle)state<=MARK_PACKET;
          MARK_PACKET:begin
            received_count<=received_count+1'b1;packet_take<=1;
            if(end_seen&&received_count==1279)state<=CRC_INIT;
            else state<=IDLE;
          end
          CRC_INIT:if(wr_idle&&!scan_outstanding)begin scan_crc<=32'hffffffff;scan_word<=0;state<=CRC_REQUEST;end
          CRC_REQUEST:if(crc_read_request&&rd_ready)state<=CRC_WAIT;
          CRC_WAIT:if(rd_valid&&scan_outstanding)begin scan_data<=rd_data;scan_byte<=0;state<=CRC_BYTE;end
          CRC_BYTE:begin
            scan_crc<=frame_crc_next;scan_data<=scan_data>>(8*FRAME_CRC_STEP);
            if(scan_byte>=16-FRAME_CRC_STEP)begin
              if(scan_word==115199)begin
                if(~frame_crc_next==expected_crc)begin
                  frame_active<=0;completed_valid<=1;completed_frame<=vision_frame_id;completed_crc<=expected_crc;
                  vision_active<=1;vision_start<=1;good_frames<=good_frames+1'b1;
                  tx_ack_crc<=expected_crc;send_reply(7,4,0,vision_frame_id,IDLE);
                end else cancel_frame();
              end else begin scan_word<=scan_word+1'b1;state<=CRC_REQUEST;end
            end else scan_byte<=scan_byte+FRAME_CRC_STEP;
          end
          // CFG_SCAN/CFG_PUSH/CFG_COMMIT were removed from the production
          // state machine. Type12/13/14 are rejected in IDLE before payload
          // staging, so no configuration path can reach this point.
          TX_GAP:state<=TX_LOAD;
          TX_LOAD:begin
            if(tx_at==tx_length-1)state<=TX_START;
            else begin tx_at<=tx_at+1'b1;map_addr<=map_addr+1'b1;state<=TX_GAP;end
          end
          TX_START:if(!tx_busy)begin tx_start<=1;state<=TX_WAIT;end
          TX_WAIT:if(tx_done)state<=after_tx;
          default:state<=IDLE;
        endcase
      end
    end
endmodule
