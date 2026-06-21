import test from 'node:test';
import assert from 'node:assert/strict';

const elements = new Map();

function createElement(id) {
  const classes = new Set();
  return {
    id,
    textContent: '',
    innerHTML: '',
    style: {},
    dataset: {},
    classList: {
      add: (...names) => names.forEach((name) => classes.add(name)),
      remove: (...names) => names.forEach((name) => classes.delete(name)),
      toggle: (name, force) => {
        const next = force === undefined ? !classes.has(name) : Boolean(force);
        if (next) classes.add(name);
        else classes.delete(name);
        return next;
      },
      contains: (name) => classes.has(name)
    },
    querySelector: () => null,
    setAttribute(name, value) {
      this[name] = String(value);
    }
  };
}

globalThis.document = {
  body: createElement('body'),
  getElementById(id) {
    if (!elements.has(id)) elements.set(id, createElement(id));
    return elements.get(id);
  }
};

globalThis.window = {
  AndroidSilverCare: {
    isVoiceFirstEnabled: () => false
  },
  setTimeout,
  clearTimeout
};

const ui = await import('../../main/assets/static/js/ui.js');

test('caption helpers show user transcript and AI reply', () => {
  ui.updateUserCaption('前面有没有椅子');
  ui.updateAiCaption('前方两米有一把椅子，建议稍微向左。');

  assert.equal(elements.get('userCaption').textContent, '前面有没有椅子');
  assert.equal(elements.get('aiCaption').textContent, '前方两米有一把椅子，建议稍微向左。');
  assert.equal(elements.get('a11y-announcer').textContent, '银龄智护：前方两米有一把椅子，建议稍微向左。');
});

test('inquiry UI copies speech transcript into captions', () => {
  ui.updateInquiryUI({
    transcript: '帮我找门口',
    thinking: '正在定位门口方向',
    ms: 128
  });

  assert.equal(elements.get('userCaption').textContent, '帮我找门口');
  assert.equal(elements.get('thinkingBox').textContent, '正在定位门口方向');
  assert.match(elements.get('latVal').innerHTML, /128/);
});

test('caption visibility setting hides panel and suppresses live announcements', () => {
  const panel = elements.get('captionPanel');
  const announcer = elements.get('a11y-announcer');

  announcer.textContent = '';
  ui.setCaptionVisibility(false);
  ui.updateAiCaption('隐藏时仍缓存回复');

  assert.equal(ui.captionsEnabled(), false);
  assert.equal(panel.classList.contains('is-hidden'), true);
  assert.equal(panel['aria-hidden'], 'true');
  assert.equal(elements.get('aiCaption').textContent, '隐藏时仍缓存回复');
  assert.equal(announcer.textContent, '');

  ui.setCaptionVisibility(true);
  ui.updateAiCaption('字幕重新开启');

  assert.equal(ui.captionsEnabled(), true);
  assert.equal(panel.classList.contains('is-hidden'), false);
  assert.equal(panel['aria-hidden'], 'false');
  assert.equal(announcer.textContent, '银龄智护：字幕重新开启');
});

test('status can update refresh mode without entering the TTS queue', () => {
  const spoken = [];
  window.AndroidSilverCare = {
    isVoiceFirstEnabled: () => true,
    speak: (text) => spoken.push(text)
  };

  ui.updateStatus('手动刷新', 'active', { speak: false });

  assert.equal(elements.get('statusText').textContent, '手动刷新');
  assert.equal(elements.get('statusPill').dataset.state, 'active');
  assert.deepEqual(spoken, []);

  ui.updateStatus('自动刷新', 'active');
  assert.deepEqual(spoken, ['状态：自动刷新']);
});

test('fall alert asks for confirmation through speech even outside normal status TTS', () => {
  const spoken = [];
  window.AndroidSilverCare = {
    isVoiceFirstEnabled: () => false,
    speak: (text) => spoken.push(text)
  };

  ui.showFallAlert(10, '检测到疑似摔倒，请确认。');

  assert.equal(elements.get('fallCountdown').textContent, '10');
  assert.equal(elements.get('fallAlert')['aria-hidden'], 'false');
  assert.equal(spoken[0], '摔倒报警触发，请问您摔倒了吗？');
});
