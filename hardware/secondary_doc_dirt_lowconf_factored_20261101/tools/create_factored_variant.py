"""Create a source-only independent candidate, then factor the exact low-score cone.

No TD executable is launched. Parent build outputs and PASS results are not
qualification of this root. Historical clock-hook proofs are imported as such.
"""
from __future__ import annotations
from datetime import datetime, timezone
import difflib
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
PARENT = ROOT.parent / 'secondary_doc_dirt_lowconf_area_20261101'
BASE = ROOT.parent / 'secondary_cnn_key3_stroke_compact_20261101'
FAILED_RUN = PARENT / 'dirt_lowconf_area_r2_Runs_20261101'
AUDIT = ROOT / 'reports/factored_source_creation'
PARENT_PIPE_SHA = 'D5F83FC41A64071C4BC6E013D731664B8A177094816189D7E6CE22BF83812B42'
BASE_PIPE_SHA = '6D9B376A6FCEA579A8DF96845C80F162FD973A99ED9BDD9A015A9A48CE84A6E9'
OLD_WIRES = b'''    wire [7:0] selected_shape_threshold=(shape_saved==1) ? TRIANGLE_MARGIN_MIN :
        (shape_saved==2) ? CIRCLE_MARGIN_MIN : SQUARE_MARGIN_MIN;'''
NEW_WIRES = OLD_WIRES + b'''
    // Separate hard eligibility from the unchanged soft-margin diagnostic.
    wire cnn_hard_reject=shape_reject_saved || color_samples_saved<8;
    wire cnn_soft_reject=color_margin_saved<COLOR_MARGIN_MIN ||
        shape_margin_saved<selected_shape_threshold;'''
OLD_BLOCK = b'''                        if(shape_reject_saved || color_samples_saved<8 || color_margin_saved<COLOR_MARGIN_MIN ||
                           shape_margin_saved<selected_shape_threshold)begin
                            multi_flags[6]<=1'b1;
                            confidence_margin<=((CNN_LOWCONF_OUTPUT != 0) &&
                                !shape_reject_saved && color_samples_saved>=8) ?
                                minimum_cnn_margin : 8'd0;
                        end else confidence_margin<=minimum_cnn_margin;'''
NEW_BLOCK = b'''                        if(cnn_hard_reject || cnn_soft_reject)
                            multi_flags[6]<=1'b1;
                        if(CNN_LOWCONF_OUTPUT != 0)
                            confidence_margin<=cnn_hard_reject ? 8'd0 : minimum_cnn_margin;
                        else
                            confidence_margin<=(cnn_hard_reject || cnn_soft_reject) ?
                                8'd0 : minimum_cnn_margin;'''


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def exact_factored(before):
    assert hashlib.sha256(before).hexdigest().upper() == PARENT_PIPE_SHA
    assert before.count(b'\r\n') == before.count(b'\n'), 'Frozen pipeline EOL differs'
    for old, new in ((OLD_WIRES, NEW_WIRES), (OLD_BLOCK, NEW_BLOCK)):
        old, new = old.replace(b'\n', b'\r\n'), new.replace(b'\n', b'\r\n')
        assert before.count(old) == 1, 'Unexpected exact factor anchor'
        before = before.replace(old, new, 1)
    return before


def main():
    assert ROOT.name == 'secondary_doc_dirt_lowconf_factored_20261101'
    assert 'work' not in {p.lower() for p in ROOT.resolve().parts}
    assert sha(PARENT / '01_rtl/vision_pipeline.v') == PARENT_PIPE_SHA
    assert sha(BASE / '01_rtl/vision_pipeline.v') == BASE_PIPE_SHA
    assert not (AUDIT / 'CREATION.json').exists(), 'Creation is one-shot'
    allowed_existing = {Path(__file__).resolve()}
    assert {p.resolve() for p in ROOT.rglob('*') if p.is_file()} == allowed_existing, \
        'Candidate root contains files beyond creation script'
    AUDIT.mkdir(parents=True)
    selected = {}

    def add_tree(relative, dest=None):
        for path in sorted((PARENT / relative).rglob('*')):
            if path.is_file() and '__pycache__' not in path.parts:
                target = Path(dest or relative) / path.relative_to(PARENT / relative)
                selected[target.as_posix()] = path

    for relative in ('01_rtl', '04_pin', 'main', 'model', 'shared', 'tools'):
        add_tree(relative)
    for relative in ('_gen_project.py', 'lint_full.f', 'secondary_cnn_multibox.al'):
        selected[relative] = PARENT / relative
    # Only static simulator sources/references are imported. Fresh simulations
    # will regenerate output logs, RESULTS, and every prepared qualification.
    for path in sorted((PARENT / '02_sim').rglob('*')):
        relative = path.relative_to(PARENT)
        if not path.is_file() or path.suffix not in ('.v', '.sv', '.vh', '.py', '.mem'):
            continue
        if any(part in ('work', '__pycache__') for part in path.parts):
            continue
        if relative.parts[1] == 'doc_dirt_frontend' or relative.parts[1].startswith('stroke_split_'):
            continue
        if '_actual' in path.name:
            continue
        selected[relative.as_posix()] = path
    # These exact files are immutable hook qualification inputs, even though
    # their historical archive includes named RESULTS/log files. Never treat
    # them as a fresh place, route, or regression result for this candidate.
    for relative in ('reports/key3_clocktrace_verification_20261031',
                     'reports/compact_area_sclk_adapter_review_20261101',
                     'reports/imported_baseline_metric_archive',
                     'reports/bootstrap_sources'):
        add_tree(relative)
    # Preserve the prepared parent fixtures separately as provenance; keep
    # runtime preparation directories unprepared so --prepare is mandatory.
    for name in ('dirt_qualification', 'cnn_lowconf_qualification',
                 'legacy_area_wrapper_qualification'):
        add_tree('reports/' + name, 'reports/imported_parent_qualification/' + name)
    for name in ('source', 'provenance'):
        add_tree('reports/dirt_qualification/' + name)
    copied = []
    for relative, source in sorted(selected.items()):
        assert source.resolve().is_relative_to(PARENT.resolve()), 'External linked input'
        assert 'work' not in {p.lower() for p in source.resolve().parts}
        target = ROOT / relative
        assert not target.exists(), 'Copy would overwrite: ' + str(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        digest = sha(source)
        assert sha(target) == digest
        copied.append({'source': str(source), 'relative': relative,
                       'bytes': source.stat().st_size, 'sha256': digest})
    project = ROOT / 'secondary_cnn_multibox.al'
    project_before = project.read_bytes()
    project_anchor = ('Path="' + PARENT.as_posix() + '"').encode('utf-8')
    assert project_before.count(project_anchor) == 1
    project.write_bytes(project_before.replace(project_anchor,
        ('Path="' + ROOT.as_posix() + '"').encode('utf-8'), 1))
    before = (ROOT / '01_rtl/vision_pipeline.v').read_bytes()
    after = exact_factored(before)
    (ROOT / '01_rtl/vision_pipeline.v').write_bytes(after)
    (AUDIT / 'vision_pipeline.parent.v').write_bytes(before)
    (AUDIT / 'vision_pipeline.factor.patch').write_text(''.join(difflib.unified_diff(
        before.decode().splitlines(keepends=True), after.decode().splitlines(keepends=True),
        fromfile='parent/01_rtl/vision_pipeline.v', tofile='factored/01_rtl/vision_pipeline.v')),
        encoding='utf-8', newline='')
    fail_inputs = {}
    for relative in ('syn_1/source_snapshot.json', 'syn_1/secondary_cnn_multibox_gate.area',
                     'syn_1/secondary_cnn_multibox_gate.timing',
                     'phy_1/source_snapshot.json', 'phy_1/td_console.log'):
        path = FAILED_RUN / relative
        if path.is_file():
            fail_inputs[relative] = {'path': str(path), 'sha256': sha(path)}
    manifest = {
        'status': 'CREATED_SOURCE_ONLY_NOT_PREPARED', 'hardware_status': 'NOT_RUN',
        'created_utc': datetime.now(timezone.utc).isoformat(),
        'root': str(ROOT), 'actual_source_parent': str(PARENT),
        'compact_control_baseline': str(BASE), 'failed_parent_run': str(FAILED_RUN),
        'failed_parent_evidence': fail_inputs,
        'baseline_pipeline_sha256': BASE_PIPE_SHA,
        'parent_pipeline_sha256': PARENT_PIPE_SHA,
        'candidate_pipeline_sha256': sha(ROOT / '01_rtl/vision_pipeline.v'),
        'parent_top_sha256': sha(PARENT / '01_rtl/secondary_top.v'),
        'candidate_top_sha256': sha(ROOT / '01_rtl/secondary_top.v'),
        'root_project_path_only_rebase': {
            'relative': 'secondary_cnn_multibox.al',
            'parent_sha256': sha(PARENT / 'secondary_cnn_multibox.al'),
            'candidate_sha256': sha(project),
            'only_change': 'XML Project Path attribute rebased to independent root',
        },
        'copied_files': copied,
        'only_production_source_change': '01_rtl/vision_pipeline.v',
        'scope': 'Exact binary hard/soft reject factoring; thresholds, flag6, model, stabilizer unchanged.',
        'excluded': ['all *_Runs*', 'artifacts', 'simulator libraries/logs/RESULTS',
                     'parent runtime PREPARED_INPUTS markers', 'parent physical PASS results'],
        'historical_only': ['reports/compact_area_sclk_adapter_review_20261101',
                            'reports/key3_clocktrace_verification_20261031',
                            'reports/imported_baseline_metric_archive',
                            'reports/bootstrap_sources', 'reports/imported_parent_qualification'],
        'fresh_evidence_required': 'Reprepare, regression, synthesis, place, route, checks, bitgen',
        'td_launched': False,
    }
    (AUDIT / 'CREATION.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: manifest[key] for key in ('status', 'root', 'candidate_pipeline_sha256',
                                                    'candidate_top_sha256', 'td_launched')}, indent=2))
    print('copied_files=' + str(len(copied)))


if __name__ == '__main__':
    main()
