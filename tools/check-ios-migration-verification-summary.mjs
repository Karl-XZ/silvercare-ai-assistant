import fs from 'node:fs';
import path from 'node:path';

const rootDir = process.cwd();
const summaryPath = process.argv[2] || path.join(rootDir, 'ios', 'build', 'migration-verification', 'summary.json');
const allowSigningBlocked = process.env.SILVERCARE_IOS_ALLOW_SIGNING_BLOCKED === '1';

function fail(message) {
  console.error(message);
  process.exit(1);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    fail(`Could not read JSON ${file}: ${error.message}`);
  }
}

function existsRelative(relativePath) {
  return typeof relativePath === 'string'
    && relativePath.length > 0
    && fs.existsSync(path.resolve(rootDir, relativePath));
}

assert(fs.existsSync(summaryPath), `Missing migration verification summary: ${summaryPath}`);
const summary = readJson(summaryPath);

assert(typeof summary.generated_at === 'string' && !Number.isNaN(Date.parse(summary.generated_at)), 'summary.generated_at must be an ISO date');
assert(typeof summary.elapsed_ms === 'number' && summary.elapsed_ms >= 0, 'summary.elapsed_ms must be >= 0');
assert(['passed', 'blocked_by_signing', 'failed'].includes(summary.status), `Unexpected summary.status: ${summary.status}`);
assert(Array.isArray(summary.results), 'summary.results must be an array');

const byName = new Map();
for (const result of summary.results) {
  assert(result && typeof result === 'object', 'each result must be an object');
  assert(typeof result.name === 'string' && result.name.length > 0, 'result.name is required');
  assert(!byName.has(result.name), `duplicate result.name: ${result.name}`);
  byName.set(result.name, result);
  assert(Array.isArray(result.command) && result.command.length > 0, `${result.name}.command must be a non-empty array`);
  assert(['passed', 'failed', 'blocked_by_signing'].includes(result.status), `${result.name}.status is invalid`);
  assert(typeof result.elapsed_ms === 'number' && result.elapsed_ms >= 0, `${result.name}.elapsed_ms must be >= 0`);
  assert(existsRelative(result.log_path), `${result.name}.log_path is missing: ${result.log_path}`);
}

for (const required of ['check-js', 'test-js']) {
  assert(byName.get(required)?.status === 'passed', `${required} must pass`);
}

if (summary.options?.skip_dashscope !== true) {
  const dashscopeGate = summary.options?.live_dashscope === true
    ? 'test-dashscope-scenarios'
    : 'check-dashscope-scenarios';
  assert(byName.get(dashscopeGate)?.status === 'passed', `${dashscopeGate} must pass when DashScope is not skipped`);
}
if (summary.options?.skip_simulator !== true) {
  assert(byName.get('test-ios-simulator')?.status === 'passed', 'test-ios-simulator must pass when not skipped');
}
if (summary.options?.skip_device !== true) {
  const device = byName.get('test-ios-device');
  assert(device, 'test-ios-device result is required when device is not skipped');
  if (summary.status === 'blocked_by_signing') {
    assert(allowSigningBlocked || summary.options?.allow_signing_blocked === true, 'blocked_by_signing requires allow-signing-blocked mode');
    assert(device.status === 'blocked_by_signing', 'test-ios-device must report blocked_by_signing');
    assert(device.device_summary_status === 'blocked_by_signing', 'test-ios-device must include device summary status');
    assert(/signing|profile|provisioning|account/i.test(String(summary.reason || '')), `summary.reason is not a signing blocker: ${summary.reason || '<empty>'}`);
    assert(byName.get('check-ios-device-summary')?.status === 'passed', 'check-ios-device-summary must pass after signing blocker');
  } else {
    assert(device.status === 'passed', `test-ios-device must pass when summary.status=${summary.status}`);
  }
}

if (summary.status === 'failed') {
  fail(`Migration verification failed: ${summary.reason || 'unknown reason'}`);
}

console.log(`Checked iOS migration verification summary: ${path.relative(rootDir, summaryPath) || summaryPath}`);
