/**
 * 银龄智护 - Input Handlers
 * Android gestures, command buttons, device sensors, audio capture, and fall detection.
 */

import { STATE, CONFIG } from './config.js';
import { toggleSystem, checkDebugOverlay, refreshNavigationOnce } from './main.js';
import {
    FALL_DEFAULTS,
    computeVisualEvidence as computeVisualEvidenceCore,
    hasFallImpact,
    isRecoveredFromFall,
    nextBaselineGravity,
    readSensorFromMotion,
    shouldConfirmFall
} from './fall_detector_core.js';
import {
    toggleIntelLayer,
    showFeedback,
    setRecordingUI,
    showFallAlert,
    updateFallCountdown,
    hideFallAlert,
    showFallAlarm,
    speakIfVoiceFirst,
    updateUserCaption,
    updateAiCaption,
    UI
} from './ui.js';
import { sendInquiryData } from './network.js';
import { buildFallCareEvent } from './care_store.js';

const FALL = FALL_DEFAULTS;
const MIN_NATIVE_SPEECH_MS = 850;
const MAX_NATIVE_SPEECH_MS = 15000;
const NATIVE_ASR_RESPONSE_TIMEOUT_MS = 35000;
const NATIVE_AI_RESPONSE_TIMEOUT_MS = 240000;

let tapTime = 0;
let holdTimer = null;
let singleTapTimer = null;
let isHolding = false;
let mediaRecorder = null;
let audioChunks = [];
let recordingIntent = false;
let nativeSpeechActive = false;
let nativeSpeechStartedAt = 0;
let nativeSpeechStopTimer = null;
let nativeSpeechMaxTimer = null;
let nativeSpeechResponseTimer = null;
let nativeSpeechPendingResult = false;
let nativeSpeechTranscriptReceived = false;

let visualCanvas = null;
let visualCtx = null;
let lastVisualData = null;
let visualSamples = [];
let baselineGravity = null;
let currentGravity = null;
let pendingFallProbe = null;
let fallAlertActive = false;
let fallAlertStartedAt = 0;

function notifyNativeSpeechBusy() {
    logDiagnostic('native_speech_busy', {
        active: nativeSpeechActive,
        pending_result: nativeSpeechPendingResult,
        transcript_received: nativeSpeechTranscriptReceived
    });
    showFeedback('上一条语音还在处理，请稍等。', 1600, false);
    updateAiCaption('上一条语音还在处理，请稍等。');
}
let fallAlertEvidence = null;
let fallCountdownTimer = null;
let fallCountdownLeft = FALL.countdownSeconds;
let fallRecoveryStableSince = 0;
let lastFallTriggerAt = 0;

function logDiagnostic(event, data = {}) {
    try {
        if (window.AndroidSilverCare && typeof window.AndroidSilverCare.diagnosticEvent === 'function') {
            window.AndroidSilverCare.diagnosticEvent(event, JSON.stringify(data));
        }
    } catch (error) {
        console.error('Diagnostic event failed:', error);
    }
}

export function setupInputs() {
    setupCommandButtons();
    setupFallActions();
    window.setInterval(sampleVideoFrame, FALL.sampleIntervalMs);
    window.setTimeout(() => {
        speakIfVoiceFirst(
            '银龄智护 已就绪。双击屏幕启动或停止导航。长按屏幕提问。点右上角设置可以切换联网或端侧离线方案，并修改语音优先模式和跌倒检测。',
            { minGapMs: 10000 }
        );
    }, 1200);

    document.body.addEventListener('touchstart', handleTouchStart, { passive: false });
    document.body.addEventListener('touchend', handleTouchEnd);
    document.body.addEventListener('touchcancel', handleTouchEnd);

    window.addEventListener('devicemotion', handleMotion);

    if (window.DeviceOrientationEvent) {
        window.addEventListener('deviceorientation', handleOrientation);
    }
}

function setupCommandButtons() {
    UI.toggleCommand?.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        toggleSystem();
    });

    UI.detailsCommand?.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        toggleIntelLayer();
    });

    UI.closeIntelButton?.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        if (STATE.debug) toggleIntelLayer();
    });

    UI.settingsCommand?.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        openSettings();
    });

    if (UI.inquiryCommand) {
        UI.inquiryCommand.addEventListener('pointerdown', (event) => {
            event.preventDefault();
            event.stopPropagation();
            UI.inquiryCommand.setPointerCapture?.(event.pointerId);
            startRecording();
        });

        UI.inquiryCommand.addEventListener('pointerup', stopButtonRecording);
        UI.inquiryCommand.addEventListener('pointercancel', stopButtonRecording);
        UI.inquiryCommand.addEventListener('lostpointercapture', stopButtonRecording);
        UI.inquiryCommand.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
        });
    }
}

function setupFallActions() {
    UI.fallSafeButton?.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        if (!fallAlertActive) {
            hideFallAlert();
            return;
        }
        cancelFallAlert('已取消报警');
    });

    UI.fallAlarmButton?.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        triggerFallAlarm('用户主动发送报警');
    });
}

function stopButtonRecording(event) {
    event?.preventDefault();
    event?.stopPropagation();
    stopRecording();
}

function openSettings() {
    if (window.AndroidSilverCare && typeof window.AndroidSilverCare.openSettings === 'function') {
        window.AndroidSilverCare.openSettings();
        return;
    }
    if (window.AndroidSilverCare && typeof window.AndroidSilverCare.openKeySettings === 'function') {
        window.AndroidSilverCare.openKeySettings();
        return;
    }
    showFeedback('请在系统菜单中设置');
}

function isInteractiveTarget(target) {
    return !!target?.closest?.('button, input, textarea, select, #intelligence-layer, #console-log, #fallAlert, #careDashboard');
}

function handleTouchStart(e) {
    if (e.touches.length === 3) {
        checkDebugOverlay();
        return;
    }

    if (isInteractiveTarget(e.target)) return;

    const now = Date.now();
    if (now - tapTime < 300) {
        e.preventDefault();
        clearSingleTapTimer();
        if (holdTimer) window.clearTimeout(holdTimer);
        toggleSystem();
        tapTime = 0;
        return;
    }
    tapTime = now;

    isHolding = false;
    holdTimer = window.setTimeout(() => {
        isHolding = true;
        startRecording();
    }, 600);
}

function handleTouchEnd(e) {
    if (isInteractiveTarget(e?.target)) return;
    if (holdTimer) window.clearTimeout(holdTimer);
    if (isHolding) {
        stopRecording();
    } else {
        scheduleManualSingleTapRefresh();
    }
    isHolding = false;
}

function scheduleManualSingleTapRefresh() {
    if (!shouldManualSingleTapRefresh()) return;
    clearSingleTapTimer();
    singleTapTimer = window.setTimeout(() => {
        singleTapTimer = null;
        if (shouldManualSingleTapRefresh()) refreshNavigationOnce();
    }, 320);
}

function clearSingleTapTimer() {
    if (!singleTapTimer) return;
    window.clearTimeout(singleTapTimer);
    singleTapTimer = null;
}

function shouldManualSingleTapRefresh() {
    return STATE.active
        && STATE.navigationRefreshMode === 'manual'
        && STATE.mode !== 'micro'
        && !nativeSpeechActive
        && !nativeSpeechPendingResult
        && !fallAlertActive;
}

function handleMotion(e) {
    const sensor = readSensor(e);
    if (!sensor) return;

    const fallConsumed = processFallMotion(sensor);
    if (fallConsumed) return;

    if (sensor.accDeviation > 20 && Date.now() - STATE.lastShake > 1000) {
        STATE.lastShake = Date.now();
        toggleIntelLayer();
    }
}

function handleOrientation(e) {
    if (Number.isFinite(e.webkitCompassHeading)) {
        STATE.heading = Math.round(e.webkitCompassHeading);
    } else if (Number.isFinite(e.alpha)) {
        STATE.heading = Math.round(360 - e.alpha);
    }

    if (UI.compassVal) UI.compassVal.textContent = `${STATE.heading}°`;
}

function readSensor(e) {
    return readSensorFromMotion(e, Date.now());
}

function processFallMotion(sensor) {
    currentGravity = sensor.gravity;
    updateBaselineGravity(sensor);

    if (!STATE.active || !isFallDetectionEnabled()) return false;

    if (fallAlertActive) {
        monitorFallRecovery(sensor);
        return true;
    }

    const impact = hasFallImpact(sensor, FALL);

    if (pendingFallProbe) {
        pendingFallProbe.maxAcc = Math.max(pendingFallProbe.maxAcc, sensor.accMagnitude);
        pendingFallProbe.maxDeviation = Math.max(pendingFallProbe.maxDeviation, sensor.accDeviation);
        pendingFallProbe.maxRotation = Math.max(pendingFallProbe.maxRotation, sensor.rotationMagnitude);
        return impact;
    }

    if (!impact || Date.now() - lastFallTriggerAt < FALL.cooldownMs) return false;

    pendingFallProbe = {
        startedAt: Date.now(),
        baseline: baselineGravity ? { ...baselineGravity } : null,
        maxAcc: sensor.accMagnitude,
        maxDeviation: sensor.accDeviation,
        maxRotation: sensor.rotationMagnitude
    };

    window.setTimeout(evaluateFallProbe, FALL.probeDelayMs);
    return true;
}

function isFallDetectionEnabled() {
    try {
        if (window.AndroidSilverCare && typeof window.AndroidSilverCare.isFallDetectionEnabled === 'function') {
            return window.AndroidSilverCare.isFallDetectionEnabled();
        }
    } catch (error) {
        console.error('Fall setting read failed:', error);
    }
    return false;
}

function updateBaselineGravity(sensor) {
    baselineGravity = nextBaselineGravity(baselineGravity, sensor, fallAlertActive);
}

function sampleVideoFrame() {
    if (!STATE.active || !isFallDetectionEnabled() || !UI.cam?.videoWidth || !UI.cam?.videoHeight) return;

    if (!visualCanvas) {
        visualCanvas = document.createElement('canvas');
        visualCanvas.width = FALL.sampleWidth;
        visualCanvas.height = FALL.sampleHeight;
        visualCtx = visualCanvas.getContext('2d', { willReadFrequently: true });
    }

    visualCtx.drawImage(UI.cam, 0, 0, FALL.sampleWidth, FALL.sampleHeight);
    const rgba = visualCtx.getImageData(0, 0, FALL.sampleWidth, FALL.sampleHeight).data;
    const gray = new Uint8Array(FALL.sampleWidth * FALL.sampleHeight);
    let brightnessTotal = 0;

    for (let i = 0, p = 0; i < rgba.length; i += 4, p += 1) {
        const lum = Math.round((rgba[i] * 0.299) + (rgba[i + 1] * 0.587) + (rgba[i + 2] * 0.114));
        gray[p] = lum;
        brightnessTotal += lum;
    }

    let diff = 0;
    if (lastVisualData && lastVisualData.length === gray.length) {
        for (let i = 0; i < gray.length; i += 1) {
            diff += Math.abs(gray[i] - lastVisualData[i]);
        }
        diff /= gray.length * 255;
    }

    lastVisualData = gray;
    const now = Date.now();
    visualSamples.push({
        time: now,
        diff,
        brightness: brightnessTotal / (gray.length * 255)
    });

    const cutoff = now - FALL.bufferWindowMs;
    visualSamples = visualSamples.filter((sample) => sample.time >= cutoff);
}

function evaluateFallProbe() {
    const probe = pendingFallProbe;
    pendingFallProbe = null;
    if (!probe || fallAlertActive || !STATE.active || !isFallDetectionEnabled()) return;

    const visual = computeVisualEvidence(FALL.bufferWindowMs);
    if (!shouldConfirmFall(probe, visual, FALL)) return;

    lastFallTriggerAt = Date.now();
    triggerFallAlert({
        sensor: {
            maxAcc: Number(probe.maxAcc.toFixed(1)),
            maxDeviation: Number(probe.maxDeviation.toFixed(1)),
            maxRotation: Math.round(probe.maxRotation)
        },
        visual,
        baseline: probe.baseline
    });
}

function computeVisualEvidence(windowMs) {
    return computeVisualEvidenceCore(visualSamples, windowMs, Date.now(), FALL);
}

function triggerFallAlert(evidence) {
    fallAlertActive = true;
    fallAlertStartedAt = Date.now();
    fallAlertEvidence = evidence;
    fallCountdownLeft = FALL.countdownSeconds;
    fallRecoveryStableSince = 0;

    const message = `检测到手机冲击和最近 ${Math.round(FALL.bufferWindowMs / 1000)} 秒画面剧烈变化。若你没事，请点击“我没事”。`;
    showFallAlert(
        fallCountdownLeft,
        message,
        '摔倒报警触发，请问您摔倒了吗？'
    );

    window.clearInterval(fallCountdownTimer);
    fallCountdownTimer = window.setInterval(() => {
        fallCountdownLeft -= 1;
        updateFallCountdown(fallCountdownLeft);
        if (fallCountdownLeft <= 0) {
            triggerFallAlarm('10 秒内未取消，已发送报警');
        }
    }, 1000);
}

function monitorFallRecovery(sensor) {
    if (!fallAlertEvidence?.baseline || !currentGravity) return;

    const recovered = isRecoveredFromFall(fallAlertEvidence.baseline, currentGravity, sensor, FALL);

    if (!recovered) {
        fallRecoveryStableSince = 0;
        return;
    }

    if (!fallRecoveryStableSince) {
        fallRecoveryStableSince = Date.now();
        return;
    }

    const stableLongEnough = Date.now() - fallRecoveryStableSince >= FALL.recoveryHoldMs;
    const alertVisibleLongEnough = Date.now() - fallAlertStartedAt >= 2200;
    if (stableLongEnough && alertVisibleLongEnough) {
        cancelFallAlert('检测到姿态恢复，已取消报警');
    }
}

function cancelFallAlert(text) {
    if (!fallAlertActive) return;
    fallAlertActive = false;
    fallAlertEvidence = null;
    window.clearInterval(fallCountdownTimer);
    hideFallAlert();
    showFeedback(text);
}

function triggerFallAlarm(reason) {
    if (!fallAlertActive && reason !== '用户主动发送报警') return;
    fallAlertActive = false;
    window.clearInterval(fallCountdownTimer);
    showFallAlarm('已发送报警', false);

    const payload = JSON.stringify({
        reason,
        evidence: fallAlertEvidence,
        triggered_at: new Date().toISOString()
    });
    const careEvent = buildFallCareEvent({ reason, evidence: fallAlertEvidence });
    fallAlertEvidence = null;

    if (window.AndroidSilverCare && typeof window.AndroidSilverCare.triggerFallAlarm === 'function') {
        window.AndroidSilverCare.triggerFallAlarm(payload);
    } else {
        try {
            window.LONG_TERM_CARE_MANAGEMENT_EVENT?.(careEvent);
        } catch (error) {
            console.error('Fall care event report failed:', error);
        }
    }
}

function speak(text) {
    if (!text) return;
    if (window.AndroidSilverCare && typeof window.AndroidSilverCare.speak === 'function') {
        window.AndroidSilverCare.speak(text);
        return;
    }
    if (!window.speechSynthesis) return;
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = 'zh-CN';
    window.speechSynthesis.speak(utterance);
}

function preferredAudioType() {
    const candidates = [
        'audio/webm;codecs=opus',
        'audio/webm',
        'audio/mp4'
    ];

    if (!window.MediaRecorder?.isTypeSupported) return '';
    return candidates.find((type) => MediaRecorder.isTypeSupported(type)) || '';
}

async function startRecording() {
    if (!STATE.active) {
        showFeedback('请先启动导航');
        return;
    }

    if (mediaRecorder && mediaRecorder.state === 'recording') return;
    if (nativeSpeechActive || nativeSpeechPendingResult) {
        notifyNativeSpeechBusy();
        return;
    }

    if (shouldUseNativeSpeechInquiry()) {
        startNativeSpeechInquiry();
        return;
    }

    if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
        showFeedback('当前 WebView 不支持录音');
        return;
    }

    showFeedback('正在聆听...');
    updateUserCaption('正在聆听...');
    updateAiCaption('等待 AI 回复...');
    setRecordingUI(true);
    recordingIntent = true;
    window.speechSynthesis?.cancel?.();
    if (window.spatialAudio) window.spatialAudio.playTone(880, 'sine', 0.1);

    try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
        if (!recordingIntent) {
            stream.getTracks().forEach((track) => track.stop());
            setRecordingUI(false);
            return;
        }

        const mimeType = preferredAudioType();
        mediaRecorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
        audioChunks = [];

        mediaRecorder.ondataavailable = (event) => {
            if (event.data?.size) audioChunks.push(event.data);
        };
        mediaRecorder.onstop = handleRecordingStop;
        mediaRecorder.onerror = () => {
            showFeedback('录音失败');
            setRecordingUI(false);
            stream.getTracks().forEach((track) => track.stop());
        };

        mediaRecorder.start();
    } catch (error) {
        console.error('Microphone Error:', error);
        showFeedback('麦克风被阻止');
        recordingIntent = false;
        setRecordingUI(false);
    }
}

function stopRecording() {
    if (nativeSpeechActive) {
        const elapsed = Date.now() - nativeSpeechStartedAt;
        if (elapsed < MIN_NATIVE_SPEECH_MS) {
            showFeedback('正在收尾...', 700, false);
            window.clearTimeout(nativeSpeechStopTimer);
            nativeSpeechStopTimer = window.setTimeout(stopNativeSpeechInquiry, MIN_NATIVE_SPEECH_MS - elapsed);
        } else {
            stopNativeSpeechInquiry();
        }
        return;
    }

    recordingIntent = false;
    if (!mediaRecorder || mediaRecorder.state !== 'recording') {
        setRecordingUI(false);
        return;
    }

    showFeedback('正在思考...');
    updateUserCaption('语音已提交，正在识别...');
    updateAiCaption('正在思考...');
    if (window.spatialAudio) window.spatialAudio.playTone(440, 'sine', 0.1);
    mediaRecorder.stop();
}

function stopNativeSpeechInquiry() {
    if (!nativeSpeechActive) return;
    logDiagnostic('native_speech_stop', {
        elapsed_ms: Date.now() - nativeSpeechStartedAt
    });
    nativeSpeechActive = false;
    window.clearTimeout(nativeSpeechStopTimer);
    window.clearTimeout(nativeSpeechMaxTimer);
    nativeSpeechStopTimer = null;
    nativeSpeechMaxTimer = null;
    startNativeResponseWatchdog();
    showFeedback('正在思考...');
    updateUserCaption('语音已提交，正在识别...');
    updateAiCaption('正在思考...');
    setRecordingUI(false);
    if (window.AndroidSilverCare && typeof window.AndroidSilverCare.stopSpeechInquiry === 'function') {
        window.AndroidSilverCare.stopSpeechInquiry();
    }
}

function handleRecordingStop() {
    recordingIntent = false;
    setRecordingUI(false);

    const recorder = mediaRecorder;
    mediaRecorder = null;
    recorder?.stream?.getTracks().forEach((track) => track.stop());

    if (!audioChunks.length) {
        showFeedback('没有录到声音');
        return;
    }

    const audioType = recorder?.mimeType || 'audio/webm';
    const blob = new Blob(audioChunks, { type: audioType });
    const reader = new FileReader();

    reader.onloadend = () => {
        const imageData = captureCurrentFrame();
        if (!imageData) {
            showFeedback('画面捕获失败');
            return;
        }
        sendInquiryData(imageData, reader.result);
    };

    reader.readAsDataURL(blob);
}

function shouldUseNativeSpeechInquiry() {
    return STATE.nativeMode
        && window.AndroidSilverCare
        && typeof window.AndroidSilverCare.startSpeechInquiry === 'function';
}

function startNativeSpeechInquiry() {
    if (nativeSpeechPendingResult) {
        notifyNativeSpeechBusy();
        return;
    }
    const imageData = captureCurrentFrame();
    if (!imageData) {
        showFeedback('画面捕获失败');
        return;
    }

    nativeSpeechActive = true;
    nativeSpeechPendingResult = false;
    nativeSpeechTranscriptReceived = false;
    nativeSpeechStartedAt = Date.now();
    logDiagnostic('native_speech_start', {
        image_chars: imageData.length,
        max_recording_ms: MAX_NATIVE_SPEECH_MS,
        asr_timeout_ms: NATIVE_ASR_RESPONSE_TIMEOUT_MS,
        ai_timeout_ms: NATIVE_AI_RESPONSE_TIMEOUT_MS
    });
    window.clearTimeout(nativeSpeechStopTimer);
    window.clearTimeout(nativeSpeechMaxTimer);
    window.clearTimeout(nativeSpeechResponseTimer);
    nativeSpeechStopTimer = null;
    nativeSpeechMaxTimer = window.setTimeout(() => {
        if (nativeSpeechActive) {
            logDiagnostic('native_speech_max_recording', {
                elapsed_ms: Date.now() - nativeSpeechStartedAt
            });
            showFeedback('录音已到最长时间，正在处理...', 1200, false);
            stopNativeSpeechInquiry();
        }
    }, MAX_NATIVE_SPEECH_MS);
    showFeedback('正在聆听...');
    updateUserCaption('正在聆听...');
    updateAiCaption('等待 AI 回复...');
    setRecordingUI(true);
    window.speechSynthesis?.cancel?.();
    if (window.spatialAudio) window.spatialAudio.playTone(880, 'sine', 0.1);
    window.AndroidSilverCare.startSpeechInquiry(imageData);
}

window.LONG_TERM_CARE_NATIVE_SPEECH_DONE = () => {
    logDiagnostic('native_speech_done', {
        active: nativeSpeechActive,
        pending_result: nativeSpeechPendingResult
    });
    nativeSpeechActive = false;
    window.clearTimeout(nativeSpeechStopTimer);
    window.clearTimeout(nativeSpeechMaxTimer);
    nativeSpeechStopTimer = null;
    nativeSpeechMaxTimer = null;
    setRecordingUI(false);
};

window.LONG_TERM_CARE_NATIVE_RESPONSE_DONE = () => {
    logDiagnostic('native_response_done_callback', {
        pending_result: nativeSpeechPendingResult,
        transcript_received: nativeSpeechTranscriptReceived
    });
    clearNativeResponseWatchdog();
};

window.LONG_TERM_CARE_NATIVE_SPEECH_TRANSCRIPT_READY = () => {
    logDiagnostic('native_transcript_ready_callback', {
        pending_result: nativeSpeechPendingResult
    });
    markNativeSpeechTranscriptReady();
};

function startNativeResponseWatchdog() {
    nativeSpeechPendingResult = true;
    nativeSpeechTranscriptReceived = false;
    logDiagnostic('native_response_watchdog_start', {
        asr_timeout_ms: NATIVE_ASR_RESPONSE_TIMEOUT_MS,
        ai_timeout_ms: NATIVE_AI_RESPONSE_TIMEOUT_MS
    });
    window.clearTimeout(nativeSpeechResponseTimer);
    nativeSpeechResponseTimer = window.setTimeout(() => {
        if (!nativeSpeechPendingResult) return;
        logDiagnostic('native_asr_timeout', {
            timeout_ms: NATIVE_ASR_RESPONSE_TIMEOUT_MS,
            transcript_received: nativeSpeechTranscriptReceived
        });
        nativeSpeechPendingResult = false;
        nativeSpeechTranscriptReceived = false;
        setRecordingUI(false);
        updateUserCaption('未识别到清晰语音，请再试一次。');
        updateAiCaption('语音识别超时，请再试一次，或在设置里切换到联网 ASR。');
        showFeedback('语音识别超时', 2600, true);
        if (window.AndroidSilverCare && typeof window.AndroidSilverCare.stopSpeechInquiry === 'function') {
            window.AndroidSilverCare.stopSpeechInquiry();
        }
    }, NATIVE_ASR_RESPONSE_TIMEOUT_MS);
}

function markNativeSpeechTranscriptReady() {
    if (!nativeSpeechPendingResult) return;
    nativeSpeechTranscriptReceived = true;
    logDiagnostic('native_transcript_ready', {
        ai_timeout_ms: NATIVE_AI_RESPONSE_TIMEOUT_MS
    });
    window.clearTimeout(nativeSpeechResponseTimer);
    nativeSpeechResponseTimer = window.setTimeout(() => {
        if (!nativeSpeechPendingResult || !nativeSpeechTranscriptReceived) return;
        logDiagnostic('native_ai_timeout', {
            timeout_ms: NATIVE_AI_RESPONSE_TIMEOUT_MS
        });
        nativeSpeechPendingResult = false;
        nativeSpeechTranscriptReceived = false;
        setRecordingUI(false);
        updateAiCaption('AI 回复超时。语音已经识别成功，但本地模型回复时间过长，请再试一次。');
        showFeedback('AI 回复超时', 2600, true);
    }, NATIVE_AI_RESPONSE_TIMEOUT_MS);
}

function clearNativeResponseWatchdog() {
    logDiagnostic('native_response_watchdog_clear', {
        pending_result: nativeSpeechPendingResult,
        transcript_received: nativeSpeechTranscriptReceived
    });
    nativeSpeechPendingResult = false;
    nativeSpeechTranscriptReceived = false;
    window.clearTimeout(nativeSpeechResponseTimer);
    nativeSpeechResponseTimer = null;
}

function captureCurrentFrame() {
    if (!UI.cam?.videoWidth || !UI.cam?.videoHeight) return '';

    const canvas = document.createElement('canvas');
    const ratio = UI.cam.videoHeight / UI.cam.videoWidth;
    canvas.width = CONFIG.imgWidth;
    canvas.height = Math.round(CONFIG.imgWidth * ratio);

    const ctx = canvas.getContext('2d');
    ctx.drawImage(UI.cam, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL('image/jpeg', 0.6);
}
