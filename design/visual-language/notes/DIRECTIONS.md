# Liquid Voice visual language: the three directions

Round 1, 2026-09-27. Same anatomy in all three (four corner chips on rails, wide fine scrolling trace, target-app icon in the pill, history card, drag with memory). What differs is the aesthetic thesis: what the overlay is *made of*.

| | Obsidian | Lumen | Signal |
|---|---|---|---|
| Thesis | **Depth.** A precision instrument milled from black glass. Light lives on edges. | **Light.** A lens of the OS's own material: Liquid Glass, refraction, a liquid trace. | **Flatness.** A printed instrument panel. No gradients, no blur, no glow. |
| Reference feel | Teenage Engineering, Nagra, oscilloscope phosphor | macOS 26 Liquid Glass, Control Center, a drop of water | Braun, Swiss type, aviation placards |
| Pill | Near-black face, 1 px edge light, deep shadow, faint grain | Translucent glass, specular edge, broad top highlight | Solid #111214, 1 px rule, hard offset shadow |
| Chips | Machined keycaps that sink when pressed | Glass beads that compress | Geometric keys that invert |
| Trace | Phosphor bars with bloom and afterglow | Filled liquid envelope with fine grain lines | Square-ended ink bars, four opacity steps, orange write head |
| Accent | Warm amber, sparingly; white recording | Spectral violet to cyan-white along the trace | International orange, the only colour |
| Light mode | Polished graphite instrument on a light desk | Light glass, dark text, deeper accent | Print on paper: white, black, orange |
| Native mapping | hudWindow material + edge-light layers | `glassEffect` on 26, vibrancy on 15 | Plain layers, no material |

## What to look at in each

1. **Listening**: does the trace read as *your* trace, only better? Does the pill feel solid?
2. **Transcribing**: the sweep alone carries the state. Is it enough?
3. **Delivered** (new): the one-line confirmation. Too much, too little?
4. **Failed → Copy** (new): the recovery card. Calm and legible, or alarming?
5. **History**: the card above the left rail. Does it read as a separate object?
6. **Chips**: hover and press each one. Press Copy.
7. **Light**: press T. Which light variant would you actually run on a light desktop?
8. **Menu bar**: click the item at the top right.

Keyboard in every prototype: digits 1–6 pick a state, hold Space to talk, P plays a full dictation, T toggles appearance. Drag the overlay; double-click to reset.

## Decisions so far

- Anatomy stays; the language changes. (Atin, round 1)
- Chips stay but are open to play. (Atin, round 1)
- Accent is not derived from the icon; the icon will follow the chosen language. (Atin, round 1)
- Assumption, unconfirmed: dark is the default for all three; each gets a designed light variant.
