"""Archive complete attempt-2 spatial evidence and create a clean test area."""
from datetime import datetime, timezone
from pathlib import Path
import shutil

from display_noise_paths import ROOT, sha, put


def main():
    sim = ROOT / '02_sim/display_noise'
    archive = sim.with_name('display_noise_attempt2_rtl_v2')
    root = ROOT.resolve()
    if not sim.is_dir() or archive.exists():
        raise ValueError('Expected old test directory and an unused archive path')
    if not sim.resolve().is_relative_to(root) or not archive.resolve().is_relative_to(root):
        raise ValueError('Test/archive paths must remain inside independent project')
    if sim.lstat().st_file_attributes & 0x400:
        raise ValueError('Refusing to move a linked test directory')
    entries = []
    for path in sorted(sim.rglob('*')):
        if path.lstat().st_file_attributes & 0x400:
            raise ValueError('Linked file in test area: ' + str(path))
        if path.is_file():
            entries.append({'path': path.relative_to(sim).as_posix(), 'sha256': sha(path),
                            'bytes': path.stat().st_size})
    sources = [p.name for p in sim.iterdir() if p.is_file() and p.suffix in {'.py', '.ps1', '.sv'}]
    if set(sources) != {'generate_vectors.py', 'summarize_results.py', 'run_display_noise.ps1', 'tb_display_spatial.sv'}:
        raise ValueError('Unexpected spatial test source set')
    sim.rename(archive)
    sim.mkdir()
    for filename in sorted(sources):
        shutil.copy2(archive / filename, sim / filename)
        if sha(archive / filename) != sha(sim / filename):
            raise ValueError('Fresh test source copy mismatch')
    if any(sha(archive / item['path']) != item['sha256'] for item in entries):
        raise ValueError('Archive changed during move')
    put(ROOT / 'reports/attempt2_spatial_archive.json', {
        'passed': True, 'generated_utc': datetime.now(timezone.utc).isoformat(),
        'archive': str(archive.resolve()), 'canonical': str(sim.resolve()),
        'original_file_count': len(entries), 'original_files': entries,
        'canonical_sources_only': sorted(sources),
        'preserved_compile_warning': 'Original vlib existing-library warning remains in archived compile.log; no original log edited.',
        'fresh_simulation_status': 'NOT_RUN',
    })
    print({'passed': True, 'archived_files': len(entries), 'fresh_sources': sorted(sources)})


if __name__ == '__main__':
    main()
