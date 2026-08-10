# 银龄智护 V1 当前硬件问题台账

本文件只记录当前仍需处理的问题。问题类型与严重程度分开：

- `SCHEMATIC / DESIGN`：重新画原理图前必须处理；
- `SYSTEM_VALIDATION`：原理图可以继续，但后续必须实测；
- `SUPPLY_CHAIN`：采购/规格确认；
- `DOCUMENTATION`：设计事实源与实际工程同步；
- `MECHANICAL`：结构/装配确认。

原则：**先关闭会让原理图本身无法成立的 P0，再重新绘制；系统压力测试不再混入“原理图错误”。**

## P0 — 重新绘制原理图前必须解决

### P0-01 双 DRV2605L 地址冲突

当前需求：

- DRV2605L ×2；
- LRA ×2；
- 左右分别独立控制。

两颗 DRV2605L 地址均为 `0x5A`，不能直接挂在同一未隔离 I²C 段上完成独立控制。

关闭条件：Plan A / Plan B 分别明确并验证以下之一：

- 独立 I²C 总线；
- I²C MUX / Switch；
- 其它有数据手册依据的独立寻址方案。

### P0-02 两套最新 Pin Matrix

必须按当前最新数量重新分配：

- OV5640 DVP + SCCB；
- ICS-43434 I²S RX；
- MAX98357A I²S TX；
- BMI270 I²C + INT1；
- DRV2605L LEFT；
- DRV2605L RIGHT；
- USB；
- EN / BOOT / UART Recovery；
- 必要的 AMP / Camera 控制；
- 合理 GPIO 余量。

旧 `pin-matrix.csv` 仅作为清单模板，不再视为已冻结结果。

### P0-03 双路 Haptic 功能闭环

必须在原理图中形成：

```text
MCU → DRV2605L LEFT  → J_LRA_LEFT  → LRA LEFT
MCU → DRV2605L RIGHT → J_LRA_RIGHT → LRA RIGHT
```

数量要求：Driver=2、LRA=2、独立控制通道=2。

### P0-04 双骨传导单声道输出闭环

需求：MAX98357A ×1，8Ω Bone ×2，两只播放相同单声道并联跨接 BTL `SPK+ / SPK-`。

必须有两个明确的物理输出：

- BONE_LEFT；
- BONE_RIGHT。

禁止任一 Bone 端接 GND。

## P1 — 原理图应一并完善

### P1-01 开发阶段 TP / Recovery

Mandatory：

- TP_GND；
- TP_3V3；
- TP_EN / RESET；
- TP_BOOT / DOWNLOAD。

Recommended：

- TP_UART_TX；
- TP_UART_RX。

原则：测试点数量必须精简，不做“每网一个 TP”。

### P1-02 Connector 语义化

原理图必须让读图者直接知道接口用途，例如：

- CAMERA_FPC；
- BONE_LEFT；
- BONE_RIGHT；
- LRA_LEFT；
- LRA_RIGHT；
- MAG_USB；
- BATTERY。

### P1-03 Camera 控制电平

`RESET / PWDN` 最终电平兼容性需依据实际 OV5640 模组/器件资料确认。资料不足时保持 `TBD`，不凭经验增加电平转换。

### P1-04 USB / 磁吸开发路径

V1 继续采用 4 Pin：`5V / GND / D+ / D-`。应保证 Native USB 可用于烧录、日志和有线数据，同时保留 EN/BOOT/UART 恢复能力。

## SYSTEM_VALIDATION — 不阻止重新画原理图

### SV-01 ESP32-S3 2 MB PSRAM 并发

需要后续验证：OV5640 + Wi-Fi + MIC + Audio + IMU + Haptic 的真实内存与稳定性。

`4 MB Flash + 2 MB PSRAM` 不是 6 MB 通用 RAM；PSRAM 风险通过固件压力测试判断，不作为当前网络审查错误。

### SV-02 BK7258 多媒体 + 无线并发

固定 SDK 后测试 Camera + Audio + Wi-Fi + BLE 并发。

### SV-03 Audio 输出能力

Bone 当前参数：8Ω、标称约 1~1.5 W/只。两只并联后等效约 4Ω。

MAX98357A 方案需要后续实测：响度、每只单元功率、失真、功放与单元温升。当前不再使用“5W Bone”作为设计输入。

### SV-04 电源峰值预算

建议在 BOM/原理图完成后做 Datasheet 级估算，并在首板阶段测峰值电流、压降和温升；当前不作为阻止重新绘图的硬门槛。

## SUPPLY_CHAIN

### SC-01 BK7258QN88616 准确料号

需在采购前确认：完整 ordering code、Flash、PSRAM、封装、温度等级、MOQ 和价格。

### SC-02 LRA 参数

继续确认额定电压、谐振频率、阻抗、过驱参数和左右安装方式。

### SC-03 ICS-43434

当前 V1 接受并按现原理图器件采购。历史 INMP441 资料保留为实验记录，不再视为当前 BOM 冲突。

## MECHANICAL

- Camera FPC 的接触面 / Pin1 / 排线机械方向：原理图电气映射不因此重做，首板前完成实物确认；
- 4 Pin 磁吸接口的防反由选定机械件/结构保证；
- 3D 打印壳体需要同时容纳 PCB、电池、外置天线、Bone、双 LRA。

## 当前进入“重新绘制原理图”的出口条件

满足以下条件即可进入新版原理图绘制：

1. 当前 Requirements / BOM / Interface 已同步；
2. 双 DRV2605L 地址隔离方案已明确；
3. Plan A / Plan B 最新 Pin Matrix 完成且无资源冲突；
4. 新原理图明确 Bone ×2、DRV2605L ×2、LRA ×2、TP/Recovery。

PSRAM、峰值功耗、整机长时间并发等继续作为原理图后的系统验证项。
