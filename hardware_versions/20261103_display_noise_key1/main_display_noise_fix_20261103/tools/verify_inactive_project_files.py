"""Hash inactive project files without parsing them as synthesis-active HDL."""
import td_release_audit as audit
from display_noise_paths import *
def validate():
    errors=[];manifest=obj(ROOT/'tools/inactive_project_files.json')
    if manifest.get('schema_version')!=1 or manifest.get('file_count')!=17 or len(manifest.get('files',[]))!=17:errors.append('Inactive file manifest must contain all 17 baseline files')
    if len(manifest.get('project_autoexcluded_entries',[]))!=9:errors.append('Inactive project entry count must be nine')
    project=audit.xml(RUN/(NAME+'.al'));entries={}
    for section in project.findall('./Source_Files/*'):
        for node in section.findall('./File'):
            p=Path(node.get('Path',''));p=p if p.is_absolute() else RUN/p
            if p.resolve().is_relative_to(ROOT):entries[p.relative_to(ROOT).as_posix()]={a.get('Name'):a.get('Val') for a in node.findall('./FileInfo/Attr')}
    for item in manifest.get('project_autoexcluded_entries',[]):
        if entries.get(item['path'],{}).get('AutoExcluded')!='true' or item['attributes'].get('AutoExcluded')!='true':errors.append('Inactive project entry became active: '+item['path'])
    seen=set()
    for item in manifest.get('files',[]):
        p=ROOT/item['path'];original=BASE/item['path']
        if item['path'] in seen:errors.append('Duplicate inactive file '+item['path'])
        seen.add(item['path'])
        if item.get('active') is not False or not p.resolve().is_relative_to(ROOT) or not p.is_file() or sha(p)!=item['sha256']:errors.append('Inactive/support copied hash changed: '+item['path'])
        if not original.is_file() or sha(original)!=item['sha256']:errors.append('Inactive/support baseline hash changed: '+item['path'])
    return {'passed':not errors,'errors':errors,'file_count':len(seen),'autoexcluded_project_count':9}
def main():
    result=validate();print(result);return int(not result['passed'])
if __name__=='__main__':raise SystemExit(main())
