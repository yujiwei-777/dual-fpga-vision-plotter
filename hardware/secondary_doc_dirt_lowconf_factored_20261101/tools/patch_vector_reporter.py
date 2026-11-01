from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'01_rtl/grbl_reporter.v'
s=p.read_text()
s=s.replace('R_NPREFLIGHT_MARK=60,R_FONT_WAIT=61,R_GLYPH_CAPTURE=62;', 'R_NPREFLIGHT_MARK=60,R_FONT_WAIT=61,R_GLYPH_CAPTURE=62,\n                     R_VSET=63,R_VMUL=64,R_VEMIT=65,R_VTRAVEL=66,R_VLIFT=67;')
s=s.replace('localparam [5:0] R_IDLE','localparam [6:0] R_IDLE').replace('reg [5:0] state,next_after_line','reg [6:0] state,next_after_line')
s=s.replace('reg [2:0] row,column,stroke_start;', '''reg [2:0] row,column;
    reg [3:0] stroke_start;
    reg vector_new_glyph,font_pen_down;
    reg [7:0] vector_x0_unit,vector_y0_unit,vector_x1_unit,vector_y1_unit;
    reg [1:0] vector_coord;
    reg [15:0] vector_y_start,font_last_x,font_last_y;
    wire [2:0] font_x0,font_y0,font_x1,font_y1;''')
s=s.replace('grbl_vector_font_rom #(.SYNC_ROM(1)) u_font(.I_clk(I_clk),.I_char(character),.I_row(row),.O_pixels(font_pixels),\n        .O_segment_count(font_segment_count),.O_advance_width(font_advance_width));', '''grbl_vector_font_rom #(.SYNC_ROM(1)) u_font(.I_clk(I_clk),.I_char(character),.I_row(row),.O_pixels(font_pixels),
        .O_segment_count(font_segment_count),.O_advance_width(font_advance_width),.I_segment(stroke_start),
        .O_x0(font_x0),.O_y0(font_y0),.O_x1(font_x1),.O_y1(font_y1));''')
s=s.replace('glyph_index<=0;last_glyph<=14;row<=0;column<=0;stroke_start<=0;', '''glyph_index<=0;last_glyph<=14;row<=0;column<=0;stroke_start<=0;
            vector_new_glyph<=1;font_pen_down<=0;vector_x0_unit<=0;vector_y0_unit<=0;
            vector_x1_unit<=0;vector_y1_unit<=0;vector_coord<=0;vector_y_start<=0;font_last_x<=0;font_last_y<=0;''')
s=s.replace('line_last<=0;maze_job<=requested_maze;maze_route<=0;', 'line_last<=0;maze_job<=requested_maze;maze_route<=0;vector_new_glyph<=1;font_pen_down<=0;stroke_start<=0;')
s=s.replace(':R_SCAN;', ':R_GLYPH;')
a=s.index('                R_GLYPH:state<=R_GLYPH_CAPTURE;')
b=s.index('                R_DOWN:begin',a)
s=s[:a]+'''                // Only the glyph's disconnected polylines lift the pen.
                // Joined segments and closed loops keep a continuous G1 path.
                R_GLYPH:begin
                    if(vector_new_glyph)state<=R_GLYPH_CAPTURE;
                    else if(stroke_start<font_segment_count)state<=R_FONT;
                    else if(font_pen_down)begin font_pen_down<=0;state<=R_UP;end
                    else begin
                        stroke_start<=0;vector_new_glyph<=1;
                        if(glyph_index==last_glyph)begin
                            if(report_line==defect_count+3'd1)
                                state<=(judgement==2&&defect_count!=0)?R_DLOAD:R_FINALUP;
                            else begin
                                report_line<=report_line+1'b1;glyph_index<=0;
                                last_glyph<=(report_line==0)?5'd8:5'd21;state<=R_GLYPH;
                            end
                        end else begin glyph_index<=glyph_index+1'b1;state<=R_GLYPH;end
                    end
                end
                R_GLYPH_CAPTURE:begin character<=decoded_char;stroke_start<=0;vector_new_glyph<=0;state<=R_FONT;end
                R_FONT:state<=R_FONT_WAIT;
                R_FONT_WAIT:begin
                    if(font_segment_count==0)state<=R_GLYPH;
                    else begin
                        vector_x0_unit<=({3'd0,glyph_index}<<2)+({3'd0,glyph_index}<<1)+font_x0;
                        vector_x1_unit<=({3'd0,glyph_index}<<2)+({3'd0,glyph_index}<<1)+font_x1;
                        vector_y0_unit<=({5'd0,report_line}<<3)+({5'd0,report_line}<<1)+font_y0;
                        vector_y1_unit<=({5'd0,report_line}<<3)+({5'd0,report_line}<<1)+font_y1;
                        vector_coord<=0;state<=R_VSET;
                    end
                end
                R_VSET:begin
                    // Reuse the existing serial defect-map multiplier. No
                    // parallel endpoint multipliers or floating point added.
                    map_acc<=0;map_term<={17'd0,step};map_bit<=0;
                    case(vector_coord)
                        0:map_factor<={3'd0,vector_x0_unit};
                        1:map_factor<={3'd0,vector_y0_unit};
                        2:map_factor<={3'd0,vector_x1_unit};
                        default:map_factor<={3'd0,vector_y1_unit};
                    endcase
                    state<=R_VMUL;
                end
                R_VMUL:begin
                    if(map_bit==7)begin
                        case(vector_coord)
                            0:x_start<=origin_x+map_sum[15:0];
                            1:vector_y_start<=origin_y+map_sum[15:0];
                            2:x_end<=origin_x+map_sum[15:0];
                            default:y_pos<=origin_y+map_sum[15:0];
                        endcase
                        if(vector_coord==3)state<=R_VEMIT;
                        else begin vector_coord<=vector_coord+1'b1;state<=R_VSET;end
                    end else begin map_acc<=map_sum;map_term<=map_term<<1;map_factor<=map_factor>>1;map_bit<=map_bit+1'b1;end
                end
                R_VEMIT:begin
                    // Safety is checked before both the G0 segment start and
                    // its G1 endpoint. X mirroring remains formatter-only.
                    if(x_start>work_x||x_end>work_x||vector_y_start>work_y||y_pos>work_y||
                       x_start<origin_x||x_end<origin_x||vector_y_start<origin_y||y_pos<origin_y)begin
                        newline_fault<=1;state<=R_IDLE;
                    end else if(font_pen_down && font_last_x==x_start && font_last_y==vector_y_start)state<=R_DRAW;
                    else if(font_pen_down)state<=R_VLIFT;
                    else state<=R_VTRAVEL;
                end
                R_VLIFT:begin
                    fmt_kind<=pen_pwm?3:2;fmt_z<=pen_up;fmt_pwm<=up_pwm;fmt_feed<=pen_feed;
                    fmt_start<=1;font_pen_down<=0;next_after_line<=R_VTRAVEL;state<=R_FORMAT;
                end
                R_VTRAVEL:begin
                    fmt_kind<=0;fmt_x<=x_start;fmt_y<=vector_y_start;fmt_feed<=travel_feed;
                    fmt_start<=1;next_after_line<=R_DOWN;state<=R_FORMAT;
                end
                R_SCAN:state<=R_GLYPH;
''' + s[b:]
s=s.replace('fmt_start<=1;next_after_line<=R_UP;state<=R_FORMAT;\n                end\n                R_MINIT', '''fmt_start<=1;stroke_start<=stroke_start+1'b1;font_pen_down<=1;
                    font_last_x<=x_end;font_last_y<=y_pos;next_after_line<=R_GLYPH;state<=R_FORMAT;
                end
                R_MINIT''')
p.write_text(s)
print('patched reporter:',p)
