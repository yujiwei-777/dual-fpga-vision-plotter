// Map the 320x320 planner canvas to the fixed A4-safe machine rectangle.
// The active camera raster is x=0..319, y=70..249.  The 16:9 image is kept
// proportional on the A4 sheet: 19000 cmm wide by 10688 cmm high, with the
// logical top-left at (1000,1000).  Products and divisions are serial; no DSP
// is inferred.
module doc_grbl_map(
    input wire clk,rst_n,start,input wire [8:0] x,y,
    output reg [15:0] x_cmm,y_cmm,output reg done
);
    localparam [2:0] ST_IDLE=3'd0,ST_MUL_X=3'd1,ST_MUL_Y=3'd2,
                     ST_DIV_X=3'd3,ST_DIV_Y=3'd4;
    localparam integer X_ORIGIN=1000,Y_ORIGIN=1000;
    localparam integer X_SCALE=19000,Y_SCALE=10688;
    localparam integer X_DEN=319,Y_DEN=179;
    reg [2:0] state;
    reg [5:0] count;
    reg [31:0] multiplier,multiplicand,product;
    reg [31:0] x_scaled,y_scaled,dividend,quotient;
    reg [10:0] remainder;
    reg [8:0] y_span;
    wire [11:0] next_remainder={remainder,dividend[31]};
    wire subtract=(state==ST_DIV_X)?(next_remainder>=X_DEN):
                                      (next_remainder>=Y_DEN);
    wire [31:0] next_quotient={quotient[30:0],subtract};
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=ST_IDLE;count<=0;multiplier<=0;multiplicand<=0;product<=0;
            x_scaled<=0;y_scaled<=0;dividend<=0;quotient<=0;remainder<=0;
            y_span<=0;x_cmm<=0;y_cmm<=0;done<=0;
        end else begin
            done<=0;
            case(state)
                ST_IDLE:if(start)begin
                    multiplier<=x;multiplicand<=X_SCALE;product<=0;
                    y_span<=y < 9'd70 ? 9'd0 : (y > 9'd249 ? 9'd179 : y-9'd70);
                    count<=0;state<=ST_MUL_X;
                end
                ST_MUL_X:begin
                    if(multiplier[0])product<=product+multiplicand;
                    multiplier<=multiplier>>1;multiplicand<=multiplicand<<1;
                    if(count==8)begin
                        x_scaled<=product+(multiplier[0]?multiplicand:32'd0)+32'd159;
                        multiplier<=y_span;multiplicand<=Y_SCALE;product<=0;
                        count<=0;state<=ST_MUL_Y;
                    end else count<=count+1'b1;
                end
                ST_MUL_Y:begin
                    if(multiplier[0])product<=product+multiplicand;
                    multiplier<=multiplier>>1;multiplicand<=multiplicand<<1;
                    if(count==8)begin
                        y_scaled<=product+(multiplier[0]?multiplicand:32'd0)+32'd89;
                        dividend<=x_scaled;quotient<=0;remainder<=0;count<=0;
                        state<=ST_DIV_X;
                    end else count<=count+1'b1;
                end
                ST_DIV_X:begin
                    dividend<=dividend<<1;quotient<=next_quotient;
                    if(subtract)remainder<=next_remainder-X_DEN;
                    else remainder<=next_remainder[10:0];
                    if(count==31)begin
                        x_cmm<=X_ORIGIN+next_quotient[15:0];
                        dividend<=y_scaled;quotient<=0;remainder<=0;count<=0;
                        state<=ST_DIV_Y;
                    end else count<=count+1'b1;
                end
                ST_DIV_Y:begin
                    dividend<=dividend<<1;quotient<=next_quotient;
                    if(subtract)remainder<=next_remainder-Y_DEN;
                    else remainder<=next_remainder[10:0];
                    if(count==31)begin
                        y_cmm<=Y_ORIGIN+next_quotient[15:0];done<=1;state<=ST_IDLE;
                    end else count<=count+1'b1;
                end
                default:state<=ST_IDLE;
            endcase
        end
    end
endmodule
