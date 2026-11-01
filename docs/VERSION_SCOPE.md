# 当前版本功能范围

本页对应仓库 README 列出的 2026-11-01 主副板 bit，依据包内实际顶层连接、参数和 RTL 整理。历史介绍、试验模块和旧报告不代表本次发布已启用的功能。两板 bit 的 SHA256 与用户实测确认见 [验证记录](VALIDATION.md)。

## 与旧版介绍的区别

| 主题 | 当前应采用的说明 |
| --- | --- |
| 系统目标 | 图像采集、普通目标识别、PCB 二分类、结果书写与手写笔迹描摹组成完整流程 |
| PCB 操作 | 固定窗口辅助摆放；主板 KEY4 每次按下触发一次，长按不连拍；不再描述为空工位背景采集或按键录入良品模板 |
| PCB 结果 | PASS / FAIL / REVIEW，左下角状态显示；固定摆放框不是缺陷定位框 |
| 普通 CNN | 输出实际名称、中心点像素坐标及 margin 分数，含连续确认、短暂保持与低分输出 |
| 文档复制 | 摄像头整帧按比例映射，提取中心线路径；不做 OCR，不保证标准汉字笔顺，不要求纸张四角定位 |
| 写字报告 | 单线矢量字模、统一一次 X 镜像、按实际内容高度换行；KEY2 每按一次画一个方框 |
| 按键 | 副板 KEY3 复位整个 FPGA 应用，KEY4 停止与重置写字任务；不是旧版仅靠 KEY3 重新布防的操作 |
| A4 | 保留纸面坐标与安全边界；当前主板已移除相机 A4 测距，模式 11 保留 |
| 运动数值 | 所选运动区域内的变化采样点数，不是累计经过人数、物体数或运动事件数 |
| 亮度 | 固定亮度曲线也进入传给副板的图像支路，不能宣称亮度变化只影响 HDMI |
| 实测状态 | 用户于 2026-11-01 确认指定组合全部通过实测；原始历史 NOT_RUN 记录仍保留 |

## 普通 CNN 与 PCB 输入

普通 CNN 使用 RGB8 64×64 输入、9 类输出和 FC3 分类层。前端以 160×90 色度连通域生成候选，再按现有 ROI 契约送入分类器。稳定模块按候选位置关联结果，连续 3 次新推理确认后更新，短暂不确定可保持 2 次；重复显示帧不算新的确认。当前 FC_CONF_SHIFT=8。低分输出不改写模型分数，也不能据此声称准确率提高。

PCB 使用固定窗口 x=158..1113、y=140..551，宽 956、高 412，按原硬件采样公式产生 96×96 Y8 输入。模型为 4→4 轻量二分类。报告使用 PASS / FAIL / REVIEW，不能将固定窗口本身解释为检测到的缺陷区域。

依据：[副板顶层](../hardware/secondary_doc_dirt_lowconf_factored_20261101/01_rtl/secondary_top.v)、[识别流水线](../hardware/secondary_doc_dirt_lowconf_factored_20261101/01_rtl/vision_pipeline.v)、[CNN 稳定模块](../hardware/secondary_doc_dirt_lowconf_factored_20261101/01_rtl/cnn_result_stabilizer.v)。

## 文档采样、脏斑补偿与路径

1280×720 有效图像映射为 320×180 网格，位于内部 320×320 画布的 y=70..249，其余补白。每格读取对应 4×4 源块，16 个 Y 中至少 2 个满足 Y≤112 才判为笔迹。

本版针对固定机位右侧脏斑，在有效网格 x=288..319、y=112..179，即相机 x=1152..1279、y=448..719 区域增加局部背景对比：第二暗像素除满足基础阈值外，还需比背景均值至少暗 12。该区域没有直接强制清白；这项补偿不等于通用纸纹、阴影或颗粒去除，换机位后应重新验证。

骨架规划优先从真实端点起笔，随后处理剩余分支与闭环；分叉处优先直行或不超过 45° 的延续，普通折角保留。容量上限仍为 MAX_EDGES=32768、MAX_PATHS=2048、MAX_POINTS=8192，保留提交、容量和机器边界检查。

依据：[文档前端](../hardware/secondary_doc_dirt_lowconf_factored_20261101/01_rtl/doc_image_frontend.v)、[笔画规划器](../hardware/secondary_doc_dirt_lowconf_factored_20261101/01_rtl/doc_stroke_planner.v)。实拍回放范围与已知限制见 [验证记录](VALIDATION.md)。

## 运动显示与亮度

当前主板采用 4×4 亮度块生成 320×180 运动网格，结合亮度自适应差分、区域筛选和连续确认输出运动框。OSD 计数来自所选区域的变化采样点数，会随运动强度和范围改变，不应作为累计通行计数使用。

显示固定亮度曲线同时进入 fixed tap，可能改变副板接收到的像素。显示空间滤波与识别输入的连接需要分别核对，不能笼统写成“所有图像处理均不影响识别”。当前顶层将距离显示输入接为常量关闭。

依据：[主板顶层](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/design_top_wrapper.v)、[运动检测](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/motion_detect.v)、[运动区域筛选](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/motion_region_select.v)、[亮度曲线](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/display_tone_96.v)、[ISP 连接](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/isp_top_basic_core.v)。

## 写字与通信边界

普通 CNN、PCB、文档与 KEY2 的正常任务均在最后一条 G-code 收到 ok 后完成逻辑任务；ok 表示 GRBL 接收，不保证机械已经 Idle。停止、异常与恢复仍保留状态查询。已接受写字任务由副板本地持有，以太网断开不取消任务，也不在重连后重放已确认的运动命令。UART / GRBL 状态不确定时按独立的停止与恢复流程处理。

镜像只作用于送往写字机的机器坐标；图像中心点、网络检测框和 HDMI 坐标不随写字镜像修改。操作与参数见 [硬件与控制](HARDWARE_AND_CONTROL.md)。

## 归档与说明修订

hardware/ 保持最初移交包的精确文件集合和字节，旧注释及历史记录不在原包内改写。v2026.11.01 标签和已发布的源码资产也保留初次归档身份。main 分支的本页、README 和外层 docs/ 是核对后的说明；阅读旧归档时请同时参照这些修订。此次说明修订不改变 RTL、模型、约束或 bit。
