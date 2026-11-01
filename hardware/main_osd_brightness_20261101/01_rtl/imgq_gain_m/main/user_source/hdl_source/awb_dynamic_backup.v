/*****************************************************************
Company : MiLianKe Electronic Technology Co., Ltd.
WebSite:https://www.milianke.com
@Description :  稳定白平衡（Grey-World）。
  对整帧统计 R/G/B（排除近黑、近饱和样本），得到
    R增益 = ΣG/ΣR,  B增益 = ΣG/ΣB
  限制到 [0.5, 2.0]，并做 7/8+1/8 帧间平滑，帧边界更新，初始增益 1.0。
  全帧共用同一组增益（取代原"4 个像素槽位各算一套增益"的不稳实现）。
  上一帧统计经 50 拍除法器得到，与 signal_delay(50) 对齐，供当前帧使用。
*****************************************************************/
module awb  #(
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920,
    parameter LUM_MIN    = 16,    // 低于此亮度的像素视为近黑，不参与统计
    parameter LUM_MAX    = 250    // 高于此亮度的像素视为饱和，不参与统计
)
(
    input                   I_clk  ,
    input                   I_rst_n,

    input                   I_tlast  ,
    input                   I_tuser  ,
    input [95:0]            I_tdata  ,
    input                   I_tvalid ,
    output                  I_tready ,

    output                  O_tlast  ,
    output                  O_tuser  ,
    output [95:0]           O_tdata  ,
    output                  O_tvalid ,
    input                   O_tready
);

    //====================================================================
    // 输入流水寄存
    //====================================================================
    reg         I_tvalid_r0, I_tvalid_r1;
    reg  [95:0] I_tdata_d0, I_tdata_d1, I_tdata_d2;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            I_tdata_d0 <= 0; I_tdata_d1 <= 0; I_tdata_d2 <= 0;
            {I_tvalid_r0, I_tvalid_r1} <= 0;
        end else begin
            I_tdata_d0  <= I_tdata;
            I_tdata_d1  <= I_tdata_d0;
            I_tdata_d2  <= I_tdata_d1;
            I_tvalid_r0 <= I_tvalid;
            I_tvalid_r1 <= I_tvalid_r0;
        end
    end

    // 每拍 4 像素 RGB 分量（用 I_tdata_d0，与 I_tvalid_r0 对齐）
    wire [7:0] r0 = I_tdata_d0[16+:8], g0 = I_tdata_d0[8+:8],  b0 = I_tdata_d0[0+:8];
    wire [7:0] r1 = I_tdata_d0[40+:8], g1 = I_tdata_d0[32+:8], b1 = I_tdata_d0[24+:8];
    wire [7:0] r2 = I_tdata_d0[64+:8], g2 = I_tdata_d0[56+:8], b2 = I_tdata_d0[48+:8];
    wire [7:0] r3 = I_tdata_d0[88+:8], g3 = I_tdata_d0[80+:8], b3 = I_tdata_d0[72+:8];

    // 有效性：像素非近黑且非饱和（最大通道处于 [LUM_MIN, LUM_MAX]）
    wire [7:0] mx0 = (r0>g0) ? ((r0>b0)?r0:b0) : ((g0>b0)?g0:b0);
    wire [7:0] mx1 = (r1>g1) ? ((r1>b1)?r1:b1) : ((g1>b1)?g1:b1);
    wire [7:0] mx2 = (r2>g2) ? ((r2>b2)?r2:b2) : ((g2>b2)?g2:b2);
    wire [7:0] mx3 = (r3>g3) ? ((r3>b3)?r3:b3) : ((g3>b3)?g3:b3);
    wire pv0 = (mx0 >= LUM_MIN) && (mx0 <= LUM_MAX);
    wire pv1 = (mx1 >= LUM_MIN) && (mx1 <= LUM_MAX);
    wire pv2 = (mx2 >= LUM_MIN) && (mx2 <= LUM_MAX);
    wire pv3 = (mx3 >= LUM_MIN) && (mx3 <= LUM_MAX);

    //====================================================================
    // 整帧统计有效像素的 R/G/B
    //====================================================================
    reg [31:0] sum_r, sum_g, sum_b;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n || I_tuser) begin
            sum_r <= 0; sum_g <= 0; sum_b <= 0;
        end else if (I_tvalid_r0) begin
            sum_r <= sum_r + (pv0?r0:8'd0) + (pv1?r1:8'd0) + (pv2?r2:8'd0) + (pv3?r3:8'd0);
            sum_g <= sum_g + (pv0?g0:8'd0) + (pv1?g1:8'd0) + (pv2?g2:8'd0) + (pv3?g3:8'd0);
            sum_b <= sum_b + (pv0?b0:8'd0) + (pv1?b1:8'd0) + (pv2?b2:8'd0) + (pv3?b3:8'd0);
        end
    end

    //====================================================================
    // 帧边界快照并触发除法（I_tuser 时 sum 含刚结束的一帧）
    //====================================================================
    reg [31:0] snap_r, snap_g, snap_b;
    reg        awb_start;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            snap_r <= 0; snap_g <= 0; snap_b <= 0; awb_start <= 0;
        end else begin
            if (I_tuser) begin
                snap_r <= sum_r; snap_g <= sum_g; snap_b <= sum_b;
            end
            awb_start <= I_tuser;          // 一拍后 start，保证 snap 已稳定
        end
    end

    //====================================================================
    // 除法：R增益 = ΣG/ΣR, B增益 = ΣG/ΣB（0x10000 = 1.0）
    //====================================================================
    wire [47:0] q_r, q_b;
    wire        done_r, done_b;
    wire        div_start_r = awb_start & (snap_r != 0);
    wire        div_start_b = awb_start & (snap_b != 0);
    wire [31:0] rem_r, rem_b;

    divider u_awb_div_r (
        .clk(I_clk), .rst(!I_rst_n), .start(div_start_r),
        .denominator(snap_r), .numerator({snap_g,16'd0}),
        .quotient(q_r), .done(done_r), .remainder(rem_r)
    );
    divider u_awb_div_b (
        .clk(I_clk), .rst(!I_rst_n), .start(div_start_b),
        .denominator(snap_b), .numerator({snap_g,16'd0}),
        .quotient(q_b), .done(done_b), .remainder(rem_b)
    );

    // 增益限制 [0.5, 2.0]
    wire [19:0] gr_clamp = (|q_r[47:20]) ? 20'h20000
                          : ((q_r[19:0] > 20'h20000) ? 20'h20000
                             : ((q_r[19:0] < 20'h8000) ? 20'h8000 : q_r[19:0]));
    wire [19:0] gb_clamp = (|q_b[47:20]) ? 20'h20000
                          : ((q_b[19:0] > 20'h20000) ? 20'h20000
                             : ((q_b[19:0] < 20'h8000) ? 20'h8000 : q_b[19:0]));

    // 帧间平滑：new = (old*7 + current)/8；初始 1.0
    reg [19:0] r_gain_r, r_gain_b;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_gain_r <= 20'h10000; r_gain_b <= 20'h10000;
        end else begin
            if (done_r) r_gain_r <= (r_gain_r*7 + gr_clamp) >> 3;
            if (done_b) r_gain_b <= (r_gain_b*7 + gb_clamp) >> 3;
        end
    end

    //====================================================================
    // 信号延迟 50 拍（与除法器 PIPLE=50 对齐）
    //====================================================================
    wire [95:0] data_d0;
    wire        valid_d0;
    wire        I_tuser_r0;

    signal_delay #(
        .IMG_HEIGHT (IMG_HEIGHT),
        .IMG_WIDTH  (IMG_WIDTH ),
        .DATA_WIDTH (96),
        .DELAY_CYCLE(50)
    ) signal_delay_d (
        .I_clk  (I_clk),
        .I_rst_n(I_rst_n),
        .I_tuser(I_tuser),
        .I_valid(I_tvalid_r1),
        .I_data (I_tdata_d1),
        .O_valid(valid_d0),
        .O_data (data_d0),
        .O_tuser(I_tuser_r0)
    );

    reg valid_d1, I_tuser_r1;
    reg [95:0] data_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_d1 <= 0; data_d1 <= 0; I_tuser_r1 <= 0;
        end else begin
            valid_d1  <= valid_d0;
            data_d1   <= data_d0;
            I_tuser_r1 <= I_tuser_r0;
        end
    end

    wire [7:0] rr0 = data_d1[16+:8], gg0 = data_d1[8+:8],  bb0 = data_d1[0+:8];
    wire [7:0] rr1 = data_d1[40+:8], gg1 = data_d1[32+:8], bb1 = data_d1[24+:8];
    wire [7:0] rr2 = data_d1[64+:8], gg2 = data_d1[56+:8], bb2 = data_d1[48+:8];
    wire [7:0] rr3 = data_d1[88+:8], gg3 = data_d1[80+:8], bb3 = data_d1[72+:8];

    // 应用增益
    reg [27:0] R_new_r0, G_new_r0, B_new_r0;
    reg [27:0] R_new_r1, G_new_r1, B_new_r1;
    reg [27:0] R_new_r2, G_new_r2, B_new_r2;
    reg [27:0] R_new_r3, G_new_r3, B_new_r3;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            {R_new_r0,G_new_r0,B_new_r0} <= 0;
            {R_new_r1,G_new_r1,B_new_r1} <= 0;
            {R_new_r2,G_new_r2,B_new_r2} <= 0;
            {R_new_r3,G_new_r3,B_new_r3} <= 0;
        end else if (valid_d1) begin
            R_new_r0 <= r_gain_r * rr0;  G_new_r0 <= {20'd0, gg0};  B_new_r0 <= r_gain_b * bb0;
            R_new_r1 <= r_gain_r * rr1;  G_new_r1 <= {20'd0, gg1};  B_new_r1 <= r_gain_b * bb1;
            R_new_r2 <= r_gain_r * rr2;  G_new_r2 <= {20'd0, gg2};  B_new_r2 <= r_gain_b * bb2;
            R_new_r3 <= r_gain_r * rr3;  G_new_r3 <= {20'd0, gg3};  B_new_r3 <= r_gain_b * bb3;
        end
    end

    // 溢出截断：高 4 位非零 -> 255
    wire [7:0] R_new_x0 = (R_new_r0[27:24]) ? 8'd255 : R_new_r0[23:16];
    wire [7:0] G_new_x0 = G_new_r0[7:0];
    wire [7:0] B_new_x0 = (B_new_r0[27:24]) ? 8'd255 : B_new_r0[23:16];
    wire [7:0] R_new_x1 = (R_new_r1[27:24]) ? 8'd255 : R_new_r1[23:16];
    wire [7:0] G_new_x1 = G_new_r1[7:0];
    wire [7:0] B_new_x1 = (B_new_r1[27:24]) ? 8'd255 : B_new_r1[23:16];
    wire [7:0] R_new_x2 = (R_new_r2[27:24]) ? 8'd255 : R_new_r2[23:16];
    wire [7:0] G_new_x2 = G_new_r2[7:0];
    wire [7:0] B_new_x2 = (B_new_r2[27:24]) ? 8'd255 : B_new_r2[23:16];
    wire [7:0] R_new_x3 = (R_new_r3[27:24]) ? 8'd255 : R_new_r3[23:16];
    wire [7:0] G_new_x3 = G_new_r3[7:0];
    wire [7:0] B_new_x3 = (B_new_r3[27:24]) ? 8'd255 : B_new_r3[23:16];

    //====================================================================
    // 输出同步 / 控制信号
    //====================================================================
    reg valid_d2, I_tuser_r2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_d2 <= 0; I_tuser_r2 <= 0;
        end else begin
            valid_d2   <= valid_d1;
            I_tuser_r2 <= I_tuser_r1;
        end
    end

    assign O_tlast  = (valid_d1 == 0) && (valid_d2 == 1);
    assign O_tuser  = I_tuser_r2;
    assign O_tvalid = valid_d2;
    assign O_tdata  = O_tvalid ? {R_new_x3,G_new_x3,B_new_x3,
                                  R_new_x2,G_new_x2,B_new_x2,
                                  R_new_x1,G_new_x1,B_new_x1,
                                  R_new_x0,G_new_x0,B_new_x0} : 96'd0;
    assign I_tready = O_tready;

endmodule
