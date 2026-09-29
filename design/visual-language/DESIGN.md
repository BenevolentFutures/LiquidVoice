# Liquid Voice visual language: Signal

**Status: locked by Atin, 2026-09-28** ("Awesome. This looks great. Let's go."), after four rounds on the recording overlay; **round 5 (same day) added the states the newer branch has** (Spoken Send, timeouts, recognition recovery, microphone permission, delivery-failure reasons, truthful wording, the app icon), see section 15. This document is the binding design for the native build. Where it and the prototype disagree, the prototype wins and this file gets fixed.

**Binding prototype:** [`prototypes/signal/index.html`](prototypes/signal/index.html) (tokens, native mapping and round history in [`prototypes/signal/DIRECTION.md`](prototypes/signal/DIRECTION.md)). Open it with [`prototypes/serve.sh`](prototypes/serve.sh) or double-click the self-contained copy [`prototypes/signal/standalone.html`](prototypes/signal/standalone.html). Keys: 1–6 pick a state, hold Space to talk, P plays a dictation, T toggles appearance, D toggles the age ruler.

**Reference only, archived:** [Obsidian](prototypes/obsidian/index.html) (depth) and [Lumen](prototypes/lumen/index.html) (light). The current app's anatomy before this work: [`notes/overlay-anatomy.md`](notes/overlay-anatomy.md). Round history and decisions: [`notes/DIRECTIONS.md`](notes/DIRECTIONS.md).

## 1. Thesis

Liquid Voice is straight voice to text. Its overlay is seen hundreds of times a day, so the language is **an engineering drawing of an instrument that stays quiet until you reach for it**: square solid surfaces, 1 px rules, square-ended ink bars, mono numerals and placards, and schematic selection brackets that draw outside a box's corners only under the pointer. No gradients, no blur, no glow, no materials, no corner radius. International orange is the only colour, and it only ever marks something live. Every state reads in a tenth of a second, and nothing moves unless it means something.

The diagram grammar (brackets, mono, thin rules, status in solid colour and words, never blinking) is inherited from Atin's Sekhem Prime. Its colours are not.

## 2. Colour tokens

| Token | Dark | Light | Used for |
|---|---|---|---|
| `accent` | `#FF4F1F` | `#FF4F1F` | record square, trace write head, transcribing sweep, delivered stamp, failed top rule, Copy button, NOT DELIVERED marker |
| `on-accent` | `#111214` | `#111214` | glyphs and text on accent |
| `surface` | `#111214` | `#FFFFFF` | pill, history card, failed card, menu |
| `edge` | `#2C2E33` | `#111214` | 1 px pill and card edge, table rules |
| `chip` | `#1A1B1F` | `#F2F2F4` | chip fill (no edge at rest) |
| `drop` | `0 2 0 rgba(0,0,0,.35)` | `0 2 0 #111214` | flat, unblurred 2 pt offset rule under pill and card; on square corners it reads as a printed thick bottom rule |
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
| Timer | Mono | 15 / 18 | semibold | right-aligned in a box reserved for "99:59" |
| Mic label | Mono | 10.5 / 13 | medium, UPPERCASE | bottom-centre of the pill |
| Meta (history, delivered, failed) | Mono | 10.5 / 14–15 | medium, UPPERCASE | "0:41 · 118 WORDS · C11" |
| History index / time | Mono | 11.5 / 17 and 10 / 14 | semibold / medium | "01" over "3:04 PM" |
| Table header, day rows, title block, menu header | Mono | 10 | medium, UPPERCASE | |
| Delivered headline | Pro | 16 / 20 | semibold | "Delivered to c11" |
| Live preview | Pro | 13.5 / 18 | medium | 3 lines, head-truncated so the newest words stay visible |
| Failed headline | Pro | 13.5 / 18 | semibold | "Couldn't paste into c11" |
| Transcripts (card, table) | Pro | 13 / 17–18 | regular | clamped to 3 and 4 lines |
| Menu rows, Copy, Dismiss | Pro | 13 | regular / semibold / medium | |

Nothing inside the overlay is smaller than 10 pt mono uppercase; prose never drops below 13 pt.

## 4. Spacing and geometry

| Token | Value |
|---|---|
| Pill | 340 × 149 pt, square |
| Pill rows, top to bottom | padding 12 · preview 54 · gap 6 · trace row 50 (44 trace + 6 ruler) · gap 4 · mic 13 · padding 10 |
| Pill padding, horizontal | 18 |
| Recovery cards | the pill grown **upward** to 174 (+25, one-line card), 231 (+82, failed with its transcript) or 248 (+99, failed with a two-line reason); its bottom rows, rails and chips do not move |
| Rails | 149 tall, bottom-aligned, 6 pt out from the pill; chips at the pill's top and bottom corners |
| Chip | 30 × 30, square, no edge at rest |
| Trace | 39 bars, 2 pt wide on a 4 pt pitch, 154 × 44, min 2 / max 40 tall, mirrored about a 1 px midline; 12 samples per second, so 3.25 s of history (52 bars before the Spoken Send placard was reserved) |
| Trace row | target-app icon 20 pt (left) · trace · Spoken Send placard (7 ch reserved, empty at rest) · orange square 6 pt · timer (right), all centred on the midline |
| Age ruler | static ticks at bar centres 1 pt below the trace: 2 pt every 0.25 s, 4 pt every 1 s; its 6 pt is reserved even when hidden |
| History card | 480 wide, ≤ 480 tall, square, 1 px edge; 36 pt header, 28 pt day rows, 68 pt index column, 28 pt title-block footer; 6 pt above the History chip, anchored to its leading edge |
| Copy button | 88 × 28, square |
| Delivered stamp | 30 × 30, square |
| Record square | 6 × 6, filled while listening, 1.5 pt outline while transcribing |
| Screen placement | bottom-centre, 50 pt above the visible bottom; whole-surface drag with position memory as screen fractions; double-click resets |

## 5. Corner radii

**0 everywhere we own.** Pill, chips, history card, failed card, Copy button, delivered stamp, menu, menu rows, record square and the menu bar mark are all plain rectangles. The target-app icon keeps whatever shape the OS gives it; chip glyphs are SF Symbols.

## 6. Materials

None. Every surface is an opaque fill with a 1 px edge and a flat 2 pt drop rule. No `NSVisualEffectView`, no vibrancy, no glass, no noise, no blurred shadows.

## 7. The selection brackets

The one flourish. Four L marks sit **outside** a box's corners, a gap clear of the edges, arms running along the outside of the two edges. They mark whatever is under the pointer and nothing else.

| Element | Gap | Arm | Shows when |
|---|---|---|---|
| Pill (and the failed card) | 3 pt (bottom gap measured from the drop rule) | 10 pt | pointer over the pill or the rails' gutter |
| Chip | 2 pt | 6 pt | pointer over that chip |
| History card | 3 pt | 10 pt | pointer over the card |
| Menu bar mark | inside its 22 × 16 box | 4 pt | pointer over the item, or menu open |

Rules: stroke 1.5 pt in `bracket` over a 1 pt `halo` in the surface colour (without the halo, ink marks vanish over a dark terminal in light mode). Never drawn at rest, never orange, never animated except a 60 ms linear fade in and out. One bracket at a time: over a chip or the card, the pill's hides, because the 6 pt gutter cannot hold two. Brackets never change layout or hit-testing. The window keeps a transparent margin around the visible content so they are not clipped: 6 pt on the top and sides (gap 3 + stroke 1.5 + halo 1 = 5.5) and 8 pt at the bottom, where the bracket also clears the 2 pt drop rule (7.5). The margin paints nothing, so clicks there reach the app beneath.

## 8. Motion

| Event | Duration | Curve | What happens |
|---|---|---|---|
| Entrance | 0 ms | none | The panel is simply there (first frame composed offscreen, as today) |
| Dismiss | 120 ms | linear | Opacity 1 → 0. No scale, no drop |
| Selection brackets | 60 ms | linear | Opacity in on hover, out on leave. Colour never changes, never blinks |
| Trace sample | every 83.3 ms | none | 12 per second; one new bar enters at the right; continues through silence at 2 pt |
| Bar morph | 60 ms | linear | Each slot morphs to its right neighbour's height, snapped to 2 pt steps |
| Stop → flat | 60 ms | linear | All bars go to 2 pt; the write head goes ink |
| Transcribing sweep | 1050 ms, repeating | linear | Solid 24 × 4 accent block stepped on the 4 pt pitch |
| Chip press | ≥ 60 ms | 60 ms linear colour | Inverts to a solid square with a 1 pt surface keyline. No scale |
| Copy feedback | 900 ms (chip), 1400 ms (card button) | none | Orange fill and check, same size |
| Pasted / Sent hold | 600 ms | none | Then dismiss (shortened from 1200 ms by Atin, 2026-09-28) |
| Menu bar bars | 8 Hz | none | 2 pt steps while listening |
| Reduced motion | | | Bars jump without morph; the sweep holds 4 positions per cycle; dismiss and bracket fades are cuts |

No springs. Nothing eases softly. Everything is deliberate.

## 9. Anatomy of each overlay state

```
┌──────────────────────────────────────────────┐
│ …scheduler when you are done give me a one   │  preview, 3 lines, head-truncated
│ line summary and the diff stat and if the    │
│ suite takes longer than a minute tell me     │
│ [c11]  ▏▎▍▌▏▎││▎▏··········▎│▍│▌▎▍  ■  0:38 │  trace row: icon · trace · square · timer
│        ╵ ╵ ╵ │ ╵ ╵ ╵ │ ╵ ╵ ╵ │ ╵ ╵ ╵ │        │  age ruler (D toggles; height reserved)
│            MACBOOK PRO MICROPHONE            │  mic, centred, in every visible state
└──────────────────────────────────────────────┘
```

1. **Idle.** Hidden. The menu bar mark shows three bars.
2. **Listening.** Live preview above. Trace live, the newest 6 bars orange (the write head). Solid orange square and a running timer at the right end of the trace row, opposite the target-app icon. Mic label bottom-centre. Chips at rest (solid squares, no edge). Menu bar: bars plus a solid square.
3. **Transcribing.** Preview frozen and dimmed. Bars flat at 2 pt with the orange sweep crossing every 1.05 s. The square goes hollow, the timer freezes at the final duration. Copy and Reprocess dim. **No status word.** Menu bar: bars plus an outlined square.
4. **Pasted** (was "Delivered"). The preview area swaps to the orange stamp, "Pasted into c11" and "118 WORDS" in mono. Trace flat, timer frozen (the duration appears once, here). Held 0.6 s, then dismissed. The paste was posted, not verified, hence the word.
5. **Failed → Copy.** The pill grows upward (82 pt, 99 with a two-line reason): an orange 2 pt top rule, "Couldn't paste into c11", one reason line ("No text field focused" / "The text is on your clipboard" / "Your newer clipboard was left alone, the text is in History"), the transcript clamped to 3 lines, a solid orange **Copy** (becomes "✓ Copied" at the same width for 1.4 s), **Dismiss**, and "118 WORDS". Trace row, mic row, rails and chips do not move. Stays until dismissed, the next dictation, or 10 s (the countdown pauses while the pointer is over the card and resumes with 4 s when it leaves); it then fades out over 120 ms linear like the pill (a cut under reduced motion).
6. **History.** The card opens 6 pt above the History chip, anchored to its leading edge, with the listening state live underneath. An engineering table: mono index column ("01" over the time), day rows, 1 px rules, transcripts clamped to 4 lines, mono meta with the orange NOT DELIVERED marker where the paste failed, and a title-block footer ("HISTORY · 12 OF 247 · NEWEST FIRST" | "LIQUID VOICE"). Rows invert on hover; click inserts. The History chip stays inverted (latched) while the card is open. Closes on outside click, re-tap, or a row pick.

7. **Send countdown**, 8. **Sent**, 9. **Transcription timed out**, 10. **Speech recognition is back**, 11. **Microphone access is off**: added in round 5, see section 15.

Chip glyphs and SF Symbols: History `clock.arrow.circlepath`, Copy `doc.on.doc`, Cancel `xmark`, Reprocess `arrow.clockwise`, feedback `checkmark`, submenu `chevron.right`, all semibold at 13 pt. Copy on a chip: orange fill with a black check for 900 ms.

## 10. Menu bar

A 22 × 16 template mark: three square-ended bars at rest; bars plus a solid square while listening (the bars follow the level at 8 Hz) and during the Spoken Send countdown (bars still); bars plus an outlined square while transcribing. The width never changes. The mark never changes while a dictation's stop pipeline runs (a status item image change is a WindowServer round trip on the paste's path): a slow final pass keeps the listening mark until the text is handed off, and the outlined square shows for work outside that pipeline (a reprocess, AI refinement). Hover draws the bracket inside the box. The menu is a plain `NSMenu` with a mono uppercase header: Start Dictation ⌥Space, the current microphone (submenu), History…, Settings…, Quit Liquid Voice.

## 11. Native mapping (the load-bearing parts)

| Effect | SwiftUI / AppKit, macOS 15 and 26 |
|---|---|
| Pill, card | `Rectangle().fill(surface)` + `.strokeBorder(edge, lineWidth: 1)`; drop rule `.shadow(color: drop, radius: 0, x: 0, y: 2)` |
| Selection brackets | A `Bracket: Shape` whose path is four L sub-paths, one per corner. Overlay it stroked twice (halo 3.5 pt in `surface`, then 1.5 pt in `bracket`), with negative padding of `gap + 0.75` (plus the drop rule at the bottom) so it sits outside the frame without changing layout, `allowsHitTesting(false)`, opacity driven by a single `hoveredElement` enum from `.onHover` on the pill, each chip and the card, animated `.linear(duration: 0.06)`. The non-activating panel needs an `NSTrackingArea` with `.activeAlways` |
| Chip | a `ButtonStyle`: `Rectangle` fill `chip`; `Bracket(len: 6)` at gap 2 on hover; `isPressed` or latched swaps to `inv-bg` with an outer 1 pt `surface` stroke |
| Trace row | `HStack(alignment: .center)`: the target icon, the `Canvas`, `Spacer`, a 6 pt `Rectangle` (filled or 1.5 pt outline), then the timer `.system(size: 15, weight: .semibold, design: .monospaced)` in a fixed-width trailing frame |
| Trace and ruler | one `Canvas` in `TimelineView(.animation)`: `fill(Path(rect))` per bar, then the static ruler ticks; the write head is the newest 6 bars in `accent`; the sweep is one accent rect stepped on the pitch |
| Trace heights | calibrated per recording, not a fixed gate: a window's peak draws by how far it rises above the recording's quiet floor (falls at once, rises 1.65 dB/s), scaled to its loud peak (rises at once, falls 1.1 dB/s, kept at least 11 dB above the gate). Settings > Sensitivity sets the gate: 6 dB above the floor at the default 0.4, 15 dB at 1.0. The fixed gate at -33 dBFS left a quiet microphone's speech on the 2 pt floor for whole dictations (2026-09-29). Each stop logs `TRACE_SUMMARY` |
| Mic row | mono 10.5 medium, `.textCase(.uppercase)`, `.tracking(0.63)`, centred |
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
- Keep the trace scrolling through silence.
- Mono uppercase for every label and number; SF Pro for anything read as prose.
- Draw brackets only under the pointer, only outside the box, only one at a time.

**Don't**
- No corner radius on anything we draw.
- No gradients, blur, glow, vibrancy, noise, springs or bounces.
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
- Direction: Signal, with Sekhem Prime's diagram grammar and not its colours. (Atin, round 2)
- Corners are a hover affordance; no "LISTENING" word; mic bottom-centre; timer opposite the app icon. (Atin, round 3)
- Square corners throughout; brackets outside the box. (Atin, round 4)
- Assumed and unchallenged: dark by default with the light variant following the system; the delivered line stays; the mic label in every state; the bracket halo stays.
- Round 5: "Pasted into" and "Sent to" instead of "Delivered to" (Atin: no preference, the state is new); recovery cards for timed out, mic off and failed, and a lighter notice row for recognition-back (Atin, "sure, great"); app icon variant A (unchallenged). Spoken Send's home, trace row or fifth chip, is awaiting Atin's word; the prototype builds both (`?send=chip`).

## 15. Round 5: Spoken Send, recovery cards, wording, icon

Added 2026-09-28 for the states the newer `liquid-voice` branch has. The pill stays 149 pt; the rails, chips, trace row and mic row never move; only a recovery card raises the pill's top. Full tokens and native mapping: the "Round 5" section of `prototypes/signal/DIRECTION.md`.

### Spoken Send (in the trace row; no fifth chip)

The trace row becomes `[icon 20] [trace 39 bars] [placard 7 ch] [■ 6] [timer 5 ch]`. The **placard** is mono 10.5 semibold uppercase, right-aligned, width reserved for "NO SEND", empty at rest.

| Phase | Placard | Trace row | Timer |
|---|---|---|---|
| Armed (the send phrase was heard) | `SEND` orange | as usual | as usual |
| **Send countdown** (1.5 s of quiet after you stop) | `SEND` orange | flat trace plus a **drain bar**: solid orange, 4 pt tall, full trace width on the midline, shrinking from the right over 1.5 s, linear, stepped on the 4 pt pitch. No easing, no ring | `1.5` → `0.0`, orange mono, one decimal; square hollow |
| Canceled (click anywhere on the pill, the Cancel chip, or Esc, whenever `SEND` shows and the stop has not yet decided: armed, counting down, stopped or transcribing; that Esc is consumed and never reaches the app) | `NO SEND` ink | drain bar ink, stopped | frozen |
| No Return will follow (a terminal that never gets one) | `NO SEND` dim, from the moment the phrase is heard | as usual | as usual |

The rule for Esc is one gate: it drops the Return (and is consumed) only while a Return is genuinely pending (the recording is live, or its stop has begun and the send is not decided) and the bottom pill visibly shows `SEND`. Everywhere else, including the top overlay, which shows no placard, Esc does what it always did. A held Esc that dropped the Return consumes its own auto-repeats and does nothing else. A second press after a cancel: while recording, Esc or Cancel cancels the dictation, as it always did. After the stop it only dismisses the pill; the text still pastes (it is already on its way), and that Esc is not consumed, since it cancels nothing and may be meant for the app. Once the stop decides, the placard follows the decision: `SEND` only when the Return will follow; `NO SEND` in ink after a cancel; `NO SEND` dim when no Return goes there (a terminal that never gets one), since ink is reserved for a cancel.

Outcomes: a completed countdown goes to **Sent** (the stamp layout, "Sent to c11", `118 WORDS · RETURN`, 0.6 s, then dismiss). A canceled send holds 700 ms, then the text lands as **Pasted** with the placard still reading `NO SEND`. Menu bar during the countdown: the listening mark with the bars still. Today's paper-plane chip in the rail's middle slot is retired; it remains in the prototype behind `?send=chip` as the unreviewed alternative.

### Recovery card family

One anatomy for every problem: the failed card grown upward from the pill with the orange 2 pt top rule, a headline (Pro 13.5 semibold), one reason line (Pro 13, `text-2`, at most two), the transcript (failed only, 3 lines), then one **primary action** as a solid orange button (at least 88 × 28, 13 pt glyph, label), **Dismiss**, and mono meta on the right. Each fact appears once: cards whose duration is already on the frozen timer show no duration meta.

| State | Headline | Reason | Primary | Meta | Trace row / mic row |
|---|---|---|---|---|---|
| Failed → Copy | Couldn't paste into c11 | one of the three reasons above | **Copy** → "✓ Copied" | `118 WORDS` | flat, frozen timer / mic |
| Transcription timed out | Transcription timed out | Your audio is kept | **Reprocess** | none | flat, frozen timer / mic |
| Microphone access is off | Microphone access is off | Allow Liquid Voice in Privacy & Security | **Open System Settings** (gear; opens Privacy & Security → Microphone) | none | flat, hollow square, `0:00` dim / `NO MICROPHONE` |

The Reprocess in a card and the Reprocess chip do the same thing; the chip stays. Card heights: 174 pt for a one-line card, 231 for failed, 248 with the two-line clipboard reason. Every card leaves after 10 s unless dismissed first (paused while the pointer is over it), fading over 120 ms linear. A card about the dictation the pill is holding takes the pill's place at once, so the pill reads as growing; a card about anything else, while a newer recording is live, sits above the pill.

### Notice row (lighter than a card)

For news that needs no rescue, the pill does not grow and there is no top rule. **Speech recognition is back** is the one notice today (Atin, round 5: "sure, great"). It swaps into the reserved 3-line preview area the way Pasted does: line 1 "Speech recognition is back" (Pro 13.5 semibold), line 2 "A kept dictation is waiting" (Pro 13, `text-2`), line 3 an inline **Reprocess** text action (Pro 13 semibold in `accent`, arrow.clockwise glyph, no fill; hover draws its outside bracket, press inverts) then `·` **Dismiss** (Pro 13 medium, `text-2`). The Cancel chip also dismisses it. Trace row, mic row, rails and chips do not move. Like the card it replaced, it leaves after 10 s unless used (paused while the pointer is over the pill), with the pill's 120 ms fade. It appears on the bottom pill only when nothing else owns it; with the top overlay, or while a recording owns the pill, the notice falls back to the card.

### Wording

The paste is posted, not verified. The outcome reads **"Pasted into c11"**; the Spoken Send outcome **"Sent to c11"**; the history marker **NOT PASTED**.

### App icon

Variant A: an ink `#111214` tile, full-bleed (macOS applies its own squircle mask), with the five white square-ended bars of the twin-peak trace (heights 6 / 12 / 8 / 12 / 6 on a 16 grid, 2 units wide on a 3 pitch) and one orange 6 × 6 square at the bars' bottom right. At 32 pt and below the mark simplifies to three bars (6 / 12 / 6, 3 wide on a 5 pitch) with the orange square kept. Variant B (paper tile, ink bars) is on the icon page as the alternative. Menu bar mark unchanged. See [`prototypes/signal/icon.html`](prototypes/signal/icon.html).
