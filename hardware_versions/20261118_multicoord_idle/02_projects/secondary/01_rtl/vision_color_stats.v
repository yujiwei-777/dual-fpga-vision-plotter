// Native-resolution colour votes from the exclusive candidate box interior.
// DDR words contain little-address-first Y0,U,Y1,V bytes. Two 128-bit
// registers overlap reads with a one-pixel/cycle integer conversion pipeline;
// there is at most one accepted, unanswered DDR request. No frame storage.
// cancel discards all local work; the link owner retires any old DDR response
// before granting a new job this port. color_conf is the raw margin even for
// fewer than eight samples; the caller must gate valid_samples >= 8.
module vision_color_stats(
    input wire clk,rst_n,start,cancel,
    input wire [10:0] box_x0,box_x1,
    input wire [9:0] box_y0,box_y1,
    output reg busy,done,
    output reg [1:0] color_id,
    output reg [7:0] color_conf,
    output reg [19:0] valid_samples,count_r,count_g,count_b,
    output wire word_req,
    output reg [20:0] byte_addr,
    input wire word_ready,word_valid,
    input wire [127:0] word_data
);
    localparam [3:0] IDLE=0,MARGINS=1,INTERIOR=2,SETUP=3,SCAN=4,DRAIN=5,RANK=6,DIVIDE=7,FINISH=8;
    reg [3:0] state;
    reg [10:0] bx0,bx1,width,mx,ix0,ix1;
    reg [9:0] by0,by1,height,my,iy0,iy1;
    wire [11:0] xplus={1'b0,bx0}+{1'b0,mx};
    wire [10:0] yplus={1'b0,by0}+{1'b0,my};
    wire [10:0] inner_x0=(xplus>={1'b0,bx1}) ? bx1-11'd1 : xplus[10:0];
    wire [9:0] inner_y0=(yplus>={1'b0,by1}) ? by1-10'd1 : yplus[9:0];
    wire [10:0] inner_x1=(bx1-mx<=inner_x0) ? inner_x0+11'd1 : bx1-mx;
    wire [9:0] inner_y1=(by1-my<=inner_y0) ? inner_y0+10'd1 : by1-my;
    wire [10:0] last_inner_x=ix1-11'd1;
    wire [9:0] last_inner_y=iy1-10'd1;
    reg [7:0] first_word,last_word,fetch_word;
    reg [9:0] fetch_y;
    reg [20:0] row_first_addr;
    reg pending,fetch_done,write_slot,read_slot;
    reg [1:0] buffer_valid;
    reg [127:0] data0,data1;
    reg [10:0] base0,base1;
    reg last0,last1;
    reg [2:0] lane;
    wire [127:0] active_data=read_slot ? data1 : data0;
    wire [10:0] active_base=read_slot ? base1 : base0;
    wire active_last=read_slot ? last1 : last0;
    wire [10:0] active_x=active_base+{8'd0,lane};
    wire emit_pixel=state==SCAN && buffer_valid[read_slot];
    assign word_req=state==SCAN && !cancel && !pending && !fetch_done && !buffer_valid[write_slot];
    wire response=(pending && word_valid) || (word_req && word_ready && word_valid);
    wire final_fetch=fetch_word==last_word && fetch_y==last_inner_y;

    reg v0,v1,v2,v3,v4;
    reg end0,end1,end2,end3,end4;
    reg [7:0] yy,uu,vv,red,green,blue;
    reg signed [17:0] pc,pe409,pd100,pe208,pd516;
    reg signed [18:0] red_sum,green_sum,blue_sum;
    wire signed [17:0] c=$signed({10'd0,yy})-18'sd16;
    wire signed [17:0] d=$signed({10'd0,uu})-18'sd128;
    wire signed [17:0] e=$signed({10'd0,vv})-18'sd128;
    wire [7:0] hi=(red>=green && red>=blue) ? red : (green>=blue ? green : blue);
    wire [7:0] lo=(red<=green && red<=blue) ? red : (green<=blue ? green : blue);
    reg [1:0] vote;
    reg eligible;
    function [7:0] clip;
        input signed [18:0] value;
        begin
            if(value<0)clip=8'd0;
            else if(value>19'sd65535)clip=8'd255;
            else clip=value[15:8];
        end
    endfunction

    wire [1:0] winner=(count_r>=count_g && count_r>=count_b) ? 2'd0 : (count_g>=count_b ? 2'd1 : 2'd2);
    wire [19:0] best=(winner==0) ? count_r : (winner==1 ? count_g : count_b);
    wire [19:0] runner_up=(winner==0) ? (count_g>=count_b ? count_g : count_b) :
                                 (winner==1 ? (count_r>=count_b ? count_r : count_b) : (count_r>=count_g ? count_r : count_g));
    wire [19:0] delta=best-runner_up;
    reg [27:0] numerator;
    reg [20:0] remainder;
    reg [7:0] quotient;
    reg [4:0] divide_steps;
    wire [20:0] shifted_remainder={remainder[19:0],numerator[27]};
    wire subtract_divisor=shifted_remainder>={1'b0,valid_samples};

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;busy<=0;done<=0;color_id<=0;color_conf<=0;
            valid_samples<=0;count_r<=0;count_g<=0;count_b<=0;
            bx0<=0;bx1<=0;by0<=0;by1<=0;width<=0;height<=0;mx<=0;my<=0;ix0<=0;ix1<=0;iy0<=0;iy1<=0;
            first_word<=0;last_word<=0;fetch_word<=0;fetch_y<=0;row_first_addr<=0;byte_addr<=0;
            pending<=0;fetch_done<=0;write_slot<=0;read_slot<=0;buffer_valid<=0;
            data0<=0;data1<=0;base0<=0;base1<=0;last0<=0;last1<=0;lane<=0;
            v0<=0;v1<=0;v2<=0;v3<=0;v4<=0;end0<=0;end1<=0;end2<=0;end3<=0;end4<=0;
            yy<=0;uu<=0;vv<=0;red<=0;green<=0;blue<=0;vote<=0;eligible<=0;
            pc<=0;pe409<=0;pd100<=0;pe208<=0;pd516<=0;red_sum<=0;green_sum<=0;blue_sum<=0;
            numerator<=0;remainder<=0;quotient<=0;divide_steps<=0;
        end else begin
            done<=0;
            if(cancel) begin
                state<=IDLE;busy<=0;color_id<=0;color_conf<=0;
                valid_samples<=0;count_r<=0;count_g<=0;count_b<=0;
                pending<=0;fetch_done<=0;buffer_valid<=0;write_slot<=0;read_slot<=0;lane<=0;
                v0<=0;v1<=0;v2<=0;v3<=0;v4<=0;end0<=0;end1<=0;end2<=0;end3<=0;end4<=0;
                eligible<=0;numerator<=0;remainder<=0;quotient<=0;divide_steps<=0;
            end else begin
                // Every pipeline stage advances even when a read stalls.
                v0<=emit_pixel && active_x>=ix0 && active_x<ix1;
                end0<=emit_pixel && lane==7 && active_last;
                if(emit_pixel) begin
                    yy<=active_data[{lane,4'b0000}+:8];
                    uu<=active_data[{lane[2:1],5'b01000}+:8];
                    vv<=active_data[{lane[2:1],5'b11000}+:8];
                    if(lane==7) begin
                        buffer_valid[read_slot]<=0;read_slot<=!read_slot;lane<=0;
                        if(active_last)state<=DRAIN;
                    end else lane<=lane+1'b1;
                end
                v1<=v0;end1<=end0;
                // Explicit constant shifts/adds avoid consuming DSPs.
                pc<=(c<<<8)+(c<<<5)+(c<<<3)+(c<<<1);
                pe409<=(e<<<8)+(e<<<7)+(e<<<4)+(e<<<3)+e;
                pd100<=(d<<<6)+(d<<<5)+(d<<<2);
                pe208<=(e<<<7)+(e<<<6)+(e<<<4);
                pd516<=(d<<<9)+(d<<<2);
                v2<=v1;end2<=end1;
                red_sum<=$signed({pc[17],pc})+$signed({pe409[17],pe409})+19'sd128;
                green_sum<=$signed({pc[17],pc})-$signed({pd100[17],pd100})-$signed({pe208[17],pe208})+19'sd128;
                blue_sum<=$signed({pc[17],pc})+$signed({pd516[17],pd516})+19'sd128;
                v3<=v2;end3<=end2;red<=clip(red_sum);green<=clip(green_sum);blue<=clip(blue_sum);
                v4<=v3;end4<=end3;
                eligible<=hi>=8'd64 && hi<=8'd245 && hi-lo>=8'd24;
                vote<=(red>=green && red>=blue) ? 2'd0 : (green>=blue ? 2'd1 : 2'd2);
                if(v4 && eligible) begin
                    valid_samples<=valid_samples+1'b1;
                    case(vote)
                        0:count_r<=count_r+1'b1;
                        1:count_g<=count_g+1'b1;
                        default:count_b<=count_b+1'b1;
                    endcase
                end
                if(end4)state<=RANK;

                if(word_req && word_ready && !word_valid)pending<=1;
                if(response) begin
                    pending<=0;buffer_valid[write_slot]<=1;write_slot<=!write_slot;
                    if(write_slot)begin data1<=word_data;base1<={fetch_word,3'b0};last1<=final_fetch;end
                    else begin data0<=word_data;base0<={fetch_word,3'b0};last0<=final_fetch;end
                    if(final_fetch)fetch_done<=1;
                    else if(fetch_word==last_word)begin
                        fetch_word<=first_word;fetch_y<=fetch_y+1'b1;
                        row_first_addr<=row_first_addr+21'd2560;byte_addr<=row_first_addr+21'd2560;
                    end else begin fetch_word<=fetch_word+1'b1;byte_addr<=byte_addr+21'd16;end
                end
                case(state)
                    IDLE:if(start)begin
                        busy<=1;color_id<=0;color_conf<=0;valid_samples<=0;count_r<=0;count_g<=0;count_b<=0;
                        pending<=0;fetch_done<=0;buffer_valid<=0;write_slot<=0;read_slot<=0;lane<=0;
                        bx0<=box_x0;bx1<=box_x1;by0<=box_y0;by1<=box_y1;
                        width<=box_x1-box_x0;height<=box_y1-box_y0;
                        if(box_x0>=box_x1 || box_y0>=box_y1 || box_x1>1280 || box_y1>720)state<=FINISH;
                        else state<=MARGINS;
                    end
                    MARGINS:begin mx<=({1'b0,width}+12'd7)>>3;my<=({1'b0,height}+11'd7)>>3;state<=INTERIOR;end
                    INTERIOR:begin ix0<=inner_x0;ix1<=inner_x1;iy0<=inner_y0;iy1<=inner_y1;state<=SETUP;end
                    SETUP:begin
                        first_word<=ix0[10:3];last_word<=last_inner_x[10:3];fetch_word<=ix0[10:3];fetch_y<=iy0;
                        row_first_addr<=({11'd0,iy0}<<11)+({11'd0,iy0}<<9)+{9'd0,ix0[10:3],4'b0};
                        byte_addr<=({11'd0,iy0}<<11)+({11'd0,iy0}<<9)+{9'd0,ix0[10:3],4'b0};state<=SCAN;
                    end
                    RANK:begin
                        color_id<=winner;quotient<=0;remainder<=0;divide_steps<=5'd27;
                        numerator<={delta,8'b0}-{8'd0,delta};
                        if(valid_samples==0)begin color_conf<=0;state<=FINISH;end
                        else state<=DIVIDE;
                    end
                    DIVIDE:begin
                        numerator<={numerator[26:0],1'b0};
                        remainder<=subtract_divisor ? shifted_remainder-{1'b0,valid_samples} : shifted_remainder;
                        quotient<={quotient[6:0],subtract_divisor};
                        if(divide_steps==0)begin color_conf<={quotient[6:0],subtract_divisor};state<=FINISH;end
                        else divide_steps<=divide_steps-1'b1;
                    end
                    FINISH:begin busy<=0;done<=1;state<=IDLE;end
                    default:begin end
                endcase
            end
        end
    end
endmodule
