// Six display fields share a 16-clock shift/add converter. No divider/DSP.
// Started at active x=4, all digits settle before the operator panel at y=224.
module operator_ui_decimal(
    input wire clk,rst_n,start,
    input wire [152:0] data,
    output wire [119:0] bcd
);
    // Exactly the 24 decimal nibbles addressed by the frozen token ROM.
    // Unused upper field digits remain zero on the unchanged 120-bit port.
    reg [95:0] displayed_bcd;
    assign bcd={displayed_bcd[95:76],4'd0,displayed_bcd[75:60],
        4'd0,displayed_bcd[59:44],4'd0,displayed_bcd[43:28],
        4'd0,displayed_bcd[27:12],8'd0,displayed_bcd[11:0]};
    reg busy;
    reg [2:0] field;
    reg [3:0] step;
    reg [15:0] binary;
    reg [19:0] working,adjusted;
    integer digit;
    wire [19:0] next_bcd={adjusted[18:0],binary[15]};
    always @* begin
        adjusted=working;
        for(digit=0;digit<5;digit=digit+1)
            if(working[digit*4+:4]>=5)adjusted[digit*4+:4]=working[digit*4+:4]+4'd3;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin busy<=0;field<=0;step<=0;binary<=0;working<=0;displayed_bcd<=0;end
        else if(start)begin
            busy<=1;field<=0;step<=0;binary<={8'd0,data[57:50]};working<=0;
        end else if(busy)begin
            binary<={binary[14:0],1'b0};working<=next_bcd;
            if(step==15)begin
                step<=0;working<=0;field<=field+1'b1;
                case(field)
                    0:begin displayed_bcd[11:0]<=next_bcd[11:0];binary<={5'd0,data[74:64]};end
                    1:begin displayed_bcd[27:12]<=next_bcd[15:0];binary<={6'd0,data[84:75]};end
                    2:begin displayed_bcd[43:28]<=next_bcd[15:0];binary<={4'd0,data[96:85]};end
                    3:begin displayed_bcd[59:44]<=next_bcd[15:0];binary<={2'd0,data[110:97]};end
                    4:begin displayed_bcd[75:60]<=next_bcd[15:0];binary<={1'b0,data[125:111]};end
                    5:begin displayed_bcd[95:76]<=next_bcd[19:0];busy<=0;end
                    default:busy<=0;
                endcase
            end else step<=step+1'b1;
        end
    end
endmodule
