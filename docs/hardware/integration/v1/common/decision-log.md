# 银龄智护 V1 设计决策记录

本文件记录已经由项目负责人明确确认的决定，用于防止后续 Skill / Codex 继续重复旧问题或读取过期设计结论。

## 2026-08-10 当前有效决策

### D-001 主控并行两套

- Plan A：ESP32-S3-MINI-1U-N4R2；
- Plan B：BK7258QN88616（8+16 供应商候选，采购前核对完整料号）。

状态：`CONFIRMED`。

### D-002 MIC

V1 当前原理图和采购基线采用 `ICS-43434 ×1`。

INMP441 保留为历史实验验证资料，不要求当前版本换回 INMP441。

状态：`CONFIRMED`。

### D-003 Bone 数量与声道

- 8Ω Bone ×2；
- 每只标称约 1~1.5 W；
- 两只播放完全相同的单声道；
- 不要求左右立体声；
- MAX98357A ×1；
- 两只 Bone 并联跨接 MAX98357A `SPK+ / SPK-`；
- 禁止任一端接 GND。

状态：`CONFIRMED`。

### D-004 Haptic 数量

- DRV2605L ×2；
- 0809 X-axis LRA ×2；
- 左右分别控制；
- LEFT / RIGHT 也允许同时触发。

状态：`CONFIRMED`。

### D-005 DRV2605L 地址问题

两颗 DRV2605L 地址均为 `0x5A`。不能简单同段并联后宣称独立控制。

独立 I²C Bus / I²C MUX / Switch 的最终实现尚未冻结。

状态：`OPEN_P0`。

### D-006 TP / Recovery

开发阶段需要测试点，但数量必须精简。

Mandatory：

- TP_GND；
- TP_3V3；
- TP_EN / RESET；
- TP_BOOT / DOWNLOAD。

Recommended：

- TP_UART_TX；
- TP_UART_RX。

Optional：TP_5V、TP_VBAT、关键 Bus/Rail。

状态：`CONFIRMED`。

### D-007 4Pin 磁吸

V1 继续使用：

- 5V；
- GND；
- USB D+；
- USB D-。

用于充电、Native USB 烧录、日志和开发数据。

状态：`CONFIRMED`。

### D-008 Camera FPC

当前 24Pin 电气映射审查未发现“大量 Pin 全部接 GND”的问题。FPC 接触面 / Pin1 / 排线机械方向属于首板前机械确认项，不作为当前重新绘制的主要阻塞问题。

状态：`ELECTRICAL_ACCEPTED / MECHANICAL_PENDING`。

### D-009 Camera RESET / PWDN

控制电平是否需要额外处理尚未最终确认。依据最终 OV5640 模组资料判断，资料不足时保持 TBD，不自动增加电平转换。

状态：`PENDING`。

### D-010 ESP32 4MB + 2MB 内存理解

ESP32-S3-MINI-1U-N4R2 为 4 MB Flash + 2 MB PSRAM；两者不是 6 MB 通用 RAM。

2 MB PSRAM 是否足够整机并发属于系统压力测试，不作为当前原理图网络错误。

状态：`SYSTEM_VALIDATION_PENDING`。

### D-011 电源峰值预算

可以做 Datasheet 估算，但暂不作为重新绘制原理图的硬阻塞项；首板阶段再结合实测峰值电流、压降和温升验证。

状态：`SYSTEM_VALIDATION_PENDING`。

## 规则

1. 新决策如果替代旧决策，必须新增条目并注明 `Supersedes`；
2. 自动化工具不得自行删除本文件中的人工确认决定；
3. 审计发现冲突时，应报告 `DOCUMENT_OUT_OF_SYNC`，而不是静默覆盖；
4. `design-requirements.md` 与本文件共同构成重新绘制原理图前的最高优先级输入。
