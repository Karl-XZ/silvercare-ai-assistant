/**
 * 银龄智护 - Network / Native Bridge Manager
 * In Android standalone mode, frames and inquiries are sent to the Java bridge.
 */

import { STATE } from './config.js';
import {
    UI,
    updateNavUI,
    updateMicroUI,
    updateTaskUI,
    updateInquiryUI,
    updateRuntimeUI,
    updateStatus,
    showFeedback,
    showFallAlarm,
    updateUserCaption,
    updateAiCaption,
    updateModelDownloadPanel,
    setRecordingUI
} from './ui.js';
import { refreshNavigationOnce, startLoop, startMicroLoop } from './main.js';
import {
    buildFallCareEvent,
    buildNavigationCareEvent,
    buildTaskCareEvent
} from './care_store.js';

let lastMicroGuidanceText = '';
let lastMicroGuidanceAt = 0;
let lastReportedCareEventKey = '';
let lastReportedCareEventAt = 0;
let pendingMicroRefreshTimer = null;

function diagnosticExcerpt(value) {
    const text = String(value || '').replace(/\s+/g, ' ').trim();
    return text.length > 160 ? `${text.slice(0, 160)}...` : text;
}

function logDiagnostic(event, data = {}) {
    try {
        if (window.AndroidSilverCare && typeof window.AndroidSilverCare.diagnosticEvent === 'function') {
            window.AndroidSilverCare.diagnosticEvent(event, JSON.stringify(data));
        }
    } catch (error) {
        console.error('Diagnostic event failed:', error);
    }
}

function scheduleFirstMicroRefresh() {
    window.clearTimeout(pendingMicroRefreshTimer);
    pendingMicroRefreshTimer = window.setTimeout(() => {
        pendingMicroRefreshTimer = null;
        if (STATE.active && STATE.mode === 'micro') {
            refreshNavigationOnce();
        }
    }, 800);
}

function hasNativeBridge() {
    return !!(window.AndroidSilverCare && typeof window.AndroidSilverCare.isStandalone === 'function');
}

function handleServerMessage(data) {
    logDiagnostic('native_message_received', {
        type: data?.type || '',
        mode: data?.mode || '',
        text: diagnosticExcerpt(data?.text || data?.speech || data?.thinking || data?.guidance_speech || '')
    });
    // Mode Switching Logic
    if (data.mode && data.mode !== STATE.mode) {
        STATE.mode = data.mode;

        if (STATE.mode === 'micro') {
            showFeedback('精确引导模式');
            if(window.spatialAudio) window.spatialAudio.startMicroTone();
            updateStatus('精确引导', 'active');
            lastMicroGuidanceText = '';
            lastMicroGuidanceAt = 0;
            startMicroLoop();
            scheduleFirstMicroRefresh();
        } else {
            window.clearTimeout(pendingMicroRefreshTimer);
            pendingMicroRefreshTimer = null;
            showFeedback(STATE.mode === 'task' ? '任务模式' : '导航模式');
            if(window.spatialAudio) window.spatialAudio.stopMicroTone();
            updateStatus('扫描中', 'active', { speak: false });
            startLoop();
        }
    }

    handleAudioFeedback(data);

    switch (data.type) {
        case 'result':
            updateNavUI(data);
            updateAiCaption(data.speech || data.guidance_speech || data.thinking || data.scene_description);
            reportNavigationCareEvent(data);
            if (STATE.navigationRefreshMode === 'manual') {
                updateStatus('手动刷新', 'active', { speak: false });
            } else {
                updateStatus('自动刷新', 'active', { speak: false });
            }
            break;
        case 'micro_result':
            updateMicroUI(data);
            updateAiCaption(data.guidance_speech);
            handleMicroGuidanceSpeech(data);
            break;
        case 'task_update':
            updateTaskUI(data);
            updateAiCaption(data.speech || data.visual_feedback);
            reportTaskCareEvent(data);
            break;
        case 'inquiry_result':
            markNativeResponseDone();
            updateInquiryUI(data);
            break;
        case 'runtime_status': updateRuntimeUI(data); break;
        case 'speech_transcript':
            updateUserCaption(data.text || '未识别到清晰语音，请再试一次。');
            if (data.text) {
                markNativeTranscriptReady();
                updateAiCaption('正在思考...');
            }
            break;
        case 'speech_transcript_correction':
            if (data.text) {
                markNativeTranscriptReady();
                const currentUserCaption = UI.userCaption?.textContent?.trim() || '';
                const sourceText = String(data.source_text || '').trim();
                if (!sourceText || currentUserCaption === sourceText) {
                    updateUserCaption(data.text);
                }
            }
            break;
        case 'speech_busy':
            updateAiCaption(data.text || '上一条语音还在处理，请稍等。');
            showFeedback(data.text || '上一条语音还在处理，请稍等。', 1600, false);
            break;
        case 'model_download_progress':
            handleModelDownloadProgress(data);
            break;
        case 'smart_refresh_skipped':
            updateStatus(STATE.navigationRefreshMode === 'manual' ? '手动刷新' : '自动刷新', 'active', { speak: false });
            showFeedback(data.text || '画面无明显变化', 1200, false);
            break;
        case 'speech_status':
            STATE.speechListening = Boolean(data.listening);
            setRecordingUI(STATE.speechListening);
            break;
        case 'fall_alarm':
            updateAiCaption(data.text || '已发送报警');
            showFallAlarm(data.text || '已发送报警', false);
            reportCareEvent(buildFallCareEvent(data));
            break;
        case 'speak':
            markNativeResponseDone();
            updateAiCaption(data.text);
            speak(data.text);
            break;
        case 'error':
            markNativeResponseDone();
            STATE.speechListening = false;
            setRecordingUI(false);
            if (/语音|录音|ASR|识别/.test(data.text || '')) {
                updateUserCaption('未识别到清晰语音，请再试一次。');
            }
            updateAiCaption(data.text || '发生错误');
            showFeedback(data.text || '发生错误');
            break;
    }
}

window.LONG_TERM_CARE_NATIVE_MESSAGE = handleServerMessage;

function markNativeResponseDone() {
    try {
        window.LONG_TERM_CARE_NATIVE_RESPONSE_DONE?.();
    } catch (error) {
        console.error('Native response completion callback failed:', error);
    }
}

function markNativeTranscriptReady() {
    try {
        window.LONG_TERM_CARE_NATIVE_SPEECH_TRANSCRIPT_READY?.();
    } catch (error) {
        console.error('Native transcript callback failed:', error);
    }
}

function reportCareEvent(event) {
    if (!event || !event.title) return;
    try {
        window.LONG_TERM_CARE_MANAGEMENT_EVENT?.(event);
    } catch (error) {
        console.error('Care management event report failed:', error);
    }
}

function reportNavigationCareEvent(data) {
    const event = buildNavigationCareEvent(data);
    if (!event) return;
    const key = `${event.title}|${event.detail}`;
    const now = Date.now();
    if (key === lastReportedCareEventKey && now - lastReportedCareEventAt < 12000) return;
    lastReportedCareEventKey = key;
    lastReportedCareEventAt = now;
    reportCareEvent(event);
}

function reportTaskCareEvent(data) {
    if (!data || data.completed !== true) return;
    reportCareEvent(buildTaskCareEvent({
        title: '任务指导已完成',
        severity: 'low',
        name: '交互式照护任务',
        status: 'done',
        detail: '老人端交互式任务指导已完成，已形成服务留痕。'
    }));
}

function handleModelDownloadProgress(data = {}) {
    updateModelDownloadPanel(data);
    const percent = Number(data.percent);
    const percentText = Number.isFinite(percent) ? `${Math.max(0, Math.min(100, Math.round(percent)))}%` : '';
    if (data.failed) {
        updateStatus('模型下载失败', 'error');
        showFeedback(data.text || '模型下载失败', 2600, true);
        return;
    }
    if (data.complete) {
        updateStatus('离线模型已就绪', 'active');
        showFeedback(data.text || '离线模型已下载完成', 2600, true);
        return;
    }
    updateStatus('模型下载中', 'active');
    showFeedback(data.text ? `${data.text} ${percentText}` : `模型下载 ${percentText}`, 1800, false);
}

export function connectWS() {
    if (!STATE.active) return;

    if (hasNativeBridge()) {
        STATE.nativeMode = true;
        STATE.ws = null;
        const runtimeMode = safeNativeString('aiRuntimeMode', 'offline_mnn');
        const runtimeLabel = safeNativeString('runtimeDisplayName', runtimeMode === 'offline_mnn' ? '端侧离线 MNN' : '联网 DashScope');
        const offlineReady = safeNativeBoolean('offlineModelReady', false);
        updateRuntimeUI({
            ai_runtime_mode: runtimeMode,
            runtime_label: runtimeLabel,
            offline_ready: offlineReady,
            asr_runtime_mode: safeNativeString('asrRuntimeMode', 'local_vosk'),
            asr_runtime_label: safeNativeString('asrRuntimeDisplayName', '本地内置 ASR'),
            local_asr_enabled: safeNativeBoolean('localAsrEnabled', false),
            local_asr_ready: safeNativeBoolean('localAsrReady', false),
            mnn_llm_tuning_mode: safeNativeString('mnnLlmTuningMode', 'auto'),
            mnn_llm_tuning_label: safeNativeString('mnnLlmTuningDisplayName', 'SME2 自动调优'),
            mnn_sme2_supported: safeNativeBoolean('mnnSme2Supported', false),
            navigation_refresh_mode: safeNativeString('navigationRefreshMode', 'auto'),
            navigation_refresh_label: safeNativeString('navigationRefreshDisplayName', '自动刷新'),
            navigation_refresh_interval_ms: safeNativeNumber('navigationRefreshIntervalMs', 3000),
            smart_navigation_refresh_enabled: safeNativeBoolean('smartNavigationRefreshEnabled', false),
            captions_enabled: safeNativeBoolean('captionsEnabled', true)
        });
        updateStatus(runtimeMode === 'offline_mnn' ? '端侧离线' : '本机联网', 'active', { speak: false });
        showFeedback(runtimeMode === 'offline_mnn' ? '端侧离线模式' : '联网 DashScope 模式', 1600, false);

        if (runtimeMode === 'offline_mnn' && !offlineReady) {
            const text = safeNativeString('offlineStatusText', '离线模型未就绪');
            showFeedback(text, 2200, false);
            speak(text);
        } else if (runtimeMode !== 'offline_mnn' && !window.AndroidSilverCare.hasDashScopeKey()) {
            const text = '请先点右上角齿轮填写 DashScope Key';
            showFeedback('需要 Key', 1600, false);
            speak(text);
        }
        startLoop();
        return;
    }

    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${proto}//${location.host}/ws`;

    STATE.ws = new WebSocket(wsUrl);

    STATE.ws.onopen = () => {
        console.log("WebSocket Connected");
        STATE.wsRetryCount = 0;
        updateStatus('扫描中', 'active', { speak: false });
        startLoop();
    };

    STATE.ws.onmessage = async (msg) => {
        try {
            const data = JSON.parse(msg.data);
            handleServerMessage(data);
        } catch (e) {
            console.error("JSON Parse Error:", e);
        }
    };

    STATE.ws.onclose = (e) => {
        console.warn("WebSocket Closed:", e.code);
        if (STATE.active) {
            updateStatus('正在重连...', 'error');
            const retryDelay = Math.min(5000, 1000 * Math.pow(1.5, STATE.wsRetryCount));
            STATE.wsRetryCount++;
            setTimeout(connectWS, retryDelay);
        }
    };

    STATE.ws.onerror = (e) => console.error("WebSocket Error:", e);
}

function safeNativeString(fn, fallback = '') {
    try {
        if (window.AndroidSilverCare && typeof window.AndroidSilverCare[fn] === 'function') {
            return String(window.AndroidSilverCare[fn]() || fallback);
        }
    } catch (error) {
        console.error(`Native bridge ${fn} failed:`, error);
    }
    return fallback;
}

function safeNativeBoolean(fn, fallback = false) {
    try {
        if (window.AndroidSilverCare && typeof window.AndroidSilverCare[fn] === 'function') {
            return Boolean(window.AndroidSilverCare[fn]());
        }
    } catch (error) {
        console.error(`Native bridge ${fn} failed:`, error);
    }
    return fallback;
}

function safeNativeNumber(fn, fallback = 0) {
    try {
        if (window.AndroidSilverCare && typeof window.AndroidSilverCare[fn] === 'function') {
            const value = Number(window.AndroidSilverCare[fn]());
            return Number.isFinite(value) ? value : fallback;
        }
    } catch (error) {
        console.error(`Native bridge ${fn} failed:`, error);
    }
    return fallback;
}

function handleAudioFeedback(data) {
    if (!window.spatialAudio) return;

    if (data.type === 'micro_result') {
        const { x, y, action } = data;
        window.spatialAudio.updateMicroTone(x, y);

        const dist = Math.sqrt(x*x + y*y);
        const maxDist = 140;
        const proximity = 1 - (Math.min(dist, maxDist) / maxDist);
        const now = Date.now();
        if (now - STATE.lastGeiger > (250 - (proximity * 200))) {
            window.spatialAudio.playGeigerClick(x, y);
            STATE.lastGeiger = now;
        }

        if (action === 'push') {
            window.spatialAudio.stopMicroTone();
            window.spatialAudio.playSuccess();
            showFeedback('现在按下', 1600, false);
        }
        return;
    }

    if (data.distance > 0) {
        if (data.target_detected) {
            window.spatialAudio.playTargetLocked(data.direction, data.distance);
        } else {
            window.spatialAudio.playSonar(data.direction, data.distance, data.priority);
        }
    }
}

function handleMicroGuidanceSpeech(data = {}) {
    const text = String(data.guidance_speech || '').trim();
    if (!text) return;
    const now = Date.now();
    const urgent = data.action === 'push' || data.action === 'stop';
    const repeatedTooSoon = text === lastMicroGuidanceText && now - lastMicroGuidanceAt < 1300;
    const changedTooSoon = text !== lastMicroGuidanceText && now - lastMicroGuidanceAt < 800;
    if (!urgent && (repeatedTooSoon || changedTooSoon)) return;

    lastMicroGuidanceText = text;
    lastMicroGuidanceAt = now;
    speak(text);
}

function speak(text) {
    if (!text) return;
    if (hasNativeBridge() && typeof window.AndroidSilverCare.speak === 'function') {
        window.AndroidSilverCare.speak(text);
        return;
    }
    if (!window.speechSynthesis) return;
    STATE.ttsSpeaking = true;
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = 'zh-CN';
    utterance.onend = () => { STATE.ttsSpeaking = false; };
    utterance.onerror = () => { STATE.ttsSpeaking = false; };
    window.speechSynthesis.speak(utterance);
}

export function sendFrame(blob) {
    if (STATE.nativeMode && hasNativeBridge()) {
        const reader = new FileReader();
        reader.onloadend = () => window.AndroidSilverCare.sendFrame(reader.result);
        reader.readAsDataURL(blob);
        return;
    }

    if (STATE.ws && STATE.ws.readyState === WebSocket.OPEN) {
        STATE.ws.send(blob);
    }
}

export function sendInquiryData(imageBlob, audioBase64) {
    if (STATE.nativeMode && hasNativeBridge()) {
        window.AndroidSilverCare.sendInquiryData(imageBlob, audioBase64);
        return;
    }

    if (!STATE.ws || STATE.ws.readyState !== WebSocket.OPEN) return;

    STATE.ws.send(JSON.stringify({
        type: 'inquiry',
        image: imageBlob,
        audio: audioBase64
    }));
}
