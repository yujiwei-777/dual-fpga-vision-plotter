`timescale 1ns/1ps
// Pose7 GOOD-only inference. No search, registration, FC or online photometry.
// External synchronous workspace, one combinational signed16*8 MAC product.
// Packed byte layout: bank1 ROI 0..4607; bank0 Conv1 0..4607;
// bank1 Conv2 4608..5759; bank1 spatial anomaly map 5760..6047.
// A source request accepted by pixel_ready owns the frame through pixel_valid.
// Cancel drains that response; any source/drain timeout locks until raw reset.
module pcb_pose7_core #(
    parameter WEIGHTS_MEM="../model/pose7_96x96/weights.mem",
    parameter BIASES_MEM="../model/pose7_96x96/biases.mem",
    parameter CENTRE_MEM="../model/pose7_96x96/feature_centre.mem",
    parameter TOLERANCE_MEM="../model/pose7_96x96/feature_tolerance.mem",
    parameter ORIENTATION_MEM="../model/pose7_96x96/orientation_reference.mem",
    parameter integer PIXEL_TIMEOUT=4096,
    parameter integer ABORT_TIMEOUT=8192,
    parameter integer PASS_THRESHOLD=106,
    parameter integer FAIL_THRESHOLD=205
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
    output wire [15:0] outline_support,
    output wire pixel_request,
    output wire [10:0] pixel_x,
    output wire [9:0] pixel_y,
    input wire pixel_ready,pixel_valid,
    input wire [7:0] pixel_y8,
    output reg ws_we,ws_wbank,
    output reg [14:0] ws_waddr,
    output reg [15:0] ws_wdata,
    output reg ws_rd_bank,
    output reg [14:0] ws_rd_addr,
    input wire [15:0] ws_rd_data,
    output reg signed [15:0] mac_a,
    output reg signed [7:0] mac_w,
    input wire signed [23:0] mac_product_ext,
    output wire [7:0] phase,
    output reg [47:0] cycles
);
    localparam [5:0] IDLE=0,VALIDATE=1,MAP_Y=2,MAP_X=3,
        PIXEL_REQ=4,PIXEL_WAIT=5,PIXEL_STORE=6,
        THUMB_ADDR=7,THUMB_READ=8,THUMB_NEXT=9,
        BIAS_ADDR=10,BIAS_READ=11,TAP_ADDR=12,TAP_READ=13,
        MUL_CAPTURE=14,ACCUMULATE=15,QUANTIZE=16,FEATURE_WRITE=17,
        ANOMALY_ADDR=18,ANOMALY_READ=19,ANOMALY_WRITE=20,
        WINDOW_ADDR=21,WINDOW_READ=22,WINDOW_NEXT=23,
        PUBLISH=24,DRAIN=25,LOCKED=26,
        CONV_OPERAND=27,THUMB_OPERAND=28,HEAD_OPERAND=29;
    localparam integer WAIT_LIMIT=PIXEL_TIMEOUT>ABORT_TIMEOUT?PIXEL_TIMEOUT:ABORT_TIMEOUT;
    localparam integer WAIT_BITS=WAIT_LIMIT>1?$clog2(WAIT_LIMIT+1):1;
    reg [5:0] state;
    reg signed [7:0] weight_q;
    reg signed [31:0] bias_q;
    reg [7:0] centre_q,tolerance_q,orientation_q;
    reg [31:0] job_q;
    reg [63:0] box_q;
    reg [2:0] count_q;
    reg overflow_q,truncated_q;
    reg [10:0] roi_width,source_x;
    reg [9:0] roi_height,source_y;
    reg [6:0] roi_u,roi_v;
    reg [13:0] roi_index;
    reg [12:0] map_x_remainder,map_y_remainder;
    reg read_pending;
    reg [WAIT_BITS-1:0] wait_count;
    reg [7:0] captured_pixel,packed_low;
    // PCB-only operand captures separate synchronous workspace output/mux
    // delay from the MAC, thumbnail SAD and anomaly arithmetic. Source indices
    // stay fixed through consumption; read-port addresses may then be released.
    reg [7:0] conv_pixel_q,thumb_pixel_q,feature_byte_q;
    reg [7:0] centre_operand_q,tolerance_operand_q,orientation_operand_q;

    // Four thumbnail passes: sums for each direction, then centered SAD each.
    reg [1:0] thumb_pass;
    reg [8:0] thumb_index;
    reg [16:0] thumb_sum0,thumb_sum180;
    reg [8:0] thumb_mean0,thumb_mean180;
    reg [16:0] reference_sum;
    reg [8:0] reference_mean;
    reg [17:0] thumb_cost0,thumb_cost180;
    reg orientation_flip;
    wire thumb_reverse=thumb_pass[0];
    wire [6:0] thumb_u3={thumb_index[4:0],1'b0}+{2'd0,thumb_index[4:0]};
    wire [6:0] thumb_v6={thumb_index[8:5],2'b0}+{1'b0,thumb_index[8:5],1'b0};
    wire [6:0] thumb_x=thumb_reverse?7'd94-thumb_u3:thumb_u3+7'd1;
    wire [6:0] thumb_y=thumb_reverse?7'd92-thumb_v6:thumb_v6+7'd3;
    wire [13:0] thumb_linear=({7'd0,thumb_y}<<6)+({7'd0,thumb_y}<<5)+thumb_x;
    wire [7:0] thumb_pixel=thumb_linear[0]?ws_rd_data[15:8]:ws_rd_data[7:0];
    wire [8:0] selected_thumb_mean=thumb_reverse?thumb_mean180:thumb_mean0;
    wire signed [10:0] thumb_difference=$signed({3'd0,thumb_pixel_q})-
        $signed({2'd0,selected_thumb_mean})-$signed({3'd0,orientation_operand_q})+$signed({2'd0,reference_mean});
    wire [10:0] thumb_absolute=thumb_difference[10]?-thumb_difference:thumb_difference;

    // One serial convolution controller, CHW output order for both layers.
    reg layer;
    reg [1:0] out_channel,in_channel,kernel_x,kernel_y;
    reg [5:0] out_x,out_y;
    reg [13:0] output_index;
    reg signed [31:0] accumulator;
    reg signed [23:0] product_q;
    reg [7:0] activation;
    wire signed [8:0] tap_x=$signed({2'd0,out_x,1'b0})+$signed({7'd0,kernel_x})-9'sd1;
    wire signed [8:0] tap_y=$signed({2'd0,out_y,1'b0})+$signed({7'd0,kernel_y})-9'sd1;
    wire tap_inside=tap_x>=0&&tap_y>=0&&tap_x<(layer?9'sd48:9'sd96)&&tap_y<(layer?9'sd48:9'sd96);
    wire [6:0] input_x=(!layer&&orientation_flip)?7'd95-tap_x[6:0]:tap_x[6:0];
    wire [6:0] input_y=(!layer&&orientation_flip)?7'd95-tap_y[6:0]:tap_y[6:0];
    wire [13:0] conv1_input_linear=({7'd0,input_y}<<6)+({7'd0,input_y}<<5)+input_x;
    wire [13:0] conv2_input_linear=({12'd0,in_channel}<<11)+({12'd0,in_channel}<<8)+
        ({7'd0,input_y}<<5)+({7'd0,input_y}<<4)+input_x;
    wire [13:0] input_linear=layer?conv2_input_linear:conv1_input_linear;
    wire [7:0] input_byte=input_linear[0]?ws_rd_data[15:8]:ws_rd_data[7:0];
    wire [7:0] kernel_linear={4'd0,kernel_y,1'b0}+{6'd0,kernel_y}+{6'd0,kernel_x};
    wire [7:0] c1_weight_address=({6'd0,out_channel}<<3)+out_channel+kernel_linear;
    wire [7:0] c2_weight_address=8'd36+({6'd0,out_channel}<<5)+({6'd0,out_channel}<<2)+
        ({6'd0,in_channel}<<3)+in_channel+kernel_linear;
    wire [7:0] weight_address=layer?c2_weight_address:c1_weight_address;
    wire [2:0] bias_address={layer,out_channel};
    wire last_tap=kernel_x==2&&kernel_y==2&&(!layer||in_channel==3);
    wire [5:0] output_last=layer?6'd23:6'd47;
    wire signed [31:0] rounded_accumulator=accumulator+32'sd64;
    wire signed [31:0] shifted_accumulator=rounded_accumulator>>>7;

    reg [9:0] spatial_index;
    reg [1:0] anomaly_channel;
    reg [7:0] anomaly_max,anomaly_value;
    wire [11:0] feature_linear=({10'd0,anomaly_channel}<<9)+({10'd0,anomaly_channel}<<6)+spatial_index;
    wire [7:0] feature_byte=feature_linear[0]?ws_rd_data[15:8]:ws_rd_data[7:0];
    wire [8:0] feature_difference=feature_byte_q>=centre_operand_q?{1'b0,feature_byte_q}-{1'b0,centre_operand_q}:
        {1'b0,centre_operand_q}-{1'b0,feature_byte_q};
    wire [7:0] feature_excess=feature_difference>{1'b0,tolerance_operand_q}?feature_difference-{1'b0,tolerance_operand_q}:8'd0;
    wire [7:0] current_anomaly=feature_excess>anomaly_max?feature_excess:anomaly_max;
    reg [4:0] window_x,window_y;
    reg [1:0] window_tap;
    reg [9:0] window_sum,score_max;
    reg [4:0] peak_x,peak_y;
    wire [5:0] anomaly_x={1'b0,window_x}+window_tap[0];
    wire [5:0] anomaly_y={1'b0,window_y}+window_tap[1];
    wire [9:0] window_linear=({4'd0,anomaly_y}<<4)+({4'd0,anomaly_y}<<3)+anomaly_x;
    wire [7:0] window_byte=window_linear[0]?ws_rd_data[15:8]:ws_rd_data[7:0];
    wire [9:0] window_total=window_sum+{2'd0,window_byte};

    (* ram_style="block" *) reg signed [7:0] weights[0:179];
    (* ram_style="block" *) reg signed [31:0] biases[0:7];
    (* ram_style="block" *) reg [7:0] centres[0:2303];
    (* ram_style="block" *) reg [7:0] tolerances[0:2303];
    (* ram_style="block" *) reg [7:0] orientation[0:511];
    initial begin
        $readmemh(WEIGHTS_MEM,weights);$readmemh(BIASES_MEM,biases);
        $readmemh(CENTRE_MEM,centres);$readmemh(TOLERANCE_MEM,tolerances);
        $readmemh(ORIENTATION_MEM,orientation);
    end
    always @(posedge clk) begin
        weight_q<=weights[weight_address];bias_q<=biases[bias_address];
        centre_q<=centres[feature_linear];tolerance_q<=tolerances[feature_linear];
        orientation_q<=orientation[thumb_index];
    end

    wire active=state!=IDLE;
    wire external_abort=cancel||(start&&active);
    wire pixel_accept=pixel_request&&pixel_ready;
    wire accepted_response=pixel_valid&&(read_pending||pixel_accept);
    assign busy=active;
    assign frame_lock=active;
    assign phase={2'd0,state};
    assign outline_support=16'd0;
    assign pixel_request=state==PIXEL_REQ&&!external_abort;
    assign pixel_x=source_x;
    assign pixel_y=source_y;

    always @* begin
        ws_we=0;ws_wbank=0;ws_waddr=0;ws_wdata=0;
        ws_rd_bank=0;ws_rd_addr=0;
        case(state)
            PIXEL_STORE:begin
                ws_we=roi_index[0];ws_wbank=1;ws_waddr={2'd0,roi_index[13:1]};
                ws_wdata={captured_pixel,packed_low};
            end
            THUMB_ADDR,THUMB_READ:begin ws_rd_bank=1;ws_rd_addr={2'd0,thumb_linear[13:1]};end
            TAP_ADDR,TAP_READ:begin ws_rd_bank=!layer;ws_rd_addr=tap_inside?{2'd0,input_linear[13:1]}:15'd0;end
            FEATURE_WRITE:begin
                ws_we=output_index[0];ws_wbank=layer;
                ws_waddr=(layer?15'd4608:15'd0)+{2'd0,output_index[13:1]};
                ws_wdata={activation,packed_low};
            end
            ANOMALY_ADDR,ANOMALY_READ:begin
                ws_rd_bank=1;ws_rd_addr=15'd4608+{4'd0,feature_linear[11:1]};
            end
            ANOMALY_WRITE:begin
                ws_we=spatial_index[0];ws_wbank=1;ws_waddr=15'd5760+{6'd0,spatial_index[9:1]};
                ws_wdata={anomaly_value,packed_low};
            end
            WINDOW_ADDR,WINDOW_READ:begin ws_rd_bank=1;ws_rd_addr=15'd5760+{6'd0,window_linear[9:1]};end
            default:begin end
        endcase
        if(external_abort)ws_we=0;
    end

    task source_lock;
        input [15:0] code;
        begin
            state<=LOCKED;done<=1;result_valid<=0;bbox_valid<=0;status<=3;error<=code;
        end
    endtask
    task begin_convolution;
        begin
            layer<=0;out_channel<=0;out_x<=0;out_y<=0;output_index<=0;
            in_channel<=0;kernel_x<=0;kernel_y<=0;state<=BIAS_ADDR;
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state<=IDLE;job_q<=0;box_q<=0;count_q<=0;overflow_q<=0;truncated_q<=0;
            done<=0;result_valid<=0;no_target<=0;status<=2;error<=0;bbox_valid<=0;
            xmin<=0;xmax<=0;ymin<=0;ymax<=0;detail_score<=0;cycles<=0;
            roi_width<=0;roi_height<=0;source_x<=0;source_y<=0;roi_u<=0;roi_v<=0;roi_index<=0;
            map_x_remainder<=0;map_y_remainder<=0;read_pending<=0;wait_count<=0;
            captured_pixel<=0;packed_low<=0;conv_pixel_q<=0;thumb_pixel_q<=0;feature_byte_q<=0;
            centre_operand_q<=0;tolerance_operand_q<=0;orientation_operand_q<=0;
            thumb_pass<=0;thumb_index<=0;
            thumb_sum0<=0;thumb_sum180<=0;thumb_mean0<=0;thumb_mean180<=0;
            reference_sum<=0;reference_mean<=0;
            thumb_cost0<=0;thumb_cost180<=0;orientation_flip<=0;
            layer<=0;out_channel<=0;in_channel<=0;kernel_x<=0;kernel_y<=0;out_x<=0;out_y<=0;
            output_index<=0;accumulator<=0;product_q<=0;activation<=0;mac_a<=0;mac_w<=0;
            spatial_index<=0;anomaly_channel<=0;anomaly_max<=0;anomaly_value<=0;
            window_x<=0;window_y<=0;window_tap<=0;window_sum<=0;score_max<=0;peak_x<=0;peak_y<=0;
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
                result_valid<=0;bbox_valid<=0;no_target<=0;status<=3;
                error<=cancel?16'h0002:16'h0003;wait_count<=0;
                mac_a<=0;mac_w<=0;
                if(read_pending&&!pixel_valid)state<=DRAIN;
                else begin state<=IDLE;done<=1;end
            end else case(state)
                IDLE:begin
                    if(cancel)begin result_valid<=0;bbox_valid<=0;end
                    else if(start)begin
                        job_q<=job_id;box_q<=I_ccl_boxes[63:0];count_q<=I_ccl_count;
                        overflow_q<=I_ccl_overflow;truncated_q<=I_ccl_truncated;
                        result_valid<=0;bbox_valid<=0;no_target<=0;detail_score<=0;status<=2;error<=0;
                        xmin<=0;xmax<=0;ymin<=0;ymax<=0;cycles<=0;wait_count<=0;
                        read_pending<=0;orientation_flip<=0;
                        if(!frame_valid||!model_valid)begin done<=1;status<=3;error<=16'h0101;end
                        else state<=VALIDATE;
                    end
                end
                VALIDATE:begin
                    // CCL already ranks by area and enforces component quality.
                    // Source border touch, malformed/empty box and overflow fail closed.
                    if(count_q==0||overflow_q||count_q>4)begin
                        no_target<=count_q==0;result_valid<=1;status<=2;error<=16'h0201;state<=PUBLISH;
                    end else if(box_q[15:0]==0||box_q[31:16]==0||box_q[47:32]>=160||box_q[63:48]>=90||
                        box_q[47:32]<=box_q[15:0]||box_q[63:48]<=box_q[31:16])begin
                        result_valid<=1;status<=2;error<=16'h0202;state<=PUBLISH;
                    end else begin
                        xmin<={box_q[7:0],3'b0};xmax<={box_q[39:32],3'b0};
                        ymin<={box_q[22:16],3'b0};ymax<={box_q[54:48],3'b0};
                        roi_width<=(box_q[47:32]-box_q[15:0])<<3;
                        roi_height<=(box_q[63:48]-box_q[31:16])<<3;
                        source_x<={box_q[7:0],3'b0};source_y<={box_q[22:16],3'b0};
                        map_x_remainder<=(box_q[47:32]-box_q[15:0])<<3;
                        map_y_remainder<=(box_q[63:48]-box_q[31:16])<<3;
                        roi_u<=0;roi_v<=0;roi_index<=0;state<=MAP_Y;
                    end
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
                    if(!roi_index[0])packed_low<=captured_pixel;
                    if(roi_index==9215)begin
                        thumb_pass<=0;thumb_index<=0;thumb_sum0<=0;thumb_sum180<=0;reference_sum<=0;
                        thumb_cost0<=0;thumb_cost180<=0;state<=THUMB_ADDR;
                    end else begin
                        roi_index<=roi_index+1'b1;
                        if(roi_u==95)begin
                            roi_u<=0;roi_v<=roi_v+1'b1;source_x<=xmin;map_x_remainder<=roi_width;
                            map_y_remainder<=map_y_remainder+{2'd0,roi_height,1'b0};state<=MAP_Y;
                        end else begin
                            roi_u<=roi_u+1'b1;map_x_remainder<=map_x_remainder+{1'd0,roi_width,1'b0};state<=MAP_X;
                        end
                    end
                end
                THUMB_ADDR:state<=THUMB_READ;
                THUMB_READ:begin
                    thumb_pixel_q<=thumb_pixel;orientation_operand_q<=orientation_q;state<=THUMB_OPERAND;
                end
                THUMB_OPERAND:begin
                    case(thumb_pass)
                        0:begin thumb_sum0<=thumb_sum0+{9'd0,thumb_pixel_q};reference_sum<=reference_sum+{9'd0,orientation_operand_q};end
                        1:thumb_sum180<=thumb_sum180+{9'd0,thumb_pixel_q};
                        2:thumb_cost0<=thumb_cost0+{7'd0,thumb_absolute};
                        3:thumb_cost180<=thumb_cost180+{7'd0,thumb_absolute};
                    endcase
                    state<=THUMB_NEXT;
                end
                THUMB_NEXT:begin
                    if(thumb_index==511)begin
                        if(thumb_pass==3)begin
                            orientation_flip<=thumb_cost180<thumb_cost0;begin_convolution();
                        end else begin
                            if(thumb_pass==1)begin
                                thumb_mean0<=(thumb_sum0+17'd256)>>9;
                                thumb_mean180<=(thumb_sum180+17'd256)>>9;
                                reference_mean<=(reference_sum+17'd256)>>9;
                            end
                            thumb_pass<=thumb_pass+1'b1;thumb_index<=0;state<=THUMB_ADDR;
                        end
                    end else begin thumb_index<=thumb_index+1'b1;state<=THUMB_ADDR;end
                end
                BIAS_ADDR:state<=BIAS_READ;
                BIAS_READ:begin
                    accumulator<=bias_q;in_channel<=0;kernel_x<=0;kernel_y<=0;state<=TAP_ADDR;
                end
                TAP_ADDR:state<=TAP_READ;
                TAP_READ:begin
                    conv_pixel_q<=input_byte;state<=CONV_OPERAND;
                end
                CONV_OPERAND:begin
                    if(!tap_inside)mac_a<=0;
                    else if(layer)mac_a<=$signed({8'd0,conv_pixel_q});
                    else mac_a<=$signed({8'd0,conv_pixel_q})-16'sd128;
                    mac_w<=weight_q;state<=MUL_CAPTURE;
                end
                MUL_CAPTURE:begin product_q<=mac_product_ext;state<=ACCUMULATE;end
                ACCUMULATE:begin
                    accumulator<=accumulator+{{8{product_q[23]}},product_q};
                    if(last_tap)state<=QUANTIZE;
                    else begin
                        if(kernel_x==2)begin
                            kernel_x<=0;
                            if(kernel_y==2)begin kernel_y<=0;in_channel<=in_channel+1'b1;end
                            else kernel_y<=kernel_y+1'b1;
                        end else kernel_x<=kernel_x+1'b1;
                        state<=TAP_ADDR;
                    end
                end
                QUANTIZE:begin
                    activation<=shifted_accumulator<0?8'd0:shifted_accumulator>255?8'd255:shifted_accumulator[7:0];
                    state<=FEATURE_WRITE;
                end
                FEATURE_WRITE:begin
                    if(!output_index[0])packed_low<=activation;
                    if(out_x==output_last&&out_y==output_last&&out_channel==3)begin
                        if(!layer)begin
                            layer<=1;out_channel<=0;out_x<=0;out_y<=0;output_index<=0;state<=BIAS_ADDR;
                        end else begin
                            spatial_index<=0;anomaly_channel<=0;anomaly_max<=0;state<=ANOMALY_ADDR;
                        end
                    end else begin
                        output_index<=output_index+1'b1;
                        if(out_x==output_last)begin
                            out_x<=0;
                            if(out_y==output_last)begin out_y<=0;out_channel<=out_channel+1'b1;end
                            else out_y<=out_y+1'b1;
                        end else out_x<=out_x+1'b1;
                        state<=BIAS_ADDR;
                    end
                end
                ANOMALY_ADDR:state<=ANOMALY_READ;
                ANOMALY_READ:begin
                    feature_byte_q<=feature_byte;centre_operand_q<=centre_q;tolerance_operand_q<=tolerance_q;
                    state<=HEAD_OPERAND;
                end
                HEAD_OPERAND:begin
                    if(anomaly_channel==3)begin anomaly_value<=current_anomaly;state<=ANOMALY_WRITE;end
                    else begin anomaly_max<=current_anomaly;anomaly_channel<=anomaly_channel+1'b1;state<=ANOMALY_ADDR;end
                end
                ANOMALY_WRITE:begin
                    if(!spatial_index[0])packed_low<=anomaly_value;
                    if(spatial_index==575)begin
                        window_x<=0;window_y<=0;window_tap<=0;window_sum<=0;score_max<=0;peak_x<=0;peak_y<=0;
                        state<=WINDOW_ADDR;
                    end else begin spatial_index<=spatial_index+1'b1;anomaly_channel<=0;anomaly_max<=0;state<=ANOMALY_ADDR;end
                end
                WINDOW_ADDR:state<=WINDOW_READ;
                WINDOW_READ:begin
                    if(window_tap==3)begin
                        if(window_total>score_max)begin score_max<=window_total;peak_x<=window_x;peak_y<=window_y;end
                        state<=WINDOW_NEXT;
                    end else begin window_sum<=window_total;window_tap<=window_tap+1'b1;state<=WINDOW_ADDR;end
                end
                WINDOW_NEXT:begin
                    if(window_x==22&&window_y==22)begin
                        detail_score<={2'd0,score_max};status<=score_max<=PASS_THRESHOLD?2'd0:score_max>=FAIL_THRESHOLD?2'd1:2'd2;
                        bbox_valid<=1;result_valid<=1;error<=0;state<=PUBLISH;
                    end else begin
                        if(window_x==22)begin window_x<=0;window_y<=window_y+1'b1;end
                        else window_x<=window_x+1'b1;
                        window_tap<=0;window_sum<=0;state<=WINDOW_ADDR;
                    end
                end
                PUBLISH:begin done<=1;state<=IDLE;mac_a<=0;mac_w<=0;end
                default:begin result_valid<=0;bbox_valid<=0;status<=3;error<=16'hffff;state<=LOCKED;done<=1;end
            endcase
        end
    end
endmodule
