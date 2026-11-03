"""Prepare source-derived top control and real shared-CCL regressions; does not run simulators."""
from pathlib import Path
import hashlib,json,re
ROOT=Path(__file__).resolve().parent.parent
OUT=ROOT/'reports/pose7/control_checks'
OUT.mkdir(parents=True,exist_ok=True)
SOURCE=ROOT/'01_rtl/secondary_top.v'
s=SOURCE.read_text(encoding='utf-8')
def statement(begin):
    a=s.index(begin);return s[a:s.index(';',a)+1]
def balanced_arg(begin):
    a=s.index(begin)+len(begin);level=1;b=a
    while level:
        if s[b]=='(':level+=1
        elif s[b]==')':level-=1
        b+=1
    return s[a:b-1]
owner_a=s.index('    reg copy_reader_select;')
owner_b=s.index('    wire [1:0] vision_purpose_locked',owner_a)
owner=s[owner_a:owner_b]
pending_a=s.index('    always @(posedge clk125 or negedge rst125_n)begin\n        if(!rst125_n)copy_pixel_pending')
pending_b=s.index('    vision_pixel_reader u_shared_reader',pending_a)
pending=s[pending_a:pending_b]
clear_m=re.search(r'if\((key4_press\|\|key4_reset_active\|\|vision_job_cancel[^\n]+?)\)begin report_pending<=0',s)
assert clear_m
parts=[statement('    wire shared_frame_lock='),statement('    wire copy_read_fenced='),statement('    wire report_network_protected=')]
probe="""module pose7_top_control_probe(
 input wire clk125,rst125_n,vision_start,vision_cancel,vision_done,vision_job_cancel,
 input wire [1:0] vision_purpose,
 input wire copy_busy,copy_image_lock,pcb_frame_lock,
 input wire copy_reader_request,shared_reader_ready,shared_reader_valid,key4_copy_reset,
 input wire report_pending,key2_report_pending,report_busy,key1_job_protected,key2_local_active,
 input wire key4_press,key4_reset_active,key4_report_reset,
 output wire owner_copy,frame_locked,pixel_pending,reader_reset_n,report_abort,
 output wire report_clear_pending,report_stop,copy_cancel,read_allowed,
 output wire [1:0] locked_purpose
);
 wire copy_task=(vision_purpose==2'd2);
 reg copy_pixel_pending;
"""+'\n'.join(parts)+'\n'+owner+pending+"""
 assign owner_copy=copy_reader_select;
 assign locked_purpose=vision_purpose_q;
 assign frame_locked=shared_frame_lock;
 assign pixel_pending=copy_pixel_pending;
 assign read_allowed=copy_read_fenced;
"""
probe+=' assign reader_reset_n='+balanced_arg('vision_pixel_reader u_shared_reader(.clk(clk125),.rst_n(')+';\n'
probe+=' assign report_abort='+balanced_arg('.I_clear(cfg_apply||report_clear),.I_abort(')+';\n'
probe+=' assign report_stop=key4_report_reset;\n'
probe+=' assign report_clear_pending='+clear_m.group(1)+';\n'
probe+=' assign copy_cancel=vision_job_cancel;\nendmodule\n'
# Pin expressions are assertions against the actual source, not copied assumptions.
assert '.cancel(vision_job_cancel),.reset_job(key4_copy_reset)' in s
assert '.v_drain_lock(shared_frame_lock)' in s
assert '.frame_lock(copy_image_lock)' in s
(OUT/'pose7_top_control_probe.v').write_text(probe,encoding='utf-8')
manifest={'scope':'Source-derived secondary_top ownership/cancel predicates and sequential reader owner/pending RTL; not a full-board elaboration or G-code replay proof.','source':str(SOURCE),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'probe_sha256':hashlib.sha256(probe.encode()).hexdigest(),'status':'PREPARED_NOT_RUN'}
(OUT/'PREPARED.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print(json.dumps(manifest,indent=2))

# A second probe extracts the exact raw-reset PCB frame owner introduced to
# break owner -> processing async-reset feedback. The processing reset here
# is an observation only and never drives the raw owner register.
pipeline=ROOT/'01_rtl/vision_pipeline.v'
v=pipeline.read_text(encoding='utf-8')
a=v.index('    always @(posedge clk or negedge rst_n)begin\n        if(!rst_n)pcb_frame_owner_q')
b=v.index('    wire [23:0] reader_rgb;',a)
pcb_owner=v[a:b]
owner_probe="""module pose7_frame_owner_probe(
 input wire clk,rst_n,start,auto_busy,cancel,teach_good,auto_done,auto_cancel_seen,
 input wire [6:0] state,input wire [1:0] purpose,purpose_q,
 input wire pcb_ccl_pending,reader_ready,reader_request,
 output wire pcb_frame_lock,processing_rst_n
);
 localparam PCB_ENABLE=1,PCB_GOODONLY_AUTO=1;
 localparam [6:0] IDLE=0,FINISH=33,PCB_AUTO_WAIT=81,PCB_CCL_DRAIN=82;
 reg pcb_frame_owner_q;
 assign pcb_frame_lock=auto_busy||pcb_frame_owner_q;
 assign processing_rst_n=rst_n && !(cancel && !pcb_frame_lock);
"""+pcb_owner+'endmodule\n'
(OUT/'pose7_frame_owner_probe.v').write_text(owner_probe,encoding='utf-8')
