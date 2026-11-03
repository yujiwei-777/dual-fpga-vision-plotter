/*****************************************************************
Company : MiLianKe Electronic Technology Co., Ltd.
WebSite: https://www.milianke.com
Five-region robust AWB using filtered RGB sums before gain application.
One serial divider and serial sort finish after the statistics ROI closes.
Gains clamp to 0.75..1.5 and slew by at most 0x400 per frame. Dark or
insufficient samples hold the last reliable gains. Updates commit at
SOF after the unchanged 50-clock pixel delay. The consumer is required
to remain ready, matching the production continuous video contract.
*****************************************************************/
module awb  #(
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920,
    parameter LUM_MIN    = 8,     // ���ڴ����ȵ�������Ϊ���ڣ�������ͳ��
    parameter LUM_MAX    = 245,   // ���ڴ����ȵ�������Ϊ���ͣ�������ͳ��
    // AWB uses a broad subject window by default.  A full-frame grey-world
    // estimate is easily biased by the blue keyboard backlight, skin and
    // desk colours in this application.  The window is only used for
    // statistics; the calculated gain remains global for the frame.
    parameter integer ROI_X0 = IMG_WIDTH / 20,
    parameter integer ROI_X1 = (IMG_WIDTH * 19) / 20,
    parameter integer ROI_Y0 = IMG_HEIGHT / 20,
    parameter integer ROI_Y1 = (IMG_HEIGHT * 19) / 20,
    // Low-light threshold is expressed as an average sum of the three
    // channels per selected pixel, then scaled by the ROI area.  Scaling is
    // required because the statistic no longer covers the full frame.
    parameter integer AWB_LOW_AVG_SUM = 65,
    // Reject strongly coloured pixels from the grey-world estimate.  The
    // tighter value keeps neutral body pixels while excluding blue LEDs and
    // other saturated scene colours that would drive the complementary gain.
    parameter integer CHROMA_MAX = 96,
    // Q8 relative chroma: 160/256 = 5/8. This is a diagnostic tuning
    // value, not a calibrated illuminant boundary. Zero/near-black samples
    // still fail the luminance and regional confidence predicates.
    parameter integer REL_CHROMA_MAX = 160,
    parameter integer REGION_MIN_SAMPLES = 32
)
(
    input                   I_clk  ,
    input                   I_rst_n,

    input                   I_tlast  ,
    input                   I_tuser  ,
    input [95:0]            I_tdata  ,
    input                   I_tvalid ,
    output                  I_tready ,

    output                  O_tlast  ,
    output                  O_tuser  ,
    output [95:0]           O_tdata  ,
    output                  O_tvalid ,
    input                   O_tready
);

    //====================================================================
    // ������ˮ�Ĵ�
    //====================================================================
    reg         I_tvalid_r0, I_tvalid_r1;
    reg         I_tuser_r1_in;
    reg         norm_tuser_r0, frame_pending_in;
    reg         I_tlast_r0_in, I_tlast_r1_in;
    reg  [95:0] I_tdata_d0, I_tdata_d1;
    // Coordinates for the statistics beat at I_tdata_d0/I_tvalid_r0.
    // One beat contains four adjacent pixels; x is therefore a group index.
    reg [11:0] stat_x_in, stat_x_r0;
    reg [10:0] stat_y_in, stat_y_r0;
    // Statistics operate on I_tdata_d0/I_tvalid_r0.  Keep the frame-start
    // marker at the same pipeline level so a back-to-back frame cannot clear
    // or snapshot the previous frame one beat too early.
    wire        frame_start_now = (I_tuser && I_tvalid) ||
                                  (frame_pending_in && I_tvalid);
    wire        stat_frame_start = norm_tuser_r0;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            I_tdata_d0 <= 0; I_tdata_d1 <= 0;
            {I_tvalid_r0, I_tvalid_r1} <= 0;
            norm_tuser_r0 <= 0;
            I_tuser_r1_in <= 0;
            frame_pending_in <= 0;
            {I_tlast_r0_in, I_tlast_r1_in} <= 0;
            stat_x_in <= 0;
            stat_y_in <= 0;
            stat_x_r0 <= 0;
            stat_y_r0 <= 0;
        end else begin
            I_tdata_d0  <= I_tdata;
            I_tdata_d1  <= I_tdata_d0;
            I_tvalid_r0 <= I_tvalid;
            I_tvalid_r1 <= I_tvalid_r0;
            // Normalize a frame marker that arrives before the first valid
            // beat.  Downstream sees exactly one SOF with valid asserted.
            norm_tuser_r0 <= frame_start_now;
            I_tuser_r1_in <= norm_tuser_r0;
            if (I_tuser && !I_tvalid)
                frame_pending_in <= 1'b1;
            else if (frame_start_now)
                frame_pending_in <= 1'b0;
            I_tlast_r0_in <= I_tlast;
            I_tlast_r1_in <= I_tlast_r0_in;

            // Reset the input coordinate at the real frame marker.  This
            // handles both conventions used by the upstream video source:
            // tuser coincident with the first valid beat, or one cycle ahead.
            // stat_*_r0 captures the coordinate of the current input beat;
            // stat_*_in advances to the next beat after that capture.
            if (frame_start_now) begin
                stat_x_in <= I_tlast ? 12'd0 : 12'd1;
                stat_y_in <= I_tlast ? ((IMG_HEIGHT > 1) ? 11'd1 : 11'd0) : 11'd0;
                stat_x_r0 <= 12'd0;
                stat_y_r0 <= 11'd0;
            end else if (I_tvalid) begin
                stat_x_r0 <= stat_x_in;
                stat_y_r0 <= stat_y_in;
                if (I_tlast) begin
                    stat_x_in <= 12'd0;
                    if (stat_y_in < IMG_HEIGHT-1) stat_y_in <= stat_y_in + 1'b1;
                    else                             stat_y_in <= 11'd0;
                end else begin
                    stat_x_in <= stat_x_in + 1'b1;
                end
            end
        end
    end

    // ÿ�� 4 ���� RGB �������� I_tdata_d0���� I_tvalid_r0 ���룩
    wire [7:0] r0 = I_tdata_d0[16+:8], g0 = I_tdata_d0[8+:8],  b0 = I_tdata_d0[0+:8];
    wire [7:0] r1 = I_tdata_d0[40+:8], g1 = I_tdata_d0[32+:8], b1 = I_tdata_d0[24+:8];
    wire [7:0] r2 = I_tdata_d0[64+:8], g2 = I_tdata_d0[56+:8], b2 = I_tdata_d0[48+:8];
    wire [7:0] r3 = I_tdata_d0[88+:8], g3 = I_tdata_d0[80+:8], b3 = I_tdata_d0[72+:8];

    // The sampled lane already needs RGB extrema for relative chroma.
    // Reuse these exact extrema for luminance and absolute-chroma predicates.
    wire [7:0] max_rg0 = (r0 > g0) ? r0 : g0;
    wire [7:0] min_rg0 = (r0 < g0) ? r0 : g0;
    wire [7:0] max_rgb0 = (max_rg0 > b0) ? max_rg0 : b0;
    wire [7:0] min_rgb0 = (min_rg0 < b0) ? min_rg0 : b0;
    wire [7:0] span_rgb0 = max_rgb0 - min_rgb0;
    // ��Ч�ԣ����طǽ����ҷǱ��ͣ����ͨ������ [LUM_MIN, LUM_MAX]��
    wire pv0 = (max_rgb0 >= LUM_MIN) && (max_rgb0 <= LUM_MAX);
    wire pv1 = ((r1 >= LUM_MIN) || (g1 >= LUM_MIN) || (b1 >= LUM_MIN)) &&
               ((r1 <= LUM_MAX) && (g1 <= LUM_MAX) && (b1 <= LUM_MAX));
    wire pv2 = ((r2 >= LUM_MIN) || (g2 >= LUM_MIN) || (b2 >= LUM_MIN)) &&
               ((r2 <= LUM_MAX) && (g2 <= LUM_MAX) && (b2 <= LUM_MAX));
    wire pv3 = ((r3 >= LUM_MIN) || (g3 >= LUM_MIN) || (b3 >= LUM_MIN)) &&
               ((r3 <= LUM_MAX) && (g3 <= LUM_MAX) && (b3 <= LUM_MAX));

    function [8:0] absdiff8;
        input [7:0] a;
        input [7:0] b;
        begin
            absdiff8 = (a >= b) ? ({1'b0,a} - {1'b0,b}) :
                                  ({1'b0,b} - {1'b0,a});
        end
    endfunction
    // The largest of the three pairwise absolute differences is max-min.
    wire chroma_ok0 = (span_rgb0 <= CHROMA_MAX);
    wire chroma_ok1 = (absdiff8(r1,g1) <= CHROMA_MAX) &&
                      (absdiff8(r1,b1) <= CHROMA_MAX) &&
                      (absdiff8(g1,b1) <= CHROMA_MAX);
    wire chroma_ok2 = (absdiff8(r2,g2) <= CHROMA_MAX) &&
                      (absdiff8(r2,b2) <= CHROMA_MAX) &&
                      (absdiff8(g2,b2) <= CHROMA_MAX);
    wire chroma_ok3 = (absdiff8(r3,g3) <= CHROMA_MAX) &&
                      (absdiff8(r3,b3) <= CHROMA_MAX) &&
                      (absdiff8(g3,b3) <= CHROMA_MAX);

    // Normalized neutral-pixel admission shared with the RAW AWB path:
    // R/G <= max(25% of G, 4 DN), B/G <= max(31% of G, 4 DN).
    wire [8:0] rg_lim0 = (g0[7:2] > 8'd4) ? {1'b0,g0[7:2]} : 9'd4;
    wire [8:0] bg_lim0 = ((g0[7:2] + g0[7:4]) > 8'd4) ?
                         {1'b0,(g0[7:2] + g0[7:4])} : 9'd4;
    wire [8:0] rg_lim1 = (g1[7:2] > 8'd4) ? {1'b0,g1[7:2]} : 9'd4;
    wire [8:0] bg_lim1 = ((g1[7:2] + g1[7:4]) > 8'd4) ?
                         {1'b0,(g1[7:2] + g1[7:4])} : 9'd4;
    wire [8:0] rg_lim2 = (g2[7:2] > 8'd4) ? {1'b0,g2[7:2]} : 9'd4;
    wire [8:0] bg_lim2 = ((g2[7:2] + g2[7:4]) > 8'd4) ?
                         {1'b0,(g2[7:2] + g2[7:4])} : 9'd4;
    wire [8:0] rg_lim3 = (g3[7:2] > 8'd4) ? {1'b0,g3[7:2]} : 9'd4;
    wire [8:0] bg_lim3 = ((g3[7:2] + g3[7:4]) > 8'd4) ?
                         {1'b0,(g3[7:2] + g3[7:4])} : 9'd4;
    wire neutral_ok0 = (absdiff8(r0,g0) <= rg_lim0) &&
                       (absdiff8(b0,g0) <= bg_lim0);
    wire neutral_ok1 = (absdiff8(r1,g1) <= rg_lim1) &&
                       (absdiff8(b1,g1) <= bg_lim1);
    wire neutral_ok2 = (absdiff8(r2,g2) <= rg_lim2) &&
                       (absdiff8(b2,g2) <= bg_lim2);
    wire neutral_ok3 = (absdiff8(r3,g3) <= rg_lim3) &&
                       (absdiff8(b3,g3) <= bg_lim3);

    // A distributed 3x3 sampling area contributes to AWB. The display and
    // CNN paths still carry every pixel; this gate changes feedback
    // statistics only. Lane coordinates are 4*x_group + lane.
    wire roi_y = (stat_y_r0 >= ROI_Y0) && (stat_y_r0 < ROI_Y1);
    wire [12:0] stat_x_px = {stat_x_r0, 2'b00};
    wire roi0 = roi_y && ((stat_x_px + 13'd0) >= ROI_X0) &&
                          ((stat_x_px + 13'd0) < ROI_X1);
    wire roi1 = roi_y && ((stat_x_px + 13'd1) >= ROI_X0) &&
                          ((stat_x_px + 13'd1) < ROI_X1);
    wire roi2 = roi_y && ((stat_x_px + 13'd2) >= ROI_X0) &&
                          ((stat_x_px + 13'd2) < ROI_X1);
    wire roi3 = roi_y && ((stat_x_px + 13'd3) >= ROI_X0) &&
                          ((stat_x_px + 13'd3) < ROI_X1);

    // Fixed 16x16 lattice: no divider or frame buffer. The same lattice
    // phase is used in each of the nine regions. Reject the four outer
    // corner cells, where lens shading and dark pixels are strongest.
    wire [12:0] px0 = stat_x_px;
    wire [12:0] px1 = stat_x_px + 13'd1;
    wire [12:0] px2 = stat_x_px + 13'd2;
    wire [12:0] px3 = stat_x_px + 13'd3;
    wire lattice_y = (stat_y_r0[3:0] == 4'd0);
    wire lattice0 = lattice_y && (px0[3:0] == 4'd0);
    wire lattice1 = lattice_y && (px1[3:0] == 4'd0);
    wire lattice2 = lattice_y && (px2[3:0] == 4'd0);
    wire lattice3 = lattice_y && (px3[3:0] == 4'd0);
    wire top_region = (stat_y_r0 < (IMG_HEIGHT/3));
    wire bottom_region = (stat_y_r0 >= ((IMG_HEIGHT*2)/3));
    wire left0 = (px0 < (IMG_WIDTH/4));
    wire right0 = (px0 >= ((IMG_WIDTH*3)/4));
    wire left1 = (px1 < (IMG_WIDTH/4));
    wire right1 = (px1 >= ((IMG_WIDTH*3)/4));
    wire left2 = (px2 < (IMG_WIDTH/4));
    wire right2 = (px2 >= ((IMG_WIDTH*3)/4));
    wire left3 = (px3 < (IMG_WIDTH/4));
    wire right3 = (px3 >= ((IMG_WIDTH*3)/4));
    wire corner0 = (left0 || right0) && (top_region || bottom_region);
    wire corner1 = (left1 || right1) && (top_region || bottom_region);
    wire corner2 = (left2 || right2) && (top_region || bottom_region);
    wire corner3 = (left3 || right3) && (top_region || bottom_region);

    wire [23:0] relative_limit0 = max_rgb0 * REL_CHROMA_MAX;
    wire relative_ok0 = ({span_rgb0,8'd0} <= relative_limit0);
    // The fixed lattice selects x mod 16 == 0. With four adjacent pixels
    // per aligned beat only lane 0 can be a statistics sample.
    wire sv0 = pv0 && neutral_ok0 && roi0 && lattice0 && !corner0;
    wire sv1 = pv1 && neutral_ok1 && roi1 && lattice1 && !corner1;
    wire sv2 = pv2 && neutral_ok2 && roi2 && lattice2 && !corner2;
    wire sv3 = pv3 && neutral_ok3 && roi3 && lattice3 && !corner3;

    // Five disjoint retained cells: top, middle-left, centre,
    // middle-right, bottom. Each valid cell has equal estimator weight.
    // No whole-frame image, neighbour pixels, or extra line RAM is stored.
    wire [2:0] sample_region = top_region ? 3'd0 :
                               bottom_region ? 3'd4 :
                               left0 ? 3'd1 : right0 ? 3'd3 : 3'd2;
    // Each well-formed frame visits a 16x16 lattice point at most once.
    // Each region is at most ceil(W/2) wide and ceil(H/3) high, so it
    // contains at most ceil(W/32)*ceil(H/48) lattice points at any phase.
    // ROI and colour predicates only remove samples. Keep the total count
    // bounded by the entire frame lattice. All arithmetic is constant-only.
    function integer awb_count_bits;
        input [63:0] maximum;
        reg [63:0] remaining;
        integer width;
        begin
            remaining=maximum; width=0;
            while(remaining!=0) begin
                remaining=remaining>>1; width=width+1;
            end
            awb_count_bits=(width<1) ? 1 : width;
        end
    endfunction
    localparam [63:0] AWB_GRID_SAMPLES =
        ((64'd1*IMG_WIDTH+64'd15)/64'd16)*
        ((64'd1*IMG_HEIGHT+64'd15)/64'd16);
    localparam [63:0] AWB_REGION_SAMPLES =
        ((64'd1*IMG_WIDTH+64'd31)/64'd32)*
        ((64'd1*IMG_HEIGHT+64'd47)/64'd48);
    localparam integer AWB_COUNT_W=awb_count_bits(AWB_GRID_SAMPLES);
    localparam integer AWB_REGION_COUNT_W=awb_count_bits(AWB_REGION_SAMPLES);
    localparam integer AWB_SUM_W=awb_count_bits(AWB_REGION_SAMPLES*64'd255);
    reg [AWB_SUM_W-1:0] region_r [0:4];
    reg [AWB_SUM_W-1:0] region_g [0:4];
    reg [AWB_SUM_W-1:0] region_b [0:4];
    reg [AWB_REGION_COUNT_W-1:0] region_count [0:4];
    reg [AWB_COUNT_W-1:0] sample_count;
    reg stats_sealed, frame_started;
    // Statistics accumulation and estimation are mutually exclusive.
    // The sealing edge only starts the estimator; its first ST_CELL is
    // on the next edge with stats_sealed already set. SOF initializes
    // statistics without reading old records and cancels the estimator.
    wire [2:0] region_read_idx;
    wire [AWB_SUM_W-1:0] region_read_r=region_r[region_read_idx];
    wire [AWB_SUM_W-1:0] region_read_g=region_g[region_read_idx];
    wire [AWB_SUM_W-1:0] region_read_b=region_b[region_read_idx];
    wire [AWB_REGION_COUNT_W-1:0] region_read_count=region_count[region_read_idx];
    integer region_i;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (region_i=0; region_i<5; region_i=region_i+1) begin
                region_r[region_i]<=0; region_g[region_i]<=0;
                region_b[region_i]<=0; region_count[region_i]<=0;
            end
            sample_count<=0; stats_sealed<=0; frame_started<=0;
        end else if (stat_frame_start) begin
            for (region_i=0; region_i<5; region_i=region_i+1) begin
                region_r[region_i]<= (sv0 && sample_region==region_i) ? r0 : 0;
                region_g[region_i]<= (sv0 && sample_region==region_i) ? g0 : 0;
                region_b[region_i]<= (sv0 && sample_region==region_i) ? b0 : 0;
                region_count[region_i]<= (sv0 && sample_region==region_i) ? 1 : 0;
            end
            sample_count<=sv0 ? 1 : 0;
            stats_sealed<=0; frame_started<=1;
        end else if (I_tvalid_r0 && frame_started) begin
            if (stat_y_r0>=ROI_Y1) stats_sealed<=1;
            if (sv0 && !stats_sealed) begin
                region_r[sample_region]<=region_read_r+r0;
                region_g[sample_region]<=region_read_g+g0;
                region_b[sample_region]<=region_read_b+b0;
                region_count[sample_region]<=region_read_count+1'b1;
                sample_count<=sample_count+1'b1;
            end
        end
    end

    reg [19:0] r_gain_r, r_gain_b, r_gain_pending_r, r_gain_pending_b;
    reg pending_valid;
    wire [95:0] data_d0;
    wire valid_d0, I_tuser_r0;
    reg valid_d1, I_tuser_r1, tlast_d1;
    reg [95:0] data_d1;
    reg tlast_pipe [0:49];
    integer tlast_k;
    localparam [19:0] AWB_STEP=20'h00200;
    localparam integer AWB_MIN_SAMPLES=(IMG_WIDTH>=1280) ? 128 : 1;
    localparam integer MIN_CELL=(IMG_WIDTH>=1280) ? REGION_MIN_SAMPLES : 1;
    // Conservative bound on 10 divisions, cell admission and serial sort.
    // If a non-production geometry provides less tail time, hold gains;
    // never extend the established 50-clock pixel/marker delay.
    localparam integer AWB_GEOMETRY_OK=((IMG_HEIGHT-ROI_Y1)*(IMG_WIDTH/4)>=256);
    localparam [3:0] ST_IDLE=0, ST_CELL=1, ST_R_INIT=2, ST_R_BITS=3,
                     ST_R_FINISH=4, ST_B_INIT=5, ST_B_BITS=6,
                     ST_B_FINISH=7, ST_NEXT=8, ST_SORT_INIT=9,
                     ST_SORT=10, ST_READY=11;
    reg [3:0] div_state;
    reg [2:0] cell_idx, good_cells, sort_pass, sort_idx;
    assign region_read_idx=stats_sealed ? cell_idx : sample_region;
    reg [AWB_SUM_W-1:0] frame_sum_g, frame_sum_b, div_num;
    reg [AWB_SUM_W:0] div_den, div_rem;
    reg [16:0] div_q, cell_ratio_r;
    reg [16:0] ratios_r [0:4];
    reg [16:0] ratios_b [0:4];
    reg [4:0] div_bit;
    wire [AWB_SUM_W+1:0] div_rem_shift={div_rem,1'b0};
    wire [AWB_SUM_W+1:0] div_den_ext={1'b0,div_den};
    wire [AWB_SUM_W+1:0] cell_rgb_sum={2'b0,region_read_r}+
                              {2'b0,region_read_g}+
                              {2'b0,region_read_b};
    wire [31:0] cell_low_limit=region_read_count*AWB_LOW_AVG_SUM;
    wire cell_good=(region_read_count>=MIN_CELL) &&
                   (region_read_r!=0) && (region_read_g!=0) &&
                   (region_read_b!=0) && (cell_rgb_sum>=cell_low_limit);
    wire [17:0] middle_r={1'b0,ratios_r[1]}+{1'b0,ratios_r[2]};
    wire [17:0] middle_b={1'b0,ratios_b[1]}+{1'b0,ratios_b[2]};
    wire [16:0] median_r=(good_cells==5) ? ratios_r[2] :
                         (good_cells==4) ? middle_r[17:1] : ratios_r[1];
    wire [16:0] median_b=(good_cells==5) ? ratios_b[2] :
                         (good_cells==4) ? middle_b[17:1] : ratios_b[1];

    function [19:0] clamp_q16;
        input [16:0] q;
        begin
            if(q<17'h0c000) clamp_q16=20'h0c000;
            else if(q>17'h18000) clamp_q16=20'h18000;
            else clamp_q16={3'd0,q};
        end
    endfunction
    function [19:0] slew_gain;
        input [19:0] cur, target;
        begin
            if(cur<target) slew_gain=((target-cur)<=AWB_STEP)?target:cur+AWB_STEP;
            else if(cur>target) slew_gain=((cur-target)<=AWB_STEP)?target:cur-AWB_STEP;
            else slew_gain=cur;
        end
    endfunction
    integer ratio_i;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            r_gain_r<=20'h10000; r_gain_b<=20'h10000;
            r_gain_pending_r<=20'h10000; r_gain_pending_b<=20'h10000;
            pending_valid<=0; div_state<=ST_IDLE;
            frame_sum_g<=0; frame_sum_b<=0; div_num<=0;
            div_den<=0; div_rem<=0; div_q<=0; div_bit<=0;
            cell_idx<=0; good_cells<=0; sort_pass<=0; sort_idx<=0;
            cell_ratio_r<=17'h10000;
            for(ratio_i=0;ratio_i<5;ratio_i=ratio_i+1) begin
                ratios_r[ratio_i]<=17'h1ffff; ratios_b[ratio_i]<=17'h1ffff;
            end
        end else begin
            if(I_tuser_r0 && valid_d0 && pending_valid) begin
                r_gain_r<=r_gain_pending_r; r_gain_b<=r_gain_pending_b;
                pending_valid<=0;
            end
            // Unexpected SOF cancels a partial estimator. A completed
            // pending estimate belongs to the preceding ROI and commits
            // only at the matching delayed output SOF below.
            if(stat_frame_start) div_state<=ST_IDLE;
            else case(div_state)
                ST_IDLE: if(AWB_GEOMETRY_OK && frame_started && !stats_sealed &&
                            I_tvalid_r0 && stat_y_r0>=ROI_Y1 &&
                            sample_count>=AWB_MIN_SAMPLES) begin
                    cell_idx<=0; good_cells<=0; div_state<=ST_CELL;
                    for(ratio_i=0;ratio_i<5;ratio_i=ratio_i+1) begin
                        ratios_r[ratio_i]<=17'h1ffff; ratios_b[ratio_i]<=17'h1ffff;
                    end
                end
                ST_CELL: begin
                    if(cell_good) begin
                        frame_sum_g<=region_read_g; frame_sum_b<=region_read_b;
                        div_num<=region_read_g; div_den<={1'b0,region_read_r};
                        div_state<=ST_R_INIT;
                    end else div_state<=ST_NEXT;
                end
                ST_R_INIT, ST_B_INIT: begin
                    div_q<=0; div_bit<=15;
                    div_state<=(div_state==ST_R_INIT) ? ST_R_BITS : ST_B_BITS;
                    if({1'b0,div_num}>={div_den[AWB_SUM_W-1:0],1'b0}) begin
                        div_q<=17'h18000; div_rem<=0;
                        div_state<=(div_state==ST_R_INIT) ? ST_R_FINISH : ST_B_FINISH;
                    end else if({1'b0,div_num}>=div_den) begin
                        div_q[16]<=1'b1; div_rem<={1'b0,div_num}-div_den;
                    end else begin div_q[16]<=1'b0; div_rem<={1'b0,div_num}; end
                end
                ST_R_BITS, ST_B_BITS: begin
                    if(div_rem_shift>=div_den_ext) begin
                        div_rem<=div_rem_shift-div_den_ext; div_q[div_bit]<=1'b1;
                    end else begin div_rem<=div_rem_shift; div_q[div_bit]<=1'b0; end
                    if(div_bit==0) div_state<=(div_state==ST_R_BITS) ? ST_R_FINISH : ST_B_FINISH;
                    else div_bit<=div_bit-1'b1;
                end
                ST_R_FINISH: begin
                    cell_ratio_r<=clamp_q16(div_q); div_num<=frame_sum_g;
                    div_den<={1'b0,frame_sum_b}; div_state<=ST_B_INIT;
                end
                ST_B_FINISH: begin
                    ratios_r[good_cells]<=cell_ratio_r;
                    ratios_b[good_cells]<=clamp_q16(div_q);
                    good_cells<=good_cells+1'b1; div_state<=ST_NEXT;
                end
                ST_NEXT: begin
                    if(cell_idx==4) div_state<=ST_SORT_INIT;
                    else begin cell_idx<=cell_idx+1'b1; div_state<=ST_CELL; end
                end
                ST_SORT_INIT: begin
                    sort_pass<=0; sort_idx<=0;
                    div_state<=(good_cells>=3) ? ST_SORT : ST_IDLE;
                end
                ST_SORT: begin
                    if(ratios_r[sort_idx]>ratios_r[sort_idx+1'b1]) begin
                        ratios_r[sort_idx]<=ratios_r[sort_idx+1'b1];
                        ratios_r[sort_idx+1'b1]<=ratios_r[sort_idx];
                    end
                    if(ratios_b[sort_idx]>ratios_b[sort_idx+1'b1]) begin
                        ratios_b[sort_idx]<=ratios_b[sort_idx+1'b1];
                        ratios_b[sort_idx+1'b1]<=ratios_b[sort_idx];
                    end
                    if(sort_idx==3-sort_pass) begin
                        sort_idx<=0;
                        if(sort_pass==3) div_state<=ST_READY;
                        else sort_pass<=sort_pass+1'b1;
                    end else sort_idx<=sort_idx+1'b1;
                end
                ST_READY: begin
                    r_gain_pending_r<=slew_gain(r_gain_r,clamp_q16(median_r));
                    r_gain_pending_b<=slew_gain(r_gain_b,clamp_q16(median_b));
                    pending_valid<=1; div_state<=ST_IDLE;
                end
                default: div_state<=ST_IDLE;
            endcase
        end
    end

    // Fixed 50-clock pixel/marker delay; estimator runs in the unsampled frame tail.
    //====================================================================
    signal_delay #(
        .IMG_HEIGHT (IMG_HEIGHT),
        .IMG_WIDTH  (IMG_WIDTH ),
        .DATA_WIDTH (96),
        .DELAY_CYCLE(50)
    ) signal_delay_d (
        .I_clk  (I_clk),
        .I_rst_n(I_rst_n),
        .I_tuser(I_tuser_r1_in),
        .I_valid(I_tvalid_r1),
        .I_data (I_tdata_d1),
        .O_valid(valid_d0),
        .O_data (data_d0),
        .O_tuser(I_tuser_r0)
    );

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_d1 <= 0; data_d1 <= 0; I_tuser_r1 <= 0; tlast_d1 <= 0;
            for (tlast_k = 0; tlast_k < 50; tlast_k = tlast_k + 1)
                tlast_pipe[tlast_k] <= 1'b0;
        end else begin
            valid_d1  <= valid_d0;
            data_d1   <= data_d0;
            I_tuser_r1 <= I_tuser_r0;
            // Keep line boundaries with exactly the same 50-cycle delay as
            // data/valid.  The old implementation inferred tlast from a
            // valid falling edge, which disappears when consecutive lines
            // have no idle gap.
            tlast_pipe[0] <= I_tlast_r1_in;
            for (tlast_k = 1; tlast_k < 50; tlast_k = tlast_k + 1)
                tlast_pipe[tlast_k] <= tlast_pipe[tlast_k-1];
            tlast_d1 <= tlast_pipe[49];
        end
    end

    wire [7:0] rr0 = data_d1[16+:8], gg0 = data_d1[8+:8],  bb0 = data_d1[0+:8];
    wire [7:0] rr1 = data_d1[40+:8], gg1 = data_d1[32+:8], bb1 = data_d1[24+:8];
    wire [7:0] rr2 = data_d1[64+:8], gg2 = data_d1[56+:8], bb2 = data_d1[48+:8];
    wire [7:0] rr3 = data_d1[88+:8], gg3 = data_d1[80+:8], bb3 = data_d1[72+:8];

    // Ӧ������
    reg [27:0] R_new_r0, G_new_r0, B_new_r0;
    reg [27:0] R_new_r1, G_new_r1, B_new_r1;
    reg [27:0] R_new_r2, G_new_r2, B_new_r2;
    reg [27:0] R_new_r3, G_new_r3, B_new_r3;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            {R_new_r0,G_new_r0,B_new_r0} <= 0;
            {R_new_r1,G_new_r1,B_new_r1} <= 0;
            {R_new_r2,G_new_r2,B_new_r2} <= 0;
            {R_new_r3,G_new_r3,B_new_r3} <= 0;
        end else if (valid_d1) begin
            R_new_r0 <= r_gain_r * rr0;
            G_new_r0 <= {20'd0, gg0};
            B_new_r0 <= r_gain_b * bb0;
            R_new_r1 <= r_gain_r * rr1;
            G_new_r1 <= {20'd0, gg1};
            B_new_r1 <= r_gain_b * bb1;
            R_new_r2 <= r_gain_r * rr2;
            G_new_r2 <= {20'd0, gg2};
            B_new_r2 <= r_gain_b * bb2;
            R_new_r3 <= r_gain_r * rr3;
            G_new_r3 <= {20'd0, gg3};
            B_new_r3 <= r_gain_b * bb3;
        end
    end

    // ����ضϣ��� 4 λ���� -> 255
    wire [7:0] R_new_x0 = (R_new_r0[27:24]) ? 8'd255 : R_new_r0[23:16];
    wire [7:0] G_new_x0 = G_new_r0[7:0];
    wire [7:0] B_new_x0 = (B_new_r0[27:24]) ? 8'd255 : B_new_r0[23:16];
    wire [7:0] R_new_x1 = (R_new_r1[27:24]) ? 8'd255 : R_new_r1[23:16];
    wire [7:0] G_new_x1 = G_new_r1[7:0];
    wire [7:0] B_new_x1 = (B_new_r1[27:24]) ? 8'd255 : B_new_r1[23:16];
    wire [7:0] R_new_x2 = (R_new_r2[27:24]) ? 8'd255 : R_new_r2[23:16];
    wire [7:0] G_new_x2 = G_new_r2[7:0];
    wire [7:0] B_new_x2 = (B_new_r2[27:24]) ? 8'd255 : B_new_r2[23:16];
    wire [7:0] R_new_x3 = (R_new_r3[27:24]) ? 8'd255 : R_new_r3[23:16];
    wire [7:0] G_new_x3 = G_new_r3[7:0];
    wire [7:0] B_new_x3 = (B_new_r3[27:24]) ? 8'd255 : B_new_r3[23:16];

    //====================================================================
    // ���ͬ�� / �����ź�
    //====================================================================
    reg valid_d2, I_tuser_r2, tlast_d2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_d2 <= 0; I_tuser_r2 <= 0; tlast_d2 <= 0;
        end else begin
            valid_d2   <= valid_d1;
            I_tuser_r2 <= I_tuser_r1;
            tlast_d2   <= tlast_d1;
        end
    end

    // Preserve the real line marker.  It is aligned to the output valid
    // beat, allowing luma/AWB/target/motion statistics to advance rows.
    assign O_tlast  = tlast_d2 & valid_d2;
    assign O_tuser  = I_tuser_r2 & valid_d2;
    assign O_tvalid = valid_d2;
    assign O_tdata  = O_tvalid ? {R_new_x3,G_new_x3,B_new_x3,
                                  R_new_x2,G_new_x2,B_new_x2,
                                  R_new_x1,G_new_x1,B_new_x1,
                                  R_new_x0,G_new_x0,B_new_x0} : 96'd0;
    assign I_tready = O_tready;

endmodule





