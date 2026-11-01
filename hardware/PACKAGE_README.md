# 双FPGA源工程移交包：固定脏斑/低分副板＋亮度主板

| 板卡 | 工程目录 | 根工程入口 | 指定bit |
| --- | --- | --- | --- |
| 主板 | main_osd_brightness_20261101 | camera_to_dsi_display_720p60_cnn_multibox.al | dual_fpga_main_20261101_osd_brightness_diagnostic.bit |
| 副板 | secondary_doc_dirt_lowconf_factored_20261101 | secondary_cnn_multibox.al | dual_fpga_secondary_20261101_doc_dirt_lowconf_factored_diagnostic.bit |

主板SHA256：`FB3FE4F57721C7068821EC0C010D589CB82398E6F38CCCF3F7892006033E5515`。

副板SHA256：`5066DC18572D27361957A63C1702EA3CD060CAEDAB88A0172F8A3C86451C1F34`。

两板均为PH1P35MDG324、speed -3，TD Release2026.1 SP2（工程记录6.2.200067）。完整解压到短英文目录，先在包根运行`python verify_package.py`（Python3.9+，不需要FPGA工具），再按各板PACKAGE_README.md打开根.al或准备重建。每板artifacts/保留指定bit，05_boot/best_result/另有同哈希归档。源码、IP、DDR初始化、模型/MEM、字库、引脚/时序约束、原验证与构建证据均独立收录。数据库、仿真工作库、波形和缓存排除。

主板tone曲线常量48改52，保留中文OSD与既有功能接口；tone8同时用于fixed tap，可能影响送往副板的O_clean_rgb像素，不能承诺仅HDMI或CNN图像完全不变。副板为固定摄像头脏斑补偿和普通CNN真实低margin输出，保留PCB、KEY1/KEY2、KEY3应用复位、KEY4安全停止及原写字链路。新分数不是校准概率，低分允许输出不代表准确率提高。

| 板卡 | Setup/Hold WNS(ns) | TNS | Slice | ERAM | DSP |
| --- | --- | --- | --- | --- | --- |
| 主板实际布线报告 | +0.384 / +0.020 | 0 | 92.73% | 83.33% | 92.50% |
| 副板最终发布报告 | +0.005 / +0.020 | 0 | 91.70% | 84.26% | 45.00% |

218条工程文件引用均在各板内闭合。副板syn/phy冻结快照各270项、合并271个不同输入逐项匹配；948项发布证据映射随包保留，唯一routed数据库有意不收录。主板现存snapshot、gate和readonly沿用旧no_hist版；本包记录189项当前来源映射，其中187项匹配旧快照、工程路径和tone两项变化，结合本版综合/布线/bitgen日志佐证。该主板清单是打包时核对，不能冒充构建时冻结或新的完整物理验收。主板旧发布报告的Slice92.58%与仅显示分支scope已在新README澄清，原记录原样保留。

副板固定补偿只适用于原摄像头位置和裁剪，浅墨仍可能漏失；历史纸边/大阴影空白误路径41→36→71，不能视作通用阴影去除。两张当前实拍RTL回放、51帧历史软件对照和实板质量区分记录。KEY3只复位FPGA应用，不能保证外部GRBL停止；最终G-code的ok只确认控制器接收，不能确认机械Idle。

历史脚本包含原机工具或旧兄弟工程路径，需适配；副板prepare_portable_run.py仅准备保留最终Tcl策略和时钟/复位钩子的综合/布线目录，不运行TD、不出bit。重建必须重新验收，新数据库不能复用旧release_gate。详细来源、限制和历史失败/补充证明以各板说明、SOURCE_PROVENANCE.json及原始报告为准。

本次仅打包、哈希核验和异目录解压验证，原工程、已有bit、旧移交包和work/未修改。两板、真实亮度/识别影响、写字质量及本组合联动均标记NOT_RUN；成套打包不新增实板通过结论。
