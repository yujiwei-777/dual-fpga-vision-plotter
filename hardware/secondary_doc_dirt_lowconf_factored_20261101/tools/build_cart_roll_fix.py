"""Frozen main-board build. Never invoke bitgen until every release gate passes.

Synthesized slice usage is only an estimate. Hard ERAM/DSP capacity prevents
implementation; release percentages are checked on the final routed design.
Regression JSON maps test names to PASS, accompanied by INPUTS.json (paths
relative to this workspace and SHA256 values) and <test>.log completion logs.
--audit supplies explicit routed timing coverage/reset/CDC/RGMII evidence;
missing evidence permits diagnostic placement/routing but never bitgen.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
NAME = 'main_cart_20260926_cart_roll_fixed'
REQUIRED_REGRESSIONS = (
    'cart_direct', 'cart_integrated', 'cart_denoise', 'reset_recovery',
    'production_720p', 'production_burst_stalls', 'style_alignment',
    'style_light_modes',
    'key3_controls', 'key3_video', 'hxa_integration', 'motion_sensitive',
    'luma_equivalence', 'udp_metadata_fifo', 'display_tone')
REQUIRED_TEST_INPUTS = tuple('main/user_source/hdl_source/isp/'+name for name in (
    'cartoon_96.v', 'style_transfer_96.v', 'denoise_96.v',
    'style_input_fifo.v', 'style_video_96.v', 'isp_luma_stat.v',
    'display_tone_96.v')) + (
    'main/user_source/hdl_source/style_controls.v',
    'main/user_source/hdl_source/pcb_teach_key.v',
    'main/user_source/hdl_source/isp/motion_region_select.v',
    'main/user_source/hdl_source/ethernet/udp_pkg_buf.v',
    'main/user_source/hdl_source/ethernet/uimac_rx.v',
    'main/user_source/hdl_source/ethernet/uimac_tx.v',
    'shared/rtl/hxa_main_link.v')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def freeze_regressions(out, regressions):
    """Keep evidence usable for diagnostics even when incomplete or stale."""
    dest = out/'regression_evidence'
    dest.mkdir()
    shutil.copy2(regressions, dest/'REGRESSIONS.json')
    results = json.loads(regressions.read_text(encoding='utf-8-sig'))
    hashes_file = regressions.parent/'INPUTS.json'
    if hashes_file.is_file():
        shutil.copy2(hashes_file, dest/'INPUTS.json')
        hashes = json.loads(hashes_file.read_text(encoding='utf-8-sig'))
        for raw_relative in hashes:
            relative = str(raw_relative).replace('\\', '/')
            source = (ROOT/relative).resolve()
            if not source.is_relative_to(ROOT) or not source.is_file():
                continue
            target = dest/'inputs'/relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    for name in REQUIRED_REGRESSIONS:
        log = regressions.parent/(name+'.log')
        if log.is_file(): shutil.copy2(log, dest/log.name)
    return results


def regression_errors(out, results):
    errors = []
    if not isinstance(results, dict) or not results:
        return ['regression mapping is empty or invalid']
    evidence = out/'regression_evidence'
    for name in REQUIRED_REGRESSIONS:
        if results.get(name) != 'PASS': errors.append(name+' missing or not PASS')
        log = evidence/(name+'.log')
        if not log.is_file():
            errors.append(name+' completion log missing')
            continue
        text = log.read_text(encoding='utf-8', errors='replace')
        if not re.search(r'\bPASS\b', text) or re.search(r'\*\* (?:Error|Fatal):|\bFAIL(?:ED)?\b', text):
            errors.append(name+' lacks clean PASS completion')
    if any(v != 'PASS' for v in results.values()): errors.append('regression bundle includes non-PASS result')
    manifest = evidence/'INPUTS.json'
    if not manifest.is_file(): return errors+['regression INPUTS.json missing']
    hashes = json.loads(manifest.read_text(encoding='utf-8-sig'))
    normalized_hashes = {str(k).replace('\\', '/'): v for k, v in hashes.items()}
    for relative in REQUIRED_TEST_INPUTS:
        if relative not in normalized_hashes: errors.append('untested RTL: '+relative)
    for relative, digest in normalized_hashes.items():
        recorded = (evidence/'inputs'/relative).resolve()
        if not recorded.is_relative_to(evidence.resolve()) or not recorded.is_file() or sha(recorded) != digest:
            errors.append('regression input changed/missing: '+relative)
            continue
        built = (out/relative).resolve()
        if built.is_relative_to(out) and built.is_file() and sha(built) != digest:
            errors.append('regression input differs from build: '+relative)
    return errors


def audit_errors(out, audit):
    """Audit claims must refer to this routed database and actual reports.

    Schema 1: input_manifest_sha256, routed_db_sha256, timing_sha256;
    checks timing_coverage/reset_mapping/cdc/rgmii_dual_edge each contain
    status="PASS", reports=[{"path":<relative to build>,"sha256":...}].
    Their numeric fields below must explicitly be zero. RGMII also records
    covered endpoints as RX/TX:<port>:rise/fall:setup/hold (40 unique checks).
    A global WNS/TNS summary alone is not a coverage or CDC audit.
    """
    if audit is None or not audit.is_file(): return ['release audit missing; diagnostic route only']
    record = json.loads(audit.read_text(encoding='utf-8-sig'))
    errors = []
    if record.get('schema_version') != 1: errors.append('audit schema_version must be 1')
    bindings = {'input_manifest_sha256':out/'INPUT_SHA256.json',
                'routed_db_sha256':out/'phy_1'/(NAME+'_pr.db'),
                'timing_sha256':out/'phy_1'/(NAME+'_pr.timing')}
    for field, path in bindings.items():
        if not path.is_file() or record.get(field) != sha(path): errors.append('audit mismatch: '+field)
    checks = record.get('checks', {})
    fields = {'timing_coverage':('unexplained_unconstrained_paths','unexplained_ignored_exceptions'),
              'reset_mapping':('unproven_reset_pins',), 'cdc':('unresolved_crossings',),
              'rgmii_dual_edge':('uncovered_checks','violating_checks')}
    for name, counts in fields.items():
        check = checks.get(name, {})
        if check.get('status') != 'PASS': errors.append('audit not PASS: '+name)
        for field in counts:
            if type(check.get(field)) is not int or check[field] != 0: errors.append(name+': '+field+' must be verified zero')
        reports = check.get('reports', [])
        if not reports: errors.append('audit reports missing: '+name)
        for report in reports:
            path = (out/report.get('path', '')).resolve()
            if not path.is_relative_to(out) or not path.is_file() or report.get('sha256') != sha(path):
                errors.append('audit report missing/hash mismatch: '+name)
    expected = {f'{direction}:{port}:{edge}:{kind}'
                for direction, ports in [('RX', ['I_rgmii_rx_ctl']+[f'I_rgmii_rxd[{i}]' for i in range(4)]),
                                         ('TX', ['O_rgmii_tx_ctl']+[f'O_rgmii_txd[{i}]' for i in range(4)])]
                for port in ports for edge in ('rise','fall') for kind in ('setup','hold')}
    covered = set(checks.get('rgmii_dual_edge', {}).get('covered_endpoints', []))
    if not expected.issubset(covered): errors.append('RGMII audit lacks all 40 dual-edge setup/hold checks')
    if audit.resolve() != (out/'RELEASE_AUDIT.json').resolve():
        shutil.copy2(audit, out/'RELEASE_AUDIT.json')
    return errors


def build(out, regressions, audit=None, strategy='default'):
    out = out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    for folder in ('main/user_source', 'main/td_project', 'main/02_sim', 'shared', 'tools'):
        shutil.copytree(ROOT/folder, out/folder,
                        ignore=shutil.ignore_patterns('*_Runs', '__pycache__'))
    source_project = out/'main/td_project/camera_to_dsi_display_720p60_cnn_multibox.al'
    project = source_project.read_text(encoding='utf-8-sig')
    project = re.sub(r'<Name>[^<]+</Name>', f'<Name>{NAME}</Name>', project, count=1)
    section = re.search(r'<Verilog>.*?</Verilog>', project, re.S)[0]
    rtl = [(source_project.parent/f).resolve() for f in re.findall(r'<File Path="([^"]+)"', section)]
    assert all(p.is_file() and p.is_relative_to(out) for p in rtl), 'unfrozen/missing RTL'
    for stage in ('syn_1', 'phy_1'):
        run = out/stage
        run.mkdir()
        def relative(match):
            value = match[1]
            if re.match(r'^[A-Za-z]:', value):
                return f'Path="{run.as_posix()}"'
            path = (source_project.parent/value).resolve()
            assert path.is_relative_to(out), path
            return 'Path="'+os.path.relpath(path, run).replace('\\', '/')+'"'
        (run/(NAME+'.prj')).write_text(re.sub(r'Path="([^"]+)"', relative, project), encoding='utf-8')
        settings = (ROOT/'tools/cart_build_templates'/(stage+'.cfg')).read_text(encoding='utf-8')
        settings = settings.replace('main_cart_key3_20260925', NAME)
        if stage=='syn_1' and strategy!='high':
            settings=re.sub(r'^set synWildParams .*\n','',settings,flags=re.M)
            settings=re.sub(r'^# TD 6.2 official PH1P AreaOptimizeHigh[^\n]*\n','',settings,flags=re.M)
            if strategy=='medium':
                settings+='\n# TD 6.2 official PH1P AreaOptimizeMedium.\nset synWildParams {gate add_map_lut_struct on gate multi_thread_mapping partition gate map_mode balance_explore}\n'
        (run/'settings.cfg').write_text(settings, encoding='utf-8')
        (run/'run.tcl').write_text('source "E:/td/scripts/DefaultFlow.tcl"\nexit\n', encoding='utf-8')
    regression_results = freeze_regressions(out, regressions)
    inputs = {p.relative_to(out).as_posix():sha(p) for p in out.rglob('*') if p.is_file()}
    (out/'INPUT_SHA256.json').write_text(json.dumps(inputs, indent=2), encoding='utf-8')
    status = {'name':NAME, 'area_strategy':strategy, 'started':time.strftime('%Y-%m-%d %H:%M:%S'),
              'stages':[], 'published':False, 'bitgen_executed':False,
              'regressions':regression_results,
              'required_regressions':list(REQUIRED_REGRESSIONS),
              'release_evidence_errors':regression_errors(out, regression_results)}
    def save():
        status['inputs_unchanged'] = all((out/p).is_file() and sha(out/p)==digest for p,digest in inputs.items())
        (out/'BUILD.json').write_text(json.dumps(status, indent=2, ensure_ascii=False), encoding='utf-8')
    def run_tool(args, cwd, name, env=None):
        start=time.time()
        with (out/(name+'.log')).open('w', encoding='utf-8') as log:
            result=subprocess.run(args, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
        log=(out/(name+'.log')).read_text(encoding='utf-8', errors='replace')
        errors=[line for line in log.splitlines() if re.search(r'\*\* (?:Error|Fatal):|\bERROR\b|Error:',line)]
        status['stages'].append({'name':name, 'returncode':result.returncode,
                                 'seconds':round(time.time()-start,1), 'errors':errors})
        save()
        if result.returncode or errors:
            raise RuntimeError(f'{name} failed; see {name}.log')
    def resources(path):
        txt=path.read_text(encoding='utf-8',errors='replace')
        result={}
        for key in ('slice','eram','dsp'):
            m=re.search(r'^#'+key+r'\*?\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%',txt,re.M)
            if not m:raise RuntimeError('Missing resource '+key)
            result[key]={'used':int(m[1]),'capacity':int(m[2]),'percent':100*int(m[1])/int(m[2])}
        return result
    try:
        env=os.environ.copy()
        license=Path('E:/model/win64/LICENSE.TXT')
        assert license.is_file()
        env.update(MGLS_LICENSE_FILE=str(license),LM_LICENSE_FILE=str(license))
        run_tool(['E:/model/win64/vlib.exe','lint_work'],out,'vlib',env)
        enc=[p for p in rtl if p.name.endswith('.enc.v')]
        run_tool(['E:/model/win64/vlog.exe','-sv','-lint','-work','lint_work',*[str(p) for p in rtl if p not in enc]],out,'lint',env)
        if enc:
            run_tool(['E:/model/win64/vlog.exe','-work','lint_work',*[str(p) for p in enc]],out,'vendor_verilog',env)
        if status['release_evidence_errors']:
            raise RuntimeError('regression evidence failed: '+'; '.join(status['release_evidence_errors']))
        # Missing release evidence cannot turn diagnostic implementation into
        # publication. It is checked again immediately before bitgen.
        run_tool(['E:/td/bin/td_commands_prompt.exe','run.tcl'],out/'syn_1','syn_1')
        assert (out/'syn_1/.opt_gate.end.f').is_file()
        assert (out/'syn_1'/(NAME+'_gate.db')).is_file()
        status['synthesis_resources']=resources(out/'syn_1'/(NAME+'_gate.area'))
        failures=[]
        status['synthesis_release_target_excess'] = [
            f'{k} exceeds {limit}% synthesis estimate'
            for k,limit in [('slice',95),('eram',90),('dsp',95)]
            if status['synthesis_resources'][k]['percent']>limit]
        for k in ('eram','dsp'):
            r=status['synthesis_resources'][k]
            if r['used']>r['capacity']:failures.append(f'{k} exceeds physical capacity')
        if failures:raise RuntimeError('; '.join(failures))
        run_tool(['E:/td/bin/td_commands_prompt.exe','run.tcl'],out/'phy_1','phy_1')
        assert (out/'phy_1/.opt_route.end.f').is_file()
        assert (out/'phy_1'/(NAME+'_pr.db')).is_file()
        status['final_resources']=resources(out/'phy_1'/(NAME+'_phy.area'))
        for k,limit in [('slice',95),('eram',90),('dsp',95)]:
            if status['final_resources'][k]['percent']>limit:raise RuntimeError(f'final {k} exceeds {limit}%')
        timing=(out/'phy_1'/(NAME+'_pr.timing')).read_text(encoding='utf-8',errors='replace')
        status['timing']={}
        timing_failures=[]
        for key in ('SWNS','HWNS','STNS','HTNS'):
            m=re.search(key+r':\s*(-?[\d.]+)ns',timing)
            if not m:raise RuntimeError('missing '+key)
            value=float(m[1]);status['timing'][key]=value
            if value<0 or ('TNS' in key and value!=0):timing_failures.append(key+' failed')
        if timing_failures:raise RuntimeError('; '.join(timing_failures))
        save()
        if not status['inputs_unchanged']:raise RuntimeError('frozen inputs changed')
        status['release_evidence_errors'] = regression_errors(out, status['regressions']) + audit_errors(out, audit)
        save()
        if status['release_evidence_errors']:
            raise RuntimeError('bitgen blocked: '+'; '.join(status['release_evidence_errors']))
        # Separate bitgen starts from the newly routed database; no flow
        # settings are edited after the input manifest has been frozen.
        bit_tcl=out/'phy_1/bitgen_only.tcl'
        bit_tcl.write_text('source settings.cfg\n'
                           'import_device $device_name -package $package_name -speed $speed\n'
                           'open_project ${prj_name}.prj -noanalyze\n'
                           'import_db ${prj_name}_pr.db\n'
                           'bitgen -bit ${prj_name}.bit\n'
                           'set done [open .bitgen.end.f w]\nclose $done\nexit\n')
        status['bitgen_executed']=True
        run_tool(['E:/td/bin/td_commands_prompt.exe',str(bit_tcl)],out/'phy_1','bitgen')
        bit=out/'phy_1'/(NAME+'.bit')
        if not bit.is_file() or not (out/'phy_1/.bitgen.end.f').is_file():raise RuntimeError('missing bitgen completion')
        save()
        if not status['inputs_unchanged']:raise RuntimeError('inputs changed before publication')
        dest=ROOT/'main/05_boot/best_result'/f'dual_fpga_main_{out.name}_cart_key3.bit'
        if dest.exists():raise RuntimeError('refusing to overwrite existing bit')
        shutil.copy2(bit,dest)
        status.update(published=True,bit=str(dest),bit_sha256=sha(dest))
    except Exception as exc:
        status['failure']=str(exc)
    save()
    print(json.dumps(status,indent=2,ensure_ascii=False),flush=True)
    return 0 if status['published'] else 1


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--regressions',type=Path,required=True)
    parser.add_argument('--audit',type=Path,help='Explicit routed coverage/reset/CDC/RGMII audit JSON; absent means diagnostic build only')
    parser.add_argument('--strategy',choices=('default','medium','high'),default='default',help='Official PH1P area mapping strategy; recorded and frozen separately per run')
    args=parser.parse_args()
    raise SystemExit(build(args.output,args.regressions,args.audit,args.strategy))
