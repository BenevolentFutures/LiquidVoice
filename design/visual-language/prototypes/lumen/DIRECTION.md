# Lumen

## Thesis

The overlay is a lens made of the operating system's own material: Liquid Glass on macOS 26, a vibrancy effect view on macOS 15. Its edge catches specular light, and the voice inside it is liquid: a filled, flowing envelope that runs from violet (oldest) to cyan-white (newest) and blooms into the glass. Lumen takes the product's name literally and stays completely native. The refraction and the liquid trace are what stop it from being a frosted card.

Open `index.html`. Keys: `1`–`6` pick a state, `T` toggles appearance, hold `Space` to talk, `P` plays a dictation. Review-only URL parameters: `hold=1` keeps Delivered on screen; `menu=1` (plus `sub=1`) opens the status menu on load. On first load into Listening or History, the page opens 10 s into a dictation so the view is representative. Every later dictation starts at 0:00.

## Colour tokens

| Token | Dark | Light | Use |
|---|---|---|---|
| `g-fill` | white 0.09 | white 0.68 | glass body (pill, beads) |
| `g-fill-hover` | white 0.18 | white 0.90 | bead hover |
| `g-fill-press` | white 0.26 | white 1.00 | bead pressed |
| `g-sheet` | white 0.09 | white 0.78 | history card |
| `g-menu` | rgb(34,36,46) 0.46 | rgb(246,247,251) 0.78 | status menu |
| `g-spec` | white 0.10 → 0 | white 0.40 → 0 | broad specular, top third |
| `g-e0` / `g-e4` | white 0.55 / 0.35 | white 1.0 / 0.90 | refractive edge, top-left / bottom-right |
| `g-e2` | white 0.03 | ink rgb(20,30,60) 0.07 | edge along the other diagonal |
| `g-rim-a` / `g-rim-b` | white 0.10 / 0.06 | white 0.55 / 0.35 | inner rim (lens thickness) |
| `g-inner` | black 0.25 | black 0.10 | 1 px bottom inner shadow |
| `g-rim` (outer) | none | 0.5 px rgb(10,20,50) 0.14 | light glass keeps its outline |
| `g-shadow` | 0 12 32 black 0.35 | 0 12 32 rgb(10,20,50) 0.18 | drop shadow |
| `g-dot` | white 0.45 | white 0.95 | bead specular dot |
| `tx` | white 0.95 | #0B0C10 0.90 | preview, headlines |
| `tx-2` | white 0.80 | #0B0C10 0.76 | failed-card transcript |
| `tx-meta` | white 0.60 | black 0.55 | timer, mic, counts, hints |
| `glyph` | white 0.85 | black 0.75 | bead icons |
| `hairline` | white 0.10 | black 0.08 | history separators |
| `accent` (UI) | #7FD4FF | #1C8EEA | delivered check before it flushes, menu highlight, focus |
| trace spectrum | #8E7CFF → #7FD4FF (62%) → #9FEFFF | #6F63F0 → #3AA6FF (50%) → #2AD3E8 | oldest → newest |
| sweep | rgb(226,251,255) 0.9 | rgb(12,150,235) 0.95 | transcribing highlight |
| ok | #8FE8B8 (ink and glow) | ink #15935B, line #2FBF7E, glow #8FE8B8 | delivered, copied |
| warn | #FFC46B ink, fill 0.14 | ink #9A5A00, fill #FFC46B 0.30 | failed glyph, Copy button |

There is no red anywhere. Failure is amber and calm.

## Type scale (SF Pro Text, system font)

| Role | Size / weight / line | Notes |
|---|---|---|
| Live preview | 13.5 / 500 / 18 | 3 lines reserved, head-truncated with a leading ellipsis |
| Delivered line | 13.5 / 600 ("Delivered to c11") + 13.5 / 500 meta colour | tabular |
| Failed headline | 13.5 / 600 | |
| Failed transcript | 13 / 400 / 17.5 | 3-line clamp |
| History transcript | 13 / 400 / 18 | 4-line clamp |
| Meta (timer, mic, counts, history meta) | 11.5 / 500 / 14 | `monospacedDigit()` everywhere |
| Labels (card header, day sections) | 10.5 / 600, uppercase, +0.04 em | used three times, no more |
| Menu rows | 13 / 400, 24 pt rows | |

## Geometry and radii

- Overlay row: bead rail 30, gap 6, pill 340, gap 6, bead rail 30 = 412 wide, bottom 50 above the screen edge.
- Pill: 340 × 150, radius 20, padding 22 h × 12 v. The height is reserved for meta row (14) + 6 + three preview lines (54) + 8 + trace row (44), so it never changes between Listening, Transcribing and Delivered.
- Failed: the pill grows **upward** to 195. The rails are bottom-anchored, so beads, trace and app icon stay put. This was verified by measuring bead and trace rects across all six states: zero movement.
- Trace row: target app icon 20 (radius 4.6) at the left of the text column, 16 gap, trace 260 × 44 flush right.
- Beads: 30 × 30, radius 11, continuous corners.
- Copy button (failed): 88 × 28, radius 10, fixed width for both labels. Dismiss: text button, 28 tall.
- History card: 480 wide, max 480 tall, radius 16. Left edge on the History bead's leading edge, bottom 6 above the bead (above the pill top when the pill is tall).
- Menu: 292 wide, radius 12, padding 5, row radius 7. The submenu is 236 wide.

## Materials

| Surface | macOS 26 | macOS 15 |
|---|---|---|
| Pill | `glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))` | `NSVisualEffectView` `.hudWindow` (dark) / `.popover` (light), `.behindWindow`, `.active`, clipped to the same path |
| Beads | `Button { Image(systemName:) }.buttonStyle(.glass)` in a `GlassEffectContainer` | 30 pt effect views + edge layer |
| History card | child `NSPanel` hosting `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))` | effect view `.popover` / `.hudWindow` |
| Copy button | `.buttonStyle(.glass)` + `.tint(#FFC46B)` | layer background amber 0.14 + edge layer |
| Menu | `NSMenu` (system glass; only the row text is ours) | `NSMenu` |

The web prototype uses `backdrop-filter: blur(28px) saturate(180%)` (card: blur 40) to stand in for these materials. The blur radius maps to the material, not to a number.

## Motion

| Event | Duration | Curve | What moves |
|---|---|---|---|
| Entrance | 110 ms | ease-out (0.2, 0.7, 0.3, 1) | glass surfaces fade in |
| Edge lights up | 120 ms, +20 ms delay | ease-out | refractive edge opacity 0 → 1 |
| Dismiss | 150 ms | ease-in (0.4, 0, 1, 1) | fade + scale 0.985 + 6 px drop |
| Bead hover | 120 ms | ease-out | fill brightens |
| Bead press | 90 ms | ease-out | scale 0.94, fill brightens more |
| Bead release | 140 ms | ease-out | back to rest |
| Copy feedback (bead) | 900 ms hold | bloom keyframes | glyph swaps to a green check, radial bloom peaks at 18% |
| Copy feedback (failed button) | 1.4 s hold | 120 ms crossfade | "Copy" ↔ check "Copied", same width |
| Face swap (preview ↔ delivered ↔ failed) | 120 ms | ease-in-out | crossfade in reserved space |
| Failed card grows | 140 ms | ease-out | pill height 150 → 195, upward |
| Trace sample | every 85 ms | linear scroll | continuous leftward flow (phase = time since last sample) |
| Write head | 60 ms settle | linear-ish | head height eases to the incoming sample |
| Flatten on stop | 180 ms | ease-out | envelope → 2 px line, live colour drains |
| Transcribing sweep | 1.05 s, infinite | linear | highlight crosses the line |
| Delivered flush | 240 ms | ease-out | line and check turn to the green glow |
| Delivered hold | 1.2 s | — | then `setState("idle")` |
| History card | 110 ms in / 120 ms out | ease-out / ease-in | fade + 4 px rise |
| Menu | 60 ms in / 90 ms out | — | fade |
| Menu bar glyph | 30 fps while listening | two time constants | lobes breathe out of step; 45% opacity while transcribing |

There are no springs. With Reduce Motion, entrance and dismiss are instant, the bead press does not scale, the sweep becomes a slow 1.6 s brightness breath, and the menu bar glyph stays still. The trace keeps scrolling because it is live data.

## The trace

- **Signal path unchanged.** 65 samples, `adjusted = clamp((level − 0.4)/0.6)`, `^1.15`, grain `0.6 + 0.25·cos(1.7n) + 0.15·cos(4.3n)`, heights 2…40, age fade `0.35 + 0.65·t^1.4`. One sample per 85 ms (the real 4096-frame tap); within a sample the peak level is held.
- **Liquid body.** A monotone-cubic (Fritsch–Carlson, no overshoot) path through a max-biased smoothing of the samples (60% local max of three, 40% 1-2-1 average), mirrored about the midline. The write head has a rounded cap. The fill is a horizontal spectral gradient carrying the age fade, masked by a vertical gradient (1.0 at the midline, 0.18 at the extremes). The oldest 12 px feather out.
- **Bloom.** A blurred copy at 0.5 behind the body.
- **Meniscus.** A 0.75 px stroke of the same path at 0.55, where light catches the liquid's surface.
- **Grain.** 1 px lines at the 65 sample positions, raw heights, accent 0.35. In dark they are additive, so they brighten the body into fine striations. In light they are a deeper ink.
- **Write head.** A small specular point whose strength follows the level.
- **Silence.** The body collapses to a 2 px luminous line. The grain dots keep flowing across it, so silence never reads as a hang.

## Native mapping, effect by effect

| Effect | Native |
|---|---|
| Refractive edge | `CAGradientLayer(.axial)` start (0,0) end (1,1), stops at 0 / 18 / 40 / 60 / 82 / 100%, masked by a `CAShapeLayer` stroking the continuous rounded rect, lineWidth 1. In unit space the isolines run parallel to the TR–BL diagonal, identical to CSS `to bottom right`. On macOS 26 it sits at 0.8 over the system glass rim. |
| Inner rim | the same gradient masked by a 6 pt stroke of the 1 pt-inset path, `layer.filters = [CIGaussianBlur r 2]`. Omitted on macOS 26, where glass renders its own lensing band. |
| Top-third specular | `CAGradientLayer` white 0.10 → 0 over the top 34% |
| Bottom inner shadow | 1 pt line layer, black 0.25, clipped to the shape |
| Drop shadow | layer shadow 0 / −12 / radius 16 / 0.35 (window shadow off) |
| Bead specular dot | radial `CAGradientLayer` white 0.45 → 0, radius 12, centre (9, 8) |
| Bead press | `ButtonStyle` reading `configuration.isPressed` → `scaleEffect(0.94)`, `.easeOut(duration: 0.09)` |
| Copy check + bloom | `symbolEffect(.replace)` doc.on.doc → checkmark; symbol shadow ok-green r4; radial gradient layer opacity keyframes |
| Trace body | `CAShapeLayer` path (rebuilt each `TimelineView(.animation)` tick) as the mask of a horizontal `CAGradientLayer`, inside a container masked by a vertical `CAGradientLayer` |
| Bloom | the body layer's own shadow: colour = accent, radius 6, opacity 0.5, offset 0, `shadowPath` = body path |
| Meniscus, grain | stroked `CAShapeLayer`s with gradient masks; dark grain uses `compositingFilter = "plusL"` |
| Sweep | `CAGradientLayer` `locations` animation, 1.05 s linear, repeat forever, masked to the line |
| Delivered flush | colour crossfade of the line's gradient layer to #8FE8B8, 240 ms, shadow radius up to 8 |
| Head truncation | `Text(tail).lineLimit(3).truncationMode(.head)` in a fixed 54 pt frame, bottom-aligned |
| History scroll edge | `.scrollEdgeEffectStyle(.soft, for: .bottom)` on 26; a gradient mask on the clip view on 15 |
| Menu bar glyph | template `NSImage` from the path; while listening, re-rendered at 30 fps from the smoothed level (or a `CAShapeLayer` in the status button) |
| Target app icon | `NSWorkspace.shared.icon(forFile:)`, 20 pt, radius 5 |

SF Symbols: `clock.arrow.circlepath` (History), `doc.on.doc` (Copy), `xmark` (Cancel), `arrow.clockwise` (Reprocess), `checkmark`, `exclamationmark.circle` (failed), `mic` (meta row), `chevron.right` (menu).

## What to look at

1. **The trace up close** (Listening, then zoom in). The liquid should read as light: droplets that swell with each syllable, a meniscus, grain inside, violet at the tail to cyan-white at the write head. In silence it is a luminous line that keeps flowing.
2. **The edge.** Top-left and bottom-right catch light and the other diagonal goes dark, on the pill, the beads and the card. Compare dark and light.
3. **Stop → Delivered** (press `P`). The body drains to a line, one sweep crosses it, then it flushes green with "Delivered to c11 · N words · 0:0N". Nothing else moves.
4. **Failed → Copy.** The pill grows upward and the beads stay under your cursor. Copy becomes "Copied" in the same 88 pt.
5. **Beads.** Hover, press and hold (they compress), then copy (a green check blooms for 900 ms).
6. **Light over your dark terminal.** The glass goes grey-milky over c11 and bright over the wallpaper. That is what the real material does. Judge whether 0.68 is opaque enough for you.
7. **Menu bar mark.** The old twin peaks become one liquid line with two lobes. It breathes while you talk and dims while transcribing.
