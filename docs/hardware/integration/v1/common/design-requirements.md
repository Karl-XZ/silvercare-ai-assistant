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
| Haptic MUX | PCA9540B | 1 | 隔离两颗固定 0x5A 的 DRV2605L |
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

## Haptic — 已冻结总线架构

V1 两套主控统一使用 PCA9540B 做双 DRV2605L 的地址隔离：

```text
MCU SENSOR_I2C
   ├── BMI270 @0x68
   └── PCA9540B @0x70
          ├── CH0 → DRV2605L LEFT  @0x5A → LRA LEFT
          └── CH1 → DRV2605L RIGHT @0x5A → LRA RIGHT

MCU HAPTIC_L_TRIG ─────────→ DRV2605L LEFT  IN/TRIG
MCU HAPTIC_R_TRIG ─────────→ DRV2605L RIGHT IN/TRIG
```

要求：

- PCA9540B ×1，VDD = SYS_3V3；
- 上游 SENSOR_I2C 及两个下游通道分别设置合适的 I²C 上拉；
- PCA9540B 上电默认两个下游通道均断开；
- LEFT / RIGHT 可分别配置、分别触发，也允许同时触发；
- 同步 ROM/预设波形：分别经 MUX 配置左右 DRV，再通过两个独立 `IN/TRIG` GPIO 触发；
- PCA9540B 是 1-of-2 MUX，同一时刻只有一个下游 I²C 通道选通。因此严格的双路高频 RTP 同步更新不作为 V1 硬要求；如后续需要，重新评估独立总线或其它驱动架构；
- DRV2605L EN 不作为地址隔离手段。

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
- PCA9540B + BMI270 + DRV2605L ×2；
- Camera 2.8V；
- Camera Core 1.2V / 1.5V（以最终模组为准）；
- MAX98357A Audio Power。

峰值功耗建议做 Datasheet 预算，但当前不作为重新绘制原理图的硬阻塞项。

## 双镜腿物理架构 — 原理图阶段必须考虑

整机电子系统必须从原理图阶段就划分为 A/B 两个物理板区，并通过正式 FPC Connector 连接；禁止先按“单板”生成原理图，再在 PCB 阶段临时拆成两块。

### A 区：MAIN / SENSING TEMPLE

A 区放置：

- MCU / SoC 及其 RF / 启动 / 下载 / 本地去耦；
- OV5640 + Camera FPC；
- Camera 2.8V / Core LDO；
- ICS-43434；
- BMI270；
- PCA9540B；
- DRV2605L A + LRA A；
- MAX98357A + Bone A；
- 4Pin Magnetic USB；
- USB ESD / input protection；
- Charger / Power Path；
- SYS_3V3 regulator；
- BOOT / EN / UART / 主要 TP；
- `J_INTER_A`。

原则：Camera DVP、I²S、USB、RF 等高速/敏感信号不跨镜腿。

### B 区：BATTERY / REMOTE ACTUATOR TEMPLE

B 区放置：

- 1S LiPo Battery；
- Battery connector / NTC interface；
- DRV2605L B + LRA B；
- Bone B；
- HAPTIC CH1 下游 pull-up / 本地去耦；
- 本地 TP_GND_B / TP_3V3_B；
- `J_INTER_B`。

A/B 当前只是工程分区名，不强制绑定左/右镜腿；最终左右方向由机械设计确定。

### Inter-Temple FPC 基线

当前按 12 conductor baseline 进入下一版原理图，核心网络为：

- BAT+（建议物理并联 Pin）；
- GND（建议物理并联 Pin）；
- SYS_3V3；
- HAPTIC_B_SCL；
- HAPTIC_B_SDA；
- HAPTIC_B_TRIG；
- SPK_P；
- SPK_N；
- BAT_NTC（条件使用）；
- Spare。

详细分区与 Pin baseline：

- `dual-temple-partition.md`
- `temple-partition.csv`
- `inter-temple-fpc.csv`

该 12Pin 是首版工程基线，不等于最终机械连接器已经冻结。电源峰值和 FPC 铜宽确认后才允许进一步减 Pin。

### 双板测试点

A 板 Mandatory：TP_GND_A、TP_3V3_A、TP_EN、TP_BOOT；UART TX/RX Recommended。

B 板 Mandatory：TP_GND_B、TP_3V3_B。

原因：FPC/远端电源故障时必须能够独立确认 B 板是否真正获得供电。

## 原理图必须表达的通道

必须能直接看到并审计：

- CAMERA；
- MIC；
- IMU；
- AUDIO_MONO；
- BONE_A / BONE_B；
- HAPTIC_MUX；
- HAPTIC_A / HAPTIC_B；
- MAG_USB；
- BATTERY；
- DEBUG / RECOVERY；
- POWER RAILS；
- A/B BOARD BOUNDARY；
- INTER_TEMPLE_FPC。

所有 Connector 除位号外必须有功能语义，禁止只依靠 J1/J2/J3 猜用途。