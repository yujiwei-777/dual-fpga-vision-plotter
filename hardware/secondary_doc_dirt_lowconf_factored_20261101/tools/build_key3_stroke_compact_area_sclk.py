"""New full area build with a reviewed, read-only PH1P SCLK proof adapter.

All production RTL, SDC, previous builders, hooks and runs remain unchanged.
The new hook only extends source tracing; it neither changes clocks nor grants
timing exceptions. Every inherited regression/physical/readonly/bitgen gate
remains mandatory. Importing or installing this module never starts TD.
"""
from __future__ import annotations

from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

import build_key3_stroke_compact_area as area

compact = area.compact
reviewed = area.reviewed
base = area.base
flow = area.flow
ROOT = area.ROOT
RUNS = 'cnn_key3_stroke_compact_area_sclk_Runs_20261101'
STEM = 'dual_fpga_secondary_20261101_cnn_key3_stroke_compact_area_sclk_diagnostic'
SELF = 'tools/build_key3_stroke_compact_area_sclk.py'
HOOK = '04_pin/clocktrace_sclk/prove_key3_supervisor_clocktrace.tcl'
LEGACY_HOOK = '04_pin/prove_key3_supervisor_clocktrace.tcl'
LEGACY_HOOK_SHA256 = 'EDC066683001510C7159AC7351348C209FFD556570F3C66CE40DD6735E834A34'

# Filled only after independent review of the exact hook and its negative
# tests. A missing digest intentionally prevents prepare and all build actions.
HOOK_SHA256: str | None = 'B075E954594269ED473318765371C9D92E510B22D2A211D5AE1AD99453DD40E9'
PROOF_TEST_INPUTS: dict[str, str] = {'04_pin/apply_cdc_exceptions.tcl': '9E5375F16D36A906DC480843BAE9F1BEA1D24770A852EED988627E6C3716D1E0',
 '04_pin/apply_reset_exceptions.tcl': 'BE1FA0BE99A0097DECEAA38AC7E5FBEEFAC2D54662077D66558292AF6CB30D94',
 '04_pin/clocktrace_sclk/prove_key3_supervisor_clocktrace.tcl': 'B075E954594269ED473318765371C9D92E510B22D2A211D5AE1AD99453DD40E9',
 '04_pin/prove_key3_supervisor_clocktrace.tcl': 'EDC066683001510C7159AC7351348C209FFD556570F3C66CE40DD6735E834A34',
 'reports/compact_area_sclk_adapter_review_20261101/archive_proof_evidence.py': '1EAA454B3CAE3E839C72C2BB50654F452592E92AC73360611779A254D93856FC',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/ARCHIVE_MANIFEST.json': '71FBD091AA2C59B0140B311C7BF245907EF2BA19D5923C36F312FF158463F6EF',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/RESULTS.json': '09281BE8B90E918C568EC9C93C3FC07017476A906CB1BDDE107578533A10F63C',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/000_run_sclk_tests.py': '47A681D73004C91B242E91A7230AA56E7C62E58B0382ACF4B449143EAFCAEBAB',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/003_test_sclk_cases.tcl': '53D91B9D56EACC9251D491CCE1FEC8545C1CB9078A49E04D6005DB403C65F036',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/004_control_route_inventory.txt': 'F65E6794C2788155E9CF8F43D7647A408A86030849E7A9308B8F2C77EE6A9B38',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/005_gate_inventory.txt': 'ABEB4A99584BECAAA0E3B63E2CD20772EF4997E580068BAABC898BF6520CEB50',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/006_key_pad_inventory.txt': 'ED2A6834186B2B9AC235BE7D6D8492A1F114D237D58573E44C429A95BD64F0DC',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/007_apply_cdc_exceptions.tcl': '9E5375F16D36A906DC480843BAE9F1BEA1D24770A852EED988627E6C3716D1E0',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/008_apply_reset_exceptions.tcl': 'BE1FA0BE99A0097DECEAA38AC7E5FBEEFAC2D54662077D66558292AF6CB30D94',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/009_prove_key3_supervisor_clocktrace.tcl': 'EDC066683001510C7159AC7351348C209FFD556570F3C66CE40DD6735E834A34',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/013_ph1p_macro.v': '049A0F45FD59FC645F63C71D1506E42348368170130B4B05E774AEE228436503',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/014_ph1p_clock.v': 'B30C8681E511AFA407E647FDAA8068360FB0BBF664EC841800FC2716831CEA0E',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/015_UG1310_PH1P_Libraries_Guide_for_HDL_Designs.pdf': '71BFFD594321B92C58116DB5BB28088FA18DB738C20BB279AB801E84F3A4C208',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/016_generated_test.tcl': '3DC84B5C81D6A6D1099C0D4F9345592C64D719AB6165526A4DA7FA004DCCA11D',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/017_stdout.log': '4919D57644BB8F17999163581052B8AF8B208F1C8D520A333E39952BABBC970E',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/018_stderr.log': 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/019_secondary_key3_full_gate.rpt': 'B0F751438CA52FF141128E6AC852D9600AD8B3ED2E6E45805731C25F256FC78F',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/020_secondary_key3_full_mixed.rpt': 'BE785C91F6A92283F1BCA6ECC900396CAF766A3BA28D34F4318047E725817B52',
 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/external/021_secondary_key3_full_physical.rpt': '250155BC15E004FDFB453FBFC97D68A80A1C3BA0E5E1BDB92B1391F2BFC2456A',
 'reports/key3_clocktrace_verification_20261031/clock_source/test_clocktrace_hook.tcl': '8A24047B30F8AD6AECE20B47E9FEC9CB70B50352C51D9DD30AA81498210DC2CF'}
PROOF_TEST_REPORT: str | None = 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/RESULTS.json'
PROOF_ARCHIVE_MANIFEST: str | None = 'reports/compact_area_sclk_adapter_review_20261101/proof_evidence/ARCHIVE_MANIFEST.json'

LEGACY_AREA_RUNS = area.RUNS
LEGACY_AREA_SELF = area.SELF
LEGACY_SNAPSHOT_EXTRAS = tuple(reviewed.SNAPSHOT_EXTRAS)
_area_prepare = area.prepare
_area_validate = area.validate_plan
_area_bitgen = area.bitgen
_installed = False


def qualification():
    """Pin both old proof behavior and the exact reviewed new proof closure."""
    flow.require(flow.sha(ROOT / LEGACY_HOOK) == LEGACY_HOOK_SHA256,
                 'Legacy EDC clocktrace hook changed; preserve the frozen input')
    flow.require(isinstance(HOOK_SHA256, str) and re.fullmatch(r'[0-9A-F]{64}', HOOK_SHA256),
                 'SCLK hook has not been reviewed and SHA256-pinned')
    hook = flow.local(HOOK)
    flow.require(hook.is_file() and flow.sha(hook) == HOOK_SHA256,
                 'Reviewed SCLK hook is missing or changed')
    flow.require(PROOF_TEST_REPORT in PROOF_TEST_INPUTS and
                 PROOF_ARCHIVE_MANIFEST in PROOF_TEST_INPUTS and bool(PROOF_TEST_INPUTS),
                 'Reviewed SCLK proof-test evidence has not been pinned')
    tests = {}
    for relative, expected in PROOF_TEST_INPUTS.items():
        path = flow.local(relative)
        flow.require(isinstance(expected, str) and re.fullmatch(r'[0-9A-F]{64}', expected) and
                     path.is_file() and flow.sha(path) == expected,
                     'SCLK proof-test input missing or changed: ' + relative)
        tests[relative] = expected
    report = flow.load(ROOT / PROOF_TEST_REPORT)
    # The precise test-report schema is bound before this adapter is eligible
    # for use. Generic truthy status strings cannot authorize a new hook.
    flow.require(report.get('passed') is True and report.get('hook_sha256') == HOOK_SHA256,
                 'SCLK proof-test report does not pass for the reviewed hook')
    flow.require(report.get('inputs_unchanged') is True and
                 report.get('full_supervisor_reports_valid') is True and
                 report.get('tcl_exit_code') == 0 and
                 report.get('td_invoked') is False and
                 report.get('timing_exceptions_installed') is False,
                 'SCLK unit proof scope or full-supervisor result differs')
    summaries = report.get('summary', [])
    flow.require(len(summaries) == 1 and summaries[0].get('failed') == 0 and
                 summaries[0].get('cases') == len(report.get('cases', [])) and
                 summaries[0].get('positive', 0) > 0 and summaries[0].get('negative', 0) > 0 and
                 summaries[0]['positive'] + summaries[0]['negative'] == summaries[0]['cases'] and
                 all(case.get('status') in {'PASS', 'EXPECTED_REJECTION'} for case in report['cases']),
                 'SCLK positive/negative test enumeration is incomplete')
    archive = flow.load(ROOT / PROOF_ARCHIVE_MANIFEST)
    flow.require(archive.get('passed') is True and
                 archive.get('report_local') == PROOF_TEST_REPORT and
                 archive.get('report_sha256') == PROOF_TEST_INPUTS[PROOF_TEST_REPORT],
                 'SCLK proof archive does not bind the exact reviewed report')
    expected = {}
    for group in ('input_sha256', 'evidence_sha256'):
        records = report.get(group, {})
        flow.require(isinstance(records, dict) and bool(records), 'SCLK test input/evidence list is empty')
        expected.update({(group, origin): digest for origin, digest in records.items()})
    seen = {}
    for record in archive.get('files', []):
        key = (record['group'], record['origin'])
        local = record['local']
        flow.require(key not in seen and key in expected and
                     record['sha256'] == expected[key] and
                     tests.get(local) == expected[key],
                     'SCLK proof archive has an unbound, duplicate or changed record')
        seen[key] = record['sha256']
    flow.require(seen == expected, 'SCLK proof archive omits an original test input or evidence file')
    return {
        'status': 'PASS_PINNED_SCLK_PROOF_SOURCE_ONLY',
        'hook': HOOK, 'hook_sha256': HOOK_SHA256,
        'legacy_hook': LEGACY_HOOK, 'legacy_hook_sha256': LEGACY_HOOK_SHA256,
        'proof_test_inputs_sha256': tests,
        'proof_archive_manifest': PROOF_ARCHIVE_MANIFEST,
        'physical_acceptance': 'NOT_GRANTED_REQUIRES_ALL_CURRENT_FIVE_PHASE_PROOFS',
    }


def identity(args, runs):
    flow.require(ROOT.name == base.scope.COMPACT_NAME and
                 Path(runs).resolve() == ROOT / RUNS and args.stem == STEM,
                 'SCLK adapter is locked to its independent run and output')


def expected_extras():
    return tuple(dict.fromkeys((*compact.accepted.EXTRAS, LEGACY_AREA_SELF,
        *LEGACY_SNAPSHOT_EXTRAS, HOOK, SELF, *PROOF_TEST_INPUTS)))


def provenance():
    return {
        'adapter': SELF, 'adapter_sha256': flow.sha(ROOT / SELF),
        'runs': RUNS, 'stem': STEM,
        'proof_only_change': qualification(),
        'production_rtl_changed': False, 'sdc_changed': False,
        'models_changed': False, 'mapping_strategy': dict(area.STRATEGY),
        'legacy_area_run_unchanged': LEGACY_AREA_RUNS,
        'required_phases': list(reviewed.PHASES),
        'inherited_gates': 'Full compact area source, regression, route, CDC/FIFO/DDR/DRC, readonly and bitgen gates',
        'hardware_status': 'NOT_RUN',
    }


def supplemental_scope(snapshot):
    qualified = qualification()
    value = flow.load(snapshot) if isinstance(snapshot, (str, Path)) else snapshot
    flow.require(value.get('passed') is True and not value.get('errors') and
                 Path(value['project_root']).resolve() == ROOT,
                 'SCLK proof snapshot did not pass or belongs to another root')
    selected = {}
    required = {LEGACY_HOOK: LEGACY_HOOK_SHA256, HOOK: HOOK_SHA256,
                SELF: flow.sha(ROOT / SELF), **PROOF_TEST_INPUTS}
    for item in value['files']:
        relative = flow.local(item['path']).relative_to(ROOT).as_posix()
        if relative in required:
            flow.require(relative not in selected, 'Duplicate SCLK proof input: ' + relative)
            flow.require(item['kind'] == 'explicit_dependency' and
                         item['sha256'] == required[relative],
                         'SCLK proof input must be explicitly frozen exactly once: ' + relative)
            selected[relative] = item['sha256']
    flow.require(selected == required, 'SCLK proof snapshot lacks an exact required dependency')
    return {**qualified, 'snapshot_dependencies_sha256': selected,
            'source_manifest_sha256': value['manifest_sha256']}


def prepare(args, runs):
    identity(args, runs)
    qualification()
    flow.require(not runs.exists(), 'Fresh independent SCLK run required')
    _area_prepare(args, runs)
    snapshots = {phase: supplemental_scope(runs / phase / 'source_snapshot.json')
                 for phase in ('syn_1', 'phy_1')}
    path = runs / 'BUILD_PLAN.json'
    plan = flow.load(path)
    plan['compact_sclk_release'] = {**provenance(), 'snapshots': snapshots}
    flow.save(path, plan)


def validate_plan(runs):
    flow.require(Path(runs).resolve() == ROOT / RUNS,
                 'SCLK adapter cannot validate a different or legacy run')
    qualification()
    plan = _area_validate(runs)
    expected = {**provenance(), 'snapshots': {
        phase: supplemental_scope(runs / phase / 'source_snapshot.json')
        for phase in ('syn_1', 'phy_1')}}
    flow.require(plan.get('compact_sclk_release') == expected,
                 'Frozen SCLK proof-only provenance differs')
    return plan


def bitgen(args, runs):
    identity(args, runs)
    plan = validate_plan(runs)
    _area_bitgen(args, runs)
    path = ROOT / 'artifacts' / (STEM + '_BUILD.json')
    data = flow.load(path)
    data['compact_sclk_release'] = plan['compact_sclk_release']
    flow.save(path, data)


def install():
    global _installed
    flow.require(not _installed, 'SCLK adapter installation is single-use')
    qualification()
    # First inherit all unchanged area/compact/controlmap/V2 gates. Runtime
    # bindings below are confined to this process and this fresh run identity.
    area.install()
    area.RUNS = RUNS
    area.STEM = STEM
    reviewed.CLOCKTRACE_HOOK = HOOK
    reviewed.CLOCKTRACE_HOOK_SHA256 = HOOK_SHA256
    reviewed.SNAPSHOT_EXTRAS = tuple(dict.fromkeys((
        *LEGACY_SNAPSHOT_EXTRAS, HOOK, SELF, *PROOF_TEST_INPUTS)))
    extras = expected_extras()
    compact.accepted.EXTRAS = base.EXTRAS = extras
    compact.accepted.RUNS = base.RUNS = flow.RUNS = RUNS
    base.STEM = flow.STEM = STEM
    # area.bitgen resolves its own validate_plan global; bind that too, so a
    # direct invocation cannot bypass this supplementary source-proof gate.
    area.validate_plan = validate_plan
    flow.prepare = prepare
    flow.validate_plan = validate_plan
    flow.bitgen = bitgen
    _installed = True


if __name__ == '__main__':
    try:
        install()
        raise SystemExit(flow.main())
    except (OSError, ValueError, KeyError, RuntimeError, AssertionError, ET.ParseError) as error:
        print('BUILD_KEY3_STROKE_COMPACT_AREA_SCLK_FAIL:', error, file=sys.stderr)
        raise SystemExit(1)
