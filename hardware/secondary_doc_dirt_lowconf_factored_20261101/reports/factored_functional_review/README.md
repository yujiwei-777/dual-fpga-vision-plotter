# 副板功能独立只读复核

状态：PASS_READ_ONLY_FUNCTIONAL_REVIEW_WITH_STATED_LIMITS；实板 NOT_RUN。

本复核绑定新 factored 副板冻结综合输入，未改变生产源码、模型、约束、runner、gate或主板。

低分输出保留真实 margin 分数，仍需原三次同类确认；真正零分不能建立新类别。已确认类别最多保留两次零分并明确输出0。原 soft-margin flag6 保留。KEY1锁存名称、中心坐标和真实分数，已接受报告不会随实时缓存更新。

已有 fresh 仿真证据包括：低分流水线107任务/489检查、top57检查、12份逐G-code低分报告；普通CNN27次完整推理；PCB15核心+9YUYV；报告33份含顺序方框、容量和停止；真实top KEY3复位26检查；40稳定器配置、生命周期和取消。

KEY3全应用复位、KEY4安全停止/任务复位、KEY2重复任务和最后ok完成的RTL与成功控制版字节相同。网络断链保护同样保持。最后ok表示控制器接收，不等于机械已停。

另只读核对既有主板lowerleft release冻结源：Type18拒绝掩码0x38允许bit6；合法类别的0..100分数通过；overlay不另设最低分门限。没有改动或构建主板，也没有作HDMI实板验证。

覆盖界限：断网fresh top测试使用HXA/PHY受控叶模块；完整真实PHY/lease/HELLO矩阵未在本复核重跑。顺序方框是reporter仿真，不能代替连续实体KEY2测试。KEY3 FPGA复位不能证明外部GRBL安全停止。锥逻辑等价只覆盖初始化后的二值状态；不宣称X传播等价。放宽输出不会提高模型本身准确率。

综合、布局布线、资源时序、DRC、只读reimport和bitgen仍须由构建流程完成；本报告不把功能PASS当作硬件交付PASS。
