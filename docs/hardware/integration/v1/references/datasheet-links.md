# V1 主控与集成参考资料

优先使用原厂/官方资料。

## ESP32-S3-MINI-1U-N4R2

- Espressif `ESP32-S3-MINI-1 & ESP32-S3-MINI-1U Datasheet`：
  - https://documentation.espressif.com/esp32-s3-mini-1_mini-1u_datasheet_en.html
- 关键已核对信息：
  - MINI-1U-N4R2：4 MB Flash + 2 MB PSRAM；
  - 尺寸 15.4 × 15.4 × 2.4 mm；
  - 外置天线接口；
  - 39 GPIO；
  - Camera / I²S / I²C / USB 等外设。

## BK7258

- Beken BK7258 官方产品页：
  - https://www.bekencorp.com/en/goods/detail/cid/60.html
- Beken BK7258 AI 智能眼镜案例：
  - https://www.bekencorp.com/en/news/newdetail/cid/27.html
- 关键已核对信息：
  - 56 GPIO；
  - 2×I²C；
  - 3×I²S；
  - 8-bit CIS DVP；
  - JPEG 编解码；
  - 720p H.264 编码；
  - USB 2.0 HS；
  - Audio ADC / DAC / DMIC；
  - Flash / PSRAM 最高 16 MB；
  - VBAT 2.0~4.35V；
  - QFN88 9×9 mm。

## BK7258QN88616 采购说明

当前方案 B 采用供应商页面展示的 `BK7258QN88616（8+16）` 作为采购候选，即按 8 MB Flash + 16 MB PSRAM 做资源预算。

**注意：**截至本次整理，公开 Beken 产品页能够确认 BK7258 系列资源，但尚未通过公开原厂页面核对 `BK7258QN88616` 这一完整订货码对应的存储配置。因此在 BOM 锁定/采购前必须向供应商或原厂确认完整料号、Flash、PSRAM、封装和温度等级。

## 项目已有实测记录

仓库内已有：

- `OV5640_ESP32-CAM调试记录.md`
- `hardware/bmi270/`
- `hardware/inmp441/`
- `docs/hardware/haptics/drv2605l-lra/`

这些实测结果作为两套新原理图的共同功能基线。
