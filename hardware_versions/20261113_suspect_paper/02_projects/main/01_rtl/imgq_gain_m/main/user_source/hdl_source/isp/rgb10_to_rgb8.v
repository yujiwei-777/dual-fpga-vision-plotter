`timescale 1ns/1ps
// Final precision boundary for the new path: rounded RGB10 -> RGB8.
// Input/output lane order is lane 3 at the MSBs and lane 0 at the LSBs.
module rgb10_to_rgb8 (
    input              I_clk,
    input              I_rst_n,
    input      [119:0] I_tdata,
    input              I_tlast,
    input              I_tuser,
    input              I_tvalid,
    output             I_tready,
    output     [95:0]  O_tdata,
    output             O_tlast,
    output             O_tuser,
    output             O_tvalid,
    input              O_tready
);
    reg [95:0] data_r;
    integer i;

    function automatic [7:0] q10_to_8;
        input [9:0] value;
        reg [10:0] rounded;
        begin
            rounded = value + 2'd2;
            if (rounded[10:2] > 8'd255)
                q10_to_8 = 8'hff;
            else
                q10_to_8 = rounded[9:2];
        end
    endfunction

    always @* begin
        data_r = 96'd0;
        for (i=0; i<4; i=i+1) begin
            data_r[i*24 +: 8]      = q10_to_8(I_tdata[i*30 +: 10]);
            data_r[i*24+8 +: 8]    = q10_to_8(I_tdata[i*30+10 +: 10]);
            data_r[i*24+16 +: 8]   = q10_to_8(I_tdata[i*30+20 +: 10]);
        end
    end

    assign I_tready = O_tready;
    assign O_tvalid = I_tvalid;
    assign O_tlast  = I_tlast;
    assign O_tuser  = I_tuser;
    assign O_tdata  = data_r;
endmodule
