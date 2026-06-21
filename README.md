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
        +-- Local ASR: Vosk Chinese model
        +-- Local vision: DAMO-YOLO MNN model
        +-- Local LLM: Qwen3 text model through MNN native bridge
        +-- Local TTS: Android TTS fallback, experimental MNN TTS bridge
        +-- Cloud AI: DashScope-compatible request path
        |
        v
Captions / Speech / Care records / Diagnostics
```

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
docs/                             功能架构、日志和离线对话能力说明
public_benchmark_silvercare/      可复用 benchmark、样例数据和评分脚本
third_party/mnn/                  MNN 运行依赖和 mnn_tts Android 子工程
```

## 安全与隐私边界

银龄智护主要用于辅助提醒和照护复核，不提供诊断结论，不替代紧急救援系统。摄像头画面、语音和照护记录应优先保存在本机；启用云端模式前，需要向用户明确说明会上传哪些数据、用于什么目的、由谁可见。

## License

请在正式开源前根据项目依赖和发布策略补充许可证。MNN、Vosk、DashScope SDK/API 及相关模型资源需遵守各自许可证和服务条款。
