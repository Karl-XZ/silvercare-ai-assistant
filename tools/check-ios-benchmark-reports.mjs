import fs from 'node:fs';
import path from 'node:path';

const defaultTests = ['status', 'asr', 'vision', 'text', 'text_suite', 'text_inquiry', 'tts', 'scenario'];
const reportDir = process.argv[2];
const tests = (process.argv[3] || defaultTests.join(','))
  .split(',')
  .map((item) => item.trim())
  .filter(Boolean);
const requireASRBenchmark = process.env.SILVERCARE_IOS_REQUIRE_ASR_BENCHMARK === '1';
const requireScenarioFixtures = process.env.SILVERCARE_IOS_REQUIRE_SCENARIO_FIXTURES === '1';
const requireScenarioASR = process.env.SILVERCARE_IOS_REQUIRE_SCENARIO_ASR === '1';

if (!reportDir) {
  console.error('Usage: node tools/check-ios-benchmark-reports.mjs <report-dir> [comma-separated-tests]');
  process.exit(2);
}

function fail(message) {
  console.error(`iOS benchmark report check failed: ${message}`);
  process.exit(1);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function readReport(test) {
  const file = path.join(reportDir, `latest-${test}.json`);
  assert(fs.existsSync(file), `missing ${file}`);
  const stat = fs.statSync(file);
  assert(stat.size > 0, `${file} is empty`);
  try {
    const payload = JSON.parse(fs.readFileSync(file, 'utf8'));
    assert(payload && typeof payload === 'object' && !Array.isArray(payload), `${file} must contain a JSON object`);
    return { file, payload };
  } catch (error) {
    fail(`${file} is not valid JSON: ${error.message}`);
  }
}

function assertString(value, context) {
  assert(typeof value === 'string' && value.trim().length > 0, `${context} must be a non-empty string`);
}

function assertStringValue(value, context) {
  assert(typeof value === 'string', `${context} must be a string`);
}

function assertBoolean(value, context) {
  assert(typeof value === 'boolean', `${context} must be a boolean`);
}

function assertObject(value, context) {
  assert(value && typeof value === 'object' && !Array.isArray(value), `${context} must be an object`);
}

function assertArray(value, context) {
  assert(Array.isArray(value), `${context} must be an array`);
}

function assertIncludesAll(text, items, context) {
  assertString(text, context);
  assertArray(items, `${context}.expected_items`);
  assert(items.length > 0, `${context}.expected_items must not be empty`);
  for (const item of items) {
    assertString(item, `${context}.expected_item`);
    assert(text.includes(item), `${context} must mention missing item ${JSON.stringify(item)}`);
  }
}

function assertSuccessfulRuns(report, context) {
  assert(report.success === true, `${context}.success must be true when runtime/model status reports ready`);
  assertArray(report.runs, `${context}.runs`);
  assert(report.runs.length > 0, `${context}.runs must be non-empty when ready`);
  for (const [index, run] of report.runs.entries()) {
    assertObject(run, `${context}.runs[${index}]`);
    assertString(run.name, `${context}.runs[${index}].name`);
    assert(run.success === true, `${context}.runs[${index}].success must be true when ready`);
    assert(Number.isFinite(Number(run.elapsed_ms)), `${context}.runs[${index}].elapsed_ms must be numeric`);
    assertString(run.output_excerpt, `${context}.runs[${index}].output_excerpt`);
  }
}

function assertBase(test, report) {
  assert(report.test === test, `${test}: expected test=${test}, got ${JSON.stringify(report.test)}`);
  assertBoolean(report.success, `${test}.success`);
  assert(Number.isFinite(Number(report.timestamp_ms)), `${test}.timestamp_ms must be numeric`);
  assertString(report.device, `${test}.device`);
  assertString(report.system, `${test}.system`);
  assertString(report.package, `${test}.package`);
  assertString(report.ai_runtime_mode, `${test}.ai_runtime_mode`);
  assertString(report.runtime_label, `${test}.runtime_label`);
  assertString(report.vision_model, `${test}.vision_model`);
  assertString(report.text_model, `${test}.text_model`);
  assertString(report.diagnostic_log_path, `${test}.diagnostic_log_path`);
  assertNativeCamera(report.native_camera, `${test}.native_camera`);
  assertNativeSpeech(report.native_speech, `${test}.native_speech`);
  assertNativeTTS(report.native_tts, `${test}.native_tts`);
  assertString(report.output_file, `${test}.output_file`);
  if (!report.success) assertString(report.error, `${test}.error`);
}

function assertStatus(report) {
  assert(report.success === true, 'status.success must be true so unavailable runtimes are reported as status, not benchmark failure');
  assertString(report.model_root, 'status.model_root');
  assertBoolean(report.mnn_available, 'status.mnn_available');
  assertString(report.mnn_summary, 'status.mnn_summary');
  assertBoolean(report.mnn_sme2_supported, 'status.mnn_sme2_supported');
  assertBoolean(report.offline_ready, 'status.offline_ready');
  assertString(report.offline_status, 'status.offline_status');
  assertOfflinePayload(report.offline, 'status.offline');
  assertBoolean(report.local_asr_ready, 'status.local_asr_ready');
  assertString(report.local_asr_status, 'status.local_asr_status');
  assertObject(report.local_asr, 'status.local_asr');
  assertBoolean(report.local_tts_ready, 'status.local_tts_ready');
  assertBoolean(report.local_tts_model_ready, 'status.local_tts_model_ready');
  assertBoolean(report.local_tts_runtime_available, 'status.local_tts_runtime_available');
  assertBoolean(report.local_tts_voice_quality_passed, 'status.local_tts_voice_quality_passed');
  assertString(report.local_tts_status, 'status.local_tts_status');
  assertObject(report.local_tts, 'status.local_tts');
  assertStringValue(report.runtime_warnings, 'status.runtime_warnings');
  assertString(report.download_summary, 'status.download_summary');
}

function assertNativeCamera(camera, context) {
  assertObject(camera, context);
  const allowedStatuses = new Set(['idle', 'running', 'stopped', 'error', 'warming', 'frame_error']);
  const allowedAuth = new Set(['authorized', 'denied', 'not_determined', 'restricted', 'unknown']);
  assertString(camera.status, `${context}.status`);
  assert(allowedStatuses.has(camera.status), `${context}.status must be one of ${[...allowedStatuses].join(', ')}`);
  assertString(camera.status_text, `${context}.status_text`);
  assertStringValue(camera.error_code, `${context}.error_code`);
  assertBoolean(camera.running, `${context}.running`);
  assertBoolean(camera.available, `${context}.available`);
  assertBoolean(camera.hardware_available, `${context}.hardware_available`);
  assertString(camera.authorization_status, `${context}.authorization_status`);
  assert(allowedAuth.has(camera.authorization_status), `${context}.authorization_status must be one of ${[...allowedAuth].join(', ')}`);
  assertBoolean(camera.preview_visible, `${context}.preview_visible`);
}

function assertNativeSpeech(speech, context) {
  assertObject(speech, context);
  const allowedASRModes = new Set(['local_vosk', 'dashscope']);
  const allowedAuth = new Set(['authorized', 'denied', 'not_determined', 'restricted', 'unknown']);
  assertString(speech.asr_runtime_mode, `${context}.asr_runtime_mode`);
  assert(allowedASRModes.has(speech.asr_runtime_mode), `${context}.asr_runtime_mode must be one of ${[...allowedASRModes].join(', ')}`);
  assertString(speech.asr_runtime_label, `${context}.asr_runtime_label`);
  assertString(speech.asr_model, `${context}.asr_model`);
  assertString(speech.microphone_authorization_status, `${context}.microphone_authorization_status`);
  assert(allowedAuth.has(speech.microphone_authorization_status), `${context}.microphone_authorization_status must be one of ${[...allowedAuth].join(', ')}`);
  assertBoolean(speech.recording, `${context}.recording`);
  assertBoolean(speech.dashscope_recording, `${context}.dashscope_recording`);
  assertBoolean(speech.local_asr_recording, `${context}.local_asr_recording`);
  assertBoolean(speech.pending_image, `${context}.pending_image`);
  assertBoolean(speech.local_asr_ready, `${context}.local_asr_ready`);
  assertString(speech.local_asr_status_text, `${context}.local_asr_status_text`);
  assertBoolean(speech.local_asr_model_ready, `${context}.local_asr_model_ready`);
  assertBoolean(speech.local_asr_runtime_available, `${context}.local_asr_runtime_available`);
  assertStringValue(speech.local_asr_model_directory, `${context}.local_asr_model_directory`);
}

function assertNativeTTS(tts, context) {
  assertObject(tts, context);
  const allowedTTSModes = new Set(['auto', 'local_mnn', 'system', 'dashscope']);
  assertString(tts.tts_runtime_mode, `${context}.tts_runtime_mode`);
  assert(allowedTTSModes.has(tts.tts_runtime_mode), `${context}.tts_runtime_mode must be one of ${[...allowedTTSModes].join(', ')}`);
  assertString(tts.tts_runtime_label, `${context}.tts_runtime_label`);
  assertString(tts.tts_status_text, `${context}.tts_status_text`);
  assertBoolean(tts.system_speaking, `${context}.system_speaking`);
  assertBoolean(tts.native_audio_playback_active, `${context}.native_audio_playback_active`);
  assertBoolean(tts.dashscope_available, `${context}.dashscope_available`);
  assertBoolean(tts.local_tts_ready, `${context}.local_tts_ready`);
  assertString(tts.local_tts_status_text, `${context}.local_tts_status_text`);
  assertBoolean(tts.local_tts_model_ready, `${context}.local_tts_model_ready`);
  assertBoolean(tts.local_tts_runtime_available, `${context}.local_tts_runtime_available`);
  assertBoolean(tts.local_tts_voice_quality_passed, `${context}.local_tts_voice_quality_passed`);
  assertStringValue(tts.local_tts_model_directory, `${context}.local_tts_model_directory`);
}

function assertOfflinePayload(offline, context) {
  assertObject(offline, context);
  assertBoolean(offline.ready, `${context}.ready`);
  assertBoolean(offline.native_runtime_available, `${context}.native_runtime_available`);
  assertBoolean(offline.directory_readable, `${context}.directory_readable`);
  assertBoolean(offline.text_ready, `${context}.text_ready`);
  assertBoolean(offline.yolo_ready, `${context}.yolo_ready`);
  assertBoolean(offline.vision_ready, `${context}.vision_ready`);
  assertBoolean(offline.text_inference_ready, `${context}.text_inference_ready`);
  assert(Array.isArray(offline.missing), `${context}.missing must be an array`);
  assert(Array.isArray(offline.vision_missing), `${context}.vision_missing must be an array`);
  assert(Array.isArray(offline.text_inference_missing), `${context}.text_inference_missing must be an array`);
  assertString(offline.short_text, `${context}.short_text`);
  assertString(offline.vision_status_text, `${context}.vision_status_text`);
  assertString(offline.text_inference_status_text, `${context}.text_inference_status_text`);
}

function assertMaybeRuns(report, context) {
  if (report.success) {
    assert(Array.isArray(report.runs) && report.runs.length > 0, `${context}.runs must be a non-empty array on success`);
    for (const [index, run] of report.runs.entries()) {
      assertObject(run, `${context}.runs[${index}]`);
      assertString(run.name, `${context}.runs[${index}].name`);
      assertBoolean(run.success, `${context}.runs[${index}].success`);
      assert(Number.isFinite(Number(run.elapsed_ms)), `${context}.runs[${index}].elapsed_ms must be numeric`);
    }
  }
}

function assertASR(report) {
  assertBoolean(report.ready, 'asr.ready');
  assertString(report.status, 'asr.status');
  assertObject(report.local_asr, 'asr.local_asr');
  if (report.audio_file !== undefined) {
    assertObject(report.audio_file, 'asr.audio_file');
  }
  if (report.transcripts !== undefined) {
    assert(Array.isArray(report.transcripts), 'asr.transcripts must be an array');
  }
  assertMaybeRuns(report, 'asr');
  if (requireASRBenchmark) {
    assert(report.success === true, 'asr.success must be true when SILVERCARE_IOS_REQUIRE_ASR_BENCHMARK=1');
    assert(report.ready === true, 'asr.ready must be true when SILVERCARE_IOS_REQUIRE_ASR_BENCHMARK=1');
    assertObject(report.audio_file, 'asr.audio_file');
    assert(report.audio_file.exists === true, 'asr.audio_file.exists must be true');
    assert(report.audio_file.readable === true, 'asr.audio_file.readable must be true');
    assert(Number(report.audio_file.size_bytes) > 0, 'asr.audio_file.size_bytes must be positive');
    assert(Array.isArray(report.runs) && report.runs.length >= 2, 'asr.runs must include cold and warm runs');
    for (const [index, run] of report.runs.entries()) {
      assert(run.success === true, `asr.runs[${index}].success must be true`);
      assertString(run.output_excerpt, `asr.runs[${index}].output_excerpt`);
    }
    assert(Array.isArray(report.transcripts) && report.transcripts.length >= 2, 'asr.transcripts must include cold and warm transcripts');
    for (const [index, transcript] of report.transcripts.entries()) {
      assertString(transcript, `asr.transcripts[${index}]`);
    }
  }
}

function assertOfflineReport(report, test) {
  assertBoolean(report.ready, `${test}.ready`);
  assertString(report.status, `${test}.status`);
  assertOfflinePayload(report.offline, `${test}.offline`);
  if (test === 'vision') {
    assert(report.ready === report.offline.vision_ready, 'vision.ready must match offline.vision_ready');
  }
  if (['text', 'text_suite', 'text_inquiry'].includes(test)) {
    assertBoolean(report.offline.text_inference_ready, `${test}.offline.text_inference_ready`);
    assert(
      report.ready === report.offline.ready,
      `${test}.ready must match offline.ready because this benchmark uses the full offline pipeline gate`
    );
  }
  if (['text', 'text_suite'].includes(test)) {
    assertString(report.text_model, `${test}.text_model`);
    assertString(report.tuning, `${test}.tuning`);
  }
  if (report.ready) {
    assertSuccessfulRuns(report, test);
  } else {
    assert(report.success === false, `${test}.success must be false when not ready`);
    assertString(report.error, `${test}.error`);
    const missing = test === 'vision' ? report.offline.vision_missing : report.offline.missing;
    const statusText = test === 'vision' ? report.offline.vision_status_text : report.offline.short_text;
    assertIncludesAll(report.error, missing, `${test}.error`);
    assert(report.status.includes(statusText), `${test}.status must include ${JSON.stringify(statusText)}`);
  }
  assertMaybeRuns(report, test);
}

function assertTTS(report) {
  assertBoolean(report.ready, 'tts.ready');
  assertBoolean(report.model_ready, 'tts.model_ready');
  assertBoolean(report.runtime_available, 'tts.runtime_available');
  assertBoolean(report.skipped, 'tts.skipped');
  assertBoolean(report.voice_quality_passed, 'tts.voice_quality_passed');
  assertString(report.status, 'tts.status');
  assertObject(report.local_tts, 'tts.local_tts');
  assertString(report.reason, 'tts.reason');
  assert(report.ready === report.local_tts.ready, 'tts.ready must match local_tts.ready');
  assert(report.model_ready === report.local_tts.model_ready, 'tts.model_ready must match local_tts.model_ready');
  assert(report.runtime_available === report.local_tts.runtime_available, 'tts.runtime_available must match local_tts.runtime_available');
  assert(report.voice_quality_passed === report.local_tts.voice_quality_passed, 'tts.voice_quality_passed must match local_tts.voice_quality_passed');
  if (report.ready) {
    assert(
      report.success === true,
      'tts.success must be true once model, runtime, and voice-quality gate all report ready'
    );
    assertSuccessfulRuns(report, 'tts');
    for (const [index, run] of report.runs.entries()) {
      assertObject(run.wav_file, `tts.runs[${index}].wav_file`);
      assert(run.wav_file.exists === true, `tts.runs[${index}].wav_file.exists must be true`);
      assert(run.wav_file.readable === true, `tts.runs[${index}].wav_file.readable must be true`);
      assert(Number(run.wav_file.size_bytes) > 44, `tts.runs[${index}].wav_file.size_bytes must be a real WAV`);
    }
  } else {
    assert(report.success === false, 'tts.success must be false while local TTS is not ready');
    assert(report.skipped === true, 'tts.skipped must be true while local TTS is not ready');
    if (Array.isArray(report.local_tts.missing) && report.local_tts.missing.length > 0) {
      assertIncludesAll(report.error, report.local_tts.missing, 'tts.error');
    } else {
      assert(report.error.includes(report.local_tts.short_text), 'tts.error must include local_tts.short_text');
    }
  }
}

function assertScenario(report) {
  assertString(report.input_dir, 'scenario.input_dir');
  assertObject(report.audio_file, 'scenario.audio_file');
  assertObject(report.image_file, 'scenario.image_file');
  if (report.local_asr_ready !== undefined) assertBoolean(report.local_asr_ready, 'scenario.local_asr_ready');
  if (report.offline_ready !== undefined) assertBoolean(report.offline_ready, 'scenario.offline_ready');
  if (report.asr !== undefined) {
    assertObject(report.asr, 'scenario.asr');
    assertString(report.asr.name, 'scenario.asr.name');
    assertBoolean(report.asr.success, 'scenario.asr.success');
  }
  if (report.vision !== undefined) {
    assertObject(report.vision, 'scenario.vision');
    assertString(report.vision.name, 'scenario.vision.name');
    assertBoolean(report.vision.success, 'scenario.vision.success');
  }
  if (report.transcript !== undefined) assertStringValue(report.transcript, 'scenario.transcript');
  if (report.asr_skipped !== undefined) assertString(report.asr_skipped, 'scenario.asr_skipped');
  if (report.vision_skipped !== undefined) assertString(report.vision_skipped, 'scenario.vision_skipped');
  if (report.pipeline_skipped !== undefined) assertString(report.pipeline_skipped, 'scenario.pipeline_skipped');
  if (requireScenarioFixtures) {
    assert(report.audio_file.exists === true, 'scenario.audio_file.exists must be true');
    assert(report.audio_file.readable === true, 'scenario.audio_file.readable must be true');
    assert(Number(report.audio_file.size_bytes) > 0, 'scenario.audio_file.size_bytes must be positive');
    assert(report.image_file.exists === true, 'scenario.image_file.exists must be true');
    assert(report.image_file.readable === true, 'scenario.image_file.readable must be true');
    assert(Number(report.image_file.size_bytes) > 0, 'scenario.image_file.size_bytes must be positive');
  }
  if (requireScenarioASR) {
    assert(report.local_asr_ready === true, 'scenario.local_asr_ready must be true');
    assertObject(report.asr, 'scenario.asr');
    assert(report.asr.name === 'manual_real_voice_vosk', 'scenario.asr.name must be manual_real_voice_vosk');
    assert(report.asr.success === true, 'scenario.asr.success must be true');
    assertString(report.asr.output_excerpt, 'scenario.asr.output_excerpt');
    assertString(report.transcript, 'scenario.transcript');
  }
  if (report.success) {
    assertObject(report.asr, 'scenario.asr');
    assertObject(report.vision, 'scenario.vision');
    assertBoolean(report.asr.success, 'scenario.asr.success');
    assertBoolean(report.vision.success, 'scenario.vision.success');
  }
}

const summaries = [];
for (const test of tests) {
  const { file, payload } = readReport(test);
  assertBase(test, payload);
  switch (test) {
    case 'status':
      assertStatus(payload);
      break;
    case 'asr':
      assertASR(payload);
      break;
    case 'vision':
    case 'text':
    case 'text_suite':
    case 'text_inquiry':
      assertOfflineReport(payload, test);
      break;
    case 'tts':
      assertTTS(payload);
      break;
    case 'scenario':
      assertScenario(payload);
      break;
    default:
      fail(`unknown benchmark test ${test}`);
  }
  summaries.push(`${test}:${payload.success ? 'ok' : 'failed-with-error'}`);
  console.log(`Checked ${file}`);
}

console.log(`Checked ${tests.length} iOS benchmark report(s): ${summaries.join(', ')}`);
