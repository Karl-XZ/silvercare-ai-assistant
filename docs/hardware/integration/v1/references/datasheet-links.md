# V1 主控与核心器件参考资料

优先使用原厂 / 官方资料。历史实验器件与当前 V1 BOM 必须区分记录。

## ESP32-S3-MINI-1U-N4R2

- Espressif `ESP32-S3-MINI-1 & ESP32-S3-MINI-1U Datasheet`
  - https://documentation.espressif.com/esp32-s3-mini-1_mini-1u_datasheet_en.html

当前用于 V1 的关键点：

- MINI-1U-N4R2：4 MB Flash + 2 MB PSRAM；
- 15.4 × 15.4 × 2.4 mm；
- 外置 2.4 GHz 天线；
- Camera / I²S / I²C / USB 等资源；
- Native USB + Boot / EN / UART Recovery 需要进入最终 Pin Matrix。

## BK7258

- Beken BK7258 官方产品页
  - https://www.bekencorp.com/en/goods/detail/cid/60.html
- Beken BK7258 AI 智能眼镜案例
  - https://www.bekencorp.com/en/news/newdetail/cid/27.html

当前用于方案评估的关键点：

- 56 GPIO；
- 2× I²C；
- 3× I²S；
- 8-bit CIS DVP；
- JPEG / H.264 媒体能力；
- USB HS；
- Audio ADC / DAC / DMIC；
- Flash / PSRAM 最高 16 MB；
- VBAT 2.0~4.35V；
- QFN88 9×9 mm。

### BK7258QN88616 采购说明

当前方案 B 采用供应商页面展示的 `BK7258QN88616（8+16）` 作为采购候选，即暂按 8 MB Flash + 16 MB PSRAM 做资源预算。

公开原厂资料尚未完成对该完整 ordering code 的逐项核对，因此 BOM 锁定 / 采购前必须确认：完整料号、Flash、PSRAM、封装、温度等级、MOQ、价格。

## ICS-43434 — 当前 V1 MIC

- TDK / InvenSense ICS-43434 产品资料
  - https://invensense.tdk.com/products/digital/ics-43434/

当前 V1 接受 `ICS-43434 ×1`。如果采购渠道对生命周期/库存提出问题，作为供应链风险处理；不要因为历史实验使用 INMP441 就自动替换当前原理图。

## MAX98357A — 当前 V1 Audio AMP

- Analog Devices MAX98357A 产品页
  - https://www.analog.com/en/products/max98357a.html

当前 V1：

- MAX98357A ×1；
- 单声道 I²S；
- 8Ω Bone ×2；
- 两只并联，播放相同单声道；
- BTL `SPK+ / SPK-`，禁止 Bone 任意一端接 GND；
- 实际功率、响度、失真、温升属于系统实测项。

## DRV2605L — 双路 Haptic

- Texas Instruments DRV2605L 产品页
  - https://www.ti.com/product/DRV2605L

当前 V1：

- DRV2605L ×2；
- 0809 X-axis LRA ×2；
- 左右独立控制；
- 两颗驱动器固定地址均为 `0x5A`；
- 最终必须通过独立 I²C 段、I²C MUX/Switch 或其它有依据方案解决地址冲突。

## BMI270

- Bosch Sensortec BMI270
  - https://www.bosch-sensortec.com/products/motion-sensors/imus/bmi270/

当前项目历史验证：I²C 六轴数据已跑通；V1 保留 INT1。

## OV5640

当前项目使用已有 OV5640 DVP Camera 实测资料作为模组级连接基线；最终原理图仍需结合实际模组 Pinout / FPC / 供电资料复核。

仓库历史资料：

- `OV5640_ESP32-CAM调试记录.md`

## 历史实验资料（不等于当前 V1 BOM）

以下资料继续保留，因为它们证明过相应技术链路，但不得被自动化工具误认为当前最终器件：

- `hardware/inmp441/`：历史 INMP441 I²S MIC 实验；
- `hardware/bmi270/`：BMI270 实验；
- `docs/hardware/haptics/drv2605l-lra/`：单路 DRV2605L + LRA 实验；
- `OV5640_ESP32-CAM调试记录.md`：Camera 实验。

当前 V1 的最高优先级器件与数量以：

- `../common/design-requirements.md`
- `../common/decision-log.md`
- `../common/common-bom.csv`

为准。
