# 诊断日志说明

本文档用于排查手机端真实使用时的耗时问题，重点覆盖语音识别、文本模型、视觉模型、朗读和 WebView 消息链路。

## 日志位置

应用每次启动会生成一份新的诊断会话，并清空 `latest.jsonl`：

```text
/sdcard/Android/data/com.silvercare.aiassistant/files/diagnostics/latest.jsonl
/sdcard/Android/data/com.silvercare.aiassistant/files/diagnostics/session-yyyyMMdd-HHmmss.jsonl
```

电脑端导出命令：

```powershell
$adb='C:\Users\Administrator\AppData\Local\Android\Sdk\platform-tools\adb.exe'
& $adb -s f5217dbe pull /sdcard/Android/data/com.silvercare.aiassistant/files/diagnostics/latest.jsonl C:\Users\Administrator\Desktop\work\silvercare-ai-assistant\test_runs\device_benchmarks\latest.jsonl
```

实时查看命令：

```powershell
$adb='C:\Users\Administrator\AppData\Local\Android\Sdk\platform-tools\adb.exe'
& $adb -s f5217dbe logcat -s SilverCareDiag
```

## 日志格式

每一行是一条 JSON：

```json
{"ts":1781822114034,"elapsed_realtime_ms":51099497,"session":"20260619-003513","thread":"main","event":"app_on_create","data":{"ai_runtime":"offline_mnn"}}
```

字段含义：

- `ts`：系统时间戳，毫秒。
- `elapsed_realtime_ms`：手机开机后的单调时间，适合计算相邻事件耗时。
- `session`：本次应用启动的诊断会话号。
- `thread`：事件所在 Java 线程。
- `event`：事件名。
- `data`：事件附加字段。

## 关键事件

语音请求入口：

- `speech_request_start`：用户开始一次语音请求，记录 AI/ASR/TTS 当前模式。
- `speech_request_lock_acquired`：请求锁获取成功。
- `speech_request_busy`：上一条语音还没处理完，新的点击被拒绝。
- `speech_request_lock_released`：本次请求处理完毕。

录音：

- `audio_record_start`：开始录音，记录采样率、缓冲区、最大录音时长。
- `audio_record_end`：结束录音，记录真实录音耗时、PCM 字节数、是否到达最大时长。

本地 ASR：

- `local_asr_request_start`：进入本地 ASR。
- `local_asr_transcribe_pipeline_start`：录音结束，准备送入本地 ASR。
- `local_asr_transcribe_start`：ASR 解码开始。
- `local_asr_transcribe_end`：ASR 解码完成，记录耗时和文本。
- `local_asr_transcribe_timeout`：ASR 超时。
- `local_asr_transcribe_error`：ASR 异常。

语音文本处理：

- `speech_process_recognized_start`：收到 ASR 原始文本。
- `speech_fast_correction_done`：快速校正完成。
- `speech_process_recognized_end`：文本提交给业务处理后结束。

离线模型：

- `mnn_text_start` / `mnn_text_end` / `mnn_text_error`：文本模型整体调用。
- `native_text_start` / `native_text_end` / `native_text_error`：Native Runtime 文本推理。
- `mnn_vision_start` / `mnn_vision_end` / `mnn_vision_error`：视觉模型整体调用。
- `native_vision_start` / `native_vision_end` / `native_vision_error`：Native Runtime 视觉推理。

业务处理：

- `processor_text_inquiry_start`：进入普通语音问答处理。
- `processor_inquiry_model_route`：决定走文本模型还是视觉模型。
- `processor_inquiry_result_ready`：AI 回复准备完成。
- `processor_text_inquiry_end`：本次文本问答处理结束。
- `processor_navigation_frame_start` / `processor_navigation_frame_end`：导航帧处理开始和结束。
- `smart_navigation_refresh_start` / `smart_navigation_refresh_end`：智能刷新二次语义判断。

朗读：

- `processor_speak_emit`：业务层要求朗读某句话。
- `tts_request`：Native 层收到朗读请求。
- `tts_system_submit`：已提交给系统 TTS。
- `dashscope_tts_start` / `dashscope_tts_end`：云端 TTS 合成。

WebView：

- `webview_message_send`：Native 发给页面的消息摘要，用于检查是否反复弹出同一提示。
- `js_native_message_received`：页面收到 Native 消息。
- `js_native_speech_start`：页面发起 Native 语音请求。
- `js_native_speech_stop`：页面停止 Native 录音并进入等待结果阶段。
- `js_native_response_watchdog_start`：页面启动 ASR/AI 响应看门狗。
- `js_native_asr_timeout`：页面认为 ASR 超时。
- `js_native_transcript_ready`：页面收到 Native 转写到达信号，开始等待 AI 回复。
- `js_native_ai_timeout`：页面认为 AI 回复超时。
- `js_native_response_watchdog_clear`：页面清除响应看门狗。

## 复测建议

每次复测前先完全关闭应用，再重新打开，保证 `latest.jsonl` 是新的。建议按以下顺序测试：

1. 打开应用，等待首页稳定。
2. 长按提问，说“你好，你可以做什么”。
3. 长按提问，说“帮我看看前面能不能走”。
4. 长按提问，说“帮我找我的碗”。
5. 开启导航，等待至少三次自动刷新。
6. 如出现 ASR 超时、AI 两分钟才回复或反复朗读，立刻导出 `latest.jsonl`。

分析重点：

- 如果 `audio_record_end.elapsed_ms` 接近最大录音时长，说明录音停止机制有问题。
- 如果 `local_asr_transcribe_end.elapsed_ms` 很高，说明本地 ASR 解码慢。
- 如果 `native_text_end.elapsed_ms` 很高，先看同条日志的 `role` 和 `prompt_chars`：`qwen3-4b-instruct-2507-mnn` 慢通常说明文本模型推理、冷启动、提示词长度或设备负载存在瓶颈。
- 如果 `processor_inquiry_result_ready` 很快但用户听到很慢，问题在 TTS 或前端提示队列。
- 如果反复出现相同 `webview_message_send` 或 `tts_request`，说明重复提示去重需要调整。
