# Liquid Voice visual language: Signal

**Status: draft, round 3 in progress (2026-09-28).** Sections marked *pending* are being revised in the prototype and will be rewritten when Atin locks the design. Everything else is stable.

The binding prototype is [`prototypes/signal/index.html`](prototypes/signal/index.html) (open through [`prototypes/serve.sh`](prototypes/serve.sh); its tokens and native mapping are in [`prototypes/signal/DIRECTION.md`](prototypes/signal/DIRECTION.md)). The two archived directions, [Obsidian](prototypes/obsidian/index.html) and [Lumen](prototypes/lumen/index.html), are reference only. The current app's anatomy is surveyed in [`notes/overlay-anatomy.md`](notes/overlay-anatomy.md); the round history is in [`notes/DIRECTIONS.md`](notes/DIRECTIONS.md).

## 1. Thesis

Liquid Voice is straight voice to text. Its overlay is seen hundreds of times a day, so the language is an **engineering drawing of an instrument**: solid surfaces, 1 px rules, square-ended ink bars, mono numerals and placards, and one colour, international orange, that only ever marks something live. No gradients, no blur, no glow, no materials. Where other apps use effects, Liquid Voice relies on alignment, weight and one accent, so every state reads in a tenth of a second and nothing moves unless it means something.

The diagram grammar (corner brackets, mono, thin rules, status in solid colour and words, never blinking) is inherited from Atin's Sekhem Prime. Its colours are not.

## 2. Colour tokens

| Token | Dark | Light | Used for |
|---|---|---|---|
| `accent` | `#FF4F1F` | `#FF4F1F` | record square, trace write head, transcribing sweep, delivered stamp, Copy, failed top rule, NOT DELIVERED marker |
| `on-accent` | `#111214` | `#111214` | glyphs and text on accent |
| `surface` | `#111214` | `#FFFFFF` | pill, history card, chips |
| `edge` | `#2C2E33` | `#111214` | 1 px pill and card edge, table rules |
| `chip` / `chip-edge` | `#1A1B1F` / `#2C2E33` | `#F2F2F4` / `#111214` | chip fill and edge |
| `drop` | `0 2 0 rgba(0,0,0,.35)` | `0 2 0 #111214` | flat, unblurred 2 pt offset rule under pill, card, chips |
| `ink` | `#FFFFFF` | `#111214` | trace bars |
| `midline` | `#2C2E33` | `#D3D4D8` | 1 px rule behind the trace |
| `text` | white 0.92 | `#111214` | preview, headlines, timer |
| `text-2` | white 0.58 | `#111214` | labels and meta; in light it is true ink and size, case and face carry the hierarchy |
| `text-dim` | white 0.46 | ink 0.50 | frozen preview while transcribing |
| `inv-bg` / `inv-fg` | `#FFFFFF` / `#111214` | `#111214` / `#FFFFFF` | pressed and latched chips, hovered history row, hovered menu row |
| `tick` | white 0.34 | ink 0.42 | corner ticks (hover affordance, *pending*) |
| `grat` | white 0.20 | ink 0.30 | age ruler ticks |

There is no green, red or amber anywhere. State is carried by orange, by words, and by inversion.

Dark is the default. The light variant is print on paper and follows the system appearance (*assumption, unconfirmed by Atin*).

## 3. Type scale

Two families: **SF Pro Text/Display** for prose and **SF Mono** (`.system(design: .monospaced)`) for every number and label. Every number is tabular by construction.

| Role | Face | Size / line | Weight | Notes |
|---|---|---|---|---|
| Elapsed timer | Mono | 15 / 18 | semibold | with the 6 pt orange square; width reserved for "99:59" |
| Mic label, meta, table header, day rows, title block, menu header | Mono | 10–10.5 / 14–18 | medium, UPPERCASE, +0.06 em | "MACBOOK PRO MICROPHONE", "0:41 · 118 WORDS · C11" |
| History index / time | Mono | 11.5 / 17 and 10 / 14 | semibold / medium | "01" over "3:04 PM" |
| Delivered headline | Pro | 16 / 20 | semibold | "Delivered to c11" |
| Live preview | Pro | 13.5 / 18 | medium | 3 lines, head-truncated so the newest words stay visible |
| Failed headline | Pro | 13.5 / 18 | semibold | "Couldn't paste into c11" |
| Transcripts (card, table) | Pro | 13 / 17–18 | regular | clamped to 3 and 4 lines |
| Menu rows, Copy, Dismiss | Pro | 13 | regular / semibold / medium | |

Minimum text size inside the overlay is 10 pt mono uppercase; body prose never drops below 13 pt.

## 4. Spacing, radii, geometry

*Pill rows are pending round 3 (label strip removed, timer on the trace row, mic label bottom-centre).*

| Token | Value |
|---|---|
| Pill width | 340 pt |
| Pill padding | 12 v × 18 h |
| Pill radius | 10 |
| Chip | 30 × 30, radius 6; rails 6 pt from the pill; chips sit at the pill's top and bottom corners |
| Trace | 65 bars, 2 pt wide on a 4 pt pitch, min 2 / max 40 tall, mirrored about a 1 px midline |
| Target-app icon | 20 pt, left end of the trace row, centred on the midline |
| History card | 480 wide, ≤ 480 tall, radius 10, 1 px edge; 36 pt header, 28 pt day rows, 68 pt index column, 28 pt title block; 6 pt above the History chip, anchored to its leading edge |
| Copy button | 88 × 28, radius 3 |
| Delivered stamp | 30 × 30, radius 3 |
| Corner ticks | 10 pt arms, 1.5 pt stroke, inset 6 pt (pill, card); 7 pt arms, inset 0 (chips); 4 pt (menu bar mark) |
| Age ruler | 1 pt ticks at bar centres, 2 / 4 / 6 pt tall at 0.25 s / 1 s / 5 s; static |
| Screen placement | bottom-centre, 50 pt above the visible bottom; whole-surface drag with position memory as fractions of the screen; double-click resets |

## 5. Materials

None. Every surface is an opaque fill with a 1 px edge and a flat 2 pt drop rule. No `NSVisualEffectView`, no vibrancy, no glass, no noise, no shadows with blur.

## 6. Motion

| Event | Duration | Curve | What happens |
|---|---|---|---|
| Entrance | 0 ms | none | The panel is simply there (first frame composed offscreen, as today) |
| Dismiss | 120 ms | linear | Opacity 1 → 0, no scale, no drop |
| Corner ticks | 60 ms | linear | Opacity in on hover, out on leave (*pending*); colour never animates, never blinks |
| Trace sample | every 83.3 ms | none | 12 per second; one new bar enters at the right |
| Bar morph | 60 ms | linear | Each slot morphs to its right neighbour's height, snapped to 2 pt steps; continues through silence at 2 pt |
| Stop → flat | 60 ms | linear | All bars go to 2 pt, the write head goes ink |
| Transcribing sweep | 1050 ms, repeating | linear | Solid 24 × 4 accent block stepped on the 4 pt pitch |
| Chip press | ≥ 60 ms | 60 ms linear colour | Inverts to a solid square, no scale |
| Copy feedback | 900 ms (chip), 1400 ms (card button) | none | Orange fill and check, same size |
| Delivered | 1200 ms | none | Then dismisses |
| Reduced motion | | | Bars jump without morph; the sweep holds 4 positions per cycle; dismiss is a cut |

No springs. Nothing eases in and out softly; everything is deliberate.

## 7. Anatomy of each overlay state

*Pending round 3. To be rewritten from the locked prototype with a measured diagram per state.*

1. **Idle**: hidden. Menu bar mark at rest.
2. **Listening**: trace live with the orange write head; live preview above; timer with orange square; mic label; chips at rest.
3. **Transcribing**: bars flat, sweep running, square hollow, timer frozen, preview dimmed. No status word.
4. **Delivered**: orange stamp and "Delivered to c11" over "118 words · 0:41" in the reserved row, 1.2 s, then dismiss.
5. **Failed → Copy**: the card grows upward from the pill; orange 2 pt top rule; transcript preview 3 lines; solid orange Copy (becomes "✓ Copied" at the same width) and Dismiss. Rails, trace and chips do not move.
6. **History**: the card above the left rail; mono index column, rules, orange NOT DELIVERED marker, title-block footer. Row hover inverts; click inserts.

## 8. Menu bar

A 16 pt template mark: three square-ended bars; a solid orange square beside them while listening; the mark outlined while transcribing. Width never changes. The menu is a plain `NSMenu` with a mono uppercase header row: Start Dictation, the current microphone, History…, Settings…, Quit.

## 9. Do / don't

**Do**
- Reserve height for every row that can appear; swap content, never grow, except the failed card, which grows upward only.
- Use inversion (white on black, black on white) for pressed, latched and hovered rows.
- Use orange only for something live or actionable right now.
- Snap every rule, tick and bar to whole pixels.
- Keep the trace scrolling through silence.
- Use mono uppercase for every label and number, SF Pro for anything a person reads as prose.

**Don't**
- No gradients, blur, glow, vibrancy, noise, springs or bounces.
- No blinking. Status is solid colour and words.
- No status words for transcribing; the sweep carries it.
- No red, green or amber.
- No proportional digits anywhere.
- No chrome that is not one of the four chips.

## 10. Out of scope of this document (to decide with Atin)

Main window (history, settings, custom dictionary) and onboarding: not yet prototyped in Signal. The tokens above apply; a dedicated round is needed before they are binding.
