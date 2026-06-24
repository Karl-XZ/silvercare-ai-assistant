import test from 'node:test';
import assert from 'node:assert/strict';

import {
  CARE_MANAGEMENT_DATA,
  applyCareAgentAction,
  buildCareAgentContext,
  buildCareAgentReply,
  buildDailyReport,
  calculateCareSummary,
  markRiskEventHandled
} from '../../main/assets/static/js/management.js';

test('care dashboard summary exposes silvercare management metrics', () => {
  const summary = calculateCareSummary(CARE_MANAGEMENT_DATA, 'today');

  assert.equal(summary.residents, 1);
  assert.equal(summary.taskCompletion, 0);
  assert.equal(summary.highRiskOpen, 0);
  assert.equal(summary.mediumRiskOpen, 0);
  assert.equal(summary.openEvents, 0);
  assert.equal(summary.trend.length, 7);
  assert.equal(CARE_MANAGEMENT_DATA.residents[0].name, '当前用户');
  assert.equal(CARE_MANAGEMENT_DATA.events.length, 0);
});

test('risk events can be marked handled without mutating source data', () => {
  const source = {
    ...CARE_MANAGEMENT_DATA,
    events: [{
      id: 'real-fall',
      resident: '当前用户',
      title: '疑似跌倒报警',
      detail: '倒计时内未取消。',
      severity: 'high',
      time: '10:30',
      status: 'open'
    }]
  };
  const next = markRiskEventHandled(source, 'real-fall');
  const originalEvent = source.events.find((event) => event.id === 'real-fall');
  const nextEvent = next.events.find((event) => event.id === 'real-fall');

  assert.equal(originalEvent.status, 'open');
  assert.equal(nextEvent.status, 'handled');
  assert.equal(calculateCareSummary(next, 'today').highRiskOpen, 0);
});

test('daily report includes risk queue and missed care tasks', () => {
  const data = {
    ...CARE_MANAGEMENT_DATA,
    events: [{
      id: 'medication-open',
      resident: '当前用户',
      title: '照护助手记录：用药',
      detail: '已记录服药，等待家属复核。',
      severity: 'medium',
      time: '08:45',
      status: 'open'
    }],
    tasks: [{ id: 'task-med', name: '早间用药', resident: '当前用户', time: '08:30', status: 'missed' }]
  };
  const report = buildDailyReport(data, 'today');

  assert.match(report, /今日照护摘要/);
  assert.match(report, /高风险 0 条/);
  assert.match(report, /中风险 1 条/);
  assert.match(report, /当前用户 早间用药/);
  assert.match(report, /复核用药/);
});

test('care data agent summarizes care budget and risks', () => {
  const context = buildCareAgentContext(CARE_MANAGEMENT_DATA.careProfile);
  const reply = buildCareAgentReply(CARE_MANAGEMENT_DATA, '最近额度还够不够？');

  assert.equal(context.budgetLeft, null);
  assert.equal(context.medicationAdherence, null);
  assert.match(reply.speech, /没有真实长护额度/);
  assert.equal(reply.intent, 'budget_advice');
});

test('care data agent records user data as a care event', () => {
  const reply = buildCareAgentReply(CARE_MANAGEMENT_DATA, '帮我记录今天头晕一次，已提醒照护者复核');
  const next = applyCareAgentAction(CARE_MANAGEMENT_DATA, reply, new Date('2026-05-23T10:30:00'));

  assert.equal(reply.intent, 'record');
  assert.equal(next.careProfile.records[0].type, '症状');
  assert.match(next.careProfile.records[0].text, /头晕/);
  assert.equal(next.events[0].title, '照护助手记录：症状');
  assert.equal(next.events[0].severity, 'medium');
});

test('care data agent records medication as medium risk', () => {
  const reply = buildCareAgentReply(CARE_MANAGEMENT_DATA, '帮我记录已经吃过降压药');
  const next = applyCareAgentAction(CARE_MANAGEMENT_DATA, reply, new Date('2026-05-23T10:30:00'));

  assert.equal(reply.intent, 'record');
  assert.equal(next.careProfile.records[0].type, '用药');
  assert.equal(next.events[0].severity, 'medium');
  assert.match(next.events[0].detail, /降压药/);
});
