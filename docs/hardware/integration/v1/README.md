# 银龄智护 V1 双主控硬件方案

当前阶段正式并行推进两套硬件方案。两套方案除主控及由主控引出的必要差异外，核心功能、传感器、执行器、Android 侧任务闭环和接口定义尽量保持一致。

## 方案 A — ESP32-S3

**主控：ESP32-S3-MINI-1U-N4R2**

- 4 MB Flash + 2 MB PSRAM；
- 15.4 × 15.4 mm；
- 外置 2.4 GHz 天线；
- 当前 ESP32 实验代码最容易迁移；
- 最大风险：2 MB PSRAM 是否足以支撑 Camera + Wi-Fi + MIC + Audio + IMU 并发。

选择 1U 的原因：将天线从主控模组主体中拆出，缩短主板主体长度并提高 3D 打印眼镜内部布局自由度。

## 方案 B — BK7258

**主控候选采购料号：BK7258QN88616（供应商标注 8 MB Flash + 16 MB PSRAM）**

> BK7258 芯片本体的 56 GPIO、3×I²S、2×I²C、8-bit CIS DVP、USB HS、Audio ADC/DAC/DMIC 等能力由 Beken 官方资料支持；`BK7258QN88616` 的准确订货编码和 8+16 存储配置仍需在采购前向供应商/原厂资料再次核对。

- 资源和媒体能力明显更宽裕；
- 适合多媒体可穿戴系统；
- 最大风险：最终 SDK 路线下 Camera + Audio + Wi-Fi + BLE 的并发能力与开发成熟度。

## 两套方案共同技术路径

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
           ┌───────────────────┼───────────────────┐
           │                   │                   │
        OV5640              INMP441             I²C BUS
       DVP Camera           I²S MIC        ┌───────┴───────┐
                                           │               │
                                        BMI270         DRV2605L
                                                            │
                                                          0809 LRA

主控 I²S TX → Class-D 功放 → 骨传导单元
```

共同保留：

- OV5640 DVP 摄像头；
- BMI270；
- INMP441；
- DRV2605L + 0809 LRA；
- 骨传导单元；
- I²S Class-D 音频输出技术路径；
- 1S LiPo；
- 4 Pin 磁吸接口：5V / GND / USB D+ / USB D-；
- 3D 打印外壳。

## 目录

- [`common/`](./common/)：两套方案共用的 BOM、接口和问题台账；
- [`plan-a-esp32-s3-mini-1u-n4r2/`](./plan-a-esp32-s3-mini-1u-n4r2/)：ESP32-S3 方案；
- [`plan-b-bk7258qn88616/`](./plan-b-bk7258qn88616/)：BK7258 方案；
- [`references/`](./references/)：官方资料来源。

## 下一步

1. 分别完成两套方案的 Pin Matrix；
2. 冻结骨传导功放；
3. 冻结充电、电池、3.3V、Camera 电源和 Audio Power；
4. 完成两套原理图；
5. 输出两套 BOM 并做采购可得性/成本检查；
6. 根据原理图和 BOM 决定是否继续两套打板，或淘汰其中一套。
