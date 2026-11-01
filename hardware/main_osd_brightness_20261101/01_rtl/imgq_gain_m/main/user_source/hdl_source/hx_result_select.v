// Stable mailbox from network to pixels. Source payload is held until ack;
// missed updates coalesce to the most recent result. Presentation changes
// only at VSYNC, including source selection and loss-of-peer fallback.
module hx_result_select(
    input wire net_clk,net_rst_n,remote_enable,remote_online,remote_pcb,
    input wire remote_toggle,remote_valid,input wire [511:0] remote_data,
    input wire px_clk,px_rst_n,frame_start,overlay_enable,
    input wire local_valid,input wire [10:0] local_x0,local_x1,local_cx,
    input wire [9:0] local_y0,local_y1,local_cy,input wire [23:0] local_area,
    input wire [1:0] local_color,local_shape,input wire [3:0] local_class,
    input wire [7:0] local_confidence,input wire [3:0] local_tens,local_ones,
    output reg valid,remote_source,toggle,pcb_mode,pcb_checked,pcb_good,
    output reg [10:0] x0,x1,cx,output reg [9:0] y0,y1,cy,
    output reg [23:0] area,output reg [1:0] color,shape,
    output reg [3:0] class_id,conf_tens,conf_ones,output reg [7:0] confidence
);
    // Either endpoint reset invalidates the full mailbox. Release each end
    // only on its own clock so neither handshake reset is an async CDC path.
    wire mailbox_rst_n=net_rst_n&&px_rst_n;
    wire src_reset_n,px_reset_n;
    reset_sync u_src_reset(.I_clk(net_clk),.I_async_rst_n(mailbox_rst_n),.O_rst_n(src_reset_n));
    reset_sync u_px_reset(.I_clk(px_clk),.I_async_rst_n(mailbox_rst_n),.O_rst_n(px_reset_n));
    reg req,ack,src_seen,source_armed,dirty;
    (* ASYNC_REG = "TRUE" *) reg [1:0] ack_sync,req_sync,online_sync,enable_sync;
    reg [255:0] box_hold,pending;
    reg valid_hold,pending_valid,pcb_hold,pending_pcb;
    reg [1:0] settle;
    // Metadata occupies the first 32 bytes of the fixed HXA1 result.
    always @(posedge net_clk or negedge src_reset_n) begin
        if(!src_reset_n) begin
            req<=0;ack_sync<=0;src_seen<=0;source_armed<=0;dirty<=0;box_hold<=0;valid_hold<=0;pcb_hold<=0;
        end else begin
            ack_sync<={ack_sync[0],ack};
            if(!source_armed)begin
                source_armed<=1;src_seen<=remote_toggle;
            end else begin
                if(remote_toggle!=src_seen) begin src_seen<=remote_toggle;dirty<=1;end
                if(req==ack_sync[1] && (dirty || remote_toggle!=src_seen)) begin
                    box_hold<=remote_data[255:0];valid_hold<=remote_valid;pcb_hold<=remote_pcb;
                    req<=~req;dirty<=0;
                end
            end
        end
    end
    wire [15:0] rx0=pending[128+:16],ry0=pending[144+:16];
    wire [15:0] rx1=pending[160+:16],ry1=pending[176+:16];
    wire sane_box=(rx0<rx1)&&(ry0<ry1)&&(rx1<=1280)&&(ry1<=720);
    wire use_remote=enable_sync[1]&&online_sync[1];
    wire [7:0] conf=(pending[120+:8]>100)?8'd100:pending[120+:8];
    // Slow metadata decode is outside the pixel mux. No divider in HDMI.
    function [3:0] tens;
        input [7:0] v;
        begin
            if(v>=100)tens=0;else if(v>=90)tens=9;else if(v>=80)tens=8;
            else if(v>=70)tens=7;else if(v>=60)tens=6;else if(v>=50)tens=5;
            else if(v>=40)tens=4;else if(v>=30)tens=3;else if(v>=20)tens=2;
            else if(v>=10)tens=1;else tens=0;
        end
    endfunction
    wire [3:0] rt=tens(conf);
    wire [7:0] rbase={rt,3'b0}+{rt,1'b0};
    always @(posedge px_clk or negedge px_reset_n) begin
        if(!px_reset_n) begin
            req_sync<=0;online_sync<=0;enable_sync<=0;ack<=0;settle<=0;
            pending<=0;pending_valid<=0;pending_pcb<=0;pcb_mode<=0;pcb_checked<=0;pcb_good<=0;valid<=0;remote_source<=0;toggle<=0;
            x0<=0;x1<=0;cx<=0;y0<=0;y1<=0;cy<=0;area<=0;color<=0;shape<=0;
            class_id<=0;confidence<=0;conf_tens<=0;conf_ones<=0;
        end else begin
            req_sync<={req_sync[0],req};online_sync<={online_sync[0],remote_online};
            enable_sync<={enable_sync[0],remote_enable};
            if(req_sync[1]!=ack) begin
                if(settle==2) begin pending<=box_hold;pending_valid<=valid_hold;pending_pcb<=pcb_hold;ack<=req_sync[1];settle<=0;end
                else settle<=settle+1'b1;
            end else settle<=0;
            if(frame_start) begin
                toggle<=~toggle;remote_source<=use_remote;pcb_mode<=use_remote&&pending_pcb;
                pcb_checked<=use_remote&&pending[98];pcb_good<=use_remote&&pending[97];
                if(use_remote) begin
                    valid<=overlay_enable&&pending_valid&&pending[96]&&sane_box&&
                        (pending_pcb||(pending[104+:8]>=1&&pending[104+:8]<=3&&pending[112+:8]>=1&&pending[112+:8]<=3));
                    x0<=rx0[10:0];x1<=rx1[10:0]-1'b1;cx<=({1'b0,rx0[10:0]}+{1'b0,rx1[10:0]})>>1;
                    y0<=ry0[9:0];y1<=ry1[9:0]-1'b1;cy<=({1'b0,ry0[9:0]}+{1'b0,ry1[9:0]})>>1;
                    area<=pending[192+:24];color<=pending[104+:2];shape<=pending[112+:2];
                    class_id<=pending[224+:4];confidence<=conf;conf_tens<=rt;conf_ones<=(conf>=100)?0:conf-rbase;
                end else begin
                    valid<=overlay_enable&&local_valid;x0<=local_x0;x1<=local_x1;cx<=local_cx;
                    y0<=local_y0;y1<=local_y1;cy<=local_cy;area<=local_area;color<=local_color;shape<=local_shape;
                    class_id<=local_class;confidence<=local_confidence;conf_tens<=local_tens;conf_ones<=local_ones;
                end
            end
        end
    end
endmodule
