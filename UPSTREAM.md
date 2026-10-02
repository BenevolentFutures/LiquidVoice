# Upstream

MouthKeys is a GPL-3 fork of [FluidVoice](https://github.com/altic-dev/FluidVoice) by altic-dev (git remote `upstream`). It is a separate product focused on straight voice to text: no Fluid Intelligence, no telemetry, no upstream updater.

## Policy

- **We port by hand. We never merge upstream.** Our typing, audio and overlay code has diverged where upstream's fixes land, so a merge conflicts and would drag in features we cut.
- `git cherry-pick -x <sha>` only when it applies cleanly. Otherwise read `git show <sha>` and re-implement the fix on our code.
- Credit every port in the commit message: `Ported from altic-dev/FluidVoice@<sha> (<original subject>) by <original author>.` Say what you left out and why.
- A commit that mixes a dictation fix with something on the never-port list: take only the dictation part.

## Never port

- Fluid Intelligence, private AI, the Edit Mode private model, "Smart" styles, the prompt picker on the pill.
- Meetings: FluidMeet, Fluid Notes, AEC, captions, speakers.
- Dashboard, onboarding redesign, stats card, What's New.
- Analytics of any kind (DAU, latency events, weekly batches, FI TPS).
- Zeppelin search.
- The updater. It would replace this build with stock FluidVoice.
- Upstream's overlay redesign. Adapt the behavior into our overlay in `BottomOverlayView.swift` instead.

## Where we stand

| | SHA | Note |
|---|---|---|
| Fork base | `d62adc9` | `d62adc9ac35467f9933fda689111514545466a2d` |
| Watermark | `3b509ea1` | `upstream/main` on 2026-09-24: where the last review stopped |

The watermark is where review stopped, not a claim that every commit before it is settled. The ledger fills in as port PRs merge. After the next review pass, move the watermark to the upstream commit it stopped at.

## Next review

```sh
git fetch upstream
git log --no-merges 3b509ea1..upstream/main
```

Skip anything on the never-port list. Each commit that gets ported, or deliberately skipped, gets a ledger row when its PR merges.

## Port ledger

| Upstream SHA | Subject | Status | Our PR |
|---|---|---|---|
| `43668220` | Fix dock visibility and locked-screen shortcuts | ported | #2 |
| `33e4eb5d` | fix(hotkey): isolate mouse event taps | ported, adapted: reprocess mouse shortcut is a one-shot in the mouse tap | #2 |
| `1fd51e4e` | fix(hotkey): preserve mouse press lifecycle | ported, adapted to com.FluidApp.app.dev | #2 |
| `b3258d25` | fix(hotkey): stop interrupted mouse holds | ported | #2 |
| `13401621` | perf(hotkey): service keyboard tap on dedicated thread | ported, adapted: own keystrokes skipped by source PID, not upstream's marker | #2 |
| `24bc8508` | Fix ignored microphones returning after reconnect | ported | #2 |
| `9db0631a` | Fix media pause and resume during dictation (#957) | ported, ASRService hooks placed by hand | #2 |
| `38730e98` | Retain media recovery ownership and skip unchanged key saves | partial: media recovery only; key-save part targets code we don't have | #2 |
| `79b91141` | fix(audio): remove Independent Volume instead of writing system volume (#989) | ported | #2 |
| `02a536ef` | test: isolate debug preferences | skipped: covered by dev isolation (#1) | #2 |
| `0039d645` | Refine AI Providers, History and Stats (#955) | partial: media query timeout only; rest is AI providers/history/stats | #2 |
| `4e00cf6b` | refactor(bench): keep stop logging within lint limits | folded into the 13401621 port | #2 |
| `02bb636c` | feat(meeting): harden audio capture and processing | skipped: meetings; its Core Audio listener move off main is a candidate for a separate audio-hardening lane | #2 |
| `126fedd1` | feat(meeting): strengthen detection and unify recording overlay | skipped: meetings | #2 |
| `cf96d35c` | feat(meeting): Phase 3 - VPIO mic capture behind a default-off flag | skipped: meetings | #2 |
| `2efaa124` | add analytics to measure latency | skipped: analytics | #2 |
| `238ff3f4` | chore(hotkey): add local debug toggle trigger | skipped: debug trigger file | #2 |
| `a1b7c30c` | feat(beta4): persist FI preparation and scope overlay choices by app | skipped: Fluid Intelligence beta; shortcut-settings features, not fixes | #2 |
| `ef74d20d` | chore: satisfy strict lint and validate optional audio values | skipped: lint over meetings code | #2 |
| `b0d64436` | Migrate to clipboard paste | partial: snapshot/restore and result reporting; not the default flip, forced migration, coordinator or analytics | #4 |
| `c59118a7` | increase limits for snapshot backup | superseded by bbaedd94 | #4 |
| `b1184755` | restore image clipboard | ported | #4 |
| `03477453` | Fix restoring image snapshot | ported | #4 |
| `56504289` | reduce snapshot restore time | skipped: replaced by our per-target restore timing and c0118882 | #4 |
| `fb896ebe` | support different keyboard layouts | ported | #4 |
| `4cb6683f` | prallelize snapshot and transcription | partial: image-file bytes; Spoken Send part goes to the spoken-send lane | #4 |
| `ebbff23a` | fix(paste): tag synthetic Cmd+V as synthesized event | ported | #4 |
| `c0118882` | fix(paste): release Command after the synthesized Cmd+V | ported | #4 |
| `a2d6ef32` | fix(clipboard): conceal temporary dictation entries | ported | #4 |
| `bbaedd94` | perf(clipboard): cap snapshot representations at 32 MB | ported | #4 |
| `a3c896a7` | fix(clipboard): preserve filenames when oversized payloads are skipped | ported | #4 |
| `7d6d0e7c` | fix(clipboard): preserve enabled transcription backup when delivery fails | ported; failed dictations always go to the clipboard | #4 |
| `58b4db56` | fix(settings): show full clipboard insertion label | ported | #4 |
| `51e62364` | feat(typing): refuse delivery when focus is certainly not a text field | ported; c11/Ghostty never refused | #4 |
| `a1a65772` | fix(typing): paste when focus is a window or app | ported | #4 |
| `fadaed91` | feat(typing): verify paste landed by reading focus back | ported; debug trigger rewritten as our own | #4 |
| `caedd4ef` | fix(typing): wait 1.5 s before a not-landed verdict | ported | #4 |
| `788d04b6` | fix(typing): ignore paste read-back after user input | ported | #4 |
| `b1d14044` | feat(settings): make the paste check card opt-in | ported | #4 |
| `98b5a278` | fix(typing): skip paste read-back when a send key follows | hook only (verifiesLanding); Spoken Send itself in its own lane | #4 |
| `5a67d658` | fix(dictation): snapshot target and route at stop | partial: stop-time target; route/prompt freezing depends on Fluid Intelligence | #4 |
| `adf0216e` | feat(dictation): make starting-field restoration optional | ported (settings search entry skipped: we have none) | #4 |
| `d5cc5090` | feat(overlay): friendlier wording for undelivered transcripts | ported into our overlay design | #4 |
| `ff92b4b8` | chore(overlay): shorter failure title and card preview trigger | ported into our overlay design | #4 |
| `8a820022` | feat(overlay): redesign delivery failure card | ported into our overlay design | #4 |
| `088efe13` | feat(overlay): show delivery failures on the transient notice panel | ported into our overlay design | #4 |
| `9c25e758` | fix(overlay): show a card for every delivery failure | ported into our overlay design | #4 |
| `fe05d7cb` | fix(overlay): stop swallowing clicks right after hide | adapted: the alpha-hidden panel is parked off-screen right after the text is handed off, and its controls are inert until shown; not ignoresMouseEvents, which would make the pill's transparent margin take clicks | #4, #9 |
| `42e33e68` | Reduce dictation latency and add pipeline evaluation (#950) | partial: PasteKeyCodeCache/Resolver (#4), readiness-gate test hook (#2); history saved off main (no SQLite migration) and today summary cached, streaming teardown off the stop path with stall recovery and stale-preview guard, no UI rebuild before handoff, final ASR before the status UI, logging off main, AI transport-failure retry removed (#9). Skipped: FI handoff/prewarm/preview, analytics, beta summaries, request-correlated evaluation | #2, #4, #9 |
| `2e0345a9` | perf(typing): skip redundant AX reads on the stop path | read-back baseline on clipboard paths only (#4); the stop-time focus audit does not exist here (#9) | #4, #9 |
| `a35dba9c` | fix(accessibility): bound AX round-trips to 2 seconds | adapted: process-wide 0.3 s bound set at launch (bounded elements already set it from the first dictation) | #4, #9 |
| `974cad2b` | chore(diagnostics): trace stop path timing end to end | adapted: StopPathTrace, one STOP_SUMMARY line per dictation, scripts/stop_path_latency.py | #9 |
| `761f2c8c` | perf(asr): run final transcription off the main actor | adapted: the model round trips run from a @concurrent helper (our provider is main-actor isolated) | #9 |
| `526c2aa2` | perf(asr): raise Transcribing status delay to 250 ms | ported | #9 |
| `22270dcc` | perf(asr): cancel Transcribing status as soon as inference ends | ported | #9 |
| `094b8d0e` | perf(overlay): hide panel by alpha instead of window transactions | adapted into our overlay; parking deferred until after the handoff (see fe05d7cb) | #9 |
| `6335acc4` | perf(overlay): isolate waveform audio level from shared state | ported, without the level throttle (our voice trace scrolls one bar per level) | #9 |
| `fcb54e49` | perf(overlay): freeze waveform at stop and defer mouse-events fence | partial: waveform freeze and unchanged-value cleanup; no ignoresMouseEvents (see fe05d7cb) | #9 |
| `6f929124` | perf(overlay): use a single 80 ms fade on exit | partial: window alpha drops to zero; our own 20 ms exit kept | #9 |
| `0be79c90` | fix(overlay): flush window ordering on immediate hide | skipped: superseded upstream by the alpha hide | #9 |
| `ebcc71ab` | perf(overlay): commit hide before any post-stop state work | partial: the fences it deferred are gone or run after the handoff; state cleanup stays synchronous | #9 |
| `fea6d6c9` | perf(menubar): stop redrawing the identical status icon | ported | #9 |
| `ed9b4078` | perf(dictionary): probe target field off main thread | ported (clean cherry-pick) | #9 |
| `0348e714` | fix(logging): exclude verbose diagnostics from production builds | ported; audio lifecycle and delivery decision lines kept in Release | #9 |
| `a5d32e6a` | perf(diagnostics): keep stop-path tracing out of Release | ported; Release keeps one STOP_SUMMARY line per dictation | #9 |
| `c32a110c` | perf(dictation): defer context reads until the mic stops | skipped: our stop path does no window-title or text-before-cursor reads | #9 |
| `1ce13665` | perf: harden incremental parakeet previews | partial: settings accessibility labels (#7); incremental Parakeet previews deferred | #7 |
| `daa0f2d3` | feat(debug): trace clipboard writes and restoration metadata | skipped: debug tracing | #4 |
| `208566c2` | feat(debug): trace clipboard shortcut event sources | skipped: debug tracing | #4 |
| `74a1ee8b` | feat(bench): log stop input timing and post-dispatch waits | skipped: benchmark tracing | #4 |
| `26ad5a41` | Refine AI provider setup and model verification | skipped: rewrite selection clipboard, Fluid Intelligence-adjacent | #4 |
| `c679506d` | feat: add spoken send commands | partial: parser, literal escape, settings/backup, send key, countdown; not upstream's overlay/notch indicators, exact-field check (replaced by our exact-pane CFEqual gate) or tag-based hotkey check | #7, #8 |
| `95fe1b15` | fix: complete spoken send after quiet countdown | ported | #7 |
| `9778fe46` | Block Spoken Send in additional terminals | ported; block list extended (WezTerm, Tabby, Hyper, Rio); c11 allow-listed ahead of it | #7 |
| `60480451` | fix(spoken-send): hold the armed phrase across noisy partials | ported | #7 |
| `4310f143` | fix: harden 1.6.10 review edge cases | partial: Spoken Send parts only; FI check skipped | #7 |
