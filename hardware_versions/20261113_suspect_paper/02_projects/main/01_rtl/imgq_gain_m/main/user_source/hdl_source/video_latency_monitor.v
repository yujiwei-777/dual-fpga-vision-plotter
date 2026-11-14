// Passive RAW-to-HDMI provenance monitor. Never feeds video/DDR control.
// Quality closes at the next RAW SOF: this checks the ENTIRE ISP word span,
// including late extra words, rather than declaring success at word 172800.
module video_latency_monitor #(
    parameter integer FRAME_PIXELS = 921600,
    parameter integer TICK_CYCLES = 5000
)(
    input wire I_sys_clk,I_sys_rst_n,I_cam_clk,I_cam_rst_n,
    input wire I_guard_sof,I_guard_done,I_guard_error,I_lane_error,
    input wire I_isp_valid,I_isp_sof,I_capture_overflow,
    input wire I_ddr_clk,I_ddr_rst_n,I_vi_wr_en,
    input wire [24:0] I_vi_addr,
    input wire I_write_retire,
    input wire [24:0] I_write_retire_addr,
    input wire I_vo_frame_start,
    input wire [1:0] I_vo_bank,
    input wire I_vo_reset,I_vo_burst,I_vo_rd_en,I_vo_rd_return,
    input wire [10:0] I_vo_pending,
    input wire I_px_clk,I_px_rst_n,I_hdmi_vs,I_hdmi_de,I_vo_underflow,
    output reg O_report_valid,
    output reg [15:0] O_report_frame,O_report_tenth_ms,
    output reg O_report_toggle
);
    localparam integer WORDS = FRAME_PIXELS*3/16;
    localparam integer CW = $clog2(WORDS+1);
    localparam integer PW = $clog2(FRAME_PIXELS+1);
    // A reset of ANY participant cancels EVERY outstanding provenance token.
    // Assertion is asynchronous, while release is synchronized locally by
    // the two-stage registers below.  The wrapper supplies S_pll_lock to all
    // four inputs, so no 23.8 MHz reset-controller path reaches this monitor.
    // Keep the named provenance reset net visible to the physical audit even
    // when the wrapper currently drives all four monitor inputs from the same
    // PLL-lock source.
    (* KEEP="TRUE", DONT_TOUCH="TRUE" *) wire all_reset_n =
        I_sys_rst_n & I_cam_rst_n & I_ddr_rst_n & I_px_rst_n;
    (* ASYNC_REG="TRUE", KEEP="TRUE" *) reg [1:0] sys_release,cam_release,ddr_release,px_release;
    always @(posedge I_sys_clk or negedge all_reset_n)
        if(!all_reset_n) sys_release<=0; else sys_release<={sys_release[0],1'b1};
    always @(posedge I_cam_clk or negedge all_reset_n)
        if(!all_reset_n) cam_release<=0; else cam_release<={cam_release[0],1'b1};
    always @(posedge I_ddr_clk or negedge all_reset_n)
        if(!all_reset_n) ddr_release<=0; else ddr_release<={ddr_release[0],1'b1};
    always @(posedge I_px_clk or negedge all_reset_n)
        if(!all_reset_n) px_release<=0; else px_release<={px_release[0],1'b1};
    wire sr=sys_release[1],cr=cam_release[1],dr=ddr_release[1],pr=px_release[1];
    reg [$clog2(TICK_CYCLES)-1:0] tick_div;
    reg [15:0] tick_binary;
    (* KEEP="TRUE" *) reg [15:0] tick_gray;
    wire [15:0] tick_next = tick_binary+16'd1;
    always @(posedge I_sys_clk or negedge sr) begin
        if(!sr) begin tick_div<=0;tick_binary<=0;tick_gray<=0;end
        else if(tick_div==TICK_CYCLES-1) begin
            tick_div<=0;tick_binary<=tick_next;tick_gray<=tick_next^(tick_next>>1);
        end else tick_div<=tick_div+1'b1;
    end
    (* ASYNC_REG="TRUE", KEEP="TRUE" *) reg [15:0] cam_gray_meta,cam_gray_sync;
    (* ASYNC_REG="TRUE", KEEP="TRUE" *) reg [15:0] px_gray_meta,px_gray_sync;
    (* ASYNC_REG="TRUE", KEEP="TRUE" *) reg [15:0] ddr_gray_meta,ddr_gray_sync;
    always @(posedge I_cam_clk or negedge cr)
        if(!cr) begin cam_gray_meta<=0;cam_gray_sync<=0;end
        else begin cam_gray_meta<=tick_gray;cam_gray_sync<=cam_gray_meta;end
    always @(posedge I_px_clk or negedge pr)
        if(!pr) begin px_gray_meta<=0;px_gray_sync<=0;end
        else begin px_gray_meta<=tick_gray;px_gray_sync<=px_gray_meta;end
    always @(posedge I_ddr_clk or negedge dr)
        if(!dr) begin ddr_gray_meta<=0;ddr_gray_sync<=0;end
        else begin ddr_gray_meta<=tick_gray;ddr_gray_sync<=ddr_gray_meta;end
    function [15:0] ungray;
        input [15:0] g; integer k;
        begin ungray[15]=g[15];for(k=14;k>=0;k=k-1) ungray[k]=ungray[k+1]^g[k];end
    endfunction
    wire [15:0] cam_time=ungray(cam_gray_sync),px_time=ungray(px_gray_sync);
    wire [15:0] ddr_time=ungray(ddr_gray_sync);

    reg [15:0] cam_frame;
    (* KEEP="TRUE" *) reg raw_heartbeat;
    reg cam_active,cam_done,cam_bad,cam_isp_seen;
    reg [CW-1:0] cam_words;
    wire start_busy,quality_busy;
    wire [31:0] start_data;
    wire [16:0] quality_data;
    wire start_pulse,quality_pulse;
    // Raw frame n metadata is sent before its first DDR FIFO burst.
    vl_mailbox #(.WIDTH(32)) u_start (
        .s_clk(I_cam_clk),.s_rst_n(cr),.s_send(I_guard_sof),
        .s_data({cam_frame+16'd1,cam_time}),.s_busy(start_busy),
        .d_clk(I_ddr_clk),.d_rst_n(dr),.d_pulse(start_pulse),.d_data(start_data));
    vl_mailbox #(.WIDTH(17)) u_quality (
        .s_clk(I_cam_clk),.s_rst_n(cr),.s_send(I_guard_sof && cam_active),
        .s_data({cam_frame,cam_done && cam_isp_seen && !cam_bad &&
            !I_capture_overflow && !I_lane_error && !I_guard_error &&
            !(I_isp_valid && !I_isp_sof) && cam_words==WORDS}),
        .s_busy(quality_busy),.d_clk(I_ddr_clk),.d_rst_n(dr),
        .d_pulse(quality_pulse),.d_data(quality_data));
    always @(posedge I_cam_clk or negedge cr) begin
        if(!cr) begin raw_heartbeat<=0;cam_frame<=0;cam_active<=0;cam_done<=0;cam_bad<=0;
            cam_isp_seen<=0;cam_words<=0;end
        else if(I_guard_sof) begin
            raw_heartbeat<=~raw_heartbeat;
            cam_frame<=cam_frame+1'b1;cam_active<=1;cam_done<=0;
            // At an ambiguous RAW boundary, conservatively fault both the
            // closing frame and the newly opened frame. A one-cycle PHY
            // lane error on this edge must not escape the new frame latch.
            cam_bad<=start_busy | quality_busy | (I_isp_sof && !I_isp_valid) |
                I_guard_error | I_lane_error | I_capture_overflow;
            cam_isp_seen<=I_isp_sof;
            cam_words<=I_isp_valid ? 1 : 0;
            if(I_isp_valid && !I_isp_sof) cam_bad<=1;
        end else if(cam_active) begin
            if(I_guard_done) cam_done<=1;
            if(I_guard_error || I_lane_error || I_capture_overflow) cam_bad<=1;
            if(I_isp_sof) begin
                if(cam_isp_seen || !I_isp_valid || cam_words!=0) cam_bad<=1;
                cam_isp_seen<=1;
            end
            if(I_isp_valid) begin
                if(!cam_isp_seen && !I_isp_sof) cam_bad<=1;
                // Saturate at the required total. The first extra valid
                // word faults immediately and can never wrap back to good.
                if(cam_words!=WORDS) cam_words<=cam_words+1'b1;
                else cam_bad<=1;
            end
        end
    end

    // Four actual DDR slots. Register arrays deliberately avoid inferred RAM.
    reg [15:0] slot_frame[0:3],slot_time[0:3];
    reg [3:0] slot_known,slot_issued,slot_retired,slot_quality;
    // One shared expiry subtractor replaces four parallel carry chains.
    // A reload checks its selected slot NOW; otherwise visit the four slots
    // in order. A reload pauses (does not skip) the background scan.
    reg [1:0] expiry_scan;
    wire [1:0] expiry_bank=I_vo_frame_start ? I_vo_bank : expiry_scan;
    wire [15:0] expiry_age=ddr_time-slot_time[expiry_bank];
    reg [31:0] pending_start;
    reg pending_start_valid;
    reg ddr_source_alive;reg [15:0] ddr_last_source;
    wire [15:0] ddr_source_age=ddr_time-ddr_last_source;
    reg [1:0] write_bank;
    reg [24:0] expected_addr;
    reg write_active,write_bad;
    wire at_base=(I_vi_addr==25'd0)||(I_vi_addr==25'd7000000)||
        (I_vi_addr==25'd14000000)||(I_vi_addr==25'd21000000);
    // Strict contiguous addresses prove the number of words without a
    // duplicate counter. An issued tail or a sticky fault forbids extra data.
    wire at_end=(I_vi_addr==25'd0+(WORDS-1)*8)||
        (I_vi_addr==25'd7000000+(WORDS-1)*8)||
        (I_vi_addr==25'd14000000+(WORDS-1)*8)||
        (I_vi_addr==25'd21000000+(WORDS-1)*8);
    // Experimental exact-base decode: only sequential writes may inherit
    // a bank; every other non-base address loses all trustworthy ownership.
    wire [1:0] addr_bank=(I_vi_addr==25'd21000000)?3:
        (I_vi_addr==25'd14000000)?2:(I_vi_addr==25'd7000000)?1:0;
    wire sequential_write=write_active && !write_bad &&
        !slot_issued[write_bank] && I_vi_addr==expected_addr;
    wire known_write_bank=at_base || sequential_write;
    wire [1:0] touched_bank=at_base ? addr_bank : write_bank;
    wire unexpected_write=I_vi_wr_en && !known_write_bank;
    function [24:0] bank_base;
        input [1:0] b;
        begin case(b) 0:bank_base=0;1:bank_base=7000000;2:bank_base=14000000;
            default:bank_base=21000000;endcase end
    endfunction
    reg [1:0] read_bank;
    reg read_active,vo_reset_d;
    (* KEEP="TRUE" *) reg read_bad;
    reg [10:0] old_pending;
    (* KEEP="TRUE" *) reg read_error_toggle;
    wire selected_good=slot_known[I_vo_bank] && slot_issued[I_vo_bank] &&
        slot_retired[I_vo_bank] && slot_quality[I_vo_bank] &&
        !(I_vi_wr_en && (!known_write_bank || touched_bank==I_vo_bank)) &&
        !I_vo_burst && !expiry_age[15];
    wire display_busy,display_pulse;
    wire [32:0] display_data;
    vl_mailbox #(.WIDTH(33)) u_display (
        .s_clk(I_ddr_clk),.s_rst_n(dr),.s_send(I_vo_frame_start),
        .s_data({selected_good,slot_frame[I_vo_bank],slot_time[I_vo_bank]}),
        .s_busy(display_busy),.d_clk(I_px_clk),.d_rst_n(pr),
        .d_pulse(display_pulse),.d_data(display_data));
    wire overwrite_read=I_vi_wr_en && read_active &&
        (!known_write_bank || touched_bank==read_bank);
    wire read_fault=(vo_reset_d && !I_vo_reset && old_pending!=0) ||
        (!I_vo_reset && I_vo_rd_return && old_pending!=0) || overwrite_read;
    integer j;
    always @(posedge I_ddr_clk or negedge dr) begin
        if(!dr) begin
            slot_known<=0;slot_issued<=0;slot_retired<=0;slot_quality<=0;expiry_scan<=0;
            for(j=0;j<4;j=j+1) begin slot_frame[j]<=0;slot_time[j]<=0;end
            pending_start<=0;pending_start_valid<=0;ddr_source_alive<=0;ddr_last_source<=0;
            write_bank<=0;
            expected_addr<=0;write_active<=0;write_bad<=0;
            read_bank<=0;read_active<=0;read_bad<=0;vo_reset_d<=0;
            old_pending<=0;read_error_toggle<=0;
        end else begin
            vo_reset_d<=I_vo_reset;
            // Expiration is sticky until a NEW first write binds a fresh token.
            // Old slots cannot become young again after a full tick wrap.
            if(!I_vo_frame_start) expiry_scan<=expiry_scan+1'b1;
            if(slot_known[expiry_bank] && expiry_age[15]) slot_known[expiry_bank]<=0;
            if(ddr_source_alive && (ddr_source_age[15] || ddr_source_age>=10000)) begin
                ddr_source_alive<=0;slot_known<=0;pending_start_valid<=0;
            end
            if(start_pulse) begin
                pending_start<=start_data;pending_start_valid<=1;
                ddr_last_source<=start_data[15:0];ddr_source_alive<=1;
            end
            if(quality_pulse) begin
                for(j=0;j<4;j=j+1)
                    if(slot_known[j] && slot_frame[j]==quality_data[16:1])
                        slot_quality[j]<=quality_data[0];
            end
            if(I_write_retire) begin
                for(j=0;j<4;j=j+1)
                    if(slot_known[j] && (slot_issued[j] ||
                        (I_vi_wr_en && !at_base && write_active && write_bank==j &&
                         !write_bad && at_end && I_vi_addr==expected_addr)) &&
                        I_write_retire_addr==bank_base(j)+(WORDS-1)*8)
                        slot_retired[j]<=1;
            end
            if(I_vi_wr_en) begin
                if(at_base) begin
                    // First overwritten word destroys ALL old provenance now.
                    slot_known[addr_bank]<=pending_start_valid;
                    slot_frame[addr_bank]<=pending_start[31:16];
                    slot_time[addr_bank]<=pending_start[15:0];
                    slot_issued[addr_bank]<=0;slot_retired[addr_bank]<=0;
                    slot_quality[addr_bank]<=0;
                    pending_start_valid<=0;write_bank<=addr_bank;
                    expected_addr<=I_vi_addr+25'd8;
                    write_active<=1;write_bad<=!pending_start_valid;
                end else if(write_active) begin
                    expected_addr<=expected_addr+25'd8;
                    if(!sequential_write) begin
                        write_bad<=1;slot_issued[write_bank]<=0;slot_known<=0;
                    end else if(at_end && !write_bad)
                        slot_issued[write_bank]<=1;
                end else slot_known<=0;
            end
            // Everything issued before/during FIFO reset is conservatively old.
            // Returns wholly drained in reset are harmless. Old data escaping
            // reset invalidates the frame instead of silently shifting pixels.
            if(I_vo_frame_start) begin
                read_bank<=I_vo_bank;read_active<=1;read_bad<=0;
                old_pending<=I_vo_pending + (I_vo_rd_en?11'd1:11'd0) -
                    ((I_vo_rd_return && I_vo_pending!=0)?11'd1:11'd0);
                if(display_busy || I_vo_burst || unexpected_write) begin
                    // A burst straddling address reload has no trustworthy
                    // first-word phase, even when some responses drain in reset.
                    read_bad<=1;read_error_toggle<=~read_error_toggle;
                end
            end else if(I_vo_reset) begin
                old_pending<=I_vo_pending + (I_vo_rd_en?11'd1:11'd0) -
                    ((I_vo_rd_return && I_vo_pending!=0)?11'd1:11'd0);
            end else if(I_vo_rd_return && old_pending!=0) old_pending<=old_pending-1'b1;
            if(read_active && read_fault && !read_bad) begin
                read_bad<=1;read_error_toggle<=~read_error_toggle;
            end
        end
    end

    (* ASYNC_REG="TRUE", KEEP="TRUE" *) reg error_meta,error_sync;
    (* ASYNC_REG="TRUE", KEEP="TRUE" *) reg read_bad_meta,read_bad_sync;
    reg error_seen;
    (* ASYNC_REG="TRUE", KEEP="TRUE" *) reg heartbeat_meta,heartbeat_sync;
    reg heartbeat_seen,source_alive;
    reg [15:0] heartbeat_time;
    wire [15:0] heartbeat_age=px_time-heartbeat_time;
    wire source_stale=!source_alive || heartbeat_age[15] || heartbeat_age>=10000;
    // The mailbox already holds this synchronous payload until the next
    // delivery. Keep only validity here, not a second 33-bit payload register.
    // A delivery coincident with/after first DE always invalidates the frame.
    wire [32:0] px_pending=display_data;
    reg px_pending_valid,px_pending_bad;
    reg vs_d,px_active,px_bad;
    reg [PW-1:0] px_count;
    reg [15:0] px_frame,px_delay,px_source_time;
    reg [3:0] finish_wait;
    reg finish_bad;
    wire [15:0] finish_frame=px_frame,finish_delay=px_delay;
    wire error_event=error_sync!=error_seen;
    wire [15:0] pending_age=px_time-px_pending[15:0];
    wire [15:0] source_age=px_time-px_source_time;
    wire vs_rise=I_hdmi_vs && !vs_d;
    always @(posedge I_px_clk or negedge pr) begin
        if(!pr) begin
            error_meta<=0;error_sync<=0;error_seen<=0;read_bad_meta<=0;read_bad_sync<=0;
            heartbeat_meta<=0;heartbeat_sync<=0;heartbeat_seen<=0;
            source_alive<=0;heartbeat_time<=0;
            px_pending_valid<=0;px_pending_bad<=0;
            vs_d<=0;px_active<=0;px_bad<=0;px_count<=0;
            px_frame<=0;px_delay<=0;px_source_time<=0;
            finish_wait<=0;finish_bad<=0;
            O_report_valid<=0;O_report_frame<=0;O_report_tenth_ms<=0;O_report_toggle<=0;
        end else begin
            error_meta<=read_error_toggle;error_sync<=error_meta;error_seen<=error_sync;
            read_bad_meta<=read_bad;read_bad_sync<=read_bad_meta;
            heartbeat_meta<=raw_heartbeat;heartbeat_sync<=heartbeat_meta;
            heartbeat_seen<=heartbeat_sync;
            if(heartbeat_sync!=heartbeat_seen) begin
                heartbeat_time<=px_time;source_alive<=1;
            end else if(source_alive && (heartbeat_age[15] || heartbeat_age>=10000))
                source_alive<=0; // sticky timeout: no resurrection after tick wrap
            vs_d<=I_hdmi_vs;
            if(display_pulse) begin
                // Normal video_out reload is at VS falling (line 731), well
                // after closing this monitor's old frame at VS rising (726).
                // A delivery during pixels or the completion settling window
                // has ambiguous ownership: fault that frame and discard it.
                if(px_active || I_hdmi_de || finish_wait!=0 || vs_rise) begin
                    px_pending_valid<=0;px_pending_bad<=0;
                    if(px_active) px_bad<=1;
                    if(finish_wait!=0) finish_bad<=1;
                end else begin
                    px_pending_valid<=1;px_pending_bad<=px_pending_valid;
                end
            end
            if(error_event) begin
                if(px_active) px_bad<=1;
                px_pending_bad<=1;
                if(finish_wait!=0) finish_bad<=1;
            end
            if(px_active && (I_vo_underflow || read_bad_sync)) px_bad<=1;
            if(vs_rise) begin
                if(px_active) begin
                    finish_wait<=8;
                    finish_bad<=px_bad || error_event || I_vo_underflow || read_bad_sync || I_hdmi_de || display_pulse ||
                        px_count!=FRAME_PIXELS || source_age[15] || source_stale;
                end
                px_active<=0;px_count<=0;px_bad<=0;
                // A token from a raster with no DE must not survive into a
                // later raster whose replacement metadata is missing/late.
                px_pending_valid<=0;px_pending_bad<=0;
            end else if(I_hdmi_de) begin
                if(!px_active) begin
                    px_active<=1;px_count<=1;
                    px_frame<=px_pending[31:16];px_source_time<=px_pending[15:0];
                    px_delay<=pending_age;
                    px_bad<=display_pulse || !px_pending_valid || !px_pending[32] || px_pending_bad ||
                        pending_age[15] || source_stale || I_vo_underflow || read_bad_sync || error_event;
                    px_pending_valid<=0;px_pending_bad<=0;
                end else begin
                    if(px_count!=FRAME_PIXELS) px_count<=px_count+1'b1;
                    else px_bad<=1;
                end
            end
            if(finish_wait!=0) begin
                // Any early next raster can change the aliased source data.
                // Reject it throughout settling, including the publish edge.
                if(I_hdmi_de) finish_bad<=1;
                finish_wait<=finish_wait-1'b1;
                if(finish_wait==1) begin
                    O_report_valid<=!finish_bad && !error_event && !display_pulse && !I_hdmi_de;
                    O_report_frame<=finish_frame;O_report_tenth_ms<=finish_delay;
                    O_report_toggle<=~O_report_toggle;
                end
            end
            // Stale reports must disappear even if HDMI itself stops.
            if(O_report_valid && (source_age[15] || source_stale)) begin
                O_report_valid<=0;O_report_toggle<=~O_report_toggle;
            end
        end
    end
endmodule

// Stable payload bundled-data CDC. Payload stays fixed from request through
// acknowledgement; request traverses two flops BEFORE payload is sampled.
// Constrain s_hold Q -> d_data D and s_req Q -> d_req_meta D explicitly.
module vl_mailbox #(parameter integer WIDTH=1)(
    input wire s_clk,s_rst_n,s_send,input wire [WIDTH-1:0] s_data,
    output wire s_busy,input wire d_clk,d_rst_n,
    output reg d_pulse,(* KEEP="TRUE" *) output reg [WIDTH-1:0] d_data
);
    (* KEEP="TRUE" *) reg [WIDTH-1:0] s_hold;
    (* KEEP="TRUE" *) reg s_req,d_ack;
    (* ASYNC_REG="TRUE", KEEP="TRUE" *) reg s_ack_meta,s_ack_sync,d_req_meta,d_req_sync;
    assign s_busy=s_req!=s_ack_sync;
    always @(posedge s_clk or negedge s_rst_n) begin
        if(!s_rst_n) begin s_hold<=0;s_req<=0;s_ack_meta<=0;s_ack_sync<=0;end
        else begin
            s_ack_meta<=d_ack;s_ack_sync<=s_ack_meta;
            if(s_send && !s_busy) begin s_hold<=s_data;s_req<=~s_req;end
        end
    end
    always @(posedge d_clk or negedge d_rst_n) begin
        if(!d_rst_n) begin d_req_meta<=0;d_req_sync<=0;d_ack<=0;d_data<=0;d_pulse<=0;end
        else begin
            d_req_meta<=s_req;d_req_sync<=d_req_meta;d_pulse<=0;
            if(d_req_sync!=d_ack) begin d_data<=s_hold;d_ack<=d_req_sync;d_pulse<=1;end
        end
    end
endmodule
