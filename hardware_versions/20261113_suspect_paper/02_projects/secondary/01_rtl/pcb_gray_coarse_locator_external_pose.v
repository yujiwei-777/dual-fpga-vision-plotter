// Area candidate: original exact two-pass exhaustive search controller,
// with its pose generator externalized. No independent coarse math instance.
// Ranking, legal bounds, per-sample reads and runner distinction are unchanged.
// Exact integer gray256 exhaustive coarse proposal search. One selected
// synchronous workspace read (one registered data cycle), shared external
// statistics and signed36 NCC engines. Coarse NCC is diagnostic only; this
// module never declares whole-board registration or PCB PASS.
module pcb_gray_coarse_locator_external_pose #(
    parameter [14:0] IMAGE_BASE=15'd8192,
    parameter FEATURE_BANK=1'b1,
    parameter [14:0] FEATURE_BASE=15'd4876,
    parameter [14:0] OFFSET_BASE=15'd12800,
    parameter integer WIDTH_FIRST=0,WIDTH_LAST=13,
    parameter integer ANGLE_FIRST=0,ANGLE_LAST=9,
    parameter integer SEARCH_X_MIN=0,SEARCH_X_MAX=127,
    parameter integer SEARCH_Y_MIN=0,SEARCH_Y_MAX=71,
    parameter [31:0] TOTAL_TIMEOUT=32'd2000000000
)(
    input wire I_clk,I_rst_n,I_start,I_cancel,
    output wire O_busy,
    output reg O_done,O_proposal_valid,
    output reg [3:0] O_error,
    output reg [3:0] O_width_index,O_angle_index,
    output reg [7:0] O_pose_index,
    output reg [6:0] O_center_x,O_center_y,
    output reg [30:0] O_score2_q30,O_runner_score2_q30,
    output reg [3:0] O_runner_width_index,O_runner_angle_index,
    output reg [6:0] O_runner_center_x,O_runner_center_y,
    output reg [31:0] O_cycles,O_candidates,
    output reg O_rd_bank,
    output reg [14:0] O_rd_addr,
    input wire [15:0] I_rd_data,
    // One external geometry engine serves pose offsets and affine packets.
    // Pose host writes OFFSET_BASE..OFFSET_BASE+255 before reporting done.
    output wire O_pose_start,O_pose_cancel,
    output wire [3:0] O_pose_width_index,O_pose_angle_index,
    input wire I_pose_done,I_pose_valid,
    input wire [3:0] I_pose_error,
    input wire [6:0] I_pose_xmin,I_pose_ymin,
    output wire O_stats_start,O_stats_cancel,
    output wire [3:0] O_stats_count_log2,
    output wire O_sample_valid,
    input wire I_sample_ready,
    output wire [7:0] O_sample_i,O_sample_t,
    input wire I_stats_done,I_stats_valid,
    input wire [3:0] I_stats_error,
    input wire signed [35:0] I_stats_covariance,
    input wire [35:0] I_stats_variance_i,I_stats_variance_t,
    output wire O_ncc_start,O_ncc_cancel,
    output wire signed [35:0] O_covariance,
    output wire [35:0] O_variance_i,O_variance_t,
    input wire I_ncc_done,I_ncc_valid,
    input wire [30:0] I_ncc_score2_q30,
    input wire [3:0] I_ncc_error,
    // One pulse per visited hypothesis, for exact RTL/reference diagnostics.
    output wire O_candidate_valid,O_candidate_pass,
    output wire [3:0] O_candidate_width_index,O_candidate_angle_index,
    output wire [6:0] O_candidate_x,O_candidate_y,
    output wire [30:0] O_candidate_score2_q30
);
    localparam [4:0] IDLE=0,PSTART=1,PWAIT=2,CSTART=3,OADDR=4,OWAIT=5,
                     TADDR=6,TWAIT=7,IADDR=8,IWAIT=9,FEED=10,STWAIT=11,
                     NSTART=12,NWAIT=13,RANK=14,CNEXT=15,PNEXT=16;
    reg [4:0] state;
    reg pass,have_best,have_runner;
    reg [3:0] wi,ai;
    reg [7:0] pose_index,sample_index;
    reg [6:0] cx,cy,xmin,xmax,ymin,ymax,pixel_x,pixel_y;
    reg [7:0] sample_i,sample_t;
    reg [30:0] candidate_score;
    reg signed [35:0] covariance;
    reg [35:0] variance_i,variance_t;
    wire gen_done=I_pose_done,gen_valid=I_pose_valid;
    wire [3:0] gen_error=I_pose_error;
    wire [6:0] gen_xmin=I_pose_xmin,gen_ymin=I_pose_ymin;
    wire abort_request=I_cancel || (I_start && state!=IDLE) ||
                       (state!=IDLE && O_cycles>=TOTAL_TIMEOUT-1);
    wire signed [9:0] mapped_x=$signed({3'd0,cx})+$signed({{2{I_rd_data[7]}},I_rd_data[7:0]});
    wire signed [9:0] mapped_y=$signed({3'd0,cy})+$signed({{2{I_rd_data[15]}},I_rd_data[15:8]});
    wire [6:0] limited_xmin=gen_xmin<SEARCH_X_MIN?SEARCH_X_MIN[6:0]:gen_xmin;
    wire [6:0] limited_ymin=gen_ymin<SEARCH_Y_MIN?SEARCH_Y_MIN[6:0]:gen_ymin;
    wire [6:0] natural_xmax=7'd127-gen_xmin,natural_ymax=7'd71-gen_ymin;
    wire [6:0] limited_xmax=natural_xmax>SEARCH_X_MAX?SEARCH_X_MAX[6:0]:natural_xmax;
    wire [6:0] limited_ymax=natural_ymax>SEARCH_Y_MAX?SEARCH_Y_MAX[6:0]:natural_ymax;
    wire [7:0] delta_width=wi>=O_width_index?{4'd0,wi-O_width_index}:{4'd0,O_width_index-wi};
    wire [6:0] delta_x=cx>=O_center_x?cx-O_center_x:O_center_x-cx;
    wire [6:0] delta_y=cy>=O_center_y?cy-O_center_y:O_center_y-cy;
    wire [7:0] winner_width=8'd44+{O_width_index,2'b0}+{O_width_index,1'b0};
    wire [7:0] translation_limit=winner_width<50?8'd50:winner_width;
    wire [10:0] delta_x10={delta_x,3'b0}+{delta_x,1'b0};
    wire [10:0] delta_y10={delta_y,3'b0}+{delta_y,1'b0};
    wire [8:0] degrees=angle_degrees(ai),winner_degrees=angle_degrees(O_angle_index);
    wire [8:0] raw_angle_delta=degrees>winner_degrees?degrees-winner_degrees:winner_degrees-degrees;
    wire [8:0] angle_delta=raw_angle_delta>180?9'd360-raw_angle_delta:raw_angle_delta;
    wire distinct=(delta_width>=2) || angle_delta>=16 || delta_x10>=translation_limit || delta_y10>=translation_limit;
    assign O_busy=state!=IDLE;
    assign O_pose_start=state==PSTART && !abort_request;
    assign O_pose_cancel=abort_request;
    assign O_pose_width_index=wi;
    assign O_pose_angle_index=ai;
    assign O_stats_start=state==CSTART && !abort_request;
    assign O_stats_cancel=abort_request;
    assign O_stats_count_log2=8;
    assign O_sample_valid=state==FEED && !abort_request;
    assign O_sample_i=sample_i;
    assign O_sample_t=sample_t;
    assign O_ncc_start=state==NSTART && !abort_request;
    assign O_ncc_cancel=abort_request;
    assign O_covariance=covariance;
    assign O_variance_i=variance_i;
    assign O_variance_t=variance_t;
    assign O_candidate_valid=state==RANK && !abort_request;
    assign O_candidate_pass=pass;
    assign O_candidate_width_index=wi;
    assign O_candidate_angle_index=ai;
    assign O_candidate_x=cx;
    assign O_candidate_y=cy;
    assign O_candidate_score2_q30=candidate_score;

    function [8:0] angle_degrees;
        input [3:0] index;
        begin
            case(index)
                0:angle_degrees=352;
                1:angle_degrees=356;
                2:angle_degrees=0;
                3:angle_degrees=4;
                4:angle_degrees=8;
                5:angle_degrees=172;
                6:angle_degrees=176;
                7:angle_degrees=180;
                8:angle_degrees=184;
                9:angle_degrees=188;
                default:angle_degrees=0;
            endcase
        end
    endfunction
    always @* begin
        O_rd_bank=0;O_rd_addr=0;
        case(state)
            OADDR,OWAIT:begin O_rd_addr=OFFSET_BASE+sample_index;end
            TADDR,TWAIT:begin O_rd_bank=FEATURE_BANK;O_rd_addr=FEATURE_BASE+{7'd0,sample_index[7:1]};end
            IADDR,IWAIT:begin O_rd_addr=IMAGE_BASE+{2'd0,pixel_y,pixel_x[6:1]};end
            default:begin end
        endcase
    end
    task fail;
        input [3:0] code;
        begin state<=IDLE;O_done<=1;O_proposal_valid<=0;O_error<=code;end
    endtask
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;pass<=0;have_best<=0;have_runner<=0;wi<=0;ai<=0;pose_index<=0;sample_index<=0;
            cx<=0;cy<=0;xmin<=0;xmax<=0;ymin<=0;ymax<=0;pixel_x<=0;pixel_y<=0;
            sample_i<=0;sample_t<=0;candidate_score<=0;covariance<=0;variance_i<=0;variance_t<=0;
            O_done<=0;O_proposal_valid<=0;O_error<=0;O_width_index<=0;O_angle_index<=0;O_pose_index<=0;
            O_center_x<=0;O_center_y<=0;O_score2_q30<=0;O_runner_score2_q30<=0;
            O_runner_width_index<=0;O_runner_angle_index<=0;O_runner_center_x<=0;O_runner_center_y<=0;
            O_cycles<=0;O_candidates<=0;
        end else begin
            O_done<=0;
            if(I_cancel) begin state<=IDLE;O_proposal_valid<=0;O_error<=0;end
            else if(I_start && state!=IDLE) fail(4'd1);
            else if(state!=IDLE && O_cycles>=TOTAL_TIMEOUT-1) fail(4'd2);
            else begin
                if(state!=IDLE) O_cycles<=O_cycles+32'd1;
                case(state)
                    IDLE:if(I_start) begin
                        O_proposal_valid<=0;O_error<=0;O_cycles<=0;O_candidates<=0;
                        O_score2_q30<=0;O_runner_score2_q30<=0;
                        have_best<=0;have_runner<=0;pass<=0;wi<=WIDTH_FIRST;ai<=ANGLE_FIRST;
                        pose_index<=0;state<=PSTART;
                    end
                    PSTART:state<=PWAIT;
                    PWAIT:if(gen_done) begin
                        if(gen_error) fail(4'd3);
                        else if(!gen_valid) state<=PNEXT;
                        else begin
                            xmin<=limited_xmin;xmax<=limited_xmax;ymin<=limited_ymin;ymax<=limited_ymax;
                            cx<=limited_xmin;cy<=limited_ymin;
                            if(limited_xmin>limited_xmax || limited_ymin>limited_ymax) state<=PNEXT;
                            else state<=CSTART;
                        end
                    end
                    CSTART:begin sample_index<=0;state<=OADDR;end
                    OADDR:state<=OWAIT;
                    OWAIT:begin
                        if(mapped_x<0 || mapped_x>127 || mapped_y<0 || mapped_y>71) fail(4'd6);
                        else begin pixel_x<=mapped_x[6:0];pixel_y<=mapped_y[6:0];state<=TADDR;end
                    end
                    TADDR:state<=TWAIT;
                    TWAIT:begin sample_t<=sample_index[0]?I_rd_data[15:8]:I_rd_data[7:0];state<=IADDR;end
                    IADDR:state<=IWAIT;
                    IWAIT:begin sample_i<=pixel_x[0]?I_rd_data[15:8]:I_rd_data[7:0];state<=FEED;end
                    FEED:if(I_sample_ready) begin
                        if(sample_index==255) state<=STWAIT;
                        else begin sample_index<=sample_index+8'd1;state<=OADDR;end
                    end
                    STWAIT:if(I_stats_done) begin
                        if(!I_stats_valid || I_stats_error) fail(4'd4);
                        else begin
                            covariance<=I_stats_covariance;variance_i<=I_stats_variance_i;variance_t<=I_stats_variance_t;
                            if(I_stats_covariance<=0 || I_stats_variance_i<589824 || I_stats_variance_t==0) begin candidate_score<=0;state<=RANK;end
                            else state<=NSTART;
                        end
                    end
                    NSTART:state<=NWAIT;
                    NWAIT:if(I_ncc_done) begin
                        if(!I_ncc_valid || I_ncc_error) fail(4'd5);
                        else begin candidate_score<=I_ncc_score2_q30;state<=RANK;end
                    end
                    RANK:begin
                        O_candidates<=O_candidates+32'd1;
                        if(!pass && (!have_best || candidate_score>O_score2_q30)) begin
                            have_best<=1;O_score2_q30<=candidate_score;O_width_index<=wi;O_angle_index<=ai;
                            O_pose_index<=pose_index;O_center_x<=cx;O_center_y<=cy;
                        end else if(pass && distinct && (!have_runner || candidate_score>O_runner_score2_q30)) begin
                            have_runner<=1;O_runner_score2_q30<=candidate_score;O_runner_width_index<=wi;
                            O_runner_angle_index<=ai;O_runner_center_x<=cx;O_runner_center_y<=cy;
                        end
                        state<=CNEXT;
                    end
                    CNEXT:begin
                        if(cx==xmax) begin
                            cx<=xmin;
                            if(cy==ymax) begin pose_index<=pose_index+8'd1;state<=PNEXT;end
                            else begin cy<=cy+7'd1;state<=CSTART;end
                        end else begin cx<=cx+7'd1;state<=CSTART;end
                    end
                    PNEXT:begin
                        if(ai==ANGLE_LAST) begin
                            ai<=ANGLE_FIRST;
                            if(wi==WIDTH_LAST) begin
                                if(!pass) begin pass<=1;wi<=WIDTH_FIRST;pose_index<=0;state<=PSTART;end
                                else begin state<=IDLE;O_done<=1;O_proposal_valid<=have_best && O_score2_q30!=0;O_error<=0;end
                            end else begin wi<=wi+4'd1;state<=PSTART;end
                        end else begin ai<=ai+4'd1;state<=PSTART;end
                    end
                    default:fail(4'd15);
                endcase
            end
        end
    end
endmodule
