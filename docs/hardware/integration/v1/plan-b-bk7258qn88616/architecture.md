# Plan B — BK7258QN88616 候选

## 定位

Plan B 是 V1 的**高资源 / 高集成度方案**。当前采购候选为供应商标注的 `BK7258QN88616（8+16）`，暂按 8 MB Flash + 16 MB PSRAM 做资源预算；完整订货码和存储配置仍需采购前确认。

当前文件已从逻辑占位升级为实际 GPIO / GPIO Group 分配基线。

## 总体结构

```text
OV5640 ── DVP + Camera SCCB ──┐
ICS-43434 ── I²S Group0 RX ───┤
MAX98357A ←─ I²S Group2 TX ───┤
BMI270 ───── I2C0 ────────────┤
PCA9540B ─── I2C0 ────────────┤
BMI270 INT1 ─ GPIO ───────────┤
HAPTIC_L_TRIG ─ GPIO ─────────┤
HAPTIC_R_TRIG ─ GPIO ─────────┤
                              ▼
                         BK7258
                              │
                              ├── USB → 4Pin Magnetic
                              ├── Wi-Fi / BLE → Android
                              └── DL_UART / Reset → TP Recovery
```

## 双 Haptic 总线

BK7258 的两套 I²C 保持清晰分工：

```text
I2C1 / GPIO0-1
→ OV5640 SCCB

I2C0 / GPIO20-21
→ BMI270 @0x68
→ PCA9540B @0x70
      ├── CH0 → DRV2605L LEFT @0x5A → LRA LEFT
      └── CH1 → DRV2605L RIGHT@0x5A → LRA RIGHT

GPIO23 → DRV LEFT  IN/TRIG
GPIO24 → DRV RIGHT IN/TRIG
```

因此不消耗第三套 I²C，也不需要把 Camera 和 Sensor 混到一个电压域。

## Camera 固定 GPIO 区

依据 BK7258 官方 GPIO map，V1 使用 JPEG/CIS 接口对应组：

```text
GPIO27  XCLK / JPEG_MCLK
GPIO29  PCLK
GPIO30  HREF / JPEG_HSYNC
GPIO31  VSYNC
GPIO32  D0
GPIO33  D1
GPIO34  D2
GPIO35  D3
GPIO36  D4
GPIO37  D5
GPIO38  D6
GPIO39  D7
```

Camera SCCB：GPIO0 SCL / GPIO1 SDA。

## Audio GPIO 策略

BK7258 GPIO余量充足，首版不强制 MIC 与 AMP 共用同一 I²S Group：

### ICS-43434 — I²S Group0

```text
GPIO6 BCLK
GPIO7 WS
GPIO8 DIN
```

### MAX98357A — I²S Group2

```text
GPIO44 BCLK
GPIO45 LRCLK
GPIO47 DOUT
```

GPIO46（Group2 DIN）保持空闲；GPIO9（Group0 DOUT）保持空闲。

这样减少 SDK 首版全双工共时钟配置风险，后续若确有必要再优化。

## 其它 GPIO

- USB：GPIO12 D+ / GPIO13 D-；
- BMI270 INT1：GPIO22；
- Haptic Trigger：GPIO23 / GPIO24；
- MAX98357A SD_MODE：GPIO25；
- 调试串口预留：GPIO10 RX / GPIO11 TX（按 BK7258 GPIO map 的 UART 功能，最终下载口名称以 Beken Hardware Reference Design 为准）；
- 其余仍有大量 GPIO 可作为扩展，不需要占用 Camera/I²S 固定组。

## 双镜腿物理分区

Plan B 与 Plan A 使用同一物理架构基线，详见 `../common/dual-temple-partition.md`。

### A — MAIN / SENSING TEMPLE

放置：BK7258 主控及其 RF/启动/下载外围、OV5640、Camera Power、ICS-43434、BMI270、PCA9540B、DRV A + LRA A、MAX98357A + Bone A、4Pin Magnetic、USB保护、Charger/Power Path、SYS_3V3 和主要调试点。

### B — BATTERY / REMOTE ACTUATOR TEMPLE

放置：1S LiPo、Battery/NTC、DRV B + LRA B、Bone B、本地去耦与最小 TP。

跨镜腿 FPC 当前按 12 conductor baseline，仅承载主电源、远端 Haptic 低速控制与远端 Bone 差分输出。BK7258 的 Camera CIS/JPEG、I²S、USB、RF 全部保持在 A 区，不跨镜腿。

该分区不改变已经冻结的 BK7258 业务 GPIO 分配。

## 调试注意

BK7258 官方调试文档说明 CPU0/CPU1 日志默认经 `DL_UART0` 输出。本版保留 UART Recovery/Test 点，但在正式原理图中还应依据 Beken QFN88 Hardware Reference Design 再核对下载、Reset、Boot、RF、晶振与电源外围的**封装引脚级**定义。

此外，下一版原理图必须明确 A/B Board Boundary、`J_INTER_A/J_INTER_B` 与 FPC Pin Map，不能生成单板原理图后在 PCB 阶段临时拆分。

这项不改变已经冻结的业务 GPIO 分配。
