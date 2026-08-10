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
RESET（如使用）
PWDN（如使用）

主控 ↔ OV5640
SCCB SDA
SCCB SCL
```

Camera SCCB 优先保持独立逻辑域；最终总线、电平和 PinMux 以具体主控与模组数据手册为准。

## Audio Input — ICS-43434 ×1

```text
主控 BCLK → ICS-43434 SCK
主控 WS   → ICS-43434 WS
ICS-43434 SD → 主控 I²S RX DATA
```

当前 V1 接受 ICS-43434 作为采购与原理图器件。INMP441 仅保留为历史实验验证资料。

## Audio Output — MAX98357A + Bone ×2

当前 V1 是**单声道、双骨传导**，两只播放完全相同的音频，不做左右立体声。

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

两只 8Ω Bone 并联后等效约 4Ω。MAX98357A 为 BTL / 差分输出，两个 Bone 都必须跨接 `SPK+ / SPK-`，禁止任一端接 GND。

Bone 当前输入参数：每只 8Ω、标称约 1~1.5 W。实际响度、功率和温升在后续系统验证中实测。

## IMU — BMI270 ×1

```text
主控 ↔ BMI270
I²C SDA
I²C SCL

BMI270 INT1 → MCU GPIO
```

当前 I²C 地址按现有验证方案为 `0x68`。

## Haptic — DRV2605L ×2 + LRA ×2

需求：左右两个 LRA，分别独立控制。

```text
主控 → DRV2605L LEFT  → LRA LEFT
主控 → DRV2605L RIGHT → LRA RIGHT
```

每个驱动器分别输出：

```text
OUT+ → 对应 LRA +
OUT- → 对应 LRA -
```

必须存在两个明确的物理输出接口：

- `J_LRA_LEFT`；
- `J_LRA_RIGHT`。

### I²C 地址约束

两颗 DRV2605L 固定地址均为 `0x5A`。因此不能直接在同一未隔离 I²C 段上并联后宣称可分别控制。

各主控方案必须在自己的 Pin Matrix / Signal Net 中明确采用：

- 独立 I²C 总线；或
- I²C Multiplexer / Switch；或
- 其它可证明的地址隔离方式。

在该选择冻结前统一标记 `TBD / P0`。

## USB / Magnetic Connector

V1 工程版本统一采用 4 Pin：

```text
Pin 1: 5V / VBUS
Pin 2: USB D-
Pin 3: USB D+
Pin 4: GND
```

目标：同时承担充电、Native USB 烧录、日志、故障恢复和必要时有线数据。

## Development Test / Recovery

开发阶段采用最少测试点策略。

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

1. 两套方案的功能名、接口名和 Channel 语义保持一致；
2. Bone 必须是 LEFT / RIGHT 两个物理输出，但播放同一单声道；
3. Haptic 必须是 LEFT / RIGHT 两个独立驱动通道；
4. Connector 不能只显示 J1/J2/J3，必须同时标注功能；
5. 两套方案共同器件尽量使用相同连接方式；
6. 不因为 BK7258 有 Audio DAC 就在 V1 主动切换模拟音频路线；
7. 系统压力测试与原理图网络审查分开记录。
