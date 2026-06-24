import fs from 'node:fs';
import path from 'node:path';

const rootDir = process.cwd();
const summaryPath = process.argv[2] || path.join(rootDir, 'ios', 'build', 'device-smoke', 'summary.json');

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

function existsMaybeRelative(value) {
  if (!value || typeof value !== 'string') return false;
  return fs.existsSync(path.isAbsolute(value) ? value : path.join(rootDir, value));
}

assert(fs.existsSync(summaryPath), `Missing iOS device smoke summary: ${summaryPath}`);
const summary = readJson(summaryPath);

assert(typeof summary.generated_at === 'string' && summary.generated_at.length > 0, 'summary.generated_at is required');
assert(summary.bundle_id === 'com.silvercare.aiassistant.ios', `Unexpected bundle_id: ${summary.bundle_id}`);
assert(typeof summary.device_id === 'string' && summary.device_id.length > 0, 'summary.device_id is required');
assert(
  ['passed', 'blocked_by_signing', 'failed'].includes(summary.status),
  `Unexpected summary.status: ${summary.status}`
);
assert(
  ['passed', 'skipped'].includes(summary.unsigned_runtime_preflight),
  `Unsigned iPhoneOS runtime preflight did not complete: ${summary.unsigned_runtime_preflight}`
);

if (summary.unsigned_runtime_preflight === 'passed') {
  assert(
    existsMaybeRelative(summary.unsigned_iphoneos_app_path),
    `Unsigned iPhoneOS app path is missing: ${summary.unsigned_iphoneos_app_path}`
  );
}

if (summary.status === 'blocked_by_signing') {
  assert(
    summary.signed_build_status === 'failed',
    `Signing-blocked summary must have signed_build_status=failed, got ${summary.signed_build_status}`
  );
  assert(summary.signing_preflight_exists === true, 'Signing-blocked summary must keep signing preflight evidence');
  assert(
    existsMaybeRelative(summary.signing_preflight_path),
    `Signing preflight report is missing: ${summary.signing_preflight_path}`
  );
  assert(
    /signing|profile|provisioning|account/i.test(String(summary.reason || '')),
    `Signing-blocked summary reason is not specific enough: ${summary.reason || '<empty>'}`
  );
}

if (summary.status === 'passed') {
  assert(summary.signed_build_status === 'passed', 'Passed summary must have signed_build_status=passed');
  assert(existsMaybeRelative(summary.benchmark_report_dir), `Benchmark dir missing: ${summary.benchmark_report_dir}`);
  assert(existsMaybeRelative(summary.diagnostic_report_dir), `Diagnostic dir missing: ${summary.diagnostic_report_dir}`);
}

console.log(`Checked iOS device smoke summary: ${path.relative(rootDir, summaryPath) || summaryPath}`);
