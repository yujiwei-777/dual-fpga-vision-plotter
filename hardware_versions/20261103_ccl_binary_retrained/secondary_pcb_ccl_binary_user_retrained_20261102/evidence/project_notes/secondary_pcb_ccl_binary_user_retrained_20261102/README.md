# 用户样本重训 PCB 二分类副板

本工程独立于旧工程、旧 bit、`work/` 和主板工程。当前构建及实板状态以 `reports/retrained/` 下本轮报告为准，不能用复制而来的工具或历史报告认定通过。

## 模型和输入

仅使用用户指定的 `D:/ai/1/0/` 与 `D:/ai/1/8/1/` 中已确认标签的样本，从头训练 PCB C4/C4 二分类模型。训练目录为 `../pcb_ccl_binary_user_retrain_20261102/`，不修改冻结训练交付。

- 与普通 CNN 分时共享 CCL；PCB 使用源 Y≤112 的 160×90 网格，采样坐标为 `(8*x+4,8*y+4)`。
- 取最大有效候选的原始半开框 **×1.00**，按 `origin+floor((2*u+1)*span/192)` 采样 96×96 源 Y8。输入不归一化、不做方向校正。
- 模型为 1→4→4、两层 stride2 卷积及 64→2 分类头，308 个 int8 权重、10 个 int32 偏置，shift 为 7/7/8。margin<32 返回 REVIEW。
- 保留无候选、标签溢出、源边界及非法框拒绝；不把整块 PCB 框当作缺陷框，defect_count=0。
- 活动 PCB 配置标识为 `0x50434233`。

权重 SHA256：`92A3BBFD2192CC3D74A5BD3A893A34FCC3D45AE727DBEB8DEFAC56033634874B`。

偏置 SHA256：`88F1FC576BB24DC35FA58B5620F09CFBA7B61E600B5E92DE2CAD40DA2080B2D0`。

## 已知准确率限制

231 个有效测试帧中，新模型分类正确 222 个（96.10%），旧模型为 197 个（85.28%）。新模型仍有 **7 张缺焊盘被接受为 PASS**，另有 1 张良品 FAIL、3 张 REVIEW。这些来自既有拍摄批次的分块划分，并非新板或独立拍摄盲测。验证集与测试集表现有差异；不能据此承诺任意摆放、光照或新工件的准确率。

## 功能保护和交付

保留普通 CNN 模型及低置信度候选发布规则、文档复制、摄像头污点处理、KEY1/KEY2/KEY3/KEY4、矢量字模、一次 X 镜像、换行、GRBL 最终 ok 完成、已接受写字任务断网保持、HXA1 和 DDR 行为。正常最后 ok 是 GRBL 接收确认，不等于机械已 Idle。

功能冻结构建位于 `E:/codex_pcb_binary_ccl_retrained_20261102_r2/`，源码清单 SHA256 为 `92E737ED8B7D585AEAAC64346A130A2AA7A9F2077A70B14A8CE2D036506A57DB`。r1 已被主板协议兼容修复取代，未生成 bit，不能用 r1 的综合数据代表 r2。最终必须满足 routed setup/hold WNS≥0、TNS=0、Slice<95%、ERAM<90%、DSP<95%，并有本轮数值/集成回归、CDC/FIFO/DDR/DRC 和只读重导入证据，才允许 bitgen。

物理续跑位于 `E:/codex_pcb_binary_ccl_retrained_20261102_r3/`，清单 SHA256 为 `31F6BE091C83865F4E2E5B1F5CA7EA82108F15654C023B7DB603EFD35D88375F`。r3 的 RTL、模型和数值约束与 r2 字节相同，仅项目根路径改变，另增严格物理证明 overlay。r2 的真实综合与已完成布局 checkpoint 作为继承证据保存；r2 原布局后 CDC helper 失败记录也完整保留，未伪造新的综合或布局完成标记。新 overlay 只验证 DDR 校准首级同步器合法折叠的 LUT5A 译码，第二级同步器和时序预算不放宽；独立 21 项故障注入通过。r3 重新证明布局后映射，实际完成 route 和只读 reimport。最终 Slice 19247/21216（90.72%）、ERAM 82/108（75.93%）、DSP 18/40（45.00%）；setup WNS +0.005 ns、hold WNS +0.020 ns、两项 TNS=0。`reports/retrained/physical_gate_r3/PHYSICAL_REVIEW_R3.json` 为物理补充证据，不能单独替代最终功能及 bitgen 门槛。

PCB 单目标结果使用现有 Type8，普通 CNN 多框结果使用 Type18。现有主板只接收 0..100 的 Type8 置信度字段；本版将模型原始 0..255 分数按 `floor((raw_score*100+127)/255)` 转换到协议范围，内部分类、logits 和 margin=32 保持不变。该传输分数不是经过校准的准确概率。使用 `main_pcb_auto_compat_20261101` 的实际报文、CRC 和结果解码模块，PASS/FAIL/REVIEW/ERROR 四种状态的兼容仿真已通过，详见 `reports/retrained/main_protocol_compat_v3/RESULTS.json`。原始未缩放的 255 会被该主板拒绝。主板 PCB 等待时间为 30 秒；完整实板链路仍需验收。

本轮只做副板，主板未修改。实际 PCB/CNN 显示兼容性、采集光照/占比、写字机、断网续写、停止/复位及 DDR 电气验证均需实板验收。新 bit 在验收前标记 **NOT_RUN**。
