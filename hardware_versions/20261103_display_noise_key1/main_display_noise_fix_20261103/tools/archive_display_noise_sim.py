"""Preserve a completed spatial attempt and recreate source-only canonical tests.

Call only after the simulation owner confirms no process still uses canonical
paths. This tool does not touch product RTL, active build RUN or constraints.
"""
import argparse
from datetime import datetime, timezone
import shutil

from display_noise_paths import ROOT, sha, put


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--failed-attempt', required=True, type=int)
    args = parser.parse_args()
    attempt = args.failed_attempt
    if attempt < 3:
        raise ValueError('Earlier simulation evidence already has its own archive')
    sim = ROOT / '02_sim/display_noise'
    archive = sim.with_name(f'display_noise_attempt{attempt}_rtl_v{attempt}')
    root = ROOT.resolve()
    if not sim.is_dir() or archive.exists():
        raise ValueError('Expected canonical tests and an unused archive path')
    if not sim.resolve().is_relative_to(root) or not archive.resolve().is_relative_to(root):
        raise ValueError('Absolute source/archive paths must remain inside independent project')
    if sim.lstat().st_file_attributes & 0x400:
        raise ValueError('Refusing to move a linked test directory')
    entries = []
    for p in sorted(sim.rglob('*')):
        if p.lstat().st_file_attributes & 0x400:
            raise ValueError('Linked item in test area: ' + str(p))
        if p.is_file():
            entries.append({'path': p.relative_to(sim).as_posix(), 'sha256': sha(p),
                            'bytes': p.stat().st_size})
    sources = [p.name for p in sim.iterdir() if p.is_file() and p.suffix in {'.py', '.ps1', '.sv'}]
    if set(sources) != {'generate_vectors.py', 'summarize_results.py', 'run_display_noise.ps1', 'tb_display_spatial.sv'}:
        raise ValueError('Unexpected canonical source set')
    sim.rename(archive)
    sim.mkdir()
    for filename in sorted(sources):
        shutil.copy2(archive / filename, sim / filename)
        if sha(archive / filename) != sha(sim / filename):
            raise ValueError('Fresh test source copy mismatch')
    if any(sha(archive / item['path']) != item['sha256'] for item in entries):
        raise ValueError('Archive changed during move')
    put(ROOT / f'reports/attempt{attempt}_spatial_archive.json', {
        'passed': True, 'generated_utc': datetime.now(timezone.utc).isoformat(),
        'archive': str(archive.resolve()), 'canonical': str(sim.resolve()),
        'original_file_count': len(entries), 'original_files': entries,
        'canonical_sources_only': sorted(sources), 'fresh_simulation_status': 'NOT_RUN',
        'trial_isolation': 'Root confirmed the concurrent trial owns independent DUT/model/tests/vectors and has no canonical path dependency.',
    })
    print({'passed': True, 'archived_files': len(entries), 'fresh_sources': sorted(sources)})


if __name__ == '__main__':
    main()
