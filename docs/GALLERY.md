# 演示图集

## 系统架构

![双 FPGA 系统架构](assets/system-architecture.png)

主板完成图像采集、显示和任务调度；副板完成 CNN / PCB 识别及文档路径规划；写字命令经串口无线桥接转发到 GRBL 控制器。

[SVG 矢量图](assets/system-architecture.svg)可用于报告和答辩材料。绘图脚本为 [render_architecture.py](render_architecture.py)，依赖 Pillow；字体路径可通过 DIAGRAM_FONT 和 DIAGRAM_FONT_BOLD 配置。

### 技术文档总体框图

![双 FPGA 协同视觉处理与控制系统总体框图](assets/pdf_20261102/architecture-system.png)

技术文档第 5 页，图 2.1：展示主板采集显示、副板识别规划、HXA1 回传和 DLC32 执行链路。

### 硬件连接与接口

![摄像头、主副板、DDR、显示器及写字机硬件连接](assets/pdf_20261102/architecture-hardware.png)

技术文档第 6 页，图 2.2：展示板间以太网、各板 DDR、HDMI、UART 与无线桥接关系。

### 关键电路与模块接口

![MIPI、ISP、DDR 调度、HXA1、CNN 与 GRBL 的模块接口](assets/pdf_20261102/architecture-modules.png)

技术文档第 8 页，图 2.4：展示视频、缓存读写和控制模块的概念性连接。三张图均由 PDF 页面高分辨率渲染并裁切，保留原图题与图例；具体 RTL 支路、任务入口和当前功能以[版本说明](DISPLAY_NOISE_KEY1_20261103.md)为准。

## 实拍：图像采集与处理

| 摄像头画面 | 边缘提取效果 |
| --- | --- |
| ![摄像头拍摄写字机并输出 HDMI 画面](assets/hdmi-live.jpg) | ![同一写字机场景的边缘提取显示](assets/hdmi-edges.jpg) |

## 实拍：普通目标识别

| 圆柱与三角物块 | 红色与蓝色物块 |
| --- | --- |
| ![圆柱与三角物块的识别框及标签](assets/cnn-targets.jpg) | ![红色和蓝色物块的多目标识别](assets/cnn-multiple.jpg) |

这些照片记录了开发阶段的识别与显示效果，界面采用当时的 OSD 布局。当前版本的输出字段和按键操作见 [硬件与控制](HARDWARE_AND_CONTROL.md)。

## 实拍：写字机平台

![写字机笔夹、纸面及开发阶段绘制结果](assets/plotter-hardware.jpg)

写字机通过笔夹安装普通笔，接收 GRBL 运动指令完成纸面绘制。图中为开发阶段的调试纸张。

## 文档描摹：实拍输入与 RTL 回放

![实拍笔迹的原始亮度、二值图与彩色路径回放对照](../hardware/secondary_doc_dirt_lowconf_factored_20261101/reports/factored_delivery_quality/INK2358_COMPARISON.png)

左上为相机采集的原始亮度图，其余面板为二值化及 RTL 路径回放。绿色框标出固定脏斑补偿区域，彩色线用于区分路径。这组回放得到 30 条路径、351 个规划点和 417 行 G-code；回放图不代表写字机实绘结果，图底状态保留生成时记录。

## 技术文档补充图片

以下图片提取自《视觉识别质检与控制描摹系统_技术文档_20261102 (1).pdf》。展示的是文档记录的开发阶段效果，按键与界面以当前版本说明为准。

### 18 种图像处理效果

第 16 页：灰度化、二值化、边缘提取、反向边缘、浮雕、腐蚀、膨胀、形态梯度和负片。

![灰度、轮廓和形态学处理的九种实拍效果](assets/pdf_20261102/style-overview-1.jpg)

第 17 页：红色通道、蓝色通道、伪彩、卡通化、海报化、饱和度增强、暗部提亮、伽马提亮和对比度拉伸。

![颜色变换、风格化及增强的九种实拍效果](assets/pdf_20261102/style-overview-2.jpg)

两张总览仅排列原图并添加模式名称。各模式单张图片也保存在 [pdf_20261102](assets/pdf_20261102/) 中，可点击查看。

### CNN 九类物块示例

![红、绿、蓝三种颜色与三类形状的九类物块样本](assets/pdf_20261102/cnn-training-examples.jpg)

提取自第 11 页，用于展示普通 CNN 的目标类别组合；这张样本图不代表独立测试准确率。

### 运动区域检测与手写采集

| 局部运动区域检测（第 18 页） | 手写笔迹采集画面（第 18 页） |
| --- | --- |
| ![手部运动时的检测框](assets/pdf_20261102/motion-detection.jpg) | ![纸面手写内容的摄像头取景](assets/pdf_20261102/document-input.jpg) |

手写照片是输入画面，实际规划路径回放见上方“文档描摹”章节。

### 历史 PCB 取景界面

![开发阶段 PCB 与绿色参考框的取景画面](assets/pdf_20261102/pcb-view.jpg)

提取自第 19 页。图中绿色框是当时版本的固定摆放参考框，不表示缺陷位置；当前 CCL 版本按副板返回的实际候选框显示，不能用本图证明当前版本检测或实板验收结果。

### HDMI 信息叠加

| Logo 显示（第 15 页） | 延迟与状态字段（第 20 页） |
| --- | --- |
| ![HDMI 左上角的安路 Logo](assets/pdf_20261102/osd-logo.jpg) | ![HDMI 右上角的延迟与状态信息](assets/pdf_20261102/osd-latency.jpg) |

## 图片来源

实拍照片选自项目说明书《main (1).pdf》：HDMI 显示和写字机照片见第 13 页，边缘提取见第 15 页，物块识别见第 17 页。发布图片仅等比例缩小并压缩为 JPEG，未修改识别标签或绘制结果。

路径对照图来自当前副板工程的 factored_delivery_quality 报告；系统架构图按当前工程连接绘制。

补充图片从 2026-11-02 技术文档的内嵌图像提取，最长边最多 1280 像素，小图不放大。保留原始画面、检测标签及结果，仅做等比例缩放、JPEG 压缩和去除 EXIF；两张效果总览另外添加了模式名称。PDF SHA256、页码、内嵌图片名称和发布图片 SHA256 见 [来源清单](assets/pdf_20261102/SOURCES.json)。图片的许可范围见[第三方与许可说明](THIRD_PARTY_NOTICES.md)。
