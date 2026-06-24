import fs from 'node:fs';
import path from 'node:path';

const jsRoots = [
  'app/src/main/assets/static/js',
  'app/src/main/assets/index.html'
];
const bridgeFile = 'ios/SilverCareiOS/Bridge/SilverCareBridgeScript.swift';
const appModelFile = 'ios/SilverCareiOS/App/SilverCareAppModel.swift';
const androidMainFile = 'app/src/main/java/com/silvercare/aiassistant/MainActivity.java';
const androidBenchmarkFile = 'app/src/main/java/com/silvercare/aiassistant/LocalModelBenchmarkActivity.java';

function walk(target, files = []) {
  const stat = fs.statSync(target);
  if (stat.isDirectory()) {
    for (const entry of fs.readdirSync(target)) {
      walk(path.join(target, entry), files);
    }
  } else if (/\.(html|mjs|js)$/.test(target)) {
    files.push(target);
  }
  return files;
}

function collectFrontendBridgeCalls() {
  const files = jsRoots.flatMap((root) => walk(root));
  const calls = new Set();
  const patterns = [
    /AndroidSilverCare\.([A-Za-z_$][\w$]*)/g,
    /AndroidSilverCare\[['"]([^'"]+)['"]\]/g,
    /safeNative(?:String|Boolean|Number)\(['"]([^'"]+)['"]/g
  ];

  for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    for (const pattern of patterns) {
      for (const match of text.matchAll(pattern)) {
        calls.add(match[1]);
      }
    }
  }
  return calls;
}

function collectIOSBridgeMethods() {
  const text = fs.readFileSync(bridgeFile, 'utf8');
  const methods = new Set();
  const pattern = /^\s{12}([A-Za-z_$][\w$]*):\s*(?:\([^)]*\)|\(\)|function|\w)/gm;
  for (const match of text.matchAll(pattern)) {
    methods.add(match[1]);
  }
  return methods;
}

function collectAndroidBridgeMethods() {
  const text = fs.readFileSync(androidMainFile, 'utf8');
  const methods = new Map();
  const pattern = /@JavascriptInterface\s+public\s+([\w<>[\].?]+)\s+([A-Za-z_$][\w$]*)\s*\(/g;
  for (const match of text.matchAll(pattern)) {
    methods.set(match[2], { returnType: match[1] });
  }
  return methods;
}

function collectIOSRouteCases() {
  const text = fs.readFileSync(appModelFile, 'utf8');
  const methods = new Set();
  const pattern = /case\s+"([^"]+)":/g;
  for (const match of text.matchAll(pattern)) {
    methods.add(match[1]);
  }
  return methods;
}

const frontendCalls = collectFrontendBridgeCalls();
const iosMethods = collectIOSBridgeMethods();
const missing = [...frontendCalls].filter((method) => !iosMethods.has(method)).sort();

if (missing.length > 0) {
  console.error(`iOS bridge is missing ${missing.length} AndroidSilverCare method(s):`);
  for (const method of missing) {
    console.error(`- ${method}`);
  }
  process.exit(1);
}

function assertAndroidBridgeParity() {
  const androidMethods = collectAndroidBridgeMethods();
  const iosRouteCases = collectIOSRouteCases();
  const missingMethods = [...androidMethods.keys()].filter((method) => !iosMethods.has(method)).sort();
  const missingRoutes = [...androidMethods.entries()]
    .filter(([, details]) => details.returnType === 'void')
    .map(([method]) => method)
    .filter((method) => !iosRouteCases.has(method))
    .sort();

  if (missingMethods.length > 0 || missingRoutes.length > 0) {
    console.error('iOS bridge is missing Android @JavascriptInterface parity:');
    for (const method of missingMethods) {
      console.error(`- bridge method: ${method}`);
    }
    for (const method of missingRoutes) {
      console.error(`- native route case: ${method}`);
    }
    process.exit(1);
  }
  console.log(`Checked iOS bridge parity for ${androidMethods.size} Android @JavascriptInterface method(s).`);
}

function collectAndroidBenchmarkTests() {
  const text = fs.readFileSync(androidBenchmarkFile, 'utf8');
  const tests = new Set(['status']);
  const pattern = /case\s+"([^"]+)"\s+->\s+benchmark/g;
  for (const match of text.matchAll(pattern)) {
    tests.add(match[1]);
  }
  return tests;
}

function assertIOSBenchmarkParity() {
  const bridgeText = fs.readFileSync(bridgeFile, 'utf8');
  const appModelText = fs.readFileSync(appModelFile, 'utf8');
  const expectedTests = collectAndroidBenchmarkTests();
  const missingTests = [];

  if (!bridgeText.includes("runLocalBenchmark: (test = 'status') => post('runLocalBenchmark', [test])")) {
    missingTests.push('bridge runLocalBenchmark(test) argument forwarding');
  }
  for (const test of expectedTests) {
    if (test === 'status') {
      if (!appModelText.includes('makeLocalBenchmarkStatusReport()')) missingTests.push(test);
      continue;
    }
    if (!appModelText.includes(`case "${test}"`)) {
      missingTests.push(test);
    }
  }

  if (missingTests.length > 0) {
    console.error('iOS local benchmark parity check failed. Missing:');
    for (const item of missingTests) {
      console.error(`- ${item}`);
    }
    process.exit(1);
  }
  console.log(`Checked iOS local benchmark parity for ${expectedTests.size} Android test branch(es).`);
}

assertAndroidBridgeParity();
assertIOSBenchmarkParity();

console.log(`Checked iOS bridge compatibility for ${frontendCalls.size} frontend native method references.`);
