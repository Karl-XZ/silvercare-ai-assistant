# V1 两套方案共用接口定义

本文件定义当前两套主控方案的**共同逻辑接口**。具体 GPIO / PinMux 在 Plan A / Plan B 的 `pin-matrix.csv` 中分别完成。

## Camera — OV5640 ×1

```text
OV5640 → 主控 DVP
D0~D7
PCLK
HREF
VSYNC

主控 → OV5640
XCLK
RESET
PWDN

主控 ↔ OV5640
SCCB SDA
SCCB SCL
```

Camera SCCB 保持独立 I²C/SCCB 总线，避免占用双 Haptic 的 Sensor I²C 地址隔离资源。最终上拉电压与控制电平以模组资料为准。

## Audio Input — ICS-43434 ×1

```text
主控 BCLK → ICS-43434 SCK
主控 WS   → ICS-43434 WS
ICS-43434 SD → 主控 I²S RX DATA
```

ICS-43434 为 24-bit 标准 I²S 数字麦克风。当前 V1 接受该器件作为采购与原理图基线；INMP441 仅作为历史实验资料。

## Audio Output — MAX98357A + Bone ×2

```text
主控 I²S TX
  ├─ BCLK
  ├─ LRCLK / WS
  └─ DATA
       ↓
MAX98357A
       ↓
SPK+ / SPK-
  ├─ BONE_LEFT  8Ω
  └─ BONE_RIGHT 8Ω
```

- 两只 Bone 播放完全相同的单声道；
- 两只 8Ω 并联后等效约 4Ω；
- MAX98357A 为 BTL / 差分输出，两只 Bone 均跨接 `SPK+ / SPK-`，禁止任一端接 GND；
- `SD_MODE/EN` 的具体偏置与关断控制按 MAX98357A 数据手册和各方案 Pin Matrix 处理。

## IMU + Dual Haptic — 公共总线方案

V1 已冻结 `PCA9540B` 作为两个固定地址 DRV2605L 的地址隔离器。

```text
MCU SENSOR_I2C
   │
   ├── BMI270 @0x68
   │
   └── PCA9540B @0x70
          ├── CH0 → DRV2605L LEFT  @0x5A → LRA LEFT
          └── CH1 → DRV2605L RIGHT @0x5A → LRA RIGHT

BMI270 INT1 → MCU GPIO

MCU HAPTIC_L_TRIG → DRV2605L LEFT  IN/TRIG
MCU HAPTIC_R_TRIG → DRV2605L RIGHT IN/TRIG
```

### I²C 物理要求

- PCA9540B VDD：`SYS_3V3`；
- upstream `SENSOR_I2C`：一组 SDA/SCL 上拉；
- CH0：独立 SDA/SCL 上拉；
- CH1：独立 SDA/SCL 上拉；
- 两颗 DRV2605L VDD 均按当前 3.3V 逻辑域设计；
- DRV2605L EN 不作为地址隔离手段。

### 同步触觉策略

PCA9540B 是 1-of-2 MUX，I²C 同一时刻只访问一侧。因此：

1. 选择 CH0，配置 LEFT 波形/模式；
2. 选择 CH1，配置 RIGHT 波形/模式；
3. 使用两个独立 `IN/TRIG` GPIO 产生边沿，可实现左右预配置效果近同时启动；
4. 如果后续必须做严格同步、持续高更新率的双路 RTP，则列为系统架构升级项，而不是在当前 V1 内强行实现。

## USB / Magnetic Connector

V1 工程版本统一采用 4 Pin：

```text
Pin 1: 5V / VBUS
Pin 2: USB D-
Pin 3: USB D+
Pin 4: GND
```

目标：充电、Native USB 烧录、日志、故障恢复和必要时有线数据。

## Development Test / Recovery

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
- 关键 I²C / Camera Rail。

禁止为所有网络无差别增加 TP。

## Android 通信

- BLE：控制、状态、电量、事件、低速数据；
- Wi-Fi：Camera、音频、大日志和高带宽数据；
- USB：工程调试、烧录、故障恢复、必要时有线数据。

## 原理图约束

1. 两套方案功能名、接口名和 Channel 语义保持一致；
2. Bone 必须有 LEFT / RIGHT 两个物理输出，但播放同一单声道；
3. Haptic 必须有 LEFT / RIGHT 两个独立 Driver + LRA；
4. 原理图必须明确画出 PCA9540B 的 upstream / CH0 / CH1 三个 I²C 段；
5. Connector 不能只显示 J1/J2/J3，必须同时标注功能；
6. 系统压力测试与原理图网络审查分开记录。
