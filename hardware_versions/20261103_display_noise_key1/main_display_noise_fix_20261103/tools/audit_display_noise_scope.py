"""Compare this variant with all actual signed-baseline frozen dependencies."""
import json
from display_noise_paths import *
from verify_inactive_project_files import validate as validate_inactive
from verify_display_noise_build_strategy import validate as validate_build_strategy
HDL='01_rtl/imgq_gain_m/main/user_source/hdl_source/'
ALLOWED={HDL+'design_top_wrapper.v',HDL+'isp/display_tone_96.v',HDL+'a4_display_spatial_h1.v'}
def main():
    old=obj(ROOT/'reports/baseline_source_snapshot_original.json')
    validation=obj(ROOT/'reports/baseline_dependency_validation.json')
    errors=[];changed=[];checked=[]
    if len(old.get('files',[]))!=189 or not old.get('passed') or validation.get('dependency_count')!=189: errors.append('Baseline must contain the validated 189 frozen dependencies')
    if not BASEBIT.is_file() or sha(BASEBIT)!=BASESHA: errors.append('Baseline bit changed')
    if sha(ROOT/'reports/baseline_source_snapshot_original.json')!=validation['baseline_snapshot_sha256']: errors.append('Historical baseline snapshot changed')
    for item in old['files']:
        p=Path(item['path']); rel=p.relative_to(BASE).as_posix()
        if not p.is_file() or sha(p)!=item['sha256']: errors.append('Baseline frozen dependency drift: '+rel)
        if item['kind']=='project':
            expected=read(p).replace(BASE.as_posix(),ROOT.as_posix()).replace(str(BASE),ROOT.as_posix()).replace('td_project_pcb_auto_v2',RUN.name)
            current=RUN/(NAME+'.al')
            if not current.is_file() or read(current)!=expected: errors.append('Project AL changed beyond independent root/run paths')
            continue
        if item['kind']=='audit_configuration':
            if not (ROOT/'tools/release_audit_config.json').is_file() or sha(ROOT/'tools/release_audit_config.json')!=item['sha256']:errors.append('Audit dependency exceptions changed')
            continue
        if '/td_project_pcb_auto_v2/' in rel:
            current=RUN/p.name
            if not current.is_file() or sha(current)!=item['sha256']:errors.append('Frozen run-local dependency changed: '+p.name)
            continue
        now=ROOT/rel;digest=sha(now) if now.is_file() else None
        checked.append({'path':rel,'baseline_sha256':item['sha256'],'sha256':digest})
        if digest!=item['sha256']:
            changed.append(rel)
            if rel not in ALLOWED: errors.append('Out-of-scope active source changed: '+rel)
        if not now.is_file(): errors.append('Missing copied baseline dependency: '+rel);continue
        if now.stat().st_nlink!=1 or not now.resolve().is_relative_to(ROOT): errors.append('Copied dependency is linked/shared/outside root: '+rel)
    result={'passed':not errors,'changed':changed,'allowed_changes':sorted(ALLOWED),'files':checked,'errors':errors,'baseline_bit_sha256':BASESHA,'scope':'Only display tone/spatial filter and required top wiring. Recognition fixed tone must be tested exhaustively; AE/AWB/CNN/PCB/HXA1/DDR/OSD contracts unchanged.','hardware_status':'NOT_RUN'}
    inactive=validate_inactive();errors.extend(inactive['errors']);result['inactive_project_files']=inactive
    strategy=validate_build_strategy();errors.extend(strategy['errors']);result['build_strategy']=strategy;result['passed']=not errors
    put(ROOT/'reports/display_noise_source_scope.json',result)
    print(json.dumps({k:result[k] for k in ['passed','changed','errors']},indent=2));return int(bool(errors))
if __name__=='__main__':raise SystemExit(main())
