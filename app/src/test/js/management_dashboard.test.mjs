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
});

test('risk events can be marked handled without mutating source data', () => {
  const data = {
    ...CARE_MANAGEMENT_DATA,
    events: [{
      id: 'real-fall',
      resident: '当前长护对象',
      title: '疑似跌倒报警',
      detail: '10 秒内未取消，已发送报警。',
      severity: 'high',
      status: 'open'
    }]
  };
  const next = markRiskEventHandled(data, 'real-fall');
  const originalEvent = data.events.find((event) => event.id === 'real-fall');
  const nextEvent = next.events.find((event) => event.id === 'real-fall');

  assert.equal(originalEvent.status, 'open');
  assert.equal(nextEvent.status, 'handled');
  assert.equal(calculateCareSummary(next, 'today').highRiskOpen, 0);
});

test('daily report refuses to invent simulated care tasks', () => {
  const report = buildDailyReport(CARE_MANAGEMENT_DATA, 'today');

  assert.match(report, /今日照护摘要/);
  assert.match(report, /还没有老人端上报的真实事件/);
  assert.doesNotMatch(report, /李伯伯|早间用药|夜间起身频繁/);
});

test('care data agent does not answer budget questions from simulated data', () => {
  const context = buildCareAgentContext(CARE_MANAGEMENT_DATA.careProfile);
  const reply = buildCareAgentReply(CARE_MANAGEMENT_DATA, '最近额度还够不够？');

  assert.equal(context.budgetLeft, 0);
  assert.equal(context.medicationAdherence, 0);
  assert.match(reply.speech, /没有录入真实长护服务额度/);
  assert.equal(reply.intent, 'budget_advice');
});

test('care data agent records user data as a care event', () => {
  const reply = buildCareAgentReply(CARE_MANAGEMENT_DATA, '帮我记录已经吃过降压药');
  const next = applyCareAgentAction(CARE_MANAGEMENT_DATA, reply, new Date('2026-05-23T10:30:00'));

  assert.equal(reply.intent, 'record');
  assert.equal(next.careProfile.records[0].type, '用药');
  assert.match(next.careProfile.records[0].text, /降压药/);
  assert.equal(next.events[0].title, '照护助手记录：用药');
  assert.equal(next.events[0].severity, 'medium');
});
