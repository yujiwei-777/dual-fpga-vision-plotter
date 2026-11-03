// SC500CS AE stability diagnostic. Statistics are one frame-stable bundle:
// centre-ROI weighted green Y, high-light proxy %, and all-green ROI mean Y.
// The latter includes black samples; it is not a subject segmentation result.
//
// I2C request/fall/rise handshake is unchanged. A completed group write is
// followed by three discarded statistics; the fourth rebuilds the Y filter.
// Lock/exit/recovery counters only consume eligible, post-write statistics.
module ae_auto #(
    parameter integer CLK_HZ = 24000000,
    parameter integer Y_TARGET = 128,
    // Raise the low-light entry threshold toward the 120 DN target so a
    // scene sitting around 109--115 DN is not left visibly dark.
    parameter integer Y_LO = 124,
    parameter integer Y_HI = 136,
    parameter integer CLIP_GATE = 4,
    parameter integer CLIP_HIGH = 16,
    parameter integer AE_MIN = 3,
    parameter integer AE_MAX = 2244,
    parameter integer AE_SPORT_MAX = 2244,
    parameter integer FLICKER_N = 1,
    parameter integer AG_MIN = 16,
    parameter integer AG_MAX = 143,
    parameter integer ADJ_FRAMES = 4, // retained interface; stability policy uses 3 discarded events
    parameter integer LOW_NOISE_GAIN_FIRST = 0,
    parameter integer DG_INIT_Q7 = 128,
    parameter integer DG_MIN_Q7 = 128,
    parameter integer DG_MAX_Q7 = 256,
    parameter integer DG_STEP_Q7 = 4,
    parameter integer CLIP_LOCK_ENTER = 5,
    parameter integer CLIP_LOCK_EXIT = 3,
    parameter integer HOT_ENTER_FRAMES = 3,
    parameter integer HOT_EXIT_FRAMES = 6,
    parameter integer ROI_DARK_FLOOR = 48,
    parameter integer ROI_DARK_RELEASE = 64,
    parameter integer SOFT_DOWN_LIMIT = 4,
    parameter integer RECOVERY_HOLD_FRAMES = 6,
    parameter integer RECOVERY_QUAL_FRAMES = 3,
    parameter integer DARK_RECOVERY_SHIFT = 3
)(
    input wire I_clk,
    input wire I_rst,
    input wire I_frame_tgl,
    input wire [8:0] I_avg_luma,
    input wire [8:0] I_clip_pct,
    input wire [8:0] I_roi_all,
    input wire I_ae_cfg_done,
    input wire I_cam_cfg_done,
    output wire O_ae_req,
    output wire [15:0] O_ae,
    output wire [15:0] O_ag,
    output wire [8:0] O_dg
);
    function integer count_width;
        input integer max_value;
        integer n;
        begin
            count_width = 1;
            n = max_value;
            while (n > 1) begin n = n >> 1; count_width = count_width + 1; end
        end
    endfunction
    localparam integer AG_STEP = 3;
    localparam integer ENTER_W = count_width(HOT_ENTER_FRAMES);
    localparam integer EXIT_W = count_width(HOT_EXIT_FRAMES);
    localparam integer SOFT_W = count_width(SOFT_DOWN_LIMIT);
    localparam integer HOLD_W = count_width(RECOVERY_HOLD_FRAMES);
    localparam integer DG_EXPOSURE_MAX = (FLICKER_N > 1) ?
                 ((AE_SPORT_MAX / FLICKER_N) * FLICKER_N) : AE_SPORT_MAX;
    localparam [1:0] S_WAIT_CFG = 2'd0, S_ARM = 2'd1,
                     S_WRITE_LO = 2'd2, S_WRITE_HI = 2'd3;

    // Only the toggle is synchronized as individual bits; data is frame-stable
    // until the next toggle, and captured together before the FSM uses it.
    reg tgl_s1, tgl_s2, tgl_s2d, r_fg_edge;
    reg [8:0] r_avg_sync, r_clip_sync, r_roi_sync;
    wire frame_event = tgl_s2 ^ tgl_s2d;
    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            tgl_s1 <= 0; tgl_s2 <= 0; tgl_s2d <= 0; r_fg_edge <= 0;
            r_avg_sync <= 0; r_clip_sync <= 0; r_roi_sync <= 0;
        end else begin
            tgl_s1 <= I_frame_tgl; tgl_s2 <= tgl_s1; tgl_s2d <= tgl_s2;
            r_fg_edge <= frame_event;
            if (frame_event) begin
                r_avg_sync <= I_avg_luma;
                r_clip_sync <= I_clip_pct;
                r_roi_sync <= I_roi_all;
            end
        end
    end

    reg [1:0] state;
    reg [15:0] r_ae = 16'd1990, r_ag = 16'd80;
    reg [8:0] r_dg = DG_INIT_Q7;
    reg r_req = 0;
    reg [1:0] r_framewait;
    reg [8:0] r_y_filtered;
    reg r_filter_valid;
    reg [ENTER_W-1:0] clip_hot_enter_count;
    reg [EXIT_W-1:0] clip_hot_exit_count;
    reg clip_hot_lock;
    reg [SOFT_W-1:0] soft_down_count;
    reg dark_hold;
    reg [1:0] dark_release_count;
    reg [HOLD_W-1:0] recovery_hold_count;
    reg [2:0] recovery_streak;
    reg protection_seen;
    reg [1:0] low_enter_count, low_exit_count;
    reg low_light_mode;

    // Only one control ever changes per request. Keeping the previous selected
    // value plus its kind is sufficient to restore the complete prior tuple.
    reg probe_pending, probe_blocked;
    wire recovery_armed = protection_seen && !clip_hot_lock &&
                         (recovery_hold_count == 0) && !probe_blocked;
    reg [1:0] probe_kind; // 0 exposure, 1 AG, 2 DG
    reg [15:0] probe_saved_value;
    reg [8:0] hold_roi_ref;
    reg ref_rebase_pending;
    reg [2:0] scene_change_count;
    reg scene_change_direction;

    assign O_ae_req = r_req;
    assign O_ae = r_ae;
    assign O_ag = r_ag;
    wire dg_to_writer_bit1; /* fehdl keep="true" */
    assign dg_to_writer_bit1 = r_dg[1];
    assign O_dg = {r_dg[8:2], dg_to_writer_bit1, r_dg[0]};

    // These temporaries are combinational decisions in the sequential process,
    // not persistent 32-bit state. Persistent counters above have exact widths.
    integer cur_y, clip, roi, err_dist, ae_shift, ae_step, ae_cont, ae_next;
    integer ag_next, dg_next, moved, direction, action, selected_kind;
    integer selected_old, scene_delta, scene_threshold;
    reg lock_now, dark_now, exited_now, recovery_ready, qualifying_frame;

    always @(posedge I_clk or posedge I_rst) begin
        if (I_rst) begin
            state <= S_WAIT_CFG; r_ae <= 1990; r_ag <= 80; r_dg <= DG_INIT_Q7;
            r_req <= 0; r_framewait <= 0;
            r_y_filtered <= 0; r_filter_valid <= 0;
            clip_hot_enter_count <= 0; clip_hot_exit_count <= 0; clip_hot_lock <= 0;
            soft_down_count <= 0; dark_hold <= 0; dark_release_count <= 0;
            recovery_hold_count <= 0; recovery_streak <= 0; protection_seen <= 0;
            low_enter_count <= 0; low_exit_count <= 0; low_light_mode <= 0;
            probe_pending <= 0; probe_blocked <= 0; probe_kind <= 0;
            probe_saved_value <= 0; hold_roi_ref <= 0; ref_rebase_pending <= 0;
            scene_change_count <= 0; scene_change_direction <= 0;
        end else begin
            r_req <= 0;
            case (state)
                S_WAIT_CFG: begin
                    if (I_cam_cfg_done) begin
                        if (I_ae_cfg_done) begin
                            state <= S_ARM;
                            r_framewait <= 3;
                            r_filter_valid <= 0;
                        end else begin r_req <= 1; state <= S_WRITE_LO; end
                    end
                end
                S_ARM: begin
                    if (r_fg_edge) begin
                        if (r_framewait != 0) begin
                            r_framewait <= r_framewait - 1'b1;
                        end else begin
                            clip = r_clip_sync;
                            roi = r_roi_sync;
                            // First post-write sample rebases instead of mixing
                            // a previous exposure into the new filter reference.
                            cur_y = r_avg_sync;
                            if (r_filter_valid) begin
                                if (r_avg_sync > r_y_filtered) begin
                                    if ((r_avg_sync-r_y_filtered) > 7)
                                        cur_y = r_y_filtered + ((r_avg_sync-r_y_filtered) >> 3);
                                    else cur_y = r_y_filtered + 1;
                                end else if (r_avg_sync < r_y_filtered) begin
                                    if ((r_y_filtered-r_avg_sync) > 7)
                                        cur_y = r_y_filtered - ((r_y_filtered-r_avg_sync) >> 3);
                                    else cur_y = r_y_filtered - 1;
                                end else cur_y = r_y_filtered;
                            end
                            r_y_filtered <= cur_y;
                            r_filter_valid <= 1;
                            lock_now = clip_hot_lock;
                            dark_now = dark_hold;
                            exited_now = 0;
                            recovery_ready = 0;
                            moved = 0; direction = 0; action = 0;
                            selected_kind = 0; selected_old = 0;

                            if (clip >= CLIP_LOCK_ENTER) begin
                                clip_hot_exit_count <= 0;
                                if (clip_hot_enter_count < HOT_ENTER_FRAMES)
                                    clip_hot_enter_count <= clip_hot_enter_count + 1'b1;
                                if (clip_hot_enter_count >= HOT_ENTER_FRAMES-1) begin
                                    lock_now = 1;
                                    clip_hot_lock <= 1;
                                    protection_seen <= 1;
                                end
                            end else begin
                                clip_hot_enter_count <= 0;
                                if (clip < CLIP_LOCK_EXIT && clip_hot_lock) begin
                                    if (clip_hot_exit_count < HOT_EXIT_FRAMES)
                                        clip_hot_exit_count <= clip_hot_exit_count + 1'b1;
                                    if (clip_hot_exit_count >= HOT_EXIT_FRAMES-1) begin
                                        lock_now = 0; exited_now = 1;
                                        clip_hot_lock <= 0; clip_hot_exit_count <= 0;
                                        recovery_hold_count <= RECOVERY_HOLD_FRAMES;
                                        recovery_streak <= 0;
                                    end
                                end else clip_hot_exit_count <= 0;
                            end

                            // Dark mixed scene latch.  It is entered only when
                            // a meaningful (>=5%) clipped component is present;
                            // a pure dark ROI must remain eligible for recovery.
                            if (roi < ROI_DARK_FLOOR && clip >= CLIP_LOCK_ENTER) begin
                                dark_now = 1; dark_hold <= 1; dark_release_count <= 0;
                                protection_seen <= 1;
                                if (!dark_hold) recovery_hold_count <= RECOVERY_HOLD_FRAMES;
                            end else if (roi >= ROI_DARK_RELEASE || clip < CLIP_LOCK_EXIT) begin
                                // Let the mixed-scene hold leave after a
                                // low-clip confirmation as well as after the
                                // ROI brightens.  This prevents clip=0 dark
                                // frames from holding the gain indefinitely.
                                if (dark_release_count < 3)
                                    dark_release_count <= dark_release_count + 1'b1;
                                if (dark_release_count >= 2) begin
                                    dark_now = 0; dark_hold <= 0;
                                end
                            end else dark_release_count <= 0;

                            if (!lock_now && !exited_now && recovery_hold_count != 0)
                                recovery_hold_count <= recovery_hold_count - 1'b1;

                            // Preserve the original low-light hysteresis, but
                            // never advance it from pre-write/discarded frames.
                            if (cur_y < 48) begin
                                low_exit_count <= 0;
                                if (low_enter_count < 3) low_enter_count <= low_enter_count + 1'b1;
                                if (low_enter_count >= 2) low_light_mode <= 1;
                            end else if (cur_y > 64) begin
                                low_enter_count <= 0;
                                if (low_exit_count < 3) low_exit_count <= low_exit_count + 1'b1;
                                if (low_exit_count >= 2) low_light_mode <= 0;
                            end else begin low_enter_count <= 0; low_exit_count <= 0; end

                            // A failed recovery is blocked in an unchanged
                            // scene. Reopen only after six same-direction large
                            // ROI changes with fixed controls and low clipping.
                            if (ref_rebase_pending) begin
                                hold_roi_ref <= roi;
                                ref_rebase_pending <= 0;
                                scene_change_count <= 0;
                            end else if (probe_blocked && !probe_pending) begin
                                scene_delta = (roi >= hold_roi_ref) ? roi-hold_roi_ref : hold_roi_ref-roi;
                                scene_threshold = hold_roi_ref >> 2;
                                if (scene_threshold < 8) scene_threshold = 8;
                                if (clip < CLIP_LOCK_ENTER && scene_delta >= scene_threshold) begin
                                    if (scene_change_count == 0 || scene_change_direction == (roi >= hold_roi_ref)) begin
                                        scene_change_direction <= (roi >= hold_roi_ref);
                                        if (scene_change_count < 6) scene_change_count <= scene_change_count + 1'b1;
                                        if (scene_change_count >= 5) begin
                                            probe_blocked <= 0; scene_change_count <= 0;
                                            hold_roi_ref <= roi; recovery_streak <= 0;
                                            soft_down_count <= 0;
                                        end
                                    end else begin
                                        scene_change_count <= 1;
                                        scene_change_direction <= (roi >= hold_roi_ref);
                                    end
                                end else scene_change_count <= 0;
                            end else scene_change_count <= 0;

                            // Low-light recovery is qualified over a short
                            // clean window; sensor write/frame latency stays
                            // unchanged.  This prevents dark scenes from
                            // waiting through six additional statistics.
                            qualifying_frame = !lock_now && !exited_now &&
                                               (recovery_hold_count == 0) && (clip < CLIP_LOCK_EXIT) && (cur_y < Y_LO);
                            if (qualifying_frame) begin
                                if (recovery_streak < RECOVERY_QUAL_FRAMES)
                                    recovery_streak <= recovery_streak + 1'b1;
                                if (recovery_streak >= RECOVERY_QUAL_FRAMES-1) begin
                                    recovery_ready = 1;
                                    // Releasing the dark hold requires a full
                                    // high-light exit and recovery qualification.
                                    dark_now = 0; dark_hold <= 0;
                                    soft_down_count <= 0;
                                end
                            end else recovery_streak <= 0;

                            err_dist = (cur_y > Y_TARGET) ? cur_y-Y_TARGET : Y_TARGET-cur_y;
                            ae_shift = (err_dist > 64) ? 2 : ((err_dist > 24) ? 3 : 4);
                            if (low_light_mode && ae_shift < 5) ae_shift = ae_shift + 1;

                            // Serious clip always retains the fixed 1/8, exposure-
                            // first guard. Defer a failed trial rollback until it
                            // clears. Restore only if still a decrease: a severe
                            // exposure reduction may already be below the saved
                            // pre-trial value, which must never be written upward.
                            if (probe_pending && clip < CLIP_HIGH &&
                                (clip >= CLIP_LOCK_ENTER || probe_blocked)) begin
                                case (probe_kind)
                                    0: if (probe_saved_value < r_ae) begin r_ae <= probe_saved_value; moved = 1; end
                                    1: if (probe_saved_value < r_ag) begin r_ag <= probe_saved_value; moved = 1; end
                                    2: if (probe_saved_value[8:0] < r_dg) begin r_dg <= probe_saved_value[8:0]; moved = 1; end
                                endcase
                                probe_pending <= 0; probe_blocked <= 1;
                                ref_rebase_pending <= 1; scene_change_count <= 0;
                                recovery_streak <= 0;
                            end else begin
                                if (probe_pending && clip < CLIP_HIGH) probe_pending <= 0;
                                if (clip >= CLIP_HIGH) begin
                                    direction = -1; ae_shift = 3; action = 1;
                                    protection_seen <= 1;
                                    if (probe_pending) begin
                                        probe_blocked <= 1;
                                        ref_rebase_pending <= 1;
                                    end
                                    // A severe one-frame event starts a hold even
                                    // before the ordinary three-frame lock enters.
                                    recovery_hold_count <= RECOVERY_HOLD_FRAMES;
                                    recovery_streak <= 0;
                                end else if (lock_now) begin
                                    if (clip >= CLIP_LOCK_ENTER && !dark_now &&
                                        roi >= ROI_DARK_FLOOR && soft_down_count < SOFT_DOWN_LIMIT) begin
                                        direction = -1; ae_shift = 4; action = 2;
                                    end
                                    // All other locked intervals, including exit
                                    // confirmation, hold the entire control tuple.
                                end else if (exited_now || recovery_hold_count != 0) begin
                                    direction = 0;
                                end else if (dark_now) begin
                                    direction = 0;
                                end else if (cur_y > Y_HI) begin
                                    // With a dark all-pixel ROI, filtered Y may
                                    // be formed only from a sparse lamp after
                                    // dark-sample exclusion.  Do not let that
                                    // ordinary-Y branch crush the background;
                                    // severe/locked clipping still took priority.
                                    if (roi >= ROI_DARK_FLOOR) begin
                                        direction = -1; action = 3;
                                    end
                                end else if (cur_y < Y_LO) begin
                                    if (!protection_seen && recovery_ready) begin
                                        direction = 1; action = 3;
                                        // Far below the dark target, use a 1/8 exposure step;
                                        // close to target use 1/16 to avoid overshoot.
                                        if (cur_y + 32 < Y_LO) ae_shift = 3;
                                        else ae_shift = 4;
                                    end
                                    else if (recovery_ready && !probe_blocked) begin
                                        direction = 1; ae_shift = (cur_y + 32 < Y_LO) ? DARK_RECOVERY_SHIFT : 4; action = 4;
                                    end
                                end

                                if (direction < 0) begin
                                    // Candidate top fixes LOW_NOISE_GAIN_FIRST=0.
                                    // Severe/soft policy always chooses exposure first.
                                    if (action == 3 && LOW_NOISE_GAIN_FIRST != 0 && r_ag > AG_MIN) begin
                                        ag_next = r_ag - AG_STEP; if (ag_next < AG_MIN) ag_next = AG_MIN;
                                        if (ag_next < r_ag) begin r_ag <= ag_next; moved = 1; end
                                    end else begin
                                        ae_step = r_ae >> ae_shift; if (ae_step < 1) ae_step = 1;
                                        ae_cont = r_ae - ae_step; if (ae_cont < AE_MIN) ae_cont = AE_MIN;
                                        ae_next = (FLICKER_N > 1) ?
                                            (((ae_cont + FLICKER_N/2) / FLICKER_N) * FLICKER_N) : ae_cont;
                                        if (ae_next < AE_MIN) ae_next = AE_MIN;
                                        if (ae_next > AE_SPORT_MAX) ae_next = AE_SPORT_MAX;
                                        if (ae_next < r_ae) begin r_ae <= ae_next; moved = 1; end
                                        else if (r_ag > AG_MIN) begin
                                            ag_next = r_ag-AG_STEP; if (ag_next < AG_MIN) ag_next = AG_MIN;
                                            if (ag_next < r_ag) begin r_ag <= ag_next; moved = 1; end
                                        end else if (r_dg > DG_MIN_Q7) begin
                                            dg_next = r_dg-DG_STEP_Q7; if (dg_next < DG_MIN_Q7) dg_next = DG_MIN_Q7;
                                            if (dg_next < r_dg) begin r_dg <= dg_next; moved = 1; end
                                        end
                                    end
                                end else if (direction > 0) begin
                                    ae_step = r_ae >> ae_shift; if (ae_step < 1) ae_step = 1;
                                    ae_cont = r_ae + ae_step; if (ae_cont > AE_SPORT_MAX) ae_cont = AE_SPORT_MAX;
                                    ae_next = (FLICKER_N > 1) ?
                                        (((ae_cont + FLICKER_N/2) / FLICKER_N) * FLICKER_N) : ae_cont;
                                    if (ae_next > AE_SPORT_MAX) ae_next = AE_SPORT_MAX;
                                    if (ae_next < AE_MIN) ae_next = AE_MIN;
                                    if (ae_next > r_ae) begin
                                        selected_kind = 0; selected_old = r_ae; r_ae <= ae_next; moved = 1;
                                    end else if (r_ag < AG_MAX) begin
                                        ag_next = r_ag+AG_STEP; if (ag_next > AG_MAX) ag_next = AG_MAX;
                                        if (ag_next > r_ag) begin
                                            selected_kind = 1; selected_old = r_ag; r_ag <= ag_next; moved = 1;
                                        end
                                    end else if (r_ae >= DG_EXPOSURE_MAX && r_ag >= AG_MAX && r_dg < DG_MAX_Q7) begin
                                        dg_next = r_dg+DG_STEP_Q7; if (dg_next > DG_MAX_Q7) dg_next = DG_MAX_Q7;
                                        if (dg_next > r_dg) begin
                                            selected_kind = 2; selected_old = r_dg; r_dg <= dg_next; moved = 1;
                                        end
                                    end
                                end

                                if (moved && action == 2) soft_down_count <= soft_down_count + 1'b1;
                                if (moved && action == 4) begin
                                    probe_kind <= selected_kind; probe_saved_value <= selected_old;
                                    probe_pending <= 1;
                                    // A committed dark increase starts a fresh
                                    // three-frame qualification window.
                                    recovery_streak <= 0;
                                    hold_roi_ref <= roi;
                                end
                            end
                            if (moved) begin
                                if (direction > 0 && action != 4) recovery_streak <= 0;
                                r_req <= 1; state <= S_WRITE_LO;
                                r_filter_valid <= 0; scene_change_count <= 0;
                                if (probe_blocked) ref_rebase_pending <= 1;
                            end
                        end
                    end
                end
                S_WRITE_LO: if (!I_ae_cfg_done) state <= S_WRITE_HI;
                S_WRITE_HI: if (I_ae_cfg_done) begin
                    r_framewait <= 3; r_filter_valid <= 0; state <= S_ARM;
                end
                default: state <= S_WAIT_CFG;
            endcase
        end
    end
endmodule
