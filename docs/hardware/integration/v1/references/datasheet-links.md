# V1 主控与核心器件参考资料

优先使用原厂 / 官方资料。历史实验器件与当前 V1 BOM 必须区分记录。

## ESP32-S3-MINI-1U-N4R2

- Espressif `ESP32-S3-MINI-1 & ESP32-S3-MINI-1U Datasheet`
  - https://documentation.espressif.com/esp32-s3-mini-1_mini-1u_datasheet_en.html
- Espressif ESP-IDF I²S documentation
  - https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/api-reference/peripherals/i2s.html

当前用于 V1 的关键点：

- MINI-1U-N4R2：4 MB Flash + 2 MB PSRAM；
- 15.4 × 15.4 × 2.4 mm；
- 外置 2.4 GHz 天线；
- GPIO19/20 为 Native USB D-/D+；
- GPIO43/44 作为 UART0 Recovery；
- GPIO0/3/45/46 为启动相关 strapping，需要谨慎；
- N4R2 的 GPIO26 被模块内 PSRAM 使用；
- 标准 I²S 全双工可让 TX/RX 共用 BCLK/WS，V1 Plan A 用于 ICS-43434 + MAX98357A。

## BK7258

- Beken BK7258 官方产品页
  - https://www.bekencorp.com/en/goods/detail/cid/60.html
- Beken `bk_idk` 官方仓库
  - https://github.com/bekencorp/bk_idk

当前用于 V1 的 GPIO / PinMux 依据来自官方 `bk7258/soc/gpio_map.h`，包括：

- Camera/JPEG：GPIO27、29~39；
- I2C1：GPIO0/1；
- I2C0：GPIO20/21；
- I²S Group0：GPIO6~9；
- I²S Group1：GPIO40~43；
- I²S Group2：GPIO44~47；
- USB0 DP/DN：GPIO12/13；
- UART 功能：GPIO10/11 可用于当前 Recovery 预留。

BK7258 CPU0/CPU1 默认日志使用 `DL_UART0`。正式 QFN88 原理图仍须依据 Beken Hardware Reference Design 核对 Reset / Boot / 下载 / RF / 晶振 / 电源的封装级引脚和外围。

### BK7258QN88616 采购说明

当前方案 B 采用供应商展示的 `BK7258QN88616（8+16）` 作为采购候选，即暂按 8 MB Flash + 16 MB PSRAM 做资源预算。

公开原厂资料尚未完成对该完整 ordering code 的逐项核对，因此 BOM 锁定 / 采购前必须确认：完整料号、Flash、PSRAM、封装、温度等级、MOQ、价格。

## PCA9540B — 当前双 Haptic I²C MUX

- NXP PCA9540B product/datasheet
  - https://www.nxp.com/products/interfaces/ic-spi-i3c-interface-devices/ic-multiplexers-switches/two-channel-ic-bus-multiplexer:PCA9540B

当前 V1 已冻结：

- PCA9540B ×1；
- upstream 地址 `0x70`；
- CH0 → DRV2605L LEFT `0x5A`；
- CH1 → DRV2605L RIGHT `0x5A`；
- 2.3~5.5V，V1 使用 SYS_3V3；
- upstream / CH0 / CH1 三段各自配置 I²C 上拉；
- 1-of-2，同一时刻仅选通一个下游通道；
- 优先 `PCA9540BGD` XSON8（3×2×0.5mm），TSSOP8 可作为加工友好备选。

## ICS-43434 — 当前 V1 MIC

- TDK / InvenSense ICS-43434 product/datasheet
  - https://invensense.tdk.com/products/digital/ics-43434/

当前 V1 接受 `ICS-43434 ×1`：24-bit standard I²S。生命周期/库存作为供应链风险处理，不因历史 INMP441 实验自动替换当前设计。

## MAX98357A — 当前 V1 Audio AMP

- Analog Devices MAX98357A product/datasheet
  - https://www.analog.com/en/products/max98357a.html

当前 V1：

- MAX98357A ×1；
- 单声道 I²S；
- 8Ω Bone ×2；
- 两只并联，播放相同单声道；
- BTL `SPK+ / SPK-`，禁止 Bone 任意一端接 GND；
- 支持标准 I²S / 24-bit 数据；
- `SD_MODE` 必须按数据手册完成模式选择和关断网络；
- 实际功率、响度、失真、温升属于系统实测项。

## DRV2605L — 双路 Haptic

- Texas Instruments DRV2605L product/datasheet
  - https://www.ti.com/product/DRV2605L

当前 V1：

- DRV2605L ×2；
- 0809 X-axis LRA ×2；
- 两颗固定地址均为 `0x5A`；
- 通过 PCA9540B CH0/CH1 隔离；
- 左右 `IN/TRIG` 分别连接独立 MCU GPIO；
- EN 不作为 I²C 地址隔离手段；
- V1 同步预设效果采用“分别配置 + Trigger GPIO 触发”。

## BMI270

- Bosch Sensortec BMI270
  - https://www.bosch-sensortec.com/products/motion-sensors/imus/bmi270/

当前项目历史验证：I²C 六轴数据已跑通；V1 保留 INT1。

## OV5640

当前项目使用已有 OV5640 DVP Camera 实测资料作为模组级连接基线；最终原理图仍需结合实际模组 Pinout / FPC / 供电资料复核。

仓库历史资料：

- `OV5640_ESP32-CAM调试记录.md`

## 历史实验资料（不等于当前 V1 BOM）

- `hardware/inmp441/`：历史 INMP441 I²S MIC 实验；
- `hardware/bmi270/`：BMI270 实验；
- `docs/hardware/haptics/drv2605l-lra/`：单路 DRV2605L + LRA 实验；
- `OV5640_ESP32-CAM调试记录.md`：Camera 实验。

当前 V1 的最高优先级输入为：

- `../common/design-requirements.md`
- `../common/decision-log.md`
- `../common/common-bom.csv`
- 对应 Plan 的 `pin-matrix.csv`
