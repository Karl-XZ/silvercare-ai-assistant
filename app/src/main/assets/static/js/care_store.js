export const CARE_STORAGE_KEY = 'silvercare_ai_assistant_data_v1';

export function cloneCareData(data) {
    return JSON.parse(JSON.stringify(data));
}

function hasStorage(storage) {
    return storage && typeof storage.getItem === 'function' && typeof storage.setItem === 'function';
}

const LEGACY_DEMO_RESIDENTS = new Set(['王阿姨', '李伯伯', '陈奶奶', '赵叔叔', '演示长护对象']);
const LEGACY_DEMO_IDS = /^(e[1-4]|t[1-4]|demo-)/;
const LEGACY_DEMO_TEXT = /比赛演示|早间用药未确认|夜间起身频繁|卫生间弱光|饮水任务已完成|长护服务额度已使用|康复训练服务|居家照护上门服务|慢病复诊与用药指导/;

function isLegacyDemoItem(item = {}) {
    const text = [
        item.id,
        item.resident,
        item.name,
        item.title,
        item.detail,
        item.text,
        item.source,
        item.status,
        item.location
    ].filter(Boolean).join(' ');
    return LEGACY_DEMO_IDS.test(String(item.id || ''))
        || LEGACY_DEMO_RESIDENTS.has(String(item.resident || item.name || ''))
        || LEGACY_DEMO_TEXT.test(text);
}

function sanitizeStoredCareProfile(profile = {}) {
    const next = { ...profile };
    if (LEGACY_DEMO_RESIDENTS.has(String(next.resident || '')) || LEGACY_DEMO_TEXT.test(JSON.stringify(next))) {
        delete next.resident;
        delete next.longTermCareLevel;
        delete next.chronicConditions;
        delete next.monthlyCareBudget;
        delete next.usedCareBudget;
        delete next.medicationAdherence;
        delete next.remainingVisits;
        delete next.recentClaims;
        delete next.riskIndicators;
        delete next.proactiveReminders;
    }
    if (Array.isArray(profile.records)) {
        next.records = profile.records.filter((item) => !isLegacyDemoItem(item));
    }
    return next;
}

export function loadCareManagementData(fallback, storage = globalThis.localStorage) {
    const base = cloneCareData(fallback);
    if (!hasStorage(storage)) return base;

    try {
        const raw = storage.getItem(CARE_STORAGE_KEY);
        if (!raw) return base;
        return mergeCareData(base, JSON.parse(raw));
    } catch (error) {
        console.error('Load care management data failed:', error);
        return base;
    }
}

export function saveCareManagementData(data, storage = globalThis.localStorage) {
    if (!hasStorage(storage)) return false;
    try {
        storage.setItem(CARE_STORAGE_KEY, JSON.stringify(data));
        return true;
    } catch (error) {
        console.error('Save care management data failed:', error);
        return false;
    }
}

export function mergeCareData(base, stored = {}) {
    const next = cloneCareData(base);
    if (Array.isArray(stored.events)) next.events = stored.events.filter((item) => !isLegacyDemoItem(item));
    if (Array.isArray(stored.tasks)) next.tasks = stored.tasks.filter((item) => !isLegacyDemoItem(item));
    if (Array.isArray(stored.residents)) next.residents = stored.residents.filter((item) => !isLegacyDemoItem(item));
    if (stored.careProfile && typeof stored.careProfile === 'object') {
        const sanitizedProfile = sanitizeStoredCareProfile(stored.careProfile);
        next.careProfile = { ...(next.careProfile || {}), ...sanitizedProfile };
        if (Array.isArray(sanitizedProfile.records)) {
            next.careProfile.records = sanitizedProfile.records;
        }
    }
    if (stored.generatedAt) next.generatedAt = stored.generatedAt;
    if (stored.periods && typeof stored.periods === 'object') {
        next.periods = { ...next.periods, ...stored.periods };
    }
    return next;
}

export function appendCareManagementEvent(data, payload = {}) {
    const next = cloneCareData(data);
    const event = normalizeCareEvent(payload);
    next.events.unshift(event);
    if (payload.record_type || payload.recordType || String(payload.type || '').includes('care_record')) {
        if (!next.careProfile) next.careProfile = {};
        if (!Array.isArray(next.careProfile.records)) next.careProfile.records = [];
        next.careProfile.records.unshift({
            time: event.time,
            type: payload.record_type || payload.recordType || '记录',
            text: payload.record_text || payload.recordText || event.detail
        });
    }
    next.generatedAt = new Date().toLocaleString('zh-CN', { hour12: false });

    const today = next.periods?.today;
    if (today && Array.isArray(today.trend) && today.trend.length) {
        const lastIndex = today.trend.length - 1;
        today.trend[lastIndex] = Number(today.trend[lastIndex] || 0) + 1;
    }
    return next;
}

export function normalizeCareEvent(payload = {}) {
    const type = String(payload.type || payload.event_type || '').trim();
    const severity = normalizeSeverity(severityForPayload(payload, type));
    const title = String(payload.title || titleFromType(type)).trim();
    const detail = String(payload.detail || payload.reason || payload.description || '老人端上报了一条需要复核的长护服务事件。').trim();

    return {
        id: payload.id || `event-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
        resident: payload.resident || payload.person || '当前长护对象',
        title,
        detail,
        severity,
        time: payload.time || new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' }),
        status: payload.status || 'open',
        source: payload.source || '老人端',
        evidence: payload.evidence || null
    };
}

function severityForPayload(payload, type) {
    const normalizedType = String(type || '').toLowerCase();
    const recordType = String(payload.record_type || payload.recordType || '').trim();
    if (normalizedType.includes('fall') || normalizedType.includes('alarm')) return 'high';
    if (normalizedType.includes('navigation') || normalizedType.includes('search')) return 'low';
    if (normalizedType.includes('care_record') || normalizedType.includes('record')) return 'medium';
    if (/用药|症状|血压|血糖|服药|吃药|降压/.test(recordType)) return 'medium';
    return payload.severity || severityFromType(normalizedType);
}

export function buildNavigationCareEvent(data = {}) {
    const environment = data.environment || {};
    const markers = Array.isArray(environment.markers) ? environment.markers : [];
    const subject = data.subject || markers[0] || environment.risk || data.scene || '老人端导航';
    const taskText = data.target_detected ? '找物结果' : '巡路记录';

    return {
        type: 'navigation_risk',
        title: `老人端${taskText}`,
        severity: 'low',
        detail: [
            data.speech || data.thinking || `识别到${subject}`,
            data.direction ? `方向：${data.direction}` : '',
            Number.isFinite(Number(data.distance)) ? `距离：${Number(data.distance).toFixed(1)}米` : ''
        ].filter(Boolean).join('；'),
        source: '老人端导航'
    };
}

export function buildFallCareEvent(payload = {}) {
    return {
        type: 'fall_alarm',
        title: '疑似跌倒报警',
        severity: 'high',
        detail: payload.detail || payload.reason || '检测到手机冲击和过去数秒画面剧烈变化，倒计时内未取消，已发送报警。',
        evidence: payload.evidence || null,
        source: '跌倒风险预警'
    };
}

export function buildTaskCareEvent(task = {}) {
    return {
        type: 'care_task',
        title: task.title || '照护任务状态更新',
        severity: task.severity || (task.status === 'missed' ? 'medium' : 'low'),
        detail: task.detail || `${task.name || '照护任务'}：${task.status || '已记录'}`,
        source: '照护任务'
    };
}

function normalizeSeverity(value) {
    return ['high', 'medium', 'low'].includes(String(value)) ? String(value) : 'medium';
}

function severityFromType(type) {
    if (type.includes('fall') || type.includes('alarm')) return 'high';
    if (type.includes('care_record') || type.includes('record') || type.includes('medication')) return 'medium';
    if (type.includes('task') || type.includes('navigation') || type.includes('search')) return 'low';
    return 'medium';
}

function titleFromType(type) {
    if (type.includes('fall')) return '疑似跌倒事件';
    if (type.includes('navigation')) return '居家环境风险提醒';
    if (type.includes('task')) return '照护任务状态更新';
    return '长护服务事件';
}
