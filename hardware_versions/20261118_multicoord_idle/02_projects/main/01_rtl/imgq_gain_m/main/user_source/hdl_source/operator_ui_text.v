// Key selection and dynamic glyph decode; token supplied by shared atlas.
module operator_ui_text #(parameter PAPER_STATUS_ENABLE=1'b1)(input wire clk,input wire valid,input wire [2:0] row,input wire [4:0] col,
 input wire [152:0] data,input wire [3:0] decimal_digit,output wire [5:0] decimal_addr,input wire [8:0] shared_token,output wire [5:0] shared_key,output reg [7:0] glyph);
 wire [2:0] kind=data[10:8],state=data[13:11];
 wire preview=data[0]||data[1];
 reg [5:0] key;
 wire [8:0] token=shared_token;
 assign shared_key=key;
 // Input metadata and decimal snapshot are frame-held. Only the ROM token
 // needs a pixel stage; no duplicate 176-bit numeric register bank is used.
 assign decimal_addr=token[5:0];
 wire [7:0] error=data[149:142];
 reg [3:0] nibble;
 always @* begin
  key=56;
  case(row)
   0:key={3'd0,state};
   1:if(preview)case(kind)
    1:key=(data[49:46]<=9)?6'd8+{2'd0,data[49:46]}:6'd8;
    2:key=6'd18+{4'd0,data[59:58]};
    3:key=22;
    4:key=23;
    default:key=24;
   endcase
   else key=24;
   2:if(preview)case(kind)
    1:key=25;
    2:key=56; // PCB report has no suspected-position row.
    3:key=27;
    4:key=28;
   endcase
   3:key=29;
   4:key=PAPER_STATUS_ENABLE?6'd31:6'd56;
   5:key=6'd32+{2'd0,data[63:60]};
   6:begin
    if(data[152:150]==5)key=58;
    else if(data[152:150]==6)key=59;
    else if(data[152:150]==4)key=48;
    else if(data[3])key=49;
    else if(PAPER_STATUS_ENABLE&&data[2])key=50;
    else if(!data[7])key=57;
    else case(data[152:150])
     1:key=51;
     2:key=52;
     3:key=53;
     default:if(data[149:142]!=0)key=54;
    endcase
   end
   7:key=55;
  endcase
  // Equivalent to the original 153-bit valid/data AND, factored after key
  // selection. These are exactly the frozen key values for data == 0.
  if(!valid)case(row)
   0:key=0;1:key=24;2:key=56;3:key=29;
   4:key=PAPER_STATUS_ENABLE?6'd31:6'd56;5:key=32;6:key=57;7:key=55;
  endcase
 end
 always @* begin
  nibble=0;glyph=token[7:0];
  if(token[8] && !token[6])begin
   nibble=decimal_digit;
   glyph=nibble<10?8'h30+nibble:8'h3f;
  end else if(token[8] && token[6])begin
   nibble=error[{token[0],2'b00}+:4];
   // Hex fields are live metadata. Decimal BCD is already a held snapshot
   // and must retain its original value through an invalidation edge.
   if(!valid)nibble=0;
   glyph=nibble<10?8'h30+nibble:8'h41+nibble-10;
  end
 end
endmodule
