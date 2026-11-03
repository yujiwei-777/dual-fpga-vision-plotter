// Single-frame BRAM motion detector. INPUT_GRID=0 accepts the legacy 320
// groups/line, 720-line camera stream; INPUT_GRID=1 accepts 320x180 samples.
// Results commit only on the next USER, after all samples (including the final
// sample) have drained. A bad/incomplete frame invalidates the reference: one
// subsequent complete frame is needed before comparisons resume.
module motion_detect #(
    parameter [7:0] MOTION_TH = 8'd48,
    parameter [7:0] DARK_DIFF_TH = 8'd6,
    parameter [7:0] DARK_MIN = 8'd64,
    // Legacy callers retain the crossing-only dark rule. The adaptive
    // display profile enables a lower threshold throughout dark/highlight
    // regions after spatial averaging, without altering its image source.
    parameter integer LUMA_ADAPTIVE = 0,
    parameter [7:0] BRIGHT_MIN = 8'd192,
    parameter [7:0] BRIGHT_DIFF_TH = 8'd6,
    parameter integer DENSITY_SHIFT = 3,
    parameter [15:0] MIN_AREA = 16'd800,
    parameter integer CONFIRM = 3,
    parameter integer INPUT_GRID = 0,
    parameter integer LOCAL_FILTER = 0,
    parameter [6:0] TILE_MIN_COUNT = 7'd4
)(
    input wire I_clk,
    input wire I_rst_n,
    input wire I_en,
    input wire I_vld,
    input wire I_tuser,
    input wire I_tlast,
    input wire [23:0] I_pix,
    input wire I_frame_error,
    output reg O_valid,
    output reg [10:0] O_x_min,
    output reg [9:0] O_y_min,
    output reg [10:0] O_x_max,
    output reg [9:0] O_y_max,
    output reg [15:0] O_count,
    // Latched frame status. O_commit is a toggle updated after each complete
    // frame result; O_empty describes that result. A toggle is used instead
    // of a one-cycle pulse because the display commits only at vertical blank
    // and must not miss a result that arrives a few clocks after USER.
    output reg O_commit,
    output reg O_empty
);
    localparam [9:0] LAST_LINE = INPUT_GRID ? 10'd179 : 10'd719;
    localparam [7:0] CONFIRM_COUNT = (CONFIRM < 1) ? 1 : ((CONFIRM > 255) ? 255 : CONFIRM);

    function [7:0] F_gray;
        input [7:0] r,g,b;
        reg [16:0] s;
        begin
            s = ({9'd0,r}<<6)+({9'd0,r}<<3)+({9'd0,r}<<2)+{9'd0,r}
              + ({9'd0,g}<<7)+({9'd0,g}<<4)+({9'd0,g}<<2)+({9'd0,g}<<1)
              + ({9'd0,b}<<4)+({9'd0,b}<<3)+({9'd0,b}<<2)+{9'd0,b};
            F_gray=s[15:8];
        end
    endfunction

    reg [8:0] S_xb;
    reg [9:0] S_y;
    reg S_started, S_complete, S_bad, S_reference_good, S_frame_en;
    wire S_start=I_vld && I_tuser;
    wire S_previous_complete=S_started && S_complete && !S_bad && !I_frame_error;
    wire [8:0] S_x=S_start ? 9'd0 : S_xb;
    wire [9:0] S_line=S_start ? 10'd0 : S_y;
    wire [7:0] S_yds=INPUT_GRID ? S_line[7:0] : S_line[9:2];
    wire S_accept=I_vld && (S_start || (S_started && !S_complete && !S_bad));
    wire S_smp=S_accept && (INPUT_GRID || (S_line[1:0]==0));
    wire [15:0] S_addr_n=({8'd0,S_yds}<<8)+({8'd0,S_yds}<<6)+{7'd0,S_x};
    wire [7:0] S_gnew=F_gray(I_pix[23:16],I_pix[15:8],I_pix[7:0]);

    // Read-first, one address and one physical frame store. No RAM reset.
    (* ram_style="bram" *) reg [7:0] S_mem[0:57599];
    reg [7:0] S_rd;
    always @(posedge I_clk) begin
        if (I_rst_n && S_smp) begin
            S_rd <= S_mem[S_addr_n];
            S_mem[S_addr_n] <= S_gnew;
        end
    end

    reg [7:0] S_g;
    reg [8:0] S_xd;
    reg [7:0] S_yd;
    reg S_sample_d, S_compare_d, S_commit_d, S_commit_good_d;
    reg S_mot_d1, S_mot_d2;
    wire [8:0] S_dif=(S_g>S_rd) ? ({1'b0,S_g}-{1'b0,S_rd}) : ({1'b0,S_rd}-{1'b0,S_g});
    wire S_dark_transition = ((S_rd<=DARK_MIN)&&(S_g>DARK_MIN)) ||
                             ((S_g<=DARK_MIN)&&(S_rd>DARK_MIN));
    wire S_dark_region = (S_rd<=DARK_MIN)||(S_g<=DARK_MIN);
    wire S_bright_region = (S_rd>=BRIGHT_MIN)||(S_g>=BRIGHT_MIN);
    wire [7:0] S_threshold = S_dark_region ? DARK_DIFF_TH :
                             (S_bright_region ? BRIGHT_DIFF_TH : MOTION_TH);
    wire S_raw_mot=S_sample_d && S_compare_d &&
                   (LUMA_ADAPTIVE ? (S_dif>{1'b0,S_threshold}) :
                    ((S_dif>{1'b0,MOTION_TH}) ||
                     (S_dark_transition && (S_dif>{1'b0,DARK_DIFF_TH}))));
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_xb<=0; S_y<=0; S_started<=0; S_complete<=0; S_bad<=0;
            S_reference_good<=0; S_frame_en<=0;
            S_g<=0; S_xd<=0; S_yd<=0;
            S_sample_d<=0; S_compare_d<=0; S_commit_d<=0; S_commit_good_d<=0;
            S_mot_d1<=0; S_mot_d2<=0;
        end else begin
            // Drain every clock, not only on I_vld. The post-HEQ adapter emits
            // one sample per four clocks, so valid-gated pipelines duplicate
            // or lose tail samples and misalign RAM data.
            S_sample_d<=S_smp;
            S_commit_d<=S_start;
            S_commit_good_d<=S_previous_complete && S_reference_good && S_frame_en && I_en;
            S_compare_d<=S_start ? S_previous_complete : S_reference_good;
            if (S_smp) begin S_g<=S_gnew; S_xd<=S_x; S_yd<=S_yds; end
            if (S_sample_d) begin
                if (S_xd==0) begin S_mot_d1<=S_raw_mot; S_mot_d2<=0; end
                else begin S_mot_d2<=S_mot_d1; S_mot_d1<=S_raw_mot; end
            end

            if (S_start) begin
                S_started<=1; S_complete<=0; S_bad<=I_tlast;
                S_reference_good<=S_previous_complete;
                S_frame_en<=I_en;
                S_xb<=9'd1; S_y<=0;
            end else begin
                if (I_frame_error) S_bad<=1;
                if (S_accept) begin
                    if (I_tlast != (S_xb==9'd319)) S_bad<=1;
                    if (I_tlast) begin
                        S_xb<=0;
                        if (S_y==LAST_LINE) S_complete<=1;
                        else S_y<=S_y+1'b1;
                    end else S_xb<=S_xb+1'b1;
                end else if (I_vld && S_started) S_bad<=1;
            end
        end
    end

    // A changed sample must touch another changed sample in its local
    // horizontal neighbourhood. The existing 8x8 tile/connected-component
    // selector supplies the vertical part of the low-cost 3x3 noise filter.
    wire S_mot=S_raw_mot && (!LOCAL_FILTER || S_mot_d1 || S_mot_d2);
    // Select local motion components before applying the existing frame
    // confirmation. Distant noise must not enlarge one global box and clear
    // an otherwise valid moving target. The grey reference RAM above is
    // unchanged; region processing runs after the last sampled source row.
    wire S_region_ready, S_region_valid, S_region_busy, S_region_overrun;
    wire [8:0] S_region_x0, S_region_x1;
    wire [7:0] S_region_y0, S_region_y1;
    wire [15:0] S_region_count;
    reg [7:0] S_conf;
    motion_region_select #(.MIN_AREA(MIN_AREA), .TILE_MIN_COUNT(TILE_MIN_COUNT),
                           .DENSITY_SHIFT(DENSITY_SHIFT)) u_motion_regions (
        .I_clk(I_clk), .I_rst_n(I_rst_n),
        // Commit the previous result while the first new-frame sample is
        // processed. Both modules see the held previous O_ready at this edge.
        .I_frame_start(S_commit_d),
        .I_sample(S_sample_d), .I_changed(S_mot), .I_x(S_xd), .I_y(S_yd),
        .O_ready(S_region_ready), .O_valid(S_region_valid),
        .O_x_min(S_region_x0), .O_x_max(S_region_x1),
        .O_y_min(S_region_y0), .O_y_max(S_region_y1), .O_count(S_region_count),
        .O_busy(S_region_busy), .O_overrun(S_region_overrun)
    );
    wire S_candidate = S_commit_good_d && S_region_ready &&
                       S_region_valid && !S_region_overrun;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_conf<=0;
            O_valid<=0; O_count<=0; O_x_min<=0; O_x_max<=0; O_y_min<=0; O_y_max<=0;
            O_commit<=0; O_empty<=0;
        end else if (S_commit_d) begin
            if (S_candidate) begin
                if (S_conf<CONFIRM_COUNT) S_conf<=S_conf+1'b1;
                O_valid<=(S_conf>=CONFIRM_COUNT-1'b1);
                O_count<=S_region_count;
                O_x_min<={S_region_x0,2'b00}; O_x_max<={S_region_x1,2'b00}+11'd3;
                O_y_min<={S_region_y0,2'b00}; O_y_max<={S_region_y1,2'b00}+10'd3;
                O_commit<=~O_commit; O_empty<=1'b0;
            end else begin
                S_conf<=0; O_valid<=0; O_count<=0;
                // A completed, ready scan with no candidate is a real empty
                // frame. If the scan was not ready or overran, leave the
                // previous display result eligible for its short hold time.
                if (S_commit_good_d && S_region_ready && !S_region_overrun) begin
                    O_commit<=~O_commit;
                    O_empty<=1'b1;
                end
            end
        end
    end
endmodule
