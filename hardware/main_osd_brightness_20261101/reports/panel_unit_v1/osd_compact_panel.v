// Compact Chinese OSD only; all numerical inputs are already packed BCD.
// s1 emits the shared synchronous font ROM address.  At s2 the ROM output
// and the pixel column/valid/color refer to the same original x/y sample.
`include "osd_compact_glyphs.vh"
module osd_compact_panel(
    input wire clk, rst_n,
    input wire [11:0] x,y,
    input wire pcb_mode,
    input wire [2:0] pcb_status,
    input wire [4:0] algo_mode,
    input wire he_on,lat_valid,lat_overflow,
    input wire [19:0] frame_bcd,
    input wire [15:0] lat_bcd,target_x_bcd,target_y_bcd,
    input wire [23:0] area_bcd,
    input wire remote,ovl_valid,
    input wire [1:0] target_color,shape3,
    input wire target_shape,motion_enable,
    input wire [19:0] motion_bcd,
    output wire panel_on,panel_border,text_on,
    output wire [23:0] text_color,
    output wire [7:0] font_glyph,
    output wire [3:0] font_row,
    input wire [15:0] font_row_bits
);
    localparam [23:0] C_LABEL=24'h62e5ea,C_NUMBER=24'hffe070,
        C_MODE=24'hca9aff,C_GOOD=24'h70f080,C_WAIT=24'hffd060,
        C_BAD=24'hff6060,C_RED=24'hff7070,C_GREEN=24'h70ef90,
        C_BLUE=24'h80b8ff;
    reg panel_c,border_c,valid_c;
    reg [7:0] glyph_c;
    reg [3:0] row_c,col_c;
    reg [23:0] color_c;
    reg [11:0] local_x,local_y;
    reg [4:0] cell_idx;
    reg [2:0] line;
    reg pcb_text;
    reg panel_s1,border_s1,valid_s1;
    reg [7:0] glyph_s1;
    reg [3:0] row_s1,col_s1;
    reg [23:0] color_s1;
    reg panel_s2,border_s2,valid_s2;
    reg [3:0] col_s2;
    reg [23:0] color_s2;

    function [7:0] digit;
        input [3:0] nibble;
        begin digit=(nibble<10)?(8'h30+{4'd0,nibble}):8'h3f; end
    endfunction

    // These names retain the existing 0..18 algorithm-mode meanings.
    function [7:0] mode_char;
        input [4:0] mode;
        input second;
        begin
            case(mode)
                0:mode_char=second?`OSD_CN_U56FE:`OSD_CN_U539F; // original
                1:mode_char=second?`OSD_CN_U5EA6:`OSD_CN_U7070; // grayscale
                2:mode_char=second?`OSD_CN_U503C:`OSD_CN_U9608; // threshold
                3:mode_char=second?`OSD_CN_U8272:`OSD_CN_U53CD; // invert
                4:mode_char=second?`OSD_CN_U8272:`OSD_CN_U51CF; // reduced color
                5:mode_char=second?`OSD_CN_U9636:`OSD_CN_U8272; // posterize
                6:mode_char=second?`OSD_CN_U548C:`OSD_CN_U9971; // saturation
                7:mode_char=second?`OSD_CN_U7F18:`OSD_CN_U8FB9; // Sobel
                8:mode_char=second?`OSD_CN_U8FB9:`OSD_CN_U9510; // edge processing
                9:mode_char=second?`OSD_CN_U96D5:`OSD_CN_U6D6E; // emboss
                10:mode_char=second?`OSD_CN_U8679:`OSD_CN_U5F69; // rainbow
                11:mode_char=second?`OSD_CN_U8680:`OSD_CN_U8150; // erode
                12:mode_char=second?`OSD_CN_U80C0:`OSD_CN_U81A8; // dilate
                13:mode_char=second?`OSD_CN_U6001:`OSD_CN_U5F62; // morphology
                14:mode_char=second?`OSD_CN_U8272:`OSD_CN_U84DD; // blue
                15:mode_char=second?`OSD_CN_U4EAE:`OSD_CN_U63D0; // lift
                16:mode_char=second?`OSD_CN_U6BD4:`OSD_CN_U5BF9; // contrast
                17:mode_char=second?`OSD_CN_U9A6C:`OSD_CN_U4F3D; // gamma
                18:mode_char=second?`OSD_CN_U901A:`OSD_CN_U5361; // cartoon
                default:mode_char=second?"?":"?";
            endcase
        end
    endfunction

    function [7:0] status_char;
        input [2:0] st;
        input [4:0] pos;
        begin
            status_char=" ";
            case(st)
                0:case(pos) 0:status_char=`OSD_CN_U5C31;1:status_char=`OSD_CN_U7EEA;endcase
                1:case(pos) 0:status_char=`OSD_CN_U626B;1:status_char=`OSD_CN_U63CF;endcase
                2:case(pos) 0:status_char=`OSD_CN_U901A;1:status_char=`OSD_CN_U8FC7;endcase
                3:case(pos) 0:status_char=`OSD_CN_U5931;1:status_char=`OSD_CN_U8D25;endcase
                4:case(pos) 0:status_char=`OSD_CN_U590D;1:status_char=`OSD_CN_U6838;endcase
                5:case(pos) 0:status_char=`OSD_CN_U65E0;1:status_char=`OSD_CN_U76EE;2:status_char=`OSD_CN_U6807;endcase
                6:case(pos) 0:status_char=`OSD_CN_U7B49;1:status_char=`OSD_CN_U5F85;2:status_char=`OSD_CN_U5C31;3:status_char=`OSD_CN_U7EEA;endcase
                7:case(pos) 0:status_char=`OSD_CN_U94FE;1:status_char=`OSD_CN_U8DEF;2:status_char=`OSD_CN_U9519;3:status_char=`OSD_CN_U8BEF;endcase
            endcase
        end
    endfunction

    always @(*) begin
        panel_c=0;border_c=0;valid_c=0;glyph_c=" ";row_c=0;col_c=0;
        color_c=C_LABEL;local_x=0;local_y=0;cell_idx=0;line=7;pcb_text=0;
        if(!pcb_mode && x>=864 && x<1200 && y>=64 && y<(motion_enable?192:168)) begin
            panel_c=1;local_x=x-864;local_y=y-64;
            border_c=(x==864 || x==1199 || y==64 || y==(motion_enable?191:167));
            cell_idx=local_x[8:4];col_c=local_x[3:0];
            if(local_y>=8 && local_y<24) begin line=0;row_c=local_y-8;end
            else if(local_y>=32 && local_y<48) begin line=1;row_c=local_y-32;end
            else if(local_y>=56 && local_y<72) begin line=2;row_c=local_y-56;end
            else if(local_y>=80 && local_y<96) begin line=3;row_c=local_y-80;end
            else if(motion_enable && local_y>=104 && local_y<120) begin line=4;row_c=local_y-104;end
            valid_c=(line!=7);
        end else if(pcb_mode && x>=24 && x<312 && y>=584 && y<680) begin
            pcb_text=1;panel_c=1;local_x=x-24;local_y=y-584;
            border_c=(x==24 || x==311 || y==584 || y==679);
            cell_idx=local_x[8:4];col_c=local_x[3:0];
            if(local_y>=8 && local_y<24) begin line=0;row_c=local_y-8;end
            else if(local_y>=40 && local_y<56) begin line=1;row_c=local_y-40;end
            else if(local_y>=72 && local_y<88) begin line=2;row_c=local_y-72;end
            valid_c=(line!=7);
        end
        if(pcb_text) begin
            case(line)
                0:begin
                    color_c=C_MODE;
                    case(cell_idx) 0:glyph_c=`OSD_CN_U7535;1:glyph_c=`OSD_CN_U8DEF;2:glyph_c=`OSD_CN_U677F;3:glyph_c=`OSD_CN_U6A21;4:glyph_c=`OSD_CN_U5F0F;endcase
                end
                1:case(cell_idx)
                    0:glyph_c=`OSD_CN_U6309;1:glyph_c="K";2:glyph_c="E";3:glyph_c="Y";4:glyph_c="4";
                    5:glyph_c=`OSD_CN_U68C0;6:glyph_c=`OSD_CN_U6D4B;
                endcase
                2:begin
                    glyph_c=status_char(pcb_status,cell_idx);
                    case(pcb_status)
                        0,2:color_c=C_GOOD;
                        3,7:color_c=C_BAD;
                        default:color_c=C_WAIT;
                    endcase
                end
            endcase
        end else begin
            case(line)
                0:begin
                    case(cell_idx)
                        0:glyph_c=`OSD_CN_U5E27;1:glyph_c=":";
                        2:glyph_c=lat_valid?digit(frame_bcd[19:16]):"-";
                        3:glyph_c=lat_valid?digit(frame_bcd[15:12]):"-";
                        4:glyph_c=lat_valid?digit(frame_bcd[11:8]):"-";
                        5:glyph_c=lat_valid?digit(frame_bcd[7:4]):"-";
                        6:glyph_c=lat_valid?digit(frame_bcd[3:0]):"-";
                        8:glyph_c=`OSD_CN_U5EF6;9:glyph_c=`OSD_CN_U8FDF;10:glyph_c=":";
                        11:glyph_c=!lat_valid?"N":lat_overflow?"O":digit(lat_bcd[15:12]);
                        12:glyph_c=!lat_valid?"/":lat_overflow?"V":digit(lat_bcd[11:8]);
                        13:glyph_c=!lat_valid?"A":lat_overflow?"F":digit(lat_bcd[7:4]);
                        14:glyph_c=(lat_valid&&!lat_overflow)?".":" ";
                        15:glyph_c=(lat_valid&&!lat_overflow)?digit(lat_bcd[3:0]):" ";
                        16:glyph_c=(lat_valid&&!lat_overflow)?"M":" ";17:glyph_c=(lat_valid&&!lat_overflow)?"S":" ";
                    endcase
                    if((cell_idx>=2&&cell_idx<=6)||(cell_idx>=11)) color_c=C_NUMBER;
                end
                1:begin
                    case(cell_idx)
                        0:glyph_c=`OSD_CN_U6A21;1:glyph_c=`OSD_CN_U5F0F;2:glyph_c=":";
                        3:glyph_c=mode_char(algo_mode,0);4:glyph_c=mode_char(algo_mode,1);
                        7:glyph_c=`OSD_CN_U76F4;8:glyph_c=`OSD_CN_U65B9;9:glyph_c=`OSD_CN_U56FE;10:glyph_c=":";
                        11:glyph_c=he_on?"O":"O";12:glyph_c=he_on?"N":"F";13:glyph_c=he_on?" ":"F";
                    endcase
                    if(cell_idx>=3&&cell_idx<=4) color_c=C_MODE;
                    else if(cell_idx>=11) color_c=he_on?C_GOOD:C_WAIT;
                end
                2:begin
                    case(cell_idx)
                        0:glyph_c="X";1:glyph_c=":";
                        2:glyph_c=digit(target_x_bcd[15:12]);3:glyph_c=digit(target_x_bcd[11:8]);
                        4:glyph_c=digit(target_x_bcd[7:4]);5:glyph_c=digit(target_x_bcd[3:0]);
                        6:glyph_c="Y";7:glyph_c=":";
                        8:glyph_c=digit(target_y_bcd[15:12]);9:glyph_c=digit(target_y_bcd[11:8]);
                        10:glyph_c=digit(target_y_bcd[7:4]);11:glyph_c=digit(target_y_bcd[3:0]);
                        12:glyph_c=`OSD_CN_U9762;13:glyph_c=":";
                        14:glyph_c=digit(area_bcd[23:20]);15:glyph_c=digit(area_bcd[19:16]);
                        16:glyph_c=digit(area_bcd[15:12]);17:glyph_c=digit(area_bcd[11:8]);
                        18:glyph_c=digit(area_bcd[7:4]);19:glyph_c=digit(area_bcd[3:0]);
                    endcase
                    if((cell_idx>=2&&cell_idx<=5)||(cell_idx>=8&&cell_idx<=11)||(cell_idx>=14&&cell_idx<=19)) color_c=C_NUMBER;
                end
                3:begin
                    case(cell_idx)
                        0:glyph_c=remote?`OSD_CN_U8FDC:`OSD_CN_U672C;1:glyph_c=remote?`OSD_CN_U7A0B:`OSD_CN_U5730;2:glyph_c=":";
                        3:glyph_c=!ovl_valid?`OSD_CN_U65E0:(target_color==0?`OSD_CN_U7EA2:target_color==1?`OSD_CN_U7EFF:`OSD_CN_U84DD);
                        5:glyph_c=!ovl_valid?`OSD_CN_U76EE:(remote?(shape3==1?`OSD_CN_U4E09:shape3==2?`OSD_CN_U5706:`OSD_CN_U6B63):(target_shape?`OSD_CN_U6591:`OSD_CN_U77E9));
                        6:glyph_c=!ovl_valid?`OSD_CN_U6807:(remote?(shape3==1?`OSD_CN_U89D2:shape3==2?`OSD_CN_U5F62:`OSD_CN_U65B9):(target_shape?`OSD_CN_U5757:`OSD_CN_U5F62));
                        7:glyph_c=(ovl_valid&&remote&&shape3!=1&&shape3!=2)?`OSD_CN_U5F62:" ";
                        10:glyph_c=ovl_valid?`OSD_CN_U9501:`OSD_CN_U4E22;11:glyph_c=ovl_valid?`OSD_CN_U5B9A:`OSD_CN_U5931;
                    endcase
                    if(cell_idx==3&&ovl_valid) color_c=(target_color==0)?C_RED:(target_color==1)?C_GREEN:C_BLUE;
                    else if(cell_idx>=5) color_c=ovl_valid?C_GOOD:C_WAIT;
                end
                4:begin
                    case(cell_idx)
                        0:glyph_c=`OSD_CN_U8FD0;1:glyph_c=`OSD_CN_U52A8;2:glyph_c=`OSD_CN_U8BA1;3:glyph_c=`OSD_CN_U6570;4:glyph_c=":";
                        5:glyph_c=digit(motion_bcd[19:16]);6:glyph_c=digit(motion_bcd[15:12]);7:glyph_c=digit(motion_bcd[11:8]);
                        8:glyph_c=digit(motion_bcd[7:4]);9:glyph_c=digit(motion_bcd[3:0]);
                    endcase
                    if(cell_idx>=5) color_c=C_NUMBER;
                end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            panel_s1<=0;border_s1<=0;valid_s1<=0;glyph_s1<=" ";row_s1<=0;col_s1<=0;color_s1<=0;
            panel_s2<=0;border_s2<=0;valid_s2<=0;col_s2<=0;color_s2<=0;
        end else begin
            panel_s1<=panel_c;border_s1<=border_c;valid_s1<=valid_c;glyph_s1<=glyph_c;
            row_s1<=row_c;col_s1<=col_c;color_s1<=color_c;
            panel_s2<=panel_s1;border_s2<=border_s1;valid_s2<=valid_s1;col_s2<=col_s1;color_s2<=color_s1;
        end
    end
    assign font_glyph=glyph_s1;
    assign font_row=row_s1;
    assign panel_on=panel_s2;
    assign panel_border=border_s2;
    assign text_on=valid_s2&&font_row_bits[15-col_s2];
    assign text_color=color_s2;
endmodule
