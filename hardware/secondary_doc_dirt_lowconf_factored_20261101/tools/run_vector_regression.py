from pathlib import Path
import os,json,hashlib,re,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'secondary_pcb_a4_newline_remote_cnn_fc8_20261027'
OUT=ROOT/'02_sim/vector_reset_regression'
OUT.mkdir(exist_ok=True)
SIM=Path('E:/model/win64')
env=os.environ.copy();env.update(MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'),LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def run(name,args):
    p=subprocess.run([x.as_posix()if isinstance(x,Path)else str(x)for x in args],cwd=ROOT,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
    (OUT/(name+'.log')).write_text(p.stdout)
    if p.returncode or re.search(r'\*\*\s+(?:Error|Fatal):',p.stdout):raise SystemExit(name+' failed:\n'+p.stdout[-3000:])
    return p.stdout
source=[ROOT/x for x in (ROOT/'lint_full.f').read_text().splitlines() if x.strip()]
test=[ROOT/'02_sim'/x for x in ['tb_grbl_vector_completion.sv','tb_doc_grbl_plotter_last_ok.sv','tb_grbl_key2_last_ok_ctrl.sv','tb_grbl_reporter_key1_vector.sv','tb_grbl_completion_priority.sv']]
test += [ROOT/'shared/tests/tb_grbl_key1_job_guard.sv',ROOT/'shared/tests/tb_hxa_job_cancel_classification.sv',ROOT/'02_sim/testmodels/ph1p_logic_eram_stub.sv']
pcb=(ROOT/'02_sim/remote_model_nontarget_invariants_fc8_20261027/tb_pcb_fullboard_binary_conv4_4.sv').read_text().replace('D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_a4_newline_remote_cnn_20261027',ROOT.as_posix())
pcbbench=OUT/'tb_pcb_fullboard_binary_conv4_4.sv';pcbbench.write_text(pcb);test.append(pcbbench)
inputs=set(source+test)
for folder in [ROOT/'model',ROOT/'01_rtl/model',ROOT/'04_pin']:
    inputs.update(p for p in folder.rglob('*')if p.is_file())
inputs.update((ROOT/'02_sim/fullboard_binary_conv4_4_vectors').glob('*.mem'))
before={str(p.resolve()):sha(p)for p in inputs}
run('vlib',[SIM/'vlib.exe',OUT/'work'])
run('lint',[SIM/'vlog.exe','-sv','-lint','-work',OUT/'work',*source,*test])
tests={}
for top,marker in [
 ('tb_grbl_vector_completion','PASS VECTOR_COMPLETION_ALL'),
 ('tb_doc_grbl_plotter_last_ok','PASS ALL DOC PLOTTER REGRESSIONS'),
 ('tb_grbl_key2_last_ok_ctrl','PASS KEY2 repeated presses'),
 ('tb_grbl_reporter_key1_vector','PASS KEY1 single-line vector'),
 ('tb_grbl_completion_priority','PASS KEY4 priority'),
 ('tb_grbl_key1_job_guard','PASS KEY1 job guard:'),
 ('tb_hxa_job_cancel_classification','PASS: lease expiry'),
 ('tb_pcb_fullboard_binary_conv4_4','BINARY_C4_4_GOLDEN_PASS'),
]:
    out=run(top,[SIM/'vsim.exe','-c','-quiet','-lib',OUT/'work',top,'-do','run -all; quit -f'])
    if marker not in out:raise SystemExit(top+' missing pass marker')
    tests[top]={'status':'PASS','checks':[x.strip('# ')for x in out.splitlines()if 'PASS' in x]}
    print(top+': PASS',flush=True)
out=run('integer_reference',[sys.executable,ROOT/'tools/check_vector_reference.py'])
tests['integer_reference']={'status':'PASS','checks':[out.strip()]}
after={str(p.resolve()):sha(p)for p in inputs}
if after!=before:raise SystemExit('inputs changed while simulations ran')
protected=['01_rtl/cnn_core.v','01_rtl/vision_pipeline.v','01_rtl/vision_workspace.v','01_rtl/pcb_fullboard_spatial96.v','01_rtl/pcb_tinycnn_core.v','01_rtl/pcb_defect_cluster.v','01_rtl/doc_image_frontend.v','01_rtl/doc_stroke_planner.v','01_rtl/doc_machine_map.v','01_rtl/doc_grbl_map.v','01_rtl/doc_path_distance.v','01_rtl/hxa_ddr_store.v','01_rtl/secondary_ddr_wrapper.v','shared/rtl/hxa_secondary_link.v','shared/rtl/hxa_packet_codec.v','shared/rtl/hxa_packet_rx_fifo4.v']
invariants={p:sha(ROOT/p)==sha(BASE/p)for p in protected}
for model in (ROOT/'model').rglob('*'):
    if model.is_file():invariants[str(model.relative_to(ROOT))]=sha(model)==sha(BASE/model.relative_to(ROOT))
assert all(invariants.values()),'protected source/model mismatch'
baselinebit=BASE/'artifacts/dual_fpga_secondary_20261027_pcb_a4_return_x10_newline_remote_cnn_fc8_diagnostic.bit'
assert sha(baselinebit)=='D8672CA4141E1C4BAF8D861EC9E44BCB44E9136011353EA32A91421A9BFC9DC5'
summary={'status':'PASS','baseline_bit_sha256':sha(baselinebit),'input_hashes':before,'tests':tests,'protected_source_model_invariants':invariants,'hardware_status':'NOT_RUN','ordinary_cnn_inference':'unchanged source/FC8/model hash audit; no new accuracy claim','formal_bit':'NOT_GENERATED; routed release gates pending'}
(OUT/'RESULTS.json').write_text(json.dumps(summary,indent=2))
print('PASS vector/reset/last-ok regression + protected-source/model invariant audit')
