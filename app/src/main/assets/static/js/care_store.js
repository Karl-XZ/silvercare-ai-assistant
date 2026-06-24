export const CARE_STORAGE_KEY = 'silvercare_ai_assistant_data_v2';

export function cloneCareData(data) {
    return JSON.parse(JSON.stringify(data));
}

function hasStorage(storage) {
    return storage && typeof storage.getItem === 'function' && typeof storage.setItem === 'function';
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
    if (Array.isArray(stored.events)) next.events = stored.events;
    if (Array.isArray(stored.tasks)) next.tasks = stored.tasks;
    if (Array.isArray(stored.residents)) next.residents = stored.residents;
    if (stored.careProfile && typeof stored.careProfile === 'object') {
        next.careProfile = { ...(next.careProfile || {}), ...stored.careProfile };
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
    const title = String(payload.title || titleFromType(type)).trim();
    const detail = String(payload.detail || payload.reason || payload.description || '老人端上报了一条需要复核的长护服务事件。').trim();
    const severity = classifyCareSeverity({ ...payload, type, title, detail });

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

export function buildNavigationCareEvent(data = {}) {
    const priority = String(data.priority || '').toLowerCase();
    const category = String(data.category || '').toLowerCase();
    const environment = data.environment || {};
    const markers = Array.isArray(environment.markers) ? environment.markers : [];
    const subject = data.subject || markers[0] || environment.risk || data.scene || '前方环境风险';
    const shouldRecord = ['critical', 'high', 'medium'].includes(priority)
        || data.target_detected === true
        || category === 'target';
    if (!shouldRecord) return null;

    return {
        type: category === 'target' ? 'target_search' : 'navigation_record',
        title: category === 'target' ? '寻物导航记录' : '行走导航记录',
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
        severity: classifyCareSeverity({
            ...task,
            type: 'care_task',
            title: task.title || task.name || '',
            detail: task.detail || ''
        }),
        detail: task.detail || `${task.name || '照护任务'}：${task.status || '已记录'}`,
        source: '照护任务'
    };
}

function normalizeSeverity(value) {
    return ['high', 'medium', 'low'].includes(String(value)) ? String(value) : '';
}

function classifyCareSeverity(payload = {}) {
    const type = String(payload.type || '').toLowerCase();
    const status = String(payload.status || '').toLowerCase();
    const text = [
        payload.title,
        payload.detail,
        payload.reason,
        payload.description,
        payload.recordType,
        payload.name
    ].map((value) => String(value || '').toLowerCase()).join(' ');

    if (/fall|alarm|跌倒|摔倒|报警/.test(`${type} ${text}`)) return 'high';
    if (/medication|medicine|drug|用药|吃药|服药|药/.test(`${type} ${text}`)) return 'medium';
    if (status === 'missed' || /missed|未确认|未响应|症状|头晕|疼|不舒服|复核/.test(`${type} ${text}`)) return 'medium';
    if (/navigation|target|search|寻物|找|导航|行走|路径/.test(`${type} ${text}`)) return 'low';
    return normalizeSeverity(payload.severity) || 'low';
}

function severityFromType(type) {
    if (type.includes('fall') || type.includes('alarm')) return 'high';
    if (type.includes('task')) return 'medium';
    if (type.includes('navigation') || type.includes('target') || type.includes('search')) return 'low';
    return 'low';
}

function titleFromType(type) {
    if (type.includes('fall')) return '疑似跌倒事件';
    if (type.includes('navigation')) return '居家环境风险提醒';
    if (type.includes('task')) return '照护任务状态更新';
    return '长护服务事件';
}
