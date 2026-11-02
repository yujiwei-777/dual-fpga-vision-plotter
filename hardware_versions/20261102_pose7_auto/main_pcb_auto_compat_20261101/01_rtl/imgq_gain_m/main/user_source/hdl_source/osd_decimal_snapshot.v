// Display-only binary-to-decimal snapshot. One shared shift/add converter,
// no divider or DSP. All four values commit together before the first OSD row.
module osd_decimal_snapshot(
    input wire clk, rst_n, frame_start,
    input wire [15:0] frame_number,
    input wire [10:0] target_x,
    input wire [9:0] target_y,
    input wire [23:0] target_area,
    output reg [19:0] frame_bcd,
    output reg [15:0] target_x_bcd, target_y_bcd,
    output reg [23:0] area_bcd
);
    reg busy;
    reg [1:0] field_id;
    reg [4:0] step;
    reg [23:0] binary, work_bcd, adjusted;
    reg [10:0] x_hold;
    reg [9:0] y_hold;
    reg [23:0] area_hold;
    reg [19:0] frame_work;
    reg [15:0] x_work, y_work;
    integer digit;
    wire [23:0] next_bcd = {adjusted[22:0], binary[23]};
    always @* begin
        adjusted = work_bcd;
        for(digit=0; digit<6; digit=digit+1)
            if(work_bcd[digit*4+:4] >= 4'd5)
                adjusted[digit*4+:4] = work_bcd[digit*4+:4] + 4'd3;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0; field_id<=0; step<=0; binary<=0; work_bcd<=0;
            x_hold<=0; y_hold<=0; area_hold<=0;
            frame_work<=0; x_work<=0; y_work<=0;
            frame_bcd<=0; target_x_bcd<=0; target_y_bcd<=0; area_bcd<=0;
        end else if(frame_start) begin
            busy<=1; field_id<=0; step<=0; work_bcd<=0;
            binary<={8'd0,frame_number}; x_hold<=target_x; y_hold<=target_y;
            // Six decimal places cover every legal 1280x720 area. Saturate
            // malformed metadata instead of wrapping its displayed value.
            area_hold<=(target_area>24'd999999)?24'd999999:target_area;
        end else if(busy) begin
            binary<={binary[22:0],1'b0}; work_bcd<=next_bcd;
            if(step==5'd23) begin
                step<=0; work_bcd<=0;
                case(field_id)
                    0:begin frame_work<=next_bcd[19:0]; binary<={13'd0,x_hold}; field_id<=1; end
                    1:begin x_work<=next_bcd[15:0]; binary<={14'd0,y_hold}; field_id<=2; end
                    2:begin y_work<=next_bcd[15:0]; binary<=area_hold; field_id<=3; end
                    3:begin
                        frame_bcd<=frame_work; target_x_bcd<=x_work;
                        target_y_bcd<=y_work; area_bcd<=next_bcd; busy<=0;
                    end
                endcase
            end else step<=step+1'b1;
        end
    end
endmodule
