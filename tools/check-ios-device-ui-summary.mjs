import fs from 'node:fs';
import path from 'node:path';

const summaryPath = process.env.SILVERCARE_IOS_DEVICE_UI_SUMMARY || 'ios/build/device-ui-debug/summary.json';
const allowBlocked = process.env.SILVERCARE_ALLOW_DEVICE_UI_BLOCKED === '1';

function fail(message) {
  console.error(message);
  process.exit(1);
}

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    fail(`Unable to read iOS device UI summary at ${file}: ${error.message}`);
  }
}

function assertFile(file, label) {
  if (!file || typeof file !== 'string') {
    fail(`Missing ${label} path in ${summaryPath}`);
  }
  if (!fs.existsSync(file)) {
    fail(`${label} does not exist: ${file}`);
  }
}

const summary = readJson(summaryPath);
if (!summary || typeof summary !== 'object') {
  fail(`Invalid summary payload in ${summaryPath}`);
}
if (!summary.generated_at || typeof summary.generated_at !== 'string') {
  fail(`Missing generated_at in ${summaryPath}`);
}
if (!summary.device_id || typeof summary.device_id !== 'string') {
  fail(`Missing device_id in ${summaryPath}`);
}

const status = summary.status;
if (status === 'passed') {
  assertFile(summary.result_bundle_path, 'result bundle');
  assertFile(summary.test_log_path, 'test log');
  const logText = fs.readFileSync(summary.test_log_path, 'utf8');
  const expectedEvidence = [
    'SilverCareiOSDeviceDebugUITests',
    'testOrdinaryDeviceLaunchScreenshotsAndSettingsTap',
    'testOrdinaryDeviceNativeControlsOpenPanels',
    'testOrdinaryDeviceStartNavigationEntersNativeCameraFlow',
    '** TEST SUCCEEDED **'
  ];
  for (const marker of expectedEvidence) {
    if (!logText.includes(marker)) {
      fail(`Device UI log is missing expected marker ${JSON.stringify(marker)}: ${summary.test_log_path}`);
    }
  }
  console.log(`Checked iOS device UI summary: ${summaryPath}`);
  process.exit(0);
}

if (allowBlocked && ['blocked_by_locked_device', 'blocked_by_device_automation', 'interrupted'].includes(status)) {
  assertFile(summary.test_log_path, 'test log');
  console.log(`Checked iOS device UI summary (${status}): ${summaryPath}`);
  process.exit(0);
}

fail(
  `iOS device UI summary is ${JSON.stringify(status)} at ${summaryPath}. ` +
    `Check ${summary.test_log_path || 'the device UI log'} and rerun npm run test:ios:device-ui.`
);
