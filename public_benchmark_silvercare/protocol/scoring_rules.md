# 评分规则

评测脚本执行硬性规则匹配，输出结构化指标。

## 单任务通过条件

一条任务同时满足以下适用条件即判定为通过：

- `category` 与期望一致。
- `priority` 与期望一致。
- 所有 `required_keywords` 都出现在 `speech`、`subtitle`、`transcript` 或 `confirmation_prompt` 中。
- 任一 `forbidden_keywords` 不得出现在输出文本中。
- 如果任务要求 `target_detected`，输出必须一致。
- 如果任务要求 `expected_transcript`，ASR 转写必须完全一致或包含同义核心短句。
- 如果任务要求 `alarm_status`，输出必须一致。
- 如果任务要求 `manual_correction_applied`，输出必须明确接纳人工修正。
- 如果任务要求 `screen_free`，输出必须满足 `screen_required=false` 且 `voice_first_ready=true`。
- 如果任务要求 `caregiver_reviewable`，输出必须包含 `care_event.reviewable=true`。

## 结构化指标

- `task_success_rate`：通过任务数 / 总任务数。
- `avg_response_ms`：所有任务的平均响应时间。
- `false_alarm_rate`：不应报警任务中被错误报警的比例。
- `screen_free_completion_rate`：无需看屏幕即可完成任务的比例。
- `caregiver_reviewable_rate`：要求照护复核的任务中，成功生成可复核事件的比例。
- `asr_transcript_pass_rate`：ASR 任务转写通过率。
- `manual_correction_acceptance_rate`：人工修正任务中成功接纳修正的比例。

## baseline 定位

`rule_based_v0` 是最小可复现 baseline，用于验证数据、协议和脚本是否能跑通。它不代表最终产品能力上限。

