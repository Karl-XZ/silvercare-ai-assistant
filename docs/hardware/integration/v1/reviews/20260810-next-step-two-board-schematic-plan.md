# 银龄智护 V1 — 当前原理图复盘与下一步双 PCB 实施建议

日期：2026-08-10

## 1. 当前结论

本轮 Revision 已经把很多电气需求补进现有工程，但当前工程仍然不适合直接进入 PCB。

当前应区分两类状态：

- **电气网络层**：大部分核心功能已经能从 Live Netlist 中闭环；
- **工程表达 / 双板实现层**：仍未完成。

当前最大的工程问题不是“又少了一根线”，而是：

1. A/B 仍然存在于同一个板级连接图中；
2. `J_INTER_A` 与 `J_INTER_B` 被当成同一电气网络的两个节点，而不是两个 PCB 之间的线束/FPC 边界；
3. 如果直接从当前工程更新 PCB，EDA 会继续把所有器件视为同一个 PCB 设计目标；
4. 大量 R/C/L/TP 没有显式的核心器件归属，人工无法快速判断哪些外围应随 A 板、哪些随 B 板移动；
5. 当前单页原理图存在文字重叠、长距离连线、网络标签不可读等问题，不能作为后续 PCB 的可靠人工审核文档。

因此下一步不是“直接自动布 PCB”，而是先把现有工程改造成真正的 **Multi-board Design**。

---

## 2. 双 PCB 的正确建模方式

### 2.1 推荐结构

把系统分成三个逻辑层：

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
- `SYSTEM / HARNESS` 只描述 `J_INTER_A.PinN ↔ J_INTER_B.PinN`，**不参与任何单块 PCB Netlist 生成**。

### 2.2 禁止的结构

禁止继续：

```text
BOARD A 元件 ── J_INTER_A ── J_INTER_B ── BOARD B 元件
                         ↑
                 全部仍在同一板级 NetGraph
```

因为这种结构对 EDA 来说仍然只是“一张完整电路板”。

### 2.3 板级 Net 必须是 Board-scoped

跨板连接应先在各自板内终止于 Connector：

```text
BOARD_A:
U1 / U10 / U6 ... → J_INTER_A

BOARD_B:
J_INTER_B → Battery / U11 / Bone B ...
```

两端的物理连接关系只存在于：

`inter-temple-fpc.csv / Harness Map`

而不是让一条 Wire 或全局 Net Label 直接跨两个 PCB 设计单元。

如果 EasyEDA 在同一项目内对多页 Net Label 使用全局作用域，则必须使用 board-scoped net IDs，或直接建立两个独立 schematic/PCB document，避免同名 Net 绕过 Connector 自动合并。

---

## 3. 下一版原理图建议结构

建议至少建立：

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

如果 EasyEDA 工程模型不方便使用上述目录，可用等效多页结构，但必须满足：

- Board A 和 Board B 可分别导出独立 Netlist；
- 可分别生成两个 PCB；
- 删除 Harness 文档不会改变任一板内部 Connectivity；
- A/B 之间不存在绕过 `J_INTER_A/J_INTER_B` 的直接电气连接。

---

## 4. 外围器件归属必须先完成

下一轮操作前必须读取：

`common/component-ownership.csv`

所有生产器件必须至少具有：

```text
Reference
Board
Owner_Core
Function
Local_Nets
Placement_Class
Status
```

尤其 R/C/L/D/F/TP 不允许再作为“散落的小器件”单独布局。

布局顺序必须是：

```text
Core IC
→ Local Support Group
→ Connector / Endpoint
→ Cross-module Net Label
```

而不是：

```text
先摆所有 IC
→ 再把所有 R/C 填空式塞进去
```

---

## 5. 当前外围归属中的两个已发现问题

### 5.1 C32 在 ProjectSpec 中存在，但最终 Live BOM / Netlist 中缺失

当前 `projectspec.json` 和 `connection-table-target.csv` 仍要求：

```text
C32
SYS_3V3 ↔ GND
BOARD_B_POWER
```

但最终 Live BOM / Live Netlist 中没有 C32。

因此当前“Requirement = Schematic = BOM 全部 PASS”并不真实。

下一轮必须人工确认：

- 如果 C32 是 B 侧本地 3V3 高频旁路，则补回；
- 如果确定不需要，则从 ProjectSpec / Connection Table 删除并记录设计理由。

不能继续保持“SSOT 有，实物没有，但 Regression PASS”。

### 5.2 C29 / C30 的 BOM Comment 与实际网络相反

当前实际网络：

```text
C29: SYS_3V3 ↔ GND        → DRV_B VDD bypass
C30: DRV_B_REG ↔ GND      → DRV_B REG bypass
```

但最终 BOM Comment 写成：

```text
C29 = DRV_B_REG_1UF
C30 = DRV_B_VDD_1UF
```

下一轮应修正 Comment / Description，避免 PCB Placement 按错误外围语义放置。

---

## 6. 双板切断检查（P0）

在允许生成 PCB 前，必须通过以下 Gate：

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

- U1~U10 中属于 A 的器件；
- Camera；
- MCU；
- USB；
- MAX98357A；
- J_INTER_A。

### HARNESS_MAP

逐 Pin 检查：

```text
J_INTER_A.1 ↔ J_INTER_B.1
...
J_INTER_A.12 ↔ J_INTER_B.12
```

Harness Mapping PASS 不能通过“同一个 Net 名存在于两边”来证明，必须通过 Connector Pin Mapping 单独证明。

---

## 7. 当前建议的 PCB A/B 器件划分

完整列表见 `common/component-ownership.csv`。

概要：

### Board A

- U1 BQ24074 + Charger/PowerPath 外围；
- U2 TPS63021 + buck-boost 外围；
- U3 ESP32-S3 + Boot/EN/UART/去耦；
- U4/U5 Camera LDO + 外围；
- U6 MAX98357A + 本地 Audio 外围；
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

## 8. 视觉原理图必须重做，而不是只移动现有对象

当前 Revision 的 Live Connectivity 可以作为电气参考，但当前单页 Layout 不应直接继承为最终图。

下一轮建议：

1. 保留已经验证的 NetGraph / Pin Matrix；
2. 按 Owner Group 重排组件；
3. 每个功能块只画短本地 Wire；
4. 跨模块使用**可见且有文字的 Named Net Label**；
5. 禁止大量长斜线；
6. 禁止文字与 Symbol / Wire / Label 重叠；
7. 每一页完成后生成截图做 Visual QA；
8. 最终必须有 after-overview，不允许只有 before screenshot。

最终状态应分别输出：

```text
ELECTRICAL_STATUS
BOARD_PARTITION_STATUS
HARNESS_STATUS
SCHEMATIC_READABILITY_STATUS
PCB_A_HANDOFF_STATUS
PCB_B_HANDOFF_STATUS
```

---

## 9. 下一步执行顺序

```text
P0-1  冻结 Component Ownership
↓
P0-2  将现有单板 NetGraph 拆为 Board A / Board B / Harness 三层
↓
P0-3  修正 C29/C30 语义并处理 C32 SSOT mismatch
↓
P0-4  生成 BOARD_A 独立原理图
↓
P0-5  生成 BOARD_B 独立原理图
↓
P0-6  生成 SYSTEM/HARNESS 页面
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

在 `BOARD_A_NETLIST`、`BOARD_B_NETLIST`、`HARNESS_MAP` 三项都 PASS 以前，不建议让 EDA 自动更新/生成最终 PCB。
