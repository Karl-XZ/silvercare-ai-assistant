# V1 双 DRV2605L 总线方案

## 结论

V1 的 Plan A / Plan B 统一采用 **PCA9540B 2-channel I²C multiplexer** 隔离两颗固定地址 `0x5A` 的 DRV2605L。

```text
MCU SENSOR_I2C
   ├── BMI270 @0x68
   └── PCA9540B @0x70
          ├── CH0 → DRV2605L LEFT  @0x5A → LRA LEFT
          └── CH1 → DRV2605L RIGHT @0x5A → LRA RIGHT

MCU GPIO_L → DRV2605L LEFT  IN/TRIG
MCU GPIO_R → DRV2605L RIGHT IN/TRIG
```

## 为什么不直接用两条主控 I²C

两套主控都需要给 OV5640 Camera 保留独立 SCCB/I²C：

- 一条 Camera I²C；
- 一条 Sensor I²C。

如果两颗 DRV2605L 再各占一条主控 I²C，会破坏统一架构或耗尽控制器资源。

PCA9540B 只增加一颗 8-pin 器件，即可把 Sensor I²C 分成两个独立下游段。

## 为什么不能直接并联两颗 DRV2605L

DRV2605L 的 I²C 地址不可修改，两颗均为 `0x5A`。TI 对多 Driver 独立控制的建议是使用不同总线或 I²C MUX/Switch；EN 拉低不能作为可靠的地址隔离方式，因为器件仍可能 ACK。

## PCA9540B 关键属性

- upstream 固定地址：`0x70`；
- 1-of-2：同一时刻只选通 CH0 或 CH1；
- 最高 400 kHz；
- 2.3~5.5V 供电；
- 支持不同下游上拉电压；
- 8-pin；
- V1 优先考虑 `PCA9540BGD` XSON8（3 × 2 × 0.5 mm），TSSOP8 作为更易加工备选。

## I²C 上拉

必须区分三个物理段：

1. Upstream SENSOR_I2C：MCU + BMI270 + PCA9540B；
2. CH0：PCA9540B + DRV2605L LEFT；
3. CH1：PCA9540B + DRV2605L RIGHT。

V1 当前三个段均按 `SYS_3V3` 逻辑域设计，并分别配置合适的 SDA/SCL 上拉。

## 同时触发

PCA9540B 一次只能访问一个下游 I²C 段，因此“同时发送两个 I²C GO”不是 V1 的同步方案。

V1 使用：

1. CH0 配置 LEFT；
2. CH1 配置 RIGHT；
3. 两颗 DRV2605L 设为 External Edge Trigger；
4. MCU 的两个独立 Trigger GPIO 同时产生有效边沿。

用于预设 ROM / waveform sequence 时，这种方式可以避免因 MUX 串行访问造成明显的左右启动差。

## 限制

如果以后需要左右两路**持续、高刷新率、严格同步的 RTP**，PCA9540B 的 1-of-2 特性会使 I²C 更新只能串行进行。该需求出现时再评估：

- 真正的独立 I²C Bus；
- 可同时选通且支持隔离策略的其它 switch 架构；
- 可配置地址/多通道的其它 haptic driver。

当前比赛 / V1 的点击、确认、方向、警告、预设节奏等触觉不以严格双路 RTP 为硬要求。
