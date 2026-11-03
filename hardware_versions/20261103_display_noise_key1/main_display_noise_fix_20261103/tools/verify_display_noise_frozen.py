"""Fail closed if any prebuild source/IP/MEM/constraint/script changed."""
from display_noise_paths import *
from verify_inactive_project_files import validate as validate_inactive
from verify_display_noise_build_strategy import validate as validate_build_strategy
def main():
    snapshot=obj(RUN/'source_snapshot.json');errors=[]
    if snapshot.get('passed') is not True:errors.append('Prebuild snapshot rejected')
    if Path(snapshot['run']).resolve()!=RUN.resolve():errors.append('Snapshot belongs to another run')
    for item in snapshot.get('files',[]):
        p=Path(item['path'])
        if not p.is_file() or sha(p)!=item['sha256']:errors.append('Frozen input drift: '+str(p))
    errors.extend(validate_inactive()['errors'])
    errors.extend(validate_build_strategy(snapshot=snapshot)['errors'])
    print({'passed':not errors,'errors':errors});return int(bool(errors))
if __name__=='__main__':raise SystemExit(main())
