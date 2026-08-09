# Plan B — BK7258QN88616 候选

## 定位

这是 V1 的 **高资源 / 高集成度方案**。

当前采购候选为供应商页面标注的 `BK7258QN88616（8+16）`，暂按 **8 MB Flash + 16 MB PSRAM** 做原理图和资源预算；但该完整订货编码及存储配置必须在下单/锁 BOM 前由供应商或原厂资料再次确认。

## BK7258 官方公开能力

- ARMv8-M Star (M33F) MCU，最高 480 MHz；
- Flash 最高 16 MB；
- PSRAM 最高 16 MB；
- 56 GPIO；
- 2× I²C；
- 3× I²S；
- 8-bit CIS DVP；
- JPEG 硬件编码/解码；
- 720p H.264 硬件编码；
- Audio ADC / DAC / DMIC；
- USB 2.0 High-Speed；
- Wi-Fi 6 + BLE 5.4；
- VBAT 2.0~4.35V，片内 Buck / LDO；
- QFN88 9×9 mm。

## V1 连接架构

```text
OV5640 ──8-bit DVP/SCCB──┐
INMP441 ─────I²S RX──────┤
BMI270 ──────I²C─────────┤
DRV2605L ────I²C─────────┤
BMI270 INT1 ─GPIO────────┤
                         ▼
                  BK7258QN88616
                         │
                         ├── Wi-Fi / BLE → Android
                         ├── USB → 4Pin磁吸接口
                         └── I²S TX → Class-D → 骨传导
```

## 为什么 V1 仍然保留 INMP441 + I²S Class-D

BK7258 虽然有 Audio ADC、DAC 和 DMIC，但 V1 不主动拆分已经验证的公共技术路线：

- MIC 仍使用 INMP441；
- Audio OUT 仍优先使用 I²S Class-D；
- 这样 Plan A / Plan B 的外围器件、Android 功能定义和软件接口更容易对比。

内置 ADC/DAC/DMIC 作为后续降 BOM / 缩面积的优化方向，不作为第一轮原理图的强制变化。

## 方案特有问题

1. `BK7258QN88616` 的准确 ordering code / Flash / PSRAM 需采购确认；
2. BK7258 的某些 SDK/配置存在媒体资源与 BLE 内存复用限制，必须固定最终 SDK 后实测；
3. 56 GPIO 和 3×I²S 不能只看数量，需要按照官方 PinMux / GPIO Group 做完整 Pin Matrix；
4. 需要建立新的 BK7258 下载、SWD、启动、晶振、RF 和电源参考电路；
5. 现有 ESP32 固件需要迁移到 Beken SDK。

## 原理图阶段目标

- Camera、MIC、IMU、Haptic、Audio OUT 与 Plan A 使用相同器件；
- 使用 BK7258 资源优势解决 GPIO、PSRAM 和媒体并发余量；
- 保留 USB 磁吸数据接口；
- 先按照原厂参考设计完成最小启动、电源、时钟、RF、Flash/PSRAM/封装相关约束，再叠加公共外围；
- 完成 Pin Matrix 后再进入正式原理图冻结。
