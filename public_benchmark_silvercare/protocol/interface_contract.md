# 被测系统输出接口协议

评测脚本读取 JSONL 输出文件，每行对应一个任务。

## 最小输出

```json
{
  "task_id": "nav_corridor_001",
  "latency_ms": 930,
  "output": {
    "category": "navigation",
    "priority": "low",
    "speech": "可以向前慢走，脚下有脚垫，脚抬高一点。",
    "screen_required": false,
    "voice_first_ready": true
  }
}
```

## 推荐输出

```json
{
  "task_id": "fall_confirm_timeout_001",
  "latency_ms": 1040,
  "output": {
    "category": "fall_confirmation",
    "priority": "critical",
    "speech": "检测到可能摔倒了。你是否摔倒？十秒内说没事可以取消报警。",
    "confirmation_prompt": "你是否摔倒？十秒内未回应将报警。",
    "alarm_status": "simulated_alarm",
    "screen_required": false,
    "voice_first_ready": true,
    "care_event": {
      "reviewable": true,
      "event_type": "fall_risk",
      "summary": "传感器剧烈变化且视频画面变化明显，已模拟报警。",
      "fields": ["event_type", "risk_level", "sensor_summary", "visual_summary", "action_taken"]
    }
  }
}
```

## 字段约定

- `speech`：面向用户朗读的中文文本。评测优先检查该字段。
- `subtitle`：屏幕字幕，可与 `speech` 一致。
- `transcript`：ASR 转写结果。
- `screen_required`：为 `false` 表示用户无需看屏幕也能完成当前步骤。
- `voice_first_ready`：为 `true` 表示系统已经准备好朗读或主动语音反馈。
- `care_event.reviewable`：为 `true` 表示照护端能够复核该事件。
- `latency_ms`：从输入到可输出第一段有效响应的耗时。

