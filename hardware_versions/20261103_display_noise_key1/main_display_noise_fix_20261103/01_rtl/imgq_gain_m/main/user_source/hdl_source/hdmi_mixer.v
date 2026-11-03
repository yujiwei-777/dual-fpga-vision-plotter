module hdmi_mixer #(
    parameter H_OFFSET = 128,
    parameter V_OFFSET = 60,
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720,
    parameter integer DEBUG_MODE = 0,
    // Logo rendering is optional.  Disabling it removes the long ROM->glyph
    // combinational path from the 75 MHz HDMI timing cone while retaining the
    // rest of the OSD and target overlays.
    parameter integer LOGO_ENABLE = 1,
    // Replace only the legacy counter row. Existing instantiations retain
    // their original pixels when the measurement display is disabled.
    parameter integer LATENCY_OSD_ENABLE = 0
)(
    input wire        I_clk,
    input wire        I_rst_n,

    input wire        I_video_vsync,
    input wire        I_video_hsync,
    input wire        I_video_de,
    input wire        I_video_user,
    input wire        I_video_last,
    // Read requests stay on the original VTC timing when an inline pixel
    // processor delays the video/timing stream.  Keeping this separate avoids
    // asking video_out for pixels three clocks late when histogram EQ is on.
    input wire        I_video_rd_req,

    input wire[3:0]   I_debug_status,
    input wire[4:0]   I_algo_mode,      // current style mode -> OSD text
    input wire        I_he_on,          // histogram equalisation enabled

    // Pixel-domain mailbox. The producer holds the data with its toggle;
    // only vertical blanking can capture/commit a new displayed value.
    input wire        I_latency_valid,
    input wire [15:0] I_latency_frame,
    input wire [15:0] I_latency_tenth_ms,
    input wire        I_latency_toggle,

    // Target-detection overlay (SW1).  Already latched once per frame in this
    // clock domain by the top level, so these are stable all frame.
    input wire        I_ovl_on,         // SW1 master switch, frame-latched
    input wire        I_ovl_valid,      // a target was found this frame
    input wire [10:0] I_ovl_x0,
    input wire [9:0]  I_ovl_y0,
    input wire [10:0] I_ovl_x1,
    input wire [9:0]  I_ovl_y1,
    input wire [10:0] I_ovl_cx,
    input wire [9:0]  I_ovl_cy,
    // Target recognition metadata.  These ports were added after the
    // original box-only interface; leaving them unconnected is safe and
    // preserves the old top-level until the detector is enabled.
    input wire [1:0]  I_ovl_color,      // 0=RED, 1=GREEN, 2=BLUE
    input wire I_ovl_pcb,I_pcb_checked,I_pcb_good,
    input wire [2:0] I_pcb_status,
    input wire I_ovl_remote,input wire [1:0] I_ovl_shape3,
    input wire        I_ovl_shape,      // 0=RECT, 1=BLOB
    input wire [23:0] I_ovl_area,
    input wire [7:0]  I_ovl_confidence,
    input wire [3:0]  I_ovl_conf_tens,
    input wire [3:0]  I_ovl_conf_ones,

    // Up to four type18 YOLO boxes.  Each 128-bit slot is
    // {area[31:0],reserved[7:0],confidence[7:0],class_id[15:0],
    //   y1[15:0],x1[15:0],y0[15:0],x0[15:0]}.
    input wire        I_multi_valid,
    input wire [2:0]  I_multi_count,
    input wire [511:0] I_multi_boxes,
    input wire I_multi_toggle,
    input wire I_aux_online,
    input wire I_copy_mode,input wire [2:0] I_copy_state,

    // Motion box (red).  Takes priority over the target box where they overlap.
    input wire        I_mot_on,
    input wire [10:0] I_mot_x0,
    input wire [9:0]  I_mot_y0,
    input wire [10:0] I_mot_x1,
    input wire [9:0]  I_mot_y1,
    // Confirmed changed-sample count for the displayed motion frame.
    // This is a held HDMI-domain value from the top-level motion commit.
    input wire [15:0] I_motion_count,
    // Motion display enable is the synchronized SW1 gate.  It is separate
    // from I_mot_on so the count row is hidden when motion monitoring is off,
    // even if a previous frame still has a held motion box.
    input wire        I_motion_enable,

    output wire       O_video_rd_en,
    input wire[23:0]  I_video_rd_data,

    output reg        O_hdmi_vsync,
    output reg        O_hdmi_hsync,
    output reg        O_hdmi_de,
    output reg[23:0]  O_hdmi_data
);

    reg        S_video_vsync_1d;
    reg        S_video_vsync_2d;
    reg        S_video_hsync_1d;
    reg        S_video_hsync_2d;
    reg        S_video_de_1d;
    reg        S_video_de_2d;
    reg [23:0] S_video_data_1d;
    reg [23:0] S_video_data_2d;
    // Three extra stages: the OSD/overlay decode is deep, so the display
    // decision is registered and the video moves with it (720p/75 MHz).
    reg [23:0] S_video_data_3d;
    reg        S_video_de_3d, S_video_hsync_3d, S_video_vsync_3d;
    // One more, because the decision is now split over two cycles: the logo
    // LUTROM / character renderer gets its own clock (stage A) before the
    // priority mux picks between OSD, motion box, target overlay and the
    // status corner (stage B).  Folding both into one cycle put the whole
    // LUTROM tree plus the 24-bit mux on a single 13.3 ns path.
    reg [23:0] S_video_data_4d;
    reg        S_video_de_4d, S_video_hsync_4d, S_video_vsync_4d;
    reg        S_disp_hit;
    reg [23:0] S_disp_col;

    // ---- stage A: OSD decode, and the cheap overlay tests ----------------
    // The overlay tests are registered here too (rather than left
    // combinational) so everything stage B combines arrives from a flop.
    reg        S_osd_hit_a;
    reg [23:0] S_osd_color_a;
    reg        S_corner_a;
    reg [23:0] S_stat_col_a;
    reg        S_mot_edge_a;
    reg        S_multi_edge_a;
    reg [23:0] S_multi_color_a;
    reg        S_ovl_hit_a;
    reg [23:0] S_ovl_color_a;
    reg [11:0] S_x;
    reg [11:0] S_y;
    reg [11:0] S_x_1d;
    reg [11:0] S_x_2d;
    reg [11:0] S_y_1d;
    reg [11:0] S_y_2d;
    reg [11:0] S_dyn_x_2d,S_dyn_y_2d;

    reg        S_osd_hit;
    reg [23:0] S_osd_color;
    reg [3:0]  S_char_idx;
    reg [2:0]  S_char_row;
    reg [2:0]  S_char_col;
    reg [4:0]  S_char_bits;
    reg        S_char_on;
    reg        S_logo_blue_on;
    reg        S_logo_red_on;
    reg [11:0] S_logo_tmp_y;
    reg [3:0]  S_logo_red_band;
    reg [11:0] S_logo_red_x_start;
    reg [11:0] S_logo_red_x_end;
    // Two synchronous palette reads align the lossless Logo with S_x_2d.
    wire [24:0] S_logo_pixel_r;
    reg [31:0] S_frame_cnt;
    reg [11:0] S_dyn_x;
    reg [11:0] S_dyn_y;
    reg [3:0]  S_dyn_char;
    reg [2:0]  S_dyn_col;
    reg [2:0]  S_dyn_row;
    reg [4:0]  S_dyn_bits;
    reg        S_dyn_on;
    reg [3:0]  S_dyn_digit_idx;
    reg [11:0] S_dyn_digit_x;
    reg [6:0]  S_dyn_seg;
    reg [3:0]  S_cnt_d0;
    reg [3:0]  S_cnt_d1;
    reg [3:0]  S_cnt_d2;
    reg [3:0]  S_cnt_d3;
    reg [3:0]  S_cnt_d4;
    reg [3:0]  S_cnt_d5;
    // Motion count is converted incrementally over sixteen pixel clocks.
    // This keeps the decimal conversion off the HDMI pixel critical path.
    reg [19:0] S_motion_bcd;
    reg [19:0] S_motion_bcd_work;
    reg [15:0] S_motion_bin_work;
    reg [4:0]  S_motion_bcd_step;
    reg        S_motion_bcd_busy;
    reg [19:0] S_motion_bcd_adjust;
    reg S_lat_seen, S_lat_busy, S_lat_ready;
    reg [3:0] S_lat_step;
    reg [15:0] S_lat_binary, S_lat_bcd_work, S_lat_bcd_adjust;
    reg [15:0] S_lat_frame_work, S_lat_frame, S_lat_bcd;
    reg S_lat_valid_work, S_lat_overflow_work, S_lat_valid, S_lat_overflow;
    integer S_lat_digit;
    reg [3:0]  S_lbl_row;
    reg [2:0]  S_lbl_col;
    reg [1:0]  S_lbl_idx;
    reg [4:0]  S_lbl_bits;
    reg [7:0]  S_lbl_local_x;
    reg [3:0]  S_dyn_dec_digit;
    reg [4:0]  S_cn_local_x;
    reg [4:0]  S_cn_local_y;
    reg [3:0]  S_cn_col;
    reg [3:0]  S_cn_row;
    reg [15:0] S_cn_row_bits;
    reg        S_cn_on;
    reg [9:0]  S_cn_scale_x;
    reg [9:0]  S_cn_scale_y;
    reg [7:0]  S_pf_char;
    reg        S_md_row;            // current pixel is on the "MODE:xxxx" row
    reg [7:0]  S_md_c0, S_md_c1, S_md_c2, S_md_c3;   // 4-letter mode name
    reg [4:0]  S_pf_local_x;
    reg [4:0]  S_pf_local_y;
    reg [3:0]  S_pf_col;
    reg [3:0]  S_pf_row;
    wire [15:0] S_pf_row_bits;
    reg        S_pf_on;
    reg [9:0]  S_pf_scale_x;
    reg [9:0]  S_pf_scale_y;
    reg [7:0]  S_large_char;
    reg [3:0]  S_large_row;
    reg [2:0]  S_large_col;
    reg [4:0]  S_large_cell;
    reg [2:0]  S_large_line;
    reg [23:0] S_large_color;
    wire [7:0] S_large_row_bits;
    reg [11:0] S_lbl_x;
    reg [11:0] S_lbl_y;
    reg [3:0]  S_lbl_char;
    reg [3:0]  S_tgt_x3, S_tgt_x2, S_tgt_x1, S_tgt_x0;
    reg [3:0]  S_tgt_y2, S_tgt_y1, S_tgt_y0;
    reg [3:0]  S_tgt_a3, S_tgt_a2, S_tgt_a1, S_tgt_a0;

    localparam LOGO_X = 12'd0;
    localparam LOGO_Y = 12'd0;
    localparam LOGO_W = 12'd160;
    localparam LOGO_H = 12'd160;

    localparam COLOR_LOGO_BLUE   = 24'h1f315c;
    localparam COLOR_LOGO_RED    = 24'hec1c2d;
    localparam COLOR_TEXT        = 24'h00e6ff;
    // Keep the dynamic status block in the upper-right corner.  The left
    // side remains reserved for the 160x160 Anlogic logo.
    // Leave a 16 pixel right margin, while allowing the longest identity
    // string ("TGT:GREEN RECT LOCK") to fit in fixed 16 pixel cells.
    // The previous 280 pixel window was just wide enough for the metadata
    // row, but the variable-width colour/status row was clipped on some
    // displays after the four-cycle mixer pipeline.
    // Keep a generous right margin.  The previous x=944 placement ended
    // only 16 pixels before the nominal 1280-wide active region; several
    // HDMI panels overscan/scale the last few columns, which clipped the
    // final LOCK/LOST characters and the metadata row.  x=880 leaves 80
    // pixels of margin while the block remains clearly in the upper-right.
    localparam DYN_OSD_X         = 12'd864;
    // Keep a generous top margin. Some HDMI panels crop/overscan the first
    // few dozen active lines, which previously clipped the first OSD row.
    // Starting at line 64 leaves the complete 68-pixel OSD block visible.
    localparam DYN_OSD_Y         = 12'd64;
    localparam DYN_OSD_W         = 12'd336;
    // Keep the legacy ANLU/CNT counter at the top of the panel and reserve a
    // separate row for the target identity.  The target row used to start at
    // local y=0, which made its glyphs overwrite the ANLU/CNT text and the
    // incrementing frame counter.  The extra 20 pixels below the metadata
    // row keep all four pieces of information visible at once.
    localparam DYN_OSD_H         = 12'd128;   // five native 16px rows, 8px gaps
    localparam TARGET_ROW_Y0     = 12'd128;
    localparam MOTION_ROW_Y0     = 12'd168;
    localparam CN_Y_OFFSET       = 12'd2;
    localparam MODE_ROW_Y0       = 12'd28;    // second row starts here (local y)
    localparam MODE_ROW_W        = 12'd224;   // 14 cells: "MODE:xxxx" + " HIST"
    // High-contrast colours are used for the status panel.  The previous
    // yellow-on-video text was readable on a dark scene but became soft on
    // bright/green camera content.  Text now has a white foreground and a
    // cyan mode row, both over an opaque near-black panel.
    localparam COLOR_DYN_TEXT    = 24'hffffff;
    localparam COLOR_MODE_TEXT   = 24'h60ffff;
    // A solid dark panel keeps the 16x16 status characters readable over
    // bright camera content.  The panel is drawn only inside DYN_OSD and
    // remains below the text in the existing OSD priority.
    localparam COLOR_DYN_PANEL   = 24'h081018;
    localparam COLOR_DYN_BORDER  = 24'h4080a0;
    localparam CHAR_AN           = 8'h80;
    localparam CHAR_LU           = 8'h81;
    localparam CHAR_C            = 8'h43;
    localparam CHAR_N            = 8'h4e;
    localparam CHAR_T            = 8'h54;
    localparam CHAR_0            = 8'h30;
    localparam CHAR_COLON        = 8'h3a;

    // (algorithm-mode OSD display moved out of the single-cycle OSD path; see note)

    function [4:0] F_logo_text_bits;
        input [3:0] I_char;
        input [2:0] I_row;
        begin
            case(I_char)
                4'd0: begin
                    case(I_row) // A
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10001;
                        3'd3: F_logo_text_bits = 5'b11111;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b10001;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd1: begin
                    case(I_row) // N
                        3'd0: F_logo_text_bits = 5'b10001;
                        3'd1: F_logo_text_bits = 5'b11001;
                        3'd2: F_logo_text_bits = 5'b10101;
                        3'd3: F_logo_text_bits = 5'b10011;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b10001;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd2: begin
                    case(I_row) // L
                        3'd0: F_logo_text_bits = 5'b10000;
                        3'd1: F_logo_text_bits = 5'b10000;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10000;
                        3'd4: F_logo_text_bits = 5'b10000;
                        3'd5: F_logo_text_bits = 5'b10000;
                        3'd6: F_logo_text_bits = 5'b11111;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd3: begin
                    case(I_row) // O
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10001;
                        3'd3: F_logo_text_bits = 5'b10001;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd4: begin
                    case(I_row) // G
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10111;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd5: begin
                    case(I_row) // I
                        3'd0: F_logo_text_bits = 5'b11111;
                        3'd1: F_logo_text_bits = 5'b00100;
                        3'd2: F_logo_text_bits = 5'b00100;
                        3'd3: F_logo_text_bits = 5'b00100;
                        3'd4: F_logo_text_bits = 5'b00100;
                        3'd5: F_logo_text_bits = 5'b00100;
                        3'd6: F_logo_text_bits = 5'b11111;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd6: begin
                    case(I_row) // C
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10000;
                        3'd4: F_logo_text_bits = 5'b10000;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                default: F_logo_text_bits = 5'b00000;
            endcase
        end
    endfunction

    // 7-seg bit mapping: {a,b,c,d,e,f,g}
    function [6:0] F_hex7seg;
        input [3:0] I_hex;
        begin
            case(I_hex)
                4'h0: F_hex7seg = 7'b1111110;
                4'h1: F_hex7seg = 7'b0110000;
                4'h2: F_hex7seg = 7'b1101101;
                4'h3: F_hex7seg = 7'b1111001;
                4'h4: F_hex7seg = 7'b0110011;
                4'h5: F_hex7seg = 7'b1011011;
                4'h6: F_hex7seg = 7'b1011111;
                4'h7: F_hex7seg = 7'b1110000;
                4'h8: F_hex7seg = 7'b1111111;
                4'h9: F_hex7seg = 7'b1111011;
                4'ha: F_hex7seg = 7'b1110111;
                4'hb: F_hex7seg = 7'b0011111;
                4'hc: F_hex7seg = 7'b1001110;
                4'hd: F_hex7seg = 7'b0111101;
                4'he: F_hex7seg = 7'b1001111;
                4'hf: F_hex7seg = 7'b1000111;
                default: F_hex7seg = 7'b0000000;
            endcase
        end
    endfunction

    // Direct nibble-to-ASCII conversion keeps the target metadata display
    // off the per-pixel divider path.  Coordinates/area are shown as fixed
    // width hexadecimal values (X:0xxx Y:0xx A:xxxx).
    function [7:0] F_hex_ascii;
        input [3:0] I_n;
        begin
            F_hex_ascii = (I_n < 4'd10) ? (8'h30 + I_n) : (8'h41 + I_n - 4'd10);
        end
    endfunction

    function [4:0] F_cnt_label_bits;
        input [1:0] I_idx;
        input [2:0] I_row;
        begin
            case(I_idx)
                2'd0: begin // C
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b01110;
                        3'd1: F_cnt_label_bits = 5'b10001;
                        3'd2: F_cnt_label_bits = 5'b10000;
                        3'd3: F_cnt_label_bits = 5'b10000;
                        3'd4: F_cnt_label_bits = 5'b10000;
                        3'd5: F_cnt_label_bits = 5'b10001;
                        3'd6: F_cnt_label_bits = 5'b01110;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                2'd1: begin // N
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b10001;
                        3'd1: F_cnt_label_bits = 5'b11001;
                        3'd2: F_cnt_label_bits = 5'b10101;
                        3'd3: F_cnt_label_bits = 5'b10011;
                        3'd4: F_cnt_label_bits = 5'b10001;
                        3'd5: F_cnt_label_bits = 5'b10001;
                        3'd6: F_cnt_label_bits = 5'b10001;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                2'd2: begin // T
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b11111;
                        3'd1: F_cnt_label_bits = 5'b00100;
                        3'd2: F_cnt_label_bits = 5'b00100;
                        3'd3: F_cnt_label_bits = 5'b00100;
                        3'd4: F_cnt_label_bits = 5'b00100;
                        3'd5: F_cnt_label_bits = 5'b00100;
                        3'd6: F_cnt_label_bits = 5'b00100;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                default: begin // ':'
                    case(I_row)
                        3'd2: F_cnt_label_bits = 5'b00100;
                        3'd5: F_cnt_label_bits = 5'b00100;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
            endcase
        end
    endfunction

    // Minimal 16x16 Chinese bitmap rows for "an" and "lu".
    function [15:0] F_cn16_row;
        input I_char; // 0: an, 1: lu
        input [3:0] I_row;
        begin
            if(!I_char) begin
                case(I_row)
                    4'd0:  F_cn16_row = 16'h0200;
                    4'd1:  F_cn16_row = 16'h7ff0;
                    4'd2:  F_cn16_row = 16'h4410;
                    4'd3:  F_cn16_row = 16'h0400;
                    4'd4:  F_cn16_row = 16'h7ff0;
                    4'd5:  F_cn16_row = 16'h0840;
                    4'd6:  F_cn16_row = 16'h1040;
                    4'd7:  F_cn16_row = 16'h1c80;
                    4'd8:  F_cn16_row = 16'h0300;
                    4'd9:  F_cn16_row = 16'h0cc0;
                    4'd10: F_cn16_row = 16'h7020;
                    4'd11: F_cn16_row = 16'h0000;
                    4'd12: F_cn16_row = 16'h0000;
                    4'd13: F_cn16_row = 16'h0000;
                    4'd14: F_cn16_row = 16'h0000;
                    4'd15: F_cn16_row = 16'h0000;
                    default: F_cn16_row = 16'h0000;
                endcase
            end
            else begin
                case(I_row)
                    4'd0:  F_cn16_row = 16'h79e0;
                    4'd1:  F_cn16_row = 16'h4a20;
                    4'd2:  F_cn16_row = 16'h4d40;
                    4'd3:  F_cn16_row = 16'h7880;
                    4'd4:  F_cn16_row = 16'h1140;
                    4'd5:  F_cn16_row = 16'h1630;
                    4'd6:  F_cn16_row = 16'h5be0;
                    4'd7:  F_cn16_row = 16'h5220;
                    4'd8:  F_cn16_row = 16'h5220;
                    4'd9:  F_cn16_row = 16'h5be0;
                    4'd10: F_cn16_row = 16'h6220;
                    4'd11: F_cn16_row = 16'h0000;
                    4'd12: F_cn16_row = 16'h0000;
                    4'd13: F_cn16_row = 16'h0000;
                    4'd14: F_cn16_row = 16'h0000;
                    4'd15: F_cn16_row = 16'h0000;
                    default: F_cn16_row = 16'h0000;
                endcase
            end
        end
    endfunction

    function [4:0] F_dyn_char_bits;
        input [3:0] I_char;
        input [2:0] I_row;
        begin
            case(I_char)
                4'h0: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10011; 3'd3:F_dyn_char_bits=5'b10101; 3'd4:F_dyn_char_bits=5'b11001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h1: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00100; 3'd1:F_dyn_char_bits=5'b01100; 3'd2:F_dyn_char_bits=5'b00100; 3'd3:F_dyn_char_bits=5'b00100; 3'd4:F_dyn_char_bits=5'b00100; 3'd5:F_dyn_char_bits=5'b00100; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h2: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b00001; 3'd3:F_dyn_char_bits=5'b00110; 3'd4:F_dyn_char_bits=5'b01000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b11111; default:F_dyn_char_bits=5'b00000; endcase end
                4'h3: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b00001; 3'd2:F_dyn_char_bits=5'b00001; 3'd3:F_dyn_char_bits=5'b01110; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b00001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h4: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00010; 3'd1:F_dyn_char_bits=5'b00110; 3'd2:F_dyn_char_bits=5'b01010; 3'd3:F_dyn_char_bits=5'b10010; 3'd4:F_dyn_char_bits=5'b11111; 3'd5:F_dyn_char_bits=5'b00010; 3'd6:F_dyn_char_bits=5'b00010; default:F_dyn_char_bits=5'b00000; endcase end
                4'h5: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b11110; 3'd3:F_dyn_char_bits=5'b00001; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h6: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00110; 3'd1:F_dyn_char_bits=5'b01000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h7: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b00001; 3'd2:F_dyn_char_bits=5'b00010; 3'd3:F_dyn_char_bits=5'b00100; 3'd4:F_dyn_char_bits=5'b01000; 3'd5:F_dyn_char_bits=5'b01000; 3'd6:F_dyn_char_bits=5'b01000; default:F_dyn_char_bits=5'b00000; endcase end
                4'h8: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b01110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h9: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b01111; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b00010; 3'd6:F_dyn_char_bits=5'b11100; default:F_dyn_char_bits=5'b00000; endcase end
                4'ha: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b11111; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b10001; default:F_dyn_char_bits=5'b00000; endcase end
                4'hb: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'hc: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b10000; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'hd: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b10001; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'he: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b11111; default:F_dyn_char_bits=5'b00000; endcase end
                4'hf: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b10000; default:F_dyn_char_bits=5'b00000; endcase end
                default: F_dyn_char_bits = 5'b00000;
            endcase
        end
    endfunction

    // Unified prefix character library (16x16 rows): an/lu/C/N/T/:
    function [15:0] F_osd_char16_row;
        input [7:0] I_char;
        input [3:0] I_row;
        begin
            case(I_char)
                CHAR_AN: begin
                    case(I_row)
                        4'd0:  F_osd_char16_row = 16'h0200;
                        4'd1:  F_osd_char16_row = 16'h7ff0;
                        4'd2:  F_osd_char16_row = 16'h4410;
                        4'd3:  F_osd_char16_row = 16'h0400;
                        4'd4:  F_osd_char16_row = 16'h7ff0;
                        4'd5:  F_osd_char16_row = 16'h0840;
                        4'd6:  F_osd_char16_row = 16'h1040;
                        4'd7:  F_osd_char16_row = 16'h1c80;
                        4'd8:  F_osd_char16_row = 16'h0300;
                        4'd9:  F_osd_char16_row = 16'h0cc0;
                        4'd10: F_osd_char16_row = 16'h7020;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_LU: begin
                    case(I_row)
                        4'd0:  F_osd_char16_row = 16'h79e0;
                        4'd1:  F_osd_char16_row = 16'h4a20;
                        4'd2:  F_osd_char16_row = 16'h4d40;
                        4'd3:  F_osd_char16_row = 16'h7880;
                        4'd4:  F_osd_char16_row = 16'h1140;
                        4'd5:  F_osd_char16_row = 16'h1630;
                        4'd6:  F_osd_char16_row = 16'h5be0;
                        4'd7:  F_osd_char16_row = 16'h5220;
                        4'd8:  F_osd_char16_row = 16'h5220;
                        4'd9:  F_osd_char16_row = 16'h5be0;
                        4'd10: F_osd_char16_row = 16'h6220;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_C: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h03f0;
                        4'd3:  F_osd_char16_row = 16'h0c0c;
                        4'd4:  F_osd_char16_row = 16'h1800;
                        4'd5:  F_osd_char16_row = 16'h3000;
                        4'd6:  F_osd_char16_row = 16'h3000;
                        4'd7:  F_osd_char16_row = 16'h3000;
                        4'd8:  F_osd_char16_row = 16'h3000;
                        4'd9:  F_osd_char16_row = 16'h3000;
                        4'd10: F_osd_char16_row = 16'h1800;
                        4'd11: F_osd_char16_row = 16'h0c0c;
                        4'd12: F_osd_char16_row = 16'h03f0;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_N: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h300c;
                        4'd3:  F_osd_char16_row = 16'h380c;
                        4'd4:  F_osd_char16_row = 16'h3c0c;
                        4'd5:  F_osd_char16_row = 16'h360c;
                        4'd6:  F_osd_char16_row = 16'h330c;
                        4'd7:  F_osd_char16_row = 16'h318c;
                        4'd8:  F_osd_char16_row = 16'h30cc;
                        4'd9:  F_osd_char16_row = 16'h306c;
                        4'd10: F_osd_char16_row = 16'h303c;
                        4'd11: F_osd_char16_row = 16'h301c;
                        4'd12: F_osd_char16_row = 16'h300c;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_T: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h3ffc;
                        4'd3:  F_osd_char16_row = 16'h03c0;
                        4'd4:  F_osd_char16_row = 16'h03c0;
                        4'd5:  F_osd_char16_row = 16'h03c0;
                        4'd6:  F_osd_char16_row = 16'h03c0;
                        4'd7:  F_osd_char16_row = 16'h03c0;
                        4'd8:  F_osd_char16_row = 16'h03c0;
                        4'd9:  F_osd_char16_row = 16'h03c0;
                        4'd10: F_osd_char16_row = 16'h03c0;
                        4'd11: F_osd_char16_row = 16'h03c0;
                        4'd12: F_osd_char16_row = 16'h03c0;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_COLON: begin
                    case(I_row)
                        4'd6:  F_osd_char16_row = 16'h0180;
                        4'd7:  F_osd_char16_row = 16'h0180;
                        4'd10: F_osd_char16_row = 16'h0180;
                        4'd11: F_osd_char16_row = 16'h0180;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                default: F_osd_char16_row = 16'h0000;
            endcase
        end
    endfunction

    // Only inputs 0..23 are used by the 24-pixel glyph cells. This exact
    // lookup replaces the wide constant multiply/divide in the glyph path.
    function [3:0] F_scale24;
        input [4:0] value;
        begin
            case(value)
                0,1:F_scale24=0; 2:F_scale24=1;
                3,4:F_scale24=2; 5:F_scale24=3;
                6,7:F_scale24=4; 8:F_scale24=5;
                9,10:F_scale24=6; 11:F_scale24=7;
                12,13:F_scale24=8; 14:F_scale24=9;
                15,16:F_scale24=10; 17:F_scale24=11;
                18,19:F_scale24=12; 20:F_scale24=13;
                21,22:F_scale24=14; 23:F_scale24=15;
                default:F_scale24=0;
            endcase
        end
    endfunction

    // Hexadecimal conversion keeps the full 16-bit motion sample count while
    // using only a small nibble-to-ASCII mux in the pixel renderer.
    function [7:0] F_hex_char;
        input [3:0] value;
        begin
            if(value < 4'd10)
                F_hex_char = CHAR_0 + value;
            else
                F_hex_char = 8'h41 + (value - 4'd10);
        end
    endfunction

    // One double-dabble step. Five nibbles are adjusted in parallel, then
    // shifted once per pixel clock by the small sequential converter.
    function [19:0] F_motion_bcd_next;
        input [19:0] bcd;
        input [15:0] binary;
        integer i;
        reg [19:0] adjusted;
        begin
            adjusted = bcd;
            for(i=0; i<5; i=i+1) begin
                if(adjusted[i*4+:4] >= 4'd5)
                    adjusted[i*4+:4] = adjusted[i*4+:4] + 4'd3;
            end
            F_motion_bcd_next = {adjusted[18:0],binary[15]};
        end
    endfunction

    assign O_video_rd_en = I_video_rd_req;

    // Double-dabble conversion uses four 4-bit add/compare units, one input
    // bit per clock. It is outside the pixel renderer and never divides.
    // A result that finishes after blanking waits for the next vertical
    // blank; even an unexpectedly short blank cannot tear the visible row.
    always @* begin
        S_lat_bcd_adjust = S_lat_bcd_work;
        for(S_lat_digit=0; S_lat_digit<4; S_lat_digit=S_lat_digit+1)
            if(S_lat_bcd_work[S_lat_digit*4+:4] >= 4'd5)
                S_lat_bcd_adjust[S_lat_digit*4+:4] =
                    S_lat_bcd_work[S_lat_digit*4+:4] + 4'd3;
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_lat_seen<=0; S_lat_busy<=0; S_lat_ready<=0; S_lat_step<=0;
            S_lat_binary<=0; S_lat_bcd_work<=0; S_lat_frame_work<=0;
            S_lat_valid_work<=0; S_lat_overflow_work<=0;
            S_lat_frame<=0; S_lat_bcd<=0; S_lat_valid<=0; S_lat_overflow<=0;
        end else if(LATENCY_OSD_ENABLE != 0) begin
            if(S_lat_busy) begin
                S_lat_bcd_work <= {S_lat_bcd_adjust[14:0],S_lat_binary[15]};
                S_lat_binary <= {S_lat_binary[14:0],1'b0};
                if(S_lat_step == 4'd15) begin
                    S_lat_busy<=0; S_lat_ready<=1;
                end else S_lat_step<=S_lat_step+1'b1;
            end else if(I_video_vsync && !I_video_de) begin
                if(S_lat_ready) begin
                    S_lat_frame<=S_lat_frame_work; S_lat_bcd<=S_lat_bcd_work;
                    S_lat_valid<=S_lat_valid_work; S_lat_overflow<=S_lat_overflow_work;
                    S_lat_ready<=0;
                end else if(I_latency_toggle != S_lat_seen) begin
                    S_lat_seen<=I_latency_toggle;
                    S_lat_frame_work<=I_latency_frame;
                    S_lat_valid_work<=I_latency_valid;
                    S_lat_overflow_work<=I_latency_tenth_ms > 16'd9999;
                    S_lat_binary<=I_latency_tenth_ms; S_lat_bcd_work<=0;
                    S_lat_step<=0; S_lat_busy<=1;
                end
            end
        end
    end

    generate
        if (LOGO_ENABLE != 0) begin : g_logo_rom
            anlogic_logo_rom u_anlogic_logo_rom(
                .I_clk   ( I_clk ),
                .I_x     ( S_x - LOGO_X ),
                .I_y     ( S_y - LOGO_Y ),
                .O_pixel ( S_logo_pixel_r )
            );
        end else begin : g_logo_off
            assign S_logo_pixel_r = 25'd0;
        end
    endgenerate

    // Native 16x16 Chinese and 8x16 ASCII, one shared synchronous ROM.
    // Address stage + ROM read keep the original two-pixel alignment.
    wire S_compact_panel_on, S_compact_text_on, S_compact_border;
    wire [23:0] S_compact_color;
    wire [7:0] S_compact_glyph;
    wire [3:0] S_compact_row;
    wire [15:0] S_compact_bits;
    wire [19:0] S_frame_decimal;
    wire [15:0] S_x_decimal, S_y_decimal;
    wire [23:0] S_area_decimal;
    // The latency mailbox commits during vertical blanking. Snapshot after
    // active video starts so the frame number and latency belong to the same
    // committed update, including the first frame after reset. Conversion
    // finishes in 96 clocks, well before the first OSD row at y=64.
    wire S_osd_snapshot_start = I_video_de && !I_video_user &&
                                (S_y == 12'd0) && (S_x == 12'd4);
    osd_decimal_snapshot u_osd_decimal(
        .clk(I_clk), .rst_n(I_rst_n), .frame_start(S_osd_snapshot_start),
        .frame_number((LATENCY_OSD_ENABLE!=0)?S_lat_frame:S_frame_cnt[15:0]),
        .target_x(I_ovl_cx), .target_y(I_ovl_cy), .target_area(I_ovl_area),
        .frame_bcd(S_frame_decimal), .target_x_bcd(S_x_decimal),
        .target_y_bcd(S_y_decimal), .area_bcd(S_area_decimal)
    );
    osd_compact_panel u_osd_compact_panel(
        .clk(I_clk), .rst_n(I_rst_n), .x(S_x), .y(S_y),
        .pcb_mode(I_ovl_pcb), .pcb_status(I_pcb_status),
        .algo_mode(I_algo_mode), .he_on(I_he_on),
        .lat_valid(S_lat_valid), .lat_overflow(S_lat_overflow),
        .frame_bcd(S_frame_decimal), .lat_bcd(S_lat_bcd),
        .target_x_bcd(S_x_decimal), .target_y_bcd(S_y_decimal),
        .area_bcd(S_area_decimal), .remote(I_ovl_remote),
        .ovl_valid(I_ovl_valid), .target_color(I_ovl_color),
        .shape3(I_ovl_shape3), .target_shape(I_ovl_shape),
        .motion_enable(I_motion_enable), .motion_bcd(S_motion_bcd),
        .panel_on(S_compact_panel_on), .panel_border(S_compact_border),
        .text_on(S_compact_text_on), .text_color(S_compact_color),
        .font_glyph(S_compact_glyph), .font_row(S_compact_row),
        .font_row_bits(S_compact_bits)
    );
    osd_compact_font_rom u_osd_compact_font(
        .clk(I_clk), .glyph(S_compact_glyph), .row(S_compact_row),
        .row_bits(S_compact_bits)
    );

    // Mode-number -> 4-letter name.  Pure mux on a signal that only changes on
    // a key press; the OSD reads the steady value.
    always @(*) begin
        case(I_algo_mode)
            5'd0 : begin S_md_c0=8'h4f; S_md_c1=8'h52; S_md_c2=8'h49; S_md_c3=8'h47; end // ORIG
            5'd1 : begin S_md_c0=8'h47; S_md_c1=8'h52; S_md_c2=8'h41; S_md_c3=8'h59; end // GRAY
            5'd2 : begin S_md_c0=8'h54; S_md_c1=8'h48; S_md_c2=8'h52; S_md_c3=8'h45; end // THRE
            5'd3 : begin S_md_c0=8'h49; S_md_c1=8'h4e; S_md_c2=8'h56; S_md_c3=8'h54; end // INVT
            5'd4 : begin S_md_c0=8'h52; S_md_c1=8'h45; S_md_c2=8'h44; S_md_c3=8'h43; end // REDC
            5'd5 : begin S_md_c0=8'h50; S_md_c1=8'h4f; S_md_c2=8'h53; S_md_c3=8'h54; end // POST
            5'd6 : begin S_md_c0=8'h53; S_md_c1=8'h41; S_md_c2=8'h54; S_md_c3=8'h55; end // SATU
            5'd7 : begin S_md_c0=8'h53; S_md_c1=8'h4f; S_md_c2=8'h42; S_md_c3=8'h4c; end // SOBL
            5'd8 : begin S_md_c0=8'h45; S_md_c1=8'h44; S_md_c2=8'h47; S_md_c3=8'h50; end // EDGP
            5'd9 : begin S_md_c0=8'h45; S_md_c1=8'h4d; S_md_c2=8'h42; S_md_c3=8'h53; end // EMBS
            5'd10: begin S_md_c0=8'h52; S_md_c1=8'h41; S_md_c2=8'h49; S_md_c3=8'h4e; end // RAIN
            5'd11: begin S_md_c0=8'h45; S_md_c1=8'h52; S_md_c2=8'h4f; S_md_c3=8'h44; end // EROD
            5'd12: begin S_md_c0=8'h44; S_md_c1=8'h49; S_md_c2=8'h4c; S_md_c3=8'h41; end // DILA
            5'd13: begin S_md_c0=8'h4d; S_md_c1=8'h4f; S_md_c2=8'h52; S_md_c3=8'h50; end // MORP
            5'd14: begin S_md_c0=8'h42; S_md_c1=8'h4c; S_md_c2=8'h55; S_md_c3=8'h45; end // BLUE
            5'd15: begin S_md_c0=8'h4c; S_md_c1=8'h49; S_md_c2=8'h46; S_md_c3=8'h54; end // LIFT
            5'd16: begin S_md_c0=8'h43; S_md_c1=8'h4e; S_md_c2=8'h54; S_md_c3=8'h52; end // CNTR
            5'd17: begin S_md_c0=8'h47; S_md_c1=8'h41; S_md_c2=8'h4d; S_md_c3=8'h4c; end // GAML
            5'd18: begin S_md_c0=8'h43; S_md_c1=8'h41; S_md_c2=8'h52; S_md_c3=8'h54; end // CART
            default: begin S_md_c0=8'h4e; S_md_c1=8'h4f; S_md_c2=8'h4e; S_md_c3=8'h45; end // NONE
        endcase
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_user) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_de) begin
            if(I_video_last) begin
                S_x <= 12'd0;
                S_y <= S_y + 12'd1;
            end
            else begin
                S_x <= S_x + 12'd1;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_frame_cnt <= 32'd0;
            S_cnt_d0 <= 4'd0;
            S_cnt_d1 <= 4'd0;
            S_cnt_d2 <= 4'd0;
            S_cnt_d3 <= 4'd0;
            S_cnt_d4 <= 4'd0;
            S_cnt_d5 <= 4'd0;
        end
        else if(I_video_user) begin
            S_frame_cnt <= S_frame_cnt + 32'd1;
            if(S_cnt_d0 == 4'd9) begin
                S_cnt_d0 <= 4'd0;
                if(S_cnt_d1 == 4'd9) begin
                    S_cnt_d1 <= 4'd0;
                    if(S_cnt_d2 == 4'd9) begin
                        S_cnt_d2 <= 4'd0;
                        if(S_cnt_d3 == 4'd9) begin
                            S_cnt_d3 <= 4'd0;
                            if(S_cnt_d4 == 4'd9) begin
                                S_cnt_d4 <= 4'd0;
                                if(S_cnt_d5 == 4'd9)
                                    S_cnt_d5 <= 4'd0;
                                else
                                    S_cnt_d5 <= S_cnt_d5 + 4'd1;
                            end
                            else
                                S_cnt_d4 <= S_cnt_d4 + 4'd1;
                        end
                        else
                            S_cnt_d3 <= S_cnt_d3 + 4'd1;
                    end
                    else
                        S_cnt_d2 <= S_cnt_d2 + 4'd1;
                end
                else
                    S_cnt_d1 <= S_cnt_d1 + 4'd1;
            end
            else
                S_cnt_d0 <= S_cnt_d0 + 4'd1;
        end
    end

    always @(*) begin
        S_motion_bcd_adjust = F_motion_bcd_next(S_motion_bcd_work,S_motion_bin_work);
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_motion_bcd <= 20'd0;
            S_motion_bcd_work <= 20'd0;
            S_motion_bin_work <= 16'd0;
            S_motion_bcd_step <= 5'd0;
            S_motion_bcd_busy <= 1'b0;
        end else if(I_video_user) begin
            S_motion_bin_work <= I_motion_count;
            S_motion_bcd_work <= 20'd0;
            S_motion_bcd_step <= 5'd0;
            S_motion_bcd_busy <= 1'b1;
        end else if(S_motion_bcd_busy) begin
            S_motion_bin_work <= {S_motion_bin_work[14:0],1'b0};
            S_motion_bcd_work <= S_motion_bcd_adjust;
            if(S_motion_bcd_step == 5'd15) begin
                S_motion_bcd <= S_motion_bcd_adjust;
                S_motion_bcd_busy <= 1'b0;
            end else begin
                S_motion_bcd_step <= S_motion_bcd_step + 5'd1;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x_1d <= 12'd0;
            S_x_2d <= 12'd0;
            S_y_1d <= 12'd0;
            S_y_2d <= 12'd0;
            S_dyn_x_2d <= 12'd0;
            S_dyn_y_2d <= 12'd0;
        end
        else begin
            S_x_1d <= S_x;
            S_x_2d <= S_x_1d;
            S_y_1d <= S_y;
            S_y_2d <= S_y_1d;
            S_dyn_x_2d <= S_x_1d-DYN_OSD_X;
            S_dyn_y_2d <= S_y_1d-DYN_OSD_Y;
        end
    end

    // The lossless palette ROM registers two reads from S_x/S_y, matching
    // S_x_2d/S_y_2d and the existing RGB/control pipeline without a new delay.

    always @(*) begin
        S_osd_hit   = 1'b0;
        S_osd_color = 24'd0;
        S_char_idx = 4'd0;
        S_char_row = 3'd0;
        S_char_col = 3'd0;
        S_char_bits = 5'd0;
        S_char_on = 1'b0;
        S_logo_blue_on = 1'b0;
        S_logo_red_on = 1'b0;
        S_logo_tmp_y = 12'd0;
        S_logo_red_band = 4'd0;
        S_logo_red_x_start = 12'd0;
        S_logo_red_x_end = 12'd0;
        S_dyn_x = 12'd0;
        S_dyn_y = 12'd0;
        S_dyn_char = 4'd0;
        S_dyn_col = 3'd0;
        S_dyn_row = 3'd0;
        S_dyn_bits = 5'd0;
        S_dyn_on = 1'b0;
        S_dyn_digit_idx = 4'd0;
        S_dyn_digit_x = 12'd0;
        S_dyn_seg = 7'd0;
        S_lbl_row = 3'd0;
        S_lbl_col = 3'd0;
        S_lbl_idx = 2'd0;
        S_lbl_bits = 5'd0;
        S_lbl_local_x = 7'd0;
        S_dyn_dec_digit = 4'd0;
        S_cn_local_x = 5'd0;
        S_cn_local_y = 5'd0;
        S_cn_col = 4'd0;
        S_cn_row = 4'd0;
        S_cn_row_bits = 16'd0;
        S_cn_on = 1'b0;
        S_cn_scale_x = 10'd0;
        S_cn_scale_y = 10'd0;
        S_pf_char = 8'd0;
        S_md_row = 1'b0;
        S_pf_local_x = 5'd0;
        S_pf_local_y = 5'd0;
        S_pf_col = 4'd0;
        S_pf_row = 4'd0;
        S_pf_on = 1'b0;
        S_pf_scale_x = 10'd0;
        S_pf_scale_y = 10'd0;
        S_large_char = 8'h20;
        S_large_row = 4'd0;
        S_large_col = 3'd0;
        S_large_cell = 5'd0;
        S_large_line = 3'd7;
        S_large_color = COLOR_DYN_TEXT;
        S_lbl_x = 12'd0;
        S_lbl_y = 12'd0;
        S_lbl_char = 4'd0;
        S_tgt_x3 = 4'd0; S_tgt_x2 = 4'd0; S_tgt_x1 = 4'd0; S_tgt_x0 = 4'd0;
        S_tgt_y2 = 4'd0; S_tgt_y1 = 4'd0; S_tgt_y0 = 4'd0;
        S_tgt_a3 = 4'd0; S_tgt_a2 = 4'd0; S_tgt_a1 = 4'd0; S_tgt_a0 = 4'd0;

        // Fixed-width hexadecimal metadata avoids four variable dividers in
        // the 75 MHz pixel path while retaining live coordinates and area.
        S_tgt_x3 = 4'd0;
        S_tgt_x2 = {1'b0,I_ovl_cx[10:8]};
        S_tgt_x1 = I_ovl_cx[7:4];
        S_tgt_x0 = I_ovl_cx[3:0];
        S_tgt_y2 = 4'd0;
        S_tgt_y1 = I_ovl_cy[7:4];
        S_tgt_y0 = I_ovl_cy[3:0];
        S_tgt_a3 = I_ovl_area[15:12];
        S_tgt_a2 = I_ovl_area[11:8];
        S_tgt_a1 = I_ovl_area[7:4];
        S_tgt_a0 = I_ovl_area[3:0];

        if(S_video_de_2d) begin
            // Two synchronous reads from S_x/S_y align the logo with S_x_2d/S_y_2d.
            if((LOGO_ENABLE != 0) &&
               (S_x_2d >= LOGO_X) && (S_x_2d < (LOGO_X + LOGO_W)) &&
               (S_y_2d >= LOGO_Y) && (S_y_2d < (LOGO_Y + LOGO_H))) begin
                if(S_logo_pixel_r[24]) begin
                    S_osd_hit   = 1'b1;
                    S_osd_color = S_logo_pixel_r[23:0];
                end
            end

            // Preserve semantic text colors through the final priority stage.
            if(!S_osd_hit && S_compact_panel_on) begin
                S_osd_hit = 1'b1;
                S_osd_color = S_compact_text_on ? S_compact_color :
                              S_compact_border ? COLOR_DYN_BORDER : COLOR_DYN_PANEL;
            end

        end
    end

    // ---- target overlay (SW1) --------------------------------------------
    // Drawn over the video but under the OSD text, so "CNT:" / "MODE:xxxx"
    // stay readable when a target is boxed.
    wire S_ovl_in    = (S_x_2d >= I_ovl_x0) && (S_x_2d <= I_ovl_x1) &&
                       (S_y_2d >= I_ovl_y0) && (S_y_2d <= I_ovl_y1);
    wire S_ovl_edge  = S_ovl_in && ((S_x_2d <= (I_ovl_x0 + 10'd3)) ||
                                    (S_x_2d >= (I_ovl_x1 - 10'd3)) ||
                                    (S_y_2d <= (I_ovl_y0 + 10'd3)) ||
                                    (S_y_2d >= (I_ovl_y1 - 10'd3)));
    wire S_ovl_cross = !I_ovl_pcb && (((S_x_2d == I_ovl_cx) &&
                        (S_y_2d >= (I_ovl_cy - 10'd5)) && (S_y_2d <= (I_ovl_cy + 10'd5))) ||
                       ((S_y_2d == I_ovl_cy) &&
                        (S_x_2d >= (I_ovl_cx - 10'd5)) && (S_x_2d <= (I_ovl_cx + 10'd5))));
    wire S_ovl_hit   = I_ovl_on && I_ovl_valid && !I_multi_valid && (S_ovl_edge || S_ovl_cross);
    wire [23:0] S_ovl_color = S_ovl_cross ? 24'hffff00 : 24'h00ff00;

    // Motion box: same rectangle test, checked first so it wins on overlap.
    wire S_mot_in   = (S_x_2d >= I_mot_x0) && (S_x_2d <= I_mot_x1) &&
                      (S_y_2d >= I_mot_y0) && (S_y_2d <= I_mot_y1);
    wire S_mot_edge = I_mot_on && S_mot_in &&
                      ((S_x_2d <= (I_mot_x0 + 10'd3)) || (S_x_2d >= (I_mot_x1 - 10'd3)) ||
                       (S_y_2d <= (I_mot_y0 + 10'd3)) || (S_y_2d >= (I_mot_y1 - 10'd3)));

    wire S_multi_edge;
    wire S_copy_edge;wire [23:0] S_copy_color;
    doc_copy_overlay u_copy_overlay(.clk(I_clk),.rst_n(I_rst_n),
        .enable(I_copy_mode===1'b1),.state(I_copy_state),.x(S_x),.y(S_y),
        .hit(S_copy_edge),.color(S_copy_color));
    wire [23:0] S_multi_color;
    hxa_multibox_overlay #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT))
      u_multi_overlay(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_x(S_x),.I_y(S_y),
        .I_frame_start(I_video_user),.I_aux_online(I_aux_online),
        .I_update(I_multi_toggle),.I_valid(I_multi_valid && I_ovl_on),
        .I_count(I_multi_count),.I_boxes(I_multi_boxes),
        .O_hit(S_multi_edge),.O_color(S_multi_color));

    // ---- final display decision, split over two registers ----------------
    // Priority is unchanged: status corner > OSD text > motion box > target
    // box/cross > plain video.  Stage A captures the OSD decode (and the
    // cheap overlay comparisons); stage B is then a 4-way mux on flop
    // outputs, which is what keeps the 24-bit output mux off the LUTROM
    // critical path.
    // The 8x8 status colour tile was useful during bring-up, but it is
    // visually indistinguishable from a CART source pixel and makes the
    // remaining upper-left frame alignment harder to judge.  Keep the status
    // colour decode for the OSD/debug path, while disabling this corner
    // overlay in the production display.
    wire S_corner_c = 1'b0;
    wire [23:0] S_stat_col_c = I_debug_status[0] ? 24'hff0000 :
                               I_debug_status[1] ? 24'hff8000 :
                               I_debug_status[3] ? 24'h00ffff :
                               I_debug_status[2] ? 24'h00ff00 : 24'h003300;
    wire S_disp_hit_c = S_corner_a | S_osd_hit_a | S_mot_edge_a | S_multi_edge_a | S_ovl_hit_a;
    wire [23:0] S_disp_col_c = S_corner_a   ? S_stat_col_a  :
                               S_osd_hit_a  ? S_osd_color_a :
                               S_mot_edge_a ? 24'hff00ff    :
                               S_multi_edge_a ? S_multi_color_a :
                                              S_ovl_color_a;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_video_vsync_1d <= 1'b0;
            S_video_vsync_2d <= 1'b0;
            S_video_hsync_1d <= 1'b0;
            S_video_hsync_2d <= 1'b0;
            S_video_de_1d    <= 1'b0;
            S_video_de_2d    <= 1'b0;
            S_video_de_3d    <= 1'b0;
            S_video_vsync_3d <= 1'b0;
            S_video_hsync_3d <= 1'b0;
            S_video_data_3d  <= 24'd0;
            S_video_de_4d    <= 1'b0;
            S_video_vsync_4d <= 1'b0;
            S_video_hsync_4d <= 1'b0;
            S_video_data_4d  <= 24'd0;
            S_disp_hit       <= 1'b0;
            S_disp_col       <= 24'd0;
            S_osd_hit_a      <= 1'b0;
            S_osd_color_a    <= 24'd0;
            S_corner_a       <= 1'b0;
            S_stat_col_a     <= 24'd0;
            S_mot_edge_a     <= 1'b0;
            S_multi_edge_a   <= 1'b0;
            S_multi_color_a  <= 24'd0;
            S_ovl_hit_a      <= 1'b0;
            S_ovl_color_a    <= 24'd0;
            O_hdmi_vsync     <= 1'b0;
            O_hdmi_hsync     <= 1'b0;
            O_hdmi_de        <= 1'b0;
            O_hdmi_data      <= 24'd0;
        end
        else begin
            S_video_vsync_1d <= I_video_vsync;
            S_video_vsync_2d <= S_video_vsync_1d;
            S_video_vsync_3d <= S_video_vsync_2d;
            S_video_vsync_4d <= S_video_vsync_3d;
            O_hdmi_vsync     <= S_video_vsync_4d;

            S_video_hsync_1d <= I_video_hsync;
            S_video_hsync_2d <= S_video_hsync_1d;
            S_video_hsync_3d <= S_video_hsync_2d;
            S_video_hsync_4d <= S_video_hsync_3d;
            O_hdmi_hsync     <= S_video_hsync_4d;

            S_video_de_1d    <= I_video_de;
            S_video_de_2d    <= S_video_de_1d;
            S_video_de_3d    <= S_video_de_2d;
            S_video_de_4d    <= S_video_de_3d;
            O_hdmi_de        <= S_video_de_4d;
            S_video_data_1d  <= I_video_rd_data;
            S_video_data_2d  <= S_video_data_1d;
            S_video_data_3d  <= S_video_data_2d;
            S_video_data_4d  <= S_video_data_3d;

            // stage A: the OSD decode for the pixel whose coords are S_x_2d
            S_osd_hit_a   <= S_osd_hit;
            S_osd_color_a <= S_osd_color;
            S_corner_a    <= S_corner_c;
            S_stat_col_a  <= S_stat_col_c;
            S_mot_edge_a  <= S_mot_edge;
            S_multi_edge_a <= S_copy_edge||S_multi_edge;
            S_multi_color_a <= S_copy_edge?S_copy_color:S_multi_color;
            S_ovl_hit_a   <= S_ovl_hit;
            S_ovl_color_a <= S_ovl_color;

            // stage B: pick, one pixel later -- matching S_video_data_4d
            S_disp_hit <= S_disp_hit_c;
            S_disp_col <= S_disp_col_c;

            if(DEBUG_MODE == 1) begin
                if(S_video_de_2d) begin
                    if(S_x < 12'd128)
                        O_hdmi_data <= 24'hff0000;
                    else if(S_x < 12'd256)
                        O_hdmi_data <= 24'h00ff00;
                    else if(S_x < 12'd384)
                        O_hdmi_data <= 24'h0000ff;
                    else if(S_x < 12'd640)
                        O_hdmi_data <= 24'hffff00;
                    else if(S_x < 12'd640)
                        O_hdmi_data <= 24'h00ffff;
                    else if(S_x < 12'd960)
                        O_hdmi_data <= 24'hff00ff;
                    else if(S_x < 12'd896)
                        O_hdmi_data <= 24'hffffff;
                    else
                        O_hdmi_data <= 24'h202020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 2) begin
                if(S_video_de_2d) begin
                    case (I_debug_status)
                        4'b0000: O_hdmi_data <= 24'h000000;
                        4'b0001: O_hdmi_data <= 24'hff0000;
                        4'b0011: O_hdmi_data <= 24'hffff00;
                        4'b0111: O_hdmi_data <= 24'h00ff00;
                        4'b1111: O_hdmi_data <= I_video_rd_data;
                        default: O_hdmi_data <= 24'h0000ff;
                    endcase
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 3) begin
                if(S_video_de_2d) begin
                    if(S_x < 12'd320)
                        O_hdmi_data <= I_debug_status[0] ? 24'hff8000 : 24'h201000;
                    else if(S_x < 12'd640)
                        O_hdmi_data <= I_debug_status[1] ? 24'hffff00 : 24'h202000;
                    else if(S_x < 12'd960)
                        O_hdmi_data <= I_debug_status[2] ? 24'hff0000 : 24'h200000;
                    else
                        O_hdmi_data <= I_debug_status[3] ? 24'h00ffff : 24'h002020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else begin
                // Top-left 8x8 status block (visible in normal mode):
                //   red   = frame word-count mismatch (framing error)
                //   orange= frame-start not on a data beat (shifted frame)
                //   green = framing OK, data flowing
                //   cyan  = DDR read data non-zero
                if(S_disp_hit)
                    O_hdmi_data <= S_disp_col;
                else
                    O_hdmi_data <= S_video_data_4d;
            end
        end
    end

endmodule
