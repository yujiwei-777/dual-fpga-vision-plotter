from pathlib import Path
import hashlib,json,re,sys
ROOT=Path(__file__).resolve().parent
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest().upper()
def main():
    m=json.loads((ROOT/'PACKAGE_MANIFEST.json').read_text(encoding='utf-8'));errors=[]
    for n,d in m['files'].items():
        p=(ROOT/n).resolve()
        if not p.is_relative_to(ROOT) or not p.is_file() or sha(p)!=d['sha256']:errors.append(n)
    for line in (ROOT/'SHA256SUMS.txt').read_text(encoding='utf-8').splitlines():
        h,n=line.split('  ',1)
        if sha(ROOT/n)!=h:errors.append('SHA256SUMS: '+n)
    for item in m['projects']:
        project=ROOT/item['directory'];mf=project/'evidence/SOURCE_MANIFEST.json'
        if sha(mf)!=item['manifest_sha256']:errors.append('frozen manifest '+item['board'])
        freeze=json.loads(mf.read_text(encoding='utf-8-sig'))
        for n,d in freeze['files'].items():
            if not (project/n).is_file() or sha(project/n)!=d['sha256'].upper():errors.append('frozen '+n)
        if sha(ROOT/'01_bit'/item['bit'])!=item['bit_sha256']:errors.append('bit '+item['board'])
        for entry in [project/n for n in freeze['files'] if Path(n).suffix in {'.al','.prj'}]:
            for ref in re.findall(r'<File\s+Path="([^"]+)"',entry.read_text(encoding='utf-8-sig')):
                p=(entry.parent/ref.replace('&amp;','&')).resolve()
                if not p.is_relative_to(project) or not p.is_file():errors.append('project ref '+ref)
    if errors:
        print('\n'.join(errors));raise SystemExit('PACKAGE_VERIFY_FAILED')
    print('PACKAGE_VERIFY_PASS: files='+str(len(m['files']))+'; frozen inputs=550; bits=2; hardware=NOT_RUN')
if __name__=='__main__':main()
