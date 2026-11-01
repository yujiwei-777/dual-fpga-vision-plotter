# 副板固定脏斑补偿与低分输出源工程移交包

对应`dual_fpga_secondary_20261101_doc_dirt_lowconf_factored_diagnostic.bit`，SHA256：`5066DC18572D27361957A63C1702EA3CD060CAEDAB88A0172F8A3C86451C1F34`。artifacts/保留原交付bit，05_boot/best_result/提供同哈希归档副本。器件PH1P35MDG324，speed -3，顶层secondary_top；TD Release2026.1 SP2，工程版本6.2.200067。

本版文档复制使用320×180网格、4×4原像素读取和原物理映射/容量，对当前摄像头右侧固定脏斑做局部背景补偿。普通CNN生产参数CNN_LOWCONF_OUTPUT=1保留真实缩放margin及软拒绝flag6，仍需3次确认，真正零分不能新建类别，已确认类别最多保持2次不确定结果。保留PCB、KEY1/KEY2、KEY3应用复位、KEY4停止、矢量字模、镜像、换行和GRBL链路。KEY3不复位外部GRBL/ESP32；最后一条ok是控制器接收，不能证明机械Idle。

## 打开与重建

完整解压到短英文目录，先用Python3.9+运行`python verify_package.py`。根`secondary_cnn_multibox.al`派生自最终factored综合入口，仅路径改为包内相对引用；80条File引用（含5条AutoExcluded仿真依赖）全部闭合。main/是副板自身必需的DDR/IP/以太网依赖，不能删除。初始化文件和include保持原布局。

运行`python prepare_portable_run.py --runs portable_Runs`仅准备新综合/布线输入，不运行TD、不生成bit。准备脚本保持两级run深度及最终run.tcl、settings.cfg的area_prior与CDC/reset/SCLK钩子。以各自syn_1、phy_1为工作目录按顺序使用兼容TD执行run.tcl。新构建需重新执行全部资源、时序、CDC/FIFO/DDR/reset/DRC、只读reimport和发布门槛；旧release_gate不能批准新数据库。run_bitgen.tcl仅以历史证据收录，不复制到准备目录。历史builder/回归脚本可能依赖旧兄弟工程或工具路径，使用前需适配。

最终身份以`artifacts/README.md`、最终_BUILD.json和`reports/factored_final_delivery/COMPLETED_RELEASE.json`为准；其同目录README仍有准备阶段NOT_READY描述，属于历史过程。两阶段冻结快照各270项、合并271个不同输入均按当前文件逐项核对；正式完成记录949项绑定证据中948项随包保留并映射，唯一TD routed数据库不打包，旧数据库哈希记录仍保留。七套回归、专项低分/脏斑、真实回放源图和向量、最终物理/只读日志齐全。原物理审核对五项AutoExcluded仿真依赖的误判、精确补充清单及重验过程均原样保留。

最终setup/hold WNS为+0.005/+0.020ns，TNS0；Slice91.70%、ERAM84.26%、DSP45.00%。setup余量小，继承SLATR-1036/1038各10条，不是无警告版本。构建证据不等于实板稳定性或书写可读性验收。

## 质量限制

固定补偿针对当前机位/裁剪，不是通用纸纹或阴影去除；真实弱墨跨越脏斑样本不足，浅墨仍可能遗漏。5张历史纸边/阴影空白误路径总数旧方案41、精确4×4方案36、固定补偿71，不能宣称通用误画改善。51帧软件对照属于历史，本工程两张实拍完整RTL回放为空白0路径、笔迹30路径351点417行G-code。低分允许输出不代表分类准确率提高，margin分数不是校准概率。

实板、真实写字质量、完整物理网口断链矩阵及本次主副板组合均为NOT_RUN。校验器针对原封移交包；新增构建目录后需用新构建的记录验收。本次未修改原工程、模型、bit或work/，没有重新综合或下载板卡。
