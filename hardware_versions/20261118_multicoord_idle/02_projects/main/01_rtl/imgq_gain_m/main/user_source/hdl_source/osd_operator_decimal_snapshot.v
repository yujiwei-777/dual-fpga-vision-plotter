// Display-only shared decimal converter for the original and operator panels.
// Original 4-field OSD still commits atomically at clock 96. The six operator
// fields share the same converter afterwards and finish at clock 192, before
// y224. Eight multi-target centre fields then finish at clock320, before y64.
// Metadata is required frame-held exactly as the actual UI mailbox.
module osd_operator_decimal_snapshot(
 input wire clk,rst_n,frame_start,
 input wire [15:0] frame_number,input wire [10:0] target_x,
 input wire [9:0] target_y,input wire [23:0] target_area,
 input wire [152:0] operator_data,
 input wire [511:0] multi_boxes,
 output reg [19:0] frame_bcd,output reg [15:0] target_x_bcd,target_y_bcd,
 output reg [23:0] area_bcd,input wire [6:0] operator_digit_addr,output wire [3:0] operator_digit
);
 // One word per decimal field. Uninitialized DRAM is hidden by valid bits.
 (* ram_style="dram" *) reg [19:0] decimal_words[0:15];
 reg [13:0] decimal_valid;
 wire [19:0] selected_word=decimal_words[operator_digit_addr[6:3]];
 assign operator_digit=(operator_digit_addr[6:3]>=14 || operator_digit_addr[2:0]>=5)?4'hf:
   (decimal_valid[operator_digit_addr[6:3]]?selected_word[{operator_digit_addr[2:0],2'b00}+:4]:4'd0);
 reg busy;reg [4:0] field;reg [4:0] step;
 reg [23:0] binary,working,adjusted;
 reg [10:0] x_hold;reg [9:0] y_hold;reg [23:0] area_hold;
 reg [19:0] frame_work;reg [15:0] x_work,y_work;
 wire [1:0] multi_slot=(field-5'd9)>>1;
 wire [127:0] multi_box=multi_boxes[{multi_slot,7'b0}+:128];
 wire [11:0] multi_xsum={1'b0,multi_box[10:0]}+{1'b0,multi_box[42:32]};
 wire [10:0] multi_ysum={1'b0,multi_box[25:16]}+{1'b0,multi_box[57:48]};
 wire [10:0] multi_cx=multi_xsum[11:1];
 wire [9:0] multi_cy=multi_ysum[10:1];
 integer digit;
 wire [23:0] next_bcd={adjusted[22:0],binary[23]};
 wire field_end=(field<4)?(step==23):(step==15);
 always @*begin
  adjusted=working;
  for(digit=0;digit<6;digit=digit+1)
   if(working[digit*4+:4]>=5)adjusted[digit*4+:4]=working[digit*4+:4]+4'd3;
 end
 always @(posedge clk)begin
  if(rst_n && !frame_start && busy && field_end && field>=4 && field<=17)
   decimal_words[field-5'd4]<=field==4?{8'd0,next_bcd[11:0]}:
       field==9?next_bcd[19:0]:{4'd0,next_bcd[15:0]};
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   busy<=0;field<=0;step<=0;binary<=0;working<=0;
   x_hold<=0;y_hold<=0;area_hold<=0;frame_work<=0;x_work<=0;y_work<=0;
   frame_bcd<=0;target_x_bcd<=0;target_y_bcd<=0;area_bcd<=0;decimal_valid<=0;
  end else if(frame_start)begin
   busy<=1;field<=0;step<=0;working<=0;binary<={8'd0,frame_number};
   x_hold<=target_x;y_hold<=target_y;
   area_hold<=(target_area > 24'd999999) ? 24'd999999 : target_area;
  end else if(busy)begin
   binary<={binary[22:0],1'b0};working<=next_bcd;
   if(field_end)begin
    step<=0;working<=0;field<=field+1'b1;
    case(field)
     0:begin frame_work<=next_bcd[19:0];binary<={13'd0,x_hold};end
     1:begin x_work<=next_bcd[15:0];binary<={14'd0,y_hold};end
     2:begin y_work<=next_bcd[15:0];binary<=area_hold;end
     3:begin
      frame_bcd<=frame_work;target_x_bcd<=x_work;target_y_bcd<=y_work;area_bcd<=next_bcd;
      binary<={8'd0,operator_data[57:50],8'd0};
     end
     4:begin decimal_valid[0]<=1'b1;binary<={5'd0,operator_data[74:64],8'd0};end
     5:begin decimal_valid[1]<=1'b1;binary<={6'd0,operator_data[84:75],8'd0};end
     6:begin decimal_valid[2]<=1'b1;binary<={4'd0,operator_data[96:85],8'd0};end
     7:begin decimal_valid[3]<=1'b1;binary<={2'd0,operator_data[110:97],8'd0};end
     8:begin decimal_valid[4]<=1'b1;binary<={1'b0,operator_data[125:111],8'd0};end
     9:begin decimal_valid[5]<=1'b1;binary<={5'd0,multi_cx,8'd0};end
     default:begin
      decimal_valid[field-5'd4]<=1'b1;
      if(field==17)busy<=0;
      else if(!field[0])binary<={6'd0,multi_cy,8'd0};
      else binary<={5'd0,multi_cx,8'd0};
     end
    endcase
   end else step<=step+1'b1;
  end
 end
endmodule
