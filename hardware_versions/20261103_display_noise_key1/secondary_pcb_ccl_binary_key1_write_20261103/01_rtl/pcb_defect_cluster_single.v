// Single-slot PCB candidate reducer for the fixed inspection-window variant.
// The public interface remains identical to pcb_defect_cluster so the HXA1
// result and GRBL reporting paths do not change.  At most one candidate is
// emitted by the fixed-window scheduler; a higher score replaces the prior
// candidate defensively.
module pcb_defect_cluster #(
    parameter integer MAX_CLUSTERS=4,
    parameter integer DIST_SAME=48,
    parameter integer DIST_MIXED=24,
    parameter integer X_BITS=7,
    parameter integer Y_BITS=6,
    parameter integer COORD_SHIFT=4,
    parameter integer FIXED_WINDOW_GEOMETRY=1,
    parameter integer ENABLE_MIXED_REVIEW=0,
    parameter integer MERGE_UNION_BOUND_ONLY=1,
    parameter integer CLEAR_VALID_ONLY=1
)(
    input wire clk,input wire rst_n,input wire start,
    input wire candidate_valid,input wire candidate_last,
    input wire [63:0] candidate_box,input wire [1:0] candidate_kind,
    input wire [7:0] candidate_score,
    output wire candidate_ready,
    output reg busy,output reg done,output wire [2:0] cluster_count,
    output wire [255:0] cluster_boxes,output wire [7:0] cluster_kinds,
    output wire [31:0] cluster_scores,output wire review_present
);
    localparam [1:0] S_IDLE=2'd0,S_ACCEPT=2'd1,S_FINISH=2'd2;
    reg [1:0] state;
    reg valid_q;
    reg [63:0] box_q;
    reg [1:0] kind_q;
    reg [7:0] score_q;

    assign candidate_ready=busy && state==S_ACCEPT;
    assign cluster_count=busy ? 3'd0 : (valid_q ? 3'd1 : 3'd0);
    assign review_present=1'b0;
    assign cluster_boxes=(!busy && valid_q) ? {192'd0,box_q} : 256'd0;
    assign cluster_kinds=(!busy && valid_q) ? {6'd0,kind_q} : 8'd0;
    assign cluster_scores=(!busy && valid_q) ? {24'd0,score_q} : 32'd0;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=S_IDLE; busy<=1'b0; done<=1'b0;
            valid_q<=1'b0; box_q<=64'd0; kind_q<=2'd0; score_q<=8'd0;
        end else begin
            done<=1'b0;
            case(state)
                S_IDLE: if(start) begin
                    busy<=1'b1; valid_q<=1'b0; box_q<=64'd0;
                    kind_q<=2'd0; score_q<=8'd0; state<=S_ACCEPT;
                end
                S_ACCEPT: begin
                    if(candidate_valid && candidate_kind!=2'd0) begin
                        if(!valid_q || candidate_score>=score_q) begin
                            valid_q<=1'b1; box_q<=candidate_box;
                            kind_q<=candidate_kind; score_q<=candidate_score;
                        end
                    end
                    if(candidate_last) state<=S_FINISH;
                end
                S_FINISH: begin
                    busy<=1'b0; done<=1'b1; state<=S_IDLE;
                end
                default: begin busy<=1'b0; state<=S_IDLE; end
            endcase
        end
    end
endmodule
