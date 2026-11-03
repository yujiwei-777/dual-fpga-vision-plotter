// One-outstanding 16-byte-aligned YUYV reader with a one-word cache.
// word_req remains asserted until word_ready. The accepted response may arrive
// with word_ready or later on word_valid. Low word bytes are low DDR addresses.
module vision_pixel_reader(
    input wire clk,rst_n,invalidate,
    input wire request,
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    output wire ready,
    output reg pixel_valid,
    output reg [23:0] pixel_rgb,
    output reg [7:0] pixel_y8,
    output wire word_req,
    output reg [20:0] byte_addr,
    input wire word_ready,word_valid,
    input wire [127:0] word_data
);
    localparam IDLE=0,REQUEST=1,RESPONSE=2,DECODE=3,CONVERT=4,RGB_SUM=5,RGB_CLIP=6;
    reg [2:0] state;
    reg cache_valid;
    reg [16:0] cache_tag;
    reg [127:0] cache_data,selected_word;
    reg [3:0] offset;
    reg [7:0] yy,uu,vv;
    // 2560 bytes/line = 2048 + 512.  Spell the stride as shifts so the
    // address generator does not consume a DSP multiplier in each reader.
    wire [20:0] requested_address=({11'd0,pixel_y}<<11)+
                                  ({11'd0,pixel_y}<<9)+{9'd0,pixel_x,1'b0};
    assign ready=state==IDLE;
    assign word_req=state==REQUEST;
    wire signed [8:0] c=$signed({1'b0,yy})-9'sd16;
    wire signed [8:0] d=$signed({1'b0,uu})-9'sd128;
    wire signed [8:0] e=$signed({1'b0,vv})-9'sd128;
    reg signed [17:0] pc,pe409,pd100,pe208,pd516;
    reg signed [18:0] red_sum,green_sum,blue_sum;
    function [7:0] clip;
        input signed [18:0] value;
        begin if(value<0)clip=0;else if(value>19'sd65535)clip=255;else clip=value[15:8];end
    endfunction
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;cache_valid<=0;cache_tag<=0;cache_data<=0;selected_word<=0;offset<=0;
            yy<=0;uu<=0;vv<=0;pixel_valid<=0;pixel_rgb<=0;pixel_y8<=0;byte_addr<=0;
            pc<=0;pe409<=0;pd100<=0;pe208<=0;pd516<=0;red_sum<=0;green_sum<=0;blue_sum<=0;
        end else begin
            pixel_valid<=0;
            if(invalidate)cache_valid<=0;
            case(state)
                IDLE:if(request)begin
                    offset<=requested_address[3:0];byte_addr<={requested_address[20:4],4'b0};
                    if(cache_valid && !invalidate && cache_tag==requested_address[20:4])begin selected_word<=cache_data;state<=DECODE;end
                    else state<=REQUEST;
                end
                REQUEST:if(word_ready)begin
                    if(word_valid)begin
                        selected_word<=word_data;cache_data<=word_data;cache_tag<=byte_addr[20:4];cache_valid<=1;state<=DECODE;
                    end else state<=RESPONSE;
                end
                RESPONSE:if(word_valid)begin
                    selected_word<=word_data;cache_data<=word_data;cache_tag<=byte_addr[20:4];cache_valid<=1;state<=DECODE;
                end
                DECODE:begin
                    yy<=selected_word[offset*8+:8];
                    uu<=selected_word[({offset[3:2],2'b01})*8+:8];
                    vv<=selected_word[({offset[3:2],2'b11})*8+:8];state<=CONVERT;
                end
                CONVERT:begin
                    pc<=c*18'sd298;pe409<=e*18'sd409;pd100<=d*18'sd100;pe208<=e*18'sd208;pd516<=d*18'sd516;
                    state<=RGB_SUM;
                end
                RGB_SUM:begin
                    red_sum<=$signed({pc[17],pc})+$signed({pe409[17],pe409})+19'sd128;
                    green_sum<=$signed({pc[17],pc})-$signed({pd100[17],pd100})-$signed({pe208[17],pe208})+19'sd128;
                    blue_sum<=$signed({pc[17],pc})+$signed({pd516[17],pd516})+19'sd128;state<=RGB_CLIP;
                end
                RGB_CLIP:begin pixel_rgb<={clip(red_sum),clip(green_sum),clip(blue_sum)};pixel_y8<=yy;pixel_valid<=1;state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
