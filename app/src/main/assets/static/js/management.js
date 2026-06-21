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
    generatedAt: '2026-05-23 14:30',
    periods: {
        today: {
            label: '今日',
            residents: 16,
            taskCompletion: 92,
            responseSeconds: 42,
            serviceClosedLoop: 88,
            trend: [2, 3, 2, 4, 3, 5, 6],
            trendLabels: ['周日', '周一', '周二', '周三', '周四', '周五', '今日'],
            progress: [
                { label: '照护提醒确认', value: 92 },
                { label: '风险事件已复核', value: 76 },
                { label: '跌倒预警闭环', value: 84 },
                { label: '日报生成覆盖', value: 100 }
            ]
        },
        week: {
            label: '7 日',
            residents: 16,
            taskCompletion: 89,
            responseSeconds: 55,
            serviceClosedLoop: 82,
            trend: [14, 18, 13, 20, 16, 19, 23],
            trendLabels: ['周日', '周一', '周二', '周三', '周四', '周五', '今日'],
            progress: [
                { label: '照护提醒确认', value: 89 },
                { label: '风险事件已复核', value: 81 },
                { label: '跌倒预警闭环', value: 78 },
                { label: '日报生成覆盖', value: 96 }
            ]
        },
        month: {
            label: '30 日',
            residents: 16,
            taskCompletion: 86,
            responseSeconds: 63,
            serviceClosedLoop: 79,
            trend: [58, 64, 71, 69, 76, 82, 88],
            trendLabels: ['第1周', '第2周', '第3周', '第4周', '第5周', '第6周', '本周'],
            progress: [
                { label: '照护提醒确认', value: 86 },
                { label: '风险事件已复核', value: 78 },
                { label: '跌倒预警闭环', value: 75 },
                { label: '日报生成覆盖', value: 93 }
            ]
        }
    },
    residents: [
        { id: 'r1', name: '王阿姨', level: '长护二级', risk: 'high', status: '夜间起身频繁', tasks: '5/6', location: '卧室' },
        { id: 'r2', name: '李伯伯', level: '长护三级', risk: 'medium', status: '用药一次未确认', tasks: '4/5', location: '客厅' },
        { id: 'r3', name: '陈奶奶', level: '长护一级', risk: 'low', status: '状态稳定', tasks: '6/6', location: '厨房' },
        { id: 'r4', name: '赵叔叔', level: '长护二级', risk: 'medium', status: '卫生间弱光提醒', tasks: '5/6', location: '卫生间' }
    ],
    events: [
        {
            id: 'e1',
            resident: '王阿姨',
            title: '疑似跌倒已询问',
            detail: '传感器冲击 + 过去数秒画面剧烈变化，10 秒内已收到“我没事”确认。',
            severity: 'high',
            time: '09:42',
            status: 'open'
        },
        {
            id: 'e2',
            resident: '李伯伯',
            title: '用药提醒未确认',
            detail: '08:30 降压药提醒未收到语音或点击确认，建议照护者电话复核。',
            severity: 'medium',
            time: '08:45',
            status: 'open'
        },
        {
            id: 'e3',
            resident: '赵叔叔',
            title: '卫生间弱光行走',
            detail: '识别到低照度和地面湿区风险，App 已播报“扶住墙面，慢慢前进”。',
            severity: 'medium',
            time: '07:18',
            status: 'handled'
        },
        {
            id: 'e4',
            resident: '陈奶奶',
            title: '饮水任务已完成',
            detail: '老人语音确认已饮水，系统记录为低风险正常事件。',
            severity: 'low',
            time: '10:10',
            status: 'handled'
        }
    ],
    tasks: [
        { id: 't1', name: '早间用药', resident: '李伯伯', time: '08:30', status: 'missed' },
        { id: 't2', name: '饮水提醒', resident: '陈奶奶', time: '10:00', status: 'done' },
        { id: 't3', name: '活动训练', resident: '王阿姨', time: '15:30', status: 'pending' },
        { id: 't4', name: '夜间起身复核', resident: '赵叔叔', time: '21:00', status: 'pending' }
    ],
    careProfile: {
        resident: '李伯伯',
        longTermCareLevel: '长护三级',
        chronicConditions: ['高血压', '轻度认知下降', '夜间起身频繁'],
        monthlyCareBudget: 2400,
        usedCareBudget: 1680,
        medicationAdherence: 82,
        remainingVisits: 5,
        recentClaims: [
            { name: '居家照护上门服务', amount: 420, date: '今日' },
            { name: '慢病复诊与用药指导', amount: 126, date: '昨日' },
            { name: '康复训练服务', amount: 280, date: '本周' }
        ],
        riskIndicators: [
            '早间用药未确认',
            '夜间起身频繁',
            '卫生间门槛与湿滑风险',
            '本月长护服务额度剩余 720 元'
        ],
        proactiveReminders: [
            '08:30 降压药未确认，建议照护者电话复核。',
            '本月长护服务额度剩余 720 元，可优先安排 2 次上门照护和 1 次康复训练。',
            '夜间起身频繁，建议检查床边照明、拖鞋位置和卫生间通道障碍。'
        ],
        records: [
            { time: '08:45', type: '用药', text: '早间用药未确认，已进入复核队列。' },
            { time: '09:12', type: '服务', text: '长护服务额度已使用 1680 元，剩余额度 720 元。' }
        ]
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
    const openEvents = events.filter((event) => event.status !== 'handled');
    const highRiskOpen = openEvents.filter((event) => event.severity === 'high').length;
    const mediumRiskOpen = openEvents.filter((event) => event.severity === 'medium').length;
    const handledEvents = events.filter((event) => event.status === 'handled').length;

    return {
        periodLabel: period.label || '今日',
        residents: Number(period.residents || data.residents?.length || 0),
        taskCompletion: Number(period.taskCompletion || 0),
        responseSeconds: Number(period.responseSeconds || 0),
        serviceClosedLoop: Number(period.serviceClosedLoop || 0),
        openEvents: openEvents.length,
        highRiskOpen,
        mediumRiskOpen,
        handledEvents,
        trend: Array.isArray(period.trend) ? period.trend : [],
        trendLabels: Array.isArray(period.trendLabels) ? period.trendLabels : [],
        progress: Array.isArray(period.progress) ? period.progress : []
    };
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

    return [
        `${summary.periodLabel}照护摘要：当前管理 ${summary.residents} 名长护对象，照护任务完成率 ${summary.taskCompletion}%，服务闭环率 ${summary.serviceClosedLoop}%。`,
        `风险情况：待复核事件 ${summary.openEvents} 条，其中高风险 ${summary.highRiskOpen} 条，中风险 ${summary.mediumRiskOpen} 条，平均响应 ${summary.responseSeconds} 秒。`,
        openNames.length ? `待处理重点：${openNames.join('；')}。` : '待处理重点：暂无未闭环风险事件。',
        missedTasks.length ? `任务缺口：${missedTasks.join('；')} 需要照护者复核。` : '任务缺口：今日暂无未确认任务。',
        'AI 建议：优先处理高风险跌倒相关事件；对未确认用药任务进行电话复核；夜间起身频繁对象建议检查床边照明和地面障碍物。'
    ].join('\n');
}

export function buildCareAgentContext(profile = CARE_MANAGEMENT_DATA.careProfile) {
    const budgetLeft = Math.max(0, Number(profile.monthlyCareBudget || 0) - Number(profile.usedCareBudget || 0));
    const budgetRatio = profile.monthlyCareBudget ? Math.round((budgetLeft / profile.monthlyCareBudget) * 100) : 0;
    return {
        resident: profile.resident,
        longTermCareLevel: profile.longTermCareLevel,
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

    if (/记录|记一下|已吃|吃过|头晕|疼|不舒服|复核/.test(text)) {
        return {
            intent: 'record',
            speech: `已记录：${text}。我会把它放入${context.resident}的长护服务记录，并提醒照护者复核。`,
            action: {
                type: 'append_record',
                recordType: /药|已吃|吃过/.test(text) ? '用药' : /头晕|疼|不舒服/.test(text) ? '症状' : '复核',
                text
            }
        };
    }

    if (/费用|药费|护理费|开销|剩余|够不够/.test(text) || normalized.includes('budget')) {
        return {
            intent: 'budget_advice',
            speech: `${context.resident}本月长护服务额度剩余 ${context.budgetLeft} 元，约占 ${context.budgetRatio}%。建议优先安排高风险复核、上门照护和康复训练，普通服务可排到下周。`
        };
    }

    if (/药|用药|降压|吃药/.test(text)) {
        const missed = openMissedTasks.map((task) => `${task.name} ${task.time}`).join('、') || '暂无未确认用药任务';
        return {
            intent: 'medication_advice',
            speech: `${context.resident}当前用药确认率 ${context.medicationAdherence}%。${missed}。建议先电话确认早间用药，再在 App 内补记确认结果。`
        };
    }

    if (/风险|摔|跌倒|夜间|起身|卫生间|怎么处理/.test(text)) {
        const highRiskText = highRisks.length ? `当前有 ${highRisks.length} 条高风险待复核。` : '当前没有未处理高风险事件。';
        return {
            intent: 'risk_advice',
            speech: `${highRiskText}${context.resident}存在夜间起身频繁和卫生间通行风险，建议今晚先检查床边照明、拖鞋位置、通往卫生间的地面障碍，并保留跌倒确认提醒。`
        };
    }

    return {
        intent: 'daily_advice',
        speech: `${context.resident}今日重点是复核早间用药、处理 ${openRisks.length} 条待复核风险，并合理使用剩余 ${context.budgetLeft} 元长护服务额度。建议先处理用药未确认，再安排夜间起身风险排查。`
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
        severity: action.recordType === '症状' ? 'medium' : 'low',
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
    setHtml(root, `
        <div class="care-agent-block">
            <h3>主动提醒</h3>
            ${reminders.map((item) => `<p>${escapeHtml(item)}</p>`).join('')}
        </div>
        <div class="care-agent-block">
            <h3>最近记录</h3>
            ${records.map((item) => `<p><b>${escapeHtml(item.time)} · ${escapeHtml(item.type)}</b> ${escapeHtml(item.text)}</p>`).join('')}
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
        addDemoEventButton: doc.getElementById('careAddDemoEventButton'),
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
            text: buildCareAgentReply(data, '今天还要注意什么？').speech
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

    function addDemoEvent() {
        data = appendCareManagementEvent(data, {
            id: `demo-${Date.now()}`,
            resident: '演示长护对象',
            title: '新增跌倒风险预警',
            detail: '前方地面有障碍物且手机移动不稳定，老人端已语音提醒停下并扶稳。',
            severity: 'high',
            source: '比赛演示'
        });
        saveCareManagementData(data);
        render();
        speak('已添加一条演示风险事件。');
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
    elements.addDemoEventButton?.addEventListener('click', addDemoEvent);
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
