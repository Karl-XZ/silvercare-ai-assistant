import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, '..');

const textExtensions = new Set(['.md', '.json', '.jsonl', '.mjs', '.js', '.txt']);
const skippedRelativeFiles = new Set(['scripts/check_anonymization.mjs', 'reports/anonymization_check.json']);

function listFiles(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'node_modules' || entry.name === '.git') continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...listFiles(full));
    else out.push(full);
  }
  return out;
}

function rel(file) {
  return path.relative(root, file).replace(/\\/g, '/');
}

const findings = [];
const secretPattern = /sk-[A-Za-z0-9]{16,}/g;
const windowsPathPattern = /[A-Za-z]:\\[^"'`\r\n]+/g;
const identityPatterns = [
  /身份证/g,
  /银行卡/g,
  /住址/g,
  /门牌号/g,
  /真实姓名/g,
  /所属机构/g,
  /参赛人员/g
];

for (const file of listFiles(root)) {
  const relative = rel(file);
  const ext = path.extname(file).toLowerCase();
  if (textExtensions.has(ext) && !skippedRelativeFiles.has(relative)) {
    const text = fs.readFileSync(file, 'utf8');
    for (const match of text.matchAll(secretPattern)) {
      findings.push({ file: relative, type: 'secret_like_pattern', match: match[0].slice(0, 8) + '...' });
    }
    for (const match of text.matchAll(windowsPathPattern)) {
      findings.push({ file: relative, type: 'absolute_windows_path', match: match[0] });
    }
    if ((relative.startsWith('dataset/') || relative.startsWith('reports/')) && ['.json', '.jsonl'].includes(ext)) {
      for (const pattern of identityPatterns) {
        if (pattern.test(text)) findings.push({ file: relative, type: 'identity_term', pattern: String(pattern) });
      }
    }
  }
  if (ext === '.jpg' || ext === '.jpeg') {
    const bytes = fs.readFileSync(file);
    if (bytes.includes(Buffer.from('Exif'))) {
      findings.push({ file: relative, type: 'jpeg_exif_marker' });
    }
  }
}

const result = {
  checked_at: new Date().toISOString(),
  checked_files: listFiles(root).length,
  passed: findings.length === 0,
  findings
};

fs.mkdirSync(path.join(root, 'reports'), { recursive: true });
fs.writeFileSync(path.join(root, 'reports', 'anonymization_check.json'), `${JSON.stringify(result, null, 2)}\n`, 'utf8');
console.log(JSON.stringify(result, null, 2));
if (!result.passed) process.exitCode = 1;
