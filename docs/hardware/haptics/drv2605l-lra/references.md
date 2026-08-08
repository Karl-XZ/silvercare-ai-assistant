# DRV2605L / LRA 参考与玩法清单

## 官方参考

- Texas Instruments — DRV2605L 产品页  
  https://www.ti.com/product/DRV2605L
- Texas Instruments — DRV2605L Datasheet  
  https://www.ti.com/lit/ds/symlink/drv2605l.pdf
- Adafruit — DRV2605L Haptic Controller Arduino Guide  
  https://learn.adafruit.com/adafruit-drv2605-haptic-controller-breakout/arduino-code
- Adafruit_DRV2605 Library  
  https://github.com/adafruit/Adafruit_DRV2605_Library

## 可研究功能

### 产品交互层

- 单 Click / 双 Click / 三 Click
- Tick / Bump / Buzz / Hum
- 渐强 / 渐弱
- 心跳 / 呼吸 / 节拍器
- 连接/断开状态
- 操作确认 / 失败 / 任务完成
- 长按完成反馈
- UI 滚轮刻度 / 边界碰撞
- 分级警告
- 距离越近越强 / 越密
- IMU 事件提示
- 未来左右导航编码
- 音频事件同步

### 驱动层

- ROM waveform library
- Waveform sequencer
- RTP real-time playback
- Internal trigger
- External edge / level trigger
- PWM / Analog input
- Audio-to-Vibe
- Auto Calibration
- Diagnostics
- LRA auto resonance tracking
- Automatic overdrive
- Automatic braking

## 当前原则

### 可以反复实验

Effect ID、节奏、停顿、RTP 包络、事件映射、提示优先级、左右编码。

### 应按马达规格确定

`RATED_VOLTAGE`、`OD_CLAMP`、Feedback / BEMF Gain、Drive Time、开环频率、校准相关底层参数。
