# 银龄智护：找物模式与手动刷新修复验证记录

## 1. 文档信息

- 日期：2026-08-04
- 项目：`silvercare-ai-assistant`
- Android 包名：`com.medicalinsurance.longtermcare`
- 测试设备：vivo V2509A
- Android SDK：36
- 应用版本：`1.0.0`（`versionCode=1`）
- 运行模式：端侧离线模式
- 端侧组件：Qwen3-4B-Instruct-2507-MNN、DAMO-YOLO MNN、MNN Native Runtime

## 2. 本次处理范围

本次处理两个问题：

1. 找物模式中，DAMO-YOLO 已检测到杯子等目标，但应用仍返回通用障碍提示或“未找到目标”。
2. 点击“手动刷新”后等待时间很长，经常需要十几秒才返回结果。

本次修复保持以下产品策略不变：

> 即使 ASR 把前半句识别错误，找物模式仍优先使用当前摄像头的 DAMO-YOLO 检测结果，不允许本地 Qwen 根据文字猜测画面内容。

## 3. 问题一：找物目标没有传入视觉解释器

### 3.1 现场现象

修复前的真机日志显示：

- ASR 正确识别“帮我找一下杯子”。
- 处理器中的 `current_goal` 已经是“杯子”。
- DAMO-YOLO 原始检测结果包含 `cup`。
- 最终解释结果却返回 `target_detected=false`，并进入通用导航/障碍提示逻辑。

### 3.2 根因

生产环境生成的视觉提示词格式为：

```text
Current task: 找物目标：杯子
```

但 `OfflineVisionInterpreter.extractTarget()` 只识别以下旧格式：

```text
正在寻找：杯子
Target: cup
用户正在找“杯子”
```

因此视觉解释器无法取得当前找物目标。即使 DAMO-YOLO 输出中存在 `cup`，解释器也会按“没有目标的通用导航”处理。

### 3.3 修复

在 `OfflineVisionInterpreter.extractTarget()` 中优先解析生产提示词：

```java
String value = between(prompt, "Current task: 找物目标：", "\n");
```

同时保留旧格式兼容逻辑。

相关文件：

- `app/src/main/java/com/silvercare/aiassistant/OfflineVisionInterpreter.java`
- `app/src/test/java/com/silvercare/aiassistant/OfflineVisionInterpreterTest.java`
- `app/src/test/java/com/silvercare/aiassistant/MnnOfflineEngineTest.java`

### 3.4 验证结果

新增单元测试使用真实生产提示词和包含 `cup` 的 DAMO-YOLO 输出，验证结果为：

- `target_detected=true`
- `category=target`
- `subject=杯子`

手机端又运行了完整文本询问与视觉流水线回归场景：

```text
用户输入：帮我找到我的碗
actual_intent：search
current_goal：碗
视觉提示词：Current task: 找物目标：碗
DAMO-YOLO 耗时：381 ms
视觉解释总耗时：383 ms
```

测试使用的合成画面没有碗，因此应用正确返回：

```text
还没有找到碗。请缓慢转动手机继续扫描。
```

该结果说明找物目标已正确进入 DAMO-YOLO 解释链路，不再错误进入通用障碍分支。合成画面未用于证明“识别到了碗”，只用于验证目标状态和分支选择。

## 4. 问题二：手动刷新时间过长

### 4.1 根因

页面中的 `refreshNavigationOnce()` 已调用：

```javascript
tick({ force: true })
```

但 `force` 参数在后续链路中丢失：

```text
refreshNavigationOnce
  -> tick
  -> sendFrame(blob)
  -> AndroidSilverCare.sendFrame(...)
  -> SilverCareProcessor.processFrame(...)
```

因此手机日志中的手动刷新仍是：

```text
force_refresh=false
```

启用智能刷新时，每次手动点击都会先调用本地 Qwen 比较前后场景语义。历史真机日志显示，这一步额外耗时约 13～16 秒；DAMO-YOLO 本身通常只需要约 0.4～0.5 秒。

### 4.2 修复

把 `force` 参数贯穿整个 JS 与 Android Bridge 调用链：

```text
tick({ force: true })
  -> sendFrame(blob, { force: true })
  -> AndroidSilverCare.sendFrameWithOptions(..., true)
  -> submitFrame(..., true)
  -> processor.processFrame(..., true)
  -> processNavigationFrame(..., true)
```

手动刷新现在会明确绕过智能语义比较，只执行当前摄像头画面的 DAMO-YOLO 检测与确定性解释。

相关文件：

- `app/src/main/assets/static/js/main.js`
- `app/src/main/assets/static/js/network.js`
- `app/src/main/java/com/silvercare/aiassistant/MainActivity.java`
- `app/src/main/java/com/silvercare/aiassistant/SilverCareProcessor.java`
- `app/src/test/java/com/silvercare/aiassistant/SilverCareProcessorTest.java`

### 4.3 真机计时结果

在安装修复版后，通过真实点击手机顶部“手动刷新”按钮采集日志：

```text
processor_navigation_frame_start force_refresh=true
native_vision_end elapsed_ms=395
mnn_vision_end elapsed_ms=400
processor_navigation_frame_end elapsed_ms=409
```

同一刷新周期内没有出现：

```text
smart_navigation_refresh_start
```

结论：

- 手动刷新总耗时：409 ms
- DAMO-YOLO 原生推理：395 ms
- Qwen 场景语义比较：未执行
- 与修复前约 13～16 秒相比，已消除主要等待来源

## 5. 自动化测试与构建结果

### 5.1 Java 单元测试

```text
测试套件：20
测试数量：99
失败：0
错误：0
跳过：2
```

新增重点用例：

- `findsCupFromProductionSearchPrompt`
- `forcedManualRefreshBypassesSmartSemanticComparison`

### 5.2 JavaScript 检查

```text
JavaScript 静态检查：17 个文件通过
JavaScript 测试：24 项通过，0 项失败
```

### 5.3 Android 构建

```text
Gradle 任务：assembleDebug
结果：BUILD SUCCESSFUL
APK 大小：74,438,039 bytes
```

APK 路径：

```text
app/build/outputs/apk/debug/app-debug.apk
```

## 6. 手机安装与一致性校验

修复版已经通过 ADB 安装到 vivo V2509A：

```text
Performing Streamed Install
Success
lastUpdateTime=2026-08-04 22:08:00
```

构建 APK 与从手机重新拉取的已安装 APK 计算得到相同的 SHA-256：

```text
3E98461062F0BB0CB33E6E77CF2D07353050D5985016072D22201B5822678454
```

校验结论：手机当前安装的应用与本次修复构建完全一致。

安装前旧版 APK 已备份：

```text
reports/install-backups/pre-fix-20260804.apk
```

## 7. 验证资料

- `reports/device-validation/2026-08-04/latest-text_inquiry.json`：手机端文本询问与找物流水线报告
- `reports/device-validation/2026-08-04/latest.jsonl`：本次手机端诊断日志
- `reports/install-verification/installed-post-fix.apk`：从手机拉取的安装后 APK
- `reports/diagnostics/2026-08-04/latest.jsonl`：修复前问题分析使用的完整日志
- `reports/install-backups/pre-fix-20260804.apk`：安装前版本备份

## 8. 最终结论

1. 找物目标现在能从生产提示词正确传入视觉解释器。
2. 找物模式继续以当前摄像头的 DAMO-YOLO 检测为事实来源，没有改成由 Qwen 猜测画面。
3. 手动刷新会强制绕过 Qwen 场景比较，真机耗时已降至约 0.4 秒。
4. 修复版已经安装到手机，并通过 APK 哈希一致性验证。
5. 自动化测试、Android 构建和手机端找物流水线回归均已通过。

