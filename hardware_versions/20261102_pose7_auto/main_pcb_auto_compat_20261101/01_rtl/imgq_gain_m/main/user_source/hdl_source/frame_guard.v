// AXI4-Stream video frame boundary guard.
//
// uial2axis generates tuser from its line/frame counters.  A spurious
// I_tuser must never reset state in downstream line buffers.  This block
// accepts only the first tuser while idle and suppresses all subsequent
// tuser assertions until a complete frame (IMG_HEIGHT lines) has arrived.
// Data, tvalid and tlast are passed through unchanged; only tuser is
// filtered so that no pixel data is silently discarded.
module frame_guard #(
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720,
    parameter INPUT_DATA_WIDTH = 40
) (
    input  wire                         I_clk,
    input  wire                         I_rst_n,
    input  wire [INPUT_DATA_WIDTH-1:0]  I_tdata,
    input  wire                         I_tvalid,
    input  wire                         I_tuser,
    input  wire                         I_tlast,
    output wire [INPUT_DATA_WIDTH-1:0]  O_tdata,
    output wire                         O_tvalid,
    output wire                         O_tuser,
    output wire                         O_tlast,
    output reg                          O_frame_active,
    output reg                          O_frame_error,
    output reg [9:0]                    O_line_count,
    output reg [15:0]                   O_group_count,
    output reg                          O_frame_done
);
    localparam integer GROUPS_PER_LINE = IMG_WIDTH / 4;
    localparam integer GROUP_W = (GROUPS_PER_LINE < 2) ? 1 : $clog2(GROUPS_PER_LINE);
    localparam integer LINE_W = (IMG_HEIGHT < 2) ? 1 : $clog2(IMG_HEIGHT);

    // tuser_armed prevents a level-held tuser from being accepted twice.
    reg tuser_armed;
    reg [GROUP_W:0] group_count_i;
    reg [LINE_W:0]  line_count_i;
    wire accept_sof = I_tvalid && I_tuser && !O_frame_active && tuser_armed;

    assign O_tdata  = I_tdata;
    assign O_tvalid = I_tvalid;
    assign O_tlast  = I_tlast;
    assign O_tuser  = accept_sof;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_frame_active <= 1'b0;
            O_frame_error  <= 1'b0;
            O_line_count   <= 10'd0;
            O_group_count  <= 16'd0;
            O_frame_done   <= 1'b0;
            tuser_armed    <= 1'b1;
            group_count_i  <= 'd0;
            line_count_i   <= 'd0;
        end else begin
            O_frame_done <= 1'b0;

            // Require a low/inactive cycle before another tuser can be used.
            if (!I_tvalid || !I_tuser)
                tuser_armed <= 1'b1;
            if (accept_sof) begin
                O_frame_active <= 1'b1;
                O_frame_error  <= 1'b0;
                O_line_count   <= 10'd0;
                O_group_count  <= 16'd0;
                line_count_i   <= 'd0;
                group_count_i  <= 'd1;
                tuser_armed    <= 1'b0;
            end else if (I_tvalid) begin
                // Any tuser while active is an error, but cannot reset state.
                if (I_tuser && O_frame_active)
                    O_frame_error <= 1'b1;

                if (O_frame_active) begin
                    if (I_tlast) begin
                        // tlast denotes end-of-line. Check the number of
                        // groups accepted BEFORE this beat. The final pixel
                        // group itself carries tlast, so a 320-beat row has
                        // 319 previous groups here. Count this beat once.
                        if (group_count_i != GROUPS_PER_LINE-1)
                            O_frame_error <= 1'b1;
                        O_group_count <= group_count_i + 1'b1;
                        group_count_i <= 'd0;
                        if (line_count_i == IMG_HEIGHT-1) begin
                            // Complete frame: release busy only after all rows.
                            O_frame_active <= 1'b0;
                            O_frame_done   <= 1'b1;
                            O_line_count   <= line_count_i[9:0];
                            line_count_i   <= 'd0;
                        end else begin
                            line_count_i <= line_count_i + 1'b1;
                            O_line_count <= (line_count_i + 1'b1);
                        end
                    end else begin
                        group_count_i <= group_count_i + 1'b1;
                    end
                end
            end
        end
    end
endmodule
