# 银龄智护公开评测集 v0.1

本目录是一套面向适老化居家长护辅助系统的公开 benchmark 草案，覆盖巡路、找物、跌倒确认、语音交互、误报处理、人工修正和任务完成复核。

评测集目标不是证明某个模型“绝对正确”，而是让不同实现可以在同一批输入、同一套输出协议和同一套指标下复现比较。

## 内容

- `dataset/images/`：脱敏后的真实居家和公共通道场景图片。
- `dataset/videos/`：由脱敏真实场景图片派生的短视频样例，用于验证视频输入和前后画面变化判断管线。
- `dataset/audio/`：语音命令样例。
- `dataset/annotations.jsonl`：媒体级场景标注。
- `dataset/tasks.jsonl`：任务级输入、期望输出和评分点。
- `dataset/trace_samples.jsonl`：脱敏流程 trace，覆盖巡路、找物、跌倒确认、误报、人工修正和任务完成记录。
- `dataset/user_feedback.jsonl`：两周用户测试的脱敏结构化反馈。
- `protocol/`：任务协议、接口协议、评分规则和脱敏规则。
- `scripts/`：baseline、评测、报告和脱敏检查脚本。
- `reports/`：运行脚本后生成的结构化指标和报告。

## 快速复现

```powershell
cd public_benchmark_silvercare
npm run benchmark
```

不需要安装第三方 npm 包。脚本只使用 Node.js 标准库。

运行后会生成：

- `dataset/baselines/rule_based_baseline.jsonl`
- `reports/task_results.jsonl`
- `reports/metrics_summary.json`
- `reports/anonymization_check.json`
- `reports/benchmark_report.md`
- `reports/failure_cases.md`

## 接入自己的系统

参赛或社区复用方只需要让自己的系统读取 `dataset/tasks.jsonl`，并按 `protocol/interface_contract.md` 输出 JSONL。然后运行：

```powershell
node scripts/evaluate_outputs.mjs path/to/your_outputs.jsonl
node scripts/build_report.mjs
```

输出文件每行必须包含：

```json
{"task_id":"nav_corridor_001","output":{"speech":"请沿着走廊中线向前慢走...","screen_required":false,"voice_first_ready":true},"latency_ms":930}
```

## 当前边界

- 本版本样例量小，适合作为公开协议、复现脚本和 baseline 的起点。
- 跌倒确认以传感器摘要、视频变化摘要和流程 trace 评测为主，不包含真人摔倒视频。
- 视频样例是从脱敏真实场景图片派生，用于验证视频输入和场景变化判断，不作为人体姿态动作识别的唯一依据。
- 医疗和长护建议必须作为辅助提醒，不能替代医生、护士或照护人员的专业判断。
