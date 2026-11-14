from pathlib import Path
import argparse, json, re, shutil, hashlib
ROOT=Path(__file__).resolve().parent
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
    ap=argparse.ArgumentParser(description='Prepare a NEW relocated developer workspace; preserve delivery originals.')
    ap.add_argument('destination',type=Path);a=ap.parse_args();dest=a.destination.resolve()
    if dest.exists():raise SystemExit('Destination must not exist: '+str(dest))
    if dest.is_relative_to(ROOT):raise SystemExit('Choose a directory outside the delivery package')
    ident=json.loads((ROOT/'04_verification/PAIR_IDENTITY.json').read_text(encoding='utf-8'))
    dest.mkdir(parents=True);changes=[];entries={}
    for p in ident['projects']:
        board=p['board'];source=ROOT/p['directory'];target=dest/board
        shutil.copytree(source,target)
        freeze=json.loads((target/'evidence/SOURCE_MANIFEST.json').read_text(encoding='utf-8-sig'))
        project_entries=[target/n for n in freeze['files'] if Path(n).suffix in {'.al','.prj'}]
        for f in project_entries:
            before=f.read_bytes();s=before.decode('utf-8-sig')
            s,count=re.subn(r'(<Project\b[^>]*\bPath=")[^"]*(")',lambda m:m[1]+f.parent.as_posix()+m[2],s,count=1)
            if count!=1:raise RuntimeError('Unknown project header: '+str(f))
            f.write_bytes(s.encode('utf-8'));changes.append(dict(file=f.relative_to(dest).as_posix(),change='Project Path only',original_sha256=hashlib.sha256(before).hexdigest().upper(),new_sha256=sha(f)))
        entries[board]=target/p['entry']
        # Match all actual source-file/CWD interpretations of existing ROM literals.
        aliases=[]
        if board=='secondary':
            for cwd in [entries[board].parent,target/'runs/phy_1']:
                for f in (target/'model/export').glob('*.mem'):aliases.append((f,cwd/'model/export'/f.name))
            for sub in ['experiments/conv4_4','suspect']:
                for f in (target/'model'/sub).glob('*.mem'):aliases.append((f,target/'runs/model'/sub/f.name))
        else:
            for name in ['horizontal.mem','vertical.mem']:
                aliases.append((target/'01_rtl/imgq_gain_m/main/user_source/hdl_source/isp'/name,entries[board].parent/name))
        for source_file,dst in aliases:
            if dst.exists():
                if sha(source_file)!=sha(dst):raise RuntimeError('ROM alias differs: '+str(dst))
            else:
                dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source_file,dst)
                changes.append(dict(file=dst.relative_to(dest).as_posix(),change='equal-byte ROM alias',source=source_file.relative_to(dest).as_posix(),sha256=sha(dst)))
        scripts=({'synth':'run_display_noise_synth.tcl','place':'run_display_noise_place.tcl','route':'run_display_noise_route.tcl'} if board=='main' else {'synth':'run.tcl','place':'../phy_1/run_place.tcl','route':'../phy_1/run_route.tcl'})
        for phase,rel in scripts.items():
            script=(entries[board].parent/rel).resolve()
            assert script.is_file(),script
            wrapper=dest/('build_'+board+'_'+phase+'.tcl')
            wd=script.parent.relative_to(dest).as_posix()
            wrapper.write_text('set delivery_root [file dirname [file normalize [info script]]]\ncd [file join $delivery_root {'+wd+'}]\nsource {'+script.name+'}\n',encoding='utf-8')
        # Validate every adapted AL/PRJ dependency without consulting the original machine.
        for f in project_entries:
            for ref in re.findall(r'<File\s+Path="([^"]+)"',f.read_text(encoding='utf-8-sig')):
                q=(f.parent/ref.replace('&amp;','&')).resolve()
                if not q.is_relative_to(target) or not q.is_file():raise RuntimeError('Project dependency missing/outside: '+str(q))
    (dest/'RELOCATION_REPORT.json').write_text(json.dumps(dict(source_package=ROOT.as_posix(),no_rtl_model_or_constraint_changes=True,changes=changes),ensure_ascii=False,indent=2),encoding='utf-8')
    for k,p in entries.items():print(k+': '+str(p))
    print('PROJECT_PREPARE_PASS; no synthesis or bitgen was run')
if __name__=='__main__':main()
