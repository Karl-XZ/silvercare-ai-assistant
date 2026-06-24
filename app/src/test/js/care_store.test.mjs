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
  assert.equal(next.events[0].severity, 'low');
  assert.equal(calculateCareSummary(next, 'today').highRiskOpen, 0);

  assert.equal(saveCareManagementData(next, storage), true);
  const loaded = loadCareManagementData(CARE_MANAGEMENT_DATA, storage);
  assert.equal(loaded.events[0].title, '卫生间地面湿滑预警');
});

test('voice care record event is stored in events and resident records', () => {
  const storage = memoryStorage();
  const base = cloneCareData(CARE_MANAGEMENT_DATA);
  const next = appendCareManagementEvent(base, {
    type: 'care_record',
    title: '照护助手记录：用药',
    detail: '吃了降压药',
    severity: 'low',
    record_type: '用药',
    record_text: '吃了降压药'
  });

  assert.equal(next.events[0].title, '照护助手记录：用药');
  assert.equal(next.events[0].severity, 'medium');
  assert.equal(next.careProfile.records[0].type, '用药');
  assert.equal(next.careProfile.records[0].text, '吃了降压药');

  assert.equal(saveCareManagementData(next, storage), true);
  const loaded = loadCareManagementData(CARE_MANAGEMENT_DATA, storage);
  assert.equal(loaded.careProfile.records[0].text, '吃了降压药');
});

test('legacy demo management data is filtered when loading stored data', () => {
  const storage = memoryStorage();
  saveCareManagementData({
    events: [
      { id: 'e1', resident: '王阿姨', title: '疑似跌倒已询问', detail: '模拟事件', severity: 'high' },
      { id: 'real-1', resident: '当前长护对象', title: '照护助手记录：用药', detail: '吃了降压药', severity: 'medium' }
    ],
    residents: [
      { id: 'r1', name: '李伯伯', level: '长护三级' },
      { id: 'current-user', name: '当前长护对象', level: '未填写' }
    ],
    tasks: [{ id: 't1', resident: '李伯伯', name: '早间用药' }],
    careProfile: {
      resident: '李伯伯',
      records: [
        { time: '08:45', type: '用药', text: '早间用药未确认，已进入复核队列。' },
        { time: '10:30', type: '用药', text: '吃了降压药' }
      ]
    }
  }, storage);

  const loaded = loadCareManagementData(CARE_MANAGEMENT_DATA, storage);
  assert.equal(loaded.events.length, 1);
  assert.equal(loaded.events[0].id, 'real-1');
  assert.equal(loaded.residents.length, 1);
  assert.equal(loaded.tasks.length, 0);
  assert.equal(loaded.careProfile.records.length, 1);
  assert.equal(loaded.careProfile.records[0].text, '吃了降压药');
});

test('navigation and object search results are low-risk service traces', () => {
  const event = buildNavigationCareEvent({
    priority: 'high',
    distance: 0.8,
    direction: '正前方',
    speech: '正前方脚边有椅子，请停一下，先扶住右侧墙面。',
    environment: { occupancy: 'occupied', markers: ['脚边障碍物'] }
  });

  assert.equal(event.title, '老人端巡路记录');
  assert.equal(event.severity, 'low');
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
