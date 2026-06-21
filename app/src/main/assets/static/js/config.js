/**
 * 银龄智护 - Config & State
 */

export const CONFIG = {
    scanInterval: 3000,
    microInterval: 200,
    imgWidth: 480,
    jpegQuality: 0.4
};

export const STATE = {
    active: false,
    debug: false,
    ws: null,
    nativeMode: false,
    loop: null,
    heading: 0,
    lastShake: 0,
    mode: 'nav',
    aiRuntimeMode: 'offline_mnn',
    runtimeLabel: '端侧离线 MNN',
    asrRuntimeMode: 'local_vosk',
    asrRuntimeLabel: '本地内置 ASR',
    navigationRefreshMode: 'auto',
    navigationRefreshLabel: '自动刷新',
    navigationRefreshIntervalMs: 3000,
    smartNavigationRefreshEnabled: false,
    offlineReady: false,
    localAsrEnabled: false,
    localAsrReady: false,
    captionsEnabled: true,
    ttsSpeaking: false,
    speechListening: false,
    lastGeiger: 0,
    wsRetryCount: 0
};
