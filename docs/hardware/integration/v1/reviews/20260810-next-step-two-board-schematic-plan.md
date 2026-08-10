# 银龄智护 V1 — 当前原理图复盘与下一步双 PCB 实施建议

日期：2026-08-10

## 1. 当前结论

本轮 Revision 已经把很多电气需求补进现有工程，但当前工程仍然不适合直接进入 PCB。

应区分：

- **电气网络层**：大部分核心功能已经能从 Live Netlist 中闭环；
- **工程表达 / 双板实现层**：仍未完成。

当前主要问题：

1. A/B 仍然存在于同一个板级连接图中；
2. `J_INTER_A` 与 `J_INTER_B` 被当成同一连续电气 NetGraph 的两个节点，而不是两个 PCB 之间的 Harness/FPC 边界；
3. 如果直接从当前工程更新 PCB，EDA 会继续把所有器件视为同一个 PCB 设计目标；
4. 大量 R/C/L/TP 没有显式核心器件归属；
5. 当前单页原理图存在文字重叠、长距离连线、网络标签不可读等问题。

因此下一步不是直接自动布 PCB，而是把当前工程**增量改造成真正的 Multi-board Design**。

---

## 2. 非常重要：继续修改当前工程，不从零重建

下一轮的默认策略必须是：

```text
当前已验证 Working Project
        ↓
创建 immutable checkpoint / backup
        ↓
在同一个工程谱系上做 Minimal Diff
        ↓
拆出 Board A / Board B design units
        ↓
重新组织已有对象和网络边界
        ↓
Live Readback / Netlist / Visual QA
```

禁止默认采用：

```text
新建文件夹
→ 复制工程
→ 重新把所有器件从头摆一遍
→ 重新连所有已经验证过的网络
```

`runs/`、`revision/`、`backup/` 只保存：

- immutable checkpoint；
- trace；
- diff；
- netlist；
- screenshot；
- audit/report。

它们不能变成新的设计起点。

只有以下情况才允许另建 working copy：

- 用户明确要求分支版本；
- 当前工程损坏；
- 高风险 destructive migration；
- disposable API smoke test / regression fixture。

下一轮应尽量**复用当前已经存在的 U/R/C/J/TP 和已经验证的电气网络**，通过 move、sheet reassignment、net boundary split、connector termination、label cleanup 等操作完成双板化，而不是重放全部设计工作。

---

## 3. 双 PCB 的正确建模方式

推荐三层：

```text
SYSTEM / HARNESS OVERVIEW
        │
        ├── BOARD_A schematic → BOARD_A PCB
        │
        └── BOARD_B schematic → BOARD_B PCB

BOARD_A J_INTER_A
        ║
        ║ 12Pin FPC / Harness Mapping
        ║
BOARD_B J_INTER_B
```

其中：

- `BOARD_A` 拥有自己的器件、局部网络和 PCB；
- `BOARD_B` 拥有自己的器件、局部网络和 PCB；
- `SYSTEM / HARNESS` 只描述 `J_INTER_A.PinN ↔ J_INTER_B.PinN`，不参与任何单块 PCB Netlist 生成。

禁止继续：

```text
BOARD A 元件 ── J_INTER_A ── J_INTER_B ── BOARD B 元件
                         ↑
                 全部仍在同一板级 NetGraph
```

因为这种结构对 EDA 来说仍是一张完整 PCB。

跨板连接必须先在各自板内终止于 Connector：

```text
BOARD_A:
core / local support → J_INTER_A

HARNESS:
J_INTER_A.PinN ↔ FPC conductor N ↔ J_INTER_B.PinN

BOARD_B:
J_INTER_B → core / local support
```

详细硬门禁见：

`common/two-board-netlist-boundary.md`

---

## 4. 下一版原理图建议结构

建议：

```text
00_SYSTEM_OVERVIEW        不转 PCB，仅系统框图 / Harness

BOARD_A/
01_A_POWER_USB
02_A_MCU_RF_DEBUG
03_A_CAMERA
04_A_AUDIO_MIC_IMU
05_A_HAPTIC_A
06_A_INTERCONNECT

BOARD_B/
01_B_BATTERY_POWER
02_B_HAPTIC_B
03_B_BONE_B
04_B_INTERCONNECT
```

但这里的“建立页面”不等于重新建一套器件。

优先方式：

- 把当前已有器件移动/重分配到目标页；
- 保留已经验证的 Part Identity / Reference；
- 保留正确局部网络；
- 只切断真正跨 Board Boundary 的连续 Net；
- 在 J_INTER_A / J_INTER_B 终止；
- 建立 Harness Map。

最终必须满足：

- Board A 和 Board B 可分别导出独立 Netlist；
- 可分别生成两个 PCB；
- A/B 不存在绕过 `J_INTER_A/J_INTER_B` 的电气连接。

---

## 5. 外围器件归属必须先完成

下一轮操作前必须读取：

`common/component-ownership.csv`

所有生产器件至少具有：

```text
Reference
Board
Owner_Core
Functional_Block
Purpose
Local_Nets
Placement_Class
Status
```

尤其 R/C/L/D/F/TP 不允许再作为散落的小器件单独布局。

布局/移动单位应是：

```text
Core IC
+
Local Support Group
```

例如：

```text
U2 TPS63021
├── L1
├── C5/C6/C7
├── C8/C9/C10
└── R6
```

这些器件必须作为一组留在 Board A，并在原理图/PCB 中靠近核心芯片。

---

## 6. 当前外围归属中的两个已发现问题

### 6.1 C32：SSOT 与 Live 不一致

`projectspec.json` / `connection-table-target.csv` 要求：

```text
C32
SYS_3V3 ↔ GND
BOARD_B_POWER
```

但最终 Live BOM / Netlist 没有 C32。

下一轮必须确认：

- 如果 C32 是 B 侧 3V3 高频旁路，则在当前工程中补回；
- 如果确定不需要，则从 SSOT 删除并记录理由。

当前不能继续判 Quantity/Requirement 全 PASS。

### 6.2 C29 / C30：BOM Comment 与实际 Net 相反

实际网络：

```text
C29: SYS_3V3 ↔ GND   → DRV_B VDD bypass
C30: DRV_B_REG ↔ GND → DRV_B REG bypass
```

最终 BOM Comment 写反。

下一轮只需要修改属性/说明，不需要删除并重放器件。

---

## 7. 双板切断检查（P0）

### BOARD_A_NETLIST

只包含 Board A 器件和 `J_INTER_A`。

不得包含：

- U11；
- J_BAT；
- J_LRA_B；
- J_BONE_B；
- J_INTER_B；
- B 侧局部 R/C/TP。

### BOARD_B_NETLIST

只包含 Board B 器件和 `J_INTER_B`。

不得包含：

- MCU / Camera / USB / MAX98357A；
- J_INTER_A；
- A 侧 R/C/TP。

### HARNESS_MAP

逐 Pin 单独验证：

```text
J_INTER_A.1 ↔ J_INTER_B.1
...
J_INTER_A.12 ↔ J_INTER_B.12
```

Harness PASS 不能靠“两个页面里 Net 名相同”来证明。

---

## 8. 当前 PCB A/B 器件划分

完整列表：

`common/component-ownership.csv`

### Board A

- U1 BQ24074 + Charger/PowerPath 外围；
- U2 TPS63021 + buck-boost 外围；
- U3 ESP32-S3 + Boot/EN/UART/去耦；
- U4/U5 Camera LDO + 外围；
- U6 MAX98357A + Audio 外围；
- U7 ICS-43434 + 外围；
- U8 BMI270 + 外围；
- U9 DRV2605L A + 外围；
- U10 PCA9540B + upstream/CH0 外围；
- Camera、USB、Bone A、LRA A、J_INTER_A；
- A 侧 TP。

### Board B

- Battery / J_BAT；
- U11 DRV2605L B；
- C29/C30；
- C31 + C32（C32 待确认）；
- R19/R20；
- J_LRA_B；
- J_BONE_B；
- J_INTER_B；
- TP_GND_B / TP_3V3_B。

---

## 9. 视觉原理图采用“重排”，不是“重建”

当前 Live Connectivity 可以继续作为电气参考。

下一轮应：

1. 保留已验证 Part / Reference / Net Intent；
2. 按 Owner Group 移动/重排当前器件；
3. 将一张拥挤单页拆成明确功能页；
4. 局部 R/C/L 只使用短线；
5. 跨模块使用**可见且有文字的 Named Net Label**；
6. 删除/替换无可见名称的无效 NetPort 表达；
7. 禁止大量长斜线；
8. 每页完成后 Render 做 Visual QA；
9. Final 必须存在 after-overview。

只有当当前对象本身已经损坏或无法可靠移动时，才局部 delete/recreate；不得因为页面不好看就整图从零重建。

最终状态分别输出：

```text
ELECTRICAL_STATUS
REVISION_LINEAGE_STATUS
BOARD_PARTITION_STATUS
HARNESS_STATUS
SCHEMATIC_READABILITY_STATUS
PCB_A_HANDOFF_STATUS
PCB_B_HANDOFF_STATUS
```

---

## 10. 下一步执行顺序

```text
P0-0  锁定当前 accepted working project，创建 immutable checkpoint
↓
P0-1  冻结 Component Ownership
↓
P0-2  将当前 NetGraph 增量拆为 Board A / Board B / Harness 三层
↓
P0-3  修正 C29/C30 属性并处理 C32 mismatch
↓
P0-4  复用并重排现有器件形成 BOARD_A 独立原理图
↓
P0-5  复用并重排现有器件形成 BOARD_B 独立原理图
↓
P0-6  建立 SYSTEM/HARNESS 页面
↓
P0-7  分别导出 A/B Live Netlist
↓
P0-8  Harness Pin-map Audit
↓
P1-1  Visual QA / Named Label / Collision Audit
↓
P1-2  分别生成 PCB A / PCB B
↓
P1-3  PCB 前再次验证器件数量、Footprint 和 Board Ownership
```

在 `REVISION_LINEAGE`、`BOARD_A_NETLIST`、`BOARD_B_NETLIST`、`HARNESS_MAP` 四项都 PASS 以前，不允许进入最终 PCB 自动生成。