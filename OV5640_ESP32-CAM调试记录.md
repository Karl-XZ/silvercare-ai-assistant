# 银龄智护 OV5640 与 ESP32-CAM 调试记录

## 1. 文档目的

本文档记录银龄智护智能眼镜项目中，200°广角 OV5640 摄像头从选型、接口确认、供电分析、开发板替换到首次出图的完整调试过程，并整理当前问题与后续工作。

## 2. 当前硬件

### 2.1 摄像头

- 图像传感器：OV5640
- 有效像素：500万，最大 2592 × 1944
- 传感器尺寸：1/4英寸
- 镜头：200°鱼眼广角镜头
- 接口：24 Pin DVP并行接口
- 排线长度：约78～100mm（以实物为准）
- 镜头类型：定焦/手动调焦，不是自动对焦版本

### 2.2 最初计划使用的主控

- 开发板：YD-ESP32-S3
- 模组：ESP32-S3-WROOM-1-N16R8
- Flash：16MB
- PSRAM：8MB OPI PSRAM
- 板载RGB灯：GPIO48
- 原生USB：GPIO19、GPIO20
- 串口下载：GPIO43、GPIO44

### 2.3 实际用于摄像头调试的主控

- 主板：AI Thinker风格 ESP32-CAM
- 主控：ESP-32S/经典ESP32
- 摄像头接口：24 Pin FPC
- 板载摄像头电源：2.8V和1.2V
- 板载PSRAM：约4MB
- 下载底板：ESP32-CAM-MB
- 原装摄像头：OV2640
- 替换摄像头：200°鱼眼OV5640

## 3. 系统分工原则

银龄智护第一版建议采用以下分工：

```text
眼镜端：摄像头、IMU、ToF、按键、振动、基础采集与传输
手机端：视觉识别、鱼眼校正、语音识别、语音合成、联网与管理
```

摄像头端优先输出JPEG照片或低分辨率MJPEG视频，手机负责畸变校正和AI推理。

## 4. OV5640 24 Pin接口定义

卖家提供的模组规格中，24 Pin定义如下：

| FPC脚位 | 信号 | 说明 |
| ---: | --- | --- |
| 1 | NC | 不连接 |
| 2 | AGND | 模拟地 |
| 3 | SDA | SCCB配置数据 |
| 4 | AVDD | 模拟电源，2.8～3.3V |
| 5 | SCL | SCCB配置时钟 |
| 6 | RESET | 低电平复位 |
| 7 | VSYNC | 场同步 |
| 8 | PWDN | 高电平休眠 |
| 9 | HREF | 行有效信号 |
| 10 | DVDD | 数字核心电源，1.2～1.5V |
| 11 | DOVDD | 数字接口电源，1.7～2.8V |
| 12 | Y9 / D7 | 图像数据位7 |
| 13 | MCLK / XCLK | 输入主时钟 |
| 14 | Y8 / D6 | 图像数据位6 |
| 15 | DGND | 数字地 |
| 16 | Y7 / D5 | 图像数据位5 |
| 17 | PCLK | 像素时钟 |
| 18 | Y6 / D4 | 图像数据位4 |
| 19 | Y2 / D0 | 图像数据位0 |
| 20 | Y5 / D3 | 图像数据位3 |
| 21 | Y3 / D1 | 图像数据位1 |
| 22 | Y4 / D2 | 图像数据位2 |
| 23 | NC | 不连接 |
| 24 | NC | 不连接 |

不同图纸可能从排线的相反方向编号，因此不能只比较脚号，必须同时比较完整的信号排列和排线触点方向。

## 5. 为什么DVP接口需要很多连接

DVP是并行摄像头接口。它使用8根数据线一次传输一个字节，同时需要独立的同步和配置线路：

```text
SDA/SCL：配置曝光、白平衡、输出尺寸等寄存器
XCLK：主控向摄像头提供工作时钟
Y2～Y9：8位并行图像数据
PCLK：标记每个数据字节的有效时刻
HREF：标记一行图像
VSYNC：标记一帧图像
```

24根触点中，3根为NC，其余包括数据、同步、控制、电源和地线。即使降低分辨率，8位数据总线仍然不能缩减成4根。

## 6. 无源通用转接板的结论

现有通用转接板没有稳压芯片、去耦和电平转换，只负责把FPC触点引出。

因此不能执行以下连接：

```text
ESP32 3.3V → 摄像头所有电源脚
```

特别是DVDD仅允许约1.2～1.5V，直接接3.3V可能损坏摄像头。

### 6.1 使用无源转接板所需电源

最简方案需要两路低压差稳压：

```text
ESP32 3.3V
    ├── 2.8V LDO → AVDD、DOVDD
    └── 1.5V LDO → DVDD

ESP32 GND
    ├── AGND
    └── DGND
```

注意：

- 不能使用电阻分压代替LDO。
- 每路电源应在摄像头接口附近配置0.1μF和1～4.7μF去耦电容。
- 3.3V降到2.8V时应使用低压差LDO，不建议使用压差较大的AMS1117-2.8。
- XCLK、RESET和PWDN需要考虑3.3V到2.8V的电平处理。
- SDA、SCL应上拉到DOVDD，即2.8V。
- 数据、PCLK、VSYNC和HREF由摄像头输出2.8V，通常可以直接接ESP32输入端。

可选LDO示例：

```text
2.8V：ME6211-2.8、TLV70028、XC6206-2.8
1.5V：TLV70015、ME6211-1.5、XC6206-1.5
```

## 7. YD-ESP32-S3的临时DVP GPIO方案

如果后续制作包含稳压和电平处理的有源转接板，可采用以下GPIO分配：

```cpp
#define PWDN_GPIO_NUM    1
#define RESET_GPIO_NUM   2
#define XCLK_GPIO_NUM   15
#define SIOD_GPIO_NUM    4
#define SIOC_GPIO_NUM    5

#define Y9_GPIO_NUM     16  // D7
#define Y8_GPIO_NUM     17  // D6
#define Y7_GPIO_NUM     18  // D5
#define Y6_GPIO_NUM     12  // D4
#define Y5_GPIO_NUM     10  // D3
#define Y4_GPIO_NUM      8  // D2
#define Y3_GPIO_NUM      9  // D1
#define Y2_GPIO_NUM     11  // D0

#define VSYNC_GPIO_NUM   6
#define HREF_GPIO_NUM    7
#define PCLK_GPIO_NUM   13
```

该方案避开了：

- GPIO48：板载RGB灯
- GPIO19/20：原生USB
- GPIO43/44：串口下载
- GPIO0：启动配置
- GPIO45/46：启动绑带相关引脚
- GPIO35～37：N16R8版本PSRAM相关资源

## 8. 使用ESP32-CAM替代S3进行摄像头测试

### 8.1 板卡识别

- ESP32-CAM主板的摄像头面带FPC插座、补光灯和MicroSD卡槽。
- 主板背面带ESP-32S模组。
- ESP32-CAM-MB是单独的USB下载和供电底板。

### 8.2 为什么可以直接替换OV5640

ESP32-CAM主板已经包含：

- XC6206-2.8V：供摄像头AVDD和DOVDD
- XC6206-1.2V：供摄像头DVDD
- 24 Pin摄像头插座
- PSRAM
- 完整DVP布线

OV5640模组允许1.2～1.5V DVDD，因此ESP32-CAM提供的1.2V在允许范围内。其余2.8V电源也满足要求。

更换步骤：

1. 先用原装OV2640验证主板和程序能够正常出图。
2. 断开USB电源。
3. 打开摄像头FPC插座锁扣。
4. 记住原装OV2640排线金属触点朝向。
5. 取出OV2640，按照相同触点朝向插入OV5640。
6. 确保排线完全插到底，再压紧锁扣。
7. 如果针数、宽度或间距不一致，不能强行插入。

## 9. Arduino IDE配置

在“开发板管理器”中安装：

```text
esp32 by Espressif Systems
```

不要在“库管理器”中搜索该开发板包。

开发板选择：

```text
AI Thinker ESP32-CAM
```

串口选择：

```text
ESP32-CAM-MB对应的COM端口
```

当前实际使用端口为COM8。

## 10. 单文件摄像头测试程序

该程序不依赖`board_config.h`或`camera_pins.h`，支持自动探测OV2640和OV5640，提供网页、单张JPEG和MJPEG视频流。

```cpp
#include <Arduino.h>
#include "esp_camera.h"
#include <WiFi.h>
#include "esp_http_server.h"

const char *WIFI_SSID = "你的WiFi名称";
const char *WIFI_PASSWORD = "你的WiFi密码";

#define CAM_PIN_PWDN     32
#define CAM_PIN_RESET    -1
#define CAM_PIN_XCLK      0
#define CAM_PIN_SIOD     26
#define CAM_PIN_SIOC     27

#define CAM_PIN_D7       35
#define CAM_PIN_D6       34
#define CAM_PIN_D5       39
#define CAM_PIN_D4       36
#define CAM_PIN_D3       21
#define CAM_PIN_D2       19
#define CAM_PIN_D1       18
#define CAM_PIN_D0        5

#define CAM_PIN_VSYNC    25
#define CAM_PIN_HREF     23
#define CAM_PIN_PCLK     22

httpd_handle_t cameraServer = NULL;

static const char INDEX_HTML[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>OV5640摄像头测试</title>
  <style>
    body { margin:0; padding:20px; background:#111; color:#fff;
           font-family:sans-serif; text-align:center; }
    img { display:block; width:100%; max-width:960px; height:auto;
          margin:20px auto; background:#222; border-radius:8px; }
    a { display:inline-block; padding:12px 18px; margin:6px; color:#fff;
        background:#0878d1; text-decoration:none; border-radius:6px; }
  </style>
</head>
<body>
  <h2>ESP32-CAM OV5640测试</h2>
  <a href="/capture" target="_blank">拍摄单张照片</a>
  <a href="/">刷新页面</a>
  <img src="/stream" alt="Camera stream">
</body>
</html>
)rawliteral";

static esp_err_t indexHandler(httpd_req_t *request) {
  httpd_resp_set_type(request, "text/html; charset=utf-8");
  return httpd_resp_send(request, INDEX_HTML, HTTPD_RESP_USE_STRLEN);
}

static esp_err_t captureHandler(httpd_req_t *request) {
  camera_fb_t *frame = esp_camera_fb_get();
  if (frame == NULL) {
    Serial.println("获取照片失败");
    httpd_resp_send_500(request);
    return ESP_FAIL;
  }

  httpd_resp_set_type(request, "image/jpeg");
  httpd_resp_set_hdr(request, "Content-Disposition",
                     "inline; filename=capture.jpg");
  httpd_resp_set_hdr(request, "Access-Control-Allow-Origin", "*");

  esp_err_t result = httpd_resp_send(
    request,
    reinterpret_cast<const char *>(frame->buf),
    frame->len
  );

  Serial.printf("照片大小：%u KB\n",
                static_cast<unsigned int>(frame->len / 1024));
  esp_camera_fb_return(frame);
  return result;
}

static const char *STREAM_TYPE =
  "multipart/x-mixed-replace;boundary=frame";
static const char *STREAM_BOUNDARY = "\r\n--frame\r\n";
static const char *STREAM_PART =
  "Content-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n";

static esp_err_t streamHandler(httpd_req_t *request) {
  esp_err_t result = httpd_resp_set_type(request, STREAM_TYPE);
  if (result != ESP_OK) return result;
  httpd_resp_set_hdr(request, "Access-Control-Allow-Origin", "*");

  char partHeader[64];
  while (true) {
    camera_fb_t *frame = esp_camera_fb_get();
    if (frame == NULL) {
      result = ESP_FAIL;
      break;
    }

    if (frame->format != PIXFORMAT_JPEG) {
      esp_camera_fb_return(frame);
      result = ESP_FAIL;
      break;
    }

    result = httpd_resp_send_chunk(
      request, STREAM_BOUNDARY, strlen(STREAM_BOUNDARY));

    if (result == ESP_OK) {
      size_t headerLength = snprintf(
        partHeader, sizeof(partHeader), STREAM_PART,
        static_cast<unsigned int>(frame->len));
      result = httpd_resp_send_chunk(request, partHeader, headerLength);
    }

    if (result == ESP_OK) {
      result = httpd_resp_send_chunk(
        request,
        reinterpret_cast<const char *>(frame->buf),
        frame->len
      );
    }

    esp_camera_fb_return(frame);
    if (result != ESP_OK) break;
    delay(1);
  }
  return result;
}

void startCameraServer() {
  httpd_config_t serverConfig = HTTPD_DEFAULT_CONFIG();
  serverConfig.server_port = 80;
  serverConfig.max_uri_handlers = 8;
  serverConfig.lru_purge_enable = true;

  httpd_uri_t indexUri = {};
  indexUri.uri = "/";
  indexUri.method = HTTP_GET;
  indexUri.handler = indexHandler;

  httpd_uri_t captureUri = {};
  captureUri.uri = "/capture";
  captureUri.method = HTTP_GET;
  captureUri.handler = captureHandler;

  httpd_uri_t streamUri = {};
  streamUri.uri = "/stream";
  streamUri.method = HTTP_GET;
  streamUri.handler = streamHandler;

  esp_err_t result = httpd_start(&cameraServer, &serverConfig);
  if (result != ESP_OK) {
    Serial.printf("HTTP服务器启动失败：0x%X\n", result);
    return;
  }

  httpd_register_uri_handler(cameraServer, &indexUri);
  httpd_register_uri_handler(cameraServer, &captureUri);
  httpd_register_uri_handler(cameraServer, &streamUri);
  Serial.println("HTTP摄像头服务器启动成功");
}

bool initializeCamera() {
  camera_config_t config = {};

  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = CAM_PIN_D0;
  config.pin_d1 = CAM_PIN_D1;
  config.pin_d2 = CAM_PIN_D2;
  config.pin_d3 = CAM_PIN_D3;
  config.pin_d4 = CAM_PIN_D4;
  config.pin_d5 = CAM_PIN_D5;
  config.pin_d6 = CAM_PIN_D6;
  config.pin_d7 = CAM_PIN_D7;
  config.pin_xclk = CAM_PIN_XCLK;
  config.pin_pclk = CAM_PIN_PCLK;
  config.pin_vsync = CAM_PIN_VSYNC;
  config.pin_href = CAM_PIN_HREF;
  config.pin_sccb_sda = CAM_PIN_SIOD;
  config.pin_sccb_scl = CAM_PIN_SIOC;
  config.pin_pwdn = CAM_PIN_PWDN;
  config.pin_reset = CAM_PIN_RESET;

  config.xclk_freq_hz = 20000000;
  config.pixel_format = PIXFORMAT_JPEG;
  config.frame_size = FRAMESIZE_VGA;
  config.jpeg_quality = 12;

  if (psramFound()) {
    Serial.println("检测到PSRAM");
    config.fb_count = 2;
    config.fb_location = CAMERA_FB_IN_PSRAM;
    config.grab_mode = CAMERA_GRAB_LATEST;
  } else {
    Serial.println("警告：没有检测到PSRAM");
    config.frame_size = FRAMESIZE_QVGA;
    config.jpeg_quality = 15;
    config.fb_count = 1;
    config.fb_location = CAMERA_FB_IN_DRAM;
    config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  }

  esp_err_t result = esp_camera_init(&config);
  if (result != ESP_OK) {
    Serial.printf("摄像头初始化失败，错误代码：0x%X\n", result);
    return false;
  }

  sensor_t *sensor = esp_camera_sensor_get();
  if (sensor != NULL) {
    Serial.printf("摄像头传感器PID：0x%04X\n", sensor->id.PID);
    sensor->set_vflip(sensor, 0);
    sensor->set_hmirror(sensor, 0);
    sensor->set_brightness(sensor, 0);
    sensor->set_saturation(sensor, 0);
  }

  Serial.println("摄像头初始化成功");
  return true;
}

void setup() {
  Serial.begin(115200);
  Serial.setDebugOutput(true);
  delay(1000);

  Serial.println("ESP32-CAM 摄像头测试启动");
  if (!initializeCamera()) return;

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("正在连接Wi-Fi");
  unsigned long startTime = millis();
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
    if (millis() - startTime > 30000) {
      Serial.println("\nWi-Fi连接超时");
      return;
    }
  }

  Serial.println("\nWi-Fi连接成功");
  startCameraServer();

  Serial.print("摄像头网页：http://");
  Serial.println(WiFi.localIP());
  Serial.print("单张照片：http://");
  Serial.print(WiFi.localIP());
  Serial.println("/capture");
  Serial.print("视频地址：http://");
  Serial.print(WiFi.localIP());
  Serial.println("/stream");
}

void loop() {
  delay(10000);
}
```

## 11. 当前已验证结果

### 11.1 编译与烧录

```text
Sketch uses 1028693 bytes (32%) of program storage space.
Global variables use 57224 bytes (17%) of dynamic memory.
Serial port: COM8
Chip type: ESP32-D0WD-V3 revision 3.1
Upload baud rate: 460800
Hash of data verified.
Hard resetting via RTS pin.
```

结论：程序已经完整烧录成功，Flash与内存占用正常。

### 11.2 OV5640启动日志

```text
检测到PSRAM
摄像头传感器PID：0x5640
摄像头初始化成功
正在连接Wi-Fi.....
Wi-Fi连接成功
HTTP摄像头服务器启动成功

摄像头网页：http://192.168.1.88
单张照片：http://192.168.1.88/capture
视频地址：http://192.168.1.88/stream
```

结论：

- OV5640识别成功。
- 摄像头供电正常。
- FPC接口与ESP32-CAM兼容。
- PSRAM工作正常。
- DVP数据、同步和时钟线路正常。
- Wi-Fi和HTTP视频服务正常。

## 12. 当前画面问题

当前画面存在两个不同现象：

### 12.1 圆形图像和黑色边缘

这是200°全周鱼眼镜头在4:3矩形传感器上的常见表现。镜头形成的有效图像圆小于整个OV5640传感器面积，因此会看到圆形画面和黑色边角。

黑边不能通过物理调焦消除，只能：

- 在手机端裁剪；
- 使用鱼眼反畸变重映射；
- 保留中央约120～160°视场；
- 更换能够覆盖传感器的120°或160°镜头。

### 12.2 整体严重模糊

模糊不是DVP接线或驱动问题，而是光学焦点没有落在传感器平面上。

调焦步骤：

1. 清洁镜片并检查透明保护膜。
2. 将摄像头对准1～3米外的门框、文字或棋盘格。
3. 使用`/capture`单张照片判断清晰度。
4. 在镜头和镜头座上标记初始位置。
5. 每次旋转镜头约1/16圈。
6. 如果更模糊，回到初始位置并向相反方向调整。
7. 找到1～3米范围最清晰的位置后再固定。
8. 不使用502胶，以免胶雾污染镜片。

如果镜头已经被胶固定，不能强行旋转，避免损坏FPC和镜头座。

## 13. 分辨率调整

调焦成功之前保持：

```cpp
config.frame_size = FRAMESIZE_VGA;
config.jpeg_quality = 12;
```

调焦清晰后可尝试：

```cpp
config.frame_size = FRAMESIZE_SVGA;
config.jpeg_quality = 10;
```

建议：

- 实时视频：VGA或SVGA
- 手机端障碍识别：约480～640像素输入
- 高分辨率：仅按需抓拍，不持续传输500万像素视频

## 14. 鱼眼畸变校正方案

### 14.1 能否用程序矫正

可以。200°鱼眼镜头应使用鱼眼相机模型，而不是普通针孔模型。

推荐在手机端或电脑端使用OpenCV：

```text
cv::fisheye::calibrate
cv::fisheye::estimateNewCameraMatrixForUndistortRectify
cv::fisheye::initUndistortRectifyMap
cv::remap
```

ESP32-CAM只负责输出原始JPEG。畸变校正放在手机端，因为ESP32进行逐像素重映射会消耗大量CPU和内存。

### 14.2 准确标定所需材料

建议打印棋盘格并拍摄15～20张照片：

- 棋盘格完整可见。
- 覆盖图像中央、四角和边缘。
- 包含不同距离和不同倾斜角度。
- 避免反光、运动模糊和过曝。
- 每张照片均使用相同分辨率。

标定输出参数包括：

- 相机内参矩阵K
- 鱼眼畸变系数D
- 有效裁剪区域
- 去畸变映射表map1、map2

### 14.3 单张照片的限制

单张普通场景照片只能做近似展开，无法可靠计算真实镜头内参。准确校正必须使用多张已知几何结构的棋盘格或圆点阵列照片。

## 15. 与银龄智护Android程序的集成

当前Android程序仍通过`getUserMedia()`读取手机后置摄像头，不会自动读取ESP32-CAM网络画面。

后续推荐的数据链路：

```text
ESP32-CAM /capture JPEG
        ↓
Android通过HTTP读取
        ↓
鱼眼校正与中央视场裁剪
        ↓
缩放至模型输入尺寸
        ↓
障碍物检测与语音提醒
```

现有程序的导航刷新周期约3秒、模型输入宽度约480像素，因此第一版使用`/capture`抓取单张JPEG比持续处理MJPEG更简单、更省电。

## 16. 方案评价

### ESP32-CAM适合

- 验证OV5640是否完好；
- 调试200°镜头和焦点；
- 低分辨率JPEG/MJPEG传输；
- 制作早期摄像头原型。

### ESP32-CAM的限制

- 经典ESP32性能弱于ESP32-S3；
- PSRAM通常只有4MB；
- 摄像头和MicroSD占用大量GPIO；
- 后续连接IMU、ToF、音频、振动和按键比较困难；
- 500万像素连续视频帧率较低。

### 最终建议

- 当前阶段：继续使用ESP32-CAM完成出图、调焦和鱼眼标定。
- 功能整合阶段：使用ESP32-S3-N16R8和自制有源摄像头转接板。
- AI处理阶段：将畸变校正和视觉推理放到Android手机端。

## 17. 下一步清单

- [x] 安装ESP32开发板支持包
- [x] 选择AI Thinker ESP32-CAM
- [x] 编译摄像头测试程序
- [x] 通过COM8完成烧录
- [x] 检测到PSRAM
- [x] 检测到OV5640，PID为0x5640
- [x] 启动HTTP摄像头服务
- [x] 浏览器能够查看实时画面
- [ ] 完成1～3米工作距离的手动调焦
- [ ] 保存清晰的原始`/capture`照片
- [ ] 打印鱼眼标定棋盘格
- [ ] 拍摄15～20张标定照片
- [ ] 计算OpenCV鱼眼内参与畸变系数
- [ ] 实现Android端鱼眼重映射
- [ ] 将ESP32-CAM画面接入银龄智护视觉识别流程
- [ ] 评估200°、160°和120°镜头对障碍识别的实际效果

## 18. 安全注意事项

- 所有FPC插拔必须在断电状态下进行。
- 不得把3.3V直接接入OV5640的DVDD脚。
- 不确定针脚方向时先使用万用表通断档确认。
- 不强行插入尺寸或间距不匹配的排线。
- 不使用502胶固定光学镜头。
- 不把未经验证的视觉结果作为唯一的老人避障或应急判断依据。
- 正式产品需要加入ToF、IMU和语音确认等冗余安全机制。
