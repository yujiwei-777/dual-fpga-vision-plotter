// Light edge-preserving denoise for the 4-pixel/96-bit RGB video path.
//
// Vertical 1-2-1 (causal, via a one-line BRAM delay) + horizontal 1-2-1 within
// the 4-pixel beat, then blended toward the original by I_strength so the amount
// of smoothing follows the analogue gain (noise).  Fixed 1-cycle latency; the
// BRAM is a plain delay line, so frame alignment is just "delay control by one".
//
// The top image line has no previous row, so it falls back to no vertical
// smoothing (edge-replicated), which avoids blending in the previous frame.
module denoise_96 #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter integer LUM_TH = 24      // edge guard: skip strong jumps (keeps text/edges)
)(
    input               I_clk,
    input               I_rst_n,
    input               I_tlast,
    input               I_tuser,
    input  [95:0]       I_tdata,
    input               I_tvalid,
    input               O_tready,
    input  [7:0]        I_strength,   // 0..255, higher = stronger denoise
    output              I_tready,
    output reg          O_tlast,
    output reg          O_tuser,
    output reg  [95:0]  O_tdata,
    output reg          O_tvalid
);
    localparam LINE = IMG_WIDTH / 4;          // beats per line (320 at 1280 pixels)
    localparam [8:0] LINE9 = LINE[8:0];

    (* ram_style = "bram" *) reg [95:0] mem [0:LINE-1];
    reg [8:0]  wr;
    reg [8:0]  write_addr_d;
    reg [95:0] cur_d, memory_read_d, forwarded_d;
    reg forward_d;
    wire [95:0] prev_d=forward_d?forwarded_d:memory_read_d;
    reg        pv_d;                          // prev_d is a real (same-frame) row
    reg        v_d, u_d, l_d;

    reg have_prev;
    reg [7:0] strength_d;
    wire [8:0] rd = I_tuser ? 9'd0 : wr;               // synchronous read-before-write previous row

    assign I_tready = O_tready;

    // ---- per-pixel colour helpers -------------------------------------
    // vertical 1-2-1 (causal, weight 3:1 toward the current row)
    function [7:0] vavg;
        input [7:0] prev; input [7:0] cur; input use_prev;
        reg signed [8:0] difference;
        reg signed [9:0] rounded;
        reg signed [9:0] total;
        begin
            difference=$signed({1'b0,prev})-$signed({1'b0,cur});
            rounded=$signed(difference)+10'sd2;
            total=$signed({1'b0,cur})+(rounded>>>2);
            vavg=use_prev?total[7:0]:cur;
        end
    endfunction
    // A signed 9-bit upper delta and unsigned 9-bit lower delta are
    // separated by 18 bits. The lower product is at most 511*255 (<2^17),
    // so it cannot carry into the upper product. One PH1P 27x18 DSP
    // therefore computes two independent exact blend products.
    // Negative lower deltas were encoded modulo 512: after division by
    // 256, subtract 2*strength modulo 256. The upper lane is already signed.
    function [15:0] blend8_pair;
        input [7:0] original0,filtered0,original1,filtered1,strength;
        reg [8:0] delta0,delta1;
        reg signed [26:0] packed_delta;
        reg signed [35:0] product;
        reg [7:0] result0,result1;
        begin
            delta0={1'b0,filtered0}-{1'b0,original0};
            delta1={1'b0,filtered1}-{1'b0,original1};
            packed_delta={delta1,9'd0,delta0};
            product=packed_delta*$signed({1'b0,strength});
            result0=original0+product[15:8]-(delta0[8]?{strength[6:0],1'b0}:8'd0);
            result1=original1+product[33:26];
            blend8_pair={result1,result0};
        end
    endfunction
    reg [15:0] blended_pair;
    reg [8:0] pair01,pair12,pair23;
    reg [9:0] horizontal;
    integer s, ch;
    reg [7:0] cc [0:3][0:2];    // current pixel RGB
    reg [7:0] pp [0:3][0:2];    // previous-row pixel RGB
    reg [7:0] vv [0:3][0:2];    // vertical filtered
    reg [7:0] hh [0:3][0:2];    // horizontally filtered
    reg [7:0] oo [0:3][0:2];
    reg signed [8:0] edge_delta;
    reg edge_guard;
    always @(posedge I_clk)begin
        if(I_rst_n && O_tready)begin
            // Read the next address while committing the previous beat. This
            // describes separate read/write ports (40-bit ERAM SDP packing),
            // rather than a wide read-before-write single port (20-bit mode).
            // Forward the pending write on a collision, including IMG_WIDTH=4
            // and blanking: observable data stays identical to immediate writes.
            memory_read_d <= mem[rd];
            forward_d <= v_d && write_addr_d==rd;
            forwarded_d <= cur_d;
            if(v_d)mem[write_addr_d]<=cur_d;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            wr<=9'd0;write_addr_d<=9'd0; cur_d<=0; pv_d<=1'b0;have_prev<=0;strength_d<=0;
            v_d<=1'b0; u_d<=1'b0; l_d<=1'b0;
            O_tdata<=0; O_tvalid<=0; O_tuser<=0; O_tlast<=0;
        end else if (O_tready) begin
            // delay line
            pv_d <= have_prev && !I_tuser;
            strength_d <= I_strength;
            cur_d  <= I_tdata;
            write_addr_d <= rd;
            v_d    <= I_tvalid;
            u_d    <= I_tuser;
            l_d    <= I_tlast;
            if(I_tuser)begin wr<=0;have_prev<=0;end
            if(I_tvalid)begin
                if(I_tlast || rd==LINE-1)begin wr<=0;have_prev<=1;end
                else wr<=rd+1'b1;
            end

            // ---- denoise on the registered beat (1-cycle latency) ----
            for (s = 0; s < 4; s = s + 1) begin
                cc[s][0] = cur_d[24*s+16 +: 8];
                cc[s][1] = cur_d[24*s+ 8 +: 8];
                cc[s][2] = cur_d[24*s+ 0 +: 8];
                pp[s][0] = prev_d[24*s+16 +: 8];
                pp[s][1] = prev_d[24*s+ 8 +: 8];
                pp[s][2] = prev_d[24*s+ 0 +: 8];
            end
            for (s = 0; s < 4; s = s + 1)
                for (ch = 0; ch < 3; ch = ch + 1)
                    vv[s][ch] = vavg(pp[s][ch], cc[s][ch], pv_d);

            // Adjacent sums are shared by the four horizontal 1-2-1 filters.
            for (ch=0;ch<3;ch=ch+1) begin
                pair01={1'b0,vv[0][ch]}+{1'b0,vv[1][ch]}+9'd1;
                pair12={1'b0,vv[1][ch]}+{1'b0,vv[2][ch]}+9'd1;
                pair23={1'b0,vv[2][ch]}+{1'b0,vv[3][ch]}+9'd1;
                horizontal={1'b0,pair01}+{1'b0,vv[0][ch],1'b0}+10'd1;
                hh[0][ch]=horizontal[9:2];
                horizontal={1'b0,pair01}+{1'b0,pair12};
                hh[1][ch]=horizontal[9:2];
                horizontal={1'b0,pair12}+{1'b0,pair23};
                hh[2][ch]=horizontal[9:2];
                horizontal={1'b0,pair23}+{1'b0,vv[3][ch],1'b0}+10'd1;
                hh[3][ch]=horizontal[9:2];
            end

            // vv-cur = floor((prev-cur+2)/4); compare its exact bounds
            // directly against the shared vertical difference.
            for (s = 0; s < 4; s = s + 2)
                for (ch = 0; ch < 3; ch = ch + 1) begin
                    blended_pair=blend8_pair(cc[s][ch],hh[s][ch],
                                             cc[s+1][ch],hh[s+1][ch],strength_d);
                    edge_delta = $signed({1'b0,pp[s][ch]})-$signed({1'b0,cc[s][ch]});
                    edge_guard = (LUM_TH<0) || (pv_d && (($signed(edge_delta)>=4*(LUM_TH+1)-2) || ($signed(edge_delta)<-4*LUM_TH-2)));
                    oo[s][ch]=edge_guard?cc[s][ch]:blended_pair[7:0];
                    edge_delta = $signed({1'b0,pp[s+1][ch]})-$signed({1'b0,cc[s+1][ch]});
                    edge_guard = (LUM_TH<0) || (pv_d && (($signed(edge_delta)>=4*(LUM_TH+1)-2) || ($signed(edge_delta)<-4*LUM_TH-2)));
                    oo[s+1][ch]=edge_guard?cc[s+1][ch]:blended_pair[15:8];
                end

            O_tdata[95:72] <= {oo[3][0], oo[3][1], oo[3][2]};
            O_tdata[71:48] <= {oo[2][0], oo[2][1], oo[2][2]};
            O_tdata[47:24] <= {oo[1][0], oo[1][1], oo[1][2]};
            O_tdata[23: 0] <= {oo[0][0], oo[0][1], oo[0][2]};
            O_tvalid <= v_d;
            O_tuser  <= u_d;
            O_tlast  <= l_d;
        end
    end
endmodule
