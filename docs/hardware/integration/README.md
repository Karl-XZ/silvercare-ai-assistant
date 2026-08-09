# 银龄智护硬件集成规划

本目录用于把已经完成的单模块实验，收敛为可进入原理图、BOM、PCB 和整机联调阶段的工程资料。

> 当前项目边界：比赛 / 初期开发版本，外壳采用 **3D 打印**。不引入其它项目中的金属外壳、金属触控等约束。

## V1 已明确的两套主控路线

当前不再继续大范围发散主控型号，而是并行推进两套方案：

### Plan A — ESP32-S3

**ESP32-S3-MINI-1U-N4R2**

- 4 MB Flash + 2 MB PSRAM；
- 15.4 × 15.4 mm；
- 外置 2.4 GHz 天线；
- 优先复用现有 ESP32 实验代码；
- 主要验证风险：2 MB PSRAM 的全功能并发余量。

### Plan B — BK7258

**BK7258QN88616（供应商候选，标注 8 MB Flash + 16 MB PSRAM）**

- BK7258 官方公开 56 GPIO、3×I²S、2×I²C、8-bit DVP、USB HS、JPEG/H.264、Audio ADC/DAC/DMIC；
- 主要验证风险：准确采购料号、SDK 迁移以及 Camera + Audio + Wi-Fi + BLE 并发。

## 两套方案共同原则

除主控及由主控引起的必要电气/PinMux/SDK 差异外，尽量共用：

- OV5640；
- BMI270；
- INMP441；
- DRV2605L + 0809 LRA；
- 骨传导单元；
- I²S Class-D 音频输出路径；
- 1S LiPo；
- 4 Pin 磁吸接口（5V / GND / USB D+ / USB D-）；
- Android 侧 AI / ASR / LLM / TTS / 任务闭环。

## 正式 V1 工程资料

进入：[`v1/`](./v1/)

其中：

- [`v1/common/`](./v1/common/)：公共 BOM、接口、问题优先级、主控比较；
- [`v1/plan-a-esp32-s3-mini-1u-n4r2/`](./v1/plan-a-esp32-s3-mini-1u-n4r2/)：ESP32-S3 方案；
- [`v1/plan-b-bk7258qn88616/`](./v1/plan-b-bk7258qn88616/)：BK7258 方案；
- [`v1/references/`](./v1/references/)：官方资料和采购核对说明。

## 下一步工程顺序

1. 完成两套 Pin Matrix；
2. 确定骨传导单元参数和 I²S Class-D 功放；
3. 冻结 1S LiPo、充电/Power Path、SYS_3V3、Camera 电源和 Audio Power；
4. 分别画两套原理图；
5. 输出两套 BOM；
6. 检查元器件采购可得性、价格、尺寸；
7. 再决定两套都打板，还是根据风险和成本淘汰其中一套。

## 旧草案

本目录根部的 `v1-hardware-status-and-issue-report.md`、`v1-power-tree.csv`、`v1-signal-net.csv` 为本轮双方案冻结前的初始草案。后续以 `v1/` 目录中的双方案资料为准。
