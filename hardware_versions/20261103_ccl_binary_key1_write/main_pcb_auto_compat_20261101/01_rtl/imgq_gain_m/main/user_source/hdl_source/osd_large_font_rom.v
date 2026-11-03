// Shared 8x16 bitmap font for the enlarged HDMI OSD.
// The source glyph is expanded by the consumers to a 16x32 cell.  Keeping the
// source at one fixed baseline makes the dynamic and PCB status panels match.
module osd_large_font_rom(
    input wire [7:0] I_char,
    input wire [3:0] I_row,
    output reg [7:0] O_row_bits
);
    function [4:0] F_font5;
        input [7:0] c;
        input [2:0] r;
        begin
            F_font5 = 5'b00000;
            case(c)
                "A": case(r) 0:F_font5=5'b01110;1:F_font5=5'b10001;2:F_font5=5'b10001;3:F_font5=5'b11111;4:F_font5=5'b10001;5:F_font5=5'b10001;6:F_font5=5'b10001; endcase
                "B": case(r) 0:F_font5=5'b11110;1:F_font5=5'b10001;2:F_font5=5'b10001;3:F_font5=5'b11110;4:F_font5=5'b10001;5:F_font5=5'b10001;6:F_font5=5'b11110; endcase
                "C": case(r) 0:F_font5=5'b01111;1:F_font5=5'b10000;2:F_font5=5'b10000;3:F_font5=5'b10000;4:F_font5=5'b10000;5:F_font5=5'b10000;6:F_font5=5'b01111; endcase
                "D": case(r) 0:F_font5=5'b11110;1:F_font5=5'b10001;2:F_font5=5'b10001;3:F_font5=5'b10001;4:F_font5=5'b10001;5:F_font5=5'b10001;6:F_font5=5'b11110; endcase
                "E": case(r) 0:F_font5=5'b11111;1:F_font5=5'b10000;2:F_font5=5'b10000;3:F_font5=5'b11110;4:F_font5=5'b10000;5:F_font5=5'b10000;6:F_font5=5'b11111; endcase
                "F": case(r) 0:F_font5=5'b11111;1:F_font5=5'b10000;2:F_font5=5'b10000;3:F_font5=5'b11110;4:F_font5=5'b10000;5:F_font5=5'b10000;6:F_font5=5'b10000; endcase
                "G": case(r) 0:F_font5=5'b01111;1:F_font5=5'b10000;2:F_font5=5'b10111;3:F_font5=5'b10001;4:F_font5=5'b10001;5:F_font5=5'b10001;6:F_font5=5'b01111; endcase
                "H": case(r) 0:F_font5=5'b10001;1:F_font5=5'b10001;2:F_font5=5'b10001;3:F_font5=5'b11111;4:F_font5=5'b10001;5:F_font5=5'b10001;6:F_font5=5'b10001; endcase
                "I": case(r) 0:F_font5=5'b11111;1:F_font5=5'b00100;2:F_font5=5'b00100;3:F_font5=5'b00100;4:F_font5=5'b00100;5:F_font5=5'b00100;6:F_font5=5'b11111; endcase
                "J": case(r) 0:F_font5=5'b00111;1:F_font5=5'b00010;2:F_font5=5'b00010;3:F_font5=5'b00010;4:F_font5=5'b10010;5:F_font5=5'b10010;6:F_font5=5'b01100; endcase
                "K": case(r) 0:F_font5=5'b10001;1:F_font5=5'b10010;2:F_font5=5'b10100;3:F_font5=5'b11000;4:F_font5=5'b10100;5:F_font5=5'b10010;6:F_font5=5'b10001; endcase
                "L": case(r) 0:F_font5=5'b10000;1:F_font5=5'b10000;2:F_font5=5'b10000;3:F_font5=5'b10000;4:F_font5=5'b10000;5:F_font5=5'b10000;6:F_font5=5'b11111; endcase
                "M": case(r) 0:F_font5=5'b10001;1:F_font5=5'b11011;2:F_font5=5'b10101;3:F_font5=5'b10101;4:F_font5=5'b10001;5:F_font5=5'b10001;6:F_font5=5'b10001; endcase
                "N": case(r) 0:F_font5=5'b10001;1:F_font5=5'b11001;2:F_font5=5'b10101;3:F_font5=5'b10011;4:F_font5=5'b10001;5:F_font5=5'b10001;6:F_font5=5'b10001; endcase
                "O": case(r) 0:F_font5=5'b01110;1:F_font5=5'b10001;2:F_font5=5'b10001;3:F_font5=5'b10001;4:F_font5=5'b10001;5:F_font5=5'b10001;6:F_font5=5'b01110; endcase
                "P": case(r) 0:F_font5=5'b11110;1:F_font5=5'b10001;2:F_font5=5'b10001;3:F_font5=5'b11110;4:F_font5=5'b10000;5:F_font5=5'b10000;6:F_font5=5'b10000; endcase
                "Q": case(r) 0:F_font5=5'b01110;1:F_font5=5'b10001;2:F_font5=5'b10001;3:F_font5=5'b10001;4:F_font5=5'b10101;5:F_font5=5'b10010;6:F_font5=5'b01101; endcase
                "R": case(r) 0:F_font5=5'b11110;1:F_font5=5'b10001;2:F_font5=5'b10001;3:F_font5=5'b11110;4:F_font5=5'b10100;5:F_font5=5'b10010;6:F_font5=5'b10001; endcase
                "S": case(r) 0:F_font5=5'b01111;1:F_font5=5'b10000;2:F_font5=5'b10000;3:F_font5=5'b01110;4:F_font5=5'b00001;5:F_font5=5'b00001;6:F_font5=5'b11110; endcase
                "T": case(r) 0:F_font5=5'b11111;1:F_font5=5'b00100;2:F_font5=5'b00100;3:F_font5=5'b00100;4:F_font5=5'b00100;5:F_font5=5'b00100;6:F_font5=5'b00100; endcase
                "U": case(r) 0:F_font5=5'b10001;1:F_font5=5'b10001;2:F_font5=5'b10001;3:F_font5=5'b10001;4:F_font5=5'b10001;5:F_font5=5'b10001;6:F_font5=5'b01110; endcase
                "V": case(r) 0:F_font5=5'b10001;1:F_font5=5'b10001;2:F_font5=5'b10001;3:F_font5=5'b10001;4:F_font5=5'b10001;5:F_font5=5'b01010;6:F_font5=5'b00100; endcase
                "W": case(r) 0:F_font5=5'b10001;1:F_font5=5'b10001;2:F_font5=5'b10001;3:F_font5=5'b10101;4:F_font5=5'b10101;5:F_font5=5'b11011;6:F_font5=5'b10001; endcase
                "X": case(r) 0:F_font5=5'b10001;1:F_font5=5'b10001;2:F_font5=5'b01010;3:F_font5=5'b00100;4:F_font5=5'b01010;5:F_font5=5'b10001;6:F_font5=5'b10001; endcase
                "Y": case(r) 0:F_font5=5'b10001;1:F_font5=5'b10001;2:F_font5=5'b01010;3:F_font5=5'b00100;4:F_font5=5'b00100;5:F_font5=5'b00100;6:F_font5=5'b00100; endcase
                "Z": case(r) 0:F_font5=5'b11111;1:F_font5=5'b00001;2:F_font5=5'b00010;3:F_font5=5'b00100;4:F_font5=5'b01000;5:F_font5=5'b10000;6:F_font5=5'b11111; endcase
                "0": case(r) 0:F_font5=5'b01110;1:F_font5=5'b10001;2:F_font5=5'b10011;3:F_font5=5'b10101;4:F_font5=5'b11001;5:F_font5=5'b10001;6:F_font5=5'b01110; endcase
                "1": case(r) 0:F_font5=5'b00100;1:F_font5=5'b01100;2:F_font5=5'b00100;3:F_font5=5'b00100;4:F_font5=5'b00100;5:F_font5=5'b00100;6:F_font5=5'b01110; endcase
                "2": case(r) 0:F_font5=5'b01110;1:F_font5=5'b10001;2:F_font5=5'b00001;3:F_font5=5'b00110;4:F_font5=5'b01000;5:F_font5=5'b10000;6:F_font5=5'b11111; endcase
                "3": case(r) 0:F_font5=5'b11110;1:F_font5=5'b00001;2:F_font5=5'b00001;3:F_font5=5'b01110;4:F_font5=5'b00001;5:F_font5=5'b00001;6:F_font5=5'b11110; endcase
                "4": case(r) 0:F_font5=5'b00010;1:F_font5=5'b00110;2:F_font5=5'b01010;3:F_font5=5'b10010;4:F_font5=5'b11111;5:F_font5=5'b00010;6:F_font5=5'b00010; endcase
                "5": case(r) 0:F_font5=5'b11111;1:F_font5=5'b10000;2:F_font5=5'b11110;3:F_font5=5'b00001;4:F_font5=5'b00001;5:F_font5=5'b10001;6:F_font5=5'b01110; endcase
                "6": case(r) 0:F_font5=5'b01110;1:F_font5=5'b10000;2:F_font5=5'b10000;3:F_font5=5'b11110;4:F_font5=5'b10001;5:F_font5=5'b10001;6:F_font5=5'b01110; endcase
                "7": case(r) 0:F_font5=5'b11111;1:F_font5=5'b00001;2:F_font5=5'b00010;3:F_font5=5'b00100;4:F_font5=5'b01000;5:F_font5=5'b01000;6:F_font5=5'b01000; endcase
                "8": case(r) 0:F_font5=5'b01110;1:F_font5=5'b10001;2:F_font5=5'b10001;3:F_font5=5'b01110;4:F_font5=5'b10001;5:F_font5=5'b10001;6:F_font5=5'b01110; endcase
                "9": case(r) 0:F_font5=5'b01110;1:F_font5=5'b10001;2:F_font5=5'b10001;3:F_font5=5'b01111;4:F_font5=5'b00001;5:F_font5=5'b00001;6:F_font5=5'b01110; endcase
                ":": case(r) 2,4:F_font5=5'b00100; endcase
                ".": case(r) 6:F_font5=5'b00100; endcase
                "-": case(r) 3:F_font5=5'b11111; endcase
                "/": case(r) 0:F_font5=5'b00001;1:F_font5=5'b00010;2:F_font5=5'b00100;3:F_font5=5'b01000;4:F_font5=5'b10000;5:F_font5=5'b10000;6:F_font5=5'b10000; endcase
                "%": case(r) 0:F_font5=5'b11001;1:F_font5=5'b11010;2:F_font5=5'b00100;3:F_font5=5'b01000;4:F_font5=5'b10011;5:F_font5=5'b01011;6:F_font5=5'b10011; endcase
                default: F_font5=5'b00000;
            endcase
        end
    endfunction

    reg [2:0] src_row;
    reg [4:0] src_bits;
    always @(*) begin
        src_row = 3'd0;
        src_bits = 5'b00000;
        if((I_row != 4'd0) && (I_row != 4'd15)) begin
            src_row = (I_row - 4'd1) >> 1;
            src_bits = F_font5(I_char, src_row);
        end
        // Duplicate the two outside columns so the 2x consumer produces a
        // roughly 14-pixel ink width inside the fixed 16-pixel cell.
        O_row_bits = {src_bits[4],src_bits,src_bits[0],1'b0};
    end
endmodule
