"""Write delivery documents only after standard bitgen and post-review pass."""
import csv
import json
from pathlib import Path
import re
from display_noise_paths import ROOT, RUN, NAME, BIT, BASEBIT, BASESHA, obj, put, sha
from verify_display_noise_build_strategy import validate as validate_build_strategy
from validate_display_equivalence_chain import validate as validate_equivalence_chain


def canonical(path):
    return str(Path(path).resolve()).replace('\\', '/').casefold()


def require_review_binding(release, path):
    """A historical gate/review cannot certify the configured final run."""
    evidence = {key.replace('\\', '/'): value
                for key, value in release.get('evidence', {}).items()}
    relative = path.relative_to(ROOT).as_posix()
    if evidence.get(relative, {}).get('sha256') != sha(path):
        raise RuntimeError('Post-bitgen review does not bind current evidence: ' + relative)


def main():
    release = obj(ROOT / 'reports/display_noise_release.json')
    gate = obj(RUN / 'release_gate.json')
    snapshot = obj(RUN / 'source_snapshot.json')
    regression = obj(ROOT / 'reports/display_noise_regression.json')
    contract = obj(ROOT / 'reports/display_functional_contract.json')
    spatial = obj(ROOT / '02_sim/display_noise/verification.json')
    if not all(d.get('passed') is True for d in [release, gate, snapshot, regression, contract]):
        raise RuntimeError('Delivery requires all real gates and post-bitgen review')
    if (canonical(gate.get('run', '')) != canonical(RUN)
            or gate.get('name') != NAME
            or canonical(gate.get('snapshot', '')) != canonical(RUN / 'source_snapshot.json')
            or canonical(snapshot.get('run', '')) != canonical(RUN)
            or canonical(contract.get('project_run', '')) != canonical(RUN)):
        raise RuntimeError('Final gate/snapshot/functional contract must identify the configured RUN')
    for path in [RUN / 'source_snapshot.json', RUN / 'release_gate.json',
                 ROOT / 'reports/display_noise_regression.json']:
        require_review_binding(release, path)
    compile_path = ROOT / '02_sim/display_noise/compile.log'
    compile_text = compile_path.read_text(encoding='utf-8-sig')
    if (spatial.get('status') != 'PASS'
            or spatial.get('compile_sha256') != sha(compile_path)
            or not re.search(r'Errors: 0, Warnings: 0', compile_text)
            or re.search(r'Errors:\s*[1-9]|Warnings:\s*[1-9]|\*\*\s+(?:Error|Warning|Fatal):', compile_text)):
        raise RuntimeError('Source-bound canonical spatial compile requires genuine zero errors and warnings')
    if not BIT.is_file() or sha(BIT) != release['details']['artifact']['sha256']:
        raise RuntimeError('Bit does not match post-bitgen review')
    if sha(BASEBIT) != BASESHA:
        raise RuntimeError('Read-only baseline bit changed')
    for item in snapshot['files']:
        if sha(Path(item['path'])) != item['sha256']:
            raise RuntimeError('Frozen input drift')
    build_strategy = validate_build_strategy(run=RUN, require_log=True, snapshot=snapshot)
    if build_strategy.get('passed') is not True:
        raise RuntimeError('Documented official AreaOptimizeHigh+pack strategy and frozen build-script validation failed: '
                           + '; '.join(build_strategy['errors']))
    chain = validate_equivalence_chain(root=ROOT)
    if chain.get('passed') is not True:
        raise RuntimeError('Implementation equivalence chain failed: ' + '; '.join(chain['errors']))
    combined = chain['stages']['combined']
    nocarry = chain['stages']['nocarry']
    resources = gate['resources']; timing = gate['timing_ns']
    sources = {Path(f['path']).relative_to(ROOT).as_posix(): f['sha256'] for f in snapshot['files']}
    inactive = obj(ROOT / 'tools/inactive_project_files.json')
    historical_attempts = []
    for label, filename, field, algorithm in [
            ('V2', 'attempt2_failure_and_v3_preparation.json', 'attempt2_status', 'direct-four-neighbour 2x2'),
            ('V3', 'attempt3_failure_and_v4_preparation.json', 'status', 'direct-four-neighbour 2x2'),
            ('V4', 'attempt4_failure_and_v5_preparation.json', 'status', 'separable two-pass 2x2'),
            ('V5', 'attempt5_failure_and_v6_preparation.json', 'status', 'equivalent compressed separable 2x2 with high packing'),
            ('V6', 'attempt6_failure_and_v7_preparation.json', 'status', 'equivalent Boolean TH16 separable 2x2 with high packing'),
            ('V7', 'attempt7_failure_and_v8_preparation.json', 'status', 'same RTL with area_prior mapping and high packing')]:
        history_path = ROOT / 'reports' / filename
        history = obj(history_path)
        if history.get(field) != 'FAILED_PLACEMENT_NO_ROUTE_NO_BITGEN':
            raise RuntimeError(label + ' placement failure must remain accurately recorded')
        historical_attempts.append({'attempt': label, 'status': history[field],
            'report': history_path.relative_to(ROOT).as_posix(),
            'sha256': sha(history_path), 'acceptance_evidence': False,
            'limitation': 'Historical ' + algorithm + ' PHY-7027/PHY-9002 placement failure; no failed gate, DB or marker is current acceptance evidence.'})
    replay = obj(ROOT / 'reports/display_noise_replay/historical_replay.json')
    rms = replay['background_temporal_residual_rms']
    if ('spatial_separable_threshold16' not in rms
            or replay.get('rtl_sha256') != sha(ROOT / '01_rtl/imgq_gain_m/main/user_source/hdl_source/a4_display_spatial_h1.v')
            or replay.get('integer_reference_sha256') != sha(ROOT / 'model/display_spatial_reference.py')
            or replay.get('replay_script_sha256') != sha(ROOT / 'model/replay_display_noise.py')
            or replay.get('vectorized_equals_integer_reference') is not True):
        raise RuntimeError('Delivery requires new separable replay bound to current RTL/model/script; old 2x2 metrics cannot certify it')
    extra = []
    # Preserve inactive provenance separately from actual synthesis dependencies.
    for p in [ROOT / 'tools/inactive_project_files.json', ROOT / 'reports/display_functional_contract.json',
              ROOT / 'model/replay_display_noise.py', ROOT / 'model/display_spatial_reference.py',
              ROOT / 'reports/display_noise_replay/historical_replay.json',
              ROOT / 'tools/verify_display_noise_build_strategy.py',
              ROOT / 'tools/test_display_noise_build_strategy.py',
              ROOT / 'tools/finalize_display_noise_delivery.py',
              ROOT / 'tools/validate_display_equivalence_chain.py',
              ROOT / 'reports/display_noise_build_strategy.json',
              ROOT / 'reports/BUILD_ATTEMPT_HISTORY.md',
              ROOT / 'reports/NOISE_FINDINGS_AND_LIMITS.md',
              ROOT / 'reports/DISPLAY_TONE_FIX_AND_GAIN_AUDIT.md',
              ROOT / 'reports/parameter_readback_trial/read_v8_parameters.tcl',
              ROOT / 'reports/parameter_readback_trial/console_readback_v2.log',
              ROOT / 'reports/parameter_readback_trial/actual_readback_run_v2.json',
              ROOT / 'reports/parameter_readback_trial/run_readback.py',
              ROOT / 'reports/attempt8_readback_checker_validation.json',
              ROOT / 'reports/v8_strategy_readback_validation.log',
              ROOT / 'reports/attempt8_readback_checker_validation_v2.json',
              ROOT / 'reports/v8_readback_tool_tests.log',
              ROOT / 'reports/attempt8_spatial_reuse.json',
              ROOT / 'reports/attempt7_spatial_archive.json',
              ROOT / 'reports/SPATIAL_V8_EVIDENCE_REUSE.md',
              ROOT / '02_sim/spatial_module_gate_20261103_schema/comparison.json']:
        extra.append({'path': p.relative_to(ROOT).as_posix(), 'sha256': sha(p)})
    failure_archive = ROOT / 'reports/attempt8_hidden_table_failure/manifest.json'
    extra.append({'path': failure_archive.relative_to(ROOT).as_posix(),
                  'sha256': sha(failure_archive), 'acceptance_evidence': False,
                  'scope': 'Original table-only checker and first DB-path failures; historical failure remains failure'})
    for item in obj(failure_archive)['files']:
        path = Path(item['archive'])
        extra.append({'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(path),
                      'acceptance_evidence': False, 'scope': 'Unaltered original failure archive'})
    # Reuse the same validator and raw evidence as collector/pre-bitgen review.
    for path, digest in sorted(chain['evidence'].items()):
        extra.append({'path': Path(path).relative_to(ROOT).as_posix(), 'sha256': digest})
    for attempt in ('v5_high', 'nocarry_high'):
        folder = ROOT / '02_sim/spatial_module_gate_20261103_schema' / attempt
        for filename in ('module_source.v', 'module_area_top.v', 'module_area.al', 'run.tcl',
                         'input_manifest.json', 'area_result.json', 'console.log',
                         'module_area_gate.area', 'module_area_after_legalize.area'):
            path = folder / filename
            extra.append({'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(path),
                          'acceptance_evidence': False,
                          'scope': 'Preliminary isolated module-gate comparison only'})
    # The palette was measured independently after preparation. Its result is
    # supplementary research, not a product change or V8 resource/timing gate.
    palette_trial = ROOT / '02_sim/osd_palette_equiv_trial'
    palette_area = palette_trial / 'module_gate_20261103_dynamicio'
    for path in [ROOT / 'reports/OSD_PALETTE_MODULE_GATE.md',
                 ROOT / 'tools/run_spatial_module_area.py',
                 palette_trial / 'verification.json', palette_trial / 'compile.log',
                 palette_trial / 'transcript.log', palette_trial / 'prepare_palette_area.py',
                 palette_area / 'comparison.json', palette_area / 'comparison_context.json']:
        extra.append({'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(path),
                      'acceptance_evidence': False,
                      'scope': 'Isolated OSD palette experiment; not promoted into production or V8'})
    for case in ('baseline', 'palette'):
        for filename in ('module_source.v', 'module_area_top.v', 'module_area.al', 'run.tcl',
                         'osd_compact_glyphs.vh', 'input_manifest.json', 'area_result.json',
                         'console.log', 'module_area_gate.area', 'module_area_after_legalize.area'):
            path = palette_area / case / filename
            extra.append({'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(path),
                          'acceptance_evidence': False,
                          'scope': 'Preliminary isolated palette gate measurement; not V8 placement/timing acceptance'})
    manifest = {'hardware_status': 'NOT_RUN', 'baseline_bit_sha256': BASESHA,
                'artifact': {'path': str(BIT), 'sha256': sha(BIT), 'bytes': BIT.stat().st_size},
                'actual_prebuild_snapshot': str(RUN / 'source_snapshot.json'),
                'snapshot_sha256': sha(RUN / 'source_snapshot.json'),
                'final_run': str(RUN),
                'active_and_build_inputs': sources, 'supplementary_evidence': extra,
                'historical_attempts': historical_attempts,
                'build_strategy': build_strategy,
                'noise_quality_limits': {
                    'report': 'reports/NOISE_FINDINGS_AND_LIMITS.md',
                    'report_sha256': sha(ROOT / 'reports/NOISE_FINDINGS_AND_LIMITS.md'),
                    'raw_frame_for_reported_severe_texture_available': False,
                    'fix_of_reported_severe_texture_established': False,
                    'hardware_validation': 'NOT_RUN',
                    'style_gain8_promoted': False, 'OSD_palette_promoted': False},
                'canonical_simulation_provenance': {
                    'receipt': 'reports/attempt8_spatial_reuse.json',
                    'receipt_sha256': sha(ROOT / 'reports/attempt8_spatial_reuse.json'),
                    'scope': 'V8 changes physical build strategy only; source-identical V7/V6 canonical simulation and replay are reused, not rerun'},
                'combined_equivalence': {
                    'candidate_sha256': combined['candidate_sha256'],
                    'frozen_product_sha256': combined['frozen_product_sha256'],
                    'cases': len(combined['cases']), 'total_cycles': combined['total_cycles'],
                    'total_valid_pixels': combined['total_valid_pixels']},
                'nocarry_equivalence': {
                    'candidate_sha256': nocarry['candidate_sha256'],
                    'frozen_product_sha256': nocarry['frozen_product_sha256'],
                    'cases': len(nocarry['cases']), 'total_cycles': nocarry['total_cycles'],
                    'total_valid_pixels': nocarry['total_valid_pixels']},
                'implementation_equivalence_chain': [combined['frozen_product_sha256'],
                    combined['candidate_sha256'], nocarry['candidate_sha256']],
                'implementation_equivalence_logs': [Path(path).relative_to(ROOT).as_posix()
                    for path in chain['logs']],
                'resources': resources, 'timing_ns': timing,
                'regression_sha256': sha(ROOT / 'reports/display_noise_regression.json'),
                'release_sha256': sha(ROOT / 'reports/display_noise_release.json')}
    put(ROOT / 'reports/DISPLAY_NOISE_DELIVERY_MANIFEST.json', manifest)
    with (ROOT / 'reports/BUILD_SOURCE_SHA256.csv').open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.writer(stream); writer.writerow(['path', 'sha256'])
        writer.writerows(sorted(sources.items()))
    (BIT.parent / (BIT.name + '.sha256')).write_text(sha(BIT) + '  ' + BIT.name + '\n', encoding='ascii')
    eram_delta = resources['eram']['used'] - 90
    regression_count = len(regression['checks'])
    regression_logs = len(regression['logs'])
    spatial_cases = len(spatial['cases'])
    report = f'''# 主板显示保边降噪交付报告

独立工程：`{ROOT}`。实板状态：**NOT_RUN**。

## 交付

- bit：`{BIT}`
- SHA256：`{sha(BIT)}`
- 大小：{BIT.stat().st_size} 字节。
- 只读基线：`main_pcb_auto_compat_20261101`，bit SHA256 `{BASESHA}`。
- 未修改基线、副板、旧 bit、识别模型权重或 `work/`。

## 修改与参数

1. HDMI 显示分支从同一行两点平均改为可分离二维保边滤波。第一级 `H=(sourceC+guardedSourceL+1)>>1`，第二级 `O=(H+guardedPreviousRowH+1)>>1`；每一级独立检查RGB全部通道，任一通道差值大于16则以当前值替代邻居。缺少左邻居时H=sourceC，缺少上一行时O=H。两次舍入是算法的一部分，并非旧四邻居独立判定的一次四项平均。RGB保留完整8位，不清低位、不做颜色量化。相对基线 ERAM 增量为 {eram_delta:+d} 块，无新增 DSP。
2. 全部五个视频标志与像素统一经过两级寄存器，DDR读请求仍使用原始VTC时序。行BRAM保存第一级H，不保存最终O，也不是原始RGB行；上下相邻行的H参与第二级计算。帧/行边界屏蔽旧RAM，无帧历史及最终输出递归，不是TNR。门限保护强边缘；低对比纹理仍可能变柔，不能宣称滤波完全无损。
3. 原图显示 tone 仅修正源值96/97/98/99，输出改为120/122/124/126；最大邻级跳变6→2，其余252值保持。CNN 固定 tone tap 及握手/帧标记与冻结基线逐周期相同。
4. AE/AG/DG、AWB、LSC、CNN/PCB模型、文档、HXA1、DDR和OSD算法/协议不变。运动采样仍位于空间滤波前，算法和参数不变；但原图显示 tone 的4值修改经DDR影响其输入。在 tone 通道本身，改动范围为−4..0DN，两帧有符号/绝对差分变化均不超过4DN；这不是所有后级运动判决的形式化上界，不能保证运动输入像素或事件与旧版完全相同。
5. 本轮选择上述可分离算法以控制组合逻辑成本；它与V2/V3的直接四邻居算法不同，重新生成整数模型、逐像素RTL回归及历史帧效果对照，不沿用旧算法RMS或等价结论。TH=16始终精确接受−16..+16，含两个边界；V6改用下面的等价布尔判定，不再依赖该固定门限分支的9位减法。实际资源及时序仍以下面的最终物理结果为准。
6. V5在V4可分离算法上仅做三项等价RTL压缩：`IMG_WIDTH>1`删除被有效位屏蔽的RAM转发支路、宽1仍保留显式转发；舍入平均精确改写为`(a>>1)+(b>>1)+(a[0]|b[0])`；把邻居输入选择移到平均结果之后，使用`use ? avg2(C,N) : C`。11/11独立等价用例逐周期核对RGB与全部五个标志（含无效周期），每例穷举65536对avg2输入；合计{combined['total_cycles']}周期、{combined['total_valid_pixels']}有效像素通过。补充控制枚举说明受测宽度大于1时无未屏蔽读写冲突，宽1确需保留转发。模型、门限、两次舍入、RGB8和行RAM内容不变；正式canonical回归及100帧回放重新绑定最终RTL哈希。
7. V8综合脚本只增加一行`set synWildParams {{gate add_map_lut_struct high gate map_mode area_prior gate multi_thread_mapping partition rtl resource_sharing auto rtl shifter_style shifter_reg gate pack_effort high}}`。前五项精确来自工具随附`doc/strategies/official_strategy_ph1.json`的AreaOptimizeHigh，SHA256为`6AAF4F51B9494C5F56AEBDB29C277FB350D05A1D122797B8553F9E24CD97792A`；额外的`gate pack_effort high`是公开ALL参数，不属于官方五项本身。TD用户手册V6.2 §9.7（PDF246／打印245）明确该策略支持PH1P，同时提示面积优化可能增加逻辑级数。除这一行外，综合脚本与成功基线逐字节一致，place/route脚本不变。实际synth.log确认六项唯一设置、对应RTL/Gate提交顺序和两个optimize成功完成，无后续覆盖或重载。首轮校验因正常提交表隐藏四项高级参数而真实失败，原报告和wrapper日志保存在`reports/attempt8_hidden_table_failure/`；之后ROOT对实际完成的gate DB执行只读`get_param`，六项实际返回精确匹配。增强校验严格绑定DB前后/current、已审Tcl、原始日志和receipt的路径/大小/SHA及查询/标记顺序，仅为四项缺失行补证；`map_mode`和`pack_effort`仍强制检查真实提交表，最终require-log/snapshot重新校验通过。不把set命令接受或receipt布尔值单独当作证据，也不声称解释优化器内部实现。没有改变器件容量、引脚、时钟/IO约束或资源及时序门槛，收益以最终物理结果为准。
8. V6在已证明的V5上仅替换TH=16邻居比较：高4位相同则接受；高4位相差1时按低4位有序关系决定；其它情形拒绝，并显式禁止高位0／15回绕。固定16的函数仅用布尔项，不含加减或有序比较运算符；非16参数保留原通用算术。独立Python穷举65536对字节，接受8176对；每个RTL用例穷举65536对字节及196608个RGB通道位置，另核对avg2。11/11用例合计{nocarry['total_cycles']}周期、{nocarry['total_valid_pixels']}有效像素，RGB和五标志在全部周期（含无效周期）与冻结V5相同。两段证明分别绑定V4→V5、V5→实际V6源码，保留原始日志并由collector、bitgen前review及finalizer共用`validate_display_equivalence_chain.py`严格解析。代码名nocarry不是最终物理零carry的保证；以真实全工程资源报告为准。算法和RMS效果不因本项等价变更而改变。
9. 两个相同配置的独立模块gate综合实测：冻结V5为100 logic LUT／102 ripple／119 seq／3 ERAM／0 DSP，布尔候选为115／48／119／3／0，即LUT+15、ripple−54，其余不变。证据在`02_sim/spatial_module_gate_20261103_schema/comparison.json`及两侧源文件／wrapper／AL／Tcl／manifest／原始日志和area报告。此数据不代表全工程最终资源或时序，也不等于释放54个最终物理Slice；不作为当前物理验收证据。
10. OSD调色板另做隔离试验：同一133-IO动态wrapper保留正常面板、全部八种PCB状态和所有输出，DUT实测logic LUT 254→245、seq 62→34，即−9 LUT／−28 FF，ripple／ERAM／DSP不变。真实gate和legalize后报告、原始含警告日志及输入哈希在`02_sim/osd_palette_equiv_trial/module_gate_20261103_dynamicio/`；准备阶段context的NOT_RUN/NOT_MEASURED不代替后来的真实面积报告。该候选和风格gain8试验均未合入生产源码或V8，不是本版全工程容量、时序或画质验收证据。

## 最终门槛

| 指标 | 实际结果 | 门槛 |
|---|---:|---:|
| Setup WNS | {timing['SWNS']:+.3f} ns | ≥0 |
| Hold WNS | {timing['HWNS']:+.3f} ns | ≥0 |
| Setup/Hold TNS | {timing['STNS']} / {timing['HTNS']} ns | 0 |
| Slice | {resources['slice']['used']}/{resources['slice']['total']}，{resources['slice']['percent']:.3f}% | <95% |
| ERAM | {resources['eram']['used']}/{resources['eram']['total']}，{resources['eram']['percent']:.3f}% | <90% |
| DSP | {resources['dsp']['used']}/{resources['dsp']['total']}，{resources['dsp']['percent']:.2f}% | <95%，数量不增加 |

最终使用 `{RUN.name}`。完成 lint/编译、RTL/整数对照、综合、布局布线、setup/hold、现有 CDC/FIFO/DDR 约束核验、DRC、只读 reimport、标准 context、无覆盖参数的标准 bitgen 和生成后复核。

## 验证与效果范围

- {regression_count}项回归、{regression_logs}份日志：普通CNN链路、启动故障、文档Type15长任务、PCB 30秒预算/250ms心跳/任务过滤、KEY4单次触发、实际框和无目标清框。未变化模块的日志按当前源码哈希继续绑定。V8仅改变物理构建策略，复用RTL与模型完全相同的V7/V6正式canonical编译／仿真及回放，不声称在V8重新运行；107项恢复文件逐项SHA一致，收据为`reports/attempt8_spatial_reuse.json`，最终检查仍绑定当前源文件及真实日志。
- tone：256值穷举；24520周期基线对照，14772次接受、4864次停顿，固定识别tap和标志一致。
- 空域滤波：{spatial_cases}组像素oracle，包括两帧完整720p、全部256个RGB8通道等级及混合值、强边缘和单像素线、DE空洞、复位、首末行列、宽1碰撞和坏行重入。总{spatial['total_valid']}个有效像素、{spatial['total_cycles']}个周期，最终canonical完整编译及每组仿真均为0错误、0警告。
- 历史{replay['frames']}帧RGB回放：背景时域残差RMS，源图 {rms['source']:.3f}、旧两点滤波 {rms['old_h1_threshold24']:.3f}、新可分离二维滤波 {rms['spatial_separable_threshold16']:.3f}，相对旧两点变化{replay['change_vs_h1_percent']:.2f}%。这是旧采集数据的离线软件结果；采集bit身份未知，不是本次拍屏异常帧，也不是新bit实测。回放为两种空间滤波器提供同一RGB输入，不包含tone修正或传感器增益变化。对照图在 `reports/display_noise_replay/historical_rgb_crop_comparison.png`。
- 保留原始 RUN-8007 容量计数和 USR-8450 IO 诊断；没有标记为clean。独立完整Slice位置/类型/容量及79物理IO/硬DPHY核验、标准context和标准bitgen通过。原始检查及限制见 `display_noise_prebitgen_review.json` 与 `02_sim/display_noise_readonly/`。
- V1探索综合保留了9个因只复制活动文件而新增的PRJ-7001告警。V2复制并绑定原本AutoExcluded的文件及支撑文件、不改变其禁用属性后重新冻结、综合，但真实place报PHY-7027（SLICEL字段容量）并以PHY-9002及`.opt_place.error.f`失败，没有完成布局、布线或bitgen。TD未打印精确超出量，21147 Slice*只是综合预估；PHY-7027单独出现也不能替代实际物理结论。原始失败证据在 `reports/attempt2_evidence/` 及 `reports/attempt2_failure_and_v3_preparation.json`，不作为当前验收证据。
- V3虽对旧算法作等价组合逻辑压缩，真实place仍报PHY-7027/PHY-9002并失败，无完成布局、布线或bitgen；21099 Slice*同样只是综合预估。失败证据及源模型保存在 `reports/attempt3_failure_and_v4_preparation.json`、`reports/attempt3_model/` 及旧run中。旧四邻居算法的回放保存在 `reports/display_noise_replay_attempt3_2x2/`，不得代替本版效果报告。
- V4改用可分离算法后，真实place仍报PHY-7027（SLICEL字段容量）及PHY-9002并失败，无完成布局、布线或bitgen；20888 Slice*仍只是综合预估，不是最终占用，也没有精确超出量。失败日志、原RTL及旧canonical证据保存在`reports/attempt4_failure_and_v5_preparation.json`、`reports/attempt4_evidence/`、`reports/attempt4_rtl/`和`02_sim/display_noise_attempt4_rtl_v4/`；不作为当前物理验收证据。
- V5采用combined等价压缩及high packing后，真实place仍报PHY-7027／PHY-9002并失败，无完成布局、布线或bitgen；20924 Slice*也是综合预估。`reports/attempt5_failure_and_v6_preparation.json`、`reports/attempt5_evidence/`、`reports/attempt5_rtl/`及`02_sim/display_noise_attempt5_rtl_v5/`保留原始证据。V6独立采用上述固定16布尔比较并重新冻结、仿真、回放及物理构建；没有把V5失败DB或marker当作成功证据。
- V6真实place仍报PHY-7027／PHY-9002并失败，无完成布局、布线或bitgen；20872 Slice*为综合预估，最后一次中间模型的21435 LUT／20908 seq／568 MSLICE／4121 LSLICE也不是最终物理验收。`reports/attempt6_failure_and_v7_preparation.json`、`reports/attempt6_evidence/`和`reports/attempt6_rtl/`保留失败证据。V7仅把有文档支持的`map_mode area_prior`加入既有high packing；产品RTL、模型、算法和CD722开头空间滤波源码哈希均不变。既有V4→V5→V6等价证据继续严格绑定，未将风格算术候选加入V7；V6失败DB与marker不作为当前验收证据。
- V7采用area_prior及high packing后仍在SLICEL容量初始化阶段报PHY-7027／PHY-9002，无完成布局、布线或bitgen。20842 Slice*为综合预估，最后中间模型为21254 LUT／20908 seq／568 MSLICE／4121 LSLICE；总LUT低于基线也不足以证明可布局或局部容量达标。`reports/attempt7_failure_and_v8_preparation.json`、`reports/attempt7_evidence/`、`reports/attempt7_rtl/`及`02_sim/display_noise_attempt7_rtl_v7/`保留原始失败证据。V8只采用官方完整五项面积策略和额外packhigh；RTL、模型和算法不变，V7失败DB与marker不作为当前验收证据。
- 最终使用 `{RUN.name}` 独立源快照、源哈希一致的V6 canonical证据和当前真实物理报告。V2旧空间编译日志中的Warnings:1完整保留于 `02_sim/display_noise_attempt2_rtl_v2/`，V3旧空间日志保留于 `02_sim/display_noise_attempt3_rtl_v3/`；均未篡改或作为新算法PASS。V6当时重新创建canonical目录和库并完成真实0错误、0警告编译及仿真，V7及V8逐项哈希验证后恢复复用，均不是新仿真。第一次并发仿真license失败日志保留在 `pcb_actual_box_v2_attempt1_license`，正式回归串行重跑通过。

本版未改变高增益回落策略，不能据离线降噪结果断言偶发严重彩噪已根治。尚未取得与本次严重噪纹对应的原始故障帧、故障时增益寄存器或可复现采集，历史100帧不替代该故障证据；完整限制见`reports/NOISE_FINDINGS_AND_LIMITS.md`并已纳入manifest。需要实板比较正常/异常帧、明暗切换、远景细纹、运动、19种风格、CNN/PCB/文档联动；AE高增益及RAW行同步问题仍需现场数据验证。

## 复现和依赖

`tools/DISPLAY_NOISE_BUILD_COMMANDS.md` 提供分阶段命令。源码清单及 SHA256 在 `BUILD_SOURCE_SHA256.csv`、`DISPLAY_NOISE_DELIVERY_MANIFEST.json` 和实际 prebuild `source_snapshot.json`；inactive文件单独绑定于 `tools/inactive_project_files.json`。已有证据不覆盖，重构建使用新独立run。
'''
    (ROOT / 'reports/DISPLAY_NOISE_BUILD_REPORT_20261103.md').write_text(report, encoding='utf-8')
    print(json.dumps({'artifact': manifest['artifact'], 'hardware_status': 'NOT_RUN', 'timing_ns': timing, 'resources': resources}, indent=2))


if __name__ == '__main__':
    main()
