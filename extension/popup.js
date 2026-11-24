(async function () {
  const KEY = 'chitter', C = ChitterCore, $ = id => document.getElementById(id);
  const langs = Object.entries(C.LANG_NAMES);
  for (const id of ['target', 'sourceLang']) for (const [code, name] of langs) $(id).add(new Option(name, code));
  $('sourceLang').add(new Option('Detect automatically', 'auto'), 0);
  const saved = (await chrome.storage.local.get(KEY))[KEY] || {};
  const s = Object.assign({ enabled: true, dub: true, target: C.baseLang(navigator.language) || 'en', sourceLang: 'auto', allowCloudSpeech: false }, saved);
  $('enabled').checked = s.enabled; $('dub').checked = s.dub; $('target').value = s.target; $('sourceLang').value = s.sourceLang; $('cloud').checked = s.allowCloudSpeech;
  const save = () => chrome.storage.local.set({ [KEY]: Object.assign({}, saved, {
    enabled: $('enabled').checked, dub: $('dub').checked, target: $('target').value, sourceLang: $('sourceLang').value, allowCloudSpeech: $('cloud').checked }) });
  ['enabled', 'dub', 'target', 'sourceLang', 'cloud'].forEach(id => $(id).addEventListener('change', save));
  $('allsites').addEventListener('click', async () => {
    try {
      const ok = await chrome.permissions.request({ origins: ['<all_urls>'] });
      if (!ok) { $('msg').textContent = 'Permission not granted. Chitter stays on the known call sites.'; return; }
      const matches = ['<all_urls>'];
      try { await chrome.scripting.unregisterContentScripts({ ids: ['chitter-main', 'chitter-bridge'] }); } catch (e) {}
      await chrome.scripting.registerContentScripts([
        { id: 'chitter-main', matches, js: ['core.js', 'page.js'], runAt: 'document_start', allFrames: true, world: 'MAIN', persistAcrossSessions: true },
        { id: 'chitter-bridge', matches, js: ['bridge.js'], runAt: 'document_start', allFrames: true, persistAcrossSessions: true }]);
      $('msg').textContent = 'Done. Reload your call tab so Chitter can hook in.';
    } catch (e) { $('msg').textContent = 'Couldn\'t enable: ' + e.message; }
  });
})();
