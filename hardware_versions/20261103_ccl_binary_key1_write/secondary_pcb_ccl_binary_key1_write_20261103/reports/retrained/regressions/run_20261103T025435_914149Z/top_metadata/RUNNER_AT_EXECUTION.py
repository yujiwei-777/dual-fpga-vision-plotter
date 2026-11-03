"""Fresh preserved-function regressions on this independent retrained design.

Historical benches are test inputs. Production RTL is compiled from --design.
Every suite uses a new isolated library and records current source/log hashes.
Behavioral DDR/mailbox tests do not constitute physical DDR or CDC signoff.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse, ast, hashlib, json, os, re, shutil, subprocess, sys, zlib
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent
OLD = BASE / 'secondary_pcb_pose7_goodonly_ccl_20261102'
DOC = BASE / 'secondary_doc_dirt_lowconf_factored_20261101'
SIM = Path('E:/model/win64')

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p): return Path(p).read_text(encoding='utf-8-sig', errors='replace')
def dump(p,v): Path(p).write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')

class Run:
    def __init__(self,design,out):
        self.design=design;self.out=out;out.mkdir(parents=True,exist_ok=False)
        self.env=dict(os.environ);self.env.update(LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'),MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
        self.rows=[];self.pins={};self.scope=[];self.limits=[]
    def pin(self,*paths):
        for p in paths:
            p=Path(p).resolve();assert p.is_file(),p
            assert 'work' not in [x.lower() for x in p.parts],p
            self.pins[str(p)]=sha(p)
    def copy(self,origin,name=None):
        self.pin(origin);p=self.out/(name or Path(origin).name);shutil.copyfile(origin,p);return p
    def cmd(self,label,argv,marker=None,cwd=None,timeout=600):
        log=self.out/(label+'.log');cmd=list(map(str,argv))
        with log.open('w',encoding='utf-8') as f:
            cp=subprocess.run(cmd,cwd=cwd or self.out,env=self.env,stdout=f,stderr=subprocess.STDOUT,timeout=timeout)
        text=read(log);ok=cp.returncode==0 and not re.search(r'\*\*\s+(?:Error|Fatal):',text) and (marker is None or marker in text)
        self.rows.append(dict(label=label,command=cmd,cwd=str(cwd or self.out),returncode=cp.returncode,status='PASS' if ok else 'FAIL',log=str(log),log_sha256=sha(log),warnings=re.findall(r'\*\* Warning:[^\n]*',text)))
        dump(self.out/'COMMANDS.json',self.rows)
        if not ok:raise RuntimeError(label+' failed: '+str(log)+'\n'+text[-2200:])
        print('PASS '+self.out.name+'/'+label,flush=True);return text
    def sim(self,label,sources,top,marker,novopt=False):
        self.pin(*sources);lib=self.out/(label+'_lib')
        self.cmd(label+'_vlib',[SIM/'vlib.exe',lib])
        self.cmd(label+'_lint',[SIM/'vlog.exe','-sv','-lint','-work',lib,*sources])
        command=[SIM/'vsim.exe','-batch','-syncio','-quiet']
        if novopt:command+=['-novopt','-suppress','12110']
        return self.cmd(label+'_simulation',command+['-lib',lib.name,top,'-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],marker)
    def finish(self,error=None):
        drift=[p for p,h in self.pins.items() if not Path(p).is_file() or sha(p)!=h]
        result=dict(status='PASS' if error is None and not drift else 'FAIL',generated_utc=datetime.now(timezone.utc).isoformat(),design=str(self.design),output=str(self.out),source_hashes=self.pins,commands=self.rows,scope=self.scope,limitations=self.limits,source_drift=drift,error=error,hardware='NOT_RUN',physical_DDR_CDC='NOT_RUN_BY_THIS_BEHAVIORAL_SUITE')
        dump(self.out/'RESULTS.json',result);return result

def plotter(r):
    bench=r.copy(OLD/'reports/pose7/tb_pose7_plotter.sv')
    files=[r.design/'01_rtl'/x for x in ('grbl_line_formatter.v','grbl_response_parser.v','grbl_shared_transport_candidate.v')]
    text=r.sim('transport',files+[bench],'tb_pose7_plotter','POSE7_PLOTTER_REGRESSION_PASS')
    r.scope.append(dict(test='actual shared report/document transport',cases=re.findall(r'PLOTTER_CASE_PASS[^\r\n]*',text)))
    r.limits+=['Producer claims are controlled; HXA and physical external machine require separate tests.','GRBL ok acknowledges command acceptance, not mechanical standstill.']

def hxa(r):
    folder=OLD/'reports/pose7/hxa_tests'
    benches=[r.copy(folder/x) for x in ('ph1p_logic_eram_stub.sv','tb_pose7_fifo4.sv','tb_pose7_hxa_crc_network.sv')]
    (r.out/'pose7_hxa_constants.svh').write_text("localparam [31:0] ZERO_FRAME_CRC=32'h%08x;\n"%(zlib.crc32(bytes(1843200))&0xffffffff))
    files=[r.design/'shared/rtl'/x for x in ('hxa_packet_codec.v','hxa_packet_rx_fifo4.v','hxa_secondary_link.v')]+benches
    r.pin(*files);lib=r.out/'hxa_lib';r.cmd('vlib',[SIM/'vlib.exe',lib]);r.cmd('lint',[SIM/'vlog.exe','-sv','-lint','-work',lib,'+incdir+'+r.out.as_posix(),*files])
    for top,marker in [('tb_pose7_fifo4','POSE7_FIFO4_PASS:'),('tb_pose7_hxa_crc_network','POSE7_HXA_CRC_NETWORK_PASS')]:
        text=r.cmd(top,[SIM/'vsim.exe','-batch','-syncio','-quiet','-lib',lib.name,top,'-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],marker)
        r.scope.append(dict(test=top,records=[x.strip('# ') for x in text.splitlines() if '_PASS' in x or 'BASELINE_LIMITATION' in x]))
    r.limits+=['Frame DATA staging count is deposited; this does not validate all1280 fragment DMA writes. Actual CRC scans115200 DDR words.','Explicit Type11 reason80 checks session but baseline does not compare task/frame ID.','Behavioral DDR read model is not vendor PHY or physical CDC signoff.']

def document(r):
    source=DOC/'reports/dirt_qualification';shutil.copytree(source/'fixtures',r.out/'fixtures')
    for p in (source/'fixtures').rglob('*'):
        if p.is_file():r.pin(p)
    front=r.copy(source/'source/tb_frontend.sv');integrated=r.copy(source/'source/tb_capture_integrated.sv')
    eram=r.copy(OLD/'reports/pose7/hxa_tests/ph1p_logic_eram_stub.sv')
    names=['doc_image_frontend.v','doc_stroke_planner.v','doc_stroke_bram.v','doc_machine_map.v','doc_grbl_plotter.v','doc_grbl_map.v','doc_grbl_streamer.v','doc_grbl_response_parser.v','grbl_line_formatter.v']
    files=[r.design/'01_rtl'/x for x in names];r.pin(*files)
    lib=r.out/'front_lib';r.cmd('frontend_vlib',[SIM/'vlib.exe',lib]);r.cmd('frontend_lint',[SIM/'vlog.exe','-sv','-lint','-work',lib,files[0],front])
    for fixture in sorted((r.out/'fixtures').iterdir()):
        text=r.cmd('frontend_'+fixture.name,[SIM/'vsim.exe','-batch','-syncio','-quiet','-lib',lib.name,'tb_frontend','+IMAGE='+(fixture/'source_y.mem').as_posix(),'+EXPECTED='+(fixture/'expected_binary.mem').as_posix(),'+OUTPUT='+(r.out/(fixture.name+'_binary.mem')).as_posix(),'+CASE='+fixture.name,'-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],'PASS FRONTEND')
        r.scope.append(dict(test='frontend '+fixture.name,records=re.findall(r'PASS FRONTEND[^\r\n]*',text)))
    for case in ['blank2418','ink2358']:
        fixture=r.out/'fixtures'/case;lib=r.out/(case+'_lib');r.cmd(case+'_vlib',[SIM/'vlib.exe',lib]);r.cmd(case+'_lint',[SIM/'vlog.exe','-sv','-lint','-work',lib,'+incdir+'+fixture.as_posix(),*files,eram,integrated])
        text=r.cmd(case+'_simulation',[SIM/'vsim.exe','-batch','-syncio','-quiet','-lib',lib.name,'tb_stroke_split','-do','onerror {quit -code 1}; onbreak {quit -code 2}; cd {'+fixture.as_posix()+'}; run -all; quit -f'],'PASS CAPTURE_INTEGRATED')
        actual=(fixture/'gcode.txt').read_text().splitlines();expected=(fixture/'expected_gcode.txt').read_text().splitlines();assert actual==expected,(case,'G-code changed',len(actual),len(expected))
        r.scope.append(dict(test=case+' frontend/skeleton/paths/coordinates/G-code',gcode_lines=len(actual),actual_gcode_sha256=sha(fixture/'gcode.txt'),records=re.findall(r'PASS CAPTURE_INTEGRATED[^\r\n]*',text)))
    r.limits+=['Archived real-frame fixtures check this current RTL; no new independent handwriting quality or hardware claim.','Integrated fixtures use document-local transport; current shared transport is separately tested.']

def ordinary(r):
    tool=r.design/'tools/run_ordinary_pose7_regression.py';r.pin(tool);output=r.out/'integer27'
    r.cmd('ordinary_integer27',[sys.executable,'-B',tool,'--rtl-root',r.design,'--model',r.design/'model/export','--output',output],'PASS RTL + integer golden: 27 cases',timeout=1800)
    result=json.loads(read(output/'RESULTS.json'));assert result['status']=='PASS' and result['simulation_cases_passed']==27
    for p,h in result['input_hashes'].items():assert sha(p)==h;r.pin(p)
    r.scope.append(dict(test='ordinary CNN input/conv1/conv2/logits/class/confidence',cases=27,results=str(output/'RESULTS.json')));r.limits+=result['limitations']

def publication(r):
    bench=r.copy(OLD/'reports/pose7/tb_cnn_publication_integration.sv')
    leaves=['vision_color_stats','edge_roi_ccl_shared_pcb_candidate','cnn_core','pcb_ccl_binary_core','vision_shared_mac','vision_workspace_goodonly'];declarations=[]
    for name in leaves:
        p=r.design/'01_rtl'/(name+'.v');r.pin(p);body=re.sub(r'/\*.*?\*/|//[^\n]*','',read(p),flags=re.S);m=re.search(r'\bmodule\s+'+name+r'\b',body);assert m,name
        declarations.append(body[m.start():body.index(';',m.end())+1]+'\nendmodule\n')
    stub=r.out/'controlled_leaf_interfaces.sv';stub.write_text('\n'.join(declarations))
    files=[r.design/'01_rtl'/x for x in ('vision_pipeline.v','cnn_result_stabilizer.v')]
    text=r.sim('publication',files+[stub,bench],'tb_cnn_publication_integration','PASS CNN_PUBLICATION_INTEGRATION',novopt=True)
    r.scope.append(dict(test='current pipeline+packed stabilizer controlled-leaf publication',records=re.findall(r'PASS CNN_PUBLICATION_INTEGRATION[^\r\n]*',text)))
    r.limits+=['CCL/CNN/PCB leaves are controlled; tests publication/state/bank lifetime, not real localization, arithmetic or physical DDR.']

def controls(r):
    source=r.design/'01_rtl/secondary_top.v';r.pin(source);s=read(source)
    def statement(begin):a=s.index(begin);return s[a:s.index(';',a)+1]
    def arg(begin):
        a=s.index(begin)+len(begin);n=1;b=a
        while n:n+=(s[b]=='(')-(s[b]==')');b+=1
        return s[a:b-1]
    a=s.index('    reg copy_reader_select;');b=s.index('    wire [1:0] vision_purpose_locked',a);owner=s[a:b]
    a=s.index('    always @(posedge clk125 or negedge rst125_n)begin\n        if(!rst125_n)copy_pixel_pending');b=s.index('    vision_pixel_reader u_shared_reader',a);pending=s[a:b]
    clear=re.search(r'if\((key4_press\|\|key4_reset_active\|\|vision_job_cancel[^\n]+?)\)begin report_pending<=0',s);assert clear
    template=OLD/'reports/pose7/control_checks/pose7_top_control_probe.v';r.pin(template);header=read(template).split(' wire copy_task=')[0]
    probe=header+" wire copy_task=(vision_purpose==2'd2);\n reg copy_pixel_pending;\n"+'\n'.join(statement(x) for x in ['    wire shared_frame_lock=','    wire copy_read_fenced=','    wire report_network_protected='])+'\n'+owner+pending
    probe+='\nassign owner_copy=copy_reader_select;assign locked_purpose=vision_purpose_q;assign frame_locked=shared_frame_lock;assign pixel_pending=copy_pixel_pending;assign read_allowed=copy_read_fenced;\n'
    probe+='assign reader_reset_n='+arg('vision_pixel_reader u_shared_reader(.clk(clk125),.rst_n(')+';\nassign report_abort='+arg('.I_clear(cfg_apply||report_clear),.I_abort(')+';\nassign report_stop=key4_report_reset;\nassign report_clear_pending='+clear[1]+';\nassign copy_cancel=vision_job_cancel;\nendmodule\n'
    p=r.out/'current_top_control_probe.sv';p.write_text(probe);bench=r.copy(OLD/'reports/pose7/control_checks/tb_pose7_top_control.v')
    text=r.sim('top_control',[p,bench],'tb_pose7_top_control','POSE7_TOP_CONTROL_PASS');r.scope.append(dict(test='source-extracted current top ownership/cancel/accepted task protection',records=re.findall(r'POSE7_TOP_CONTROL_PASS[^\r\n]*',text)))
    bench=r.copy(BASE/'secondary_pcb_stability_20261026/shared/tests/tb_grbl_key1_job_guard.sv');text=r.sim('key1',[source,bench],'tb_grbl_key1_job_guard','PASS KEY1 job guard:');r.scope.append(dict(test='current real local KEY1 guard',records=re.findall(r'PASS KEY1[^\r\n]*',text)))
    r.limits+=['Source-extracted top predicates are not full top elaboration; packet cancellation and shared transport use separate suites.']

def reader(r):
    source=OLD/'reports/pose7/reader_regression_r4/run_reader.py';r.pin(source);text=read(source)
    start=text.index("top=DESIGN/'01_rtl/secondary_top.v'");end=text.index("sources=[DESIGN/'01_rtl/vision_pixel_reader.v'")
    # Reuse only deterministic source-extraction statements; never old build/results.
    exec(compile(text[start:end],str(source),'exec'),{'DESIGN':r.design,'run':r.out})
    r.pin(r.design/'01_rtl/secondary_top.v',r.design/'shared/rtl/hxa_secondary_link.v')
    bench=r.copy(OLD/'reports/pose7/reader_regression_r4/tb_reader.sv')
    files=[r.design/'01_rtl/vision_pixel_reader.v',r.design/'01_rtl/hxa_ddr_store.v',r.out/'top_read_route_probe.sv',r.out/'hxa_read_route_probe.sv',bench]
    text=r.sim('reader_mailbox',files,'tb_pose7_real_reader','POSE7_REAL_READER_PASS')
    r.scope.append(dict(test='actual current pixel reader+dual-clock mailbox+source-extracted top/HXA routes',records=re.findall(r'POSE7_REAL_READER_(?:CASE_PASS|PASS)[^\r\n]*',text)))
    r.limits+=['Independent125/DDR clocks plus behavioral app interface verify logical mailbox ordering, not metastability, vendor PHY calibration, physical latency or static CDC signoff.']

def key3(r):
    tool=DOC/'tools/run_key3_reset_unit.py';r.pin(tool);tree=ast.parse(read(tool));value=None
    for n in ast.walk(tree):
        if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='BENCH' for t in n.targets):value=ast.literal_eval(n.value);break
    assert value;bench=r.out/'tb_key3_reset_unit.sv';bench.write_text(value)
    files=[r.design/'01_rtl/secondary_top.v',r.design/'main/user_source/hdl_source/reset_sync.v',bench]
    text=r.sim('key3_supervisor',files,'tb_key3_reset_unit','KEY3_RESET_UNIT_PASS cases=5')
    r.scope.append(dict(test='actual KEY3 whole-board supervisor and dual-clock reset_sync',records=re.findall(r'(?:KEY3_CASE_RESULT|KEY3_PRODUCTION_THRESHOLD|RESET_SYNC_CASE_RESULT|KEY3_RESET_UNIT_PASS)[^\r\n]*',text)))
    r.limits+=['Does not claim external GRBL/ESP32 is reset or mechanically stopped.']

def top_declarations(r):
    rels=['01_rtl/secondary_ddr_wrapper.v','01_rtl/hxa_ddr_store.v','01_rtl/vision_pixel_reader.v','01_rtl/vision_pipeline.v','01_rtl/doc_copy_pipeline_shared_candidate.v','01_rtl/grbl_uart.v','01_rtl/grbl_reporter_shared_candidate.v','01_rtl/grbl_shared_transport_candidate.v','shared/rtl/hxa_secondary_link.v','shared/rtl/hxa_config_store.v','main/user_source/hdl_source/reset_sync.v','main/user_source/hdl_source/ethernet/pll.v','main/user_source/ip_source/PLL/PLL.v','main/user_source/hdl_source/ethernet/uiudp_stack.v','main/user_source/hdl_source/ethernet/rgmii_interface.v']
    dec={}
    for rel in rels:
        path=r.design/rel;r.pin(path);code=re.sub(r'/\*.*?\*/|//[^\n]*','',read(path),flags=re.S)
        for m in re.finditer(r'\bmodule\s+(\w+)\b',code):dec[m[1]]=code[m.start():code.index(';',m.end())+1]
    return dec

def top_metadata(r):
    origin=DOC/'reports/cnn_lowconf_qualification/tb_lowconf_top.sv';r.pin(origin)
    bench=r.out/'tb_lowconf_top.sv';bench_text=read(origin)
    old_no_target='''    check(dut.report_cnn_mode && dut.report_judgement==0 && dut.report_defect_count==0,
          "KEY1 after no target cannot report stale valid object");'''
    new_no_target='''    check(!dut.report_pending && !dut.key1_job_active,
          "KEY1 after no target does not start writing");'''
    old_pcb='''    check(!dut.report_cnn_mode && dut.report_source==4 && dut.report_job==88 && dut.report_judgement==1,
          "PCB completion remains non-CNN report with original judgement");
    retire;'''
    new_pcb='''    check(!dut.report_pending && !dut.key1_job_active && dut.pcb_report_cache_valid &&
          dut.pcb_report_cache_job==88 && dut.pcb_report_cache_judgement==1,
          "PCB completion caches result without starting a report");
    press_key1;
    check(!dut.report_cnn_mode && dut.report_source==0 && dut.report_job==88 && dut.report_judgement==1,
          "PCB-mode KEY1 writes the cached PCB result");
    retire;'''
    assert bench_text.count(old_no_target)==1 and bench_text.count(old_pcb)==1
    bench_text=bench_text.replace(old_no_target,new_no_target).replace(old_pcb,new_pcb)
    bench.write_text(bench_text,encoding='utf-8');r.pin(bench)
    dec=top_declarations(r)
    leafs=['pll','PLL','secondary_ddr_wrapper','reset_sync','hxa_ddr_store','uiudp_stack','vision_pixel_reader','vision_pipeline','hxa_config_store','hxa_secondary_link','grbl_uart_port','grbl_reporter_shared_candidate','grbl_shared_transport_candidate','doc_copy_pipeline_shared_candidate','rgmii_interface']
    stub=r.out/'current_top_metadata_leaves.sv';stub.write_text('\n'.join(dec[x]+'\nendmodule\n' for x in leafs)+'\nmodule PH1P_LOGIC_BUFG(input i,output o);assign o=i;endmodule\n')
    text=r.sim('top_metadata',[stub,r.design/'01_rtl/secondary_top.v',bench],'tb_cnn_named_top','PASS CNN_NAMED_TOP_ALL',novopt=True)
    r.scope.append(dict(test='actual top KEY1 class/center/actual confidence immutable snapshot, pending/active network preservation, history clear',records=re.findall(r'(?:PASS[^\r\n]*|CENTER_CACHE_FULL_TOP_COUNTS[^\r\n]*)',text)))
    r.limits+=['Physical/vision/reporter/transport leaves are controlled metadata interfaces. Actual classifier and shared transport have separate fresh regressions.','Current top and all controlled leaf interfaces are bound to new production hashes; no old top/stub implementation compiled.']

def top_reset(r):
    origin=DOC/'tools/run_key3_top_reset.py';r.pin(origin);tree=ast.parse(read(origin));value=None
    for n in ast.walk(tree):
        if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute) and n.func.attr=='write_text' and n.args:
            try:
                v=ast.literal_eval(n.args[0])
                if isinstance(v,str) and 'module tb_key3_top_reset;' in v:value=v;break
            except ValueError:pass
    assert value
    value=value.replace('dut.u_reporter.u_stream.recovery_required=1','dut.u_plot_transport.R_recovery_required=1')
    bench=r.out/'tb_key3_top_reset.sv';bench.write_text(value)
    dec=top_declarations(r);leafs=['pll','PLL','secondary_ddr_wrapper','hxa_ddr_store','uiudp_stack','vision_pixel_reader','vision_pipeline','hxa_config_store','doc_copy_pipeline_shared_candidate','rgmii_interface']
    bodies={'pll':'assign clk0_out=refclk&&!reset;assign clk1_out=refclk&&!reset;assign lock=!reset;','PLL':'assign clk0_out=refclk&&!reset;assign lock=!reset;','secondary_ddr_wrapper':'assign O_ddr_clk=I_sys_clk;assign O_init_calib_complete=I_sys_rst_n;'}
    stub=r.out/'current_top_reset_leaves.sv';stub.write_text('\n'.join(dec[x]+'\n'+bodies.get(x,'')+'\nendmodule\n' for x in leafs)+'\nmodule PH1P_LOGIC_BUFG(input i,output o);assign o=i;endmodule\n')
    used=[r.design/'01_rtl'/x for x in ['secondary_top.v','grbl_uart.v','grbl_response_parser.v','grbl_shared_transport_candidate.v','grbl_reporter_shared_candidate.v','grbl_line_formatter.v','grbl_vector_font_rom.v']]
    used+=[r.design/'shared/rtl'/x for x in ['hxa_secondary_link.v','hxa_packet_codec.v','hxa_packet_rx_fifo4.v']]
    used+=[r.design/'main/user_source/hdl_source/reset_sync.v',r.copy(OLD/'reports/pose7/hxa_tests/ph1p_logic_eram_stub.sv'),stub,bench]
    text=r.sim('top_reset',used,'tb_key3_top_reset','PASS KEY3_TOP_RESET_ALL',novopt=True)
    r.scope.append(dict(test='actual top/shared reporter+transport/HXA/UART/reset_sync reset fanout',records=re.findall(r'PASS[^\r\n]*',text)))
    r.limits+=['Physical PLL/RGMII/DDR/image/configuration leaves controlled; external mechanical stopping untested.','Old bench recovery deposit explicitly adapted to current shared transport R_recovery_required; no DUT behavior bypassed.']

SUITES=dict(plotter=plotter,hxa=hxa,document=document,ordinary=ordinary,publication=publication,controls=controls,reader=reader,key3=key3,top_metadata=top_metadata,top_reset=top_reset)
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--design',type=Path,default=ROOT);p.add_argument('--suite',choices=['all',*SUITES],default='all');p.add_argument('--output',type=Path);a=p.parse_args()
    design=a.design.resolve();assert design.is_relative_to(BASE) and 'work' not in [x.lower() for x in design.parts]
    out=(a.output or design/'reports/retrained/regressions'/('run_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))).resolve();assert out.is_relative_to(design/'reports/retrained/regressions')
    out.mkdir(parents=True,exist_ok=False);results=[]
    for label,fn in SUITES.items():
        if a.suite not in ('all',label):continue
        r=Run(design,out/label);r.copy(Path(__file__),'RUNNER_AT_EXECUTION.py');r.pins.pop(str(Path(__file__).resolve()))
        r.pin(r.out/'RUNNER_AT_EXECUTION.py')
        try:fn(r);result=r.finish()
        except Exception as e:result=r.finish(str(e))
        results.append(result);dump(out/'RESULTS.json',dict(status='PASS' if all(x['status']=='PASS' for x in results) else 'FAIL',design=str(design),suite_results=results,hardware='NOT_RUN'))
        print(label+' '+result['status'],flush=True)
        if result['error']:print(result['error'],flush=True)
    return 0 if all(x['status']=='PASS' for x in results) else 1
if __name__=='__main__':raise SystemExit(main())
