// 96-bit (4x24 RGB) -> 128-bit word re-packer.
//
// Fixes vs the original:
//   * proper async reset on the adder counter and all latched registers
//     (S_cnt used to power up random, corrupting the whole first frame);
//   * O_128b_frame_start is emitted ONLY on a valid output word (S_cnt==1),
//     aligned with O_128b_valid, instead of blindly delayed from the input.
module data_96bit_to_128bit (
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire        I_96b_frame_start,
    input  wire        I_96b_valid,
    input  wire [95:0] I_96b_data,

    output reg         O_128b_frame_start,
    output reg         O_128b_valid,
    output reg [127:0] O_128b_data
);

    reg [95:0] S_96b_data_1d;
    reg        S_96b_fs_1d;
    reg [1:0]  S_cnt;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_96b_data_1d <= 'd0;
            S_96b_fs_1d   <= 1'b0;
            S_cnt         <= 2'd0;
        end else begin
            S_96b_data_1d <= I_96b_data;
            S_96b_fs_1d   <= I_96b_frame_start;
            // Hold the group counter on idle beats; only a frame boundary clears
            // any residue.  This way an in-line bubble no longer drops a partial
            // 96->128 group, while the frame start still realigns the packing.
            if (I_96b_frame_start)
                S_cnt <= I_96b_valid ? 2'd1 : 2'd0;
            else if (I_96b_valid)
                S_cnt <= S_cnt + 2'd1;
            else
                S_cnt <= S_cnt;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_128b_valid       <= 1'b0;
            O_128b_data        <= 'd0;
            O_128b_frame_start <= 1'b0;
        end else begin
            O_128b_valid       <= 1'b0;
            O_128b_data        <= 'd0;
            O_128b_frame_start <= 1'b0;
            if (I_96b_valid) begin
                case (I_96b_frame_start ? 2'd0 : S_cnt)
                    2'd0 : begin
                        O_128b_valid <= 1'b0;
                    end
                    2'd1 : begin
                        O_128b_valid       <= 1'b1;
                        O_128b_data        <= {S_96b_data_1d, I_96b_data[95:64]};
                        // frame start must ride the first VALID output word
                        O_128b_frame_start <= S_96b_fs_1d;
                    end
                    2'd2 : begin
                        O_128b_valid <= 1'b1;
                        O_128b_data  <= {S_96b_data_1d[63:0], I_96b_data[95:32]};
                    end
                    2'd3 : begin
                        O_128b_valid <= 1'b1;
                        O_128b_data  <= {S_96b_data_1d[31:0], I_96b_data};
                    end
                endcase
            end
        end
    end

endmodule
