`timescale 1ns / 1ns

module uicfgcs500_720p #(
    parameter CLK_DIV = 16'd239,
    parameter [17:0] POST_STREAM_DELAY = 18'd240000,
    parameter integer DG_INIT_Q7 = 128,
    parameter integer DG_MAX_Q7  = 256
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_ae_req,
    input  wire [15:0] I_ae,
    input  wire [15:0] I_ag,
    input  wire [8:0]  I_dg,
    output wire        O_cam_scl,
    inout  wire        IO_cam_sda,
    output reg         O_cfg_done,
    output reg         O_ae_cfg_done
);

localparam CAM_ID = 8'h6c;
// Initialization keeps the former register order and appends DG/group
// configuration before stream-on. The delayed release is now index119.
localparam [8:0] POST_STREAM_INDEX = 9'd119;

reg [7:0]  rst_cnt = 8'd0;
reg        iic_req;
wire       iic_busy;
wire       iic_bus_error;
reg        iic_error_meta = 1'b0; /* fehdl keep="true" */
reg        iic_error_sync = 1'b0; /* fehdl keep="true" */
reg        transaction_failed;
reg [31:0] wr_data;
reg [1:0]  state;
reg [8:0]  reg_index;
reg [17:0] delay_cnt;
// One accepted request owns the entire 11-register group transaction.
// Changes to the live controller inputs cannot mix command generations.
reg [15:0] ae_command, ag_index_command;
reg [8:0] dg_command;
// Keep the actual encoder input bit observable without forcing a register.
wire dg_to_encoder_bit1; /* fehdl keep="true" */
assign dg_to_encoder_bit1 = dg_command[1];

wire [31:0] init_data_word;
wire [23:0] init_data = init_data_word[23:0];
wire [8:0]  init_size;
wire [31:0] ae_data_word;
wire [23:0] ae_data = ae_data_word[23:0];
wire [8:0]  ae_size;
wire [23:0] selected_data = O_cfg_done ? ae_data : init_data;
wire [8:0]  selected_size = O_cfg_done ? ae_size : init_size;

always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n)
        rst_cnt <= 8'd0;
    else if (!rst_cnt[7])
        rst_cnt <= rst_cnt + 1'b1;
end

// The master error is generated on its slower SCL edge. Capture its
// multi-I_clk pulse through two stages, then remember it until STOP.
always @(posedge I_clk) begin
    if (!rst_cnt[7]) begin
        iic_error_meta <= 1'b0;
        iic_error_sync <= 1'b0;
    end else begin
        iic_error_meta <= iic_bus_error;
        iic_error_sync <= iic_error_meta;
    end
end

always @(posedge I_clk) begin
    if (!rst_cnt[7]) begin
        reg_index     <= 9'd0;
        iic_req       <= 1'b0;
        wr_data       <= 32'd0;
        O_cfg_done    <= 1'b0;
        O_ae_cfg_done <= 1'b0;
        delay_cnt     <= 18'd0;
        state         <= 2'd0;
        ae_command    <= 16'd1990;
        ag_index_command <= 16'd80;
        dg_command    <= DG_INIT_Q7;
        transaction_failed <= 1'b0;
    end else begin
        if ((state == 2'd2 || state == 2'd3) && iic_error_sync)
            transaction_failed <= 1'b1;
        case (state)
            2'd0: begin
                iic_req <= 1'b0;
                if (!O_cfg_done) begin
                    if ((reg_index == POST_STREAM_INDEX) && (delay_cnt < POST_STREAM_DELAY))
                        delay_cnt <= delay_cnt + 1'b1;
                    else if (reg_index == init_size) begin
                        O_cfg_done    <= 1'b1;
                        O_ae_cfg_done <= 1'b1;
                        reg_index     <= 9'd0;
                    end else
                        state <= 2'd1;
                end else if (I_ae_req && O_ae_cfg_done) begin
                    ae_command <= I_ae;
                    ag_index_command <= I_ag;
                    dg_command <= I_dg;
                    O_ae_cfg_done <= 1'b0;
                    reg_index     <= 9'd0;
                end else if (!O_ae_cfg_done) begin
                    if (reg_index == ae_size)
                        O_ae_cfg_done <= 1'b1;
                    else
                        state <= 2'd1;
                end
            end
            2'd1: begin
                if (!iic_busy) begin
                    transaction_failed <= 1'b0;
                    iic_req        <= 1'b1;
                    wr_data[7:0]   <= CAM_ID;
                    wr_data[15:8]  <= selected_data[23:16];
                    wr_data[23:16] <= selected_data[15:8];
                    wr_data[31:24] <= selected_data[7:0];
                    state          <= 2'd2;
                end
            end
            2'd2: begin
                if (iic_busy) begin
                    iic_req <= 1'b0;
                    state   <= 2'd3;
                end
            end
            2'd3: begin
                if (!iic_busy) begin
                    // NACK does not complete a register. Retrying the same
                    // frozen payload preserves group ordering and holds done
                    // low until every register has received an ACK.
                    if (!transaction_failed && !iic_error_sync)
                        reg_index <= reg_index + 1'b1;
                    state     <= 2'd0;
                end
            end
        endcase
    end
end

uii2c #(
    .WMEN_LEN (4),
    .RMEN_LEN (1),
    .CLK_DIV  (CLK_DIV)
) u_i2c (
    .I_clk      (I_clk),
    .I_rstn     (rst_cnt[7]),
    .O_iic_scl  (O_cam_scl),
    .IO_iic_sda (IO_cam_sda),
    .I_wr_data  (wr_data),
    .I_wr_cnt   (8'd4),
    .O_rd_data  (),
    .I_rd_cnt   (8'd0),
    .I_iic_mode (1'b0),
    .I_iic_req  (iic_req),
    .O_iic_busy (iic_busy),
    .O_iic_bus_error(iic_bus_error), .IO_iic_sda_dg()
);

uics500reg_720p60 #(.DG_INIT_Q7(DG_INIT_Q7), .DG_MAX_Q7(DG_MAX_Q7)) u_init_table (
    .REG_INDEX (reg_index),
    .REG_DATA  (init_data_word),
    .REG_SIZE  (init_size)
);

wire [15:0] gain_value;
wire [15:0] gain_index = ag_index_command - 16'd16;
SC500GainTbl u_gain_table (
    .I_clk  (I_clk),
    .I_rstn (rst_cnt[7]),
    .I      (gain_index[6:0]),
    .O      (gain_value)
);

uics500regAE #(.DG_MAX_Q7(DG_MAX_Q7)) u_ae_table (
    .REG_INDEX (reg_index),
    .REG_DATA  (ae_data_word),
    .REG_SIZE  (ae_size),
    .I_AG      (gain_value),
    .I_AE      (ae_command),
    .I_DG      ({dg_command[8:2], dg_to_encoder_bit1, dg_command[0]})
);

endmodule
