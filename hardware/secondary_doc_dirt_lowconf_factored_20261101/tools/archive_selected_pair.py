"""Archive the pair explicitly selected by the user on 2026-10-01."""
import hashlib
import html
import json
import os
from pathlib import Path
import re
import shutil
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / 'work'
PAIR = LIB / 'pair_1001'
SPECS = [
    ('main', 'awb_region_highlight_20260930', 'main_1001',
     'artifacts/dual_fpga_main_20260930_awb_region_highlight_diagnostic.bit',
     '893f8787456c57e21668dcc44617f9fdb2660a02469868434b492aecb2be78f4',
     'main/td_project/camera_to_dsi_display_720p60_cnn_multibox.al'),
    ('secondary', 'secondary_uart_qg_timingfix_20261001', 'sec_1001',
     'artifacts/dual_fpga_secondary_20261001_uart_idle_query_timing_fixed.bit',
     '04c60379e42e1849135c294e093cee5160472f6cfb2745ddc2281ced958537ec',
     'td_project/secondary_edge_bypass.al'),
]


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def write_json(p, x):
    p.write_text(json.dumps(x, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def inventory(root):
    entries = []
    for d, ds, fs in os.walk(root, followlinks=False):
        for name in ds + fs:
            p = Path(d) / name
            if getattr(p.lstat(), 'st_file_attributes', 0) & 0x400:
                raise RuntimeError('Reparse point requires explicit handling: ' + str(p))
        for name in fs:
            p = Path(d) / name
            entries.append({'path': p.relative_to(root).as_posix(), 'bytes': p.stat().st_size, 'sha256': sha(p)})
    return sorted(entries, key=lambda e: e['path'])


def independent_copy(src, dst):
    assert not dst.exists(), str(dst)
    entries = inventory(src)
    shutil.copytree(src, dst, copy_function=shutil.copy2)
    for e in entries:
        a, b = src / e['path'], dst / e['path']
        assert sha(b) == e['sha256'], str(b)
        assert not os.path.samefile(a, b), str(b)
    return entries


def relocate_projects(src, dst, saved):
    changes = []
    # Preserve reports, source, constraints, historical snapshots and databases.
    for p in list(dst.rglob('*')):
        if not p.is_file() or p.suffix.lower() not in ('.al', '.prj', '.cfg', '.bat'):
            continue
        rel = p.relative_to(dst)
        if rel.parts[0] in ('artifacts', 'archive_metadata'):
            continue
        before = p.read_bytes()
        after = before
        for old, new in ((src.as_posix(), dst.as_posix()), (str(src), str(dst))):
            after = after.replace(old.encode(), new.encode())
        if before != after:
            orig = saved / rel
            orig.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, orig)
            p.write_bytes(after)
            changes.append({'path': rel.as_posix(), 'before': hashlib.sha256(before).hexdigest(), 'after': sha(p)})
    return changes


def check_project(p, archive):
    data = p.read_text(encoding='utf-8-sig')
    section = data.split('<Source_Files>', 1)[1].split('</Source_Files>', 1)[0]
    paths = [html.unescape(v) for v in re.findall(r'<File\s+Path="([^"]+)"', section)]
    for v in paths:
        q = (p.parent / v).resolve()
        assert q.is_file(), str(q)
        assert q.is_relative_to(archive), str(q)
    return len(paths)


def main():
    for _, src_name, dst_name, bit, expected, _ in SPECS:
        assert sha(ROOT / src_name / bit) == expected
        assert not (LIB / dst_name).exists()
    assert not PAIR.exists()
    PAIR.mkdir()
    metadata = PAIR / 'archive_metadata'
    metadata.mkdir()
    shutil.copy2(__file__, metadata / Path(__file__).name)
    result = {'selected_at_utc': datetime.now(timezone.utc).isoformat(),
              'selection': 'User explicitly selected these two bit files as main and secondary programs.',
              'hardware_validation': 'No new hardware validation claimed by archiving.', 'boards': {}}
    for role, src_name, dst_name, bit, expected, project in SPECS:
        src, dst = ROOT / src_name, LIB / dst_name
        entries = independent_copy(src, dst)
        saved = dst / 'archive_metadata'
        saved.mkdir()
        write_json(saved / 'SOURCE_INVENTORY.json', {'source': str(src), 'files': entries})
        changes = relocate_projects(src, dst, saved / 'original_paths')
        write_json(saved / 'PATH_RELOCATIONS.json', changes)
        count = check_project(dst / project, dst)
        short_bit = dst / (role + '.bit')
        shutil.copy2(dst / bit, short_bit)
        assert sha(short_bit) == expected
        bat = '@echo off\r\nsetlocal\r\npushd "%~dp0' + str(Path(project).parent) + '"\r\nif errorlevel 1 exit /b 1\r\nstart "" "E:\\td\\bin\\td.exe" "' + Path(project).name + '"\r\npopd\r\n'
        (dst / 'open_archive_td.bat').write_bytes(bat.encode('ascii'))
        (dst / 'ARCHIVE_README.md').write_text(
            '# 用户选定版本备份\n\n2026-10-01 用户明确选定本版为配套' + ('主板' if role == 'main' else '副板') + '程序。\n\n'
            '烧录文件：`' + short_bit.name + '`（与原命名 bit 逐字节一致）。TD 查看入口：`open_archive_td.bat`。配套说明见 `../pair_1001/README.md`。\n\n'
            '本目录只作备份；开发和重新构建应另建独立副本。源码、约束、模型、bit、报告和数据库完整保留；仅活动工程配置中的目录位置重定位，原文件在 archive_metadata/original_paths。历史 BUILD/MANIFEST 的路径与校验值保留为构建证据，归档以 archive_metadata/ARCHIVE_MANIFEST.json 校验；未在此路径重新构建或重新实板验收。\n', encoding='utf-8')
        final = inventory(dst)
        write_json(saved / 'ARCHIVE_MANIFEST.json', {'source_files': len(entries), 'relocations': changes,
                    'project_file_count': count, 'bit_sha256': expected, 'files': final})
        result['boards'][role] = {'source': str(src), 'archive': str(dst), 'original_bit': bit,
            'bit': str(short_bit), 'sha256': expected, 'project': str(dst / project),
            'files_copied': len(entries), 'project_files_checked': count, 'path_only_changes': len(changes)}
        print(role, 'COPIED_VERIFIED', len(entries), 'files', 'project_files', count, flush=True)
    host_entries = independent_copy(LIB / 'host_gui', PAIR / 'host_gui')
    dep_counts = {}
    for name in ('model', 'shared'):
        dep_counts[name] = len(independent_copy(ROOT / 'secondary_uart_qg_timingfix_20261001' / name, PAIR / name))
    for name in ('start_gui.bat', '启动上位机.bat', '使用步骤.md', '主板与副板功能说明.md'):
        shutil.copy2(LIB / name, PAIR / name)
    result['host'] = {'path': str(PAIR / 'host_gui'), 'files': len(host_entries), 'dependencies': dep_counts,
                      'origin': str(LIB / 'host_gui'), 'launcher': str(PAIR / 'start_gui.bat')}
    write_json(PAIR / 'PAIR.json', result)
    write_json(metadata / 'HOST_SOURCE_INVENTORY.json', host_entries)
    print('PAIR_COPY_COMPLETE', str(PAIR), flush=True)


if __name__ == '__main__':
    main()
