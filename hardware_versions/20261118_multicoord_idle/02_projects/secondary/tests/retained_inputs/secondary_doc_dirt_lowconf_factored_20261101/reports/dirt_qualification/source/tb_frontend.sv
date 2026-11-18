`timescale 1ns/1ps
module tb_frontend;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, start=0, cancel=0;
    wire busy,done,error; wire [7:0] error_code;
    wire pixel_request,pixel_invalidate; wire [10:0] pixel_x; wire [9:0] pixel_y;
    reg pixel_ready=0,pixel_valid=0; reg [7:0] pixel_luma=0;
    wire ink_valid,ink_bit; wire [16:0] ink_addr; reg ink_ready=0;
    wire [127:0] corners;
    doc_image_frontend #(.TIMEOUT_CYCLES(30000000)) dut(.*);
    reg [7:0] image[0:921599]; reg expected[0:102399];
    string image_path,expected_path,output_path,case_name;
    integer output_file,cycle=0,requests=0,emitted=0,in_cell=0;
    integer outstanding=0,pending=0,delay_left=0,px_hold,py_hold;
    integer ax,ay,gx,gy,si,ex,ey,cell_reads,lifecycle=0,partial=0;
    integer response_count=0,backpressure_count=0,request_stall_count=0;
    reg hold_ink=0,hold_request=0; reg [16:0] held_addr; reg held_bit;
    reg [10:0] held_x; reg [9:0] held_y;
    function integer clampx(input integer x);
        clampx=(x<0)?0:((x>1279)?1279:x);
    endfunction
    function integer clampy(input integer y);
        clampy=(y<0)?0:((y>719)?719:y);
    endfunction
    function integer offset(input integer k);
        case(k) 0: offset=-10; 1: offset=-2; 2: offset=6; 3: offset=14; endcase
    endfunction
    always @(posedge clk) begin
        cycle<=cycle+1;
        pixel_ready<=((cycle%7)!=0)&&((cycle%11)!=0);
        ink_ready<=((cycle%5)!=0)&&((cycle%13)!=0);
        pixel_valid<=0;
        if(!rst_n || cancel) begin
            pending<=0; outstanding<=0; requests<=0; emitted<=0; in_cell<=0;
            hold_ink<=0; hold_request<=0;
        end else begin
            if(error) $fatal(1,"unexpected frontend error %d",error_code);
            if(hold_ink && (!ink_valid || ink_addr!==held_addr || ink_bit!==held_bit))
                $fatal(1,"ink changed under backpressure");
            hold_ink<=ink_valid&&!ink_ready;
            if(ink_valid&&!ink_ready) begin
                held_addr<=ink_addr; held_bit<=ink_bit; backpressure_count<=backpressure_count+1;
            end
            if(hold_request && (!pixel_request || pixel_x!==held_x || pixel_y!==held_y))
                $fatal(1,"request changed before acceptance");
            hold_request<=pixel_request&&!pixel_ready;
            if(pixel_request&&!pixel_ready) begin
                held_x<=pixel_x; held_y<=pixel_y; request_stall_count<=request_stall_count+1;
            end
            if(pending) begin
                if(pixel_x!==px_hold || pixel_y!==py_hold)
                    $fatal(1,"address changed while pixel pending");
                if(delay_left==0) begin
                    pixel_valid<=1; pixel_luma<=partial?8'd0:image[py_hold*1280+px_hold]; pending<=0;
                end else delay_left<=delay_left-1;
            end
            if(pixel_valid) begin
                if(outstanding!=1) $fatal(1,"response without outstanding request");
                outstanding<=0; response_count<=response_count+1;
            end
            if(pixel_request&&pixel_ready) begin
                if(outstanding!=0 || pending || pixel_valid) $fatal(1,"multiple outstanding requests");
                gx=ink_addr%320; gy=(ink_addr/320)-70; si=in_cell;
                cell_reads=(gx>=288 && gx<=319 && gy>=112 && gy<=179)?32:16;
                if(gy<0 || gy>=180 || si>=cell_reads) $fatal(1,"request outside active cell or unnecessary ROI probe");
                if(si<16) begin ex=4*gx+(si%4); ey=4*gy+(si/4); end
                else begin ex=clampx(4*gx+offset(si%4)); ey=clampy(4*gy+offset((si-16)/4)); end
                if(pixel_x!==ex || pixel_y!==ey)
                    $fatal(1,"address sequence mismatch addr=%d sample=%d got=%d,%d want=%d,%d",ink_addr,si,pixel_x,pixel_y,ex,ey);
                requests<=requests+1; in_cell<=in_cell+1; outstanding<=1; pending<=1;
                px_hold<=pixel_x; py_hold<=pixel_y; delay_left<=(requests%3);
            end
            if(ink_valid&&ink_ready) begin
                if(ink_addr!==emitted) $fatal(1,"output address mismatch");
                if(!partial && ink_bit!==expected[emitted]) $fatal(1,"bit mismatch addr=%d got=%d expected=%d",ink_addr,ink_bit,expected[emitted]);
                gy=(ink_addr/320)-70;
                gx=ink_addr%320;
                cell_reads=(gy<0 || gy>=180)?0:((gx>=288 && gx<=319 && gy>=112 && gy<=179)?32:16);
                if(in_cell!=cell_reads) $fatal(1,"wrong requests per cell %d expected %d",in_cell,cell_reads);
                if(outstanding!=0) $fatal(1,"emit with outstanding request");
                if(!partial) $fwrite(output_file,"%0d\n",ink_bit);
                emitted<=emitted+1; in_cell<=0;
            end
            if(done) begin
                if(emitted!=102400 || requests!=956416) $fatal(1,"incomplete frame %d %d",emitted,requests);
                if(busy) $fatal(1,"done still busy");
            end
        end
    end
    task automatic launch;
        begin @(negedge clk);start=1;@(negedge clk);start=0; end
    endtask
    task automatic wait_complete;
        begin
            wait(done); @(negedge clk);
            if(error || busy || emitted!=102400) $fatal(1,"bad completion");
            if(corners!=={{16'd719},{16'd0},{16'd719},{16'd1279},{16'd0},{16'd1279},{16'd0},{16'd0}})
                $fatal(1,"corners contract changed");
            $display("PASS FRAME %s requests=%0d outputs=%0d",case_name,requests,emitted);
            @(negedge clk);
        end
    endtask
    initial begin
        if(!$value$plusargs("IMAGE=%s",image_path) || !$value$plusargs("EXPECTED=%s",expected_path) ||
           !$value$plusargs("OUTPUT=%s",output_path) || !$value$plusargs("CASE=%s",case_name)) $fatal(1,"missing paths");
        ax=$value$plusargs("LIFECYCLE=%d",lifecycle);
        $readmemh(image_path,image); $readmemb(expected_path,expected);
        output_file=$fopen(output_path,"w"); if(!output_file) $fatal(1,"cannot open output");
        repeat(5) @(negedge clk); rst_n=1;
        if(lifecycle) begin
            // Dirty the minimum and background accumulator inside the fixed
            // ROI, cancel with one read outstanding, then replay clean blank.
            partial=1; launch(); wait(requests>=578069 && pending);
            @(negedge clk); cancel=1; @(negedge clk);cancel=0;
            repeat(6) @(negedge clk);
            if(busy||done||error||ink_valid||pixel_request) $fatal(1,"cancel did not release");
            partial=0; launch(); wait_complete();
            $display("PASS CANCEL_DIRTY_ROI_PENDING_AND_BLANK_REENTRY");
            @(negedge clk); cancel=1; @(negedge clk);cancel=0;
            partial=1; launch(); wait(requests>=578079 && pending);
            @(negedge clk);rst_n=0; repeat(3) @(negedge clk);rst_n=1;
            repeat(5) @(negedge clk);
            if(busy||done||error||ink_valid||pixel_request) $fatal(1,"reset did not release");
            partial=0; launch(); wait_complete();
            $display("PASS RESET_DIRTY_ROI_PENDING_AND_BLANK_REENTRY");
        end else begin launch(); wait_complete(); end
        if(!backpressure_count || !request_stall_count) $fatal(1,"stall coverage missing");
        $fclose(output_file);
        $display("PASS FRONTEND %s cycles=%0d backpressure=%0d request_stalls=%0d",case_name,cycle,backpressure_count,request_stall_count);
        $finish;
    end
    initial begin #1500000000; $fatal(1,"testbench watchdog"); end
endmodule
