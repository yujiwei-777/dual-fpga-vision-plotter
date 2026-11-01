"""Strict legacy seven-suite gate with one reviewed top parameter delta.

The inherited gate and all suite runners remain byte-identical. Only the top
pin is rebound while calling that gate, after byte-for-byte reconstruction of
the three explicitly zeroed shape thresholds from the successful baseline.
No other pin, suite contract, expected marker, or reference model is amended.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
from unittest import mock

import key3_stroke_regression_gate as inherited

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / 'secondary_cnn_key3_stroke_compact_20261101'
TOP = '01_rtl/secondary_top.v'
OLD_TOP_SHA = '64176506920BFF546415A1D1433FE1F6558FAAA565B5845FA826B56566694DCA'
TOP_SHA = '3E72FBEA76575DC277DAEFB75DFD213E502009F29B1F31C9F0EA23501ECA2B2E'
ANCHOR = b'vision_pipeline #(.EXTERNAL_READER(1),'
REPLACEMENT = (b'vision_pipeline #(.TRIANGLE_MARGIN_MIN(0),.CIRCLE_MARGIN_MIN(0),'
               b'.SQUARE_MARGIN_MIN(0),.EXTERNAL_READER(1),')
SUITES = inherited.SUITES
LAST_AUDIT = None


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def top_scope():
    require = inherited._require
    require(ROOT.name == 'secondary_doc_dirt_cnn_lowconf_20261101' and
            'work' not in {p.lower() for p in ROOT.resolve().parts},
            'Low-confidence gate is restricted to its independent root')
    old = BASE / TOP
    current = ROOT / TOP
    require(sha(old) == OLD_TOP_SHA and sha(current) == TOP_SHA,
            'Unreviewed low-confidence top source')
    before, after = old.read_bytes(), current.read_bytes()
    require(before.count(ANCHOR) == 1 and after == before.replace(ANCHOR, REPLACEMENT, 1),
            'Top changed beyond the three explicit u_vision shape thresholds')
    gate = Path(inherited.__file__).resolve()
    require(gate == ROOT / 'tools/key3_stroke_regression_gate.py' and
            sha(gate) == sha(BASE / 'tools/key3_stroke_regression_gate.py'),
            'Inherited strict seven-suite gate was modified')
    require(inherited.ROOT == ROOT and inherited.PINS.get(TOP) == OLD_TOP_SHA,
            'Inherited gate root/pin configuration was already overridden')
    return {
        'status': 'PASS_EXACT_THREE_TOP_MARGIN_PARAMETER_DELTA',
        'top': TOP, 'before': OLD_TOP_SHA, 'after': TOP_SHA,
        'parameters': {'TRIANGLE_MARGIN_MIN': 0, 'CIRCLE_MARGIN_MIN': 0,
                       'SQUARE_MARGIN_MIN': 0},
        'inherited_gate_sha256': sha(gate),
        'all_other_pins_and_seven_suite_contracts_unchanged': True,
    }


def check(files, required=None):
    global LAST_AUDIT
    scope = top_scope()
    pins = dict(inherited.PINS)
    pins[TOP] = TOP_SHA
    with mock.patch.object(inherited, 'PINS', pins):
        result = inherited.check(files, required)
    audit = dict(inherited.LAST_AUDIT)
    consumed = dict(audit['validated_file_sha256'])
    consumed[Path(__file__).resolve().relative_to(ROOT).as_posix()] = sha(__file__)
    audit['validated_file_sha256'] = consumed
    audit['top_parameter_scope'] = scope
    LAST_AUDIT = audit
    return result


def evidence_manifest(files, required=None):
    check(files, required)
    return dict(LAST_AUDIT['validated_file_sha256'])
