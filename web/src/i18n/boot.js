'use strict';

const translations = /* AGY_TRANSLATIONS */ {};
const language = window.__AG_UI_LANGUAGE__ === 'en' ? 'en' : 'zh-CN';
document.documentElement.lang = language;

window.__agyI18n = Object.freeze({
  language,
  t(source) {
    if (language === 'zh-CN' && Object.prototype.hasOwnProperty.call(translations, source)) {
      return translations[source];
    }
    return source;
  },
  setLanguage(value) {
    if (value !== language && (value === 'zh-CN' || value === 'en')) {
      window.Android?.setUiLanguage?.(window.__AG_NATIVE_BRIDGE_TOKEN__, value);
    }
  },
});
