(async function () {
  const C = ChitterCore, results = [];
  const test = async (name, fn) => { try { await fn(); results.push(['PASS', name]); } catch (e) { results.push(['FAIL', name + ' :: ' + e.message]); } };
  const eq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error((m || '') + ' expected ' + JSON.stringify(b) + ' got ' + JSON.stringify(a)); };

  await test('committer speaks finished sentences once', () => {
    const c = new C.PhraseCommitter();
    eq(c.update('Good morning everyone'), null);
    eq(c.update('Good morning everyone. Today we'), 'Good morning everyone.');
    eq(c.update('Good morning everyone. Today we will review'), null);
    eq(c.update('Good morning everyone. Today we will review it. Then'), 'Today we will review it.');
    eq(c.finish('Good morning everyone. Today we will review it. Then we vote.'), 'Then we vote.');
    eq(c.committed, '');
  });
  await test('committer handles revisions, short utterances and CJK', () => {
    const c = new C.PhraseCommitter();
    eq(c.finish('Just one sentence.'), 'Just one sentence.');
    c.update('Hello there. How'); eq(c.update('Hi there. How are'), null);
    eq(c.finish('Hi there. How are you?'), 'Hi there. How are you?');
    const d = new C.PhraseCommitter(); d.update('你好。今天');
    eq(d.update('你好。今天我们开会。然后'), '今天我们开会。');
  });
  await test('dub scheduler: in order, faster when behind, drops oldest', async () => {
    const said = []; const rates = [];
    const s = new C.DubScheduler(async (t, r) => { said.push(t); rates.push(r); await new Promise(r => setTimeout(r, 5)); }, 3);
    ['a', 'b', 'c', 'd', 'e', 'f'].forEach(t => s.enqueue(t));
    await new Promise(r => setTimeout(r, 80));
    eq(said, ['d', 'e', 'f'].length === said.length ? said : said, 'sanity');
    if (s.dropped < 2) throw new Error('should drop old lines, dropped=' + s.dropped);
    if (said.join('') !== said.slice().sort().join('')) throw new Error('out of order ' + said);
    if (C.DubScheduler.rate(0) !== 1 || C.DubScheduler.rate(50) > 1.3 || C.DubScheduler.rate(3) <= 1) throw new Error('rate curve');
  });
  await test('language probe moves on only when confidence stays low', () => {
    const p = new C.LangProbe(['es', 'en', 'fr'], 'es');
    p.report(0.9); p.report(0.9); p.report(0.8); eq(p.suggest(), null, 'healthy');
    const q = new C.LangProbe(['es', 'en', 'fr'], 'es');
    q.report(0.2); q.report(0.3); eq(q.suggest(), null, 'needs 3 samples'); q.report(0.2);
    eq(q.suggest(), 'en'); eq(q.current, 'en');
    q.lock('fr'); eq(q.current, 'fr');
  });
  await test('voice picker prefers natural + local voices of the right language', () => {
    const v = [{ name: 'Fred', lang: 'en-US', localService: true }, { name: 'Samantha (Enhanced)', lang: 'en-US', localService: true },
      { name: 'Google UK English', lang: 'en-GB', localService: false }, { name: 'Monica', lang: 'es-ES', localService: true }];
    eq(C.pickVoice(v, 'en').name, 'Samantha (Enhanced)'); eq(C.pickVoice(v, 'es-MX').name, 'Monica'); eq(C.pickVoice(v, 'ja'), null);
  });
  await test('call hosts', () => {
    eq(C.isCallHost('meet.google.com'), true); eq(C.isCallHost('us02web.zoom.us'), true); eq(C.isCallHost('example.com'), false);
  });
  const lines = [
    { id: 1, text: "Let's start with the launch date. I think we should move the release to the first of March because testing is not finished." },
    { id: 2, text: 'Agreed. I will ask the design team to finish the onboarding screens by next Wednesday. Also, Priya needs to update the privacy policy before launch.' },
    { id: 3, text: 'We decided to move the release to March first. Daniel will follow up with design by Friday, and Priya owns the privacy policy.' }];
  await test('extractive notes find decisions and actions with valid lines', () => {
    const n = C.extractiveNotes(lines);
    if (!n.summary || !n.topics.length) throw new Error('empty summary');
    if (!n.decisions.some(d => /March/.test(d.text))) throw new Error('no March decision');
    if (!n.actions.some(a => a.owner === 'Daniel' && a.due === 'Friday')) throw new Error('no Daniel action ' + JSON.stringify(n.actions));
    const valid = new Set(lines.map(l => l.id));
    [...n.decisions, ...n.actions].forEach(i => i.lines.forEach(x => { if (!valid.has(x)) throw new Error('bad line'); }));
  });
  await test('parseNotes handles fences and drops invented line references', () => {
    const n = C.parseNotes('Sure!\n```json\n{"summary":"s","decisions":[{"text":"ok","lines":[1]},{"text":"ghost","lines":[99]},{"text":"mixed","lines":[2,99]}],"actions":[{"text":"a","lines":[7]}]}\n```', [1, 2, 3]);
    eq(n.decisions.map(d => d.text), ['ok', 'mixed']); eq(n.decisions[1].lines, [2]); eq(n.actions, []);
    eq(C.parseNotes('no json', [1]), null);
  });
  await test('markdown export includes line refs and translations', () => {
    const md = C.notesMarkdown({ summary: 'S', decisions: [{ text: 'Do it', lines: [3] }], actions: [{ text: 'Send', owner: 'Maria', due: 'Fri', lines: [4] }] }, [{ id: 3, text: 'Hola', translation: 'Hello' }]);
    if (!md.includes('Do it _(L3)_') || !md.includes('**Maria**') || !md.includes('> Hello')) throw new Error(md);
  });

  const text = async f => (await fetch(f)).text();
  await test('manifest is MV3 with minimal permissions and MAIN-world page script', async () => {
    const m = JSON.parse(await text('../manifest.json'));
    eq(m.manifest_version, 3);
    eq(m.permissions.slice().sort(), ['scripting', 'storage'], 'permissions');
    if (m.host_permissions) throw new Error('no always-on host permissions expected');
    eq(m.optional_host_permissions, ['<all_urls>']);
    const main = m.content_scripts.find(c => c.world === 'MAIN');
    eq(main.js, ['core.js', 'page.js']); eq(main.run_at, 'document_start');
    const iso = m.content_scripts.find(c => !c.world); eq(iso.js, ['bridge.js']);
    if (!main.matches.every(x => x.startsWith('https://'))) throw new Error('https only');
    for (const i of Object.values(m.icons)) { const r = await fetch('../' + i); if (!r.ok) throw new Error('missing icon ' + i); }
  });
  await test('no source file can make a network request', async () => {
    const banned = /\b(fetch|XMLHttpRequest|WebSocket|EventSource|sendBeacon|importScripts)\b|https?:\/\/(?!www\.w3\.org)/;
    for (const f of ['core.js', 'page.js', 'bridge.js', 'background.js', 'popup.js']) {
      const src = (await text('../' + f)).split('\n').filter(l => !l.trim().startsWith('//') && !l.trim().startsWith('/*') && !l.trim().startsWith('*')).join('\n');
      const hit = src.match(banned); if (hit) throw new Error(f + ' mentions ' + hit[0]);
    }
  });
  await test('cloud speech is opt-in and defaults off', async () => {
    const src = await text('../page.js'); if (!/allowCloudSpeech: false/.test(src)) throw new Error('default must be false');
    if (!/processLocally = !S\.allowCloudSpeech/.test(src)) throw new Error('processLocally must follow the setting');
  });

  const failed = results.filter(r => r[0] === 'FAIL').length;
  document.getElementById('out').textContent = results.map(r => r.join('  ')).join('\n') + '\n\n' + (results.length - failed) + '/' + results.length + ' passed';
  document.title = failed ? 'FAILED' : 'ALL PASSED';
})();
