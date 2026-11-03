from pathlib import Path
import hashlib,json,re
ROOT=Path(__file__).resolve().parent
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest().upper()
def main():
 m=json.loads((ROOT/'PACKAGE_MANIFEST.json').read_text(encoding='utf-8'))
 actual={p.relative_to(ROOT).as_posix() for p in ROOT.rglob('*') if p.is_file()}
 assert actual==set(m['files'])|{'PACKAGE_MANIFEST.json','SHA256SUMS.txt'},'File set mismatch'
 for name,item in m['files'].items():
  p=ROOT/name
  assert p.stat().st_size==item['bytes'] and sha(p)==item['sha256'],name
 for line in (ROOT/'SHA256SUMS.txt').read_text().splitlines():
  digest,name=line.split('  ',1)
  assert sha(ROOT/name)==digest,name
 records=json.loads((ROOT/'SOURCE_AND_EVIDENCE_MAPPING.json').read_text(encoding='utf-8'))['records']
 for item in records:assert sha(ROOT/item['path'])==item['sha256'],item['path']
 for item in m['projects']:
  p=ROOT/item['directory'];assert sha(p/item['bit'])==item['bit_sha256']
  text=(p/item['entry']).read_text(encoding='utf-8-sig')
  assert not re.search(r'[A-Za-z]:[/\\]',text)
  for ref in re.findall(r'<File\s+Path="([^"]+)"',text):
   target=(p/ref).resolve();assert target.is_relative_to(p.resolve()) and target.is_file(),ref
 print('PACKAGE_VERIFY_PASS; pair hardware=NOT_RUN; source mappings='+str(len(records)))
if __name__=='__main__':main()
