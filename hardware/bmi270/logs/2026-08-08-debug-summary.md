# BMI270 调试日志摘要 2026-08-08

## 已解决问题

### Arduino IDE

问题：

```
Missing FQBN
```

解决：选择 ESP32-S3 Dev Module。

### I2C扫描

成功发现：

```
Found I2C device: 0x68
```

### 六轴读取

成功输出：

```
ACC[g] X Y Z
GYRO[dps] X Y Z
```

### Python环境

缺少：

```
matplotlib
```

安装：

```
py -m pip install matplotlib pyserial
```

## 当前问题记录

部分启动情况下：

```
ERROR,BMI270_INIT
```

原因需要继续验证，可能与 ESP32 串口打开导致复位后的初始化时序有关。

## 串口问题

```
PermissionError COM13
```

原因：COM13 被其他程序占用。

解决：关闭 Arduino 串口监视器或旧 Python 程序。
