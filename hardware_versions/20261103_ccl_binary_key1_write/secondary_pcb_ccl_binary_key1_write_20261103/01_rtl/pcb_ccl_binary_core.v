`timescale 1ns/1ps
// CCL-localised retrained binary PCB classifier; original CCL box is published.
// CNN input uses the exact original CCL box x1.0 and unsigned source Y8.
// Accepted DDR reads retain frame ownership until their response is drained.
module pcb_ccl_binary_core #(
    parameter WEIGHTS_MEM="../model/experiments/conv4_4/weights.mem",
    parameter BIASES_MEM="../model/experiments/conv4_4/biases.mem",
    parameter integer PIXEL_TIMEOUT=4096,
    parameter integer ABORT_TIMEOUT=8192,
    parameter integer INFER_TIMEOUT=2097152,
    parameter integer MARGIN_MIN=32
)(
    input wire clk,rst_n,start,cancel,frame_valid,model_valid,
    input wire [31:0] job_id,
    input wire [2:0] I_ccl_count,
    input wire [255:0] I_ccl_boxes,
    input wire I_ccl_overflow,I_ccl_truncated,
    output wire busy,frame_lock,
    output reg done,result_valid,no_target,
    output reg [1:0] status,
    output reg [15:0] error,
    output reg bbox_valid,
    output reg [10:0] xmin,xmax,
    output reg [9:0] ymin,ymax,
    output reg [11:0] detail_score,
    output reg [7:0] classifier_score,
    output reg [15:0] classifier_margin,
    output wire [15:0] outline_support,
    output wire pixel_request,
    output wire [10:0] pixel_x,
    output wire [9:0] pixel_y,
    input wire pixel_ready,pixel_valid,
    input wire [7:0] pixel_y8,
    output wire ws_we,ws_wbank,
    output wire [14:0] ws_waddr,
    output wire [15:0] ws_wdata,
    output wire ws_rd_bank,
    output wire [14:0] ws_rd_addr,
    input wire [15:0] ws_rd_data,
    output wire signed [15:0] mac_a,
    output wire signed [7:0] mac_w,
    input wire signed [23:0] mac_product_ext,
    output wire [7:0] phase,
    output reg [47:0] cycles
);
    localparam [4:0] IDLE=0,VALIDATE=1,EXPAND_CHECK=5,MAP_Y=6,MAP_X=7,PIXEL_REQ=8,
        PIXEL_WAIT=9,PIXEL_STORE=10,CORE_START=11,CORE_WAIT=12,
        PUBLISH=13,DRAIN=14,LOCKED=15;
    localparam integer IO_LIMIT=PIXEL_TIMEOUT>ABORT_TIMEOUT?PIXEL_TIMEOUT:ABORT_TIMEOUT;
    localparam integer WAIT_LIMIT=IO_LIMIT>INFER_TIMEOUT?IO_LIMIT:INFER_TIMEOUT;
    localparam integer WAIT_BITS=WAIT_LIMIT>1?$clog2(WAIT_LIMIT+1):1;
    reg [4:0] state;
    reg [31:0] job_q;
    reg [63:0] box_q;
    reg [2:0] count_q;
    reg overflow_q,truncated_q;
    reg [10:0] roi_width,source_x,roi_left;
    reg [9:0] roi_height,source_y,roi_top;
    reg [6:0] roi_u,roi_v;
    reg [13:0] roi_index;
    reg [12:0] map_x_remainder,map_y_remainder;
    reg read_pending,core_enable;
    reg [WAIT_BITS-1:0] wait_count;
    reg [7:0] captured_pixel;
    wire active=state!=IDLE;
    wire external_abort=cancel||(start&&active);
    wire pixel_accept=pixel_request&&pixel_ready;
    wire accepted_response=pixel_valid&&(read_pending||pixel_accept);
    wire core_busy,core_done;
    wire [1:0] core_class;
    wire [7:0] core_score;
    wire [15:0] core_margin,core_sat;
    wire core_ws_we,core_ws_wbank,core_ws_rd_bank;
    wire [14:0] core_ws_waddr,core_ws_rd_addr;
    wire [15:0] core_ws_wdata;
    wire signed [15:0] core_mac_a;
    wire signed [7:0] core_mac_w;
    wire core_rst_n=rst_n&&core_enable;
    wire core_pixel_we=state==PIXEL_STORE&&!external_abort;
    wire core_start=state==CORE_START&&!external_abort;
    pcb_fullboard_spatial96 #(
        .WEIGHTS_MEM(WEIGHTS_MEM),.BIASES_MEM(BIASES_MEM),
        .USE_SHARED_WORKSPACE(1),.EXTERNAL_MAC(1),.HEAD_CLASSES(2),
        .C1_CHANNELS(4),.C2_CHANNELS(4),
        .C1_SHIFT(7),.C2_SHIFT(7),.HEAD_SHIFT(8)
    ) classifier(
        .clk(clk),.rst_n(core_rst_n),.start(core_start),
        .pixel_we(core_pixel_we),.pixel_addr(roi_index),.pixel_gray(captured_pixel),
        .busy(core_busy),.done(core_done),.class_id(core_class),
        .score(core_score),.margin(core_margin),.saturation_count(core_sat),
        .ws_we(core_ws_we),.ws_wbank(core_ws_wbank),.ws_waddr(core_ws_waddr),
        .ws_wdata(core_ws_wdata),.ws_rd_bank(core_ws_rd_bank),
        .ws_rd_addr(core_ws_rd_addr),.ws_rd_data(ws_rd_data),
        .mac_a(core_mac_a),.mac_w(core_mac_w),.mac_product_ext(mac_product_ext));
    assign busy=active;
    assign frame_lock=active;
    assign phase={3'd0,state};
    assign outline_support=16'd0;
    assign pixel_request=state==PIXEL_REQ&&!external_abort;
    assign pixel_x=source_x;
    assign pixel_y=source_y;
    assign ws_we=core_ws_we&&core_enable&&!external_abort&&active&&state!=LOCKED;
    assign ws_wbank=core_ws_wbank;
    assign ws_waddr=core_ws_waddr;
    assign ws_wdata=core_ws_wdata;
    assign ws_rd_bank=core_ws_rd_bank;
    assign ws_rd_addr=core_ws_rd_addr;
    assign mac_a=core_enable&&!external_abort?core_mac_a:16'sd0;
    assign mac_w=core_enable&&!external_abort?core_mac_w:8'sd0;
    task source_lock;
        input [15:0] code;
        begin
            state<=LOCKED;core_enable<=0;done<=1;result_valid<=0;
            bbox_valid<=0;status<=3;error<=code;
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=IDLE;job_q<=0;box_q<=0;count_q<=0;overflow_q<=0;truncated_q<=0;
            done<=0;result_valid<=0;no_target<=0;status<=2;error<=0;bbox_valid<=0;
            xmin<=0;xmax<=0;ymin<=0;ymax<=0;detail_score<=0;
            classifier_score<=0;classifier_margin<=0;cycles<=0;
            roi_width<=0;roi_height<=0;source_x<=0;source_y<=0;roi_left<=0;roi_top<=0;
            roi_u<=0;roi_v<=0;roi_index<=0;
            map_x_remainder<=0;map_y_remainder<=0;read_pending<=0;wait_count<=0;
            captured_pixel<=0;core_enable<=0;
        end else begin
            done<=0;
            if(active&&state!=LOCKED)cycles<=cycles+48'd1;
            if(pixel_accept)read_pending<=!pixel_valid;
            if(accepted_response)read_pending<=0;
            if(state==LOCKED)begin state<=LOCKED;end
            else if(state==DRAIN)begin
                if(!read_pending||pixel_valid)begin state<=IDLE;done<=1;wait_count<=0;end
                else if(wait_count>=ABORT_TIMEOUT-1)source_lock(16'h1003);
                else wait_count<=wait_count+1'b1;
            end else if(active&&external_abort)begin
                core_enable<=0;result_valid<=0;bbox_valid<=0;no_target<=0;status<=3;
                error<=cancel?16'h0002:16'h0003;wait_count<=0;
                if(read_pending&&!pixel_valid)state<=DRAIN;
                else begin state<=IDLE;done<=1;end
            end else case(state)
                IDLE:begin
                    core_enable<=0;
                    if(cancel)begin result_valid<=0;bbox_valid<=0;end
                    else if(start)begin
                        job_q<=job_id;box_q<=I_ccl_boxes[63:0];count_q<=I_ccl_count;
                        overflow_q<=I_ccl_overflow;truncated_q<=I_ccl_truncated;
                        result_valid<=0;bbox_valid<=0;no_target<=0;detail_score<=0;
                        classifier_score<=0;classifier_margin<=0;status<=2;error<=0;
                        xmin<=0;xmax<=0;ymin<=0;ymax<=0;cycles<=0;wait_count<=0;read_pending<=0;
                        if(!frame_valid||!model_valid)begin done<=1;status<=3;error<=16'h0101;end
                        else begin core_enable<=1;state<=VALIDATE;end
                    end
                end
                VALIDATE:begin
                    // Truncation alone preserves the established largest-box policy.
                    if(count_q==0||overflow_q||count_q>4)begin
                        no_target<=count_q==0;result_valid<=1;status<=2;error<=16'h0201;state<=PUBLISH;
                    end else if(box_q[15:0]==0||box_q[31:16]==0||
                        box_q[47:32]>=160||box_q[63:48]>=90||
                        box_q[47:32]<=box_q[15:0]||box_q[63:48]<=box_q[31:16])begin
                        result_valid<=1;status<=2;error<=16'h0202;state<=PUBLISH;
                    end else begin
                        xmin<={box_q[7:0],3'b0};xmax<={box_q[39:32],3'b0};
                        ymin<={box_q[22:16],3'b0};ymax<={box_q[54:48],3'b0};
                        roi_width<=(box_q[47:32]-box_q[15:0])<<3;
                        roi_height<=(box_q[63:48]-box_q[31:16])<<3;
                        // Exact frozen training crop: no expansion or clipping.
                        roi_u<=0;roi_v<=0;roi_index<=0;state<=EXPAND_CHECK;
                    end
                end
                EXPAND_CHECK:begin
                    // VALIDATE already rejected source-border/malformed boxes.
                    roi_left<=xmin;roi_top<=ymin;source_x<=xmin;source_y<=ymin;
                    map_x_remainder<={2'd0,roi_width};map_y_remainder<={3'd0,roi_height};
                    state<=MAP_Y;
                end
                MAP_Y:if(map_y_remainder>=192)begin
                    map_y_remainder<=map_y_remainder-13'd192;source_y<=source_y+1'b1;
                end else state<=MAP_X;
                MAP_X:if(map_x_remainder>=192)begin
                    map_x_remainder<=map_x_remainder-13'd192;source_x<=source_x+1'b1;
                end else begin wait_count<=0;state<=PIXEL_REQ;end
                PIXEL_REQ:begin
                    if(pixel_ready)begin
                        wait_count<=0;
                        if(pixel_valid)begin captured_pixel<=pixel_y8;state<=PIXEL_STORE;end
                        else state<=PIXEL_WAIT;
                    end else if(wait_count>=PIXEL_TIMEOUT-1)source_lock(16'h1001);
                    else wait_count<=wait_count+1'b1;
                end
                PIXEL_WAIT:begin
                    if(pixel_valid)begin captured_pixel<=pixel_y8;wait_count<=0;state<=PIXEL_STORE;end
                    else if(wait_count>=PIXEL_TIMEOUT-1)source_lock(16'h1002);
                    else wait_count<=wait_count+1'b1;
                end
                PIXEL_STORE:begin
                    if(roi_index==9215)begin wait_count<=0;state<=CORE_START;end
                    else begin
                        roi_index<=roi_index+1'b1;
                        if(roi_u==95)begin
                            roi_u<=0;roi_v<=roi_v+1'b1;source_x<=roi_left;
                            map_x_remainder<={2'd0,roi_width};
                            map_y_remainder<=map_y_remainder+{2'd0,roi_height,1'b0};state<=MAP_Y;
                        end else begin
                            roi_u<=roi_u+1'b1;
                            map_x_remainder<=map_x_remainder+{1'd0,roi_width,1'b0};state<=MAP_X;
                        end
                    end
                end
                CORE_START:begin wait_count<=0;state<=CORE_WAIT;end
                CORE_WAIT:begin
                    if(core_done)begin
                        classifier_score<=core_score;classifier_margin<=core_margin;
                        detail_score<=core_margin>4095?12'hfff:core_margin[11:0];
                        if((core_class!=0&&core_class!=1)||(^core_class===1'bx)||
                            (^core_score===1'bx)||(^core_margin===1'bx)||(^core_sat===1'bx))begin
                            result_valid<=0;bbox_valid<=0;status<=3;error<=16'h0301;
                        end else begin
                            bbox_valid<=1;result_valid<=1;error<=0;
                            status<=core_margin<MARGIN_MIN?2'd2:core_class;
                        end
                        state<=PUBLISH;
                    end else if(wait_count>=INFER_TIMEOUT-1)begin
                        core_enable<=0;result_valid<=0;bbox_valid<=0;status<=3;error<=16'h1004;state<=PUBLISH;
                    end else wait_count<=wait_count+1'b1;
                end
                PUBLISH:begin done<=1;state<=IDLE;core_enable<=0;end
                default:source_lock(16'hffff);
            endcase
        end
    end
endmodule
