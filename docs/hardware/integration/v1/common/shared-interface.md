# V1 两套方案共用接口定义

本文件只定义逻辑接口，不提前写死最终 GPIO。GPIO 分配分别在 Plan A / Plan B 的 `pin-matrix.csv` 中完成。

## Camera — OV5640

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

Camera SCCB 建议优先使用独立 I²C 控制器/总线，避免与低速传感器总线互相影响。

## Audio Input — INMP441

```text
主控 BCLK → INMP441 SCK
主控 WS   → INMP441 WS
INMP441 SD → 主控 I²S RX DATA
```

V1 继续使用已经验证的 INMP441，不在原理图第一版同时引入新的 MIC 技术路径。

## Audio Output — Bone Conduction

```text
主控 I²S TX
  ├─ BCLK
  ├─ LRCLK / WS
  └─ DATA
       ↓
I²S Class-D 功放
       ↓
骨传导单元
```

两套主控优先使用同一功放。只有在 PinMux、电气或 SDK 无法统一时再拆分器件。

## Sensor / Haptic I²C

```text
主控 I²C
  ├─ BMI270      0x68
  └─ DRV2605L    0x5A
```

BMI270 另预留 INT1 → MCU GPIO。

## USB / Magnetic Connector

V1 工程版本统一采用 4 Pin：

```text
Pin 1: 5V / VBUS
Pin 2: USB D-
Pin 3: USB D+
Pin 4: GND
```

目标：同时承担充电、调试、日志、固件恢复。后续 OTA 和生产测试成熟后再评估是否简化成 2 Pin 纯充电。

## Android 通信

- BLE：控制、状态、电量、事件、低速数据；
- Wi-Fi：Camera、音频、大日志和高带宽数据；
- USB：工程调试、故障恢复、必要时有线数据。

## 原理图约束

1. 两套方案的接口名称保持一致；
2. 软件协议尽量保持一致；
3. 两套方案共同器件尽量使用相同供电电压与连接方式；
4. 不因为 BK7258 有 Audio DAC 就在 V1 主动改为模拟音频链路；
5. 不因为 ESP32 方案现有代码较成熟，就跳过全功能并发验证。
