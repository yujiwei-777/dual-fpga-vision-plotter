# 当前版本功能范围

本页介绍 2026-11-01 主副板版本的算法参数、功能范围和源码入口。bit 校验值及实板测试情况见 [验证记录](VALIDATION.md)。

## 与旧版介绍的区别

| 主题 | 当前实现 |
| --- | --- |
| 系统目标 | 图像采集、普通目标识别、PCB 二分类、结果书写与手写笔迹描摹组成完整流程 |
| PCB 操作 | 固定窗口辅助摆放；主板 KEY4 每次按下触发一次，长按不连拍；不采用背景建模或按键模板录入 |
| PCB 结果 | PASS / FAIL / REVIEW，左下角状态显示；固定摆放框不是缺陷定位框 |
| 普通 CNN | 输出实际名称、中心点像素坐标及 margin 分数，含连续确认、短暂保持与低分输出 |
| 文档复制 | 摄像头整帧按比例映射，提取中心线路径；不做 OCR，不保证标准汉字笔顺，不要求纸张四角定位 |
| 写字报告 | 单线矢量字模、统一一次 X 镜像、按实际内容高度换行；KEY2 每按一次画一个方框 |
| 按键 | 副板 KEY3 复位整个 FPGA 应用，KEY4 停止与重置写字任务 |
| A4 | 保留纸面坐标与安全边界；当前主板已移除相机 A4 测距，模式 11 保留 |
| 运动数值 | 所选运动区域内的变化采样点数，不是累计经过人数、物体数或运动事件数 |
| 亮度 | 固定亮度曲线同时作用于 HDMI 和传给副板的图像 |
| 实测状态 | 通过，测试结论见版本验收记录 |

## 普通 CNN 与 PCB 输入

普通 CNN 使用 RGB8 64×64 输入、9 类输出和 FC3 分类层。前端以 160×90 色度连通域生成候选，再按 ROI 采样规则送入分类器。稳定模块按候选位置关联结果，连续 3 次新推理确认后更新，短暂不确定可保持 2 次；重复显示帧不算新的确认。当前 FC_CONF_SHIFT=8。低分结果保留原始模型分数。

PCB 使用固定窗口 x=158..1113、y=140..551，宽 956、高 412，按硬件采样公式产生 96×96 Y8 输入。模型为 4→4 轻量二分类。报告使用 PASS / FAIL / REVIEW，窗口仅用于辅助摆放。

依据：[副板顶层](../hardware/secondary_doc_dirt_lowconf_factored_20261101/01_rtl/secondary_top.v)、[识别流水线](../hardware/secondary_doc_dirt_lowconf_factored_20261101/01_rtl/vision_pipeline.v)、[CNN 稳定模块](../hardware/secondary_doc_dirt_lowconf_factored_20261101/01_rtl/cnn_result_stabilizer.v)。

## 文档采样、脏斑补偿与路径

1280×720 有效图像映射为 320×180 网格，位于内部 320×320 画布的 y=70..249，其余补白。每格读取对应 4×4 源块，16 个 Y 中至少 2 个满足 Y≤112 才判为笔迹。

本版针对固定机位右侧脏斑，在有效网格 x=288..319、y=112..179，即相机 x=1152..1279、y=448..719 区域增加局部背景对比：第二暗像素除满足基础阈值外，还需比背景均值至少暗 12。该区域没有直接强制清白；这项补偿不等于通用纸纹、阴影或颗粒去除，换机位后应重新验证。

骨架规划优先从真实端点起笔，随后处理剩余分支与闭环；分叉处优先直行或不超过 45° 的延续，普通折角保留。容量上限仍为 MAX_EDGES=32768、MAX_PATHS=2048、MAX_POINTS=8192，保留提交、容量和机器边界检查。

依据：[文档前端](../hardware/secondary_doc_dirt_lowconf_factored_20261101/01_rtl/doc_image_frontend.v)、[笔画规划器](../hardware/secondary_doc_dirt_lowconf_factored_20261101/01_rtl/doc_stroke_planner.v)。实拍回放范围与已知限制见 [验证记录](VALIDATION.md)。

## 图像风格化、运动检测与成像调节

### 图像处理与风格化

主板采用定点运算、行缓存和流水线实现原图及 18 种图像处理模式。按处理类型可分为：

| 类型 | 模式 |
| --- | --- |
| 亮度与颜色变换 | 灰度化、二值化、负片、红色通道、蓝色通道 |
| 轮廓与形态学 | Sobel 边缘、反向边缘、浮雕、腐蚀、膨胀、形态梯度 |
| 图像风格化 | 伪彩、海报化、卡通化 |
| 视觉增强 | 饱和度增强、暗部提亮、对比度拉伸、伽马提亮 |

模式通过按键切换，OSD 同步显示模式信息。卡通化结合边缘提取与颜色量化，其他模式使用像素映射或邻域运算，不采用神经网络风格迁移。

依据：[风格化流水线](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/style_transfer_96.v)、[模式控制](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/style_controls.v)。实拍效果见 [演示图集](GALLERY.md)。

### 运动区域检测

当前主板采用 4×4 亮度块生成 320×180 运动网格，结合亮度自适应差分、区域筛选和连续确认输出运动框。OSD 计数来自所选区域的变化采样点数，会随运动强度和范围改变，不应作为累计通行计数使用。

### 成像质量自动调节

自动曝光控制器根据帧亮度、过曝比例和 ROI 亮度统计，反馈调整 SC500 曝光及模拟 / 数字增益；使用亮度死区、调整间隔和恢复保持等控制，限制频繁调节。RAW 域自动白平衡采用灰世界统计，按颜色通道反馈调整增益。当前顶层启用 RAW 自动曝光统计与 RAW 自动白平衡。

显示支路另有保边空间滤波，用于减轻细小颗粒；空间滤波不使用历史帧，不属于 TNR。自动成像调节、固定亮度曲线和显示滤波是不同环节，实际效果受光源、场景颜色和传感器噪声影响。

固定亮度曲线同时进入 fixed tap，会影响副板接收到的像素；显示空间滤波则使用独立的支路连接。当前顶层的距离显示输入固定关闭。

依据：[自动曝光与增益控制](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/uiisp_beta/ae_auto.v)、[RAW 自动白平衡](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/awb_raw10_bggr_grayworld.v)。

依据：[主板顶层](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/design_top_wrapper.v)、[运动检测](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/motion_detect.v)、[运动区域筛选](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/motion_region_select.v)、[亮度曲线](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/display_tone_96.v)、[ISP 连接](../hardware/main_osd_brightness_20261101/01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/isp_top_basic_core.v)。

## 写字与通信边界

普通 CNN、PCB、文档与 KEY2 的正常任务均在最后一条 G-code 收到 ok 后完成逻辑任务；ok 表示 GRBL 接收，不保证机械已经 Idle。停止、异常与恢复仍保留状态查询。已接受写字任务由副板本地持有，以太网断开不取消任务，也不在重连后重放已确认的运动命令。UART / GRBL 状态不确定时按独立的停止与恢复流程处理。

镜像只作用于送往写字机的机器坐标；图像中心点、网络检测框和 HDMI 坐标不随写字镜像修改。操作与参数见 [硬件与控制](HARDWARE_AND_CONTROL.md)。

## 归档与说明修订

hardware/、v2026.11.01 标签及源码压缩包保留发布时的内容。README 和 docs/ 在 main 分支持续维护；旧归档中的功能介绍请参照当前文档。
