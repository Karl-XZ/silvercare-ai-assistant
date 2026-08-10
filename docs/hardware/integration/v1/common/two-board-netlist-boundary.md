# 银龄智护 V1 — 双 PCB 电气边界规范

## 状态

`P0 / AUTHORITATIVE ADDENDUM`

本文件补充 `design-requirements.md` 与 `dual-temple-partition.md`，用于消除“在一张单板原理图中画 A/B 两个区域即可”的歧义。

V1 最终必须是 **两个独立 PCB 电气设计单元**，不是一个 PCB 上的两个区域。

---

## 1. 三层模型

```text
SYSTEM / HARNESS LEVEL
        │
        ├── BOARD_A ELECTRICAL DESIGN UNIT
        │       └── 独立 Board A PCB
        │
        └── BOARD_B ELECTRICAL DESIGN UNIT
                └── 独立 Board B PCB

J_INTER_A
   ║
   ║ physical 12-pin FPC / harness
   ║
J_INTER_B
```

### Board A

Board A 原理图 / Netlist 只描述：

- Board A 器件；
- Board A 局部网络；
- `J_INTER_A` 作为跨板网络终点。

### Board B

Board B 原理图 / Netlist 只描述：

- Board B 器件；
- Board B 局部网络；
- `J_INTER_B` 作为跨板网络终点。

### System / Harness

System / Harness 层只描述：

```text
J_INTER_A.PinN ↔ FPC conductor N ↔ J_INTER_B.PinN
```

它是装配/线束关系，不是一个可直接转为单块 PCB 的连续板级 Netlist。

---

## 2. P0 禁止项

禁止：

1. 使用一条普通 Wire 从 Board A 器件跨过 J_INTER_A/J_INTER_B 直接接到 Board B 器件；
2. 使用作用域覆盖两个板的同名全局 Net Label，从而绕过 FPC Connector 自动合并 A/B 网络；
3. 在同一个 PCB design unit 中同时包含 A/B 两侧全部 footprints；
4. 仅靠 PCB 绘制 Board Cutout / 分板线，把一个逻辑 PCB 假装成两个独立 PCB；
5. 在 PCB 阶段才临时判断某个 R/C/L 属于 A 还是 B。

---

## 3. Board-scoped Net

跨板信号必须先在各自板内终止于 Connector。

概念示例：

```text
Board A local:
U10.CH1_SDA → A_HAPTIC_B_SDA → J_INTER_A.7

Harness:
J_INTER_A.7 ↔ J_INTER_B.7

Board B local:
J_INTER_B.7 → B_HAPTIC_B_SDA → U11.SDA
```

A/B 板内部 Net ID 可以保留语义关联，但 EDA 不得因为名称相同而把两个 PCB design unit 合并成一个连续 Netlist。

如果 EDA 多页同名 Net Label 是全局作用域，则必须：

- 使用 board-scoped net names；或
- 建立两个独立 schematic/PCB documents；
- Harness Map 负责两端语义映射。

---

## 4. PCB Handoff Gate

生成 PCB 前必须分别导出并检查：

### `BOARD_A_NETLIST`

必须包含 `J_INTER_A`，不得包含：

- `J_INTER_B`；
- `U11`；
- `J_BAT`；
- `J_LRA_B`；
- `J_BONE_B`；
- B 侧 R/C/TP。

### `BOARD_B_NETLIST`

必须包含 `J_INTER_B`，不得包含：

- `J_INTER_A`；
- MCU / Camera / USB / RF；
- U1~U10 中属于 A 的器件；
- Board A R/C/TP。

### `HARNESS_MAP`

必须逐 Pin 验证：

```text
A connector pin
A local function
FPC conductor
B connector pin
B local function
```

三项全部 PASS 后，才允许：

```text
PCB_A_HANDOFF_STATUS = PASS
PCB_B_HANDOFF_STATUS = PASS
```

---

## 5. Component Ownership 是前置条件

`component-ownership.csv` 是双 PCB 拆分的正式输入。

所有生产器件，包括：

- R；
- C；
- L；
- D；
- F；
- TP；
- Connector；

都必须具有：

```text
Board
Owner_Core
Functional_Block
Purpose
Placement_Class
```

没有明确 Ownership 的器件：

```text
BOARD_PARTITION_STATUS = FAIL
```

禁止进入自动 PCB 放置。

---

## 6. 当前目标

下一版 EDA Revision 的目标不是“在现有单页上把 A 和 B 拉远一点”，而是：

1. 复用已经验证的电气意图；
2. 建立 Board A 独立 design unit；
3. 建立 Board B 独立 design unit；
4. 建立 System / Harness 关系；
5. 确保两个 PCB 能分别更新、分别布局、分别导出制造文件。

这才算完成 V1 双镜腿电气架构。