// Full-board PCB classifier for the spatial96 training contract.
//
// Input pixels are loaded as a 96x96 unsigned Y8 image through the legacy
// PCB-core loader interface.  The loader and intermediate feature maps use
// the same two-bank workspace protocol as pcb_tinycnn_core:
//   bank 1: packed input, then Conv2 output (6912 words)
//   bank 0: Conv1 output (18432 words)
// A single MAC is shared by both convolutions and the FC head.  The explicit
// read, wait, product, and accumulate phases preserve the synchronous RAM
// read latency of vision_workspace without requiring a full-frame feature
// register array.
module pcb_fullboard_spatial96 #(
    parameter WEIGHTS_MEM = "../model/fullboard/weights.mem",
    parameter BIASES_MEM = "../model/fullboard/biases.mem",
    parameter integer USE_SHARED_WORKSPACE = 1,
    parameter integer EXTERNAL_MAC = 0,
    // The convolution and pooling trunk is shared by the 3-class diagnostic
    // model and the reduced GOOD/BAD head.  Keeping this as a parameter lets
    // the binary build use a 1320-word ROM without changing the default
    // three-class source contract.
    parameter integer HEAD_CLASSES = 3,
    // Optional resource-reduced trunk. C1=8/C2=12 is the reviewed default;
    // binary candidates may use C1=8/C2=8 or the smaller C1=4/C2=4 model.
    parameter integer C1_CHANNELS = 8,
    parameter integer C2_CHANNELS = 12,
    // Quantization shifts are part of the ROM/model contract. The reviewed
    // three-class model uses 7/6/7; the binary exports use 7/7/8.
    parameter integer C1_SHIFT = 7,
    parameter integer C2_SHIFT = 6,
    parameter integer HEAD_SHIFT = 7
)(
    input wire clk,input wire rst_n,input wire start,
    input wire pixel_we,input wire [13:0] pixel_addr,input wire [7:0] pixel_gray,
    output reg busy,output reg done,output reg [1:0] class_id,
    output reg [7:0] score,output reg [15:0] margin,output wire [15:0] saturation_count,
    output wire ws_we, output wire ws_wbank, output wire [14:0] ws_waddr,
    output wire [15:0] ws_wdata,
    output wire ws_rd_bank, output wire [14:0] ws_rd_addr,
    input wire [15:0] ws_rd_data,
    output wire signed [15:0] mac_a, output wire signed [7:0] mac_w,
    input wire signed [23:0] mac_product_ext
);
    localparam integer C1=C1_CHANNELS, C2=C2_CHANNELS;
    localparam integer S_IDLE=0, S_C1_INIT=1, S_C1_MAC=2, S_C1_STORE=3,
                       S_C2_INIT=4, S_C2_MAC=5, S_C2_STORE=6,
                       S_HEAD_INIT=7, S_POOL=8, S_HEAD_MAC=9,
                       S_HEAD_STORE=10, S_SORT01=11, S_SORT2=12,
                       S_MARGIN=13, S_FINISH=14;
    localparam integer PH_SETUP=0, PH_WAIT=1, PH_PRODUCT=2, PH_ACC=3,
                       PH_SUM=4;

    // The previous version indexed the 12-Kbit weight table combinationally.
    // TD then implemented the table as distributed logic, which exhausted
    // SLICEL during placement.  Keep the same contents and address order,
    // but use a registered address and synchronous ROM output so the table
    // is inferred as ERAM.
    localparam integer HEAD_WEIGHT_BASE = C1*9 + C1*C2*9;
    localparam integer HEAD_BIAS_BASE = C1 + C2;
    localparam integer HEAD_FEATURES = C2*16;
    localparam integer WEIGHT_COUNT = HEAD_WEIGHT_BASE + HEAD_CLASSES*HEAD_FEATURES;
    localparam integer BIAS_COUNT = C1 + C2 + HEAD_CLASSES;
    (* rom_style="bram" *) reg signed [7:0] weights [0:WEIGHT_COUNT-1] /* synthesis syn_ramstyle="block_ram" */;
    (* rom_style="bram" *) reg signed [31:0] biases [0:BIAS_COUNT-1] /* synthesis syn_ramstyle="block_ram" */;
    initial begin
        $readmemh(WEIGHTS_MEM,weights);
        $readmemh(BIASES_MEM,biases);
    end

    // The non-shared branch is useful for RTL comparison only.  The routed
    // design uses vision_workspace, whose bank geometry matches these arrays.
    (* ram_style="bram" *) reg [15:0] local_bank0 [0:18431];
    (* ram_style="bram" *) reg [15:0] local_bank1 [0:6911];
    reg [15:0] local_rd_q;
    reg [7:0] input_low_q;

    reg [3:0] state;
    reg [2:0] phase;
    reg [5:0] x,y;
    reg [3:0] oc;
    reg [3:0] c2_oc;
    reg [4:0] c2_x,c2_y;
    reg [6:0] tap;
    reg [1:0] tap_kx,tap_ky;
    reg [3:0] tap_ic;
    reg [14:0] read_addr_q;
    reg read_bank_q;
    reg input_byte_select_q;
    reg operand_valid_q;
    reg [10:0] weight_addr_q;
    reg signed [7:0] weight_rom_q;
    reg [4:0] bias_addr_q;
    reg signed [31:0] bias_rom_q;
    // Break the workspace-ERAM -> shared-MAC path.  The operand is captured
    // after the synchronous workspace read, then consumed by the MAC during
    // the following PH_ACC cycle.  This preserves the tap order and values
    // while giving routing a full cycle between ERAM and the DSP input.
    // Keep this register as a real pipeline boundary.  Without the keep
    // attribute TD may retime it through the shared DSP and recreate a
    // workspace-RAM-to-DSP path in the routed netlist.
    (* keep = "true", dont_touch = "true" *) reg signed [15:0] operand_hold_q;
    // Register each completed product before the 27-bit accumulation. The
    // extra PH_SUM cycle keeps DSP delay and accumulator carry propagation in
    // separate eth125 cycles without changing tap order or arithmetic.
    (* keep = "true", dont_touch = "true" *) reg signed [23:0] product_hold_q;
    // Bounds are derived from every coefficient in the fixed MEM files and
    // the legal activation maxima, not from observed training samples.
    // C1: 192235; C2: 41714731; FC: 64916255.
    reg signed [26:0] acc;
    // Keep three physical slots for source/tool compatibility. Binary heads
    // use only slots 0 and 1; slot 2 is never written or compared.
    reg signed [19:0] logits [0:2];
    reg signed [19:0] best_logit,second_logit;
    reg [1:0] winner;
    reg signed [20:0] logit_margin;
    reg [14:0] saturation_count_q;

    // Head/pooling counters.  hindex is CHW: C[11:0], Y[3:0], X[3:0].
    reg [1:0] hclass;
    reg [7:0] hindex;
    reg [2:0] pool_dx,pool_dy;
    reg signed [21:0] pool_acc;
    reg signed [16:0] pool_value;
    reg signed [26:0] head_acc;

    wire [15:0] workspace_read_data = USE_SHARED_WORKSPACE ? ws_rd_data : local_rd_q;
    wire [7:0] input_byte = input_byte_select_q ? workspace_read_data[15:8] : workspace_read_data[7:0];
    wire signed [15:0] operand_q = state==S_C1_MAC ? $signed({8'd0,input_byte}) :
                                   state==S_HEAD_MAC ? $signed(pool_value[15:0]) :
                                                       $signed(workspace_read_data);

    // Compatibility output. In shared mode the workspace is the only
    // memory; the local read register is used by the simulation-only branch.
    assign ws_we = rst_n &&
        ((!busy && pixel_we && pixel_addr[0]) || (state==S_C1_STORE) || (state==S_C2_STORE));
    assign ws_wbank = (state==S_C1_STORE) ? 1'b0 : 1'b1;
    wire [13:0] packed_addr = pixel_addr[13:1];
    wire [15:0] packed_data = {pixel_gray,input_low_q};
    wire [14:0] c1_write_addr = ({9'd0,y} * (48*C1))+
                                 ({10'd0,x} * C1)+{11'd0,oc};
    wire [14:0] c2_write_addr = ({10'd0,c2_y} * (24*C2))+
                                 ({11'd0,c2_x} * C2)+{11'd0,c2_oc};
    assign ws_waddr = (!busy && pixel_we) ? {1'b0,packed_addr} :
                      (state==S_C1_STORE ? c1_write_addr : {1'b0,c2_write_addr});
    wire signed [20:0] conv_shifted = state==S_C1_STORE ? (acc >>> C1_SHIFT) : (acc >>> C2_SHIFT);
    wire signed [15:0] conv_store = conv_shifted < 0 ? 16'sd0 :
                                    conv_shifted > 40'sd32767 ? 16'sh7fff : conv_shifted[15:0];
    assign ws_wdata = (!busy && pixel_we) ? packed_data : conv_store;

    assign ws_rd_bank = read_bank_q;
    assign ws_rd_addr = read_addr_q;
    assign mac_a = operand_hold_q;
    assign mac_w = weight_rom_q;
    assign saturation_count = {1'b0,saturation_count_q};

    // Input pixel address for Conv1. Border taps are zero and do not need a
    // workspace read.  The image is packed low-byte/even, high-byte/odd.
    wire signed [8:0] in_x = $signed({1'b0,x,1'b0}) + $signed({7'd0,tap_kx}) - 9'sd1;
    wire signed [8:0] in_y = $signed({1'b0,y,1'b0}) + $signed({7'd0,tap_ky}) - 9'sd1;
    wire input_in_range = in_x>=0 && in_y>=0 && in_x<96 && in_y<96;
    wire [13:0] input_byte_addr = ({7'd0,in_y[6:0]}<<6)+
                                  ({7'd0,in_y[6:0]}<<5)+{7'd0,in_x[6:0]};
    wire [12:0] input_word_addr = input_byte_addr[13:1];

    // Conv2 input address.  tap_ic is the input channel and tap_kx/tap_ky
    // are the 3x3 kernel coordinates.
    wire signed [7:0] f1_x = $signed({1'b0,c2_x,1'b0})+
                             $signed({6'd0,tap_kx})-8'sd1;
    wire signed [7:0] f1_y = $signed({1'b0,c2_y,1'b0})+
                             $signed({6'd0,tap_ky})-8'sd1;
    wire f1_in_range = f1_x>=0 && f1_y>=0 && f1_x<48 && f1_y<48;
    wire [14:0] f1_addr = ({8'd0,f1_y[5:0]} * (48*C1))+
                          ({9'd0,f1_x[5:0]} * C1)+{11'd0,tap_ic};

    // One f2 word contains one signed 16-bit activation. The pool counter
    // reads 36 pixels for one pooled value, then the FC head consumes it.
    wire [3:0] pool_c = hindex[7:4];
    wire [1:0] pool_x = hindex[1:0];
    wire [1:0] pool_y = hindex[3:2];
    wire [5:0] pool_src_x = {pool_x,1'b0}+{pool_x,2'b0}+pool_dx;
    wire [5:0] pool_src_y = {pool_y,1'b0}+{pool_y,2'b0}+pool_dy;
    wire [14:0] pool_addr = ({9'd0,pool_src_y} * (24*C2))+
                             ({9'd0,pool_src_x} * C2)+{11'd0,pool_c};
    wire signed [31:0] pool_sample = $signed(workspace_read_data);

    wire signed [23:0] product_input = EXTERNAL_MAC != 0 ?
        mac_product_ext :
        operand_hold_q * $signed(weight_rom_q);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) product_hold_q <= 0;
        else if(phase==PH_ACC &&
                (state==S_C1_MAC || state==S_C2_MAC || state==S_HEAD_MAC))
            product_hold_q <= product_input;
    end

    function [1:0] tap_x;
        input [6:0] n;
        begin case(n[3:0])
            0,3,6: tap_x=0; 1,4,7: tap_x=1; default: tap_x=2;
        endcase end
    endfunction
    function [1:0] tap_y;
        input [6:0] n;
        begin if(n<9) tap_y=0; else if(n<18) tap_y=1; else tap_y=2; end
    endfunction
    function [3:0] tap_channel;
        input [6:0] n;
        begin
            case(n[6:3])
                0: tap_channel=0; 1: tap_channel=1; 2: tap_channel=2;
                3: tap_channel=3; 4: tap_channel=4; 5: tap_channel=5;
                6: tap_channel=6; default: tap_channel=7;
            endcase
        end
    endfunction

    wire [10:0] c1_weight_addr = ({7'd0,oc}*11'd9)+{8'd0,tap};
    wire [13:0] c2_weight_addr = (C1*9) + ({10'd0,c2_oc}*(C1*9)) +
                                  ({10'd0,tap_ic}*14'd9) +
                                  ({11'd0,tap_ky}*14'd3)+{12'd0,tap_kx};
    wire [10:0] head_weight_addr = HEAD_WEIGHT_BASE + ({9'd0,hclass}*HEAD_FEATURES)+
                                   {3'd0,hindex};

    // Local-memory read mirror. In the routed configuration USE_SHARED_WORKSPACE
    // is one and ws_rd_data is the registered workspace output.
    // Synchronous weight-ROM read.  The address is issued in PH_SETUP,
    // the ROM output is captured during PH_WAIT, and PH_PRODUCT consumes
    // the stable output.  This preserves one product per tap and the exact
    // signed arithmetic while allowing block-RAM inference.
    always @(posedge clk) begin
        if(state==S_C1_MAC || state==S_C2_MAC || state==S_HEAD_MAC)
            weight_rom_q <= weights[weight_addr_q];
        bias_rom_q <= biases[bias_addr_q];
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            local_rd_q <= 0;
            input_low_q <= 0;
        end else begin
            if(!busy && pixel_we) begin
                if(!pixel_addr[0]) input_low_q <= pixel_gray;
                if(!USE_SHARED_WORKSPACE) begin
                    if(pixel_addr[0]) local_bank1[packed_addr] <= packed_data;
                end
            end
            if(!USE_SHARED_WORKSPACE) begin
                if(read_bank_q) local_rd_q <= local_bank1[read_addr_q[12:0]];
                else local_rd_q <= local_bank0[read_addr_q];
                if(state==S_C1_STORE) local_bank0[c1_write_addr] <= conv_store;
                if(state==S_C2_STORE) local_bank1[c2_write_addr[12:0]] <= conv_store;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=S_IDLE; phase<=PH_SETUP; busy<=0; done<=0;
            class_id<=0; score<=0; margin<=0; saturation_count_q<=0;
            x<=0; y<=0; oc<=0; c2_x<=0; c2_y<=0; c2_oc<=0; tap<=0;
            tap_kx<=0; tap_ky<=0; tap_ic<=0; read_addr_q<=0; read_bank_q<=0;
            operand_valid_q<=0; input_byte_select_q<=0; acc<=0;
            logits[0]<=0; logits[1]<=0; best_logit<=0;
            if (HEAD_CLASSES > 2) logits[2]<=0;
            second_logit<=0; winner<=0; logit_margin<=0;
            hclass<=0; hindex<=0; pool_dx<=0; pool_dy<=0; pool_acc<=0;
            pool_value<=0; head_acc<=0; operand_hold_q<=0;
        end else begin
            done<=0;
            case(state)
                S_IDLE: begin
                    if(start) begin
                        busy<=1; saturation_count_q<=0; x<=0; y<=0; oc<=0;
                        state<=S_C1_INIT;
                    end
                end
                S_C1_INIT: begin
                    if(phase==PH_SETUP) begin
                        bias_addr_q<=oc; phase<=PH_WAIT;
                    end else if(phase==PH_WAIT) begin
                        phase<=PH_PRODUCT;
                    end else begin
                        acc<=bias_rom_q; tap<=0; tap_kx<=0; tap_ky<=0;
                        operand_valid_q<=0; phase<=PH_SETUP; state<=S_C1_MAC;
                    end
                end
                S_C1_MAC: begin
                    if(phase==PH_SETUP) begin
                        read_bank_q<=1;
            read_addr_q<=input_in_range ? {2'd0,input_word_addr} : 0;
                        input_byte_select_q<=input_byte_addr[0];
                        operand_valid_q<=input_in_range;
                        weight_addr_q<=c1_weight_addr;
                        phase<=PH_WAIT;
                    end else if(phase==PH_WAIT) begin
                        phase<=PH_PRODUCT;
                    end else if(phase==PH_PRODUCT) begin
                        operand_hold_q <= operand_valid_q ? operand_q : 0;
                        phase<=PH_ACC;
                    end else if(phase==PH_ACC) begin
                        phase<=PH_SUM;
                    end else begin
                        acc<=acc+product_hold_q; phase<=PH_SETUP;
                        if(tap==8) state<=S_C1_STORE;
                        else begin
                            tap<=tap+1'b1;
                            if(tap_kx==2) begin tap_kx<=0;tap_ky<=tap_ky+1'b1;end
                            else tap_kx<=tap_kx+1'b1;
                        end
                    end
                end
                S_C1_STORE: begin
                    if(conv_shifted>40'sd32767) saturation_count_q<=saturation_count_q+1'b1;
                    if(oc==C1-1) begin
                        oc<=0;
                        if(x==47) begin x<=0; if(y==47) begin y<=0; c2_x<=0;c2_y<=0;c2_oc<=0;state<=S_C2_INIT;end
                            else begin y<=y+1'b1;state<=S_C1_INIT;end end
                        else begin x<=x+1'b1;state<=S_C1_INIT;end
                    end else begin oc<=oc+1'b1;state<=S_C1_INIT;end
                end
                S_C2_INIT: begin
                    if(phase==PH_SETUP) begin
                        bias_addr_q<=C1+c2_oc; phase<=PH_WAIT;
                    end else if(phase==PH_WAIT) begin
                        phase<=PH_PRODUCT;
                    end else begin
                        acc<=bias_rom_q; tap<=0; tap_kx<=0; tap_ky<=0; tap_ic<=0;
                        operand_valid_q<=0; phase<=PH_SETUP; state<=S_C2_MAC;
                    end
                end
                S_C2_MAC: begin
                    if(phase==PH_SETUP) begin
                        read_bank_q<=0;
                        read_addr_q<=f1_in_range ? f1_addr : 0;
                        operand_valid_q<=f1_in_range;
                        weight_addr_q<=c2_weight_addr; phase<=PH_WAIT;
                    end else if(phase==PH_WAIT) phase<=PH_PRODUCT;
                    else if(phase==PH_PRODUCT) begin
                        operand_hold_q<=operand_valid_q ? operand_q : 0;
                        phase<=PH_ACC;
                    end else if(phase==PH_ACC) begin
                        phase<=PH_SUM;
                    end else begin
                        acc<=acc+product_hold_q; phase<=PH_SETUP;
                        if(tap==(C1*9)-1) state<=S_C2_STORE;
                        else begin
                            tap<=tap+1'b1;
                            if(tap_ic==C1-1) begin tap_ic<=0;
                                if(tap_kx==2) begin tap_kx<=0;tap_ky<=tap_ky+1'b1;end else tap_kx<=tap_kx+1'b1;
                            end else tap_ic<=tap_ic+1'b1;
                        end
                    end
                end
                S_C2_STORE: begin
                    if(conv_shifted>40'sd32767) saturation_count_q<=saturation_count_q+1'b1;
                    if(c2_oc==C2-1) begin
                        c2_oc<=0;
                        if(c2_x==23) begin c2_x<=0;if(c2_y==23) begin c2_y<=0;hclass<=0;hindex<=0;state<=S_HEAD_INIT;end else begin c2_y<=c2_y+1'b1;state<=S_C2_INIT;end end
                        else begin c2_x<=c2_x+1'b1;state<=S_C2_INIT;end
                    end else begin c2_oc<=c2_oc+1'b1;state<=S_C2_INIT;end
                end
                S_HEAD_INIT: begin
                    if(phase==PH_SETUP) begin
                        bias_addr_q<=HEAD_BIAS_BASE+hclass; phase<=PH_WAIT;
                    end else if(phase==PH_WAIT) begin
                        phase<=PH_PRODUCT;
                    end else begin
                        head_acc<=bias_rom_q; hindex<=0;
                        pool_dx<=0;pool_dy<=0;pool_acc<=0;phase<=PH_SETUP;state<=S_POOL;
                    end
                end
                S_POOL: begin
                    if(phase==PH_SETUP) begin
                        read_bank_q<=1;read_addr_q<=pool_addr;phase<=PH_WAIT;
                    end else if(phase==PH_WAIT) begin
                        phase<=PH_PRODUCT;
                    end else begin
                        if(pool_dx==5) begin
                            pool_dx<=0;
                            if(pool_dy==5) begin
                                pool_dy<=0;pool_value<=(pool_acc+pool_sample)>>>5;
                                phase<=PH_SETUP;state<=S_HEAD_MAC;
                            end else begin
                                pool_dy<=pool_dy+1'b1;pool_acc<=pool_acc+pool_sample;phase<=PH_SETUP;
                            end
                        end else begin
                            pool_dx<=pool_dx+1'b1;pool_acc<=pool_acc+pool_sample;phase<=PH_SETUP;
                        end
                    end
                end
                S_HEAD_MAC: begin
                    if(phase==PH_SETUP) begin
                        weight_addr_q<=head_weight_addr;phase<=PH_WAIT;
                    end else if(phase==PH_WAIT) begin
                        phase<=PH_PRODUCT;
                    end else if(phase==PH_PRODUCT) begin
                        operand_hold_q<=operand_q;
                        phase<=PH_ACC;
                    end else if(phase==PH_ACC) begin
                        phase<=PH_SUM;
                    end else begin
                        head_acc<=head_acc+product_hold_q;phase<=PH_SETUP;
                        if(hindex==HEAD_FEATURES-1) state<=S_HEAD_STORE;
                        else begin hindex<=hindex+1'b1;pool_dx<=0;pool_dy<=0;pool_acc<=0;state<=S_POOL;end
                    end
                end
                S_HEAD_STORE: begin
                    logits[hclass]<=head_acc>>>HEAD_SHIFT;
                    if(hclass==HEAD_CLASSES-1) state<=S_SORT01;
                    else begin hclass<=hclass+1'b1;state<=S_HEAD_INIT;end
                end
                S_SORT01: begin
                    if(logits[1]>logits[0]) begin best_logit<=logits[1];second_logit<=logits[0];winner<=1;end
                    else begin best_logit<=logits[0];second_logit<=logits[1];winner<=0;end
                    state<=S_SORT2;
                end
                S_SORT2: begin
                    if (HEAD_CLASSES == 2) begin
                        // Binary head: logits[0]=GOOD and logits[1]=BAD.
                        // S_SORT01 already selected both values, so no third
                        // logit may enter the comparison or ROM address path.
                        state<=S_MARGIN;
                    end else begin
                        if(logits[2]>best_logit) begin second_logit<=best_logit;best_logit<=logits[2];winner<=2;end
                        else if(logits[2]>second_logit) second_logit<=logits[2];
                        state<=S_MARGIN;
                    end
                end
                S_MARGIN: begin
                    logit_margin <= $signed({best_logit[19],best_logit}) -
                                    $signed({second_logit[19],second_logit});
                    state<=S_FINISH;
                end
                S_FINISH: begin
                    class_id<=winner;
                    score<=best_logit<=0 ? 0 : best_logit>255 ? 8'hff : best_logit[7:0];
                    margin<=logit_margin<=0 ? 0 : logit_margin>65535 ? 16'hffff : logit_margin[15:0];
                    busy<=0;done<=1;state<=S_IDLE;
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
