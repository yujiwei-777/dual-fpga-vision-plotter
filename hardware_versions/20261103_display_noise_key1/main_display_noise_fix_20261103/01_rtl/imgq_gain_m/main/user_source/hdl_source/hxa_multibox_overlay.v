// Four-box type18 renderer. Inputs are already frame-committed in I_clk.
// Two stages line up with hdmi_mixer's S_x_2d/S_y_2d. A single synchronous
// text/glyph ROM serves every label; there are no per-pixel divides.
module hxa_multibox_overlay #(
    parameter integer IMG_WIDTH=1280,
    parameter integer IMG_HEIGHT=720,
    parameter integer BADGE_W=144,
    parameter integer CONNECT_FRAMES=120
)(
    input wire I_clk,I_rst_n,
    input wire [11:0] I_x,I_y,
    input wire I_frame_start,I_aux_online,
    input wire I_update,I_valid,
    input wire [2:0] I_count,
    input wire [511:0] I_boxes,
    output reg O_hit,
    output wire [23:0] O_color
);
    reg update_d;
    reg [3:0] slot_valid;
    wire [10:0] x0[0:3],x1[0:3];
    wire [9:0] y0[0:3],y1[0:3];
    wire [3:0] cls[0:3];
    wire [1:0] color_id[0:3],shape_id[0:3];
    reg [10:0] badge_x[0:3];
    reg [9:0] badge_y[0:3];
    // The mailbox already supplies a pixel-domain frame-committed bank.
    // Reuse those coordinates/class bits directly instead of copying them
    // into a second per-box register bank.
    genvar g;
    generate for(g=0;g<4;g=g+1)begin:g_slot
      assign x0[g]=I_boxes[g*128+:11];
      assign y0[g]=I_boxes[g*128+16+:10];
      assign x1[g]=I_boxes[g*128+32+:11];
      assign y1[g]=I_boxes[g*128+48+:10];
      assign cls[g]=I_boxes[g*128+64+:4];
      assign color_id[g]=color_of(cls[g]);
      assign shape_id[g]=shape_of(cls[g]);
    end endgenerate
    reg [11:0] bcd[0:3];
    integer k;
    reg loading;
    reg [1:0] load_at;
    wire [127:0] slot=I_boxes[load_at*128+:128];
    reg [10:0] bx;
    reg [9:0] by;
    reg online_d;
    reg [7:0] connected_frames;
    reg connect_pending;
    // Fixed class map: RED TRI/CIRC/SQR, GREEN TRI/CIRC/SQR, BLUE TRI/CIRC/SQR.
    function [1:0] color_of;
      input [3:0] c;
      begin color_of=(c>=1&&c<=3)?1:(c>=4&&c<=6)?2:(c>=7&&c<=9)?3:0;end
    endfunction
    function [1:0] shape_of;
      input [3:0] c;
      begin case(c)1,4,7:shape_of=1;2,5,8:shape_of=2;3,6,9:shape_of=3;default:shape_of=0;endcase end
    endfunction
    function [23:0] rgb_of;
      input [1:0] c;
      begin case(c)1:rgb_of=24'hff6060;2:rgb_of=24'h50ff50;3:rgb_of=24'h70a0ff;default:rgb_of=24'hffffff;endcase end
    endfunction
    function [11:0] percent_bcd;
      input [7:0] n;
      reg [3:0] t;
      reg [7:0] base;
      begin
        if(n>=100)percent_bcd=12'h100;
        else begin
          if(n>=90)begin t=9;base=90;end
          else if(n>=80)begin t=8;base=80;end
          else if(n>=70)begin t=7;base=70;end
          else if(n>=60)begin t=6;base=60;end
          else if(n>=50)begin t=5;base=50;end
          else if(n>=40)begin t=4;base=40;end
          else if(n>=30)begin t=3;base=30;end
          else if(n>=20)begin t=2;base=20;end
          else if(n>=10)begin t=1;base=10;end
          else begin t=0;base=0;end
          percent_bcd={4'd0,t,4'd0}+(n-base);
        end
      end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
      if(!I_rst_n)begin
        update_d<=0;slot_valid<=0;online_d<=0;connected_frames<=0;connect_pending<=0;loading<=0;load_at<=0;
        for(k=0;k<4;k=k+1)begin
          badge_x[k]<=0;badge_y[k]<=0;bcd[k]<=0;
        end
      end else begin
        online_d<=I_aux_online;
        if(I_aux_online&&!online_d)connect_pending<=1;
        if(!I_aux_online)begin connect_pending<=0;connected_frames<=0;end
        else if(I_frame_start)begin
          if(connect_pending)begin connected_frames<=CONNECT_FRAMES;connect_pending<=0;end
          else if(connected_frames!=0)connected_frames<=connected_frames-1'b1;
        end
        update_d<=I_update;
        if(I_update!=update_d)begin
          load_at<=0;loading<=1;slot_valid<=0;
        end else if(loading)begin
          // The receiver validates all four 128-bit wire slots. After the
          // frame-commit we use only 11/10 coordinate bits, class[3:0] and
          // percent[6:0]. Process one slot per blanking clock to share the
          // decimal conversion and label-placement hardware.
          slot_valid[load_at]<=I_valid && (load_at<I_count);
          bcd[load_at]<=percent_bcd({1'b0,slot[86:80]});
          bx=(slot[10:0]>IMG_WIDTH-BADGE_W)?IMG_WIDTH-BADGE_W:slot[10:0];
          by=(slot[25:16]>=10'd16)?slot[25:16]-10'd16:slot[25:16];
          if(((bx<160)&&(by<160))||
             ((bx<1200)&&(bx+BADGE_W>864)&&(by<192)&&(by+16>64)))begin
            if({1'b0,slot[57:48]}+11'd16<IMG_HEIGHT)by=slot[57:48];
          end
          badge_x[load_at]<=bx;badge_y[load_at]<=by;
          if(load_at==3)loading<=0;
          else load_at<=load_at+1'b1;
        end
      end
    end

    reg edge_hit_c,label_hit_c,notice_c,border_c;
    reg [23:0] edge_color_c;
    reg [3:0] cls_c;
    reg [1:0] color_c,shape_c;
    reg [11:0] bcd_c;
    reg [7:0] dx_c;
    reg [3:0] row_c;
    integer j;
    wire [10:0] px=I_x[10:0];
    wire [9:0] py=I_y[9:0];
    always @* begin
      edge_hit_c=0;label_hit_c=0;notice_c=0;border_c=0;edge_color_c=0;
      cls_c=0;color_c=0;shape_c=0;bcd_c=0;dx_c=0;row_c=0;
      for(j=3;j>=0;j=j-1)begin
        if(slot_valid[j]&&px>=x0[j]&&px<x1[j]&&py>=y0[j]&&py<y1[j]&&
          ((px<x0[j]+11'd3)||({1'b0,px}+12'd3>=x1[j])||(py<y0[j]+10'd3)||({1'b0,py}+11'd3>=y1[j])))begin
          edge_hit_c=1;edge_color_c=rgb_of(color_id[j]);
        end
        if(slot_valid[j]&&px>=badge_x[j]&&px<badge_x[j]+11'd144&&
          py>=badge_y[j]&&py<badge_y[j]+10'd16)begin
          label_hit_c=1;dx_c=px-badge_x[j];row_c=py-badge_y[j];
          cls_c=cls[j];color_c=color_id[j];shape_c=shape_id[j];bcd_c=bcd[j];
        end
      end
      // One short notification on each successful connection, independent of
      // SW1. No persistent lower-left marker is reintroduced.
      if(connected_frames!=0&&I_x>=528&&I_x<672&&I_y>=24&&I_y<40)begin
        label_hit_c=1;notice_c=1;dx_c=I_x-528;row_c=I_y-24;
      end
      border_c=(dx_c==0)||(dx_c==BADGE_W-1)||(row_c==0)||(row_c==15);
    end

    reg edge_s,label_s,notice_s,border_s;
    reg [23:0] edge_color_s;
    reg [3:0] cls_s,row_s;
    reg [1:0] color_s,shape_s;
    reg [11:0] bcd_s;
    reg [7:0] dx_s;
    wire [4:0] idx=dx_s[7:3];
    function [4:0] font5;
      input [7:0] c; input [2:0] r;
      begin
        case(c)
          "A":case(r)0:font5=14;3:font5=31;default:font5=17;endcase
          "B":case(r)0,3,6:font5=30;default:font5=17;endcase
          "C":case(r)0,6:font5=14;default:font5=16;endcase
          "D":case(r)0,6:font5=30;default:font5=17;endcase
          "E":case(r)0,3,6:font5=31;default:font5=16;endcase
          "G":case(r)0,6:font5=14;1,2:font5=16;3:font5=23;default:font5=17;endcase
          "I":case(r)0,6:font5=31;default:font5=4;endcase
          "L":case(r)6:font5=31;default:font5=16;endcase
          "N":case(r)1:font5=25;2:font5=21;3:font5=19;default:font5=17;endcase
          "O":case(r)0,6:font5=14;default:font5=17;endcase
          "Q":case(r)0:font5=14;4:font5=21;5:font5=18;6:font5=13;default:font5=17;endcase
          "R":case(r)0,3:font5=30;4:font5=20;5:font5=18;default:font5=17;endcase
          "S":case(r)0,3,6:font5=14;1,2:font5=16;default:font5=1;endcase
          "T":case(r)0:font5=31;default:font5=4;endcase
          "U":case(r)6:font5=14;default:font5=17;endcase
          "X":case(r)0,6:font5=17;1,5:font5=10;default:font5=4;endcase
          "0":case(r)0,6:font5=14;default:font5=17;endcase
          "1":case(r)0:font5=4;1:font5=12;default:font5=4;endcase
          "2":case(r)0,3,6:font5=31;1,2:font5=1;default:font5=16;endcase
          "3":case(r)0,3,6:font5=31;default:font5=1;endcase
          "4":case(r)0,1,2:font5=18;3:font5=31;default:font5=2;endcase
          "5":case(r)0,3,6:font5=31;1,2:font5=16;default:font5=1;endcase
          "6":case(r)0,3,6:font5=14;1,2:font5=16;default:font5=17;endcase
          "7":case(r)0:font5=31;default:font5=1;endcase
          "8":case(r)0,3,6:font5=14;default:font5=17;endcase
          "9":case(r)0,3,6:font5=14;1,2:font5=17;default:font5=1;endcase
          "%":case(r)0,2:font5=25;1:font5=26;3:font5=4;4:font5=8;default:font5=19;endcase
          default:font5=0;
        endcase
      end
    endfunction
    // A single synchronous one-bit glyph ROM replaces the character/row
    // decode tree. Its read is the existing second pipeline clock.
    (* ram_style="bram" *) reg glyph_rom[0:16383];
    reg [3:0] rom_class,rom_cell;
    // Classes 1..9 contain their complete fixed label prefix. Class zero is
    // the connection banner and class 10 is the decimal/percent glyph bank.
    // This eliminates the runtime ASCII formatter from the pixel path.
    always @* begin
      rom_class=10;rom_cell=11;
      if(notice_s)begin rom_class=idx[4]?11:0;rom_cell=idx[3:0];end
      else if(idx<=12)begin rom_class=cls_s;rom_cell=idx[3:0];end
      else case(idx)
        13:rom_cell=bcd_s[8]?1:bcd_s[7:4];
        14:rom_cell=bcd_s[8]?0:bcd_s[3:0];
        15:rom_cell=bcd_s[8]?0:10;
        16:rom_cell=bcd_s[8]?10:11;
        default:rom_cell=11;
      endcase
    end
    function [7:0] fixed_char;
      input [3:0] cl,pos;
      reg [1:0] co,sh;
      begin
        co=color_of(cl);sh=shape_of(cl);fixed_char=" ";
        if(cl==0)case(pos)
          1:fixed_char="A";2:fixed_char="U";3:fixed_char="X";5:fixed_char="C";
          6:fixed_char="O";7,8:fixed_char="N";9:fixed_char="E";10:fixed_char="C";
          11:fixed_char="T";12:fixed_char="E";13:fixed_char="D";default:fixed_char=" ";
        endcase
        else if(cl<=9)case(pos)
          0:fixed_char="0"+cl;
          2:fixed_char=(co==1)?"R":(co==2)?"G":"B";
          3:fixed_char=(co==1)?"E":(co==2)?"R":"L";
          4:fixed_char=(co==1)?"D":(co==2)?"E":"U";
          5:fixed_char=(co==2)?"E":(co==3)?"E":" ";
          6:fixed_char=(co==2)?"N":" ";
          8:fixed_char=(sh==1)?"T":(sh==2)?"C":"S";
          9:fixed_char=(sh==1)?"R":(sh==2)?"I":"Q";
          10:fixed_char=(sh==1)?"I":"R";
          11:fixed_char=(sh==2)?"C":" ";
          default:fixed_char=" ";
        endcase
        else if(cl==10)fixed_char=(pos<10)?8'h30+pos:(pos==10)?"%":" ";
      end
    endfunction
    reg glyph_q;
    reg label_q,notice_q,border_q,glyph_visible_q;
    reg [1:0] color_q;
    reg [23:0] edge_color_q;
    integer fi;
    reg [4:0] init_bits;
    initial begin
      for(fi=0;fi<16384;fi=fi+1)begin
        init_bits=font5(fixed_char(fi[13:10],fi[9:6]),fi[5:3]);
        case(fi[2:0])
          1,2:glyph_rom[fi]=init_bits[4];3:glyph_rom[fi]=init_bits[3];
          4,5:glyph_rom[fi]=init_bits[2];6:glyph_rom[fi]=init_bits[1];7:glyph_rom[fi]=init_bits[0];
          default:glyph_rom[fi]=0;
        endcase
      end
    end
    always @(posedge I_clk)glyph_q<=glyph_rom[{rom_class,rom_cell,row_s[3:1],dx_s[2:0]}];
    assign O_color=label_q?((glyph_q&&glyph_visible_q)?(notice_q?24'h60ffff:rgb_of(color_q)):
                               (border_q?24'h406080:24'h001018)):edge_color_q;
    always @(posedge I_clk or negedge I_rst_n)begin
      if(!I_rst_n)begin
        edge_s<=0;label_s<=0;notice_s<=0;border_s<=0;edge_color_s<=0;
        cls_s<=0;row_s<=0;color_s<=0;shape_s<=0;bcd_s<=0;dx_s<=0;O_hit<=0;
        label_q<=0;notice_q<=0;border_q<=0;glyph_visible_q<=0;color_q<=0;edge_color_q<=0;
      end else begin
        edge_s<=edge_hit_c;label_s<=label_hit_c;notice_s<=notice_c;border_s<=border_c;
        edge_color_s<=edge_color_c;cls_s<=cls_c;row_s<=row_c;color_s<=color_c;
        shape_s<=shape_c;bcd_s<=bcd_c;dx_s<=dx_c;
        O_hit<=edge_s||label_s;
        label_q<=label_s;notice_q<=notice_s;border_q<=border_s;
        glyph_visible_q<=row_s!=0&&row_s<15;
        color_q<=color_s;edge_color_q<=edge_color_s;
      end
    end
endmodule
