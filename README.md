# SilverCare AI Assistant / 银龄智护

银龄智护是一款面向低视力老人、独居老人、家庭照护者和居家护理场景的 Android 端侧 AI 助手。应用以语音优先交互为核心，结合手机摄像头、离线视觉检测、端侧文本模型、本地语音识别和可选云端模型，提供居家巡路、找物、精确引导、跌倒风险确认、照护记录和管理端复核能力。

项目目标不是替代专业护理或医疗判断，而是在老人独自在家活动时提供更及时、更容易听懂的行动提醒，并让家属或照护人员可以复核关键事件。

## 核心能力

- 语音优先：支持语音输入、字幕显示、语音播报和大按钮界面，默认面向不看屏幕也能完成主要操作的使用方式。
- 端侧离线：支持本地 ASR、DAMO-YOLO 视觉检测、Qwen3 文本模型和 MNN Runtime，在无网络环境下完成主要交互链路。
- 云端可选：支持 DashScope 模式，用于更强的云端多模态理解和 TTS 能力，API Key 通过本地配置或应用设置提供。
- 居家巡路：摄像头连续观察前方环境，按小型、中型、大型障碍给出中文避障提示。
- 目标寻找：用户说“帮我找杯子/碗/手机”等目标后，系统会先校正 ASR 文本，再确认该目标是否属于离线视觉可识别类别。
- 精确引导：用户明确说出“引导”后进入持续引导模式；说“关闭、停止、退出”等指令后退出。
- 跌倒确认：结合传感器和画面变化触发风险确认，先询问用户是否摔倒，未恢复时进入模拟报警 UI。
- 管理端视图：汇总风险事件、照护任务、语音交互记录和 AI 日报，便于家庭成员或照护人员复核。
- 公开 benchmark：包含脱敏场景图片、语音、trace、评分脚本和 baseline，便于复现实验和对比优化。

## 技术架构

```text
Android WebView UI
        |
        v
SilverCareBridge (JavaScript bridge)
        |
        v
SilverCareProcessor
        |
        +-- Local ASR: Alibaba SenseVoiceSmall INT8 through sherpa-onnx
        +-- Local vision: DAMO-YOLO MNN model
        +-- Local LLM: Qwen3 text model through MNN native bridge
        +-- Local TTS: Android TTS fallback, experimental MNN TTS bridge
        +-- Cloud AI: DashScope-compatible request path
        |
        v
Captions / Speech / Care records / Diagnostics
```

## V1 可穿戴硬件集成

项目当前正在从“单模块硬件实验”进入“统一原理图 / BOM / PCB”阶段。眼镜端主要承担第一视角采集、运动感知、语音输入、触觉/骨传导反馈、无线与供电；Android 手机继续承担主要 AI 计算和任务闭环。

当前并行两套主控：

- **Plan A：ESP32-S3-MINI-1U-N4R2**；
- **Plan B：BK7258QN88616（8+16 供应商候选，采购前需再次核对完整料号）**。

当前 V1 核心硬件基线：

```text
Camera      OV5640 ×1
IMU         BMI270 ×1
MIC         ICS-43434 ×1
Audio AMP   MAX98357A ×1
Bone        8Ω ×2（并联、相同单声道）
Haptic MUX  PCA9540B ×1
Haptic      DRV2605L ×2 + 0809 LRA ×2（左右独立控制）
Battery     1S LiPo ×1
Connector   4Pin Magnetic：5V / GND / USB D+ / USB D-
```

双 Haptic 地址隔离已经冻结为：`SENSOR_I2C → PCA9540B @0x70 → CH0/CH1 → 两颗 DRV2605L @0x5A`。左右 DRV2605L 另各有一根独立 `IN/TRIG` GPIO，用于预配置波形后的左右独立/近同步触发。

Plan A / Plan B 的当前 V1 **业务 GPIO / Pin Matrix 已完成分配**。BK7258 QFN88 的 Reset / Boot / RF / 下载等封装级专用脚仍需在正式原理图阶段按 Beken Hardware Reference Design 逐 Pin 复核。

开发阶段要求保留最少但可救板的测试 / 恢复点：`GND`、`3V3`、`EN/RESET`、`BOOT/DOWNLOAD` 为必需，UART TX/RX 推荐保留。

完整硬件事实源、BOM、Signal Net、Power Tree、Pin Matrix 和问题台账位于：

```text
docs/hardware/integration/v1/
```

其中重新绘制原理图时优先读取：

- `docs/hardware/integration/v1/common/design-requirements.md`
- `docs/hardware/integration/v1/common/decision-log.md`
- `docs/hardware/integration/v1/common/common-bom.csv`
- 对应 Plan 的 `pin-matrix.csv`

`hardware/` 目录主要保存历史单模块实验，实验器件不自动等于当前 V1 最终 BOM。

**当前下一步已经从“总线 / GPIO 规划”进入“按冻结基线更新两套原理图 → Live Netlist 审计”。**

## 模型与资源策略

仓库内包含 Android 工程、MNN native bridge、DAMO-YOLO 端侧视觉模型和公开 benchmark 样例数据。较大的 Qwen 文本模型、ASR 模型和 TTS 模型由应用内下载器按需下载到应用私有目录，避免把大模型权重直接提交到仓库。

云端能力不需要把密钥提交到代码仓库。开发调试时可以在根目录创建 `local.properties`：

```properties
DASHSCOPE_API_KEY=your_key_here
```

`local.properties` 已被 `.gitignore` 忽略。

## Android Studio 打开方式

直接用 Android Studio 打开仓库根目录：

```text
silvercare-ai-assistant
```

不要只打开 `app` 子目录，否则 Gradle 无法找到根工程配置和 `mnn_tts` 子工程。

## 构建与测试

Windows PowerShell:

```powershell
.\gradlew.bat :app:assembleDebug --no-daemon
.\gradlew.bat :app:testDebugUnitTest --no-daemon
```

联网 DashScope 集成测试默认不运行。需要真实云端测试时，在本机配置 `DASHSCOPE_API_KEY` 后执行：

```powershell
.\gradlew.bat :app:testDebugUnitTest -Dsilvercare.liveDashScope=true --no-daemon
```

## Qwen / MNN / Arm SME2 调优

端侧文本链路至少使用一款 Qwen 系列模型，当前提供两个本地模型角色：

- `Qwen3-4B-Instruct-2507-MNN`：默认本地文本模型，通过 MNN native bridge 推理。
- `Qwen2.5-1.5B-Instruct-MNN`：轻量备用模型，可在开发基准中单独验证。

应用启动时会通过 Android `HWCAP2` 和 `/proc/cpuinfo` 检测 Arm SME2。检测成功后，所选配置会在 `llm->load()` 之前通过 MNN `set_config()` 写入；不支持 SME2 的设备会自动回退到 MNN 默认执行路径。Qwen3 的 thinking 模式在端侧关闭，以减少无用输出和首轮延迟。

本项目还将高频离线指令改为确定性本地路由，并为仍需 Qwen 理解的复杂请求使用小于 1000 字符的紧凑提示词。这样可避免把找物、通行检查、场景查看等明确意图先送入 4B 模型，同时保留复杂自然语言请求的 Qwen 回退能力。

2026-07-27 在 vivo V2509A（MT6993、arm64-v8a、Android SDK 36、确认支持 SME2）上的真机结果如下。每次运行都验证 Qwen 返回的 `{"ok":true}`，表中的单位为毫秒：

| 配置 | MNN 参数（比例/SME 核） | 次数 | 冷启动平均 | 热运行平均 | 语义校验 |
|---|---:|---:|---:|---:|---|
| 自动调优 | 41 / 2 | 2 | 5939 | 871 | 通过 |
| MNN 默认 | 不覆盖 | 2 | 6386 | 877 | 通过 |
| 性能优先 | 49 / 2 | 1 | 5814 | 888 | 通过 |
| 省电稳定 | 33 / 1 | 1 | 6196 | 901 | 通过 |

因此当前默认保留 `41 / 2`：它与 MNN 默认档的热运行相当，同时两轮平均冷启动约快 7%。单次结果会受温度、系统调度和后台负载影响，换用其他 SoC 后应重新运行基准，而不是直接照搬参数。

同一设备上的最终 `text_inquiry` 回归中，能力问答、通行检查、找碗和不支持目标分别耗时 7、299、281、1 毫秒，四项语义校验全部通过。其中明确但不支持的目标由优化前的 23081 毫秒降至 1 毫秒，因为它不再无意义地启动两轮 4B 推理。真实摄像头导航刷新使用 DAMO-YOLO 耗时 374 毫秒。

Debug APK 可用以下命令复测，其中 `tuning_profile` 可取 `auto`、`performance`、`efficiency` 或 `mnn_default`：

```powershell
adb shell am start -W `
  -n com.medicalinsurance.longtermcare/com.silvercare.aiassistant.LocalModelBenchmarkActivity `
  --es benchmark_test sme2_profile `
  --es tuning_profile auto `
  --el timeout_ms 180000
```

结果写入应用外部私有目录的 `files/benchmarks/latest-sme2_profile.json`，报告同时包含 SME2 检测、实际 MNN 配置、冷/热耗时和语义校验结果。

## Benchmark

公开 benchmark 位于 `public_benchmark_silvercare/`，包含：

- 脱敏真实居家场景图片和样例音频
- 巡路、找物、跌倒确认、语音交互、人工复核等任务定义
- trace 样例与结构化评分规则
- rule-based baseline 和报告生成脚本

运行方式：

```powershell
cd public_benchmark_silvercare
npm run benchmark
```

## 目录结构

```text
app/                              Android 应用源码
app/src/main/assets/              WebView UI、离线视觉模型和前端逻辑
app/src/main/java/                Android bridge、业务处理器、模型下载与推理入口
app/src/main/cpp/                 MNN native runtime bridge
docs/                             功能架构、硬件集成、日志和离线对话能力说明
hardware/                         单模块硬件实验记录（不等同于V1最终BOM）
public_benchmark_silvercare/      可复用 benchmark、样例数据和评分脚本
third_party/mnn/                  MNN 运行依赖和 mnn_tts Android 子工程
```

## 安全与隐私边界

银龄智护主要用于辅助提醒和照护复核，不提供诊断结论，不替代紧急救援系统。摄像头画面、语音和照护记录应优先保存在本机；启用云端模式前，需要向用户明确说明会上传哪些数据、用于什么目的、由谁可见。

## License

请在正式开源前根据项目依赖和发布策略补充许可证。MNN、Vosk、DashScope SDK/API 及相关模型资源需遵守各自许可证和服务条款。
