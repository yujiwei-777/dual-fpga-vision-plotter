"""Current frozen reader/mailbox and source-derived shared routing regression.

Behavioral app interface only. No vendor DDR, analog timing or physical CDC proof.
Large simulation files are kept on E:; production files remain read-only.
"""
from pathlib import Path
from datetime import datetime, timezone
import hashlib,json,os,re,subprocess

BASE=Path(__file__).resolve().parent
DESIGN=Path('E:/codex_pcb_pose7_20261102_r4')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest().upper()
manifest=DESIGN/'SOURCE_MANIFEST.json'
frozen=json.loads(manifest.read_text(encoding='utf-8'))['files']
assert all(sha(DESIGN/name)==row['sha256'] for name,row in frozen.items())
run=BASE/('run_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
run.mkdir()
top=DESIGN/'01_rtl/secondary_top.v'
t=top.read_text(encoding='utf-8')
a=t.index('    reg copy_pixel_pending;')
b=t.index('    wire cfg_we,cfg_begin',a)
fragment=t[a:b]
# The original top declares this wire locally; the probe exposes the same
# source as a controlled input. Only its duplicate declaration is removed.
fragment=fragment.replace('    wire color_word_active,shared_word_req;','    wire shared_word_req;')
probe='''module pose7_read_route_probe(
 input wire clk125,rst125_n,vision_start,vision_cancel,vision_done,vision_job_cancel,
 input wire [1:0] vision_purpose,
 input wire normal_busy,copy_busy,copy_image_lock,pcb_frame_lock,key4_copy_reset,
 input wire copy_reader_request,copy_reader_invalidate,normal_reader_request,normal_reader_invalidate,
 input wire [10:0] copy_pixel_x,normal_pixel_x,
 input wire [9:0] copy_pixel_y,normal_pixel_y,
 input wire color_word_active,normal_rd_req,
 input wire [20:0] normal_rd_addr,
 output wire v_rd_req,output wire [20:0] v_rd_addr,
 input wire v_rd_ready,v_rd_valid,input wire [127:0] v_rd_data,
 output wire pixel_ready,pixel_valid,output wire [23:0] pixel_rgb,output wire [7:0] pixel_y8,
 output wire owner_copy,frame_locked,pixel_pending,vision_busy
);
 wire copy_task=(vision_purpose==2'd2);
'''+fragment+'''
 assign pixel_ready=shared_reader_ready;
 assign pixel_valid=shared_reader_valid;
 assign pixel_rgb=shared_reader_rgb;
 assign pixel_y8=shared_reader_luma;
 assign owner_copy=copy_reader_select;
 assign frame_locked=shared_frame_lock;
 assign pixel_pending=copy_pixel_pending;
endmodule
'''
(run/'top_read_route_probe.sv').write_text(probe,encoding='utf-8')
hxa=DESIGN/'shared/rtl/hxa_secondary_link.v'
h=hxa.read_text(encoding='utf-8')
def statement(prefix):
    at=h.index(prefix);return h[at:h.index(';',at)+1]
aa=h.index('    always @(posedge clk or negedge rst_n)begin\n      if(!rst_n)vision_read_outstanding')
bb=h.index('    wire crc_read_request=',aa)
routing='''module pose7_hxa_read_route_probe(
 input wire clk,rst_n,vision_active,v_drain_lock,scanning,scan_outstanding,crc_read_request,
 input wire [17:0] scan_word,
 input wire v_rd_req,input wire [20:0] v_rd_byte_addr,
 output wire v_rd_ready,v_rd_valid,output wire [127:0] v_rd_data,
 output wire rd_req,output wire [20:0] rd_byte_addr,
 input wire rd_ready,rd_valid,input wire [127:0] rd_data,
 output wire admission_safe,vision_pending
);
 localparam PRESERVE_VISION_DRAIN=1;
 reg vision_read_outstanding;
'''+statement('    wire vision_read_owner=')+'\n'+statement('    wire drain_admission_safe=')+'\n'+h[aa:bb]+'\n'+'\n'.join(statement(p) for p in ['    assign rd_req=','    assign rd_byte_addr=','    assign v_rd_ready=','    assign v_rd_valid=','    assign v_rd_data='])+'''
 assign admission_safe=drain_admission_safe;
 assign vision_pending=vision_read_outstanding;
endmodule
'''
(run/'hxa_read_route_probe.sv').write_text(routing,encoding='utf-8')
sources=[DESIGN/'01_rtl/vision_pixel_reader.v',DESIGN/'01_rtl/hxa_ddr_store.v',
         run/'top_read_route_probe.sv',run/'hxa_read_route_probe.sv',BASE/'tb_reader.sv']
inputs=[top,hxa,*sources,Path(__file__),manifest]
pins={str(p):sha(p) for p in inputs}
(run/'SOURCE_SHA256.json').write_text(json.dumps(pins,indent=2)+'\n')
do=['onerror {quit -code 2}','onbreak {quit -code 3}','vlib simlib',
    'vlog -sv -lint -work simlib '+' '.join('"'+p.as_posix()+'"' for p in sources),
    'vsim -voptargs=+acc simlib.tb_pose7_real_reader','run -all','quit -code 0','']
(run/'run.do').write_text('\n'.join(do),encoding='ascii')
env=dict(os.environ);env.update(LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT',MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT')
with (run/'SIM.log').open('w') as log:
    cp=subprocess.run(['E:/model/win64/vsim.exe','-batch','-syncio','-do','run.do'],cwd=run,env=env,stdout=log,stderr=subprocess.STDOUT)
log=(run/'SIM.log').read_text(errors='replace')
passed=cp.returncode==0 and 'POSE7_REAL_READER_PASS' in log and not re.search(r'\*\*\s+(Error|Fatal):',log)
result={'status':'PASS' if passed else 'FAIL','design':str(DESIGN),'run_directory':str(run),
        'source_manifest_sha256':sha(manifest),'returncode':cp.returncode,
        'sources_unchanged':all(sha(Path(p))==v for p,v in pins.items()),
        'frozen_sources_unchanged':all(sha(DESIGN/name)==row['sha256'] for name,row in frozen.items()),
        'scope':'Actual vision_pixel_reader+hxa_ddr_store; exact source-extracted top shared owner/request/data mux and HXA read routing/outstanding logic; controlled owner/CRC input state.',
        'coverage_records':re.findall(r'POSE7_REAL_READER_CASE_PASS[^\r\n]*',log),
        'summary':re.findall(r'POSE7_REAL_READER_PASS[^\r\n]*',log),
        'limitations':['Behavioral app ready/data model, not vendor controller/PHY, no physical DDR latency or hardware CDC proof.',
                       'Top and HXA routing slices are source extracted; this is not full secondary_top/HXA state machine elaboration.',
                       'Normal/doc/PCB ownership inputs and CRC scanner state are controlled; admission protocol has separate packet/control regressions.',
                       'No complete model inference in this test; r4 fullpipeline separately checks values with abstract pixel reader.'],
        'hardware':'NOT_RUN'}
if not(result['sources_unchanged'] and result['frozen_sources_unchanged']):result['status']='FAIL_SOURCE_DRIFT'
(run/'RESULTS.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
raise SystemExit(result['status']!='PASS')
