// Liquid Voice prototype stage. Direction-agnostic host: mock desktop, menu bar, c11 window,
// state switcher, appearance toggle, simulated microphone level, PROTOTYPE badge.
//
// Usage from a direction page:
//   LVStage.init({
//     name: "Signal",
//     states: [{ id: "idle", label: "Idle" }, ...],   // in order; digits 1..n select them
//     onState(next, prev) {},                          // render the overlay for a state
//     onTheme(theme) {},                               // "dark" | "light"
//     onTick(level, t) {},                             // called every frame while listening, level 0..1
//     sequence: [["listening", 4200], ["transcribing", 1100], ["delivered", 1300], ["idle", 0]],
//   });

(function () {
  const S = {
    name: "",
    states: [],
    state: null,
    theme: "dark",
    level: 0,
    listeners: { state: [], theme: [], tick: [] },
    sequence: [],
    playing: false,
    _seqTimer: null,
    _raf: null,
    _t0: 0,
  };

  // ---------- simulated speech envelope ----------
  // Syllable bursts grouped into phrases with pauses. Deterministic per seed so a screenshot is repeatable.
  const rnd = LV.seeded(20260927);
  const timeline = []; // [start, end, peak]
  (function build() {
    let t = 0.35;
    for (let phrase = 0; phrase < 400; phrase++) {
      const syllables = 2 + Math.floor(rnd() * 9);
      for (let i = 0; i < syllables; i++) {
        const len = 0.12 + rnd() * 0.16;
        const peak = 0.35 + rnd() * 0.65;
        timeline.push([t, t + len, peak]);
        t += len + 0.02 + rnd() * 0.06;
      }
      t += 0.25 + rnd() * 0.7; // pause between phrases
    }
  })();
  const jitter = LV.seeded(7);
  function envelope(t) {
    let v = 0.02 + jitter() * 0.03; // room noise floor
    for (let i = 0; i < timeline.length; i++) {
      const [a, b, p] = timeline[i];
      if (t < a) break;
      if (t <= b + 0.08) {
        const x = (t - a) / (b - a);
        const shape = x < 0.25 ? x / 0.25 : Math.max(0, 1 - (x - 0.25) / 0.9);
        v = Math.max(v, p * shape * (0.85 + jitter() * 0.3));
      }
    }
    return Math.min(1, v);
  }
  const LOOP = 60; // seconds of envelope before looping

  // ---------- DOM ----------
  function el(tag, cls, html) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (html != null) e.innerHTML = html;
    return e;
  }

  const TERM_LINES = [
    '<span class="p">❯</span> <span class="d">claude --resume</span>',
    '',
    '<span class="d">Merge Captain · workspace:10 · surface:291</span>',
    '',
    'Read the three open PRs on lattice/retry-admission.',
    '',
    '  <span class="d">#412</span>  Queue: key admission on job id + lease epoch    <span class="d">+184 −31</span>',
    '  <span class="d">#409</span>  Scheduler: drop the duplicate lease timer         <span class="d">+12 −40</span>',
    '  <span class="d">#407</span>  Tests: reproduce double admission                <span class="d">+96 −0</span>',
    '',
    'I would merge #407 first: it is test-only and lands the failing case that #412 fixes.',
    'Then #412. #409 touches the scheduler, which you said not to touch, so I would hold it.',
    '',
    '<span class="d">Running the queue suite · 214 tests · 3.8 s · all green</span>',
    '',
    '<span class="p">❯</span> <span id="lv-insert"></span><span class="caret"></span>',
  ];

  function buildDesktop() {
    document.body.insertAdjacentHTML("afterbegin", `
      <div class="desktop"></div>
      <div class="menubar">
        <div class="left"><span class="apple"></span><span class="app">c11</span><span>File</span><span>Edit</span><span>View</span><span>Workspace</span><span>Window</span><span>Help</span></div>
        <div class="right status">
          <span id="lv-menubar-slot"></span>
          <svg width="16" height="12" viewBox="0 0 16 12" fill="currentColor" aria-label="Wi-Fi"><path d="M8 11.2a1.3 1.3 0 1 0 0-2.6 1.3 1.3 0 0 0 0 2.6zM4.2 7.4a5.4 5.4 0 0 1 7.6 0l1.1-1.1a7 7 0 0 0-9.8 0zM1.3 4.5a9.5 9.5 0 0 1 13.4 0L15.8 3.4a11 11 0 0 0-15.6 0z"/></svg><svg width="26" height="12" viewBox="0 0 26 12" fill="none" stroke="currentColor" aria-label="Battery"><rect x="0.75" y="0.75" width="21.5" height="10.5" rx="2.5" opacity="0.5"/><rect x="2.5" y="2.5" width="15" height="7" rx="1.2" fill="currentColor" stroke="none"/><path d="M24 4v4" stroke-width="1.6" opacity="0.5"/></svg><span>Sat Sep 27&nbsp; 3:14 PM</span>
        </div>
      </div>
      <div class="c11">
        <div class="titlebar">
          <div class="lights"><i></i><i></i><i></i></div>
          <div class="tabs"><span class="tab">184: OSS Strategy Partner</span><span class="tab active">291: Merge Captain</span><span class="tab">284: Style Studio</span></div>
        </div>
        <div class="body">
          <div class="sidebar">
            <div class="ws">Gregorovich<small>constellation · 2 agents</small></div>
            <div class="ws active">LiquidVoice<small>Merge Captain · working</small></div>
            <div class="ws">Stage11 / c11<small>idle</small></div>
            <div class="ws">Acetate<small>idle</small></div>
          </div>
          <div class="term">${TERM_LINES.join("\n")}</div>
        </div>
      </div>
      <div class="overlay-host" id="lv-overlay-host"></div>
      <div class="proto-badge">PROTOTYPE<small>not wired to real data</small></div>
      <div class="proto-controls" id="lv-controls"></div>
    `);
  }

  function buildControls() {
    const c = document.getElementById("lv-controls");
    const stateButtons = S.states.map((s, i) =>
      `<button data-state="${s.id}" aria-pressed="false"><span>${s.label}</span><kbd>${i + 1}</kbd></button>`).join("");
    c.innerHTML = `
      <h1>${S.name} · prototype controls</h1>
      <p class="sub">Liquid Voice visual language · direction ${S.name}</p>
      <div class="row"><label>Appearance</label><div class="seg" id="lv-theme">
        <button data-theme="dark" aria-pressed="true">Dark</button>
        <button data-theme="light" aria-pressed="false">Light</button>
      </div></div>
      <div class="row"><label>State</label><div class="states" id="lv-states">${stateButtons}</div></div>
      <button class="play" id="lv-play" aria-pressed="false">Play a dictation (P)</button>
      <p class="hint">Hold <b>Space</b> to talk, release to transcribe. Digits pick a state. <b>T</b> toggles appearance. Drag the overlay to move it; double-click resets.</p>
    `;
    c.querySelector("h1").addEventListener("click", () => c.classList.toggle("collapsed"));
    c.querySelector("#lv-theme").addEventListener("click", (e) => {
      const b = e.target.closest("button"); if (!b) return; setTheme(b.dataset.theme);
    });
    c.querySelector("#lv-states").addEventListener("click", (e) => {
      const b = e.target.closest("button"); if (!b) return; stopSequence(); setState(b.dataset.state);
    });
    c.querySelector("#lv-play").addEventListener("click", () => S.playing ? stopSequence() : playSequence());
  }

  // ---------- state ----------
  function setState(id) {
    if (!S.states.some((s) => s.id === id)) return;
    const prev = S.state;
    S.state = id;
    document.documentElement.dataset.state = id;
    document.querySelectorAll("#lv-states button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.state === id)));
    if (id === "listening") startTicking(); else stopTicking();
    S.listeners.state.forEach((f) => f(id, prev));
  }
  function setTheme(theme) {
    S.theme = theme;
    document.documentElement.dataset.appearance = theme;
    document.querySelectorAll("#lv-theme button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.theme === theme)));
    S.listeners.theme.forEach((f) => f(theme));
  }

  // ---------- ticking ----------
  function startTicking() {
    if (S._raf) return;
    S._t0 = performance.now();
    const step = (now) => {
      const t = ((now - S._t0) / 1000) % LOOP;
      S.level = envelope(t);
      S.listeners.tick.forEach((f) => f(S.level, t));
      S._raf = requestAnimationFrame(step);
    };
    S._raf = requestAnimationFrame(step);
  }
  function stopTicking() {
    if (S._raf) cancelAnimationFrame(S._raf);
    S._raf = null; S.level = 0;
  }

  // ---------- sequence ----------
  function playSequence() {
    stopSequence();
    S.playing = true;
    document.getElementById("lv-play").setAttribute("aria-pressed", "true");
    let i = 0;
    const next = () => {
      if (i >= S.sequence.length) { stopSequence(); return; }
      const [id, ms] = S.sequence[i++];
      setState(id);
      if (ms > 0) S._seqTimer = setTimeout(next, ms); else stopSequence();
    };
    next();
  }
  function stopSequence() {
    if (S._seqTimer) clearTimeout(S._seqTimer);
    S._seqTimer = null; S.playing = false;
    const b = document.getElementById("lv-play"); if (b) b.setAttribute("aria-pressed", "false");
  }

  // ---------- keyboard ----------
  let spaceHeld = false;
  function keys() {
    window.addEventListener("keydown", (e) => {
      if (e.target && /input|textarea/i.test(e.target.tagName)) return;
      if (e.key === " " && !spaceHeld) { e.preventDefault(); spaceHeld = true; stopSequence(); setState("listening"); }
      else if (e.key === "t" || e.key === "T") setTheme(S.theme === "dark" ? "light" : "dark");
      else if (e.key === "p" || e.key === "P") S.playing ? stopSequence() : playSequence();
      else if (/^[1-9]$/.test(e.key)) { const s = S.states[Number(e.key) - 1]; if (s) { stopSequence(); setState(s.id); } }
    });
    window.addEventListener("keyup", (e) => {
      if (e.key === " " && spaceHeld) {
        spaceHeld = false;
        // release: run the tail of the sequence from "transcribing" on
        const tail = S.sequence.slice(S.sequence.findIndex(([id]) => id === "transcribing"));
        if (tail.length) { S.playing = true; let i = 0;
          const next = () => { if (i >= tail.length) { stopSequence(); return; } const [id, ms] = tail[i++]; setState(id); if (ms > 0) S._seqTimer = setTimeout(next, ms); else stopSequence(); };
          next();
        }
      }
    });
  }

  // ---------- helpers exposed to directions ----------
  function insertText(text) {
    const slot = document.getElementById("lv-insert");
    if (!slot) return;
    slot.innerHTML = `<span class="inserted">${text}</span>`;
  }
  function clearInserted() { const slot = document.getElementById("lv-insert"); if (slot) slot.innerHTML = ""; }

  // Whole-surface drag with position memory and double-click reset (matches the current app).
  function makeDraggable(node, storageKey) {
    let drag = null;
    const key = "lv-pos-" + storageKey;
    const apply = (dx, dy) => { node.style.transform = `translate(${dx}px, ${dy}px)`; };
    try { const saved = JSON.parse(localStorage.getItem(key) || "null"); if (saved) apply(saved.dx, saved.dy); } catch (_) {}
    node.addEventListener("mousedown", (e) => {
      if (e.target.closest("button, a, input, [data-nodrag]")) return;
      const m = /translate\((-?[\d.]+)px, (-?[\d.]+)px\)/.exec(node.style.transform) || [0, 0, 0];
      drag = { x: e.clientX, y: e.clientY, dx: +m[1], dy: +m[2] };
      e.preventDefault();
    });
    window.addEventListener("mousemove", (e) => { if (!drag) return; apply(drag.dx + e.clientX - drag.x, drag.dy + e.clientY - drag.y); });
    window.addEventListener("mouseup", () => {
      if (!drag) return;
      const m = /translate\((-?[\d.]+)px, (-?[\d.]+)px\)/.exec(node.style.transform);
      if (m) { try { localStorage.setItem(key, JSON.stringify({ dx: +m[1], dy: +m[2] })); } catch (_) {} }
      drag = null;
    });
    node.addEventListener("dblclick", (e) => { if (e.target.closest("button")) return; node.style.transform = ""; try { localStorage.removeItem(key); } catch (_) {} });
  }

  window.LVStage = {
    init(cfg) {
      S.name = cfg.name || "";
      S.states = cfg.states || [];
      S.sequence = cfg.sequence || [["listening", 4200], ["transcribing", 1100], ["delivered", 1300], ["idle", 0]];
      buildDesktop();
      buildControls();
      keys();
      if (cfg.onState) S.listeners.state.push(cfg.onState);
      if (cfg.onTheme) S.listeners.theme.push(cfg.onTheme);
      if (cfg.onTick) S.listeners.tick.push(cfg.onTick);
      const params = new URLSearchParams(location.search);
      setTheme(params.get("theme") || cfg.theme || (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark"));
      setState(params.get("state") || cfg.defaultState || S.states[0].id);
      return this;
    },
    setState, setTheme, insertText, clearInserted, makeDraggable, playSequence, stopSequence,
    get state() { return S.state; },
    get theme() { return S.theme; },
    get level() { return S.level; },
    host() { return document.getElementById("lv-overlay-host"); },
    menubarSlot() { return document.getElementById("lv-menubar-slot"); },
    onState(f) { S.listeners.state.push(f); },
    onTheme(f) { S.listeners.theme.push(f); },
    onTick(f) { S.listeners.tick.push(f); },
    envelope,
  };
})();
