module signal_delay #(
    parameter IMG_HEIGHT  = 1080,
    parameter IMG_WIDTH   = 1920,
    parameter DATA_WIDTH  = 96,
    parameter DELAY_CYCLE = 50
) (
    input                         I_clk,
    input                         I_rst_n,
    input                         I_tuser,
    input  wire                   I_valid,
    input  wire [DATA_WIDTH-1:0]  I_data,
    output wire                   O_valid,
    output wire [DATA_WIDTH-1:0]  O_data,
    output wire                   O_tuser
);

    // Fixed pipeline delay. The former circular line-RAM read window restarted
    // at the same h_cnt value every line for 1280 pixels, causing permanent
    // horizontal wrap and loss of line-end bubbles.
    reg [DATA_WIDTH-1:0] data_pipe [0:DELAY_CYCLE-1];
    reg                   valid_pipe[0:DELAY_CYCLE-1];
    reg                   tuser_pipe[0:DELAY_CYCLE-1];
    integer k;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            for (k = 0; k < DELAY_CYCLE; k = k + 1) begin
                data_pipe[k]  <= {DATA_WIDTH{1'b0}};
                valid_pipe[k] <= 1'b0;
                tuser_pipe[k] <= 1'b0;
            end
        end else begin
            data_pipe[0]  <= I_data;
            valid_pipe[0] <= I_valid;
            tuser_pipe[0] <= I_tuser;
            for (k = 1; k < DELAY_CYCLE; k = k + 1) begin
                data_pipe[k]  <= data_pipe[k-1];
                valid_pipe[k] <= valid_pipe[k-1];
                tuser_pipe[k] <= tuser_pipe[k-1];
            end
        end
    end

    assign O_data  = data_pipe[DELAY_CYCLE-1];
    assign O_valid = valid_pipe[DELAY_CYCLE-1];
    assign O_tuser = tuser_pipe[DELAY_CYCLE-1];

endmodule
