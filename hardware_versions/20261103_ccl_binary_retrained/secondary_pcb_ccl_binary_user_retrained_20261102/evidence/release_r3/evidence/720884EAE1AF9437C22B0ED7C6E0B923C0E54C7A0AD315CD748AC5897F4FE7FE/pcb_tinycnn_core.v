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
    parameter TAPS_MEM="../td_project/model/pcb_tinycnn_taps.mem",
    parameter integer USE_SHARED_WORKSPACE=0,
    parameter integer EXTERNAL_MAC=0
)(
    input wire clk,input wire rst_n,input wire start,
    input wire pixel_we,input wire [13:0] pixel_addr,input wire [7:0] pixel_gray,
    output reg busy,output reg done,output reg [1:0] class_id,
    output reg [7:0] score,output reg [15:0] margin,output wire [15:0] saturation_count,
    output wire ws_we, output wire ws_wbank, output wire [14:0] ws_waddr, output wire [15:0] ws_wdata,
    output wire ws_rd_bank, output wire [14:0] ws_rd_addr, input wire [15:0] ws_rd_data,
    output wire signed [15:0] mac_a, output wire signed [7:0] mac_w,
    input wire signed [23:0] mac_product_ext
);
    localparam integer C1=8,C2=12;
    (* rom_style="distributed" *) reg signed [7:0] weights [0:971];
    // Keep the source MEM width intact for readmemh and simulation parity;
    // the ROM-bound gate proves its values fit the narrowed accumulator.
    (* rom_style="distributed" *) reg signed [31:0] biases [0:22];
    // The grayscale window is dead after Conv1.  Keep the same physical
    // block RAM for the packed input window and the later FC feature map.
    // Input pixels are written as two bytes per word while the classifier is
    // idle; after C1 has consumed them, the same 16-bit words hold f2.  The
    // f2 address range is only 0..6911, so the old 9216-word depth was
    // needlessly costing two additional ERAM blocks.
    localparam integer WORK_DEPTH = USE_SHARED_WORKSPACE ? 1 : 6912;
    localparam integer F1_DEPTH = USE_SHARED_WORKSPACE ? 1 : 18432;
    (* ram_style="bram" *) reg [15:0] work_mem [0:WORK_DEPTH-1];
    (* ram_style="bram" *) reg signed [15:0] f1 [0:F1_DEPTH-1];
    (* rom_style="distributed" *) reg [9:0] first_tap[0:22];
    (* rom_style="distributed" *) reg [9:0] next_tap[0:971];
    (* rom_style="distributed" *) reg [7:0] tap_desc[0:971];
    initial begin
        $readmemh(WEIGHTS_MEM,weights); $readmemh(BIASES_MEM,biases);
        $readmemh(FIRST_MEM,first_tap); $readmemh(NEXT_MEM,next_tap); $readmemh(TAPS_MEM,tap_desc);
    end
    reg [3:0] state;
    localparam S_IDLE=0,S_C1_INIT=1,S_C1_MAC=2,S_C1_STORE=3,
               S_C2_INIT=4,S_C2_MAC=5,S_C2_STORE=6,S_HEAD_INIT=7,
               S_HEAD_MAC=8,S_HEAD_STORE=9,S_FINISH=10,
               S_SORT01=11,S_SORT2=12,S_MARGIN=13;
    reg [5:0] x,y; reg [3:0] oc;
    reg [9:0] tap;
    wire [3:0] ic=tap_desc[tap][3:0];
    wire [1:0] kx=tap_desc[tap][5:4],ky=tap_desc[tap][7:6];
    reg [1:0] hclass; reg [9:0] hindex; reg signed [21:0] acc;
    reg [7:0] input_q;
    reg [7:0] input_low_q;
    reg signed [15:0] f1_q,f2_q;
    // C2 feature-map addresses are registered one cycle before the
    // synchronous f1 RAM read.  This keeps tap_desc/tap arithmetic out of
    // the RAM chip-select path while preserving the existing three-cycle MAC
    // schedule and pixel ordering.
    reg [14:0] f1_addr_q;
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
    // The ROM-bound audit also proves every individual product fits signed
    // 22 bits, so the MAC and head keep the original exact integer values.
    wire signed [21:0] mac_addend = mac_product_q[21:0];
    reg signed [21:0] logits [0:2];
    reg signed [21:0] best_logit,second_logit;
    reg signed [22:0] logit_margin;
    reg [1:0] winner;
    reg [14:0] saturation_count_q;
    assign saturation_count={1'b0,saturation_count_q};
    wire signed [9:0] ix=$signed({3'b0,x,1'b0})+$signed({8'd0,kx})-10'sd1;
    wire signed [9:0] iy=$signed({3'b0,y,1'b0})+$signed({8'd0,ky})-10'sd1;
    wire input_in_range=ix>=0 && iy>=0 && ix<96 && iy<96;
    // C2 coordinates are x/y in 0..23 and kx/ky in 0..3.  Keep the
    // border test independent of the address adders so the RAM chip-select
    // path does not inherit the ix/iy arithmetic cone.  This is exactly
    // equivalent to -1 <= ix,iy < 48 for this layer.
    wire f1_in_range= !((x==7'd0  && kx==2'd0) ||
                        (x==7'd23 && kx==2'd3) ||
                        (y==7'd0  && ky==2'd0) ||
                        (y==7'd23 && ky==2'd3));
    // Explicit shifts/adds keep address generation out of DSP blocks.  The
    // C1 and C2 shared-workspace reads use registered addresses. C2 reads use
    // f1_addr_q, which is registered in S_C2_INIT and at each tap boundary;
    // do not retain a parallel combinational f1 address cone, since the
    // physical RAM chip-select path would otherwise still be driven by the
    // unregistered tap descriptor arithmetic.
    // The next-tap ROM and descriptor ROM are staged during the two cycles
    // before the current MAC is committed.  This keeps the long
    // next_tap -> descriptor -> offset -> address cone out of the phase-2
    // address register path while preserving the three-cycle MAC schedule.
    reg [9:0] c2_next_tap_q;
    reg [7:0] c2_next_desc_q;
    reg [9:0] c1_next_tap_q;
    reg [14:0] c1_next_position_q;
    reg [13:0] c1_position_q;
    reg c1_position_valid_q;
    wire [13:0] input_addr_raw=({7'd0,iy[6:0]}<<6)+({7'd0,iy[6:0]}<<5)+{7'd0,ix[6:0]};
    wire [13:0] input_addr=input_in_range ? input_addr_raw : 14'd0;
    wire [12:0] input_word_addr=input_addr[13:1];

    function [14:0] c1_position_from_desc;
        input [6:0] xv;
        input [6:0] yv;
        input [7:0] desc;
        reg signed [9:0] ix_calc,iy_calc;
        reg [13:0] byte_addr;
        begin
            ix_calc=$signed({2'b0,xv,1'b0})+$signed({8'd0,desc[5:4]})-10'sd1;
            iy_calc=$signed({2'b0,yv,1'b0})+$signed({8'd0,desc[7:6]})-10'sd1;
            if(ix_calc>=0 && iy_calc>=0 && ix_calc<96 && iy_calc<96) begin
                byte_addr=({7'd0,iy_calc[6:0]}<<6)+
                          ({7'd0,iy_calc[6:0]}<<5)+{7'd0,ix_calc[6:0]};
                c1_position_from_desc={1'b1,byte_addr};
            end else begin
                c1_position_from_desc=15'd0;
            end
        end
    endfunction

    reg [14:0] c1_first_position,c1_next_position;
    always @* begin
        c1_first_position=15'd0;
        c1_next_position=15'd0;
        if(first_tap[oc]!=10'd1023)
            c1_first_position=c1_position_from_desc(x,y,tap_desc[first_tap[oc]]);
        if(c1_next_tap_q!=10'd1023)
            c1_next_position=c1_position_from_desc(x,y,tap_desc[c1_next_tap_q]);
    end

    wire signed [15:0] shared_c1_operand = c1_position_q[0] ? $signed({8'd0,ws_rd_data[15:8]}) : $signed({8'd0,ws_rd_data[7:0]});
    wire signed [15:0] a_q = state==S_HEAD_MAC ? (USE_SHARED_WORKSPACE ? $signed(ws_rd_data) : f2_q) :
        !operand_in_range_q ? 16'sd0 :
        state==S_C1_MAC ? (USE_SHARED_WORKSPACE ? shared_c1_operand : $signed({8'd0,input_q})) :
        (USE_SHARED_WORKSPACE ? $signed(ws_rd_data) : f1_q);
    wire signed [23:0] mac_product_internal = a_q * w_q;
    wire signed [23:0] mac_product;
    generate if(EXTERNAL_MAC != 0) begin : g_external_mac
        assign mac_product=mac_product_ext;
    end else begin : g_local_mac
        assign mac_product=mac_product_internal;
    end endgenerate
    assign mac_a=a_q;
    assign mac_w=w_q;
    // C2 address generation is expressed as a registered x/y base plus a
    // small descriptor offset.  The previous implementation recomputed
    // 2*x+kx-1 and 2*y+ky-1, then multiplied both coordinates by shifts in
    // every tap boundary.  That put a long tap_desc -> address cone on the
    // 125-MHz path.  Since the descriptor's kx/ky fields are only two bits,
    // the sixteen possible spatial offsets are constants; only the channel
    // nibble remains variable.  The base is calculated once per C2 output
    // pixel and held for all taps.
    reg [14:0] c2_xy_base_q;
    function [14:0] c2_xy_base_calc;
        input [6:0] xv;
        input [6:0] yv;
        begin
            c2_xy_base_calc=({8'd0,xv}<<4)+
                            ({8'd0,yv}<<9)+({8'd0,yv}<<8);
        end
    endfunction
    function [9:0] c2_offset_base;
        input [7:0] desc;
        begin
            case(desc[7:4])
                4'h0: c2_offset_base=-10'sd392;
                4'h1: c2_offset_base=-10'sd384;
                4'h2: c2_offset_base=-10'sd376;
                4'h3: c2_offset_base=-10'sd368;
                4'h4: c2_offset_base=-10'sd8;
                4'h5: c2_offset_base=10'sd0;
                4'h6: c2_offset_base=10'sd8;
                4'h7: c2_offset_base=10'sd16;
                4'h8: c2_offset_base=10'sd376;
                4'h9: c2_offset_base=10'sd384;
                4'ha: c2_offset_base=10'sd392;
                4'hb: c2_offset_base=10'sd400;
                4'hc: c2_offset_base=10'sd760;
                4'hd: c2_offset_base=10'sd768;
                4'he: c2_offset_base=10'sd776;
                default: c2_offset_base=10'sd784;
            endcase
        end
    endfunction
    function [14:0] c2_addr_from_base;
        input [14:0] base;
        input [6:0] xv;
        input [6:0] yv;
        input [7:0] desc;
        reg invalid;
        reg signed [9:0] ob;
        reg signed [10:0] off;
        begin
            invalid=((xv==7'd0  && desc[5:4]==2'd0) ||
                     (xv==7'd23 && desc[5:4]==2'd3) ||
                     (yv==7'd0  && desc[7:6]==2'd0) ||
                     (yv==7'd23 && desc[7:6]==2'd3));
            ob=c2_offset_base(desc);
            off=$signed(ob)+$signed({7'd0,desc[3:0]});
            c2_addr_from_base=invalid ? 15'd0 : base+$signed(off);
        end
    endfunction
    wire [12:0] f2_addr=({3'd0,hindex}<<3)+({3'd0,hindex}<<2)+{9'd0,ic};
    wire [14:0] f1_write_addr=({8'd0,y}<<8)+({8'd0,y}<<7)+({8'd0,x}<<3)+{11'd0,oc};
    wire [12:0] f2_write_addr=({6'd0,y}<<8)+({6'd0,y}<<5)+({6'd0,x}<<3)+({6'd0,x}<<2)+{9'd0,oc};
    wire work_mem_f2_we=rst_n && state==S_C2_STORE;
    wire [12:0] work_mem_wr_addr=f2_write_addr;
    wire [15:0] f2_work_mem_data=(acc<0 ? 16'd0 : acc>32767 ? 16'h7fff : acc[15:0]);
    // Shared workspace ports. Bank 0 is the 18,432-word Conv1 feature map;
    // bank 1 is the 6,912-word packed input/Conv2 output overlay.
    assign ws_we = USE_SHARED_WORKSPACE &&
                   ((rst_n && state==S_C1_STORE) || (rst_n && state==S_C2_STORE) ||
                    (rst_n && pixel_we && !busy && pixel_addr<14'd9216 && pixel_addr[0]));
    assign ws_wbank = (rst_n && state==S_C1_STORE) ? 1'b0 : 1'b1;
    assign ws_waddr = (rst_n && state==S_C1_STORE) ? f1_write_addr :
                      ((rst_n && state==S_C2_STORE) ? {2'd0,f2_write_addr} : {1'b0,pixel_addr[13:1]});
    assign ws_wdata = (rst_n && state==S_C1_STORE) ?
                      (acc<0 ? 16'd0 : acc>32767 ? 16'h7fff : acc[15:0]) :
                      ((rst_n && state==S_C2_STORE) ? f2_work_mem_data : {pixel_gray,input_low_q});
    assign ws_rd_bank = (state==S_C2_MAC) ? 1'b0 : 1'b1;
    assign ws_rd_addr = (state==S_C1_MAC) ? {2'd0,c1_position_q[13:1]} :
                        ((state==S_C2_MAC) ? f1_addr_q : {2'd0,f2_addr});
    always @(posedge clk) begin
        if(!rst_n) input_low_q<=0;
        // The external loader presents one pixel per cycle.  Hold the even
        // byte and commit a complete word on the odd byte; this keeps a
        // single synchronous write port and does not add a read-modify-write
        // cycle to frame loading.
        // The mutually-exclusive f2/input branches are deliberately written
        // as one assignment tree so TD infers one single-port ERAM rather
        // than expanding the overlay into flip-flops.
        if(work_mem_f2_we) begin
            if(!USE_SHARED_WORKSPACE) work_mem[work_mem_wr_addr]<=f2_work_mem_data;
        end else if(rst_n && pixel_we && !busy && pixel_addr<14'd9216) begin
            if(!pixel_addr[0]) input_low_q<=pixel_gray;
            else if(!USE_SHARED_WORKSPACE) work_mem[pixel_addr[13:1]]<={pixel_gray,input_low_q};
        end
        if(state==S_C1_MAC) begin
            if(!USE_SHARED_WORKSPACE) begin
                if(input_addr[0]) input_q<=work_mem[input_word_addr][15:8];
                else input_q<=work_mem[input_word_addr][7:0];
            end
        end
        if(state==S_C2_MAC && mac_phase==2'd0 && !USE_SHARED_WORKSPACE) f1_q<=f1[f1_addr_q];
        if(state==S_HEAD_MAC && !USE_SHARED_WORKSPACE) f2_q<=work_mem[f2_addr];
        if(state==S_C1_MAC) begin
            if(!USE_SHARED_WORKSPACE || mac_phase==2'd0)
                operand_in_range_q<=USE_SHARED_WORKSPACE ? c1_position_valid_q : input_in_range;
        end else if(state==S_C2_MAC) begin
            operand_in_range_q<=f1_in_range;
        end
        if(state==S_C1_MAC || state==S_C2_MAC || state==S_HEAD_MAC) w_q<=weights[tap];
        if((state==S_C1_MAC || state==S_C2_MAC || state==S_HEAD_MAC) && mac_phase==2'd1)
            mac_product_q<=mac_product;
        if(!USE_SHARED_WORKSPACE && rst_n && state==S_C1_STORE)
            f1[f1_write_addr] <= acc<0 ? 16'sd0 : acc>32767 ? 16'sd32767 : acc[15:0];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            busy<=0;done<=0;state<=S_IDLE;class_id<=0;score<=0;margin<=0;
            saturation_count_q<=0;x<=0;y<=0;oc<=0;tap<=0;hclass<=0;hindex<=0;acc<=0;mac_phase<=2'd0;c2_xy_base_q<=15'd0;
            best_logit<=0;second_logit<=0;logit_margin<=0;winner<=0;f1_addr_q<=0;
            c2_next_tap_q<=10'd1023;c2_next_desc_q<=8'd0;
            c1_next_tap_q<=10'd1023;c1_next_position_q<=15'd0;
            c1_position_q<=14'd0;c1_position_valid_q<=1'b0;
        end else begin
            done<=0;
            case(state)
                S_IDLE: if(start) begin busy<=1; saturation_count_q<=0; x<=0;y<=0;oc<=0;state<=S_C1_INIT;end
                S_C1_INIT: begin
                    acc<=biases[oc];tap<=first_tap[oc];mac_phase<=2'd0;
                    if(USE_SHARED_WORKSPACE) begin
                        c1_position_q<=c1_first_position[13:0];
                        c1_position_valid_q<=c1_first_position[14];
                    end
                    state<=first_tap[oc]==1023 ? S_C1_STORE : S_C1_MAC;
                end
                S_C1_MAC: begin
                    if(mac_phase==2'd0) begin
                        mac_phase<=2'd1;
                        if(USE_SHARED_WORKSPACE) c1_next_tap_q<=next_tap[tap];
                    end
                    else if(mac_phase==2'd1) begin
                        mac_phase<=2'd2;
                        if(USE_SHARED_WORKSPACE && c1_next_tap_q!=10'd1023)
                            c1_next_position_q<=c1_next_position;
                    end
                    else begin
                    mac_phase<=2'd0; acc<=acc+mac_addend;
                    if(USE_SHARED_WORKSPACE ? (c1_next_tap_q==10'd1023) : (next_tap[tap]==10'd1023)) begin
                        state<=S_C1_STORE;
                    end else if(USE_SHARED_WORKSPACE) begin
                        tap<=c1_next_tap_q;
                        c1_position_q<=c1_next_position_q[13:0];
                        c1_position_valid_q<=c1_next_position_q[14];
                    end else begin
                        tap<=next_tap[tap];
                    end
                    end
                end
                S_C1_STORE: begin
                    if (acc > 22'sd32767) saturation_count_q <= saturation_count_q + 1'b1;
                    if(oc==C1-1) begin oc<=0;if(x==47) begin x<=0;if(y==47) begin y<=0;state<=S_C2_INIT;end else begin y<=y+1'b1;state<=S_C1_INIT;end end else begin x<=x+1'b1;state<=S_C1_INIT;end end else begin oc<=oc+1'b1;state<=S_C1_INIT;end
                end
                S_C2_INIT: begin
                    acc<=biases[8+oc];tap<=first_tap[8+oc];mac_phase<=2'd0;
                    c2_xy_base_q<=c2_xy_base_calc(x,y);
                    if(first_tap[8+oc]!=1023)
                        f1_addr_q<=c2_addr_from_base(c2_xy_base_calc(x,y),x,y,tap_desc[first_tap[8+oc]]);
                    state<=first_tap[8+oc]==1023 ? S_C2_STORE : S_C2_MAC;
                end
                S_C2_MAC: begin
                    if(mac_phase==2'd0) begin
                        mac_phase<=2'd1;
                        // Stage the linked-list successor first. The value
                        // is consumed only after the current product is
                        // accumulated in phase 2.
                        c2_next_tap_q<=next_tap[tap];
                    end
                    else if(mac_phase==2'd1) begin
                        mac_phase<=2'd2;
                        // Avoid indexing the ROM with the 1023 sentinel.
                        if(c2_next_tap_q!=10'd1023)
                            c2_next_desc_q<=tap_desc[c2_next_tap_q];
                        else
                            c2_next_desc_q<=8'd0;
                    end
                    else begin
                    mac_phase<=2'd0; acc<=acc+mac_addend;
                    if(c2_next_tap_q==10'd1023) state<=S_C2_STORE;
                    else begin
                        tap<=c2_next_tap_q;
                        f1_addr_q<=c2_addr_from_base(c2_xy_base_q,x,y,c2_next_desc_q);
                    end
                    end
                end
                S_C2_STORE: begin
                    if (acc > 22'sd32767) saturation_count_q <= saturation_count_q + 1'b1;
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
                S_MARGIN: begin
                    logit_margin<=$signed({best_logit[21],best_logit})-
                                  $signed({second_logit[21],second_logit});
                    state<=S_FINISH;
                end
                S_FINISH: begin
                    class_id<=winner;
                    if (best_logit <= 0) score <= 0;
                    else if (best_logit > 22'sd255) score <= 8'hff;
                    else score <= best_logit[7:0];
                    if (logit_margin <= 0) margin <= 0;
                    else if (logit_margin > 23'sd65535) margin <= 16'hffff;
                    else margin <= logit_margin[15:0];
                    busy<=0;done<=1;state<=S_IDLE;
                end
                default: state<=S_IDLE;
            endcase
        end
    end
endmodule
