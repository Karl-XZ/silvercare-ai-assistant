# BMI270 + ESP32-S3 六轴传感器调试记录

日期：2026-08-08

## 1. 目标

为银龄智护智能眼镜建立 IMU 感知模块，用于后续：

- 姿态检测
- 跌倒风险分析
- 异常动作识别
- 与手机端算法联动

硬件：

- ESP32-S3
- BMI270 六轴 IMU 模块
- I2C 通信

## 2. 硬件连接

ESP32-S3 → BMI270：

| ESP32-S3 | BMI270 | 功能 |
|-|-|-|
| GPIO41 | SDA | I2C 数据 |
| GPIO42 | SCL | I2C 时钟 |
| 3.3V | VCC | 电源 |
| GND | GND | 地 |
| GND | AD0 | I2C 地址选择 |
| 3.3V | CS | I2C 模式 |

默认地址：0x68

## 3. I2C 通信验证

首先使用扫描程序确认设备：

```
Found I2C device: 0x68
```

说明 ESP32-S3 已经能够识别 BMI270。

## 4. 六轴读取验证

成功读取：

- 加速度 X/Y/Z
- 陀螺仪 X/Y/Z

输出格式：

```
DATA,ax,ay,az,gx,gy,gz
```

用于 Python 数据处理。

当前配置：

- Accelerometer: 100 Hz
- Gyroscope: 100 Hz
- Acc range: ±16 g
- Gyro range: ±1000 deg/s

## 5. PC端可视化

Python 程序实现：

- 实时三轴加速度曲线
- 实时三轴陀螺仪曲线
- 合加速度 |A|
- 合角速度 |ω|

用于观察动作变化。

## 6. 跌倒数据采集方案

采集标签：

- 静止
- 正常走路
- 坐下/起立
- 弯腰
- 转头
- 上下楼
- 绊倒但未跌倒
- 模拟跌倒
- 设备掉落

CSV记录内容：

```
time
label
ax ay az
acc magnitude
gx gy gz
gyro magnitude
```

## 7. 当前测试结果

已完成：

- BMI270 I2C连接 ✅
- ESP32-S3读取六轴数据 ✅
- Python实时显示 ✅
- 数据格式统一 ✅

待继续：

- 初始化稳定性优化
- INT1中断测试
- BLE传输
- Android端接收
- 跌倒算法
