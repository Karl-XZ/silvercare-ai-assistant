export const CARE_STORAGE_KEY = 'silvercare_ai_assistant_data_v1';

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
    const severity = normalizeSeverity(payload.severity || severityFromType(type));
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

export function buildNavigationCareEvent(data = {}) {
    const priority = String(data.priority || '').toLowerCase();
    const environment = data.environment || {};
    const markers = Array.isArray(environment.markers) ? environment.markers : [];
    const subject = data.subject || markers[0] || environment.risk || data.scene || '前方环境风险';
    const highRisk = priority === 'critical' || priority === 'high';
    const mediumRisk = priority === 'medium' || environment.occupancy === 'occupied';
    if (!highRisk && !mediumRisk) return null;

    return {
        type: 'navigation_risk',
        title: highRisk ? '居家行走高风险预警' : '居家环境风险提醒',
        severity: highRisk ? 'high' : 'medium',
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
    if (type.includes('task') || type.includes('navigation')) return 'medium';
    return 'medium';
}

function titleFromType(type) {
    if (type.includes('fall')) return '疑似跌倒事件';
    if (type.includes('navigation')) return '居家环境风险提醒';
    if (type.includes('task')) return '照护任务状态更新';
    return '长护服务事件';
}
