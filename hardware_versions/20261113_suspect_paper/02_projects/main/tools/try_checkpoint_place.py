"""Try supported placer booleans on the exact current gate checkpoint."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
BUILD=Path('E:/codex_pcb_suspect_center_main_20261113_r3')
RUN=BUILD/'01_rtl/imgq_gain_m/main/td_project_display_noise_v8'
NAME='camera_to_dsi_display_720p60_cnn_multibox'
TD=Path('E:/td/bin/td_commands_prompt.exe')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def put(p,o):p.write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
manifest=json.loads((BUILD/'SOURCE_MANIFEST.json').read_text(encoding='utf-8'))
def check():
    assert all(sha(BUILD/p)==v['sha256'] for p,v in manifest['files'].items())
bound={str(RUN/(NAME+s)):sha(RUN/(NAME+s)) for s in ('.al','_gate.db')}
out=BUILD/'audits/checkpoint_place_trials_r2';out.mkdir()
for label,params in [('unpack_off',{'unpack_repack_flow':'off'}),
        ('logic_level_on',{'logic_level_opt':'on'}),
        ('unpack_off_logic_on',{'unpack_repack_flow':'off','logic_level_opt':'on'})]:
    check();folder=out/label;folder.mkdir()
    script='set run {'+RUN.as_posix()+'}\nset out {'+folder.as_posix()+'}\nset name {'+NAME+'}\n'
    script+='cd $run\nif {[catch {\nimport_device ph1_35p.db -package PH1P35MDG324 -speed 3\nopen_project "$run/$name.al" -noanalyze\nimport_db "$run/${name}_gate.db"\ncommit_param -step place\n'
    for k,v in params.items():script+=f'set_param place {k} {v}\nputs "CHECKPOINT_PARAM {k}=[get_param place {k}]"\n'
    script+='place\nupdate_timing -mode manhattan\nreport_timing_summary -file "$out/place.timing"\nreport_area -io_info -file "$out/place.area"\nexport_db "$out/place.db"\nputs CHECKPOINT_PLACE_PASS\n} reason]} {puts "CHECKPOINT_PLACE_FAIL: $reason"; exit 1}\nexit 0\n'
    tcl=folder/'place.tcl';tcl.write_text(script,encoding='utf-8')
    record={'params':params,'parent_gate_sha256':bound[str(RUN/(NAME+'_gate.db'))],
        'source_manifest_sha256':sha(BUILD/'SOURCE_MANIFEST.json'),'script_sha256':sha(tcl),
        'started_utc':datetime.now(timezone.utc).isoformat(),'hardware_status':'NOT_RUN'}
    put(folder/'START.json',record);print('START '+label,flush=True)
    log=folder/'place.log'
    with log.open('xb') as f:cp=subprocess.run([str(TD),tcl.name],cwd=folder,stdout=f,stderr=subprocess.STDOUT)
    check();assert all(sha(Path(p))==v for p,v in bound.items())
    raw=log.read_text(encoding='utf-8',errors='replace')
    errors=[s for s in raw.splitlines() if re.search(r'\bERROR\b|\bFATAL\b|CHECKPOINT_PLACE_FAIL',s)]
    passed=cp.returncode==0 and not errors and raw.splitlines().count('CHECKPOINT_PLACE_PASS')==1 and (folder/'place.db').is_file()
    record.update(passed=passed,returncode=cp.returncode,errors=errors,log_sha256=sha(log),ended_utc=datetime.now(timezone.utc).isoformat())
    put(folder/'RESULT.json',record);print('END '+label+' '+str(passed),flush=True)
    if passed:
        put(out/'SUCCESS.json',dict(record,folder=str(folder),place_db_sha256=sha(folder/'place.db')));sys.exit(0)
sys.exit(1)
