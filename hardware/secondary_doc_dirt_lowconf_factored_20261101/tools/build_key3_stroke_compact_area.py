"""Independent compact area-prior build using the original reviewed V2 flow.

The failed compact auto/medium run is never opened for mutation. Production
RTL, models, constraints, current-root regressions and metric proofs are the
same inputs. Only a new run uses area_prior/high/high mapping. All inherited
five-phase reset/CDC/KEY3, routed, readonly and bitgen gates remain mandatory.
No build is started on import.
"""
from __future__ import annotations

from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

import build_key3_stroke_compact as compact

reviewed=compact.reviewed
base=compact.base
flow=compact.flow
ROOT=compact.ROOT
RUNS='cnn_key3_stroke_compact_area_Runs_20261101'
STEM='dual_fpga_secondary_20261101_cnn_key3_stroke_compact_area_diagnostic'
SELF='tools/build_key3_stroke_compact_area.py'
STRATEGY={'map_mode':'area_prior','pack_effort':'high','add_map_lut_struct':'high',
          'map_strategy':'TOOL_DEFAULT_NO_OVERRIDE'}
PHASES=('gate','place_begin','place_end','route_begin','route_end')
_compact_validate=compact.validate_plan
_release_bitgen=compact._original_bitgen


def dependencies():
    proof,evidence,extras=compact.compact_dependencies()
    extras=tuple(dict.fromkeys((*extras,SELF)))
    return proof,evidence,extras


def identity(runs):
    flow.require(ROOT.name==base.scope.COMPACT_NAME and Path(runs).resolve()==ROOT/RUNS,
        'Area adapter is locked to the independent compact area run')


def flow_identity(runs):
    """Check actual generated scripts, rather than trusting strategy labels."""
    expected=[('add_map_lut_struct','high'),('map_mode','area_prior'),('pack_effort','high')]
    records={}
    for relative in ('syn_1/run.tcl','phy_1/run.tcl','phy_1/run_bitgen.tcl'):
        path=runs/relative
        text=flow.read(path)
        settings=re.findall(r'(?m)^\s*set_param gate (\w+) (\w+)\s*$',text)
        flow.require(settings==(expected if relative.startswith('syn_1/') else []),
            'Area run must retain original V2 area_prior/high/high settings: '+relative)
        timing=re.findall(r'(?m)^\s*secondary_apply_phase_timing (\w+) \{([^}]+)\} (\w+)\s*$',text)
        proof=re.findall(r'(?m)^\s*source \{([^}]*prove_key3_supervisor_clocktrace\.tcl)\}\s*\n\s*secondary_prove_key3_supervisor (\w+)\s*$',text)
        flow.require(tuple(item[0] for item in timing)==PHASES and tuple(item[1] for item in proof)==PHASES,
            'Area flow lost ordered five-phase reset/CDC/clocktrace checks: '+relative)
        flow.require(all((path.parent/item[1]).resolve()==ROOT/'04_pin/timing.sdc' for item in timing) and
            all((path.parent/item[0]).resolve()==ROOT/reviewed.CLOCKTRACE_HOOK for item in proof),
            'Area flow points outside current SDC/proof closure')
        flow.require(text.count('export_db ${prj_name}_mapped_before_proof.db')==1,
            'Area mapped checkpoint missing')
        records[relative]={'sha256':flow.sha(path),'gate_options':dict(settings),'proof_phases':list(PHASES)}
    return records


def provenance(proof,evidence):
    return {'creation_manifest':base.scope.CREATION_MANIFEST,
        'creation_manifest_sha256':base.scope.CREATION_MANIFEST_SHA,
        'reviewed_release_rtl_delta':{name:{'before':values[0],'after':values[1]}
            for name,values in base.scope.COMPACT_RTL.items()},
        'current_metric_boundary_proof':proof,'current_metric_evidence_sha256':evidence,
        'candidate_local_reports_are_physical_acceptance':False,
        'required_synthesis_suites':sorted(compact.SYN_SUITES),
        'required_bitgen_suites':sorted(compact.BIT_SUITES),'hardware_status':'NOT_RUN'}


def prepare(args,runs):
    identity(runs)
    flow.require(args.stem==STEM and not runs.exists(),'Fresh area run and exact area output identity required')
    proof,evidence,extras=dependencies()
    flow.require(base.EXTRAS==extras,'Area dependency set changed after installation')
    # This is the original reviewed V2 area prepare, whose captured release
    # prepare installs area_prior/high/high. Do not call compact.prepare or
    # controlmap.prepare, both of which intentionally implement auto/medium.
    reviewed.prepare(args,runs)
    generated=flow_identity(runs)
    path=runs/'BUILD_PLAN.json'
    plan=flow.load(path)
    plan['compact_release']=provenance(proof,evidence)
    plan['compact_area_release']={'adapter':SELF,'adapter_sha256':flow.sha(ROOT/SELF),
        'runs':RUNS,'stem':STEM,'strategy':dict(STRATEGY),'generated_flow_identity':generated,
        'prepare_implementation':'reviewed V2 original area-prior release flow',
        'failed_controlmap_run_unchanged':compact.RUNS,'hardware_status':'NOT_RUN'}
    plan['mapping_experiment'].update(gate_map_mode='area_prior',gate_pack_effort='high',
        gate_add_map_lut_struct='high',gate_map_strategy='TOOL_DEFAULT_NO_OVERRIDE',
        rtl_changed_from_clockproof=True,constraints_changed_from_clockproof=False,
        rtl_candidate='metadata predicate sharing; exact bounded metric storage; nonzero-step flag',
        production_contract=compact.production_contract())
    flow.save(path,plan)


def validate_plan(runs):
    identity(runs)
    plan=_compact_validate(runs)
    proof,evidence,extras=dependencies()
    area=plan.get('compact_area_release',{})
    flow.require(area.get('adapter')==SELF and area.get('adapter_sha256')==flow.sha(ROOT/SELF) and
        area.get('runs')==RUNS and area.get('stem')==STEM and area.get('strategy')==STRATEGY and
        area.get('hardware_status')=='NOT_RUN','Frozen area adapter/run/output/strategy identity differs')
    flow.require(plan.get('compact_release')==provenance(proof,evidence),'Frozen compact provenance changed')
    mapping=plan.get('mapping_experiment',{})
    flow.require((mapping.get('gate_map_mode'),mapping.get('gate_pack_effort'),
        mapping.get('gate_add_map_lut_struct'),mapping.get('gate_map_strategy'))==
        ('area_prior','high','high','TOOL_DEFAULT_NO_OVERRIDE'),'Frozen area mapping metadata differs')
    flow.require(area.get('generated_flow_identity')==flow_identity(runs),'Frozen area flow semantics changed')
    # _compact_validate -> original validator verifies all syn snapshot bytes
    # and complete explicit dependencies. Also bind the area adapter in both
    # phase snapshots; the original reviewed V2 prepare already sealed them.
    for phase in ('syn_1','phy_1'):
        snapshot=flow.load(runs/phase/'source_snapshot.json')
        compact.active_scope_check(snapshot,flow.baseline_check())
        selected=[item for item in snapshot['files'] if flow.local(item['path'])==ROOT/SELF]
        flow.require(len(selected)==1 and selected[0]['kind']=='explicit_dependency' and
            selected[0]['sha256']==flow.sha(ROOT/SELF),'Area adapter not explicitly frozen exactly once')
    return plan


def bitgen(args,runs):
    flow.require(args.stem==STEM,'Area bit output name cannot be overridden')
    plan=validate_plan(runs)
    # The original full release bitgen retains seven fresh suites, routed
    # resource/timing/DRC proofs, readonly reimport and normal bitgen checks.
    # Avoid compact.bitgen, whose final strategy annotation is auto/medium.
    _release_bitgen(args,runs)
    path=ROOT/'artifacts'/(STEM+'_BUILD.json')
    data=flow.load(path)
    data['compact_release']=plan['compact_release']
    data['compact_area_release']=plan['compact_area_release']
    data['compact_production_contract']=compact.production_contract()
    data['mapping_strategy']=dict(STRATEGY)
    flow.save(path,data)


def install():
    compact.install()
    proof,evidence,extras=dependencies()
    # compact.active_scope_check dynamically checks compact_dependencies;
    # updating accepted.EXTRAS keeps the new adapter in that same strict set.
    compact.accepted.EXTRAS=base.EXTRAS=extras
    compact.accepted.RUNS=base.RUNS=flow.RUNS=RUNS
    base.STEM=flow.STEM=STEM
    flow.prepare=prepare
    flow.validate_plan=validate_plan
    flow.bitgen=bitgen


if __name__=='__main__':
    try:
        install()
        raise SystemExit(flow.main())
    except (OSError,ValueError,KeyError,RuntimeError,AssertionError,ET.ParseError) as error:
        print('BUILD_KEY3_STROKE_COMPACT_AREA_FAIL:',error,file=sys.stderr)
        raise SystemExit(1)
