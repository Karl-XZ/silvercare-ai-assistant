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
    mode: 'nav',
    aiRuntimeMode: 'dashscope',
    runtimeLabel: '联网 DashScope',
    asrRuntimeMode: 'dashscope',
    asrRuntimeLabel: '联网 DashScope',
    navigationRefreshMode: 'manual',
    navigationRefreshLabel: '手动刷新',
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
