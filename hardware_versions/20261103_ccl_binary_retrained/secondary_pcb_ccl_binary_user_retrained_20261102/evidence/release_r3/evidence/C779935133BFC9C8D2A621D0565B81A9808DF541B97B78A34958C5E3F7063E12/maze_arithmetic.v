// Shared signed 40-bit serial arithmetic. The one 41-bit carry chain is
// reused for multiplication, restoring division, add/sub and sign changes.
// sum_mode extends the internal interface: 0=multiply/divide, 1=add/sub.
module maze_arithmetic(
    input wire clk,rst_n,start,divide,
    input wire signed [39:0] a,b,
    output reg busy,done,error,
    output reg signed [39:0] result,
    input wire sum_mode,subtract
);
    localparam IDLE=0,ABS_A=1,ABS_B=2,RUN=3,FINAL=4,SUM=5;
    reg [2:0] state;
    reg div_mode,negative,sum_sub;
    reg [5:0] count;
    reg [39:0] left,right,accum;
    reg [40:0] add_a,add_b;
    reg add_sub;
    wire [40:0] add_result=add_a+(add_b^{41{add_sub}})+add_sub;
    wire div_take=!add_result[40];
    wire [39:0] div_next={left[38:0],div_take};
    always @*begin
        add_a=0;add_b=0;add_sub=0;
        case(state)
            ABS_A:begin add_b={1'b0,left};add_sub=1;end
            ABS_B:begin add_b={1'b0,right};add_sub=1;end
            RUN:if(div_mode)begin add_a={accum,left[39]};add_b={1'b0,right};add_sub=1;end
                else begin add_a={1'b0,accum};add_b=right[0]?{1'b0,left}:41'd0;end
            SUM:begin add_a={1'b0,left};add_b={1'b0,right};add_sub=sum_sub;end
            FINAL:begin add_b={1'b0,div_mode?left:accum};add_sub=1;end
            default:;
        endcase
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;busy<=0;done<=0;error<=0;result<=0;
            div_mode<=0;negative<=0;sum_sub<=0;count<=0;left<=0;right<=0;accum<=0;
        end else begin
            done<=0;
            case(state)
                IDLE:if(start)begin
                    error<=0;left<=a;right<=b;accum<=0;count<=0;
                    div_mode<=divide;sum_sub<=subtract;
                    negative<=a[39]^b[39];
                    if(sum_mode===1'b1)begin busy<=1;state<=SUM;end
                    else if(divide&&b==0)begin result<=0;error<=1;done<=1;end
                    else begin busy<=1;state<=ABS_A;end
                end
                ABS_A:begin if(left[39])left<=add_result[39:0];state<=ABS_B;end
                ABS_B:begin if(right[39])right<=add_result[39:0];state<=RUN;end
                RUN:begin
                    count<=count+1'b1;
                    if(div_mode)begin
                        accum<=div_take?add_result[39:0]:{accum[38:0],left[39]};
                        left<=div_next;
                    end else begin
                        accum<=add_result[39:0];left<=left<<1;right<=right>>1;
                    end
                    if(count==39)state<=FINAL;
                end
                SUM:begin result<=add_result[39:0];busy<=0;done<=1;state<=IDLE;end
                FINAL:begin
                    result<=negative?add_result[39:0]:(div_mode?left:accum);
                    busy<=0;done<=1;state<=IDLE;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
