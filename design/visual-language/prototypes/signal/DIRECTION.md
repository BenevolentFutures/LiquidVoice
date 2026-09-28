# Signal

## Thesis

The overlay is an engineering drawing of an instrument that stays quiet until you reach for it. It is built from solid surfaces, 1 px rules, square-ended ink bars, mono numerals and placards, and corner brackets that draw only under the pointer. It has no gradients, no blur and no glow. International orange is the only colour, and it only ever marks something live: the recording square, the trace's write head, the transcribing sweep, the delivered stamp, the failed top rule and the Copy action. Every state reads in a tenth of a second, and nothing on it moves unless it means something.

## History

- **Round 1 (2026-09-27):** a printed instrument panel. Flat surfaces, one accent, a label strip over the preview.
- **Round 2 (2026-09-28):** Atin chose Signal and asked for Sekhem Prime's diagram grammar: 8-tick corner brackets ("corners are the design"), mono numbers and labels, thin rules, status in solid colour and words. We inherited the grammar, not the teal and gold.
- **Round 3 (2026-09-28), current.** Atin: *"let's only have those corners appear in a standard way on mouseover … show [the microphone] in the bottom in the middle and get rid of the listening. And then move the time to the right-hand side, the opposite on the horizontal axis from the icon."* So:
  1. **Corners are a hover affordance.** They are never drawn at rest and never orange.
  2. **The top label strip is gone** ("LISTENING", mic and timer at the top).
  3. **The timer now closes the trace row**, opposite the target-app icon.
  4. **The mic name sits bottom centre.**
  5. **There is one chip style.**
  6. **Density now only controls the age ruler.**

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

**Pill: 340 × 149.**
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

## Hover grammar

- **Overlay:** with the pointer anywhere over the overlay (pill or rails), the pill's 8-tick corners draw in ink at the rest tick colour. They fade in over 60 ms linear and fade out the same way on leave.
- **Chip:** at rest, a solid square (radius 2) with no edge and no bracket; the fill keeps glyphs legible over a busy terminal. On chip hover, its own 4-corner bracket draws in ink. Press inverts to a solid square with a 1 px surface keyline. It stays inverted while the history card is open (latched). Copy fills orange with a black check for 900 ms.
- **History card:** its corners draw on card hover. Rows invert on hover.
- **Menu bar item:** a bracket draws around the mark on hover and while its menu is open.

## Tokens

### Diagram grammar

| Token | Value | Notes |
|---|---|---|
| `tk-len` | 10 pt | pill and card; 7 pt on chips; 4 pt in the menu bar mark |
| `tk-w` | 1.5 pt | every tick |
| `tk-inset` | 6 pt (pill), 5 pt (card), 0 (chips) | inside the 10 pt radius |
| `tick` | white 0.34 / ink 0.42 | pill and card corners on hover |
| `bracket` | white 0.62 / `#111214` | chip corners on hover |
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
| `drop` | `0 2 0 rgba(0,0,0,.35)` | `0 2 0 #111214` | flat offset rule under pill and card |
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

Pill and card 10, chips 2, stamp and Copy button 3, menu 8. There are no materials: opaque fills, 1 px edges and a flat 2 pt drop rule, with no NSVisualEffectView, vibrancy, glass or noise.

## Motion

| Event | Duration | Curve |
|---|---|---|
| Entrance | 0 ms | the panel is simply there |
| Dismiss | 120 ms | linear opacity → 0, no scale, no drop |
| Corner ticks (hover in / out) | 60 ms | linear opacity. Colour never changes; never blinks |
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
| Pill, card | `RoundedRectangle(cornerRadius: 10, style: .continuous).fill(surface)` + `.strokeBorder(edge, lineWidth: 1)`; drop rule `.shadow(color: drop, radius: 0, x: 0, y: 2)` |
| **Hover corners** | `@State var hovering`, set by `.onHover` on the overlay's root `HStack`. The pill's `.overlay` holds one `Path`, inset 6: for each corner `move(to: c + (0, ±10))`, `addLine(to: c)`, `addLine(to: c + (±10, 0))`, stroked 1.5 pt with `.butt` / `.miter`. Apply `.opacity(hovering ? 1 : 0).animation(.linear(duration: 0.06), value: hovering)`. The panel needs an `NSTrackingArea` with `.activeAlways` because it is non-activating |
| Chip | a `ButtonStyle`: `Rectangle` fill `chip` (radius 2); its own tick `Path` (inset 0, length 7) is shown on the chip's `.onHover`. `configuration.isPressed` or latched swaps to an `inv-bg` fill plus an outer 1 pt `surface` stroke |
| Trace row | `HStack(alignment: .center)`: `Image(nsImage: targetIcon)` 20 pt, the `Canvas`, `Spacer`, a 6 pt `Rectangle` (filled or `strokeBorder` 1.5), then `Text(time).font(.system(size: 15, weight: .semibold, design: .monospaced)).frame(width: fiveCh, alignment: .trailing)` |
| Trace + age ruler | one `Canvas` in `TimelineView(.animation)`: `fill(Path(rect))` per bar, then per ruler tick (`x = 205 − 4·age`, 1 × 2 or 1 × 4). The ruler is static, and Quiet skips it but keeps the frame height |
| Mic row | `Text(micName).font(.system(size: 10.5, weight: .medium, design: .monospaced)).textCase(.uppercase).tracking(0.63).frame(maxWidth: .infinity)` |
| Failed top rule | `Rectangle().frame(height: 2)` aligned `.top`, clipped by the pill's `clipShape` |
| Menu bar mark | `NSStatusItem` with a 22 × 16 template `NSImage` per state (bars; bars + filled square; bars + outlined square). Hover: the button's tracking area redraws with the bracket. The width never changes |
| Dismiss | `NSAnimationContext` 0.12 s linear `alphaValue` → 0, then park |

SF Symbols: `clock.arrow.circlepath`, `doc.on.doc`, `xmark`, `arrow.clockwise`, `checkmark`, `chevron.right`, semibold at 13 pt.

## Prototype controls

A "Signal options" strip sits under the stage's controls: **Density: Quiet | Drawn** (Drawn is the default). It persists as `density=` and toggles with **D**. The Chips toggle is retired; `C` does nothing.

Inspection hooks: `?hover=1` holds the overlay's hover state (corners drawn), `?hoverChip=cancel` holds one chip's bracket, `?hold=1` keeps Delivered up, `?menu=1` opens the menu, `?copied=1` shows both copy confirmations, `?hoverRow=2` holds a history row inverted. The state picker opens mid-dictation (0:37); Space, Play and the menu start at 0:00.

## What to look at

1. **Listening (2), then move the pointer onto the overlay and off.** The corners draw in and out; nothing else changes.
2. **The trace row:** icon left, timer right, the orange square beside it. Then Transcribing (3): the square goes hollow and the timer freezes.
3. **The mic at bottom centre**, identical across 2, 3, 4 and 5.
4. **Hover a chip.** Its bracket draws; press inverts it.
5. **Light theme (T), with D toggled.** The ruler appears and disappears; nothing moves.

## Decisions to confirm

1. **52 bars instead of 65.** We kept the 2 pt grain and shortened history to 4.3 s. The alternative is 65 bars at a 3 pt pitch (1 pt gaps), which is denser and less printed.
2. **Delivered meta reads "118 WORDS" only.** The duration is the frozen timer in the row below, so each fact appears once.
3. **The mic is shown in every visible state**, including failed and delivered, for positional stability. Our assumption is that stability beats relevance there.
4. **No "TRANSCRIBING" word** (contract rule). The hollow square, frozen timer and sweep carry it.
