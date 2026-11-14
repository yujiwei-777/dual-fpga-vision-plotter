// Exact RGB8 Q8.8 CCM diagnostic; four pixels per accepted beat.
// Rn=256R+5(R-4G+3B); Gn=256G+10(G-R); Bn=264B+5(R-3G+B).
// Signed >>>8 without rounding, then clamp 0..255. Shared T3 is eleven bits.
// Three elastic stages retain markers, isolated SOF, reset flush and stalls.
// Selective Anlogic dsp_style postadders are compile-time mappings only.
// This RGB8 equivalent does not recover discarded RAW precision.
module ccm8_4x (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire [95:0] I_tdata,
    input  wire        I_tvalid,
    input  wire        I_tuser,
    input  wire        I_tlast,
    output wire        I_tready,
    output reg  [95:0] O_tdata,
    output reg         O_tvalid,
    output reg         O_tuser,
    output reg         O_tlast,
    input  wire        O_tready
);
    reg stage1_valid, stage1_user, stage1_last;
    reg stage2_valid, stage2_user, stage2_last;
    reg [95:0] stage1_rgb;
    reg user_pending;

    wire stage3_free = !O_tvalid || O_tready;
    wire stage2_free = !stage2_valid || stage3_free;
    wire stage1_free = !stage1_valid || stage2_free;
    assign I_tready = stage1_free;

    // Arithmetic >>>8 followed by clamp 0..255. The temporary is explicitly
    // signed so negative residuals cannot be interpreted as unsigned.
    function [7:0] quantise_clamp;
        input signed [9:0] shifted;
        begin
            if (shifted[9]) quantise_clamp = 8'd0;
            else if (shifted[8]) quantise_clamp = 8'd255;
            else quantise_clamp = shifted[7:0];
        end
    endfunction

    genvar lane;
    generate
        for (lane = 0; lane < 4; lane = lane + 1) begin : g_lane
            wire [7:0] in_r = I_tdata[95-lane*24 -: 8];
            wire [7:0] in_g = I_tdata[87-lane*24 -: 8];
            wire [7:0] in_b = I_tdata[79-lane*24 -: 8];
            wire signed [10:0] r_ext = $signed({3'd0,in_r});
            wire signed [10:0] g_ext = $signed({3'd0,in_g});
            wire signed [10:0] b_ext = $signed({3'd0,in_b});
            // Shared T3 is -765..510; Rmix is -1020..1020.
            wire signed [10:0] common_rbg = r_ext-((g_ext <<< 1)+g_ext)+b_ext;
            reg signed [10:0] stage1_r_mix,stage1_b_mix;
            reg signed [8:0] stage1_g_mix;
            (* use_dsp="yes" *) wire signed [13:0] product_r=stage1_r_mix*4'sd5;
            (* use_dsp="yes" *) wire signed [12:0] product_g=stage1_g_mix*5'sd10;
            (* use_dsp="yes" *) wire signed [13:0] product_b=stage1_b_mix*4'sd5;
            wire [7:0] base1_r=stage1_rgb[95-lane*24 -: 8];
            wire [7:0] base1_g=stage1_rgb[87-lane*24 -: 8];
            wire [7:0] base1_b=stage1_rgb[79-lane*24 -: 8];
            // 264B is real logic arithmetic; shifts alone do not remove its add.
            (* dsp_style="no" *) wire signed [17:0] bbase=
                $signed({2'd0,base1_b,8'd0})+$signed({7'd0,base1_b,3'd0});
            (* dsp_style="yes" *) wire signed [17:0] rnum_post=
                $signed({2'd0,base1_r,8'd0})+product_r;
            (* dsp_style="yes" *) wire signed [17:0] bnum_post=bbase+product_b;
            reg signed [17:0] stage2_r_num,stage2_b_num;
            wire signed [9:0] output_r=stage2_r_num >>> 8;
            wire signed [9:0] output_b=stage2_b_num >>> 8;
            wire signed [9:0] output_g;
            // All lanes compute the same matrix. Three G postadders use DSPs;
            // lane3 uses an exact ten-bit LUT sum to keep total DSP below 38/40.
            if (lane < 3) begin : g_dsp_g_post
                (* dsp_style="yes" *) wire signed [17:0] gnum_post=
                    $signed({2'd0,base1_g,8'd0})+product_g;
                reg signed [17:0] stage2_g_num;
                assign output_g=stage2_g_num >>> 8;
                always @(posedge I_clk or negedge I_rst_n) begin
                    if (!I_rst_n) stage2_g_num<=18'sd0;
                    else if(stage2_free && stage1_valid) stage2_g_num<=gnum_post;
                end
            end else begin : g_lut_g_post
                reg signed [12:0] stage2_g_residual;
                reg [7:0] stage2_base_g;
                assign output_g=$signed({2'd0,stage2_base_g})+(stage2_g_residual >>> 8);
                always @(posedge I_clk or negedge I_rst_n) begin
                    if(!I_rst_n) begin stage2_g_residual<=13'sd0;stage2_base_g<=8'd0;end
                    else if(stage2_free && stage1_valid) begin
                        stage2_g_residual<=product_g;stage2_base_g<=base1_g;
                    end
                end
            end
            always @(posedge I_clk or negedge I_rst_n) begin
                if(!I_rst_n) begin
                    stage1_r_mix<=11'sd0;stage1_b_mix<=11'sd0;stage1_g_mix<=9'sd0;
                    stage2_r_num<=18'sd0;stage2_b_num<=18'sd0;
                    O_tdata[95-lane*24 -: 24]<=24'd0;
                end else begin
                    if(stage1_free && I_tvalid) begin
                        stage1_r_mix<=common_rbg-g_ext+(b_ext <<< 1);
                        stage1_b_mix<=common_rbg;
                        stage1_g_mix<=$signed({1'b0,in_g})-$signed({1'b0,in_r});
                    end
                    if(stage2_free && stage1_valid) begin
                        stage2_r_num<=rnum_post;stage2_b_num<=bnum_post;
                    end
                    if(stage3_free && stage2_valid)
                        O_tdata[95-lane*24 -: 24]<={quantise_clamp(output_r),quantise_clamp(output_g),quantise_clamp(output_b)};
                end
            end
        end
    endgenerate

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            stage1_valid <= 1'b0;
            stage1_user <= 1'b0;
            stage1_last <= 1'b0;
            stage1_rgb <= 96'd0;
            stage2_valid <= 1'b0;
            stage2_user <= 1'b0;
            stage2_last <= 1'b0;
            O_tvalid <= 1'b0;
            O_tuser <= 1'b0;
            O_tlast <= 1'b0;
            user_pending <= 1'b0;
        end else begin
            if (stage1_free) begin
                // Match the legacy Tone boundary's isolated-SOF support.
                if (I_tuser)
                    user_pending <= 1'b1;
                stage1_valid <= I_tvalid;
                if (I_tvalid) begin
                    stage1_rgb <= I_tdata;
                    stage1_user <= I_tuser || user_pending;
                    stage1_last <= I_tlast;
                    user_pending <= 1'b0;
                end else begin
                    stage1_user <= 1'b0;
                    stage1_last <= 1'b0;
                end
            end
            if (stage2_free) begin
                stage2_valid <= stage1_valid;
                if (stage1_valid) begin
                    stage2_user <= stage1_user;
                    stage2_last <= stage1_last;
                end else begin
                    stage2_user <= 1'b0;
                    stage2_last <= 1'b0;
                end
            end
            if (stage3_free) begin
                O_tvalid <= stage2_valid;
                O_tuser <= stage2_valid && stage2_user;
                O_tlast <= stage2_valid && stage2_last;
            end
        end
    end
endmodule
