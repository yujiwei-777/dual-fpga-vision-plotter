// One physical transport/parser/formatter for mutually-exclusive plot jobs.
// Report and document policies retain their original acknowledgement, safety
// and timer semantics. Mode is held until the generator, UART and formatter
// are quiescent; a recovery lock never releases ownership automatically.
module grbl_shared_transport_candidate #(
    parameter integer CLK_HZ=125000000,
    parameter integer REPORT_ACK_TIMEOUT_CYCLES=CLK_HZ*5,
    parameter integer REPORT_STATUS_TIMEOUT_CYCLES=CLK_HZ*2,
    parameter integer DOC_QUERY_MS=500,DOC_STATUS_MS=2000,
    parameter integer DOC_FINAL_MS=120000,DOC_PROGRESS_MS=30000,DOC_JOB_MS=1800000
)(
    input wire clk,
    input wire rst_n,
    input wire I_doc_owner,
    input wire I_report_claim,
    input wire link_ready,
    input wire tx_ready,
    input wire tx_done,
    input wire rt_ready,
    input wire [7:0] rx_data,
    input wire rx_valid,
    input wire rx_error,
    output wire [7:0] tx_data,
    output wire tx_valid,
    output wire [7:0] rt_data,
    output wire rt_valid,
    input wire R_start,
    input wire R_clear,
    input wire R_abort,
    input wire R_stop,
    input wire R_rearm,
    input wire R_cancel,
    input wire R_fault,
    input wire R_reset_job,
    input wire R_profile_valid,
    input wire [7:0] R_fault_code,
    input wire [511:0] R_line,
    input wire [6:0] R_length,
    input wire R_line_valid,
    input wire R_line_last,
    input wire R_finish,
    output wire R_available,
    output wire R_line_ready,
    output reg R_line_done,
    output wire R_busy,
    output reg R_done,
    output reg R_error,
    output wire R_cancelled,
    output reg R_recovery_required,
    output reg [7:0] R_error_code,
    output reg [31:0] R_acked_lines,
    output wire [2:0] R_job_state,
    output wire R_rt_done,
    input wire R_fmt_start,
    input wire [1:0] R_fmt_kind,
    input wire [15:0] R_fmt_x,
    input wire [15:0] R_fmt_y,
    input wire [15:0] R_fmt_z,
    input wire [15:0] R_fmt_feed,
    input wire [15:0] R_fmt_pwm,
    output wire [511:0] R_fmt_line,
    output wire [6:0] R_fmt_length,
    output wire R_fmt_done,
    output wire R_fmt_busy,
    input wire D_start,
    input wire D_clear,
    input wire D_abort,
    input wire D_stop,
    input wire D_rearm,
    input wire D_cancel,
    input wire D_fault,
    input wire D_reset_job,
    input wire D_profile_valid,
    input wire [7:0] D_fault_code,
    input wire [511:0] D_line,
    input wire [6:0] D_length,
    input wire D_line_valid,
    input wire D_line_last,
    input wire D_finish,
    output wire D_available,
    output wire D_line_ready,
    output reg D_line_done,
    output wire D_busy,
    output reg D_done,
    output reg D_error,
    output reg D_cancelled,
    output reg D_recovery_required,
    output reg [7:0] D_error_code,
    output reg [31:0] D_acked_lines,
    output wire [2:0] D_job_state,
    output wire D_rt_done,
    input wire D_fmt_start,
    input wire [1:0] D_fmt_kind,
    input wire [15:0] D_fmt_x,
    input wire [15:0] D_fmt_y,
    input wire [15:0] D_fmt_z,
    input wire [15:0] D_fmt_feed,
    input wire [15:0] D_fmt_pwm,
    output wire [511:0] D_fmt_line,
    output wire [6:0] D_fmt_length,
    output wire D_fmt_done,
    output wire D_fmt_busy
);
    localparam [4:0] R_IDLE=0,R_LINE=1,R_SEND=2,R_DRAIN=3,R_ACK=4,R_FAULT=9,
                     R_STOP_DRAIN=11,R_STOP_BANG=12,R_STOP_BANG_WAIT=13,
                     R_STOP_QUERY=14,R_STOP_QUERY_WAIT=15,R_STOP_STATUS=16,R_STOP_RESET=17,
                     R_STOP_RESET_WAIT=18,R_REARM_QUERY=19,R_REARM_WAIT=20,R_REARM_STATUS=21,R_DONE_PENDING=22;
    localparam [7:0] R_ERR_PROFILE=1,R_ERR_LINK=2,R_ERR_ACK_TIMEOUT=3,
                     R_ERR_STATUS_TIMEOUT=4,R_ERR_RESPONSE=5,R_ERR_UART=6,
                     R_ERR_LINE=7,R_ERR_ABORT=8,R_ERR_RESET=9;
    localparam [4:0] D_IDLE=0,D_READY=1,D_SEND=2,D_BYTE_WAIT=3,D_ACK_WAIT=4,
        D_FINAL_QUERY=5,D_FINAL_QUERY_WAIT=6,D_FINAL_STATUS=7,
        D_C_DRAIN=8,D_C_BANG=9,D_C_BANG_WAIT=10,D_C_QUERY=11,D_C_QUERY_WAIT=12,
        D_C_STATUS=13,D_C_RESET=14,D_C_RESET_WAIT=15,D_R_QUERY=16,D_R_QUERY_WAIT=17,D_R_STATUS=18;
    localparam integer DOC_MS_DIV=(CLK_HZ/1000<1)?1:CLK_HZ/1000;

    localparam integer ACK_TIMER_W=(REPORT_ACK_TIMEOUT_CYCLES<2)?1:$clog2(REPORT_ACK_TIMEOUT_CYCLES+1);
    localparam integer STATUS_TIMER_W=(REPORT_STATUS_TIMEOUT_CYCLES<2)?1:$clog2(REPORT_STATUS_TIMEOUT_CYCLES+1);
    localparam integer R_TIMER_W=(ACK_TIMER_W>STATUS_TIMER_W)?ACK_TIMER_W:STATUS_TIMER_W;
    localparam integer SHARED_TIMER_W=(R_TIMER_W>32)?R_TIMER_W:32;
    reg owner_valid,owner_doc;
    wire doc_claim=I_doc_owner || D_reset_job || D_rearm || D_start || D_recovery_required;
    wire active_doc=owner_valid?owner_doc:(!R_recovery_required && doc_claim);
    // Busy outputs below use only the registered owner, not active_doc's
    // first-cycle look-ahead. Their public aliases feed I_doc_owner and
    // I_report_claim, so using look-ahead there would form a combinational
    // owner -> busy -> claim -> owner loop. An unheld owner has state IDLE;
    // the look-ahead remains necessary only for same-edge start/reset policy.
    // After a preparation Reset transfers ownership to the report lock, the
    // top may still route KEY4 to document for one retiring copy_busy cycle.
    // Fence TX and run the same report stop policy for that reset pulse.
    wire report_stop=R_stop || (!active_doc && D_reset_job);
    reg [4:0] state;
    reg [511:0] payload;
    reg [6:0] payload_length,byte_index;
    reg report_last,inflight,rt_inflight,parser_clear,r_stop_fault;
    reg [SHARED_TIMER_W-1:0] response_timer;
    wire [ACK_TIMER_W-1:0] ack_timer=response_timer[ACK_TIMER_W-1:0];
    wire [STATUS_TIMER_W-1:0] status_timer=response_timer[STATUS_TIMER_W-1:0];
    reg d_cancel_fault,d_status_pending,d_first_query,d_final_idle_seen,d_stop_seen,d_reset_pending;
    reg [2:0] d_terminal_state;
    reg [31:0] d_tick_count,d_job_ms,d_progress_ms,d_final_ms,d_query_ms;
    wire d_reset_request=(D_reset_job===1'b1);
    wire p_ok,p_error,p_alarm,p_status,p_idle,p_hold0,p_overflow,p_reset;
    reg [7:0] r_tx_data;
    reg r_tx_valid;
    wire [7:0] d_tx_data,r_rt_data,d_rt_data;
    wire d_tx_valid,r_rt_valid,d_rt_valid;
    assign R_available=owner_valid?!owner_doc:!doc_claim;
    assign D_available=owner_valid?owner_doc:(!R_recovery_required &&
        (I_doc_owner || D_reset_job || D_rearm || !I_report_claim));
    assign R_cancelled=1'b0;
    assign D_rt_done=active_doc && tx_done;
    assign tx_data=active_doc?d_tx_data:r_tx_data;
    assign tx_valid=active_doc?d_tx_valid:r_tx_valid;
    assign rt_data=active_doc?d_rt_data:r_rt_data;
    assign rt_valid=active_doc?d_rt_valid:r_rt_valid;
    grbl_response_parser u_parser(.I_clk(clk),.I_rst_n(rst_n),.I_clear(parser_clear),
        .I_data(rx_data),.I_valid(rx_valid),.O_ok(p_ok),.O_error(p_error),
        .O_alarm(p_alarm),.O_status(p_status),.O_idle(p_idle),.O_overflow(p_overflow),
        .O_hold0(p_hold0),.O_reset(p_reset));
    // Dynamic pre-mirror is identical to the two released formatter constants.
    wire fmt_start=active_doc?D_fmt_start:R_fmt_start;
    wire [15:0] fmt_x=active_doc?(16'd21000-D_fmt_x):(16'd20000-R_fmt_x);
    wire [511:0] fmt_line;
    wire [6:0] fmt_length;
    wire fmt_done,fmt_busy;
    grbl_line_formatter #(.PLOT_MIRROR_X(0)) u_formatter(.I_clk(clk),.I_rst_n(rst_n),.I_start(fmt_start),
        .I_kind(active_doc?D_fmt_kind:R_fmt_kind),.I_x_cmm(fmt_x),
        .I_y_cmm(active_doc?D_fmt_y:R_fmt_y),.I_z_cmm(active_doc?D_fmt_z:R_fmt_z),
        .I_feed(active_doc?D_fmt_feed:R_fmt_feed),.I_pwm(active_doc?D_fmt_pwm:R_fmt_pwm),
        .O_line(fmt_line),.O_length(fmt_length),.O_done(fmt_done),.O_busy(fmt_busy));
    assign R_fmt_line=fmt_line;assign D_fmt_line=fmt_line;
    assign R_fmt_length=fmt_length;assign D_fmt_length=fmt_length;
    assign R_fmt_done=!active_doc && fmt_done;assign D_fmt_done=active_doc && fmt_done;
    assign R_fmt_busy=fmt_busy;assign D_fmt_busy=fmt_busy;
    assign R_busy=owner_valid && !owner_doc && (state!=R_IDLE && state!=R_FAULT);
    assign R_line_ready=(!active_doc && state==R_LINE && link_ready && R_profile_valid);
    assign R_job_state=active_doc ? 3'd0 : (state==R_FAULT)?3'd5:(state==R_IDLE)?3'd0:
                       (state>=R_STOP_DRAIN)?3'd3:3'd2;
    assign r_rt_valid=(state==R_STOP_BANG||state==R_STOP_QUERY||state==R_STOP_RESET||
                       state==R_REARM_QUERY);
    assign r_rt_data=(state==R_STOP_BANG)?8'h21:(state==R_STOP_RESET)?8'h18:8'h3f;
    assign R_rt_done=!active_doc && rt_inflight && tx_done;
    wire d_tick=(d_tick_count==DOC_MS_DIV-1);
    wire d_cancelling=(state>=D_C_DRAIN);
    wire d_final_phase=(state>=D_FINAL_QUERY && state<=D_FINAL_STATUS);
    wire d_rearm_phase=(state>=D_R_QUERY && state<=D_R_STATUS);
    // The motion-progress lease applies while streaming or preparing a D_line.
    // Once the final status poll is active, only the dedicated final/status
    // timers may fail the job; otherwise a long-but-valid GRBL Idle response
    // would be misreported as the generic progress timeout.
    wire d_normal_fault=D_busy && !d_cancelling &&
        (D_fault || rx_error || !link_ready || p_error || p_alarm || p_overflow || p_reset ||
         (d_tick && (d_job_ms>=DOC_JOB_MS-1 ||
          ((!d_final_phase) && d_progress_ms>=DOC_PROGRESS_MS-1) ||
          (d_final_phase && d_final_ms>=DOC_FINAL_MS-1) ||
          (d_status_pending && response_timer>=DOC_STATUS_MS-1))));
    assign D_busy=owner_valid && owner_doc && (state!=D_IDLE);
    assign D_job_state=!active_doc ? d_terminal_state : d_cancelling ? (d_cancel_fault?3'd5:3'd6) :
                     d_final_phase?3'd1:D_busy?3'd2:d_terminal_state;
    assign D_line_ready=(active_doc && state==D_READY && !D_cancel && !D_fault);
    assign d_tx_valid=(state==D_SEND && !D_cancel && !d_normal_fault);
    assign d_tx_data=(byte_index==payload_length)?8'h0a:payload[7:0];
    assign d_rt_valid=(state==D_FINAL_QUERY || state==D_C_BANG || state==D_C_QUERY || state==D_C_RESET || state==D_R_QUERY) &&
                    !(D_cancel && !d_cancelling);
    assign d_rt_data=(state==D_C_BANG)?8'h21:(state==D_C_RESET)?8'h18:8'h3f;
    always @* begin
        r_tx_valid=0;r_tx_data=0;
        if(link_ready && R_profile_valid && !R_abort && !report_stop)begin
            if(state==R_SEND)begin
                r_tx_valid=1;
                r_tx_data=(byte_index==payload_length)?8'h0a:payload[7:0];
            end
        end
    end

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            owner_valid<=0;owner_doc<=0;
            state<=R_IDLE;payload<=0;payload_length<=0;byte_index<=0;report_last<=0;
            response_timer<=0;
            parser_clear<=1;R_done<=0;R_error<=0;R_error_code<=0;
            R_acked_lines<=0;R_line_done<=0;
            inflight<=0;rt_inflight<=0;R_recovery_required<=0;r_stop_fault<=0;
            state<=D_IDLE;payload<=0;payload_length<=0;byte_index<=0;
            inflight<=0;parser_clear<=1;d_cancel_fault<=0;d_status_pending<=0;d_terminal_state<=0;
            d_first_query<=0;d_final_idle_seen<=0;d_stop_seen<=0;d_reset_pending<=0;
            d_tick_count<=0;d_job_ms<=0;d_progress_ms<=0;d_final_ms<=0;d_query_ms<=0;response_timer<=0;
            D_line_done<=0;D_done<=0;D_error<=0;D_cancelled<=0;D_recovery_required<=0;
            D_error_code<=0;D_acked_lines<=0;

        end else begin
            // Pulse outputs clear even while the other producer owns the UART.
            R_done<=0;R_line_done<=0;D_done<=0;D_line_done<=0;D_error<=0;D_cancelled<=0;
            // Preserve the original document millisecond divider phase even
            // while report mode owns the shared datapath.
            if(d_tick)d_tick_count<=0;else d_tick_count<=d_tick_count+1'b1;
            if(active_doc && R_clear && !report_stop)begin R_error<=0;R_error_code<=0;end
            if(!owner_valid)begin
                if(doc_claim && !R_recovery_required)begin owner_valid<=1;owner_doc<=1;end
                else if(I_report_claim || R_start || R_stop || R_rearm || R_recovery_required || p_reset)begin
                    owner_valid<=1;owner_doc<=0;
                end
            end else if(state==0 && !inflight && !rt_inflight && !fmt_busy && !fmt_done && !fmt_start && !p_reset &&
                !(owner_doc?D_recovery_required:R_recovery_required) &&
                !(owner_doc?I_doc_owner:I_report_claim) &&
                !R_done && !D_done && !R_start && !D_start && !R_stop && !D_reset_job)begin
                owner_valid<=0;
            end
            // IMAGE/PLAN reserves the document owner before its streamer is
            // busy. The released reporter still watched Reset in this epoch.
            // Retain that report-side lock, then let the existing admission
            // guard abort preparation (including a simultaneous DRAW entry).
            if(active_doc && state==D_IDLE && !D_recovery_required && !D_reset_job && p_reset)begin
                owner_valid<=1;owner_doc<=0;state<=R_FAULT;
                R_error<=1;R_error_code<=R_ERR_RESET;R_recovery_required<=1;
                parser_clear<=1;response_timer<=0;
            end else if(active_doc)begin
            D_line_done<=0;D_done<=0;D_error<=0;D_cancelled<=0;parser_clear<=0;
            if(tx_done)inflight<=0;
            if((d_tx_valid&&tx_ready)||(d_rt_valid&&rt_ready))inflight<=1;
            if(D_busy && d_tick)begin
                d_job_ms<=d_job_ms+1'b1;d_progress_ms<=d_progress_ms+1'b1;
                if(d_final_phase || d_cancelling)d_final_ms<=d_final_ms+1'b1;
                if(d_final_phase || d_cancelling)d_query_ms<=d_query_ms+1'b1;
                if(d_status_pending)response_timer<=response_timer+1'b1;
            end
            // Only a complete response in the current query epoch refreshes
            // the status deadline; repeated '?' cannot keep it alive forever.
            if(p_status && d_status_pending)begin
                d_status_pending<=0;response_timer<=0;d_progress_ms<=0;
                if(d_final_phase && p_idle)d_final_idle_seen<=1;
                if(d_cancelling && (p_idle || p_hold0))d_stop_seen<=1;
            end
            if(D_rearm && state==D_IDLE && D_recovery_required)begin
                // A cached Idle from the old epoch is not proof of current
                // machine state. Require a fresh response before rearming.
                parser_clear<=1;d_status_pending<=0;response_timer<=0;d_query_ms<=0;
                state<=D_R_QUERY;D_recovery_required<=1;D_error_code<=0;
            end

            if(d_reset_request || (D_busy && !d_cancelling && (D_cancel || d_normal_fault)))begin
                state<=D_C_DRAIN;D_recovery_required<=1;parser_clear<=1;
                d_cancel_fault<=!D_cancel&&!d_reset_request;d_reset_pending<=d_reset_request;d_status_pending<=0;response_timer<=0;d_query_ms<=0;d_final_ms<=0;
                d_stop_seen<=0;d_final_idle_seen<=0;
                if(D_cancel||d_reset_request)D_error_code<=0;
                else if(D_fault)D_error_code<=D_fault_code;
                else if(rx_error)D_error_code<=8'h21;
                else if(!link_ready)D_error_code<=8'h22;
                else if(p_error)D_error_code<=8'h23;
                else if(p_alarm)D_error_code<=8'h24;
                else if(p_overflow)D_error_code<=8'h25;
                else if(p_reset)D_error_code<=8'h2d;
                else if(d_job_ms>=DOC_JOB_MS-1)D_error_code<=8'h26;
                else if(d_progress_ms>=DOC_PROGRESS_MS-1)D_error_code<=8'h27;
                else if(d_final_ms>=DOC_FINAL_MS-1)D_error_code<=8'h28;
                else D_error_code<=8'h29;
            end else if(d_cancelling && d_tick &&
                        ((d_status_pending && response_timer>=DOC_STATUS_MS-1) || d_final_ms>=DOC_FINAL_MS-1))begin
                // No proof of a stopped machine: do not send a queue reset or
                // claim pen-up. Operator recovery remains mandatory.
                state<=D_IDLE;D_error<=1;D_error_code<=8'h2a;D_recovery_required<=1;d_terminal_state<=5;
                parser_clear<=1;d_status_pending<=0;
            end else begin
                case(state)
                    D_IDLE:if(D_start && !D_recovery_required)begin
                        D_acked_lines<=0;d_job_ms<=0;d_progress_ms<=0;d_final_ms<=0;
                        d_query_ms<=0;response_timer<=0;d_status_pending<=0;parser_clear<=1;
                        D_error_code<=0;d_cancel_fault<=0;d_terminal_state<=2;
                        d_first_query<=1;d_final_idle_seen<=0;d_stop_seen<=0;
                        // The UART guard may describe an old Idle. A fresh
                        // query is mandatory before the first new G-code,
                        // especially after a Ctrl-X/D_rearm response epoch.
                        if(link_ready)state<=D_FINAL_QUERY;
                        else begin D_error<=1;D_error_code<=8'h20;d_terminal_state<=5;end
                    end
                    D_READY:begin
                        if(D_line_valid)begin
                            if(D_length==0 || D_length>64)begin
                                state<=D_C_DRAIN;d_cancel_fault<=1;D_recovery_required<=1;D_error_code<=8'h2b;
                            end else begin
                                payload<=D_line;payload_length<=D_length;byte_index<=0;state<=D_SEND;
                            end
                        end else if(D_finish)begin
                            // Producer asserts D_finish only after the final
                            // D_line_done. Every D_line, including return/newline,
                            // has therefore received its own GRBL ok.
                            D_done<=1;state<=D_IDLE;d_terminal_state<=4;
                            D_recovery_required<=0;D_error_code<=0;
                            d_status_pending<=0;parser_clear<=1;
                        end
                    end
                    D_SEND:if(tx_ready)state<=D_BYTE_WAIT;
                    D_BYTE_WAIT:if(tx_done)begin
                        if(byte_index==payload_length)begin state<=D_ACK_WAIT;parser_clear<=1;end
                        else begin byte_index<=byte_index+1'b1;payload<={8'd0,payload[511:8]};state<=D_SEND;end
                    end
                    D_ACK_WAIT:if(p_ok)begin
                        D_acked_lines<=D_acked_lines+1'b1;D_line_done<=1;d_progress_ms<=0;state<=D_READY;
                    end
                    D_FINAL_QUERY:if(rt_ready)state<=D_FINAL_QUERY_WAIT;
                    D_FINAL_QUERY_WAIT:if(tx_done)begin
                        if(!d_status_pending)begin response_timer<=0;d_status_pending<=1;end
                        // A clear on the first query excludes pre-existing
                        // partial status. Subsequent polls preserve a response
                        // already arriving at the UART.
                        if(d_first_query)begin parser_clear<=1;d_first_query<=0;end
                        d_query_ms<=0;state<=D_FINAL_STATUS;
                    end
                    D_FINAL_STATUS:begin
                        if(!inflight && (d_final_idle_seen || (p_status && p_idle && d_status_pending)))begin
                            d_status_pending<=0;parser_clear<=1;d_final_idle_seen<=0;
                            // This query epoch is reachable only from D_start.
                            // Normal final-ok completion exits D_READY directly.
                            state<=D_READY;d_progress_ms<=0;
                        end else if(d_tick && d_query_ms>=DOC_QUERY_MS-1)state<=D_FINAL_QUERY;
                    end
                    D_C_DRAIN:if(!inflight)state<=D_C_BANG;
                    D_C_BANG:if(rt_ready)state<=D_C_BANG_WAIT;
                    D_C_BANG_WAIT:if(tx_done)begin
                        state<=D_C_QUERY;parser_clear<=1;d_query_ms<=0;
                    end
                    D_C_QUERY:if(rt_ready)state<=D_C_QUERY_WAIT;
                    D_C_QUERY_WAIT:if(tx_done)begin
                        if(!d_status_pending)begin
                            response_timer<=0;d_status_pending<=1;parser_clear<=1;
                        end
                        d_query_ms<=0;state<=D_C_STATUS;
                    end
                    D_C_STATUS:begin
                        if(!inflight && (d_stop_seen || (p_status && d_status_pending && (p_idle || p_hold0))))begin
                            state<=D_C_RESET;d_status_pending<=0;parser_clear<=1;
                        end else if(d_tick && d_query_ms>=DOC_QUERY_MS-1)state<=D_C_QUERY;
                    end
                    D_C_RESET:if(rt_ready)state<=D_C_RESET_WAIT;
                    D_C_RESET_WAIT:if(tx_done)begin
                        state<=D_IDLE;parser_clear<=1;d_status_pending<=0;
                        if(d_reset_pending)begin
                            // A task reset reuses the confirmed stop/reset
                            // sequence, then requires fresh post-reset Idle.
                            state<=D_R_QUERY;D_recovery_required<=1;d_query_ms<=0;response_timer<=0;
                        end else if(d_cancel_fault)begin D_error<=1;d_terminal_state<=5;end
                        else begin D_cancelled<=1;d_terminal_state<=6;end
                    end
                    D_R_QUERY:if(rt_ready)state<=D_R_QUERY_WAIT;
                    D_R_QUERY_WAIT:if(tx_done)begin
                        parser_clear<=1;d_status_pending<=1;response_timer<=0;d_query_ms<=0;state<=D_R_STATUS;
                    end
                    D_R_STATUS:begin
                        if(d_status_pending && p_status)begin
                            d_status_pending<=0;response_timer<=0;
                            if(p_idle)begin
                                D_recovery_required<=0;parser_clear<=1;state<=D_IDLE;D_error_code<=0;
                                if(d_reset_pending)begin D_cancelled<=1;d_terminal_state<=6;d_reset_pending<=0;end
                            end
                        end else if(d_tick && response_timer>=DOC_STATUS_MS-1)begin
                            state<=D_IDLE;D_error<=1;D_error_code<=8'h2c;D_recovery_required<=1;d_terminal_state<=5;parser_clear<=1;
                        end else if(d_tick)response_timer<=response_timer+1'b1;
                    end
                    default:begin state<=D_IDLE;D_error<=1;D_error_code<=8'h2f;D_recovery_required<=1;d_terminal_state<=5;end
                endcase
            end

            end else begin
            parser_clear<=0;R_done<=0;R_line_done<=0;
            if(r_tx_valid && tx_ready)inflight<=1;
            if(tx_done)begin inflight<=0; if(rt_inflight)rt_inflight<=0; end
            if(p_reset && !report_stop && (state<=R_FAULT || state==R_DONE_PENDING))begin
                // An external Reset may have discarded queued motion and
                // modal coordinates. Never continue or replay the old job.
                // The expected banner in KEY4 stop/reset/rearm is outside
                // these states and remains gated by a fresh Idle response.
                state<=R_FAULT;R_error<=1;R_error_code<=R_ERR_RESET;R_recovery_required<=1;parser_clear<=1;
            end else if(R_clear && !R_busy && !report_stop)begin
                state<=R_IDLE;R_error<=0;R_error_code<=0;parser_clear<=1;
                response_timer<=0;
            end else if(R_rearm && !report_stop && (state==R_IDLE || state==R_FAULT) && R_recovery_required && link_ready && R_profile_valid)begin
                // A rearm is a fresh status epoch; a cached Idle is not
                // sufficient proof that the machine is currently safe.
                R_error<=0;R_error_code<=0;
                parser_clear<=1;response_timer<=0;
                R_recovery_required<=1;state<=R_REARM_QUERY;
            end else if(report_stop && (state<R_STOP_DRAIN || state==R_DONE_PENDING))begin
                // Stop requests never replay a motion line. Drain the one
                // byte already accepted by the UART, then use the realtime
                // GRBL hold/status/reset sequence.
                state<=R_STOP_DRAIN;r_stop_fault<=0;parser_clear<=1;R_recovery_required<=1;R_error<=0;R_error_code<=0;
                response_timer<=0;
            end else if(R_busy && (R_abort || !link_ready || !R_profile_valid ||
                         rx_error || p_error || p_alarm || p_overflow))begin
                state<=R_FAULT;R_error<=1;R_recovery_required<=1;
                if(R_abort)R_error_code<=R_ERR_ABORT;
                else if(rx_error)R_error_code<=R_ERR_UART;
                else if(p_error || p_alarm || p_overflow)R_error_code<=R_ERR_RESPONSE;
                else if(!link_ready)R_error_code<=R_ERR_LINK;
                else if(!R_profile_valid)R_error_code<=R_ERR_PROFILE;
                else R_error_code<=R_ERR_STATUS_TIMEOUT;
            end else begin
                // Reachable wait states override this clear with their own
                // counter update below. The retired normal-final query chain
                // had no incoming edge after last-ok completion was enabled.
                if(R_busy)response_timer<=0;
                case(state)
                    R_IDLE:if(R_start && !R_recovery_required)begin
                        if(!R_profile_valid || !link_ready)begin
                            state<=R_FAULT;R_error<=1;R_recovery_required<=1;
                            R_error_code<=!R_profile_valid?R_ERR_PROFILE:R_ERR_LINK;
                        end else begin
                            state<=R_LINE;R_error<=0;R_error_code<=0;R_acked_lines<=0;
                            response_timer<=0;
                            parser_clear<=1;
                        end
                    end
                    R_LINE:if(R_line_valid)begin
                        if(R_length==0 || R_length>63)begin
                            state<=R_FAULT;R_error<=1;R_error_code<=R_ERR_LINE;R_recovery_required<=1;
                        end else begin
                            payload<=R_line;payload_length<=R_length;
                            report_last<=R_line_last;byte_index<=0;state<=R_SEND;response_timer<=0;
                        end
                    end
                    R_SEND:if(r_tx_valid && tx_ready)begin
                        if(byte_index==payload_length)state<=R_DRAIN;
                        else begin payload<={8'd0,payload[511:8]};byte_index<=byte_index+1'b1;end
                    end
                    R_DRAIN:if(tx_done)begin state<=R_ACK;response_timer<=0;end
                    R_ACK:begin
                        if(p_ok)begin
                            R_acked_lines<=R_acked_lines+1'b1;R_line_done<=1;response_timer<=0;
                            if(report_last)begin
                                // All normal report paths complete on the
                                // last line R_ACK. The extra state exposes the
                                // updated R_ACK counter before R_done pulses.
                                state<=R_DONE_PENDING;R_recovery_required<=0;
                            end else state<=R_LINE;
                        end else if(ack_timer>=REPORT_ACK_TIMEOUT_CYCLES-1)begin
                            state<=R_FAULT;R_error<=1;R_error_code<=R_ERR_ACK_TIMEOUT;R_recovery_required<=1;
                        end else response_timer<=ack_timer+1'b1;
                    end
                    R_DONE_PENDING:begin
                        R_done<=1;state<=R_IDLE;R_recovery_required<=0;R_error<=0;R_error_code<=0;
                        parser_clear<=1;
                    end
                    R_STOP_DRAIN:if(!inflight)state<=R_STOP_BANG;
                    R_STOP_BANG:if(r_rt_valid && rt_ready)begin rt_inflight<=1;state<=R_STOP_BANG_WAIT;end
                    R_STOP_BANG_WAIT:if(tx_done)begin parser_clear<=1;state<=R_STOP_QUERY;end
                    R_STOP_QUERY:if(r_rt_valid && rt_ready)begin rt_inflight<=1;state<=R_STOP_QUERY_WAIT;end
                    R_STOP_QUERY_WAIT:if(tx_done)begin parser_clear<=1;response_timer<=0;state<=R_STOP_STATUS;end
                    R_STOP_STATUS:begin
                        if(p_hold0 || p_idle)begin
                            state<=R_STOP_RESET;parser_clear<=1;
                        end else if(status_timer>=REPORT_STATUS_TIMEOUT_CYCLES-1)begin
                            state<=R_FAULT;R_error<=1;R_error_code<=R_ERR_STATUS_TIMEOUT;R_recovery_required<=1;
                        end else response_timer<=status_timer+1'b1;
                    end
                    R_STOP_RESET:if(r_rt_valid && rt_ready)begin rt_inflight<=1;state<=R_STOP_RESET_WAIT;end
                    R_STOP_RESET_WAIT:if(tx_done)begin
                        // KEY4 is a safe task reset, not a raw FPGA/POR
                        // reset. Clear/rearm only after a new post-Ctrl-X
                        // Idle status; unknown or Alarm remains locked.
                        state<=R_REARM_QUERY;R_recovery_required<=1;R_done<=0;
                        parser_clear<=1;response_timer<=0;
                    end
                    R_REARM_QUERY:if(r_rt_valid && rt_ready)begin rt_inflight<=1;state<=R_REARM_WAIT;end
                    R_REARM_WAIT:if(tx_done)begin parser_clear<=1;response_timer<=0;state<=R_REARM_STATUS;end
                    R_REARM_STATUS:begin
                        if(p_idle)begin R_recovery_required<=0;parser_clear<=1;state<=R_IDLE;end
                        else if(status_timer>=REPORT_STATUS_TIMEOUT_CYCLES-1)begin
                            state<=R_FAULT;R_error<=1;R_error_code<=R_ERR_STATUS_TIMEOUT;R_recovery_required<=1;
                        end else response_timer<=status_timer+1'b1;
                    end
                    R_FAULT:begin end
                    default:begin state<=R_FAULT;R_error<=1;R_error_code<=R_ERR_LINE;end
                endcase
            end

            end
        end
    end
endmodule
