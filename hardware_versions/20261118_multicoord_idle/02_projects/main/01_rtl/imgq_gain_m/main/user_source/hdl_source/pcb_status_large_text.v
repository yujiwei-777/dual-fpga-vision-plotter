// Enlarged PCB status panel.  Coordinates are supplied in the HDMI pixel
// domain; the two register stages keep the same alignment as the legacy PCB
// text ROM while using the shared 8x16 source font.
module pcb_status_large_text(
    input wire clk,
    input wire rst_n,
    input wire [11:0] x,
    input wire [11:0] y,
    input wire [2:0] status,
    input wire [7:0] font_bits,
    output wire [7:0] font_char,
    output wire [3:0] font_row,
    output wire text_on,
    output wire [23:0] text_color
);
    reg valid_c;
    reg [7:0] char_c;
    reg [3:0] row_c;
    reg [2:0] col_c;
    reg [23:0] color_c;
    reg [4:0] cell_c;
    reg [11:0] local_x_c,local_y_c;
    reg [1:0] line_c;
    reg [7:0] line_char;
    reg [7:0] char_s1;
    reg [3:0] row_s1;
    reg [2:0] col_s1;
    reg valid_s1;
    reg [23:0] color_s1;
    reg [7:0] row_bits_s2;
    reg [2:0] col_s2;
    reg valid_s2;
    reg [23:0] color_s2;

    function [7:0] F_status_char;
        input [2:0] st;
        input [4:0] pos;
        begin
            F_status_char = " ";
            case(st)
                3'd0: case(pos) 0:F_status_char="R";1:F_status_char="E";2:F_status_char="A";3:F_status_char="D";4:F_status_char="Y"; endcase
                3'd1: case(pos) 0:F_status_char="S";1:F_status_char="C";2:F_status_char="A";3:F_status_char="N";4:F_status_char="N";5:F_status_char="I";6:F_status_char="N";7:F_status_char="G"; endcase
                3'd2: case(pos) 0:F_status_char="P";1:F_status_char="A";2:F_status_char="S";3:F_status_char="S"; endcase
                3'd3: case(pos) 0:F_status_char="F";1:F_status_char="A";2:F_status_char="I";3:F_status_char="L"; endcase
                3'd4: case(pos) 0:F_status_char="R";1:F_status_char="E";2:F_status_char="V";3:F_status_char="I";4:F_status_char="E";5:F_status_char="W"; endcase
                3'd5: case(pos) 0:F_status_char="N";1:F_status_char="O";3:F_status_char="T";5:F_status_char="A";6:F_status_char="R";7:F_status_char="G";8:F_status_char="E";9:F_status_char="T"; endcase
                3'd6: case(pos) 0:F_status_char="W";1:F_status_char="A";2:F_status_char="I";3:F_status_char="T";5:F_status_char="R";6:F_status_char="E";7:F_status_char="A";8:F_status_char="D";9:F_status_char="Y"; endcase
                3'd7: case(pos) 0:F_status_char="L";1:F_status_char="I";2:F_status_char="N";3:F_status_char="K";5:F_status_char="E";6:F_status_char="R";7:F_status_char="R";8:F_status_char="O";9:F_status_char="R"; endcase
                default: F_status_char=" ";
            endcase
        end
    endfunction

    function [23:0] F_status_color;
        input [2:0] st;
        begin
            case(st)
                3'd2: F_status_color=24'h50ff50; // PASS
                3'd3: F_status_color=24'hff6060; // FAIL
                3'd5: F_status_color=24'hffea64; // NO TARGET
                3'd6: F_status_color=24'hffea64; // WAIT READY
                3'd7: F_status_color=24'hff6060; // LINK ERROR
                default: F_status_color=24'hffea64;
            endcase
        end
    endfunction

    assign font_char = char_s1;
    assign font_row = row_s1;

    always @(*) begin
        valid_c=1'b0; char_c=" "; row_c=4'd0; col_c=3'd0; color_c=24'h62e5ea;
        local_x_c=x-12'd24; local_y_c=y-12'd560; cell_c=local_x_c[8:4];
        line_c=2'd0;
        if((x>=12'd24)&&(x<12'd344)) begin
            if((local_y_c>=12'd8)&&(local_y_c<12'd40)) begin
                line_c=2'd0; valid_c=1'b1; row_c=(local_y_c-12'd8)>>1;
            end else if((local_y_c>=12'd52)&&(local_y_c<12'd84)) begin
                line_c=2'd1; valid_c=1'b1; row_c=(local_y_c-12'd52)>>1;
            end else if((local_y_c>=12'd96)&&(local_y_c<12'd128)) begin
                line_c=2'd2; valid_c=1'b1; row_c=(local_y_c-12'd96)>>1;
            end
        end
        col_c=local_x_c[3:1];
        case(line_c)
            2'd0: case(cell_c)
                0:char_c="P";1:char_c="C";2:char_c="B";4:char_c="M";5:char_c="O";6:char_c="D";7:char_c="E";default:char_c=" ";
            endcase
            2'd1: case(cell_c)
                0:char_c="H";1:char_c="O";2:char_c="L";3:char_c="D";5:char_c="K";6:char_c="E";7:char_c="Y";8:char_c="4";10:char_c="T";11:char_c="O";13:char_c="T";14:char_c="E";15:char_c="S";16:char_c="T";default:char_c=" ";
            endcase
            default: char_c=F_status_char(status,cell_c);
        endcase
        if(line_c==2'd2) color_c=F_status_color(status);
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            char_s1<= " "; row_s1<=0; col_s1<=0; valid_s1<=0; color_s1<=0;
            row_bits_s2<=0; col_s2<=0; valid_s2<=0; color_s2<=0;
        end else begin
            char_s1<=char_c; row_s1<=row_c; col_s1<=col_c; valid_s1<=valid_c; color_s1<=color_c;
            row_bits_s2<=font_bits; col_s2<=col_s1; valid_s2<=valid_s1; color_s2<=color_s1;
        end
    end

    assign text_on = valid_s2 && row_bits_s2[7-col_s2];
    assign text_color = color_s2;
endmodule
