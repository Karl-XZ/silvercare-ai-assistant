# 数据集说明

本目录包含脱敏媒体、任务标注和流程 trace。

媒体文件使用相对路径引用，方便在不同电脑和 CI 环境中运行。

## 文件

- `annotations.jsonl`：媒体级标注。
- `tasks.jsonl`：任务级测试用例。
- `trace_samples.jsonl`：流程级脱敏 trace。
- `user_feedback.jsonl`：两周用户测试的脱敏反馈。
- `images/`：真实场景图片样例。
- `videos/`：视频输入样例。
- `audio/`：语音输入样例。
- `baselines/`：baseline 输出。
