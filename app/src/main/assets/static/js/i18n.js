import zh from './locales/zh.js';
import en from './locales/en.js';
import ja from './locales/ja.js';

const catalogs = { zh, en, ja };
const locales = { zh: 'zh-CN', en: 'en-US', ja: 'ja-JP' };
const storageKey = 'silvercare_app_language';
const host = globalThis.window || globalThis;
const normalize = code => {
    const base = String(code || '').toLowerCase().split(/[-_]/)[0];
    return Object.hasOwn(catalogs, base) ? base : 'zh';
};
const bridge = () => host.AndroidSilverCare || host.Android;
let language = 'zh';
try { language = normalize(host.localStorage?.getItem(storageKey)); } catch { /* Storage may be unavailable. */ }
try {
    if (typeof bridge()?.getAppLanguage === 'function') language = normalize(bridge().getAppLanguage());
} catch { /* Browser fallback also supports bridge startup failures. */ }

export function t(source, values = []) {
    const translated = Object.hasOwn(catalogs[language], source) ? catalogs[language][source] : source;
    return String(translated).replace(/\{(\d+)\}/g, (match, index) => index in values ? String(values[index]) : match);
}

function apply(root = globalThis.document) {
    if (!root) return;
    if (root.documentElement) root.documentElement.lang = locales[language];
    const manifest = root.querySelector?.('link[rel="manifest"]');
    if (manifest) manifest.href = language === 'zh' ? 'static/manifest.json' : `static/manifest-${language}.json`;
    root.querySelectorAll?.('[data-i18n]').forEach(element => {
        element.textContent = t(element.getAttribute('data-i18n'));
    });
    for (const attribute of ['aria-label', 'title', 'placeholder', 'data-agent-prompt', 'content']) {
        root.querySelectorAll?.(`[data-i18n-${attribute}]`).forEach(element => {
            element.setAttribute(attribute, t(element.getAttribute(`data-i18n-${attribute}`)));
        });
    }
}

export const I18n = {
    language: () => language,
    locale: () => locales[language],
    t,
    apply,
    setLanguage(code, options = {}) {
        const next = normalize(code);
        if (options.native !== false && typeof bridge()?.setAppLanguage === 'function') bridge().setAppLanguage(next);
        const changed = language !== next;
        language = next;
        try { host.localStorage?.setItem(storageKey, next); } catch { /* Keep current session usable. */ }
        apply();
        if (changed && typeof host.dispatchEvent === 'function') host.dispatchEvent(new Event('app-language-changed'));
        return next;
    },
    openSettings() {
        const doc = globalThis.document;
        let dialog = doc.getElementById('browserLanguageSettings');
        if (!dialog) {
            dialog = doc.createElement('dialog');
            dialog.id = 'browserLanguageSettings';
            dialog.innerHTML = '<form method="dialog"><h2 data-i18n="语言"></h2><p data-i18n="界面、语音识别和朗读使用相同语言"></p><select data-i18n-aria-label="语言"><option value="zh">简体中文</option><option value="en">English</option><option value="ja">日本語</option></select><button data-i18n="关闭"></button></form>';
            dialog.style.cssText = 'background:#17212d;color:#fff;border:1px solid #607080;border-radius:16px;max-width:90%;padding:24px';
            dialog.querySelector('select').addEventListener('change', event => {
                I18n.setLanguage(event.target.value);
                // Reload recreates authored data labels in the selected language; persisted care records are untouched.
                host.location?.reload();
            });
            doc.body.appendChild(dialog);
        }
        dialog.querySelector('select').value = language;
        apply();
        dialog.showModal();
    }
};
host.I18n = I18n;
host.LONG_TERM_CARE_LANGUAGE_CHANGED = code => {
    const previous = language;
    I18n.setLanguage(code, {native:false});
    if (previous !== language) host.location?.reload();
};
if (globalThis.document?.readyState === 'loading') {
    globalThis.document.addEventListener('DOMContentLoaded', () => apply());
} else apply();
