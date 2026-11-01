# 主板亮度增强版可移交源工程

对应 bit：`dual_fpga_main_20261101_osd_brightness_diagnostic.bit`；SHA256：`FB3FE4F57721C7068821EC0C010D589CB82398E6F38CCCF3F7892006033E5515`。实板状态 **NOT_RUN**。

用 Tang Dynasty Release 2026.1 SP2 / 工程记录 6.2.200067 或兼容版本打开包根 `camera_to_dsi_display_720p60_cnn_multibox.al`。器件 PH1P35MDG324，speed -3，顶层 design_top_wrapper。完整保留源码、IP、约束、模型、MEM、字库、目标 bit 和 05_boot 同哈希副本；138 条活动引用均为包内相对路径。请整体解压到短英文目录并保留目录结构。

本版从 no_hist 继承中文 OSD，只把 display_tone_96.v 的 tone8 常量 48 改为 52，中高亮区约提高 4 个码值。no_hist 只是隐藏模式行“直方图”及 ON/OFF 字样，没有删除直方图处理功能。**tone8 也用于 O_fixed_tdata；isp_top_basic_core.v 将该固定 tone 输出接入 O_clean_rgb，供副板识别。因此不能声称本版只影响 HDMI 或 CNN 输入像素完全不变。** 原 brightness_release 报告中的相关范围声明作为历史原文保留，以此处纠正为准；实板亮度、过曝和识别影响尚未验证。

本次从实际 brightness route 报告核对：Setup WNS +0.384 ns，Hold WNS +0.020 ns，TNS 0；Slice **19673/21216 = 92.73%**，ERAM 90/108 = 83.33%，DSP 37/40 = 92.50%。brightness_release 报告的 Slice 92.58% 是旧值，不能作为本版实际资源值。

构建来源必须区分：td_project_compact_v2/source_snapshot.json、release_gate.json、compact_readonly_v2 和部分验证/仿真报告继承自 no_hist，其 189 项原始条目仍指向旧项目。打包时映射到当前 brightness 文件后，187 项与继承哈希一致，2 项（入口 AL 和 display_tone_96.v）存在预期差异。本包 CURRENT_SOURCE_PROVENANCE.json / SOURCE_PROVENANCE.json 是**打包时当前文件核验**，不是 brightness 构建时冻结证明。实际 brightness synth/place/route 与 bitgen 日志保留在 artifacts/evidence/final_build；它们确认当前变体来源和 bitgen，但不能补造构建时哈希。

旧 release_gate、readonly、CDC/FIFO/DDR/DRC 报告仅是继承证据，不能据此宣称本版新增全部审查通过。历史警告和失败日志如实保留。USER_GUIDE.md、预览和部分回归也继承基线。本次只整理指定已有 bit 和源工程，没有重新综合、重新生成 bit 或实板测试，成套分发不等于联动验收。

包根执行 `python verify_package.py`（Python 3.11+）校验清单、全部文件哈希、bit 副本、138 条引用和 189 项当前映射。`SHA256SUMS.txt` 提供逐文件校验。TD 数据库、仿真库、缓存、波形及旧 bit 不含在包内。

若需要保留原工程深度进行新构建，可先在**额外解压的工作副本**运行 `python prepare_portable_run.py`，它只创建 01_rtl/imgq_gain_m/main/build_portable 的相对入口、ROM 和三个 synth/place/route Tcl，不启动工具，且脚本禁用 bitgen；然后在 TD 打开该入口，按顺序执行三个阶段并自行验收。创建工作目录会使原始分发清单校验不再通过，请保留一份未修改分发副本。历史 tools/Tcl/仿真脚本含开发机路径或工具依赖，使用前需适配，不能当作已经验证的一键复现流程。点阵字模已嵌入 RTL，正常综合不需要原机字体。

原工程、旧 bit、其它发布包及 work/ 未在本次打包中修改。
