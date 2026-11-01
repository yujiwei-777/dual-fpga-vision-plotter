"""Strict seven-suite adapter for exact opt-in low-score RTL deltas.

The inherited gate/runners are unchanged. Only the reviewed top and pipeline
pins are rebound after reconstructing their exact approved byte changes.
Default CNN_LOWCONF_OUTPUT=0 preserves the golden pipeline behavior; the
configured production top enables real low scores with original flag6 intact.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from unittest import mock

import key3_stroke_regression_gate as inherited

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / 'secondary_cnn_key3_stroke_compact_20261101'
TOP = '01_rtl/secondary_top.v'
PIPELINE = '01_rtl/vision_pipeline.v'
OLD_TOP_SHA = '64176506920BFF546415A1D1433FE1F6558FAAA565B5845FA826B56566694DCA'
TOP_SHA = 'DCA939F1C76E1920FF99647E1C19B733C6A0177033631317DCAED237FD2106DC'
OLD_PIPELINE_SHA = '6D9B376A6FCEA579A8DF96845C80F162FD973A99ED9BDD9A015A9A48CE84A6E9'
PIPELINE_SHA = '02E7954C55C5696E299D7B980DE0C4BF95C1FDF65531D1D005CFDC6882D099D5'
WRAPPER = 'tools/run_cnn_area_pipeline_lowconf_factored.py'
WRAPPER_SHA = 'E6F7DA5B40862CF59CD831C898E10015ACF87420DB80A79C59FD3398055C12BF'
WRAPPER_PREPARED = 'reports/factored_area_wrapper_qualification/PREPARED_INPUTS.json'
SUITES = inherited.SUITES
LAST_AUDIT = None


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def exact_pipeline(before):
    require = inherited._require
    replacements = (
        (b'    parameter integer CNN_STABILITY_ENABLE=1,',
         b'    // Preserve soft-margin diagnostics while optionally publishing real low scores.\n'
         b'    parameter integer CNN_LOWCONF_OUTPUT=0,\n'
         b'    parameter integer CNN_STABILITY_ENABLE=1,'),
        (b'                        // Keep low-margin candidates internal for spatial\n'
         b'                        // association. They cannot establish a new class:\n'
         b'                        // the stable publisher may briefly retain a previously\n'
         b'                        // confirmed identity with confidence zero, or omit it.',
         b'                        // Keep the original margin comparison and bit6 diagnostic.\n'
         b'                        // Default output preserves zero-confidence soft rejection.\n'
         b'                        // Opt-in low-score output retains the real margin, while\n'
         b'                        // hard rejection and the unchanged stabilizer still apply.'),
        (b"                            multi_flags[6]<=1'b1;confidence_margin<=0;",
         b"                            multi_flags[6]<=1'b1;\n"
         b'                            confidence_margin<=((CNN_LOWCONF_OUTPUT != 0) &&\n'
         b'                                !shape_reject_saved && color_samples_saved>=8) ?\n'
         b"                                minimum_cnn_margin : 8'd0;"),
    )
    # Frozen Windows sources use CRLF. Preserve those exact source bytes;
    # replacement literals above use LF only for readable Python source.
    newline = b'\r\n'
    require(before.count(newline) == before.count(b'\n'), 'Unexpected baseline EOL')
    for old, new in replacements:
        old, new = old.replace(b'\n', newline), new.replace(b'\n', newline)
        require(before.count(old) == 1, 'Unreviewed pipeline replacement anchor')
        before = before.replace(old, new, 1)
    # Preserve the reviewed optional-output delta, then factor its exact
    # binary hard/soft predicates without changing state/cycle behavior.
    factored_replacements = (
        (b'    reg [1:0] cnn_color_work,cnn_shape_work;',
         b'    // Separate hard eligibility from the unchanged soft-margin diagnostic.\n'
         b'    wire cnn_hard_reject=shape_reject_saved || color_samples_saved<8;\n'
         b'    wire cnn_soft_reject=color_margin_saved<COLOR_MARGIN_MIN ||\n'
         b'        shape_margin_saved<selected_shape_threshold;\n'
         b'    reg [1:0] cnn_color_work,cnn_shape_work;'),
        (b'                        if(shape_reject_saved || color_samples_saved<8 || color_margin_saved<COLOR_MARGIN_MIN ||\n'
         b'                           shape_margin_saved<selected_shape_threshold)begin\n'
         b"                            multi_flags[6]<=1'b1;\n"
         b'                            confidence_margin<=((CNN_LOWCONF_OUTPUT != 0) &&\n'
         b'                                !shape_reject_saved && color_samples_saved>=8) ?\n'
         b"                                minimum_cnn_margin : 8'd0;\n"
         b'                        end else confidence_margin<=minimum_cnn_margin;',
         b'                        if(cnn_hard_reject || cnn_soft_reject)\n'
         b"                            multi_flags[6]<=1'b1;\n"
         b'                        if(CNN_LOWCONF_OUTPUT != 0)\n'
         b"                            confidence_margin<=cnn_hard_reject ? 8'd0 : minimum_cnn_margin;\n"
         b'                        else\n'
         b'                            confidence_margin<=(cnn_hard_reject || cnn_soft_reject) ?\n'
         b"                                8'd0 : minimum_cnn_margin;"),
    )
    for old, new in factored_replacements:
        old, new = old.replace(b'\n', newline), new.replace(b'\n', newline)
        require(before.count(old) == 1, 'Unreviewed factored pipeline replacement anchor')
        before = before.replace(old, new, 1)
    return before


def top_scope():
    require = inherited._require
    require(ROOT.name == 'secondary_doc_dirt_lowconf_factored_20261101' and
            'work' not in {p.lower() for p in ROOT.resolve().parts},
            'Low-score area gate restricted to its independent root')
    for relative, old_sha, new_sha in ((TOP, OLD_TOP_SHA, TOP_SHA),
                                      (PIPELINE, OLD_PIPELINE_SHA, PIPELINE_SHA)):
        require(sha(BASE / relative) == old_sha and sha(ROOT / relative) == new_sha,
                'Unreviewed low-score source: ' + relative)
    anchor = b'vision_pipeline #(.EXTERNAL_READER(1)'
    before = (BASE / TOP).read_bytes()
    require(before.count(anchor) == 1 and (ROOT / TOP).read_bytes() == before.replace(
        anchor, b'vision_pipeline #(.CNN_LOWCONF_OUTPUT(1),.EXTERNAL_READER(1)', 1),
        'Top changed beyond exact CNN_LOWCONF_OUTPUT(1) parameter')
    require((ROOT / PIPELINE).read_bytes() == exact_pipeline((BASE / PIPELINE).read_bytes()),
            'Pipeline changed beyond exact optional low-score output branch')
    gate = Path(inherited.__file__).resolve()
    require(gate == ROOT / 'tools/key3_stroke_regression_gate.py' and
            sha(gate) == sha(BASE / 'tools/key3_stroke_regression_gate.py'),
            'Inherited strict seven-suite gate was modified')
    require(inherited.ROOT == ROOT and inherited.PINS.get(TOP) == OLD_TOP_SHA and
            inherited.PINS.get(PIPELINE) == OLD_PIPELINE_SHA,
            'Inherited gate root/pin was already overridden')
    require(sha(ROOT / WRAPPER) == WRAPPER_SHA, 'Unreviewed legacy area wrapper')
    return {
        'status': 'PASS_EXACT_FACTORED_OPTIN_LOW_SCORE_TOP_AND_PIPELINE_DELTA',
        'top': {'before': OLD_TOP_SHA, 'after': TOP_SHA},
        'pipeline': {'before': OLD_PIPELINE_SHA, 'after': PIPELINE_SHA},
        'parameters': {'CNN_LOWCONF_OUTPUT': 1, 'TRIANGLE_MARGIN_MIN': 31,
                       'CIRCLE_MARGIN_MIN': 28, 'SQUARE_MARGIN_MIN': 77, 'COLOR_MARGIN_MIN': 0},
        'default_pipeline_parameter_zero_preserves_golden': True,
        'soft_margin_comparison_and_flag6_preserved': True,
        'hard_rejection_separated_from_soft_diagnostics': True,
        'inherited_gate_sha256': sha(gate),
        'legacy_area_wrapper_sha256': WRAPPER_SHA,
        'all_other_pins_and_seven_suite_contracts_unchanged': True,
    }


def wrapper_qualification():
    require = inherited._require
    path = ROOT / WRAPPER_PREPARED
    data = json.loads(path.read_text(encoding='utf-8-sig'))
    require(data.get('status') == 'PREPARED_EXACT_LEGACY_AREA_PIPELINE_HASH_ADAPTER' and
            Path(data['project_root']).resolve() == ROOT and data.get('hardware_status') == 'NOT_RUN' and
            data.get('original_runner_sha256') == inherited.RUNNERS['cnn_area_pipeline_compact'][1] and
            data.get('original_pipeline_pin') == OLD_PIPELINE_SHA and
            data.get('approved_pipeline_pin') == PIPELINE_SHA and
            data.get('all_legacy_simulation_contracts_unchanged') is True,
            'Legacy wrapper preparation identity/contract differs')
    expected = {WRAPPER, 'tools/run_cnn_area_pipeline_compact.py',
                'tools/key3_stroke_lowconf_factored_regression_gate.py',
                'tools/key3_stroke_regression_gate.py', PIPELINE, TOP,
                '01_rtl/cnn_result_stabilizer.v', '01_rtl/cnn_core.v', 'lint_full.f'}
    require(set(data['input_sha256']) == expected, 'Legacy wrapper input closure differs')
    for relative, digest in data['input_sha256'].items():
        require(sha(ROOT / relative) == digest, 'Legacy wrapper input drift: ' + relative)
    return {**data['input_sha256'], WRAPPER_PREPARED: sha(path)}


def derived_fixture_pins():
    require = inherited._require
    renamed = (ROOT / PIPELINE).read_text().replace(
        'module vision_pipeline #(', 'module vision_pipeline_baseline #(').replace(
        '        cnn_result_stabilizer #(', '        cnn_result_stabilizer_baseline #(')
    original_domain = BASE / '02_sim/cnn_area_pipeline_compact/domain/prove_compact_area_domain.py'
    require(sha(original_domain) == '316487DCED53A37E6502746903F7F29A00C2F29A83BF44E0B61D2B803C47DF45',
            'Frozen successful domain script differs')
    before = original_domain.read_bytes()
    require(before.count(OLD_PIPELINE_SHA.encode('ascii')) == 1,
            'Domain script has unexpected production pipeline binding')
    domain = before.replace(OLD_PIPELINE_SHA.encode('ascii'), PIPELINE_SHA.encode('ascii'), 1)
    return {
        'pipeline_reference': {
            'relative': '02_sim/cnn_area_pipeline_compact/pipeline_miter/vision_pipeline_baseline.v',
            'original_sha256': '7876918A9EA2347E2E1791DCA47A30004462F8B536EECF81B3780BB8EE1233C3',
            'approved_sha256': hashlib.sha256(renamed.encode('utf-8')).hexdigest().upper(),
            'expected_bytes': renamed.encode('utf-8')},
        'domain_script': {
            'relative': '02_sim/cnn_area_pipeline_compact/domain/prove_compact_area_domain.py',
            'original_sha256': sha(original_domain),
            'approved_sha256': hashlib.sha256(domain).hexdigest().upper(),
            'expected_bytes': domain},
    }


def check(files, required=None):
    global LAST_AUDIT
    scope = top_scope()
    wrapper_inputs = wrapper_qualification()
    files = tuple(files)
    area_path = ROOT / '02_sim/cnn_area_pipeline_compact/RESULTS.json'
    inherited._require(area_path in {Path(p).resolve() for p in files},
                       'Missing fresh legacy area suite result')
    area = json.loads(area_path.read_text(encoding='utf-8-sig'))
    supplied = {Path(p).resolve(): digest for p, digest in area.get('input_hashes', {}).items()}
    inherited._require(all(supplied.get(ROOT / p) == digest for p, digest in wrapper_inputs.items()),
                       'Area suite omitted its exact wrapper/gate/preparation input closure')
    pins = dict(inherited.PINS)
    pins.update({TOP: TOP_SHA, PIPELINE: PIPELINE_SHA})
    derived = derived_fixture_pins()
    replacements = {}
    for item in derived.values():
        path = ROOT / item['relative']
        inherited._require(path.read_bytes() == item['expected_bytes'] and
                           sha(path) == item['approved_sha256'],
                           'Derived legacy fixture differs: ' + item['relative'])
        replacements[path] = item
    original_digest = inherited._digest

    def digest(path, expected):
        item = replacements.get(Path(path).resolve())
        if item is not None and expected == item['original_sha256']:
            return original_digest(path, item['approved_sha256'])
        return original_digest(path, expected)

    with mock.patch.object(inherited, 'PINS', pins), mock.patch.object(inherited, '_digest', digest):
        result = inherited.check(files, required)
    audit = dict(inherited.LAST_AUDIT)
    consumed = dict(audit['validated_file_sha256'])
    consumed[Path(__file__).resolve().relative_to(ROOT).as_posix()] = sha(__file__)
    audit['validated_file_sha256'] = consumed
    audit['configured_low_score_scope'] = scope
    LAST_AUDIT = audit
    return result


def evidence_manifest(files, required=None):
    check(files, required)
    return dict(LAST_AUDIT['validated_file_sha256'])
