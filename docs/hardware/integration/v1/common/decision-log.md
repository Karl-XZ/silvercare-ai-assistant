# 银龄智护 V1 设计决策记录

本文件记录已经由项目负责人明确确认或在原厂资料基础上完成工程冻结的决定，用于防止后续 Skill / Codex 重复读取过期结论。

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

### D-005 双 DRV2605L 总线架构

两颗 DRV2605L 均使用固定 `0x5A` 地址。V1 两套主控统一增加：

- `PCA9540B ×1`，上游固定地址 `0x70`；
- 上游接 `SENSOR_I2C`；
- CH0 接 `DRV2605L LEFT @0x5A`；
- CH1 接 `DRV2605L RIGHT @0x5A`；
- BMI270 `0x68` 留在 MUX 上游；
- 左右 DRV 的 `IN/TRIG` 分别连接独立 MCU GPIO。

这样 Camera 可以继续占用另一套独立 SCCB/I²C，Plan A / Plan B 使用同一外围架构。

PCA9540B 同一时刻只选通一个下游 I²C 通道，因此 V1 的同步触觉策略为：先分别配置 LEFT / RIGHT，再通过两个 `IN/TRIG` GPIO 触发预设波形。严格双路高频 RTP 同步更新不作为 V1 硬要求。

DRV2605L EN 不用于地址隔离。

状态：`CONFIRMED / SCHEMATIC_REQUIRED`。

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

### D-012 Plan A 音频引脚策略

ESP32-S3 采用一个 I²S 控制器的标准全双工结构，让 ICS-43434 与 MAX98357A 共享 BCLK / WS，使用独立 DIN / DOUT。两者均采用标准 I²S，当前按相同采样率 / frame timing 设计。

目的：减少 GPIO 占用，同时保留第二套 I²S 控制器作为扩展余量。

状态：`PIN_MATRIX_FROZEN / BENCH_VALIDATION_PENDING`。

### D-013 Plan B 音频引脚策略

BK7258 为降低首版 SDK 配置风险，MIC 与 AMP 暂使用不同 I²S Group：

- ICS-43434 → I²S Group 0；
- MAX98357A → I²S Group 2。

BK7258 GPIO 余量足够，不需要为了省 2 个 GPIO 强制共用同一组时钟。

状态：`PIN_MATRIX_FROZEN`。

### D-014 双镜腿 A/B 物理分区

产品最终为眼镜形态，电子器件必须分布在两个镜腿，通过跨镜框 FPC / 排线互连。该约束从原理图阶段开始执行，不允许等到 PCB 阶段再把“单板原理图”临时拆开。

当前冻结首版分区：

**A — MAIN / SENSING TEMPLE**

- MCU / SoC + RF / 启动 /下载；
- OV5640 + Camera FPC；
- Camera 2.8V / Core LDO；
- ICS-43434；
- BMI270；
- PCA9540B；
- DRV2605L A + LRA A；
- MAX98357A + Bone A；
- 4Pin Magnetic USB + ESD；
- Charger / Power Path；
- SYS_3V3 regulator；
- 主 Debug / Recovery TP；
- Inter-temple connector A。

**B — BATTERY / REMOTE ACTUATOR TEMPLE**

- 1S LiPo；
- Battery connector / NTC；
- DRV2605L B + LRA B；
- Bone B；
- CH1 downstream pull-up / local decoupling；
- TP_GND_B / TP_3V3_B；
- Inter-temple connector B。

核心理由：

1. Battery 与主逻辑分居两侧，改善单边重量；
2. Camera DVP、I²S、USB、RF 不跨镜腿；
3. 只让低速 Haptic 控制、主电源和远端 Bone 差分输出跨 FPC；
4. A/B 只是工程分区，不提前绑定左/右镜腿。

Inter-temple FPC 当前采用 **12 conductor baseline**，包括并联 BAT+/GND、SYS_3V3、HAPTIC_B SDA/SCL/TRIG、SPK_P/N、可选 BAT_NTC 和 Spare。最终 FPC 型号、Pitch、Pin Order、铜宽、弯折寿命在机械/PCB阶段冻结。

状态：`ARCHITECTURE_BASELINE / MECHANICAL_VALIDATION_PENDING`。

详细文件：

- `dual-temple-partition.md`
- `temple-partition.csv`
- `inter-temple-fpc.csv`

## 规则

1. 新决策如果替代旧决策，必须新增条目并注明 `Supersedes`；
2. 自动化工具不得自行删除本文件中的人工确认决定；
3. 审计发现冲突时，应报告 `DOCUMENT_OUT_OF_SYNC`，而不是静默覆盖；
4. `design-requirements.md` 与本文件共同构成重新绘制原理图前的最高优先级输入。
