// Four independent pixel windows per beat. RAM ports are synchronous
// read-before-write; only row storage is used, never a frame buffer.
module cartoon_96 #(
    parameter integer IMG_WIDTH=1280, IMG_HEIGHT=720,
    parameter integer EDGE_THRESHOLD=128
)(
    input wire I_clk,I_rst_n,
    input wire [95:0] I_tdata,
    input wire I_tvalid,I_tuser,I_tlast,I_cart,
    output wire I_tready,
    input wire O_tready,
    output reg [95:0] O_tdata,
    output reg O_tvalid,O_tuser,O_tlast
);
    localparam integer GROUPS=IMG_WIDTH/4;
    localparam integer AW=(GROUPS<2)?1:$clog2(GROUPS+1);
    localparam integer YW=$clog2(IMG_HEIGHT+1);
    // All row state shares a read address. Delay its write one accepted
    // cycle so top<-previous and previous<-input use a single SDP RAM.
    // No same-address collision occurs: the next row is GROUPS beats away.
    // Keep the complete three-row payload in one inferred BRAM array.  The
    // former split (80-bit BRAM plus a 20-bit distributed-RAM tail) consumed
    // 192 LUTs for the tail and made placement harder.  A 100-bit BRAM
    // inference maps to three legal PH1P ERAM lanes and preserves the exact
    // read-before-write payload and pixel timing.
    (* ram_style="bram" *) reg [99:0] rows[0:GROUPS-1];
    reg [99:0] rd_rows;
    wire [31:0] rd_mid=rd_rows[67:36],rd_top=rd_rows[99:68];
    wire [35:0] rd_quant=rd_rows[35:0];
    reg [35:0] r_quant;
    wire [95:0] rd_rgb;
    wire [35:0] input_quant;
    genvar lane;
    generate for(lane=0;lane<4;lane=lane+1)begin : g_quant
        assign input_quant[35-lane*9 -:9]={I_tdata[95-lane*24 -:3],I_tdata[87-lane*24 -:3],I_tdata[79-lane*24 -:3]};
        assign rd_rgb[95-lane*24 -:24]={rd_quant[35-lane*9 -:3],5'b0,rd_quant[32-lane*9 -:3],5'b0,rd_quant[29-lane*9 -:3],5'b0};
    end endgenerate
    reg [AW-1:0] x;
    reg [YW-1:0] y;
    reg cart_active;
    wire ce=!O_tvalid || O_tready;
    // Row zero of the next line closes the previous line concurrently.
    // Only the bottom row needs synthetic input, drained in frame blanking.
    wire synthetic=cart_active && (y==IMG_HEIGHT);
    assign I_tready=ce && !synthetic;
    wire accept=I_tvalid && I_tready;
    wire use_cart=I_tuser ? I_cart : cart_active;
    wire token=ce && (synthetic || (accept && use_cart));
    wire [AW-1:0] tx=(accept && I_tuser)?0:x;
    wire [YW-1:0] ty=(accept && I_tuser)?0:y;
    wire real_write=token && tx<GROUPS && ty<IMG_HEIGHT;
    reg rv,r_write,r_bypass;
    reg [AW-1:0] rx;
    reg [YW-1:0] ry;
    reg [31:0] r_bottom;
    reg [95:0] r_data;
    reg r_user,r_last;
    // A row-buffer token is not necessarily an output token.  The first
    // group of the first two rows is consumed only to prime the 3x3 window;
    // advancing the output coordinates on those priming tokens loses the
    // frame marker and shifts every later line marker.
    wire cart_emit = rv && ((ry!=0 && rx!=0) || (ry>=2 && rx==0));
    // Output coordinates are independent from the row-buffer read address.
    // The latter includes the two-row/one-group pipeline delay and must never
    // be used to generate AXI line markers.
    reg [AW-1:0] out_x;
    reg [YW-1:0] out_y;
    reg out_cart_pending;

    function [7:0] gray;
        input [23:0] p;
        reg [9:0] sum;
        begin sum={2'b0,p[23:16]}+{1'b0,p[15:8],1'b0}+{2'b0,p[7:0]};gray=sum[9:2];end
    endfunction
    wire [31:0] input_gray={gray(I_tdata[95:72]),gray(I_tdata[71:48]),gray(I_tdata[47:24]),gray(I_tdata[23:0])};
    always @(posedge I_clk) begin
        if(ce && token && tx<GROUPS)begin
            rd_rows<=rows[tx];
        end
        if(I_rst_n && ce && rv && r_write)begin
            rows[rx]<={rd_mid,r_bottom,r_quant};
        end
    end

    reg [31:0] prev_top,prev_mid,prev_bot;
    reg [7:0] left_top,left_mid,left_bot;
    reg [95:0] prev_rgb;
    wire [47:0] win_top={left_top,prev_top,rd_top[31:24]};
    wire [47:0] win_mid={left_mid,prev_mid,rd_mid[31:24]};
    wire [47:0] win_bot={left_bot,prev_bot,r_bottom[31:24]};
    // Adjacent output pixels share columns. Build each column once, then
    // take horizontal differences/sums for the four independent windows.
    // These are exact integer Sobel operations, with no extra pipeline stage.
    wire [9:0] col_smooth[0:5];
    wire signed [8:0] col_diff[0:5];
    genvar col;
    generate for(col=0;col<6;col=col+1)begin : g_sobel_columns
        wire [7:0] t=win_top[47-col*8 -:8];
        wire [7:0] m=win_mid[47-col*8 -:8];
        wire [7:0] b=win_bot[47-col*8 -:8];
        assign col_smooth[col]={2'b0,t}+{1'b0,m,1'b0}+{2'b0,b};
        assign col_diff[col]=$signed({1'b0,b})-$signed({1'b0,t});
    end endgenerate
    reg wv,wu,wl;
    reg [95:0] w_rgb;
    reg [3:0] w_border;
    reg signed [11:0] gx[0:3],gy[0:3];
    reg av,au,al;
    reg [95:0] a_rgb;
    reg [3:0] a_edge;
    function signed [11:0] sx;
        input [23:0] t,m,b;
        begin sx=$signed({4'b0,t[7:0]})-$signed({4'b0,t[23:16]})+
            ($signed({4'b0,m[7:0]})<<<1)-($signed({4'b0,m[23:16]})<<<1)+
            $signed({4'b0,b[7:0]})-$signed({4'b0,b[23:16]});end
    endfunction
    function signed [11:0] sy;
        input [23:0] t,b;
        begin sy=$signed({4'b0,b[23:16]})+($signed({4'b0,b[15:8]})<<<1)+$signed({4'b0,b[7:0]})-
            $signed({4'b0,t[23:16]})-($signed({4'b0,t[15:8]})<<<1)-$signed({4'b0,t[7:0]});end
    endfunction
    function [11:0] mag;
        input signed [11:0] xx,yy;
        reg [11:0] ax,ay;
        begin ax=xx<0?-xx:xx;ay=yy<0?-yy:yy;mag=ax+ay;end
    endfunction
    integer k;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            x<=0;y<=0;cart_active<=0;rv<=0;r_write<=0;r_bypass<=0;
            rx<=0;ry<=0;r_bottom<=0;r_data<=0;r_user<=0;r_last<=0;
            out_x<=0;out_y<=0;out_cart_pending<=0;
            prev_top<=0;prev_mid<=0;prev_bot<=0;prev_rgb<=0;
            left_top<=0;left_mid<=0;left_bot<=0;
            wv<=0;wu<=0;wl<=0;w_rgb<=0;w_border<=0;
            av<=0;au<=0;al<=0;a_rgb<=0;a_edge<=0;
            O_tvalid<=0;O_tuser<=0;O_tlast<=0;O_tdata<=0;
            for(k=0;k<4;k=k+1)begin gx[k]<=0;gy[k]<=0;end
        end else if(ce)begin
            rv<=token;r_write<=real_write;r_bypass<=accept&&!use_cart;
            if(accept)begin r_data<=I_tdata;r_user<=I_tuser;r_last<=I_tlast;end
            if(accept && I_tuser)
                out_cart_pending<=use_cart;
            if(accept && I_tuser)begin cart_active<=I_cart;x<=0;y<=0;end
            if(token)begin
                rx<=tx;ry<=ty;r_bottom<=input_gray;r_quant<=input_quant;
                if(ty==IMG_HEIGHT && tx==GROUPS)begin
                    x<=0;y<=0;cart_active<=0;
                end else if(tx==GROUPS-1 && ty<IMG_HEIGHT)begin
                    x<=0;
                    y<=ty+1'b1;
                end else x<=tx+1'b1;
            end
            wv<=r_bypass || (rv && ((ry!=0 && rx!=0)||(ry>=2 && rx==0)));
            if(r_bypass)begin
                w_rgb<=r_data;wu<=r_user;wl<=r_last;w_border<=4'hf;
            end else if(rv)begin
                if(rx<GROUPS)begin
                    prev_top<=rd_top;prev_mid<=rd_mid;prev_bot<=r_bottom;prev_rgb<=rd_rgb;
                    left_top<=prev_top[7:0];left_mid<=prev_mid[7:0];left_bot<=prev_bot[7:0];
                end
                w_rgb<=prev_rgb & 96'he0e0e0e0e0e0e0e0e0e0e0e0;
                // Markers are assigned from the number of valid CART output
                // groups already emitted.  rx/ry describe the delayed line
                // buffer token and are not output coordinates.
                if (cart_emit && out_cart_pending) begin
                    wu<=1'b1;
                    wl<=1'b0;
                    out_cart_pending<=1'b0;
                    out_x<= (GROUPS==1) ? 0 : 1;
                    out_y<=0;
                end else if (cart_emit) begin
                    wu<=(out_x==0 && out_y==0);
                    if (out_x==GROUPS-1) begin
                        wl<=1'b1;
                        out_x<=0;
                        out_y<= (out_y==IMG_HEIGHT-1) ? 0 : out_y+1'b1;
                    end else begin
                        wl<=1'b0;
                        out_x<=out_x+1'b1;
                    end
                end
                for(k=0;k<4;k=k+1)begin
                    gx[k]<=$signed({2'b0,col_smooth[k+2]})-$signed({2'b0,col_smooth[k]});
                    gy[k]<=$signed({{3{col_diff[k][8]}},col_diff[k]})+
                           ($signed({{3{col_diff[k+1][8]}},col_diff[k+1]})<<<1)+
                           $signed({{3{col_diff[k+2][8]}},col_diff[k+2]});
                    w_border[k]<=((rx==0?ry==2:ry==1) || (ry==IMG_HEIGHT&&rx!=0) || (rx==1&&k==0)||((rx==0||rx==GROUPS)&&k==3));
                end
            end
            av<=wv;au<=wu;al<=wl;a_rgb<=w_rgb;
            for(k=0;k<4;k=k+1)a_edge[k]<=!w_border[k] && mag(gx[k],gy[k])>=EDGE_THRESHOLD;
            O_tvalid<=av;O_tuser<=av && au;O_tlast<=av && al;
            for(k=0;k<4;k=k+1)O_tdata[95-k*24 -:24]<=a_edge[k]?24'd0:a_rgb[95-k*24 -:24];
        end
    end
endmodule
