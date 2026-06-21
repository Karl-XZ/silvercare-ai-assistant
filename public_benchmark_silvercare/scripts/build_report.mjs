import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function readJsonl(file) {
  const text = fs.readFileSync(file, 'utf8').trim();
  if (!text) return [];
  return text.split(/\r?\n/).map((line) => JSON.parse(line));
}

const metrics = readJson(path.join(root, 'reports', 'metrics_summary.json'));
const results = readJsonl(path.join(root, 'reports', 'task_results.jsonl'));
const failures = results.filter((row) => !row.passed);

const typeRows = Object.entries(metrics.by_task_type)
  .map(([type, value]) => `| ${type} | ${value.passed}/${value.total} | ${value.success_rate} |`)
  .join('\n');

const report = `# 银龄智护公开评测报告

## 总览

| 指标 | 数值 |
| --- | ---: |
| 任务总数 | ${metrics.total_tasks} |
| 通过任务数 | ${metrics.passed_tasks} |
| 任务成功率 | ${metrics.task_success_rate} |
| 平均响应时间 | ${metrics.avg_response_ms} ms |
| 误报率 | ${metrics.false_alarm_rate} |
| 免看屏完成率 | ${metrics.screen_free_completion_rate} |
| 照护复核事件生成率 | ${metrics.caregiver_reviewable_rate} |
| ASR 转写通过率 | ${metrics.asr_transcript_pass_rate} |
| 人工修正接纳率 | ${metrics.manual_correction_acceptance_rate} |

## 分场景结果

| 场景 | 通过 | 成功率 |
| --- | ---: | ---: |
${typeRows}

## 评测覆盖

- 巡路：走廊、入口堆物、浴室高风险空间。
- 找物：桌面小物件定位，并提示脚边电线风险。
- 跌倒确认：传感器突变、视频变化、十秒确认、模拟报警和取消报警。
- 误报抑制：仅传感器变化但画面无摔倒变化时不报警。
- 语音交互：语音命令转写、生活照护需求记录。
- 人工修正：用户修正路线后，系统改写下一步引导。
- 照护复核：生成可复核事件摘要和关键字段。

## 结论

当前 baseline 用于验证协议和脚本可复现。正式系统应在同一任务集上提交自己的 JSONL 输出，并比较上述结构化指标。
`;

const failureReport = failures.length === 0
  ? '# 失败用例\n\n当前 baseline 未发现失败用例。\n'
  : `# 失败用例\n\n${failures.map((row) => `- ${row.task_id}: ${row.failures.join(', ')}`).join('\n')}\n`;

fs.writeFileSync(path.join(root, 'reports', 'benchmark_report.md'), report, 'utf8');
fs.writeFileSync(path.join(root, 'reports', 'failure_cases.md'), failureReport, 'utf8');
console.log('Wrote reports/benchmark_report.md and reports/failure_cases.md');

