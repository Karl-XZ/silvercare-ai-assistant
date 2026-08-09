# Plan A — ESP32-S3-MINI-1U-N4R2

## 定位

这是 V1 的 **低风险/继承现有实验资产方案**。

选择该模组而不是 MINI-1-N4R2 的主要原因不是性能，而是结构自由度：MINI-1U 为 15.4 × 15.4 mm，并使用外置天线，可以把 RF 天线布置到 3D 打印镜腿的其它空闲位置，从而缩短主 PCB 主控区域并提高机械布局自由度。

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

## V1 连接架构

```text
OV5640 ──8-bit DVP/SCCB──┐
INMP441 ─────I²S RX──────┤
BMI270 ──────I²C─────────┤
DRV2605L ────I²C─────────┤
BMI270 INT1 ─GPIO────────┤
                         ▼
             ESP32-S3-MINI-1U-N4R2
                         │
                         ├── Wi-Fi / BLE → Android
                         ├── USB → 4Pin磁吸接口
                         └── I²S TX → Class-D → 骨传导
```

## 方案特有问题

1. **2 MB PSRAM** 是最大风险。不能仅凭单模块成功判断整机可行；
2. 外置天线型号、馈线长度、天线摆放位置需要与 3D 打印结构同时设计；
3. N4R2 模组内部 PSRAM 会占用特定 IO，最终 Pin Matrix 必须根据官方模组 Pin 定义检查；
4. Camera + Wi-Fi + 双向音频的 DMA / buffer 策略需要在 ESP-IDF 下做压力测试。

## 原理图阶段目标

- 原理图尽量复用现有 ESP32 实验模块的已验证逻辑；
- Camera、MIC、IMU、Haptic 和 Audio OUT 与 BK 方案使用相同器件和逻辑网络；
- 保留原生 USB 作为磁吸接口数据通道；
- 主板上预留 BOOT、EN、UART/USB 等生产与救砖测试点；
- 在完成 Pin Matrix 后才锁定具体 GPIO。
