`timescale 1ns/1ps
module tb_timeout;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,start=0,cancel=0;
    wire busy,done,error; wire [7:0] error_code;
    wire pixel_request,pixel_invalidate; wire [10:0] pixel_x; wire [9:0] pixel_y;
    reg pixel_ready=1,pixel_valid=0; reg [7:0] pixel_luma=0;
    wire ink_valid,ink_bit; wire [16:0] ink_addr; reg ink_ready=1;
    wire [127:0] corners;
    integer requests=0;
    doc_image_frontend #(.TIMEOUT_CYCLES(64),.FRAME_AS_A4_WIDTH(0)) dut(.*);
    always @(posedge clk) if(pixel_request&&pixel_ready) requests<=requests+1;
    initial begin
        repeat(5) @(negedge clk); rst_n=1; start=1;
        @(negedge clk); start=0; wait(done); @(negedge clk);
        if(!error || error_code!=1 || busy || requests!=1) $fatal(1,"timeout contract mismatch");
        @(negedge clk); cancel=1; @(negedge clk); cancel=0;
        repeat(2) @(negedge clk);
        if(error||busy||done||pixel_request||ink_valid) $fatal(1,"timeout cancel did not clear");
        $display("PASS TIMEOUT_PENDING_AND_CANCEL requests=%0d",requests); $finish;
    end
    initial begin #10000; $fatal(1,"timeout test watchdog"); end
endmodule
