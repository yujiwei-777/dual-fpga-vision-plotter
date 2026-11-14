"""Index fresh current-source functional receipts and all emitted PASS markers."""
from pathlib import Path
import hashlib,json,re,sys
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
entry=Path(sys.argv[1]).resolve()
root=json.loads(entry.read_text(encoding='utf-8-sig'))
assert root['status']=='PASS_CURRENT_PAPER_R2_PRESERVED'
receipts={entry:sha(entry)};logs={};errors=[];pinned={}
def scan(v):
 if isinstance(v,list):
  for x in v:scan(x)
 elif isinstance(v,dict):
  log=v.get('log')
  if isinstance(log,str) and Path(log).is_file():
   path=Path(log);digest=v.get('log_sha256') or v.get('sha256')
   if digest and sha(path)!=digest:errors.append('log drift '+str(path))
   logs[path]=sha(path)
  for k in ['source_before','source_hashes','source_sha256','source_sha256_before']:
   ps=v.get(k)
   if isinstance(ps,dict):
    for path,digest in ps.items():
     if isinstance(digest,str) and len(digest)==64 and Path(path).is_file():
      pinned[path]=digest
      if sha(path)!=digest:errors.append('source drift '+path)
  for k,x in v.items():
   if k=='receipts' and isinstance(x,list):
    for row in x:
     path=Path(row['path']);assert sha(path)==row['sha256'];receipts[path]=row['sha256'];scan(json.loads(path.read_text(encoding='utf-8-sig')))
   else:scan(x)
scan(root)
markers=[]
for path,digest in sorted(logs.items()):
 for line in path.read_text(encoding='utf-8-sig',errors='replace').splitlines():
  clean=line.lstrip('# ').strip()
  if re.match(r'(?:PASS\b|[A-Z0-9_]*PASS\b)',clean):
   markers.append(dict(log=str(path),log_sha256=digest,marker=clean))
result=dict(status='PASS_INDEX' if not errors else 'FAIL',
 aggregate=dict(path=str(entry),sha256=sha(entry)),receipts=[dict(path=str(p),sha256=h) for p,h in sorted(receipts.items())],
 current_pins_checked=len(pinned),log_count=len(logs),pass_marker_count=len(markers),pass_markers=markers,errors=sorted(set(errors)),
 hardware='NOT_RUN',physical_signoff='ROOT_BUILD_GATES_REQUIRED',localization_accuracy='EXPLORATORY_NOT_PASSED')
out=entry.parent/'EVIDENCE_INDEX.json';out.write_text(json.dumps(result,indent=2)+'\n')
(entry.parent/'PASS_MARKERS.txt').write_text('\n'.join(x['marker']+'\n  '+x['log'] for x in markers)+'\n')
print(json.dumps(dict(status=result['status'],report=str(out),sha256=sha(out),markers=len(markers),errors=result['errors'])))
raise SystemExit(0 if not errors else 1)
