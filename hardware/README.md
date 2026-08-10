# 银龄智护硬件实验与 V1 集成入口

本目录用于保存银龄智护智能眼镜 / 可穿戴端的**单模块实验资产**：硬件选型、接线、最小固件、调试记录和实测数据。

> 重要：本目录中的实验器件不自动等于当前 V1 最终 BOM。当前整机设计事实源位于：
>
> `docs/hardware/integration/v1/`
>
> 其中最高优先级输入为：
>
> - `common/design-requirements.md`
> - `common/decision-log.md`
> - `common/common-bom.csv`
> - 对应主控方案的 `pin-matrix.csv`

## 已完成 / 保留的实验资产

| 模块 | 作用 | 当前实验状态 | 与 V1 的关系 | 记录 |
|---|---|---|---|---|
| BMI270 | 六轴 IMU，姿态 / 跌倒风险数据 | 六轴读取与 PC 可视化已验证 | 当前 V1 继续采用 BMI270 ×1 | [`bmi270/`](./bmi270/) |
| INMP441 | I²S 数字麦克风，语音输入 | I²S、WAV、USB 回传已验证 | **历史实验方案**；当前 V1 原理图 / 采购基线采用 ICS-43434 | [`inmp441/`](./inmp441/) |

其它重要实验资料：

- OV5640 Camera：仓库根目录 `OV5640_ESP32-CAM调试记录.md`；
- DRV2605L + 0809 LRA：`docs/hardware/haptics/drv2605l-lra/`；
- 当前 V1 双 Haptic 是在“单路已验证”的基础上扩展为 `DRV2605L ×2 + LRA ×2`；
- 双路固定 `0x5A` 地址问题已冻结为 `PCA9540B ×1`：CH0 → LEFT、CH1 → RIGHT，左右另有独立 `IN/TRIG` GPIO。

## 当前 V1 核心硬件基线摘要

```text
Camera      OV5640 ×1
IMU         BMI270 ×1
MIC         ICS-43434 ×1
Audio AMP   MAX98357A ×1
Bone        8Ω ×2（同一单声道，并联）
Haptic MUX  PCA9540B ×1
Haptic      DRV2605L ×2 + 0809 LRA ×2（左右独立）
Battery     1S LiPo ×1
Connector   4Pin Magnetic：5V / GND / USB D+ / USB D-
```

主控并行两套：

- Plan A：ESP32-S3-MINI-1U-N4R2；
- Plan B：BK7258QN88616（8+16 供应商候选）。

两套方案的业务 GPIO / Pin Matrix 已完成当前 V1 分配。详细架构、BOM、Signal Net、Power Tree、Pin Matrix 和问题台账统一见：

`docs/hardware/integration/v1/`

## 硬件实验原则

1. 先独立验证传感器 / 执行器；
2. 保存明确接线和引脚定义；
3. 保留最小测试固件；
4. 保存调试失败路径和排查方法；
5. 保存真实测试数据；
6. 单模块实验与整机设计事实源分开管理；
7. 基础链路稳定后再并入 Android / AI 主系统；
8. 新原理图必须以 V1 Requirements / Decision Log / BOM / Pin Matrix 为输入，完成后从 EDA 实时导出 Netlist 做独立审查。
