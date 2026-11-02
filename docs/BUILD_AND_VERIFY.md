# 构建与核验

> 本页保留 2026-11-01 固定窗口版本记录。2026-11-02 自动定位 PCB 配套版本的算法、工程入口与 NOT_RUN 状态见 [新版说明](POSE7_AUTO_20261102.md)。


## 文件校验

完整下载仓库，使用 Python 3.11+ 在仓库根运行：

~~~powershell
python -B verify_release.py
~~~

该命令检查源文件数量、尺寸、SHA256、218 条工程引用、双板 bit 及归档副本，并核对验收记录中的 bit 校验值。综合与仿真需单独运行。

请复制 hardware/ 后再构建，避免生成文件影响原目录的完整性校验。该目录已关闭 Git 自动换行转换，以保留源文件字节。

## 工具与入口

- Tang Dynasty Release 2026.1 SP2，工程记录 6.2.200067，或经核对的兼容版本。
- 两板器件 PH1P35MDG324，speed -3。
- ModelSim / Questa 用于原有 Verilog / SystemVerilog 测试。许可证由使用者合法配置，仓库不包含许可证文件。
- Python 3.11+ 用于参考模型、清单和包核验；不同历史脚本的额外依赖以各脚本说明为准。

主板入口：hardware/main_osd_brightness_20261101/camera_to_dsi_display_720p60_cnn_multibox.al。

副板入口：hardware/secondary_doc_dirt_lowconf_factored_20261101/secondary_cnn_multibox.al。

先阅读各板 PACKAGE_README.md。副板 main/ 收录本板必需的 DDR、PLL 和以太网依赖，并非冗余主板源码，不能删除。模型、ROM 和 include 的相对布局也应保留。

## 在独立副本重建

1. 复制完整 hardware/ 到新的短英文路径，例如 D:/fpga_build/pair_20261101/，不要直接在原分发副本中跑工具。
2. 在新副本先执行包根 python -B verify_package.py。
3. 在板卡目录运行 python -B prepare_portable_run.py，按该板 README 处理运行目录参数和入口。该脚本只准备目录，不执行 TD，不生成 bit。
4. 用兼容 TD 按生成的 Tcl 与目录结构依次完成 synthesis、place、route；历史辅助脚本可能含开发机工具路径或兄弟工程路径，需逐项适配。
5. 对新构建执行 lint / RTL 回归、CDC、FIFO、DDR、复位、DRC、只读 reimport 和资源 / 时序检查，通过后执行 bitgen。
6. 保存新 bit 的 SHA256、源清单和验收记录，与原版本分别归档。

门槛：setup / hold WNS ≥ 0、TNS = 0、Slice < 95%、ERAM < 90%、DSP < 95%。也需要检查局部可放置性、固定 DDR / RGMII / 时钟区域及实际布线关键路径。

## 报告与记录

- hardware/PACKAGE_README.md、SOURCE_CHECKS.json、PACKAGE_MANIFEST.json。
- 各板 PACKAGE_README.md、SOURCE_PROVENANCE.json、artifacts/README.md。
- 副板 reports/factored_final_delivery/COMPLETED_RELEASE.json。
- 副板 reports/factored_delivery_quality/QUALITY.json、reports/factored_functional_review/FUNCTIONAL_REVIEW.json。
- 各板 artifacts/evidence/ 与 02_sim/ 中的原始记录。

构建脚本中的工具路径和运行参数需按本机环境配置。
