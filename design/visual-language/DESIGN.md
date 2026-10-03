# MouthKeys visual language: Signal

**Status: locked by Atin, 2026-09-28** ("Awesome. This looks great. Let's go."), after four rounds on the recording overlay; **round 5 (same day) added the states the newer branch has** (Spoken Send, timeouts, recognition recovery, microphone permission, delivery-failure reasons, truthful wording, the app icon), see section 15; **round 6 (2026-10-01) made the pill shorter and gave the trace the room** (section 16), and the same day gave the foot row live counters, words and words per minute, and the Hollyland lapel mic's battery in the mic label (§16). This document is the binding design for the native build. Where it and the prototype disagree, the prototype wins and this file gets fixed.

**Binding prototype:** [`prototypes/signal/round6.html`](prototypes/signal/round6.html) for the overlay's layout since round 6 (its top CSS block "ROUND 6" lists every number; `?layout=r5` or L shows round 5), and [`prototypes/signal/index.html`](prototypes/signal/index.html) for everything else (tokens, native mapping and round history in [`prototypes/signal/DIRECTION.md`](prototypes/signal/DIRECTION.md)). Open it with [`prototypes/serve.sh`](prototypes/serve.sh) or double-click the self-contained copy [`prototypes/signal/standalone.html`](prototypes/signal/standalone.html). Keys: 1–6 pick a state, hold Space to talk, P plays a dictation, T toggles appearance, D toggles the age ruler.

**Reference only, archived:** [Obsidian](prototypes/obsidian/index.html) (depth) and [Lumen](prototypes/lumen/index.html) (light). The current app's anatomy before this work: [`notes/overlay-anatomy.md`](notes/overlay-anatomy.md). Round history and decisions: [`notes/DIRECTIONS.md`](notes/DIRECTIONS.md).

## 1. Thesis

MouthKeys is straight voice to text. Its overlay is seen hundreds of times a day, so the language is **an engineering drawing of an instrument that stays quiet until you reach for it**: square solid surfaces, 1 px rules, square-ended ink bars, mono numerals and placards, and schematic selection brackets that draw outside a box's corners only under the pointer. No gradients, no blur, no glow, no materials, no corner radius. International orange is the only colour, and it only ever marks something live. Every state reads in a tenth of a second, and nothing moves unless it means something.

The diagram grammar (brackets, mono, thin rules, status in solid colour and words, never blinking) is inherited from an earlier engineering-drawing deck design of Atin's. Its colours are not.

## 2. Colour tokens

| Token | Dark | Light | Used for |
|---|---|---|---|
| `accent` | `#FF4F1F` | `#FF4F1F` | record square, trace write head, transcribing sweep, delivered stamp, failed top rule, Copy button, NOT DELIVERED marker |
| `on-accent` | `#111214` | `#111214` | glyphs and text on accent |
| `surface` | `#111214` | `#FFFFFF` | pill, history card, failed card, menu |
| `edge` | `#2C2E33` | `#111214` | 1 px pill and card edge, table rules |
| `chip` | `#1A1B1F` | `#F2F2F4` | chip fill (no edge at rest) |
| `drop` | `0 2 0 rgba(0,0,0,.35)` | `0 2 0 #111214` | flat, unblurred 2 pt offset rule under pill and card; on square corners it reads as a printed thick bottom rule |
| `float-shadow` | black 0.55, radius 18, y 9 | black 0.16, radius 12, y 5 | the soft floating shadow under pill and cards (§6); dark floats more (Atin, 2026-10-01) |
| `ink` | `#FFFFFF` | `#111214` | trace bars |
| `midline` | `#2C2E33` | `#D3D4D8` | 1 px rule behind the trace |
| `text` | white 0.92 | `#111214` | preview, headlines, timer |
| `text-2` | white 0.58 | `#111214` | mic label, meta, table labels; in light it is true ink and size, case and face carry the hierarchy |
| `text-dim` | white 0.46 | ink 0.50 | frozen preview while transcribing |
| `inv-bg` / `inv-fg` | `#FFFFFF` / `#111214` | `#111214` / `#FFFFFF` | pressed and latched chips, hovered history and menu rows |
| `bracket` | white 0.78 | `#111214` | selection brackets (hover only) |
| `halo` | `surface` | `surface` | 1 pt knockout under every bracket |
| `grat` | white 0.20 | ink 0.30 | age ruler ticks |

No green, red or amber anywhere. State is carried by orange, by words, and by inversion.

Dark is the default. The light variant is print on paper and follows the system appearance.

## 3. Type scale

Two families. **SF Pro Text/Display** for anything read as prose. **SF Mono** (`.system(design: .monospaced)`) for every number and label, so every number is tabular by construction. Labels are uppercase, tracked +0.06 em.

| Role | Face | Size / line | Weight | Notes |
|---|---|---|---|---|
| Timer | Mono | 14 / 18 | semibold | right-aligned in a box reserved for "99:59" (Atin, 2026-10-01, round 6) |
| Mic label, live counters | Mono | 10 / 16 | medium, UPPERCASE | the foot row: mic centred beside the app icon, word count at its left end (Atin, 2026-10-01, round 6), words per minute at its right end ("169 WPM"); numbers in fixed boxes, right-aligned, unused leading places blank (Atin, 2026-10-01) |
| Meta (history, delivered, failed) | Mono | 10.5 / 14–15 | medium, UPPERCASE | "0:41 · 118 WORDS · C11" |
| History index / time | Mono | 11.5 / 17 and 10 / 14 | semibold / medium | "01" over "3:04 PM" |
| Table header, day rows, title block, menu header | Mono | 10 | medium, UPPERCASE | |
| Delivered headline | Pro | 15 / 19 | semibold | "Pasted into c11" (Atin, 2026-10-01, round 6) |
| Live preview | Pro | 12.5 / 16 | medium | 3 lines, head-truncated so the newest words stay visible (Atin, 2026-10-01, round 6) |
| Card and notice headline | Pro | 12.5 / 16 | semibold | "Couldn't paste into c11", "Speech recognition is back" (Atin, 2026-10-01, round 6) |
| Card reason, card transcript, notice reason and actions | Pro | 12 / 16 | regular (actions medium, Reprocess semibold) | (Atin, 2026-10-01, round 6) |
| Transcripts in the history table | Pro | 13 / 18 | regular | clamped to 4 lines |
| Menu rows, a card's primary button and Dismiss | Pro | 13 | regular / semibold / medium | |

Nothing inside the overlay is smaller than 10 pt mono uppercase; prose inside the pill never drops below 12 pt (Atin, 2026-10-01, round 6), and the history card and menu keep 13.

## 4. Spacing and geometry

| Token | Value |
|---|---|
| Pill | 340 × 130 pt, square (Atin, 2026-10-01, round 6) |
| Pill rows, top to bottom | padding 10 · preview 48 · gap 6 · trace row 38 (34 trace + 4 ruler) · gap 4 · foot 16 · padding 8 = 130 (was 149) (Atin, 2026-10-01, round 6) |
| Pill padding, horizontal | 12 (was 18), so the content is 316 wide (Atin, 2026-10-01, round 6) |
| Recovery cards | the pill grown **upward** to 156 (+26, one-line card), 210 (+80, failed with its transcript) or 226 (+96, failed with a two-line reason); its bottom rows, rails and chips do not move (Atin, 2026-10-01, round 6) |
| Rails | 130 tall, bottom-aligned, 6 pt out from the pill; the two chips spaced evenly down the rail (23 pt above, 24 between, 23 below), no longer pinned to the pill's corners; the retired middle slot stays reserved at the centre (Atin, 2026-10-01, round 6) |
| Chip | 30 × 30, square, no edge at rest |
| Trace | 63 bars, 2 pt wide on a 4 pt pitch, 250 × 34, min 2 / max 30 tall, mirrored about a 1 px midline at 17; 12 bars per second of voice, so 5.25 s of speech (39 in round 5); silence adds none (§8) (Atin, 2026-10-01, round 6) |
| Trace row | trace from the left edge · at least 12 pt · orange square 6 pt · 4 · timer (5 ch reserved), the square and timer flush right, all centred on the midline. The trace takes the room the icon and the placard left: trace + 12 + readout fill the 316 pt content (Atin, 2026-10-01, round 6) |
| Foot row | 16 tall: target-app icon 16 pt · 7 · microphone (at most 160 wide, tail-truncated; the Hollyland lapel's battery label reserves its widest reading, §16 item 9), centred as a pair; the live word count ("  53 WORDS") at the left end and Spoken Send's placard (7 ch reserved, empty at rest) at the right end, both pinned so the pair never moves (Atin, 2026-10-01, round 6). While the placard is empty its slot shows words per minute ("169 WPM"), flush right (Atin, 2026-10-01) |
| Live counters | the words number in a fixed 4-digit box, WPM in a fixed 3-digit box, right-aligned, mono (tabular), unused leading places blank space (never zeros), 6 pt (0.6 em) before the label; clamped at 9999 and 999. Neither label ever moves (Atin, 2026-10-01) |
| Age ruler | static ticks at bar centres 1 pt below the trace: 2 pt every 0.25 s, 3 pt every 1 s; its 4 pt is reserved even when hidden (Atin, 2026-10-01, round 6) |
| History card | 480 wide, ≤ 480 tall, square, 1 px edge; 36 pt header, 28 pt day rows, 68 pt index column, 28 pt title-block footer; centred on the overlay, 6 pt above its visible top (a recovery card's grown pill included), clamped 8 pt inside the screen's visible frame (Atin, 2026-10-01) |
| Copy button | 88 × 28, square |
| Delivered stamp | 30 × 30, square |
| Record square | 6 × 6, filled while listening, 1.5 pt outline while transcribing |
| Screen placement | bottom-centre, 50 pt above the visible bottom; whole-surface drag with position memory as screen fractions; double-click anywhere but a button resets |

## 5. Corner radii

**0 everywhere we own.** Pill, chips, history card, failed card, Copy button, delivered stamp, menu, menu rows, record square and the menu bar mark are all plain rectangles. The target-app icon keeps whatever shape the OS gives it; chip glyphs are SF Symbols.

## 6. Materials

None. Every surface is an opaque fill with a 1 px edge and a flat 2 pt drop rule. No `NSVisualEffectView`, no vibrancy, no glass, no noise.

**Floating shadow (Atin, 2026-09-29).** The one blurred shadow, "a little bit of drop shadow to make it seem like it's floating above the screen": the pill, the recovery cards and the history card sit on a soft neutral shadow (`float-shadow`): in dark black at 0.55, blur radius 18, offset y 9; in light black at 0.16, radius 12, y 5. Dark floats more (Atin, 2026-10-01): over a dark terminal the lighter shadow barely read. The flat 2 pt drop rule stays, drawn over it: it still reads as the printed bottom rule, and the bottom bracket gap is still measured from it. Chips, brackets and the menu cast none. The shadow lives in its own click-through panel under the surface's (§11), so the transparent bracket margin still passes clicks, and it follows the surface's alpha and fade: a hidden surface casts nothing.

## 7. The selection brackets

The one flourish. Four L marks sit **outside** a box's corners, a gap clear of the edges, arms running along the outside of the two edges. They mark whatever is under the pointer and nothing else.

**Brackets mark only things you can click (Atin, 2026-09-29).** A surface that is not clickable as a whole takes no bracket: not the pill at rest, not a recovery card, not the history card (its rows invert on hover). The one exception is the pill while the SEND placard shows, when a click on it cancels the Return. Recovery-card buttons (Copy, Reprocess, Open System Settings, Try Again, Dismiss) and the notice row's actions take a chip's bracket on hover; the text buttons lose their hover underline, the bracket is their hover mark.

| Element | Gap | Arm | Shows when |
|---|---|---|---|
| Pill | 3 pt (bottom gap measured from the drop rule) | 10 pt | pointer over the pill itself (not the rails, their gutter or the empty chip slot), **only while SEND shows** (a click cancels the Return) |
| Chip | 2 pt | 6 pt | pointer over that chip |
| Card button, notice action | 2 pt | 6 pt | pointer over that button |
| Menu bar mark | inside its 22 × 16 box | 4 pt | pointer over the item, or menu open |

Rules: stroke 1.5 pt in `bracket` over a 1 pt `halo` in the surface colour (without the halo, ink marks vanish over a dark terminal in light mode). Never drawn at rest, never orange, never animated except a 60 ms linear fade in and out. One bracket at a time: over a chip or the card, the pill's hides, because the 6 pt gutter cannot hold two. Brackets never change layout or hit-testing. The window keeps a transparent margin around the visible content so they are not clipped: 6 pt on the top and sides (gap 3 + stroke 1.5 + halo 1 = 5.5) and 8 pt at the bottom, where the bracket also clears the 2 pt drop rule (7.5). The margin paints nothing, so clicks there reach the app beneath.

## 8. Motion

| Event | Duration | Curve | What happens |
|---|---|---|---|
| Entrance | 0 ms | none | The panel is simply there (first frame composed offscreen, as today) |
| Dismiss | 120 ms | linear | Opacity 1 → 0. No scale, no drop |
| Selection brackets | 60 ms | linear | Opacity in on hover, out on leave. Colour never changes, never blinks |
| Trace advance (Atin, 2026-09-29) | 83.3 ms of voice per bar | continuous | Voice-gated: the trace adds bars only while the voice is on (a level above the calibrated gate, held on for a 250 ms hangover so it never stutters between words); in silence it holds still, the last words on screen. While it advances, every bar slides left through the 4 pt pitch with the frame clock, one new bar entering at the right every 83.3 ms of voice |
| Bar height (Atin, 2026-09-29) | ~135 ms | exponential ease | Each drawn bar eases toward its height; a new bar grows from 2 pt. No 2 pt snapping: edges land on device pixels, bars stay square-ended |
| Stop → flat | 60 ms | linear | All bars go to 2 pt; the write head goes ink |
| Transcribing sweep | 1050 ms, repeating | linear | Solid 24 × 4 accent block stepped on the 4 pt pitch |
| Chip press | ≥ 60 ms | 60 ms linear colour | Inverts to a solid square with a 1 pt surface keyline. No scale |
| Copy feedback | 900 ms (chip), 1400 ms (card button) | none | Orange fill and check, same size |
| Pasted / Sent hold | 600 ms | none | Then dismiss (shortened from 1200 ms by Atin, 2026-09-28) |
| Menu bar bars | 8 Hz | none | 2 pt steps while listening |
| Word count (Atin, 2026-10-01) | 30–110 ms a word | stepped | Steps up one word at a time toward the true count, each step `max(30, min(110, 450 / remaining))` ms after the last, so a burst of the streaming preview (up to about 15 words) plays out over about half a second; a larger one runs at the 30 ms floor. Never passes the true count; drops at once when a revised partial lowers it. Digits change in place, no roll |
| Words per minute (Atin, 2026-10-01) | τ 0.7 s | exponential ease | Target = words × 60 / max(6, elapsed s) (the first 6 s count as 6, so the first burst does not spike it); `shown += (target − shown) × (1 − e^(−dt/0.7))`, shown rounded. Keeps updating through silence, so it drifts down while you pause. After the stop the count finishes catching up and WPM settles from the frozen length |
| Reduced motion | | | Bars step a whole pitch and take their height at once; the sweep holds 4 positions per cycle; dismiss and bracket fades are cuts; the word count and WPM show their targets at once (Atin, 2026-10-01) |

No springs. Everything is deliberate; the trace's bar heights are the one soft ease (Atin, 2026-09-29: the stepped trace felt choppy).

## 9. Anatomy of each overlay state

Round 6 (Atin, 2026-10-01, round 6):

```
┌────────────────────────────────────────────┐
│ …scheduler when you are done give me a one │  preview, 3 lines of 16, head-truncated
│ line summary and the diff stat and if the  │
│ suite takes longer than a minute tell me   │
│ ▏▎▍▌▏▎││▎▏···········▎│▍│▌▎▍▏▎▍▌▎▍  ■ 0:38 │  trace row: trace · square · timer
│ ╵ ╵ ╵ │ ╵ ╵ ╵ │ ╵ ╵ ╵ │ ╵ ╵ ╵ │ ╵ ╵ ╵       │  age ruler (height reserved)
│  53 WORDS  [c11] MACBOOK PRO MIC   169 WPM │  foot: words · icon + mic, centred · WPM or placard
└────────────────────────────────────────────┘
```

1. **Idle.** Hidden. The menu bar mark shows three bars.
2. **Listening.** Live preview above. Trace live, the newest 6 bars orange (the write head). Solid orange square and a running timer flush right in the trace row. The foot row: the target-app icon and the mic label centred as a pair, the live word count at its left end (also while stopped, transcribing and counting down; not on Pasted, Sent, a card or a notice, where the count shows elsewhere or means nothing) (Atin, 2026-10-01, round 6). The count shows "0 WORDS" from the first frame and steps up as words land; words per minute sits at the right end whenever the placard is empty, with the same visibility (Atin, 2026-10-01). Chips at rest (solid squares, no edge), spaced evenly down the rails. Menu bar: bars plus a solid square.
3. **Transcribing.** Preview frozen and dimmed. Bars flat at 2 pt with the orange sweep crossing every 1.05 s. The square goes hollow, the timer freezes at the final duration. Copy and Reprocess dim. **No status word.** Menu bar: bars plus an outlined square.
4. **Pasted** (was "Delivered"). The preview area swaps to the orange stamp, "Pasted into c11" and "118 WORDS" in mono. Trace flat, timer frozen (the duration appears once, here). Held 0.6 s, then dismissed. The paste was posted, not verified, hence the word.
5. **Failed → Copy.** The pill grows upward (80 pt, 96 with a two-line reason; round 6): an orange 2 pt top rule, "Couldn't paste into c11", one reason line ("No text field focused" / "The text is on your clipboard" / "Your newer clipboard was left alone, the text is in History"), the transcript clamped to 3 lines, a solid orange **Copy** (becomes "✓ Copied" at the same width for 1.4 s), **Dismiss**, and "118 WORDS". Trace row, foot row, rails and chips do not move. Stays until dismissed, the next dictation, or 10 s (the countdown pauses while the pointer is over the card and resumes with 4 s when it leaves); it then fades out over 120 ms linear like the pill (a cut under reduced motion).
6. **History.** The card opens at once, centred on the overlay and 6 pt above it (above a recovery card's grown pill too), with the listening state live underneath (Atin, 2026-10-01). An engineering table: mono index column ("01" over the time), day rows, 1 px rules, transcripts clamped to 4 lines, mono meta with the orange NOT DELIVERED marker where the paste failed, and a title-block footer ("HISTORY · 12 OF 247 · NEWEST FIRST" | "MOUTHKEYS"). Rows invert on hover; click inserts. The History chip stays inverted (latched) while the card is open. Closes on outside click, re-tap, or a row pick.

7. **Send countdown**, 8. **Sent**, 9. **Transcription timed out**, 10. **Speech recognition is back**, 11. **Microphone access is off**: added in round 5, see section 15.

Chip glyphs and SF Symbols: History `clock.arrow.circlepath`, Copy `doc.on.doc`, Cancel `xmark`, Reprocess `arrow.clockwise`, feedback `checkmark`, submenu `chevron.right`, all semibold at 13 pt. Copy on a chip: orange fill with a black check for 900 ms.

## 10. Menu bar

A 22 × 16 template mark: the grin at rest (four square-ended teeth a jaw, the bite smiling, §17); the grin plus a solid square while listening (the lower jaw opens with the level at 8 Hz) and during the Spoken Send countdown (jaw still); the grin, jaw closed, plus an outlined square while transcribing. The width never changes. The mark never changes while a dictation's stop pipeline runs (a status item image change is a WindowServer round trip on the paste's path): a slow final pass keeps the listening mark until the text is handed off, and the outlined square shows for work outside that pipeline (a reprocess, AI refinement). Hover draws the bracket inside the box. The menu is a plain `NSMenu` with a mono uppercase header: Start Dictation ⌥Space, the current microphone (submenu), History…, Settings…, Quit MouthKeys.

## 11. Native mapping (the load-bearing parts)

| Effect | SwiftUI / AppKit, macOS 15 and 26 |
|---|---|
| Pill, card | `Rectangle().fill(surface)` + `.strokeBorder(edge, lineWidth: 1)`; drop rule `.shadow(color: drop, radius: 0, x: 0, y: 2)` |
| Floating shadow (Atin, 2026-09-29) | a borderless child `NSPanel` ordered below the surface's panel (so it moves with it), `ignoresMouseEvents` set once at creation and never toggled, framed to the surface's panel plus 48 pt (refitted on the parent's moves and resizes, and never clamped onto a screen while parked), mirroring its alpha by KVO on the next main-queue turn (a card's fade takes it along). The pill's shadow stays off the dictation start path: it is ordered in two main-queue turns after the pill is shown and withdrawn once the pill hides, so showing the pill moves and orders one window. One `Canvas` fills the surface's rect, reported by `onGeometryChange` from the view its own panel hosts (a render or another host reports nowhere), with `.shadow(color: float-shadow, radius:, x: 0, y:, options: .shadowOnly)` at the appearance's values (`Palette.floatShadowRadius`, `floatShadowY`), then clears the rect, so nothing paints under a fading surface. The overlay's shadow shares the overlay's fade and hidden-opacity modifiers. Not `hasShadow`: the window server's shadow rims every painted pixel with a dark hairline, shadows the brackets and chips too, and has no per-appearance values. Not `.shadow` in the surface's own panel: its pixels would make the transparent margin take clicks |
| Double-click reset | detected in AppKit: the overlay's hosting view, after SwiftUI has the click, checks `clickCount == 2` and that the point is on no button (every Signal button style reports its frame, `SignalClickTargetsKey`). Never a SwiftUI `onTapGesture(count: 2)` on a parent: it makes every child Button wait out the double-click interval, ~350 ms, before it acts (the History lag, 2026-10-01). `HISTORY_OPEN click_to_action_ms=…` in the log times each History click |
| Selection brackets | A `Bracket: Shape` whose path is four L sub-paths, one per corner. Overlay it stroked twice (halo 3.5 pt in `surface`, then 1.5 pt in `bracket`), with negative padding of `gap + 0.75` (plus the drop rule at the bottom) so it sits outside the frame without changing layout, `allowsHitTesting(false)`, opacity driven by a single `hoveredElement` enum from `.onHover` on the pill, each chip and the card, animated `.linear(duration: 0.06)`. The non-activating panel needs an `NSTrackingArea` with `.activeAlways` |
| Chip | a `ButtonStyle`: `Rectangle` fill `chip`; `Bracket(len: 6)` at gap 2 on hover; `isPressed` or latched swaps to `inv-bg` with an outer 1 pt `surface` stroke |
| Trace row | `SignalTraceRow`: the `Canvas`, `Spacer(minLength: 12)`, a 6 pt `Rectangle` (filled or 1.5 pt outline), then the timer `.system(size: 14, weight: .semibold, design: .monospaced)` in a fixed-width trailing frame. The bar count is `SignalOverlayGeometry.traceBars`: what fits the content width less 12 and the readout (63 in the medium pill) (Atin, 2026-10-01, round 6) |
| Foot row | `SignalFootRow`, a `ZStack`: the 16 pt icon and the mic label in an `HStack(spacing: 7)`, the label framed to its own measured width (at most 160) so the pair centres; over it `SignalLiveCounters` (words, `Spacer`, WPM) and an `HStack` of `Spacer` and the placard in its reserved 7 ch trailing frame. The word count counts the whole live text (`NotchContentState.liveWordCount`, not the stored 800-character tail) and freezes at the stop (`SignalOverlayModel.frozenWordCount`) (Atin, 2026-10-01, round 6) |
| Live counters (Atin, 2026-10-01) | `SignalLiveCounters`: its own `TimelineView(.animation(minimumInterval: 1/60))`, paused while hidden and, after the stop, once the counts have finished moving (`SignalCounterSmoother.settleDuration`: the remaining words at up to 110 ms each and the ease to within half a word a minute, at most 3 s; usually well under a second), then it shows the targets, so the trace's clock and the rest of the pill are never invalidated by it. The stepping and the WPM ease live in the pure `SignalCounterSmoother`, held across updates by `SignalCounterClock` (the overlay model's, keyed by the recording's start, so nothing is added to the start path). The face (`SignalCounterFace`, `.equatable()`) redraws only when a shown number changes: the number padded with spaces to its box (SF Mono gives a space a digit's advance), the label 6 pt after it. Shown for a recording of this session, after a real stop once it has stopped, while live text arrives: the streaming preview on and a model that streams (a reprocess, the preview off, or Whisper Medium/Large or Qwen3 has no live text to count, and the counters would read 0 throughout); WPM yields to the placard whenever it has content |
| Rails | `SignalRail`: top chip, `Spacer`, bottom chip, padded by `(height - 60) / 3` rounded down; the reserved middle slot is an overlay at the centre (Atin, 2026-10-01, round 6) |
| Trace and ruler | one `Canvas` in `TimelineView(.animation)`: `fill(Path(rect))` per bar, then the static ruler ticks; the write head is the newest 6 bars in `accent`; the sweep is one accent rect stepped on the pitch |
| Trace heights | calibrated per recording, not a fixed gate: a window's peak draws by how far it rises above the recording's quiet floor (falls at once, rises 1.65 dB/s), scaled to its loud peak (rises at once, falls 1.1 dB/s, kept at least 11 dB above the gate). Settings > Sensitivity sets the gate: 6 dB above the floor at the default 0.4, 15 dB at 1.0. The fixed gate at -33 dBFS left a quiet microphone's speech on the 2 pt floor for whole dictations (2026-09-29). Each stop logs `TRACE_SUMMARY` (windows, voiced windows, bars pushed, bars raised, loudest, floor, gate, peak) |
| Mic label | mono 10 medium, `.textCase(.uppercase)`, `.tracking(0.6)`, 16 pt line, in the foot row. The Hollyland lapel mic's label (§16 item 9) is one concatenated `Text` (name, then the one percent, in `accent` when low) framed leading in the width `SignalMicLabel.layout` reserves, from `SignalOverlayModel.micBattery` |
| Failed top rule | `Rectangle().frame(height: 2)` aligned `.top` |
| Menu bar mark | `NSStatusItem` with a square-cornered template `NSImage` per state |
| Dismiss | `NSAnimationContext` 0.12 s linear `alphaValue` → 0, then park |

The full table is in `prototypes/signal/DIRECTION.md`.

## 12. Do / don't

**Do**
- Reserve height for every row that can appear; swap content in place. The only growth is the failed card, upward.
- Use inversion (white on black, black on white) for pressed, latched and hovered rows.
- Use orange only for something live or actionable right now.
- Snap every rule, tick and bar to whole points.
- Advance the trace only while the voice is on, smoothly; hold it still in silence (Atin, 2026-09-29).
- Mono uppercase for every label and number; SF Pro for anything read as prose.
- Draw brackets only under the pointer, only outside the box, only one at a time.

**Don't**
- No corner radius on anything we draw.
- No gradients, blur, glow, vibrancy, noise, springs or bounces. The floating shadow (§6) is the one blur.
- No blinking. Status is solid colour and words.
- No status words for transcribing; the hollow square, frozen timer and sweep carry it.
- No red, green or amber.
- No proportional digits.
- No chrome beyond the four chips.

## 13. Main window and onboarding

Not prototyped in this pass; Atin locked the overlay and menu bar. The tokens, type scale, radii (0), materials (none) and motion rules above apply to the main window (history, settings, custom dictionary) and to onboarding. Guidance until a dedicated round: solid surfaces with 1 px rules, sidebar rows that invert on selection, mono uppercase section labels and counts, orange only for the one live thing on a page (a recording button, an unsaved change), and the history list as the same engineering table as the overlay's card. Upstream's cards, glossy effects and teal are retired.

## 14. Decisions on record

- Anatomy stays (four corner chips, rail, trace, target-app icon, history card, drag with memory); the language changes. (Atin, round 1)
- Accent is not derived from the app icon; the icon should follow this language (square, ink, one orange mark). (Atin, round 1)
- Direction: Signal, with the earlier deck's diagram grammar and not its colours. (Atin, round 2)
- Corners are a hover affordance; no "LISTENING" word; mic bottom-centre; timer opposite the app icon. (Atin, round 3)
- Square corners throughout; brackets outside the box. (Atin, round 4)
- Assumed and unchallenged: dark by default with the light variant following the system; the delivered line stays; the mic label in every state; the bracket halo stays.
- Round 5: "Pasted into" and "Sent to" instead of "Delivered to" (Atin: no preference, the state is new); recovery cards for timed out, mic off and failed, and a lighter notice row for recognition-back (Atin, "sure, great"); app icon variant A (unchallenged). Spoken Send lives in the trace row, not a fifth chip (Atin: "Row, sounds good"); the chip alternative stays in the prototype behind `?send=chip` as an unreviewed reference only.

## 15. Round 5: Spoken Send, recovery cards, wording, icon

Added 2026-09-28 for the states the newer integration branch had. The pill stays 130 pt (149 until round 6); the rails, chips, trace row and foot row never move; only a recovery card raises the pill's top. Full tokens and native mapping: the "Round 5" section of `prototypes/signal/DIRECTION.md`.

### Spoken Send (the placard at the foot row's right end; no fifth chip)

Round 5 put the placard in the trace row; **round 6 moved it to the foot row's right end** (Atin, 2026-10-01, round 6), so the trace row is `[trace 63 bars] ≥12 [■ 6] [timer 5 ch]`. The **placard** is mono 10.5 semibold uppercase, right-aligned, width reserved for "NO SEND", empty at rest. The drain bar and the countdown timer stay in the trace row.

| Phase | Placard | Trace row | Timer |
|---|---|---|---|
| Armed (the send phrase was heard) | `SEND` orange | as usual | as usual |
| **Send countdown** (1.5 s of quiet after you stop) | `SEND` orange | flat trace plus a **drain bar**: solid orange, 4 pt tall, full trace width on the midline, shrinking from the right over 1.5 s, linear, stepped on the 4 pt pitch. No easing, no ring | `1.5` → `0.0`, orange mono, one decimal; square hollow |
| Canceled (click anywhere on the pill, the Cancel chip, or Esc, whenever `SEND` shows and the stop has not yet decided: armed, counting down, stopped or transcribing; that Esc is consumed and never reaches the app) | `NO SEND` ink | drain bar ink, stopped | frozen |
| No Return will follow (a terminal that never gets one) | `NO SEND` dim, from the moment the phrase is heard | as usual | as usual |

The rule for Esc is one gate: it drops the Return (and is consumed) only while a Return is genuinely pending (the recording is live, or its stop has begun and the send is not decided) and the bottom pill visibly shows `SEND`. Everywhere else, including the top overlay, which shows no placard, Esc does what it always did. A held Esc that dropped the Return consumes its own auto-repeats and does nothing else. A second press after a cancel: while recording, Esc or Cancel cancels the dictation, as it always did. After the stop it only dismisses the pill; the text still pastes (it is already on its way), and that Esc is not consumed, since it cancels nothing and may be meant for the app. Once the stop decides, the placard follows the decision: `SEND` only when the Return will follow; `NO SEND` in ink after a cancel; `NO SEND` dim when no Return goes there (a terminal that never gets one), since ink is reserved for a cancel.

Outcomes: a completed countdown goes to **Sent** (the stamp layout, "Sent to c11", `118 WORDS · RETURN`, 0.6 s, then dismiss). A canceled send holds 700 ms, then the text lands as **Pasted** with the placard still reading `NO SEND`. Menu bar during the countdown: the listening mark with the bars still. Today's paper-plane chip in the rail's middle slot is retired; it remains in the prototype behind `?send=chip` as the unreviewed alternative.

### Recovery card family

One anatomy for every problem: the failed card grown upward from the pill with the orange 2 pt top rule, a headline (Pro 12.5/16 semibold), 4 pt, one reason line (Pro 12/16, `text-2`, at most two), 6 pt, the transcript (failed only, 3 lines of Pro 12/16), 10 pt, then one **primary action** as a solid orange button (at least 88 × 28, 13 pt glyph, label), **Dismiss**, and mono meta on the right. Each fact appears once: cards whose duration is already on the frozen timer show no duration meta.

| State | Headline | Reason | Primary | Meta | Trace row / foot row |
|---|---|---|---|---|---|
| Failed → Copy | Couldn't paste into c11 | one of the three reasons above | **Copy** → "✓ Copied" | `118 WORDS` | flat, frozen timer / mic |
| Transcription timed out | Transcription timed out | Your audio is kept | **Reprocess** | none | flat, frozen timer / mic |
| Microphone access is off | Microphone access is off | Allow MouthKeys in Privacy & Security | **Open System Settings** (gear; opens Privacy & Security → Microphone) | none | flat, hollow square, `0:00` dim / `NO MICROPHONE` |

The Reprocess in a card and the Reprocess chip do the same thing; the chip stays. Card heights: 156 pt for a one-line card, 210 for failed, 226 with the two-line clipboard reason (Atin, 2026-10-01, round 6). Every card leaves after 10 s unless dismissed first (paused while the pointer is over it), fading over 120 ms linear. A card about the dictation the pill is holding takes the pill's place at once, so the pill reads as growing; a card about anything else, while a newer recording is live, sits above the pill.

### Notice row (lighter than a card)

For news that needs no rescue, the pill does not grow and there is no top rule. **Speech recognition is back** is the one notice today (Atin, round 5: "sure, great"). It swaps into the reserved 3-line preview area the way Pasted does: three 16 pt lines (round 6): line 1 "Speech recognition is back" (Pro 12.5 semibold), line 2 "A kept dictation is waiting" (Pro 12, `text-2`), line 3 an inline **Reprocess** text action (Pro 12 semibold in `accent`, arrow.clockwise glyph, no fill; hover draws its outside bracket, press inverts) then `·` **Dismiss** (Pro 12 medium, `text-2`). The Cancel chip also dismisses it. Trace row, foot row, rails and chips do not move. Like the card it replaced, it leaves after 10 s unless used (paused while the pointer is over the pill), with the pill's 120 ms fade. It appears on the bottom pill only when nothing else owns it; with the top overlay, or while a recording owns the pill, the notice falls back to the card.

### Wording

The paste is posted, not verified. The outcome reads **"Pasted into c11"**; the Spoken Send outcome **"Sent to c11"**; the history marker **NOT PASTED**.

### App icon

Variant A: an ink `#111214` tile, full-bleed (macOS applies its own squircle mask), with the five white square-ended bars of the twin-peak trace (heights 6 / 12 / 8 / 12 / 6 on a 16 grid, 2 units wide on a 3 pitch) and one orange 6 × 6 square at the bars' bottom right. At 32 pt and below the mark simplifies to three bars (6 / 12 / 6, 3 wide on a 5 pitch) with the orange square kept. Variant B (paper tile, ink bars) is on the icon page as the alternative. Menu bar mark unchanged. See [`prototypes/signal/icon.html`](prototypes/signal/icon.html). **Superseded by the grin, §17.**

## 16. Round 6: shorter pill, wider trace

Approved by Atin in the prototype on 2026-10-01 ("definitely nicer, really nice"). Binding: [`prototypes/signal/round6.html`](prototypes/signal/round6.html), its "ROUND 6" CSS block. The numbers are in §3, §4, §9 and §11, each marked (Atin, 2026-10-01, round 6).

1. The target-app icon moves from the trace row's left end to the foot row, 16 pt, left of the microphone; the icon and mic are centred as a pair.
2. The trace takes the freed room: horizontal padding 18 → 12, and 63 bars (5.25 s) where 39 stood.
3. Spoken Send's placard moves to the foot row's right end; the timer sits flush right in the trace row.
4. Shorter: prose 13.5/18 → 12.5/16, trace 44 → 34 (+4 ruler), timer 15 → 14, mic 10.5/13 → 10/16. The pill is 130 tall (was 149); recovery cards still grow it upward, to 156, 210 and 226.
5. Rail chips space evenly down the rail instead of pinning to the pill's corners.
6. A live word count at the foot row's left end while the dictation is live, stopped, transcribing or counting down (the prototype's default, `?words=show`).
7. The history card centres on the overlay, 6 pt above it (§4), and dark mode's floating shadow is deeper (§6).

8. **Live counters (Atin, 2026-10-01).** The word count starts at "0 WORDS" with the dictation and ticks up; words per minute ("169 WPM") takes the foot row's right end, in the placard's 7-character slot, whenever SEND / NO SEND is not showing (armed, countdown, canceled, no Return all take it back). Same face as the count (mono 10, uppercase, tracked, `text-2`), same visibility: live, stopped, transcribing and the send countdown; hidden on Pasted, Sent, the recovery cards and notices. Nothing moves as the numbers grow: words sit in a fixed 4-digit box and WPM in a 3-digit box, right-aligned, unused leading places blank ("   7 WORDS", never "0007"); clamped at 9999 and 999. Smoothing is the prototype's `tick=step`: the count steps through each burst one word at a time and WPM eases with a 0.7 s time constant (§8). Prototype: `round6.html`, "Live counters", "Fixed width" and `tickCounters()`, with `tick=step` and `pad=blank` (its defaults).

9. **The lapel mic's battery (Atin, 2026-10-01: "Hollyland lapel and then the percentage level"; the same day he asked for one number, the active mic's).** While the input is Atin's Hollyland Lark A1 (the "Hollyland Lapel Mic" aggregate or the raw "Wireless Microphone" receiver, found by its USB vendor and product, 0x3547 / 0x0407, never by name), the mic label reads **HOLLYLAND LAPEL 33%** in the mic label's face (mono 10, uppercase, tracked, `text-2`; digits are tabular by construction). Always one number: with one transmitter linked, its percent; with both linked, the **lower** of the two, since the receiver's heartbeat does not say which one is being spoken into (still "HOLLYLAND LAPEL 33%"). A linked mic that reports no valid percent is left out, so the other's shows. None linked, no reading yet, or a reading older than 2 minutes: "HOLLYLAND LAPEL" alone. Every other mic keeps its own name. Nothing moves: one box serves every lapel state, the widest reading ("HOLLYLAND LAPEL 100%", 137 pt), with the text at its left, so the centred icon and label stay put as a percent appears, changes width or goes, and as a second transmitter links or unlinks; it clears "9999 WORDS" and "999 WPM" at the row's ends. With a mode word in front, "EDIT · HOLLYLAND LAPEL 100%" would pass the mic's 160 pt, so the name there is "HOLLYLAND" ("EDIT · HOLLYLAND 33%"). The name never switches as the number changes. At 15% and below the percent is drawn in `accent` (orange is for something actionable now, §2): **our assumption, not yet confirmed with Atin.** The reading comes from the receiver's HID heartbeat (a status query that changes no setting), polled off the main thread 1 s after the input becomes the receiver and every 30 s while it stays selected; the overlay only reads the cached value (`LapelMicBatteryMonitor`, `LarkA1Protocol`). Each changed poll logs both mics, `MIC_BATTERY device=lark-a1 mic1=… mic2=… result=…`. Recovery cards show the label as the card appeared. Prototype: `round6.html?lapel=33` (also `none`, `9`, `two`, which shows the lower of 33 and 80).

Open options in the prototype, and what native does: SEND tag in the foot row (not the trace row), icon and mic centred (not flush left), rails even (not inset or flush), words shown. The PNG renders that compared native with the prototype are not committed; `scripts/capture_prototype.py` and `scripts/compose_render_compare.py` regenerate them into `native-renders/`.

## 17. The MouthKeys grin: app icon and menu bar mark (2026-10-02)

The rename to MouthKeys gave the icon a joke to tell. The trace is already mirrored about a midline; split it with a gap and its bars are a row of teeth, so the icon is a mouth full of keys in the same grammar as before (ink tile, square-ended white marks, one orange mark, no radius). Four rounds on [`prototypes/signal/icon-grin.html`](prototypes/signal/icon-grin.html), every round kept on the page: a plain grin, keycap teeth, and an orange tooth (round 1); a single oversized orange key centred in the lower jaw, declined because it "loses the mouth shape" (round 2); the orange tooth back off centre with keycap teeth, "pirate orange tooth aura is great" (round 3); heavier keycap lines so the 128 px slot reads as keys (round 4, Atin: "a little bit easier to see that they are keys at 64").

**App icon.** An ink `#111214` tile, full-bleed (macOS applies its squircle). Seven teeth a jaw on a 64-unit grid, 5 wide on a 6.4 pitch, heights from the twin-peak trace (upper 5 / 8 / 9 / 9 / 9 / 8 / 5, lower 4 / 7 / 9 / 9 / 9 / 7 / 4), a 3-unit bite that rises 2.5 units at the corners so it smiles, the whole mark scaled 1.15 about the tile centre. The fifth lower tooth, right of centre, is accent orange: the gold tooth. Detail follows the pixel count, not the point size:

| Pixels | Slots | Drawing |
|---|---|---|
| 256 and up | 128@2x, 256, 512 | every tooth (the gold one too) drawn as a keycap in plan view: top face inset 0.22 of the tooth's width and offset toward the bite, four chamfer lines, ink at 0.55, 0.3 units |
| 128 | 128@1x (the Dock at 64 pt) | the same keycaps at double weight: inset 0.24, ink at 0.8, 0.6 units |
| 64 | 32@2x | the small master, plain: five teeth a jaw, 6 wide on an 8 pitch, scaled 1.1, the fourth lower tooth gold |
| 32 and 16 | 16@2x, 32@1x, 16@1x | the small master placed on whole pixels (32 px: five teeth 3 px on a 4 px pitch; 16 px: four teeth 2 px on a 3 px pitch, the third lower tooth gold) |

`scripts/make_app_icon.swift` writes every slot of `AppIcon.appiconset` (Core Graphics, no dependencies).

**Menu bar mark.** A template image cannot be orange, so the gold tooth stays on the app icon and the mark keeps the shipping state grammar with the grin in place of the bars. Four teeth a jaw, 2 pt wide on a 3 pt pitch from x 2: upper teeth hang from y 2 to the bite at 7 (the outer two to 6), lower teeth start at 8 (the outer two at 7), 4 and 3 pt tall. The status square sits at x 15, 6 × 6, exactly as before: absent at rest, solid while listening and counting down, outlined (1.5 pt) while transcribing. While listening the lower jaw drops by `SignalMenuBarMark.listeningJaw`: 1 pt while the voice is on, 2 pt on the louder half of the range, closed once the voice has been off past the 250 ms hangover, sampled at the existing 8 Hz. The hover bracket is unchanged.

