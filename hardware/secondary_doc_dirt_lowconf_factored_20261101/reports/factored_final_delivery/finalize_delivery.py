"""Read-only verification and optional final release index; never runs TD."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import sys

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
RUN = ROOT / 'dirt_lowconf_factored_Runs_20261101'
PHY = RUN / 'phy_1'
NAME = 'secondary_cnn_multibox'
STEM = 'dual_fpga_secondary_20261101_doc_dirt_lowconf_factored_diagnostic'
BIT = ROOT / 'artifacts' / (STEM + '.bit')
BUILD = ROOT / 'artifacts' / (STEM + '_BUILD.json')
BASE_SHA = '3C5F52B2247DE0C6DF5E774204D6C0241B326D73AB628352D4ED3042ABDD67F0'
PLAN_SHA = '1D147B5094B6CED1242C55BF48CFB6C80819A414F3212CAECB4EEA444C1956FE'
QUALITY_SHA = '6D215EB338877FBA6E7F8CDBB6B3D1C2D9601B42EFFE48FB2A64D9139997A6F7'
PRODUCTION_PINS = {
    '01_rtl/doc_image_frontend.v': '42F2140588B7DB5AB5E815DFDFA0BFD0CEE161944CC198DD1BEAA571B22D05F4',
    '01_rtl/secondary_top.v': 'DCA939F1C76E1920FF99647E1C19B733C6A0177033631317DCAED237FD2106DC',
    '01_rtl/vision_pipeline.v': '02E7954C55C5696E299D7B980DE0C4BF95C1FDF65531D1D005CFDC6882D099D5',
}


def require(value, message):
    if not value:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def read(path):
    return Path(path).read_text(encoding='utf-8-sig')


def load(path):
    return json.loads(read(path))


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def verify_production():
    require(ROOT.name == 'secondary_doc_dirt_lowconf_factored_20261101' and
            'work' not in {x.lower() for x in ROOT.resolve().parts}, 'Wrong/protected root')
    for relative, expected in PRODUCTION_PINS.items():
        require(sha(ROOT / relative) == expected, 'Production pin differs: ' + relative)
    require(sha(RUN / 'BUILD_PLAN.json') == PLAN_SHA, 'Frozen build plan differs')


def verify_gate(build, gate):
    require(build['status'] == 'DIAGNOSTIC_NOT_RUN' and build['hardware_validation'] == 'NOT_RUN', 'Bit status differs')
    require(build['baseline_bit_sha256'] == BASE_SHA and Path(build['runs']).resolve() == RUN and
            build['bit'] == BIT.name, 'Build identity differs')
    require(gate['passed'] is True and gate['bitgen_allowed'] is True and gate['failures'] == [], 'Routed gate failed')
    require(Path(gate['run']).resolve() == PHY and gate['name'] == NAME and
            gate['hardware_status'] == 'NOT_RUN', 'Routed gate identity differs')
    require(gate['timing_ns'] == build['timing_ns'] and gate['resources'] == build['resources'], 'Published physical metrics differ')


def verify_readonly_identity(readonly, inputs):
    require(readonly['passed'] is True and readonly['failures'] == [] and
            readonly['hardware_status'] == 'NOT_RUN', 'Readonly verification failed')
    require({Path(p).resolve() for p in inputs} == {
        PHY / (NAME + '.al'), PHY / (NAME + '_pr.db')}, 'Readonly DB/AL closure differs')


def verify_quality(quality, scope, document, lowconf):
    require(quality['status'] == 'PASS_SOFTWARE_AND_RTL_SCOPE_ONLY' and
            quality['hardware_status'] == 'NOT_RUN', 'Quality scope differs')
    require(Path(quality['project_root']).resolve() == ROOT and Path(quality['run']).resolve() == RUN and
            quality['build_plan_bound'] is True, 'Quality root/run/plan differs')
    require(quality['source_scope'] == scope and quality['doc_regression'] == document and
            quality['lowconfidence_regression'] == lowconf, 'Quality current-source/RTL evidence differs')
    require(quality['production_sha256'] == {**PRODUCTION_PINS,
        '01_rtl/cnn_result_stabilizer.v': '9C946B4DDBA2E0BE3CE917E172EAF6775095349E19A28B95D4300A5596157128',
        '01_rtl/cnn_core.v': 'CD3C6128836B816D5CA211722E22090E4676173CA52DB462592224E18C3E5ED3'},
        'Quality production pins differ')
    require(quality['physical_build_acceptance_claimed'] is False and
            quality['bitgen_authorized_by_this_report'] is False and
            quality['bound_evidence_sha256'] and quality['limitations'], 'Quality overclaims or lacks provenance/limits')


def verify():
    require(ROOT.name == 'secondary_doc_dirt_lowconf_factored_20261101' and
            'work' not in {x.lower() for x in ROOT.resolve().parts}, 'Wrong/protected root')
    required = [BIT, BUILD, BIT.with_suffix('.bit.sha256'), PHY / (NAME + '.bit'),
        PHY / '.opt_place.end.f', PHY / '.opt_route.end.f', PHY / '.bitgen.end.f',
        RUN / 'syn_1/.opt_gate.end.f', PHY / 'release_gate.json',
        PHY / (NAME + '_pr.timing'), PHY / (NAME + '_phy.area'),
        ROOT / '02_sim' / (RUN.name + '_physical_review/FINAL_PHYSICAL_REVIEW.json'),
        ROOT / '02_sim' / (RUN.name + '_readonly/readonly_verification.json'),
        ROOT / 'reports/factored_delivery_quality/QUALITY.json']
    missing = [str(p.relative_to(ROOT)) for p in required if not p.is_file()]
    require(not missing, 'NOT_READY: missing ' + ', '.join(missing))
    verify_production()
    require(BIT.stat().st_size > 0, 'Empty bitstream')
    sys.path.insert(0, str(ROOT / 'tools'))
    builder = module(ROOT / 'tools/build_doc_dirt_lowconf_factored.py', 'final_frozen_builder')
    require(sha(ROOT / 'tools/build_doc_dirt_lowconf_factored.py') ==
        '2ADA653BB3BB7FD72B3424FA379A3620E5AE363C87505DE90F249C8753B14CBA', 'Frozen builder differs')
    builder.validate(RUN)
    for phase in ('syn_1', 'phy_1'):
        require(not list((RUN / phase).glob('.*.error.f')) and not (RUN / phase / '.stop.f').exists(),
                'Failed/stopped stage: ' + phase)
    bound = {}

    def bind(path, expected=None):
        path = Path(path).resolve(strict=True)
        require(path.is_relative_to(ROOT.resolve()), 'Evidence escapes independent root')
        digest = sha(path)
        require(expected is None or digest == expected, 'Changed evidence: ' + str(path))
        key = path.relative_to(ROOT).as_posix()
        require(key not in bound or bound[key] == digest, 'Evidence changed during verification')
        bound[key] = digest
        return digest

    for path in required:
        bind(path)
    plan, build, gate = load(RUN / 'BUILD_PLAN.json'), load(BUILD), load(PHY / 'release_gate.json')
    bind(RUN / 'BUILD_PLAN.json')
    verify_gate(build, gate)
    require(build['source_manifest_sha256'] == plan['source_manifest_sha256'], 'Published source manifest differs')
    bit_sha = bind(BIT, build['bit_sha256'])
    bind(PHY / (NAME + '.bit'), bit_sha)
    require(read(BIT.with_suffix('.bit.sha256')).strip() == bit_sha + '  ' + BIT.name, 'SHA256 sidecar differs')
    require(gate['source_manifest_sha256'] == load(PHY / 'source_snapshot.json')['manifest_sha256'] and
            Path(gate['snapshot']).resolve() == RUN / 'syn_1/source_snapshot.json', 'Gate source manifest/snapshot differs')
    timing = read(PHY / (NAME + '_pr.timing'))
    require('Both (Slow and Fast)' in timing and 'Confidence          : Routed' in timing, 'Missing routed corner coverage')
    for key in ('SWNS', 'STNS', 'HWNS', 'HTNS'):
        values = re.findall(r'\b' + key + r':\s*([-+]?\d+(?:\.\d+)?)ns', timing)
        require(len(values) == 1 and float(values[0]) == build['timing_ns'][key], 'Timing field differs: ' + key)
        require(float(values[0]) >= 0 and (not key.endswith('TNS') or float(values[0]) == 0), 'Timing failed: ' + key)
    area = read(PHY / (NAME + '_phy.area'))
    for kind, limit in (('slice', 95), ('eram', 90), ('dsp', 95)):
        values = re.findall(r'^#' + kind + r'\s+(\d+)\s+out of\s+(\d+)', area, re.M)
        require(len(values) == 1, 'Resource field differs: ' + kind)
        used, total = map(int, values[0])
        require(0 <= used <= total and total > 0 and used * 100 < total * limit, 'Resource failed: ' + kind)
        require(build['resources'][kind]['used'] == used and build['resources'][kind]['total'] == total, 'Published resource differs')
    require(isinstance(gate['evidence'], dict) and gate['evidence'], 'Empty routed-gate evidence')
    for key, record in gate['evidence'].items():
        bind(PHY / key, record['sha256'])
    review_path = required[-3]
    review = load(review_path)
    bind(review_path, build['physical_review_sha256'])
    require(review['status'] == 'PASS_WITH_INHERITED_WARNINGS' and review['errors'] == [], 'Physical review failed')
    require(review['timing_ns'] == build['timing_ns'] and review['pcb_model_bytes_unchanged'] is True, 'Physical review differs')
    require(review['fixed_dirt_lowconf_factored_source_scope'] == builder.scope() == build['source_scope'], 'Source scope differs')
    for key in ('new_drc_codes', 'increased_drc_counts', 'increased_check_categories', 'active_source_mismatches',
                'protected_source_mismatches', 'unexpected_cnn_pcb_mismatches', 'intentional_pcb_model_hash_mismatches'):
        require(not review[key], 'Unresolved physical review field: ' + key)
    require(review['cnn_pcb_source_mismatches'] == ['01_rtl/vision_pipeline.v'] and
        review['intentional_pcb_model_updates'] == {'01_rtl/vision_pipeline.v': PRODUCTION_PINS['01_rtl/vision_pipeline.v']} and
        review['intentional_vision_source_updates']['01_rtl/vision_pipeline.v']['after'] == PRODUCTION_PINS['01_rtl/vision_pipeline.v'],
        'Unexpected CNN/PCB source delta')
    key3 = builder.key3.check(ROOT, RUN)
    require(key3 == review['key3_reset_proof'], 'Fresh KEY3 proof differs')
    for key, digest in review['reviewed_report_hashes'].items():
        bind(ROOT / key, digest)
    for key, digest in key3['evidence_sha256'].items():
        bind(ROOT / key, digest)
    readonly_dir = ROOT / '02_sim' / (RUN.name + '_readonly')
    readonly = load(readonly_dir / 'readonly_verification.json')
    readonly_inputs = load(readonly_dir / 'readonly_input_hashes.json')
    verify_readonly_identity(readonly, readonly_inputs)
    bind(readonly_dir / 'readonly_input_hashes.json')
    bind(readonly_dir / 'readonly_verification.json', build['readonly_verification_sha256'])
    require('TD_READONLY_REIMPORT_PASS' in read(readonly_dir / 'td_console.log'), 'Missing readonly marker')
    for key, digest in readonly_inputs.items():
        bind(key, digest)
    for name in ('readonly.ts', 'readonly.timing', 'readonly.exceptions', 'readonly.check',
                 'readonly.area', 'readonly.clocks', 'readonly.flow', 'readonly_reimport.tcl', 'td_console.log'):
        bind(readonly_dir / name)
    readonly_timing = read(readonly_dir / 'readonly.timing')
    for key in ('SWNS', 'STNS', 'HWNS', 'HTNS'):
        values = re.findall(r'\b' + key + r':\s*([-+]?\d+(?:\.\d+)?)ns', readonly_timing)
        require(len(values) == 1 and float(values[0]) == build['timing_ns'][key], 'Readonly timing differs: ' + key)
    for key, digest in build['regression_evidence_sha256'].items():
        bind(ROOT / key, digest)
    bind(ROOT / build['regression_evidence_manifest'], build['regression_evidence_manifest_sha256'])
    require(set(build['regression_evidence_sha256']) == {
        '02_sim/' + name + '/RESULTS.json' for name in builder.SUITES}, 'Seven-suite release closure differs')
    regression_files = [ROOT / p for p in build['regression_evidence_sha256']]
    builder.regression.check(regression_files, required=builder.SUITES)
    require(builder.regression.evidence_manifest(regression_files, required=builder.SUITES) ==
            load(ROOT / build['regression_evidence_manifest']), 'Seven-suite evidence manifest differs')
    document, lowconf = builder.dirt_regression_gate(), builder.lowconf_regression_gate()
    require(document == build['document_regression'], 'Document evidence differs')
    require(lowconf == build['lowconfidence_regression'], 'Low-score evidence differs')
    quality = load(ROOT / 'reports/factored_delivery_quality/QUALITY.json')
    bind(ROOT / 'reports/factored_delivery_quality/QUALITY.json', QUALITY_SHA)
    verify_quality(quality, build['source_scope'], document, lowconf)
    for key, digest in quality['bound_evidence_sha256'].items():
        path = Path(key)
        if not path.is_absolute():
            path = ROOT / key
        require(path.is_file() and sha(path) == digest, 'Changed quality provenance: ' + key)
        if path.resolve().is_relative_to(ROOT.resolve()):
            bind(path, digest)
    source_rows = {}
    for phase in ('syn_1', 'phy_1'):
        snapshot_path = RUN / phase / 'source_snapshot.json'
        bind(snapshot_path, plan['snapshots'][phase]['sha256'])
        for record in load(snapshot_path)['files']:
            path = Path(record['path'])
            bind(path, record['sha256'])
            key = path.relative_to(ROOT).as_posix()
            require(key not in source_rows or source_rows[key]['sha256'] == record['sha256'], 'Inconsistent source across phases')
            source_rows[key] = {'path': key, 'sha256': record['sha256'], 'bytes': record['bytes'], 'kind': record['kind']}
    for group in ('flow_sha256', 'explicit_dependencies_sha256'):
        for key, digest in plan[group].items():
            bind(ROOT / key, digest)
    logs = ''
    for path in (RUN / 'syn_1/td_console.log', PHY / 'td_console.log', PHY / 'bitgen_console.log'):
        bind(path)
        logs += read(path)
    require(not any(code in logs for code in ('PHY-7027', 'PHY-9002', 'RTCLK-5078', 'USR-6113', 'HDL-5105')),
            'Forbidden placement/clock/ROM diagnostic')
    require(not re.search(r'(?:[A-Z]+-\d+\s+ERROR:|\*\*\s+(?:Error|Fatal):)', logs), 'TD error diagnostic')
    for key, digest in bound.items():
        require(sha(ROOT / key) == digest, 'Evidence changed during final verification: ' + key)
    return {'status': 'DIAGNOSTIC_NOT_RUN', 'created_utc': datetime.now(timezone.utc).isoformat(),
        'root': str(ROOT), 'runs': str(RUN), 'bit': str(BIT), 'bit_sha256': bit_sha,
        'baseline_bit_sha256': BASE_SHA, 'hardware_status': 'NOT_RUN',
        'timing_ns': build['timing_ns'], 'resources': build['resources'],
        'source_scope': build['source_scope'], 'source_inventory': list(source_rows.values()),
        'quality_report': 'reports/factored_delivery_quality/QUALITY.json',
        'quality_limitations': quality['limitations'],
        'recovered_placement_supplement': None,
        'final_frozen_plan_sha256': PLAN_SHA,
        'production_pins': PRODUCTION_PINS,
        'source_manifest_sha256': build['source_manifest_sha256'],
        'bound_evidence_sha256': bound, 'finalizer_sha256': sha(__file__)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    report = verify()
    if args.publish:
        target = OUT / 'RELEASE.json'
        require(not target.exists() and not (OUT / 'FROZEN_INPUTS.csv').exists(), 'Preserve existing final release index/inventory')
        target.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        buf = io.StringIO(newline='')
        writer = csv.DictWriter(buf, fieldnames=['path', 'sha256', 'bytes', 'kind'])
        writer.writeheader()
        writer.writerows(report['source_inventory'])
        (OUT / 'FROZEN_INPUTS.csv').write_text(buf.getvalue(), encoding='utf-8-sig')
    print(json.dumps({key: report[key] for key in ('status', 'bit', 'bit_sha256', 'timing_ns', 'resources')}, indent=2))


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, AssertionError, KeyError) as error:
        print('FINAL_DELIVERY_FAIL:', error, file=sys.stderr)
        raise SystemExit(1)
