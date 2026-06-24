import fs from 'node:fs/promises';
import path from 'node:path';

const rootDir = process.cwd();
const maxTextBytes = 5 * 1024 * 1024;
const tokenPrefix = `${['s', 'k'].join('')}-${['w', 's'].join('')}`;

const skippedDirectories = new Set([
  '.git',
  '.gradle',
  '.swiftpm',
  '.build',
  'node_modules',
  'DerivedData-SimulatorAutomation',
  'DerivedData-device',
  'DerivedData-device-nosign',
  'DerivedData-MNNLoaderCheck'
]);

const skippedExtensions = new Set([
  '.a',
  '.app',
  '.dylib',
  '.framework',
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.mp3',
  '.m4a',
  '.wav',
  '.zip'
]);

const secretPatterns = [
  {
    label: 'DashScope-style API key',
    regex: new RegExp(`${tokenPrefix.replaceAll('-', '\\-')}[A-Za-z0-9._-]{20,}`, 'g')
  },
  {
    label: 'generic long bearer token',
    regex: /\bBearer\s+[A-Za-z0-9._-]{32,}/g
  }
];

function shouldSkipDirectory(name) {
  return skippedDirectories.has(name);
}

function normalizedRelativePath(filePath) {
  return path.relative(rootDir, filePath).split(path.sep).join('/');
}

function isAppBundlePrivateConfig(filePath) {
  return /^ios\/build\/.*\.app\/SilverCarePrivateConfig\.plist$/.test(normalizedRelativePath(filePath));
}

function shouldSkipFile(filePath, stat) {
  if (stat.size > maxTextBytes) return true;
  if (isAppBundlePrivateConfig(filePath)) return true;
  const ext = path.extname(filePath).toLowerCase();
  return skippedExtensions.has(ext);
}

function isLikelyBinary(buffer) {
  return buffer.includes(0);
}

async function* walk(directory) {
  const entries = await fs.readdir(directory, { withFileTypes: true });
  for (const entry of entries) {
    if (shouldSkipDirectory(entry.name)) continue;
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      yield* walk(fullPath);
    } else if (entry.isFile()) {
      yield fullPath;
    }
  }
}

function redactMatch(value) {
  if (value.length <= 12) return '[REDACTED]';
  return `${value.slice(0, 4)}...[REDACTED]...${value.slice(-4)}`;
}

async function main() {
  const findings = [];
  for await (const filePath of walk(rootDir)) {
    const stat = await fs.stat(filePath);
    if (shouldSkipFile(filePath, stat)) continue;
    const buffer = await fs.readFile(filePath);
    if (isLikelyBinary(buffer)) continue;
    const text = buffer.toString('utf8');
    for (const pattern of secretPatterns) {
      for (const match of text.matchAll(pattern.regex)) {
        findings.push({
          file: path.relative(rootDir, filePath),
          label: pattern.label,
          token: redactMatch(match[0])
        });
      }
    }
  }

  if (findings.length > 0) {
    console.error('Sensitive secret scan failed:');
    for (const finding of findings) {
      console.error(`- ${finding.file}: ${finding.label} (${finding.token})`);
    }
    process.exit(1);
  }

  console.log('Checked repository secret scan.');
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
