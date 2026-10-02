# Signal

## Thesis

The overlay is an engineering drawing of an instrument that stays quiet until you reach for it. It is built from square solid surfaces, 1 px rules, square-ended ink bars, mono numerals and placards, and schematic selection brackets that draw outside a box's corners only under the pointer. It has no gradients, no blur, no glow and no corner radius. International orange is the only colour, and it only ever marks something live: the recording square, the trace's write head, the transcribing sweep, the delivered stamp, the failed top rule and the Copy action. Every state reads in a tenth of a second, and nothing on it moves unless it means something.

## History

- **Round 1 (2026-09-27):** a printed instrument panel. Flat surfaces, one accent, a label strip over the preview.
- **Round 2 (2026-09-28):** Atin chose Signal and asked for the earlier deck design's diagram grammar: 8-tick corner brackets ("corners are the design"), mono numbers and labels, thin rules, status in solid colour and words. We inherited the grammar, not the teal and gold.
- **Round 3 (2026-09-28), current.** Atin: *"let's only have those corners appear in a standard way on mouseover … show [the microphone] in the bottom in the middle and get rid of the listening. And then move the time to the right-hand side, the opposite on the horizontal axis from the icon."* So:
  1. **Corners are a hover affordance.** They are never drawn at rest and never orange.
  2. **The top label strip is gone** ("LISTENING", mic and timer at the top).
  3. **The timer now closes the trace row**, opposite the target-app icon.
  4. **The mic name sits bottom centre.**
  5. **There is one chip style.**
  6. **Density now only controls the age ruler.**
- **Round 4 (2026-09-28), current.** Atin: *"get rid of all the rounded corners and go with square corners throughout … have the schematic highlight corners appear outside of the box."* So:
  1. **Radius 0 everywhere we own:** pill, chips, history card, failed card, Copy button, delivered stamp, menu and its rows, record square, menu bar mark. The target-app icon keeps the shape the OS gives it, and the chip glyphs are SF Symbols.
  2. **The hover brackets now sit outside each corner**, like a schematic's selection marks or print registration marks. The rule became "the bracket marks what is under the pointer".

## Anatomy (round 3)

```
┌──────────────────────────────────────────────┐
│ …scheduler when you are done give me a one    │  preview, 3 lines, head-truncated
│ line summary and the diff stat and if the     │
│ suite takes longer than a minute tell me which│
│ [c11]  ▏▎▍▌▏▎││▎▏··········▎│▍│▌▎▍  ■  0:38  │  trace row: icon · trace · square · timer
│        ╵ ╵ ╵ │ ╵ ╵ ╵ │ ╵ ╵ ╵ │ ╵ ╵ ╵ │         │  age ruler (Drawn; reserved in Quiet)
│            MACBOOK PRO MICROPHONE             │  mic, centred
└──────────────────────────────────────────────┘
```

**Pill: 340 × 149, square.**
- Rows, top to bottom: padding 12, preview 54, gap 6, trace row 50 (a 44 trace plus a 6 ruler), gap 4, mic 13, padding 10. So 12 + 54 + 6 + 50 + 4 + 13 + 10 = **149** (v2 was 158).
- The height is reserved in every non-failed state. Failed grows **upward** to 210 (+61); its bottom rows, the rails and the chips do not move.
- The rails are 149 tall and bottom-aligned, with chips at the pill's top and bottom corners, 6 pt out.

**Trace row.** Left to right:
- the 20 pt target-app icon on the text column's left edge;
- the trace: **52 bars**, 2 pt wide on a 4 pt pitch, 206 × 44;
- the 6 pt record square;
- the timer, SF Mono semibold 15, **right-aligned in a 5 ch box reserved for "99:59"**, on the text column's right edge.

The icon, trace and readout are all centred on the trace midline. The trace kept its 2 pt grain and got shorter rather than finer: 52 bars is 4.3 s of history at 12 samples/s, down from 65 bars and 5.4 s. A 1 pt gap (pitch 3) would keep 65 bars but lose the printed spacing.

**Mic row.** SF Mono medium 10.5, uppercase, +0.06 em, secondary colour, centred, the same in listening, transcribing, delivered and failed.

**Age ruler (Drawn).** Static ticks at bar centres, 1 pt below the trace frame: 2 pt every 0.25 s (3 bars), 4 pt every 1 s (12 bars). It never scrolls; it measures age. In Quiet the 6 pt is still reserved, so toggling moves nothing.

## States

| State | Preview area | Trace row | Corners | Accent |
|---|---|---|---|---|
| Listening | live preview | live trace, orange write head (newest 6 bars), **■ solid** + running timer | on hover only, ink | square, write head |
| Transcribing | frozen preview, dimmed | flat trace, orange 24 × 4 sweep, **□ hollow** + frozen timer; Copy and Reprocess dim | on hover only | hollow square, sweep |
| Delivered | orange stamp + "Delivered to c11" / "118 WORDS" | flat trace, frozen timer (the duration) | on hover only | stamp |
| Failed → Copy | the card grows upward: headline, 3-line transcript, Copy / Dismiss / "118 WORDS" | flat trace, frozen timer | on hover only | 2 pt top rule, Copy button |
| History | listening underneath, with the card 6 pt above the History chip | live | card corners on card hover | as listening |
| Idle | hidden | | | |

## Hover grammar (round 4): brackets outside the box

A bracket is four L marks, one outside each corner. Each L's inner edge sits a **gap** clear of the box and its arms run along the outside of the two edges. They fade in over 60 ms linear on hover and fade out the same way. They never draw at rest, never turn orange, and never affect layout or hit-testing.

| Element | Gap (clear) | Arm | Shows when |
|---|---|---|---|
| Pill (and the failed card, which is the grown pill) | **3 pt** | 10 pt | the pointer is over the pill or the rails' empty gutter |
| Chip | 2 pt | 6 pt | the pointer is over that chip (not a disabled one) |
| History card | 3 pt | 10 pt | the pointer is over the card |

**Rules:**
- **The bracket marks what is under the pointer.** Over a chip or the card, only that element's bracket draws and the pill's hides. The 6 pt gutter between rail and pill cannot hold two brackets side by side: the pill's would sit 3–4.5 pt out and a chip's 2–3.5 pt out, so they would collide.
- **Clearances at 3 pt:** the pill bracket's ink sits 1.5 pt clear of the chips and its halo 0.5 pt, so nothing touches and the fallback to 2 pt was not needed. The chip brackets sit 2.5 pt clear of the pill.
- **Drop rule:** on surfaces with the 2 pt drop rule (pill, card), the bottom gap is measured from the rule's bottom edge, so the bracket never doubles the printed rule.
- **Knockout halo:** each bracket is drawn twice, first as a 1 pt halo in the surface colour, then the 1.5 pt ink stroke. Outside the box it sits on whatever is behind the overlay (in light mode often the black c11 terminal), and without the halo ink marks vanish there.

**Other hover and press states (unchanged from round 3):**
- **Chip:** at rest a solid square with no edge and no bracket; the fill keeps glyphs legible over a busy terminal. Press inverts to a solid square with a 1 pt surface keyline. It stays inverted while the history card is open (latched). Copy fills orange with a black check for 900 ms.
- **History rows** invert on hover.
- **Menu bar item:** a bracket draws around the mark, inside its 22 × 16 box, on hover and while its menu is open.

## Tokens

### Diagram grammar

| Token | Value | Notes |
|---|---|---|
| `tk-len` | 10 pt | arm length from the outer vertex: pill and card; 6 pt on chips; 4 pt in the menu bar mark |
| `tk-w` | 1.5 pt | every bracket stroke |
| `tk-gap` | 3 pt (pill, card), 2 pt (chips) | clear space between the box edge and the bracket's inner edge, outside the box |
| `tk-drop` | 2 pt | added to the bottom gap on surfaces that carry the drop rule |
| Halo | 1 pt, `surface` colour | a knockout under every bracket |
| `bracket` | white 0.78 / `#111214` | every selection bracket |
| `grat` | white 0.20 / ink 0.30 | age ruler |
| Tick fade | 60 ms linear | in and out |

### Colour

| Token | Dark | Light | Used for |
|---|---|---|---|
| `accent` | `#FF4F1F` | `#FF4F1F` | record square, write head, sweep, stamp, failed top rule, Copy, NOT DELIVERED marker |
| `on-accent` | `#111214` | `#111214` | glyphs and text on accent |
| `surface` | `#111214` | `#FFFFFF` | pill, card |
| `edge` | `#2C2E33` | `#111214` | 1 px pill and card edge, table rules |
| `chip` | `#1A1B1F` | `#F2F2F4` | chip fill |
| `drop` | `0 2 0 rgba(0,0,0,.35)` | `0 2 0 #111214` | flat offset rule under pill and card: exactly 2 pt, 0 blur (verified computed value). On square corners it reads as a printed thick bottom rule |
| `ink` | `#FFFFFF` | `#111214` | trace bars |
| `midline` | `#2C2E33` | `#D3D4D8` | 1 px rule behind the trace |
| `text` | white 0.92 | `#111214` | preview, headlines, timer |
| `text-2` | white 0.58 | `#111214` | mic, meta, table labels. In light it is true ink |
| `text-dim` | white 0.46 | ink 0.50 | frozen preview while transcribing |
| `inv-bg` / `inv-fg` | `#FFFFFF` / `#111214` | `#111214` / `#FFFFFF` | pressed and latched chips, hovered rows |

There is no green, red or amber.

## Type

SF Pro Text / Display for prose. **SF Mono** for every number and label: `.system(design: .monospaced)` natively, and the stack `"SF Mono", ui-monospace, Menlo` in the prototype. Safari renders SF Mono; Chrome falls back to Menlo, which has the same 0.6 em advance.

| Role | Face | Size / line | Weight |
|---|---|---|---|
| Timer | Mono | 15 / 18 | semibold, 5 ch box, right-aligned |
| Mic | Mono | 10.5 / 13 | medium, UPPERCASE, +0.06 em |
| Meta (history, delivered, failed) | Mono | 10.5 / 14–15 | medium, UPPERCASE, +0.06 em |
| History index / time | Mono | 11.5 / 17, 10 / 14 | semibold / medium |
| Table header, day rows, title block, menu header | Mono | 10 | medium, UPPERCASE, +0.06 em |
| Delivered headline | Pro | 16 / 20 | semibold |
| Live preview | Pro | 13.5 / 18 | medium |
| Failed headline | Pro | 13.5 / 18 | semibold |
| Transcripts | Pro | 13 / 17–18 | regular |
| Menu rows, Copy, Dismiss | Pro | 13 | regular / semibold / medium |

## Radii and materials

**0 everywhere we own.** Pill, chips, history card, failed card, Copy button, delivered stamp, menu, menu rows, record square and menu bar mark are all `Rectangle()`. The target-app icon keeps the OS shape, and the chip glyphs are the system SF Symbols. There are no materials: opaque fills, 1 px edges and a flat 2 pt drop rule, with no NSVisualEffectView, vibrancy, glass or noise.

## Motion

| Event | Duration | Curve |
|---|---|---|
| Entrance | 0 ms | the panel is simply there |
| Dismiss | 120 ms | linear opacity → 0, no scale, no drop |
| Selection brackets (hover in / out) | 60 ms | linear opacity. Colour never changes; never blinks |
| Trace sample | 83.3 ms (12/s) | one bar in at the right |
| Bar morph | 60 ms | linear, snapped to 2 pt steps |
| Stop → flat | 60 ms | linear |
| Sweep | 1050 ms, repeating | linear, stepped on the 4 pt pitch |
| Chip press | ≥ 60 ms | 60 ms linear colour, no scale |
| Copy feedback | 900 ms chip, 1400 ms button | none |
| Delivered hold | 1200 ms | then dismiss (`?hold=1` keeps it) |
| Menu bar bars | 8 Hz | 2 pt steps |
| Reduced motion | | no bar morph; the sweep holds 4 positions; dismiss and tick fades are cuts |

## Native mapping

| Effect | SwiftUI / AppKit (macOS 15 and 26) |
|---|---|
| Pill, card | `Rectangle().fill(surface)` + `.strokeBorder(edge, lineWidth: 1)`; drop rule `.shadow(color: drop, radius: 0, x: 0, y: 2)` |
| **Selection brackets** | A `Bracket: Shape` whose `path(in:)` returns four L sub-paths, one per corner: `move(to: c + (0, ±len))`, `addLine(to: c)`, `addLine(to: c + (±len, 0))`. Attach it as `.overlay(Bracket(len: 10).stroke(surface, lineWidth: 3.5).overlay(Bracket(len: 10).stroke(bracket, lineWidth: 1.5)).padding(-(gap + 0.75)).padding(.bottom, -dropRule).allowsHitTesting(false))`. That strokes it twice: the halo, then the ink. Negative padding puts it outside the frame without changing layout. Visibility is `.opacity(hoveredElement == .pill ? 1 : 0).animation(.linear(duration: 0.06))`, where `hoveredElement` comes from `.onHover` on the pill, each chip and the card. The panel needs an `NSTrackingArea` with `.activeAlways` because it is non-activating. The panel's content view must not clip: size the panel 6 pt larger on every side than the visible content |
| Chip | a `ButtonStyle`: `Rectangle` fill `chip`; the same `Bracket(len: 6)` at gap 2, shown on the chip's `.onHover`. `configuration.isPressed` or latched swaps to an `inv-bg` fill plus an outer 1 pt `surface` stroke |
| Trace row | `HStack(alignment: .center)`: `Image(nsImage: targetIcon)` 20 pt, the `Canvas`, `Spacer`, a 6 pt `Rectangle` (filled or `strokeBorder` 1.5), then `Text(time).font(.system(size: 15, weight: .semibold, design: .monospaced)).frame(width: fiveCh, alignment: .trailing)` |
| Trace + age ruler | one `Canvas` in `TimelineView(.animation)`: `fill(Path(rect))` per bar, then per ruler tick (`x = 205 − 4·age`, 1 × 2 or 1 × 4). The ruler is static, and Quiet skips it but keeps the frame height |
| Mic row | `Text(micName).font(.system(size: 10.5, weight: .medium, design: .monospaced)).textCase(.uppercase).tracking(0.63).frame(maxWidth: .infinity)` |
| Failed top rule | `Rectangle().frame(height: 2)` aligned `.top`, clipped by the pill's `clipShape` |
| Menu bar mark | `NSStatusItem` with a 22 × 16 template `NSImage` per state (bars; bars + filled square; bars + outlined square), all square-cornered. Hover: the button's tracking area redraws with the bracket inside the 22 × 16 box (the menu bar has no room outside it). The width never changes |
| Dismiss | `NSAnimationContext` 0.12 s linear `alphaValue` → 0, then park |

SF Symbols: `clock.arrow.circlepath`, `doc.on.doc`, `xmark`, `arrow.clockwise`, `checkmark`, `chevron.right`, semibold at 13 pt.

## Prototype controls

A "Signal options" strip sits under the stage's controls: **Density: Quiet | Drawn** (Drawn is the default). It persists as `density=` and toggles with **D**. The Chips toggle is retired; `C` does nothing.

Inspection hooks: `?hover=1` holds the pill's hover state (brackets drawn), `?hoverChip=cancel` holds one chip's bracket, `?hold=1` keeps Delivered up, `?menu=1` opens the menu, `?copied=1` shows both copy confirmations, `?hoverRow=2` holds a history row inverted. The state picker opens mid-dictation (0:37); Space, Play and the menu start at 0:00.

## What to look at

1. **Light theme (T), Listening (2), then move the pointer onto the pill, onto a chip, then off.** The brackets jump to whatever is under the pointer, outside its corners, with nothing else moving. Over the black terminal, the ink brackets hold on their white halo.
2. **The trace row:** icon left, timer right, the orange square beside it. Then Transcribing (3): the square goes hollow and the timer freezes.
3. **The mic at bottom centre**, identical across 2, 3, 4 and 5.
4. **Hover a chip.** Its bracket draws; press inverts it.
5. **History (6) in light.** A square, ruled engineering table; hover the card and its brackets draw outside it.
6. **D toggles the ruler**; nothing moves.

## Decisions to confirm

1. **52 bars instead of 65.** We kept the 2 pt grain and shortened history to 4.3 s. The alternative is 65 bars at a 3 pt pitch (1 pt gaps), which is denser and less printed.
2. **Delivered meta reads "118 WORDS" only.** The duration is the frozen timer in the row below, so each fact appears once.
3. **The mic is shown in every visible state**, including failed and delivered, for positional stability. Our assumption is that stability beats relevance there.
4. **No "TRANSCRIBING" word** (contract rule). The hollow square, frozen timer and sweep carry it.
5. **One bracket at a time (round 4).** Over a chip or the card, the pill's bracket hides. Both at once would collide in the 6 pt gutter.
6. **The knockout halo (round 4)** was added so outside brackets survive any backdrop. Without it they vanish over the dark terminal in light mode.

## Round 5 (2026-09-28): states from the newer code

The locked design, extended with the overlay states that later PRs added: Spoken Send, timeouts, ASR recovery, mic permission and TextDelivery failure reasons. The pill stays 149 pt, and the rails, chips, trace row and mic row never move. Every default below is our recommendation; its alternative is one URL param (also one click in the "Signal options" strip).

### Spoken Send (default: in the trace row, not a chip)

**Trace row:** `[icon 20] [trace] [placard] [■ 6] [timer 5 ch]`.
- **Placard:** SF Mono 10.5 semibold, uppercase, +0.06 em, right-aligned, width reserved for "NO SEND" (7 ch). Empty at rest.
- **Trace length:** the trace takes what is left, so it shortens from 52 bars to **39 bars** (154 pt, 3.25 s of history).

| Phase | Placard | Trace row | Timer |
|---|---|---|---|
| armed (the phrase was heard, while listening and transcribing) | `SEND`, orange | live / sweep as usual | running / frozen |
| `countdown` (1.5 s of quiet after you stop) | `SEND`, orange | flat trace plus the **drain bar**: solid orange, 4 pt tall, the full trace width on the midline, shrinking from the right toward the left | `1.5` → `0.0`, orange mono, one decimal, in the reserved box. The square is hollow |
| canceled (click anywhere on the pill, the Cancel chip, or Esc) | `NO SEND`, ink | drain bar in ink, stopped | frozen, ink |
| no Return will follow (a terminal that never gets one) | `NO SEND`, dim, from the moment the phrase is heard | as usual | as usual |

**Outcomes:**
- A canceled send holds for 700 ms, then the text lands without the phrase: `delivered` ("Pasted into c11"), with the placard still reading NO SEND.
- A completed countdown goes to **`sent`**: the stamp layout, "Sent to c11", meta `118 WORDS · RETURN`, dismissed after 1.2 s.
- With No Return, there is no countdown and the text lands.

**Drain bar motion:** 1.5 s, linear, stepped on the 4 pt bar pitch (`width = floor(remaining / 1.5 × (trace + 2) / 4) × 4`). No easing, no ring. Native: the same `Canvas`, one `fill(Path(rect))`, driven by the `TimelineView` date.

**Menu bar during the countdown:** the same solid square as listening. The bars hold still.

**Alternative, `?send=chip`:** today's design, a fifth chip in the trailing rail's reserved middle slot (top 60).
- Glyph: a filled `paperplane.fill`, which becomes the hollow `paperplane` for No Return.
- Ring: a 1.5 pt orange square that drains clockwise from top centre (`pathLength` 100, dash offset), ink once canceled.
- The row has no placard, so the trace keeps 52 bars. The timer still counts down.
- Limitation: this alternative was not polished (it is not the default). The ring renders but received no pixel-level review, and the plane glyph is a rough stand-in; the native build uses the SF Symbol.

### Recovery card family

One anatomy for every problem: the failed card, grown upward from the pill, with the orange 2 pt top rule.
- **Headline:** Pro 13.5 semibold.
- **Reason line:** Pro 13, `text-2`. One line reserved, at most two.
- **Transcript:** failed only, 3 lines.
- **Action row:** one primary as a solid orange button (at least 88 × 28, 12 pt side padding, a 13 pt glyph plus the label), then **Dismiss**, then mono meta on the right.

The pill grows upward by 25 pt for a one-line card, and the history card clears it through `--grow`.

| State | Headline | Reason | Primary | Meta | Trace row / mic row |
|---|---|---|---|---|---|
| `failed` | Couldn't paste into c11 | `nofocus` (default) "No text field focused" · `clipboard` "The text is on your clipboard" · `clipboardkept` "Your newer clipboard was left alone, the text is in History" (two lines, +17 pt) | **Copy** (doc.on.doc), which becomes "✓ Copied" in the same width | `118 WORDS` | flat, 0:41 / mic |
| `timedout` | Transcription timed out | Your audio is kept | **Reprocess** (arrow.clockwise) | none (the frozen timer shows 0:41) | flat, 0:41 / mic |
| `micoff` | Microphone access is off | Allow MouthKeys in Privacy & Security | **Open System Settings** (gearshape) | none | flat, hollow square, 0:00 dim / `NO MICROPHONE` |

The Reprocess in a card and the Reprocess chip do the same thing, and the chip stays. Pixel heights: generic card 174 pt (+25), failed 231 pt (+82), failed with the two-line reason 248 pt (+99).

**Notice row (`asrback`), not a card (Atin).** "Speech recognition is back" is good news, so it gets a lighter treatment:
- **Placement:** it lives in the pill's reserved preview slot (54 pt, three 18 pt lines) and swaps content the way Pasted does. There is no upward growth and no orange top rule.
- **Line 1:** "Speech recognition is back", Pro 13.5 semibold, `text`.
- **Line 2:** "A kept dictation is waiting", Pro 13, `text-2`.
- **Line 3:** an inline **Reprocess** text action (Pro 13 semibold, `accent`, a 12 pt `arrow.clockwise` glyph, no fill), then `·`, then **Dismiss** (Pro 13 medium, `text-2`).
- **Hover and press:** each text action draws its own outside bracket on hover (2 pt gap, 6 pt arms, like a chip), and the pill's bracket yields. Press inverts.
- **Everything else:** the trace row (flat, frozen 0:41), mic row, rails and chips are unchanged, and the Cancel chip dismisses the row.
- **Native:** a `VStack(spacing: 0)` of three 18 pt rows in the preview slot; the actions are `Button`s with a plain style plus the `Bracket` overlay on hover.

### Wording (default: truthful)

The paste is posted, not verified, so:
- The outcome reads **"Pasted into c11"**, and the Spoken Send outcome reads **"Sent to c11"**.
- The history marker reads **NOT PASTED**.
- Under `?wording=delivered` these become "Delivered to c11" and NOT DELIVERED.

### Tokens added

| Token | Value |
|---|---|
| Placard | Mono 10.5 / 14 semibold, +0.06 em, uppercase, width `7 × (1ch + 0.06em)`, right-aligned, 8 pt after the trace, 6 pt before the square |
| Placard colours | armed / countdown `accent`; canceled `text`; no Return `text-dim` |
| Drain bar | 4 pt tall, full trace width, `accent` (`ink` once canceled), 1.5 s linear, 4 pt steps |
| Countdown readout | Mono 15 semibold `accent`, `0.0` format, in the reserved 5 ch box |
| Primary button | min 88 × 28, 0 radius, 12 pt padding, 13 pt glyph, 6 pt gap, `accent` / `on-accent` |
| Reason line | Pro 13 / 17, `text-2`, clamp 2 |

### Native mapping

- **Placard:** `Text(label).font(.system(size: 10.5, weight: .semibold, design: .monospaced)).textCase(.uppercase).tracking(0.63).frame(width: sevenCh, alignment: .trailing)`, always present, empty at rest.
- **Drain bar:** the trace `Canvas`, one extra rect.
- **Countdown readout:** the timer `Text` with `String(format: "%.1f", remaining)`.
- **Cards:** one `RecoveryCard(headline:reason:showsTranscript:primary:meta:)` view reusing the failed card's layout, placed in the pill's upper region. The pill grows upward and its bottom rows are anchored.
- **Open System Settings:** `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)`.

### Prototype

- **asrback** is a notice row (above), not a card.
- **New states** in the stage list, in this order: idle, listening, transcribing, delivered (labelled "Pasted"), failed, history, countdown, sent, timedout, asrback, micoff. Digits reach the first nine.
- **Demo:** **S** plays a Spoken Send dictation.
- **Hooks:** `?armed=1`, `?t=<remaining>` (holds the countdown), `?canceled=1`, `?target=noreturn`, `?send=chip`, `?wording=delivered`, `?reason=…`.

### App icon (`icon.html`)

- **A (default):** an ink `#111214` tile with the five white square-ended bars (6 / 12 / 8 / 12 / 6 on a 16 grid, 2 wide on a 3 pitch) and one orange 6 × 6 square at the bars' bottom right.
- **B:** a paper tile with ink bars and the same orange square.
- **Drawing:** full-bleed, drawn on a 32-unit grid so the 16 pt @2x size is pixel-exact.
- **Small-size rule:** at **32 pt and below** the mark simplifies to **three bars** (6 / 12 / 6 of the 16 grid, 3 units wide on a 5 pitch, x 5 / 10 / 15), with the orange 6 × 6 square kept at x 21. 64 pt and above keep the five bars. The five-bar mark smudged at 16 pt. The page shows 1024 → 16 pt, masked with a superellipse approximating the macOS squircle and also unmasked, plus the 22 × 16 menu bar mark in its three states.
