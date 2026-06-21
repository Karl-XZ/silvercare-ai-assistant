# 视频样例说明

`scene_luggage_obstacle_transition.mp4` 是由脱敏后的真实场景照片派生的短视频，用于测试视频输入、前后画面变化判断、路线重新规划和语音提示输出。

它不用于评估真人摔倒姿态识别。跌倒确认能力在本版本中通过 `dataset/trace_samples.jsonl` 里的传感器摘要、画面变化摘要和确认流程进行评测。

如果要加入新的真实视频，请按以下规则处理：

1. 不包含人脸、门牌、可识别住址、个人身份文本。
2. 保留原始采样时间间隔或在元数据中说明重采样方式。
3. 在 `dataset/annotations.jsonl` 添加媒体级标注。
4. 在 `dataset/tasks.jsonl` 添加对应任务。
5. 在 `dataset/trace_samples.jsonl` 添加流程 trace，便于复核系统判断过程。

