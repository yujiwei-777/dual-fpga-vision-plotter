# 2026-11-03 CCL 自动定位与 PCB 二分类

配套主板为 main_pcb_auto_compat_20261101，副板为 secondary_pcb_ccl_binary_user_retrained_20261102。完整工程位于 [hardware_versions/20261103_ccl_binary_retrained](../hardware_versions/20261103_ccl_binary_retrained/)，实板状态 **NOT_RUN**。主板 bit 与上一组相同，副板切换为重训后的 GOOD/BAD 二分类。

## PCB 算法与操作

主板选择 SW4:SW3=01、SW2=1。KEY4 按下并完成约 20 ms 消抖后触发一次识别；长按不连续抓拍，忙时不排队，松开不取消已接受任务。

副板与普通 CNN 分时复用 CCL：在 160×90 网格按源位置 (8x+4,8y+4) 取样，以 Y≤112、四连通规则找最大合法候选。采用候选原始半开框 ×1.0，从原始 Y8 读取 96×96：

    source = origin + floor((2*u+1)*span/192)，u=0..95

不做 RGB 转灰、Y−128、旋转校正或 pose7 良品异常评分。没有候选、标签溢出、坏框或越界时仍拒绝有效分类。

模型为 1→4→4，两层 stride=2 卷积与 FC64→2，308 个 int8 权重、10 个 int32 偏置，量化移位 7/7/8。类别 0=GOOD、1=BAD；原始 margin<32 为 REVIEW，否则分别输出 PASS/FAIL。模型配置 ID 为 0x50434233。

Type8 的原始 0..255 分数按 floor((score*100+127)/255) 编码到 0..100，与主板解码范围匹配。该分数不是校准后的正确概率。实际封包、CRC 和主板解码覆盖 PASS/FAIL/REVIEW/ERROR；普通 CNN 结果仍使用 Type18。

HDMI 显示副板返回的实际候选框，右、下独占坐标转换为包含坐标。defect_count=0；整块 PCB 框不是缺陷位置。主板左下状态显示最近结果，FRAME_ACK 后 PCB 结果预算为 30 秒，普通 CNN 为 2 秒；250 ms 心跳和 3 秒租约独立保持。

## 普通 CNN、文档与写字机

普通 CNN 保留 9 类模型、FC_CONF_SHIFT=8、低置信分数输出、连续确认与短暂类别保持。KEY1 锁存名称、中心点和分数，不把图像坐标当作机器毫米坐标。

文档复制保留 320×180、4×4 源块判定、固定脏斑补偿、骨架和路径规划。单线矢量报告、一次 X 镜像、按实际内容高度换行、KEY2 方框测试、KEY3 整体应用复位、KEY4 停止/重置保持此版行为。已接受的写字任务不因以太网断链取消，已发送运动命令不盲目重放。

正常任务在末条 G-code 收到 ok 后逻辑完成；ok 不表示机械已经 Idle。停止、报警、复位和恢复仍使用独立安全流程。接线、速度和操作见 [硬件与控制](HARDWARE_AND_CONTROL.md)。

## 工程入口与模型

| 内容 | 位置 |
| --- | --- |
| 主板工程 | [camera_to_dsi_display_720p60_cnn_multibox.al](../hardware_versions/20261103_ccl_binary_retrained/main_pcb_auto_compat_20261101/camera_to_dsi_display_720p60_cnn_multibox.al) |
| 副板工程 | [secondary_cnn_multibox.al](../hardware_versions/20261103_ccl_binary_retrained/secondary_pcb_ccl_binary_user_retrained_20261102/secondary_cnn_multibox.al) |
| 活动 PCB 模型 | [model/experiments/conv4_4](../hardware_versions/20261103_ccl_binary_retrained/secondary_pcb_ccl_binary_user_retrained_20261102/model/experiments/conv4_4/) |
| 重训与数据清单 | [training_reference](../hardware_versions/20261103_ccl_binary_retrained/secondary_pcb_ccl_binary_user_retrained_20261102/training_reference/) |
| 副板发布证据索引 | [RELEASE_MANIFEST.json](../hardware_versions/20261103_ccl_binary_retrained/secondary_pcb_ccl_binary_user_retrained_20261102/evidence/release_r3/RELEASE_MANIFEST.json) |
| 最终审计 | [FINAL_GATE_AUDIT_R3.json](../hardware_versions/20261103_ccl_binary_retrained/secondary_pcb_ccl_binary_user_retrained_20261102/evidence/FINAL_GATE_AUDIT_R3.json) |
| 原始来源与哈希 | [SOURCE_AND_EVIDENCE_MAPPING.json](../hardware_versions/20261103_ccl_binary_retrained/SOURCE_AND_EVIDENCE_MAPPING.json) |
| bit 身份与验收 | [release/20261103_ccl_binary_retrained](../release/20261103_ccl_binary_retrained/) |

冻结快照中仍保留旧模型和历史文件，不能据其存在判断已启用。活动模型由 r3 的 model_freeze 和工程引用确定。

~~~text
PCB weights.mem
92A3BBFD2192CC3D74A5BD3A893A34FCC3D45AE727DBEB8DEFAC56033634874B
PCB biases.mem
88F1FC576BB24DC35FA58B5620F09CFBA7B61E600B5E92DE2CAD40DA2080B2D0
~~~

## 校验与重建

完整仓库根执行 python -B verify_release.py，分别校验三组归档。也可在此版工程包根运行 python -B verify_package.py，检查文件集合、尺寸、SHA256、bit 与来源映射。

主板 189 项、副板 360 项冻结输入按原始字节保存；可移植根入口分别闭合 138、84 条 File 引用。仅根 .al 工程路径相对化，原始入口另存。副板 1,705 条发布证据记录对应 799 份内容寻址文件，含历史失败检查、检查点数据库和最终通过记录。来源映射将旧绝对路径对应到包内实际文件。

重建前复制到短英文路径，使用 Tang Dynasty 2026.1 SP2 / 6.2.200067，器件 PH1P35MDG324、speed -3。保留 IP、ROM、include 与原有启动目录布局。历史构建和仿真脚本包含原机器路径，需先适配；不能直接视为跨机器一键构建脚本。文件校验不重新运行仿真或综合，也不生成 bit。

## 验证与限制

| 板卡 | Setup WNS | Hold WNS | TNS | Slice | ERAM | DSP |
| --- | --- | --- | --- | --- | --- | --- |
| auto_compat 主板 | +0.384 ns | +0.020 ns | 0 | 92.93% | 83.33% | 92.50% |
| CCL 二分类 r3 副板 | +0.005 ns | +0.020 ns | 0 | 90.72% | 75.93% | 45.00% |

副板 r3 继承 r2 综合及布局检查点，再执行布线、物理证明和只读核验。RTL、模型与数值约束按清单绑定；DDR 首级同步器物理证明补充折叠 LUT5A 解码器的合法情况，二级同步器和时序预算没有放宽，21 个故障注入检查通过。原失败记录保留，不能将“最终审计通过”写成所有历史检查均通过。

发布证据覆盖整数、取消重入、普通 CNN、文档、写字、CDC、FIFO、DDR、DRC 和只读重导入；其中部分结果按冻结哈希继承，并非 r3 全部重跑。主板原始 RUN-8007 / USR-8450 与独立物理容量及 79 个 IO 对照同时保留。

重训只使用指定的 1,494 张实拍原始帧，其中 44 张触边帧保留门控 REVIEW。1,450 个有效输入按同采集组连续 20 帧分块，分为 train=713、validation=286、test=231、guard=220；不是新板、新会话盲测。

| 231 个有效 test 输入 | 原二分类模型 | 本版模型 |
| --- | --- | --- |
| 最大 logit 分类正确 | 197/231（85.28%） | 222/231（96.10%） |
| 良品 PASS / REVIEW / FAIL（135 张） | 129 / 3 / 3 | 132 / 2 / 1 |
| 缺陷 PASS / REVIEW / FAIL（96 张） | 29 / 0 / 67 | 7 / 1 / 88 |

仍有 **7 张缺焊盘被接受为 PASS**，不能宣称质检已可靠或以 96.10% 代表新场景准确率。REVIEW 单列，不算缺陷已检出。训练核心 RTL 18/18 与独立整数回放记录随包保存；集成回归范围以最终证据索引为准。

该主副板组合实板状态为 **NOT_RUN**。需验证完整候选、不同摆放/光照、PASS/FAIL/REVIEW 显示、普通 CNN、文档、KEY2、断网保持、停止和复位。旧版实板通过结论只绑定旧 bit。
