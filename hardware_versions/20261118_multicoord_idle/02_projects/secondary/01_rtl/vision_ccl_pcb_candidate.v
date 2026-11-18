// Streaming four-connected-component labelling with exact union/merged statistics.
// Pixels are accepted in raster order. Color 0 is background; 1..3 are distinct.
// A bounded 510-component-label table fails closed on overflow. No global color bounding box.
// Parent/statistic/line arrays all use synchronous read ports.
module vision_ccl_pcb_candidate #(
    // Disabled by default for other users. Ordinary CNN applies its existing
    // 8x8 eligibility before ranking, so narrow fragments cannot consume slots.
    parameter integer MIN_WIDTH=0,
    parameter integer MIN_HEIGHT=0
)(
    input wire clk,rst_n,start,
    input wire [8:0] width,
    input wire [7:0] height,
    input wire [15:0] min_area,
    input wire filter_shape,
    input wire pcb_mode,
    input wire pixel_valid,
    input wire [1:0] pixel_color,
    output wire pixel_ready,
    output reg busy,done,overflow,
    output reg [2:0] count,
    output reg [255:0] boxes,
    output reg [15:0] largest_area,
    output reg [1:0] largest_color,
    // Same ordering as boxes; used by the sequential multi-object CNN.
    output reg [63:0] areas,
    output reg truncated
);
    localparam IDLE=0,CLEAR=1,PIXEL=2,TOP=3,LR=4,LU=5,UR=6,UU=7,
        SELECT=8,AR=9,AU=10,BR=11,BU=12,COMMIT=13,SCAN_R=14,SCAN_U=15,FINISH=16,
        SCAN_MUL=17,SCAN_CHECK=18,SCAN_INSERT=19,STAT_WRITE=20;
    reg [4:0] state;
    reg [8:0] w,x,clear_x,next_label,left_label,up_label,left_root,up_root,root,other,resolve,scan_label;
    reg [7:0] h,y;
    reg [15:0] minimum;
    reg filtering,pcb_filter;
    reg [1:0] color,left_color,up_color;
    reg [8:0] parents[0:511];
    // [51:50] color, [49:34] area, [33:26] y1, [25:18] y0,
    // [17:9] x1 and [8:0] x0. Coordinates are exclusive on right/bottom.
    reg [51:0] stats[0:511];
    reg [10:0] line[0:319];
    reg [8:0] parent_q;
    reg [51:0] stat_q,stat_a,stat_wdata_q;
    reg [10:0] line_q;
    reg [8:0] stat_addr,parent_addr;
    reg [51:0] best[0:3];
    reg [51:0] candidate_stat;
    reg [9:0] candidate_w;
    reg [8:0] candidate_h;
    reg [18:0] candidate_box_area;
    reg [19:0] candidate_area_x12;
    reg candidate_root_ok,candidate_aspect_ok,candidate_ok;
    reg [3:0] candidate_rank;
    reg [2:0] accepted_components;
    integer k;
    assign pixel_ready=(state==PIXEL);
    always @* begin
        parent_addr=resolve;stat_addr=root;
        if(state==BR || state==BU)stat_addr=other;
        if(state==SCAN_R || state==SCAN_U)begin parent_addr=scan_label;stat_addr=scan_label;end
    end
    // TD needs an explicit single write address/data port. Multiple array
    // assignments, even in mutually exclusive FSM states, infer extra ports
    // and previously expanded the 512 x 52 statistic RAM into 25,600 FFs.
    wire allocate_label=state==SELECT && color!=0 && !overflow &&
                        left_root==0 && up_root==0 && next_label!=511;
    wire stat_we=allocate_label || (state==AU && other==0) || state==STAT_WRITE;
    wire [8:0] stat_waddr=allocate_label ? next_label : root;
    wire [51:0] stat_wdata=allocate_label ? add_pixel(0,0,x,y,color) :
                          state==AU ? add_pixel(stat_q,0,x,y,color) : stat_wdata_q;
    wire parent_we=allocate_label || state==BU;
    wire [8:0] parent_waddr=allocate_label ? next_label : other;
    wire [8:0] parent_wdata=allocate_label ? next_label : root;
    wire line_we=state==CLEAR || state==COMMIT;
    wire [8:0] line_waddr=state==CLEAR ? clear_x : x;
    wire [10:0] line_wdata=state==CLEAR ? 11'd0 : {color,root};
    always @(posedge clk) begin
        parent_q<=parents[parent_addr];stat_q<=stats[stat_addr];line_q<=line[x];
        if(rst_n && line_we)line[line_waddr]<=line_wdata;
        if(rst_n && parent_we)parents[parent_waddr]<=parent_wdata;
        if(rst_n && stat_we)stats[stat_waddr]<=stat_wdata;
    end
    function [51:0] add_pixel;
        input [51:0] a,b;
        input [8:0] xx;
        input [7:0] yy;
        input [1:0] cc;
        reg [8:0] bx0,bx1;
        reg [7:0] by0,by1;
        reg [15:0] n;
        begin
            bx0=xx;bx1=xx+1'b1;by0=yy;by1=yy+1'b1;
            if(a[49:34]!=0)begin
                if(a[8:0]<bx0)bx0=a[8:0];if(a[17:9]>bx1)bx1=a[17:9];
                if(a[25:18]<by0)by0=a[25:18];if(a[33:26]>by1)by1=a[33:26];
            end
            if(b[49:34]!=0)begin
                if(b[8:0]<bx0)bx0=b[8:0];if(b[17:9]>bx1)bx1=b[17:9];
                if(b[25:18]<by0)by0=b[25:18];if(b[33:26]>by1)by1=b[33:26];
            end
            n=a[49:34]+b[49:34]+1'b1;
            add_pixel={cc,n,by1,by0,bx1,bx0};
        end
    endfunction
    function [63:0] box64;
        input [51:0] st;
        begin box64={{8{1'b0}},st[33:26],{7{1'b0}},st[17:9],{8{1'b0}},st[25:18],{7{1'b0}},st[8:0]};end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=IDLE;busy<=0;done<=0;overflow<=0;count<=0;boxes<=0;largest_area<=0;largest_color<=0;areas<=0;truncated<=0;accepted_components<=0;
            w<=0;h<=0;x<=0;y<=0;clear_x<=0;next_label<=1;left_label<=0;up_label<=0;
            left_root<=0;up_root<=0;root<=0;other<=0;resolve<=0;scan_label<=0;
            minimum<=0;filtering<=0;pcb_filter<=0;color<=0;left_color<=0;up_color<=0;stat_a<=0;stat_wdata_q<=0;
            candidate_stat<=0;candidate_w<=0;candidate_h<=0;candidate_box_area<=0;
            candidate_area_x12<=0;candidate_root_ok<=0;candidate_aspect_ok<=0;candidate_ok<=0;candidate_rank<=0;
            for(k=0;k<4;k=k+1)best[k]<=0;
        end else begin
            done<=0;
            case(state)
                IDLE:if(start)begin
                    w<=width;h<=height;minimum<=min_area;filtering<=filter_shape;pcb_filter<=pcb_mode;
                    busy<=1;overflow<=0;count<=0;boxes<=0;largest_area<=0;largest_color<=0;areas<=0;truncated<=0;accepted_components<=0;
                    clear_x<=0;x<=0;y<=0;next_label<=1;left_label<=0;left_color<=0;
                    for(k=0;k<4;k=k+1)best[k]<=0;
                    if(width==0 || width>320 || height==0 || height>180)begin overflow<=1;state<=FINISH;end
                    else state<=CLEAR;
                end
                CLEAR:begin
                    if(clear_x==w-1'b1)state<=PIXEL;else clear_x<=clear_x+1'b1;
                end
                PIXEL:if(pixel_valid)begin color<=pixel_color;state<=TOP;end
                TOP:begin
                    up_color<=line_q[10:9];up_label<=line_q[8:0];
                    resolve<=(left_color==color && color!=0) ? left_label : 0;
                    state<=LR;
                end
                LR:state<=LU;
                LU:begin
                    if(resolve==0 || parent_q==resolve)begin
                        left_root<=resolve;resolve<=(up_color==color && color!=0) ? up_label : 0;state<=UR;
                    end else begin resolve<=parent_q;state<=LR;end
                end
                UR:state<=UU;
                UU:begin
                    if(resolve==0 || parent_q==resolve)begin up_root<=resolve;state<=SELECT;end
                    else begin resolve<=parent_q;state<=UR;end
                end
                SELECT:begin
                    other<=0;
                    if(color==0 || overflow)begin root<=0;state<=COMMIT;end
                    else if(left_root==0 && up_root==0)begin
                        // Label 511 is intentionally retained as the overflow sentinel.
                        if(next_label==511)begin overflow<=1;root<=0;state<=COMMIT;end
                        else begin
                            root<=next_label;
                            next_label<=next_label+1'b1;state<=COMMIT;
                        end
                    end else begin
                        if(left_root==0)root<=up_root;
                        else if(up_root==0 || left_root==up_root)root<=left_root;
                        else if(left_root<up_root)begin root<=left_root;other<=up_root;end
                        else begin root<=up_root;other<=left_root;end
                        state<=AR;
                    end
                end
                AR:state<=AU;
                AU:begin
                    if(other==0)state<=COMMIT;
                    else begin stat_a<=stat_q;state<=BR;end
                end
                BR:state<=BU;
                BU:begin stat_wdata_q<=add_pixel(stat_a,stat_q,x,y,color);state<=STAT_WRITE;end
                STAT_WRITE:state<=COMMIT;
                COMMIT:begin
                    left_label<=root;left_color<=color;
                    if(x==w-1'b1)begin
                        x<=0;left_label<=0;left_color<=0;
                        if(y==h-1'b1)begin scan_label<=1;state<=SCAN_R;end
                        else begin y<=y+1'b1;state<=PIXEL;end
                    end else begin x<=x+1'b1;state<=PIXEL;end
                end
                SCAN_R:state<=SCAN_U;
                SCAN_U:begin
                    // Break RAM read -> dimension subtraction -> area/filter ->
                    // rank -> wide best-array enable into registered stages.
                    candidate_stat<=stat_q;
                    candidate_w<={1'b0,stat_q[17:9]}-{1'b0,stat_q[8:0]};
                    candidate_h<={1'b0,stat_q[33:26]}-{1'b0,stat_q[25:18]};
                    candidate_root_ok<=!overflow && scan_label<next_label && parent_q==scan_label && stat_q[49:34]>=minimum;
                    state<=SCAN_MUL;
                end
                SCAN_MUL:begin
                    candidate_box_area<=candidate_w*candidate_h;
                    candidate_area_x12<={1'b0,candidate_stat[49:34],3'b000}+{2'b00,candidate_stat[49:34],2'b00};
                    // Keep only components whose bounding box is at most 3:1
                    // in either orientation.  The previous 4:1 check admitted
                    // long paper/edge fragments and did not match the fast160
                    // ROI contract used by the retrained dataset.
                    candidate_aspect_ok<=pcb_filter ?
                        (({2'b00,candidate_w} <= ({3'b000,candidate_h}+{candidate_h,2'b00})) &&
                         ({3'b000,candidate_h} <= ({2'b00,candidate_w}+{candidate_w,2'b00}))) :
                        (({2'b00,candidate_w} <= ({3'b000,candidate_h}+{2'b00,candidate_h,1'b0})) &&
                         ({3'b000,candidate_h} <= ({2'b00,candidate_w}+{1'b0,candidate_w,1'b0})));
                    state<=SCAN_CHECK;
                end
                SCAN_CHECK:begin
                    candidate_ok<=candidate_root_ok &&
                        candidate_w>=(pcb_filter ? 10'd8 : MIN_WIDTH) && candidate_h>=MIN_HEIGHT && (!filtering ||
                        (candidate_aspect_ok && candidate_area_x12>={1'b0,candidate_box_area}));
                    for(k=0;k<4;k=k+1)candidate_rank[k]<=candidate_stat[49:34]>best[k][49:34];
                    state<=SCAN_INSERT;
                end
                SCAN_INSERT:begin
                    if(candidate_ok)begin
                        if(accepted_components==4)truncated<=1;
                        else accepted_components<=accepted_components+1'b1;
                        if(candidate_rank[0])begin best[3]<=best[2];best[2]<=best[1];best[1]<=best[0];best[0]<=candidate_stat;end
                        else if(candidate_rank[1])begin best[3]<=best[2];best[2]<=best[1];best[1]<=candidate_stat;end
                        else if(candidate_rank[2])begin best[3]<=best[2];best[2]<=candidate_stat;end
                        else if(candidate_rank[3])best[3]<=candidate_stat;
                    end
                    if(scan_label>=next_label-1'b1)state<=FINISH;
                    else begin scan_label<=scan_label+1'b1;state<=SCAN_R;end
                end
                FINISH:begin
                    boxes<={box64(best[3]),box64(best[2]),box64(best[1]),box64(best[0])};
                    areas<={best[3][49:34],best[2][49:34],best[1][49:34],best[0][49:34]};
                    largest_area<=best[0][49:34];largest_color<=best[0][51:50];
                    count<={2'b0,(best[0][49:34]!=0)}+{2'b0,(best[1][49:34]!=0)}+{2'b0,(best[2][49:34]!=0)}+{2'b0,(best[3][49:34]!=0)};
                    busy<=0;done<=1;state<=IDLE;
                end
                default:begin state<=IDLE;busy<=0;end
            endcase
        end
    end
endmodule
