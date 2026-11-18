"""Fresh retained-function tests bound to the exact independent r4 freeze.

This runner never changes a production source or launches a physical build.
Child tests compile current candidate RTL; every frozen production input is
compared with the candidate and the independent build before and after tests.
"""
from pathlib import Path
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor, as_completed
import argparse, hashlib, json, os, re, subprocess, sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
PREFIXES = ('01_rtl/', 'shared/', '04_pin/', 'model/', 'main/')


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            h.update(block)
    return h.hexdigest().upper()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def put(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, default=Path('E:/codex_paper_airwalk_secondary_20261113_r4'))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    run = args.run.resolve()
    manifest = run/'SOURCE_MANIFEST.json'
    plan = read(run/'BUILD_PLAN.json')
    manifest_hash = sha(manifest)
    assert manifest_hash == plan['source_manifest_sha256'], 'Build manifest differs from plan'
    assert Path(plan['source_root']).resolve() == ROOT, 'Wrong current source tree'
    frozen = read(manifest)['files']
    pins = {str(manifest): manifest_hash, str(Path(__file__).resolve()): sha(__file__)}
    production = {}

    def check_frozen():
        assert sha(manifest) == manifest_hash, 'Manifest drift'
        for rel, row in frozen.items():
            assert sha(run/rel) == row['sha256'], 'Frozen drift '+rel
            if rel.startswith(PREFIXES):
                assert sha(ROOT/rel) == row['sha256'], 'Current production drift '+rel
                production[rel] = row['sha256']

    check_frozen()
    out = (args.output or ROOT/'reports/preserved_airwalk_r4'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')).resolve()
    assert out.is_relative_to(ROOT/'reports/preserved_airwalk_r4')
    out.mkdir(parents=True, exist_ok=False)
    base = ['--run', str(run)]
    tests = ROOT/'tests'
    jobs = [
        ('ordinary27', tests/'suspect_r6/run_current.py', base+['ordinary']),
        ('pcb_pipeline_adapter_sharehold', tests/'suspect_r6/run_current.py', base+['pipeline', 'adapter', 'sharehold']),
        ('pcb_core22', tests/'suspect_r6/run_core.py', base),
        ('cnn_publication', tests/'suspect_r6/run_publication.py', base),
        ('plotter', tests/'suspect_r6/run_current.py', base+['plotter']),
        ('hxa_fifo_crc', tests/'suspect_r6/run_current.py', base+['hxa']),
        ('reader', tests/'suspect_r6/run_current.py', base+['reader']),
        ('key3', tests/'suspect_r6/run_current.py', base+['key3']),
        ('key1_snapshot', tests/'operator_ui/run_key1_retained_snapshot.py', []),
        ('key2_consecutive', ROOT/'tools/run_doc_key1_key2_regression.py', ['--suspect-center']),
        ('report_suspect12', ROOT/'tools/run_suspect_report_regression.py', ['--center-input']),
    ]
    for _, path, _ in jobs:
        pins[str(path)] = sha(path)
    helper = ROOT/'tools/run_retrained_preserved_regressions.py'
    pins[str(helper)] = sha(helper)
    shutil_source = Path(__file__).resolve().read_bytes()
    (out/'RUNNER_AT_EXECUTION.py').write_bytes(shutil_source)

    def bind_receipt(path):
        value = read(path)
        assert value['status'].startswith('PASS'), 'Receipt failed '+str(path)
        bound = {}
        def visit(v):
            if isinstance(v, dict):
                if 'source_drift' in v:
                    assert not v['source_drift'], 'Child source drift'
                for key in ('source_hashes', 'source_sha256', 'input_hashes'):
                    for filename, digest in v.get(key, {}).items():
                        if not isinstance(digest, str):
                            continue
                        source = Path(filename)
                        if not source.is_absolute():
                            source = ROOT/source
                        source = source.resolve()
                        if source.is_relative_to(ROOT):
                            rel = source.relative_to(ROOT).as_posix()
                            if rel.startswith(PREFIXES):
                                assert rel in frozen, 'Unfrozen production input '+rel
                                assert digest.upper() == frozen[rel]['sha256'], 'Child source mismatch '+rel
                                assert sha(source) == digest.upper(), 'Child input drift '+rel
                                bound[rel] = digest.upper()
                for child in v.values():
                    if isinstance(child, (dict, list)):
                        visit(child)
            elif isinstance(v, list):
                for child in v:
                    visit(child)
        visit(value)
        assert bound, 'Receipt did not identify current production sources '+str(path)
        return dict(path=str(path), sha256=sha(path), status=value['status'], bound_current_production_sources=bound)

    references = [] # All new-variant suites run fresh; no old receipts imported.
    checked_references = [bind_receipt(path) for path in references]
    put(out/'PLAN.json', dict(run=str(run), source_manifest_sha256=manifest_hash,
        production_inputs=production, jobs=[dict(label=x, path=str(p), arguments=a) for x,p,a in jobs],
        reused_fresh_results=checked_references, doc_integrated_and_ack='Assigned separately; not repeated here.',
        bitgen_allowed=False, hardware='NOT_RUN'))
    env = dict(os.environ, LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT', MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT')

    def execute(job):
        label, path, arguments = job
        log = out/(label+'.log')
        # Concurrent Windows datetime calls can share the same clock tick.
        # Explicit per-job output names prevent two run_current children from
        # selecting the same timestamp directory before any RTL test starts.
        child_arguments = list(arguments)
        if path.name == 'run_current.py':
            child_arguments += ['--output', str(ROOT/'reports'/('retained_'+out.name+'_'+label))]
        command = [sys.executable, '-B', str(path), *child_arguments]
        with log.open('xb') as stream:
            cp = subprocess.run(command, cwd=ROOT.parent, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=7200)
        text = log.read_text(encoding='utf-8-sig', errors='replace')
        passed = cp.returncode == 0 and not re.search(r'Traceback \(most recent call last\)|\*\*\s+(?:Error|Fatal):', text)
        receipts = []
        for line in text.splitlines():
            if line.startswith('CURRENT_SUITE_OUTPUT '):
                receipts.append(Path(line.split(' ', 1)[1])/'RESULTS.json')
            try:
                v = json.loads(line)
            except ValueError:
                continue
            if isinstance(v, dict):
                for key in ('report', 'result', 'output'):
                    if isinstance(v.get(key), str) and Path(v[key]).is_file():
                        receipts.append(Path(v[key]))
        bound = []
        error = None
        try:
            assert receipts, 'No current test receipt'
            for receipt in sorted(set(receipts)):
                bound.append(bind_receipt(receipt))
        except Exception as exc:
            passed = False
            error = repr(exc)
        print(label+': '+('PASS' if passed else 'FAIL')+' '+str(log), flush=True)
        return dict(label=label, status='PASS' if passed else 'FAIL', returncode=cp.returncode,
            command=command, log=str(log), log_sha256=sha(log), receipts=bound, error=error)

    rows = []
    with ThreadPoolExecutor(max_workers=3) as pool:
        futures = {pool.submit(execute, job): job[0] for job in jobs}
        for future in as_completed(futures):
            try:
                rows.append(future.result())
            except BaseException as exc:
                rows.append(dict(label=futures[future], status='FAIL', error=repr(exc)))
            put(out/'PROGRESS.json', rows)
    drift = [p for p,h in pins.items() if not Path(p).is_file() or sha(p) != h]
    validation_error = None
    try:
        check_frozen()
    except Exception as exc:
        validation_error = repr(exc)
    passed = not drift and validation_error is None and all(row['status']=='PASS' for row in rows)
    value = dict(status='PASS_CURRENT_R4_PRESERVED' if passed else 'FAIL',
        source_manifest=dict(path=str(manifest), sha256=manifest_hash), production_inputs=production,
        source_before=pins, source_drift=drift, frozen_validation_error=validation_error,
        commands=rows, reused_fresh_results=checked_references, hardware='NOT_RUN', bitgen_allowed=False,
        localization_accuracy='EXPLORATORY_NOT_PASSED', limitations=[
            'Archived frames are regression fixtures; no new classifier/localization accuracy claim.',
            'Behavioral tests do not establish physical DDR/CDC, plotter mechanics or routed timing acceptance.',
            'Document integrated/ACK tests are assigned separately and are not repeated here.',
            'Publication requires independent successful place/route and release audit.'])
    target = out/'RESULTS.json'
    put(target, value)
    print(json.dumps(dict(status=value['status'], report=str(target), sha256=sha(target))), flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
