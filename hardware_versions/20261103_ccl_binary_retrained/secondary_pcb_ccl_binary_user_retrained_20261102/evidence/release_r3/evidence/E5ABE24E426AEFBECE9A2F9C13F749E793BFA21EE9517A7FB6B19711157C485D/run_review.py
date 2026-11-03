"""Run helper fault injection only. Never starts TD or changes frozen sources."""
from pathlib import Path
import hashlib,json,re,subprocess,sys
from datetime import datetime,timezone
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def require(ok,message):
    if not ok:raise RuntimeError(message)
source=[ROOT/'04_pin/apply_reset_exceptions.tcl',ROOT/'04_pin/apply_cdc_exceptions.tcl',HERE/'calibrated_lut5a_override.tcl',HERE/'test_override.tcl',Path(__file__)]
before={str(p):sha(p) for p in source}
require(before[str(HERE/'calibrated_lut5a_override.tcl')]=='31794B9B5E5E90BD33AA5A07E85B9BF6396342CD7B70D531500BFD3CC0FFFDF4','Overlay differs from parent freeze')
r=subprocess.run(['D:/conda/Library/bin/tclsh.exe',str(HERE/'test_override.tcl')],capture_output=True,text=True)
log=HERE/'FAULT_INJECTION.log';log.write_text(r.stdout+r.stderr,encoding='utf-8')
rows=re.findall(r'^TEST_PASS (\S+) expected=(PASS|REJECT)',r.stdout,re.M)
require(r.returncode==0 and len(rows)==21 and 'TEST_FAIL' not in r.stdout,'Fault injection failed; preserve log')
require(before=={str(p):sha(p) for p in source},'Source changed during selftest')
value={'status':'PASS_NARROW_HELPER_REVIEW_AND_FAULT_INJECTION','created_utc':datetime.now(timezone.utc).isoformat(),'source_sha256':before,'overlay_sha256':before[str(HERE/'calibrated_lut5a_override.tcl')],'tests':{'passed':21,'failed':0,'positive_cases':[name for name,state in rows if state=='PASS'],'negative_cases':[name for name,state in rows if state=='REJECT'],'log_path':str(log),'log_sha256':sha(log),'execution':'Actual frozen helper procedures + overlay; mocked read-only TD object API'},'actual_td_proof':'NOT_RUN_BY_THIS_AGENT','rtl_or_model_modified':False,'constraints_or_database_modified':False,'runtime_evidence_requirements':{'logical_first':'u_store/cal_sync[0]','first_data_select':'REGA_SD=LUT5A','first_data_role':'SELECTED_LUT_OUTPUT_OBSERVATION_ONLY','first_data_proof':'CALIBRATED_DECODE_PROVEN CAL_EN=0 S_DONE=01111','five_state_input_truth':'00000000000000010000000000000000 for sorted state_cnt[0..4]','physical_modes':['TYPE=AL_PHY_LSLICE','REF_NAME=PH1P_PHY_LSLICE','LATCHMODE=DFF','CLKMUX=SIG','OQAMUX=QA','SSRMUX=0','CEAMUX=1','REGA_REGSET_ASYNC=RESET','REGA_SD=LUT5A','LUTMODE=DLUT5','OFA_SD=LUT5A'],'second_stage':'unchanged frozen IM-only proof, same clk/reset and Dnet == first Qnet','mailbox_timing_endpoint':'unchanged get_regs cal_sync[0], never OFA or IMA','full_phase_inventory_and_numeric_budgets':'unchanged existing CDC gate requirements'},'inheritance_limitations':['Only helper-Tcl change permits inherited synthesis and place checkpoint. RTL/model/active synth configuration must match r2 exactly.','Preserve original synthesis logs, source snapshots, checkpoint and error logs as inherited artifacts; do not create fresh synthesis marker or rewrite timestamps.','New physical proofs/SDC, actual route, two-corner timing, DRC, read-only reimport and final current gate are still required.','If CCL ROI x1.2 is implemented, it changes the functional input contract and cannot be certified by this unchanged RTL inherited netlist.'],'hardware_status':'NOT_RUN'}
(HERE/'REVIEW.json').write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print(json.dumps({'status':value['status'],'overlay_sha256':value['overlay_sha256'],'report':str(HERE/'REVIEW.json'),'report_sha256':sha(HERE/'REVIEW.json'),'tests':21},indent=2))
