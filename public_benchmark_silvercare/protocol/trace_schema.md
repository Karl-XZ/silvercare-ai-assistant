# 脱敏 Trace 协议

Trace 文件：`dataset/trace_samples.jsonl`

每行记录一个任务流程，体现系统在真实使用中如何从输入到输出、确认、纠错和完成。

## 字段

- `trace_id`：全局唯一流程编号。
- `task_id`：关联任务编号。
- `trace_type`：流程类型，例如 `navigation`、`object_search`、`fall_confirmation`。
- `events`：按时间排序的事件数组。
- `task_completed`：任务是否完成。
- `caregiver_reviewable`：照护端是否可以复核。
- `manual_correction`：用户或照护人员是否做过修正。

## 事件字段

- `t_ms`：相对任务开始时间，单位毫秒。
- `event`：事件类型，例如 `voice_command`、`frame_summary`、`sensor_spike`、`assistant_response`。
- `payload`：脱敏后的摘要，不存放原始个人信息。

## 覆盖场景

本版本 trace 覆盖：

- 巡路
- 找物
- 跌倒确认
- 语音交互
- 误报抑制
- 人工修正
- 任务完成记录
- 照护人员复核

