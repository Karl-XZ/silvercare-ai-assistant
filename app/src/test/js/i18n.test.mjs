import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { I18n } from '../../main/assets/static/js/i18n.js';

test('catalog parity and complete English and Japanese translations', async () => {
  const catalogs = await Promise.all(['zh','en','ja'].map(async code => (await import(`../../main/assets/static/js/locales/${code}.js`)).default));
  for (const catalog of catalogs) assert.deepEqual(Object.keys(catalog).sort(), Object.keys(catalogs[0]).sort());
  for (const [source, english] of Object.entries(catalogs[1])) {
    assert.ok(english.trim(), source);
    assert.doesNotMatch(english, /[\u3400-\u9fff]/u, source);
    assert.ok(catalogs[2][source].trim(), source);
    assert.doesNotMatch(catalogs[2][source], /[这请护录识侧联网还没务风险]/u, source);
  }
});

test('language normalization, templates and authored content preserve values', () => {
  I18n.setLanguage('en', {native:false});
  assert.equal(I18n.t('步骤 {0}', [3]), 'Step 3');
  assert.equal(I18n.t('我说：{0}', ['用户原文']), 'You: 用户原文');
  I18n.setLanguage('ja', {native:false});
  assert.equal(I18n.t('步骤 {0}', [4]), 'ステップ4');
  I18n.setLanguage('unsupported', {native:false});
  assert.equal(I18n.language(), 'zh');
});

test('static HTML explicitly marks authored labels and loads localization', () => {
  const html = fs.readFileSync(new URL('../../main/assets/index.html', import.meta.url),'utf8');
  assert.match(html, /i18n.js/);
  assert.match(html, /data-i18n/);
});

test('DOM localization updates labels and accessibility without touching user content', () => {
  const labels = [
    {source:'银龄智护',textContent:'银龄智护', getAttribute(){return this.source;}},
    {source:'按住提问',textContent:'按住提问', getAttribute(){return this.source;}}
  ];
  const field = {value:'用户原文',attributes:{},getAttribute(){return '输入照护数据助手问题';},setAttribute(k,v){this.attributes[k]=v;}};
  const doc = {documentElement:{},querySelectorAll(selector){
    if(selector==='[data-i18n]')return labels;
    if(selector==='[data-i18n-placeholder]' || selector==='[data-i18n-aria-label]')return [field];
    return [];
  }};
  I18n.setLanguage('en',{native:false}); I18n.apply(doc);
  assert.equal(labels[1].textContent,'Hold to ask');
  assert.equal(doc.documentElement.lang,'en-US');
  assert.equal(field.attributes['aria-label'],'Enter a question for the care data assistant');
  assert.equal(field.value,'用户原文');
  I18n.setLanguage('ja',{native:false}); I18n.apply(doc);
  assert.equal(labels[1].textContent,'長押しで質問');
  assert.equal(doc.documentElement.lang,'ja-JP');
  assert.equal(field.value,'用户原文');
});

test('native getter is authoritative and browser storage restores language', async () => {
  globalThis.window = {localStorage:{getItem:()=> 'ja'},AndroidSilverCare:{getAppLanguage:()=> 'en-US'}};
  const native = await import('../../main/assets/static/js/i18n.js?native-test');
  assert.equal(native.I18n.language(),'en');
  delete window.AndroidSilverCare;
  const browser = await import('../../main/assets/static/js/i18n.js?browser-test');
  assert.equal(browser.I18n.language(),'ja');
  delete globalThis.window;
});

test('selected language reaches dynamic fall, task, reports and care assistant branches', async () => {
  const elements = new Map();
  const element = id => ({id,textContent:'',innerHTML:'',style:{},dataset:{},classList:{add(){},remove(){},toggle(){}},setAttribute(){},addEventListener(){},querySelector(){return null;}});
  globalThis.document={body:element('body'),querySelectorAll(){return [];},getElementById(id){if(!elements.has(id))elements.set(id,element(id));return elements.get(id);}};
  globalThis.window={setTimeout:()=>0,clearTimeout(){},AndroidSilverCare:{isVoiceFirstEnabled:()=>false,speak(){}}};
  const ui = await import('../../main/assets/static/js/ui.js');
  const management = await import('../../main/assets/static/js/management.js');
  for(const code of ['en','ja']) {
    I18n.setLanguage(code,{native:false});
    ui.showFallAlert(7);
    assert.equal(elements.get('fallTitle').textContent,I18n.t('疑似摔倒'));
    assert.equal(elements.get('fallCountdown').textContent,'7');
    ui.updateTaskUI({plan:[{}]});
    assert.ok(elements.get('taskList').innerHTML.includes(code==='en'?'Step 1':'ステップ1'));
    management.setupManagementDashboard();
    if(code==='en') {
      for(const id of ['careResidentList','careAgentProfile','careRiskList','careTaskList','careChartLabels','careMetricGrid','careAgentMessages']) {
        assert.doesNotMatch(elements.get(id).innerHTML, /[\u3400-\u9fff]/u, id);
      }
    }
    const report=management.buildDailyReport();
    if(code==='en')assert.doesNotMatch(report,/[\u3400-\u9fff]/u);
    assert.ok(report.includes(code==='en'?'Today':'今日'));
    const request=code==='en'?'Record that I took my medication':'血圧の薬を飲んだことを記録して';
    const reply=management.buildCareAgentReply(undefined,request);
    assert.equal(reply.intent,'record');
    assert.equal(reply.action.recordType,'用药');
    assert.equal(reply.action.text,request);
    if(code==='en')assert.doesNotMatch(reply.speech,/[\u3400-\u9fff]/u);
    const budget=management.buildCareAgentReply(undefined,code==='en'?'Is there enough budget?':'予算はまだ足りていますか？');
    assert.equal(budget.intent,'budget_advice');
    const risk=management.buildCareAgentReply(undefined,code==='en'?'How can I reduce fall risk?':'夜中の転倒リスクにはどう対応しますか？');
    assert.equal(risk.intent,'risk_advice');
  }
  I18n.setLanguage('zh',{native:false});
  delete globalThis.window;delete globalThis.document;
});

test('all explicit authored call sites and HTML annotations have catalog entries', async () => {
  const catalog=(await import('../../main/assets/static/js/locales/zh.js')).default;
  const dir=new URL('../../main/assets/static/js/',import.meta.url);
  for(const name of ['ui.js','input.js','main.js','config.js','management.js','network.js','care_store.js']) {
    const source=fs.readFileSync(new URL(name,dir),'utf8');
    for(const match of source.matchAll(/\bt\(("(?:[^"\\]|\\.)*")/g)) {
      const key=JSON.parse(match[1]);
      assert.ok(Object.hasOwn(catalog,key), `${name}: ${key}`);
    }
  }
  const html=fs.readFileSync(new URL('../../main/assets/index.html',import.meta.url),'utf8');
  for(const match of html.matchAll(/data-i18n(?:-[\w-]+)?="([^"]*)"/g)) assert.ok(Object.hasOwn(catalog,match[1]),match[1]);
});

test('English detector labels remain specific and Japanese precision guidance uses shared terminology', async () => {
  const elements=new Map();
  const element=()=>({textContent:'',innerHTML:'',style:{},dataset:{},classList:{add(){},remove(){},toggle(){}},setAttribute(){},querySelector(){return null;}});
  globalThis.document={body:element(),getElementById(id){if(!elements.has(id))elements.set(id,element());return elements.get(id);}};
  globalThis.window={setTimeout:()=>0,clearTimeout(){}};
  const ui=await import('../../main/assets/static/js/ui.js?object-label-regression');
  I18n.setLanguage('en',{native:false});
  ui.updateNavUI({objects:['fork','knife','spoon','apple'].map(name=>({name,distance:2}))});
  for(const name of ['fork','knife','spoon','apple'])assert.ok(elements.get('objList').innerHTML.includes(name),name);
  I18n.setLanguage('ja',{native:false});
  assert.equal(I18n.t('精确引导'),'精密誘導');
  const japanese=(await import('../../main/assets/static/js/locales/ja.js')).default;
  assert.ok(Object.values(japanese).every(text=>!text.includes('詳細ガイド')));
  const source=fs.readFileSync(new URL('../../main/assets/static/js/i18n.js',import.meta.url),'utf8');
  assert.match(source,/select[^>]+data-i18n-aria-label="语言"/);
  I18n.setLanguage('zh',{native:false});
  delete globalThis.document;delete globalThis.window;
});
