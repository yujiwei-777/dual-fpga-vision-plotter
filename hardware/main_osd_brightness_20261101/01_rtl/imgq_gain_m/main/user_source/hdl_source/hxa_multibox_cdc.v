// One-outstanding bundled-data CDC mailbox for HXA1 type18 results.
// Only request/ack and link state pass through 2-FF synchronizers. The
// source held bus is NEVER modified until the pixel side acknowledges its
// local copy. Complete snapshots become visible at frame boundaries only.
module hxa_multibox_cdc (
    input  wire         I_src_clk, I_src_rst_n,
    input  wire         I_src_online,
    input  wire         I_src_valid,
    input  wire         I_src_toggle,
    input  wire [2:0]   I_src_count,
    input  wire [511:0] I_src_data,
    input  wire [31:0]  I_src_job,
    input  wire         I_px_clk, I_px_rst_n,
    input  wire         I_px_frame_start,
    input  wire         I_px_enable,
    output wire         O_valid,
    output wire [2:0]   O_count,
    output wire [511:0] O_data,
    output wire [31:0]  O_job,
    output reg          O_toggle
);
    // Restart both ends if either clock domain resets: an old request may
    // never be mistaken for a new session after an independent reset.
    wire mailbox_rst_n = I_src_rst_n && I_px_rst_n;
    wire src_reset_n, px_reset_n;
    reset_sync u_src_reset(.I_clk(I_src_clk),.I_async_rst_n(mailbox_rst_n),.O_rst_n(src_reset_n));
    reset_sync u_px_reset(.I_clk(I_px_clk),.I_async_rst_n(mailbox_rst_n),.O_rst_n(px_reset_n));
    reg req, ack;
    (* ASYNC_REG = "TRUE" *) reg ack_s1, ack_s2;
    (* ASYNC_REG = "TRUE" *) reg req_s1, req_s2;
    (* ASYNC_REG = "TRUE" *) reg online_s1, online_s2;
    reg source_seen, source_armed, dirty, latest_valid, source_online_d;
    reg [547:0] held;
    reg capture_wait;
    reg pending;
    reg [547:0] staged;
    assign O_valid=staged[547];
    assign O_job=staged[546:515];
    assign O_count=staged[514:512];
    assign O_data=staged[511:0];
    // The producer can retain its last toggle/data when only the other
    // domain resets. Baseline the toggle after coordinated reset release;
    // only a subsequent arrival may recreate a mailbox transaction.
    wire source_event = source_armed && (I_src_toggle != source_seen);

    always @(posedge I_src_clk or negedge src_reset_n) begin
        if (!src_reset_n) begin
            req<=0;ack_s1<=0;ack_s2<=0;source_seen<=0;source_armed<=0;
            source_online_d<=0;dirty<=0;latest_valid<=0;held<=0;
        end else begin
            ack_s1<=ack;ack_s2<=ack_s1;
            source_armed<=1;
            source_seen<=I_src_toggle;source_online_d<=I_src_online;
            if (!I_src_online) begin
                latest_valid<=0;
                if (source_online_d) dirty<=1;
            end else if (source_event) begin
                latest_valid<=I_src_valid;dirty<=1;
            end
            // hxa_main_link's source outputs retain the most recent result.
            // Arrivals while busy coalesce into the latest complete snapshot.
            // No new snapshot can overwrite held before ACK returns.
            if ((req==ack_s2) && dirty && !source_event &&
                !(source_online_d && !I_src_online)) begin
                held<={latest_valid && I_src_online,I_src_job,
                       I_src_count,I_src_data};
                req<=~req;
                dirty<=0;
            end
        end
    end

    always @(posedge I_px_clk or negedge px_reset_n) begin
        if (!px_reset_n) begin
            req_s1<=0;req_s2<=0;online_s1<=0;online_s2<=0;
            ack<=0;capture_wait<=0;pending<=0;
            staged<=0;O_toggle<=0;
        end else begin
            req_s1<=req;req_s2<=req_s1;
            online_s1<=I_src_online;online_s2<=online_s1;
            // The source keeps held frozen until ACK. Wait an extra pixel
            // clock after req_s2, then read it directly at the frame boundary.
            // ACK is delayed until that commit, so a third full-width staging
            // register bank is unnecessary and the bundled bus cannot tear.
            if ((req_s2!=ack) && !capture_wait && !pending) capture_wait<=1;
            if (capture_wait) begin
                pending<=1;
                capture_wait<=0;
            end
            if (I_px_frame_start) begin
                if (!I_px_enable || !online_s2) begin
                    staged<=0;
                    O_toggle<=~O_toggle;
                end else if (pending) begin
                    staged<={held[547:515],
                             held[547] ? ((held[514:512]>4)?3'd4:held[514:512]) : 3'd0,
                             held[511:0]};
                    O_toggle<=~O_toggle;
                end
                // Disabled/disconnected frames also consume the mailbox;
                // old results must not be replayed when SW1 is re-enabled.
                if (pending) begin ack<=req_s2;pending<=0;end
            end
        end
    end
endmodule
