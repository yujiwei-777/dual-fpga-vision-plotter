`timescale 1ns/1ps
// Topology-preserving centre-line extraction and bounded route planning.
// All image, graph, point and descriptor storage has synchronous ERAM reads.
// No motion is released until thinning, all capacity checks and planning finish.
module doc_stroke_planner_baseline #(
    parameter integer MAX_EDGES=32768,MAX_PATHS=2048,MAX_POINTS=8192,
    parameter integer THIN_PAIRS=64,OPT_WINDOW=32,OPT_PASSES=2,
    parameter integer EXTERNAL_METRIC=0
)(
    input wire clk,input wire rst_n,input wire start,input wire cancel,
    input wire load_valid,input wire [16:0] load_addr,input wire load_bit,
    output wire load_ready,input wire emit_start,
    output reg busy,output reg prepared,output reg done,output reg error,
    output reg [7:0] error_code,
    output reg point_valid,output reg [8:0] point_x,point_y,
    output reg point_start,point_end,point_dot,input wire point_ready,
    output reg [15:0] edge_count,output reg [11:0] path_count,
    output reg [13:0] point_count,
    output reg [63:0] baseline_distance,planned_distance,
    output wire metric_start,output wire [8:0] metric_ax,metric_ay,metric_bx,metric_by,
    output wire metric_a_origin,input wire metric_busy,metric_done,
    input wire [31:0] metric_distance,input wire [32:0] metric_squared
);
    // The input stream is a 320x320 canvas, but only rows 70..249 contain
    // camera samples. Store that 320x180 active window at local rows 0..179.
    // 8 image +15 graph +8 point +4 descriptor =35 physical 20K ERAMs.
    // After extraction the graph is dead: route[i] occupies its words 8*i..8*i+7,
    // and nearest-neighbour used flags occupy words 16384..18431. No route RAM.
    localparam integer GRID_WIDTH=320, GRID_HEIGHT=180, GRID_Y_OFFSET=70;
    localparam [16:0] INPUT_ACTIVE_BASE=17'd22400;
    localparam [16:0] INPUT_ACTIVE_LIMIT=17'd80000;
    reg awe,bwe,gwe,pwe,dwe;
    reg [16:0] awa,bwa,gwa,ara,bra,gra;
    reg awd,bwd;reg [3:0] gwd;
    reg [12:0] pwa,pra;reg [19:0] pwd;
    reg [10:0] dwa,dra;reg [39:0] dwd;
    wire aq,bq;wire [3:0] gq;wire [19:0] pq;wire [39:0] dq;
    doc_stroke_bram #(1,14,4,17) image_a(clk,awe,awa,awd,ara,aq);
    doc_stroke_bram #(1,14,4,17) image_b(clk,bwe,bwa,bwd,bra,bq);
    doc_stroke_bram #(4,12,15,17) graph(clk,gwe,gwa,gwd,gra,gq);
    doc_stroke_bram #(20,10,8,13) points(clk,pwe,pwa,pwd,pra,pq);
    doc_stroke_bram #(40,9,4,11) descriptors(clk,dwe,dwa,dwd,dra,dq);

    localparam IDLE=0,MR0=1,MR1=2,MR2=3,
        NB0=10,NB1=11,NB2=12,TH0=20,TH1=21,TH2=22,GR0=25,GR1=26,
        AD0=30,AD1=31,AD2=32,AD3=33,AD4=34,AD5=35,
        FIND0=40,FIND1=41,FIND2=42,FIND3=43,FIND_NEXT=44,
        PATH0=50,PATH1=51,PATH2=52,PATH3=53,PATH4=54,PATH5=55,PATH_END=56,
        DOT0=57,APPEND=58,PATH_JUNCTION=59,
        RR0=60,RR1=61,RW0=62,RW1=63,
        EP0=70,EP1=71,EP2=72,DIST0=75,
        INIT_ROUTE=80,BASE_START=81,BASE_DONE=82,
        COST0=90,COST1=91,COST2=92,COST3=93,COST4=94,COST5=95,COST_END=96,
        NN0=100,NN1=101,NN2=102,NN3=103,NN4=104,NN5=105,NN6=106,
        NN7=107,NN8=108,NN9=109,NN10=110,NN11=111,NN12=112,
        O0=120,O1=121,O2=122,O3=123,O4=124,O5=125,O6=126,O7=127,
        O8=128,O9=129,O10=130,O11=131,O12=132,O13=133,O14=134,
        O15=135,O16=136,O17=137,O18=138,O19=139,O20=140,
        SEAM0=150,SEAM1=151,SEAM2=152,SEAM3=153,SEAM4=154,SEAM5=155,
        SEAM6=156,SEAM7=157,SEAM8=158,SEAM9=159,SEAM10=160,
        PLAN_DONE=170,WAIT_EMIT=171,EM0=180,EM1=181,EM2=182,EM3=183,
        EM4=184,EM5=185,EM6=186,EM_DONE=187;
    reg [8:0] state,mr_return,nb_return,adj_return,append_return;
    reg [8:0] rr_return,rw_return,ep_return,dist_return,cost_return;
    reg [2:0] mr_sel;
    reg [39:0] rd;
    reg [8:0] sx,sy;
    reg phase,pair_changed;
    reg [6:0] iteration;
    reg [3:0] ni,bc,tc;
    reg [8:0] nb;
    reg [8:0] nx,ny;
    reg nb_source;
    reg [8:0] adj_x,adj_y;
    reg [3:0] adj_c,adj_w,adj_nw,adj_n,adj_ne;
    reg [7:0] adj;
    reg find_pass;
    reg [8:0] cx,cy,first_x,first_y,last_x,last_y;
    reg [2:0] previous_dir,chosen_dir;
    reg [15:0] steps;
    reg [12:0] pool_start;
    reg [13:0] pool_count,path_len;
    reg closed_path;
    reg [8:0] append_x,append_y;
    reg [10:0] rr_index,rw_index;
    reg [2:0] rn;
    reg [31:0] route_word,route_write_word;
    reg [31:0] ep_route;
    reg ep_exit;
    reg [8:0] ep_x,ep_y;
    reg [39:0] ep_desc;
    reg dist_start;
    reg [8:0] dax,day,dbx,dby;
    reg da_origin;
    wire local_dist_done,local_dist_busy;wire [31:0] local_distance;wire [32:0] local_square;
    wire dist_done=EXTERNAL_METRIC ? metric_done : local_dist_done;
    wire dist_busy=EXTERNAL_METRIC ? metric_busy : local_dist_busy;
    wire [31:0] distance=EXTERNAL_METRIC ? metric_distance : local_distance;
    wire [32:0] square=EXTERNAL_METRIC ? metric_squared : local_square;
    reg [31:0] dist_result;
    reg [32:0] dist_square;
    assign metric_start=dist_start;
    assign metric_ax=dax;assign metric_ay=day;assign metric_bx=dbx;assign metric_by=dby;
    assign metric_a_origin=da_origin;
    generate if(!EXTERNAL_METRIC) begin : g_local_metric
        doc_path_distance metric_local(clk,rst_n,dist_start,cancel,dax,day,dbx,dby,
            da_origin,local_dist_busy,local_dist_done,local_distance,local_square);
    end endgenerate

    reg cost_baseline;
    reg [11:0] cost_index;
    reg [31:0] cost_route;
    reg [8:0] cost_x,cost_y;
    reg cost_origin;
    // Machine-coordinate distances are below 46,000 units; 2,048 paths keep
    // the full route cost below 2^27, so 32-bit internal accumulators suffice.
    reg [31:0] cost_sum,cost_result;
    reg [11:0] init_index,nn_pos,nn_cand;
    reg [8:0] current_x,current_y;
    reg current_origin;
    reg [32:0] best_square;
    reg [10:0] best_id;
    reg best_reverse;
    reg [39:0] nn_desc;
    reg [8:0] nn_first_x,nn_first_y;
    reg [31:0] selected_route;
    reg [11:0] oi,oj,ol,orr;
    reg [2:0] opt_pass;
    reg [8:0] opx,opy,oax,oay,obx,oby,onx,ony;
    reg op_origin,has_next;
    reg [31:0] old_cost,new_cost;
    reg [31:0] swap_left,swap_right;
    reg [11:0] seam_path;
    reg [31:0] seam_route;
    reg [39:0] seam_desc;
    reg [13:0] seam_n,seam_length;
    reg [12:0] best_seam;
    reg [31:0] seam_best,seam_partial;
    reg [8:0] seam_x,seam_y;
    reg use_baseline;
    reg [11:0] emit_path;
    reg [31:0] emit_route;
    reg [39:0] emit_desc;
    reg [13:0] emit_length,emit_k;
    reg [12:0] emit_offset;
    reg [8:0] emit_first_x,emit_first_y;

    function [16:0] addr;
        input [8:0] x,y;
        begin addr=({8'd0,y}<<8)+({8'd0,y}<<6)+x;end
    endfunction
    function signed [9:0] dx;
        input [2:0] d;
        begin case(d) 0,1,7:dx=1;4,3,5:dx=-1;default:dx=0;endcase end
    endfunction
    function signed [9:0] dy;
        input [2:0] d;
        begin case(d) 1,2,3:dy=1;5,6,7:dy=-1;default:dy=0;endcase end
    endfunction
    // Zhang-Suen neighbourhood is N,NE,E,SE,S,SW,W,NW,C.
    function signed [9:0] ndx;
        input [3:0] n;
        begin case(n) 1,2,3:ndx=1;5,6,7:ndx=-1;default:ndx=0;endcase end
    endfunction
    function signed [9:0] ndy;
        input [3:0] n;
        begin case(n) 0,1,7:ndy=-1;3,4,5:ndy=1;default:ndy=0;endcase end
    endfunction
    function [3:0] pop8;
        input [7:0] v;integer k;
        begin pop8=0;for(k=0;k<8;k=k+1)pop8=pop8+v[k];end
    endfunction
    function [3:0] transitions;
        input [7:0] v;integer k;
        begin transitions=0;for(k=0;k<8;k=k+1)
            transitions=transitions+(!v[k]&&v[(k+1)%8]);end
    endfunction
    function [2:0] straight_direction;
        input [7:0] a;input [2:0] prev;
        reg [2:0] d;reg found;integer k;integer off;
        begin d=0;found=0;for(k=0;k<8;k=k+1)begin
            case(k)0:off=0;1:off=1;2:off=7;3:off=2;
                4:off=6;5:off=3;6:off=5;default:off=4;endcase
            if(!found && a[(prev+off)%8])begin d=(prev+off)%8;found=1;end
        end straight_direction=d;end
    endfunction
    wire delete_pixel=nb[8] && bc>=2 && bc<=6 && tc==1 &&
        (!phase ? (!(nb[0]&nb[2]&nb[4]) && !(nb[2]&nb[4]&nb[6])):
                  (!(nb[0]&nb[2]&nb[6]) && !(nb[0]&nb[4]&nb[6])));
    wire [3:0] canonical={nb[5]&&!nb[4]&&!nb[6],
                          nb[3]&&!nb[2]&&!nb[4],nb[4],nb[2]};
    wire [7:0] original_adj={nb[1]&&!nb[0]&&!nb[2],nb[0],
        nb[7]&&!nb[0]&&!nb[6],nb[6],nb[5]&&!nb[4]&&!nb[6],
        nb[4],nb[3]&&!nb[2]&&!nb[4],nb[2]};
    wire [2:0] clockwise_dir=previous_dir+3'd1;
    wire [2:0] counterclockwise_dir=previous_dir-3'd1;
    wire gentle_turn=(chosen_dir==previous_dir)||(chosen_dir==clockwise_dir)||
                     (chosen_dir==counterclockwise_dir);
    wire signed [9:0] nb_x_calc=$signed({1'b0,nx})+ndx(ni);
    wire signed [9:0] nb_y_calc=$signed({1'b0,ny})+ndy(ni);
    wire [13:0] desc_len={1'b0,rd[25:13]}+14'd1;
    wire [8:0] append_y_external=append_y+GRID_Y_OFFSET;
    wire [13:0] ep_offset=rd[26]?{1'b0,ep_route[24:12]}:
        ((ep_route[11]^ep_exit)?desc_len-1'b1:14'd0);
    assign load_ready=(state==IDLE)&&!busy;

    task fail;
        input [7:0] code;
        begin state<=IDLE;busy<=0;prepared<=0;point_valid<=0;
            error<=1;error_code<=code;end
    endtask
    task read_mem;
        input [2:0] sel;input [16:0] a;input [8:0] resume;
        begin mr_sel<=sel;mr_return<=resume;state<=MR0;
            case(sel)0:ara<=a;1:bra<=a;2:gra<=a;3:pra<=a[12:0];4:dra<=a[10:0];endcase
        end
    endtask
    task neighbourhood;
        input [8:0] x,y;input source;input [8:0] resume;
        begin nx<=x;ny<=y;nb_source<=source;nb_return<=resume;
            nb<=0;ni<=0;state<=NB0;end
    endtask
    task adjacency;
        input [8:0] x,y;input [8:0] resume;
        begin adj_x<=x;adj_y<=y;adj_return<=resume;state<=AD0;end
    endtask
    task append_point;
        input [8:0] x,y;input [8:0] resume;
        begin append_x<=x;append_y<=y;append_return<=resume;state<=APPEND;end
    endtask
    task route_read;
        input [10:0] index;input [8:0] resume;
        begin rr_index<=index;rn<=0;route_word<=0;rr_return<=resume;state<=RR0;end
    endtask
    task route_write;
        input [10:0] index;input [31:0] value;input [8:0] resume;
        begin rw_index<=index;rn<=0;route_write_word<=value;rw_return<=resume;state<=RW0;end
    endtask
    task endpoint;
        input [31:0] value;input last;input [8:0] resume;
        begin ep_route<=value;ep_exit<=last;ep_return<=resume;state<=EP0;end
    endtask
    task measure;
        input [8:0] ax,ay,bx,by;input origin;input [8:0] resume;
        begin dax<=ax;day<=ay;dbx<=bx;dby<=by;da_origin<=origin;
            dist_start<=1;dist_return<=resume;state<=DIST0;end
    endtask
    task route_cost;
        input baseline;input [8:0] resume;
        begin cost_baseline<=baseline;cost_return<=resume;cost_index<=0;
            cost_sum<=0;cost_x<=0;cost_y<=0;cost_origin<=1;state<=COST0;end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=IDLE;busy<=0;prepared<=0;done<=0;error<=0;error_code<=0;
            point_valid<=0;point_x<=0;point_y<=0;point_start<=0;point_end<=0;point_dot<=0;
            edge_count<=0;path_count<=0;point_count<=0;baseline_distance<=0;planned_distance<=0;
            awe<=0;bwe<=0;gwe<=0;pwe<=0;dwe<=0;dist_start<=0;
            awa<=0;bwa<=0;gwa<=0;pwa<=0;dwa<=0;ara<=0;bra<=0;gra<=0;pra<=0;dra<=0;
            awd<=0;bwd<=0;gwd<=0;pwd<=0;dwd<=0;rd<=0;
            mr_sel<=0;mr_return<=0;nb_return<=0;adj_return<=0;append_return<=0;
            rr_return<=0;rw_return<=0;ep_return<=0;dist_return<=0;cost_return<=0;
            sx<=0;sy<=0;phase<=0;pair_changed<=0;iteration<=0;ni<=0;bc<=0;tc<=0;nb<=0;
            nx<=0;ny<=0;nb_source<=0;adj_x<=0;adj_y<=0;adj_c<=0;adj_w<=0;
            adj_nw<=0;adj_n<=0;adj_ne<=0;adj<=0;find_pass<=0;
            cx<=0;cy<=0;first_x<=0;first_y<=0;last_x<=0;last_y<=0;
            previous_dir<=0;chosen_dir<=0;steps<=0;pool_start<=0;pool_count<=0;path_len<=0;
            closed_path<=0;append_x<=0;append_y<=0;rr_index<=0;rw_index<=0;rn<=0;
            route_word<=0;route_write_word<=0;ep_route<=0;ep_exit<=0;ep_x<=0;ep_y<=0;ep_desc<=0;
            dax<=0;day<=0;dbx<=0;dby<=0;da_origin<=0;dist_result<=0;dist_square<=0;
            cost_baseline<=0;cost_index<=0;cost_route<=0;cost_x<=0;cost_y<=0;cost_origin<=0;
            cost_sum<=0;cost_result<=0;init_index<=0;nn_pos<=0;nn_cand<=0;
            current_x<=0;current_y<=0;current_origin<=0;best_square<=0;best_id<=0;
            best_reverse<=0;nn_desc<=0;nn_first_x<=0;nn_first_y<=0;selected_route<=0;
            oi<=0;oj<=0;ol<=0;orr<=0;opt_pass<=0;opx<=0;opy<=0;oax<=0;oay<=0;
            obx<=0;oby<=0;onx<=0;ony<=0;op_origin<=0;has_next<=0;old_cost<=0;new_cost<=0;
            swap_left<=0;swap_right<=0;seam_path<=0;seam_route<=0;seam_desc<=0;
            seam_n<=0;seam_length<=0;best_seam<=0;seam_best<=0;seam_partial<=0;
            seam_x<=0;seam_y<=0;use_baseline<=0;emit_path<=0;emit_route<=0;emit_desc<=0;
            emit_length<=0;emit_k<=0;emit_offset<=0;emit_first_x<=0;emit_first_y<=0;
        end else begin
            done<=0;error<=0;dist_start<=0;
            awe<=0;bwe<=0;gwe<=0;pwe<=0;dwe<=0;
            if(cancel)begin state<=IDLE;busy<=0;prepared<=0;point_valid<=0;end
            else case(state)
                IDLE:begin
                    if(load_valid&&load_ready&&load_addr>=INPUT_ACTIVE_BASE&&
                       load_addr<INPUT_ACTIVE_LIMIT)begin
                        awe<=1;awa<=load_addr-INPUT_ACTIVE_BASE;awd<=load_bit;
                    end
                    if(start)begin
                        busy<=1;prepared<=0;point_valid<=0;error_code<=0;
                        edge_count<=0;path_count<=0;point_count<=0;pool_count<=0;
                        baseline_distance<=0;planned_distance<=0;use_baseline<=0;
                        sx<=0;sy<=0;phase<=0;pair_changed<=0;iteration<=0;
                        neighbourhood(0,0,0,TH0);
                    end
                end
                MR0:state<=MR1;
                MR1:state<=MR2;
                MR2:begin
                    case(mr_sel)0:rd<={39'd0,aq};1:rd<={39'd0,bq};
                        2:rd<={36'd0,gq};3:rd<={20'd0,pq};4:rd<=dq;default:rd<=0;endcase
                    state<=mr_return;
                end
                NB0:begin
                    if(nb_x_calc<0||nb_x_calc>=GRID_WIDTH||
                       nb_y_calc<0||nb_y_calc>=GRID_HEIGHT)begin
                        nb[ni]<=0;state<=NB2;
                    end else read_mem(nb_source?1:0,addr(nb_x_calc[8:0],nb_y_calc[8:0]),NB1);
                end
                NB1:begin nb[ni]<=rd[0];state<=NB2;end
                NB2:if(ni==8)state<=nb_return;else begin ni<=ni+1'b1;state<=NB0;end
                TH0:begin bc<=pop8(nb[7:0]);tc<=transitions(nb[7:0]);state<=TH1;end
                TH1:begin
                    if(!phase)begin bwe<=1;bwa<=addr(sx,sy);bwd<=nb[8]&&!delete_pixel;end
                    else begin awe<=1;awa<=addr(sx,sy);awd<=nb[8]&&!delete_pixel;end
                    if(delete_pixel)pair_changed<=1;
                    state<=TH2;
                end
                TH2:begin
                    if(sx==GRID_WIDTH-1&&sy==GRID_HEIGHT-1)begin
                        sx<=0;sy<=0;
                        if(!phase)begin phase<=1;neighbourhood(0,0,1,TH0);end
                        else if(!pair_changed)begin
                            edge_count<=0;neighbourhood(0,0,0,GR0);
                        end else if(iteration+1>=THIN_PAIRS)fail(8'h01);
                        else begin iteration<=iteration+1'b1;phase<=0;pair_changed<=0;
                            neighbourhood(0,0,0,TH0);end
                    end else if(sx==GRID_WIDTH-1)begin sx<=0;sy<=sy+1'b1;neighbourhood(0,sy+1'b1,phase,TH0);end
                    else begin sx<=sx+1'b1;neighbourhood(sx+1'b1,sy,phase,TH0);end
                end
                GR0:begin
                    if({1'b0,edge_count}+(nb[8]?pop8({4'd0,canonical}):4'd0)>MAX_EDGES)fail(8'h02);
                    else begin
                        gwe<=1;gwa<=addr(sx,sy);gwd<=nb[8]?canonical:4'd0;
                        edge_count<=edge_count+(nb[8]?pop8({4'd0,canonical}):4'd0);
                        bwe<=1;bwa<=addr(sx,sy);bwd<=nb[8]&&(original_adj==0);
                        state<=GR1;
                    end
                end
                GR1:begin
                    if(sx==GRID_WIDTH-1&&sy==GRID_HEIGHT-1)begin sx<=0;sy<=0;find_pass<=0;state<=FIND0;end
                    else if(sx==GRID_WIDTH-1)begin sx<=0;sy<=sy+1'b1;neighbourhood(0,sy+1'b1,0,GR0);end
                    else begin sx<=sx+1'b1;neighbourhood(sx+1'b1,sy,0,GR0);end
                end
                AD0:begin adj_w<=0;adj_nw<=0;adj_n<=0;adj_ne<=0;
                    read_mem(2,addr(adj_x,adj_y),AD1);end
                AD1:begin adj_c<=rd[3:0];
                    if(adj_x!=0)read_mem(2,addr(adj_x-1'b1,adj_y),AD2);else state<=AD2;end
                AD2:begin if(adj_x!=0)adj_w<=rd[3:0];
                    if(adj_x!=0&&adj_y!=0)read_mem(2,addr(adj_x-1'b1,adj_y-1'b1),AD3);else state<=AD3;end
                AD3:begin if(adj_x!=0&&adj_y!=0)adj_nw<=rd[3:0];
                    if(adj_y!=0)read_mem(2,addr(adj_x,adj_y-1'b1),AD4);else state<=AD4;end
                AD4:begin if(adj_y!=0)adj_n<=rd[3:0];
                    if(adj_x!=GRID_WIDTH-1&&adj_y!=0)read_mem(2,addr(adj_x+1'b1,adj_y-1'b1),AD5);else state<=AD5;end
                AD5:begin
                    if(adj_x!=GRID_WIDTH-1&&adj_y!=0)adj_ne<=rd[3:0];
                    adj<={(adj_x!=GRID_WIDTH-1&&adj_y!=0)?rd[3]:1'b0,
                        adj_n[1],adj_nw[2],adj_w[0],adj_c[3],adj_c[1],adj_c[2],adj_c[0]};
                    state<=adj_return;
                end
                FIND0:adjacency(sx,sy,FIND1);
                FIND1:begin
                    // Pass one starts only at original degree-one endpoints.
                    // image_a remains the immutable skeleton throughout graph
                    // extraction; the graph holds only the unconsumed edges.
                    if(adj!=0)begin
                        if(find_pass)state<=PATH0;
                        else neighbourhood(sx,sy,0,FIND3);
                    end
                    else if(adj==0)read_mem(1,addr(sx,sy),FIND2);
                    else state<=FIND_NEXT;
                end
                FIND2:if(rd[0])state<=DOT0;else state<=FIND_NEXT;
                FIND3:if(pop8(original_adj)==1)state<=PATH0;else state<=FIND_NEXT;
                FIND_NEXT:begin
                    if(sx==GRID_WIDTH-1&&sy==GRID_HEIGHT-1)begin
                        sx<=0;sy<=0;
                        if(!find_pass)begin find_pass<=1;state<=FIND0;end
                        else begin init_index<=0;state<=INIT_ROUTE;end
                    end else begin
                        if(sx==GRID_WIDTH-1)begin sx<=0;sy<=sy+1'b1;end else sx<=sx+1'b1;
                        state<=FIND0;
                    end
                end
                DOT0:begin
                    if(path_count>=MAX_PATHS)fail(8'h03);
                    else begin pool_start<=pool_count[12:0];path_len<=0;closed_path<=0;
                        bwe<=1;bwa<=addr(sx,sy);bwd<=0;
                        append_point(sx,sy,PATH_END);end
                end
                PATH0:begin
                    if(path_count>=MAX_PATHS)fail(8'h03);
                    else begin
                        cx<=sx;cy<=sy;first_x<=sx;first_y<=sy;pool_start<=pool_count[12:0];
                        path_len<=0;steps<=0;previous_dir<=0;closed_path<=0;
                        append_point(sx,sy,PATH1);
                    end
                end
                PATH1:adjacency(cx,cy,PATH2);
                PATH2:begin
                    if(adj==0)begin
                        if(cx!=last_x||cy!=last_y)append_point(cx,cy,PATH_END);
                        else state<=PATH_END;
                    end else begin
                        chosen_dir<=straight_direction(adj,previous_dir);
                        if(steps==0)state<=PATH3;
                        else neighbourhood(cx,cy,0,PATH_JUNCTION);
                    end
                end
                PATH_JUNCTION:begin
                    // Only original junctions restrict a continuing stroke.
                    // Keep straight / +/-45 degrees; leave a sharper branch
                    // unconsumed for a later path. Degree-two corners retain
                    // the original rule, including 90-degree box/pen corners.
                    if(pop8(original_adj)>=3&&!gentle_turn)begin
                        if(cx!=last_x||cy!=last_y)append_point(cx,cy,PATH_END);
                        else state<=PATH_END;
                    end else state<=PATH3;
                end
                PATH3:begin
                    if(steps!=0&&chosen_dir!=previous_dir)append_point(cx,cy,PATH4);
                    else state<=PATH4;
                end
                PATH4:begin
                    gwe<=1;
                    case(chosen_dir)
                        0:begin gwa<=addr(cx,cy);gwd<=adj_c&4'b1110;end
                        1:begin gwa<=addr(cx,cy);gwd<=adj_c&4'b1011;end
                        2:begin gwa<=addr(cx,cy);gwd<=adj_c&4'b1101;end
                        3:begin gwa<=addr(cx,cy);gwd<=adj_c&4'b0111;end
                        4:begin gwa<=addr(cx-1'b1,cy);gwd<=adj_w&4'b1110;end
                        5:begin gwa<=addr(cx-1'b1,cy-1'b1);gwd<=adj_nw&4'b1011;end
                        6:begin gwa<=addr(cx,cy-1'b1);gwd<=adj_n&4'b1101;end
                        7:begin gwa<=addr(cx+1'b1,cy-1'b1);gwd<=adj_ne&4'b0111;end
                    endcase
                    cx<=$signed({1'b0,cx})+dx(chosen_dir);
                    cy<=$signed({1'b0,cy})+dy(chosen_dir);
                    previous_dir<=chosen_dir;steps<=steps+1'b1;state<=PATH5;
                end
                PATH5:if(cx==first_x&&cy==first_y)begin closed_path<=1;state<=PATH_END;end
                    else state<=PATH1;
                APPEND:begin
                    if(pool_count>=MAX_POINTS||point_count>=MAX_POINTS)fail(8'h04);
                    else begin pwe<=1;pwa<=pool_count[12:0];pwd<={2'd0,append_y_external,append_x};
                        pool_count<=pool_count+1'b1;point_count<=point_count+1'b1;
                        path_len<=path_len+1'b1;last_x<=append_x;last_y<=append_y;
                        state<=append_return;end
                end
                PATH_END:begin
                    if(closed_path&&point_count>=MAX_POINTS)fail(8'h04);
                    else begin
                        dwe<=1;dwa<=path_count[10:0];
                        dwd<={13'd0,closed_path,(path_len[12:0]-13'd1),pool_start};
                        if(closed_path)point_count<=point_count+1'b1;
                        path_count<=path_count+1'b1;state<=FIND0;
                    end
                end
                // A route word uses eight graph nibbles, only after graph traversal.
                RR0:read_mem(2,({6'd0,rr_index}<<3)+rn,RR1);
                RR1:begin
                    route_word[rn*4+:4]<=rd[3:0];
                    if(rn==7)state<=rr_return;else begin rn<=rn+1'b1;state<=RR0;end
                end
                RW0:begin gwe<=1;gwa<=({6'd0,rw_index}<<3)+rn;
                    gwd<=route_write_word[rn*4+:4];state<=RW1;end
                RW1:if(rn==7)state<=rw_return;else begin rn<=rn+1'b1;state<=RW0;end
                EP0:read_mem(4,{6'd0,ep_route[10:0]},EP1);
                EP1:begin ep_desc<=rd;
                    read_mem(3,{4'd0,rd[12:0]}+ep_offset,EP2);end
                EP2:begin ep_x<=rd[8:0];ep_y<=rd[17:9];state<=ep_return;end
                DIST0:if(dist_done)begin dist_result<=distance;dist_square<=square;state<=dist_return;end
                INIT_ROUTE:begin
                    if(init_index>=path_count)state<=BASE_START;
                    else begin gwe<=1;gwa<=17'd16384+init_index;gwd<=0;init_index<=init_index+1'b1;end
                end
                BASE_START:route_cost(1,BASE_DONE);
                BASE_DONE:begin baseline_distance<={32'd0,cost_result};
                    nn_pos<=0;current_x<=0;current_y<=0;current_origin<=1;state<=NN0;end
                COST0:begin
                    if(cost_index>=path_count)begin cost_result<=cost_sum;state<=cost_return;end
                    else if(cost_baseline)begin cost_route<={21'd0,cost_index[10:0]};state<=COST2;end
                    else route_read(cost_index[10:0],COST1);
                end
                COST1:begin cost_route<=route_word;state<=COST2;end
                COST2:endpoint(cost_route,0,COST3);
                COST3:measure(cost_x,cost_y,ep_x,ep_y,cost_origin,COST4);
                COST4:begin cost_sum<=cost_sum+dist_result;endpoint(cost_route,1,COST5);end
                COST5:begin cost_x<=ep_x;cost_y<=ep_y;cost_origin<=0;
                    cost_index<=cost_index+1'b1;state<=COST0;end
                NN0:begin
                    if(nn_pos>=path_count)begin oi<=0;oj<=1;opt_pass<=0;state<=O0;end
                    else begin nn_cand<=0;best_square<=33'h1ffffffff;best_id<=0;best_reverse<=0;state<=NN1;end
                end
                NN1:begin
                    if(nn_cand>=path_count)begin
                        selected_route<={20'd0,best_reverse,best_id};state<=NN9;
                    end else read_mem(2,17'd16384+nn_cand,NN2);
                end
                NN2:if(rd[0])begin nn_cand<=nn_cand+1'b1;state<=NN1;end
                    else read_mem(4,{6'd0,nn_cand[10:0]},NN3);
                NN3:begin nn_desc<=rd;read_mem(3,{4'd0,rd[12:0]},NN4);end
                NN4:begin nn_first_x<=rd[8:0];nn_first_y<=rd[17:9];
                    measure(current_x,current_y,rd[8:0],rd[17:9],current_origin,NN5);end
                NN5:begin
                    if(dist_square<best_square)begin best_square<=dist_square;best_id<=nn_cand[10:0];best_reverse<=0;end
                    if(!nn_desc[26]&&nn_desc[25:13]!=0)
                        read_mem(3,{4'd0,nn_desc[12:0]}+nn_desc[25:13],NN6);
                    else begin nn_cand<=nn_cand+1'b1;state<=NN1;end
                end
                NN6:measure(current_x,current_y,rd[8:0],rd[17:9],current_origin,NN7);
                NN7:begin
                    if(dist_square<best_square)begin best_square<=dist_square;best_id<=nn_cand[10:0];best_reverse<=1;end
                    nn_cand<=nn_cand+1'b1;state<=NN1;
                end
                NN9:route_write(nn_pos[10:0],selected_route,NN10);
                NN10:begin gwe<=1;gwa<=17'd16384+selected_route[10:0];gwd<=1;
                    endpoint(selected_route,1,NN11);end
                NN11:begin current_x<=ep_x;current_y<=ep_y;current_origin<=0;
                    nn_pos<=nn_pos+1'b1;state<=NN0;end
                // Bounded two-opt: reverse route order AND each stroke direction.
                O0:begin
                    if(path_count<2||opt_pass>=OPT_PASSES)begin seam_path<=0;state<=SEAM0;end
                    else if(oi+1>=path_count)begin oi<=0;oj<=1;opt_pass<=opt_pass+1'b1;end
                    else if(oj>=path_count||oj>oi+OPT_WINDOW)begin oi<=oi+1'b1;oj<=oi+2;end
                    else begin has_next<=oj+1<path_count;
                        if(oi==0)begin opx<=0;opy<=0;op_origin<=1;state<=O3;end
                        else route_read(oi[10:0]-1'b1,O1);
                    end
                end
                O1:endpoint(route_word,1,O2);
                O2:begin opx<=ep_x;opy<=ep_y;op_origin<=0;state<=O3;end
                O3:route_read(oi[10:0],O4);
                O4:endpoint(route_word,0,O5);
                O5:begin oax<=ep_x;oay<=ep_y;route_read(oj[10:0],O6);end
                O6:endpoint(route_word,1,O7);
                O7:begin obx<=ep_x;oby<=ep_y;
                    if(has_next)route_read(oj[10:0]+1'b1,O8);else state<=O10;end
                O8:endpoint(route_word,0,O9);
                O9:begin onx<=ep_x;ony<=ep_y;state<=O10;end
                O10:measure(opx,opy,oax,oay,op_origin,O11);
                O11:begin old_cost<=dist_result;
                    if(has_next)measure(obx,oby,onx,ony,0,O12);else state<=O13;end
                O12:begin old_cost<=old_cost+dist_result;state<=O13;end
                O13:measure(opx,opy,obx,oby,op_origin,O14);
                O14:begin new_cost<=dist_result;
                    if(has_next)measure(oax,oay,onx,ony,0,O15);else state<=O16;end
                O15:begin new_cost<=new_cost+dist_result;state<=O16;end
                O16:begin
                    if(old_cost>=new_cost+32'd10)begin ol<=oi;orr<=oj;state<=O17;end
                    else begin oj<=oj+1'b1;state<=O0;end
                end
                O17:if(ol>orr)begin oj<=oj+1'b1;state<=O0;end
                    else route_read(ol[10:0],O18);
                O18:begin swap_left<=route_word;
                    if(ol==orr)route_write(ol[10:0],route_word^32'h800,O20);
                    else route_read(orr[10:0],O19);end
                O19:begin swap_right<=route_word;route_write(ol[10:0],route_word^32'h800,O20);end
                O20:begin
                    if(ol==orr)begin oj<=oj+1'b1;state<=O0;end
                    else begin route_write(orr[10:0],swap_left^32'h800,O17);
                        ol<=ol+1'b1;orr<=orr-1'b1;end
                end
                // Choose a closed-loop seam among existing stored vertices.
                SEAM0:if(seam_path>=path_count)route_cost(0,PLAN_DONE);
                    else route_read(seam_path[10:0],SEAM1);
                SEAM1:begin seam_route<=route_word;read_mem(4,{6'd0,route_word[10:0]},SEAM2);end
                SEAM2:begin
                    seam_desc<=rd;seam_length<={1'b0,rd[25:13]}+1'b1;
                    if(!rd[26])begin seam_path<=seam_path+1'b1;state<=SEAM0;end
                    else begin seam_n<=0;best_seam<=seam_route[24:12];seam_best<=32'hffffffff;
                        has_next<=seam_path+1<path_count;
                        if(seam_path==0)begin opx<=0;opy<=0;op_origin<=1;state<=SEAM5;end
                        else route_read(seam_path[10:0]-1'b1,SEAM3);end
                end
                SEAM3:endpoint(route_word,1,SEAM4);
                SEAM4:begin opx<=ep_x;opy<=ep_y;op_origin<=0;state<=SEAM5;end
                SEAM5:if(has_next)route_read(seam_path[10:0]+1'b1,SEAM6);else state<=SEAM8;
                SEAM6:endpoint(route_word,0,SEAM7);
                SEAM7:begin onx<=ep_x;ony<=ep_y;state<=SEAM8;end
                SEAM8:begin
                    if(seam_n>=seam_length)begin
                        route_write(seam_path[10:0],{seam_route[31:25],best_seam,seam_route[11:0]},SEAM0);
                        seam_path<=seam_path+1'b1;
                    end else read_mem(3,{4'd0,seam_desc[12:0]}+seam_n,SEAM9);
                end
                SEAM9:begin seam_x<=rd[8:0];seam_y<=rd[17:9];
                    measure(opx,opy,rd[8:0],rd[17:9],op_origin,SEAM10);end
                SEAM10:begin seam_partial<=dist_result;
                    if(has_next)measure(seam_x,seam_y,onx,ony,0,NN8);
                    else begin if(dist_result<seam_best)begin seam_best<=dist_result;best_seam<=seam_n[12:0];end
                        seam_n<=seam_n+1'b1;state<=SEAM8;end
                end
                NN8:begin
                    if(seam_partial+dist_result<seam_best)begin seam_best<=seam_partial+dist_result;best_seam<=seam_n[12:0];end
                    seam_n<=seam_n+1'b1;state<=SEAM8;
                end
                PLAN_DONE:begin
                    use_baseline<={32'd0,cost_result}>baseline_distance;
                    planned_distance<={32'd0,cost_result}>baseline_distance?
                        baseline_distance:{32'd0,cost_result};
                    prepared<=1;state<=WAIT_EMIT;
                end
                WAIT_EMIT:if(emit_start)begin emit_path<=0;point_valid<=0;state<=EM0;end
                EM0:begin
                    if(emit_path>=path_count)state<=EM_DONE;
                    else if(use_baseline)begin emit_route<={21'd0,emit_path[10:0]};state<=EM2;end
                    else route_read(emit_path[10:0],EM1);
                end
                EM1:begin emit_route<=route_word;state<=EM2;end
                EM2:read_mem(4,{6'd0,emit_route[10:0]},EM3);
                EM3:begin
                    emit_desc<=rd;emit_length<={1'b0,rd[25:13]}+1'b1;emit_k<=0;
                    emit_offset<=rd[26]?emit_route[24:12]:(emit_route[11]?rd[25:13]:13'd0);
                    state<=EM4;
                end
                EM4:read_mem(3,{4'd0,emit_desc[12:0]}+emit_offset,EM5);
                EM5:begin
                    point_x<=rd[8:0];point_y<=rd[17:9];point_valid<=1;
                    point_start<=emit_k==0;point_dot<=emit_length==1;
                    point_end<=emit_desc[26]?emit_k==emit_length:emit_k+1==emit_length;
                    if(emit_k==0)begin emit_first_x<=rd[8:0];emit_first_y<=rd[17:9];end
                    state<=EM6;
                end
                EM6:if(point_valid&&point_ready)begin
                    point_valid<=0;
                    if(point_end)begin emit_path<=emit_path+1'b1;state<=EM0;end
                    else begin
                        emit_k<=emit_k+1'b1;
                        if(emit_desc[26])begin
                            if(emit_route[11])emit_offset<=emit_offset==0?emit_length-1'b1:emit_offset-1'b1;
                            else emit_offset<=emit_offset+1>=emit_length?13'd0:emit_offset+1'b1;
                        end else if(emit_route[11])emit_offset<=emit_offset-1'b1;
                        else emit_offset<=emit_offset+1'b1;
                        state<=EM4;
                    end
                end
                EM_DONE:begin busy<=0;prepared<=0;done<=1;state<=IDLE;end
                default:fail(8'hff);
            endcase
        end
    end
endmodule
