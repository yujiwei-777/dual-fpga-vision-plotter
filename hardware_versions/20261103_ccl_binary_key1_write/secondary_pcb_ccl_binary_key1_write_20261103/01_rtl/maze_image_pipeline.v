// Complete YUYV frame -> dark quadrilateral -> Q12 projective sampling ->
// symmetric 16x16 edge walls -> BFS -> atomic MZR1 payload. All at clk125.
// Capture contract: dark maze walls on a light sheet, one red start and one
// green goal; outer border at least four camera pixels thick. Ambiguous or
// missing markers/maps fail closed. Pixels are read only after frame CRC.
module maze_image_pipeline #(
    parameter integer TIMEOUT_CYCLES=125000000,
    parameter [7:0] WALL_Y=96,
    parameter integer EXTERNAL_READER=0
)(
    input wire clk,rst_n,start,cancel,input wire [31:0] job_id,config_version,
    input wire [10:0] roi_x0,roi_x1,input wire [9:0] roi_y0,roi_y1,
    output wire word_req,output wire [20:0] byte_addr,
    input wire word_ready,word_valid,input wire [127:0] word_data,
    output reg busy,done,output reg [1791:0] result,
    output reg [1:0] route_status,output reg [8:0] route_steps,
    output reg [7:0] route_start,route_goal,route_endpoint,
    output wire [511:0] route_directions,output reg [1023:0] route_walls,
    // Optional shared reader interface; appended for compatibility with
    // existing maze simulation benches.
    input wire ext_reader_ready,ext_reader_valid,
    input wire [23:0] ext_reader_rgb,
    input wire [7:0] ext_reader_luma,
    output wire ext_reader_request,ext_reader_invalidate,
    output wire [10:0] ext_pixel_x,
    output wire [9:0] ext_pixel_y
);
    localparam IDLE=0,SCAN_REQ=1,SCAN_WAIT=2,CORNERS=3,MAP_CONFIG=4,
        MAP_WAIT=5,PROBE_MAP=6,PROBE_WAIT=7,PIX_REQ=8,PIX_WAIT=9,
        CELL_END=10,SOLVE=11,SOLVE_WAIT=12,PACK=13,CRC_BODY=14,FINISH=15,NORMALIZE=16;
    reg [4:0] state;
    wire run_n=rst_n&&!cancel;
    reg pixel_req,invalidate;reg [10:0] sx;reg [9:0] sy;
    wire pixel_ready,pixel_valid;wire [23:0] rgb;wire [7:0] yy;
    generate if(EXTERNAL_READER) begin : g_external_reader
        assign pixel_ready=ext_reader_ready;
        assign pixel_valid=ext_reader_valid;
        assign rgb=ext_reader_rgb;
        assign yy=ext_reader_luma;
        assign word_req=1'b0;
        assign byte_addr=21'd0;
    end else begin : g_internal_reader
        vision_pixel_reader reader(.clk(clk),.rst_n(run_n),.invalidate(invalidate),.request(pixel_req),
            .pixel_x(sx),.pixel_y(sy),.ready(pixel_ready),.pixel_valid(pixel_valid),.pixel_rgb(rgb),.pixel_y8(yy),
            .word_req(word_req),.byte_addr(byte_addr),.word_ready(word_ready),.word_valid(word_valid),.word_data(word_data));
    end endgenerate
    assign ext_reader_request=EXTERNAL_READER ? pixel_req : 1'b0;
    assign ext_reader_invalidate=EXTERNAL_READER ? invalidate : 1'b0;
    assign ext_pixel_x=sx;
    assign ext_pixel_y=sy;
    wire [8:0] rr={1'b0,rgb[23:16]},gg={1'b0,rgb[15:8]},bb={1'b0,rgb[7:0]};
    wire red=(rr>=80&&rr>gg+9'd32&&rr>bb+9'd32);
    wire green=(gg>=80&&gg>rr+9'd32&&gg>bb+9'd32);
    wire blue=(bb>=80&&bb>rr+9'd32&&bb>gg+9'd32);
    wire wall=(yy<WALL_Y)&&!red&&!green&&!blue;
    reg [31:0] timer,saved_job,saved_version;
    reg [10:0] scan_x,left,right;reg [9:0] scan_y,top,bottom;
    reg [15:0] dark_count;reg [127:0] corners;
    reg [11:0] min_sum,max_sum;
    reg signed [12:0] min_diff,max_diff;
    wire [11:0] score_sum={1'b0,scan_x}+{2'd0,scan_y};
    wire signed [12:0] score_diff=$signed({2'd0,scan_x})-$signed({3'd0,scan_y});
    reg map_config,map_request;reg [6:0] map_u,map_v;
    wire map_ready,map_configured,map_valid,map_error;wire [10:0] map_x;wire [9:0] map_y;
    // Keep the validated projective mapping for trapezoidal camera views.
    maze_homography mapper(.clk(clk),.rst_n(run_n),.configure(map_config),.corners(corners),
        .request(map_request),.u(map_u),.v(map_v),.ready(map_ready),.configured(map_configured),
        .valid(map_valid),.error(map_error),.x(map_x),.y(map_y));
    reg [7:0] cell_at;reg [2:0] feature;reg [3:0] probe;
    reg [3:0] cell_walls,norm_walls;
    reg [2:0] norm_phase;
    // Cells arrive in increasing order. Shift a nibble at each completed
    // cell instead of decoding a write-enable across 1024 registers. After
    // 256 writes, cell zero is back in the low nibble. Normalization rotates
    // the same ring once more, with the current cell always in bits [3:0].
    // N/E/S/W are therefore fixed taps (offset -16/+1/+16/-1 modulo 256),
    // eliminating the 256-way neighbour mux without changing in-place ORs.
    reg [3:0] norm_neighbor_walls;
    always @* begin
        case(norm_phase)
            1:norm_neighbor_walls=route_walls[963:960];
            2:norm_neighbor_walls=route_walls[7:4];
            3:norm_neighbor_walls=route_walls[67:64];
            4:norm_neighbor_walls=route_walls[1023:1020];
            default:norm_neighbor_walls=route_walls[3:0];
        endcase
    end
    wire wall_store_we=(state==CELL_END)||(state==NORMALIZE&&norm_phase==5);
    wire [3:0] wall_store_data=(state==CELL_END)?cell_walls:norm_walls;
    always @(posedge clk or negedge run_n) begin
        if(!run_n)route_walls<=0;
        else if(state==IDLE&&start)route_walls<=0;
        else if(wall_store_we)route_walls<={wall_store_data,route_walls[1023:4]};
    end
    reg [3:0] red_hits,green_hits;reg [1:0] red_cells,green_cells;
    reg [6:0] border_hits;
    reg [15:0] error_code;
    reg [15:0] bx0,by0,bx1,by1;
    reg solve_start;wire solve_busy,solve_done;wire [1:0] solve_status;
    wire [8:0] solve_steps;wire [7:0] solve_endpoint;wire [511:0] solve_directions;
    // The solver holds the completed path until the next start/cancel.
    // route_status is the atomic publication gate. Consumers pipeline their
    // indexed reads; no second copy of the entire 512-bit path is needed.
    assign route_directions=(route_status!=0)?solve_directions:512'd0;
    maze_solver_16x16 solver(.clk(clk),.rst_n(run_n),.start(solve_start),.walls(route_walls),
        .markers_valid(red_cells==1&&green_cells==1&&border_hits>=56),
        .start_cell(route_start),.goal_cell(route_goal),.busy(solve_busy),.done(solve_done),
        .status(solve_status),.steps(solve_steps),.endpoint(solve_endpoint),.directions(solve_directions));
    // The route and direction registers are the authoritative result store.
    // Keep only the rolling CRC in flops; assembling the fixed MZR1 body at
    // the output removes a second 224-byte payload register bank.
    reg [7:0] crc_at;reg [31:0] crc,result_crc;
    function [31:0] crc_byte;input [31:0] value;input [7:0] data;reg [31:0] t;integer j;
        begin t=value^{24'd0,data};for(j=0;j<8;j=j+1)t=t[0]?(t>>1)^32'hedb88320:t>>1;crc_byte=t;end endfunction
    wire [1791:0] result_body={route_walls,route_directions,32'd0,by1,bx1,by0,bx0,error_code,7'd0,route_steps,
        route_endpoint,route_goal,route_start,6'd0,route_status,saved_version,saved_job,32'h31525a4d};
    always @* begin
        result=result_body;
        result[255:224]=result_crc;
    end
    wire [31:0] next_crc=crc_byte(crc,result_body[crc_at*8+:8]);
    wire [6:0] center_u={1'b0,cell_at[3:0],2'b10};
    wire [6:0] center_v={1'b0,cell_at[7:4],2'b10};
    // Three positions along an edge and three physical offsets across it.
    reg [1:0] along,across;
    always @*begin
        case(probe)0,3,6:along=0;1,4,7:along=1;default:along=2;endcase
        if(probe<3)across=0;else if(probe<6)across=1;else across=2;
    end
    always @(posedge clk or negedge run_n)begin
        if(!run_n)begin
            state<=IDLE;busy<=0;done<=0;result_crc<=0;route_status<=0;route_steps<=0;route_start<=0;route_goal<=0;route_endpoint<=0;
            pixel_req<=0;invalidate<=0;sx<=0;sy<=0;timer<=0;saved_job<=0;saved_version<=0;
            scan_x<=0;scan_y<=0;left<=0;right<=1280;top<=0;bottom<=720;dark_count<=0;corners<=0;min_sum<=4095;max_sum<=0;
            min_diff<=4095;max_diff<=-4096;map_config<=0;map_request<=0;map_u<=0;map_v<=0;cell_at<=0;feature<=0;probe<=0;
            cell_walls<=0;norm_walls<=0;norm_phase<=0;
            red_hits<=0;green_hits<=0;red_cells<=0;green_cells<=0;border_hits<=0;error_code<=0;bx0<=0;by0<=0;bx1<=0;by1<=0;
            solve_start<=0;crc_at<=0;crc<=32'hffffffff;
        end else begin
            done<=0;pixel_req<=0;invalidate<=0;map_config<=0;map_request<=0;solve_start<=0;
            if(busy)timer<=timer+1'b1;
            if(busy&&timer>=TIMEOUT_CYCLES-1&&(state<PACK||state==NORMALIZE))begin
                error_code<=3;route_status<=0;route_steps<=0;state<=PACK;
            end else case(state)
                IDLE:if(start)begin
                    busy<=1;timer<=0;saved_job<=job_id;saved_version<=config_version;invalidate<=1;
                    left<=roi_x0;right<=roi_x1;top<=roi_y0;bottom<=roi_y1;scan_x<=roi_x0;scan_y<=roi_y0;
                    dark_count<=0;corners<=0;min_sum<=4095;max_sum<=0;min_diff<=4095;max_diff<=-4096;
                    route_status<=0;route_steps<=0;route_start<=0;route_goal<=0;route_endpoint<=0;
                    cell_walls<=0;norm_walls<=0;norm_phase<=0;
                    red_cells<=0;green_cells<=0;border_hits<=0;error_code<=0;bx0<=0;by0<=0;bx1<=0;by1<=0;
                    if(roi_x1<=roi_x0||roi_y1<=roi_y0||roi_x1>1280||roi_y1>720)begin error_code<=1;state<=PACK;end
                    else state<=SCAN_REQ;
                end
                SCAN_REQ:if(pixel_ready)begin sx<=scan_x;sy<=scan_y;pixel_req<=1;state<=SCAN_WAIT;end
                SCAN_WAIT:if(pixel_valid)begin
                    if(wall)begin
                        if(dark_count!=65535)dark_count<=dark_count+1'b1;
                        if(score_sum<min_sum)begin min_sum<=score_sum;corners[31:0]<={6'd0,scan_y,5'd0,scan_x};end
                        if(score_diff>max_diff)begin max_diff<=score_diff;corners[63:32]<={6'd0,scan_y,5'd0,scan_x};end
                        if(score_sum>max_sum)begin max_sum<=score_sum;corners[95:64]<={6'd0,scan_y,5'd0,scan_x};end
                        if(score_diff<min_diff)begin min_diff<=score_diff;corners[127:96]<={6'd0,scan_y,5'd0,scan_x};end
                    end
                    if({1'b0,scan_x}+12'd4>=right)begin
                        scan_x<=left;
                        if({1'b0,scan_y}+11'd4>=bottom)state<=CORNERS;
                        else begin scan_y<=scan_y+10'd4;state<=SCAN_REQ;end
                    end else begin scan_x<=scan_x+11'd4;state<=SCAN_REQ;end
                end
                CORNERS:begin
                    bx0<=corners[15:0]<corners[111:96]?corners[15:0]:corners[111:96];
                    by0<=corners[31:16]<corners[63:48]?corners[31:16]:corners[63:48];
                    bx1<=(corners[47:32]>corners[79:64]?corners[47:32]:corners[79:64])+16'd1;
                    by1<=(corners[95:80]>corners[127:112]?corners[95:80]:corners[127:112])+16'd1;
                    if(dark_count<64||corners[47:32]<corners[15:0]+64||corners[79:64]<corners[111:96]+64||
                        corners[127:112]<corners[31:16]+64||corners[95:80]<corners[63:48]+64)begin error_code<=1;state<=PACK;end
                    else begin map_config<=1;state<=MAP_CONFIG;end
                end
                MAP_CONFIG:state<=MAP_WAIT;
                MAP_WAIT:if(map_ready)begin
                    if(map_error||!map_configured)begin error_code<=4;state<=PACK;end
                    else begin cell_at<=0;feature<=0;probe<=0;red_hits<=0;green_hits<=0;state<=PROBE_MAP;end
                end
                PROBE_MAP:if(map_ready)begin
                    if(feature==0)begin map_u<=center_u+along-7'd1;map_v<=center_v+across-7'd1;end
                    else if(feature==1||feature==3)begin map_u<=center_u+along-7'd1;map_v<=feature==1?center_v-7'd2:center_v+7'd2;end
                    else begin map_u<=feature==2?center_u+7'd2:center_u-7'd2;map_v<=center_v+along-7'd1;end
                    map_request<=1;state<=PROBE_WAIT;
                end
                PROBE_WAIT:if(map_valid)begin
                    if(map_error)begin error_code<=4;state<=PACK;end
                    else begin
                        sx<=map_x;sy<=map_y;
                        if(feature==1||feature==3)sy<=across==0?(map_y<3?10'd0:map_y-10'd3):across==2?(map_y>716?10'd719:map_y+10'd3):map_y;
                        if(feature==2||feature==4)sx<=across==0?(map_x<3?11'd0:map_x-11'd3):across==2?(map_x>1276?11'd1279:map_x+11'd3):map_x;
                        state<=PIX_REQ;
                    end
                end
                PIX_REQ:if(pixel_ready)begin pixel_req<=1;state<=PIX_WAIT;end
                PIX_WAIT:if(pixel_valid)begin
                    if(feature==0)begin if(red)red_hits<=red_hits+1'b1;if(green)green_hits<=green_hits+1'b1;end
                    else if(wall)cell_walls[feature-1'b1]<=1;
                    if(probe==8)begin
                        probe<=0;
                        if(feature==4)state<=CELL_END;
                        else begin feature<=feature+1'b1;state<=PROBE_MAP;end
                    end else begin probe<=probe+1'b1;state<=PROBE_MAP;end
                end
                CELL_END:begin
                    if(red_hits>=2)begin route_start<=cell_at;if(red_cells<3)red_cells<=red_cells+1'b1;end
                    if(green_hits>=2)begin route_goal<=cell_at;if(green_cells<3)green_cells<=green_cells+1'b1;end
                    border_hits<=border_hits+
                        ((cell_at[7:4]==0&&cell_walls[0])?7'd1:7'd0)+
                        ((cell_at[3:0]==15&&cell_walls[1])?7'd1:7'd0)+
                        ((cell_at[7:4]==15&&cell_walls[2])?7'd1:7'd0)+
                        ((cell_at[3:0]==0&&cell_walls[3])?7'd1:7'd0);
                    cell_walls<=0;
                    if(cell_at==255)begin cell_at<=0;norm_phase<=0;state<=NORMALIZE;end
                    else begin cell_at<=cell_at+1'b1;feature<=0;probe<=0;red_hits<=0;green_hits<=0;state<=PROBE_MAP;end
                end
                NORMALIZE:begin
                    case(norm_phase)
                        0:norm_walls<=norm_neighbor_walls;
                        1:norm_walls[0]<=cell_at[7:4]==0?1'b1:norm_walls[0]|norm_neighbor_walls[2];
                        2:norm_walls[1]<=cell_at[3:0]==15?1'b1:norm_walls[1]|norm_neighbor_walls[3];
                        3:norm_walls[2]<=cell_at[7:4]==15?1'b1:norm_walls[2]|norm_neighbor_walls[0];
                        4:norm_walls[3]<=cell_at[3:0]==0?1'b1:norm_walls[3]|norm_neighbor_walls[1];
                        default:begin
                            if(cell_at==255)state<=SOLVE;else cell_at<=cell_at+1'b1;
                        end
                    endcase
                    if(norm_phase==5)norm_phase<=0;else norm_phase<=norm_phase+1'b1;
                end
                SOLVE:begin
                    if(border_hits<56)begin error_code<=1;state<=PACK;end
                    else if(red_cells!=1||green_cells!=1||route_start==route_goal)begin error_code<=2;state<=PACK;end
                    else begin solve_start<=1;state<=SOLVE_WAIT;end
                end
                SOLVE_WAIT:if(solve_done)begin
                    route_status<=solve_status;route_steps<=solve_steps;route_endpoint<=solve_endpoint;state<=PACK;
                end
                PACK:begin
                    result_crc<=0;crc<=32'hffffffff;crc_at<=32;state<=CRC_BODY;
                end
                CRC_BODY:begin
                    crc<=next_crc;
                    if(crc_at==223)begin result_crc<=~next_crc;state<=FINISH;end
                    else crc_at<=crc_at+1'b1;
                end
                FINISH:begin busy<=0;done<=1;state<=IDLE;end
                default:begin busy<=0;state<=IDLE;end
            endcase
        end
    end
endmodule

