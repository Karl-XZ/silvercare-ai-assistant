# 银龄智护 V1 双主控硬件方案

本目录是银龄智护 V1 眼镜端硬件集成的当前工程基线。当前阶段仍并行保留两套主控路线；除主控及其必需外围差异外，Camera、IMU、MIC、Audio、Haptic、USB/磁吸接口、供电和 Android 侧功能定义尽量保持一致。

> 当前边界：比赛 / 初期开发版本，外壳采用 **3D 打印**。本项目不引入其它项目中的金属外壳、金属触控等约束。

## 方案 A — ESP32-S3

**主控：ESP32-S3-MINI-1U-N4R2**

- 4 MB Flash + 2 MB PSRAM；
- 15.4 × 15.4 mm；
- 外置 2.4 GHz 天线；
- 现有 ESP32 实验代码最容易迁移；
- 2 MB PSRAM 的全功能并发能力属于后续系统验证项，不作为当前原理图网络是否正确的判据。

## 方案 B — BK7258

**主控候选采购料号：BK7258QN88616（供应商标注 8 MB Flash + 16 MB PSRAM）**

- 资源和媒体能力更宽裕；
- 当前完整订货码、Flash/PSRAM 配置、封装和温度等级仍需在采购前向供应商/原厂确认；
- Camera + Audio + Wi-Fi + BLE 的并发能力与 SDK 成熟度属于系统验证项。

## V1 当前统一硬件基线

```text
                           Android 手机
                  AI / ASR / LLM / TTS / App
                               │
                         Wi-Fi / BLE
                               │
                    ┌──────────▼──────────┐
                    │   Plan A / Plan B  │
                    │   主控 MCU / SoC   │
                    └──────────┬──────────┘
             ┌─────────────────┼─────────────────┐
             │                 │                 │
          OV5640           ICS-43434          BMI270
        DVP + SCCB           I²S RX          I²C + INT1

主控 I²S TX → MAX98357A → SPK+/SPK-
                           ├→ 8Ω Bone LEFT
                           └→ 8Ω Bone RIGHT
                         （同一单声道，并联）

触觉：
主控 → DRV2605L LEFT  → 0809 LRA LEFT
主控 → DRV2605L RIGHT → 0809 LRA RIGHT
```

### 当前冻结数量

- OV5640 ×1；
- BMI270 ×1；
- ICS-43434 ×1；
- MAX98357A ×1；
- 8Ω 骨传导单元 ×2，标称约 1~1.5 W/只，播放相同单声道；
- DRV2605L ×2；
- 0809 X 轴 LRA ×2；
- 1S LiPo ×1；
- 4 Pin 磁吸接口 ×1：5V / GND / USB D+ / USB D-。

## 双路触觉必须注意

两颗 DRV2605L 的固定 I²C 地址均为 `0x5A`。因此两颗器件**不能未经隔离直接并联在同一 I²C 段上**并宣称可分别控制。

重新绘制原理图前必须在各方案 Pin Matrix / Signal Net 中明确采用以下之一：

1. 独立 I²C 总线；或
2. I²C Multiplexer / Switch；或
3. 其它有数据手册依据且能保证左右独立控制的方案。

该项在确定前保持 P0 `TBD`，不允许 Skill 自行猜测。

## 开发阶段测试 / 恢复接口

V1 开发板采用“最少但可救板”的测试点策略：

**Mandatory：**
- TP_GND；
- TP_3V3；
- TP_EN / RESET；
- TP_BOOT / DOWNLOAD。

**Recommended：**
- TP_UART_TX；
- TP_UART_RX。

**Optional（空间允许）：**
- TP_5V；
- TP_VBAT；
- 关键 I²C / Camera Rail 测试点。

禁止给所有网络无差别增加 TP。

## 当前文档结构

- [`common/`](./common/)：当前统一 BOM、需求、接口、问题台账、主控比较；
- [`plan-a-esp32-s3-mini-1u-n4r2/`](./plan-a-esp32-s3-mini-1u-n4r2/)：ESP32-S3 方案；
- [`plan-b-bk7258qn88616/`](./plan-b-bk7258qn88616/)：BK7258 方案；
- [`references/`](./references/)：原厂资料和历史实验资料。

## 下一步

1. 以 `common/design-requirements.md` 为当前需求事实源；
2. 明确双 DRV2605L 的地址隔离技术路径；
3. 分别完成 Plan A / Plan B 最新 Pin Matrix；
4. 根据 Pin Matrix 更新 Signal Net / Power Tree；
5. 重新绘制两套原理图；
6. 从 EDA **实时导出 Netlist** 做网络审计；
7. ERC / BOM / Requirement 三方一致性通过后，再进入 PCB。
