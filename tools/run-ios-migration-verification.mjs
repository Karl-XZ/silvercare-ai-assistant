import childProcess from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const rootDir = process.cwd();
const buildDir = path.join(rootDir, 'ios', 'build', 'migration-verification');
const summaryPath = path.join(buildDir, 'summary.json');

const skipSimulator = process.env.SILVERCARE_IOS_VERIFY_SKIP_SIMULATOR === '1';
const skipDevice = process.env.SILVERCARE_IOS_VERIFY_SKIP_DEVICE === '1';
const skipDashscope = process.env.SILVERCARE_IOS_VERIFY_SKIP_DASHSCOPE === '1';
const allowSigningBlocked = process.env.SILVERCARE_IOS_ALLOW_SIGNING_BLOCKED === '1';
const hasDashScopeKey = Boolean((process.env.DASHSCOPE_API_KEY || '').trim());

const startedAt = new Date();
const results = [];

function ensureBuildDir() {
  fs.mkdirSync(buildDir, { recursive: true });
}

function logName(name) {
  return `${name.replace(/[^A-Za-z0-9_.-]+/g, '-')}.log`;
}

function writeSummary(status, reason = '') {
  const payload = {
    generated_at: new Date().toISOString(),
    elapsed_ms: Date.now() - startedAt.getTime(),
    status,
    reason,
    options: {
    skip_simulator: skipSimulator,
    skip_device: skipDevice,
    skip_dashscope: skipDashscope,
    allow_signing_blocked: allowSigningBlocked,
    live_dashscope: hasDashScopeKey
    },
    results
  };
  fs.writeFileSync(summaryPath, `${JSON.stringify(payload, null, 2)}\n`);
}

function runGate(name, command, args, options = {}) {
  const started = Date.now();
  const logPath = path.join(buildDir, logName(name));
  console.log(`\n==> ${name}`);
  console.log([command, ...args].join(' '));
  const result = childProcess.spawnSync(command, args, {
    cwd: rootDir,
    encoding: 'utf8',
    maxBuffer: 128 * 1024 * 1024,
    env: { ...process.env, ...(options.env || {}) }
  });
  const output = `${result.stdout || ''}${result.stderr || ''}`;
  fs.writeFileSync(logPath, output);
  if (output.trim()) {
    process.stdout.write(output);
    if (!output.endsWith('\n')) process.stdout.write('\n');
  }
  const gate = {
    name,
    command: [command, ...args],
    status: result.status === 0 ? 'passed' : 'failed',
    exit_code: result.status,
    signal: result.signal || '',
    elapsed_ms: Date.now() - started,
    log_path: path.relative(rootDir, logPath)
  };
  results.push(gate);
  if (result.error) {
    gate.status = 'failed';
    gate.error = result.error.message;
  }
  return gate;
}

function readDeviceSummary() {
  const deviceSummaryPath = path.join(rootDir, 'ios', 'build', 'device-smoke', 'summary.json');
  try {
    return JSON.parse(fs.readFileSync(deviceSummaryPath, 'utf8'));
  } catch {
    return null;
  }
}

ensureBuildDir();

let finalStatus = 'passed';
let finalReason = '';

const gates = [
  ['check-js', 'npm', ['run', 'check:js']],
  ['test-js', 'npm', ['run', 'test:js']]
];

if (!skipDashscope) {
  gates.push(hasDashScopeKey
    ? ['test-dashscope-scenarios', 'npm', ['run', 'test:dashscope:scenarios']]
    : ['check-dashscope-scenarios', 'npm', ['run', 'check:dashscope:scenarios']]
  );
}
if (!skipSimulator) {
  gates.push(['test-ios-simulator', 'npm', ['run', 'test:ios:sim']]);
}
if (!skipDevice) {
  gates.push(['test-ios-device', 'npm', ['run', 'test:ios:device']]);
  gates.push(['check-ios-device-summary', 'npm', ['run', 'check:ios:device-summary']]);
}

for (const [name, command, args] of gates) {
  const gate = runGate(name, command, args);
  if (gate.status === 'passed') continue;

  if (name === 'test-ios-device') {
    const deviceSummary = readDeviceSummary();
    if (allowSigningBlocked && deviceSummary?.status === 'blocked_by_signing') {
      gate.status = 'blocked_by_signing';
      gate.device_summary_status = deviceSummary.status;
      gate.device_summary_reason = deviceSummary.reason || '';
      finalStatus = 'blocked_by_signing';
      finalReason = deviceSummary.reason || 'device signing blocked';
      continue;
    }
  }

  finalStatus = 'failed';
  finalReason = `${name} failed`;
  writeSummary(finalStatus, finalReason);
  process.exit(1);
}

writeSummary(finalStatus, finalReason);
console.log(`\nMigration verification summary: ${path.relative(rootDir, summaryPath)}`);
if (finalStatus === 'blocked_by_signing') {
  console.log('Migration verification reached the device signing blocker after passing earlier gates.');
  process.exitCode = allowSigningBlocked ? 0 : 2;
}
