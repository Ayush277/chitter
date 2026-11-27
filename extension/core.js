/* Chitter core logic: pure functions and classes with no DOM access, so they can be tested in test/test.html.
   Loaded before page.js; exposes globalThis.ChitterCore. No network access anywhere in this extension. */
(function (root) {
  'use strict';

  const TERMINATORS = new Set(['.', '?', '!', '。', '！', '？', '…']);

  /** Speak finished sentences early: hand out each sentence once the live transcript has moved past it. */
  class PhraseCommitter {
    constructor() { this.committed = ''; }
    update(partial) {
      if (!partial.startsWith(this.committed)) return null;      // earlier words were revised: wait for the final
      let cut = -1;
      for (let i = 0; i < partial.length; i++) {
        if (TERMINATORS.has(partial[i])) {
          const rest = partial.slice(i + 1);
          if (rest.length && ![...rest].every(c => c === ' ' || TERMINATORS.has(c))) cut = i + 1;
        }
      }
      if (cut < 0) return null;
      const candidate = partial.slice(0, cut);
      if (candidate.length <= this.committed.length) return null;
      const fresh = candidate.slice(this.committed.length).trim();
      this.committed = candidate;
      return fresh || null;
    }
    finish(final) {
      const text = final.trim(), c = this.committed.trim();
      this.committed = '';
      if (!c) return text || null;
      let n = 0;
      while (n < c.length && n < text.length && c[n] === text[n]) n++;
      if (n >= c.length * 0.8) { const rest = text.slice(Math.max(n, Math.min(c.length, text.length))).trim(); return rest || null; }
      return text;
    }
  }

  /** Voice-over queue: in order, faster when behind, drops the oldest beyond maxBacklog. `speak(text, rate)` returns a Promise. */
  class DubScheduler {
    constructor(speak, maxBacklog = 3) { this.speak = speak; this.maxBacklog = maxBacklog; this.queue = []; this.running = false; this.dropped = 0; this.spoken = 0; }
    static rate(backlog) { return Math.min(1.3, 1 + 0.1 * Math.max(0, backlog - 1)); }
    enqueue(text) {
      this.queue.push(text);
      while (this.queue.length > this.maxBacklog) { this.queue.shift(); this.dropped++; }
      if (!this.running) this._drain();
    }
    clear() { this.queue.length = 0; }
    async _drain() {
      this.running = true;
      while (this.queue.length) {
        const backlog = this.queue.length, text = this.queue.shift();
        try { await this.speak(text, DubScheduler.rate(backlog)); this.spoken++; } catch (e) { /* skip a failed line */ }
      }
      this.running = false;
    }
  }

  /** Speech recognisers need the language up front. When results stay low-confidence, move to the next candidate. */
  class LangProbe {
    constructor(candidates, start) { this.candidates = candidates.slice(); this.i = Math.max(0, this.candidates.indexOf(start)); this.recent = []; this.tried = new Set([this.current]); }
    get current() { return this.candidates[this.i]; }
    report(confidence) { this.recent.push(confidence); if (this.recent.length > 4) this.recent.shift(); }
    /** The next language to try, or null if recognition looks healthy / everything was tried. */
    suggest() {
      if (this.recent.length < 3) return null;
      const avg = this.recent.reduce((a, b) => a + b, 0) / this.recent.length;
      if (avg >= 0.5) return null;
      for (let k = 1; k <= this.candidates.length; k++) {
        const j = (this.i + k) % this.candidates.length;
        if (!this.tried.has(this.candidates[j])) { this.i = j; this.tried.add(this.candidates[j]); this.recent = []; return this.current; }
      }
      this.tried = new Set([this.current]); this.recent = [];      // tried them all: start over next time
      return null;
    }
    lock(lang) { const j = this.candidates.indexOf(lang); if (j >= 0) this.i = j; this.recent = []; this.tried = new Set([this.current]); }
  }

  /** Plain words for the speech recogniser's error codes. null = routine, nothing to tell the user. */
  function speechErrorMessage(code) {
    const m = {
      'network': 'This browser\'s speech service failed (network error). Browsers other than Google Chrome may not be able to run it. On a Mac, use the Chitter app instead: it works with any browser or call app.',
      'service-not-allowed': 'This browser doesn\'t allow speech recognition here. On a Mac, use the Chitter app instead.',
      'not-allowed': 'Speech recognition was blocked for this page.',
      'audio-capture': 'Speech recognition couldn\'t read the audio.',
      'language-not-supported': 'No on-device speech model is available for this language.',
    };
    return m[code] || null;
  }

  /** Some browsers allow only one speech recogniser at a time: a second one keeps aborting the first. */
  class ConflictGuard {
    constructor(limit = 3, windowMs = 10000) { this.limit = limit; this.windowMs = windowMs; this.times = []; }
    aborted(now = Date.now()) {
      this.times.push(now); this.times = this.times.filter(t => now - t <= this.windowMs);
      if (this.times.length < this.limit) return false;
      this.times = []; return true;
    }
  }

  /** Audio is playing but no text ever comes back: say so, once, instead of staying silently blank. */
  class SilenceWatch {
    constructor(seconds = 15) { this.seconds = seconds; this.heard = 0; this.warned = false; }
    audio(duration) { this.heard += duration; }
    result() { this.heard = 0; this.warned = false; }
    shouldWarn() { if (this.warned || this.heard < this.seconds) return false; this.warned = true; return true; }
  }

  const LANG_NAMES = { en: 'English', es: 'Spanish', fr: 'French', de: 'German', it: 'Italian', pt: 'Portuguese', zh: 'Chinese', ja: 'Japanese', ko: 'Korean', ru: 'Russian', hi: 'Hindi', ar: 'Arabic', tr: 'Turkish', nl: 'Dutch', pl: 'Polish' };
  const BCP47 = { en: 'en-US', es: 'es-ES', fr: 'fr-FR', de: 'de-DE', it: 'it-IT', pt: 'pt-BR', zh: 'zh-CN', ja: 'ja-JP', ko: 'ko-KR', ru: 'ru-RU', hi: 'hi-IN', ar: 'ar-SA', tr: 'tr-TR', nl: 'nl-NL', pl: 'pl-PL' };
  const baseLang = l => String(l || '').toLowerCase().split(/[-_]/)[0];

  /** Best speech-synthesis voice: matching language, local voices preferred, natural-sounding names first. */
  function pickVoice(voices, lang) {
    const base = baseLang(lang);
    const pool = voices.filter(v => baseLang(v.lang) === base);
    if (!pool.length) return null;
    const score = v => (/premium|enhanced|natural|neural/i.test(v.name) ? 100 : 0) + (v.localService ? 20 : 0) +
      (v.lang.replace('_', '-').toLowerCase() === (BCP47[base] || '').toLowerCase() ? 5 : 0) + (v.default ? 1 : 0);
    return pool.slice().sort((a, b) => score(b) - score(a))[0];
  }

  /** Does this page's URL look like a call site? Used only to decide when to show "waiting for a call". */
  const CALL_HOSTS = [/(^|\.)meet\.google\.com$/, /(^|\.)teams\.microsoft\.com$/, /(^|\.)teams\.live\.com$/, /(^|\.)zoom\.us$/, /(^|\.)whereby\.com$/, /(^|\.)webex\.com$/, /(^|\.)meet\.jit\.si$/, /(^|\.)discord\.com$/, /(^|\.)slack\.com$/];
  const isCallHost = host => CALL_HOSTS.some(re => re.test(host));

  /** Offline fallback notes (port of the Mac app's extractive generator). lines: [{id, text}] */
  function extractiveNotes(lines) {
    const stop = new Set('the a an and or but to of in on for with is are was were be been we i you it that this will so at by as not have has had do does also then there their they our let lets today about from what which who would should could need needs can because before after next'.split(' '));
    const words = s => s.toLowerCase().split(/[^\p{L}']+/u).filter(Boolean);
    const freq = {};
    lines.forEach(l => words(l.text).forEach(w => { if (!stop.has(w) && w.length > 3) freq[w] = (freq[w] || 0) + 1; }));
    const score = t => { const ws = words(t).filter(w => !stop.has(w) && w.length > 3); return ws.length ? ws.reduce((a, w) => a + (freq[w] || 0), 0) / ws.length : 0; };
    const top = lines.slice().sort((a, b) => score(b.text) - score(a.text)).slice(0, 3).sort((a, b) => a.id - b.id);
    const decisionRE = /\b(decided|agreed|we will|we'll|the decision|conclude[ds]?|let's go with|move the|moved to|approved)\b/i;
    const actionRE = /\b(will|needs? to|has to|must|should|owns?|responsible|follow up|please)\b/i;
    const ownerRE = /\b([A-Z][a-z]{1,15})\s+(?:will|needs? to|has to|must|owns|should)\b/;
    const dueRE = /\bby\s+((?:next\s+|the\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|tomorrow|end of (?:the )?(?:day|week|month)))/i;
    const decisions = [], actions = [];
    lines.forEach(l => (l.text.match(/[^.!?。！？]+[.!?。！？]?/g) || [l.text]).forEach(s => {
      s = s.trim(); if (!s) return;
      if (decisionRE.test(s)) decisions.push({ text: s, lines: [l.id] });
      else if (actionRE.test(s)) {
        const o = s.match(ownerRE), d = s.match(dueRE);
        if (o || d) actions.push({ text: s, owner: o ? o[1] : null, due: d ? d[1] : null, lines: [l.id] });
      }
    }));
    const topics = Object.entries(freq).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0, 5).map(e => e[0][0].toUpperCase() + e[0].slice(1));
    return { summary: top.map(l => l.text.trim()).join(' '), topics, decisions: decisions.slice(0, 8), actions: actions.slice(0, 12), glossary: [], generatedBy: 'Extractive (offline)' };
  }

  /** Parse model output (may be fenced) and drop items that cite line IDs that don't exist. */
  function parseNotes(raw, validIds) {
    const a = raw.indexOf('{'), b = raw.lastIndexOf('}');
    if (a < 0 || b <= a) return null;
    let n; try { n = JSON.parse(raw.slice(a, b + 1)); } catch (e) { return null; }
    const ok = new Set(validIds);
    const clean = arr => (Array.isArray(arr) ? arr : []).map(x => ({ ...x, lines: (Array.isArray(x.lines) ? x.lines : []).filter(i => ok.has(i)) })).filter(x => x.text && x.lines.length);
    return { summary: String(n.summary || ''), topics: Array.isArray(n.topics) ? n.topics.map(String) : [], decisions: clean(n.decisions), actions: clean(n.actions), glossary: Array.isArray(n.glossary) ? n.glossary : [] };
  }

  function notesMarkdown(n, lines) {
    const refs = l => l.length ? ' _(' + l.map(i => 'L' + i).join(', ') + ')_' : '';
    let s = '';
    if (n.summary) s += '## Summary\n\n' + n.summary + '\n\n';
    if (n.decisions.length) s += '## Decisions\n\n' + n.decisions.map(d => '- ' + d.text + refs(d.lines)).join('\n') + '\n\n';
    if (n.actions.length) s += '## Action items\n\n' + n.actions.map(a => '- [ ] ' + a.text + (a.owner ? ' — **' + a.owner + '**' : '') + (a.due ? ' (due ' + a.due + ')' : '') + refs(a.lines)).join('\n') + '\n\n';
    s += '## Transcript\n\n' + lines.map(l => '**L' + l.id + '** ' + l.text + (l.translation ? '\n> ' + l.translation : '')).join('\n\n') + '\n';
    return s;
  }

  root.ChitterCore = { speechErrorMessage, ConflictGuard, SilenceWatch, PhraseCommitter, DubScheduler, LangProbe, pickVoice, isCallHost, extractiveNotes, parseNotes, notesMarkdown, baseLang, LANG_NAMES, BCP47 };
})(typeof globalThis !== 'undefined' ? globalThis : window);
