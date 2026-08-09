# INMP441 I²S 数字麦克风实验记录

日期：2026-08-09

## 1. 实验目标

为银龄智护智能眼镜建立语音输入模块，验证低成本 MEMS 数字麦克风方案。

目标链路：

```
声音
 ↓
INMP441 MEMS Microphone
 ↓ I²S
ESP32-S3
 ↓ USB
PC
 ↓
WAV 文件
```

## 2. 硬件

- ESP32-S3 开发板
- INMP441 I²S MEMS 麦克风

## 3. 接线

| INMP441 | ESP32-S3 | 功能 |
|-|-|-|
| VDD | 3.3V | 电源 |
| GND | GND | 地 |
| SCK | GPIO4 | I²S BCLK |
| WS | GPIO5 | I²S LRCLK |
| SD | GPIO6 | 数字音频输出 |
| L/R | GND | 左声道选择 |

## 4. 第一阶段：I²S读取验证

初始测试发现：

- I²S 初始化成功；
- 但是 RMS 数据为 0；
- 判断为声道配置或数据读取问题。

随后改为同时检查左右槽位，确认：

- SD 数据正常；
- 左声道存在有效数据；
- INMP441 工作正常。

## 5. 第二阶段：WAV录音

实现：

- 16kHz 采样率；
- 16bit PCM；
- 单声道；
- 标准 WAV 封装。

## 6. 第三阶段：USB回传

最终方案放弃 Wi-Fi 下载，改为：

```
ESP32-S3
 ↓ USB Serial 921600
Python
 ↓
recordings/*.wav
```

原因：

- 录音数据量较小；
- 无需网络环境；
- 更接近后续开发调试流程。

## 7. 实测结果

测试文件：

|文件|时长|采样率|RMS|Peak|削波|
|-|-|-|-|-|-|
|191520.wav|5s|16kHz|-30.5dBFS|-15.5dBFS|0%|
|191603.wav|5s|16kHz|-19.7dBFS|-1.0dBFS|0%|
|191615.wav|5s|16kHz|-19.1dBFS|-2.0dBFS|0%|

结论：

INMP441 + ESP32-S3 音频采集链路验证成功。

## 8. 后续优化

- 增益调整；
- 24bit到16bit转换优化；
- VAD语音活动检测；
- BLE/USB实时音频流；
- Android端语音输入集成。
