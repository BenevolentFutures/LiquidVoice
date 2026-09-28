# Signal

## Thesis

The overlay is a printed instrument panel: solid surfaces, 1 px rules, square-ended ink bars, big tabular numerals and small uppercase placards. It has no gradients, no blur and no glow. International orange is the only colour, and it only ever marks something live: the recording square, the trace's write head, the transcribing sweep, the delivered stamp and the Copy action. Where the other directions use effects, Signal relies on alignment, weight and one accent, so every state reads in a tenth of a second and nothing on it moves unless it means something.

## Colour tokens

| Token | Dark | Light | Used for |
|---|---|---|---|
| `accent` | `#FF4F1F` | `#FF4F1F` | record square, write head, sweep, delivered stamp, Copy, failed top rule, NOT DELIVERED marker |
| `on-accent` | `#111214` | `#111214` | glyphs and text on accent |
| `surface` | `#111214` | `#FFFFFF` | pill, history card |
| `edge` | `#2C2E33` | `#111214` | 1 px pill and card edge, card rules |
| `chip` / `chip-edge` | `#1A1B1F` / `#2C2E33` | `#F2F2F4` / `#111214` | chips |
| `drop` | `0 2 0 rgba(0,0,0,.35)` | `0 2 0 #111214` | one flat offset rule under every surface, with no blur |
| `ink` | `#FFFFFF` | `#111214` | trace bars |
| `midline` | `#2C2E33` | `#D3D4D8` | 1 px rule behind the trace |
| `text` | white 0.92 | `#111214` | preview, headlines, timer |
| `text-2` | white 0.58 | `#111214` | labels and meta. In light it is true ink, and size, case and weight carry the hierarchy |
| `text-dim` | white 0.46 | ink 0.50 | frozen preview while transcribing |
| `glyph` / `glyph-off` | white 0.85 / 0.28 | `#111214` / ink 0.28 | chip glyphs, enabled / disabled |
| `inv-bg` / `inv-fg` | `#FFFFFF` / `#111214` | `#111214` / `#FFFFFF` | pressed and latched chips, hovered history row, hovered menu row |

There is no green, red or amber. Words and the one accent carry every state.

## Type scale (SF Pro Text / Display; every number uses `.monospacedDigit()`)

| Role | Size / line | Weight | Notes |
|---|---|---|---|
| Elapsed timer | 15 / 18 | semibold | right-aligned, always present while listening |
| Delivered headline | 16 / 20 | semibold | "Delivered to c11" |
| Live preview | 13.5 / 18 | medium | 3 lines, head-truncated so the newest words stay |
| Failed headline | 13.5 / 18 | semibold | "Couldn't paste into c11" |
| Failed transcript, history transcript | 13 / 17–18 | regular | clamped to 3 (card) and 4 (history) lines |
| Menu rows, Copy, Dismiss | 13 | regular / semibold / medium | |
| Meta and history index | 11.5 / 15–17 | medium / semibold | "0:41 · 118 words · c11", "01" |
| Label (placard) | 10.5 / 18 | semibold, UPPERCASE, +0.06 em | "LISTENING · MACBOOK PRO MICROPHONE", "RECENT DICTATIONS", "TODAY · SEP 27", "NOT DELIVERED" |

## Geometry and radii

- **Pill**: 340 wide, radius **12** (tighter than today's 18), padding 12 v × 18 h. From the top it holds a strip (18), 8, the preview (54), 10 and the trace row (44). That makes it **158 tall** in every non-failed state, and the height is reserved. In failed it grows **upward** to 193. The rails are fixed at 158 and bottom-aligned, so no chip moves.
- **Trace row**: 20 pt target-app icon on the left edge of the text column, then a 260 × 44 trace whose newest bar ends on the text column's right edge. Two edges and one grid.
- **Chips**: 30 × 30 squares, radius 7, glyph box 16, stroke 1.75. The rails sit 6 pt from the pill, with chips at the pill's top and bottom corners.
- **History card**: 480 wide, at most 480 tall, radius 12, 1 px border. It sits 6 pt above the History chip on the chip's leading edge (35 pt higher while the failed card is up). It has a 36 pt header, 28 pt day rows, a 64 pt index column (index over time), and 1 px rules between rows.
- **Copy button**: 88 × 28, radius 7. **Delivered stamp**: 30 × 30, radius 7. **Menu**: radius 8, 22 pt rows, 1 px separators.

## Materials

There are none. Every surface is an opaque fill with a 1 px edge and a flat, unblurred 2 pt drop rule. The panel keeps `hasShadow = false`. The drop rule is part of the drawing, not a window shadow. There is no NSVisualEffectView, vibrancy, glass or noise.

## Motion

| Event | Duration | Curve | What happens |
|---|---|---|---|
| Entrance | 0 ms | none | The panel is simply there, pre-composed offscreen as today |
| Dismiss | 120 ms | linear | Opacity 1 → 0, no scale and no drop, then parked |
| Trace sample | every 85 ms | none | One new bar at the right edge (about the real tap's 11.7 samples/s) |
| Bar morph | 60 ms | linear | Each slot morphs to its right neighbour's height, snapped to 2 pt steps |
| Stop → flat | 60 ms | linear | All bars go to 2 pt. The fade bands stay; the write head goes ink |
| Transcribing sweep | 1050 ms, repeating | linear | Solid 24 × 4 accent block, stepped on the 4 pt bar pitch |
| Chip press | ≥ 60 ms | 60 ms linear colour | Chip inverts, no scale |
| Copy feedback | 900 ms (chip), 1400 ms (card button) | none | Accent fill and check, same size; "Copy" → "✓ Copied" in the same 88 pt |
| Delivered | 1200 ms | none | Then dismisses (skipped with `?hold=1`) |
| Menu bar live bars | 8 Hz | none | Knocked-out bars follow the level in 2 pt steps |
| Reduced motion | | | Bars jump with no morph. The sweep holds 4 discrete positions per cycle. Dismiss is a cut |

Nothing eases in and out, and nothing springs.

## Native mapping

| Effect | SwiftUI / AppKit (macOS 15 and 26) |
|---|---|
| Pill, chips, card | `RoundedRectangle(cornerRadius:, style: .continuous).fill(surface)` plus `.strokeBorder(edge, lineWidth: 1)` |
| Drop rule | `.shadow(color: drop, radius: 0, x: 0, y: 2)`, or a second shape offset y +2 behind the surface |
| Failed top rule | `Rectangle().frame(height: 2)` aligned `.top`, clipped by the pill's `clipShape` |
| Voice trace | `Canvas` in `TimelineView(.animation)`: 65 `fill(Path(rect))` calls, integer-snapped. Opacity bands are per-bar `opacity` constants. The midline is a 1 pt rect |
| Sweep | The same `Canvas` draws one accent rect. x comes from the timeline date, `floor`ed to the 4 pt pitch |
| Chip press / latch | `ButtonStyle` whose `configuration.isPressed` swaps fill and foreground, plus an outer 1 pt `strokeBorder` in the surface colour (the keyline) |
| Hover edge | `.onHover` swaps the stroke colour to accent |
| Copy check swap | `Image(systemName:)` swapped by state; the frame never changes |
| Labels | `.font(.system(size: 10.5, weight: .semibold)).textCase(.uppercase).tracking(0.63)` |
| Head truncation | `Text(...).lineLimit(3).truncationMode(.head)` |
| Menu bar glyph | `NSStatusItem` with a template `NSImage` drawn per state. While listening the image is redrawn at 8 Hz |
| Menu | a plain `NSMenu`. The top row is a disabled item with an attributed uppercase title. The system draws the highlight (the prototype shows the Signal inversion) |
| Dismiss | `NSAnimationContext` 0.12 s linear `alphaValue` → 0, then park |

SF Symbols: `clock.arrow.circlepath` (History), `doc.on.doc` (Copy), `xmark` (Cancel), `arrow.clockwise` (Reprocess), `checkmark` (feedback, stamp), `chevron.right` (menu submenu). All are rendered semibold at 13 pt.

## Menu bar mark

A 16 pt template glyph where **the frame means "a session is open"**.
- **Idle**: three bold square-ended bars, 3 pt wide, 6 / 12 / 8 tall.
- **Listening**: a solid rounded square with three bars knocked out that follow the live level.
- **Transcribing**: the same square, outlined.

The width never changes, so the menu bar never shifts.

## What to look at

1. **Light, History (6 then T).** Print on paper: white card, black ledger rules, "01 / 3:04 PM" index column, an orange square on NOT DELIVERED. Hover a row and it inverts to solid ink.
2. **Listening trace.** 65 square-ended bars in four printed opacity steps, a 6-bar orange write head at the right, a 1 pt midline, and 2 pt dashes that keep scrolling through silence.
3. **Transcribing (3).** Only the orange block moves. The strip drops "LISTENING ·", the square goes hollow, the preview dims, and Copy and Reprocess dim without moving.
4. **Press any chip.** It inverts for the press, with no scale. Copy fills orange with a black check for 900 ms.
5. **Failed (5).** The card grows up from the pill. Trace and chips stay exactly where they were. The orange top rule and the orange Copy carry the state; Copy becomes "✓ Copied" in the same width.
6. **Play (P).** Timer from 0:00, flat, sweep, orange stamp, 120 ms fade.

Inspection hooks: `?hold=1` keeps Delivered up, `?menu=1` opens the menu, `?copied=1` shows both copy confirmations, `?hoverRow=2` holds a history row inverted. Choosing a state from the picker opens mid-dictation (0:37) so the steady state is visible. Space, Play and the menu start a real dictation at 0:00.

## Decisions to confirm

1. **No "TRANSCRIBING" label.** The contract forbids status words there, so transcribing is signalled by the sweep, the hollow square and the dimmed preview, not a word.
2. **Label tracking is +0.06 em, not +0.08.** At 0.08, "LISTENING · MACBOOK PRO MICROPHONE" truncates beside the timer. At 0.06 it fits with a 12 pt gap. Longer mic names tail-truncate.
3. **The pill is 158 tall (today about 102–130)**, because the label strip is a row of its own. Dropping the preview to 2 lines would bring it to 140.
4. **Delivered is two lines:** "Delivered to c11" over "118 words · 0:41", beside an orange stamp. It is the contract's line broken for scale.
