"""Reconstruct baseline provenance read-only; this is not a prebuild snapshot."""
import datetime as dt
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / 'main_osd_brightness_20261101'
RUN = BASE / '01_rtl/imgq_gain_m/main/td_project_compact_v2'
LEGACY = RUN / 'source_snapshot.json'
EXPECTED_BIT = 'FB3FE4F57721C7068821EC0C010D589CB82398E6F38CCCF3F7892006033E5515'
START_NS = int(dt.datetime(2026, 11, 1, 15, 36, 31).timestamp() * 1_000_000_000)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

old = json.loads(LEGACY.read_text(encoding='utf-8'))
old_root = Path(old['project_root'])
files, changed, late, missing = [], [], [], []
for item in old['files']:
    source = Path(item['path'])
    current = BASE / source.relative_to(old_root) if source.is_relative_to(old_root) else source
    if not current.is_file():
        missing.append(str(current))
        continue
    row = dict(item)
    row.update(path=current.as_posix(), sha256=digest(current), bytes=current.stat().st_size,
               mtime_ns=current.stat().st_mtime_ns, legacy_path=item['path'],
               legacy_sha256=item['sha256'])
    row['matches_legacy_sha256'] = row['sha256'] == item['sha256']
    files.append(row)
    if not row['matches_legacy_sha256']:
        changed.append(current.relative_to(BASE).as_posix())
    if row['mtime_ns'] > START_NS:
        late.append(current.as_posix())

evidence_paths = [LEGACY, BASE/'bitgen.log', BASE/'reports/brightness_release_20261101.json',
    RUN/'console_brightness_synth.log', RUN/'camera_to_dsi_display_720p60_cnn_multibox_gate.db',
    RUN/'camera_to_dsi_display_720p60_cnn_multibox_pr.db',
    BASE/'artifacts/dual_fpga_main_20261101_osd_brightness_diagnostic.bit']
evidence = [dict(path=p.as_posix(), sha256=digest(p), bytes=p.stat().st_size,
                 mtime_ns=p.stat().st_mtime_ns) for p in evidence_paths]
al = RUN/'camera_to_dsi_display_720p60_cnn_multibox.al'
old_al = ROOT.parent/'main_osd_chinese_no_hist_20261031/01_rtl/imgq_gain_m/main/td_project_compact_v2/camera_to_dsi_display_720p60_cnn_multibox.al'
al_rebase_only = old_al.read_text().replace('main_osd_chinese_no_hist_20261031', BASE.name) == al.read_text()
expected_changes = ['01_rtl/imgq_gain_m/main/td_project_compact_v2/camera_to_dsi_display_720p60_cnn_multibox.al',
    '01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/display_tone_96.v']
passed = (not missing and not late and sorted(changed) == sorted(expected_changes)
    and al_rebase_only and evidence[-1]['sha256'] == EXPECTED_BIT and len(files) == 189)
result = dict(schema_version=1, classification='POST_HOC_RECONSTRUCTED_BASELINE_NOT_PREBUILD_SNAPSHOT',
    generated_utc=dt.datetime.now(dt.timezone.utc).isoformat(), baseline_root=BASE.as_posix(),
    original_legacy_snapshot_root=old['project_root'], legacy_snapshot_hash=digest(LEGACY),
    synthesis_start_local='2026-11-01T15:36:31+08:00', source_files=files, evidence=evidence,
    changed_relative_to_legacy=changed, files_after_synthesis_start=late, missing=missing,
    al_only_root_rebase=al_rebase_only, consistency_checks_passed=passed,
    limitations=['Reconstructed after the successful build; not a prebuild freeze.',
        'Legacy source hashes plus successful synthesis/bitgen logs and file mtimes support provenance.',
        'Mtimes are not tamper-proof; this does not prove every bitstream byte is derived from current source bytes.',
        'New variant must create its own prebuild source snapshot before synthesis.'])
out = ROOT/'reports/recovered_brightness_baseline_manifest.json'
out.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
text = '\n'.join(['# Brightness baseline provenance reconstruction', '',
    'Classification: **POST_HOC_RECONSTRUCTED_BASELINE_NOT_PREBUILD_SNAPSHOT**.', '',
    f'Baseline bit SHA256: `{EXPECTED_BIT}`.',
    f'Consistency checks: {passed}; {len(files)} complete hashed dependencies; {len(changed)} expected differences.',
    'The only changes from the old no_hist manifest are project root rebasing and display_tone_96 48 -> 52.',
    'All hashed inputs predate the 2026-11-01 15:36:31 synthesis start; successful gate/route DB and bitgen logs are hashed.',
    'All source paths and previous/current hashes are in the accompanying JSON.', '',
    'This reconstruction is not the original prebuild snapshot. File mtimes are supporting evidence, not tamper-proof proof.',
    'No baseline RTL, bit, database, manifest or work/ file was modified.', ''])
(ROOT/'reports/recovered_brightness_baseline_manifest.md').write_text(text, encoding='utf-8')
print(json.dumps(dict(passed=passed, files=len(files), changed=changed, manifest=str(out)), indent=2))
raise SystemExit(0 if passed else 1)
