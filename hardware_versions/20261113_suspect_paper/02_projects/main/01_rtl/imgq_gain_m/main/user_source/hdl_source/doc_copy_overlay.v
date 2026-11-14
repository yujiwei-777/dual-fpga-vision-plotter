// Two-clock guide/status renderer, aligned with hxa_multibox_overlay.
module doc_copy_overlay(
    input wire clk,rst_n,enable,input wire [2:0] state,
    input wire [11:0] x,y,output reg hit,output wire [23:0] color
);
    function [7:0] letter;
        input [2:0] s,c;
        begin
            letter=" ";
            case(s)
                0:case(c)0:letter="R";1:letter="E";2:letter="A";3:letter="D";4:letter="Y";default:;endcase
                1:case(c)0:letter="S";1:letter="C";2:letter="A";3:letter="N";default:;endcase
                2:case(c)0:letter="D";1:letter="R";2:letter="A";3:letter="W";default:;endcase
                3:case(c)0:letter="D";1:letter="O";2:letter="N";3:letter="E";default:;endcase
                4:case(c)0:letter="E";3:letter="O";1,2,4:letter="R";default:;endcase
                default:;
            endcase
        end
    endfunction
    function [4:0] font;
        input [7:0] c;input [2:0] row;
        begin
            font=0;
            if(row<7)case(c)
                "A":case(row)0:font=14;3:font=31;default:font=17;endcase
                "C":case(row)0,6:font=14;1,5:font=17;default:font=16;endcase
                "D":case(row)0,6:font=30;default:font=17;endcase
                "E":case(row)0,6:font=31;3:font=30;default:font=16;endcase
                "N":case(row)2:font=25;3:font=21;4:font=19;default:font=17;endcase
                "O":case(row)0,6:font=14;default:font=17;endcase
                "R":case(row)0,3:font=30;4:font=20;5:font=18;default:font=17;endcase
                "S":case(row)0,3,6:font=14;1,2:font=16;default:font=1;endcase
                "W":case(row)4,5:font=21;6:font=10;default:font=17;endcase
                "Y":case(row)0,1:font=17;2:font=10;default:font=4;endcase
                default:;
            endcase
        end
    endfunction
    (* ram_style="bram" *) reg glyph[0:4095];
    integer i;reg [4:0] row_bits;
    initial for(i=0;i<4096;i=i+1)begin
        row_bits=font(letter(i[11:9],i[8:6]),i[5:3]);
        glyph[i]=(i[2:0]>=1&&i[2:0]<=5)?row_bits[5-i[2:0]]:1'b0;
    end
    wire label=enable&&x>=32&&x<112&&y>=96&&y<112;
    wire guide=enable&&x>=430&&x<850&&y>=64&&y<658&&
        (x<432||x>=848||y<66||y>=656);
    wire [11:0] dx=x-32,dy=y-96;
    reg label_s,guide_s,glyph_q,guide_q,label_q;
    reg [2:0] state_s,state_q;
    reg [11:0] glyph_addr;
    always @(posedge clk)glyph_q<=glyph[glyph_addr];
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            label_s<=0;guide_s<=0;state_s<=0;glyph_addr<=0;
            hit<=0;label_q<=0;guide_q<=0;state_q<=0;
        end else begin
            label_s<=label;guide_s<=guide;state_s<=state;
            glyph_addr<={state,dx[6:4],dy[3:1],dx[3:1]};
            hit<=label_s||guide_s;label_q<=label_s;guide_q<=guide_s;state_q<=state_s;
        end
    end
    wire [23:0] ink=(state_q==4)?24'hff6050:(state_q==3)?24'h60ff80:24'h60ffff;
    assign color=guide_q?24'h60ffff:(glyph_q?ink:24'h001018);
endmodule
