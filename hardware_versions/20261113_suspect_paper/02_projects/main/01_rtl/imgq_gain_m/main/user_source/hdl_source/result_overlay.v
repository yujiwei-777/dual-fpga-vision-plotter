// Independent pipelined recognition badge overlay.
// class_id: 1..9 = RED/GREEN/BLUE x TRI/CIRC/SQR.  Local results are
// rule-based; a connected secondary board may replace them with its CNN
// result at the frame boundary.
(* keep_hierarchy = "yes" *)
module result_overlay #(
    parameter integer IMG_WIDTH=1280,
    parameter integer IMG_HEIGHT=720,
    parameter integer EDGE=3,
    parameter integer BADGE_W=128,
    parameter integer BADGE_H=16,
    // Optional pipeline diagnostic row.  It is deliberately disabled by
    // default so existing designs keep exactly the original overlay.
    parameter integer DIAGNOSTIC_ENABLE=0,
    // The mixer owns the persistent PCB status row and fixed window. Hide
    // an older latched badge immediately on PCB mode entry, even without
    // a new result toggle. Default preserves all other project instances.
    parameter integer HIDE_PCB_BADGE=0
)(
    input wire I_clk, input wire I_rst_n,
    input wire [23:0] I_video_rgb,
    input wire I_video_de, input wire I_video_hs, input wire I_video_vs,
    input wire I_video_user, input wire I_video_last,
    input wire I_enable, input wire I_valid,
    input wire [10:0] I_x0, input wire [10:0] I_x1, input wire [10:0] I_cx,
    input wire [9:0] I_y0, input wire [9:0] I_y1, input wire [9:0] I_cy,
    input wire I_remote,input wire [1:0] I_color,I_shape,
    input wire I_pcb_mode,I_pcb_checked,I_pcb_good,
    input wire [3:0] I_class_id,
    input wire [7:0] I_confidence,
    input wire [3:0] I_conf_hundreds, input wire [3:0] I_conf_tens, input wire [3:0] I_conf_ones,
    input wire I_toggle,
    // Sticky pipeline status, bit 0 is rendered at the left-most square.
    input wire [7:0] I_pipeline_status,
    // Main-board A4 distance status.  BCD is millimetres, four nibbles
    // {thousands,hundreds,tens,ones}; the row is rendered only in SW=11.
    input wire        I_distance_mode,
    input wire        I_distance_valid,
    input wire [15:0] I_distance_bcd,
    input wire        I_distance_toggle,
    output reg [23:0] O_video_rgb,
    output reg O_video_de, output reg O_video_hs, output reg O_video_vs,
    output reg O_video_user, output reg O_video_last
);
    reg [10:0] px,x0_r,x1_r,cx_r;
    reg [9:0] py,y0_r,y1_r,cy_r;
    reg [3:0] cls_r,conf_h_r,conf_t_r,conf_o_r;
    reg valid_r,toggle_r,remote_r;
    reg [1:0] color_r,shape_r;
    reg pcb_r,checked_r,good_r;
    reg [15:0] distance_bcd_r;
    reg distance_valid_r,distance_toggle_r;
    wire [10:0] badge_x=(x0_r>(IMG_WIDTH-BADGE_W))?(IMG_WIDTH-BADGE_W):x0_r;
    wire [9:0] badge_y0=(y0_r>=BADGE_H)?y0_r-BADGE_H:y0_r;
    wire [9:0] badge_y_below=(y1_r+1<IMG_HEIGHT)?y1_r+1:y1_r;
    wire osd_x_overlap=(badge_x<1200)&&((badge_x+BADGE_W)>864);
    // Keep recognition badges outside the compact Chinese status panel.
    wire osd_overlap=(osd_x_overlap&&(badge_y0<192)&&((badge_y0+BADGE_H)>64));
    wire osd_below_overlap=(osd_x_overlap&&(badge_y_below<192)&&((badge_y_below+BADGE_H)>64));
    wire [9:0] badge_y=(osd_overlap && (y1_r+BADGE_H+1<IMG_HEIGHT) && !osd_below_overlap)?badge_y_below:badge_y0;
    // The mixer remains the owner of the target/motion boxes and center
    // cross.  This module only contributes the recognition badge, so it
    // cannot overwrite the established overlay priority.
    wire protected_area=((px<12'd8)&&(py<12'd8)) ||
                        ((px>=12'd864)&&(px<12'd1200)&&(py>=12'd64)&&(py<12'd192));

    // A4 distance row is drawn after the proven HDMI mixer, so it does not
    // lengthen the mixer timing path. The row reads "A4:052.4CM EST" when a
    // valid measurement is latched, or "A4:NO A4" after an invalid capture.
    wire distance_area = I_distance_mode && I_video_de &&
                         (px>=12'd880) && (px<12'd1200) &&
                         (py>=12'd160) && (py<12'd192);
    wire [8:0] distance_dx = px-12'd880;
    wire [4:0] distance_cell = distance_dx[8:4];
    wire [2:0] distance_col = distance_dx[3:1];
    wire [2:0] distance_row = (py-12'd160)>>1;
    reg [7:0] distance_ascii;
    reg [4:0] distance_bits;
    reg distance_glyph;
    reg distance_hit_p1,distance_hit_s1;
    reg [23:0] distance_color_p1,distance_color_s1;
    wire badge_area=valid_r&&(!HIDE_PCB_BADGE || !I_pcb_mode)&&I_video_de&&!protected_area&&
                    (px>=badge_x)&&(px<badge_x+BADGE_W)&&
                    (py>=badge_y)&&(py<badge_y+BADGE_H);
    wire [6:0] bdx=px-badge_x;
    wire [3:0] bchar=bdx[6:3];
    wire [2:0] bcol=bdx[2:0];
    wire [3:0] brow=py-badge_y;
    reg [7:0] ascii;
    reg [4:0] bits;
    reg glyph_hit;
    reg glyph_border;
    // Saturated foreground colours remain legible over both dark and bright
    // camera content.  The badge itself has an opaque navy panel and a thin
    // border, so the 5x7 glyphs do not disappear into the image.
    wire [23:0] cls_rgb=pcb_r ? (!checked_r?24'hffff40:good_r?24'h50ff50:24'hff6060) : (color_r==1)?24'hff6060:(color_r==2)?24'h50ff50:(color_r==3)?24'h70a0ff:24'hffffff;
    // Stage the expensive character decode separately from the output mux.
    // This keeps the 75 MHz HDMI output path short even with the 5x7 ROM.
    //
    // The geometry/character path is deliberately split into two stages:
    //   raw video + current result -> *_p1 (geometry capture)
    //   *_p1 -> *_s1 (font decode and overlay decision)
    // The old implementation drove glyph_hit directly from x0_r through
    // badge_x/bchar, the character mux and font ROM.  That made one
    // x0_r->badge_hit_s1 path exceed the HDMI pixel-clock period.  Keeping
    // the timing, RGB and decision registers in the same two stages preserves
    // pixel alignment while giving the mapper a short first stage.
    reg [23:0] rgb_p1;
    reg de_p1, hs_p1, vs_p1, user_p1, last_p1;
    reg badge_area_p1, badge_border_p1;
    reg diag_hit_p1;
    reg [23:0] diag_color_p1;
    reg [6:0] bchar_p1;
    reg [2:0] bcol_p1;
    reg [3:0] brow_p1;
    reg [1:0] color_p1, shape_p1;
    reg pcb_p1, checked_p1, good_p1;
    reg [3:0] conf_h_p1, conf_t_p1, conf_o_p1;
    wire [23:0] cls_rgb_p1=pcb_p1 ? (!checked_p1?24'hffff40:good_p1?24'h50ff50:24'hff6060) : (color_p1==1)?24'hff6060:(color_p1==2)?24'h50ff50:(color_p1==3)?24'h70a0ff:24'hffffff;

    reg [23:0] rgb_s1, badge_color_s1;
    reg de_s1, hs_s1, vs_s1, user_s1, last_s1;
    reg badge_hit_s1, badge_area_s1, badge_border_s1;
    reg diag_hit_s1;
    reg [23:0] diag_color_s1;

    // Eight 16x16 indicators at the bottom of a 1280x720 frame.  The
    // 2-pixel gap makes each state easy to distinguish on a live screen.
    // The last square ends at x=157 (16 + 8*16 + 7*2 - 1).
    localparam integer DIAG_X0 = 16;
    localparam integer DIAG_Y0 = 680;
    localparam integer DIAG_STEP = 18;
    wire diag_row = (py >= DIAG_Y0) && (py < (DIAG_Y0 + 16));
    // Explicit ranges avoid a variable divide/modulo in the pixel path.
    wire diag_col = ((px >= 11'd16)  && (px < 11'd32))  ||
                    ((px >= 11'd34)  && (px < 11'd50))  ||
                    ((px >= 11'd52)  && (px < 11'd68))  ||
                    ((px >= 11'd70)  && (px < 11'd86))  ||
                    ((px >= 11'd88)  && (px < 11'd104)) ||
                    ((px >= 11'd106) && (px < 11'd122)) ||
                    ((px >= 11'd124) && (px < 11'd140)) ||
                    ((px >= 11'd142) && (px < 11'd158));
    wire diag_area = (DIAGNOSTIC_ENABLE != 0) && I_video_de && diag_row && diag_col;
    wire [2:0] diag_idx = (px < 11'd34)  ? 3'd0 :
                          (px < 11'd52)  ? 3'd1 :
                          (px < 11'd70)  ? 3'd2 :
                          (px < 11'd88)  ? 3'd3 :
                          (px < 11'd106) ? 3'd4 :
                          (px < 11'd124) ? 3'd5 :
                          (px < 11'd142) ? 3'd6 : 3'd7;
    wire [23:0] diag_color = I_pipeline_status[diag_idx] ? 24'h00ff00 : 24'h600000;

    function [4:0] font5;
      input [7:0] ch; input [2:0] row;
      begin
        case(ch)
          "R": case(row) 0:font5=5'b11110;1:font5=5'b10001;2:font5=5'b10001;3:font5=5'b11110;4:font5=5'b10100;5:font5=5'b10010;default:font5=5'b10001; endcase
          "E": case(row) 0,3,6:font5=5'b11111;1,2,4,5:font5=5'b10000;default:font5=0; endcase
          "D": case(row) 0:font5=5'b11110;1,2,3,4,5:font5=5'b10001;default:font5=5'b11110; endcase
          "G": case(row) 0:font5=5'b01110;1,2:font5=5'b10000;3:font5=5'b10111;4,5:font5=5'b10001;default:font5=5'b01110; endcase
          "N": case(row) 0:font5=5'b10001;1:font5=5'b11001;2:font5=5'b10101;3:font5=5'b10011;4,5,6:font5=5'b10001; endcase
          "B": case(row) 0:font5=5'b11110;1,2:font5=5'b10001;3:font5=5'b11110;4,5:font5=5'b10001;default:font5=5'b11110; endcase
          "L": case(row) 0,1,2,3,4,5:font5=5'b10000;default:font5=5'b11111; endcase
          "U": case(row) 0,1,2,3,4,5:font5=5'b10001;default:font5=5'b01110; endcase
          "O": case(row) 0,6:font5=5'b01110;1,2,3,4,5:font5=5'b10001; endcase
          "C": case(row) 0,6:font5=5'b01110;1,2,3,4,5:font5=5'b10000; endcase
          "M": case(row) 0:font5=5'b10001;1:font5=5'b11011;2:font5=5'b10101;3,4,5,6:font5=5'b10001; endcase
          ":": case(row) 2,4:font5=5'b00100;default:font5=5'b00000; endcase
          "T": case(row) 0:font5=5'b11111;default:font5=5'b00100; endcase
          "0": case(row) 0,6:font5=5'b01110;1,2,3,4,5:font5=5'b10001; endcase
          "1": case(row) 0:font5=5'b00100;1:font5=5'b01100;2,3,4,5,6:font5=5'b00100; endcase
          "2": case(row) 0,3,6:font5=5'b11111;1,2:font5=5'b00001;4,5:font5=5'b10000; endcase
          "3": case(row) 0,3,6:font5=5'b11111;1,2,4,5:font5=5'b00001; endcase
          "4": case(row) 0,1,2:font5=5'b10010;3:font5=5'b11111;4,5,6:font5=5'b00010; endcase
          "5": case(row) 0,3,6:font5=5'b11111;1,2:font5=5'b10000;4,5:font5=5'b00001; endcase
          "6": case(row) 0,3,6:font5=5'b01110;1,2:font5=5'b10000;4,5:font5=5'b10001; endcase
          "7": case(row) 0:font5=5'b11111;1,2,3,4,5,6:font5=5'b00001; endcase
          "8": case(row) 0,3,6:font5=5'b01110;1,2,4,5:font5=5'b10001; endcase
          "9": case(row) 0,3,6:font5=5'b01110;1,2:font5=5'b10001;4,5:font5=5'b00001; endcase
          "%": case(row) 0,2:font5=5'b11001;1:font5=5'b11010;3:font5=5'b00100;4:font5=5'b01000;5,6:font5=5'b10011; endcase
          "P": case(row)0,3:font5=5'b11110;1,2:font5=5'b10001;default:font5=5'b10000;endcase
          "A": case(row)0:font5=5'b01110;3:font5=5'b11111;default:font5=5'b10001;endcase
          "F": case(row)0,3:font5=5'b11111;default:font5=5'b10000;endcase
          "V": case(row)0,1,2,3:font5=5'b10001;4,5:font5=5'b01010;default:font5=5'b00100;endcase
          "W": case(row)0,1,2,3:font5=5'b10001;4,5:font5=5'b10101;default:font5=5'b01010;endcase
          "I": case(row) 0,6:font5=5'b11111;default:font5=5'b00100;endcase
          "S": case(row) 0,3,6:font5=5'b01110;1,2:font5=5'b10000;default:font5=5'b00001;endcase
          "Q": case(row) 0:font5=5'b01110;1,2,3:font5=5'b10001;4:font5=5'b10101;5:font5=5'b10010;default:font5=5'b01101;endcase
          default: font5=0;
        endcase
      end
    endfunction

    // Decode one shape enum for both sources.  The local classifier and the
    // secondary-board CNN use the same TRI/CIRC/SQR encoding, so the label
    // remains stable when the link comes and goes.
    reg [3:0] name_len,shape_len,relative_char;
    reg [31:0] shape_text;
    always @* begin
      name_len=(color_p1==1)?3:(color_p1==2)?5:4;
      shape_len=(shape_p1==2)?4:3;
      case(shape_p1)
        1:shape_text="TRI ";
        2:shape_text="CIRC";
        3:shape_text="SQR ";
        default:shape_text="NONE";
      endcase
      ascii=" ";relative_char=0;
      if(bchar_p1<name_len) begin
        case(color_p1)
          1:case(bchar_p1)0:ascii="R";1:ascii="E";2:ascii="D";default:ascii=" ";endcase
          2:case(bchar_p1)0:ascii="G";1:ascii="R";2,3:ascii="E";4:ascii="N";default:ascii=" ";endcase
          3:case(bchar_p1)0:ascii="B";1:ascii="L";2:ascii="U";3:ascii="E";default:ascii=" ";endcase
          default:ascii=" ";
        endcase
      end else if(bchar_p1>name_len && bchar_p1<=name_len+shape_len) begin
        relative_char=bchar_p1-name_len-1;
        case(relative_char)0:ascii=shape_text[31:24];1:ascii=shape_text[23:16];2:ascii=shape_text[15:8];3:ascii=shape_text[7:0];default:ascii=" ";endcase
      end else if(bchar_p1>name_len+shape_len+1) begin
        relative_char=bchar_p1-name_len-shape_len-2;
        case(relative_char)
          0:ascii=(conf_h_p1!=0)?"1":8'h30+conf_t_p1;
          1:ascii=(conf_h_p1!=0)?"0":8'h30+conf_o_p1;
          2:ascii=(conf_h_p1!=0)?"0":"%";
          3:ascii=(conf_h_p1!=0)?"%":" ";default:ascii=" ";
        endcase
      end
      if(pcb_p1) begin
        ascii=" ";
        case(bchar_p1)0:ascii="P";1:ascii="C";2:ascii="B";3:ascii=" ";
          4:ascii=!checked_p1?"R":good_p1?"P":"F";
          5:ascii=!checked_p1?"E":"A";
          6:ascii=!checked_p1?"V":good_p1?"S":"I";
          7:ascii=!checked_p1?"I":good_p1?"S":"L";
          8:ascii=!checked_p1?"E":" ";9:ascii=!checked_p1?"W":" ";
          11:ascii=conf_h_p1!=0?"1":8'h30+conf_t_p1;
          12:ascii=conf_h_p1!=0?"0":8'h30+conf_o_p1;
          13:ascii=conf_h_p1!=0?"0":"%";14:ascii=conf_h_p1!=0?"%":" ";default:ascii=" ";endcase
      end
      bits=font5(ascii,brow_p1[3:1]);
      // Keep the compact 128-pixel badge width, but widen each active
      // vertical stroke to one or two pixels.  This materially improves
      // readability at 720p without adding a second ROM or a long path.
      glyph_hit=1'b0;
      if (badge_area_p1 && (brow_p1!=0) && (brow_p1<15) && (bcol_p1>=1) && (bcol_p1<=7)) begin
        case (bcol_p1)
          3'd1,3'd2: glyph_hit = bits[4];
          3'd3:     glyph_hit = bits[3];
          3'd4,3'd5: glyph_hit = bits[2];
          3'd6:     glyph_hit = bits[1];
          3'd7:     glyph_hit = bits[0];
          default:  glyph_hit = 1'b0;
        endcase
      end
      // One-pixel frame around the badge gives a crisp separation from the
      // live video.  It is intentionally computed from coordinates only.
      glyph_border = badge_area && ((brow==0)||(brow==15)||(bdx==0)||(bdx==BADGE_W-1));

      distance_ascii=" ";
      if(distance_valid_r) begin
        case(distance_cell)
          0:distance_ascii="A"; 1:distance_ascii="4"; 2:distance_ascii=":";
          3:distance_ascii=8'h30+distance_bcd_r[15:12];
          4:distance_ascii=8'h30+distance_bcd_r[11:8];
          5:distance_ascii=8'h30+distance_bcd_r[7:4];
          6:distance_ascii=".";
          7:distance_ascii=8'h30+distance_bcd_r[3:0];
          8:distance_ascii="C"; 9:distance_ascii="M";
          11:distance_ascii="E"; 12:distance_ascii="S"; 13:distance_ascii="T";
          default:distance_ascii=" ";
        endcase
      end else begin
        case(distance_cell)
          0:distance_ascii="A"; 1:distance_ascii="4"; 2:distance_ascii=":";
          3:distance_ascii="N"; 4:distance_ascii="O"; 5:distance_ascii=":";
          6:distance_ascii="A"; 7:distance_ascii="4";
          default:distance_ascii=" ";
        endcase
      end
      distance_bits=font5(distance_ascii,distance_row);
      distance_glyph=1'b0;
      if(distance_area && distance_row<7) begin
        case(distance_col)
          3'd0:distance_glyph=distance_bits[4];
          3'd1:distance_glyph=distance_bits[3];
          3'd2:distance_glyph=distance_bits[2];
          3'd3:distance_glyph=distance_bits[1];
          3'd4:distance_glyph=distance_bits[0];
          default:distance_glyph=1'b0;
        endcase
      end
      distance_hit_p1=distance_glyph;
      distance_color_p1=distance_valid_r?24'hffffff:24'hffb040;
    end

    always @(posedge I_clk or negedge I_rst_n) begin
      if(!I_rst_n) begin
        px<=0;py<=0;x0_r<=0;x1_r<=0;cx_r<=0;y0_r<=0;y1_r<=0;cy_r<=0;cls_r<=0;
        conf_h_r<=0;conf_t_r<=0;conf_o_r<=0;valid_r<=0;toggle_r<=0;remote_r<=0;color_r<=0;shape_r<=0;pcb_r<=0;checked_r<=0;good_r<=0;
        distance_bcd_r<=0;distance_valid_r<=0;distance_toggle_r<=0;
        rgb_p1<=0;
        de_p1<=0; hs_p1<=0; vs_p1<=0; user_p1<=0; last_p1<=0;
        badge_area_p1<=0; badge_border_p1<=0;
        diag_hit_p1<=0; diag_color_p1<=0;
        bchar_p1<=0; bcol_p1<=0; brow_p1<=0;
        color_p1<=0; shape_p1<=0; pcb_p1<=0; checked_p1<=0; good_p1<=0;
        conf_h_p1<=0; conf_t_p1<=0; conf_o_p1<=0;
        rgb_s1<=0; badge_color_s1<=0;
        de_s1<=0; hs_s1<=0; vs_s1<=0; user_s1<=0; last_s1<=0;
        badge_hit_s1<=0; badge_area_s1<=0; badge_border_s1<=0;
        diag_hit_s1<=0; diag_color_s1<=0;
        distance_hit_s1<=0; distance_color_s1<=0;
        O_video_rgb<=0;O_video_de<=0;O_video_hs<=0;O_video_vs<=0;O_video_user<=0;O_video_last<=0;
      end else begin
        // Output the previous stage while capturing the current pixel and
        // badge decision.  RGB and all timing markers therefore share the
        // same additional cycle of latency.
        O_video_de<=de_s1; O_video_hs<=hs_s1; O_video_vs<=vs_s1;
        O_video_user<=user_s1; O_video_last<=last_s1;
        O_video_rgb<=diag_hit_s1?diag_color_s1:(badge_hit_s1?badge_color_s1:
                      (distance_hit_s1?distance_color_s1:
                      (badge_area_s1?((badge_border_s1)?24'h406080:24'h001018):rgb_s1)));
        // Stage 2: decode the registered geometry/context.  RGB and all
        // timing markers are taken from the same stage-A pixel, so adding
        // this register cannot skew the badge relative to the video.
        de_s1<=de_p1; hs_s1<=hs_p1; vs_s1<=vs_p1;
        user_s1<=user_p1; last_s1<=last_p1; rgb_s1<=rgb_p1;
        badge_hit_s1<=glyph_hit; badge_area_s1<=badge_area_p1; badge_color_s1<=cls_rgb_p1;
        badge_border_s1<=badge_border_p1;
        diag_hit_s1<=diag_hit_p1; diag_color_s1<=diag_color_p1;
        distance_hit_s1<=distance_hit_p1; distance_color_s1<=distance_color_p1;

        // Stage 1: capture the current pixel and the inexpensive geometry
        // terms.  In particular, bchar/bcol/brow terminate the x0_r path
        // before the character mux and 5x7 font decode.
        de_p1<=I_video_de; hs_p1<=I_video_hs; vs_p1<=I_video_vs;
        user_p1<=I_video_user; last_p1<=I_video_last; rgb_p1<=I_video_rgb;
        badge_area_p1<=badge_area;
        badge_border_p1<=glyph_border;
        diag_hit_p1<=diag_area; diag_color_p1<=diag_color;
        bchar_p1<=bchar; bcol_p1<=bcol; brow_p1<=brow;
        color_p1<=color_r; shape_p1<=shape_r; pcb_p1<=pcb_r;
        checked_p1<=checked_r; good_p1<=good_r;
        conf_h_p1<=conf_h_r; conf_t_p1<=conf_t_r; conf_o_p1<=conf_o_r;
        if(I_toggle!=toggle_r) begin
          toggle_r<=I_toggle;remote_r<=I_remote;color_r<=I_color;shape_r<=I_shape;pcb_r<=I_pcb_mode;checked_r<=I_pcb_checked;good_r<=I_pcb_good; valid_r<=I_enable&&I_valid&&(I_class_id!=0||I_pcb_mode);
          x0_r<=I_x0;x1_r<=I_x1;cx_r<=I_cx;y0_r<=I_y0;y1_r<=I_y1;cy_r<=I_cy;cls_r<=I_class_id;
          conf_h_r<=I_conf_hundreds;conf_t_r<=I_conf_tens;conf_o_r<=I_conf_ones;
        end
        if(I_distance_toggle!=distance_toggle_r) begin
          distance_toggle_r<=I_distance_toggle;
          distance_bcd_r<=I_distance_bcd;
          distance_valid_r<=I_distance_valid;
        end
        if(I_video_vs) begin px<=0;py<=0; end
        else if(I_video_user&&I_video_de) begin px<=0;py<=0; end
        else if(I_video_de) begin
          if(I_video_last || px==IMG_WIDTH-1) begin px<=0;if(py<IMG_HEIGHT-1)py<=py+1'b1; end
          else px<=px+1'b1;
        end
      end
    end
endmodule
