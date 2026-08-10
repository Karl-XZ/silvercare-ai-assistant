# Plan A — ESP32-S3-MINI-1U-N4R2

## 定位

这是 V1 的**低风险 / 继承现有实验资产方案**。

主控固定为 `ESP32-S3-MINI-1U-N4R2`。选择 1U 的主要原因是模块本体更短且使用外置天线，可把 RF 天线布置到 3D 打印镜腿的其它位置，提高机械布局自由度。

## 核心资源

- 4 MB Flash；
- 2 MB PSRAM；
- 39 GPIO；
- 2× I²C；
- 2× I²S；
- LCD/Camera 控制器，支持并行 DVP；
- USB 2.0 Full-Speed OTG + USB Serial/JTAG；
- 2.4 GHz Wi-Fi + BLE 5；
- 外置 2.4 GHz 天线。

## V1 当前连接架构

```text
OV5640 ──8-bit DVP/SCCB──┐
ICS-43434 ───I²S RX──────┤
BMI270 ──────I²C + INT───┤
                         ▼
             ESP32-S3-MINI-1U-N4R2
                         │
                         ├── Wi-Fi / BLE → Android
                         ├── USB → 4Pin磁吸接口
                         ├── I²S TX → MAX98357A
                         │               │
                         │          SPK+ / SPK-
                         │          ├→ Bone LEFT  8Ω
                         │          └→ Bone RIGHT 8Ω
                         │
                         ├── Haptic Control → DRV2605L LEFT  → LRA LEFT
                         └── Haptic Control → DRV2605L RIGHT → LRA RIGHT
```

## 双路触觉约束

两颗 DRV2605L 地址均为 `0x5A`。当前需求是左右独立控制，因此 Plan A 不允许直接把两颗 DRV2605L 并联在同一未隔离 I²C 段。

重新画原理图前必须根据最终 Pin Matrix 确定：

- 独立 I²C 总线；或
- I²C MUX / Switch；或
- 其它有依据的地址隔离方法。

Camera SCCB、BMI270 和双 Haptic 会共同占用 I²C/可映射 GPIO 资源，这也是 Plan A Pin Matrix 的重点。

## Audio

V1 使用：

- `ICS-43434 ×1` 作为 I²S MIC；
- `MAX98357A ×1` 作为单声道 I²S Class-D；
- `8Ω Bone ×2` 并联到 BTL `SPK+ / SPK-`；
- 两只播放完全相同的单声道。

不做左右立体声，不增加第二颗音频功放。

## Development / Recovery

主板必须保留最小开发恢复能力：

Mandatory：

- TP_GND；
- TP_3V3；
- TP_EN；
- TP_BOOT。

Recommended：

- TP_UART_TX；
- TP_UART_RX。

Native USB 通过 4Pin 磁吸接口承担主要烧录、日志和有线数据；UART TP 作为恢复通道。

## 方案特有风险

### 原理图级 P0

1. 双 DRV2605L 地址隔离方式；
2. 最新 GPIO / PinMux Matrix；
3. Camera + MIC + Audio + 双 Haptic + USB + Recovery 全部资源无冲突。

### 系统验证项

1. 2 MB PSRAM 是否足够 OV5640 + Wi-Fi + Audio/MIC 并发；
2. Camera + Wi-Fi + 双向音频的 DMA / Buffer 策略；
3. 双 Bone 实际响度/功率/温升；
4. 整机峰值电流和温升。

这些系统验证项不应被误写成当前原理图网络错误。

## 原理图阶段目标

- 以 `../common/design-requirements.md` 为需求事实源；
- Camera、MIC、IMU、Audio、双 Haptic 数量和接口全部满足当前基线；
- Connector 明确标注 LEFT / RIGHT / CAMERA / MAG_USB / BATTERY；
- 完成 Pin Matrix 后再锁定 GPIO；
- 原理图完成后从 EDA 实时导出 Netlist 做独立审计，而不是只检查生成时的连接表。
