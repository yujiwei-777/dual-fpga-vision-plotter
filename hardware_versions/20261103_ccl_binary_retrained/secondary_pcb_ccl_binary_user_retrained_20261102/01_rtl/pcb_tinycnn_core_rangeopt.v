// PCB TinyCNN: 96x96 grayscale, shared-MAC, two strided 3x3 layers and
// three-class head.  Weights are fixed ROMs; the deliberately slow schedule
// trades throughput for HX1P35A DSP/BRAM usage.
module pcb_tinycnn_core #(
    // Paths are relative to this RTL source directory so TD and simulation
    // consume the same checked-in model artifacts.
    parameter WEIGHTS_MEM="../td_project/model/pcb_tinycnn_weights.mem",
    parameter BIASES_MEM="../td_project/model/pcb_tinycnn_bias.mem",
    parameter FIRST_MEM="../td_project/model/pcb_tinycnn_first.mem",
    parameter NEXT_MEM="../td_project/model/pcb_tinycnn_next.mem",
    parameter TAPS_MEM="../td_project/model/pcb_tinycnn_taps.mem"
)(
    input wire clk,input wire rst_n,input wire start,
    input wire pixel_we,input wire [13:0] pixel_addr,input wire [7:0] pixel_gray,
    output reg busy,output reg done,output reg [1:0] class_id,
    output reg [7:0] score,output reg [15:0] margin,output reg [15:0] saturation_count
);
    localparam integer C1=8,C2=12;
    reg signed [7:0] weights [0:971];
    reg signed [31:0] biases [0:22];
    (* ram_style="bram" *) reg [7:0] input_mem [0:9215];
    (* ram_style="bram" *) reg signed [15:0] f1 [0:18431];
    (* ram_style="bram" *) reg signed [15:0] f2 [0:6911];
    reg [9:0] first_tap[0:22],next_tap[0:971];
    reg [7:0] tap_desc[0:971];
    initial begin
        $readmemh(WEIGHTS_MEM,weights); $readmemh(BIASES_MEM,biases);
        $readmemh(FIRST_MEM,first_tap); $readmemh(NEXT_MEM,next_tap); $readmemh(TAPS_MEM,tap_desc);
    end
    reg [4:0] state;
    localparam S_IDLE=0,S_C1_INIT=1,S_C1_MAC=2,S_C1_STORE=3,
               S_C2_INIT=4,S_C2_MAC=5,S_C2_STORE=6,S_HEAD_INIT=7,
               S_HEAD_MAC=8,S_HEAD_STORE=9,S_FINISH=10,
               S_SORT01=11,S_SORT2=12,S_MARGIN=13;
    reg [6:0] x,y; reg [3:0] oc;
    reg [9:0] tap;
    wire [3:0] ic=tap_desc[tap][3:0];
    wire [1:0] kx=tap_desc[tap][5:4],ky=tap_desc[tap][7:6];
    reg [3:0] hclass; reg [9:0] hindex; reg signed [31:0] acc;
    reg [7:0] input_q;
    reg signed [15:0] f1_q,f2_q;
    reg operand_in_range_q;
    reg signed [7:0] w_q;
    // A nonzero tap now occupies read/product/accumulate phases. The
    // product register is written before it can be consumed, including after
    // reset, so it need not reset and may map to the DSP output register.
    reg [1:0] mac_phase;
    reg signed [23:0] mac_product_q;
    // One multiplier is time-shared by both convolutions and the head.
    // Each RAM has its own unreset synchronous output register. Select the
    // operand AFTER these registers; combining arrays/padding before one
    // shared register makes TD implement the maps as distributed RAM.
    wire signed [15:0] a_q = state==S_HEAD_MAC ? f2_q :
        !operand_in_range_q ? 16'sd0 :
        state==S_C1_MAC ? $signed({8'd0,input_q}) : f1_q;
    wire signed [23:0] mac_product = a_q * w_q;
    // Explicit signed extension preserves the original INT32 modulo sum.
    wire signed [31:0] mac_addend = {{8{mac_product_q[23]}},mac_product_q};
    reg signed [31:0] logits [0:2];
    reg signed [31:0] best_logit,second_logit,logit_margin;
    reg [1:0] winner;
    wire signed [9:0] ix=$signed({2'b0,x,1'b0})+$signed({8'd0,kx})-10'sd1;
    wire signed [9:0] iy=$signed({2'b0,y,1'b0})+$signed({8'd0,ky})-10'sd1;
    wire input_in_range=ix>=0 && iy>=0 && ix<96 && iy<96;
    // C2 coordinates are x/y in 0..23 and kx/ky in 0..3.  Keep the
    // border test independent of the address adders so the RAM chip-select
    // path does not inherit the ix/iy arithmetic cone.  This is exactly
    // equivalent to -1 <= ix,iy < 48 for this layer.
    wire f1_in_range= !((x==7'd0  && kx==2'd0) ||
                        (x==7'd23 && kx==2'd3) ||
                        (y==7'd0  && ky==2'd0) ||
                        (y==7'd23 && ky==2'd3));
    // Explicit shifts/adds keep address generation out of DSP blocks.
    wire [13:0] input_addr_raw=({7'd0,iy[6:0]}<<6)+({7'd0,iy[6:0]}<<5)+{7'd0,ix[6:0]};
    wire [13:0] input_addr=input_in_range ? input_addr_raw : 14'd0;
    wire [14:0] f1_addr_raw=({8'd0,iy[6:0]}<<8)+({8'd0,iy[6:0]}<<7)+({8'd0,ix[6:0]}<<3)+{11'd0,ic};
    wire [14:0] f1_addr=f1_in_range ? f1_addr_raw : 15'd0;
    wire [12:0] f2_addr=({3'd0,hindex}<<3)+({3'd0,hindex}<<2)+{9'd0,ic};
    wire [14:0] f1_write_addr=({8'd0,y}<<8)+({8'd0,y}<<7)+({8'd0,x}<<3)+{11'd0,oc};
    wire [12:0] f2_write_addr=({6'd0,y}<<8)+({6'd0,y}<<5)+({6'd0,x}<<3)+({6'd0,x}<<2)+{9'd0,oc};
    always @(posedge clk) begin
        if(rst_n && pixel_we && !busy && pixel_addr<9216) input_mem[pixel_addr]<=pixel_gray;
        if(state==S_C1_MAC) input_q<=input_mem[input_addr];
        if(state==S_C2_MAC) f1_q<=f1[f1_addr];
        if(state==S_HEAD_MAC) f2_q<=f2[f2_addr];
        operand_in_range_q<=state==S_C1_MAC ? input_in_range : f1_in_range;
        if(state==S_C1_MAC || state==S_C2_MAC || state==S_HEAD_MAC) w_q<=weights[tap];
        if((state==S_C1_MAC || state==S_C2_MAC || state==S_HEAD_MAC) && mac_phase==2'd1)
            mac_product_q<=mac_product;
        if(rst_n && state==S_C1_STORE)
            f1[f1_write_addr] <= acc<0 ? 16'sd0 : acc>32767 ? 16'sd32767 : acc[15:0];
        if(rst_n && state==S_C2_STORE)
            f2[f2_write_addr] <= acc<0 ? 16'sd0 : acc>32767 ? 16'sd32767 : acc[15:0];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0;done<=0;state<=S_IDLE;class_id<=0;score<=0;margin<=0;
            saturation_count<=0;x<=0;y<=0;oc<=0;tap<=0;hclass<=0;hindex<=0;acc<=0;mac_phase<=2'd0;
            best_logit<=0;second_logit<=0;logit_margin<=0;winner<=0;
        end else begin
            done<=0;
            case(state)
                S_IDLE: if(start) begin busy<=1; saturation_count<=0; x<=0;y<=0;oc<=0;state<=S_C1_INIT;end
                S_C1_INIT: begin
                    acc<=biases[oc];tap<=first_tap[oc];mac_phase<=2'd0;
                    state<=first_tap[oc]==1023 ? S_C1_STORE : S_C1_MAC;
                end
                S_C1_MAC: begin
                    if(mac_phase==2'd0) mac_phase<=2'd1;
                    else if(mac_phase==2'd1) mac_phase<=2'd2;
                    else begin
                    mac_phase<=2'd0; acc<=acc+mac_addend;
                    if(next_tap[tap]==1023) state<=S_C1_STORE; else tap<=next_tap[tap];
                    end
                end
                S_C1_STORE: begin
                    if (acc > 32767) saturation_count <= saturation_count + 1'b1;
                    if(oc==C1-1) begin oc<=0;if(x==47) begin x<=0;if(y==47) begin y<=0;state<=S_C2_INIT;end else begin y<=y+1'b1;state<=S_C1_INIT;end end else begin x<=x+1'b1;state<=S_C1_INIT;end end else begin oc<=oc+1'b1;state<=S_C1_INIT;end
                end
                S_C2_INIT: begin
                    acc<=biases[8+oc];tap<=first_tap[8+oc];mac_phase<=2'd0;
                    state<=first_tap[8+oc]==1023 ? S_C2_STORE : S_C2_MAC;
                end
                S_C2_MAC: begin
                    if(mac_phase==2'd0) mac_phase<=2'd1;
                    else if(mac_phase==2'd1) mac_phase<=2'd2;
                    else begin
                    mac_phase<=2'd0; acc<=acc+mac_addend;
                    if(next_tap[tap]==1023) state<=S_C2_STORE; else tap<=next_tap[tap];
                    end
                end
                S_C2_STORE: begin
                    if (acc > 32767) saturation_count <= saturation_count + 1'b1;
                    if(oc==C2-1) begin oc<=0;if(x==23) begin x<=0;if(y==23) begin y<=0;hclass<=0;hindex<=0;state<=S_HEAD_INIT;end else begin y<=y+1'b1;state<=S_C2_INIT;end end else begin x<=x+1'b1;state<=S_C2_INIT;end end else begin oc<=oc+1'b1;state<=S_C2_INIT;end
                end
                S_HEAD_INIT: begin
                    acc<=biases[20+hclass];hindex<=0;tap<=first_tap[20+hclass];mac_phase<=2'd0;
                    state<=first_tap[20+hclass]==1023 ? S_HEAD_STORE : S_HEAD_MAC;
                end
                S_HEAD_MAC: begin
                    if(mac_phase==2'd0) mac_phase<=2'd1;
                    else if(mac_phase==2'd1) mac_phase<=2'd2;
                    else begin
                    mac_phase<=2'd0; acc<=acc+mac_addend;
                    if(next_tap[tap]==1023) begin
                        if(hindex==575) state<=S_HEAD_STORE;
                        else begin hindex<=hindex+1'b1;tap<=first_tap[20+hclass];end
                    end else tap<=next_tap[tap];
                    end
                end
                S_HEAD_STORE: begin logits[hclass]<=acc; if(hclass==2)state<=S_SORT01;else begin hclass<=hclass+1'b1;hindex<=0;state<=S_HEAD_INIT;end end
                // Register each sorting/comparison stage. The previous
                // sort -> subtraction -> saturation chain exceeded 8 ns.
                // Strict comparisons preserve NORMAL then MISSING tie order.
                S_SORT01: begin
                    if(logits[1]>logits[0]) begin
                        best_logit<=logits[1];second_logit<=logits[0];winner<=1;
                    end else begin
                        best_logit<=logits[0];second_logit<=logits[1];winner<=0;
                    end
                    state<=S_SORT2;
                end
                S_SORT2: begin
                    if(logits[2]>best_logit) begin
                        second_logit<=best_logit;best_logit<=logits[2];winner<=2;
                    end else if(logits[2]>second_logit) second_logit<=logits[2];
                    state<=S_MARGIN;
                end
                S_MARGIN: begin logit_margin<=best_logit-second_logit;state<=S_FINISH;end
                S_FINISH: begin
                    class_id<=winner;
                    if (best_logit <= 0) score <= 0;
                    else if (best_logit > 32'sd255) score <= 8'hff;
                    else score <= best_logit[7:0];
                    if (logit_margin <= 0) margin <= 0;
                    else if (logit_margin > 32'sd65535) margin <= 16'hffff;
                    else margin <= logit_margin[15:0];
                    busy<=0;done<=1;state<=S_IDLE;
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
