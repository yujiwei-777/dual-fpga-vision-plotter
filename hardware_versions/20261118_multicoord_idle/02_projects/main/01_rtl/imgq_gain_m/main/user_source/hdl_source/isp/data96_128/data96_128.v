// Repack four 96-bit (4 RGB pixels) beats into three 128-bit words.
// Advances only on valid beats; bubbles do not destroy the packing phase.
module data_96bit_to_128bit (
    input  wire         I_clk,
    input  wire         I_rst_n,
    input  wire         I_96b_frame_start,
    input  wire         I_96b_tlast,
    input  wire         I_96b_valid,
    input  wire [95:0]  I_96b_data,
    output reg          O_128b_frame_start,
    output reg          O_128b_tlast,
    output reg          O_128b_valid,
    output reg [127:0]  O_128b_data
);
    reg [95:0] S_prev_data;
    reg [1:0]  S_phase;
    reg        S_frame_pending;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_prev_data        <= 96'd0;
            S_phase            <= 2'd0;
            S_frame_pending    <= 1'b0;
            O_128b_frame_start <= 1'b0;
            O_128b_tlast       <= 1'b0;
            O_128b_valid       <= 1'b0;
            O_128b_data        <= 128'd0;
        end else begin
            O_128b_frame_start <= 1'b0;
            O_128b_tlast       <= 1'b0;
            O_128b_valid       <= 1'b0;
            if (I_96b_valid) begin
                // Frame start realigns the group. The first output word is
                // produced when the second valid 96-bit beat arrives.
                if (I_96b_frame_start) begin
                    S_prev_data     <= I_96b_data;
                    S_phase         <= 2'd1;
                    S_frame_pending <= 1'b1;
                end else begin
                    case (S_phase)
                        2'd0: begin
                            S_prev_data <= I_96b_data;
                            S_phase     <= 2'd1;
                        end
                        2'd1: begin
                            O_128b_valid       <= 1'b1;
                            O_128b_data        <= {S_prev_data, I_96b_data[95:64]};
                            O_128b_frame_start <= S_frame_pending;
                            S_frame_pending    <= 1'b0;
                            S_prev_data        <= I_96b_data;
                            S_phase            <= 2'd2;
                        end
                        2'd2: begin
                            O_128b_valid <= 1'b1;
                            O_128b_data  <= {S_prev_data[63:0], I_96b_data[95:32]};
                            S_prev_data  <= I_96b_data;
                            S_phase      <= 2'd3;
                        end
                        default: begin
                            O_128b_valid <= 1'b1;
                            O_128b_data  <= {S_prev_data[31:0], I_96b_data};
                            O_128b_tlast  <= I_96b_tlast;
                            S_prev_data   <= I_96b_data;
                            S_phase       <= 2'd0;
                        end
                    endcase
                end
            end
        end
    end
endmodule
