# 银龄智护 V1 双镜腿分区架构

## 目的

V1 最终产品为眼镜形态，电子器件主要布置在左右两个镜腿。由于重量、体积和佩戴舒适性约束，不能把主控、电池、Camera、Audio、Haptic 等全部堆在同一个镜腿。

因此，从原理图阶段开始就把整机视为 **A / B 两个物理电子分区**，中间通过一条跨镜框 FPC / 排线连接，而不是等到 PCB 阶段再临时把单板网络切成两块。

本方案适用于 Plan A ESP32-S3 与 Plan B BK7258，两套主控尽量保持相同的物理功能分区。

> A / B 当前是工程分区名，不强行等同“左镜腿 / 右镜腿”。最终左右方向由 Camera 视角、磁吸接口位置、佩戴结构和工业设计决定。

## 核心设计目标

优先级如下：

1. **重量分配**：电池与主逻辑板分居两侧，避免单边过重；
2. **跨镜腿线数尽量少**；
3. **高速 / 敏感信号尽量不跨镜腿**：Camera DVP、主 I²S、USB、RF 优先留在 A 侧；
4. **左右执行器尽量就近放置**：左/右 LRA、Bone 各在对应镜腿；
5. **电源跨线可以接受，但必须按电流设计 FPC 铜宽和并联 Pin**；
6. 原理图必须明确 A/B Board Boundary 与 FPC Connector，不允许先画成“单板逻辑”再到 PCB 阶段随意拆分。

---

## 冻结的首版分区

### A 区 — MAIN / SENSING TEMPLE

A 区是主逻辑、高速信号与主要电源管理侧。

```text
A TEMPLE
├── MCU / SoC
├── RF / antenna interface
├── OV5640 + Camera FPC
├── Camera 2.8V / Core LDO
├── ICS-43434
├── BMI270
├── PCA9540B
├── DRV2605L A
├── LRA A
├── MAX98357A
├── Bone A
├── 4Pin Magnetic USB/Charge connector
├── USB ESD / input protection
├── Charger / Power Path
├── SYS_3V3 regulator
├── BOOT / EN / UART / Debug TP
└── Inter-temple FPC connector A
```

A 区承担：

- Camera DVP / SCCB；
- MIC I²S；
- MAX98357A I²S；
- Native USB；
- Wi-Fi / BLE / RF；
- BMI270；
- PCA9540B 上游；
- 本侧 Haptic；
- 整机主要 Power Path / Regulation。

### B 区 — BATTERY / REMOTE ACTUATOR TEMPLE

B 区以电池和远端执行器为主，用于分担重量，同时避免重复 MCU / Audio / Camera 等大功能块。

```text
B TEMPLE
├── 1S LiPo Battery
├── Battery connector / NTC interface
├── DRV2605L B
├── LRA B
├── Bone B
├── PCA9540B CH1 downstream pull-up / local decoupling
├── local 3V3 bulk / bypass capacitors
├── local TP_GND / TP_3V3
└── Inter-temple FPC connector B
```

B 区不放：

- Camera DVP；
- MCU；
- USB PHY / Magnetic USB connector；
- RF；
- I²S Audio AMP；
- Camera multi-rail regulator。

目的是避免这些高速/敏感网络跨过整副眼镜。

---

## 为什么电池放 B，主控放 A

电池通常是整机最重的单个部件，而 MCU、传感器、LDO、MUX 等 IC 单颗质量较低。

因此把：

```text
A：主控 + Camera + MIC + IMU + AMP + Power IC
B：Battery + 远端 Haptic + 远端 Bone
```

分开，比“Battery + MCU + Camera 全放同一侧”更有利于左右重量平衡。

最终是否达到平衡不能只凭 BOM 判断。机械样机阶段必须称重：

- A 侧 PCB + 器件 + 执行器 + 外壳；
- B 侧 Battery + PCB + 执行器 + 外壳。

优先通过 **电池尺寸 / 电池在镜腿前后方向的位置** 调整重心，不优先为了配重把 Camera DVP / USB / RF 等高速块搬到另一侧。

---

## 为什么磁吸 USB 放 A

磁吸口仍放 A，靠近 MCU / Native USB / Charger。

这样：

```text
MAG_USB → ESD → MCU USB D+/D-
```

保持本地，不需要把 USB D+/D- 通过跨镜腿 FPC 走一整圈。

代价是：Battery 位于 B，因此 `BAT+ / GND` 需要通过 FPC 往返 A 区 Charger / Power Path。

V1 接受这一取舍，因为电源线可以通过：

- 加宽 FPC 铜线；
- 多 Pin 并联；
- 充分 GND 回流；

解决，而高速 USB / DVP / I²S 跨长 FPC 会带来更明显的 SI / EMI / 调试风险。

---

## Haptic 的跨镜腿方式

PCA9540B 放 A 区。

```text
A SENSOR_I2C
   ├── BMI270
   └── PCA9540B
          ├── CH0 → DRV A → LRA A   （全部本地）
          └── CH1 → FPC → DRV B → LRA B

MCU HAPTIC_B_TRIG → FPC → DRV B IN/TRIG
```

因此 B 侧 Haptic 只需要跨：

- CH1 SDA；
- CH1 SCL；
- HAPTIC_B_TRIG；
- SYS_3V3；
- GND。

DRV B 的 EN 默认在 B 侧本地处理，不为了 EN 再额外占一根 FPC 信号线；如果后续确需 MCU 控制 EN，可使用 FPC 预留 Pin。

---

## Bone Audio 的跨镜腿方式

MAX98357A 放 A 区，避免 I²S 跨镜腿。

```text
MAX98357A
   ├── SPK+ / SPK- → Bone A（本地）
   └── SPK+ / SPK- → FPC → Bone B
```

因此跨镜腿仅增加一对差分 Class-D 输出：

- `SPK_P`；
- `SPK_N`。

它们必须按差分对思路布线，避免与敏感 I²C 线长距离平行耦合；最终 FPC pin ordering 在 PCB/SI 阶段根据实际连接器和铜宽进一步调整。

Bone 任意一端继续禁止接 GND。

---

## Inter-Temple FPC 基线

当前建议：**12 conductor baseline**。

它不是说整机必须最终使用 12Pin FPC，而是给首版原理图/PCB留下足够可靠性余量。

逻辑上需要的核心网络约 8 类：

```text
BAT+
GND
SYS_3V3
HAPTIC_B_SCL
HAPTIC_B_SDA
HAPTIC_B_TRIG
SPK_P
SPK_N
```

物理上增加：

- BAT+ 并联 Pin；
- GND 并联 Pin；
- BAT_NTC / TEMP 预留；
- 1 根 Spare。

详见 `inter-temple-fpc.csv`。

在电源峰值预算完成后，可决定：

- 保留 12Pin；
- 或在确认电流与温升后缩减到更少 Pin。

禁止在不知道电流的情况下为了“线越少越好”强行只给 BAT+/GND 各一条很窄的 FPC 导体。

---

## 两块 PCB 的测试点策略

原先“TP 必须精简”规则继续有效，但双板以后需要按 Board Boundary 调整：

### A 板 Mandatory

- TP_GND_A；
- TP_3V3_A；
- TP_EN / RESET；
- TP_BOOT / DOWNLOAD。

Recommended：

- TP_UART_TX；
- TP_UART_RX；
- TP_VBAT_A；
- TP_5V_A。

### B 板 Mandatory

- TP_GND_B；
- TP_3V3_B。

Optional：

- TP_BAT_B；
- HAPTIC_B SDA/SCL；
- HAPTIC_B_TRIG。

原因：如果 FPC / connector / remote rail 出问题，只在 A 板留 TP 无法快速判断 B 板是否实际得到电源。

---

## FPC / 机械设计规则

1. FPC / 排线必须从原理图开始作为正式 Connector，不是 PCB 阶段的“临时飞线”；
2. FPC 两端应使用清晰功能名，例如 `J_INTER_A` / `J_INTER_B`；
3. 必须区分逻辑 Net 与物理并联 Pin，例如 BAT+ 可占 2 个 Pin；
4. 经过镜腿铰链/动态弯折区域时，需选支持反复弯折的 FPC/Flex 结构并给出最小弯折半径；
5. 器件、焊盘、过孔不放在动态弯折区；
6. 电源大电流线优先加宽/并联；
7. Class-D `SPK_P/N` 作为差分输出成对走线；
8. I²C/Trigger 与 Class-D 线尽量隔开，必要时使用 GND Pin 做回流/隔离；
9. 最终 Pin Order 需在 PCB 阶段结合 SI/EMI 和连接器机械方向冻结；
10. FPC 断开时，A/B 两板不能因浮空信号进入危险状态；B 侧 Driver 的 EN / Trigger 必须有明确默认态。

---

## 对下一版原理图的强制要求

下一版 EDA Skill / Codex 不允许继续生成“看起来是一张单板”的逻辑原理图后再随意拆 PCB。

原理图必须明确：

```text
[A TEMPLE / MAIN BOARD]
        │
        │ J_INTER_A
        ║  Inter-Temple FPC
        │ J_INTER_B
        ▼
[B TEMPLE / REMOTE BOARD]
```

并且自动输出：

- A/B Component Partition；
- Inter-Temple Net List；
- FPC Pin Map；
- 跨板电源网络；
- 跨板信号网络；
- 每块板独立 TP；
- 跨板 Connector ERC / Netlist Audit。

任何新增器件都必须回答：

1. 放 A 还是 B？
2. 为什么？
3. 是否会增加跨镜腿线数？
4. 是否把高速/敏感信号带过 FPC？
5. 是否破坏重量分配？

## 当前状态

`ARCHITECTURE_BASELINE / MECHANICAL_VALIDATION_PENDING`

该分区方案现在可以作为下一版原理图的输入基线；最终 A/B 实际对应左/右镜腿、FPC 型号、Pin pitch、长度、弯折寿命和重量平衡需在机械样机阶段验证。