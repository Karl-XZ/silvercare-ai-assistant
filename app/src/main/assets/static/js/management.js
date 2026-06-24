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

const CURRENT_USER_NAME = '当前用户';

export const CARE_MANAGEMENT_DATA = {
    generatedAt: '',
    periods: {
        today: {
            label: '今日',
            trend: [0, 0, 0, 0, 0, 0, 0],
            trendLabels: ['周日', '周一', '周二', '周三', '周四', '周五', '今日'],
            progress: []
        },
        week: {
            label: '7 日',
            trend: [0, 0, 0, 0, 0, 0, 0],
            trendLabels: ['周日', '周一', '周二', '周三', '周四', '周五', '今日'],
            progress: []
        },
        month: {
            label: '30 日',
            trend: [0, 0, 0, 0, 0, 0, 0],
            trendLabels: ['第1周', '第2周', '第3周', '第4周', '第5周', '第6周', '本周'],
            progress: []
        }
    },
    residents: [
        { id: 'current-user', name: CURRENT_USER_NAME, level: '未设置长护等级', risk: 'low', status: '暂无异常记录', tasks: '0/0', location: '未设置位置' }
    ],
    events: [],
    tasks: [],
    careProfile: {
        resident: CURRENT_USER_NAME,
        longTermCareLevel: '未设置长护等级',
        chronicConditions: [],
        monthlyCareBudget: null,
        usedCareBudget: null,
        medicationAdherence: null,
        remainingVisits: null,
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
    const residents = Array.isArray(data.residents) ? data.residents : [];
    const openEvents = events.filter((event) => event.status !== 'handled');
    const highRiskOpen = openEvents.filter((event) => event.severity === 'high').length;
    const mediumRiskOpen = openEvents.filter((event) => event.severity === 'medium').length;
    const handledEvents = events.filter((event) => event.status === 'handled').length;
    const completedTasks = tasks.filter((task) => task.status === 'done').length;
    const taskCompletion = tasks.length ? Math.round((completedTasks / tasks.length) * 100) : 0;
    const serviceClosedLoop = events.length ? Math.round((handledEvents / events.length) * 100) : 100;
    const fallEvents = events.filter((event) => /fall|alarm|跌倒|摔倒|报警/.test(`${event.type || ''} ${event.title || ''} ${event.detail || ''}`));
    const handledFallEvents = fallEvents.filter((event) => event.status === 'handled').length;
    const fallClosedLoop = fallEvents.length ? Math.round((handledFallEvents / fallEvents.length) * 100) : 100;

    return {
        periodLabel: period.label || '今日',
        residents: residents.length,
        taskCompletion,
        responseSeconds: Number(period.responseSeconds || 0),
        serviceClosedLoop,
        openEvents: openEvents.length,
        highRiskOpen,
        mediumRiskOpen,
        handledEvents,
        trend: Array.isArray(period.trend) ? period.trend : [],
        trendLabels: Array.isArray(period.trendLabels) ? period.trendLabels : [],
        progress: [
            { label: '照护提醒确认', value: taskCompletion },
            { label: '事件已复核', value: serviceClosedLoop },
            { label: '跌倒报警闭环', value: fallClosedLoop },
            { label: '真实记录覆盖', value: events.length || tasks.length ? 100 : 0 }
        ]
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
    const events = Array.isArray(data.events) ? data.events : [];
    const tasks = Array.isArray(data.tasks) ? data.tasks : [];
    const openNames = events
        .filter((event) => event.status !== 'handled')
        .map((event) => `${event.resident}：${event.title}`);
    const missedTasks = tasks
        .filter((task) => task.status === 'missed')
        .map((task) => `${task.resident} ${task.name}`);
    const advice = [];
    if (summary.highRiskOpen > 0) advice.push('优先处理跌倒报警，并尽快联系当前用户确认安全。');
    if (summary.mediumRiskOpen > 0 || missedTasks.length) advice.push('复核用药、症状或未确认照护记录。');
    if (summary.openEvents > summary.highRiskOpen + summary.mediumRiskOpen) advice.push('普通寻路和找物记录按低风险留痕，不升级为紧急事件。');
    if (!advice.length) advice.push('当前没有待复核风险，继续根据老人端真实上报记录更新日报。');

    return [
        `${summary.periodLabel}照护摘要：当前管理 ${summary.residents} 名长护对象，照护任务完成率 ${summary.taskCompletion}%，服务闭环率 ${summary.serviceClosedLoop}%。`,
        `风险情况：待复核事件 ${summary.openEvents} 条，其中高风险 ${summary.highRiskOpen} 条，中风险 ${summary.mediumRiskOpen} 条，平均响应 ${summary.responseSeconds} 秒。`,
        openNames.length ? `待处理重点：${openNames.join('；')}。` : '待处理重点：暂无未闭环风险事件。',
        missedTasks.length ? `任务缺口：${missedTasks.join('；')} 需要照护者复核。` : '任务缺口：今日暂无未确认任务。',
        `AI 建议：${advice.join('')}`
    ].join('\n');
}

export function buildCareAgentContext(profile = CARE_MANAGEMENT_DATA.careProfile) {
    const budgetTotal = profile.monthlyCareBudget == null ? NaN : Number(profile.monthlyCareBudget);
    const budgetUsed = profile.usedCareBudget == null ? NaN : Number(profile.usedCareBudget);
    const hasBudget = Number.isFinite(budgetTotal) && budgetTotal > 0;
    const budgetLeft = hasBudget ? Math.max(0, budgetTotal - (Number.isFinite(budgetUsed) ? budgetUsed : 0)) : null;
    const budgetRatio = hasBudget ? Math.round((budgetLeft / budgetTotal) * 100) : null;
    const medicationAdherence = profile.medicationAdherence == null ? NaN : Number(profile.medicationAdherence);
    const remainingVisits = profile.remainingVisits == null ? NaN : Number(profile.remainingVisits);
    return {
        resident: profile.resident || CURRENT_USER_NAME,
        longTermCareLevel: profile.longTermCareLevel || '未设置长护等级',
        chronicConditions: profile.chronicConditions || [],
        budgetLeft,
        budgetRatio,
        medicationAdherence: Number.isFinite(medicationAdherence) ? medicationAdherence : null,
        remainingVisits: Number.isFinite(remainingVisits) ? remainingVisits : null,
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
        if (context.budgetLeft === null) {
            return {
                intent: 'budget_advice',
                speech: `${context.resident}目前还没有真实长护额度或费用记录。请先记录服务额度、已使用金额或上传账单后，我再根据真实数据计算。`
            };
        }
        return {
            intent: 'budget_advice',
            speech: `${context.resident}本月长护服务额度剩余 ${context.budgetLeft} 元，约占 ${context.budgetRatio}%。建议优先安排高风险复核、上门照护和康复训练，普通服务可排到下周。`
        };
    }

    if (/药|用药|降压|吃药/.test(text)) {
        const missed = openMissedTasks.map((task) => `${task.name} ${task.time}`).join('、') || '暂无未确认用药任务';
        const adherence = context.medicationAdherence === null
            ? '目前没有真实用药确认率记录'
            : `当前用药确认率 ${context.medicationAdherence}%`;
        return {
            intent: 'medication_advice',
            speech: `${context.resident}${adherence}。${missed}。用药相关记录按中风险复核，请根据真实服药情况补记。`
        };
    }

    if (/风险|摔|跌倒|夜间|起身|卫生间|怎么处理/.test(text)) {
        const highRiskText = highRisks.length ? `当前有 ${highRisks.length} 条高风险待复核。` : '当前没有未处理高风险事件。';
        const mediumRiskCount = openRisks.filter((event) => event.severity === 'medium').length;
        const lowRiskCount = openRisks.filter((event) => event.severity === 'low').length;
        return {
            intent: 'risk_advice',
            speech: `${highRiskText}中风险 ${mediumRiskCount} 条，低风险 ${lowRiskCount} 条。普通寻路和找东西只按低风险留痕；用药、症状或复核记录按中风险；摔倒报警按高风险处理。`
        };
    }

    const summary = calculateCareSummary(data, 'today');
    return {
        intent: 'daily_advice',
        speech: `${context.resident}今日共有 ${summary.openEvents} 条待复核事件：高风险 ${summary.highRiskOpen} 条，中风险 ${summary.mediumRiskOpen} 条。当前建议只基于老人端真实上报和你手动记录的数据，不使用演示样例。`
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
        severity: careRecordSeverity(action.recordType),
        time,
        status: 'open',
        source: '照护数据智能助手'
    });
    return next;
}

function careRecordSeverity(recordType) {
    return /用药|症状|复核/.test(String(recordType || '')) ? 'medium' : 'low';
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
        setHtml(root, '<article class="care-event"><div><h3>暂无真实事件</h3><p>老人端上报、摔倒报警或你手动记录后会显示在这里。</p></div></article>');
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
        setHtml(root, '<article class="care-resident"><div class="care-avatar" aria-hidden="true">当</div><div><h3>当前用户 · 未设置长护等级</h3><p>暂无真实状态记录 · 任务 0/0</p></div><span class="care-severity low">低风险</span></article>');
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
        setHtml(root, '<article class="care-task"><div><h3>暂无照护任务</h3><p>用药、复核或服务任务记录后会显示在这里。</p></div><span class="care-status done">无待办</span></article>');
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
    const reminders = context.proactiveReminders.length ? context.proactiveReminders : ['暂无基于真实记录生成的主动提醒。'];
    const records = context.records.slice(0, 3);
    setHtml(root, `
        <div class="care-agent-block">
            <h3>主动提醒</h3>
            ${reminders.map((item) => `<p>${escapeHtml(item)}</p>`).join('')}
        </div>
        <div class="care-agent-block">
            <h3>最近记录</h3>
            ${records.length ? records.map((item) => `<p><b>${escapeHtml(item.time)} · ${escapeHtml(item.type)}</b> ${escapeHtml(item.text)}</p>`).join('') : '<p>暂无手动记录。</p>'}
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
            text: buildCareAgentReply(data, '今天还要注意什么？').speech
        }
    ];

    function render() {
        data = withDerivedCurrentUser(data);
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

    window.SILVERCARE_MANAGEMENT_DASHBOARD = {
        open: openDashboard,
        close: closeDashboard
    };

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
    openButton.addEventListener('touchend', (event) => {
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation?.();
        openDashboard();
    }, { passive: false });

    elements.closeButton?.addEventListener('click', closeDashboard);
    elements.closeButton?.addEventListener('touchend', (event) => {
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation?.();
        closeDashboard();
    }, { passive: false });
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

function withDerivedCurrentUser(data) {
    const next = cloneCareData(data);
    if (!next.careProfile) next.careProfile = cloneCareData(CARE_MANAGEMENT_DATA.careProfile);
    if (!next.careProfile.resident) next.careProfile.resident = CURRENT_USER_NAME;
    const openEvents = Array.isArray(next.events) ? next.events.filter((event) => event.status !== 'handled') : [];
    const highest = openEvents.some((event) => event.severity === 'high')
        ? 'high'
        : openEvents.some((event) => event.severity === 'medium')
            ? 'medium'
            : 'low';
    const totalTasks = Array.isArray(next.tasks) ? next.tasks.length : 0;
    const doneTasks = Array.isArray(next.tasks) ? next.tasks.filter((task) => task.status === 'done').length : 0;
    const latest = openEvents[0];
    next.residents = [{
        id: 'current-user',
        name: next.careProfile.resident || CURRENT_USER_NAME,
        level: next.careProfile.longTermCareLevel || '未设置长护等级',
        risk: highest,
        status: latest ? latest.title : '暂无异常记录',
        tasks: `${doneTasks}/${totalTasks}`,
        location: next.careProfile.location || '未设置位置'
    }];
    return next;
}
