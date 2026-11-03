# PCB 二分类重新训练：限定样本与共享 CCL 原框

已完成独立重训、整数回放和 CNN 核心 RTL 对照。旧模型、旧 bit、原工程、主板和 work/ 保留。当前交付是候选模型，未集成整板或生成新 bit，实板状态 NOT_RUN。

## 数据与输入

只使用用户指定的 D:/ai/1/0/ 和 D:/ai/1/8/1/：870 张良品、209 张缺角、415 张缺焊盘，共 1494 张原始 YUYV 帧。标签按用户确认的子目录定义，未使用普通 CNN 的类别注释作为 PCB 真值。

共享 CCL 继续采用 160×90、源 Y≤112、四邻接与最大候选规则。模型输入采用 **CCL 原框 ×1.0**，从原始 Y8 按整数点采样读取 96×96，不使用 RGB 转灰、掩膜、旋转校正或 Y−128。现有 ×1.2 适配器必须同步改为 ×1.0 才能接入本模型；只替换权重不能满足输入契约。

44 张原始候选框触碰画面边界的帧保留为门控 REVIEW，不伪造 ROI 训练。其余 1450 个有效输入按采集组中的连续 20 帧分块，划分转换处两侧各留 2 帧 guard。有效输入为 train=713、validation=286、test=231、guard=220。guard 不参与训练；没有原始帧重复或跨划分重复。

## 训练与冻结

从随机参数开始，同时训练两层卷积和 FC 分类层，没有使用旧模型初始化。结构保持 1→4→4、两层 3×3 stride=2 padding=1、6×6 sum>>5、FC64→2，总计 308 个 int8 权重和 10 个 int32 偏置。量化移位保持 7/7/8，margin 门限保持 32，类别 0=GOOD、1=BAD。

两个预定随机种子各训练 120 epoch；前 25 epoch 为浮点训练，之后采用与硬件 floor/饱和规则一致的 float64 QAT。训练只做轻度亮度和噪声增强，没有在线新增搜索或几何变换。按 validation 的分组效用选取 checkpoint 和种子；选中 seed=20261103。先冻结模型再进行最终 test 回放，没有用 test 选择模型。

## 同一组留出帧的结果

下表均使用 CCL 原框 ×1.0 与同一组 231 个有效 test 输入，门限保持 32。BAD 被判 PASS 是缺陷误放行；REVIEW 单列，不能算成缺陷已检出。

| 项目 | 原冻结二分类模型 | 新模型 |
|---|---:|---:|
| 按最大 logit 分类正确 | 197/231，85.28% | 222/231，96.10% |
| 良品 PASS / REVIEW / FAIL（135 张） | 129 / 3 / 3 | 132 / 2 / 1 |
| 缺陷 PASS / REVIEW / FAIL（96 张） | 29 / 0 / 67 | 7 / 1 / 88 |
| 正确且通过门限 | 196/231 | 220/231 |

新模型减少了缺陷误放行，但仍有 7 张缺焊盘图被判为 PASS，集中在最新缺焊盘采集组。该组留出的 32 张图为 7 PASS、1 REVIEW、24 FAIL。不能据此宣称质检已可靠。validation 的缺陷误放行为 0、test 为 7，进一步说明需要保留分组结果，不能只看训练拟合率。

这些帧已被用于以往开发观察，分块 test 可以减轻相邻帧混用，却不属于新工位、新板或新采集会话的独立实拍验收。没有空工位、复杂背景或新板泛化结论。

## 数值与 RTL 验证

- 全部 1450 个有效输入：独立 int64 回放 logits 与导出结果完全一致。
- 15 个实帧和 6 个合成／随机输入：checkpoint、MEM 回读、QUANTIZED、float64 QAT、独立整数与 batch 模型的 Conv1、Conv2、pool、logits 一致。
- CNN 核心 RTL：15 个实帧和黑／灰／白输入共 18/18 通过。每例真实运行 889996 个周期，检查全部 Conv1 9216 值、Conv2 2304 值、池化、logits、class、score、margin，饱和计数为 0。未 force 分类输出。
- 已证明合法 Y8 输入范围内 27 位累加器、signed16 池化操作数和 20 位 logits 的安全边界。

这是核心计算验证，没有证明新模型整板 CCL 裁剪、取消／重入、普通 CNN／文档／写字回归、综合、布局布线或实板质量通过。现有其他版本的综合、时序或 bit 不作为本模型交付证据。

## 文件与接入限制

- model/selected/：冻结权重、偏置、MODEL.json、QUANTIZED.npz 和边界证明。
- train_ccl_binary.py：本轮训练与导出脚本。
- data/POLICY.json、MANIFEST.json、SUMMARY.json、SPLIT_AUDIT.json：来源与划分。
- reports/TRAINING_REPORT.json：新旧模型各划分、各采集组结果。
- reports/SELECTION_BEFORE_TEST.json：test 前冻结记录。
- reports/contract_audit/FULL_REPLAY_AUDIT.json：全量独立整数审查。
- reports/rtl_core/LATEST.json：本轮核心 RTL 回归入口。
- reports/INTEGRATION_CONTRACT.json：必须一起核对的裁剪和量化契约。
- SHA256_DELIVERY.json：交付清单。

MODEL.json 中 RTL=NOT_RUN_FOR_THIS_MODEL 是模型导出时冻结状态；后续 18 例核心 RTL 结果以 reports/rtl_core/LATEST.json 为准。它不代表整板已验证。硬件仍为 NOT_RUN。

权重 SHA256：92A3BBFD2192CC3D74A5BD3A893A34FCC3D45AE727DBEB8DEFAC56033634874B

偏置 SHA256：88F1FC576BB24DC35FA58B5620F09CFBA7B61E600B5E92DE2CAD40DA2080B2D0
