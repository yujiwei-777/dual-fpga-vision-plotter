`timescale 1ns/1ps
module tb_doc_center80;
parameter integer CENTER=1;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,start=0,cancel=0;
wire busy,done,error,pixel_request,pixel_invalidate,ink_valid,ink_bit;
wire [7:0]error_code;wire [10:0]pixel_x;wire [9:0]pixel_y;
wire [16:0]ink_addr;wire [127:0]corners;
reg pixel_valid=0;reg[7:0]pixel_luma=255;
integer cycle=0,pending=0,delay_left=0,address=0;
integer emitted=0,requests=0,pass_count=0,mode=0;
integer checks=0,cancels=0;
reg check_outputs=0;reg [7:0]source_y[0:921599];reg expected[0:102399];
wire pixel_ready=!pending&&(cycle%7!=1)&&(cycle%11!=3);
wire ink_ready=(cycle%5!=1)&&(cycle%13!=2)&&(cycle%17!=7);
reg stall=0;reg[16:0]held_addr;reg held_bit;
string source_file,expected_file;
doc_image_frontend #(.CENTER80_ENABLE(CENTER)) dut(.*);
task tick(input integer n);repeat(n)@(negedge clk);endtask
task launch;begin start=1;tick(1);start=0;end endtask
task abandon;begin
 cancel=1;tick(1);cancel=0;pending=0;pixel_valid=0;stall=0;tick(5);
 if(busy||done||error||ink_valid||pixel_request)$fatal(1,"cancel not quiescent");
 cancels++;
end endtask
initial begin
 if(!$value$plusargs("SOURCE=%s",source_file)||!$value$plusargs("EXPECTED=%s",expected_file))$fatal(1,"missing fixture");
 $readmemh(source_file,source_y);$readmemb(expected_file,expected);
 tick(5);rst_n=1;tick(3);
 if(CENTER!=0)begin
  launch;wait(pixel_request&&pixel_ready);tick(1);abandon;
  launch;wait(ink_valid&&!ink_ready);tick(1);abandon;
 end
 emitted=0;requests=0;check_outputs=1;launch;
 wait(done);tick(2);
 if(busy||error||emitted!=102400)$fatal(1,"incomplete output count=%0d busy=%b error=%h",emitted,busy,error_code);
 if(CENTER!=0&&requests!=589824)$fatal(1,"central crop request count=%0d",requests);
 if(CENTER==0&&requests!=956416)$fatal(1,"default fullframe/dirt request count=%0d",requests);
 if(corners!=={16'd719,16'd0,16'd719,16'd1279,16'd0,16'd1279,16'd0,16'd0})$fatal(1,"coordinate corners remapped");
 tick(20);if(busy||ink_valid||pixel_request)$fatal(1,"completed frame replayed");
 $display("DOC_CENTER80_PASS center=%0d outputs=%0d requests=%0d checks=%0d cancels=%0d",CENTER,emitted,requests,checks,cancels);$finish;
end
always @(posedge clk)begin
 cycle<=cycle+1;pixel_valid<=0;
 if(cycle>30000000)$fatal(1,"watchdog");
 if(rst_n&&!cancel)begin
  if(stall&&(ink_valid!==1||ink_addr!==held_addr||ink_bit!==held_bit))$fatal(1,"output changed under backpressure");
  stall=ink_valid&&!ink_ready;held_addr=ink_addr;held_bit=ink_bit;
  if(pixel_request)begin
   if(pixel_x>1279||pixel_y>719)$fatal(1,"DDR outside source");
   if(CENTER!=0&&(pixel_x<128||pixel_x>1151||pixel_y<72||pixel_y>647))$fatal(1,"DDR requested outside center80 x%0d y%0d",pixel_x,pixel_y);
  end
  if(pixel_request&&pixel_ready)begin
   address=pixel_y*1280+pixel_x;pending=1;delay_left=1+cycle%4;
   if(check_outputs)requests++;
  end else if(pending)begin
   if(delay_left>0)delay_left--;
   else begin pixel_luma<=source_y[address];pixel_valid<=1;pending=0;end
  end
  if(check_outputs&&ink_valid&&ink_ready)begin
   if(ink_addr!==emitted||ink_bit!==expected[emitted])$fatal(1,"output mismatch addr=%0d expectedaddr=%0d bit=%b expected=%b",ink_addr,emitted,ink_bit,expected[emitted]);
   emitted++;checks++;
  end
 end
end
endmodule
