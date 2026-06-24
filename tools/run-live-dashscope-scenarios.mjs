import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const outputRoot = path.join(repoRoot, 'test_runs', 'live_dashscope_scenarios');
const imageRoot = path.join(outputRoot, 'images');
const audioRoot = path.join(outputRoot, 'audio');

const apiKey = (process.env.DASHSCOPE_API_KEY || '').trim();
const compatibleBaseURL = process.env.DASHSCOPE_COMPATIBLE_BASE_URL || 'https://dashscope.aliyuncs.com/compatible-mode/v1';
const apiBaseURL = process.env.DASHSCOPE_API_BASE_URL || 'https://dashscope.aliyuncs.com/api/v1';
const visionModel = process.env.DASHSCOPE_VISION_MODEL || 'qwen3-vl-flash';
const textModel = process.env.DASHSCOPE_TEXT_MODEL || 'qwen-plus';
const asrModel = process.env.DASHSCOPE_ASR_MODEL || 'qwen3-asr-flash';
const runTts = process.env.SILVERCARE_LIVE_TEST_TTS !== '0';
const runAsr = process.env.SILVERCARE_LIVE_TEST_ASR !== '0';

const scenarios = [
  {
    id: 'crosswalk_town_street',
    title: '街道斑马线',
    expectedHints: ['行人', '斑马线', '道路', '车辆', '过街'],
    url: 'https://upload.wikimedia.org/wikipedia/commons/6/69/Pedestrian_Crossing%2C_Town_Street%2C_Beeston_-_geograph.org.uk_-_5577367.jpg',
    sourcePage: 'https://commons.wikimedia.org/wiki/File:Pedestrian_Crossing,_Town_Street,_Beeston_-_geograph.org.uk_-_5577367.jpg'
  },
  {
    id: 'new_york_street',
    title: '城市街道',
    expectedHints: ['街道', '道路', '车辆', '行人', '交通'],
    url: 'https://upload.wikimedia.org/wikipedia/commons/f/f9/Street_in_New_York_City.jpg',
    sourcePage: 'https://commons.wikimedia.org/wiki/File:Street_in_New_York_City.jpg'
  },
  {
    id: 'brick_sidewalk',
    title: '人行道',
    expectedHints: ['人行道', '路面', '前方', '障碍', '通行'],
    url: 'https://upload.wikimedia.org/wikipedia/commons/1/15/Brick_sidewalk_%28Salem%2C_Massachusetts%29_Photography_by_David_Adam_Kess.jpg',
    sourcePage: 'https://commons.wikimedia.org/wiki/File:Brick_sidewalk_(Salem,_Massachusetts)_Photography_by_David_Adam_Kess.jpg'
  }
];

function assertApiKey() {
  if (!apiKey) {
    throw new Error('DASHSCOPE_API_KEY is required for live DashScope scenario tests.');
  }
}

function endpoint(baseURL, suffix) {
  const base = baseURL.replace(/\/+$/, '');
  const cleanSuffix = suffix.replace(/^\/+/, '');
  return `${base}/${cleanSuffix}`;
}

function redactError(error) {
  const raw = error?.stack || error?.message || String(error);
  return raw.replaceAll(apiKey, '[REDACTED_DASHSCOPE_API_KEY]');
}

function normalizeContent(content) {
  if (typeof content === 'string') return content;
  if (Array.isArray(content)) {
    return content
      .map((item) => {
        if (typeof item === 'string') return item;
        if (item && typeof item === 'object') return item.text || item.content || '';
        return '';
      })
      .join('\n')
      .trim();
  }
  return '';
}

function parseJSONFromModel(text) {
  const clean = String(text || '').trim()
    .replace(/^```(?:json)?/i, '')
    .replace(/```$/i, '')
    .trim();
  try {
    return JSON.parse(clean);
  } catch {
    const start = clean.indexOf('{');
    const end = clean.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return JSON.parse(clean.slice(start, end + 1));
    }
    throw new Error(`Model output is not parseable JSON: ${clean.slice(0, 240)}`);
  }
}

function validateNavigationJSON(result) {
  const allowedPriorities = new Set(['low', 'medium', 'high']);
  const allowedDirections = new Set(['left', 'right', 'ahead', 'behind', 'unknown']);
  const errors = [];
  if (!allowedPriorities.has(result.priority)) errors.push('priority must be low, medium, or high');
  if (typeof result.speech !== 'string' || result.speech.trim().length < 2) errors.push('speech must be non-empty');
  if (typeof result.scene_description !== 'string' || result.scene_description.trim().length < 4) {
    errors.push('scene_description must be non-empty');
  }
  if (!allowedDirections.has(result.direction)) errors.push('direction must be left, right, ahead, behind, or unknown');
  if (!Array.isArray(result.objects)) errors.push('objects must be an array');
  return errors;
}

function imageContentTypeForPath(filePath) {
  const extension = path.extname(filePath).toLowerCase();
  if (extension === '.png') return 'image/png';
  if (extension === '.webp') return 'image/webp';
  return 'image/jpeg';
}

async function cachedScenarioImage(scenario, downloadError = '') {
  for (const extension of ['jpg', 'jpeg', 'png', 'webp']) {
    const filePath = path.join(imageRoot, `${scenario.id}.${extension}`);
    try {
      const bytes = await readFile(filePath);
      if (bytes.length >= 1024) {
        return {
          filePath,
          contentType: imageContentTypeForPath(filePath),
          bytes: bytes.length,
          sourceURL: scenario.url,
          cached: true,
          downloadError
        };
      }
    } catch {
      // Try the next cached extension.
    }
  }
  return null;
}

async function downloadScenarioImage(scenario) {
  await mkdir(imageRoot, { recursive: true });
  let lastError = '';
  for (const url of [scenario.url, ...(scenario.fallbackUrls || [])]) {
    try {
      const response = await fetch(url, {
        headers: { 'user-agent': 'SilverCareLiveDashScopeScenarioTest/1.0' }
      });
      if (!response.ok) {
        throw new Error(`${response.status} ${response.statusText}`);
      }
      const contentType = response.headers.get('content-type') || 'application/octet-stream';
      if (!contentType.startsWith('image/')) {
        throw new Error(`returned ${contentType}`);
      }
      const extension = contentType.includes('png') ? 'png' : contentType.includes('webp') ? 'webp' : 'jpg';
      const filePath = path.join(imageRoot, `${scenario.id}.${extension}`);
      const bytes = Buffer.from(await response.arrayBuffer());
      await writeFile(filePath, bytes);
      return { filePath, contentType, bytes: bytes.length, sourceURL: url, cached: false };
    } catch (error) {
      lastError = `Image download failed for ${scenario.id}: ${error.message || String(error)}`;
    }
  }
  const cached = await cachedScenarioImage(scenario, lastError);
  if (cached) return cached;
  throw new Error(lastError || `Image download failed for ${scenario.id}`);
}

function extensionFromAudioContentType(contentType) {
  const normalized = contentType.toLowerCase();
  if (normalized.includes('mpeg') || normalized.includes('mp3')) return 'mp3';
  if (normalized.includes('wav') || normalized.includes('wave')) return 'wav';
  if (normalized.includes('mp4') || normalized.includes('m4a')) return 'm4a';
  if (normalized.includes('ogg')) return 'ogg';
  if (normalized.includes('webm')) return 'webm';
  return 'bin';
}

async function downloadGeneratedAudio(audioURL, label) {
  await mkdir(audioRoot, { recursive: true });
  const response = await fetch(audioURL, {
    headers: { 'user-agent': 'SilverCareLiveDashScopeScenarioTest/1.0' }
  });
  if (!response.ok) {
    throw new Error(`TTS audio download failed: ${response.status} ${response.statusText}`);
  }
  const contentType = response.headers.get('content-type') || 'application/octet-stream';
  if (!contentType.startsWith('audio/') && contentType !== 'application/octet-stream') {
    throw new Error(`TTS audio download returned ${contentType}`);
  }
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length < 1024) {
    throw new Error(`TTS audio download is too small: ${bytes.length} bytes`);
  }
  const extension = extensionFromAudioContentType(contentType);
  const filePath = path.join(audioRoot, `${label}.${extension}`);
  await writeFile(filePath, bytes);
  return {
    path: path.relative(repoRoot, filePath),
    content_type: contentType,
    bytes: bytes.length,
    source_host: new URL(audioURL).host
  };
}

async function imageDataURL(filePath, contentType) {
  const bytes = await readFile(filePath);
  return `data:${contentType};base64,${bytes.toString('base64')}`;
}

async function fileDataURL(filePath, contentType) {
  const bytes = await readFile(filePath);
  return `data:${contentType};base64,${bytes.toString('base64')}`;
}

function scenarioPrompt(scenario) {
  return [
    '你是“银龄智护”盲人/低视力老人导航助手。',
    `请分析这张真实${scenario.title}图片，判断老人下一步是否安全。`,
    '只返回严格 JSON，不要 Markdown，不要解释。',
    'JSON 字段必须是：',
    '{',
    '  "priority": "low|medium|high",',
    '  "category": "navigation",',
    '  "subject": "主要风险或通行目标",',
    '  "distance": 0到10之间的数字，未知填0,',
    '  "direction": "left|right|ahead|behind|unknown",',
    '  "speech": "20字以内中文语音提示",',
    '  "scene_description": "一句中文场景描述",',
    '  "objects": ["最多5个关键物体"]',
    '}',
    `提示词范围：${scenario.expectedHints.join('、')}`
  ].join('\n');
}

async function postJSON(url, payload) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${apiKey}`,
      'content-type': 'application/json; charset=utf-8',
      'user-agent': 'SilverCareLiveDashScopeScenarioTest/1.0'
    },
    body: JSON.stringify(payload)
  });
  const text = await response.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new Error(`DashScope returned non-JSON ${response.status}: ${text.slice(0, 500)}`);
  }
  if (!response.ok) {
    throw new Error(`DashScope request failed ${response.status}: ${JSON.stringify(json).slice(0, 800)}`);
  }
  return json;
}

async function runVisionScenario(scenario) {
  const image = await downloadScenarioImage(scenario);
  const dataURL = await imageDataURL(image.filePath, image.contentType);
  const startedAt = Date.now();
  const payload = {
    model: visionModel,
    messages: [
      {
        role: 'user',
        content: [
          { type: 'text', text: scenarioPrompt(scenario) },
          { type: 'image_url', image_url: { url: dataURL } }
        ]
      }
    ],
    response_format: { type: 'json_object' },
    stream: false,
    temperature: 0.1
  };
  const response = await postJSON(endpoint(compatibleBaseURL, '/chat/completions'), payload);
  const content = normalizeContent(response.choices?.[0]?.message?.content);
  const result = parseJSONFromModel(content);
  const validationErrors = validateNavigationJSON(result);
  return {
    id: scenario.id,
    title: scenario.title,
    status: validationErrors.length === 0 ? 'passed' : 'failed',
    elapsed_ms: Date.now() - startedAt,
    image: {
      path: path.relative(repoRoot, image.filePath),
      source_url: image.sourceURL || scenario.url,
      source_page: scenario.sourcePage,
      content_type: image.contentType,
      bytes: image.bytes,
      cached: image.cached === true,
      download_error: image.downloadError || ''
    },
    validation_errors: validationErrors,
    result: {
      priority: result.priority,
      category: result.category,
      subject: result.subject,
      distance: result.distance,
      direction: result.direction,
      speech: result.speech,
      scene_description: result.scene_description,
      objects: Array.isArray(result.objects) ? result.objects.slice(0, 5) : []
    }
  };
}

async function runTextSmoke() {
  const startedAt = Date.now();
  const response = await postJSON(endpoint(compatibleBaseURL, '/chat/completions'), {
    model: textModel,
    messages: [
      {
        role: 'user',
        content: [
          {
            type: 'text',
            text: '只返回 JSON：{"ok":true,"speech":"云端文本测试通过"}'
          }
        ]
      }
    ],
    response_format: { type: 'json_object' },
    stream: false,
    temperature: 0
  });
  const content = normalizeContent(response.choices?.[0]?.message?.content);
  const result = parseJSONFromModel(content);
  return {
    status: result.ok === true && typeof result.speech === 'string' ? 'passed' : 'failed',
    elapsed_ms: Date.now() - startedAt,
    speech: result.speech || ''
  };
}

async function runTtsSmoke() {
  if (!runTts) {
    return { status: 'skipped', reason: 'SILVERCARE_LIVE_TEST_TTS=0' };
  }
  const startedAt = Date.now();
  const response = await postJSON(endpoint(apiBaseURL, '/services/aigc/multimodal-generation/generation'), {
    model: 'qwen3-tts-flash',
    input: {
      text: '前方有人行横道，请等待安全后再直行。',
      voice: 'Cherry',
      language_type: 'Chinese'
    }
  });
  const audioURL = response.output?.audio?.url || '';
  if (!/^https?:\/\//.test(audioURL)) {
    return {
      status: 'failed',
      elapsed_ms: Date.now() - startedAt,
      has_audio_url: false
    };
  }
  const audio = await downloadGeneratedAudio(audioURL, 'tts_smoke');
  return {
    status: 'passed',
    elapsed_ms: Date.now() - startedAt,
    has_audio_url: true,
    audio
  };
}

async function runAsrSmoke() {
  if (!runAsr) {
    return { status: 'skipped', reason: 'SILVERCARE_LIVE_TEST_ASR=0' };
  }
  const startedAt = Date.now();
  const audioPath = path.join(repoRoot, 'public_benchmark_silvercare', 'dataset', 'audio', 'find_door.wav');
  const audioDataURL = await fileDataURL(audioPath, 'audio/wav');
  const response = await postJSON(endpoint(apiBaseURL, '/services/aigc/multimodal-generation/generation'), {
    model: asrModel,
    input: {
      messages: [
        {
          role: 'system',
          content: [
            {
              text: '银龄智护 盲人导航助手。常见词：找门、找水杯、启动导航、倒一杯水、障碍物。'
            }
          ]
        },
        {
          role: 'user',
          content: [
            {
              audio: audioDataURL
            }
          ]
        }
      ]
    },
    parameters: {
      asr_options: {
        language: 'zh',
        enable_itn: false
      }
    }
  });
  const transcript = response.output?.choices?.[0]?.message?.content?.[0]?.text || '';
  const normalized = String(transcript).replace(/\s+/g, '');
  const passed = /找.*门|门/.test(normalized);
  return {
    status: passed ? 'passed' : 'failed',
    elapsed_ms: Date.now() - startedAt,
    model: asrModel,
    audio: path.relative(repoRoot, audioPath),
    transcript
  };
}

async function main() {
  assertApiKey();
  await mkdir(outputRoot, { recursive: true });
  const startedAt = new Date();
  const report = {
    generated_at: startedAt.toISOString(),
    api_key: '[REDACTED_DASHSCOPE_API_KEY]',
    models: {
      vision: visionModel,
      text: textModel,
      asr: asrModel,
      tts: 'qwen3-tts-flash'
    },
    endpoints: {
      compatible: compatibleBaseURL,
      api: apiBaseURL
    },
    text_smoke: null,
    asr_smoke: null,
    tts_smoke: null,
    scenarios: []
  };

  try {
    report.text_smoke = await runTextSmoke();
    for (const scenario of scenarios) {
      report.scenarios.push(await runVisionScenario(scenario));
    }
    report.asr_smoke = await runAsrSmoke();
    report.tts_smoke = await runTtsSmoke();
  } catch (error) {
    report.fatal_error = redactError(error);
  }

  const passed =
    !report.fatal_error &&
    report.text_smoke?.status === 'passed' &&
    report.scenarios.every((scenario) => scenario.status === 'passed') &&
    (!runAsr || report.asr_smoke?.status === 'passed') &&
    (!runTts || report.tts_smoke?.status === 'passed');

  report.status = passed ? 'passed' : 'failed';
  report.elapsed_ms = Date.now() - startedAt.getTime();

  const jsonPath = path.join(outputRoot, 'summary.json');
  const markdownPath = path.join(outputRoot, 'summary.md');
  await writeFile(jsonPath, `${JSON.stringify(report, null, 2)}\n`);
  await writeFile(markdownPath, renderMarkdown(report));

  console.log(`Live DashScope scenario status: ${report.status}`);
  console.log(`Report: ${path.relative(repoRoot, jsonPath)}`);
  for (const scenario of report.scenarios) {
    console.log(`- ${scenario.id}: ${scenario.status} / ${scenario.result?.speech || scenario.validation_errors?.join('; ')}`);
  }
  if (report.tts_smoke) {
    console.log(`TTS smoke: ${report.tts_smoke.status}`);
  }
  if (report.asr_smoke) {
    console.log(`ASR smoke: ${report.asr_smoke.status} / ${report.asr_smoke.transcript || report.asr_smoke.reason || ''}`);
  }
  if (!passed) {
    process.exitCode = 1;
  }
}

function renderMarkdown(report) {
  const lines = [
    '# SilverCare Live DashScope Scenario Test',
    '',
    `- Status: ${report.status}`,
    `- Generated at: ${report.generated_at}`,
    `- Vision model: ${report.models.vision}`,
    `- Text smoke: ${report.text_smoke?.status || 'not-run'}`,
    `- ASR smoke: ${report.asr_smoke?.status || 'not-run'}`,
    `- TTS smoke: ${report.tts_smoke?.status || 'not-run'}`,
    `- API key: ${report.api_key}`,
    ''
  ];
  if (report.fatal_error) {
    lines.push('## Fatal Error', '', '```text', report.fatal_error, '```', '');
  }
  if (report.asr_smoke) {
    lines.push(
      '## ASR Smoke',
      '',
      `- Status: ${report.asr_smoke.status}`,
      `- Model: ${report.asr_smoke.model || ''}`,
      `- Audio: ${report.asr_smoke.audio || ''}`,
      `- Transcript: ${report.asr_smoke.transcript || report.asr_smoke.reason || ''}`,
      ''
    );
  }
  if (report.tts_smoke) {
    lines.push(
      '## TTS Smoke',
      '',
      `- Status: ${report.tts_smoke.status}`,
      `- Audio file: ${report.tts_smoke.audio?.path || ''}`,
      `- Audio bytes: ${report.tts_smoke.audio?.bytes || ''}`,
      `- Audio content type: ${report.tts_smoke.audio?.content_type || ''}`,
      ''
    );
  }
  lines.push('## Scenarios', '');
  for (const scenario of report.scenarios) {
    lines.push(
      `### ${scenario.title}`,
      '',
      `- Status: ${scenario.status}`,
      `- Source: ${scenario.image.source_page}`,
      `- Local image: ${scenario.image.path}`,
      `- Speech: ${scenario.result?.speech || ''}`,
      `- Priority: ${scenario.result?.priority || ''}`,
      `- Direction: ${scenario.result?.direction || ''}`,
      `- Scene: ${scenario.result?.scene_description || ''}`,
      `- Objects: ${(scenario.result?.objects || []).join(', ')}`,
      ''
    );
    if (scenario.validation_errors?.length) {
      lines.push(`Validation errors: ${scenario.validation_errors.join('; ')}`, '');
    }
  }
  return `${lines.join('\n')}\n`;
}

await main();
