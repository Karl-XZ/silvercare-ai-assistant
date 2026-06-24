/**
 * 银龄智护 - Main Entry Point
 * Orchestrates the modules.
 */

import { CONFIG, STATE } from './config.js';
import { UI, showFeedback, updateAiCaption, updateStatus } from './ui.js';
import { connectWS, sendFrame } from './network.js';
import { setupInputs } from './input.js';
import { setupManagementDashboard } from './management.js';

// Initialize Inputs 
// (Wait for DOM load if using <script type="module"> in head, 
// but usually put at end of body. Modules defer by default anyway.)
setupInputs();
setupManagementDashboard();

// Global Access for Debugging
window.LONG_TERM_CARE_ASSISTANT = { STATE, CONFIG, UI };

// --- System Control ---

export async function toggleSystem() {
    if (STATE.active || STATE.nativeCameraStartPending) {
        stopSystem();
    } else {
        await startSystem();
    }
}

async function startSystem() {
    if (window.spatialAudio) window.spatialAudio.init();

    try {
        if (hasStandaloneNativeBridge() && !hasNativeCameraBridge()) {
            STATE.active = false;
            STATE.nativeCameraStartPending = false;
            STATE.nativeCameraRunning = false;
            UI.body.classList.remove('active');
            window.clearTimeout(STATE.nativeCameraStartTimer);
            STATE.nativeCameraStartTimer = null;
            const statusText = safeNativeString('nativeCameraStatusText', '');
            const auth = safeNativeString('nativeCameraAuthorizationStatus', 'unknown');
            const hardwareAvailable = safeNativeBoolean('nativeCameraHardwareAvailable', false);
            const text = statusText
                || (!hardwareAvailable ? '没有找到可用摄像头' : (auth === 'denied' || auth === 'restricted' ? '摄像头权限未开启' : '摄像头不可用'));
            showFeedback(text, 2600, true);
            updateAiCaption(text);
            updateStatus('摄像头错误', 'error', { speak: false });
            return;
        }

        if (hasNativeCameraBridge()) {
            STATE.nativeCameraStartPending = true;
            STATE.nativeCameraRunning = false;
            window.clearTimeout(STATE.nativeCameraStartTimer);
            STATE.nativeCameraStartTimer = window.setTimeout(() => {
                if (!STATE.nativeCameraStartPending || STATE.nativeCameraRunning) return;
                STATE.nativeCameraStartPending = false;
                STATE.active = false;
                UI.body.classList.remove('active');
                updateStatus('摄像头无响应', 'error', { speak: false });
                showFeedback('摄像头启动无响应，请检查权限', 2600, true);
                try {
                    window.AndroidSilverCare.stopCamera?.();
                } catch (error) {
                    console.error('Native camera stop after timeout failed:', error);
                }
            }, 8000);
            showFeedback('正在打开摄像头...', 1200, false);
            updateStatus('启动相机', 'active', { speak: false });
            window.AndroidSilverCare.startCamera();
            return;
        }

        const stream = await navigator.mediaDevices.getUserMedia({
            video: { 
                facingMode: { ideal: 'environment' }, 
                width: { ideal: 1280 } 
            }
        });
        
        UI.cam.srcObject = stream;
        await new Promise(resolve => UI.cam.onloadedmetadata = resolve);
        
        STATE.active = true;
        UI.body.classList.add('active');

        showFeedback('银龄智护 已启动');
        updateStatus('连接中...', 'active');

        connectWS();

    } catch (e) {
        console.error("Camera Error:", e);
        showFeedback('摄像头错误');
        updateStatus('摄像头错误', 'error');
    }
}

function stopSystem() {
    STATE.active = false;
    STATE.nativeCameraStartPending = false;
    STATE.nativeCameraRunning = false;
    window.clearTimeout(STATE.nativeCameraStartTimer);
    STATE.nativeCameraStartTimer = null;
    STATE.nativeFrameInFlight = false;
    window.clearTimeout(STATE.nativeFrameTimer);
    STATE.nativeFrameTimer = null;
    STATE.mode = 'nav';
    STATE.wsRetryCount = 0;
    
    if (window.spatialAudio) window.spatialAudio.stopMicroTone();
    UI.body.classList.remove('active');

    // Close WS
    if (STATE.ws) {
        STATE.ws.onclose = null;
        STATE.ws.close();
        STATE.ws = null;
    }
    
    // Stop Loop
    stopLoop();

    // Stop Camera
    if (hasNativeCameraBridge()) {
        window.AndroidSilverCare.stopCamera();
    } else if (UI.cam.srcObject) {
        UI.cam.srcObject.getTracks().forEach(track => track.stop());
        UI.cam.srcObject = null;
    }

    showFeedback('已停止');
    updateStatus('就绪', '');
}

// --- Loop Logic ---

export function startLoop() {
    if (STATE.loop) clearInterval(STATE.loop);
    STATE.loop = null;
    if (manualFrameRefreshEnabled()) {
        updateStatus('手动刷新', 'active', { speak: false });
        showFeedback('手动模式：单击屏幕刷新', 1600, false);
        return;
    }
    updateStatus('自动刷新', 'active', { speak: false });
    tick({ force: true });
    STATE.loop = setInterval(() => tick({ auto: true }), CONFIG.scanInterval);
}

export function startMicroLoop() {
    if (STATE.loop) clearInterval(STATE.loop);
    STATE.loop = null;
    if (manualFrameRefreshEnabled()) {
        updateStatus('手动引导', 'active', { speak: false });
        showFeedback('手动模式：单击屏幕刷新精确引导', 1600, false);
        return;
    }
    updateStatus('精确引导', 'active', { speak: false });
    tick({ force: true });
    STATE.loop = setInterval(() => tick({ auto: true }), CONFIG.scanInterval);
}

function stopLoop() {
    if (STATE.loop) clearInterval(STATE.loop);
    STATE.loop = null;
}

export function refreshNavigationOnce() {
    if (!STATE.active) {
        showFeedback('请先启动导航');
        return;
    }
    if (STATE.mode === 'micro') {
        showFeedback('正在刷新精确引导...', 900, false);
        updateStatus('刷新引导', 'active', { speak: false });
        tick({ force: true });
        return;
    }
    showFeedback('正在刷新导航...', 900, false);
    updateStatus('刷新中', 'active', { speak: false });
    tick({ force: true });
}

function manualFrameRefreshEnabled() {
    return STATE.navigationRefreshMode === 'manual';
}

function tick(options = {}) {
    if (!STATE.active) return;
    if (!STATE.nativeMode && (!STATE.ws || STATE.ws.readyState !== WebSocket.OPEN)) return;
    if (options.auto && STATE.speechListening) return;
    if (options.auto && STATE.ttsSpeaking) return;
    if (hasNativeCameraBridge()) {
        if (STATE.nativeFrameInFlight) return;
        STATE.nativeFrameInFlight = true;
        window.clearTimeout(STATE.nativeFrameTimer);
        STATE.nativeFrameTimer = window.setTimeout(() => {
            if (!STATE.nativeFrameInFlight) return;
            STATE.nativeFrameInFlight = false;
            updateStatus(STATE.navigationRefreshMode === 'manual' ? '手动刷新' : '等待相机帧', 'active', { speak: false });
        }, Math.max(CONFIG.scanInterval * 2, 6000));
        window.AndroidSilverCare.captureFrame();
        return;
    }
    if (!UI.cam?.videoWidth || !UI.cam?.videoHeight) return;

    const cvs = document.createElement('canvas');
    const ratio = UI.cam.videoHeight / UI.cam.videoWidth;
    cvs.width = CONFIG.imgWidth;
    cvs.height = Math.round(CONFIG.imgWidth * ratio);

    const ctx = cvs.getContext('2d');
    ctx.drawImage(UI.cam, 0, 0, cvs.width, cvs.height);

    cvs.toBlob(blob => {
        sendFrame(blob);
    }, 'image/jpeg', CONFIG.jpegQuality);
}

function hasNativeCameraBridge() {
    return !!(window.AndroidSilverCare
        && typeof window.AndroidSilverCare.startCamera === 'function'
        && typeof window.AndroidSilverCare.stopCamera === 'function'
        && typeof window.AndroidSilverCare.captureFrame === 'function');
}

function hasStandaloneNativeBridge() {
    try {
        return !!(window.AndroidSilverCare && typeof window.AndroidSilverCare.isStandalone === 'function' && window.AndroidSilverCare.isStandalone());
    } catch (error) {
        console.error('Native standalone bridge check failed:', error);
        return false;
    }
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

window.LONG_TERM_CARE_TTS_STATE_CHANGED = (speaking) => {
    STATE.ttsSpeaking = Boolean(speaking);
};

// --- Debug Overlay ---
export function checkDebugOverlay() { 
    const box = document.getElementById('console-log');
    if (box) box.classList.toggle('visible'); 
}

// --- On-Screen Console Setup ---
(function setupConsole() {
    const box = document.getElementById('console-log');
    if (!box) return;

    const _log = console.log;
    const _err = console.error;
    
    const addItem = (msg, type) => {
        const div = document.createElement('div');
        div.className = `log-entry log-${type}`;
        div.textContent = `[${type.toUpperCase()}] ${msg}`;
        box.appendChild(div);
        box.scrollTop = box.scrollHeight;
    };

    console.log = (...args) => { _log(...args); addItem(args.join(' '), 'info'); };
    console.error = (...args) => { _err(...args); addItem(args.join(' '), 'error'); };
})();

window.LONG_TERM_CARE_REFRESH_MODE_CHANGED = (mode) => {
    STATE.navigationRefreshMode = mode === 'manual' ? 'manual' : 'auto';
    STATE.navigationRefreshLabel = STATE.navigationRefreshMode === 'manual' ? '手动刷新' : '自动刷新';
    if (STATE.active) {
        if (STATE.mode === 'micro') startMicroLoop();
        else startLoop();
    } else {
        updateStatus(STATE.navigationRefreshLabel, '', { speak: false });
    }
};

window.LONG_TERM_CARE_REFRESH_SETTINGS_CHANGED = (mode, intervalMs, smartRefresh) => {
    STATE.navigationRefreshMode = mode === 'manual' ? 'manual' : 'auto';
    STATE.navigationRefreshLabel = STATE.navigationRefreshMode === 'manual' ? '手动刷新' : '自动刷新';
    const nextInterval = Number(intervalMs);
    if (Number.isFinite(nextInterval)) {
        CONFIG.scanInterval = Math.max(1000, Math.min(10000, nextInterval));
        STATE.navigationRefreshIntervalMs = CONFIG.scanInterval;
    }
    STATE.smartNavigationRefreshEnabled = Boolean(smartRefresh);
    if (STATE.active) {
        if (STATE.mode === 'micro') startMicroLoop();
        else startLoop();
    } else {
        updateStatus(STATE.navigationRefreshLabel, '', { speak: false });
    }
};
