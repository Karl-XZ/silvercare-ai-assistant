import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');

function readJsonl(file) {
  if (!fs.existsSync(file)) {
    throw new Error(`Missing file: ${file}`);
  }
  const text = fs.readFileSync(file, 'utf8').trim();
  if (!text) return [];
  return text.split(/\r?\n/).map((line, index) => {
    try {
      return JSON.parse(line);
    } catch (error) {
      throw new Error(`${file}:${index + 1} JSON parse failed: ${error.message}`);
    }
  });
}

function writeJsonl(file, rows) {
  fs.writeFileSync(file, `${rows.map((row) => JSON.stringify(row)).join('\n')}\n`, 'utf8');
}

function collectText(value) {
  const parts = [];
  const visit = (item) => {
    if (typeof item === 'string') {
      parts.push(item);
      return;
    }
    if (Array.isArray(item)) {
      item.forEach(visit);
      return;
    }
    if (item && typeof item === 'object') {
      Object.values(item).forEach(visit);
    }
  };
  visit(value);
  return parts.join('\n');
}

function round(value) {
  return Math.round(value * 1000) / 1000;
}

function evaluateTask(task, outputRow) {
  const expected = task.expected || {};
  const output = outputRow?.output || {};
  const failures = [];
  const text = collectText(output);

  if (!outputRow) failures.push('missing_output');
  if (expected.category && output.category !== expected.category) {
    failures.push(`category_expected_${expected.category}_got_${output.category ?? 'missing'}`);
  }
  if (expected.priority && output.priority !== expected.priority) {
    failures.push(`priority_expected_${expected.priority}_got_${output.priority ?? 'missing'}`);
  }
  for (const keyword of expected.required_keywords || []) {
    if (!text.includes(keyword)) failures.push(`missing_keyword_${keyword}`);
  }
  for (const keyword of expected.forbidden_keywords || []) {
    if (text.includes(keyword)) failures.push(`forbidden_keyword_${keyword}`);
  }
  if (Object.hasOwn(expected, 'target_detected') && output.target_detected !== expected.target_detected) {
    failures.push(`target_detected_expected_${expected.target_detected}`);
  }
  if (expected.expected_transcript) {
    const transcript = String(output.transcript || '');
    if (transcript !== expected.expected_transcript && !transcript.includes(expected.expected_transcript)) {
      failures.push(`transcript_expected_${expected.expected_transcript}_got_${transcript || 'missing'}`);
    }
  }
  if (expected.alarm_status && output.alarm_status !== expected.alarm_status) {
    failures.push(`alarm_status_expected_${expected.alarm_status}_got_${output.alarm_status ?? 'missing'}`);
  }
  if (Object.hasOwn(expected, 'manual_correction_applied') && output.manual_correction_applied !== expected.manual_correction_applied) {
    failures.push(`manual_correction_expected_${expected.manual_correction_applied}`);
  }
  if (expected.screen_free && !(output.screen_required === false && output.voice_first_ready === true)) {
    failures.push('screen_free_not_satisfied');
  }
  if (expected.caregiver_reviewable && output.care_event?.reviewable !== true) {
    failures.push('caregiver_event_not_reviewable');
  }

  return {
    task_id: task.task_id,
    task_type: task.task_type,
    passed: failures.length === 0,
    failures,
    latency_ms: Number(outputRow?.latency_ms ?? output.latency_ms ?? 0),
    expected_category: expected.category,
    output_category: output.category
  };
}

const outputArg = process.argv[2] || path.join(root, 'dataset', 'baselines', 'rule_based_baseline.jsonl');
const outputFile = path.resolve(process.cwd(), outputArg);
const tasks = readJsonl(path.join(root, 'dataset', 'tasks.jsonl'));
const outputs = readJsonl(outputFile);
const outputByTask = new Map(outputs.map((row) => [row.task_id, row]));
const results = tasks.map((task) => evaluateTask(task, outputByTask.get(task.task_id)));

const passed = results.filter((row) => row.passed).length;
const total = results.length;
const byType = {};
for (const row of results) {
  byType[row.task_type] ||= { total: 0, passed: 0 };
  byType[row.task_type].total += 1;
  if (row.passed) byType[row.task_type].passed += 1;
}
for (const value of Object.values(byType)) {
  value.success_rate = round(value.passed / value.total);
}

const latencyValues = results.map((row) => row.latency_ms).filter((value) => Number.isFinite(value) && value > 0);
const avgLatency = latencyValues.reduce((sum, value) => sum + value, 0) / Math.max(latencyValues.length, 1);

const noAlarmTasks = tasks.filter((task) => ['no_alarm', 'cancelled'].includes(task.expected?.alarm_status));
let falseAlarmCount = 0;
for (const task of noAlarmTasks) {
  const alarmStatus = outputByTask.get(task.task_id)?.output?.alarm_status;
  if (alarmStatus === 'simulated_alarm') falseAlarmCount += 1;
}

const screenFreeRequired = tasks.filter((task) => task.expected?.screen_free);
const screenFreePassed = screenFreeRequired.filter((task) => {
  const out = outputByTask.get(task.task_id)?.output || {};
  return out.screen_required === false && out.voice_first_ready === true;
}).length;

const caregiverRequired = tasks.filter((task) => task.expected?.caregiver_reviewable);
const caregiverPassed = caregiverRequired.filter((task) => outputByTask.get(task.task_id)?.output?.care_event?.reviewable === true).length;

const asrTasks = tasks.filter((task) => task.task_type === 'asr');
const asrPassed = asrTasks.filter((task) => {
  const transcript = outputByTask.get(task.task_id)?.output?.transcript || '';
  return transcript === task.expected?.expected_transcript || transcript.includes(task.expected?.expected_transcript || '__missing__');
}).length;

const correctionTasks = tasks.filter((task) => Object.hasOwn(task.expected || {}, 'manual_correction_applied'));
const correctionPassed = correctionTasks.filter((task) => {
  return outputByTask.get(task.task_id)?.output?.manual_correction_applied === task.expected.manual_correction_applied;
}).length;

const metrics = {
  benchmark_version: '0.1.0',
  evaluated_output: path.relative(root, outputFile).replace(/\\/g, '/'),
  total_tasks: total,
  passed_tasks: passed,
  task_success_rate: round(passed / Math.max(total, 1)),
  avg_response_ms: round(avgLatency),
  false_alarm_rate: round(falseAlarmCount / Math.max(noAlarmTasks.length, 1)),
  screen_free_completion_rate: round(screenFreePassed / Math.max(screenFreeRequired.length, 1)),
  caregiver_reviewable_rate: round(caregiverPassed / Math.max(caregiverRequired.length, 1)),
  asr_transcript_pass_rate: round(asrPassed / Math.max(asrTasks.length, 1)),
  manual_correction_acceptance_rate: round(correctionPassed / Math.max(correctionTasks.length, 1)),
  by_task_type: byType
};

fs.mkdirSync(path.join(root, 'reports'), { recursive: true });
writeJsonl(path.join(root, 'reports', 'task_results.jsonl'), results);
fs.writeFileSync(path.join(root, 'reports', 'metrics_summary.json'), `${JSON.stringify(metrics, null, 2)}\n`, 'utf8');

console.log(JSON.stringify(metrics, null, 2));

