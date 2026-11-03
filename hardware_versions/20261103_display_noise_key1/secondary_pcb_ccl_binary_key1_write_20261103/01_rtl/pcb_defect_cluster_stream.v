// Four-slot PCB candidate reducer with a sequential four-cycle scan.
// Same-kind overlapping windows are merged and the lowest-score slot is
// replaced when the table is full.  The score sort is intentionally omitted;
// slot order is not part of the PCB result contract.
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
    input wire [63:0] candidate_box,
    input wire [1:0] candidate_kind,input wire [7:0] candidate_score,
    output wire candidate_ready,
    output reg busy,output reg done,output wire [2:0] cluster_count,
    output wire [255:0] cluster_boxes,output wire [7:0] cluster_kinds,
    output wire [31:0] cluster_scores,output wire review_present
);
    localparam [2:0] S_IDLE=3'd0,S_ACCEPT=3'd1,S_SCAN=3'd2,
                     S_INSERT=3'd3,S_POST=3'd4;
    localparam integer BOX_W=26;
    reg [2:0] state;
    reg [BOX_W-1:0] boxes[0:3];
    reg [1:0] kinds[0:3];
    reg [7:0] scores[0:3];
    reg [2:0] count_q;
    reg [BOX_W-1:0] work_box;
    reg [1:0] work_kind;
    reg [7:0] work_score;
    reg [1:0] index,free_slot,overlap_slot,min_slot;
    reg free_found,overlap_found,last_pending;
    reg [7:0] min_score;
    integer i;

    assign candidate_ready=busy && state==S_ACCEPT;
    assign cluster_count=busy ? 3'd0 : count_q;
    assign review_present=1'b0;

    function [BOX_W-1:0] pack_box;
        input [63:0] b;
        reg [6:0] x0,x1;
        reg [5:0] y0,y1;
        begin
            x0=b[15:0]>>4; y0=b[31:16]>>4;
            x1=b[47:32]>>4; y1=b[63:48]>>4;
            pack_box={y1,x1,y0,x0};
        end
    endfunction
    function [63:0] unpack_box;
        input [BOX_W-1:0] b;
        begin
            unpack_box=64'd0;
            unpack_box[15:0]={{9{1'b0}},b[6:0]}<<4;
            unpack_box[31:16]={{10{1'b0}},b[12:7]}<<4;
            unpack_box[47:32]={{9{1'b0}},b[19:13]}<<4;
            unpack_box[63:48]={{10{1'b0}},b[25:20]}<<4;
        end
    endfunction
    function overlap_box;
        input [BOX_W-1:0] a,b;
        begin overlap_box=(a[6:0]<b[19:13]) && (b[6:0]<a[19:13]) &&
                           (a[12:7]<b[25:20]) && (b[12:7]<a[25:20]); end
    endfunction
    function [BOX_W-1:0] union_box;
        input [BOX_W-1:0] a,b;
        begin
            union_box[6:0]=a[6:0]<b[6:0]?a[6:0]:b[6:0];
            union_box[12:7]=a[12:7]<b[12:7]?a[12:7]:b[12:7];
            union_box[19:13]=a[19:13]>b[19:13]?a[19:13]:b[19:13];
            union_box[25:20]=a[25:20]>b[25:20]?a[25:20]:b[25:20];
        end
    endfunction

    genvar slot;
    generate for(slot=0;slot<4;slot=slot+1) begin : g_publish
        wire valid=!busy && (kinds[slot]==1 || kinds[slot]==2);
        assign cluster_boxes[slot*64+:64]=valid ? unpack_box(boxes[slot]) : 64'd0;
        assign cluster_kinds[slot*2+:2]=valid ? kinds[slot] : 2'd0;
        assign cluster_scores[slot*8+:8]=valid ? scores[slot] : 8'd0;
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=S_IDLE;busy<=0;done<=0;count_q<=0;
            work_box<=0;work_kind<=0;work_score<=0;index<=0;
            free_slot<=0;overlap_slot<=0;min_slot<=0;
            free_found<=0;overlap_found<=0;last_pending<=0;min_score<=0;
            for(i=0;i<4;i=i+1) begin boxes[i]<=0;kinds[i]<=0;scores[i]<=0;end
        end else begin
            done<=0;
            case(state)
                S_IDLE: if(start) begin
                    busy<=1;count_q<=0;index<=0;
                    for(i=0;i<4;i=i+1) begin boxes[i]<=0;kinds[i]<=0;scores[i]<=0;end
                    state<=S_ACCEPT;
                end
                S_ACCEPT: begin
                    if(candidate_valid) begin
                        work_box<=pack_box(candidate_box);work_kind<=candidate_kind;
                        work_score<=candidate_score;last_pending<=candidate_last;
                        index<=0;free_slot<=0;overlap_slot<=0;min_slot<=0;
                        free_found<=0;overlap_found<=0;min_score<=8'hff;
                        if(candidate_kind==0) state<=S_POST; else state<=S_SCAN;
                    end else if(candidate_last) begin
                        busy<=0;done<=1;state<=S_IDLE;
                    end
                end
                S_SCAN: begin
                    if(!free_found && kinds[index]==0) begin free_found<=1;free_slot<=index;end
                    if(!overlap_found && kinds[index]==work_kind &&
                       overlap_box(work_box,boxes[index])) begin
                        overlap_found<=1;overlap_slot<=index;
                    end
                    if(scores[index]<min_score) begin min_score<=scores[index];min_slot<=index;end
                    if(index==3) state<=S_INSERT; else index<=index+1'b1;
                end
                S_INSERT: begin
                    if(overlap_found) begin
                        boxes[overlap_slot]<=union_box(work_box,boxes[overlap_slot]);
                        kinds[overlap_slot]<=work_kind;
                        if(work_score>scores[overlap_slot]) scores[overlap_slot]<=work_score;
                    end else if(free_found) begin
                        boxes[free_slot]<=work_box;kinds[free_slot]<=work_kind;
                        scores[free_slot]<=work_score;count_q<=count_q+1'b1;
                    end else if(work_score>min_score) begin
                        boxes[min_slot]<=work_box;kinds[min_slot]<=work_kind;scores[min_slot]<=work_score;
                    end
                    state<=S_POST;
                end
                S_POST: begin
                    if(last_pending) begin busy<=0;done<=1;state<=S_IDLE;end
                    else state<=S_ACCEPT;
                end
                default: begin busy<=0;state<=S_IDLE;end
            endcase
        end
    end
endmodule
