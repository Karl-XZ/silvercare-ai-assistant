import fs from 'node:fs';
import path from 'node:path';

const rootDir = process.cwd();
const paths = {
  migration: process.env.SILVERCARE_IOS_MIGRATION_SUMMARY
    || path.join(rootDir, 'ios', 'build', 'migration-verification', 'summary.json'),
  liveDashscope: process.env.SILVERCARE_LIVE_DASHSCOPE_SUMMARY
    || path.join(rootDir, 'test_runs', 'live_dashscope_scenarios', 'summary.json'),
  simulatorStatus: process.env.SILVERCARE_IOS_SIMULATOR_STATUS_REPORT
    || path.join(rootDir, 'ios', 'build', 'simulator-automation', 'local-benchmark-reports', 'latest-status.json'),
  simulatorScreenshot: process.env.SILVERCARE_IOS_SIMULATOR_SCREENSHOT
    || path.join(rootDir, 'ios', 'build', 'simulator-automation', 'silvercare-home.png'),
  deviceSmoke: process.env.SILVERCARE_IOS_DEVICE_SMOKE_SUMMARY
    || path.join(rootDir, 'ios', 'build', 'device-smoke', 'summary.json')
};

const secretPrefix = `${['s', 'k'].join('')}-${['w', 's'].join('')}`;

function fail(message) {
  console.error(message);
  process.exit(1);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function readJson(file, label) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    fail(`Unable to read ${label} JSON at ${file}: ${error.message}`);
  }
}

function existsMaybeRelative(value) {
  if (!value || typeof value !== 'string') return false;
  const fullPath = path.isAbsolute(value) ? value : path.join(rootDir, value);
  return fs.existsSync(fullPath);
}

function requireFile(value, label, minBytes = 1) {
  assert(typeof value === 'string' && value.length > 0, `${label} path is required`);
  const fullPath = path.resolve(rootDir, value);
  assert(fullPath.startsWith(`${rootDir}${path.sep}`), `${label} must stay inside the repository: ${value}`);
  const stat = fs.existsSync(fullPath) ? fs.statSync(fullPath) : null;
  assert(stat?.isFile(), `${label} does not exist: ${value}`);
  assert(stat.size >= minBytes, `${label} is too small: ${value}`);
  return stat;
}

function assertGate(summary, name) {
  const result = summary.results?.find((entry) => entry?.name === name);
  assert(result, `migration summary is missing gate: ${name}`);
  assert(result.status === 'passed', `${name} must pass, got ${result.status || 'missing'}`);
  assert(existsMaybeRelative(result.log_path), `${name} log is missing: ${result.log_path || '<missing>'}`);
}

function checkMigrationSummary() {
  const summary = readJson(paths.migration, 'migration summary');
  assert(summary.status === 'passed', `migration summary must be passed, got ${summary.status || 'missing'}`);
  assert(summary.options?.live_dashscope === true, 'migration summary must prove a live DashScope run, not only cached report validation');
  for (const gate of [
    'check-js',
    'test-js',
    'test-dashscope-scenarios',
    'test-ios-simulator',
    'test-ios-device',
    'check-ios-device-summary'
  ]) {
    assertGate(summary, gate);
  }
  return summary;
}

function checkLiveDashScope() {
  const raw = fs.readFileSync(paths.liveDashscope, 'utf8');
  assert(!raw.includes(secretPrefix), 'live DashScope summary contains an unredacted key prefix');
  const report = JSON.parse(raw);
  assert(report.status === 'passed', `live DashScope report must pass, got ${report.status || 'missing'}`);
  assert(report.api_key === '[REDACTED_DASHSCOPE_API_KEY]', 'live DashScope report api_key must be redacted');
  assert(report.text_smoke?.status === 'passed', 'live DashScope text smoke must pass');
  assert(report.asr_smoke?.status === 'passed', 'live DashScope ASR smoke must pass');
  assert(typeof report.asr_smoke?.transcript === 'string' && report.asr_smoke.transcript.includes('找门'), 'live DashScope ASR transcript must prove the benchmark audio was understood');
  assert(report.tts_smoke?.status === 'passed', 'live DashScope TTS smoke must pass');
  assert(report.tts_smoke?.has_audio_url === true, 'live DashScope TTS must return an audio URL');
  requireFile(report.tts_smoke.audio?.path, 'live DashScope TTS audio', 1024);

  assert(Array.isArray(report.scenarios) && report.scenarios.length >= 3, 'live DashScope report must include at least 3 street/navigation scenarios');
  for (const scenario of report.scenarios) {
    assert(scenario.status === 'passed', `${scenario.id || '<scenario>'} must pass`);
    assert(scenario.image?.source_url?.startsWith('https://'), `${scenario.id} image must come from an HTTPS network source`);
    requireFile(scenario.image?.path, `${scenario.id} image`, 1024);
    assert(scenario.result?.category === 'navigation', `${scenario.id} result.category must be navigation`);
    assert(typeof scenario.result?.speech === 'string' && scenario.result.speech.length >= 2, `${scenario.id} speech is required`);
    assert(Array.isArray(scenario.result?.objects) && scenario.result.objects.length > 0, `${scenario.id} objects are required`);
  }
  return report;
}

function checkDeviceSmoke() {
  const summary = readJson(paths.deviceSmoke, 'device smoke summary');
  assert(summary.status === 'passed', `device smoke summary must be passed, got ${summary.status || 'missing'}`);
  assert(summary.signed_build_status === 'passed', 'device smoke signed build must pass');
  assert(summary.unsigned_runtime_preflight === 'passed', 'device smoke unsigned runtime preflight must pass');
  assert(existsMaybeRelative(summary.benchmark_report_dir), `device benchmark directory is missing: ${summary.benchmark_report_dir}`);

  const statusPath = path.join(summary.benchmark_report_dir, 'latest-status.json');
  const status = readJson(statusPath, 'device latest-status benchmark');
  assert(status.success === true, 'device latest-status benchmark must succeed');
  assert(status.native_speech?.asr_runtime_mode === 'dashscope', `device ASR runtime must be dashscope, got ${status.native_speech?.asr_runtime_mode || 'missing'}`);
  assert(status.native_speech?.local_asr_status_text?.includes('已配置'), 'device ASR status must show the DashScope key is configured');
  assert(status.native_tts?.tts_runtime_mode === 'dashscope', `device TTS runtime must be dashscope, got ${status.native_tts?.tts_runtime_mode || 'missing'}`);
  assert(status.native_tts?.dashscope_available === true, 'device TTS must report DashScope available');
  assert(status.native_tts?.tts_status_text?.includes('已配置'), 'device TTS status must show the DashScope key is configured');
  assert(status.native_camera?.available === true, 'device native camera must be available in status benchmark');
  assert(status.native_camera?.hardware_available === true, 'device native camera hardware must be available');
  return { summary, statusPath };
}

function checkOnlineRuntimeStatus(status, label, options = {}) {
  assert(status.success === true, `${label} latest-status benchmark must succeed`);
  if (typeof status.ai_runtime_mode === 'string') {
    assert(status.ai_runtime_mode === 'dashscope', `${label} AI runtime must be dashscope, got ${status.ai_runtime_mode || 'missing'}`);
  }
  if (typeof status.runtime_label === 'string') {
    assert(status.runtime_label.includes('DashScope'), `${label} runtime label must show DashScope, got ${status.runtime_label}`);
  }
  assert(status.native_speech?.asr_runtime_mode === 'dashscope', `${label} ASR runtime must be dashscope, got ${status.native_speech?.asr_runtime_mode || 'missing'}`);
  assert(status.native_speech?.local_asr_status_text?.includes('已配置'), `${label} ASR status must show the DashScope key is configured`);
  assert(status.native_tts?.tts_runtime_mode === 'dashscope', `${label} TTS runtime must be dashscope, got ${status.native_tts?.tts_runtime_mode || 'missing'}`);
  assert(status.native_tts?.dashscope_available === true, `${label} TTS must report DashScope available`);
  assert(status.native_tts?.tts_status_text?.includes('已配置'), `${label} TTS status must show the DashScope key is configured`);
  if (options.requireCameraHardware) {
    assert(status.native_camera?.available === true, `${label} native camera must be available`);
    assert(status.native_camera?.hardware_available === true, `${label} native camera hardware must be available`);
  } else {
    assert(status.native_camera && typeof status.native_camera === 'object', `${label} native camera diagnostics are required`);
  }
}

function checkSimulatorSmoke() {
  const status = readJson(paths.simulatorStatus, 'simulator latest-status benchmark');
  checkOnlineRuntimeStatus(status, 'simulator');
  requireFile(path.relative(rootDir, paths.simulatorScreenshot), 'simulator screenshot', 1024);
  return { statusPath: paths.simulatorStatus, screenshotPath: paths.simulatorScreenshot };
}

const migration = checkMigrationSummary();
const live = checkLiveDashScope();
const simulator = checkSimulatorSmoke();
const device = checkDeviceSmoke();

console.log('Checked iOS online chain evidence:');
console.log(`- migration summary: ${path.relative(rootDir, paths.migration)} (${migration.results.length} gates)`);
console.log(`- live DashScope scenarios: ${path.relative(rootDir, paths.liveDashscope)} (${live.scenarios.length} network image scenarios)`);
console.log(`- simulator DashScope runtime: ${path.relative(rootDir, simulator.statusPath)}`);
console.log(`- simulator screenshot: ${path.relative(rootDir, simulator.screenshotPath)}`);
console.log(`- device DashScope runtime: ${path.relative(rootDir, device.statusPath)}`);
