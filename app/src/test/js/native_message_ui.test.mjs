import test from 'node:test';
import assert from 'node:assert/strict';

const elements = new Map();

function createElement(id) {
  const classes = new Set();
  const listeners = new Map();
  const element = {
    id,
    textContent: '',
    innerHTML: '',
    className: '',
    scrollTop: 0,
    scrollHeight: 0,
    videoWidth: 0,
    videoHeight: 0,
    style: {},
    dataset: {},
    children: [],
    parentElement: null,
    parentNode: null,
    classList: {
      add: (...names) => names.forEach((name) => classes.add(name)),
      remove: (...names) => names.forEach((name) => classes.delete(name)),
      toggle: (name, force) => {
        const next = force === undefined ? !classes.has(name) : Boolean(force);
        if (next) classes.add(name);
        else classes.delete(name);
        return next;
      },
      contains: (name) => classes.has(name)
    },
    addEventListener(type, handler) {
      listeners.set(type, handler);
    },
    removeEventListener() {},
    dispatchEvent(event = {}) {
      event.target ??= element;
      listeners.get(event.type)?.(event);
      return true;
    },
    click() {
      listeners.get('click')?.({
        preventDefault() {},
        stopPropagation() {},
        currentTarget: element
      });
    },
    querySelector(selector) {
      if (selector === 'span') {
        return element.children.find((child) => child.id === 'span' || child.tagName === 'SPAN') || null;
      }
      return null;
    },
    querySelectorAll() {
      return [];
    },
    matches() {
      return false;
    },
    appendChild(child) {
      child.parentElement = element;
      child.parentNode = element;
      element.children.push(child);
      return child;
    },
    setAttribute(name, value) {
      element[name] = String(value);
    },
    getContext() {
      return {
        drawImage() {},
        getImageData() {
          return { data: new Uint8ClampedArray(4) };
        }
      };
    },
    toDataURL() {
      return 'data:image/jpeg;base64,AA==';
    }
  };
  element.tagName = String(id || '').toUpperCase();
  return element;
}

const body = createElement('body');
const documentElement = createElement('html');

globalThis.document = {
  documentElement,
  body,
  addEventListener() {},
  removeEventListener() {},
  elementFromPoint() {
    return null;
  },
  createElement(tag) {
    return createElement(tag);
  },
  getElementById(id) {
    if (!elements.has(id)) {
      const element = createElement(id);
      element.parentElement = body;
      element.parentNode = body;
      elements.set(id, element);
    }
    return elements.get(id);
  },
  querySelector() {
    return null;
  },
  querySelectorAll() {
    return [];
  }
};

globalThis.window = {
  AndroidSilverCare: {
    isStandalone: () => true,
    isVoiceFirstEnabled: () => false,
    diagnosticEvent() {},
    nativeCameraAvailable: () => true,
    aiRuntimeMode: () => 'dashscope',
    runtimeDisplayName: () => '联网 DashScope',
    offlineModelReady: () => false,
    asrRuntimeMode: () => 'dashscope',
    asrRuntimeDisplayName: () => '联网 DashScope',
    localAsrEnabled: () => false,
    localAsrReady: () => false,
    ttsRuntimeMode: () => 'dashscope',
    ttsRuntimeDisplayName: () => '联网 DashScope',
    ttsStatusText: () => '联网 DashScope TTS 需要先填写 Key。',
    localTtsReady: () => false,
    localTtsModelReady: () => false,
    localTtsRuntimeAvailable: () => false,
    localTtsVoiceQualityPassed: () => false,
    mnnLlmTuningMode: () => 'auto',
    mnnLlmTuningDisplayName: () => '自动',
    mnnSme2Supported: () => false,
    navigationRefreshMode: () => 'auto',
    navigationRefreshDisplayName: () => '自动刷新',
    navigationRefreshIntervalMs: () => 3000,
    smartNavigationRefreshEnabled: () => false,
    captionsEnabled: () => true,
	    hasDashScopeKey: () => false,
	    startCamera() {},
	    stopCamera() {},
	    captureFrame() {},
	    startSpeechInquiry() {},
	    stopSpeechInquiry() {},
	    speak() {}
	  },
  setTimeout(fn, ms) {
    const timer = setTimeout(fn, ms);
    timer.unref?.();
    return timer;
  },
  clearTimeout,
  setInterval() {
    return 0;
  },
  clearInterval() {},
  addEventListener() {},
  removeEventListener() {},
  speechSynthesis: {
    cancel() {},
    speak() {}
  }
};
globalThis.setInterval = globalThis.window.setInterval;
globalThis.clearInterval = globalThis.window.clearInterval;

Object.defineProperty(globalThis, 'navigator', {
  value: { mediaDevices: {} },
  configurable: true
});

globalThis.location = { protocol: 'http:', host: 'localhost' };
globalThis.WebSocket = class {};
globalThis.MouseEvent = class {};

const { STATE } = await import('../../main/assets/static/js/config.js');
const main = await import('../../main/assets/static/js/main.js');
await import('../../main/assets/static/js/network.js');

test('TTS fallback errors stay out of the main feedback overlay', () => {
  elements.get('aiCaption').textContent = 'AI 回复会显示在这里';

  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'error',
    text: '联网 DashScope TTS 需要先填写 DashScope Key。'
  });

  assert.equal(elements.get('mainFeedback').textContent, '');
  assert.equal(elements.get('mainFeedback').classList.contains('visible'), false);
  assert.equal(elements.get('userCaption').textContent, '');
  assert.equal(elements.get('aiCaption').textContent, 'AI 回复会显示在这里');
});

test('TTS fallback errors do not clear active native speech capture', () => {
  const inquiry = elements.get('inquiryCommand');
  const label = createElement('span');
  inquiry.children = [];
  inquiry.appendChild(label);

  window.LONG_TERM_CARE_NATIVE_MESSAGE({ type: 'speech_status', listening: true });
  assert.equal(STATE.speechListening, true);
  assert.equal(inquiry.classList.contains('is-recording'), true);
  assert.equal(label.textContent, '松开发送');

  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'error',
    text: '联网 DashScope TTS 需要先填写 DashScope Key。'
  });

  assert.equal(STATE.speechListening, true);
  assert.equal(inquiry.classList.contains('is-recording'), true);
  assert.equal(label.textContent, '松开发送');

  window.LONG_TERM_CARE_NATIVE_MESSAGE({ type: 'speech_status', listening: false });
});

test('ASR errors still surface in feedback and user captions', () => {
  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'error',
    text: '联网 DashScope ASR 需要先在设置里填写 DashScope Key。'
  });

  assert.equal(elements.get('userCaption').textContent, '未识别到清晰语音，请再试一次。');
  assert.equal(elements.get('aiCaption').textContent, '联网 DashScope ASR 需要先在设置里填写 DashScope Key。');
  assert.equal(elements.get('mainFeedback').classList.contains('visible'), true);
  assert.equal(elements.get('mainFeedback').textContent, '联网 DashScope ASR 需要先在设置里填写 DashScope Key。');
});

test('native speech status and ASR errors restore inquiry button UI', () => {
  const inquiry = elements.get('inquiryCommand');
  const label = createElement('span');
  inquiry.children = [];
  inquiry.appendChild(label);

  window.LONG_TERM_CARE_NATIVE_MESSAGE({ type: 'speech_status', listening: true });
  assert.equal(STATE.speechListening, true);
  assert.equal(inquiry.classList.contains('is-recording'), true);
  assert.equal(label.textContent, '松开发送');

  window.LONG_TERM_CARE_NATIVE_MESSAGE({ type: 'speech_status', listening: false });
  assert.equal(STATE.speechListening, false);
  assert.equal(inquiry.classList.contains('is-recording'), false);
  assert.equal(label.textContent, '按住提问');

  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'speech_status',
    listening: true
  });
  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'error',
    text: '本地语音识别失败：模型未就绪。'
  });

  assert.equal(STATE.speechListening, false);
  assert.equal(inquiry.classList.contains('is-recording'), false);
  assert.equal(label.textContent, '按住提问');
});

test('native fall alarm message updates alarm UI and management risk queue', () => {
  const before = window.LONG_TERM_CARE_GET_MANAGEMENT_DATA().events.length;

  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'fall_alarm',
    text: '已发送跌倒报警，请保持手机在身边。',
    reason: '10 秒内未取消，已发送报警',
    evidence: {
      sensor: { maxAcc: 34.2 },
      visual: { strongChange: true }
    }
  });

  assert.equal(elements.get('fallAlert').classList.contains('visible'), true);
  assert.equal(elements.get('fallAlert').classList.contains('sent'), true);
  assert.equal(elements.get('fallAlert')['aria-hidden'], 'false');
  assert.equal(elements.get('fallTitle').textContent, '已发送报警');
  assert.equal(elements.get('fallCountdown').textContent, '✓');
  assert.equal(elements.get('fallCountdownLabel').textContent, '报警已发送');
  assert.equal(elements.get('fallAlarmButton').disabled, true);
  assert.equal(elements.get('aiCaption').textContent, '已发送跌倒报警，请保持手机在身边。');

  const after = window.LONG_TERM_CARE_GET_MANAGEMENT_DATA();
  assert.equal(after.events.length, before + 1);
  assert.equal(after.events[0].title, '疑似跌倒报警');
  assert.equal(after.events[0].severity, 'high');
  assert.equal(after.events[0].source, '跌倒风险预警');
  assert.equal(after.events[0].evidence.sensor.maxAcc, 34.2);
});

test('native camera loop keeps only one frame in flight', () => {
  let captures = 0;
  window.AndroidSilverCare.captureFrame = () => { captures += 1; };
  STATE.active = true;
  STATE.nativeMode = true;
  STATE.nativeFrameInFlight = false;
  STATE.nativeCameraAvailable = true;
  STATE.navigationRefreshMode = 'auto';
  STATE.speechListening = false;
  STATE.ttsSpeaking = false;

  main.startLoop();
  assert.equal(captures, 1);
  assert.equal(STATE.nativeFrameInFlight, true);

  main.startLoop();
  assert.equal(captures, 1);

  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'result',
    speech: '前方可以通行',
    objects: [],
    direction: 'ahead',
    distance: 2
  });

  assert.equal(STATE.nativeFrameInFlight, false);
  assert.ok(STATE.nativeLastFrameReturnedAt > 0);
  main.startLoop();
  assert.equal(captures, 2);
});

test('native camera running status starts automatic frame capture', () => {
  let captures = 0;
  window.AndroidSilverCare.captureFrame = () => { captures += 1; };
  window.AndroidSilverCare.navigationRefreshMode = () => 'auto';
  window.AndroidSilverCare.navigationRefreshDisplayName = () => '自动刷新';
  window.AndroidSilverCare.nativeCameraStatus = () => 'running';
  window.AndroidSilverCare.nativeCameraRunning = () => true;
  window.AndroidSilverCare.nativeCameraPreviewVisible = () => true;
  window.AndroidSilverCare.hasDashScopeKey = () => true;
  STATE.active = false;
  STATE.nativeMode = false;
  STATE.nativeFrameInFlight = false;
  STATE.navigationRefreshMode = 'auto';
  STATE.speechListening = false;
  STATE.ttsSpeaking = false;

  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'camera_status',
    status: 'running',
    running: true,
    preview_visible: true,
    text: '摄像头已打开'
  });

  assert.equal(captures, 1);
  assert.equal(STATE.nativeFrameInFlight, true);
});

test('manual native navigation tap captures a frame after camera starts', async () => {
  let captures = 0;
  window.AndroidSilverCare.captureFrame = () => { captures += 1; };
  window.AndroidSilverCare.navigationRefreshMode = () => 'manual';
  window.AndroidSilverCare.navigationRefreshDisplayName = () => '手动刷新';
  window.AndroidSilverCare.nativeCameraStatus = () => 'running';
  window.AndroidSilverCare.nativeCameraRunning = () => true;
  window.AndroidSilverCare.nativeCameraPreviewVisible = () => true;
  window.AndroidSilverCare.hasDashScopeKey = () => true;
  STATE.active = false;
  STATE.nativeMode = false;
  STATE.nativeFrameInFlight = false;
  STATE.navigationRefreshMode = 'manual';
  STATE.mode = 'nav';
  STATE.speechListening = false;
  STATE.ttsSpeaking = false;

  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'camera_status',
    status: 'running',
    running: true,
    preview_visible: true,
    text: '摄像头已打开'
  });
  assert.equal(captures, 0);

  body.dispatchEvent({
    type: 'touchstart',
    touches: [{ clientX: 120, clientY: 120 }],
    target: body,
    preventDefault() {}
  });
  body.dispatchEvent({
    type: 'touchend',
    touches: [],
    changedTouches: [{ clientX: 120, clientY: 120 }],
    target: body,
    preventDefault() {}
  });

  await new Promise((resolve) => setTimeout(resolve, 360));

  assert.equal(captures, 1);
  assert.equal(STATE.nativeFrameInFlight, true);
});

test('start navigation calls native camera even before availability snapshot is true', async () => {
  let starts = 0;
  window.AndroidSilverCare.nativeCameraAvailable = () => false;
  window.AndroidSilverCare.startCamera = () => { starts += 1; };
  STATE.active = false;
  STATE.nativeMode = false;
  STATE.nativeCameraStartPending = false;
  STATE.nativeCameraRunning = false;
  STATE.nativeCameraAvailable = false;
  STATE.nativeFrameInFlight = false;
  body.classList.remove('active');

  await main.toggleSystem();

  assert.equal(starts, 1);
  assert.equal(STATE.nativeCameraStartPending, true);
  assert.equal(elements.get('statusText').textContent, '启动相机');

  STATE.nativeCameraStartPending = false;
  window.clearTimeout(STATE.nativeCameraStartTimer);
  STATE.nativeCameraStartTimer = null;
  window.AndroidSilverCare.startCamera = () => {};
  window.AndroidSilverCare.nativeCameraAvailable = () => true;
});

test('native speech inquiry delegates camera capture to iOS when availability snapshot is stale', () => {
  const images = [];
  window.AndroidSilverCare.nativeCameraAvailable = () => false;
  window.AndroidSilverCare.startSpeechInquiry = (imageData) => { images.push(imageData); };
  STATE.active = true;
  STATE.nativeMode = true;
  STATE.nativeCameraAvailable = false;
  STATE.speechListening = false;
  elements.get('mainFeedback').textContent = '';

  elements.get('inquiryCommand').dispatchEvent({
    type: 'pointerdown',
    pointerId: 1,
    preventDefault() {},
    stopPropagation() {}
  });

  assert.deepEqual(images, ['']);
  assert.equal(elements.get('mainFeedback').textContent, '正在聆听...');

  window.LONG_TERM_CARE_NATIVE_SPEECH_DONE();
  elements.get('inquiryCommand').dispatchEvent({
    type: 'pointerup',
    pointerId: 1,
    preventDefault() {},
    stopPropagation() {}
  });
  window.AndroidSilverCare.startSpeechInquiry = () => {};
  window.AndroidSilverCare.nativeCameraAvailable = () => true;
});

test('native camera warming and busy statuses release frame lock', () => {
  STATE.nativeFrameInFlight = true;
  STATE.nativeFrameTimer = window.setTimeout(() => {}, 10000);

  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'camera_status',
    status: 'warming',
    text: '摄像头正在启动，请稍等。',
    running: true,
    available: true,
    hardware_available: true,
    authorization_status: 'authorized',
    error_code: 'no_frame'
  });

  assert.equal(STATE.nativeFrameInFlight, false);
  assert.equal(STATE.nativeFrameTimer, null);
  assert.equal(elements.get('statusText').textContent, '等待相机帧');

  STATE.nativeFrameInFlight = true;
  STATE.nativeFrameTimer = window.setTimeout(() => {}, 10000);
  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'frame_status',
    status: 'busy',
    text: '上一帧仍在分析，已跳过本次刷新。'
  });

  assert.equal(STATE.nativeFrameInFlight, false);
  assert.equal(STATE.nativeFrameTimer, null);
});

test('native frame processor errors release frame lock without shutting down navigation', () => {
  STATE.active = true;
  STATE.nativeFrameInFlight = true;
  STATE.nativeFrameTimer = window.setTimeout(() => {}, 10000);
  STATE.navigationRefreshMode = 'auto';
  body.classList.add('active');

  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'frame_status',
    status: 'error',
    text: '联网 DashScope 需要先填写 Key。'
  });

  assert.equal(STATE.nativeFrameInFlight, false);
  assert.equal(STATE.nativeFrameTimer, null);
  assert.equal(STATE.active, true);
  assert.equal(body.classList.contains('active'), true);
  assert.equal(elements.get('statusText').textContent, '自动刷新');
  assert.equal(elements.get('mainFeedback').textContent, '联网 DashScope 需要先填写 Key。');
});

test('iOS native camera class follows explicit runtime camera availability', () => {
  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'runtime_status',
    ai_runtime_mode: 'dashscope',
    runtime_label: '联网 DashScope',
    native_camera_available: false,
    native_camera_running: false,
    native_camera_preview_visible: false,
    native_camera_hardware_available: false,
    native_camera_status: 'idle',
    captions_enabled: true
  });

  assert.equal(STATE.nativeCameraAvailable, false);
  assert.equal(STATE.nativeCameraPreviewVisible, false);
  assert.equal(documentElement.classList.contains('silvercare-ios-native-camera'), false);

  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'runtime_status',
    ai_runtime_mode: 'dashscope',
    runtime_label: '联网 DashScope',
    native_camera_available: true,
    native_camera_running: true,
    native_camera_preview_visible: true,
    native_camera_hardware_available: true,
    native_camera_status: 'running',
    captions_enabled: true
  });

  assert.equal(STATE.nativeCameraAvailable, true);
  assert.equal(STATE.nativeCameraPreviewVisible, true);
  assert.equal(documentElement.classList.contains('silvercare-ios-native-camera'), true);
});

test('runtime status exposes TTS mode in state and subtitle', () => {
  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'runtime_status',
    ai_runtime_mode: 'offline_mnn',
    runtime_label: '端侧离线 MNN',
    offline_ready: true,
    offline_text_model_label: 'Qwen3-4B',
    asr_runtime_mode: 'local_vosk',
    asr_runtime_label: '本地内置 ASR',
    local_asr_ready: true,
    tts_runtime_mode: 'local_mnn',
    tts_runtime_label: '本地 MNN TTS（实验）',
    tts_status: '本地 MNN TTS Runtime 已绑定，但音质验收未通过',
    local_tts_ready: false,
    local_tts_model_ready: true,
    local_tts_runtime_available: true,
    local_tts_voice_quality_passed: false,
    navigation_refresh_mode: 'manual',
    navigation_refresh_interval_ms: 3000,
    native_camera_available: true,
    native_camera_running: false,
    native_camera_preview_visible: false,
    native_camera_hardware_available: true,
    native_camera_status: 'idle',
    captions_enabled: true
  });

  assert.equal(STATE.ttsRuntimeMode, 'local_mnn');
  assert.equal(STATE.ttsRuntimeLabel, '本地 MNN TTS（实验）');
  assert.equal(STATE.ttsStatusText, '本地 MNN TTS Runtime 已绑定，但音质验收未通过');
  assert.equal(STATE.localTtsReady, false);
  assert.equal(STATE.localTtsModelReady, true);
  assert.equal(STATE.localTtsRuntimeAvailable, true);
  assert.equal(STATE.localTtsVoiceQualityPassed, false);
  assert.match(elements.get('runtimeSubtitle').textContent, /朗读:本地MNN未就绪/);
});

test('manual single tap refresh still works during micro guidance mode', async () => {
  let captures = 0;
  window.AndroidSilverCare.captureFrame = () => { captures += 1; };
  STATE.active = true;
  STATE.nativeMode = true;
  STATE.nativeFrameInFlight = false;
  STATE.nativeCameraAvailable = true;
  STATE.navigationRefreshMode = 'manual';
  STATE.mode = 'micro';
  STATE.speechListening = false;
  STATE.ttsSpeaking = false;

  body.dispatchEvent({
    type: 'touchstart',
    touches: [{ clientX: 100, clientY: 100 }],
    target: body,
    preventDefault() {}
  });
  body.dispatchEvent({
    type: 'touchend',
    touches: [],
    changedTouches: [{ clientX: 100, clientY: 100 }],
    target: body,
    preventDefault() {}
  });

  await new Promise((resolve) => setTimeout(resolve, 360));

  assert.equal(captures, 1);
  assert.equal(STATE.nativeFrameInFlight, true);
  assert.equal(elements.get('statusText').textContent, '刷新引导');
  assert.equal(elements.get('mainFeedback').textContent, '正在刷新精确引导...');
});

test('micro results update guidance UI, spatial tone, and speech throttle', () => {
  const spoken = [];
  const toneUpdates = [];
  const toneEvents = [];
  window.AndroidSilverCare.speak = (text) => spoken.push(text);
  window.spatialAudio = {
    updateMicroTone: (x, y) => toneUpdates.push([x, y]),
    playGeigerClick: (x, y) => toneEvents.push(['geiger', x, y]),
    stopMicroTone: () => toneEvents.push(['stop']),
    playSuccess: () => toneEvents.push(['success'])
  };
  STATE.nativeFrameInFlight = true;
  STATE.nativeFrameTimer = window.setTimeout(() => {}, 10000);
  STATE.lastGeiger = 0;

  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'micro_result',
    x: -24,
    y: 36,
    action: 'move',
    guidance_speech: '手机稍微向左，保持高度不变。',
    ms: 42
  });

  assert.equal(STATE.nativeFrameInFlight, false);
  assert.equal(STATE.nativeFrameTimer, null);
  assert.equal(elements.get('dirVal').textContent, '微调');
  assert.match(elements.get('distVal').innerHTML, /-24,36/);
  assert.equal(elements.get('thinkingBox').textContent, '手机稍微向左，保持高度不变。');
  assert.deepEqual(toneUpdates.at(-1), [-24, 36]);
  assert.deepEqual(spoken, ['手机稍微向左，保持高度不变。']);

  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'micro_result',
    x: -20,
    y: 28,
    action: 'move',
    guidance_speech: '手机稍微向左，保持高度不变。',
    ms: 30
  });
  assert.deepEqual(spoken, ['手机稍微向左，保持高度不变。']);

  window.LONG_TERM_CARE_NATIVE_MESSAGE({
    type: 'micro_result',
    x: 0,
    y: 0,
    action: 'push',
    guidance_speech: '现在按下',
    ms: 18
  });

  assert.equal(elements.get('dirVal').textContent, '按下');
  assert.equal(elements.get('mainFeedback').textContent, '现在按下');
  assert.ok(toneEvents.some((event) => event[0] === 'stop'));
  assert.ok(toneEvents.some((event) => event[0] === 'success'));
  assert.deepEqual(spoken, ['手机稍微向左，保持高度不变。', '现在按下']);
});
