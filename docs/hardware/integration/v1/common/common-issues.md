# 银龄智护 V1 当前硬件问题台账

本文件只记录当前仍需处理的问题，并保留已经关闭的关键设计 Gate 作为版本记录。

问题类型与严重程度分开：

- `SCHEMATIC / DESIGN`：原理图本身必须正确表达；
- `SYSTEM_VALIDATION`：原理图可以继续，后续必须实测；
- `SUPPLY_CHAIN`：采购/规格确认；
- `DOCUMENTATION`：设计事实源与实际工程同步；
- `MECHANICAL`：结构/装配确认。

## 已关闭的原理图前置 Gate

### CLOSED-P0-01 双 DRV2605L 地址冲突

已冻结公共架构：

```text
SENSOR_I2C
├── BMI270 @0x68
└── PCA9540B @0x70
    ├── CH0 → DRV2605L LEFT  @0x5A
    └── CH1 → DRV2605L RIGHT @0x5A
```

左右各有独立 `IN/TRIG` GPIO。PCA9540B 为 1-of-2 MUX，严格双路高频 RTP 同步不属于 V1 硬要求。

状态：`CLOSED / SCHEMATIC_REQUIRED`。

### CLOSED-P0-02 两套实际 GPIO Pin Matrix

Plan A / Plan B 的核心业务 GPIO 已完成冻结并写入各自 `pin-matrix.csv`。

- Plan A：Camera / USB / Sensor I²C / BMI INT / Haptic Trigger / Audio / UART Recovery 已分配；
- Plan B：Camera fixed group / I2C0/1 / I²S Group0/2 / USB / Haptic / UART 已分配；
- BK7258 的 Reset/Boot/RF 仍需在正式 QFN88 原理图中按原厂 Hardware Reference Design 做**封装引脚级**核对，但不再影响业务 GPIO 资源规划。

状态：`CLOSED_FOR_SCHEMATIC`。

## P0 — 新版原理图必须实现

### P0-01 双路 Haptic 功能闭环

必须形成：

```text
MCU → PCA9540B → DRV2605L LEFT  → J_LRA_LEFT  → LRA LEFT
               → DRV2605L RIGHT → J_LRA_RIGHT → LRA RIGHT

MCU GPIO → LEFT IN/TRIG
MCU GPIO → RIGHT IN/TRIG
```

数量：Driver=2、LRA=2、独立 Trigger=2。

### P0-02 双骨传导单声道闭环

```text
MCU I²S → MAX98357A → SPK+/SPK-
                      ├→ BONE_LEFT  8Ω
                      └→ BONE_RIGHT 8Ω
```

必须有两个物理接口，两只并联播放同一单声道，任一 Bone 端不得接 GND。

### P0-03 Requirements / Netlist / BOM 一致性

新版原理图完成后必须从当前 EDA **实时导出 Netlist**，并与：

- `design-requirements.md`；
- `decision-log.md`；
- `common-bom.csv`；
- 对应 Plan 的 `pin-matrix.csv`；

做三方/多方一致性审计。

## P1 — 原理图应一并完善

### P1-01 开发阶段 TP / Recovery

Mandatory：TP_GND、TP_3V3、TP_EN/RESET、TP_BOOT/DOWNLOAD。

Recommended：TP_UART_TX、TP_UART_RX。

原则：测试点数量精简，不做“每网一个 TP”。

### P1-02 Connector 语义化

必须直接标出：CAMERA_FPC、BONE_LEFT、BONE_RIGHT、LRA_LEFT、LRA_RIGHT、MAG_USB、BATTERY。

### P1-03 Camera 控制电平

`RESET / PWDN` 电平兼容性需依据实际 OV5640 模组资料确认。资料不足时保持 `TBD`，不凭经验增加电平转换。

### P1-04 BK7258 封装级启动/调试/RF

业务 GPIO Matrix 已完成；正式 QFN88 原理图仍需依据 Beken Hardware Reference Design 复核：

- DL_UART 实际下载链；
- Reset / Boot；
- 晶振；
- RF matching / antenna；
- 电源与去耦；
- Flash / PSRAM 与具体采购料号关系。

## SYSTEM_VALIDATION — 不阻止重新画原理图

### SV-01 ESP32-S3 2 MB PSRAM 并发

后续验证 OV5640 + Wi-Fi + MIC + Audio + IMU + Haptic 的真实内存与稳定性。

### SV-02 Plan A 共时钟 I²S 全双工

ICS-43434 与 MAX98357A 在 ESP32-S3 上共享 BCLK / WS。官方接口能力和器件格式兼容，仍需在目标采样率与 slot/frame 配置下做实机全双工验证。

### SV-03 BK7258 多媒体 + 无线并发

固定 SDK 后测试 Camera + Audio + Wi-Fi + BLE 并发。

### SV-04 Audio 输出能力

Bone：8Ω、约 1~1.5 W/只；并联等效约 4Ω。后续实测响度、功率、失真和温升。

### SV-05 电源峰值预算

建议 BOM/原理图完成后做 Datasheet 级估算，首板再测峰值电流、压降和温升。

### SV-06 双 Haptic RTP 极限

PCA9540B 一次只选通一侧。预设效果通过独立 Trigger 可同步启动；如果未来要求左右严格同步的持续高刷新率 RTP，需要升级总线/Driver 架构。

## SUPPLY_CHAIN

### SC-01 BK7258QN88616 准确料号

采购前确认完整 ordering code、Flash、PSRAM、封装、温度等级、MOQ 和价格。

### SC-02 PCA9540B

优先小型 `PCA9540BGD` XSON8；如果装配/供应链不合适，可改 TSSOP8，但逻辑架构不变。

### SC-03 LRA 参数

确认额定电压、谐振频率、阻抗、过驱参数和左右安装方式。

### SC-04 ICS-43434

当前 V1 接受并按现设计采购；生命周期/库存仅作为供应链风险，不自动替换回 INMP441。

## MECHANICAL

- Camera FPC 接触面 / Pin1 / 排线方向首板前实物确认；
- 4Pin 磁吸防反由机械件/结构保证；
- 3D 打印壳体容纳 PCB、电池、外置天线、Bone、双 LRA。

## 当前结论

**已经满足进入“新版原理图更新绘制”的架构条件。**

下一步不是继续重新分配 GPIO，而是：

1. 按最新 Plan A / Plan B Pin Matrix 更新原理图；
2. 加入 PCA9540B + 第二颗 DRV2605L + 第二颗 LRA；
3. 增加第二个 Bone 物理接口；
4. 加入精简 TP/Recovery；
5. 完成后 Live Netlist + ERC + Requirements/BOM 审计。
