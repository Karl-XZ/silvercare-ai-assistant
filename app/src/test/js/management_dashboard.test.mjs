import test from 'node:test';
import assert from 'node:assert/strict';

import {
  CARE_MANAGEMENT_DATA,
  applyInsuranceAgentAction,
  buildInsuranceAgentContext,
  buildInsuranceAgentReply,
  buildDailyReport,
  calculateCareSummary,
  markRiskEventHandled
} from '../../main/assets/static/js/management.js';

test('care dashboard summary exposes long-term-care management metrics', () => {
  const summary = calculateCareSummary(CARE_MANAGEMENT_DATA, 'today');

  assert.equal(summary.residents, 16);
  assert.equal(summary.taskCompletion, 92);
  assert.equal(summary.highRiskOpen, 1);
  assert.equal(summary.mediumRiskOpen, 1);
  assert.equal(summary.openEvents, 2);
  assert.equal(summary.trend.length, 7);
});

test('risk events can be marked handled without mutating source data', () => {
  const next = markRiskEventHandled(CARE_MANAGEMENT_DATA, 'e1');
  const originalEvent = CARE_MANAGEMENT_DATA.events.find((event) => event.id === 'e1');
  const nextEvent = next.events.find((event) => event.id === 'e1');

  assert.equal(originalEvent.status, 'open');
  assert.equal(nextEvent.status, 'handled');
  assert.equal(calculateCareSummary(next, 'today').highRiskOpen, 0);
});

test('daily report includes risk queue and missed care tasks', () => {
  const report = buildDailyReport(CARE_MANAGEMENT_DATA, 'today');

  assert.match(report, /今日照护摘要/);
  assert.match(report, /高风险 1 条/);
  assert.match(report, /李伯伯 早间用药/);
  assert.match(report, /夜间起身频繁对象/);
});

test('insurance data agent summarizes quota and care risks', () => {
  const context = buildInsuranceAgentContext(CARE_MANAGEMENT_DATA.insuranceProfile);
  const reply = buildInsuranceAgentReply(CARE_MANAGEMENT_DATA, '最近额度还够不够？');

  assert.equal(context.quotaLeft, 720);
  assert.equal(context.medicationAdherence, 82);
  assert.match(reply.speech, /剩余 720 元/);
  assert.equal(reply.intent, 'quota_advice');
});

test('insurance data agent records user data as a care event', () => {
  const reply = buildInsuranceAgentReply(CARE_MANAGEMENT_DATA, '帮我记录今天头晕一次，已提醒照护者复核');
  const next = applyInsuranceAgentAction(CARE_MANAGEMENT_DATA, reply, new Date('2026-05-23T10:30:00'));

  assert.equal(reply.intent, 'record');
  assert.equal(next.insuranceProfile.records[0].type, '症状');
  assert.match(next.insuranceProfile.records[0].text, /头晕/);
  assert.equal(next.events[0].title, '照护助手记录：症状');
  assert.equal(next.events[0].severity, 'medium');
});
