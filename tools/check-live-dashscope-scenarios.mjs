import { stat, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const defaultReportPath = path.join(repoRoot, 'test_runs', 'live_dashscope_scenarios', 'summary.json');
const reportPath = path.resolve(process.argv[2] || defaultReportPath);

const expectedScenarios = new Map([
  ['crosswalk_town_street', {
    title: '街道斑马线',
    hints: ['斑马线', '道路', '车辆', '过街', '人行横道']
  }],
  ['new_york_street', {
    title: '城市街道',
    hints: ['街道', '道路', '车辆', '行人', '交通', '人行横道']
  }],
  ['brick_sidewalk', {
    title: '人行道',
    hints: ['人行道', '路面', '障碍', '通行', '砖']
  }]
]);

const allowedPriorities = new Set(['low', 'medium', 'high']);
const allowedDirections = new Set(['left', 'right', 'ahead', 'behind', 'unknown']);
const secretPrefix = ['sk', 'ws'].join('-');

function fail(message) {
  throw new Error(message);
}

function assertObject(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    fail(`${label} must be an object`);
  }
  return value;
}

function assertString(value, label, minLength = 1) {
  if (typeof value !== 'string' || value.trim().length < minLength) {
    fail(`${label} must be a non-empty string`);
  }
  return value;
}

function assertNumber(value, label, min = 0) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min) {
    fail(`${label} must be a number >= ${min}`);
  }
  return value;
}

function assertStatus(smoke, label, allowed = new Set(['passed'])) {
  assertObject(smoke, label);
  if (!allowed.has(smoke.status)) {
    fail(`${label}.status must be ${[...allowed].join(' or ')}, got ${smoke.status || 'missing'}`);
  }
}

function containsAnyHint(result, hints) {
  const searchable = [
    result.subject,
    result.speech,
    result.scene_description,
    ...(Array.isArray(result.objects) ? result.objects : [])
  ].join(' ');
  return hints.some((hint) => searchable.includes(hint));
}

async function assertImage(image, scenarioId) {
  assertObject(image, `${scenarioId}.image`);
  const relativePath = assertString(image.path, `${scenarioId}.image.path`);
  assertString(image.source_url, `${scenarioId}.image.source_url`);
  assertString(image.source_page, `${scenarioId}.image.source_page`);
  if (!image.source_url.startsWith('https://')) {
    fail(`${scenarioId}.image.source_url must be https`);
  }
  if (!image.source_page.startsWith('https://')) {
    fail(`${scenarioId}.image.source_page must be https`);
  }
  if (typeof image.content_type !== 'string' || !image.content_type.startsWith('image/')) {
    fail(`${scenarioId}.image.content_type must be image/*`);
  }
  const expectedBytes = assertNumber(image.bytes, `${scenarioId}.image.bytes`, 1024);
  const fullPath = path.resolve(repoRoot, relativePath);
  if (!fullPath.startsWith(`${repoRoot}${path.sep}`)) {
    fail(`${scenarioId}.image.path escapes the repository`);
  }
  const imageStat = await stat(fullPath);
  if (!imageStat.isFile()) {
    fail(`${scenarioId}.image.path is not a file`);
  }
  if (imageStat.size !== expectedBytes) {
    fail(`${scenarioId}.image.bytes does not match local file size`);
  }
}

async function assertAudio(audio, label) {
  assertObject(audio, `${label}.audio`);
  const relativePath = assertString(audio.path, `${label}.audio.path`);
  const contentType = assertString(audio.content_type, `${label}.audio.content_type`);
  if (!contentType.startsWith('audio/') && contentType !== 'application/octet-stream') {
    fail(`${label}.audio.content_type must be audio/* or application/octet-stream`);
  }
  assertString(audio.source_host, `${label}.audio.source_host`);
  const expectedBytes = assertNumber(audio.bytes, `${label}.audio.bytes`, 1024);
  const fullPath = path.resolve(repoRoot, relativePath);
  if (!fullPath.startsWith(`${repoRoot}${path.sep}`)) {
    fail(`${label}.audio.path escapes the repository`);
  }
  const audioStat = await stat(fullPath);
  if (!audioStat.isFile()) {
    fail(`${label}.audio.path is not a file`);
  }
  if (audioStat.size !== expectedBytes) {
    fail(`${label}.audio.bytes does not match local file size`);
  }
}

async function main() {
  const text = await readFile(reportPath, 'utf8');
  const report = JSON.parse(text);
  assertObject(report, 'report');

  if (text.includes(secretPrefix)) {
    fail('report appears to contain an unredacted DashScope key');
  }
  if (report.api_key !== '[REDACTED_DASHSCOPE_API_KEY]') {
    fail('report.api_key must be redacted');
  }
  if (report.status !== 'passed') {
    fail(`report.status must be passed, got ${report.status || 'missing'}`);
  }
  assertString(report.generated_at, 'report.generated_at');
  if (Number.isNaN(Date.parse(report.generated_at))) {
    fail('report.generated_at must be an ISO date');
  }
  assertNumber(report.elapsed_ms, 'report.elapsed_ms', 1);

  const models = assertObject(report.models, 'report.models');
  assertString(models.vision, 'report.models.vision');
  assertString(models.text, 'report.models.text');
  assertString(models.asr, 'report.models.asr');
  assertString(models.tts, 'report.models.tts');

  const endpoints = assertObject(report.endpoints, 'report.endpoints');
  assertString(endpoints.compatible, 'report.endpoints.compatible');
  assertString(endpoints.api, 'report.endpoints.api');

  assertStatus(report.text_smoke, 'report.text_smoke');
  assertString(report.text_smoke.speech, 'report.text_smoke.speech', 2);
  assertNumber(report.text_smoke.elapsed_ms, 'report.text_smoke.elapsed_ms', 1);

  assertStatus(report.asr_smoke, 'report.asr_smoke', new Set(['passed', 'skipped']));
  if (report.asr_smoke.status === 'passed') {
    assertString(report.asr_smoke.model, 'report.asr_smoke.model');
    assertString(report.asr_smoke.audio, 'report.asr_smoke.audio');
    assertString(report.asr_smoke.transcript, 'report.asr_smoke.transcript', 1);
    assertNumber(report.asr_smoke.elapsed_ms, 'report.asr_smoke.elapsed_ms', 1);
  }

  assertStatus(report.tts_smoke, 'report.tts_smoke', new Set(['passed', 'skipped']));
  if (report.tts_smoke.status === 'passed') {
    if (report.tts_smoke.has_audio_url !== true) {
      fail('report.tts_smoke.has_audio_url must be true when TTS passed');
    }
    assertNumber(report.tts_smoke.elapsed_ms, 'report.tts_smoke.elapsed_ms', 1);
    await assertAudio(report.tts_smoke.audio, 'report.tts_smoke');
  }

  if (!Array.isArray(report.scenarios) || report.scenarios.length !== expectedScenarios.size) {
    fail(`report.scenarios must contain ${expectedScenarios.size} scenario(s)`);
  }

  const seen = new Set();
  for (const scenario of report.scenarios) {
    assertObject(scenario, 'scenario');
    const id = assertString(scenario.id, 'scenario.id');
    const expected = expectedScenarios.get(id);
    if (!expected) {
      fail(`unexpected scenario id: ${id}`);
    }
    if (seen.has(id)) {
      fail(`duplicate scenario id: ${id}`);
    }
    seen.add(id);
    if (scenario.title !== expected.title) {
      fail(`${id}.title must be ${expected.title}`);
    }
    if (scenario.status !== 'passed') {
      fail(`${id}.status must be passed`);
    }
    assertNumber(scenario.elapsed_ms, `${id}.elapsed_ms`, 1);
    if (!Array.isArray(scenario.validation_errors) || scenario.validation_errors.length !== 0) {
      fail(`${id}.validation_errors must be empty`);
    }
    await assertImage(scenario.image, id);

    const result = assertObject(scenario.result, `${id}.result`);
    if (!allowedPriorities.has(result.priority)) {
      fail(`${id}.result.priority is invalid`);
    }
    if (!allowedDirections.has(result.direction)) {
      fail(`${id}.result.direction is invalid`);
    }
    if (result.category !== 'navigation') {
      fail(`${id}.result.category must be navigation`);
    }
    assertString(result.subject, `${id}.result.subject`, 1);
    assertNumber(result.distance, `${id}.result.distance`, 0);
    assertString(result.speech, `${id}.result.speech`, 2);
    assertString(result.scene_description, `${id}.result.scene_description`, 4);
    if (!Array.isArray(result.objects) || result.objects.length < 1 || result.objects.length > 5) {
      fail(`${id}.result.objects must contain 1-5 item(s)`);
    }
    for (const [index, object] of result.objects.entries()) {
      assertString(object, `${id}.result.objects[${index}]`, 1);
    }
    if (!containsAnyHint(result, expected.hints)) {
      fail(`${id}.result does not mention any expected navigation/street hint`);
    }
  }

  for (const id of expectedScenarios.keys()) {
    if (!seen.has(id)) {
      fail(`missing scenario id: ${id}`);
    }
  }

  console.log(`Checked live DashScope scenario report: ${path.relative(repoRoot, reportPath)}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
