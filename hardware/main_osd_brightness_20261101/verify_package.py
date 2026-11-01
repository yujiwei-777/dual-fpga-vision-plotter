"""Run in an unchanged extracted package with Python 3.11+."""
from pathlib import Path
import hashlib,json,re
root=Path(__file__).resolve().parent
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest().upper()
m=json.loads((root/'PACKAGE_MANIFEST.json').read_text(encoding='utf-8-sig'))
actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
expected={x['path'] for x in m['files']}|{'PACKAGE_MANIFEST.json','SHA256SUMS.txt'}
assert actual==expected, actual^expected
for x in m['files']:
 p=root/x['path']; assert p.is_file() and p.stat().st_size==x['bytes'] and sha(p)==x['sha256'],x['path']
for line in (root/'SHA256SUMS.txt').read_text(encoding='utf-8-sig').splitlines():
 h,rel=line.split('  ',1); assert sha(root/rel)==h,rel
al=(root/m['entry_project']).read_text(encoding='utf-8-sig')
assert re.search(r'<Project\b[^>]*\bPath="\."',al)
refs=re.findall(r'<File\s+Path="([^"]+)"',al)
assert len(refs)==m['active_reference_count']
for ref in refs:
 assert not re.match(r'^(?:[A-Za-z]:|/|\\)',ref),ref
 p=(root/ref).resolve(); assert p.is_file() and root.resolve() in p.parents,ref
assert sha(root/m['bit'])==m['bit_sha256']
assert sha(root/'05_boot/best_result'/Path(m['bit']).name)==m['bit_sha256']
s=json.loads((root/'SOURCE_PROVENANCE.json').read_text(encoding='utf-8-sig'))
for x in s['snapshot_mapping']: assert sha(root/x['packaged_path'])==x['source_sha256'],x['packaged_path']
assert len(s['snapshot_mapping'])==189 and s['exact_inherited_count']==187
print(f"PACKAGE_VERIFY_PASS: refs={len(refs)}; current_inputs=189; inherited_exact=187; documented_differences=2; historical_freeze_not_reasserted")
