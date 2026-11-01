# 副板固定脏斑补偿与 CNN 低分输出 diagnostic

状态：`DIAGNOSTIC_NOT_RUN`。本轮只构建副板，主板未修改，未进行下载或实板验证。

## 下载文件

`dual_fpga_secondary_20261101_doc_dirt_lowconf_factored_diagnostic.bit`

SHA256：

```text
5066DC18572D27361957A63C1702EA3CD060CAEDAB88A0172F8A3C86451C1F34
```

原生 `phy_1/secondary_cnn_multibox.bit` 与交付副本逐字节一致。完整构建记录见同目录 `_BUILD.json`；最终交付核验见 `../reports/factored_final_delivery/COMPLETED_RELEASE.json`，冻结输入清单见同目录 `COMPLETED_FROZEN_INPUTS.csv`。

## 本轮功能

- 文档复制对当前摄像头右侧固定脏斑进行局部背景补偿；保留 320×180 网格、4×4 源像素读取、物理映射和规划容量。不是整块擦除，也不是通用纸纹或阴影去除。
- 普通 CNN 的软门限低分保留真实缩放 margin，经现有稳定器后可输出名称、中心坐标及分数至 Type18 和 KEY1 写字报告。保留原软拒绝 flag6，默认关闭参数仍保持黄金行为，生产顶层显式启用。
- 保留连续 3 次确认、零分不确定结果最多保持 2 次；真正零分不能新建类别，硬背景拒绝和无目标不会强制产生类别。分数不是经过校准的正确率。
- hard/soft 判断采用经过二态穷举和逐周期对照的等价组合改写，改善本轮实际映射和布局。没有修改 CNN/PCB 模型、阈值、DDR、HXA 或主板约束。
- 保留 KEY2、KEY3 全应用复位、KEY4 安全停止、单线矢量字体、镜像、换行和既有 GRBL 完成语义。最后一条 `ok` 表示控制器已接收，不保证机械已处于 Idle。

## 构建结果

| 项目 | 最终布线结果 |
|---|---:|
| Setup WNS | +0.005 ns |
| Setup TNS | 0 ns |
| Hold WNS | +0.020 ns |
| Hold TNS | 0 ns |
| Slice | 19455/21216，91.70% |
| ERAM | 91/108，84.26% |
| DSP | 18/40，45.00% |

综合、实际 place/route、严格资源和时序门槛、CDC/FIFO/DDR/reset/DRC 审核、只读 reimport 和 bitgen 已通过。只读 reimport 前后 DB/AL 哈希不变。本轮没有 PHY-7027/PHY-9002。继承的 DRC/旧 I/O 提示保留在报告中，不宣称零警告。

七套当前工程回归通过，另有固定脏斑与低分输出专项。两张实拍的完整 RTL 回放中，测试空白帧为 0 路径，笔迹帧为 30 路径、351 点、417 行 G-code。PCB 核心与 YUYV、普通 CNN、报告 G-code、KEY3、路径规划及稳定器生命周期/取消检查均有独立日志。

原物理审核误将五个只作为仿真附加依赖的 `AutoExcluded` 文件判为新增传输源码。五项基线/当前字节相同，133 项生产输入不变；通过精确哈希比较清单补充后，原审核规则完整重跑通过。原失败报告及补充证明保留于 `../reports/factored_manifest_completion/`；没有删除错误、修改原 reviewer 或放宽验收门槛。

## 使用限制

- 实板、写字机可读性和完整物理网口断链矩阵仍为 `NOT_RUN`。KEY3 FPGA 应用复位不代表外部 GRBL 已安全停止。
- 固定补偿只适用于当前摄像头机位/裁剪。真实弱墨穿越脏斑的样本不足；部分浅墨可能遗漏。
- 五张历史纸边/大阴影空白样本的误路径总数为旧方案 41、仅精确 4×4 方案 36、固定补偿方案 71；不能据此宣称通用纸纹/阴影误画已解决。
- 历史 51 帧软件对照与本工程两张完整实拍 RTL 回放分开记录。允许低分输出可能暴露弱错误分类，不宣称分类准确率提高。

详细范围、来源哈希、图像对照和限制见 `../reports/factored_delivery_quality/QUALITY.json`；独立功能复核见 `../reports/factored_functional_review/FUNCTIONAL_REVIEW.json`。
