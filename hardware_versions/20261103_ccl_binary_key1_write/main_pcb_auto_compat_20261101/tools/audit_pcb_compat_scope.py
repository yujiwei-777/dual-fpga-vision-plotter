"""Read-only baseline comparison. Writes only new scope evidence.
This is a current source comparison, not retrospective bit provenance proof.
"""
from argparse import Namespace
import json
import td_release_audit as audit
from pcb_compat_paths import *
ALLOWED = {
 '01_rtl/imgq_gain_m/shared/rtl/hxa_main_link.v',
 '01_rtl/imgq_gain_m/main/user_source/hdl_source/design_top_wrapper.v',
 '01_rtl/imgq_gain_m/main/user_source/hdl_source/key4_hold_debounce.v',
 '01_rtl/imgq_gain_m/main/user_source/hdl_source/hx_result_select.v',
}
def main():
    br = BASE / '01_rtl/imgq_gain_m/main/td_project_compact_v2'
    baseline = audit.collect(Namespace(root=BASE, run=br, al=None, name=NAME,
        config=BASE/'tools/release_audit_config.json', extra=[]))
    errors = list(baseline['errors'])
    rows, changed = [], []
    if not BASEBIT.is_file() or sha(BASEBIT) != BASESHA:
        errors.append('Baseline bit identity changed')
    for item in baseline['files']:
        p = Path(item['path']); rel = p.relative_to(BASE).as_posix()
        if item['kind'] in {'project','audit_configuration'}: continue
        if rel.startswith('01_rtl/imgq_gain_m/main/td_project_compact_v2/'): continue
        now = ROOT/rel
        digest = sha(now) if now.is_file() else None
        rows.append({'path':rel, 'baseline_sha256':item['sha256'], 'sha256':digest})
        if digest != item['sha256']:
            changed.append(rel)
            if rel not in ALLOWED: errors.append('Out-of-scope active input changed: '+rel)
        if not now.is_file(): errors.append('Missing active input: '+rel); continue
        if not now.resolve().is_relative_to(ROOT): errors.append('Dependency escapes new copy: '+rel)
        if 'work' in [v.lower() for v in now.resolve().parts]: errors.append('Protected work reference: '+rel)
        if now.stat().st_nlink != 1: errors.append('Shared hardlink input: '+rel)
    result = {'passed':not errors, 'baseline_bit':str(BASEBIT), 'baseline_bit_sha256':BASESHA,
      'changed':changed, 'allowed_changes':sorted(ALLOWED), 'errors':errors, 'files':rows,
      'scope':'PCB wait, existing task lifecycle and existing result overlay only. Current baseline dependencies collected read-only; no claim that stale baseline snapshots certify its bit.',
      'hardware_status':'NOT_RUN'}
    put(ROOT/'reports/pcb_compat_source_scope.json',result)
    print(json.dumps({k:result[k] for k in ('passed','changed','errors')},indent=2))
    return int(bool(errors))
if __name__ == '__main__': raise SystemExit(main())
