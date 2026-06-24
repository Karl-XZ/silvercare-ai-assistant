import childProcess from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const rootDir = process.cwd();
const androidManifestPath = path.join(rootDir, 'app/src/main/AndroidManifest.xml');
const iosInfoPlistPath = path.join(rootDir, 'ios/SilverCareiOS/Info.plist');

function readText(relativeOrAbsolutePath) {
  const filePath = path.isAbsolute(relativeOrAbsolutePath)
    ? relativeOrAbsolutePath
    : path.join(rootDir, relativeOrAbsolutePath);
  return fs.readFileSync(filePath, 'utf8');
}

function readPlist(filePath) {
  const output = childProcess.execFileSync('/usr/bin/plutil', ['-convert', 'json', '-o', '-', filePath], {
    cwd: rootDir,
    encoding: 'utf8',
    maxBuffer: 4 * 1024 * 1024
  });
  return JSON.parse(output);
}

function androidPermissions(manifest) {
  return [...manifest.matchAll(/<uses-permission\s+[^>]*android:name="([^"]+)"/g)]
    .map((match) => match[1])
    .sort();
}

function androidFeatures(manifest) {
  return [...manifest.matchAll(/<uses-feature\s+([^>]+?)\/>/gs)]
    .map((match) => ({
      name: match[1].match(/android:name="([^"]+)"/)?.[1] ?? '',
      required: match[1].match(/android:required="([^"]+)"/)?.[1] ?? 'true'
    }))
    .filter((feature) => feature.name)
    .sort((a, b) => a.name.localeCompare(b.name));
}

function assertNonEmptyString(object, key, failures) {
  if (typeof object[key] !== 'string' || object[key].trim().length < 12) {
    failures.push(`iOS Info.plist missing useful ${key}`);
  }
}

function assertIncludes(file, marker, label, failures) {
  const text = readText(file);
  if (!text.includes(marker)) {
    failures.push(`${label}: ${file} missing ${JSON.stringify(marker)}`);
  }
}

const manifest = readText(androidManifestPath);
const infoPlist = readPlist(iosInfoPlistPath);
const permissions = androidPermissions(manifest);
const features = androidFeatures(manifest);
const failures = [];

if (permissions.includes('android.permission.CAMERA')) {
  assertNonEmptyString(infoPlist, 'NSCameraUsageDescription', failures);
  assertIncludes(
    'ios/SilverCareiOS/Services/NativeCameraService.swift',
    'AVCaptureDevice.requestAccess(for: .video)',
    'Android CAMERA parity',
    failures
  );
  assertIncludes(
    'ios/SilverCareiOS/App/SilverCareAppModel.swift',
    'nativeCameraAuthorizationStatus',
    'Android CAMERA bridge diagnostics parity',
    failures
  );
}

if (permissions.includes('android.permission.RECORD_AUDIO')) {
  assertNonEmptyString(infoPlist, 'NSMicrophoneUsageDescription', failures);
  assertIncludes(
    'ios/SilverCareiOS/App/SilverCareAppModel.swift',
    'AVCaptureDevice.requestAccess(for: .audio)',
    'Android RECORD_AUDIO parity',
    failures
  );
  assertIncludes(
    'ios/SilverCareiOS/Services/DashScopeAudioRecorderService.swift',
    'AVAudioEngine',
    'Android RECORD_AUDIO recorder parity',
    failures
  );
}

if (permissions.includes('android.permission.MODIFY_AUDIO_SETTINGS')) {
  assertIncludes(
    'ios/SilverCareiOS/Services/SystemSpeechService.swift',
    'AVAudioSession.sharedInstance()',
    'Android MODIFY_AUDIO_SETTINGS parity',
    failures
  );
  assertIncludes(
    'ios/SilverCareiOS/Services/DashScopeAudioRecorderService.swift',
    'setCategory',
    'Android audio-session parity',
    failures
  );
}

if (permissions.includes('android.permission.INTERNET')) {
  if (!infoPlist.NSAppTransportSecurity || infoPlist.NSAppTransportSecurity.NSAllowsArbitraryLoads !== false) {
    failures.push('iOS Info.plist must keep NSAppTransportSecurity.NSAllowsArbitraryLoads=false for HTTPS API parity');
  }
}

if (features.some((feature) => feature.name === 'android.hardware.camera' && feature.required === 'false')) {
  assertIncludes(
    'ios/SilverCareiOS/Services/NativeCameraService.swift',
    'hardwareAvailable',
    'Android optional camera feature parity',
    failures
  );
  assertIncludes(
    'ios/SilverCareiOS/App/SilverCareAppModel.swift',
    'camera_hardware_available',
    'Android optional camera diagnostics parity',
    failures
  );
}

if (features.some((feature) => feature.name === 'android.hardware.microphone' && feature.required === 'false')) {
  assertIncludes(
    'ios/SilverCareiOS/App/SilverCareAppModel.swift',
    'ensureMicrophonePermission',
    'Android optional microphone feature parity',
    failures
  );
}

if (manifest.includes('android.intent.action.TTS_SERVICE')) {
  assertIncludes(
    'ios/SilverCareiOS/Services/SystemSpeechService.swift',
    'AVSpeechSynthesizer',
    'Android TTS service query parity',
    failures
  );
  assertIncludes(
    'ios/Sources/SilverCareCore/SilverCareTypes.swift',
    'SilverCareTTSRuntimeMode',
    'Android TTS mode parity',
    failures
  );
}

assertNonEmptyString(infoPlist, 'NSMotionUsageDescription', failures);
assertIncludes(
  'ios/SilverCareiOS/Services/MotionFallMonitorService.swift',
  'CMMotionManager',
  'iOS fall-detection motion privacy',
  failures
);

if (failures.length > 0) {
  console.error('iOS permission/privacy parity check failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log(
  `Checked iOS permission/privacy parity for ${permissions.length} Android permission(s) and ${features.length} hardware feature declaration(s).`
);
