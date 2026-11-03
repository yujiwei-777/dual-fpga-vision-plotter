// Stream-compatible image styles for the 4-pixel/96-bit RGB video path.
// Spatial styles use a 3x3 window over four-pixel groups.  This keeps the
// throughput and packing identical to the existing MIPI -> DDR -> HDMI path.
module style_transfer_96 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    // The compact runtime mode table contains 19 entries (0..18).  The
    // retired WARM/BRIT/LAPL/HIST paths are intentionally absent; CART is 18.
    parameter NUM_STYLES = 19,
    parameter integer CART_EDGE_THRESHOLD = 48,
    // Keep the module default compatible with the archived 16-level CART
    // reference.  The production top-level selects the stronger 8-level
    // mask explicitly so legacy unit tests and diagnostic modes remain
    // bit-compatible.
    parameter [7:0] CART_QUANT_MASK = 8'hf0,
    // Keep modes 0..17 while allowing the CART renderer to be compiled out.
    // With this disabled, mode 18 uses the ordinary RGB stream path.
    parameter CARTOON_ENABLE = 1'b1,
    // First integration build: retain the complete frame/line pipeline but
    // make mode 0 a compile-time RGB pass-through.  This removes the large
    // dynamic style arithmetic from the timing-critical path while validating
    // tuser/tlast, ready and line-buffer alignment.  Set to 0 for full modes.
    parameter SIMPLE_BYPASS = 1'b0,
    // Non-zero selects one compile-time style and lets synthesis remove the
    // other style arithmetic.  0 keeps the run-time I_style_mode selection.
    parameter integer FIXED_STYLE_MODE = -1
)(
    input               I_clk,
    input               I_rst_n,
    input               [4:0] I_style_mode,
    input               I_tlast,
    input               I_tuser,
    input               [95:0] I_tdata,
    input               I_tvalid,
    input               O_tready,
    output              I_tready,
    output wire          O_tlast,
    output wire          O_tuser,
    output wire          [95:0] O_tdata,
    output wire          O_tvalid
);
    reg [95:0] base_data;
    reg base_valid,base_user,base_last,base_cart,out_pend_cart;
    wire base_ready;
    generate
      if (CARTOON_ENABLE) begin : g_cartoon
        cartoon_96 #(.IMG_WIDTH(IMG_WIDTH),.IMG_HEIGHT(IMG_HEIGHT),
                     .EDGE_THRESHOLD(CART_EDGE_THRESHOLD),
                     .QUANT_MASK(CART_QUANT_MASK)) u_cart(
            .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tdata(base_data),.I_tvalid(base_valid),
            .I_tuser(base_user),.I_tlast(base_last),.I_cart(base_cart),.I_tready(base_ready),
            .O_tready(O_tready),.O_tdata(O_tdata),.O_tvalid(O_tvalid),.O_tuser(O_tuser),.O_tlast(O_tlast));
      end else begin : g_no_cartoon
        assign base_ready = !base_valid || O_tready;
        assign O_tdata = base_data;
        assign O_tvalid = base_valid;
        assign O_tuser = base_user;
        assign O_tlast = base_last;
      end
    endgenerate
    localparam GROUPS = IMG_WIDTH / 4;
    // Line 1 and line 2 share one 16-bit ERAM word. Retire both row
    // updates together one cycle later and forward a colliding low byte;
    // this preserves the legacy pixel timing with one read/one write port.
    (* ram_style = "bram" *) reg [15:0] line_mem [0:GROUPS-1];

    reg [8:0] x_grp;
    reg [9:0] y_pos;
    reg [4:0] active_style;
    reg [7:0] top_d2, top_d1;
    reg [7:0] mid_d2, mid_d1;
    reg [7:0] bot_d2, bot_d1;

    // RAM outputs have no asynchronous reset, allowing actual block RAMs.
    // The line1->line2 transfer retires one clock later; a read collision
    // forwards that pending value so the original video latency is unchanged.
    reg [7:0] ram_mid_r, ram_top_r, deferred_gray, mid_forward_data;
    reg ram_read_live, line2_wr_pending, line2_forward;
    reg [8:0] line2_wr_addr;
    reg [7:0] line2_forward_data;
    wire [7:0] mid_cur_r = !ram_read_live ? 8'd0 : (line2_forward ? mid_forward_data : ram_mid_r);
    wire [7:0] top_cur_r = !ram_read_live ? 8'd0 :
                          (line2_forward ? line2_forward_data : ram_top_r);

    reg        pending_valid;
    reg        frame_user_pending;
    reg [4:0]  frame_style_pending;
    reg        pending_tlast;
    reg        pending_tuser;
    reg [4:0]  pending_style;
    reg [23:0] pending_pix0, pending_pix1, pending_pix2, pending_pix3;
    reg [7:0]  pending_gray0, pending_gray1, pending_gray2, pending_gray3;
    reg [7:0]  pending_group_gray;
    reg [7:0]  pending_group_gray_d1;

    reg        stage_valid;
    reg        stage_tlast;
    reg        stage_tuser;
    reg [4:0]  stage_style;
    reg [3:0]  stage_class;
    reg [1:0]  stage_enhance_sel;
    reg [23:0] stage_pix0, stage_pix1, stage_pix2, stage_pix3;
    reg [7:0]  stage_gray0, stage_gray1, stage_gray2, stage_gray3;
    reg [7:0]  stage_top_d2, stage_top_d1, stage_top_cur;
    reg [7:0]  stage_mid_d2, stage_mid_d1, stage_mid_cur;
    reg [7:0]  stage_bot_d2, stage_bot_d1, stage_group_gray;
    reg        stage_window_valid;

    reg        calc_valid;
    reg        calc_tlast;
    reg        calc_tuser;
    reg [4:0]  calc_style;
    reg [3:0]  calc_class;
    reg [1:0]  calc_enhance_sel;
    reg [23:0] calc_pix0, calc_pix1, calc_pix2, calc_pix3;
    reg [7:0]  calc_gray0, calc_gray1, calc_gray2, calc_gray3;
    reg [7:0] calc_feature;

    reg [95:0] out_pend_data;
    reg        out_pend_valid, out_pend_last, out_pend_user;

    wire [23:0] in_pix0 = I_tdata[95:72];
    wire [23:0] in_pix1 = I_tdata[71:48];
    wire [23:0] in_pix2 = I_tdata[47:24];
    wire [23:0] in_pix3 = I_tdata[23:0];

    function [7:0] clamp8;
        input signed [12:0] value;
        begin
            if (value < 0) clamp8 = 8'h00;
            else if (value > 255) clamp8 = 8'hff;
            else clamp8 = value[7:0];
        end
    endfunction
    function [7:0] gray8;
        input [7:0] r; input [7:0] g; input [7:0] b;
        begin
            // Maximum is 63+127+15+31=236; no saturation is possible.
            gray8 = (r >> 2) + (g >> 1) + (g >> 4) + (b >> 3);
        end
    endfunction
    function [7:0] max2; input [7:0] a; input [7:0] b; begin max2 = (a > b) ? a : b; end endfunction
    function [7:0] min2; input [7:0] a; input [7:0] b; begin min2 = (a < b) ? a : b; end endfunction
    // Kept as reference functions for the arithmetic-equivalence testbench.
    // The active datapath below uses the shared spatial intermediates instead
    // of instantiating these functions independently.
    function [7:0] sobel8;
        input [7:0] p00; input [7:0] p01; input [7:0] p02;
        input [7:0] p10; input [7:0] p11; input [7:0] p12;
        input [7:0] p20; input [7:0] p21; input [7:0] p22;
        reg signed [10:0] gx, gy;
        reg [10:0] mag;
        begin
            gx = (p02 + (p12 << 1) + p22) - (p00 + (p10 << 1) + p20);
            gy = (p20 + (p21 << 1) + p22) - (p00 + (p01 << 1) + p02);
            if (gx < 0) gx = -gx;
            if (gy < 0) gy = -gy;
            mag = gx + gy;
            sobel8 = clamp8(mag);
        end
    endfunction
    function [7:0] emboss8;
        input [7:0] p00; input [7:0] p01; input [7:0] p02;
        input [7:0] p10; input [7:0] p11; input [7:0] p12;
        input [7:0] p20; input [7:0] p21; input [7:0] p22;
        reg signed [12:0] value;
        begin
            value = ((p12 + p21 + (p22 << 1)) - (p01 + p10 + (p00 << 1))) << 1;
            emboss8 = clamp8(value + 128);
        end
    endfunction
    // Legacy arithmetic reference retained for the archived equivalence
    // bench only.  LAPL is no longer selected by process_pixel.
    function [7:0] laplacian8;
        input [7:0] p00; input [7:0] p01; input [7:0] p02;
        input [7:0] p10; input [7:0] p11; input [7:0] p12;
        input [7:0] p20; input [7:0] p21; input [7:0] p22;
        reg signed [11:0] value;
        begin
            value = p11 + (p11 << 2) - p01 - p10 - p12 - p21;
            laplacian8 = clamp8(value + 128);
        end
    endfunction
    function [7:0] max9;
        input [7:0] p00; input [7:0] p01; input [7:0] p02;
        input [7:0] p10; input [7:0] p11; input [7:0] p12;
        input [7:0] p20; input [7:0] p21; input [7:0] p22;
        begin
            max9 = max2(max2(max2(p00, p01), max2(p02, p10)),
                        max2(max2(p11, p12), max2(max2(p20, p21), p22)));
        end
    endfunction
    function [7:0] min9;
        input [7:0] p00; input [7:0] p01; input [7:0] p02;
        input [7:0] p10; input [7:0] p11; input [7:0] p12;
        input [7:0] p20; input [7:0] p21; input [7:0] p22;
        begin
            min9 = min2(min2(min2(p00, p01), min2(p02, p10)),
                        min2(min2(p11, p12), min2(min2(p20, p21), p22)));
        end
    endfunction
    // Dark-region lift: same fractional correction per channel, implemented
    // as shift/add and saturated to 8 bits.
    function [7:0] lift8;
        input [7:0] value;
        reg [9:0] lifted;
        begin
            lifted = value + ((10'd255 - value) >> 2);
            lift8 = (lifted > 10'd255) ? 8'hff : lifted[7:0];
        end
    endfunction
    // Contrast around 128, with 1.5x gain (delta + delta/2).
    function [7:0] contrast8;
        input [7:0] value;
        reg signed [10:0] delta;
        reg signed [12:0] adjusted;
        begin
            delta = $signed({1'b0, value}) - 11'sd128;
            adjusted = 13'sd128 + delta + (delta >>> 1);
            contrast8 = clamp8(adjusted);
        end
    endfunction
    // Three-segment gamma approximation.  The dark range receives the
    // largest lift and highlights are changed only gently.
    function [7:0] gamma_light8;
        input [7:0] value;
        reg [9:0] adjusted;
        begin
            // Monotonic curve through (0,0),(64,128),(128,160),(255,255).
            if (value < 8'd64)
                adjusted = {2'd0, value} << 1;
            else if (value < 8'd128)
                adjusted = 10'd128 + (({2'd0,value}-10'd64) >> 1);
            else
                adjusted = 10'd160 + ((({2'd0,value}-10'd128) >> 1) + (({2'd0,value}-10'd128) >> 2));
            gamma_light8 = (adjusted > 10'd255) ? 8'hff : adjusted[7:0];
        end
    endfunction
    // SATU/LIFT/CONTR/GAML all add a bounded offset to the input channel.
    // Select the offset before one signed adder and one saturation check.
    // CONTR: 128+(v-128)+floor((v-128)/2) = v+floor(v/2)-64.
    // LIFT: floor((255-v)/4) is exactly the complemented upper six bits.
    function [1:0] style_enhance_sel;
        input [4:0] style;
        begin
            case (style)
                5'd15: style_enhance_sel = 2'd1;
                5'd16: style_enhance_sel = 2'd2;
                5'd17: style_enhance_sel = 2'd3;
                default: style_enhance_sel = 2'd0;
            endcase
        end
    endfunction
    function [7:0] enhance8_sel;
        input [1:0] enhance_sel;
        input [7:0] value;
        input [7:0] gray;
        reg signed [9:0] offset, delta, adjusted;
        begin
            case (enhance_sel)
                2'd0: begin
                    delta = $signed({2'b0,value}) - $signed({2'b0,gray});
                    offset = {1'b0,delta[9:1]};
                end
                2'd1: offset = {4'b0, ~value[7:2]};
                2'd2: offset = {{4{~value[7]}}, value[6:1]};
                default: begin
                    if (value < 8'd64) offset = {1'b0, value};
                    else if (value < 8'd128) offset = {3'b0, value[7:2]};
                    else offset = {4'b0, value[7:3]};
                end
            endcase
            adjusted = $signed({2'b0, value}) + $signed(offset);
            enhance8_sel = adjusted[9] ? 8'h00 : (adjusted[8] ? 8'hff : adjusted[7:0]);
        end
    endfunction
    // Preserve the legacy reference signature used by the archived benches.
    function [7:0] enhance8;
        input [4:0] style;
        input [7:0] value;
        input [7:0] gray;
        begin enhance8 = enhance8_sel(style_enhance_sel(style), value, gray); end
    endfunction
    // All four pixels in a group use one frame style. Decode the style once
    // and pass a compact class to each pixel function; retain the original
    // style only for the four enhancement transfer curves.
    function [3:0] style_class;
        input [4:0] style;
        begin
            case (style)
                5'd1: style_class = 4'd1;
                5'd2: style_class = 4'd2;
                5'd3: style_class = 4'd3;
                5'd4: style_class = 4'd4;
                5'd5: style_class = 4'd5;
                5'd6,5'd15,5'd16,5'd17: style_class = 4'd6;
                5'd7,5'd8,5'd9,5'd11,5'd12,5'd13: style_class = 4'd7;
                5'd10: style_class = 4'd8;
                5'd14: style_class = 4'd9;
                default: style_class = 4'd0;
            endcase
        end
    endfunction
    function [23:0] process_pixel_class;
        input [3:0] style_class_i;
        input [1:0] enhance_sel;
        input [4:0] style;
        input [7:0] r; input [7:0] g; input [7:0] b;
        input [7:0] gray;
        input [7:0] edge_value; input [7:0] emboss_value;
        input [7:0] erode_value; input [7:0] dilate_value;
        input [7:0] morph_value;
        reg signed [9:0] value_r, value_g, value_b, delta;
        reg [16:0] gg, bb, sepia_r, sepia_g, sepia_b;
        begin
            value_r = r; value_g = g; value_b = b; gg = g; bb = b;
            if (SIMPLE_BYPASS) begin
                process_pixel_class = {r, g, b};
            end else if (FIXED_STYLE_MODE == 5'd1) begin
                process_pixel_class = {gray, gray, gray};
            end else case (style_class_i)
                4'd0:  process_pixel_class = {r, g, b};
                4'd1:  process_pixel_class = {gray, gray, gray};
                4'd2:  process_pixel_class = (gray >= 8'd128) ? 24'hffffff : 24'h000000;
                4'd3:  process_pixel_class = {~r, ~g, ~b};
                4'd4:  process_pixel_class = {r, 8'h00, 8'h00};
                4'd5:  process_pixel_class = {r & 8'he0, g & 8'he0, b & 8'he0};
                4'd6:
                    process_pixel_class = {enhance8_sel(enhance_sel,r,gray), enhance8_sel(enhance_sel,g,gray), enhance8_sel(enhance_sel,b,gray)};
                4'd7:  process_pixel_class = (style == 5'd8) ?
                                      {~edge_value, ~edge_value, ~edge_value} :
                                      {edge_value, edge_value, edge_value};
                4'd8: begin
                    if (gray < 64) process_pixel_class = {8'd0, gray << 2, 8'hff};
                    else if (gray < 128) process_pixel_class = {8'd0, 8'hff, 8'hff - ((gray - 64) << 2)};
                    else if (gray < 192) process_pixel_class = {(gray - 128) << 2, 8'hff, 8'd0};
                    else process_pixel_class = {8'hff, 8'hff - ((gray - 192) << 2), 8'd0};
                end
                4'd9:  process_pixel_class = {8'h00, 8'h00, b};
                // CART is applied after the legacy pipeline using per-pixel windows.
                default: process_pixel_class = {r, g, b};
            endcase
        end
    endfunction
    // Pack all four pixels in one mode-select function.  This keeps the
    // mode decode and common edge/morphology selection shared across the
    // four lanes; per-lane arithmetic remains independent.
    function [95:0] process_group_class;
        input [3:0] style_class_i;
        input [1:0] enhance_sel;
        input [4:0] style;
        input [23:0] p0; input [23:0] p1; input [23:0] p2; input [23:0] p3;
        input [7:0] g0; input [7:0] g1; input [7:0] g2; input [7:0] g3;
        input [7:0] edge_value; input [7:0] emboss_value;
        input [7:0] erode_value; input [7:0] dilate_value;
        input [7:0] morph_value;
        reg [23:0] q0, q1, q2, q3;
        begin
            q0 = p0; q1 = p1; q2 = p2; q3 = p3;
            if (SIMPLE_BYPASS) begin
                process_group_class = {p0,p1,p2,p3};
            end else if (FIXED_STYLE_MODE == 5'd1) begin
                process_group_class = {g0,g0,g0,g1,g1,g1,g2,g2,g2,g3,g3,g3};
            end else begin
                case (style_class_i)
                    4'd0: begin q0=p0; q1=p1; q2=p2; q3=p3; end
                    4'd1: begin q0={g0,g0,g0}; q1={g1,g1,g1}; q2={g2,g2,g2}; q3={g3,g3,g3}; end
                    4'd2: begin q0=(g0>=8'd128)?24'hffffff:24'h0; q1=(g1>=8'd128)?24'hffffff:24'h0; q2=(g2>=8'd128)?24'hffffff:24'h0; q3=(g3>=8'd128)?24'hffffff:24'h0; end
                    4'd3: begin q0=~p0; q1=~p1; q2=~p2; q3=~p3; end
                    4'd4: begin q0={p0[23:16],16'h0}; q1={p1[23:16],16'h0}; q2={p2[23:16],16'h0}; q3={p3[23:16],16'h0}; end
                    4'd5: begin q0={p0[23:16]&8'he0,p0[15:8]&8'he0,p0[7:0]&8'he0}; q1={p1[23:16]&8'he0,p1[15:8]&8'he0,p1[7:0]&8'he0}; q2={p2[23:16]&8'he0,p2[15:8]&8'he0,p2[7:0]&8'he0}; q3={p3[23:16]&8'he0,p3[15:8]&8'he0,p3[7:0]&8'he0}; end
                    4'd6: begin
                        q0={enhance8_sel(enhance_sel,p0[23:16],g0),enhance8_sel(enhance_sel,p0[15:8],g0),enhance8_sel(enhance_sel,p0[7:0],g0)};
                        q1={enhance8_sel(enhance_sel,p1[23:16],g1),enhance8_sel(enhance_sel,p1[15:8],g1),enhance8_sel(enhance_sel,p1[7:0],g1)};
                        q2={enhance8_sel(enhance_sel,p2[23:16],g2),enhance8_sel(enhance_sel,p2[15:8],g2),enhance8_sel(enhance_sel,p2[7:0],g2)};
                        q3={enhance8_sel(enhance_sel,p3[23:16],g3),enhance8_sel(enhance_sel,p3[15:8],g3),enhance8_sel(enhance_sel,p3[7:0],g3)};
                    end
                    4'd7: begin
                        q0=(style==5'd8)?{~edge_value,~edge_value,~edge_value}:{edge_value,edge_value,edge_value};
                        q1=q0; q2=q0; q3=q0;
                    end
                    4'd8: begin
                        q0=(g0<64)?{8'd0,g0<<2,8'hff}:(g0<128)?{8'd0,8'hff,8'hff-((g0-64)<<2)}:(g0<192)?{(g0-128)<<2,8'hff,8'd0}:{8'hff,8'hff-((g0-192)<<2),8'd0};
                        q1=(g1<64)?{8'd0,g1<<2,8'hff}:(g1<128)?{8'd0,8'hff,8'hff-((g1-64)<<2)}:(g1<192)?{(g1-128)<<2,8'hff,8'd0}:{8'hff,8'hff-((g1-192)<<2),8'd0};
                        q2=(g2<64)?{8'd0,g2<<2,8'hff}:(g2<128)?{8'd0,8'hff,8'hff-((g2-64)<<2)}:(g2<192)?{(g2-128)<<2,8'hff,8'd0}:{8'hff,8'hff-((g2-192)<<2),8'd0};
                        q3=(g3<64)?{8'd0,g3<<2,8'hff}:(g3<128)?{8'd0,8'hff,8'hff-((g3-64)<<2)}:(g3<192)?{(g3-128)<<2,8'hff,8'd0}:{8'hff,8'hff-((g3-192)<<2),8'd0};
                    end
                    4'd9: begin q0={8'h0,8'h0,p0[7:0]}; q1={8'h0,8'h0,p1[7:0]}; q2={8'h0,8'h0,p2[7:0]}; q3={8'h0,8'h0,p3[7:0]}; end
                    default: begin q0=p0; q1=p1; q2=p2; q3=p3; end
                endcase
                process_group_class={q0,q1,q2,q3};
            end
        end
    endfunction
    // Keep the original reference-function signature for archived benches.
    // The active RTL calls process_pixel_class directly with the shared decode.
    function [23:0] process_pixel;
        input [4:0] style;
        input [7:0] r; input [7:0] g; input [7:0] b;
        input [7:0] gray;
        input [7:0] edge_value; input [7:0] emboss_value;
        input [7:0] erode_value; input [7:0] dilate_value;
        input [7:0] morph_value;
        begin
            process_pixel = process_pixel_class(style_class(style), style_enhance_sel(style), style, r, g, b, gray,
                                                edge_value, emboss_value, erode_value,
                                                dilate_value, morph_value);
        end
    endfunction

    wire [7:0] gray0 = gray8(in_pix0[23:16], in_pix0[15:8], in_pix0[7:0]);
    wire [7:0] gray1 = gray8(in_pix1[23:16], in_pix1[15:8], in_pix1[7:0]);
    wire [7:0] gray2 = gray8(in_pix2[23:16], in_pix2[15:8], in_pix2[7:0]);
    wire [7:0] gray3 = gray8(in_pix3[23:16], in_pix3[15:8], in_pix3[7:0]);
    wire [9:0] gray_sum = gray0 + gray1 + gray2 + gray3;

    // Edge-replicate the left border so the spatial styles do not zero-fill the
    // first two groups (removes the black strip on the left of the image).
    wire [7:0] c_top_d2 = (x_grp >= 2) ? top_d2 : ((x_grp == 1) ? top_d1 : top_cur_r);
    wire [7:0] c_top_d1 = (x_grp >= 1) ? top_d1 : top_cur_r;
    wire [7:0] c_mid_d2 = (x_grp >= 2) ? mid_d2 : ((x_grp == 1) ? mid_d1 : mid_cur_r);
    wire [7:0] c_mid_d1 = (x_grp >= 1) ? mid_d1 : mid_cur_r;
    wire [7:0] c_bot_d2 = (x_grp >= 2) ? bot_d2 : ((x_grp == 1) ? bot_d1 : pending_group_gray_d1);
    wire [7:0] c_bot_d1 = (x_grp >= 1) ? bot_d1 : pending_group_gray_d1;
    wire window_valid = (x_grp >= 2) && (y_pos >= 2) && !pending_tuser;

    // Shared spatial arithmetic.  The previous implementation called four
    // independent 3x3 functions (Sobel, emboss, min9 and max9) and then
    // selected one result.  That replicated the adders/comparators in the
    // synthesized netlist even though every pixel uses only one spatial
    // style.  Build the common window sums once, then select the registered
    // feature below.  The explicit widths preserve the original 8-bit
    // saturation and 8-bit morphology behaviour.
    // The old implementation formed Sobel, emboss and the complete min/max
    // tree in parallel for every cycle, then selected one result.  A frame has
    // exactly one active style, so those mutually exclusive operations are
    // now described as one selected spatial operator.  Besides reducing the
    // adder/comparator fan-out, this keeps the intermediate widths local to
    // the selected result and gives the mapper an opportunity to share carry
    // chains.  The selected result is still produced every accepted group, so
    // the four-pixel/beat protocol and all frame latency remain unchanged.
    reg [9:0] spatial_a, spatial_b;
    reg signed [10:0] spatial_diff;
    reg [10:0] spatial_abs;
    reg [11:0] spatial_sum;
    reg signed [12:0] spatial_emb_value;
    reg [7:0] spatial_pair_min0, spatial_pair_min1, spatial_pair_min2, spatial_pair_min3;
    reg [7:0] spatial_pair_max0, spatial_pair_max1, spatial_pair_max2, spatial_pair_max3;
    reg [7:0] spatial_min_value, spatial_max_value;
    reg [7:0] stage_feature;
    always @* begin
        spatial_a = 10'd0;
        spatial_b = 10'd0;
        spatial_diff = 11'sd0;
        spatial_abs = 11'd0;
        spatial_sum = 12'd0;
        spatial_emb_value = 13'sd0;
        spatial_pair_min0 = 8'd0;
        spatial_pair_min1 = 8'd0;
        spatial_pair_min2 = 8'd0;
        spatial_pair_min3 = 8'd0;
        spatial_pair_max0 = 8'd0;
        spatial_pair_max1 = 8'd0;
        spatial_pair_max2 = 8'd0;
        spatial_pair_max3 = 8'd0;
        spatial_min_value = stage_group_gray;
        spatial_max_value = stage_group_gray;
        stage_feature = 8'd0;

        case (stage_style)
            5'd7, 5'd8: begin
                // Sobel: calculate the two signed directional differences in
                // the shared 10-bit add/subtract datapath.
                spatial_a = {2'b00,stage_top_cur} +
                            ({2'b00,stage_mid_cur} << 1) +
                            {2'b00,stage_group_gray};
                spatial_b = {2'b00,stage_top_d2} +
                            ({2'b00,stage_mid_d2} << 1) +
                            {2'b00,stage_bot_d2};
                spatial_diff = $signed({1'b0,spatial_a}) - $signed({1'b0,spatial_b});
                spatial_abs = spatial_diff[10] ? $unsigned(-spatial_diff) :
                              $unsigned(spatial_diff);
                spatial_a = {2'b00,stage_bot_d2} +
                            ({2'b00,stage_bot_d1} << 1) +
                            {2'b00,stage_group_gray};
                spatial_b = {2'b00,stage_top_d2} +
                            ({2'b00,stage_top_d1} << 1) +
                            {2'b00,stage_top_cur};
                spatial_diff = $signed({1'b0,spatial_a}) - $signed({1'b0,spatial_b});
                spatial_sum = {1'b0,spatial_abs} +
                              {1'b0,(spatial_diff[10] ? $unsigned(-spatial_diff) :
                                      $unsigned(spatial_diff))};
                if (!stage_window_valid)
                    stage_feature = 8'd0;
                else if (spatial_sum > 12'd255)
                    stage_feature = 8'hff;
                else
                    stage_feature = spatial_sum[7:0];
            end
            5'd9: begin
                // Emboss uses the same selected subtract datapath, with the
                // legacy <<1 and +128 saturation rules preserved exactly.
                spatial_a = {2'b00,stage_mid_cur} +
                            {2'b00,stage_bot_d1} +
                            ({2'b00,stage_group_gray} << 1);
                spatial_b = {2'b00,stage_top_d1} +
                            {2'b00,stage_mid_d2} +
                            ({2'b00,stage_top_d2} << 1);
                spatial_diff = $signed({1'b0,spatial_a}) - $signed({1'b0,spatial_b});
                spatial_emb_value = (spatial_diff <<< 1) + 13'sd128;
                if (!stage_window_valid)
                    stage_feature = 8'd0;
                else if (spatial_emb_value < 0)
                    stage_feature = 8'd0;
                else if (spatial_emb_value > 13'sd255)
                    stage_feature = 8'hff;
                else
                    stage_feature = spatial_emb_value[7:0];
            end
            5'd11, 5'd12, 5'd13: begin
                // One pairwise comparator produces both min and max.  The
                // same tree feeds EROD, DILA and MORP; only the final mux is
                // mode-dependent.
                spatial_pair_min0 = (stage_top_d2 < stage_top_d1) ? stage_top_d2 : stage_top_d1;
                spatial_pair_max0 = (stage_top_d2 < stage_top_d1) ? stage_top_d1 : stage_top_d2;
                spatial_pair_min1 = (stage_top_cur < stage_mid_d2) ? stage_top_cur : stage_mid_d2;
                spatial_pair_max1 = (stage_top_cur < stage_mid_d2) ? stage_mid_d2 : stage_top_cur;
                spatial_pair_min2 = (stage_mid_d1 < stage_mid_cur) ? stage_mid_d1 : stage_mid_cur;
                spatial_pair_max2 = (stage_mid_d1 < stage_mid_cur) ? stage_mid_cur : stage_mid_d1;
                spatial_pair_min3 = (stage_bot_d2 < stage_bot_d1) ? stage_bot_d2 : stage_bot_d1;
                spatial_pair_max3 = (stage_bot_d2 < stage_bot_d1) ? stage_bot_d1 : stage_bot_d2;
                spatial_min_value = min2(min2(min2(spatial_pair_min0, spatial_pair_min1),
                                              min2(spatial_pair_min2, spatial_pair_min3)), stage_group_gray);
                spatial_max_value = max2(max2(max2(spatial_pair_max0, spatial_pair_max1),
                                              max2(spatial_pair_max2, spatial_pair_max3)), stage_group_gray);
                case (stage_style)
                    5'd11: stage_feature = stage_window_valid ? spatial_min_value : stage_group_gray;
                    5'd12: stage_feature = stage_window_valid ? spatial_max_value : stage_group_gray;
                    default: stage_feature = stage_window_valid ?
                                (spatial_max_value - spatial_min_value) : 8'd0;
                endcase
            end
            default: stage_feature = 8'd0;
        endcase
    end

    assign I_tready = base_ready;

    wire line1_wr_en = pending_valid && base_ready;
    wire [8:0] line1_wr_addr = pending_tuser ? 9'd0 : x_grp;
    // One 16-bit row word retains both historical grayscale rows. Port A
    // reads the current column; port B retires both byte writes together.
    // Low-byte forwarding preserves the former immediate-write timing.
    always @(posedge I_clk) begin
        if (I_rst_n) begin
            {ram_top_r,ram_mid_r} <= line_mem[line1_wr_addr];
            if (line1_wr_en) deferred_gray <= pending_group_gray;
            if (line2_wr_pending) line_mem[line2_wr_addr] <= {ram_mid_r,deferred_gray};
        end
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            ram_read_live <= 0;
            line2_wr_pending <= 0;
            line2_wr_addr <= 0;
            line2_forward <= 0;
            line2_forward_data <= 0;
            mid_forward_data <= 0;
        end else begin
            ram_read_live <= 1;
            line2_wr_pending <= line1_wr_en;
            if (line1_wr_en) line2_wr_addr <= line1_wr_addr;
            line2_forward <= line2_wr_pending && (line2_wr_addr == x_grp);
            line2_forward_data <= ram_mid_r;
            mid_forward_data <= deferred_gray;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            base_last <= 0; base_user <= 0; base_data <= 96'd0; base_valid <= 0;
            stage_valid <= 0; stage_tlast <= 0; stage_tuser <= 0; stage_style <= 0; stage_class <= 0; stage_enhance_sel <= 0;
            stage_pix0<=0; stage_pix1<=0; stage_pix2<=0; stage_pix3<=0;
            stage_gray0<=0; stage_gray1<=0; stage_gray2<=0; stage_gray3<=0;
            stage_top_d2<=0; stage_top_d1<=0; stage_top_cur<=0;
            stage_mid_d2<=0; stage_mid_d1<=0; stage_mid_cur<=0;
            stage_bot_d2<=0; stage_bot_d1<=0; stage_group_gray<=0;
            stage_window_valid<=0;
            calc_valid<=0; calc_tlast<=0; calc_tuser<=0; calc_style<=0; calc_class<=0; calc_enhance_sel<=0;
            calc_pix0<=0; calc_pix1<=0; calc_pix2<=0; calc_pix3<=0;
            calc_gray0<=0; calc_gray1<=0; calc_gray2<=0; calc_gray3<=0;
            calc_feature<=0;
            out_pend_data<=0; out_pend_valid<=0; out_pend_last<=0; out_pend_user<=0;out_pend_cart<=0;base_cart<=0;
            x_grp<=0; y_pos<=0; active_style<=0;
            top_d2<=0; top_d1<=0; mid_d2<=0; mid_d1<=0; bot_d2<=0; bot_d1<=0;
            pending_valid<=0; frame_user_pending<=0; frame_style_pending<=0;
            pending_tlast<=0; pending_tuser<=0; pending_style<=0;
            pending_pix0<=0; pending_pix1<=0; pending_pix2<=0; pending_pix3<=0;
            pending_gray0<=0; pending_gray1<=0; pending_gray2<=0; pending_gray3<=0;
            pending_group_gray<=0;
            pending_group_gray_d1<=0;
        end else begin
            if (base_ready) begin
                if (calc_valid) begin
                    out_pend_data <= process_group_class(calc_class, calc_enhance_sel, calc_style,
                                      calc_pix0, calc_pix1, calc_pix2, calc_pix3,
                                      calc_gray0, calc_gray1, calc_gray2, calc_gray3,
                                      calc_feature, 8'd0, 8'd0, 8'd0, 8'd0);
                    out_pend_valid <= 1;
                    out_pend_last  <= calc_tlast;
                    out_pend_user  <= calc_tuser;
                    out_pend_cart <= CARTOON_ENABLE && (calc_style==18) &&
                                     !SIMPLE_BYPASS && (FIXED_STYLE_MODE!=1);
                end else begin
                    out_pend_valid <= 0;
                end
                base_data  <= out_pend_data;
                base_valid <= out_pend_valid;
                base_last  <= out_pend_last;
                base_user  <= out_pend_user;
                base_cart <= out_pend_cart;
            end
            if (stage_valid && base_ready) begin
                calc_valid <= 1;
                calc_tlast <= stage_tlast;
                calc_tuser <= stage_tuser;
                calc_style <= stage_style;
                calc_class <= stage_class;
                calc_enhance_sel <= stage_enhance_sel;
                calc_pix0<=stage_pix0; calc_pix1<=stage_pix1; calc_pix2<=stage_pix2; calc_pix3<=stage_pix3;
                calc_gray0<=stage_gray0; calc_gray1<=stage_gray1; calc_gray2<=stage_gray2; calc_gray3<=stage_gray3;
                calc_feature <= stage_feature;
            end else if (base_ready) begin
                calc_valid <= 0;
            end
            if (pending_valid && base_ready) begin
                stage_valid <= 1;
                stage_tlast <= pending_tlast;
                stage_tuser <= pending_tuser;
                stage_style <= pending_style;
                stage_class <= style_class(pending_style);
                stage_enhance_sel <= style_enhance_sel(pending_style);
                stage_pix0<=pending_pix0; stage_pix1<=pending_pix1; stage_pix2<=pending_pix2; stage_pix3<=pending_pix3;
                stage_gray0<=pending_gray0; stage_gray1<=pending_gray1; stage_gray2<=pending_gray2; stage_gray3<=pending_gray3;
                stage_top_d2 <= c_top_d2;
                stage_top_d1 <= c_top_d1;
                stage_top_cur <= top_cur_r;
                stage_mid_d2 <= c_mid_d2;
                stage_mid_d1 <= c_mid_d1;
                stage_mid_cur <= mid_cur_r;
                stage_bot_d2 <= c_bot_d2;
                stage_bot_d1 <= c_bot_d1;
                // P2: the BRAM-registered top/mid reads are one beat behind, so the
                // bottom (current group) must also be taken one beat late (the previous
                // group's gray) to keep all three window rows on the same group.
                stage_group_gray <= pending_group_gray_d1;
                stage_window_valid <= pending_tuser ? 1'b0 : window_valid;

                if (pending_tuser) begin
                    // 帧首拍：group0 写入 mem[0]，x_grp 置 1，防止下一拍 group1 覆盖 mem[0]。
                    x_grp <= (GROUPS == 1) ? 0 : 1;
                    y_pos <= 0;
                    top_d2 <= 0; top_d1 <= 0;
                    mid_d2 <= 0; mid_d1 <= 0;
                    bot_d2 <= 0; bot_d1 <= 0;
                end else begin
                    top_d2 <= top_d1; top_d1 <= top_cur_r;
                    mid_d2 <= mid_d1; mid_d1 <= mid_cur_r;
                    bot_d2 <= bot_d1; bot_d1 <= pending_group_gray;
                    if (pending_tlast || (x_grp == GROUPS - 1)) begin
                        x_grp <= 0;
                        if (y_pos == IMG_HEIGHT - 1) y_pos <= 0; else y_pos <= y_pos + 1'b1;
                        top_d2 <= 0; top_d1 <= 0;
                        mid_d2 <= 0; mid_d1 <= 0;
                        bot_d2 <= 0; bot_d1 <= 0;
                    end else begin
                        x_grp <= x_grp + 1'b1;
                    end
                end
                if (pending_tuser) active_style <= pending_style;
            end else if (base_ready) begin
                stage_valid <= 0;
            end
            if (I_tvalid && base_ready) begin
                pending_valid <= 1;
                pending_tlast <= I_tlast;
                pending_tuser <= I_tuser | frame_user_pending;
                pending_style <= I_tuser ? ((I_style_mode < NUM_STYLES) ? I_style_mode : 5'd0) :
                                 (frame_user_pending ? frame_style_pending :
                                  ((pending_valid && pending_tuser) ? pending_style : active_style));
                pending_pix0<=in_pix0; pending_pix1<=in_pix1; pending_pix2<=in_pix2; pending_pix3<=in_pix3;
                pending_gray0<=gray0; pending_gray1<=gray1; pending_gray2<=gray2; pending_gray3<=gray3;
                pending_group_gray    <= gray_sum[9:2];
                pending_group_gray_d1 <= pending_group_gray;
            end else if (base_ready) begin
                pending_valid <= 0;
            end
            if (base_ready && I_tuser) begin
                frame_user_pending <= 1;
                frame_style_pending <= (I_style_mode < NUM_STYLES) ? I_style_mode : 5'd0;
            end
            if (base_ready && I_tvalid && (I_tuser || frame_user_pending))
                frame_user_pending <= 0;
        end
    end
endmodule
