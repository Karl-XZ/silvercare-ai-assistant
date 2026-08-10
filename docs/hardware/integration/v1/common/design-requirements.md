# 银龄智护 V1 当前设计需求基线

本文件是 `docs/hardware/integration/v1/` 的当前需求事实源（SSOT）。

当其它 README、BOM、Signal Net、Pin Matrix、原理图或审查报告与本文件冲突时，应先人工确认并更新本文件，再同步其它产物；禁止让自动化 Skill 自行猜测冲突的最终答案。

## 项目边界

- 用途：比赛 / 初期硬件开发；
- 外壳：3D 打印；
- 眼镜端负责采集、执行、无线和基础控制；
- Android 手机负责视觉 AI、ASR、LLM、TTS、任务闭环和联网管理；
- 当前并行主控：ESP32-S3-MINI-1U-N4R2 / BK7258QN88616 候选。

## 数量与功能要求

| 功能 | 器件 | 数量 | 当前要求 |
|---|---|---:|---|
| Camera | OV5640 DVP | 1 | 第一视角视觉输入 |
| IMU | BMI270 | 1 | I²C + INT1 |
| MIC | ICS-43434 | 1 | I²S 数字音频输入 |
| Audio AMP | MAX98357A | 1 | 单声道 I²S Class-D |
| Bone | 8Ω 骨传导单元 | 2 | 两只播放完全相同的单声道 |
| Haptic Driver | DRV2605L | 2 | 左右分别独立控制 |
| Haptic Actuator | 0809 X轴 LRA | 2 | 左右各一个 |
| Battery | 1S LiPo | 1 | 主电池 |
| Magnetic Connector | 4Pin | 1 | 5V / GND / USB D+ / USB D- |

## Audio

```text
MCU I²S TX → MAX98357A → SPK+ / SPK-
                           ├→ BONE_LEFT  8Ω
                           └→ BONE_RIGHT 8Ω
```

- 两只 Bone 并联，等效约 4Ω；
- 每只标称约 1~1.5 W；
- 两只播放完全相同的单声道，不要求立体声；
- MAX98357A 为 BTL / 差分输出，Bone 任一端禁止接 GND；
- 最大音量、实际功率、响度与温升通过后续实测确认。

## Haptic

```text
MCU → DRV2605L LEFT  → LRA LEFT
MCU → DRV2605L RIGHT → LRA RIGHT
```

- Driver ×2；
- LRA ×2；
- LEFT / RIGHT 必须可以分别触发，也允许同时触发；
- 两颗 DRV2605L 地址均为 `0x5A`；
- 必须通过独立 I²C 段、I²C MUX/Switch 或其它有依据方案处理地址冲突；
- 未冻结前不得直接把两颗同地址器件并到同一 I²C 段。

## Development Test / Recovery

开发阶段必须兼顾可调试性和 PCB 面积。

Mandatory：

- TP_GND；
- TP_3V3；
- TP_EN / RESET；
- TP_BOOT / DOWNLOAD。

Recommended：

- TP_UART_TX；
- TP_UART_RX。

Optional：

- TP_5V；
- TP_VBAT；
- 关键 Bus / Camera Rail。

原则：不做“所有 Net 自动加 TP”。

## USB / Charging

V1 采用 4Pin 磁吸接口：

```text
5V
GND
USB D+
USB D-
```

目标：充电 + Native USB 烧录 + 日志 + 开发数据 + 故障恢复。

## Camera

OV5640 继续采用现有 DVP + SCCB 技术路径。当前已审查的 24Pin 电气映射不因视觉误判重新推倒。FPC 接触面、Pin1、机械方向属于首板前机械确认项。

Camera RESET/PWDN 电平兼容性仍需依据最终模组资料确认；资料不足时保留 TBD。

## Memory / Performance

ESP32-S3-MINI-1U-N4R2 为 4 MB Flash + 2 MB PSRAM。两者不是 6 MB 通用 RAM。

2 MB PSRAM 是否足够 Camera + Wi-Fi + MIC + Audio + IMU + Haptic 并发，属于后续 `SYSTEM_VALIDATION`，不作为当前原理图网络正确性的判据。

## Power

当前电源架构需要覆盖：

- 5V 磁吸输入；
- 1S LiPo 充电 / Power Path；
- SYS_3V3；
- Camera 2.8V；
- Camera Core 1.2V / 1.5V（以最终模组为准）；
- MAX98357A Audio Power。

峰值功耗建议做 Datasheet 预算，但当前不作为重新绘制原理图的硬阻塞项。

## 原理图必须表达的通道

必须能直接看到并审计：

- CAMERA；
- MIC；
- IMU；
- AUDIO_MONO；
- BONE_LEFT；
- BONE_RIGHT；
- HAPTIC_LEFT；
- HAPTIC_RIGHT；
- MAG_USB；
- BATTERY；
- DEBUG / RECOVERY；
- POWER RAILS。

所有 Connector 除位号外必须有功能语义，禁止只依靠 J1/J2/J3 猜用途。
