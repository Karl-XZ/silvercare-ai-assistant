# 用户反馈数据协议

用户反馈文件：`dataset/user_feedback.jsonl`

每行是一位参与者的脱敏测试反馈摘要，不包含姓名、联系方式、住址、机构和可识别身份信息。

## 字段

- `participant_id`：脱敏编号。
- `age`：年龄。
- `gender`：性别。
- `profile`：健康和居住特征摘要。
- `test_duration`：测试周期。
- `validated_scenarios`：用户实际验证过的场景。
- `positive_signals`：明确正向反馈。
- `pain_points`：暴露问题。
- `improvement_tasks`：对应改进任务。

## 使用方式

该文件用于把主观反馈和自动化评测连接起来。后续每次用户测试后，应把新增反馈归一化到同一结构，并把可自动化验证的改进项补充到 `dataset/tasks.jsonl`。

