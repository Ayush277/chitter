// Isolated-world helper: the only part of the extension that can use chrome.* APIs. Relays settings to page.js.
(function () {
  'use strict';
  if (window.__chitterBridge) return;      // may be injected again by "Caption this tab"
  window.__chitterBridge = true;
  const KEY = 'chitter';
  chrome.runtime.onMessage.addListener((msg, sender, reply) => {
    if (sender.id !== chrome.runtime.id || !msg || msg.type !== 'tab-audio' || typeof msg.streamId !== 'string') return;
    window.postMessage({ __chitter: 'tab-audio', streamId: msg.streamId }, '*');
    reply(true);
  });
  const SAVEABLE = { dub: 'boolean', enabled: 'boolean' };   // the page may only flip these two switches
  const send = s => window.postMessage({ __chitter: 'settings', settings: s || {} }, '*');
  const load = () => chrome.storage.local.get(KEY).then(r => send(r[KEY]));
  load();
  chrome.storage.onChanged.addListener((c, area) => { if (area === 'local' && c[KEY]) send(c[KEY].newValue); });
  window.addEventListener('message', ev => {
    const m = ev.data;
    if (ev.source !== window || !m || m.__chitter !== 'to-bridge') return;
    if (m.type === 'ready') load();
    else if (m.type === 'badge') chrome.runtime.sendMessage({ type: 'badge', on: !!m.on }).catch(() => {});
    else if (m.type === 'save' && m.patch && typeof m.patch === 'object') {
      chrome.storage.local.get(KEY).then(r => {
        const next = Object.assign({}, r[KEY]);
        for (const k of Object.keys(SAVEABLE)) if (typeof m.patch[k] === SAVEABLE[k]) next[k] = m.patch[k];
        return chrome.storage.local.set({ [KEY]: next });
      });
    }
  });
})();
