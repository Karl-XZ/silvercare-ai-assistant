# 银龄智护 V1 硬件集成规划

本目录用于把当前已经完成的单模块实验，收敛为可进入原理图、BOM、PCB 和整机联调阶段的工程资料。

> 当前边界：本项目为比赛/初期开发版本，外壳优先采用 **3D 打印**。本目录不引入其它项目中的金属外壳、金属触控等约束。

## 当前目标

1. 把每个核心功能按“已验证 / 未验证 / 技术路径问题 / 供应链问题 / 集成问题”分类；
2. 按 P0 / P1 / P2 排优先级；
3. 建立主控候选、核心 BOM、逻辑信号网络和电源树；
4. 先在原理图层面验证整机是否能连接、供电和并发工作；
5. 再根据 BOM 做采购可得性和成本检查；
6. 最后决定哪些技术方案保留、替换或降级。

## 文件

- [`v1-hardware-status-and-issue-report.md`](./v1-hardware-status-and-issue-report.md)：当前硬件状态与问题报告
- [`v1-core-bom.csv`](./v1-core-bom.csv)：核心元器件与候选 BOM
- [`v1-signal-net.csv`](./v1-signal-net.csv)：逻辑信号网络 / 核心连接关系
- [`v1-power-tree.csv`](./v1-power-tree.csv)：V1 电源树与待确认电源参数
- [`v1-mcu-comparison.csv`](./v1-mcu-comparison.csv)：主控候选比较

## 当前架构原则

```text
眼镜端：Camera / IMU / MIC / Haptic / Audio OUT / 采集与传输
                           │
                      主控 MCU/SoC
                           │
                     BLE / Wi-Fi
                           │
Android 手机：视觉 AI / ASR / LLM / TTS / 任务闭环 / 网络 / 管理
```

当前不要求眼镜端独立运行完整 AI。第一版优先目标是：**把感知、反馈、通信和电源做成稳定的统一硬件平台。**

## 原理图阶段冻结原则

- 逻辑接口先冻结，最终 GPIO 号后冻结；
- 两条主控路线允许并行：ESP32-S3R8 与 BK7258；
- 未验证的器件不得因为“理论支持”直接视为已完成；
- 音频输出、电源、主控 PinMux、采购料号属于当前最高优先级；
- 所有 P0 问题关闭后，再进入第一版集成 PCB。
