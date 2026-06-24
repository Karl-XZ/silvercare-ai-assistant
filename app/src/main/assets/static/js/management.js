/**
 * 银龄智护 management dashboard.
 * Provides a lightweight silvercare management view inside the Android WebView.
 */

import {
    CARE_STORAGE_KEY,
    appendCareManagementEvent,
    loadCareManagementData,
    saveCareManagementData
} from './care_store.js';

export const CARE_MANAGEMENT_DATA = {
    generatedAt: '',
    periods: {
        today: {
            label: '今日',
            residents: 1,
            taskCompletion: 0,
            responseSeconds: 0,
            serviceClosedLoop: 0,
            trend: [0, 0, 0, 0, 0, 0, 0],
            trendLabels: ['周日', '周一', '周二', '周三', '周四', '周五', '今日'],
            progress: [
                { label: '真实事件闭环', value: 0 },
                { label: '中高风险复核', value: 0 },
                { label: '跌倒报警闭环', value: 0 },
                { label: '照护记录留存', value: 0 }
            ]
        },
        week: {
            label: '7 日',
            residents: 1,
            taskCompletion: 0,
            responseSeconds: 0,
            serviceClosedLoop: 0,
            trend: [0, 0, 0, 0, 0, 0, 0],
            trendLabels: ['周日', '周一', '周二', '周三', '周四', '周五', '今日'],
            progress: [
                { label: '真实事件闭环', value: 0 },
                { label: '中高风险复核', value: 0 },
                { label: '跌倒报警闭环', value: 0 },
                { label: '照护记录留存', value: 0 }
            ]
        },
        month: {
            label: '30 日',
            residents: 1,
            taskCompletion: 0,
            responseSeconds: 0,
            serviceClosedLoop: 0,
            trend: [0, 0, 0, 0, 0, 0, 0],
            trendLabels: ['第1周', '第2周', '第3周', '第4周', '第5周', '第6周', '本周'],
            progress: [
                { label: '真实事件闭环', value: 0 },
                { label: '中高风险复核', value: 0 },
                { label: '跌倒报警闭环', value: 0 },
                { label: '照护记录留存', value: 0 }
            ]
        }
    },
    residents: [
        { id: 'current-user', name: '当前长护对象', level: '未填写', risk: 'low', status: '等待老人端真实数据', tasks: '0/0', location: '居家环境' }
    ],
    events: [],
    tasks: [],
    careProfile: {
        resident: '当前长护对象',
        longTermCareLevel: '未填写',
        chronicConditions: [],
        monthlyCareBudget: 0,
        usedCareBudget: 0,
        medicationAdherence: 0,
        remainingVisits: 0,
        recentClaims: [],
        riskIndicators: [],
        proactiveReminders: [],
        records: []
    }
};

const severityText = {
    high: '高风险',
    medium: '中风险',
    low: '低风险'
};

const taskStatusText = {
    done: '已完成',
    pending: '待执行',
    missed: '未确认'
};

const metricIcons = {
    residents: '<path d="M16 21v-2a4 4 0 0 0-8 0v2" /><circle cx="12" cy="7" r="4" />',
    completion: '<path d="M20 6 9 17l-5-5" />',
    risk: '<path d="M12 3 2.8 19a1.4 1.4 0 0 0 1.2 2h16a1.4 1.4 0 0 0 1.2-2L12 3Z" /><path d="M12 8v5" /><path d="M12 17h.01" />',
    response: '<path d="M12 8v4l3 2" /><circle cx="12" cy="12" r="9" />'
};

function cloneCareData(data) {
    return JSON.parse(JSON.stringify(data));
}

function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

export function calculateCareSummary(data = CARE_MANAGEMENT_DATA, periodKey = 'today') {
    const period = data.periods?.[periodKey] || data.periods?.today || {};
    const events = Array.isArray(data.events) ? data.events : [];
    const tasks = Array.isArray(data.tasks) ? data.tasks : [];
    const openEvents = events.filter((event) => event.status !== 'handled');
    const highRiskOpen = openEvents.filter((event) => event.severity === 'high').length;
    const mediumRiskOpen = openEvents.filter((event) => event.severity === 'medium').length;
    const handledEvents = events.filter((event) => event.status === 'handled').length;
    const doneTasks = tasks.filter((task) => task.status === 'done').length;
    const taskCompletion = tasks.length ? Math.round((doneTasks / tasks.length) * 100) : 0;
    const serviceClosedLoop = events.length ? Math.round((handledEvents / events.length) * 100) : 0;
    const highAndMediumOpen = highRiskOpen + mediumRiskOpen;
    const highAndMediumTotal = events.filter((event) => ['high', 'medium'].includes(event.severity)).length;
    const highAndMediumHandled = events.filter((event) => ['high', 'medium'].includes(event.severity) && event.status === 'handled').length;
    const highAndMediumClosedLoop = highAndMediumTotal ? Math.round((highAndMediumHandled / highAndMediumTotal) * 100) : 0;
    const fallEvents = events.filter((event) => event.severity === 'high' || String(event.type || '').includes('fall'));
    const fallHandled = fallEvents.filter((event) => event.status === 'handled').length;
    const fallClosedLoop = fallEvents.length ? Math.round((fallHandled / fallEvents.length) * 100) : 0;
    const records = Array.isArray(data.careProfile?.records) ? data.careProfile.records : [];
    const recordRetention = records.length ? 100 : 0;
    const trend = Array.isArray(period.trend) && period.trend.length ? [...period.trend] : [0, 0, 0, 0, 0, 0, 0];
    trend[trend.length - 1] = events.length;

    return {
        periodLabel: period.label || '今日',
        residents: residentCountForData(data),
        taskCompletion,
        responseSeconds: Number(period.responseSeconds || 0),
        serviceClosedLoop,
        openEvents: openEvents.length,
        highRiskOpen,
        mediumRiskOpen,
        handledEvents,
        trend,
        trendLabels: Array.isArray(period.trendLabels) ? period.trendLabels : [],
        progress: [
            { label: '真实事件闭环', value: serviceClosedLoop },
            { label: '中高风险复核', value: highAndMediumClosedLoop },
            { label: '跌倒报警闭环', value: fallClosedLoop },
            { label: '照护记录留存', value: recordRetention || (records.length ? 100 : 0) }
        ],
        highAndMediumOpen
    };
}

function residentCountForData(data = {}) {
    const residents = Array.isArray(data.residents) ? data.residents : [];
    if (residents.length) return residents.length;
    const profileResident = String(data.careProfile?.resident || '').trim();
    return profileResident ? 1 : 0;
}

export function markRiskEventHandled(data, eventId) {
    const next = cloneCareData(data);
    const event = next.events.find((item) => item.id === eventId);
    if (event) event.status = 'handled';
    return next;
}

export function buildDailyReport(data = CARE_MANAGEMENT_DATA, periodKey = 'today') {
    const summary = calculateCareSummary(data, periodKey);
    const openNames = data.events
        .filter((event) => event.status !== 'handled')
        .map((event) => `${event.resident}：${event.title}`);
    const missedTasks = data.tasks
        .filter((task) => task.status === 'missed')
        .map((task) => `${task.resident} ${task.name}`);
    const records = Array.isArray(data.careProfile?.records) ? data.careProfile.records : [];

    if (!data.events.length && !data.tasks.length && !records.length) {
        return [
            `${summary.periodLabel}照护摘要：当前还没有老人端上报的真实事件。`,
            '风险情况：暂无跌倒报警、照护记录、巡路或找物事件。',
            '待处理重点：请等待老人端完成一次巡路、找物、用药记录或跌倒报警后再复核。',
            'AI 建议：当前不生成照护判断；后续只根据真实上报记录给出建议。'
        ].join('\n');
    }

    return [
        `${summary.periodLabel}照护摘要：当前管理 ${summary.residents} 名长护对象，真实事件 ${data.events.length} 条，照护任务完成率 ${summary.taskCompletion}%，服务闭环率 ${summary.serviceClosedLoop}%。`,
        `风险情况：待复核事件 ${summary.openEvents} 条，其中高风险 ${summary.highRiskOpen} 条，中风险 ${summary.mediumRiskOpen} 条，平均响应 ${summary.responseSeconds} 秒。`,
        openNames.length ? `待处理重点：${openNames.join('；')}。` : '待处理重点：暂无未闭环风险事件。',
        missedTasks.length ? `任务缺口：${missedTasks.join('；')} 需要照护者复核。` : '任务缺口：今日暂无未确认任务。',
        summary.highRiskOpen > 0
            ? 'AI 建议：优先处理高风险跌倒报警事件；其他低风险巡路和找物记录可作为服务留痕复核。'
            : 'AI 建议：当前没有未处理跌倒报警；低风险巡路和找物记录主要用于服务留痕，中风险照护记录请照护者复核。'
    ].join('\n');
}

export function buildCareAgentContext(profile = CARE_MANAGEMENT_DATA.careProfile) {
    const budgetLeft = Math.max(0, Number(profile.monthlyCareBudget || 0) - Number(profile.usedCareBudget || 0));
    const budgetRatio = profile.monthlyCareBudget ? Math.round((budgetLeft / profile.monthlyCareBudget) * 100) : 0;
    return {
        resident: profile.resident || '当前长护对象',
        longTermCareLevel: profile.longTermCareLevel || '未填写',
        chronicConditions: profile.chronicConditions || [],
        budgetLeft,
        budgetRatio,
        medicationAdherence: Number(profile.medicationAdherence || 0),
        remainingVisits: Number(profile.remainingVisits || 0),
        riskIndicators: profile.riskIndicators || [],
        proactiveReminders: profile.proactiveReminders || [],
        records: profile.records || []
    };
}

export function buildCareAgentReply(data = CARE_MANAGEMENT_DATA, message = '') {
    const profile = data.careProfile || CARE_MANAGEMENT_DATA.careProfile;
    const context = buildCareAgentContext(profile);
    const text = String(message || '').trim();
    const normalized = text.toLowerCase();
    const openMissedTasks = (data.tasks || []).filter((task) => task.status === 'missed');
    const openRisks = (data.events || []).filter((event) => event.status !== 'handled');
    const highRisks = openRisks.filter((event) => event.severity === 'high');
    const mediumRisks = openRisks.filter((event) => event.severity === 'medium');
    const records = Array.isArray(profile.records) ? profile.records : [];

    if (/记录|记一下|已吃|吃过|头晕|疼|不舒服|复核/.test(text)) {
        const recordType = /药|已吃|吃过|服药|降压/.test(text) ? '用药' : /头晕|疼|不舒服|症状/.test(text) ? '症状' : '复核';
        return {
            intent: 'record',
            speech: `已记录：${text}。这是一条${recordType}记录，会作为中风险照护事件进入管理端复核。`,
            action: {
                type: 'append_record',
                recordType,
                text
            }
        };
    }

    if (/费用|药费|护理费|开销|剩余|够不够/.test(text) || normalized.includes('budget')) {
        if (!Number(profile.monthlyCareBudget || 0)) {
            return {
                intent: 'budget_advice',
                speech: '当前没有录入真实长护服务额度或费用数据，暂时不能给出费用建议。请先录入真实额度、已用额度或服务记录。'
            };
        }
        return {
            intent: 'budget_advice',
            speech: `${context.resident}本月长护服务额度剩余 ${context.budgetLeft} 元，约占 ${context.budgetRatio}%。建议优先安排高风险复核、上门照护和康复训练，普通服务可排到下周。`
        };
    }

    if (/药|用药|降压|吃药/.test(text)) {
        const medicationRecords = records.filter((record) => record.type === '用药');
        const missed = openMissedTasks.map((task) => `${task.name} ${task.time}`).join('、');
        return {
            intent: 'medication_advice',
            speech: missed
                ? `当前有未确认用药任务：${missed}。建议照护者优先复核。`
                : medicationRecords.length
                    ? `当前已有 ${medicationRecords.length} 条真实用药记录，最近一条是：${medicationRecords[0].text}。`
                    : '当前还没有真实用药记录。请通过老人端说“记录我吃了某某药”来新增记录。'
        };
    }

    if (/风险|摔|跌倒|夜间|起身|卫生间|怎么处理/.test(text)) {
        const highRiskText = highRisks.length ? `当前有 ${highRisks.length} 条高风险待复核。` : '当前没有未处理高风险事件。';
        return {
            intent: 'risk_advice',
            speech: `${highRiskText}中风险照护记录 ${mediumRisks.length} 条，普通巡路和找物记录为低风险。请优先复核跌倒报警，其次复核用药、症状等照护记录。`
        };
    }

    if (!openRisks.length && !records.length && !(data.tasks || []).length) {
        return {
            intent: 'daily_advice',
            speech: '当前还没有真实老人端数据；请先完成一次巡路、找物、用药记录或跌倒报警测试。'
        };
    }

    return {
        intent: 'daily_advice',
        speech: `当前有 ${openRisks.length} 条待复核事件，其中高风险 ${highRisks.length} 条、中风险 ${mediumRisks.length} 条。请按高风险跌倒报警、中风险照护记录、低风险巡路找物记录的顺序处理。`
    };
}

export function applyCareAgentAction(data = CARE_MANAGEMENT_DATA, reply, now = new Date()) {
    const next = cloneCareData(data);
    if (!next.careProfile) next.careProfile = cloneCareData(CARE_MANAGEMENT_DATA.careProfile);
    if (!Array.isArray(next.careProfile.records)) next.careProfile.records = [];
    const action = reply?.action;
    if (action?.type !== 'append_record') return next;

    const time = now.toTimeString().slice(0, 5);
    next.careProfile.records.unshift({
        time,
        type: action.recordType || '记录',
        text: action.text || reply.speech || '新增对话记录'
    });
    next.events.unshift({
        id: `agent-${now.getTime()}`,
        resident: next.careProfile.resident,
        title: `照护助手记录：${action.recordType || '记录'}`,
        detail: action.text || reply.speech || '新增对话记录',
        severity: 'medium',
        time,
        status: 'open',
        source: '照护数据智能助手'
    });
    return next;
}

function setHtml(element, html) {
    if (element) element.innerHTML = html;
}

function setText(element, text) {
    if (element) element.textContent = text;
}

function renderMetricGrid(root, summary) {
    const metrics = [
        {
            key: 'residents',
            label: '长护对象',
            value: summary.residents,
            change: `${summary.periodLabel}在管人数`,
            tone: ''
        },
        {
            key: 'completion',
            label: '任务完成率',
            value: `${summary.taskCompletion}%`,
            change: `闭环率 ${summary.serviceClosedLoop}%`,
            tone: ''
        },
        {
            key: 'risk',
            label: '高风险待办',
            value: summary.highRiskOpen,
            change: summary.openEvents > 0 ? `待复核 ${summary.openEvents} 条` : '全部已处理',
            tone: summary.highRiskOpen > 0 ? 'danger' : ''
        },
        {
            key: 'response',
            label: '平均响应',
            value: `${summary.responseSeconds}s`,
            change: summary.responseSeconds <= 45 ? '响应良好' : '需要提速',
            tone: summary.responseSeconds <= 45 ? '' : 'warn'
        }
    ];

    setHtml(root, metrics.map((metric) => `
        <article class="care-card">
            <div class="care-card-top">
                <span class="care-card-label">${escapeHtml(metric.label)}</span>
                <span class="care-card-icon" aria-hidden="true"><svg viewBox="0 0 24 24">${metricIcons[metric.key]}</svg></span>
            </div>
            <div class="care-card-value">${escapeHtml(metric.value)}</div>
            <div class="care-card-change ${metric.tone}">${escapeHtml(metric.change)}</div>
        </article>
    `).join(''));
}

function renderTrend(elements, summary) {
    const trend = summary.trend.length ? summary.trend : [0, 0, 0, 0, 0, 0, 0];
    const labels = summary.trendLabels.length ? summary.trendLabels : ['1', '2', '3', '4', '5', '6', '7'];
    const width = 520;
    const height = 210;
    const padX = 18;
    const padY = 18;
    const max = Math.max(...trend, 1);
    const min = Math.min(...trend, 0);
    const span = Math.max(1, max - min);
    const points = trend.map((value, index) => {
        const x = padX + (index * ((width - padX * 2) / Math.max(1, trend.length - 1)));
        const y = height - padY - (((value - min) / span) * (height - padY * 2));
        return { x, y, value };
    });

    const pointText = points.map((point) => `${point.x.toFixed(1)},${point.y.toFixed(1)}`).join(' ');
    const area = `M${points[0].x.toFixed(1)},${height - padY} L${pointText} L${points[points.length - 1].x.toFixed(1)},${height - padY} Z`;
    setText(elements.trendLine, pointText);
    if (elements.trendLine) elements.trendLine.setAttribute('points', pointText);
    if (elements.trendArea) elements.trendArea.setAttribute('d', area);
    setHtml(elements.trendPoints, points.map((point) => `
        <circle cx="${point.x.toFixed(1)}" cy="${point.y.toFixed(1)}" r="6">
            <title>${escapeHtml(point.value)} 条风险事件</title>
        </circle>
    `).join(''));
    setHtml(elements.chartLabels, labels.map((label) => `<span>${escapeHtml(label)}</span>`).join(''));

    const first = trend[0] || 1;
    const last = trend[trend.length - 1] || 0;
    const delta = Math.round(((last - first) / first) * 100);
    setText(elements.trendDelta, `${delta >= 0 ? '+' : ''}${delta}%`);
}

function renderProgress(root, progress) {
    setHtml(root, progress.map((item) => `
        <div class="care-progress-item">
            <div class="care-progress-meta">
                <span>${escapeHtml(item.label)}</span>
                <span>${escapeHtml(item.value)}%</span>
            </div>
            <div class="care-progress-track" aria-hidden="true">
                <div class="care-progress-bar" style="width:${Math.max(0, Math.min(100, Number(item.value) || 0))}%"></div>
            </div>
        </div>
    `).join(''));
}

function renderEvents(root, events) {
    if (!events.length) {
        setHtml(root, '<article class="care-event"><div><h3>暂无真实事件</h3><p>老人端完成巡路、找物、照护记录或跌倒报警后会自动同步到这里。</p></div></article>');
        return;
    }
    const sorted = [...events].sort((a, b) => Number(a.status === 'handled') - Number(b.status === 'handled'));
    setHtml(root, sorted.map((event) => `
        <article class="care-event">
            <div>
                <h3>${escapeHtml(event.title)}</h3>
                <p>${escapeHtml(event.time)} · ${escapeHtml(event.resident)} · ${escapeHtml(event.detail)}</p>
            </div>
            <div class="care-event-actions">
                <span class="care-severity ${escapeHtml(event.severity)}">${escapeHtml(severityText[event.severity] || '风险')}</span>
                <button
                    class="care-mini-button"
                    type="button"
                    data-handle-event="${escapeHtml(event.id)}"
                    ${event.status === 'handled' ? 'disabled' : ''}
                >${event.status === 'handled' ? '已处理' : '标记处理'}</button>
            </div>
        </article>
    `).join(''));
}

function renderResidents(root, residents) {
    if (!residents.length) {
        setHtml(root, '<article class="care-resident"><div class="care-avatar" aria-hidden="true">当</div><div><h3>当前长护对象 · 未填写</h3><p>等待老人端真实数据 · 任务 0/0</p></div><span class="care-severity low">低风险</span></article>');
        return;
    }
    setHtml(root, residents.map((resident) => `
        <article class="care-resident">
            <div class="care-avatar" aria-hidden="true">${escapeHtml(resident.name.slice(0, 1))}</div>
            <div>
                <h3>${escapeHtml(resident.name)} · ${escapeHtml(resident.level)}</h3>
                <p>${escapeHtml(resident.location)} · ${escapeHtml(resident.status)} · 任务 ${escapeHtml(resident.tasks)}</p>
            </div>
            <span class="care-severity ${escapeHtml(resident.risk)}">${escapeHtml(severityText[resident.risk] || '风险')}</span>
        </article>
    `).join(''));
}

function renderTasks(root, tasks) {
    if (!tasks.length) {
        setHtml(root, '<article class="care-task"><div><h3>暂无真实任务</h3><p>任务指导完成后会形成服务留痕。</p></div><span class="care-status pending">待产生</span></article>');
        return;
    }
    setHtml(root, tasks.map((task) => `
        <article class="care-task">
            <div>
                <h3>${escapeHtml(task.name)}</h3>
                <p>${escapeHtml(task.time)} · ${escapeHtml(task.resident)}</p>
            </div>
            <span class="care-status ${escapeHtml(task.status)}">${escapeHtml(taskStatusText[task.status] || '待处理')}</span>
        </article>
    `).join(''));
}

function renderCareAgentProfile(root, profile) {
    if (!root || !profile) return;
    const context = buildCareAgentContext(profile);
    setHtml(root, `
        <div class="care-agent-profile-card">
            <span>长护对象</span>
            <strong>${escapeHtml(context.resident)} · ${escapeHtml(context.longTermCareLevel)}</strong>
        </div>
        <div class="care-agent-profile-card">
            <span>本月剩余额度</span>
            <strong>${escapeHtml(context.budgetLeft)} 元 · ${escapeHtml(context.budgetRatio)}%</strong>
        </div>
        <div class="care-agent-profile-card">
            <span>用药确认率</span>
            <strong>${escapeHtml(context.medicationAdherence)}%</strong>
        </div>
        <div class="care-agent-profile-card">
            <span>剩余服务次数</span>
            <strong>${escapeHtml(context.remainingVisits)} 次</strong>
        </div>
    `);
}

function renderCareAgentInsights(root, profile) {
    if (!root || !profile) return;
    const context = buildCareAgentContext(profile);
    const reminders = context.proactiveReminders.length ? context.proactiveReminders : ['今日暂无主动提醒。'];
    const records = context.records.slice(0, 3);
    const recordHtml = records.length
        ? records.map((item) => `<p><b>${escapeHtml(item.time)} · ${escapeHtml(item.type)}</b> ${escapeHtml(item.text)}</p>`).join('')
        : '<p>暂无真实照护记录。</p>';
    setHtml(root, `
        <div class="care-agent-block">
            <h3>主动提醒</h3>
            ${reminders.map((item) => `<p>${escapeHtml(item)}</p>`).join('')}
        </div>
        <div class="care-agent-block">
            <h3>最近记录</h3>
            ${recordHtml}
        </div>
    `);
}

function renderCareAgentMessages(root, messages = []) {
    if (!root) return;
    setHtml(root, messages.map((message) => `
        <div class="care-agent-message ${escapeHtml(message.role)}">
            <span>${message.role === 'user' ? '我说' : '照护助手'}</span>
            <p>${escapeHtml(message.text)}</p>
        </div>
    `).join(''));
    root.scrollTop = root.scrollHeight;
}

function downloadReport(text) {
    const blob = new Blob([text], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `silvercare-care-report-${new Date().toISOString().slice(0, 10)}.md`;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 500);
}

function speak(text) {
    try {
        if (window.AndroidSilverCare && typeof window.AndroidSilverCare.speak === 'function') {
            window.AndroidSilverCare.speak(text);
        }
    } catch (error) {
        console.error('Care dashboard speech failed:', error);
    }
}

export function setupManagementDashboard(doc = document) {
    const dashboard = doc.getElementById('careDashboard');
    const openButton = doc.getElementById('managementCommand');
    if (!dashboard || !openButton) return false;

    let data = loadCareManagementData(CARE_MANAGEMENT_DATA);
    let periodKey = 'today';
    let currentReport = buildDailyReport(data, periodKey);

    const elements = {
        metricGrid: doc.getElementById('careMetricGrid'),
        trendLine: doc.getElementById('careTrendLine'),
        trendArea: doc.getElementById('careTrendArea'),
        trendPoints: doc.getElementById('careTrendPoints'),
        trendDelta: doc.getElementById('careTrendDelta'),
        chartLabels: doc.getElementById('careChartLabels'),
        progressList: doc.getElementById('careProgressList'),
        riskList: doc.getElementById('careRiskList'),
        residentList: doc.getElementById('careResidentList'),
        taskList: doc.getElementById('careTaskList'),
        reportText: doc.getElementById('careReportText'),
        closeButton: doc.getElementById('careCloseButton'),
        exportButton: doc.getElementById('careExportReportButton'),
        generateButton: doc.getElementById('careGenerateReportButton'),
        navRiskCount: doc.getElementById('careNavRiskCount'),
        navResidentCount: doc.getElementById('careNavResidentCount'),
        careAgentProfile: doc.getElementById('careAgentProfile'),
        careAgentInsights: doc.getElementById('careAgentInsights'),
        careAgentMessages: doc.getElementById('careAgentMessages'),
        careAgentInput: doc.getElementById('careAgentInput'),
        careAgentSendButton: doc.getElementById('careAgentSendButton')
    };

    let agentMessages = [
        {
            role: 'assistant',
            text: '当前只使用老人端真实上报数据。完成巡路、找物、用药记录或跌倒报警后，我会基于这些记录给出建议。'
        }
    ];

    function render() {
        const summary = calculateCareSummary(data, periodKey);
        renderMetricGrid(elements.metricGrid, summary);
        renderTrend(elements, summary);
        renderProgress(elements.progressList, summary.progress);
        renderEvents(elements.riskList, data.events);
        renderResidents(elements.residentList, data.residents);
        renderTasks(elements.taskList, data.tasks);
        currentReport = buildDailyReport(data, periodKey);
        setText(elements.reportText, currentReport);
        setText(elements.navRiskCount, String(summary.openEvents));
        setText(elements.navResidentCount, String(summary.residents));
        renderCareAgentProfile(elements.careAgentProfile, data.careProfile);
        renderCareAgentInsights(elements.careAgentInsights, data.careProfile);
        renderCareAgentMessages(elements.careAgentMessages, agentMessages);
    }

    function sendAgentMessage(message) {
        const clean = String(message || '').trim();
        if (!clean) return;
        const reply = buildCareAgentReply(data, clean);
        agentMessages = [
            ...agentMessages,
            { role: 'user', text: clean },
            { role: 'assistant', text: reply.speech }
        ].slice(-8);
        data = applyCareAgentAction(data, reply);
        saveCareManagementData(data);
        render();
        speak(reply.speech);
    }

    function openDashboard() {
        dashboard.classList.add('visible');
        dashboard.setAttribute('aria-hidden', 'false');
        render();
        speak('长护管理端已打开。这里可以查看风险队列、长护对象、任务完成率和照护日报。');
    }

    function closeDashboard() {
        dashboard.classList.remove('visible');
        dashboard.setAttribute('aria-hidden', 'true');
        speak('已返回老人端。');
    }

    function setPeriod(nextPeriod) {
        periodKey = data.periods[nextPeriod] ? nextPeriod : 'today';
        doc.querySelectorAll('.care-period').forEach((button) => {
            button.classList.toggle('active', button.dataset.period === periodKey);
        });
        render();
    }

    function markHandled(eventId) {
        data = markRiskEventHandled(data, eventId);
        saveCareManagementData(data);
        render();
        speak('风险事件已标记处理。');
    }

    openButton.addEventListener('click', (event) => {
        event.preventDefault();
        event.stopPropagation();
        openDashboard();
    });

    elements.closeButton?.addEventListener('click', closeDashboard);
    elements.generateButton?.addEventListener('click', () => {
        currentReport = buildDailyReport(data, periodKey);
        setText(elements.reportText, currentReport);
        speak('AI 照护日报已重新生成。');
    });
    elements.exportButton?.addEventListener('click', () => {
        downloadReport(`# 银龄智护 照护日报\n\n${currentReport}\n`);
        speak('照护日报已导出。');
    });
    elements.careAgentSendButton?.addEventListener('click', () => {
        const value = elements.careAgentInput?.value || '';
        sendAgentMessage(value);
    });
    elements.careAgentInput?.addEventListener('keydown', (event) => {
        if (event.key !== 'Enter') return;
        event.preventDefault();
        sendAgentMessage(elements.careAgentInput.value);
    });

    doc.querySelectorAll('[data-agent-prompt]').forEach((button) => {
        button.addEventListener('click', () => {
            if (elements.careAgentInput) elements.careAgentInput.value = button.dataset.agentPrompt || '';
            sendAgentMessage(button.dataset.agentPrompt);
        });
    });

    doc.querySelectorAll('.care-period').forEach((button) => {
        button.addEventListener('click', () => setPeriod(button.dataset.period));
    });

    doc.querySelectorAll('.care-nav-item').forEach((button) => {
        button.addEventListener('click', () => {
            doc.querySelectorAll('.care-nav-item').forEach((item) => item.classList.remove('active'));
            button.classList.add('active');
            const target = doc.getElementById(button.dataset.section);
            target?.scrollIntoView({ behavior: 'smooth', block: 'start' });
        });
    });

    dashboard.addEventListener('click', (event) => {
        const button = event.target?.closest?.('[data-handle-event]');
        if (!button) return;
        markHandled(button.dataset.handleEvent);
    });

    window.LONG_TERM_CARE_MANAGEMENT_EVENT = (payload) => {
        const event = typeof payload === 'string' ? JSON.parse(payload) : payload;
        if (!event) return;
        data = appendCareManagementEvent(data, event);
        saveCareManagementData(data);
        render();
    };

    window.LONG_TERM_CARE_GET_MANAGEMENT_DATA = () => cloneCareData(data);

    window.addEventListener?.('storage', (event) => {
        if (event.key !== CARE_STORAGE_KEY) return;
        data = loadCareManagementData(CARE_MANAGEMENT_DATA);
        render();
    });

    render();
    return true;
}
