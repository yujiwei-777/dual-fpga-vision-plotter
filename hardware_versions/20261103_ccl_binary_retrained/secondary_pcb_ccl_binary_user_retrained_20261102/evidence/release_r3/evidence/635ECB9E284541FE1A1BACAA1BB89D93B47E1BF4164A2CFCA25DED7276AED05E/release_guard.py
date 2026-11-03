"""Report-only gate validation and archival helpers; never runs FPGA tools."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

CHECKS = {'binary_integer','ordinary_cnn','document','writing','cancel_reentry','cdc','fifo','ddr','drc','readonly'}
MANIFEST = '92E737ED8B7D585AEAAC64346A130A2AA7A9F2077A70B14A8CE2D036506A57DB'

def require(ok, message):
    if not ok: raise ValueError(message)

def safe(path):
    path=Path(path).resolve()
    require('work' not in {p.lower() for p in path.parts}, 'Protected backup path: '+str(path))
    return path

def sha(path):
    h=hashlib.sha256()
    with safe(path).open('rb') as f:
        for block in iter(lambda:f.read(1048576),b''):h.update(block)
    return h.hexdigest().upper()

def load(path):return json.loads(safe(path).read_text(encoding='utf-8-sig'))
def put(path,value):Path(path).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def quarantine_gate(here, reason):
    """Archive every old actionable gate before assembly, preserving evidence."""
    here=safe(here)
    paths=[here/name for name in ('FINAL_GATE.json','FINAL_GATE_AUDIT.json','final_gate_evidence_r2') if (here/name).exists()]
    if not paths:return None
    hashes={}
    for path in paths:
        require(path.resolve().is_relative_to(here),'Gate archive escapes report root')
        files=[path] if path.is_file() else sorted(p for p in path.rglob('*') if p.is_file())
        for item in files:hashes[item.relative_to(here).as_posix()]=sha(item)
    archive=here/'gate_history_r2'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    archive.mkdir(parents=True,exist_ok=False)
    for path in paths:path.replace(archive/path.name)
    put(archive/'ARCHIVE.json',dict(reason=reason,files=hashes,hardware='NOT_RUN'))
    for relative,digest in hashes.items():require(sha(archive/relative)==digest,'Gate archive hash differs')
    return str(archive)

def verify_inputs(inputs):
    require(isinstance(inputs,dict) and bool(inputs),'Empty gate input_sha256')
    for path,digest in inputs.items():
        require(isinstance(digest,str) and re.fullmatch('[A-F0-9]{64}',digest),'Invalid input digest: '+str(path))
        require(sha(path)==digest,'Gate input drift: '+str(path))

def verify_current_gate(build,gate_path,here):
    build,gate_path,here=safe(build),safe(gate_path),safe(here)
    require(gate_path==here/'FINAL_GATE.json','Use only the current FINAL_GATE.json')
    gate=load(gate_path);audit=load(here/'FINAL_GATE_AUDIT.json');plan=load(build/'BUILD_PLAN.json')
    require(gate.get('status')=='PASS' and audit.get('status')=='PASS','Current gate/audit not PASS')
    require(not audit.get('errors') and not audit.get('pending') and not audit.get('missing_checks'),'Current gate audit incomplete')
    require(safe(audit['gate']['path'])==gate_path and audit['gate']['sha256']==sha(gate_path),'Current gate audit hash/path differs')
    require(gate.get('generated_utc')==audit.get('generated_utc'),'Gate/audit generation differs')
    require(plan['source_manifest_sha256']==sha(build/'SOURCE_MANIFEST.json')==MANIFEST==gate['source_manifest_sha256']==audit['source_manifest_sha256'],'Wrong r2 manifest')
    require(safe(plan['build_root'])==build and safe(plan['source_root'])==here.parents[1],'Build identity differs')
    require(gate.get('input_sha256')==audit.get('input_sha256'),'Gate/audit input sets differ')
    verify_inputs(gate['input_sha256'])
    manifest=load(build/'SOURCE_MANIFEST.json')['files']
    for relative,row in manifest.items():
        path=safe(build/relative);require(path.is_relative_to(build),'Manifest escapes build')
        require(sha(path)==row['sha256'],'Frozen source drift: '+relative)
    require(set(gate.get('checks',{}))==CHECKS and all(gate['checks'][k] is True for k in CHECKS),'Wrong or failed required check set')
    require(set(gate.get('evidence',{}))==CHECKS,'Wrong required evidence set')
    require(set(audit.get('completed_checks',[]))==CHECKS,'Audit completed checks differ')
    for check,row in gate['evidence'].items():
        require(row.get('status')=='PASS' and sha(row['path'])==row['sha256'],'Evidence drift/failure: '+check)
        detail=load(row['path']);require(detail.get('status')=='PASS' and detail.get('source_manifest_sha256')==MANIFEST,'Evidence wrapper failed/wrong manifest: '+check)
        require(detail.get('source_sha256')==row.get('source_sha256') and bool(row['source_sha256']),'Evidence source set differs: '+check)
        for relative,digest in row['source_sha256'].items():require(relative in manifest and manifest[relative]['sha256']==digest,'Evidence source mismatch: '+relative)
    db=sha(build/'runs/phy_1/secondary_cnn_multibox_pr.db')
    require(gate['routed_database_sha256']==audit['routed_database_sha256']==db,'Gate/audit database differs')
    return gate,audit,manifest

def verify_main_protocol(here):
    folder=safe(here)/'main_protocol_compat_v3';report=load(folder/'RESULTS.json')
    require(report.get('status')=='PASS_PACKET_LEVEL_MAIN_COMPATIBILITY' and report.get('all256_scale_range') is True,'Main packet compatibility failed')
    require(report.get('hardware')=='NOT_RUN','Main hardware status must remain NOT_RUN')
    pins=load(folder/'SOURCE_SHA256.json');require(pins==report['source_hashes'],'Main compatibility source pin set differs');verify_inputs(pins)
    log=(folder/'SIM.log').read_text(encoding='utf-8-sig',errors='replace')
    require(sha(folder/'SIM.log')==report['log_sha256'],'Main compatibility log drift')
    require('TYPE8_COMPAT_ALL_PASS cases=4 malformed255_rejected=1' in log and not re.search(r'\*\*\s+(?:Error|Fatal):',log),'Main compatibility log failed')
    require(len(report['result_records'])==4 and all(line in log for line in report['result_records']),'Main compatibility records absent')
    bits=[path for path in pins if Path(path).suffix.lower()=='.bit'];require(len(bits)==1 and sha(bits[0])==report['main_bit_sha256'],'Main bit identity differs')
    return report
