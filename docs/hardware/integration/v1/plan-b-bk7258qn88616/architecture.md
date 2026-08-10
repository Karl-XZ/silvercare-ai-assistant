# Plan B — BK7258QN88616 候选

## 定位

这是 V1 的**高资源 / 高集成度方案**。

当前采购候选为供应商页面标注的 `BK7258QN88616（8+16）`，暂按 **8 MB Flash + 16 MB PSRAM** 做资源预算；完整订货编码、实际存储配置、封装和温度等级必须在 BOM 锁定 / 下单前向供应商或原厂确认。

## BK7258 当前用于方案评估的公开能力

- ARMv8-M Star (M33F) MCU，最高 480 MHz；
- Flash / PSRAM 最高 16 MB；
- 56 GPIO；
- 2× I²C；
- 3× I²S；
- 8-bit CIS DVP；
- JPEG 编解码；
- 720p H.264 编码；
- Audio ADC / DAC / DMIC；
- USB 2.0 High-Speed；
- Wi-Fi 6 + BLE 5.4；
- VBAT 2.0~4.35V；
- QFN88 9×9 mm。

## V1 当前连接架构

```text
OV5640 ──8-bit DVP/SCCB──┐
ICS-43434 ───I²S RX──────┤
BMI270 ──────I²C + INT───┤
                         ▼
                  BK7258QN88616
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

## 为什么 V1 仍采用独立 I²S MIC / I²S Class-D

BK7258 虽然公开能力中包含 Audio ADC / DAC / DMIC，但 V1 不主动拆分共同技术路径：

- MIC 使用 `ICS-43434`；
- Audio OUT 使用 `MAX98357A`；
- Bone ×2 并联播放相同单声道；
- 这样 Plan A / Plan B 的外设和 Android 功能定义更容易直接对比。

BK7258 内置 Audio 能力作为后续降 BOM / 缩面积方向，不在当前重新绘图阶段强制引入。

## 双路触觉约束

需求：`DRV2605L ×2 + LRA ×2`，左右独立控制。

两颗 DRV2605L 固定地址都为 `0x5A`。Plan B 也必须在最终 Pin Matrix 中明确采用独立 I²C 段、I²C MUX/Switch 或其它有依据的地址隔离方案，不能简单同段并联。

BK7258 虽有 2× I²C 和更多 GPIO，但 Camera SCCB、BMI270、双 Haptic 都需要进入同一套资源规划，不能只根据“GPIO总数够”判断设计成立。

## Development / Recovery

Plan B 必须根据 Beken 参考设计保留可用的：

- 下载 / Boot；
- Reset；
- UART；
- SWD；
- USB（如采用）。

开发阶段统一测试点策略：

Mandatory：TP_GND、TP_3V3、TP_RESET/EN、TP_BOOT/DOWNLOAD。

Recommended：TP_UART_TX、TP_UART_RX；SWD 按实际调试方式以测试焊盘或小型接口实现。

## 方案特有风险

### 原理图级 P0

1. `BK7258QN88616` 最终器件形态和完整参考设计；
2. 双 DRV2605L 地址隔离；
3. DVP / I²S / I²C / USB / Debug / RF 的完整 Pin Matrix；
4. RF、时钟、下载、SWD、Flash/PSRAM/封装相关必需外围。

### 系统验证项

1. 固定 SDK 后 Camera + Audio + Wi-Fi + BLE 并发；
2. 当前供应商 8+16 配置的真实可用内存；
3. 双 Bone 实际响度/功率/温升；
4. 整机峰值电流与温升。

## 原理图阶段目标

- 以 `../common/design-requirements.md` 为需求事实源；
- Camera、MIC、IMU、Audio、双 Haptic 与 Plan A 使用相同功能定义；
- 先按原厂参考设计完成最小启动、电源、时钟、RF、下载/调试；
- 完成 Pin Matrix 后才锁定 GPIO；
- 原理图完成后从 EDA 实时导出 Netlist 做独立审计。
