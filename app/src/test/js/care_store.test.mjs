import test from 'node:test';
import assert from 'node:assert/strict';

import {
  appendCareManagementEvent,
  buildFallCareEvent,
  buildNavigationCareEvent,
  cloneCareData,
  loadCareManagementData,
  saveCareManagementData
} from '../../main/assets/static/js/care_store.js';
import { CARE_MANAGEMENT_DATA, calculateCareSummary } from '../../main/assets/static/js/management.js';

function memoryStorage() {
  const state = new Map();
  return {
    getItem(key) {
      return state.has(key) ? state.get(key) : null;
    },
    setItem(key, value) {
      state.set(key, String(value));
    }
  };
}

test('care management events persist and update summary counts', () => {
  const storage = memoryStorage();
  const base = cloneCareData(CARE_MANAGEMENT_DATA);
  const next = appendCareManagementEvent(base, {
    type: 'navigation_risk',
    title: '卫生间地面湿滑预警',
    detail: '老人端识别到卫生间湿区，已语音提醒扶住墙面。',
    severity: 'high'
  });

  assert.equal(next.events[0].title, '卫生间地面湿滑预警');
  assert.equal(calculateCareSummary(next, 'today').highRiskOpen, 2);

  assert.equal(saveCareManagementData(next, storage), true);
  const loaded = loadCareManagementData(CARE_MANAGEMENT_DATA, storage);
  assert.equal(loaded.events[0].title, '卫生间地面湿滑预警');
});

test('navigation result can become a care management risk event', () => {
  const event = buildNavigationCareEvent({
    priority: 'high',
    distance: 0.8,
    direction: '正前方',
    speech: '正前方脚边有椅子，请停一下，先扶住右侧墙面。',
    environment: { occupancy: 'occupied', markers: ['脚边障碍物'] }
  });

  assert.equal(event.title, '居家行走高风险预警');
  assert.equal(event.severity, 'high');
  assert.match(event.detail, /脚边有椅子/);
  assert.match(event.detail, /0.8米/);
});

test('fall alarm payload becomes high-risk management event', () => {
  const event = buildFallCareEvent({
    reason: '10 秒内未取消，模拟报警',
    evidence: { sensor: { maxAcc: 32.5 }, visual: { strongChange: true } }
  });

  assert.equal(event.title, '疑似跌倒报警');
  assert.equal(event.severity, 'high');
  assert.equal(event.evidence.sensor.maxAcc, 32.5);
});
