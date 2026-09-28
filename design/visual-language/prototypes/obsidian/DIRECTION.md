# Obsidian

## Thesis

The overlay is a precision instrument milled from one block of black glass: heavy, exact, quiet, and slightly luminous only where the signal lives. Depth comes from light on edges (a top edge light, hairline rims, keycap bevels, a phosphor bloom on the trace), never from gradients on faces. It keeps the soul of today's pure-black pill and grainy, contrasty trace, and makes them material.

## Geometry

| Element | Value |
|---|---|
| Overlay | 416 wide: key rail 32, gap 6, pill 340, gap 6, key rail 32. Bottom edge 50 above the screen bottom. |
| Pill | 340 × 128, radius 18, padding 18 h × 12 v. Failed only: 340 × 149, grown **upward** by 21. Keys and trace baseline never move. |
| Preview area | top 12, 304 × 54 (3 lines × 18), bottom-anchored, head-truncated with a leading "…" |
| Trace row | bottom 12, height 44. App icon 20 at leading inset 11, centred on the midline. Trace 260 × 44 at x 40. Elapsed counter centred at x 319, mirroring the icon. |
| Trace | 65 bars, 2 wide, 4 pitch (258 drawn), min 2, max 40, mirrored capsules |
| Keys (rails) | 32 × 26, radius 9. Rails are 128 tall and bottom-aligned, so the top keys sit on the pill's top corners. |
| Copy button (failed) | 88 × 28, radius 9, label and glyph centred, same box for "Copied" |
| History card | 480 × up to 440, radius 14. Leading edge = History key's leading edge; bottom = key top − 6. Absolutely positioned: never moves the overlay. 440 (contract allows 480) so a row is always cut under the fade and the scroll reads. |
| Menu | 300 wide, radius 10, padding 5, rows 22, row highlight radius 5 |

Measured in Chrome with getBoundingClientRect across all five visible states in both themes: the four keys are identical to the hundredth of a pixel, and the pill's x, bottom and width never change.

## Colour tokens

| Token | Dark | Light | Use |
|---|---|---|---|
| `face` | `#070709` | `#1E2024` (polished graphite) | pill face |
| `card` | `#131317` | `#26282D` | history card, one step lighter |
| `key` | `#0B0B0E` | `#2A2C31` | keycap face |
| `edge-top` | white 0.16 → 0 over 52 px | white 0.28 → 0 | 1 px inner top edge light |
| `edge-out` | white 0.09, 0.5 px | black 0.30, 0.5 px | outer hairline (dark hairline on a light desk) |
| `key-top` / hover / pressed | white 0.15 / 0.30 / 0.05 | 0.22 / 0.42 / 0.08 | keycap top bevel |
| `key-shade` | black 0.70 | black 0.40 | keycap bottom bevel |
| `shadow` | 0 10 30 black 0.55 + 0 1 2 black 0.60 | 0 8 24 black 0.30 + 0 1 2 black 0.35 | pill |
| `ink` | white 0.92 | same | live preview |
| `ink-2` | white 0.85 | same | failed transcript |
| `meta` | white 0.55 | same | counter, labels, word counts (the contract's 55% floor) |
| `glyph` | cool white `rgb(236,240,248)` 0.78, hover 1.0, disabled 0.28 | 0.82 / 1.0 / 0.30 | key glyphs |
| `hair` | white 0.08 | white 0.09 | card dividers |
| `trace` | `#E9EDF4`, newest bars warm to `#FAFBFF` | same | bars |
| `bloom` | trace 0.35, radius 5 | 0.46 | phosphor bloom |
| `afterglow` | `rgb(176,198,236)`, blur 7, layer 0.25 | layer 0.30 | persistence glow |
| `amber` | `#FFB65C` | same | failed LED, Copy button edge, "Not pasted" |
| `ok` | `#9FE3B2` | same | delivered check, flat delivered line, Copied |

Recording itself is white. There is no red REC.

## Type scale (SF Pro Text, tabular numerals everywhere)

| Role | Size / line | Weight | Colour |
|---|---|---|---|
| Live preview | 13.5 / 18 | Medium | ink 0.92 (frozen while transcribing: 0.62) |
| Delivered line | 13.5 / 18 | Medium; app name Semibold | ink, trailing counts meta |
| Failed headline | 13.5 / 18 | Semibold | white |
| Failed transcript | 13 / 17, 3 lines | Regular | 0.85 |
| History entry | 13 / 18, 4 lines | Regular | 0.90 |
| Meta (counter, counts, history meta) | 11.5 / 14 | Medium, +0.02em | 0.55 |
| Labels (mic readout, card header) | 11–11.5, uppercase | Medium/Semibold, +0.06–0.07em | 0.55 |
| Copy button | 13 | Semibold | white |
| Menu rows | 13 | Regular | 0.92, shortcuts 0.50 |

## Materials

- **Black glass slab** (pill, card): flat near-black face, 3.5% static grain, 1 px top edge light fading out, 0.5 px outer hairline, deep soft shadow plus a tight contact shadow. No material, no blur, no vibrancy.
- **Machined keycap** (keys, Copy button): the same face with a bevel: a top highlight, a bottom shade, an outer hairline and a short drop. Hover brightens the edge; press sinks the cap 1 px and shortens its shadow. The History key is **lit** (not sunk) while its card is open, so it never moves.
- **Phosphor** (trace): crisp capsules with a tight bloom, over a blurred afterglow of the trace's decaying peak-hold, so loud syllables linger faintly the way a CRT trace does.
- **Status LED** (failed): a 7 px amber dot with a soft glow beside the headline. Calm, legible, not an alarm.

## States

| State | What shows |
|---|---|
| idle | Nothing. The menu bar glyph at rest. |
| listening | Live preview (3 lines, newest words on the line nearest the trace). Before the first words: a `MIC  MACBOOK PRO MICROPHONE` readout in that slot, so an AirPods hijack is visible at a glance. Trace scrolls at 85 ms per sample, including tiny bars in silence. Counter runs. |
| transcribing | Preview freezes at 0.62, counter freezes, trace eases flat and a white sweep crosses it every 1.05 s. No words. Copy and Reprocess dim (as today). |
| delivered | One centred line: green-white check, "Delivered to **c11** · 118 words · 0:41". The counter hides (the line carries the time). The flat trace turns green-white. Dismisses after 1.2 s. |
| failed | The pill grows 21 px upward into a Copy card: amber LED + "Couldn't paste into c11", 3 lines of transcript, then Copy keycap, Dismiss, "189 words · 1:06" in the trace row's slot. |
| history | The card over listening. Rows lift on hover; "Not pasted" in amber marks the failed entry. |

## Motion

| Event | Duration | Curve | Notes |
|---|---|---|---|
| Entrance | 90 ms | linear opacity | first frame fully composed at its final size |
| Dismiss | 140 ms | cubic-bezier(0.4, 0, 1, 1) | opacity 0, scale 0.985, drop 6 px |
| Key hover / press | 80 ms | linear | press = 1 px sink, top light 0.05 |
| Content swap (delivered, failed, card) | 100 ms | linear fade-in | slots never resize |
| Failed growth | 120 ms | cubic-bezier(0.2, 0, 0, 1) | upward only |
| Bar morph | 60 ms per sample | linear | one sample per 85 ms buffer |
| Flatten on stop | 180 ms | ease-out cubic | as today |
| Sweep | 1050 ms | linear, repeating | window ±0.3 of the width, cosine profile |
| Copy key check | 900 ms | swap | green-white check |
| Copy button "Copied" | 1800 ms | swap | same 88 px box |
| Delivered hold | 1200 ms | then Dismiss | skipped with `?hold=1` |
| Menu bar micro-trace | 120 ms step | none | four bars shift left with the level |

No springs anywhere. **Reduced motion:** entrance and dismiss are instant, bars jump rather than morph, the sweep becomes a slow 1.6 s crossfade of the dim line, and the menu bar glyph holds a static listening pose.

## Native mapping

| Effect | SwiftUI / AppKit |
|---|---|
| Pill face | `RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.027))` in the existing borderless `NSPanel` |
| Top edge light | `.strokeBorder(LinearGradient([.white.opacity(0.16), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 52 / height)), lineWidth: 1)` (today's border technique) |
| Outer hairline | second `strokeBorder` at 0.5 pt, or `layer.borderWidth = 0.5` on an outset layer |
| Grain | a 128 px opaque grey-noise PNG, `Image(...).resizable(resizingMode: .tile).opacity(0.035)`, clipped to the shape |
| Shadows | two `.shadow()` modifiers (0.55 r15 y10, 0.6 r1 y1); window shadow stays off, as today |
| Keycap bevel | `RoundedRectangle(9)` + top inner line (inset `Rectangle().frame(height: 1)` masked to the shape) + bottom inner line + 0.5 pt stroke + `.shadow`; press via a `ButtonStyle` reading `configuration.isPressed` → `.offset(y: 1)` |
| Keys as real buttons | switch today's `onTapGesture` chips to `Button` with that style, which also gives the missing pressed state |
| Copy feedback | swap `doc.on.doc` → `checkmark` for 0.9 s in a fixed `frame(width: 32, height: 26)` |
| Trace bars | today's `ForEach` of capsules keyed by slot + `withAnimation(.linear(duration: 0.06))`; per-bar opacity `0.35 + 0.65·t^1.4` |
| Phosphor bloom | `.compositingGroup().shadow(color: trace.opacity(0.35), radius: 5)` on the bar row (one composited shadow, as today) |
| Afterglow | a second bar row driven by a decaying peak-hold array (`max(h, prev·0.84)`), `.blur(radius: 7).opacity(0.25)` behind the bars |
| Sweep | today's `CAGradientLayer` locations animation (1.05 s, linear, repeat) masked to the bars |
| Timer | `Text(timerInterval:)` or a `TimelineView(.periodic(by: 1))` with `.monospacedDigit()` |
| Head truncation | `Text(tail).lineLimit(3).truncationMode(.head)` in `frame(height: 54, alignment: .bottomLeading)` |
| Failed growth | pill `frame(height:)` 128 → 149 inside a bottom-aligned `HStack`; rails `frame(height: 128)`; `.animation(.timingCurve(0.2, 0, 0, 1, duration: 0.12))` |
| Amber LED | `Circle().fill(amber).frame(width: 7, height: 7).shadow(color: amber.opacity(0.55), radius: 3)` |
| History card | today's child `NSPanel`; origin x = key.minX, y = key.maxY + 6; surface `#131317`, same edge light; list `ScrollView` with a bottom `mask` gradient |
| Dismiss | `.scaleEffect(0.985).offset(y: 6).opacity(0)` with `.timingCurve(0.4, 0, 1, 1, duration: 0.14)`, then park (replaces today's 20 ms nudge) |
| Light appearance | read `NSApp.effectiveAppearance`; swap the token set (graphite face, brighter top light, dark outer hairline, softer shadows) |
| Menu bar glyph | `NSStatusItem` template image: a 13.8 × 8.8 rounded slab (1.2 pt stroke) holding four 1.2 pt bars. Listening: redraw the bars from the level every 120 ms. Transcribing: bars flat, `alphaValue = 0.45`. |
| Menu | a plain `NSMenu` with `appearance = NSAppearance(named: .darkAqua)`; the mic row is a submenu of `NSMenuItem`s with `.state = .on`. The graphite highlight in the prototype matches macOS with the Graphite accent; other accents highlight in the system colour. |

## What to look at

1. **Press a key.** Each key is a machined keycap that sinks 1 px. Click Copy and watch the glyph become a green-white check without the key changing size.
2. **Watch the trace for ten seconds.** Look at the crisp bars, the faint bloom on the tall ones, and the soft afterglow that lingers after a loud syllable. The newest bars run hottest at the right edge.
3. **Switch between states with 2–6.** Nothing moves. Only failed grows, and it grows upward. The keys under your cursor stay put.
4. **Hold Space.** The preview first reads out the microphone ("MACBOOK PRO MICROPHONE") until your first words land. Is that useful enough to keep?
5. **Failed.** The amber LED and amber Copy edge are the only warm colour in the whole system. Does it read calm?
6. **Toggle T.** Light mode is a graphite instrument designed for a bright desk, not an inverted one.
7. **Open History from the key.** The key lights up instead of sinking, the card sits exactly on the key's leading edge, and a cut row under the fade says there is more.

Review aids (URL): `?state=<id>&theme=<dark|light>`, `&hold=1` keeps delivered on screen, `&menu=1` opens the menu, `&copied=1` shows the Copied button, `&demo=keys` forces hover, pressed, copied and lifted-row states for inspection.
