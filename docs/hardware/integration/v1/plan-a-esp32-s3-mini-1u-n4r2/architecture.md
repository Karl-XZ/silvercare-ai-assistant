# Plan A — ESP32-S3-MINI-1U-N4R2

## 定位

Plan A 是 V1 的**低迁移风险 / 现有实验继承方案**。主控固定为 `ESP32-S3-MINI-1U-N4R2`：4 MB Flash + 2 MB PSRAM，外置 2.4 GHz 天线。

当前文件已从“逻辑占位”升级为**实际 GPIO 分配基线**。后续原理图应以本目录 `pin-matrix.csv` 为输入，不再自行重新分配 GPIO。

## 总体结构

```text
OV5640 ── DVP + Camera SCCB ──┐
ICS-43434 ── I²S RX ──────────┤
MAX98357A ←── I²S TX ─────────┤
BMI270 ───── SENSOR_I2C ──────┤
PCA9540B ─── SENSOR_I2C ──────┤
BMI270 INT1 ─ GPIO ───────────┤
HAPTIC_L_TRIG ─ GPIO ─────────┤
HAPTIC_R_TRIG ─ GPIO ─────────┤
                              ▼
                ESP32-S3-MINI-1U-N4R2
                              │
                              ├── USB D-/D+ → 4Pin Magnetic
                              ├── Wi-Fi / BLE → Android
                              └── UART0 / EN / BOOT → TP Recovery
```

## 双 Haptic 总线

Plan A 不为两颗 DRV2605L 各占一套主控 I²C 控制器。Camera 使用独立 SCCB 总线，Sensor/Haptic 使用第二套逻辑总线，并通过 PCA9540B 隔离两个 `0x5A`：

```text
GPIO18 SCL / GPIO21 SDA
        │
        ├── BMI270 @0x68
        └── PCA9540B @0x70
               ├── CH0 → DRV2605L LEFT @0x5A → LRA LEFT
               └── CH1 → DRV2605L RIGHT@0x5A → LRA RIGHT

GPIO34 → DRV LEFT  IN/TRIG
GPIO35 → DRV RIGHT IN/TRIG
```

两个独立 Trigger GPIO 用于在左右 Driver 已分别配置后触发预设效果。严格双路高频 RTP 同步更新不作为 V1 硬要求。

## Audio GPIO 策略

ESP32-S3 官方 I²S 标准全双工允许 TX/RX 共用 BCLK 与 WS，前提是 frame timing 一致。V1 利用这一能力减少 GPIO：

```text
GPIO36 → AUDIO_BCLK → ICS-43434 + MAX98357A
GPIO37 → AUDIO_WS   → ICS-43434 + MAX98357A
GPIO38 ← MIC_DIN    ← ICS-43434 SD
GPIO39 → AMP_DOUT   → MAX98357A DIN
GPIO40 → AMP_SD_MODE / shutdown control
```

ICS-43434 是 24-bit 标准 I²S；MAX98357A 支持标准 I²S 及 24-bit 数据。固件阶段需使用相同采样率与 frame timing 做全双工实机验证。

这样保留第二个 I²S 控制器作为后续扩展余量。

## GPIO 资源结果

- Camera：GPIO1~17 中除 GPIO3 外的规划区；
- USB：GPIO19/20 固定；
- Sensor I²C：GPIO18/21；
- BMI INT：GPIO33；
- Haptic Trigger：GPIO34/35；
- Audio：GPIO36~40；
- UART0 Recovery：GPIO43/44；
- Clean spare：GPIO41、42、47、48；
- Restricted reserve：GPIO3、45、46（Strapping，仅在重新验证启动条件后使用）；
- GPIO0 专用于 BOOT/DOWNLOAD；
- N4R2 的 GPIO26 连接模块内 PSRAM，不分配给外设。

## 双镜腿物理分区

Plan A 必须遵循 `../common/dual-temple-partition.md`，不能按单板原理图生成后再在 PCB 阶段临时拆板。

### A — MAIN / SENSING TEMPLE

放置：ESP32-S3、RF、OV5640、Camera LDO、ICS-43434、BMI270、PCA9540B、DRV A + LRA A、MAX98357A + Bone A、4Pin Magnetic、USB ESD、Charger/Power Path、SYS_3V3、Debug/Recovery。

### B — BATTERY / REMOTE ACTUATOR TEMPLE

放置：1S LiPo、Battery/NTC interface、DRV B + LRA B、Bone B、本地去耦和最小 TP。

跨镜腿 FPC 当前按 12 conductor baseline：BAT+/GND 并联承流、SYS_3V3、HAPTIC_B SDA/SCL/TRIG、SPK_P/N、可选 BAT_NTC、Spare。

目的：Camera DVP、I²S、Native USB 和 RF 不跨镜腿；利用 B 侧 Battery 作为主要配重。

## 原理图阶段注意

1. `GPIO0 / EN / GPIO43 / GPIO44` 保留为恢复链路；
2. GPIO19/20 只做 USB；
3. GPIO3/45/46 不用于当前核心功能；
4. Camera SCCB 与 SENSOR_I2C 分开；
5. PCA9540B upstream / CH0 / CH1 均要正确上拉；
6. MAX98357A `SD_MODE` 的偏置/关断网络按 ADI 数据手册实现，GPIO40 不应被简单视为普通高低电平 EN 而忽略其模式选择要求；
7. 外置天线按 MINI-1U RF 要求布局；
8. 2 MB PSRAM 是否足够整机并发属于后续 System Validation，不重开 Pin Matrix；
9. 原理图中必须明确 A/B Board Boundary、J_INTER_A/J_INTER_B 与 FPC Pin Map。
