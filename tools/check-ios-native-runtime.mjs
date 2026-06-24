import childProcess from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

const rootDir = process.cwd();
const iosDir = path.join(rootDir, 'ios');
const nativeDir = path.join(iosDir, 'Native');
const strict = process.env.SILVERCARE_REQUIRE_IOS_NATIVE_RUNTIME === '1';
const appPath = (process.env.SILVERCARE_IOS_APP_PATH || '').trim();
const requireAppBundleRuntime = process.env.SILVERCARE_REQUIRE_IOS_APP_BUNDLE_RUNTIME === '1';
const requiredAppBundlePlatform = (process.env.SILVERCARE_IOS_REQUIRE_APP_BUNDLE_PLATFORM || 'IOS').trim();

const mnnRequiredAll = [
  'silvercare_mnn_runtime_kind',
  'silvercare_mnn_text_json'
];
const mnnRequiredAny = [
  'silvercare_mnn_vision_json_from_chw',
  'silvercare_mnn_vision_json'
];
const voskRequiredAll = [
  'vosk_model_new',
  'vosk_model_free',
  'vosk_recognizer_new',
  'vosk_recognizer_free',
  'vosk_recognizer_set_words',
  'vosk_recognizer_accept_waveform',
  'vosk_recognizer_final_result'
];
const ttsRequiredAll = [
  'silvercare_mnn_tts_runtime_kind',
  'silvercare_mnn_tts_voice_quality_passed',
  'silvercare_mnn_tts_synthesize_wav'
];
const mnnCoreRequiredCxx = [
  'MNN::Interpreter::createFromFile(char const*)',
  'MNN::Interpreter::createSession(MNN::ScheduleConfig const&)',
  'MNN::Interpreter::runSession(MNN::Session*) const',
  'MNN::Interpreter::getSessionInput(MNN::Session const*, char const*)',
  'MNN::Interpreter::getSessionOutput(MNN::Session const*, char const*)',
  'MNN::Tensor::copyFromHostTensor(MNN::Tensor const*)',
  'MNN::Tensor::copyToHostTensor(MNN::Tensor*) const'
];

function readText(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), 'utf8');
}

function exists(filePath) {
  return fs.existsSync(filePath);
}

function isDirectory(filePath) {
  try {
    return fs.statSync(filePath).isDirectory();
  } catch {
    return false;
  }
}

function shell(command, args) {
  try {
    return childProcess.execFileSync(command, args, {
      cwd: rootDir,
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe']
    });
  } catch {
    return '';
  }
}

function collectFiles(target, files = []) {
  if (!exists(target)) return files;
  const stat = fs.statSync(target);
  if (stat.isDirectory()) {
    for (const entry of fs.readdirSync(target)) {
      if (entry === '.DS_Store') continue;
      collectFiles(path.join(target, entry), files);
    }
  } else {
    files.push(target);
  }
  return files;
}

function binaryFromFramework(frameworkPath) {
  const basename = path.basename(frameworkPath, '.framework');
  return path.join(frameworkPath, basename);
}

function collectXcframeworkBinaries(xcframeworkPath) {
  return collectFiles(xcframeworkPath).filter((file) => {
    const name = path.basename(file);
    return !name.includes('.') || name.endsWith('.a') || name.endsWith('.dylib');
  });
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function candidateFiles(candidates) {
  const files = [];
  for (const candidate of candidates) {
    if (!exists(candidate)) continue;
    if (candidate.endsWith('.framework')) {
      files.push(binaryFromFramework(candidate));
    } else if (candidate.endsWith('.xcframework')) {
      files.push(...collectXcframeworkBinaries(candidate));
    } else if (isDirectory(candidate)) {
      files.push(...collectFiles(candidate));
    } else {
      files.push(candidate);
    }
  }
  return unique(files).filter((file) => exists(file));
}

function nmSymbols(file) {
  const output = shell('/usr/bin/nm', ['-gU', file]);
  if (!output) return new Set();
  const symbols = new Set();
  for (const line of output.split(/\r?\n/)) {
    const match = line.match(/(?:^|\s)_?([A-Za-z][A-Za-z0-9_]+)$/);
    if (match) symbols.add(match[1]);
  }
  return symbols;
}

function demangledSymbols(file) {
  const output = shell('/usr/bin/nm', ['-gU', file]);
  if (!output) return '';
  try {
    return childProcess.execFileSync('/usr/bin/c++filt', {
      cwd: rootDir,
      input: output,
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
      stdio: ['pipe', 'pipe', 'ignore']
    });
  } catch {
    return output;
  }
}

function binaryDiagnostics(file) {
  const fileType = shell('/usr/bin/file', ['-b', file]).trim();
  const archOutput = shell('/usr/bin/lipo', ['-archs', file]).trim();
  const archs = archOutput ? archOutput.split(/\s+/).filter(Boolean) : [];
  const buildInfo = shell('/usr/bin/xcrun', ['vtool', '-show-build', file]).trim();
  return {
    fileType,
    archs,
    buildInfo
  };
}

function buildPlatforms(diagnostics) {
  const platforms = new Set();
  for (const match of diagnostics.buildInfo.matchAll(/platform\s+([A-Z0-9_]+)/g)) {
    platforms.add(match[1]);
  }
  return [...platforms];
}

function hasIOSDeviceArch(diagnostics) {
  if (diagnostics.archs.includes('arm64')) return true;
  return /\barm64\b/.test(diagnostics.fileType);
}

function looksLikeRuntimeArtifact(name, file) {
  const normalizedName = name.replace(/^app-bundle\s+/, '');
  const lowerPath = file.toLowerCase();
  if (normalizedName === 'MNN') {
    return lowerPath.includes('silvercaremnnruntime') || lowerPath.includes('silvercare_mnn_runtime');
  }
  if (normalizedName === 'MNN TTS') {
    return lowerPath.includes('silvercaremnnttsruntime')
      || lowerPath.includes('silvercare_mnn_tts_runtime')
      || lowerPath.includes('mnn_tts');
  }
  return lowerPath.includes('vosk');
}

function symbolReport(name, files, requiredAll, requiredAny = [], options = {}) {
  const inspected = [];
  const malformed = [];
  const relevantSymbols = [...requiredAll, ...requiredAny];
  const requiredPlatform = options.requiredPlatform || '';
  for (const file of files) {
    const diagnostics = binaryDiagnostics(file);
    const namedLikeRuntime = looksLikeRuntimeArtifact(name, file);
    const symbols = nmSymbols(file);
    const hasRelevantSymbol = relevantSymbols.some((symbol) => symbols.has(symbol));
    if (!namedLikeRuntime && !hasRelevantSymbol) continue;
    if (symbols.size === 0) {
      inspected.push({
        file,
        complete: false,
        missingAll: requiredAll,
        missingAny: requiredAny,
        diagnostics,
        reason: 'no exported symbols found'
      });
      continue;
    }
    const missingAll = requiredAll.filter((symbol) => !symbols.has(symbol));
    const hasAny = requiredAny.length === 0 || requiredAny.some((symbol) => symbols.has(symbol));
    const missingArch = hasIOSDeviceArch(diagnostics) ? [] : ['arm64 iOS device slice'];
    const platforms = buildPlatforms(diagnostics);
    const missingPlatform = requiredPlatform && !platforms.includes(requiredPlatform)
      ? [`${requiredPlatform} platform slice`]
      : [];
    inspected.push({
      file,
      complete: missingAll.length === 0 && hasAny && missingArch.length === 0 && missingPlatform.length === 0,
      missingAll,
      missingAny: hasAny ? [] : requiredAny,
      missingArch,
      missingPlatform,
      diagnostics
    });
  }

  for (const item of inspected) {
    if (!item.complete) malformed.push(item);
  }

  const complete = inspected.find((item) => item.complete);
  return {
    name,
    available: Boolean(complete),
    complete,
    inspected,
    malformed
  };
}

function appRuntimeCandidates() {
  if (!appPath || !exists(appPath)) return { mnn: [], vosk: [], tts: [] };
  const infoPlist = path.join(appPath, 'Info.plist');
  const executable = exists(infoPlist)
    ? shell('/usr/bin/plutil', ['-extract', 'CFBundleExecutable', 'raw', infoPlist]).trim()
    : '';
  const appExecutables = [
    executable ? path.join(appPath, executable) : '',
    path.join(appPath, 'SilverCareiOS.debug.dylib')
  ];
  const frameworks = path.join(appPath, 'Frameworks');
  return {
    mnn: [
      ...appExecutables,
      path.join(frameworks, 'SilverCareMNNRuntime.framework'),
      path.join(frameworks, 'libsilvercare_mnn_runtime.dylib')
    ],
    tts: [
      ...appExecutables,
      path.join(frameworks, 'SilverCareMNNTTSRuntime.framework'),
      path.join(frameworks, 'libsilvercare_mnn_tts_runtime.framework'),
      path.join(frameworks, 'libsilvercare_mnn_tts_runtime.dylib'),
      path.join(frameworks, 'libmnn_tts.framework'),
      path.join(frameworks, 'libmnn_tts.dylib'),
      path.join(appPath, 'libsilvercare_mnn_tts_runtime.dylib'),
      path.join(appPath, 'libmnn_tts.dylib')
    ],
    vosk: [
      path.join(frameworks, 'vosk.framework'),
      path.join(frameworks, 'libvosk.framework'),
      path.join(frameworks, 'libvosk.dylib'),
      path.join(appPath, 'libvosk.dylib')
    ]
  };
}

function assertSourceContracts() {
  const bridge = readText('ios/SilverCareiOS/Bridge/SilverCareBridgeScript.swift');
  const mnnRuntime = readText('ios/SilverCareiOS/Services/DynamicIOSMNNLocalModelRuntime.swift');
  const ttsRuntime = readText('ios/SilverCareiOS/Services/DynamicIOSMNNTTSRuntime.swift');
  const voskRuntime = readText('ios/SilverCareiOS/Services/LocalVoskASRRuntime.swift');
  const project = readText('ios/project.yml');
  const abi = readText('ios/Native/SilverCareMNNRuntimeABI.h');
  const ttsAbi = readText('ios/Native/SilverCareMNNTTSRuntimeABI.h');

  const failures = [];
  for (const symbol of [...mnnRequiredAll, ...mnnRequiredAny, 'silvercare_mnn_free_string']) {
    if (!abi.includes(symbol)) failures.push(`MNN ABI header missing ${symbol}`);
  }
  for (const symbol of [...ttsRequiredAll, 'silvercare_mnn_tts_free_string']) {
    if (!ttsAbi.includes(symbol)) failures.push(`MNN TTS ABI header missing ${symbol}`);
  }
  for (const symbol of mnnRequiredAll) {
    if (!mnnRuntime.includes(symbol)) failures.push(`DynamicIOSMNNLocalModelRuntime does not probe ${symbol}`);
  }
  for (const symbol of ttsRequiredAll) {
    if (!ttsRuntime.includes(symbol)) failures.push(`DynamicIOSMNNTTSRuntime does not probe ${symbol}`);
  }
  for (const token of [
    'SILVERCARE_MNN_LIBRARY',
    'SilverCareMNNRuntime.framework/SilverCareMNNRuntime',
    'libsilvercare_mnn_runtime.framework/libsilvercare_mnn_runtime',
    'libsilvercare_mnn_runtime.dylib'
  ]) {
    if (!mnnRuntime.includes(token)) failures.push(`DynamicIOSMNNLocalModelRuntime does not search ${token}`);
  }
  if (!mnnRequiredAny.some((symbol) => mnnRuntime.includes(symbol))) {
    failures.push('DynamicIOSMNNLocalModelRuntime does not probe a vision ABI symbol');
  }
  for (const token of [
    'SILVERCARE_MNN_TTS_LIBRARY',
    'SilverCareMNNTTSRuntime.framework/SilverCareMNNTTSRuntime',
    'libsilvercare_mnn_tts_runtime.framework/libsilvercare_mnn_tts_runtime',
    'libsilvercare_mnn_tts_runtime.dylib',
    'libmnn_tts.framework/libmnn_tts',
    'libmnn_tts.dylib'
  ]) {
    if (!ttsRuntime.includes(token)) failures.push(`DynamicIOSMNNTTSRuntime does not search ${token}`);
  }
  for (const symbol of voskRequiredAll) {
    if (!voskRuntime.includes(symbol)) failures.push(`LocalVoskASRRuntime does not probe ${symbol}`);
  }
  if (!voskRuntime.includes('dlopen(nil')) {
    failures.push('LocalVoskASRRuntime does not probe symbols linked into the main app image');
  }
  for (const method of [
    'offlineNativeRuntimeAvailable',
    'localAsrRuntimeAvailable',
    'localTtsRuntimeAvailable',
    'localTtsVoiceQualityPassed',
    'mnnRuntimeSummary',
    'runLocalBenchmark'
  ]) {
    if (!bridge.includes(method)) failures.push(`iOS bridge missing runtime method ${method}`);
  }
  if (!project.includes('app/src/main/assets')) {
    failures.push('iOS project is not bundling shared Android web assets');
  }
  return failures;
}

function printReport(report) {
  if (report.available) {
    console.log(`iOS ${report.name} runtime: available (${path.relative(rootDir, report.complete.file)})`);
    return;
  }
  if (report.inspected.length > 0) {
    console.log(`iOS ${report.name} runtime: candidate found but ABI incomplete`);
    for (const item of report.inspected) {
      if (item.complete) continue;
      const missing = [
        ...item.missingAll,
        ...item.missingAny,
        ...(item.missingArch || []),
        ...(item.missingPlatform || [])
      ].join(', ');
      const archs = item.diagnostics?.archs?.length ? item.diagnostics.archs.join(',') : 'unknown-arch';
      const platforms = buildPlatforms(item.diagnostics || { buildInfo: '' });
      const platformText = platforms.length ? `; platforms: ${platforms.join(',')}` : '';
      const reason = item.reason ? ` (${item.reason})` : '';
      console.log(`- ${path.relative(rootDir, item.file)} missing: ${missing || 'unknown'}; archs: ${archs}${platformText}${reason}`);
    }
    return;
  }
  console.log(`iOS ${report.name} runtime: not bundled yet`);
}

function mnnCoreReport(files) {
  const inspected = [];
  for (const file of files) {
    const diagnostics = binaryDiagnostics(file);
    const symbols = demangledSymbols(file);
    if (!symbols) continue;
    const missing = mnnCoreRequiredCxx.filter((symbol) => !symbols.includes(symbol));
    const missingArch = hasIOSDeviceArch(diagnostics) ? [] : ['arm64 iOS device slice'];
    inspected.push({
      file,
      complete: missing.length === 0 && missingArch.length === 0,
      missing,
      missingArch,
      diagnostics
    });
  }
  return {
    available: inspected.some((item) => item.complete),
    complete: inspected.find((item) => item.complete),
    inspected
  };
}

function printMnnCoreReport(report) {
  if (report.available) {
    console.log(`Official MNN iOS core: available (${path.relative(rootDir, report.complete.file)})`);
    return;
  }
  if (report.inspected.length > 0) {
    console.log('Official MNN iOS core: candidate found but incomplete');
    for (const item of report.inspected) {
      if (item.complete) continue;
      const missing = [...item.missing, ...item.missingArch].join(', ');
      const archs = item.diagnostics?.archs?.length ? item.diagnostics.archs.join(',') : 'unknown-arch';
      console.log(`- ${path.relative(rootDir, item.file)} missing: ${missing || 'unknown'}; archs: ${archs}`);
    }
    return;
  }
  console.log('Official MNN iOS core: not vendored yet');
}

const contractFailures = assertSourceContracts();
if (contractFailures.length > 0) {
  console.error('iOS native runtime source contract check failed:');
  for (const failure of contractFailures) console.error(`- ${failure}`);
  process.exit(1);
}

if (appPath && !exists(appPath)) {
  console.error(`SILVERCARE_IOS_APP_PATH does not exist: ${appPath}`);
  process.exit(1);
}

const appCandidates = appRuntimeCandidates();
const appFirst = Boolean(appPath);
function orderedCandidates(appSpecific, sourceSpecific) {
  return appFirst ? [...appSpecific, ...sourceSpecific] : [...sourceSpecific, ...appSpecific];
}

const mnnSourceCandidates = [
  path.join(nativeDir, 'SilverCareMNNRuntime.framework'),
  path.join(nativeDir, 'libsilvercare_mnn_runtime.framework'),
  path.join(nativeDir, 'SilverCareMNNRuntime.xcframework'),
  path.join(nativeDir, 'libsilvercare_mnn_runtime.a'),
  path.join(nativeDir, 'libsilvercare_mnn_runtime.dylib'),
  path.join(nativeDir, 'Vendor', 'SilverCareMNNRuntime.framework'),
  path.join(nativeDir, 'Vendor', 'libsilvercare_mnn_runtime.framework'),
  path.join(nativeDir, 'Vendor', 'SilverCareMNNRuntime.xcframework'),
  path.join(nativeDir, 'Vendor', 'libsilvercare_mnn_runtime.a'),
  path.join(nativeDir, 'Vendor', 'libsilvercare_mnn_runtime.dylib')
];
const mnnAppCandidates = candidateFiles(appCandidates.mnn);
const mnnCandidates = candidateFiles(orderedCandidates(appCandidates.mnn, mnnSourceCandidates));

const ttsSourceCandidates = [
  path.join(nativeDir, 'SilverCareMNNTTSRuntime.framework'),
  path.join(nativeDir, 'libsilvercare_mnn_tts_runtime.framework'),
  path.join(nativeDir, 'SilverCareMNNTTSRuntime.xcframework'),
  path.join(nativeDir, 'libsilvercare_mnn_tts_runtime.xcframework'),
  path.join(nativeDir, 'libsilvercare_mnn_tts_runtime.a'),
  path.join(nativeDir, 'libsilvercare_mnn_tts_runtime.dylib'),
  path.join(nativeDir, 'libmnn_tts.framework'),
  path.join(nativeDir, 'libmnn_tts.xcframework'),
  path.join(nativeDir, 'libmnn_tts.a'),
  path.join(nativeDir, 'libmnn_tts.dylib'),
  path.join(nativeDir, 'Vendor', 'SilverCareMNNTTSRuntime.framework'),
  path.join(nativeDir, 'Vendor', 'libsilvercare_mnn_tts_runtime.framework'),
  path.join(nativeDir, 'Vendor', 'SilverCareMNNTTSRuntime.xcframework'),
  path.join(nativeDir, 'Vendor', 'libsilvercare_mnn_tts_runtime.xcframework'),
  path.join(nativeDir, 'Vendor', 'libsilvercare_mnn_tts_runtime.a'),
  path.join(nativeDir, 'Vendor', 'libsilvercare_mnn_tts_runtime.dylib'),
  path.join(nativeDir, 'Vendor', 'libmnn_tts.framework'),
  path.join(nativeDir, 'Vendor', 'libmnn_tts.xcframework'),
  path.join(nativeDir, 'Vendor', 'libmnn_tts.a'),
  path.join(nativeDir, 'Vendor', 'libmnn_tts.dylib')
];
const ttsAppCandidates = candidateFiles(appCandidates.tts);
const ttsCandidates = candidateFiles(orderedCandidates(appCandidates.tts, ttsSourceCandidates));

const voskSourceCandidates = [
  path.join(nativeDir, 'vosk.framework'),
  path.join(nativeDir, 'libvosk.framework'),
  path.join(nativeDir, 'libvosk.dylib'),
  path.join(nativeDir, 'libvosk.a'),
  path.join(nativeDir, 'Vendor', 'vosk.framework'),
  path.join(nativeDir, 'Vendor', 'libvosk.framework'),
  path.join(nativeDir, 'Vendor', 'libvosk.dylib'),
  path.join(nativeDir, 'Vendor', 'libvosk.a'),
  path.join(nativeDir, 'Vendor', 'vosk.xcframework'),
  path.join(nativeDir, 'Vendor', 'libvosk.xcframework')
];
const voskAppCandidates = candidateFiles(appCandidates.vosk);
const voskCandidates = candidateFiles(orderedCandidates(appCandidates.vosk, voskSourceCandidates));
const mnnCoreCandidates = candidateFiles([
  path.join(nativeDir, 'Vendor', 'MNN-3.5.0-ios', 'MNN-iOS-CPU-GPU', 'Static', 'MNN.framework'),
  path.join(nativeDir, 'Vendor', 'MNN.framework'),
  path.join(nativeDir, 'Vendor', 'MNN.xcframework')
]);

const mnnReport = symbolReport('MNN', mnnCandidates, mnnRequiredAll, mnnRequiredAny);
const ttsReport = symbolReport('MNN TTS', ttsCandidates, ttsRequiredAll);
const voskReport = symbolReport('Vosk', voskCandidates, voskRequiredAll);
const appReportOptions = requireAppBundleRuntime ? { requiredPlatform: requiredAppBundlePlatform } : {};
const mnnAppReport = appPath ? symbolReport('app-bundle MNN', mnnAppCandidates, mnnRequiredAll, mnnRequiredAny, appReportOptions) : null;
const ttsAppReport = appPath ? symbolReport('app-bundle MNN TTS', ttsAppCandidates, ttsRequiredAll, [], appReportOptions) : null;
const voskAppReport = appPath ? symbolReport('app-bundle Vosk', voskAppCandidates, voskRequiredAll, [], appReportOptions) : null;
const mnnCore = mnnCoreReport(mnnCoreCandidates);

printMnnCoreReport(mnnCore);
printReport(mnnReport);
printReport(ttsReport);
printReport(voskReport);
if (appPath) {
  printReport(mnnAppReport);
  printReport(ttsAppReport);
  printReport(voskAppReport);
}

const malformed = [mnnReport, ttsReport, voskReport, mnnAppReport, ttsAppReport, voskAppReport]
  .filter(Boolean)
  .flatMap((report) => report.malformed);
if (malformed.length > 0) {
  console.error('iOS native runtime candidate ABI check failed.');
  process.exit(1);
}

if (strict && (!mnnReport.available || !ttsReport.available || !voskReport.available)) {
  console.error('SILVERCARE_REQUIRE_IOS_NATIVE_RUNTIME=1 requires iOS MNN, MNN TTS, and Vosk runtimes.');
  process.exit(1);
}

if (requireAppBundleRuntime && (!appPath || !mnnAppReport.available || !ttsAppReport.available || !voskAppReport.available)) {
  console.error(`SILVERCARE_REQUIRE_IOS_APP_BUNDLE_RUNTIME=1 requires bundled iOS MNN, MNN TTS, and Vosk runtimes with ${requiredAppBundlePlatform} platform slices.`);
  process.exit(1);
}

console.log('Checked iOS native runtime source contracts.');
