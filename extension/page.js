/* Chitter for Chrome: runs inside the meeting page (MAIN world) so it can read the call's remote audio tracks directly.
   Everything is on-device: Chrome's built-in SpeechRecognition (processLocally), Translator, LanguageDetector,
   LanguageModel and the system's speechSynthesis. This file makes no network requests (a test enforces that). */
(function () {
  'use strict';
  if (window.__chitterLoaded) return;
  window.__chitterLoaded = true;
  const C = window.ChitterCore;
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;

  // ---------------------------------------------------------------- settings (relayed from chrome.storage by bridge.js)
  const defaults = {
    enabled: true, target: C.baseLang(navigator.language) || 'en', dub: true, sourceLang: 'auto',
    candidates: ['en', 'es', 'fr', 'de', 'zh', 'ja', 'ko', 'hi', 'pt', 'it', 'ru'], allowCloudSpeech: false, showRibbon: true, captionMe: true,
  };
  let S = Object.assign({}, defaults);
  window.addEventListener('message', ev => {
    if (ev.source === window && ev.data && ev.data.__chitter === 'tab-audio' && typeof ev.data.streamId === 'string') { startTabAudio(ev.data.streamId); return; }
    if (ev.source !== window || !ev.data || ev.data.__chitter !== 'settings') return;
    const s = ev.data.settings || {};
    for (const k of Object.keys(defaults)) if (typeof s[k] === typeof defaults[k]) S[k] = s[k];
    if (typeof s.candidates === 'object' && Array.isArray(s.candidates)) S.candidates = s.candidates.filter(x => typeof x === 'string').slice(0, 20);
    ui.applySettings();
  });
  const toBridge = msg => window.postMessage(Object.assign({ __chitter: 'to-bridge' }, msg), '*');

  // ---------------------------------------------------------------- overlay (shadow DOM so the site's CSS can't touch it)
  let ui;
  try { ui = (() => {
    const host = document.createElement('div');
    host.style.cssText = 'all:initial;position:fixed;inset:0;pointer-events:none;z-index:2147483647';
    const root = host.attachShadow({ mode: 'closed' });
    // Built with DOM calls, never innerHTML: Google Meet (and other Google apps) enforce Trusted Types, which makes
    // assigning an HTML string throw and would kill this whole script.
    const el = (tag, props, ...kids) => { const e = document.createElement(tag);
      for (const k in props || {}) { if (k === 'class') e.className = props[k]; else e.setAttribute(k, props[k]); }
      kids.forEach(c => e.append(c)); return e; };
    const style = document.createElement('style');
    style.textContent = `
:host{all:initial}
*{box-sizing:border-box;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
.rib{position:fixed;left:50%;bottom:90px;transform:translateX(-50%);width:min(860px,92vw);background:rgba(0,0,0,.92);color:#F4F6FF;border:1.5px solid rgba(0,229,255,.65);border-radius:24px;padding:14px 22px;pointer-events:auto;opacity:0;transition:opacity .2s;box-shadow:0 0 26px rgba(0,229,255,.38),0 10px 40px rgba(0,0,0,.6)}
.rib.on{opacity:1}.rib.hover{opacity:.12}
.who{display:flex;gap:10px;align-items:baseline}
.chip{flex:none;width:22px;height:22px;border-radius:50%;background:#00E5FF;color:#000;font:700 12px system-ui;display:grid;place-items:center;box-shadow:0 0 10px rgba(0,229,255,.9)}
.o{font-size:15px;color:#A9AFCB}.t{font:600 20px ui-rounded,system-ui,sans-serif;color:#3DFFA8;margin-top:4px}
.u{height:3px;border-radius:999px;background:linear-gradient(90deg,#00E5FF,#FF2BD6);box-shadow:0 0 8px #00E5FF;margin-top:9px;width:0;transition:width .25s ease-out}
.pill{position:fixed;top:14px;right:14px;display:flex;gap:7px;align-items:center;background:rgba(0,0,0,.93);color:#F4F6FF;border:1px solid rgba(0,229,255,.5);border-radius:999px;padding:7px 12px;font-size:12px;box-shadow:0 0 18px rgba(0,229,255,.3);pointer-events:auto;opacity:0;transition:opacity .2s}
.pill.on{opacity:1}.dot{width:9px;height:9px;border-radius:50%;background:#FF3B6B;box-shadow:0 0 8px currentColor}
.pill button{all:unset;cursor:pointer;padding:3px 10px;border-radius:999px;border:1px solid rgba(0,229,255,.55)}
.pill button:hover,.pill button:focus-visible{background:#00E5FF;color:#000;box-shadow:0 0 12px #00E5FF;outline:none}
.toast{position:fixed;top:62px;right:14px;max-width:340px;background:#0B0B12;color:#F4F6FF;border:1.5px solid rgba(255,43,214,.7);border-radius:20px;padding:13px 16px;font-size:13px;box-shadow:0 0 22px rgba(255,43,214,.35);pointer-events:auto;display:none}
.toast button{margin-top:8px;all:unset;cursor:pointer;background:#FF2BD6;color:#000;border-radius:999px;padding:5px 14px;font-weight:700}
.panel{position:fixed;top:8px;right:8px;height:calc(100% - 16px);width:min(460px,calc(100vw - 16px));background:#000;color:#F4F6FF;border:1.5px solid rgba(166,107,255,.6);border-radius:26px;box-shadow:0 0 30px rgba(166,107,255,.35);pointer-events:auto;transform:translateX(calc(100% + 60px));transition:transform .25s ease-out;padding:18px;overflow:auto;font-size:14px;line-height:1.45}
.panel.on{transform:none}.panel h3{font:700 18px ui-rounded,system-ui,sans-serif;color:#00E5FF;margin:14px 0 6px}
.item{padding:9px 12px;background:#15151F;border:1px solid rgba(166,107,255,.5);border-radius:16px;margin:7px 0;cursor:pointer}.item:hover,.item:focus{border-color:#FF2BD6;background:rgba(255,43,214,.18);box-shadow:0 0 14px rgba(255,43,214,.4);outline:none}
.line{padding:8px 12px;background:#0B0B12;border:1px solid transparent;border-radius:14px;margin:5px 0}.line.hit{background:rgba(255,43,214,.18);border-color:#FF2BD6;box-shadow:0 0 14px rgba(255,43,214,.4)}
.line b{font:11px monospace;color:#00E5FF;margin-right:6px}.tr{color:#3DFFA8}
.panel button.act{all:unset;cursor:pointer;background:#00E5FF;color:#000;border-radius:999px;padding:6px 14px;font-weight:700;margin:0 6px 6px 0;box-shadow:0 0 12px rgba(0,229,255,.5)}
.panel button.act:focus-visible,.toast button:focus-visible{outline:3px solid #F4F6FF;outline-offset:2px}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
`;
    root.append(style,
      el('div', { class: 'rib', id: 'rib', role: 'status', 'aria-live': 'polite' },
        el('div', { class: 'who' }, el('span', { class: 'chip', id: 'chip' }, 'A'), el('div', {}, el('div', { class: 'o', id: 'o' }))),
        el('div', { class: 't', id: 't' }), el('div', { class: 'u', id: 'u' })),
      el('div', { class: 'pill', id: 'pill' }, el('span', { class: 'dot', id: 'dot' }), el('span', { id: 'status' }, 'Chitter'),
        el('button', { id: 'bVoice', title: 'Toggle voice-over', 'aria-label': 'Toggle voice-over' }, 'Voice'),
        el('button', { id: 'bNotes', 'aria-label': 'Open notes' }, 'Notes'),
        el('button', { id: 'bHide', 'aria-label': 'Hide Chitter' }, '×')),
      el('div', { class: 'toast', id: 'toast', role: 'alert' }, el('span', { id: 'toastText' }), el('br'), el('button', { id: 'toastBtn' }, 'OK')),
      el('aside', { class: 'panel', id: 'panel', 'aria-label': 'Chitter notes' },
        el('button', { class: 'act', id: 'pClose' }, 'Close'), el('button', { class: 'act', id: 'pWrite' }, 'Write notes'),
        el('button', { class: 'act', id: 'pCopy' }, 'Copy Markdown'), el('button', { class: 'act', id: 'pSave' }, 'Download .md'),
        el('div', { id: 'pBody' })));
    const $ = id => root.getElementById(id);
    let hideTimer, reduce = matchMedia('(prefers-reduced-motion: reduce)').matches, mounted = false;
    const mount = () => { if (!mounted) { mounted = true; (document.body || document.documentElement).appendChild(host); } };
    const rib = $('rib');
    // hover → see-through (the ribbon never blocks the call's own controls for long)
    rib.addEventListener('mouseenter', () => rib.classList.add('hover')); rib.addEventListener('mouseleave', () => rib.classList.remove('hover'));
    const api = {
      applySettings() { $('bVoice').style.opacity = S.dub ? 1 : .45; if (!S.enabled || !S.showRibbon) rib.classList.remove('on'); },
      show(speaker, original, translation, final) {
        if (!S.enabled || !S.showRibbon) return; mount();
        $('chip').textContent = String.fromCharCode(65 + (speaker % 26)); $('o').textContent = original;
        if (translation != null) $('t').textContent = translation; else if (final) $('t').textContent = '';
        $('u').style.width = final ? '100%' : '40%'; rib.classList.add('on');
        clearTimeout(hideTimer); hideTimer = setTimeout(() => rib.classList.remove('on'), 3000);   // fades after 3 s of silence
      },
      setTranslation(t) { $('t').textContent = t; },
      status(text, live) { mount(); $('pill').classList.add('on'); $('status').textContent = text; $('dot').style.background = live ? '#FF3B6B' : '#3DFFA8'; },
      hidePill() { $('pill').classList.remove('on'); },
      toast(text, label, fn) { mount(); $('toastText').textContent = text; const b = $('toastBtn'); b.textContent = label || 'OK'; $('toast').style.display = 'block';
        b.onclick = () => { $('toast').style.display = 'none'; if (fn) fn(); }; },
      onVoice(fn) { $('bVoice').onclick = fn; }, onNotes(fn) { $('bNotes').onclick = fn; }, onHide(fn) { $('bHide').onclick = fn; },
      panel: { el: $('panel'), body: $('pBody'), open() { mount(); $('panel').classList.add('on'); }, close() { $('panel').classList.remove('on'); },
        bind(w, c, s, x) { $('pWrite').onclick = w; $('pCopy').onclick = c; $('pSave').onclick = s; $('pClose').onclick = x; } },
      reduce,
    };
    return api;
  })(); } catch (e) {
    console.error('[Chitter] overlay failed to start:', e);
    const noop = () => {};
    ui = { applySettings: noop, show: noop, setTranslation: noop, status: noop, hidePill: noop, toast: (t) => console.warn('[Chitter]', t), onVoice: noop, onNotes: noop, onHide: noop,
      panel: { body: document.createElement('div'), open: noop, close: noop, bind: noop }, reduce: false };
  }

  // ---------------------------------------------------------------- on-device language tools
  let detectorP = null;
  const detector = () => detectorP || (detectorP = (async () => {
    try { if (!window.LanguageDetector) return null; const a = await LanguageDetector.availability(); if (a === 'unavailable') return null;
      return await LanguageDetector.create(); } catch (e) { return null; } })());
  async function detectLang(text) {
    const d = await detector(); if (!d || text.length < 20) return null;
    try { const r = await d.detect(text); return r && r[0] ? { lang: C.baseLang(r[0].detectedLanguage), confidence: r[0].confidence } : null; } catch (e) { return null; }
  }

  const translators = new Map();
  function getTranslator(src, dst) {
    const key = src + '>' + dst;
    if (translators.has(key)) return translators.get(key);
    const p = (async () => {
      if (!window.Translator) return null;
      try {
        const opts = { sourceLanguage: src, targetLanguage: dst };
        const a = await Translator.availability(opts);
        if (a === 'unavailable') return null;
        if (a === 'available' || navigator.userActivation.isActive) return await Translator.create(opts);
        // Chrome needs a click to download a translation model.
        ui.toast('Chitter needs to download the ' + (C.LANG_NAMES[src] || src) + ' → ' + (C.LANG_NAMES[dst] || dst) + ' translation model (on-device).', 'Download', () => {
          translators.set(key, Translator.create(opts).catch(() => null));
        });
        translators.delete(key); return null;
      } catch (e) { translators.delete(key); return null; }
    })();
    translators.set(key, p); return p;
  }
  async function translate(text, src, dst) {
    if (C.baseLang(src) === C.baseLang(dst)) return null;
    const t = await getTranslator(C.baseLang(src), C.baseLang(dst));
    if (!t) return null;
    try { return (await t.translate(text)).trim(); } catch (e) { return null; }
  }

  // ---------------------------------------------------------------- voice-over
  let voices = [];
  const loadVoices = () => { voices = speechSynthesis.getVoices(); };
  if (window.speechSynthesis) { loadVoices(); speechSynthesis.addEventListener('voiceschanged', loadVoices); }
  const dub = new C.DubScheduler((text, rate) => new Promise((resolve, reject) => {
    if (!window.speechSynthesis) return reject(new Error('no speech synthesis'));
    const u = new SpeechSynthesisUtterance(text);
    const v = C.pickVoice(voices, S.target); if (v) { u.voice = v; u.lang = v.lang; } else u.lang = C.BCP47[S.target] || S.target;
    u.rate = rate;
    const guard = setTimeout(() => { speechSynthesis.cancel(); resolve(); }, 20000);
    u.onend = () => { clearTimeout(guard); resolve(); }; u.onerror = () => { clearTimeout(guard); resolve(); };
    speechSynthesis.speak(u);
  }));

  // ---------------------------------------------------------------- transcript
  const lines = [];            // {id, text, translation, speaker, lang}
  let lastRibbonTranslate = 0;

  // ---------------------------------------------------------------- one pipeline per remote audio track (= per participant)
  class Pipeline {
    constructor(key, track, index, isMe) {
      this.key = key; this.track = track; this.index = index; this.active = true; this.isMe = !!isMe; this.errors = 0;
      this.committer = new C.PhraseCommitter();
      const start = S.sourceLang === 'auto' ? (S.candidates.includes(S.target) ? S.target : S.candidates[0]) : S.sourceLang;
      this.probe = new C.LangProbe(S.candidates.length ? S.candidates : ['en'], start);
      this.lang = this.probe.current || start;
      track.addEventListener('ended', () => this.stop());
      this.begin();
    }
    async begin() {
      if (!SR) { ui.toast('This browser has no speech recognition. Update Chrome.', 'OK'); return; }
      try {   // check the on-device model for this language; never fall back to cloud unless the user allowed it
        if (SR.available) {
          const a = await SR.available({ langs: [C.BCP47[this.lang] || this.lang], processLocally: true });
          if (a === 'unavailable' && !S.allowCloudSpeech) { return this.nextLang('No on-device speech for ' + (C.LANG_NAMES[this.lang] || this.lang)); }
          if (a === 'downloadable' || a === 'downloading') {
            if (!navigator.userActivation.isActive) {
              ui.toast('Chitter needs to download on-device speech for ' + (C.LANG_NAMES[this.lang] || this.lang) + '.', 'Download', async () => {
                try { await SR.install({ langs: [C.BCP47[this.lang] || this.lang], processLocally: true }); } catch (e) {}
                this.begin();
              });
              return;
            }
            try { await SR.install({ langs: [C.BCP47[this.lang] || this.lang], processLocally: true }); } catch (e) {}
          }
        }
      } catch (e) { /* older Chrome without available(): try anyway */ }
      this.listen();
    }
    listen() {
      if (!this.active) return;
      const r = new SR();
      r.continuous = true; r.interimResults = true; r.lang = C.BCP47[this.lang] || this.lang;
      if ('processLocally' in r) r.processLocally = !S.allowCloudSpeech;
      r.onresult = e => { this.errors = 0; if (!this.isMe) watch.result(); this.onResult(e); };
      r.onerror = e => this.onError(r, e.error);
      // Restart when Chrome ends a session; back off while it keeps failing.
      r.onend = () => { if (this.active && this.rec === r) setTimeout(() => { if (this.active && this.rec === r) this.listen(); }, Math.min(8000, 120 * Math.pow(2, this.errors))); };
      this.rec = r;
      try { r.start(this.track.clone()); }   // Chrome ≥ 139 accepts a MediaStreamTrack here
      catch (e) { this.active = false;
        ui.toast('This Chrome version can\'t transcribe a call\'s audio on-device yet (needs SpeechRecognition with audio-track input). Update Chrome.', 'OK'); }
    }
    onError(rec, code) {
      if (code === 'no-speech') return;
      if (code === 'aborted') {
        if (rec.__chitterAbort || !this.active) return;      // we aborted it ourselves
        this.errors++;
        // Two recognisers fighting: keep the call, drop the microphone.
        if (guard.aborted() && pipelines.has('me') && pipelines.size > 1) {
          pipelines.get('me').stop();
          ui.toast('This browser can only transcribe one stream at a time, so Chitter stopped captioning your own voice and kept the call.', 'OK');
        }
        return;
      }
      this.errors++;
      console.warn('[Chitter] speech error:', code, 'language', this.lang);
      if (code === 'language-not-supported') { this.nextLang(); if (this.errors < this.probe.candidates.length) return; }
      const message = C.speechErrorMessage(code);
      if (message && this.errors <= 1 + (code === 'language-not-supported' ? this.probe.candidates.length : 0)) ui.toast(message, 'OK');
      if (this.errors >= 6) { this.stop(); ui.status('Chitter stopped: speech error "' + code + '"', false); }
    }
    abort() { if (this.rec) { this.rec.__chitterAbort = true; try { this.rec.abort(); } catch (e) {} } }
    nextLang(why) {
      const n = this.probe.suggest() || this.probe.candidates[(this.probe.candidates.indexOf(this.lang) + 1) % this.probe.candidates.length];
      if (n && n !== this.lang) { this.switchTo(n); }
    }
    switchTo(lang) {
      if (lang === this.lang) return;
      this.lang = lang; this.probe.lock(lang);
      this.abort();      // onend restarts with the new language
      if (!this.rec) this.begin();
    }
    onResult(e) {
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const res = e.results[i], alt = res[0], text = (alt.transcript || '').trim();
        if (!text) continue;
        if (res.isFinal) this.final(text, alt.confidence); else this.partial(text);
      }
    }
    partial(text) {
      ui.show(this.index, text, null, false);
      const phrase = this.committer.update(text);
      if (phrase) this.say(phrase);
      if (!this.isTarget() && Date.now() - lastRibbonTranslate > 1200) {
        lastRibbonTranslate = Date.now();
        translate(text, this.lang, S.target).then(t => { if (t) ui.setTranslation(t); });
      }
    }
    async final(text, confidence) {
      if (confidence > 0) this.probe.report(confidence);
      const id = lines.length + 1, line = { id, text, translation: null, speaker: this.index, lang: this.lang };
      lines.push(line);
      ui.show(this.index, text, null, true);
      const rest = this.committer.finish(text);
      if (rest) this.say(rest);
      if (!this.isTarget()) translate(text, this.lang, S.target).then(t => { if (t) { line.translation = t; ui.setTranslation(t); } });
      // language safety nets: confident text-language disagreement, or sustained low recognition confidence
      const d = await detectLang(text);
      if (S.sourceLang === 'auto') {
        if (d && d.confidence > 0.85 && d.lang !== C.baseLang(this.lang) && this.probe.candidates.includes(d.lang)) return this.switchTo(d.lang);
        const s = this.probe.suggest(); if (s) this.switchTo(s);
      }
    }
    isTarget() { return C.baseLang(this.lang) === C.baseLang(S.target); }
    async say(phrase) {
      if (this.isMe || this.isTarget() || !S.dub || !S.enabled) return;   // never read your own words back
      const t = await translate(phrase, this.lang, S.target);
      if (t) dub.enqueue(t);
    }
    stop() { this.active = false; this.abort(); if (pipelines.get(this.key) === this) pipelines.delete(this.key); refreshStatus(); }
  }

  // At most two recognisers: one for what you hear ('call' or 'tab') and one for your own voice ('me').
  // (A meeting such as Google Meet delivers several remote audio tracks; one recogniser each made them fight.)
  const pipelines = new Map();
  const guard = new C.ConflictGuard();
  const watch = new C.SilenceWatch();
  function refreshStatus() {
    if (!pipelines.size) { setTimeout(() => { if (!pipelines.size) ui.hidePill(); }, 5000); return; }
    const what = pipelines.has('tab') ? 'this tab' : pipelines.has('call') ? 'the call' : 'your microphone';
    ui.status('Chitter · ' + what + ' → ' + (C.LANG_NAMES[S.target] || S.target), true);
    toBridge({ type: 'badge', on: true });
  }

  let audio = null;      // { ctx, out (one mixed track), analyser, sources: Map<trackId, node> }
  function mixer() {
    if (audio) return audio;
    const ctx = new AudioContext(), out = ctx.createMediaStreamDestination(), analyser = ctx.createAnalyser();
    analyser.fftSize = 2048;
    audio = { ctx, out, analyser, sources: new Map() };
    const buf = new Float32Array(analyser.fftSize);
    setInterval(() => {
      if (!pipelines.has('call') && !pipelines.has('tab')) return;
      analyser.getFloatTimeDomainData(buf);
      let sum = 0; for (let i = 0; i < buf.length; i++) sum += buf[i] * buf[i];
      if (Math.sqrt(sum / buf.length) > 0.01) watch.audio(1);
      if (watch.shouldWarn()) ui.toast('Chitter can hear this audio, but your browser is returning no text. Check that the on-device speech model is installed. On a Mac, the Chitter app works with any browser.', 'OK');
    }, 1000);
    return audio;
  }
  function resumeAudio() {
    const m = mixer();
    if (m.ctx.state !== 'running') m.ctx.resume().catch(() => {});
    return m;
  }
  addEventListener('pointerdown', () => { if (audio && audio.ctx.state !== 'running') audio.ctx.resume().catch(() => {}); }, true);

  function onRemoteAudio(track) {
    if (!S.enabled) return;
    const m = resumeAudio();
    if (m.sources.has(track.id)) return;
    const stream = new MediaStream([track]);
    // Chromium only feeds a remote WebRTC track into Web Audio while a media element is also consuming it.
    const sink = new Audio(); sink.muted = true; sink.srcObject = stream; sink.play().catch(() => {});
    const node = m.ctx.createMediaStreamSource(stream);
    node.connect(m.out); node.connect(m.analyser);
    node.__chitterSink = sink;
    m.sources.set(track.id, node);
    track.addEventListener('ended', () => {
      sink.srcObject = null; node.disconnect(); m.sources.delete(track.id);
      if (!m.sources.size && pipelines.has('call')) pipelines.get('call').stop();
    });
    if (!pipelines.has('call') && !pipelines.has('tab')) pipelines.set('call', new Pipeline('call', m.out.stream.getAudioTracks()[0], 0));
    refreshStatus();
  }

  // "Caption this tab": the extension captures whatever the tab plays, so it also covers sites that don't use
  // WebRTC audio tracks (Zoom in the browser, videos, webinars).
  const gum = navigator.mediaDevices && navigator.mediaDevices.getUserMedia ? navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices) : null;
  async function startTabAudio(streamId) {
    if (pipelines.has('tab') || !gum) return;
    S.enabled = true;
    let stream;
    try { stream = await gum({ audio: { mandatory: { chromeMediaSource: 'tab', chromeMediaSourceId: streamId } } }); }
    catch (e) { ui.toast('Chitter couldn\'t capture this tab\'s audio: ' + e.message, 'OK'); return; }
    const m = resumeAudio(), node = m.ctx.createMediaStreamSource(stream);
    node.connect(m.analyser);
    node.connect(m.ctx.destination);      // a captured tab goes silent unless we play it back
    if (m.ctx.state !== 'running') ui.toast('Click once to hear this tab again.', 'Resume sound', () => m.ctx.resume());
    if (pipelines.has('call')) pipelines.get('call').stop();      // the tab already contains the call
    const track = stream.getAudioTracks()[0];
    watch.result();
    pipelines.set('tab', new Pipeline('tab', track, 0));
    track.addEventListener('ended', () => { node.disconnect(); if (pipelines.has('tab')) pipelines.get('tab').stop(); });
    refreshStatus();
  }

  // Your own microphone: the call's remote tracks only carry the OTHER people, so caption your own track too.
  function onLocalAudio(track) {
    if (!S.enabled || !S.captionMe || pipelines.has('me')) return;
    pipelines.set('me', new Pipeline('me', track, 24, true));     // shown as speaker "Y" (you)
    refreshStatus();
  }
  if (gum) {
    navigator.mediaDevices.getUserMedia = async function (constraints) {
      const stream = await gum(constraints);
      try { if (constraints && constraints.audio) stream.getAudioTracks().forEach(onLocalAudio); } catch (e) {}
      return stream;
    };
  }

  // ---------------------------------------------------------------- hook WebRTC: a remote audio track means a call is live
  function hook(name) {
    const Native = window[name]; if (!Native) return;
    const Wrapped = function (...args) {
      const pc = new Native(...args);
      try { pc.addEventListener('track', ev => { if (ev.track && ev.track.kind === 'audio') onRemoteAudio(ev.track); }); } catch (e) {}
      return pc;
    };
    Wrapped.prototype = Native.prototype; Object.setPrototypeOf(Wrapped, Native);
    window[name] = Wrapped;
  }
  hook('RTCPeerConnection'); hook('webkitRTCPeerConnection');

  // ---------------------------------------------------------------- toolbar + notes
  ui.onVoice(() => { S.dub = !S.dub; if (!S.dub) { dub.clear(); speechSynthesis.cancel(); } ui.applySettings(); toBridge({ type: 'save', patch: { dub: S.dub } }); });
  ui.onHide(() => { S.enabled = false; pipelines.forEach(p => p.stop()); dub.clear(); ui.hidePill(); ui.panel.close(); toBridge({ type: 'save', patch: { enabled: false } }); });
  let notes = null;
  function renderPanel() {
    const body = ui.panel.body; body.textContent = '';
    const add = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; e.textContent = text; body.appendChild(e); return e; };
    if (notes) {
      add('h3', '', 'Summary'); add('div', '', notes.summary || '—');
      const items = (title, arr, fmt) => { if (!arr.length) return; add('h3', '', title);
        arr.forEach(x => { const el = add('div', 'item', fmt(x)); el.tabIndex = 0;
          const hit = on => lineEls.forEach((le, id) => le.classList.toggle('hit', on && x.lines.includes(id)));
          const go = () => { hit(true); const f = lineEls.get(x.lines[0]); if (f) f.scrollIntoView({ block: 'center', behavior: ui.reduce ? 'auto' : 'smooth' }); };
          el.addEventListener('mouseenter', () => hit(true)); el.addEventListener('mouseleave', () => hit(false));
          el.addEventListener('focus', go); el.addEventListener('click', go); }); };
      items('Decisions', notes.decisions, d => d.text + '  (' + d.lines.map(i => 'L' + i).join(', ') + ')');
      items('Action items', notes.actions, a => a.text + (a.owner ? ' — ' + a.owner : '') + (a.due ? ' (due ' + a.due + ')' : '') + '  (' + a.lines.map(i => 'L' + i).join(', ') + ')');
      add('div', '', 'Notes by: ' + (notes.generatedBy || 'on-device model')).style.opacity = .6;
    }
    add('h3', '', 'Transcript');
    lineEls.clear();
    lines.forEach(l => { const d = add('div', 'line', ''); const b = document.createElement('b'); b.textContent = 'L' + l.id; d.appendChild(b); d.appendChild(document.createTextNode(l.text));
      if (l.translation) { const t = document.createElement('div'); t.className = 'tr'; t.textContent = l.translation; d.appendChild(t); } lineEls.set(l.id, d); });
  }
  const lineEls = new Map();
  async function writeNotes() {
    if (!lines.length) { ui.toast('Nothing to summarise yet.', 'OK'); return; }
    ui.status('Chitter · writing notes…', false);
    let result = null;
    try {
      if (window.LanguageModel && (await LanguageModel.availability()) !== 'unavailable') {
        const session = await LanguageModel.create({ initialPrompts: [{ role: 'system', content:
          'You turn a meeting transcript into structured notes. Lines are labelled L1, L2, ... Reply with ONLY JSON: {"summary": string, "topics": [string], "decisions": [{"text": string, "lines": [int]}], "actions": [{"text": string, "owner": string|null, "due": string|null, "lines": [int]}], "glossary": [{"term": string, "meaning": string}]}. "lines" are the integer line numbers that support the item. Use only line numbers that exist. Do not invent facts.' }] });
        const transcript = lines.map(l => 'L' + l.id + ': ' + (l.translation && l.lang !== S.target ? l.translation : l.text)).join('\n').slice(-6000);
        const raw = await session.prompt('Transcript:\n' + transcript);
        result = C.parseNotes(raw, lines.map(l => l.id));
        if (result) result.generatedBy = 'Chrome on-device model';
        session.destroy && session.destroy();
      }
    } catch (e) { result = null; }
    notes = result || C.extractiveNotes(lines.map(l => ({ id: l.id, text: l.translation || l.text })));
    renderPanel(); refreshStatus();
  }
  const md = () => C.notesMarkdown(notes || { summary: '', decisions: [], actions: [] }, lines);
  ui.panel.bind(writeNotes,
    () => navigator.clipboard && navigator.clipboard.writeText(md()),
    () => { const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([md()], { type: 'text/markdown' })); a.download = 'chitter-meeting.md'; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 2000); },
    () => ui.panel.close());
  ui.onNotes(() => { renderPanel(); ui.panel.open(); });

  console.info('[Chitter] loaded on', location.host, '- waiting for a call');
  toBridge({ type: 'ready' });          // ask bridge.js for the saved settings
  window.__chitter = { pipelines, lines, dub, mixer };   // handy for debugging in DevTools
})();
