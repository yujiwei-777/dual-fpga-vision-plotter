"""CCL/original-ROI/retrained-binary-model integrated RTL regression with real source Y.
The external pixel interface is abstract; raw DDR timing is not proved here.
"""
from datetime import datetime,timezone
from pathlib import Path
import argparse,importlib.util,json,os,re,shutil,subprocess,sys
import numpy as np
sys.dont_write_bytecode=True
import binary_validation_reference_compat as ref
ROOT=ref.ROOT;OUT=ref.OUT
def load_module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def fixtures():
    target=OUT/'pipeline_fixtures';target.mkdir(exist_ok=False)
    index=ref.read(OUT/'fixtures/INDEX.json');arrays=np.load(OUT/'fixtures/ARRAYS.npz')
    allrows=[]
    for row in index['selected_source_results']:
        y,_,_=ref.load_y(row['source_json']);allrows.append((row,y))
    y=np.full((720,1280),240,np.uint8);allrows.append(({'name':'synthetic_blank','status':'REVIEW','ccl':ref.ccl(y),'gate_reasons':['no_candidate']},y))
    y=np.full((720,1280),240,np.uint8);y[80:400,:320]=20
    allrows.append(({'name':'synthetic_source_border','status':'REVIEW','ccl':ref.ccl(y),'gate_reasons':['source_border']},y))
    y=np.full((720,1280),240,np.uint8)
    for gy in range(0,90,2):
        for gx in range(0,160,2):y[8*gy+4,8*gx+4]=20
    allrows.append(({'name':'synthetic_label_overflow','status':'REVIEW','ccl':ref.ccl(y),'gate_reasons':['ccl_overflow']},y))
    cases=[]
    for row,y in allrows:
        dst=target/row['name'];dst.mkdir();mask,cc=ref.independent_ccl(y.ravel().tolist())
        assert cc['count']==row['ccl']['count'] and cc['overflow']==row['ccl']['overflow']
        ref.mem(dst/'source_y.mem',y,8);ref.mem(dst/'mask.mem',mask,4)
        boxes=[];areas=[]
        for r in cc['top4']:
            x0,y0,x1,y1=r['grid_box'];boxes.append((y1<<48)|(x1<<32)|(y0<<16)|x0);areas.append(r['area'])
        ref.mem(dst/'boxes.mem',boxes+[0]*(4-len(boxes)),64);ref.mem(dst/'areas.mem',areas+[0]*(4-len(areas)),16)
        valid=not row['gate_reasons'];case={'name':row['name'],'ccl':cc,'valid':valid,'bbox':row['ccl']['bbox'] if valid else [0,0,0,0],'status':dict(PASS=0,FAIL=1,REVIEW=2)[row['status']],'score':row.get('score',0),'margin':row.get('margin',0),'class_id':row.get('class_id',0),'core_case':row.get('core_case')}
        if valid:
            i=row['core_case'];ref.mem(dst/'roi.mem',arrays['roi'][i],8);ref.mem(dst/'sample_x.mem',row['x_addresses'],16);ref.mem(dst/'sample_y.mem',row['y_addresses'],16)
            ref.mem(dst/'conv1.mem',arrays['conv1'][i].transpose(1,2,0),16);ref.mem(dst/'conv2.mem',arrays['conv2'][i].transpose(1,2,0),16)
            ref.mem(dst/'pool.mem',arrays['pool'][i],16);ref.mem(dst/'logits.mem',arrays['logits'][i],32)
        ref.save(dst/'EXPECTED.json',case);cases.append(case)
    ref.save(target/'INDEX.json',cases);ref.save(target/'SHA256.json',{str(p.relative_to(target)):ref.sha(p) for p in target.rglob('*') if p.is_file()})
    return cases

BENCH=r'''
\x60timescale 1ns/1ps
\x60define AD dut.g_pcb_ccl_binary.pcb_auto
\x60define CORE dut.g_pcb_ccl_binary.pcb_auto.classifier
\x60define WS dut.g_shared_workspace.workspace
module tb_binary_fullpipeline;
    localparam WEIGHTS="@WEIGHTS@",BIASES="@BIASES@",CNN_WEIGHTS="@CNN_WEIGHTS@",CNN_BIASES="@CNN_BIASES@";
    reg clk=0;always #4 clk=~clk;
    reg rst_n=0,start=0,cancel=0;reg[1:0] purpose=1;reg[31:0] job_id=0;
    wire busy,done,valid,checked,good,frame_lock;wire[2:0] status,defect_count,multi_count;
    wire[255:0] defect_boxes;wire[7:0] defect_kinds,confidence;wire[511:0] multi_boxes;
    wire[10:0] x0,x1,pixel_x;wire[9:0]y0,y1,pixel_y;wire request,invalidate;
    wire[31:0]result_job_id,version;
    reg pending=0,pixel_valid=0,response_enable=1;reg[7:0]pixel_luma=0,response_data=0;
    wire pixel_ready=!pending;wire[23:0]pixel_rgb={pixel_luma,pixel_luma,pixel_luma};
    integer delay_left=0,accepts=0,replies=0,cycles=0,launch_cycle=0;
    integer scan_reads=0,roi_reads=0,stored_mask=0,streamed_mask=0,ccl_commits=0,roi_stores=0,f1_writes=0,f2_writes=0,pool_count=0;
    integer expected_count,expected_overflow,expected_truncated,expected_status,expected_score,expected_margin,expected_class,expected_valid;
    integer expected_x0,expected_y0,expected_x1,expected_y1,frame_cases=0,cancel_cases=0,i;
    reg checks=0,active_job=0,cancel_job=0;
    reg[7:0]source_y[0:921599],roi[0:9215];reg[15:0]f1[0:9215],f2[0:2303],pool[0:63],sample_x[0:95],sample_y[0:95],areas[0:3];
    reg signed[31:0]logits[0:1];reg[63:0]boxes[0:3];reg mask[0:14399];
    string fixtures,case_name;
    vision_pipeline #(.EXTERNAL_READER(1),.LOCAL_CNN_ENABLE(1),.SHARED_WORKSPACE(1),.PCB_ENABLE(1),.PCB_GOODONLY_AUTO(1),.PCB_BINARY_WEIGHTS_MEM(WEIGHTS),.PCB_BINARY_BIASES_MEM(BIASES))dut(
      .clk(clk),.rst_n(rst_n),.start(start),.purpose(purpose),.teach_good(1'b0),.cancel(cancel),.job_id(job_id),
      .word_req(),.byte_addr(),.word_ready(1'b0),.word_valid(1'b0),.word_data(128'd0),
      .cfg_we(1'b0),.cfg_addr(15'd0),.cfg_data(8'd0),.cfg_commit(1'b0),.busy(busy),.done(done),.result_job_id(result_job_id),.config_version(version),
      .color_id(),.shape_id(),.confidence(confidence),.valid(valid),.x0(x0),.x1(x1),.y0(y0),.y1(y1),.area(),
      .pcb_checked(checked),.pcb_good(good),.pcb_status(status),.defect_count(defect_count),.defect_boxes(defect_boxes),.defect_kinds(defect_kinds),
      .multi_count(multi_count),.multi_boxes(multi_boxes),.multi_flags(),.teach_success(),.teach_failed(),.teach_code(),.teach_commit(),.taught_station_header(),
      .ext_reader_ready(pixel_ready),.ext_reader_valid(pixel_valid),.ext_reader_rgb(pixel_rgb),.ext_reader_luma(pixel_luma),.ext_reader_request(request),.ext_reader_invalidate(invalidate),
      .ext_pixel_x(pixel_x),.ext_pixel_y(pixel_y),.yolo_pixel_valid(),.yolo_pixel_rgb(),.yolo_pixel_last(),.color_word_active(),.history_clear(1'b0),.pcb_frame_lock(frame_lock));
    defparam dut.g_local_cnn.classifier.WEIGHTS_MEM=CNN_WEIGHTS;
    defparam dut.g_local_cnn.classifier.BIASES_MEM=CNN_BIASES;
    task fail(input string why);begin $display("BINARY_FULLPIPELINE_FAIL case=%s cycle=%0d state=%0d adapter=%0d %s",case_name,cycles,dut.state,\x60AD.state,why);$fatal(1,"integrated regression failed");end endtask
    always@(posedge clk)begin
      cycles=cycles+1;
      if(!rst_n)begin pending<=0;delay_left<=0;accepts=0;replies=0;end
      else begin
        if(pixel_valid)begin pending<=0;replies=replies+1;end
        if(pending&&delay_left>0)delay_left<=delay_left-1;
        if(request&&pixel_ready)begin
          if(pixel_x>=1280||pixel_y>=720)fail("out of source coordinate");
          if(cancel_job)fail("new request after cancel");
          if(checks)begin
            if(dut.auto_owner)begin
              if(!expected_valid||roi_reads>=9216)fail("unexpected ROI read");
              if(pixel_x!==sample_x[roi_reads%96]||pixel_y!==sample_y[roi_reads/96])fail($sformatf("ROI address index=%0d got=%0d,%0d expected=%0d,%0d",roi_reads,pixel_x,pixel_y,sample_x[roi_reads%96],sample_y[roi_reads/96]));
              roi_reads=roi_reads+1;
            end else begin
              if(scan_reads>=14400||pixel_x!==(8*(scan_reads%160)+4)||pixel_y!==(8*(scan_reads/160)+4))fail("CCL scan address/order");
              scan_reads=scan_reads+1;
            end
          end
          response_data<=source_y[pixel_y*1280+pixel_x];pending<=1;delay_left<=1+(accepts%3);accepts=accepts+1;
        end
        if(pending&&purpose==1&&!frame_lock)fail("frame ownership released before response");
        if(active_job&&purpose==1&&busy&&!frame_lock)fail("active PCB frame not locked");
        if(cancel&&request)fail("same-cycle cancel admitted request");
        if(cancel_job&&done)fail("cancelled job published done");
        if(purpose==1&&(defect_count!==0||defect_boxes!==0||defect_kinds!==0))fail("unvalidated localized defects published");
        if(checks)begin
          if(dut.edge_components.state==dut.edge_components.S_STORE&&dut.cc_pixel_valid&&dut.cc_ready)begin
            if(stored_mask>=14400||(dut.sampled_source_y<=112)!==mask[stored_mask])fail("CCL stored source-Y mask");
            stored_mask=stored_mask+1;
          end
          if(dut.edge_components.ccl_pixel_valid&&dut.edge_components.ccl_ready)begin
            if(streamed_mask>=14400||dut.edge_components.mask_pending!==mask[streamed_mask])fail("CCL streamed mask");
            streamed_mask=streamed_mask+1;
          end
          if(dut.cc_done)begin
            if(dut.cc_count!==expected_count||dut.cc_overflow!==expected_overflow[0]||dut.cc_truncated!==expected_truncated[0])fail("CCL flags");
            for(i=0;i<4;i=i+1)begin if(dut.cc_boxes[64*i+:64]!==boxes[i])fail("CCL bbox");if(dut.cc_areas[16*i+:16]!==areas[i])fail("CCL area");end
            ccl_commits=ccl_commits+1;
          end
          if(\x60AD.core_pixel_we)begin
            if(roi_stores>=9216||\x60AD.roi_index!==roi_stores||\x60AD.captured_pixel!==roi[roi_stores])fail("ROI byte/load index");
            roi_stores=roi_stores+1;
          end
          if(dut.ws_pcb_we&&\x60CORE.state==3)begin if(dut.ws_pcb_waddr>=9216||dut.ws_pcb_wdata!==f1[dut.ws_pcb_waddr])fail("Conv1 workspace write");f1_writes=f1_writes+1;end
          if(dut.ws_pcb_we&&\x60CORE.state==6)begin if(dut.ws_pcb_waddr>=2304||dut.ws_pcb_wdata!==f2[dut.ws_pcb_waddr])fail("Conv2 workspace write");f2_writes=f2_writes+1;end
          if(\x60CORE.busy&&\x60CORE.state==9&&\x60CORE.phase==0)begin if(\x60CORE.pool_value!==pool[\x60CORE.hindex])fail("spatial pool value");pool_count=pool_count+1;end
          if(\x60CORE.done)begin
            if($signed(\x60CORE.logits[0])!==logits[0]||$signed(\x60CORE.logits[1])!==logits[1])fail("final logits");
            if(\x60CORE.class_id!==expected_class||\x60CORE.score!==expected_score||\x60CORE.margin!==expected_margin)fail("core class/score/margin");
          end
        end
      end
    end
    always@(negedge clk)begin pixel_valid<=0;if(rst_n&&pending&&delay_left==0&&response_enable)begin pixel_valid<=1;pixel_luma<=response_data;end end
    task load(input string name);string path;begin
      case_name=name;path={fixtures,"/",name,"/"};
      \x60include "binary_pipeline_config.svh"
      $readmemh({path,"source_y.mem"},source_y);$readmemh({path,"mask.mem"},mask);$readmemh({path,"boxes.mem"},boxes);$readmemh({path,"areas.mem"},areas);
      if(expected_valid)begin $readmemh({path,"roi.mem"},roi);$readmemh({path,"sample_x.mem"},sample_x);$readmemh({path,"sample_y.mem"},sample_y);$readmemh({path,"conv1.mem"},f1);$readmemh({path,"conv2.mem"},f2);$readmemh({path,"pool.mem"},pool);$readmemh({path,"logits.mem"},logits);end
    end endtask
    task launch;begin if(busy||frame_lock||pending)fail("reentry before owner clear");@(negedge clk);start=1;job_id=job_id+1;active_job=1;launch_cycle=cycles;@(negedge clk);start=0;end endtask
    task run_frame(input string name);integer timeout;begin
      purpose=1;checks=0;cancel_job=0;response_enable=1;load(name);scan_reads=0;roi_reads=0;stored_mask=0;streamed_mask=0;ccl_commits=0;roi_stores=0;f1_writes=0;f2_writes=0;pool_count=0;
      checks=1;launch();timeout=0;while(!done&&timeout<3000000)begin@(negedge clk);timeout=timeout+1;end
      if(!done)fail("timeout");
      if(valid!==expected_valid[0]||status!==expected_status||checked!==(expected_valid&&expected_status<2)||good!==(expected_valid&&expected_status==0))fail("result verdict/checked/valid");
      if(x0!==expected_x0||x1!==expected_x1||y0!==expected_y0||y1!==expected_y1)fail("published original bbox");
      if(result_job_id!==job_id||version!==32'h50434233||confidence!==((expected_score*100+127)/255))fail("result metadata/confidence");
      if(scan_reads!=14400||stored_mask!=14400||streamed_mask!=14400||ccl_commits!=1)fail("CCL coverage counts");
      if(expected_valid&&(roi_reads!=9216||roi_stores!=9216||f1_writes!=9216||f2_writes!=2304||pool_count!=128))fail("inference coverage counts");
      if(!expected_valid&&(roi_reads!=0||roi_stores!=0||f1_writes!=0||f2_writes!=0))fail("gated frame entered CNN");
      if(busy||frame_lock||pending||accepts!=replies)fail("completion retains read/owner");
      $display("BINARY_FULLPIPELINE_FRAME_PASS name=%s status=%0d valid=%0d ROI=%0d cycles=%0d",name,status,valid,roi_reads,cycles-launch_cycle);frame_cases=frame_cases+1;checks=0;active_job=0;repeat(3)@(negedge clk);
    end endtask
    task run_cancel(input integer mode);integer timeout;begin
      purpose=1;checks=0;cancel_job=0;load("real_00_current_good");response_enable=(mode!=0);launch();timeout=0;
      if(mode==0)begin while(!pending&&timeout<1000)begin@(negedge clk);timeout=timeout+1;end if(!pending)fail("no CCL pending cancel trigger");end
      else if(mode==1)begin while(!(dut.auto_owner&&pending)&&timeout<1000000)begin@(negedge clk);timeout=timeout+1;end if(timeout>=1000000)fail("no ROI cancel trigger");response_enable=0;end
      else begin while(!(\x60CORE.busy&&\x60CORE.state==5)&&timeout<2000000)begin@(negedge clk);timeout=timeout+1;end if(timeout>=2000000)fail("no Conv2 cancel trigger");end
      @(negedge clk);cancel=1;cancel_job=1;repeat(5)@(negedge clk);response_enable=1;repeat(2)@(negedge clk);cancel=0;
      timeout=0;while((busy||frame_lock||pending)&&timeout<100000)begin@(negedge clk);timeout=timeout+1;end
      if(busy||frame_lock||pending||valid||accepts!=replies)fail("cancel did not drain/invalidate");
      active_job=0;cancel_job=0;$display("BINARY_FULLPIPELINE_CANCEL_PASS mode=%0d",mode);cancel_cases=cancel_cases+1;repeat(4)@(negedge clk);
    end endtask
    task run_ordinary_empty;integer timeout;begin
      purpose=0;checks=0;cancel_job=0;load("synthetic_blank");launch();timeout=0;while(!done&&timeout<2000000)begin@(negedge clk);timeout=timeout+1;end
      if(!done||valid||multi_count!==0||multi_boxes!==0||frame_lock||pending)fail("ordinary empty after PCB retained stale target");
      $display("BINARY_FULLPIPELINE_ORDINARY_EMPTY_PASS");active_job=0;repeat(3)@(negedge clk);
    end endtask
    initial begin
      if(!$value$plusargs("FIXTURES=%s",fixtures))$fatal(1,"missing FIXTURES");repeat(5)@(negedge clk);rst_n=1;
      \x60include "binary_pipeline_calls.svh"
      run_ordinary_empty();run_frame("real_00_current_good");
      $display("BINARY_FULLPIPELINE_GOLDEN_PASS frames=%0d cancels=%0d",frame_cases,cancel_cases);$finish;
    end
endmodule
'''.replace('\\x60',chr(96))

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run',action='store_true');parser.add_argument('--design',type=Path,default=ROOT);args=parser.parse_args();design=args.design.resolve()
    cases=ref.read(OUT/'pipeline_fixtures/INDEX.json') if(OUT/'pipeline_fixtures/INDEX.json').is_file() else fixtures()
    for directory in (OUT/'fixtures',OUT/'pipeline_fixtures'):
        sealed=ref.read(directory/'SHA256.json');assert all(ref.sha(directory/k)==v for k,v in sealed.items()),'fixture hash drift'
    run=OUT/'pipeline'/('run_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'));run.mkdir(parents=True,exist_ok=False)
    shutil.copy2('E:/model/modelsim.ini',run/'modelsim.ini')
    bench=BENCH
    for tag,path in{'WEIGHTS':design/'model/experiments/conv4_4/weights.mem','BIASES':design/'model/experiments/conv4_4/biases.mem','CNN_WEIGHTS':design/'model/export/weights.mem','CNN_BIASES':design/'model/export/biases.mem'}.items():bench=bench.replace('@'+tag+'@',path.as_posix())
    (run/'tb_binary_fullpipeline.sv').write_text(bench,encoding='ascii')
    config=[]
    for r in cases:
        c=r['ccl'];box=r['bbox'];assignments={'expected_count':c['count'],'expected_overflow':int(c['overflow']),'expected_truncated':int(c['truncated']),'expected_status':r['status'],'expected_score':r['score'],'expected_margin':r['margin'],'expected_class':r['class_id'],'expected_valid':int(r['valid']),'expected_x0':box[0],'expected_y0':box[1],'expected_x1':box[2],'expected_y1':box[3]}
        config.append('if(name=="'+r['name']+'")begin '+''.join(f'{k}={v};' for k,v in assignments.items())+'end')
    (run/'binary_pipeline_config.svh').write_text(' else '.join(config)+' else fail("unknown fixture");\n',encoding='ascii')
    calls=''.join('run_frame("'+r['name']+'");\n' for r in cases)
    for mode in range(3):calls+=f'run_cancel({mode});run_frame("real_00_current_good");\n'
    (run/'binary_pipeline_calls.svh').write_text(calls,encoding='ascii')
    names=['vision_pipeline.v','edge_roi_ccl_shared_pcb_candidate.v','vision_ccl_pcb_candidate.v','pcb_ccl_binary_core.v','pcb_fullboard_spatial96.v','cnn_core.v','vision_workspace_goodonly.v','vision_shared_mac.v','cnn_result_stabilizer.v','vision_color_stats.v','vision_pixel_reader.v']
    sources=[design/'01_rtl'/n for n in names]+[run/'tb_binary_fullpipeline.sv']
    (run/'run.do').write_text('\n'.join(['onerror {quit -code 2}','onbreak {quit -code 3}','vlib work','vlog -modelsimini '+(run/'modelsim.ini').as_posix()+' -sv +incdir+'+run.as_posix()+' '+' '.join('"'+p.as_posix()+'"' for p in sources),'vsim -modelsimini '+(run/'modelsim.ini').as_posix()+' -voptargs=+acc work.tb_binary_fullpipeline +FIXTURES='+(OUT/'pipeline_fixtures').as_posix(),'run -all','quit -code 0','']),encoding='ascii')
    inputs=sources+[run/'modelsim.ini',design/'SOURCE_MANIFEST.json',Path(__file__),Path(ref.__file__),OUT/'fixtures/SHA256.json',run/'binary_pipeline_calls.svh',run/'binary_pipeline_config.svh',OUT/'pipeline_fixtures/SHA256.json']+list((design/'model/experiments/conv4_4').glob('*.mem'))+list((design/'model/export').glob('*.mem'))
    manifest=ref.read(design/'SOURCE_MANIFEST.json')['files'];frozen={p.relative_to(design).as_posix():ref.sha(p) for p in sources[:-1]+list((design/'model/experiments/conv4_4').glob('*.mem'))+list((design/'model/export').glob('*.mem'))};assert all(manifest[k]['sha256']==v for k,v in frozen.items()),'E frozen manifest mismatch'
    pins={str(p):ref.sha(p) for p in inputs};ref.save(run/'SOURCE_SHA256.json',pins)
    result={'status':'PREPARED','run_directory':str(run),'source_cases':len(cases),'frozen_manifest_sha256':ref.sha(design/'SOURCE_MANIFEST.json'),'frozen_design_inputs':frozen,'RTL':'NOT_RUN','hardware':'NOT_RUN','limitations':['Abstract source-Y pixel response latency 2..4 clocks, not actual DDR functional/timing verification.','Ordinary empty reentry is separate from full ordinary CNN numerical regression.']}
    if args.run:
        env=dict(os.environ);env['MGLS_LICENSE_FILE']=env['LM_LICENSE_FILE']='E:/model/win64/LICENSE.TXT'
        with(run/'SIM.log').open('w',encoding='utf-8')as log:proc=subprocess.run(['E:/model/win64/vsim.exe','-modelsimini',(run/'modelsim.ini').as_posix(),'-batch','-syncio','-do','run.do'],cwd=run,env=env,stdout=log,stderr=subprocess.STDOUT)
        log=(run/'SIM.log').read_text(encoding='utf-8',errors='replace');unchanged=all(ref.sha(Path(p))==h for p,h in pins.items());ok=proc.returncode==0 and 'BINARY_FULLPIPELINE_GOLDEN_PASS' in log and not re.search(r'\*\*\s+(Error|Fatal):',log) and unchanged
        result.update(status='PASS' if ok else 'FAIL',RTL='PASS' if ok else 'FAIL',returncode=proc.returncode,sources_unchanged=unchanged,frames_passed=log.count('BINARY_FULLPIPELINE_FRAME_PASS'),cancels_passed=log.count('BINARY_FULLPIPELINE_CANCEL_PASS'),ordinary_empty_passed='BINARY_FULLPIPELINE_ORDINARY_EMPTY_PASS'in log,log_sha256=ref.sha(run/'SIM.log'))
    ref.save(run/'RESULTS.json',result);print(json.dumps(result,indent=2));return 1 if result['status']=='FAIL'else 0
if __name__=='__main__':raise SystemExit(main())
