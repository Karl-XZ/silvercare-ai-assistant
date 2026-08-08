# DRV2605L + 0809 LRA 触觉反馈原型

> 日期：2026-08-08  
> 项目：银龄智护 / 智能眼镜硬件原型  
> 当前结论：**技术方案已完成实机验证，ESP32-S3 → I²C → DRV2605L → 0809 LRA 的完整触觉链路可用。最终“如何用振动表达交互语义”仍待后续设计与用户测试。**

## 1. 本次验证目标

本次实验不是为了直接定稿最终交互，而是先确认以下技术问题：

1. ESP32-S3 能否稳定识别并控制 DRV2605L；
2. DRV2605L 能否驱动手头的 0809 X 轴 LRA 线性马达；
3. 是否能够调用 DRV2605L 的内置触觉效果；
4. 后续是否具备做强度、节奏、渐强渐弱、警告、导航等触觉交互的技术基础。

本次四项均得到正向结果。

---

## 2. 已验证硬件

- 主控：XIAO ESP32-S3
- 触觉驱动：DRV2605L 模块
- 执行器：0809 X 轴 LRA（Linear Resonant Actuator，线性谐振马达）
- 通信：I²C
- DRV2605L I²C 地址：`0x5A`
- Arduino 库：`Adafruit DRV2605 Library`

### 接线

| DRV2605L | XIAO ESP32-S3 | 说明 |
|---|---|---|
| VIN | 3V3 | 驱动模块供电 |
| GND | GND | 共地 |
| SDA | GPIO5 / D4 | I²C 数据 |
| SCL | GPIO6 / D5 | I²C 时钟 |
| IN/TRIG | 当前 I²C 测试不使用 | 可用于外部触发、PWM/Analog、Audio-to-Vibe 等模式 |
| OUT+ / OUT- | 0809 LRA 两根线 | 马达差分输出 |

```text
XIAO ESP32-S3
    │
    ├── 3V3 ─────────────→ VIN
    ├── GND ─────────────→ GND
    ├── GPIO5 / D4 ──────→ SDA
    └── GPIO6 / D5 ──────→ SCL
                              │
                              ▼
                         DRV2605L
                           OUT+ OUT-
                              │
                              ▼
                         0809 X轴 LRA
```

## 3. 实机验证结果

### I²C 扫描

```text
Found I2C: 0x5A
```

说明 ESP32-S3 与 DRV2605L 的 I²C 控制链路正常。

### 触觉驱动测试

```cpp
drv.useLRA();
drv.selectLibrary(6);
drv.setMode(DRV2605_MODE_INTTRIG);
drv.setWaveform(0, 47);
drv.setWaveform(1, 0);
drv.go();
```

串口输出：

```text
DRV2605L connected
Vibrate!
```

实际现象：**0809 LRA 成功短暂振动/跳动一次。**

因此已经证明：

```text
ESP32-S3
   │  I²C ✅
   ▼
DRV2605L
   │  LRA驱动 ✅
   ▼
0809 LRA
   │
   └── 实际振动 ✅
```

## 4. 当前可用能力

- ROM 内置触觉效果（Effect ID 1–123）；
- 多段 Waveform Sequencer；
- RTP（Real-Time Playback）实时强度控制；
- 单击、双击、三击、Buzz、Tick、Ramp 等触觉类型；
- 心跳、呼吸、渐强、渐弱、脉冲等自定义包络；
- 距离越近 → 强度越高 / 间隔越短；
- 左右双马达方向编码（未来需双驱动或 I²C 地址复用方案）；
- 外部触发；
- PWM / Analog 输入；
- Audio-to-Vibe；
- LRA 自动谐振跟踪；
- 自动过驱与制动；
- Auto Calibration；
- Diagnostics / 执行器自检。

详细内容：

- [`DRV2605L_0809_LRA-playground.html`](./DRV2605L_0809_LRA-playground.html)
- [`2026-08-08-lab-notes.md`](./2026-08-08-lab-notes.md)
- [`references.md`](./references.md)

## 5. 当前状态：技术可行，交互方案未定稿

本次验证的目的已经完成：**振动触觉输出通道在当前硬件架构上可实现。**

尚未定稿：

- 哪一种 Effect ID 对应“确认”；
- 哪种节奏对应“危险”；
- 导航是否使用单侧/双侧触觉；
- 距离与 RTP 强度如何映射；
- 最大强度、持续时间和重复频率；
- 老年用户是否容易区分不同触觉编码；
- 马达最终在镜腿上的位置与安装结构。

下一阶段属于 **交互设计 + 人因测试 + 机械结构调优**。

## 6. 后续待办

1. 向 0809 LRA 供应商确认额定电压、最大/过驱电压、谐振频率、线圈阻抗；
2. 根据规格配置 `RATED_VOLTAGE`、`OD_CLAMP` 等底层参数；
3. 扫描并主观记录 Effect `1–123`；
4. 建立触觉效果词典；
5. 测试 RTP 心跳、呼吸、距离告警；
6. 测试马达安装在眼镜镜腿后的触感与噪声；
7. 再决定最终交互规则。

## 7. 示例程序

- [`examples/i2c_scan.ino`](./examples/i2c_scan.ino)
- [`examples/effect_47_test.ino`](./examples/effect_47_test.ino)
- [`examples/effect_scan_1_123.ino`](./examples/effect_scan_1_123.ino)
- [`examples/rtp_heartbeat.ino`](./examples/rtp_heartbeat.ino)
