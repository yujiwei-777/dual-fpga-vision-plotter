"""Audit physical-only continuation without inventing a new synthesis.

The parent's failed post-place proof is retained as failed evidence. Its hashed
checkpoint is merely an input to a new, real reproof/route/readonly execution.
No TD invocation, build mutation, timestamp adjustment or marker creation occurs.
Use --pin-readonly after route and before the actual readonly tool invocation.

PHYSICAL_CONTINUATION.json schema is supplied by prepare_physical_r3.py:
parent, parent_artifacts, copied_parent_files, project_files, added_files,
phase_inheritance and phases. Invocation records bind script/log, execution
times and input_artifact_sha256/output_artifact_sha256 maps.
"""
from __future__ import annotations
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
SOURCE = HERE.parents[1]
BASE = SOURCE.parent / 'secondary_doc_dirt_lowconf_factored_20261101'
BASE_RUN = BASE / 'dirt_lowconf_factored_Runs_20261101'
NAME = 'secondary_cnn_multibox'
PARENT_MANIFEST = '92E737ED8B7D585AEAAC64346A130A2AA7A9F2077A70B14A8CE2D036506A57DB'
KEY3_HELPER = '1BC78BBA154413DC49E54617B72DC52C5F85A0AD9998712E6197268FA45C7C14'
LIMITS = {'slice': 95, 'eram': 90, 'dsp': 95}
OVERLAY_SHA256 = '31794B9B5E5E90BD33AA5A07E85B9BF6396342CD7B70D531500BFD3CC0FFFDF4'
FROZEN_OVERLAY_SHA256 = '14683618AEB5851F2D014C8C983E6B7EB0D5561D888AFCEBCB00A494E8EB8A0B'
OVERLAY_REVIEW_SHA256 = '5944F51BDD57E3815FF70DD024231573FBE4545F96D1DF4AE64DB8889521A199'


class PendingEvidence(Exception):
    pass


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def read(path):
    return Path(path).read_text(encoding='utf-8-sig', errors='replace')


def load(path):
    return json.loads(read(path))


def put(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def local(root, value):
    path = Path(value)
    path = (path if path.is_absolute() else root / path).resolve()
    require(path.is_relative_to(root) and 'work' not in {x.lower() for x in path.parts},
            'Evidence path escapes isolated build: ' + str(path))
    return path


def timing(text):
    values = {}
    for key in ('SWNS', 'STNS', 'HWNS', 'HTNS'):
        match = re.search(r'\b' + key + r':\s*([-+\d.]+)ns', text)
        require(match, 'Missing timing metric ' + key)
        values[key] = float(match[1])
    coverage = {}
    for mode in ('Max', 'Min'):
        rows = re.findall(r'^' + mode + r'\s+:.*?(\d+) Total Endpoints,\s+(\d+) Paths Analyzed', text, re.M)
        coverage[mode] = dict(groups=len(rows), endpoints=sum(int(a) for a, _ in rows),
                              paths=sum(int(b) for _, b in rows))
    require(all(x['endpoints'] > 0 and x['paths'] > 0 for x in coverage.values()),
            'Missing real setup/hold endpoint coverage')
    return values, coverage


def routed_timing(text):
    require(re.search(r'Confidence\s*:\s*Routed', text), 'Timing is not routed')
    require(re.search(r'Check Corner\s*:\s*Both \(Slow and Fast\)', text), 'Both corners absent')
    for corner in ('Slow', 'Fast'):
        require(re.search(r'^' + corner + r'\s*\|\s*yes\s+yes', text, re.M), corner + ' max/min absent')
    values, coverage = timing(text)
    require(all(v >= 0 for v in values.values()) and values['STNS'] == values['HTNS'] == 0,
            'Final setup/hold timing fails')
    return values, coverage


def resources(text):
    capacities = {}
    for match in re.finditer(r'^\s*#([A-Za-z_][A-Za-z_0-9 ]*?)\*?\s+(\d+)\s+out of\s+(\d+)\b', text, re.M):
        name = re.sub(r'\s+', '_', match[1].strip().lower())
        require(name not in capacities, 'Duplicate capacity ' + name)
        used, total = int(match[2]), int(match[3])
        require(total > 0 and 0 <= used <= total, 'Resource exceeds capacity ' + name)
        capacities[name] = dict(used=used, total=total)
    result = {}
    for name, limit in LIMITS.items():
        require(name in capacities, 'Missing resource ' + name)
        used, total = capacities[name]['used'], capacities[name]['total']
        result[name] = dict(used=used, total=total, percent=used * 100 / total,
                            strict_pass=used * 100 < total * limit)
        require(result[name]['strict_pass'], 'Strict resource gate fails ' + name)
    return result, capacities


def check_categories(text):
    return {label.strip(): int(n) for label, n in re.findall(
        r'^\d+\. checking (.*?)\((\d+)\) \((?:HIGH|MEDIUM)\)', text, re.M)}


def project_identity(parent, child):
    # TD emits nonstandard :: tag names. Apply the same reversible escaping
    # used by the frozen build parser, to both sides, before comparing XML.
    def xml(path):
        value = re.sub(r'&(?!#?\w+;)', '&amp;', read(path))
        value = re.sub(r'(<\/?[A-Za-z_][\w:]*)::', lambda m: m[1] + '_TD_DOUBLE_COLON_', value)
        return ET.fromstring(value)
    a, b = xml(parent), xml(child)
    old, new = a.attrib.pop('Path', None), b.attrib.pop('Path', None)
    require(old and new, 'Project root Path absent')
    def canonical(node):
        return (node.tag, sorted(node.attrib.items()), (node.text or '').strip(),
                tuple(canonical(x) for x in node))
    require(canonical(a) == canonical(b), 'Project change exceeds root Path: ' + str(child))
    require(Path(new).resolve() == child.parent.resolve(), 'Project Path points outside its own run')
    return dict(parent_path=old, child_path=new, logical_xml_equal=True)


class Audit:
    def __init__(self, build, parent, out):
        self.build, self.parent, self.out = build, parent, out
        self.evidence, self.checks, self.errors, self.pending = {}, {}, [], []
        self.continuation, self.manifest, self.invocations = None, None, {}

    def pin(self, path, expected=None):
        path = Path(path).resolve()
        digest = sha(path)
        require(expected is None or digest == expected.upper(), 'Hash differs: ' + str(path))
        self.evidence[str(path)] = digest
        return digest

    def text(self, path):
        self.pin(path)
        return read(path)

    def json(self, path):
        self.pin(path)
        return load(path)

    def perform(self, name, action):
        try:
            self.checks[name] = action()
        except PendingEvidence as exc:
            self.pending.append(name + ': ' + str(exc))
        except FileNotFoundError as exc:
            self.pending.append(name + ': ' + str(exc))
        except (OSError, ValueError, RuntimeError, KeyError, TypeError, AssertionError, ET.ParseError) as exc:
            self.errors.append(name + ': ' + str(exc))

    def freeze(self):
        build, parent = self.build, self.parent
        require(build != parent, 'Parent and child must be independent')
        self.pin(parent / 'SOURCE_MANIFEST.json', PARENT_MANIFEST)
        pm = self.json(parent / 'SOURCE_MANIFEST.json')['files']
        for rel, row in pm.items():
            self.pin(local(parent, rel), row['sha256'])
        self.manifest = self.json(build / 'SOURCE_MANIFEST.json')['files']
        plan = self.json(build / 'BUILD_PLAN.json')
        self.manifest_sha = self.pin(build / 'SOURCE_MANIFEST.json', plan['source_manifest_sha256'])
        require(Path(plan['build_root']).resolve() == build, 'Build plan belongs to another root')
        require(plan['status'] == 'PHYSICAL_ONLY_CONTINUATION' and plan['synthesis'] == 'INHERITED_NOT_RERUN',
                'Continuation must explicitly inherit synthesis')
        for rel, row in self.manifest.items():
            self.pin(local(build, rel), row['sha256'])
        c = self.json(build / 'PHYSICAL_CONTINUATION.json')
        require(c['schema_version'] == 1 and Path(c['parent']['build_root']).resolve() == parent and
                c['parent']['source_manifest_sha256'] == PARENT_MANIFEST, 'Wrong parent continuation binding')
        require(c['phase_inheritance'] == {'syn': 'INHERITED',
                'place_checkpoint': 'INHERITED_FAILED_POST_PLACE_PROOF'}, 'Inheritance semantics differ')
        require(c['ordinary_cnn_or_model_change'] is False and c['numeric_constraint_change'] is False,
                'Functional or numeric timing changes require a new build')
        copied, projects = c['copied_parent_files'], c['project_files']
        require(not set(copied) & set(projects) and set(copied) | set(projects) == set(pm),
                'Every parent frozen file must be accounted for exactly once')
        identities = {}
        for rel, row in copied.items():
            require(row['sha256'] == pm[rel]['sha256'], 'Inherited input digest differs ' + rel)
            self.pin(local(build, rel), pm[rel]['sha256'])
        for rel, row in projects.items():
            require(Path(rel).suffix in {'.al', '.prj'} and row['allowed_change'] == 'project_root_only',
                    'Unapproved project delta ' + rel)
            self.pin(local(parent, rel), row['parent_sha256'])
            require(row['parent_sha256'] == pm[rel]['sha256'], 'Project parent digest differs')
            self.pin(local(build, rel), row['sha256'])
            identities[rel] = project_identity(parent / rel, build / rel)
        added = c['added_files']
        require('physical_proof/cdc_cal_lut5a.tcl' in added, 'Narrow packed-decode override is absent')
        frozen_overlay = build / 'physical_proof/cdc_cal_lut5a.tcl'
        self.pin(frozen_overlay, FROZEN_OVERLAY_SHA256)
        review = self.json(HERE / 'cdc_mapping_review/REVIEW.json')
        self.pin(HERE / 'cdc_mapping_review/REVIEW.json', OVERLAY_REVIEW_SHA256)
        require(review['status'] == 'PASS_NARROW_HELPER_REVIEW_AND_FAULT_INJECTION' and
                review['overlay_sha256'] == OVERLAY_SHA256 and
                review['tests']['passed'] == 21 and review['tests']['failed'] == 0, 'Narrow override review failed')
        for path, digest in review['source_sha256'].items():
            self.pin(Path(path), digest)
        reviewed_overlay = HERE / 'cdc_mapping_review/calibrated_lut5a_override.tcl'
        self.pin(reviewed_overlay, OVERLAY_SHA256)
        # prepare.add used Windows text writing. Preserve both original bytes
        # and hashes and accept exactly the audited LF -> CRLF conversion.
        require(frozen_overlay.read_bytes() == reviewed_overlay.read_bytes().replace(b'\n', b'\r\n'),
                'Frozen override differs beyond recorded LF-to-CRLF conversion')
        self.pin(Path(review['tests']['log_path']), review['tests']['log_sha256'])
        for rel, row in added.items():
            require(rel not in pm and rel in self.manifest and bool(row['purpose']), 'Untracked added input ' + rel)
            self.pin(local(build, rel), row['sha256'])
        required = {'logs/syn.json', 'logs/syn.log', 'SYNTHESIS_REVIEW.json',
            'runs/syn_1/' + NAME + '_gate.db', 'runs/phy_1/' + NAME + '_place_checkpoint.db',
            'logs/place.json', 'logs/place.log'}
        artifacts = c['parent_artifacts']
        require(required <= set(artifacts), 'Parent synthesis/checkpoint evidence incomplete')
        for rel, row in artifacts.items():
            self.pin(local(parent, rel), row['sha256'])
            target = local(build, row['copy'])
            require(target.relative_to(build).as_posix() in self.manifest, 'Inherited evidence not frozen')
            self.pin(target, row['sha256'])
        accounted = set(pm) | set(added) | {r['copy'] for r in artifacts.values()} | {'PHYSICAL_CONTINUATION.json'}
        require(set(self.manifest) == accounted, 'Unexplained child frozen manifest entries')
        syn = self.json(parent / 'logs/syn.json')
        require(syn['status'] == 'PASS_TOOL_INVOCATION' and syn['exit_code'] == 0 and not syn['errors'],
                'Parent synthesis was not successful')
        self.pin(parent / 'logs/syn.log', syn['log_sha256'])
        self.pin(parent / 'runs/syn_1/run.tcl', syn['script_sha256'])
        review = self.json(parent / 'SYNTHESIS_REVIEW.json')
        require(not review['illegal_logic_evidence'], 'Parent synthesis had illegal logic')
        resources(self.text(parent / ('runs/syn_1/' + NAME + '_gate.area')))
        failed = self.json(parent / 'logs/place.json')
        require(failed['status'] == 'FAILED_TOOL_INVOCATION' and failed['errors'] == [
            'SECONDARY_CDC_MAPPING_ERROR place_end u_store/cal_sync_reg[0]_syn_2 REGA_SD requires IMA'],
            'Parent failure differs from the reviewed post-place mapping-helper limitation')
        self.pin(parent / 'logs/place.log', failed['log_sha256'])
        self.continuation = c
        return dict(parent_manifest_sha256=PARENT_MANIFEST, entries=len(self.manifest),
                    copied_parent_files=len(copied), project_identity=identities,
                    synthesis='INHERITED_NOT_RERUN', parent_place_status=failed['status'],
                    parent_place_is_not_claimed_as_pass=True,
                    overlay_review_sha256=OVERLAY_REVIEW_SHA256,
                    overlay_source_sha256=OVERLAY_SHA256, frozen_overlay_sha256=FROZEN_OVERLAY_SHA256,
                    overlay_copy_delta='Only LF to CRLF; exact bytes compared')

    def invocation(self, phase):
        row = self.continuation['phases'][phase]
        script, logfile, invocation = [local(self.build, row[k]) for k in ('script', 'log', 'invocation')]
        relative = script.relative_to(self.build).as_posix()
        require(relative in self.continuation['added_files'], 'Executed script was not separately frozen')
        record = self.json(invocation)
        if record.get('status') == 'RUNNING':
            raise PendingEvidence('Actual tool invocation still running: ' + phase)
        require(record['phase'] == phase and record['status'] == 'PASS_TOOL_INVOCATION' and
                record['exit_code'] == 0 and not record.get('errors'), 'Actual phase failed ' + phase)
        require(isinstance(record['started_ns'], int) and record['finished_ns'] >= record['started_ns'],
                'Actual invocation timestamps absent')
        self.pin(script, record['script_sha256'])
        self.pin(logfile, record['log_sha256'])
        cwd = local(self.build, record['cwd'])
        require(cwd == script.parent, 'Invocation cwd differs from script directory')
        command = record['command']
        require(len(command) == 2 and Path(command[0]).name.lower() == 'td_commands_prompt.exe' and
                local(cwd, command[1]) == script, 'Invocation command does not identify TD/script')
        input_path = self.build / ('inherited/r2/runs/phy_1/' + NAME + '_place_checkpoint.db') if phase == 'resume_place' else self.build / ('runs/phy_1/' + NAME + ('_place.db' if phase == 'route' else '_pr.db'))
        output_path = self.build / ('runs/phy_1/' + NAME + ('_place.db' if phase == 'resume_place' else '_pr.db'))
        for field, expected in [('input_artifact_sha256', input_path), ('output_artifact_sha256', output_path)]:
            mapping = record[field]
            require(len(mapping) == 1, 'Invocation must bind exactly one stage database ' + phase)
            path, digest = next(iter(mapping.items()))
            require(local(self.build, path) == expected.resolve(), 'Wrong phase database ' + phase)
            self.pin(expected, digest)
        if phase == 'readonly':
            require(list(record['input_artifact_sha256'].values()) == list(record['output_artifact_sha256'].values()),
                    'Readonly changed database')
        self.invocations[phase] = record
        return record

    def physical(self, key3):
        build, parent = self.build, self.parent
        phy = build / 'runs/phy_1'
        resume, route = self.invocation('resume_place'), self.invocation('route')
        require(route['started_ns'] >= resume['finished_ns'], 'Route precedes checkpoint reproof')
        for directory in (phy, build / 'readonly'):
            require(not (directory / '.stop.f').exists() and not list(directory.glob('.*.error.f')),
                    'Current physical continuation failed/stopped')
        values, coverage = routed_timing(self.text(phy / (NAME + '_pr.timing')))
        res, capacities = resources(self.text(phy / (NAME + '_phy.area')))
        flow = self.text(phy / 'route_flow.status')
        require(re.search(r'Timing Mode\s*:\s*final', flow) and
                re.search(r'^\s*route\s*\|\s*[1-9]\d*\s*\|', flow, re.M), 'No actual final route')
        return dict(timing_ns=values, coverage=coverage, resources=res, reported_capacity=capacities,
                    database_sha256=self.pin(phy / (NAME + '_pr.db')))

    def proofs(self, key3):
        phy = self.build / 'runs/phy_1'
        phases = {}
        for phase in ('place_end', 'route_begin', 'route_end'):
            phases[phase] = key3.verify_key3(self.text(phy / ('secondary_key3_' + phase + '.rpt')), phase)
        calibration = {}
        for phase in ('place_end', 'route_begin', 'route_end'):
            report = self.text(phy / ('secondary_cdc_' + phase + '.rpt'))
            matches = [line for line in report.splitlines() if line.startswith('MAILBOX_CONTROL FIRST=logical {u_store/cal_sync[0]} ')]
            require(len(matches) == 1 and matches[0].count(' SECOND=') == 1, 'Calibration synchronizer proof absent/duplicated')
            first, second = matches[0].split(' SECOND=', 1)
            def dictionary(value):
                words = key3.tcl_list(value)
                require(len(words) % 2 == 0, 'Malformed runtime Tcl dictionary')
                result = dict(zip(words[::2], words[1::2]))
                require(len(result) * 2 == len(words), 'Duplicate runtime proof keys')
                return result
            first = dictionary(first.removeprefix('MAILBOX_CONTROL FIRST='))
            second = dictionary(second)
            require(first['logical'] == 'u_store/cal_sync[0]' and second['logical'] == 'u_store/cal_sync[1]',
                    'Wrong calibration logical stages')
            require(first['data_select'] == 'REGA_SD=LUT5A' and
                    first['d_role'] == 'SELECTED_LUT_OUTPUT_OBSERVATION_ONLY', 'Packed decoder selection/role unproven')
            require(first['d'] == first['q'].removesuffix('.oqa') + '.ofa' and first['q'].endswith('.oqa'),
                    'Packed decoder observation is not the first FF selected LUT')
            proof = first['data_proof']
            require(proof.startswith('CALIBRATED_DECODE_PROVEN CAL_EN=0 S_DONE=01111 ') and
                    '00000000000000010000000000000000' in proof and 'SUPPORT=A B C D E' in proof,
                    'Exact five-bit decoder truth proof absent')
            require(all('state_cnt[' + str(n) + ']' in proof for n in range(5)), 'Decoder state inputs incomplete')
            require(second['d'].endswith(('.ima', '.imb')) and second['dnet'] == first['net'] and
                    second['clk'] == first['clk'] and second['reset'] == first['reset'],
                    'Calibration second stage no longer uses direct first-stage output/clock/reset')
            calibration[phase] = dict(first=first, second=second)
        loaded = self.text(phy / 'secondary_loaded_route_end.rpt')
        for tag, name in [('EXACT_SDC', 'secondary_exact_route_end.sdc'),
                          ('EFFECTIVE_SDC', 'secondary_effective_route_end.sdc')]:
            matches = re.findall(r'^' + tag + r' (.+)$', loaded, re.M)
            require(len(matches) == 1 and local(self.build, matches[0]) == phy / name,
                    'Loaded SDC points to a different physical run')
        names = ['secondary_reset_route_end.rpt', 'secondary_reset_route_end.sdc',
                 'secondary_cdc_route_end.rpt', 'secondary_cdc_route_end.sdc',
                 'secondary_exact_route_end.sdc', 'secondary_effective_route_end.sdc',
                 'secondary_effective_route_end.ignored.rpt']
        texts = {name: self.text(phy / name) for name in names}
        effective = texts['secondary_effective_route_end.sdc']
        require(key3.commands(effective).count(key3.KEY3_COMMAND) == 1, 'KEY3 first-stage exception differs')
        stage2 = phases['route_end']['stages']['SYNC']
        for command in key3.commands(effective):
            if not command.startswith(('set_false_path ', 'set_max_delay ')):
                continue
            for role, kind, pins in key3.selectors(command):
                require(not (role == '-to' and ((kind == 'get_pins' and stage2['D'] in pins) or
                    (kind == 'get_regs' and 'u_board_reset/key_sync' in pins))), 'KEY3 stage two must remain timed')
        resets = key3.verify_resets(texts[names[0]], texts[names[1]], texts[names[4]], effective,
            texts[names[6]], loaded, phases['route_end']['supervisor']['OUTPUT_NET'])
        cdc = key3.verify_cdc(texts[names[2]], texts[names[3]], texts[names[4]], effective)
        require('u_store/cal_sync[0]' in cdc['control_regs'] and
                calibration['route_end']['second']['d'] in cdc['stage2_d'], 'Calibration endpoint inventory differs')
        for command in key3.commands(effective):
            if command.startswith(('set_false_path ', 'set_max_delay ')):
                for role, kind, pins in key3.selectors(command):
                    require(not (role == '-to' and kind == 'get_pins' and calibration['route_end']['first']['d'] in pins),
                            'Observation-only OFA was incorrectly used as timing destination')
        require('EFFECTIVE_SMD_PATHS 290 128 9 52' in loaded, 'Effective CDC path counts changed')
        return dict(database_sha256=self.pin(phy / (NAME + '_pr.db')), key3_phases=phases,
                    reset_proof=resets, cdc_actual_endpoint_groups=cdc, calibrated_lut5a_proof=calibration,
                    scope='Actual continuation mapping proof; no fresh synthesis/place claim')

    def gate_proofs(self, key3):
        syn = self.parent / 'runs/syn_1'
        q = key3.verify_key3(self.text(syn / 'secondary_key3_gate.rpt'), 'gate')
        groups = key3.verify_cdc(*[self.text(syn / name) for name in ['secondary_cdc_gate.rpt',
            'secondary_cdc_gate.sdc', 'secondary_exact_gate.sdc', 'secondary_effective_gate.sdc']])
        return dict(synthesis='INHERITED_NOT_RERUN', key3_registers=len(q['registers']),
                    cdc_groups={k: len(v) for k, v in groups.items()})

    def drc(self):
        phy = self.build / 'runs/phy_1'
        current = check_categories(self.text(phy / (NAME + '_chk.timing')))
        accepted = check_categories(self.text(BASE_RUN / 'phy_1' / (NAME + '_chk.timing')))
        require(current and set(current) == set(accepted), 'Timing-check category set differs')
        require(not {k: v for k, v in current.items() if v > accepted[k]}, 'New/increased timing-check categories')
        physical = ''.join(self.text(local(self.build, self.continuation['phases'][p]['log'])) for p in ('resume_place', 'route'))
        syn = self.text(self.parent / 'logs/syn.log')
        for code in ('HDL-5105', 'RTCLK-5078', 'USR-6113'):
            require(code not in physical + syn, 'Forbidden ROM/clock diagnostic ' + code)
        require(not re.search(r'(?:[A-Z]+-\d+\s*(?:ERROR|FATAL)|\bBUILD_FAILED\b|MAPPING_ERROR|^\s*(?:ERROR|FATAL)\s*[:\[])',
                              physical + syn, re.M), 'Fatal tool diagnostic')
        old = self.text(BASE_RUN / 'phy_1/td_console.log')
        inherited_place = self.text(self.parent / 'logs/place.log')
        require('Report DRC' in inherited_place and 'End Stage 8 | DRC Check;' in inherited_place,
                'Inherited checkpoint lacks actual placement DRC execution')
        route_log = self.text(local(self.build, self.continuation['phases']['route']['log']))
        route_checkers = ['Check And Add Lut-bridge', 'Run Pin Swap Checker', 'Run Net Connection Checker',
            'Run Lut Bridge Checker', 'Run Multi Drive Checker', 'Run Clock Status Checker',
            'Run Abnormal Path Checker', 'Run Route Region Checker', 'Run Bound Checker']
        require('End Stage 5 | Design Rule Check;' in route_log, 'Current route DRC did not complete')
        for index, checker in enumerate(route_checkers, 1):
            require('End Stage 5.' + str(index) + ' | ' + checker + ';' in route_log,
                    'Current route checker did not complete: ' + checker)
        # Placement DRC belongs to the inherited, hash-pinned checkpoint;
        # route DRC is a separate actual continuation execution. Neither
        # is mislabeled as a fresh placement in the child build.
        drc_text = inherited_place + '\n' + physical
        counts, old_counts = Counter(re.findall(r'DRC ([A-Z]+-\d+)', drc_text)), Counter(re.findall(r'DRC ([A-Z]+-\d+)', old))
        require(not {k: v for k, v in counts.items() if v > old_counts.get(k, 0)}, 'New/increased DRC code')
        lines = Counter(x.strip() for x in drc_text.splitlines() if x.startswith('DRC '))
        before = Counter(x.strip() for x in old.splitlines() if x.startswith('DRC '))
        require(not lines - before, 'New DRC target/meaning requires review')
        for rel in ['main/user_source/hdl_source/ethernet/uiip_tx.v', 'main/user_source/hdl_source/ethernet/uimac_tx.v']:
            require(self.pin(self.build / rel) == self.pin(BASE / rel), 'Inherited shifter source differs')
        return dict(timing_check=current, accepted_timing_check=accepted, drc=dict(counts),
                    accepted_drc=dict(old_counts), exact_inherited_drc_lines=dict(lines),
                    inherited_place_drc='Hash-pinned r2 actual place DRC before saved checkpoint/proof failure',
                    current_route_completed_checkers=route_checkers)

    def ddr(self):
        protected = self.json(self.parent / 'BUILD_PLAN.json')['original_vendor_flow']['protected_constraint_ip_sha256']
        for rel, digest in protected.items():
            self.pin(self.build / rel, digest)
        snapshot = self.json(self.parent / 'runs/syn_1/source_snapshot.json')
        refs = [r for r in snapshot['memory_references'] if r['literal'] == 'ddrphy_cfg_rom.txt']
        require(len(refs) == 1 and refs[0]['resolved'], 'DDR ROM resolution absent')
        digests = {self.pin(Path(p)) for p in refs[0]['resolved']}
        require(len(digests) == 1, 'DDR ROM aliases differ')
        log = self.text(self.parent / 'logs/syn.log')
        require('ph1p_ddrphy_init(ROM_LEN=45,ROM_INIT="ddrphy_cfg_rom.txt")' in log, 'DDR init elaboration binding absent')
        return dict(protected_entries=len(protected), rom=refs[0], rom_sha256=next(iter(digests)),
                    synthesis='INHERITED_NOT_RERUN', hardware_status='NOT_RUN')

    def pin_readonly(self):
        self.invocation('resume_place')
        self.invocation('route')
        phy = self.build / 'runs/phy_1'
        routed_timing(self.text(phy / (NAME + '_pr.timing')))
        resources(self.text(phy / (NAME + '_phy.area')))
        path = self.out / 'READONLY_INPUT_PINS_R3.json'
        require(not path.exists(), 'Refusing overwrite of readonly input pins')
        row = self.continuation['phases']['readonly']
        require(not local(self.build, row['log']).exists() and not local(self.build, row['invocation']).exists(),
                'Readonly pins must precede actual readonly invocation')
        paths = [phy / (NAME + '_pr.db'), phy / (NAME + '.al'), local(self.build, row['script']),
                 phy / (NAME + '_pr.timing'), phy / (NAME + '_phy.area')]
        put(path, dict(source_manifest_sha256=self.manifest_sha, generated_utc=datetime.now(timezone.utc).isoformat(),
                       files={str(p): self.pin(p) for p in paths}))
        return dict(path=str(path), sha256=sha(path))

    def readonly(self):
        pins = self.json(self.out / 'READONLY_INPUT_PINS_R3.json')
        require(pins['source_manifest_sha256'] == self.manifest_sha, 'Readonly pins bind another manifest')
        for path, digest in pins['files'].items():
            self.pin(local(self.build, path), digest)
        record = self.invocation('readonly')
        require(record['started_ns'] >= self.invocations['route']['finished_ns'], 'Readonly precedes route completion')
        require(datetime.fromisoformat(pins['generated_utc']).timestamp() * 1e9 <= record['started_ns'],
                'Readonly pin record postdates the actual invocation')
        phy, ro = self.build / 'runs/phy_1', self.build / 'readonly'
        values, coverage = routed_timing(self.text(ro / 'readonly.timing'))
        route_values, _ = routed_timing(self.text(phy / (NAME + '_pr.timing')))
        require(values == route_values, 'Readonly timing differs')
        require(resources(self.text(ro / 'readonly.area')) == resources(self.text(phy / (NAME + '_phy.area'))),
                'Readonly resources differ')
        require(check_categories(self.text(ro / 'readonly.check')) == check_categories(self.text(phy / (NAME + '_chk.timing'))),
                'Readonly check_timing differs')
        for name in ('readonly.ts', 'readonly.exceptions', 'readonly.clocks', 'readonly.flow'):
            self.text(ro / name)
        log = self.text(local(self.build, self.continuation['phases']['readonly']['log']))
        require('TD_READONLY_REIMPORT_PASS' in log, 'Readonly tool did not pass')
        return dict(status='PASS_INPUTS_AND_REPORTS_MATCH', timing_ns=values, coverage=coverage,
                    database_sha256=self.pin(phy / (NAME + '_pr.db')))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, default=Path('E:/codex_pcb_binary_ccl_retrained_20261102_r3'))
    parser.add_argument('--parent', type=Path, default=Path('E:/codex_pcb_binary_ccl_retrained_20261102_r2'))
    parser.add_argument('--output-dir', type=Path, default=HERE / 'physical_gate_r3')
    parser.add_argument('--pin-readonly', action='store_true')
    parser.add_argument('--require-complete', action='store_true')
    args = parser.parse_args()
    build, parent, out = args.build.resolve(), args.parent.resolve(), args.output_dir.resolve()
    require('work' not in {x.lower() for x in build.parts + parent.parts + out.parts}, 'Protected backup path forbidden')
    require(not out.is_relative_to(build) and not out.is_relative_to(parent), 'Audit outputs must stay outside frozen builds')
    out.mkdir(parents=True, exist_ok=True)
    a = Audit(build, parent, out)
    a.pin(Path(__file__))
    a.perform('freeze', a.freeze)
    if a.continuation is not None:
        helper = BASE / 'tools/key3_physical_gate.py'
        a.pin(helper, KEY3_HELPER)
        spec = importlib.util.spec_from_file_location('baseline_key3_r3_review', helper)
        key3 = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(key3)
        if args.pin_readonly:
            a.perform('readonly_input_pins', a.pin_readonly)
        else:
            a.perform('gate_proofs', lambda: a.gate_proofs(key3))
            a.perform('final_routed', lambda: a.physical(key3))
            a.perform('reset_cdc', lambda: a.proofs(key3))
            a.perform('timing_check_drc', a.drc)
            a.perform('ddr_identity', a.ddr)
            a.perform('readonly', a.readonly)
    required = {'freeze', 'readonly_input_pins'} if args.pin_readonly else {
        'freeze', 'gate_proofs', 'final_routed', 'reset_cdc', 'timing_check_drc', 'ddr_identity', 'readonly'}
    missing = sorted(required - set(a.checks))
    complete = not a.errors and not a.pending and not missing
    result = dict(status='REVIEW_REQUIRED' if a.errors else (('PASS_READONLY_INPUT_PINS' if args.pin_readonly else 'PASS_PHYSICAL_SUPPLEMENT') if complete else 'PENDING_PHYSICAL'),
        generated_utc=datetime.now(timezone.utc).isoformat(), source_manifest_sha256=getattr(a, 'manifest_sha', None),
        parent_source_manifest_sha256=PARENT_MANIFEST, build_root=str(build), parent_root=str(parent),
        checks=a.checks, errors=a.errors, pending=a.pending, missing_checks=missing, evidence_sha256=a.evidence,
        bitgen_allowed=False, hardware_status='NOT_RUN',
        scope='Physical-only continuation audit. Parent synthesis/checkpoint are inherited, parent failure retained. '
              'Functional evidence must separately prove exact RTL/model identity; board acceptance remains NOT_RUN.')
    report = out / ('READONLY_PIN_AUDIT_R3.json' if args.pin_readonly else 'PHYSICAL_REVIEW_R3.json')
    put(report, result)
    print(json.dumps({k: result[k] for k in ('status', 'errors', 'pending', 'missing_checks', 'bitgen_allowed')}, indent=2))
    return int(bool(a.errors) or (args.require_complete and not complete))


if __name__ == '__main__':
    raise SystemExit(main())
