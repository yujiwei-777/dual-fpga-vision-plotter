// Fixed-grid PCB candidate reducer.
// Overlapping same-kind windows are represented by the highest scoring
// window, preserving four output slots without generic review/union storage.
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
    localparam integer LIMIT=(MAX_CLUSTERS<4)?MAX_CLUSTERS:4;
    localparam integer BOX_W=26;
    localparam [3:0] IDLE=0,ACCEPT=1,SCAN=2,INSERT=3,SORT=4,POST=5,FLUSH=6;
    reg [3:0] state;
    reg [BOX_W-1:0] boxes[0:3];
    reg [1:0] kinds[0:3];
    reg [7:0] scores[0:3];
    reg [2:0] cluster_count_q;
    reg [BOX_W-1:0] work_box;
    reg [1:0] work_kind;
    reg [7:0] work_score;
    reg [1:0] index,sort_index,sort_pass,free_slot,overlap_slot,min_slot;
    reg free_found,overlap_found,last_pending;
    reg [7:0] min_score;
    integer k;

    assign candidate_ready=busy && state==ACCEPT;
    assign cluster_count=busy ? 3'd0 : cluster_count_q;
    assign review_present=1'b0;

    function [BOX_W-1:0] pack_box;
        input [63:0] b;
        begin pack_box={b[63:48]>>4,b[47:32]>>4,b[31:16]>>4,b[15:0]>>4}; end
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
        begin
            overlap_box=(a[6:0]<b[19:13]) && (b[6:0]<a[19:13]) &&
                        (a[12:7]<b[25:20]) && (b[12:7]<a[25:20]);
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
            state<=IDLE; busy<=0; done<=0; cluster_count_q<=0;
            work_box<=0; work_kind<=0; work_score<=0;
            index<=0; sort_index<=0; sort_pass<=0;
            free_slot<=0; overlap_slot<=0; min_slot<=0;
            free_found<=0; overlap_found<=0; last_pending<=0; min_score<=0;
            for(k=0;k<4;k=k+1) begin boxes[k]<=0; kinds[k]<=0; scores[k]<=0; end
        end else begin
            done<=0;
            case(state)
                IDLE: if(start) begin
                    busy<=1; cluster_count_q<=0;
                    for(k=0;k<4;k=k+1) begin boxes[k]<=0; kinds[k]<=0; scores[k]<=0; end
                    state<=ACCEPT;
                end
                ACCEPT: begin
                    if(candidate_valid) begin
                        work_box<=pack_box(candidate_box);
                        work_kind<=candidate_kind;
                        work_score<=candidate_score;
                        last_pending<=candidate_last;
                        index<=0; free_found<=0; overlap_found<=0;
                        free_slot<=0; overlap_slot<=0; min_slot<=0; min_score<=8'hff;
                        if(candidate_kind==0) state<=POST; else state<=SCAN;
                    end else if(candidate_last) begin
                        index<=0; cluster_count_q<=0; state<=FLUSH;
                    end
                end
                SCAN: begin
                    if(index<LIMIT) begin
                        if(!free_found && kinds[index]==0) begin free_found<=1; free_slot<=index; end
                        if(!overlap_found && kinds[index]==work_kind && overlap_box(work_box,boxes[index])) begin
                            overlap_found<=1; overlap_slot<=index;
                        end
                        if(scores[index]<min_score) begin min_score<=scores[index]; min_slot<=index; end
                    end
                    if(index==3) state<=INSERT; else index<=index+1'b1;
                end
                INSERT: begin
                    if(overlap_found) begin
                        if(work_score>scores[overlap_slot]) begin
                            boxes[overlap_slot]<=work_box; scores[overlap_slot]<=work_score; kinds[overlap_slot]<=work_kind;
                        end
                    end else if(free_found) begin
                        boxes[free_slot]<=work_box; kinds[free_slot]<=work_kind; scores[free_slot]<=work_score;
                    end else if(work_score>min_score) begin
                        boxes[min_slot]<=work_box; kinds[min_slot]<=work_kind; scores[min_slot]<=work_score;
                    end
                    sort_index<=0; sort_pass<=0; state<=SORT;
                end
                SORT: begin
                    if((kinds[sort_index]==0 && kinds[sort_index+1'b1]!=0) ||
                       (kinds[sort_index+1'b1]!=0 && scores[sort_index+1'b1]>scores[sort_index])) begin
                        boxes[sort_index]<=boxes[sort_index+1'b1]; boxes[sort_index+1'b1]<=boxes[sort_index];
                        kinds[sort_index]<=kinds[sort_index+1'b1]; kinds[sort_index+1'b1]<=kinds[sort_index];
                        scores[sort_index]<=scores[sort_index+1'b1]; scores[sort_index+1'b1]<=scores[sort_index];
                    end
                    if(sort_index==2-sort_pass) begin
                        sort_index<=0;
                        if(sort_pass==2) state<=POST; else sort_pass<=sort_pass+1'b1;
                    end else sort_index<=sort_index+1'b1;
                end
                POST: begin
                    if(last_pending) begin index<=0; cluster_count_q<=0; state<=FLUSH; end
                    else state<=ACCEPT;
                end
                FLUSH: begin
                    if(kinds[index]==1 || kinds[index]==2) cluster_count_q<=cluster_count_q+1'b1;
                    if(index==3) begin busy<=0; done<=1; state<=IDLE; end
                    else index<=index+1'b1;
                end
                default: begin busy<=0; state<=IDLE; end
            endcase
        end
    end
endmodule
