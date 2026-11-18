// Full 3x3 Sobel CART renderer for the four-pixel RGB stream.
// Two packed line memories retain luma and quantized colour.  Output
// coordinates are independent from delayed input coordinates so tuser/tlast
// remain stable through the one-line pipeline and the final-line drain.
module cartoon_sobel_96 #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer EDGE_THRESHOLD = 48
)(
    input wire I_clk,I_rst_n,
    input wire [95:0] I_tdata,
    input wire I_tvalid,I_tuser,I_tlast,I_cart,
    output wire I_tready,
    input wire O_tready,
    output reg [95:0] O_tdata,
    output reg O_tvalid,O_tuser,O_tlast
);
    localparam integer GROUPS = IMG_WIDTH/4;
    localparam integer XW = (GROUPS < 2) ? 1 : $clog2(GROUPS);
    localparam integer YW = (IMG_HEIGHT < 2) ? 1 : $clog2(IMG_HEIGHT);

    // 32 luma bits + 48 quantized RGB-nibble bits per group.
    (* ram_style="bram" *) reg [79:0] line0[0:GROUPS-1];
    (* ram_style="bram" *) reg [79:0] line1[0:GROUPS-1];
    reg [XW-1:0] in_x;
    reg [YW-1:0] in_y;
    reg active_cart,tail_pending,flush_active,flush_after_tail,last_row_parity;
    reg [XW-1:0] flush_x;
    reg [31:0] top_old,top_prev,mid_old,mid_prev,bot_old,bot_prev;
    reg [47:0] q_old,q_prev;
    reg [95:0] tail_data;
    reg [XW-1:0] out_x;
    reg [YW-1:0] out_y;

    wire out_slot = !O_tvalid || O_tready;
    wire take = I_tvalid && I_tready;
    wire take_cart = I_tuser ? I_cart : active_cart;
    wire [XW-1:0] take_x = I_tuser ? 0 : in_x;
    wire [YW-1:0] take_y = I_tuser ? 0 : in_y;
    assign I_tready = out_slot && !tail_pending && !flush_active;

    function [7:0] luma8;
        input [23:0] p;
        begin luma8=(p[23:16]>>2)+(p[15:8]>>1)+(p[15:8]>>4)+(p[7:0]>>3); end
    endfunction
    function [31:0] luma_group;
        input [95:0] p;
        begin luma_group={luma8(p[95:72]),luma8(p[71:48]),luma8(p[47:24]),luma8(p[23:0])}; end
    endfunction
    function [11:0] q12;
        input [23:0] p;
        begin q12={p[23:20],p[15:12],p[7:4]}; end
    endfunction
    function [47:0] quant_group;
        input [95:0] p;
        begin quant_group={q12(p[95:72]),q12(p[71:48]),q12(p[47:24]),q12(p[23:0])}; end
    endfunction
    function [7:0] lane32;
        input [31:0] g; input integer n;
        begin lane32=g[31-n*8 -: 8]; end
    endfunction
    function [11:0] lane48;
        input [47:0] q; input integer n;
        begin lane48=q[47-n*12 -: 12]; end
    endfunction
    function [23:0] q_to_rgb;
        input [11:0] q;
        begin q_to_rgb={q[11:8],4'b0,q[7:4],4'b0,q[3:0],4'b0}; end
    endfunction
    function [23:0] cart_pixel;
        input [7:0] tl,tc,tr,ml,mc,mr,bl,bc,br;
        input [11:0] q; input integer border;
        integer gx,gy,mag;
        begin
            gx=-tl+tr-(ml<<<1)+(mr<<<1)-bl+br;
            gy=-tl-(tc<<<1)-tr+bl+(bc<<<1)+br;
            if(gx<0)gx=-gx; if(gy<0)gy=-gy; mag=gx+gy;
            cart_pixel=(border!=0 || mag<EDGE_THRESHOLD)?q_to_rgb(q):24'd0;
        end
    endfunction
    function [95:0] cart_group;
        input [31:0] to,tp,tc,mo,mp,mc,bo,bp,bc;
        input [47:0] qp; input integer center_group,center_y;
        integer k; integer left_border;
        reg [7:0] tl,tm,tr,ml,mm,mr,bl,bm,br; reg [11:0] qv;
        begin
            cart_group=0;
            for(k=0;k<4;k=k+1) begin
                left_border=(center_group==0)&&(k==0);
                tl=(k==0)?(left_border?lane32(tp,0):lane32(to,3)):lane32(tp,k-1);
                tm=lane32(tp,k); tr=(k==3)?lane32(tc,0):lane32(tp,k+1);
                ml=(k==0)?(left_border?lane32(mp,0):lane32(mo,3)):lane32(mp,k-1);
                mm=lane32(mp,k); mr=(k==3)?lane32(mc,0):lane32(mp,k+1);
                bl=(k==0)?(left_border?lane32(bp,0):lane32(bo,3)):lane32(bp,k-1);
                bm=lane32(bp,k); br=(k==3)?lane32(bc,0):lane32(bp,k+1);
                qv=lane48(qp,k);
                cart_group[95-k*24 -: 24]=cart_pixel(tl,tm,tr,ml,mm,mr,bl,bm,br,qv,
                    (center_y==0)||(center_y==IMG_HEIGHT-1)||
                    ((center_group==0)&&(k==0)) ||
                    ((center_group==GROUPS-1)&&(k==3)));
            end
        end
    endfunction

    wire [79:0] mem0_at_x=line0[take_x];
    wire [79:0] mem1_at_x=line1[take_x];
    wire [31:0] cur_luma=luma_group(I_tdata);
    wire [47:0] cur_quant=quant_group(I_tdata);
    wire [31:0] cur_top=(take_y==0)?0:(take_y==1)?mem0_at_x[79:48]:
                         (take_y[0]==0?mem0_at_x[79:48]:mem1_at_x[79:48]);
    wire [31:0] cur_mid=(take_y==0)?0:(take_y==1)?mem0_at_x[79:48]:
                         (take_y[0]==0?mem1_at_x[79:48]:mem0_at_x[79:48]);
    wire [47:0] cur_mid_q=(take_y==0)?0:(take_y==1)?mem0_at_x[47:0]:
                           (take_y[0]==0?mem1_at_x[47:0]:mem0_at_x[47:0]);
    wire [79:0] last_mem_word=last_row_parity?line1[flush_x]:line0[flush_x];
    wire [47:0] flush_quant=last_mem_word[47:0];

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            in_x<=0; in_y<=0; active_cart<=0; tail_pending<=0; flush_active<=0;
            flush_after_tail<=0; last_row_parity<=0; flush_x<=0;
            top_old<=0;top_prev<=0;mid_old<=0;mid_prev<=0;bot_old<=0;bot_prev<=0;
            q_old<=0;q_prev<=0;tail_data<=0;out_x<=0;out_y<=0;
            O_tdata<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;
        end else begin
            if(out_slot) begin
                O_tvalid<=0; O_tuser<=0; O_tlast<=0;
                if(flush_active) begin
                    O_tdata<={q_to_rgb(lane48(flush_quant,0)),q_to_rgb(lane48(flush_quant,1)),
                              q_to_rgb(lane48(flush_quant,2)),q_to_rgb(lane48(flush_quant,3))};
                    O_tvalid<=1; O_tuser<=(out_x==0)&&(out_y==0); O_tlast<=(out_x==GROUPS-1);
                    if(out_x==GROUPS-1) begin out_x<=0;out_y<=0;flush_x<=0;flush_active<=0;end
                    else begin out_x<=out_x+1'b1;flush_x<=flush_x+1'b1;end
                end else if(tail_pending) begin
                    O_tdata<=tail_data; O_tvalid<=1; O_tuser<=(out_x==0)&&(out_y==0);
                    O_tlast<=(out_x==GROUPS-1); tail_pending<=0;
                    if(out_x==GROUPS-1) begin out_x<=0;out_y<=(out_y==IMG_HEIGHT-1)?0:out_y+1'b1;end
                    else out_x<=out_x+1'b1;
                    if(flush_after_tail) begin flush_active<=1;flush_x<=0;flush_after_tail<=0;end
                end
            end
            if(take) begin
                if(I_tuser) begin active_cart<=I_cart;in_x<=0;in_y<=0;out_x<=0;out_y<=0;end
                if(!take_cart) begin
                    O_tdata<=I_tdata;O_tvalid<=1;O_tuser<=I_tuser;O_tlast<=I_tlast;
                end else begin
                    if(take_y[0]==0) line0[take_x]<={cur_luma,cur_quant};
                    else line1[take_x]<={cur_luma,cur_quant};
                    if(take_x==0) begin
                        top_old<=cur_top;top_prev<=cur_top;mid_old<=cur_mid;mid_prev<=cur_mid;
                        bot_old<=cur_luma;bot_prev<=cur_luma;q_old<=cur_mid_q;q_prev<=cur_mid_q;
                    end else if(take_y==0) begin
                        top_old<=top_prev;top_prev<=cur_top;mid_old<=mid_prev;mid_prev<=cur_mid;
                        bot_old<=bot_prev;bot_prev<=cur_luma;q_old<=q_prev;q_prev<=cur_mid_q;
                    end else begin
                        O_tdata<=cart_group(top_old,top_prev,cur_top,mid_old,mid_prev,cur_mid,
                                            bot_old,bot_prev,cur_luma,q_prev,take_x-1,take_y-1);
                        O_tvalid<=1;O_tuser<=(out_x==0)&&(out_y==0);O_tlast<=0;
                        if(out_x==GROUPS-1) begin out_x<=0;out_y<=(out_y==IMG_HEIGHT-1)?0:out_y+1'b1;end
                        else out_x<=out_x+1'b1;
                        if(take_x==GROUPS-1) begin
                            tail_data<=cart_group(top_prev,cur_top,cur_top,mid_prev,cur_mid,cur_mid,
                                                  bot_prev,cur_luma,cur_luma,cur_mid_q,GROUPS-1,take_y-1);
                            tail_pending<=1;
                            if(take_y==IMG_HEIGHT-1) begin flush_after_tail<=1;last_row_parity<=take_y[0];end
                        end
                        top_old<=top_prev;top_prev<=cur_top;mid_old<=mid_prev;mid_prev<=cur_mid;
                        bot_old<=bot_prev;bot_prev<=cur_luma;q_old<=q_prev;q_prev<=cur_mid_q;
                    end
                end
                if(take_cart) begin
                    if(take_x==GROUPS-1) begin in_x<=0;in_y<=(take_y==IMG_HEIGHT-1)?0:take_y+1'b1;end
                    else in_x<=take_x+1'b1;
                end
            end
        end
    end
endmodule
