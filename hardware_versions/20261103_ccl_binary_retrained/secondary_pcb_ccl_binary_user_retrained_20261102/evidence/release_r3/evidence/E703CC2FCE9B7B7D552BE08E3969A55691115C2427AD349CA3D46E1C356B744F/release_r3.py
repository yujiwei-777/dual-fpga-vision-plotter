"""Strict r3 preflight, real vendor bitgen, and transactional diagnostic release.

No action runs implicitly on import. 'check' only audits. 'bitgen' invokes the
frozen vendor script after the complete current gate. 'package' never invokes
TD and publishes only a previously verified bit. Frozen inputs are never edited.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse, json, re, shutil, subprocess, sys, time
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import assemble_final_gate_r3 as gate
from release_guard import sha, load, put, require, safe, verify_inputs
ROOT, BUILD = gate.ROOT, gate.BUILD
NAME = 'dual_fpga_secondary_20261102_pcb_ccl_binary_user_retrained_diagnostic.bit'
PHY = BUILD / 'runs/phy_1'
DATABASE = PHY / 'secondary_cnn_multibox_pr.db'
SCRIPT = PHY / 'run_bitgen.tcl'
TD = Path('E:/td/bin/td_commands_prompt.exe')
BIT = PHY / 'secondary_cnn_multibox.bit'
LOG = BUILD / 'logs/bitgen_r3.log'
INVOCATION = BUILD / 'logs/bitgen_r3.json'

def preflight():
    g, audit, manifest = gate.validate_gate()
    physical = load(gate.PHYSICAL)
    final = physical['checks']['final_routed']
    t = final['timing_ns']
    require(set(t) == {'SWNS','STNS','HWNS','HTNS'} and t['SWNS'] >= 0 and t['HWNS'] >= 0 and
        t['STNS'] == t['HTNS'] == 0, 'Strict final routed timing failed')
    for name, limit in {'slice':95, 'eram':90, 'dsp':95}.items():
        row = final['resources'][name]
        require(row['total'] > 0 and 0 <= row['used'] and row['used'] * 100 < row['total'] * limit,
            'Strict resource gate failed: ' + name)
    require(physical['checks']['readonly']['database_sha256'] == sha(DATABASE) ==
        final['database_sha256'] == g['routed_database_sha256'], 'Readonly/routed DB differs')
    require(sha(SCRIPT) == manifest['runs/phy_1/run_bitgen.tcl']['sha256'], 'Bitgen script drift')
    text = SCRIPT.read_text(encoding='utf-8-sig')
    require('set start_step bitgen' in text and 'set end_step bitgen' in text and
        'bitgen -bit $prj_name.bit' in text, 'Not the frozen vendor bitgen-only flow')
    require(not (PHY / '.stop.f').exists() and not list(PHY.glob('.*.error.f')),
        'Existing physical failure/stop marker')
    return dict(gate=g, audit=audit, manifest=manifest, physical=physical, final=final,
        pins={**g['input_sha256'], str(gate.GATE):sha(gate.GATE), str(gate.AUDIT):sha(gate.AUDIT),
              str(SCRIPT):sha(SCRIPT), str(DATABASE):sha(DATABASE)})

def bitgen():
    c = preflight()
    require(TD.is_file(), 'TD executable missing')
    require(not any(p.exists() for p in (BIT, LOG, INVOCATION, PHY / '.bitgen.begin.f',
        PHY / '.bitgen.end.f', PHY / '.bitgen.error.f')), 'Refusing overwrite of bitgen attempt/output')
    verify_inputs(c['pins'])
    command = [str(TD), SCRIPT.name]
    record = dict(status='RUNNING', phase='bitgen', started_ns=time.time_ns(), cwd=str(PHY),
        command=command, script=str(SCRIPT), script_sha256=sha(SCRIPT),
        source_manifest_sha256=gate.MANIFEST, gate_path=str(gate.GATE), gate_sha256=sha(gate.GATE),
        input_artifact_sha256={str(DATABASE):sha(DATABASE)}, preflight_input_sha256=c['pins'],
        hardware_status='NOT_RUN')
    put(INVOCATION, record)
    try:
        with LOG.open('xb') as output:
            invocation = subprocess.run(command, cwd=PHY, stdout=output, stderr=subprocess.STDOUT)
        text = LOG.read_text(encoding='utf-8-sig', errors='replace')
        errors = re.findall(r'(?m)^.*(?:MAPPING_ERROR|BUILD_FAILED|TD_READONLY_REIMPORT_FAIL|[A-Z]+-\d+\s+(?:ERROR|FATAL)|^\s*(?:ERROR|FATAL)\s*[:\[]).*$', text)
        passed = (invocation.returncode == 0 and not errors and BIT.is_file() and BIT.stat().st_size > 0 and
            'BIT-1004 : Generate file secondary_cnn_multibox.bit.' in text and
            (PHY / '.bitgen.end.f').is_file() and not (PHY / '.bitgen.error.f').exists())
        # Bit generation is not allowed to change its routed input or any
        # source, report, tool, gate, or read-only input reviewed beforehand.
        verify_inputs(c['pins']); gate.validate_gate()
        record.update(status='PASS_TOOL_INVOCATION' if passed else 'FAILED_TOOL_INVOCATION',
            finished_ns=time.time_ns(), exit_code=invocation.returncode, log_sha256=sha(LOG), errors=errors,
            output_artifact_sha256={str(BIT):sha(BIT)} if BIT.is_file() else {},
            unchanged_database_sha256=sha(DATABASE))
        put(INVOCATION, record)
        require(passed, 'Bitgen failed; logs and attempted outputs retained without publishing')
        print(json.dumps(dict(status='DIAGNOSTIC_NOT_RUN', bit=str(BIT), bit_sha256=sha(BIT)), indent=2))
        return record
    except Exception as exc:
        record.update(status='FAILED_TOOL_INVOCATION', finished_ns=time.time_ns(), error=str(exc),
            log_sha256=sha(LOG) if LOG.is_file() else None,
            output_artifact_sha256={str(BIT):sha(BIT)} if BIT.is_file() else {})
        put(INVOCATION, record)
        raise

def verify_bitgen(c):
    row = load(INVOCATION)
    require(row['status'] == 'PASS_TOOL_INVOCATION' and row['phase'] == 'bitgen' and
        row['exit_code'] == 0 and not row['errors'] and not row.get('error'), 'Bitgen invocation did not pass')
    require(row['source_manifest_sha256'] == gate.MANIFEST and row['gate_sha256'] == sha(gate.GATE),
        'Bitgen gate/manifest identity differs')
    require(safe(row['gate_path']) == gate.GATE and row['script_sha256'] == sha(SCRIPT) and
        safe(row['script']) == SCRIPT and safe(row['cwd']) == PHY and
        row['command'] == [str(TD), SCRIPT.name], 'Bitgen executable/script/cwd differ')
    require(row['finished_ns'] >= row['started_ns'] > 0, 'Bitgen timestamps absent')
    verify_inputs(row['preflight_input_sha256'])
    require(row['input_artifact_sha256'] == {str(DATABASE):sha(DATABASE)} and
        row['output_artifact_sha256'] == {str(BIT):sha(BIT)} and
        row['unchanged_database_sha256'] == sha(DATABASE), 'Bitgen artifact identity differs')
    require(row['log_sha256'] == sha(LOG), 'Bitgen log drift')
    text = LOG.read_text(encoding='utf-8-sig', errors='replace')
    require('BIT-1004 : Generate file secondary_cnn_multibox.bit.' in text and
        (PHY / '.bitgen.end.f').is_file() and not (PHY / '.bitgen.error.f').exists(),
        'Real bitgen completion evidence missing')
    require(BIT.stat().st_size > 0, 'Empty bit file')
    return row

def publication_preflight():
    c = preflight(); c['bitgen'] = verify_bitgen(c)
    c['pins'].update({str(BIT):sha(BIT), str(LOG):sha(LOG), str(INVOCATION):sha(INVOCATION)})
    report, artifacts = HERE / 'release_r3', ROOT / 'artifacts'
    require(not report.exists(), 'Refusing to replace published release report')
    require(not artifacts.exists() or (artifacts.is_dir() and not any(artifacts.iterdir())),
        'Refusing to replace existing artifacts')
    return c

def publish(copy_file=shutil.copy2, inject=None):
    c = publication_preflight()
    stage = HERE / ('.release_r3_staging_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    stage.mkdir(exist_ok=False); report = stage / 'release_r3'; artifacts = stage / 'artifacts'
    report.mkdir(); artifacts.mkdir(); moved = []; removed_empty = False
    try:
        # Preserve every recursively pinned evidence file in a content-addressed
        # closure, including inherited DBs. Do not relabel their execution dates.
        sources = dict(c['pins'])
        for name, row in c['gate']['evidence'].items(): sources[str(safe(row['path']))] = row['sha256']
        copies = {}
        for source, digest in sources.items():
            p = safe(source); relative = 'evidence/' + digest + '/' + p.name
            dest = report / relative; dest.parent.mkdir(parents=True, exist_ok=True)
            if not dest.exists(): copy_file(p, dest)
            require(sha(dest) == digest == sha(p), 'Staged evidence copy drift: ' + source)
            copies[source] = dict(copy=relative, sha256=digest, bytes=dest.stat().st_size)
        target = artifacts / NAME; copy_file(BIT, target)
        require(sha(target) == sha(BIT), 'Staged bit drift')
        (artifacts / (NAME + '.sha256')).write_text(sha(target) + '  ' + NAME + '\n', encoding='ascii')
        package = dict(status='DIAGNOSTIC_NOT_RUN', created_utc=datetime.now(timezone.utc).isoformat(),
            bit=str(ROOT / 'artifacts' / NAME), bit_sha256=sha(target), bit_bytes=target.stat().st_size,
            project_root=str(ROOT), frozen_build=str(BUILD), source_manifest_sha256=gate.MANIFEST,
            inherited_functional_manifest_sha256=gate.PARENT_MANIFEST, synthesis='INHERITED_NOT_RERUN',
            parent_failed_post_place_proof_retained=True, routed_database_sha256=sha(DATABASE),
            resources=c['final']['resources'], timing_ns=c['final']['timing_ns'], checks=c['gate']['checks'],
            hardware_status='NOT_RUN', main_board_changed=False, known_missing_pad_falsePASS=7,
            model_freeze=load(gate.PARENT / 'MODEL_FREEZE.json'), copied_evidence=copies,
            bitgen_invocation_sha256=sha(INVOCATION), gate_sha256=sha(gate.GATE))
        put(report / 'RELEASE_MANIFEST.json', package)
        notes = '# PCB 二分类副板 diagnostic bit — NOT_RUN\n\n'
        notes += 'bit: ' + NAME + '\n\nSHA256: ' + sha(target) + '\n\n'
        notes += '只使用用户指定 D:/ai/1/0/ 与 D:/ai/1/8/1/ 样本；共享 CCL 原框 ×1.00，精确采样 96×96 源 Y8；C4/C4 二分类，margin<32 返回 REVIEW。\n\n'
        notes += '最终资源：' + json.dumps(c['final']['resources'], ensure_ascii=False) + '\n\n'
        notes += '最终布线时序 ns：' + json.dumps(c['final']['timing_ns']) + '。Setup/hold 两角通过，TNS=0，真实只读重导入一致，bitgen 完成。\n\n'
        notes += 'r3 是物理续跑：真实成功 r2 综合和完成 place 的 checkpoint 继承；r2 放置后映射辅助检查失败原样保留。增加精确 packed-LUT 校验后重新证明映射、布线与只读导入。未伪称新综合或新 r3 行为仿真；功能证据来自哈希完全相同的 r2 RTL/模型。全部 evidence 闭包按原文件哈希保留。\n\n'
        notes += '同批次分块测试 222/231 分类正确；仍有 7 张缺焊盘被误接受为 PASS、1 张良品 FAIL、3 张 REVIEW，不能据此宣称缺陷漏检已解决。\n\n'
        notes += '普通 CNN、文档、按键、矢量字体、镜像、换行、GRBL、已接受写字任务断网保持、HXA 与 DDR 保持。主板未修改。正常最终 ok 表示 GRBL 接收命令，不等于机械 Idle。\n\n'
        notes += '配套 main_pcb_auto_compat_20261101；真实主板报文/CRC/解码 RTL 兼容验证已通过。原始 0..255 分数转换为协议 0..100，是传输缩放而非校准概率。HDMI、主副板实联、真实采集与写字机验收均为 NOT_RUN。旧工程、旧 bit、work/ 与主板不覆盖。\n'
        (report / 'RELEASE_NOTES.md').write_text(notes, encoding='utf-8')
        (artifacts / 'README.md').write_text('# Diagnostic bit — NOT_RUN\n\n' + NAME +
            '\n\nSHA256: ' + sha(target) + '\n\n[交付报告](../reports/retrained/release_r3/RELEASE_NOTES.md)\n', encoding='utf-8')
        preflight(); verify_bitgen(c); verify_inputs(sources)
        require(not (HERE / 'release_r3').exists(), 'Report appeared while staging')
        final_artifacts = ROOT / 'artifacts'
        if final_artifacts.exists():
            require(final_artifacts.is_dir() and not any(final_artifacts.iterdir()), 'Artifacts appeared while staging')
            final_artifacts.rmdir(); removed_empty = True
        if inject: inject('before_publish')
        report.replace(HERE / 'release_r3'); moved.append((HERE / 'release_r3', report))
        if inject: inject('after_report_publish')
        artifacts.replace(final_artifacts); moved.append((final_artifacts, artifacts))
        stage.rmdir(); return package
    except Exception as exc:
        for final, original in reversed(moved):
            require(final.resolve().is_relative_to(ROOT) and original.resolve().is_relative_to(stage),
                'Rollback path escapes isolated project')
            final.replace(original)
        if removed_empty and not (ROOT / 'artifacts').exists(): (ROOT / 'artifacts').mkdir()
        put(stage / 'STAGING_FAILED.json', dict(status='FAILED_NOT_PUBLISHED', error=str(exc), hardware='NOT_RUN'))
        raise

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['check', 'bitgen', 'package'])
    args = p.parse_args()
    if args.action == 'check':
        c = preflight(); print(json.dumps(dict(status='PASS_PREFLIGHT_NO_BITGEN',
            timing_ns=c['final']['timing_ns'], resources=c['final']['resources']), indent=2))
    elif args.action == 'bitgen': bitgen()
    else:
        result = publish(); print(json.dumps({k:result[k] for k in ('status','bit','bit_sha256','bit_bytes')}, indent=2))
if __name__ == '__main__': main()
