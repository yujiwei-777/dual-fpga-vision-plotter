"""Verify the untouched source distribution with Python 3.9+."""
from pathlib import Path
import hashlib,json,re
root=Path(__file__).resolve().parent
def sha(p):
 with p.open('rb') as f:
  h=hashlib.sha256()
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
  return h.hexdigest().upper()
m=json.loads((root/'PACKAGE_MANIFEST.json').read_text(encoding='utf-8-sig'))
expected={x['path'] for x in m['files']}|{'PACKAGE_MANIFEST.json','SHA256SUMS.txt'}
actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()}
assert actual==expected, f'Unexpected/missing files: {actual^expected}'
for item in m['files']:
 p=root/item['path']
 assert p.stat().st_size==item['bytes'] and sha(p)==item['sha256'],item['path']
for line in (root/'SHA256SUMS.txt').read_text(encoding='utf-8-sig').splitlines():
 digest,relative=line.split('  ',1)
 assert sha(root/relative)==digest,relative
assert sha(root/m['bit'])==m['bit_sha256']
t=(root/m['entry_project']).read_text(encoding='utf-8-sig')
assert re.search(r'<Project\b[^>]*\bPath="\."',t)
refs=re.findall(r'<File\s+Path="([^"]+)"',t)
assert len(refs)==m['active_reference_count']
for ref in refs:
 assert not re.match(r'^(?:[A-Za-z]:|/|\\)',ref),ref
 p=(root/ref).resolve()
 assert p.is_file() and root in p.parents,ref
p=json.loads((root/'SOURCE_PROVENANCE.json').read_text(encoding='utf-8-sig'))
for item in p['snapshot_mapping']:
 assert sha(root/item['packaged_path'])==item['source_sha256'],item['packaged_path']
for snapshot in p['snapshots']:
 assert sha(root/snapshot['packaged_snapshot'])==snapshot['original_snapshot_sha256']
 assert len(snapshot['files'])==270
 for item in snapshot['files']:
  assert sha(root/item['packaged_path'])==item['source_sha256'],item['packaged_path']
build=json.loads((root/m['build_record']).read_text(encoding='utf-8-sig'))
for ref,digest in build['regression_evidence_sha256'].items():assert sha(root/ref)==digest,ref
for item in p['memory_and_include_dependencies']:
 assert sha(root/item['packaged_path'])==item['source_sha256'],item['packaged_path']
boot=root/'05_boot/best_result'/Path(m['bit']).name
assert sha(boot)==m['bit_sha256']
print(f"SECONDARY_PACKAGE_VERIFY_PASS: files={len(actual)}; refs={len(refs)}; frozen_unique={len(p['snapshot_mapping'])}")

e=json.loads((root/'RELEASE_EVIDENCE_MAPPING.json').read_text(encoding='utf-8-sig'))
assert len(e['mapped_evidence'])==948 and len(e['omitted_evidence'])==1
for item in e['mapped_evidence']:
 assert sha(root/item['packaged_path'])==item['source_sha256'],item['packaged_path']
print('CURRENT_FACTORED_EVIDENCE_VERIFY_PASS')
