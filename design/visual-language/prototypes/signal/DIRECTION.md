# Signal

## Thesis

The overlay is an engineering drawing of an instrument: solid surfaces, 1 px rules, 8-tick corner brackets, square-ended ink bars, and mono numerals and placards. It has no gradients, no blur and no glow. International orange is the only colour, and it only ever marks something live: the recording frame (the four corners), the recording square, the trace's write head, the transcribing sweep, the delivered stamp and the Copy action. Where the other directions use effects, Signal relies on alignment, weight and one accent, so every state reads in a tenth of a second and nothing on it moves unless it means something.

## Round 2: diagram grammar (2026-09-28)

Atin chose Signal and asked for the diagram aesthetic he uses in Sekhem Prime: "engineering-diagram type things, accented corners, crisp lines". We inherit the grammar of `Sekhem_Prime/design/deck-corners.html` and `big-number-language.html`, not its colours:
- **Corners are the design.** An 8-tick bracket draws each corner as a short horizontal and a short vertical tick, with nothing along the edges.
- **Mono** for every number and label.
- **Thin rules.**
- **Status in solid colour and words**, never blinking.

### What changed from v1

1. **Corner ticks on the pill.** They are ink at rest and turn **orange while listening**, so the four corners are the recording frame (a viewfinder's REC brackets). They return to ink while transcribing, since the sweep carries that state. They are orange on delivered (with the stamp) and on failed (with the top rule). They never move and never blink.
2. **SF Mono for every number and label:** timer, word counts, durations, the history index and time, meta rows, status and mic labels, day rows, the menu header and the title block. Transcripts and button text stay SF Pro.
3. **Graticule** under the trace (Drawn only): a static age ruler on the bar grid, with a minor tick every 0.25 s, a taller tick every second and the tallest at 5 s. To make the ruler honest, the trace now samples at exactly 12 per second (was about 11.8), so 12 bars = 1 s.
4. **Bracketed chips** as an option beside the keyed ones. There is no edge and no drop: the key is its four corners. Hover draws the full 1 px rule. Press and latch invert to a solid square. Copy still fills orange.
5. **Labels placed like a drawing.** The status label sits top-left against the corner tick, and the timer with its orange square sits top-right. In Drawn, a thin **title rule** runs under the strip. I tried an inline leader from the label to the timer and dropped it. With the default mic it gets only about 15 pt and reads as an em dash; the title rule does the same job without the noise.
6. **History card as an engineering table.** It has corner ticks, a mono index column ("01" over "3:04 PM"), mono uppercase meta rows and 1 px rules. In Drawn it adds a two-cell **title block** on the bottom edge: "HISTORY · 12 OF 247 · NEWEST FIRST" | "LIQUID VOICE".
7. **Failed → Copy** keeps its orange top rule and gains orange corners. Copy stays solid orange.
8. **Menu bar mark** in the same grammar:
   - Idle: three bars in a 4-corner bracket.
   - Listening: the bracket closes into a solid square with the bars knocked out and following the level. It is solid and never blinks.
   - Transcribing: the square is outlined.
   The status item never changes width.
9. **Radii tightened** so the ticks read square: pill and card 10 (was 12), keyed chips 6 (was 7), bracketed chips 2, stamp and Copy button 3.

### The two live options (prototype only)

A "Signal options" strip sits under the stage's controls. Both options persist in the URL (`density=`, `chips=`) and have keys **D** and **C**.

| Option | Values | What it switches |
|---|---|---|
| Density | **Quiet** | corner ticks and mono only |
|  | **Drawn** (default) | also the graticule, the title rule under the strip, and the history title block |
| Chips | Keys | v1 keys: filled, 1 px edge, 2 pt drop rule |
|  | **Brackets** (default) | surface fill, four corner ticks, no edge, no drop |

Switching options never moves anything. The title rule sits inside the existing 8 pt gap, the graticule sits in the pill's bottom padding, and both chip styles are the same 30 × 30.

## Tokens

### Diagram grammar

| Token | Value | Notes |
|---|---|---|
| `tk-len` | 10 pt | tick arm length on the pill and card; 7 pt on bracketed chips; 4 pt in the menu bar mark |
| `tk-w` | 1.5 pt | tick stroke everywhere |
| `tk-inset` | 6 pt from the surface's outer corner | inside the 10 pt radius; 0 on chips |
| `tick` (rest) | white 0.34 / ink 0.42 | pill (transcribing) and history card |
| `tick` (live) | `#FF4F1F` | pill while listening, delivered, failed |
| `bracket` | white 0.62 / `#111214` | bracketed chip corners and hover rule |
| `grat` | white 0.20 / ink 0.30 | graticule ticks and the title rule |
| Graticule | ticks 1 pt wide at bar centres, from 2 pt below the trace: 2 pt (0.25 s), 4 pt (1 s), 6 pt (5 s) | static; it measures age, so it never scrolls |

### Colour

| Token | Dark | Light | Used for |
|---|---|---|---|
| `accent` | `#FF4F1F` | `#FF4F1F` | live corners, record square, write head, sweep, stamp, Copy, failed top rule, NOT DELIVERED marker |
| `on-accent` | `#111214` | `#111214` | glyphs and text on accent |
| `surface` | `#111214` | `#FFFFFF` | pill, card, bracketed chips |
| `edge` | `#2C2E33` | `#111214` | 1 px pill and card edge, table rules |
| `chip` / `chip-edge` | `#1A1B1F` / `#2C2E33` | `#F2F2F4` / `#111214` | keyed chips |
| `drop` | `0 2 0 rgba(0,0,0,.35)` | `0 2 0 #111214` | flat, unblurred offset rule under pill, card, keyed chips |
| `ink` | `#FFFFFF` | `#111214` | trace bars |
| `midline` | `#2C2E33` | `#D3D4D8` | 1 px rule behind the trace |
| `text` | white 0.92 | `#111214` | preview, headlines, timer |
| `text-2` | white 0.58 | `#111214` | labels and meta. In light it is true ink, and size, case and face carry the hierarchy |
| `text-dim` | white 0.46 | ink 0.50 | frozen preview while transcribing |
| `inv-bg` / `inv-fg` | `#FFFFFF` / `#111214` | `#111214` / `#FFFFFF` | pressed and latched chips, hovered history row, hovered menu row |

There is no green, red or amber.

## Type scale

The two families are SF Pro Text / Display for prose and **SF Mono** for numbers and labels. SF Mono is `.system(.monospaced)` natively. In the prototype the stack is `"SF Mono", ui-monospace, Menlo`: Safari renders SF Mono, and Chrome renders Menlo, which has the same 0.6 em advance.

| Role | Face | Size / line | Weight | Notes |
|---|---|---|---|---|
| Elapsed timer | Mono | 15 / 18 | semibold | top-right, with the 6 pt orange square |
| Status / mic label | Mono | 10 / 18 | medium, UPPERCASE, +0.06 em | "LISTENING · MACBOOK PRO MICROPHONE" fits at 225 pt beside the timer |
| Meta, delivered meta, failed meta | Mono | 10.5 / 14–15 | medium, UPPERCASE, +0.06 em | "0:41 · 118 WORDS · C11" |
| History index / time | Mono | 11.5 / 17 and 10 / 14 | semibold / medium | "01" over "3:04 PM" |
| Table header, day rows, title block, menu header | Mono | 10 | medium (title-block right cell semibold) | uppercase, +0.06 em |
| Delivered headline | Pro | 16 / 20 | semibold | "Delivered to c11" |
| Live preview | Pro | 13.5 / 18 | medium | 3 lines, head-truncated |
| Failed headline | Pro | 13.5 / 18 | semibold | "Couldn't paste into c11" |
| Transcripts (card, table) | Pro | 13 / 17–18 | regular | clamped to 3 and 4 lines |
| Menu rows, Copy, Dismiss | Pro | 13 | regular / semibold / medium | |

## Geometry

- **Pill**: 340 wide, radius 10, padding 12 v × 18 h. From the top: strip 18, gap 8 (with the title rule at 4), preview 54, gap 10, trace row 44. That makes it **158 tall** in every non-failed state, and the height is reserved. The graticule lives in the bottom padding. In failed the pill grows **upward** to 193. The rails are fixed at 158 and bottom-aligned, so no chip moves.
- **Trace row**: the 20 pt target-app icon sits on the left edge of the text column. Then comes a 260 × 44 trace of 65 bars, 2 wide on a 4 pt pitch, whose newest bar ends on the text column's right edge.
- **Chips**: 30 × 30, rails 6 pt from the pill, at the pill's top and bottom corners.
- **History card**: 480 wide, at most 480 tall, radius 10, 1 px border, ticks inset 6. It has a 36 pt header, 28 pt day rows, a 68 pt index column, and a 28 pt title block (Drawn). It sits 6 pt above the History chip on the chip's leading edge (35 pt higher while the failed card is up).
- **Copy button** 88 × 28. **Delivered stamp** 30 × 30. **Menu**: radius 8, 22 pt rows.

## Materials

There are none. Every surface is an opaque fill with a 1 px edge, a flat 2 pt drop rule and ink or orange corner ticks. There is no NSVisualEffectView, vibrancy, glass or noise.

## Motion

| Event | Duration | Curve | What happens |
|---|---|---|---|
| Entrance | 0 ms | none | The panel is simply there |
| Dismiss | 120 ms | linear | Opacity 1 → 0, no scale and no drop |
| Corner ticks | 0 ms | none | Colour swaps with the state. Never animated, never blinking |
| Trace sample | every 83.3 ms | none | 12 per second; one new bar at the right edge |
| Bar morph | 60 ms | linear | Each slot morphs to its right neighbour's height, snapped to 2 pt steps |
| Stop → flat | 60 ms | linear | All bars go to 2 pt, and the write head goes ink |
| Transcribing sweep | 1050 ms, repeating | linear | Solid 24 × 4 accent block, stepped on the 4 pt bar pitch |
| Chip press | ≥ 60 ms | 60 ms linear colour | Inverts to a solid square, no scale |
| Copy feedback | 900 ms (chip), 1400 ms (card button) | none | Orange fill and check, same size |
| Delivered | 1200 ms | none | Then dismisses (skipped with `?hold=1`) |
| Menu bar knocked-out bars | 8 Hz | none | 2 pt steps |
| Reduced motion | | | Bars jump with no morph; the sweep holds 4 positions per cycle; dismiss is a cut |

## Native mapping

| Effect | SwiftUI / AppKit (macOS 15 and 26) |
|---|---|
| Pill, card, keyed chips | `RoundedRectangle(cornerRadius:, style: .continuous).fill(surface)` + `.strokeBorder(edge, lineWidth: 1)` |
| Drop rule | `.shadow(color: drop, radius: 0, x: 0, y: 2)` or a second shape offset y +2 |
| **Corner ticks** | One `Path` in the surface's `.overlay`, inset 6. For each corner: `move(to: c + (0, ±10))`, `addLine(to: c)`, `addLine(to: c + (±10, 0))`. Stroke 1.5 pt, `lineCap: .butt`, `lineJoin: .miter`, colour from state. Equivalent: eight 10 × 1.5 `Rectangle`s. `.animation(nil)` so the colour swaps instantly |
| **Bracketed chip** | `Button` with a custom `ButtonStyle`: fill `surface`, the same tick `Path` at inset 0 and length 7. Hover (`.onHover`) adds `.strokeBorder(bracket, 1)`. `isPressed` or latched swaps to a solid `inv-bg` fill |
| Voice trace + **graticule** | One `Canvas` in `TimelineView(.animation)`: `fill(Path(rect))` per bar, then per graticule tick (`x = 259 − 4·age`, 1 × 2 / 4 / 6 pt), all integer-snapped. The graticule is static |
| Title rule, table rules, title block | `Rectangle().frame(height: 1)` and `.frame(width: 1)`; the title block is an `HStack` of two cells with a 1 pt divider |
| Sweep | The same `Canvas`: one accent rect, x from the timeline date, `floor`ed to the 4 pt pitch |
| Failed top rule | `Rectangle().frame(height: 2)` aligned `.top`, clipped by the pill's `clipShape` |
| Mono type | `.font(.system(size: 10, weight: .medium, design: .monospaced)).textCase(.uppercase).tracking(0.6)`; timer `.system(size: 15, weight: .semibold, design: .monospaced)` |
| Head truncation | `Text(...).lineLimit(3).truncationMode(.head)` |
| Menu bar mark | `NSStatusItem` with a template `NSImage` per state (bracket / solid / outlined), redrawn at 8 Hz while listening |
| Menu | a plain `NSMenu`. The header is a disabled item with an attributed mono uppercase title. The system draws the highlight |
| Dismiss | `NSAnimationContext` 0.12 s linear `alphaValue` → 0, then park |

SF Symbols: `clock.arrow.circlepath`, `doc.on.doc`, `xmark`, `arrow.clockwise`, `checkmark`, `chevron.right`, semibold at 13 pt.

## What to look at

1. **Light, Listening, Drawn + Brackets** (the default; press T for light). The orange corners are the recording frame: white paper, black mono strip with a title rule, graticule under the trace, keys drawn as four corners.
2. **History (6).** The engineering table: mono index column, caps meta, orange NOT DELIVERED marker, the title block on the bottom edge. Hover a row and it inverts.
3. **Transcribing (3) after Listening (2).** The corners fall back to ink the moment the mic closes. Only the orange block moves.
4. **Density and Chips (D, C).** Flip them while watching the overlay: nothing moves, only drawing appears or disappears.
5. **The menu bar mark** at idle, while listening, and while transcribing.

Inspection hooks: `?hold=1`, `?menu=1`, `?copied=1`, `?hoverRow=2`, plus `density=` and `chips=`. The state picker opens mid-dictation (0:37); Space, Play and the menu start at 0:00.

## Decisions to confirm

1. **Bracketed chips keep a surface fill.** Without it the glyph would be illegible over a busy backdrop. Our assumption is the fill stays; the corners, not an edge, draw the key.
2. **Inline leader dropped for a title rule.** With the default mic the leader is a 15 pt stub that reads as an em dash.
3. **Failed shows both the orange top rule and orange corners.** If it reads as too loud, drop the rule and let the corners carry it.
4. **Sampling moved to exactly 12 per second** so the graticule is true. The real tap runs at about 11.7 per second; the native build would resample to 12 or label the ruler per sample rate.
5. **No "TRANSCRIBING" word** (contract rule). The hollow square, ink corners and the sweep carry it.
