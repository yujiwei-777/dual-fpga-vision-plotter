"""Strict independent compact build with all reviewed release safety gates.

The successful control's auto/medium gate strategy is used. The V2 clock-trace
hook, original baseline/model closure, routed/readonly gates and bitgen checks
remain mandatory. Fresh current-root CNN and document proofs cannot be replaced
by the earlier local optimization reports. This module does not run on import.
"""
from __future__ import annotations

from pathlib import Path
import sys
import xml.etree.ElementTree as ET

import build_key3_stroke_release_controlmap as accepted
import key3_stroke_regression_gate as regressions

reviewed = accepted.reviewed
base = accepted.base
flow = accepted.flow
ROOT = accepted.ROOT
RUNS = 'cnn_key3_stroke_compact_Runs_20261101'
STEM = 'dual_fpga_secondary_20261101_cnn_key3_stroke_compact_diagnostic'
SELF = 'tools/build_key3_stroke_compact.py'
SYN_SUITES = {'cnn_named_top','key3_top_reset_release','stroke_release',
              'cnn_named_pcb','cnn_area_pipeline_compact'}
BIT_SUITES = SYN_SUITES | {'cnn_stability_core','cnn_named_report'}

_original_contract = base.production_contract
_original_active_scope = reviewed.active_scope_check
_original_validate_plan = flow.validate_plan
_original_bitgen = base.bitgen


def compact_dependencies():
    """Verified directed-proof files become explicit immutable run inputs."""
    proof = regressions.compact_metric_gate()
    evidence = regressions.compact_metric_evidence_manifest()
    # Production RTL already belongs to the active project closure, so do not
    # change its snapshot kind by re-adding it as an explicit dependency.
    proof_files = tuple(path for path in evidence if not path.startswith('01_rtl/'))
    runner_files = tuple('tools/'+value[0] for value in regressions.RUNNERS.values())
    extras = tuple(dict.fromkeys((*accepted.EXTRAS,SELF,
        base.scope.CREATION_MANIFEST,*runner_files,*proof_files)))
    return proof,evidence,extras


def production_contract():
    contract = _original_contract()
    scope = base.scope.compact_creation_check(ROOT.resolve())
    return {**contract,'compact_rtl_sha256':dict(base.scope.COMPACT_RTL),
        'PLANNER_OPT_PASSES':0,'EXTERNAL_METRIC':1,'METRIC_DISTANCE_BOUND':23164,
        'planner_generic_default':'FFFFFFFF','MAX_EDGES':32768,'MAX_PATHS':2048,
        'MAX_POINTS':8192,'creation_manifest_sha256':scope['creation_manifest_sha256']}


def active_scope_check(snapshot,baseline):
    result = _original_active_scope(snapshot,baseline)
    value = flow.load(snapshot) if isinstance(snapshot,(str,Path)) else snapshot
    proof,evidence,extras = compact_dependencies()
    entries = {}
    for item in value['files']:
        relative = flow.local(item['path']).relative_to(ROOT).as_posix()
        entries.setdefault(relative,[]).append(item)
    for relative in extras:
        selected = entries.get(relative,[])
        flow.require(len(selected) == 1 and selected[0]['kind'] == 'explicit_dependency' and
            selected[0]['sha256'].upper() == flow.sha(ROOT/relative),
            'Compact build/proof dependency is not explicitly frozen once: '+relative)
    return {**result,'compact_build_dependencies':{
        'status':'PASS_CURRENT_EXPLICIT_BUILD_AND_DIRECTED_PROOF_CLOSURE',
        'extras_sha256':{path:flow.sha(ROOT/path) for path in extras},
        'metric_proof':proof,'metric_evidence_sha256':evidence}}


def prepare(args,runs):
    flow.require(ROOT.name == base.scope.COMPACT_NAME and runs == ROOT/RUNS,
        'Compact builder is locked to the independent compact root/run')
    flow.require(not runs.exists(),'Fresh compact run directory required')
    proof,evidence,extras = compact_dependencies()
    flow.require(base.EXTRAS == extras,'Compact explicit-dependency set changed after installation')
    accepted.prepare(args,runs)
    plan_path = runs/'BUILD_PLAN.json'
    plan = flow.load(plan_path)
    plan['compact_release'] = {
        'creation_manifest':base.scope.CREATION_MANIFEST,
        'creation_manifest_sha256':base.scope.CREATION_MANIFEST_SHA,
        'reviewed_release_rtl_delta':{name:{'before':values[0],'after':values[1]}
            for name,values in base.scope.COMPACT_RTL.items()},
        'current_metric_boundary_proof':proof,
        'current_metric_evidence_sha256':evidence,
        'candidate_local_reports_are_physical_acceptance':False,
        'required_synthesis_suites':sorted(SYN_SUITES),
        'required_bitgen_suites':sorted(BIT_SUITES),
        'hardware_status':'NOT_RUN'}
    plan['mapping_experiment'].update(
        rtl_changed_from_clockproof=True,constraints_changed_from_clockproof=False,
        rtl_candidate='metadata predicate sharing; exact bounded metric storage; nonzero-step flag',
        production_contract=production_contract())
    flow.save(plan_path,plan)


def validate_plan(runs):
    # Recheck directed proof before every synthesis, route, readonly or bitgen
    # action. The original validator rechecks all frozen sources and flow bytes.
    proof,evidence,_ = compact_dependencies()
    plan = _original_validate_plan(runs)
    compact = plan.get('compact_release',{})
    flow.require(compact.get('creation_manifest_sha256') == base.scope.CREATION_MANIFEST_SHA and
        compact.get('current_metric_boundary_proof') == proof and
        compact.get('current_metric_evidence_sha256') == evidence,
        'Compact directed proof changed after preparation')
    return plan


def bitgen(args,runs):
    validate_plan(runs)
    # The inherited bitgen checks all seven fresh suites, current route timing,
    # resources, physical proof and readonly reimport before invoking TD bitgen.
    _original_bitgen(args,runs)
    build_path = ROOT/'artifacts'/(args.stem+'_BUILD.json')
    data = flow.load(build_path)
    plan = flow.load(runs/'BUILD_PLAN.json')
    data['compact_release'] = plan['compact_release']
    data['compact_production_contract'] = production_contract()
    data['mapping_strategy'] = {'map_mode':'auto','pack_effort':'medium','map_strategy':1,
        'add_map_lut_struct':'TOOL_DEFAULT_NO_OVERRIDE'}
    flow.save(build_path,data)


def install():
    # Bind the existing reviewed stack first, then replace only compact root/run
    # metadata, source qualification and the additional current-proof closure.
    accepted.install()
    proof,evidence,extras = compact_dependencies()
    accepted.RUNS = base.RUNS = flow.RUNS = RUNS
    accepted.EXTRAS = base.EXTRAS = extras
    base.STEM = flow.STEM = STEM
    base.production_contract = flow.production_grid_contract = production_contract
    base.active_scope_check = flow.active_scope_check = active_scope_check
    flow.REQUIRED_SYN_TESTS = SYN_SUITES
    flow.REQUIRED_BIT_TESTS = BIT_SUITES
    flow.prepare = prepare
    flow.validate_plan = validate_plan
    flow.bitgen = bitgen


if __name__ == '__main__':
    try:
        install()
        raise SystemExit(flow.main())
    except (OSError,ValueError,KeyError,RuntimeError,AssertionError,ET.ParseError) as error:
        print('BUILD_KEY3_STROKE_COMPACT_FAIL:',error,file=sys.stderr)
        raise SystemExit(1)
