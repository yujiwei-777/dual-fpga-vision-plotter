"""Verify the complete pair before building; Python 3.9+, no FPGA tools."""
from pathlib import Path
import hashlib,json,subprocess,sys
r=Path(__file__).resolve().parent
def sha(p):
 with p.open('rb') as f:
  h=hashlib.sha256()
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
  return h.hexdigest().upper()
m=json.loads((r/'PACKAGE_MANIFEST.json').read_text(encoding='utf-8-sig'))
expected={x['path'] for x in m['files']}|{'PACKAGE_MANIFEST.json','SHA256SUMS.txt'}
actual={p.relative_to(r).as_posix() for p in r.rglob('*') if p.is_file()}
assert actual==expected,f'Unexpected/missing files: {actual^expected}'
for item in m['files']:
 p=r/item['path']
 assert p.stat().st_size==item['bytes'] and sha(p)==item['sha256'],item['path']
for line in (r/'SHA256SUMS.txt').read_text(encoding='utf-8-sig').splitlines():
 digest,relative=line.split('  ',1)
 assert sha(r/relative)==digest,relative
for p in m['projects']:
 root=r/p['directory']
 subprocess.run([sys.executable,str(root/'verify_package.py')],check=True)
 assert sha(root/p['bit'])==p['bit_sha256']
 assert sha(root/'05_boot/best_result'/Path(p['bit']).name)==p['bit_sha256']
print('PAIR_PACKAGE_VERIFY_PASS')
