// Select a local motion component from a 320x180 sampled difference mask.
// The video path never waits for this module. Each 8x8 tile retains its changed
// sample count and exact local bounds; sparse tiles are discarded. After the
// final sample, an eight-neighbour flood fill selects the largest qualifying
// component. When no individual component qualifies, substantial components
// may form one qualifying union (e.g. a moving target's disjoint leading and
// trailing edges). Tiny remote fragments never enter that fallback union.
// Results remain stable until I_frame_start, when the consumer
// must sample O_ready and the result before the new frame replaces them.
module motion_region_select #(
    parameter [15:0] MIN_AREA = 16'd400,
    parameter [6:0] TILE_MIN_COUNT = 7'd4,
    parameter integer DENSITY_SHIFT = 3,
    parameter [8:0] MAX_BOX_W = 9'd280,
    parameter [7:0] MAX_BOX_H = 8'd160
)(
    input wire I_clk,
    input wire I_rst_n,
    input wire I_frame_start,
    input wire I_sample,
    input wire I_changed,
    input wire [8:0] I_x,
    input wire [7:0] I_y,
    output reg O_ready,
    output reg O_valid,
    output reg [8:0] O_x_min,
    output reg [8:0] O_x_max,
    output reg [7:0] O_y_min,
    output reg [7:0] O_y_max,
    output reg [15:0] O_count,
    output wire O_busy,
    output reg O_overrun
);
    localparam [4:0] COLLECT=0, SCAN_REQ=1, SCAN_WAIT=2, SCAN_EVAL=3,
        SCAN_ADV=4, POP_REQ=5, POP_WAIT=6, POP_EVAL=7, NEIGH_PREP=8,
        NEIGH_REQ=9, NEIGH_WAIT=10, NEIGH_EVAL=11, POP_CHECK=12,
        COMP_SIZE=13, COMP_AREA=14, COMP_CHECK=15, FINISH=16, HOLD=17;
    localparam [15:0] SUPPORT_AREA=(MIN_AREA<16'd4) ? 16'd1 : (MIN_AREA>>2);
    reg [4:0] S_state;
    assign O_busy=(S_state!=COLLECT)&&(S_state!=HOLD);

    // Metadata layout: count[18:12], xmin[11:9], xmax[8:6],
    // ymin[5:3], ymax[2:0]. The first row of every tile starts from zero,
    // so no reset loop or initial contents are required for either RAM.
    (* ram_style="dram" *) reg [18:0] S_row_mem[0:63];
    (* ram_style="bram" *) reg [18:0] S_map_mem[0:1023];
    (* ram_style="bram" *) reg [10:0] S_queue_mem[0:1023];
    reg [18:0] S_row_q, S_map_q;
    reg [10:0] S_queue_q;
    reg S_sample_d, S_changed_d;
    reg [8:0] S_x_d;
    reg [7:0] S_y_d;
    reg [18:0] S_tile_acc;

    always @(posedge I_clk) begin
        if (I_rst_n && I_sample) S_row_q<=S_row_mem[I_x[8:3]];
    end
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_sample_d<=0; S_changed_d<=0; S_x_d<=0; S_y_d<=0;
        end else begin
            S_sample_d<=I_sample;
            if (I_sample) begin
                S_changed_d<=I_changed; S_x_d<=I_x; S_y_d<=I_y;
            end
        end
    end

    reg [18:0] S_tile_next;
    reg [18:0] S_tile_base;
    always @* begin
        S_tile_base=S_tile_acc;
        if (S_x_d[2:0]==0)
            S_tile_base=(S_y_d[2:0]==0) ? 19'd0 : S_row_q;
        S_tile_next=S_tile_base;
        if (S_changed_d) begin
            S_tile_next[18:12]=S_tile_base[18:12]+7'd1;
            if (S_tile_base[18:12]==0) begin
                S_tile_next[11:9]=S_x_d[2:0];
                S_tile_next[8:6]=S_x_d[2:0];
                S_tile_next[5:3]=S_y_d[2:0];
                S_tile_next[2:0]=S_y_d[2:0];
            end else begin
                if (S_x_d[2:0]<S_tile_base[11:9]) S_tile_next[11:9]=S_x_d[2:0];
                if (S_x_d[2:0]>S_tile_base[8:6]) S_tile_next[8:6]=S_x_d[2:0];
                if (S_y_d[2:0]<S_tile_base[5:3]) S_tile_next[5:3]=S_y_d[2:0];
                if (S_y_d[2:0]>S_tile_base[2:0]) S_tile_next[2:0]=S_y_d[2:0];
            end
        end
    end
    wire S_collect_sample=S_sample_d && (S_state==COLLECT) && !I_frame_start;
    wire S_row_write=S_collect_sample && (S_x_d[2:0]==7);
    wire S_tile_write=S_row_write && ((S_y_d[2:0]==7)||(S_y_d==8'd179));
    wire [9:0] S_tile_addr=({5'd0,S_y_d[7:3]}<<5)
                            +({5'd0,S_y_d[7:3]}<<3)+{4'd0,S_x_d[8:3]};
    always @(posedge I_clk) begin
        if (I_rst_n && S_row_write) S_row_mem[S_x_d[8:3]]<=S_tile_next;
    end

    reg [9:0] S_scan_addr, S_neigh_addr;
    reg [5:0] S_scan_x, S_node_x, S_neigh_x;
    reg [4:0] S_scan_y, S_node_y, S_neigh_y;
    reg [2:0] S_neigh_index;
    reg [10:0] S_q_head, S_q_tail;
    reg [5:0] S_next_x;
    reg [4:0] S_next_y;
    reg S_next_valid;
    always @* begin
        S_next_x=S_node_x;
        S_next_y=S_node_y;
        S_next_valid=1'b1;
        case (S_neigh_index)
            0: begin S_next_x=S_node_x-1'b1; S_next_y=S_node_y-1'b1;
                S_next_valid=(S_node_x!=0)&&(S_node_y!=0); end
            1: begin S_next_y=S_node_y-1'b1; S_next_valid=(S_node_y!=0); end
            2: begin S_next_x=S_node_x+1'b1; S_next_y=S_node_y-1'b1;
                S_next_valid=(S_node_x!=39)&&(S_node_y!=0); end
            3: begin S_next_x=S_node_x-1'b1; S_next_valid=(S_node_x!=0); end
            4: begin S_next_x=S_node_x+1'b1; S_next_valid=(S_node_x!=39); end
            5: begin S_next_x=S_node_x-1'b1; S_next_y=S_node_y+1'b1;
                S_next_valid=(S_node_x!=0)&&(S_node_y!=22); end
            6: begin S_next_y=S_node_y+1'b1; S_next_valid=(S_node_y!=22); end
            7: begin S_next_x=S_node_x+1'b1; S_next_y=S_node_y+1'b1;
                S_next_valid=(S_node_x!=39)&&(S_node_y!=22); end
        endcase
    end

    // The migrated document profile fixes TILE_MIN_COUNT at four.  Expand
    // that comparison explicitly so the near-full SLICEL device does not
    // spend a generic comparator on a constant threshold.
    wire S_tile_qualifies;
    generate
        if (TILE_MIN_COUNT == 7'd4) begin : g_tile_min_four
            assign S_tile_qualifies = (|S_map_q[18:15]) || S_map_q[14];
        end else begin : g_tile_min_generic
            assign S_tile_qualifies = (S_map_q[18:12] >= TILE_MIN_COUNT);
        end
    endgenerate
    wire S_seed=(S_state==SCAN_EVAL)&&S_tile_qualifies;
    wire S_neighbor=(S_state==NEIGH_EVAL)&&S_tile_qualifies;
    wire S_enqueue=(S_seed || S_neighbor) && (S_seed || S_q_tail<11'd1024)
                    && !I_frame_start && I_rst_n;
    wire [5:0] S_found_x=S_seed ? S_scan_x : S_neigh_x;
    wire [4:0] S_found_y=S_seed ? S_scan_y : S_neigh_y;
    wire [8:0] S_found_x_min={S_found_x,3'b000}+{6'd0,S_map_q[11:9]};
    wire [8:0] S_found_x_max={S_found_x,3'b000}+{6'd0,S_map_q[8:6]};
    wire [7:0] S_found_y_min={S_found_y,3'b000}+{5'd0,S_map_q[5:3]};
    wire [7:0] S_found_y_max={S_found_y,3'b000}+{5'd0,S_map_q[2:0]};
    wire S_map_read=(S_state==SCAN_REQ)||(S_state==NEIGH_REQ);
    wire [9:0] S_map_read_addr=(S_state==SCAN_REQ) ? S_scan_addr : S_neigh_addr;
    wire [9:0] S_map_clear_addr=S_seed ? S_scan_addr : S_neigh_addr;
    always @(posedge I_clk) begin
        if (I_rst_n && !I_frame_start && S_map_read)
            S_map_q<=S_map_mem[S_map_read_addr];
        if (I_rst_n && S_tile_write)
            S_map_mem[S_tile_addr]<=(((TILE_MIN_COUNT == 7'd4) &&
                                      ((|S_tile_next[18:15]) || S_tile_next[14])) ||
                                     ((TILE_MIN_COUNT != 7'd4) &&
                                      (S_tile_next[18:12]>=TILE_MIN_COUNT)))
                                   ? S_tile_next : 19'd0;
        else if (S_enqueue) S_map_mem[S_map_clear_addr]<=19'd0;
        if (S_enqueue)
            S_queue_mem[S_seed ? 10'd0 : S_q_tail[9:0]]<={S_found_y,S_found_x};
        if (I_rst_n && !I_frame_start && (S_state==POP_REQ))
            S_queue_q<=S_queue_mem[S_q_head[9:0]];
    end

    reg [15:0] S_comp_count, S_best_count;
    reg [8:0] S_comp_x_min, S_comp_x_max, S_best_x_min, S_best_x_max;
    reg [7:0] S_comp_y_min, S_comp_y_max, S_best_y_min, S_best_y_max;
    reg [8:0] S_comp_width;
    reg [7:0] S_comp_height;
    reg [16:0] S_comp_area;
    reg S_best_valid;
    reg S_union_eval;
    reg [15:0] S_support_count;
    reg [8:0] S_support_x_min, S_support_x_max;
    reg [7:0] S_support_y_min, S_support_y_max;
    // Full-frame luminance changes still fail the width/height guard. Use a
    // constant shift, never a divider/DSP, to retain sparse moving edges.
    wire [31:0] S_density_support = {16'd0,S_comp_count} << DENSITY_SHIFT;
    wire S_comp_shape_ok=(S_comp_width<=MAX_BOX_W) && (S_comp_height<=MAX_BOX_H)
        && (S_comp_area!=0) && (S_density_support>={15'd0,S_comp_area});
    wire S_area_qualifies;
    generate
        if (MIN_AREA == 16'd80) begin : g_area_min_eighty
            assign S_area_qualifies = (|S_comp_count[15:7]) ||
                                      (S_comp_count[6] &&
                                       (S_comp_count[5] || S_comp_count[4]));
        end else begin : g_area_min_generic
            assign S_area_qualifies = (S_comp_count>=MIN_AREA);
        end
    endgenerate
    wire S_comp_qualifies=S_area_qualifies && S_comp_shape_ok;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_state<=COLLECT; S_tile_acc<=0;
            S_scan_addr<=0; S_scan_x<=0; S_scan_y<=0;
            S_neigh_addr<=0; S_neigh_x<=0; S_neigh_y<=0;
            S_node_x<=0; S_node_y<=0; S_neigh_index<=0;
            S_q_head<=0; S_q_tail<=0;
            S_comp_count<=0; S_comp_x_min<=0; S_comp_x_max<=0;
            S_comp_y_min<=0; S_comp_y_max<=0;
            S_comp_width<=0; S_comp_height<=0; S_comp_area<=0;
            S_union_eval<=0; S_support_count<=0;
            S_support_x_min<=0; S_support_x_max<=0; S_support_y_min<=0; S_support_y_max<=0;
            S_best_valid<=0; S_best_count<=0;
            S_best_x_min<=0; S_best_x_max<=0; S_best_y_min<=0; S_best_y_max<=0;
            O_ready<=0; O_valid<=0; O_count<=0;
            O_x_min<=0; O_x_max<=0; O_y_min<=0; O_y_max<=0; O_overrun<=0;
        end else if (I_frame_start) begin
            // The parent samples the old O_ready/result on this same edge.
            // A late scan is abandoned, never committed as a partial result.
            // A previous unfinished scan has O_ready=0 at this edge. Start
            // this frame cleanly rather than carrying its fault into the
            // next complete result.
            O_overrun<=0;
            O_ready<=0; O_valid<=0; O_count<=0;
            S_state<=COLLECT; S_tile_acc<=0;
            S_best_valid<=0; S_best_count<=0;
            S_union_eval<=0; S_support_count<=0;
            S_scan_addr<=0; S_scan_x<=0; S_scan_y<=0;
            S_q_head<=0; S_q_tail<=0;
        end else if (I_sample && O_busy) begin
            // Unexpected video during the post-frame scan cannot share the
            // map RAM with its clear-on-enqueue writes. Wait for a clean USER.
            S_state<=HOLD; O_ready<=0; O_valid<=0; O_count<=0; O_overrun<=1;
        end else begin
            case (S_state)
                COLLECT: if (S_sample_d) begin
                    S_tile_acc<=S_tile_next;
                    if ((S_x_d==9'd319)&&(S_y_d==8'd179)) begin
                        // This edge writes tile 919. First synchronous read
                        // occurs on the following clock in SCAN_REQ.
                        S_scan_addr<=0; S_scan_x<=0; S_scan_y<=0;
                        S_best_valid<=0; S_best_count<=0;
                        S_state<=SCAN_REQ;
                    end
                end
                SCAN_REQ: S_state<=SCAN_WAIT;
                SCAN_WAIT: S_state<=SCAN_EVAL;
                SCAN_EVAL: begin
                    if (S_seed) begin
                        S_comp_count<={9'd0,S_map_q[18:12]};
                        S_comp_x_min<=S_found_x_min; S_comp_x_max<=S_found_x_max;
                        S_comp_y_min<=S_found_y_min; S_comp_y_max<=S_found_y_max;
                        S_q_head<=0; S_q_tail<=1;
                        S_state<=POP_REQ;
                    end else S_state<=SCAN_ADV;
                end
                SCAN_ADV: begin
                    if (S_scan_addr==10'd919) S_state<=FINISH;
                    else begin
                        S_scan_addr<=S_scan_addr+1'b1;
                        if (S_scan_x==6'd39) begin S_scan_x<=0; S_scan_y<=S_scan_y+1'b1; end
                        else S_scan_x<=S_scan_x+1'b1;
                        S_state<=SCAN_REQ;
                    end
                end
                POP_REQ: begin S_q_head<=S_q_head+1'b1; S_state<=POP_WAIT; end
                POP_WAIT: S_state<=POP_EVAL;
                POP_EVAL: begin
                    S_node_x<=S_queue_q[5:0]; S_node_y<=S_queue_q[10:6];
                    S_neigh_index<=0; S_state<=NEIGH_PREP;
                end
                NEIGH_PREP: begin
                    if (S_next_valid) begin
                        S_neigh_x<=S_next_x; S_neigh_y<=S_next_y;
                        S_neigh_addr<=({5'd0,S_next_y}<<5)+({5'd0,S_next_y}<<3)+{4'd0,S_next_x};
                        S_state<=NEIGH_REQ;
                    end else if (S_neigh_index==7) S_state<=POP_CHECK;
                    else S_neigh_index<=S_neigh_index+1'b1;
                end
                NEIGH_REQ: S_state<=NEIGH_WAIT;
                NEIGH_WAIT: S_state<=NEIGH_EVAL;
                NEIGH_EVAL: begin
                    if (S_neighbor && (S_q_tail>=11'd1024)) begin
                        S_state<=HOLD; O_ready<=0; O_valid<=0; O_count<=0; O_overrun<=1;
                    end else begin
                        if (S_neighbor) begin
                            S_q_tail<=S_q_tail+1'b1;
                            S_comp_count<=S_comp_count+{9'd0,S_map_q[18:12]};
                            if (S_found_x_min<S_comp_x_min) S_comp_x_min<=S_found_x_min;
                            if (S_found_x_max>S_comp_x_max) S_comp_x_max<=S_found_x_max;
                            if (S_found_y_min<S_comp_y_min) S_comp_y_min<=S_found_y_min;
                            if (S_found_y_max>S_comp_y_max) S_comp_y_max<=S_found_y_max;
                        end
                        if (S_neigh_index==7) S_state<=POP_CHECK;
                        else begin S_neigh_index<=S_neigh_index+1'b1; S_state<=NEIGH_PREP; end
                    end
                end
                POP_CHECK: S_state<=(S_q_head<S_q_tail) ? POP_REQ : COMP_SIZE;
                COMP_SIZE: begin
                    S_comp_width<=S_comp_x_max-S_comp_x_min+9'd1;
                    S_comp_height<=S_comp_y_max-S_comp_y_min+8'd1;
                    S_state<=COMP_AREA;
                end
                COMP_AREA: begin
                    // One small registered multiplier replaces the original
                    // detector's frame-wide fill-rate product.
                    S_comp_area<=S_comp_width*S_comp_height;
                    S_state<=COMP_CHECK;
                end
                COMP_CHECK: begin
                    if (S_comp_qualifies && (!S_best_valid || S_comp_count>S_best_count)) begin
                        S_best_valid<=1; S_best_count<=S_comp_count;
                        S_best_x_min<=S_comp_x_min; S_best_x_max<=S_comp_x_max;
                        S_best_y_min<=S_comp_y_min; S_best_y_max<=S_comp_y_max;
                    end
                    if (!S_union_eval && (S_comp_count>=SUPPORT_AREA) && S_comp_shape_ok) begin
                        S_support_count<=S_support_count+S_comp_count;
                        if ((S_support_count==0)||(S_comp_x_min<S_support_x_min)) S_support_x_min<=S_comp_x_min;
                        if ((S_support_count==0)||(S_comp_x_max>S_support_x_max)) S_support_x_max<=S_comp_x_max;
                        if ((S_support_count==0)||(S_comp_y_min<S_support_y_min)) S_support_y_min<=S_comp_y_min;
                        if ((S_support_count==0)||(S_comp_y_max>S_support_y_max)) S_support_y_max<=S_comp_y_max;
                    end
                    S_state<=S_union_eval ? FINISH : SCAN_ADV;
                end
                FINISH: begin
                    if (!S_best_valid && !S_union_eval && (S_support_count>=MIN_AREA)) begin
                        // Reuse the same width/height/product path once after
                        // scanning. The union must pass the original area,
                        // density and maximum-size rules; this is not a lower
                        // motion threshold for a single small component.
                        S_union_eval<=1;
                        S_comp_count<=S_support_count;
                        S_comp_x_min<=S_support_x_min; S_comp_x_max<=S_support_x_max;
                        S_comp_y_min<=S_support_y_min; S_comp_y_max<=S_support_y_max;
                        S_state<=COMP_SIZE;
                    end else begin
                        O_ready<=1; O_valid<=S_best_valid;
                        O_count<=S_best_valid ? S_best_count : 16'd0;
                        O_x_min<=S_best_x_min; O_x_max<=S_best_x_max;
                        O_y_min<=S_best_y_min; O_y_max<=S_best_y_max;
                        S_state<=HOLD;
                    end
                end
                HOLD: begin end
                default: begin S_state<=HOLD; O_ready<=0; O_valid<=0; O_overrun<=1; end
            endcase
        end
    end
endmodule
