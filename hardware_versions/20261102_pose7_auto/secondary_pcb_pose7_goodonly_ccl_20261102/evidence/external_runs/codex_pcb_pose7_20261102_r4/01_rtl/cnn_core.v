// Factored joint model: RGB8 64x64 HWC -> color SUM argmax plus
// maxRGB shape Conv1/8 -> Pool2 -> Conv2/16 -> Pool2 -> FC3.
// The external interface is compatible with the legacy FC4 core.
module cnn_core #(
    parameter WEIGHTS_MEM = "model/export/weights.mem",
    parameter BIASES_MEM = "model/export/biases.mem",
    parameter integer C1_SHIFT = 10,
    parameter integer C2_SHIFT = 8,
    parameter integer FC_CONF_SHIFT = 7,
    parameter integer USE_SHARED_WORKSPACE = 0,
    parameter integer EXTERNAL_MAC = 0
)(
    input wire clk,input wire rst_n,input wire pixel_we,input wire [11:0] pixel_addr,
    input wire [23:0] pixel_rgb,input wire start,
    output reg busy,output reg done,output reg [1:0] color_id,output reg [1:0] shape_id,
    output reg [7:0] color_conf,output reg [7:0] shape_conf,output reg background_reject,
    output wire ws_shape_we, output wire [11:0] ws_shape_waddr, output wire [15:0] ws_shape_wdata,
    output wire ws_f1_we, output wire [12:0] ws_f1_waddr, output wire [15:0] ws_f1_wdata,
    output wire ws_f2_we, output wire [11:0] ws_f2_waddr, output wire [15:0] ws_f2_wdata,
    output wire [1:0] ws_rd_sel, output wire [12:0] ws_rd_addr, input wire [7:0] ws_rd_data,
    output wire signed [15:0] mac_a, output wire signed [7:0] mac_w,
    input wire signed [23:0] mac_product_ext
);
    localparam integer W2_BASE=72,WF_BASE=1224;
    localparam integer SHAPE_DEPTH = USE_SHARED_WORKSPACE ? 1 : 4096;
    localparam integer FEATURE1_DEPTH = USE_SHARED_WORKSPACE ? 1 : 8192;
    localparam integer FEATURE2_DEPTH = USE_SHARED_WORKSPACE ? 1 : 4096;
    reg [7:0] shape_input [0:SHAPE_DEPTH-1];
    reg [7:0] feature1 [0:FEATURE1_DEPTH-1];
    reg [7:0] feature2 [0:FEATURE2_DEPTH-1];
    reg signed [7:0] weights [0:13511];
    reg signed [31:0] biases [0:26];
    reg signed [31:0] scores [0:2];
    reg [18:0] color_sum [0:2];
    initial begin $readmemh(WEIGHTS_MEM,weights); $readmemh(BIASES_MEM,biases); end

    localparam IDLE=0,C_SETUP=1,C_BIAS=2,C_READ=3,C_ACT=4,C_DRAIN=5,C_STORE=6,
               F_SETUP=7,F_BIAS=8,F_READ=9,F_DRAIN=11,F_STORE=12,
               CLASSIFY=13,FINISH=14,CLASSIFY_COMMIT=15;
    reg [3:0] state; reg layer; reg [4:0] px,py; reg [3:0] oc; reg [2:0] ic;
    reg [1:0] kx,ky,subpixel; reg [1:0] fc_class; reg [11:0] fc_index;
    reg signed [31:0] accumulator; reg [7:0] pool_max; reg pad_q,source_layer_q;
    reg read_valid,read_last; reg [14:0] weight_addr; reg [4:0] bias_addr;
    reg [12:0] activation_addr,output_addr; reg padding; integer ix,iy,conv_width;
    always @* begin
        ix=0;iy=0;conv_width=64;padding=0;weight_addr=0;bias_addr=0;activation_addr=0;output_addr=0;
        if(state>=F_SETUP) begin
            weight_addr=WF_BASE+fc_class*15'd4096+fc_index; bias_addr=5'd24+fc_class; activation_addr={1'b0,fc_index};
        end else begin
            conv_width=layer?32:64;
            ix=({1'b0,px}<<1)+subpixel[0]+kx-1; iy=({1'b0,py}<<1)+subpixel[1]+ky-1;
            padding=(ix<0||iy<0||ix>=conv_width||iy>=conv_width);
            if(layer) begin
                weight_addr=W2_BASE+oc*72+ic*9+ky*3+kx; bias_addr=5'd8+oc;
                if(!padding)activation_addr=(iy*32+ix)*8+ic; output_addr=(py*16+px)*16+oc;
            end else begin
                weight_addr=oc*9+ky*3+kx; bias_addr=oc;
                if(!padding)activation_addr=iy*64+ix; output_addr=(py*32+px)*8+oc;
            end
        end
    end
    reg signed [7:0] weight_q; reg signed [31:0] bias_q;
    // Register CNN memory addresses before the distributed/ERAM read.  The
    // joint model's classifier address arithmetic otherwise sits directly in
    // front of the DSP multiplier and misses the 125 MHz Ethernet clock.
    // This adds a read latency only; the valid/last pipeline below keeps the
    // accumulator and state machine aligned with the delayed sample.
    reg [14:0] weight_addr_q;
    reg [12:0] activation_addr_q;
    reg pad_issue_q, source_layer_issue_q;
    reg [7:0] shape_q,feature1_q,feature2_q;
    reg [7:0] ws_shape_low_q,ws_f1_low_q,ws_f2_low_q;
    wire [7:0] ws_shape_value = (pixel_rgb[23:16]>=pixel_rgb[15:8]&&pixel_rgb[23:16]>=pixel_rgb[7:0]) ? pixel_rgb[23:17] :
                                (pixel_rgb[15:8]>=pixel_rgb[7:0]) ? pixel_rgb[15:9] : pixel_rgb[7:1];
    reg read_valid_d1, read_valid_d2, read_last_d1, read_last_d2;
    // Address/valid pipeline. This block intentionally has only a rising
    // clock edge. The old async-reset block made the synthesis tool treat
    // every RAM read assignment as being driven from two clock edges
    // (HDL-7238), which prevented block-RAM inference.
    always @(posedge clk) begin
        if(!rst_n) begin
            weight_addr_q<=0; activation_addr_q<=0;
            read_valid_d1<=0; read_valid_d2<=0;
            read_last_d1<=0; read_last_d2<=0;
        end else begin
            weight_addr_q<=weight_addr;
            activation_addr_q<=activation_addr;
            read_valid_d1<=read_valid;
            read_valid_d2<=read_valid_d1;
            read_last_d1<=read_last;
            read_last_d2<=read_last_d1;
        end
    end

    // Synchronous read ports have no reset. Keeping the output registers out
    // of an async/sync reset cone lets PH1P infer ERAM/BRAM output registers
    // instead of expanding the activation memories into registers.
    always @(posedge clk) begin
        weight_q<=weights[weight_addr_q];
        bias_q<=biases[bias_addr];
        if(!USE_SHARED_WORKSPACE) begin
            shape_q<=shape_input[activation_addr_q[11:0]];
            feature1_q<=feature1[activation_addr_q];
            feature2_q<=feature2[activation_addr_q[11:0]];
        end
    end

    // Frame-load write port and colour accumulation remain synchronous. The
    // CNN state machine only starts after the final pixel write, so a read
    // can never race the RGB8 input buffer during inference.
    always @(posedge clk) begin
        if(!rst_n) begin
            color_sum[0]<=0; color_sum[1]<=0; color_sum[2]<=0;
        end else if(pixel_we&&!busy)begin
            if(USE_SHARED_WORKSPACE && !pixel_addr[0]) ws_shape_low_q<=ws_shape_value;
            if(!USE_SHARED_WORKSPACE) begin
                if(pixel_rgb[23:16]>=pixel_rgb[15:8]&&pixel_rgb[23:16]>=pixel_rgb[7:0])shape_input[pixel_addr]<=pixel_rgb[23:17];
                else if(pixel_rgb[15:8]>=pixel_rgb[7:0])shape_input[pixel_addr]<=pixel_rgb[15:9];
                else shape_input[pixel_addr]<=pixel_rgb[7:1];
            end
            // The 4096 RGB pixels are loaded before start is asserted.  Clear
            // the colour sums on the first write of each frame; clearing on
            // start used to erase the completed accumulation and made every
            // frame tie at color 3 (and usually fail the confidence gate).
            if(pixel_addr==12'd0) begin
                color_sum[0]<=pixel_rgb[23:17];
                color_sum[1]<=pixel_rgb[15:9];
                color_sum[2]<=pixel_rgb[7:1];
            end else begin
                color_sum[0]<=color_sum[0]+pixel_rgb[23:17];
                color_sum[1]<=color_sum[1]+pixel_rgb[15:9];
                color_sum[2]<=color_sum[2]+pixel_rgb[7:1];
            end
        end
    end
    reg signed [7:0] activation_q;
    // Conv2 consumes feature1; FC3 must consume the second pooled feature2.
    // The old selector routed every source_layer_q=1 cycle to feature1_q,
    // including F_READ/F_DRAIN, which made all 4096 FC inputs stale.
    always @* begin
        if(state>=F_SETUP) activation_q=USE_SHARED_WORKSPACE ? $signed(ws_rd_data) : $signed(feature2_q);
        // Both convolution layers use zero padding. Test padding before the
        // Conv2 source selector; otherwise padded taps read feature1[0].
        else if(pad_q) activation_q=0;
        else if(source_layer_q) activation_q=USE_SHARED_WORKSPACE ? $signed(ws_rd_data) : $signed(feature1_q);
        else activation_q=USE_SHARED_WORKSPACE ? $signed(ws_rd_data) : $signed(shape_q);
    end
    wire signed [15:0] product_internal=activation_q*weight_q;
    wire signed [15:0] product_used;
    generate if(EXTERNAL_MAC != 0) begin : g_external_mac
        assign product_used=mac_product_ext[15:0];
    end else begin : g_local_mac
        assign product_used=product_internal;
    end endgenerate
    assign mac_a={{8{activation_q[7]}},activation_q};
    assign mac_w=weight_q;
    reg signed [15:0] product_q; reg product_valid,product_last;
    wire signed [31:0] product32={{16{product_q[15]}},product_q};
    reg signed [31:0] rounded_activation; reg [7:0] quant_activation,pooled_activation,pooled_activation_q;
    always @* begin
        if(layer)rounded_activation=(accumulator+(32'sd1<<(C2_SHIFT-1)))>>>C2_SHIFT;
        else rounded_activation=(accumulator+(32'sd1<<(C1_SHIFT-1)))>>>C1_SHIFT;
        if(rounded_activation<0)quant_activation=0; else if(rounded_activation>127)quant_activation=127; else quant_activation=rounded_activation[7:0];
        pooled_activation=(quant_activation>pool_max)?quant_activation:pool_max;
    end
    // In shared-workspace mode the three activation maps are placed in one
    // byte-addressed bank owned by vision_workspace.  The local arrays remain
    // for legacy simulations, but all accesses to them are constant-pruned.
    assign ws_shape_we = USE_SHARED_WORKSPACE && pixel_we && !busy && pixel_addr[0];
    assign ws_shape_waddr = pixel_addr;
    assign ws_shape_wdata = {ws_shape_value,ws_shape_low_q};
    assign ws_f1_we = USE_SHARED_WORKSPACE && rst_n && state==C_STORE && subpixel==3 && !layer && output_addr[0];
    assign ws_f1_waddr = output_addr;
    assign ws_f1_wdata = {pooled_activation_q,ws_f1_low_q};
    assign ws_f2_we = USE_SHARED_WORKSPACE && rst_n && state==C_STORE && subpixel==3 && layer && output_addr[0];
    assign ws_f2_waddr = output_addr[11:0];
    assign ws_f2_wdata = {pooled_activation_q,ws_f2_low_q};
    assign ws_rd_sel = (state>=F_SETUP) ? 2'd2 : (source_layer_issue_q ? 2'd1 : 2'd0);
    assign ws_rd_addr = activation_addr_q;
    always @(posedge clk) begin
        if(USE_SHARED_WORKSPACE && rst_n && state==C_STORE && subpixel==3 && !layer && !output_addr[0]) ws_f1_low_q<=pooled_activation_q;
        if(USE_SHARED_WORKSPACE && rst_n && state==C_STORE && subpixel==3 && layer && !output_addr[0]) ws_f2_low_q<=pooled_activation_q;
        if(!USE_SHARED_WORKSPACE && rst_n&&state==C_STORE&&subpixel==3) begin
            if(layer) feature2[output_addr[11:0]]<=pooled_activation_q;
            else feature1[output_addr]<=pooled_activation_q;
        end
    end

    integer j; reg signed [31:0] shape_best,shape_second; reg [1:0] shape_best_id;
    reg signed [31:0] shape_best_q,shape_second_q; reg [1:0] shape_id_q;
    reg [18:0] color_best_q,color_second_q; reg [1:0] color_best_id_q;
    reg signed [32:0] shape_difference; reg [31:0] color_difference,shape_margin,color_margin;
    reg [18:0] color_pair_best_q,color_pair_second_q;
    reg [1:0] color_pair_best_id_q;
    reg [18:0] color_pair_best_next,color_pair_second_next;
    reg [1:0] color_pair_best_id_next;
    reg [18:0] color_final_best_next,color_final_second_next;
    reg [1:0] color_final_id_next;
    always @* begin
        shape_best=-32'sd2147483647-1;shape_second=-32'sd2147483647-1;shape_best_id=0;
        for(j=0;j<3;j=j+1)begin if(scores[j]>shape_best)begin shape_second=shape_best;shape_best=scores[j];shape_best_id=j;end else if(scores[j]>shape_second)shape_second=scores[j];end
        if(color_sum[1]>=color_sum[0])begin
            color_pair_best_next=color_sum[1];
            color_pair_second_next=color_sum[0];
            color_pair_best_id_next=1;
        end else begin
            color_pair_best_next=color_sum[0];
            color_pair_second_next=color_sum[1];
            color_pair_best_id_next=0;
        end
        if(color_sum[2]>=color_pair_best_q)begin
            color_final_best_next=color_sum[2];
            color_final_second_next=color_pair_best_q;
            color_final_id_next=2;
        end else if(color_sum[2]>color_pair_second_q)begin
            color_final_best_next=color_pair_best_q;
            color_final_second_next=color_sum[2];
            color_final_id_next=color_pair_best_id_q;
        end else begin
            color_final_best_next=color_pair_best_q;
            color_final_second_next=color_pair_second_q;
            color_final_id_next=color_pair_best_id_q;
        end
        shape_difference=$signed({shape_best_q[31],shape_best_q})-$signed({shape_second_q[31],shape_second_q});
        color_difference={1'b0,color_best_q}-{1'b0,color_second_q};
        shape_margin=(shape_difference<=0)?0:(shape_difference>>>FC_CONF_SHIFT); color_margin=(color_difference>>>8);
    end

    integer z;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;busy<=0;done<=0;color_id<=0;shape_id<=0;color_conf<=0;shape_conf<=0;background_reject<=0;
            layer<=0;px<=0;py<=0;oc<=0;ic<=0;kx<=0;ky<=0;subpixel<=0;fc_class<=0;fc_index<=0;accumulator<=0;pool_max<=0;pooled_activation_q<=0;pad_q<=0;source_layer_q<=0;pad_issue_q<=0;source_layer_issue_q<=0;read_valid<=0;read_last<=0;product_q<=0;product_valid<=0;product_last<=0;shape_best_q<=0;shape_second_q<=0;shape_id_q<=0;color_best_q<=0;color_second_q<=0;
            for(z=0;z<3;z=z+1)scores[z]<=0;
            color_pair_best_q<=0;color_pair_second_q<=0;color_pair_best_id_q<=0;color_best_id_q<=0;
        end else begin
            // The registered RAM outputs (weight_q/shape_q) become valid one
            // cycle after the address issue.  read_valid_d1 is therefore the
            // matching capture enable.  Using d2 here dropped the first
            // multiply of every 3x3 dot product and shifted all FC scores,
            // which made valid objects fail the shape margin gate.
            done<=0;read_valid<=0;product_valid<=read_valid_d1;
            if(read_valid_d1)begin product_q<=product_used;product_last<=read_last_d1;end
            if(product_valid)accumulator<=accumulator+product32;
            pad_q<=pad_issue_q; source_layer_q<=source_layer_issue_q;
            case(state)
                IDLE:if(start)begin busy<=1;layer<=0;px<=0;py<=0;oc<=0;ic<=0;kx<=0;ky<=0;subpixel<=0;pool_max<=0;state<=C_SETUP;end
                C_SETUP:state<=C_BIAS;
                C_BIAS:begin accumulator<=bias_q;read_valid<=0;product_valid<=0;state<=C_READ;end
                C_READ:begin
                    pad_issue_q<=padding;source_layer_issue_q<=layer;read_valid<=1;read_last<=(kx==2&&ky==2&&ic==(layer?7:0));
                    if(kx==2)begin kx<=0;if(ky==2)begin ky<=0;if(ic==(layer?7:0))begin ic<=0;state<=C_DRAIN;end else begin ic<=ic+1'b1;state<=C_READ;end end else begin ky<=ky+1'b1;state<=C_READ;end end else begin kx<=kx+1'b1;state<=C_READ;end
                end
                C_DRAIN:if(product_valid&&product_last)state<=C_ACT;
                C_ACT:begin pooled_activation_q<=pooled_activation;state<=C_STORE;end
                C_STORE:begin
                    if(subpixel==3)begin subpixel<=0;pool_max<=0;state<=C_SETUP;if(oc==(layer?15:7))begin oc<=0;if(px==(layer?15:31))begin px<=0;if(py==(layer?15:31))begin py<=0;if(layer)begin fc_class<=0;fc_index<=0;state<=F_SETUP;end else layer<=1;end else py<=py+1'b1;end else px<=px+1'b1;end else oc<=oc+1'b1;end
                    else begin subpixel<=subpixel+1'b1;pool_max<=pooled_activation_q;state<=C_SETUP;end
                end
                F_SETUP:state<=F_BIAS;
                F_BIAS:begin accumulator<=bias_q;read_valid<=0;product_valid<=0;state<=F_READ;end
                F_READ:begin source_layer_issue_q<=1;read_valid<=1;read_last<=(fc_index==4095);if(fc_index==4095)begin fc_index<=0;state<=F_DRAIN;end else fc_index<=fc_index+1'b1;end
                F_DRAIN:if(product_valid&&product_last)state<=F_STORE;
                F_STORE:begin scores[fc_class]<=accumulator;if(fc_class==2)state<=CLASSIFY;else begin fc_class<=fc_class+1'b1;state<=F_SETUP;end end
                CLASSIFY:begin
                    // Stage one resolves classes 0 and 1.  >= makes class 1
                    // win ties, matching the original ascending-index scan.
                    shape_best_q<=shape_best;shape_second_q<=shape_second;shape_id_q<=shape_best_id;
                    color_pair_best_q<=color_pair_best_next;
                    color_pair_second_q<=color_pair_second_next;
                    color_pair_best_id_q<=color_pair_best_id_next;
                    state<=CLASSIFY_COMMIT;
                end
                CLASSIFY_COMMIT:begin
                    // Stage two inserts class 2 into the registered top two.
                    color_best_q<=color_final_best_next;color_second_q<=color_final_second_next;
                    color_best_id_q<=color_final_id_next;
                    state<=FINISH;
                end
                FINISH:begin color_id<=color_best_id_q+1'b1;shape_id<=shape_id_q+1'b1;color_conf<=(color_margin>255)?8'd255:color_margin[7:0];shape_conf<=(shape_margin>255)?8'd255:shape_margin[7:0];background_reject<=0;busy<=0;done<=1;state<=IDLE;end
                default:begin state<=IDLE;busy<=0;end
            endcase
        end
    end
endmodule

