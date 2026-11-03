// Four-pixel, one-input/one-output cartoon renderer.  A causal left/up
// gradient treats every lane identically, including boundaries between beats.
// There are no synthetic pixels or line/frame drains in the live camera path.
module cartoon_96 #(
    parameter integer IMG_WIDTH=1280,
    parameter integer IMG_HEIGHT=720,
    parameter integer EDGE_THRESHOLD=32,
    parameter [7:0] QUANT_MASK=8'he0
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
    localparam integer XW=(GROUPS<2)?1:$clog2(GROUPS);
    localparam integer YW=(IMG_HEIGHT<2)?1:$clog2(IMG_HEIGHT);
    // Only the preceding row's luma is needed.  Do not asynchronously reset
    // the RAM or its read register: first-row border handling masks stale data.
    (* ram_style="bram" *) reg [31:0] rows[0:GROUPS-1];
    reg [31:0] row_q;
    reg [31:0] p_gray;
    reg [7:0] left_gray;
    reg [95:0] p_data;
    reg [XW-1:0] p_x,in_x;
    reg [YW-1:0] in_y;
    reg p_first_row;
    reg p_valid,p_user,p_last,p_cart,active_cart;
    wire out_free=!O_tvalid||O_tready;
    wire take=I_tvalid&&I_tready;
    wire retire=p_valid&&out_free;
    assign I_tready=!p_valid||out_free;
    wire [XW-1:0] take_x=I_tuser?{XW{1'b0}}:in_x;

    function [7:0] gray8;
      input [23:0] p;
      begin
        // Maximum 63+127+15+31=236, so eight bits are sufficient.
        gray8=(p[23:16]>>2)+(p[15:8]>>1)+(p[15:8]>>4)+(p[7:0]>>3);
      end
    endfunction

    wire [31:0] input_gray={gray8(I_tdata[95:72]),gray8(I_tdata[71:48]),
                           gray8(I_tdata[47:24]),gray8(I_tdata[23:0])};

    function [7:0] absdiff8;
      input [7:0] a,b;
      reg signed [8:0] d;
      reg [7:0] inv;
      begin
        d=$signed({1'b0,a})-$signed({1'b0,b});
        inv=d[7:0] ^ {8{d[8]}};
        absdiff8=inv+{7'b0,d[8]};
      end
    endfunction
    function [95:0] cart_group;
      input [95:0] cur;
      input [31:0] gray,prev;
      input [7:0] left;
      input [XW-1:0] xpos;
      input first_row;
      integer i;
      reg [23:0] cp,q;
      reg [7:0] cg,pg,lg,hd,vd;
      reg [8:0] mag;
      reg [5:0] mag_low;
      reg edge_pixel;
      begin
        cart_group=96'd0;
        for(i=0;i<4;i=i+1) begin
          cp=cur[95-i*24 -:24];
          cg=gray[31-i*8 -:8];
          pg=prev[31-i*8 -:8];
          if(i==0) lg=left;
          else lg=gray[31-(i-1)*8 -:8];
          hd=absdiff8(cg,lg);
          vd=absdiff8(cg,pg);
          mag={1'b0,hd}+{1'b0,vd};
          mag_low={1'b0,hd[4:0]}+{1'b0,vd[4:0]};
          if(EDGE_THRESHOLD==32) edge_pixel=(|hd[7:5]) || (|vd[7:5]) || mag_low[5];
          else edge_pixel=(mag>=EDGE_THRESHOLD);
          q={cp[23:16]&QUANT_MASK,cp[15:8]&QUANT_MASK,cp[7:0]&QUANT_MASK};
          cart_group[95-i*24 -:24]=(((xpos==0)&&(i==0))||first_row||
                                   (!edge_pixel))?q:24'd0;
        end
      end
    endfunction

    // Keep the production row store in canonical synchronous-read form.
    // Adjacent accepted beats use different addresses when GROUPS>1.  An
    // abrupt SOF may collide with the retiring old beat, but its y=0 border
    // masks the old-row sample.  The single-group test geometry still needs
    // explicit forwarding because every ordinary row transition collides.
    generate if (GROUPS > 1) begin : g_row_eram
      always @(posedge I_clk) begin
        if(I_rst_n) begin
          if(retire) rows[p_x] <= p_gray;
          if(take) row_q <= rows[take_x];
        end
      end
    end else begin : g_row_single
      always @(posedge I_clk) begin
        if(I_rst_n) begin
          if(retire) rows[p_x] <= p_gray;
          if(take) row_q <= (retire && p_x==take_x) ? p_gray : rows[take_x];
        end
      end
    end endgenerate

    always @(posedge I_clk or negedge I_rst_n) begin
      if(!I_rst_n) begin
        left_gray<=0;p_gray<=0;p_data<=0;p_x<=0;p_first_row<=1;in_x<=0;in_y<=0;
        p_valid<=0;p_user<=0;p_last<=0;p_cart<=0;active_cart<=0;
        O_tdata<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;
      end else begin
        if(retire) begin
          O_tdata <= p_cart ? cart_group(p_data,p_gray,row_q,left_gray,p_x,p_first_row) : p_data;
          O_tvalid<=1;O_tuser<=p_user;O_tlast<=p_last;
          left_gray<=p_last?8'd0:p_gray[7:0];
        end else if(out_free) begin
          O_tvalid<=0;O_tuser<=0;O_tlast<=0;
        end
        if(take) begin
          p_data<=I_tdata;p_gray<=input_gray;p_user<=I_tuser;
          // Fixed geometry prevents a missing input EOL from shifting the
          // downstream HDMI/DDR packer.  SOF is accepted only with a pixel.
          p_last<=I_tuser ? (GROUPS==1) : (in_x==GROUPS-1);
          if(I_tuser) active_cart<=I_cart;
          p_cart<=I_tuser ? I_cart : active_cart;
          p_x<=take_x;p_first_row<=I_tuser||(in_y==0);p_valid<=1;
          if(I_tuser) begin
            in_x<=(GROUPS==1)?0:1;
            in_y<=((GROUPS==1)&&(IMG_HEIGHT>1))?1:0;
          end
          else if(in_x==GROUPS-1) begin in_x<=0;in_y<=(in_y==IMG_HEIGHT-1)?0:in_y+1'b1; end
          else in_x<=in_x+1'b1;
        end else if(retire) p_valid<=0;
      end
    end
endmodule

