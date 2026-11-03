"""Real adapter safety checks; no force or replacement of classification outputs."""
from datetime import datetime,timezone
from pathlib import Path
import argparse,json,os,re,shutil,subprocess,sys
sys.dont_write_bytecode=True
import binary_validation_reference as ref
ROOT=ref.ROOT;OUT=ref.OUT
BENCH=r'''
\x60timescale 1ns/1ps
module tb_binary_adapter_control;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,start=0,cancel=0,frame_valid=1,model_valid=1;
reg [31:0] job_id=0;reg[2:0]count=1;reg[255:0]boxes=0;reg overflow=0,truncated=0;
wire busy,lock,done,valid,no_target,bbox;wire[1:0]status;wire[15:0]error;
wire[10:0]xmin,xmax,px;wire[9:0]ymin,ymax,py;wire request;
reg ready=0,pixel_valid=0;reg[7:0]pixel_y8=128;
wire ws_we,ws_wbank,ws_rd_bank;wire[14:0]ws_waddr,ws_rd_addr;wire[15:0]ws_wdata,ws_rd_data;
wire signed[15:0]mac_a;wire signed[7:0]mac_w;wire signed[23:0]mac_product;
integer tests=0,reads=0,writes=0,t;string label;
pcb_ccl_binary_core #(.WEIGHTS_MEM("@WEIGHTS@"),.BIASES_MEM("@BIASES@"),.PIXEL_TIMEOUT(12),.ABORT_TIMEOUT(20))dut(
 .clk(clk),.rst_n(rst_n),.start(start),.cancel(cancel),.frame_valid(frame_valid),.model_valid(model_valid),.job_id(job_id),
 .I_ccl_count(count),.I_ccl_boxes(boxes),.I_ccl_overflow(overflow),.I_ccl_truncated(truncated),
 .busy(busy),.frame_lock(lock),.done(done),.result_valid(valid),.no_target(no_target),.status(status),.error(error),
 .bbox_valid(bbox),.xmin(xmin),.xmax(xmax),.ymin(ymin),.ymax(ymax),.detail_score(),.classifier_score(),.classifier_margin(),.outline_support(),
 .pixel_request(request),.pixel_x(px),.pixel_y(py),.pixel_ready(ready),.pixel_valid(pixel_valid),.pixel_y8(pixel_y8),
 .ws_we(ws_we),.ws_wbank(ws_wbank),.ws_waddr(ws_waddr),.ws_wdata(ws_wdata),.ws_rd_bank(ws_rd_bank),.ws_rd_addr(ws_rd_addr),.ws_rd_data(ws_rd_data),
 .mac_a(mac_a),.mac_w(mac_w),.mac_product_ext(mac_product),.phase(),.cycles());
vision_workspace_goodonly workspace(.clk(clk),.purpose(2'd1),.cnn_shape_we(1'b0),.cnn_shape_waddr(12'd0),.cnn_shape_wdata(16'd0),
 .cnn_f1_we(1'b0),.cnn_f1_waddr(13'd0),.cnn_f1_wdata(16'd0),.cnn_f2_we(1'b0),.cnn_f2_waddr(12'd0),.cnn_f2_wdata(16'd0),
 .cnn_rd_sel(2'd0),.cnn_rd_addr(13'd0),.cnn_rd_data(),.pcb_we(ws_we),.pcb_wbank(ws_wbank),.pcb_waddr(ws_waddr),.pcb_wdata(ws_wdata),
 .pcb_rd_bank(ws_rd_bank),.pcb_rd_addr(ws_rd_addr),.pcb_rd_data(ws_rd_data));
vision_shared_mac mac(.pcb_select(1'b1),.cnn_a(16'sd0),.cnn_w(8'sd0),.pcb_a(mac_a),.pcb_w(mac_w),.product(),.cnn_product(),.pcb_product(mac_product));
always@(posedge clk)if(rst_n)begin
 if(request&&ready)reads=reads+1;
 if(ws_we)writes=writes+1;
 if(cancel&&(request||ws_we))begin $display("CONTROL_FAIL cancellation admits work");$fatal(1);end
end
task fail(input string why);begin $display("BINARY_ADAPTER_CONTROL_FAIL case=%s state=%0d err=%h %s",label,dut.state,error,why);$fatal(1);end endtask
task pass;begin tests=tests+1;$display("BINARY_ADAPTER_CONTROL_PASS case=%s reads=%0d writes=%0d",label,reads,writes);end endtask
task reset;begin rst_n=0;start=0;cancel=0;ready=0;pixel_valid=0;repeat(3)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);count=1;overflow=0;truncated=0;frame_valid=1;model_valid=1;boxes=0;boxes[63:0]={16'd60,16'd120,16'd10,16'd20};reads=0;writes=0;end endtask
task launch;begin @(negedge clk);start=1;job_id=job_id+1;@(negedge clk);start=0;end endtask
task waitdone;begin t=0;while(!done&&t<100)begin@(negedge clk);t=t+1;end if(!done)fail("missing done");end endtask
task gate(input integer expect_status,input integer expect_error,input integer expect_no_target);begin
 launch();waitdone();if(status!==expect_status[1:0]||error!==expect_error[15:0]||valid!==(expect_status==2)||bbox||no_target!==expect_no_target[0]||busy||lock||reads!=0||writes!=0)fail("gate verdict/owner/side effects");pass();
end endtask
task awaitrequest;begin t=0;while(!request&&t<100)begin@(negedge clk);t=t+1;end if(!request||!lock)fail("request/ownership");if(px!==164||py!==82)fail("original-box first sample");end endtask
task accept;begin ready=1;@(negedge clk);ready=0;if(!dut.read_pending||!lock)fail("accepted read not owned");end endtask
task assertlocked(input integer code);begin
 waitdone();if(status!==3||error!==code[15:0]||valid||bbox||!busy||!lock||dut.state!=15)fail("missing persistent lock");
 start=1;pixel_valid=1;repeat(3)@(negedge clk);start=0;pixel_valid=0;repeat(3)@(negedge clk);
 if(!busy||!lock||dut.state!=15||request||ws_we||valid||bbox)fail("late response/restart unlocked fault");pass();
end endtask
initial begin
 reset();label="no_candidate";count=0;gate(2,'h0201,1);
 reset();label="label_overflow";overflow=1;gate(2,'h0201,0);
 reset();label="invalid_count";count=5;gate(2,'h0201,0);
 reset();label="model_invalid";model_valid=0;gate(3,'h0101,0);
 reset();label="frame_invalid";frame_valid=0;gate(3,'h0101,0);
 reset();label="source_left_border";boxes[15:0]=0;gate(2,'h0202,0);
 reset();label="source_top_border";boxes[31:16]=0;gate(2,'h0202,0);
 reset();label="source_right_border";boxes[47:32]=160;gate(2,'h0202,0);
 reset();label="source_bottom_border";boxes[63:48]=90;gate(2,'h0202,0);
 reset();label="zero_width";boxes[47:32]=20;gate(2,'h0202,0);
 reset();label="negative_height";boxes[63:48]=9;gate(2,'h0202,0);
 reset();label="ready_timeout";launch();assertlocked('h1001);
 reset();label="response_timeout_late_response";launch();awaitrequest();accept();assertlocked('h1002);
 reset();label="cancel_drain_late_response";launch();awaitrequest();accept();cancel=1;@(negedge clk);cancel=0;
 repeat(5)@(negedge clk);if(!lock||!busy||done||request||ws_we)fail("cancel failed to retain pending read");
 pixel_valid=1;@(negedge clk);pixel_valid=0;waitdone();if(busy||lock||valid||bbox||error!=='h0002||reads!=1||writes!=0)fail("late response drain");pass();
 label="reentry_after_drain";reads=0;writes=0;count=0;gate(2,'h0201,1);
 reset();label="cancel_abort_timeout";launch();awaitrequest();accept();cancel=1;@(negedge clk);cancel=0;assertlocked('h1003);
 reset();label="cancel_unaccepted_request";launch();awaitrequest();cancel=1;@(negedge clk);cancel=0;waitdone();if(busy||lock||valid||bbox||reads!=0||writes!=0||error!=='h0002)fail("unaccepted cancel");pass();
 reset();label="active_restart_abort";launch();awaitrequest();start=1;@(negedge clk);start=0;waitdone();if(busy||lock||valid||bbox||reads!=0||error!=='h0003)fail("restart abort");pass();
 reset();label="truncated_largest_box_allowed";truncated=1;launch();awaitrequest();if(xmin!==160||xmax!==960||ymin!==80||ymax!==480)fail("truncation/largest original box");cancel=1;@(negedge clk);cancel=0;waitdone();if(busy||lock)fail("truncated cancel");pass();
 reset();label="same_cycle_response_then_cancel";launch();awaitrequest();ready=1;pixel_valid=1;@(negedge clk);ready=0;pixel_valid=0;
 if(dut.read_pending||dut.state!=10||dut.captured_pixel!==128)fail("zero-latency accepted byte");
 cancel=1;@(negedge clk);cancel=0;waitdone();if(busy||lock||valid||bbox||reads!=1||writes!=0)fail("same-cycle cancel leaked byte");pass();
 $display("BINARY_ADAPTER_CONTROL_GOLDEN_PASS tests=%0d",tests);$finish;
end
endmodule
'''.replace('\\x60',chr(96))
def main():
 p=argparse.ArgumentParser();p.add_argument('--design',type=Path,required=True);a=p.parse_args();design=a.design.resolve()
 run=OUT/'adapter'/('run_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'));run.mkdir(parents=True,exist_ok=False);shutil.copy2('E:/model/modelsim.ini',run/'modelsim.ini')
 bench=BENCH.replace('@WEIGHTS@',(design/'model/experiments/conv4_4/weights.mem').as_posix()).replace('@BIASES@',(design/'model/experiments/conv4_4/biases.mem').as_posix());(run/'tb_adapter.sv').write_text(bench,encoding='ascii')
 rtl=[design/'01_rtl'/n for n in ['pcb_ccl_binary_core.v','pcb_fullboard_spatial96.v','vision_workspace_goodonly.v','vision_shared_mac.v']];models=list((design/'model/experiments/conv4_4').glob('*.mem'))
 manifest=ref.read(design/'SOURCE_MANIFEST.json')['files'];frozen={q.relative_to(design).as_posix():ref.sha(q) for q in rtl+models};assert all(manifest[k]['sha256']==v for k,v in frozen.items())
 ini=(run/'modelsim.ini').as_posix();(run/'run.do').write_text('\n'.join(['onerror {quit -code 2}','onbreak {quit -code 3}','vlib work','vlog -modelsimini '+ini+' -sv '+' '.join('"'+q.as_posix()+'"' for q in rtl+[run/'tb_adapter.sv']),'vsim -modelsimini '+ini+' -voptargs=+acc work.tb_binary_adapter_control','run -all','quit -code 0','']),encoding='ascii')
 pins={str(q):ref.sha(q) for q in rtl+models+[Path(__file__),Path(ref.__file__),design/'SOURCE_MANIFEST.json',run/'tb_adapter.sv',run/'modelsim.ini',run/'run.do']};ref.save(run/'SOURCE_SHA256.json',pins)
 env=dict(os.environ);env['MGLS_LICENSE_FILE']=env['LM_LICENSE_FILE']='E:/model/win64/LICENSE.TXT'
 with(run/'SIM.log').open('w',encoding='utf-8')as log:proc=subprocess.run(['E:/model/win64/vsim.exe','-modelsimini',ini,'-batch','-syncio','-do','run.do'],cwd=run,env=env,stdout=log,stderr=subprocess.STDOUT)
 log=(run/'SIM.log').read_text(encoding='utf-8',errors='replace');unchanged=all(ref.sha(Path(q))==h for q,h in pins.items());ok=proc.returncode==0 and 'BINARY_ADAPTER_CONTROL_GOLDEN_PASS tests=20'in log and not re.search(r'\*\*\s+(Error|Fatal):',log) and unchanged
 result={'status':'PASS'if ok else'FAIL','tests_passed':log.count('BINARY_ADAPTER_CONTROL_PASS'),'returncode':proc.returncode,'sources_unchanged':unchanged,'frozen_manifest_sha256':ref.sha(design/'SOURCE_MANIFEST.json'),'frozen_design_inputs':frozen,'run_directory':str(run),'log_sha256':ref.sha(run/'SIM.log'),'limitations':['Isolated actual adapter with shortened I/O timeout parameters; numerical equality is proved separately by integrated fixtures.','No physical DDR or board behavior is proved.'],'hardware':'NOT_RUN'}
 ref.save(run/'RESULTS.json',result);print(json.dumps(result,indent=2));return 0 if ok else 1
if __name__=='__main__':raise SystemExit(main())
