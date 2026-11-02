# r4 reader 与共享读路径补充回归

权威小型入口：`RESULTS.json`、`AUDIT.json`、`PIXEL_COMPARISON.json`、`MIRROR_INDEX.json`。

当前 r4 冻结源实际通过 12 场景、506 项检查。44 个返回像素逐项比较源地址计算、YUYV 亮度字节和整数 RGB 结果；并非只检查交易数量。37 个 client word 与 37 个 app command 一一匹配，编译及仿真均零错误、零警告。

真实 `vision_pixel_reader`、`hxa_ddr_store` 运行于 8ns/14ns 数字时钟；top 共享读所有权及 mux、HXA 读路由/outstanding 逻辑直接由冻结源抽取。脚本、bench、源切片及哈希均随报告保留。生产源未修改。

显式取消与 KEY4 取消均在旧 doc 请求已送往 app 后，尝试启动新 normal owner 并提出新像素请求。直到旧像素返回的每个周期及 pixel-valid 边沿，检查仍属于原 doc owner/purpose=2、保持 frame lock/pending，且没有新增 client 请求。旧像素先按原坐标逐值核验；drain 释放后，再用新 generation 发起并核验新 normal 请求。

覆盖 calibration 门控、全部 8 个 Y 字节位置及奇偶 RGB、跨 word/行与帧尾地址、cache 及失效、app 背压及同周期响应、color direct-word 与 doc/normal/CRC 隔离、网络变化下 PCB 读保持、显式/KEY4 doc 取消排空及重入、丢失响应保持锁定与 raw-reset 重入。

完整日志和仿真库留在 E:/codex_pose7_reader_20261102_r4/run_20261102T072040_848611Z/。本目录只镜像小型结果、审计和测试源。

限制：使用行为 app 响应，不包含 vendor DDR 控制器/PHY，不验证物理 CDC 或真实延迟。源切片不是完整 secondary_top/HXA FSM；owner/CRC 状态是受控输入。完整模型逐值由独立 fullpipeline 回归覆盖，其像素 reader 为抽象模型。实板仍为 NOT_RUN。
