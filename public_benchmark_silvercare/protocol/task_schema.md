# 任务数据协议

任务文件：`dataset/tasks.jsonl`

每行是一个独立 JSON 对象。

## 字段

- `task_id`：全局唯一任务编号。
- `task_type`：任务类型，例如 `navigation`、`object_search`、`fall_confirmation_trace`、`asr`。
- `input`：输入媒体、语音文本、目标物或 trace。
- `expected`：评分用期望输出。

## expected 评分字段

- `category`：系统输出的任务类别。
- `priority`：风险等级，允许值为 `low`、`medium`、`high`、`critical`。
- `required_keywords`：输出语音或字幕中必须包含的关键词。
- `forbidden_keywords`：输出中不得出现的词。
- `target_detected`：找物任务是否找到目标。
- `expected_transcript`：ASR 任务期望转写文本。
- `alarm_status`：跌倒确认任务的报警状态，例如 `simulated_alarm`、`cancelled`、`no_alarm`。
- `manual_correction_applied`：人工修正是否被系统接纳。
- `screen_free`：是否支持用户不看屏幕完成任务。
- `caregiver_reviewable`：是否需要形成照护人员可复核事件。

## 新增任务建议

新增任务时应同时补充：

1. 媒体级标注：`dataset/annotations.jsonl`
2. 任务级期望：`dataset/tasks.jsonl`
3. 流程 trace：`dataset/trace_samples.jsonl`
4. baseline 输出或被测系统输出

