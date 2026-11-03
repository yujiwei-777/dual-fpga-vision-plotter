# PCB 二分类副板 diagnostic bit — NOT_RUN

bit: dual_fpga_secondary_20261102_pcb_ccl_binary_user_retrained_diagnostic.bit

SHA256: A0034350D2421B14BEBDB7CF419269EA910033AE5381BF4615F5258B5BD5A81B

只使用用户指定 D:/ai/1/0/ 与 D:/ai/1/8/1/ 样本；共享 CCL 原框 ×1.00，精确采样 96×96 源 Y8；C4/C4 二分类，margin<32 返回 REVIEW。

最终资源：{"slice": {"used": 19247, "total": 21216, "percent": 90.71926847662142, "strict_pass": true}, "eram": {"used": 82, "total": 108, "percent": 75.92592592592592, "strict_pass": true}, "dsp": {"used": 18, "total": 40, "percent": 45.0, "strict_pass": true}}

最终布线时序 ns：{"SWNS": 0.005, "STNS": 0.0, "HWNS": 0.02, "HTNS": 0.0}。Setup/hold 两角通过，TNS=0，真实只读重导入一致，bitgen 完成。

r3 是物理续跑：真实成功 r2 综合和完成 place 的 checkpoint 继承；r2 放置后映射辅助检查失败原样保留。增加精确 packed-LUT 校验后重新证明映射、布线与只读导入。未伪称新综合或新 r3 行为仿真；功能证据来自哈希完全相同的 r2 RTL/模型。全部 evidence 闭包按原文件哈希保留。

同批次分块测试 222/231 分类正确；仍有 7 张缺焊盘被误接受为 PASS、1 张良品 FAIL、3 张 REVIEW，不能据此宣称缺陷漏检已解决。

普通 CNN、文档、按键、矢量字体、镜像、换行、GRBL、已接受写字任务断网保持、HXA 与 DDR 保持。主板未修改。正常最终 ok 表示 GRBL 接收命令，不等于机械 Idle。

配套 main_pcb_auto_compat_20261101；真实主板报文/CRC/解码 RTL 兼容验证已通过。原始 0..255 分数转换为协议 0..100，是传输缩放而非校准概率。HDMI、主副板实联、真实采集与写字机验收均为 NOT_RUN。旧工程、旧 bit、work/ 与主板不覆盖。
