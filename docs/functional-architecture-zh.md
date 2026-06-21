# 银龄智护：多模态居家长护与跌倒风险预警系统 Android 功能架构与测试清单

本文记录当前 Android 版本的真实功能、端到端流程、关键代码入口和测试要求。目标是避免“同一条功能链被拆散”，让后续开发能按用户流程验证，而不是只验证单个按钮或单个模型调用。

## 1. 总体架构

### 1.1 运行层

- WebView UI 层：`app/src/main/assets/index.html`、`static/js/*.js`、`static/css/*.css`
- Android 原生桥：`MainActivity.SilverCareBridge`
- 业务编排：`SilverCareProcessor`
- AI 抽象：`SilverCareArtificialIntelligenceClient`
- 云端实现：`DashScopeClient`
- 端侧实现：`OfflineAiClient` + `MnnOfflineEngine` + `OfflineVisionInterpreter`
- 持久记忆：`MemoryStore`
- 本地 ASR：`VoskLocalAsrEngine`
- 本地 MNN TTS 实验入口：`LocalTtsRuntimeBridge` / `MnnTtsRuntimeBridge`，当前音质未通过可懂度验收，不进入主朗读链路。

### 1.2 消息方向

- UI 到 Android：`window.AndroidSilverCare.*`
- Android 到 UI：`window.LONG_TERM_CARE_NATIVE_MESSAGE(data)`
- 后端业务到 UI：`SilverCareProcessor.MessageSink.send(JSONObject)`
- UI 可见结果：导航卡片、字幕、状态胶囊、跌倒弹窗、设置项
- UI 可听结果：`AndroidSilverCare.speak(text)`，当前主链路优先进入手机系统 TTS，本机系统不可用时回退 DashScope TTS；本地 MNN TTS 只保留实验入口。

### 1.3 核心原则

- 状态文字不等于 AI 语音。状态如“刷新中”“手动刷新”“自动刷新”只应更新 UI，不应抢占 TTS。
- 安全事件优先。跌倒确认和报警必须强制朗读，即使普通语音优先模式关闭。
- 语音指令必须闭环。用户说“帮我找 X”后，不能只回复“正在寻找 X”，还必须进入后续视觉导航。
- 云端和端侧应共用同一套 `SilverCareProcessor` 意图和消息协议。
- 每个用户功能都应有至少一个业务单元测试或 JS 行为测试。

## 2. 用户主流程

### 2.1 启动导航

入口：
- UI：底部“启动导航”
- JS：`main.js -> toggleSystem() -> startSystem()`
- Android/AI：`network.js -> connectWS()`，本机模式走 `AndroidSilverCare.processFrame`

流程：
1. 申请后置摄像头。
2. 设置 `STATE.active = true`。
3. 读取运行时状态：云端/本地、ASR、TTS、导航刷新模式、字幕。
4. 根据刷新模式启动循环：
   - 自动刷新：每 `CONFIG.scanInterval` 毫秒调用 `tick()`
   - 手动刷新：不启动定时器，单击屏幕调用一次 `refreshNavigationOnce()`

期望输出：
- UI 状态显示“自动刷新”或“手动刷新”
- 语音不朗读“扫描中/自动刷新/手动刷新”
- AI 返回导航结果后朗读 AI 的导航内容

测试点：
- JS：`npm test` 中状态静默更新测试
- Android：`SilverCareProcessorTest.navigationFrameEmitsResultAndSpeechWithDistance`

## 3. 导航与刷新

### 3.1 自动刷新

入口：
- 设置项“导航刷新模式”
- JS：`LONG_TERM_CARE_REFRESH_SETTINGS_CHANGED`
- Android：`MainActivity.showNavigationRefreshModeDialog`

当前默认：
- 新安装默认 3 秒
- 用户保存过的历史值会继续保留，不强行覆盖
- 允许范围 1 到 10 秒

流程：
1. 设置保存 `navigation_refresh_mode=auto`
2. 保存 `navigation_refresh_interval_seconds`
3. 通知 WebView 更新 `STATE.navigationRefreshMode` 和 `CONFIG.scanInterval`
4. 若导航正在运行，重启循环

期望输出：
- 右上角显示“自动刷新”
- 设置副标题显示“自动每 N 秒刷新”
- 状态变化不抢占 AI TTS
- 如果上一条朗读还没结束，自动刷新先等待；上一条朗读结束后下一次定时 tick 再继续分析，避免连续打断。

### 3.2 手动刷新

入口：
- 设置项“导航刷新模式：手动刷新”
- UI：导航运行时单击屏幕
- JS：`main.js -> refreshNavigationOnce()`

流程：
1. 设置保存 `navigation_refresh_mode=manual`
2. 右上角显示“手动刷新”
3. 导航运行中单击屏幕，抓取一帧发送给 Android
4. AI 分析后返回 `result` 和 `speak`

期望输出：
- UI 可显示“刷新中”，但不朗读
- AI 导航内容必须朗读
- 手动刷新以用户操作为准。即使上一条朗读还没结束，用户点击刷新也会继续分析并允许新结果覆盖上一条朗读。

测试点：
- JS：状态静默更新测试
- 真机：切换手动/自动后右上角状态即时变化

### 3.3 智能刷新

入口：
- 设置项“智能刷新：语义一致时不刷新”
- Java：`SilverCareProcessor.shouldSkipSmartNavigationRefresh`

流程：
1. 视觉模型生成当前导航文本
2. 文本模型比较上一次导航语义与当前语义
3. 若 JSON 返回 `consistent=true`，发送 `smart_refresh_skipped`
4. UI 不更新导航结果、不朗读

测试点：
- `SilverCareProcessorTest.smartRefreshSkipsSemanticallyConsistentNavigationText`

## 4. 语音提问与寻找

### 4.1 语音输入

入口：
- UI：底部“长按提问”
- JS：`input.js -> startNativeSpeechInquiry()`
- Android：`MainActivity.startSpeechInquiry`

可选 ASR：
- 本地 Vosk
- 联网 DashScope
- 系统离线 SpeechRecognizer 兜底路径仍存在

流程：
1. 长按时抓取当前画面一帧
2. 开始录音或系统识别
3. ASR 产生 transcript
4. 调用 `SilverCareProcessor.processTextInquiry` 或 `processInquiry`
5. UI 显示用户字幕和 AI 字幕

期望输出：
- 用户语音识别文本显示在“我说”
- AI 回复显示在“银龄智护：多模态居家长护与跌倒风险预警系统”
- 若语音优先开启，AI 回复朗读

### 4.2 寻找物体

入口示例：
- “帮我找门”
- “我要找水杯”
- “带我去找电梯”

业务入口：
- `SilverCareProcessor.processTranscriptInquiry`
- `SilverCareProcessor.handleIntent("search")`
- `SilverCareProcessor.processNavigationFrame(imageDataUrl, true)`

正确闭环：
1. ASR 得到用户文本
2. 意图模型返回 `intent=search` 和 `search_target`
3. `currentGoal` 设置为目标物
4. UI 收到 `inquiry_result`，显示当前目标
5. App 朗读“好的，正在寻找 X”
6. 立即用同一帧再跑一次导航视觉分析
7. UI 收到 `result`
8. App 朗读具体导航内容，例如“门在左前方，向左前方走，距离 1.2 米”
9. 后续自动刷新继续追踪；手动模式下用户单击屏幕继续刷新

不能接受的状态：
- 只朗读“正在寻找 X”然后没有后续导航
- 设置了目标但 `currentGoal` 没有进入 `navigationPrompt`
- 手动刷新状态朗读覆盖 AI 导航朗读

测试点：
- `SilverCareProcessorTest.searchInquiryUpdatesGoalAndSpeaksOverride`
- `SilverCareProcessorTest.offlineInquiryUsesTextModelForIntent`
- 真机：启动导航后长按说“帮我找门”，应听到确认语和一次具体导航语

## 5. 精确引导

入口示例：
- “引导我按电梯上行按钮”
- “引导我摸到门把手”
- “引导我靠近排插”

业务入口：
- `intent=micro_nav`
- `SilverCareProcessor.processMicroFrame`
- UI：`updateMicroUI`

流程：
1. 用户必须明确说出“引导”两个字，才允许进入精确引导。
2. 语音意图设置 `mode=micro`
2. 精确引导刷新服从用户的导航刷新设置：
   - 自动模式：按用户设置的 1 到 10 秒刷新，并等待上一条朗读结束
   - 手动模式：不自动刷新，用户单击屏幕刷新一次
3. 视觉模型返回目标相对坐标 `x/y` 与 `action`
4. UI、节流朗读和空间音频提供靠近反馈
5. 到达后 `action=push`，强制提示“现在按下”

追问规则：
- 精确引导中，用户长按追问但没有说“引导”或“关闭”，不会切换目标，也不会退出引导。
- 追问会带着当前 `microTarget`、上一条短引导和当前画面进入 `microFollowUpPrompt`。
- AI 回复必须基于当前引导上下文，例如解释“它是不是在某个物体旁边”，但要继续服务于当前目标。
- 如果用户想换目标，需要重新说“引导我靠近/按/摸到 XXX”。
- 如果用户想退出，可以说“关闭”“停止”“退出”“结束”或“取消”。
- 为了让“停止”这类短词能被识别，原生录音至少保留约 850ms 后再提交，避免过短录音直接报错。

禁止行为：
- 用户只说“帮我按按钮”时自动进入精确引导。
- 用户在引导中追问“旁边是什么”时直接切到另一个引导。
- 使用“绿色行李箱旁边、排插附近”这类只靠视觉定位的完整答案。

推荐表达：
- “你前面有个行李箱。向前一步摸到行李箱后，沿它底部向下摸，排插在更靠近地面的方向。把手机对准排插再问我下一步。”
- “手机稍微向左，保持高度不变。”
- “右手沿桌边往下摸，摸到开关后停住。”

期望输出：
- 目标方向连续更新
- 到达后提示按下或停止
- 追问不会破坏当前引导状态
- 退出必须由用户说“关闭/停止/退出/结束/取消”等明确退出词触发

测试点：
- `SilverCareProcessorTest.offlineInquiryFallsBackWhenBackupModelReturnsNoJson`
- `SilverCareProcessorTest.microNavigationRequiresExplicitGuidanceKeyword`
- `SilverCareProcessorTest.microFollowUpKeepsCurrentGuidanceMode`
- `SilverCareProcessorTest.closeKeywordStopsMicroGuidance`

## 6. 任务指导

入口示例：
- “教我倒一杯水”
- “帮我拿杯子”

业务入口：
- `intent=task`
- `SilverCareProcessor.generateTaskPlan`
- `SilverCareProcessor.processTaskFrame`

流程：
1. 意图模型识别任务
2. 文本模型生成步骤 JSON 数组
3. `mode=task`
4. UI 显示步骤列表
5. 每帧检查当前步骤是否完成
6. 用户可说“完成了 / 下一步 / 重复 / 跳过 / 上一步”

期望输出：
- 开始任务时朗读第一步
- 每步完成后朗读下一步
- 任务完成后返回普通导航

测试点：
- `SilverCareProcessorTest.taskInquiryCreatesTaskPlanAndAnnouncesFirstStep`

## 7. 记忆与位置

入口示例：
- “记住这里是办公室门口”
- “我的水杯在哪里”

业务入口：
- `MemoryStore`
- `SilverCareProcessor.applyTranscriptFallback`

流程：
1. 标记地点或对象位置写入本地 SharedPreferences
2. 后续问题优先查本地记忆
3. 记忆内容进入导航 prompt 的 Memory / Known locations

期望输出：
- 记住地点后朗读确认
- 询问已记忆物体时直接回答位置，不错误进入搜索

测试点：
- `SilverCareProcessorTest.transcriptFallbackAnswersRememberedObjectLocation`

## 8. 跌倒检测

入口：
- 设置项“跌倒检测”
- JS：`input.js` 监听 `devicemotion`
- 视觉历史：`fall_detector_core.js`

判断逻辑：
1. 陀螺仪/加速度检测冲击
2. 最近数秒视频画面变化必须足够强
3. 两者同时满足才弹出确认
4. 弹出后倒计时 10 秒
5. 若用户点“我没事”或姿态恢复，取消报警
6. 倒计时结束触发模拟报警

语音要求：
- 疑似摔倒确认必须强制朗读
- 倒计时关键秒数朗读
- 模拟报警触发必须朗读

当前实现：
- `showFallAlert` 会强制朗读：“检测到疑似摔倒。如果你没有摔倒，请点击我没事。10 秒后将模拟报警。”
- `triggerFallAlarm` 会调用 Android 原生模拟报警弹窗和朗读

测试点：
- `fall_detector_core.test.mjs`：传感器和画面变化逻辑
- `caption_ui.test.mjs`：跌倒确认强制朗读

## 9. 字幕与语音优先

设置项：
- 语音优先模式：默认开启
- 语音字幕：可开启/关闭

流程：
1. ASR transcript -> `updateUserCaption`
2. AI speak -> `updateAiCaption`
3. `AndroidSilverCare.speak` 负责真正朗读

期望输出：
- 用户录音转文字显示字幕
- AI 回复显示字幕
- 字幕关闭时仍保留内部文本，但不做 live announce
- Android TTS 会把播放中/播放结束状态回传给 WebView，用于自动刷新等待上一条朗读结束。

测试点：
- `caption_ui.test.mjs`

## 10. ASR / TTS 运行方案

ASR：
- 本地 Vosk
- 联网 DashScope
- 系统 SpeechRecognizer 兜底

TTS：
- 自动模式：优先手机系统 TTS；系统 TTS 不可用时，若已配置有效 DashScope Key，则回退 DashScope TTS。
- 系统 TTS
- 联网 DashScope TTS
- 本地 MNN TTS：实验项，当前真实试听不可懂，已从主朗读链路停用。

关键要求：
- 设置里可切换 ASR/TTS
- 一键本地/云端切换应同时设置 AI、ASR、TTS
- 没有 Google TTS 时不能直接失败，必须优先尝试手机厂商系统 TTS；系统 TTS 不可用时再尝试 DashScope TTS。当前不能回退到本地 MNN TTS 作为主朗读。

测试点：
- `TtsRuntimeModeTest`
- `AsrRuntimeModeTest`
- 真机：切换 TTS 后触发一条短朗读

## 11. 模型与运行时

云端：
- DashScope 视觉、文本、ASR、TTS

本地：
- MNN 文本模型：Qwen3-4B-Instruct-2507-MNN
- 本地视觉：DAMO-YOLO 解释层
- 本地 ASR：Vosk
- 本地 MNN TTS：模型和运行时入口保留，但真实试听不可懂，当前不作为用户主朗读方案。

模型下载：
- 设置中自动下载到应用目录
- 不要求用户手动选择文件夹
- 下载状态通过 `model_download_progress` 回传 UI

测试点：
- `OfflineModelDownloaderTest`
- `OfflineModelManagerTest`
- `MnnOfflineEngineTest`
- 真机：进入设置检查下载状态和路径

## 12. 每次改动后的最低测试矩阵

### 12.1 必跑自动化

```powershell
npm test
.\gradlew.bat testDebugUnitTest --no-daemon
.\gradlew.bat assembleDebug --no-daemon
```

### 12.2 真机冒烟

1. 安装 APK。
2. 启动 App。
3. 打开设置，确认运行方案、ASR、TTS、字幕、跌倒检测、导航刷新项显示正常。
4. 切换手动/自动刷新，确认右上角状态同步。
5. 启动导航，确认 AI 导航内容能朗读。
6. 长按说“帮我找门”，确认：
   - 显示用户字幕
   - 朗读“正在寻找门”
   - 随后朗读具体导航结果
   - UI 显示目标和 result
7. 触发或模拟跌倒确认，确认：
   - 弹窗出现
   - 立即语音询问是否摔倒
   - 10 秒未取消后模拟报警并朗读
8. 切换字幕关闭/开启，确认字幕面板行为正确。

### 12.3 不允许只测的内容

- 只看 UI 状态，不听 TTS。
- 只测 ASR 文本，不测 AI 回复字幕。
- 只测“正在寻找 X”，不测后续导航 result。
- 只测跌倒算法，不测确认弹窗和语音询问。

## 13. 当前仍需继续加固的点

- 精确引导缺少完整 JS 行为测试。
- 真实跌倒流程需要真机传感器录制或注入工具测试。
- 本地 MNN TTS 已确认“能生成音频文件”不等于“可听懂”，当前需要更换模型或重新验证音质后才允许重新进入主朗读链路。
- 本地视觉 DAMO-YOLO 的真实检测质量需要独立图片集回归测试。
- 设置页目前是系统 AlertDialog 列表，功能可用，但长期应改成结构化设置页面，便于盲人按区域理解。
