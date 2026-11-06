import { t, I18n } from './i18n.js';
/**
 * 银龄智护 - Android UI Manager
 * Owns DOM references, status presentation, and mode-specific view updates.
 */

import { CONFIG, STATE } from './config.js';

export const UI = {
    cam: document.getElementById('cam'),
    body: document.body,
    announcer: document.getElementById('a11y-announcer'),

    statusPill: document.getElementById('statusPill'),
    statusDot: document.getElementById('statusDot'),
    statusText: document.getElementById('statusText'),
    runtimeSubtitle: document.getElementById('runtimeSubtitle'),
    searchBanner: document.getElementById('searchBanner'),
    mainFeedback: document.getElementById('mainFeedback'),
    captionPanel: document.getElementById('captionPanel'),
    userCaption: document.getElementById('userCaption'),
    aiCaption: document.getElementById('aiCaption'),
    modelDownloadPanel: document.getElementById('modelDownloadPanel'),
    modelDownloadTitle: document.getElementById('modelDownloadTitle'),
    modelDownloadPercent: document.getElementById('modelDownloadPercent'),
    modelDownloadBar: document.getElementById('modelDownloadBar'),
    modelDownloadText: document.getElementById('modelDownloadText'),
    modelDownloadBytes: document.getElementById('modelDownloadBytes'),

    taskHud: document.getElementById('task-hud'),
    taskList: document.getElementById('taskList'),
    taskFeedback: document.getElementById('taskFeedback'),

    intelLayer: document.getElementById('intelligence-layer'),
    thinkingBox: document.getElementById('thinkingBox'),
    socialCue: document.getElementById('socialCue'),
    envCue: document.getElementById('envCue'),
    objList: document.getElementById('objList'),
    objCount: document.getElementById('objCount'),
    compassVal: document.getElementById('compassVal'),

    distVal: document.getElementById('distVal'),
    dirVal: document.getElementById('dirVal'),
    latVal: document.getElementById('latVal'),

    toggleCommand: document.getElementById('toggleCommand'),
    inquiryCommand: document.getElementById('inquiryCommand'),
    detailsCommand: document.getElementById('detailsCommand'),
    closeIntelButton: document.getElementById('closeIntelButton'),
    settingsCommand: document.getElementById('settingsCommand'),

    fallAlert: document.getElementById('fallAlert'),
    fallTitle: document.getElementById('fallTitle'),
    fallMessage: document.getElementById('fallMessage'),
    fallCountdown: document.getElementById('fallCountdown'),
    fallCountdownLabel: document.getElementById('fallCountdownLabel'),
    fallSafeButton: document.getElementById('fallSafeButton'),
    fallAlarmButton: document.getElementById('fallAlarmButton')
};

let feedbackTimer = null;
let modelDownloadHideTimer = null;
let lastStatusText = '';
let lastSpokenText = '';
let lastSpokenAt = 0;

function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function setText(el, text) {
    if (el) {
        el.removeAttribute?.('data-i18n');
        el.textContent = text;
    }
}

function setHtml(el, html) {
    if (el) el.innerHTML = html;
}

function announce(text) {
    if (UI.announcer) UI.announcer.textContent = text;
}

function formatBytes(bytes) {
    const number = Number(bytes);
    if (!Number.isFinite(number) || number <= 0) return '--';
    const units = ['B', 'KB', 'MB', 'GB'];
    let value = number;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
        value /= 1024;
        unit += 1;
    }
    return `${value.toFixed(unit === 0 ? 0 : 1)}${units[unit]}`;
}

export function updateModelDownloadPanel(data = {}) {
    if (!UI.modelDownloadPanel) return;

    window.clearTimeout(modelDownloadHideTimer);
    const rawPercent = Number(data.percent);
    const percent = Number.isFinite(rawPercent)
        ? Math.max(0, Math.min(100, Math.round(rawPercent)))
        : 0;
    const failed = Boolean(data.failed);
    const complete = Boolean(data.complete);
    const title = failed ? t("模型下载失败") : (complete ? t("模型下载完成") : t("模型下载中"));
    const text = String(data.text || title);

    UI.modelDownloadPanel.classList.add('visible');
    UI.modelDownloadPanel.classList.toggle('failed', failed);
    UI.modelDownloadPanel.classList.toggle('complete', complete);
    UI.modelDownloadPanel.setAttribute('aria-hidden', 'false');
    setText(UI.modelDownloadTitle, title);
    setText(UI.modelDownloadPercent, `${percent}%`);
    setText(UI.modelDownloadText, text);
    setText(
        UI.modelDownloadBytes,
        `${formatBytes(data.downloaded_bytes)} / ${formatBytes(data.total_bytes)}`
    );
    if (UI.modelDownloadBar) UI.modelDownloadBar.style.width = `${percent}%`;
    announce(`${title}，${percent}%`);

    if (complete || failed) {
        modelDownloadHideTimer = window.setTimeout(() => {
            UI.modelDownloadPanel?.classList.remove('visible');
            UI.modelDownloadPanel?.setAttribute('aria-hidden', 'true');
        }, failed ? 9000 : 6000);
    }
}

export function voiceFirstEnabled() {
    try {
        if (window.AndroidSilverCare && typeof window.AndroidSilverCare.isVoiceFirstEnabled === 'function') {
            return window.AndroidSilverCare.isVoiceFirstEnabled();
        }
    } catch (error) {
        console.error('Voice-first setting read failed:', error);
    }
    return true;
}

export function speakText(text, interrupt = true) {
    if (!text) return;
    if (window.AndroidSilverCare && typeof window.AndroidSilverCare.speak === 'function') {
        window.AndroidSilverCare.speak(text);
        return;
    }

    if (!window.speechSynthesis) return;
    if (interrupt) window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = I18n.locale();
    window.speechSynthesis.speak(utterance);
}

export function speakIfVoiceFirst(text, options = {}) {
    if (!voiceFirstEnabled() || !text) return false;

    const minGapMs = options.minGapMs ?? 900;
    const now = Date.now();
    if (text === lastSpokenText && now - lastSpokenAt < minGapMs) return false;

    lastSpokenText = text;
    lastSpokenAt = now;
    speakText(text, options.interrupt ?? true);
    return true;
}

export function updateUserCaption(text) {
    const clean = String(text || '').trim();
    if (!clean || !UI.userCaption) return;
    setText(UI.userCaption, clean);
    if (captionsEnabled()) announce(t("我说：{0}", [clean]));
}

export function updateAiCaption(text) {
    const clean = String(text || '').trim();
    if (!clean || !UI.aiCaption) return;
    setText(UI.aiCaption, clean);
    if (captionsEnabled()) announce(t("银龄智护：{0}", [clean]));
}

export function captionsEnabled() {
    return STATE.captionsEnabled !== false;
}

export function setCaptionVisibility(enabled) {
    STATE.captionsEnabled = enabled !== false;
    if (!UI.captionPanel) return;
    UI.captionPanel.classList.toggle('is-hidden', !STATE.captionsEnabled);
    UI.captionPanel.setAttribute('aria-hidden', String(!STATE.captionsEnabled));
}

function metric(value, unit = '') {
    if (value === null || value === undefined || value === '' || Number.isNaN(value)) return '--';
    return `${escapeHtml(value)}${unit ? `<small>${escapeHtml(unit)}</small>` : ''}`;
}

function formatDistance(distance) {
    const num = Number(distance);
    if (!Number.isFinite(num)) return '--';
    if (num < 1) return metric(Math.max(0, Math.round(num * 100)), t("厘米"));
    return metric(num.toFixed(1), t("米"));
}

function formatDirection(direction) {
    const value = String(direction || '').trim().toLowerCase();
    if (!value) return '--';
    const map = {
        ahead: t("正前方"),
        left: t("左侧"),
        right: t("右侧"),
        behind: t("后方"),
        unknown: t("未知"),
        nearby: t("附近")
    };
    return map[value] || String(direction);
}

function formatObjectName(name) {
    const raw = String(name || '').trim();
    if (!raw) return t("未知物体");
    const key = raw.toLowerCase().replace(/_/g, ' ');
    const map = {
        person: t("人"),
        bicycle: t("自行车"),
        car: t("汽车"),
        motorcycle: t("摩托车"),
        bus: t("公交车"),
        truck: t("卡车"),
        backpack: t("背包"),
        handbag: t("手提包"),
        suitcase: t("行李箱"),
        bottle: t("瓶子"),
        cup: t("杯子"),
        bowl: t("碗"),
        chair: t("椅子"),
        couch: t("沙发"),
        sofa: t("沙发"),
        bed: t("床"),
        'dining table': t("桌子"),
        table: t("桌子"),
        toilet: t("马桶"),
        tv: t("电视"),
        tvmonitor: t("电视"),
        laptop: t("笔记本电脑"),
        remote: t("遥控器"),
        keyboard: t("键盘"),
        'cell phone': t("手机"),
        phone: t("手机"),
        sink: t("水槽"),
        refrigerator: t("冰箱"),
        book: t("书"),
        door: t("门"),
        mat: t("地垫"),
        rug: t("地毯"),
        box: t("箱子"),
        cable: t("电线"),
        wire: t("电线"),
        'power strip': t("插排"),
        socket: t("插座"),
        outlet: t("插座")
    };
    if (map[key]) return map[key];
    return t(raw);
}

function formatLatency(ms) {
    const num = Number(ms);
    if (!Number.isFinite(num)) return '--';
    return metric(Math.round(num), 'ms');
}

function syncCommandState() {
    if (UI.toggleCommand) {
        UI.toggleCommand.classList.toggle('is-active', STATE.active);
        UI.toggleCommand.setAttribute('aria-pressed', String(STATE.active));
        const label = UI.toggleCommand.querySelector('span');
        if (label) label.textContent = STATE.active ? t("停止导航") : t("启动导航");
    }

    if (UI.detailsCommand) {
        UI.detailsCommand.classList.toggle('is-active', STATE.debug);
        UI.detailsCommand.setAttribute('aria-pressed', String(STATE.debug));
        const label = UI.detailsCommand.querySelector('span');
        if (label) label.textContent = STATE.debug ? t("隐藏详情") : t("查看详情");
    }
}

function renderCue(el, label, value) {
    if (!el) return;
    if (!value) {
        el.classList.remove('visible');
        el.textContent = '';
        return;
    }

    el.classList.add('visible');
    el.innerHTML = `<b>${escapeHtml(label)}：</b>${escapeHtml(value)}`;
}

function renderObjects(objects = []) {
    const items = Array.isArray(objects) ? objects : [];
    setText(UI.objCount, String(items.length));

    if (!UI.objList) return;
    if (!items.length) {
        UI.objList.innerHTML = t("<div class=\"obj-empty\">未检测到明确对象，正在持续扫描</div>");
        return;
    }

    UI.objList.innerHTML = items.map((obj) => {
        const name = escapeHtml(formatObjectName(obj?.name || obj?.subject || t("未知对象")));
        const distance = Number(obj?.distance);
        const distanceText = Number.isFinite(distance) ? t("{0}米", [distance.toFixed(1)]) : '--';
        const isNear = Number.isFinite(distance) && distance < 1;
        return `
            <div class="obj-item" role="listitem">
                <span>${name}</span>
                <span class="obj-dist ${isNear ? 'near' : ''}">${escapeHtml(distanceText)}</span>
            </div>`;
    }).join('');
}

function updateSearchBanner(goal) {
    const cleanGoal = goal && goal !== 'null' ? String(goal) : '';
    if (!UI.searchBanner) return;

    if (cleanGoal) {
        UI.searchBanner.classList.add('visible');
        UI.searchBanner.textContent = t("目标：{0}", [cleanGoal]);
    } else {
        UI.searchBanner.classList.remove('visible');
    }
}

export function showFeedback(text, duration = 1600, speak = true) {
    if (!text || !UI.mainFeedback) return;

    window.clearTimeout(feedbackTimer);
    UI.mainFeedback.textContent = text;
    UI.mainFeedback.classList.add('visible');
    announce(text);
    if (speak) speakIfVoiceFirst(text);

    feedbackTimer = window.setTimeout(() => {
        UI.mainFeedback?.classList.remove('visible');
    }, duration);
}

export function updateStatus(text, stateClass = '', options = {}) {
    setText(UI.statusText, text);
    if (UI.statusDot) UI.statusDot.className = `status-dot ${stateClass}`.trim();
    if (UI.statusPill) UI.statusPill.dataset.state = stateClass || 'idle';
    if (text && text !== lastStatusText && options.speak !== false) {
        lastStatusText = text;
        speakIfVoiceFirst(t("状态：{0}", [text]), { minGapMs: 2500 });
    } else if (text) {
        lastStatusText = text;
    }
    syncCommandState();
}

export function updateRuntimeUI(data = {}) {
    if (data.app_language && data.app_language !== I18n.language()) {
        window.LONG_TERM_CARE_LANGUAGE_CHANGED(data.app_language);
        return;
    }
    const mode = data.ai_runtime_mode || data.mode || STATE.aiRuntimeMode || 'dashscope';
    const label = data.runtime_label || (mode === 'offline_mnn' ? t("端侧离线 MNN") : t("联网 DashScope"));
    STATE.aiRuntimeMode = mode;
    STATE.runtimeLabel = label;
    STATE.offlineReady = Boolean(data.offline_ready);
    STATE.asrRuntimeMode = data.asr_runtime_mode || (data.local_asr_enabled ? 'local_sensevoice' : 'dashscope');
    STATE.asrRuntimeLabel = data.asr_runtime_label || (STATE.asrRuntimeMode === 'local_sensevoice' ? t("本地 SenseVoice") : t("联网 DashScope"));
    STATE.localAsrEnabled = STATE.asrRuntimeMode === 'local_sensevoice';
    STATE.localAsrReady = Boolean(data.local_asr_ready);
    STATE.mnnLlmTuningLabel = data.mnn_llm_tuning_label || STATE.mnnLlmTuningLabel || t("SME2 自动调优");
    STATE.mnnSme2Supported = Boolean(data.mnn_sme2_supported);
    STATE.navigationRefreshMode = data.navigation_refresh_mode || STATE.navigationRefreshMode || 'manual';
    STATE.navigationRefreshLabel = data.navigation_refresh_label || (STATE.navigationRefreshMode === 'manual' ? t("手动刷新") : t("自动刷新"));
    const intervalMs = Number(data.navigation_refresh_interval_ms);
    if (Number.isFinite(intervalMs)) {
        CONFIG.scanInterval = Math.max(1000, Math.min(10000, intervalMs));
        STATE.navigationRefreshIntervalMs = CONFIG.scanInterval;
    }
    STATE.smartNavigationRefreshEnabled = Boolean(data.smart_navigation_refresh_enabled);
    setCaptionVisibility(data.captions_enabled !== false);

    const offlineLabel = data.offline_text_model_label || t("Qwen 文本模型");
    const asrLabel = STATE.asrRuntimeMode === 'local_sensevoice'
        ? (STATE.localAsrReady ? t(" · 本地SenseVoice") : t(" · 本地SenseVoice未就绪"))
        : t(" · 联网ASR");
    const tuningLabel = mode === 'offline_mnn'
        ? ` · ${STATE.mnnLlmTuningLabel}${STATE.mnnSme2Supported ? '' : t("（回退）")}`
        : '';
    const refreshLabel = STATE.navigationRefreshMode === 'manual'
        ? t(" · 手动刷新")
        : t(" · {0}秒刷新", [Math.round((STATE.navigationRefreshIntervalMs || CONFIG.scanInterval) / 1000)]);
    const smartLabel = STATE.smartNavigationRefreshEnabled ? t(" · 智能刷新") : '';
    const subtitle = mode === 'offline_mnn'
        ? (STATE.offlineReady ? t("银龄智护端侧智能照护版 · 端侧离线 · {0}{1}{2}{3}{4}", [offlineLabel, tuningLabel, asrLabel, refreshLabel, smartLabel]) : t("银龄智护端侧智能照护版 · 端侧离线未就绪 · {0}{1}{2}{3}", [offlineLabel, tuningLabel, refreshLabel, smartLabel]))
        : t("银龄智护端侧智能照护版 · 联网 DashScope 模式{0}{1}{2}", [asrLabel, refreshLabel, smartLabel]);
    setText(UI.runtimeSubtitle, subtitle);
}

export function showFallAlert(seconds, message, speechPrompt) {
    if (!UI.fallAlert) return;
    UI.fallAlert.classList.remove('sent');
    setText(UI.fallTitle, t("疑似摔倒"));
    setText(UI.fallMessage, message || t("摔倒报警触发，请问您摔倒了吗？若没有摔倒，请点击“我没事”。"));
    setText(UI.fallCountdown, String(seconds));
    setText(UI.fallCountdownLabel, t("秒后发送报警"));
    if (UI.fallSafeButton) {
        UI.fallSafeButton.textContent = t("我没事");
        UI.fallSafeButton.disabled = false;
    }
    if (UI.fallAlarmButton) {
        UI.fallAlarmButton.textContent = t("立即发送报警");
        UI.fallAlarmButton.disabled = false;
    }
    UI.fallAlert.classList.add('visible');
    UI.fallAlert.setAttribute('aria-hidden', 'false');
    announce(t("检测到疑似摔倒"));
    const prompt = speechPrompt || t("摔倒报警触发，请问您摔倒了吗？");
    updateAiCaption(prompt);
    speakText(prompt, true);
}

export function updateFallCountdown(seconds) {
    setText(UI.fallCountdown, String(Math.max(0, seconds)));
}

export function hideFallAlert() {
    UI.fallAlert?.classList.remove('visible');
    UI.fallAlert?.classList.remove('sent');
    UI.fallAlert?.setAttribute('aria-hidden', 'true');
}

export function showFallAlarm(text = t("已发送报警"), speak = false) {
    if (UI.fallAlert) {
        UI.fallAlert.classList.add('visible', 'sent');
        UI.fallAlert.setAttribute('aria-hidden', 'false');
    }
    setText(UI.fallTitle, t("已发送报警"));
    setText(UI.fallMessage, t("已记录跌倒报警事件，并通知照护端。请保持手机在身边，等待家属或照护人员联系。"));
    setText(UI.fallCountdown, '✓');
    setText(UI.fallCountdownLabel, t("报警已发送"));
    if (UI.fallSafeButton) {
        UI.fallSafeButton.textContent = t("我知道了");
        UI.fallSafeButton.disabled = false;
    }
    if (UI.fallAlarmButton) {
        UI.fallAlarmButton.textContent = t("已发送报警");
        UI.fallAlarmButton.disabled = true;
    }
    announce(t("已发送报警"));
    updateAiCaption(text);
    if (speak) speakText(text, true);
}

export function setRecordingUI(recording) {
    if (!UI.inquiryCommand) return;
    UI.inquiryCommand.classList.toggle('is-recording', recording);
    const label = UI.inquiryCommand.querySelector('span');
    if (label) label.textContent = recording ? t("松开发送") : t("按住提问");
}

export function setIntelLayerVisible(visible) {
    STATE.debug = visible;
    UI.intelLayer?.classList.toggle('visible', visible);
    UI.intelLayer?.setAttribute('aria-hidden', String(!visible));
    syncCommandState();
}

export function toggleIntelLayer() {
    const next = !STATE.debug;
    setIntelLayerVisible(next);

    if (window.spatialAudio) {
        window.spatialAudio.playTone(next ? 800 : 400, 'sine', 0.1);
    }

    showFeedback(next ? t("详情已开启") : t("详情已关闭"));
}

export function updateNavUI(data = {}) {
    const {
        thinking,
        distance,
        direction,
        social_cues,
        environment,
        objects,
        ms,
        current_goal,
        scene
    } = data;

    updateSearchBanner(current_goal);
    setText(UI.thinkingBox, thinking || scene || t("正在分析前方环境..."));

    const socialIntent = social_cues?.intent;
    const socialText = socialIntent && socialIntent !== 'none'
        ? (social_cues.details || socialIntent)
        : '';
    renderCue(UI.socialCue, t("社交"), socialText);

    const markers = Array.isArray(environment?.markers) ? environment.markers : [];
    const envText = environment?.occupancy === 'occupied'
        ? (markers[0] || environment?.risk || t("附近有障碍或人流"))
        : '';
    renderCue(UI.envCue, t("环境"), envText);

    setHtml(UI.distVal, formatDistance(distance));
    setText(UI.dirVal, formatDirection(direction));
    setHtml(UI.latVal, formatLatency(ms));
    renderObjects(objects);
}

export function updateMicroUI(data = {}) {
    const { x, y, action, guidance_speech, ms } = data;
    setHtml(UI.latVal, formatLatency(ms));
    setText(UI.dirVal, action === 'push' ? t("按下") : t("微调"));
    setHtml(UI.distVal, metric(`${Number(x || 0)},${Number(y || 0)}`));
    if (guidance_speech) setText(UI.thinkingBox, guidance_speech);
}

export function updateTaskUI(data = {}) {
    const plan = Array.isArray(data.plan) ? data.plan : [];
    const currentIndex = Number.isFinite(Number(data.current_step_index))
        ? Number(data.current_step_index)
        : 0;

    if (!plan.length) {
        UI.taskHud?.classList.remove('visible');
        return;
    }

    UI.taskHud?.classList.add('visible');
    setText(UI.taskFeedback, data.visual_feedback || '');
    setHtml(UI.latVal, formatLatency(data.ms));

    if (UI.taskList) {
        UI.taskList.innerHTML = plan.map((step, idx) => {
            let cls = '';
            if (idx < currentIndex || step?.completed) cls = 'completed';
            else if (idx === currentIndex) cls = 'active';

            return `
                <div class="task-step ${cls}" role="listitem">
                    <div class="step-num">${idx + 1}</div>
                    <div>${escapeHtml(step?.instruction || t("步骤 {0}", [idx + 1]))}</div>
                </div>`;
        }).join('');
    }

    if (currentIndex >= plan.length) {
        showFeedback(t("任务已完成"));
        window.setTimeout(() => UI.taskHud?.classList.remove('visible'), 4200);
    }
}

export function updateInquiryUI(data = {}) {
    const { thinking, current_goal, transcript, ms } = data;
    updateSearchBanner(current_goal);
    setHtml(UI.latVal, formatLatency(ms));
    if (transcript) updateUserCaption(transcript);

    if (thinking) {
        setText(UI.thinkingBox, thinking);
    } else if (transcript) {
        setText(UI.thinkingBox, t("语音：{0}", [transcript]));
    }
}

syncCommandState();
