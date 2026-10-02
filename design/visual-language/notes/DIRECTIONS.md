# MouthKeys visual language: the three directions

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

## Round 2 (2026-09-28): Signal, pushed toward a diagram grammar

Atin chose **Signal**. He wants it to carry the "diagram aesthetic" he uses in an earlier deck design: engineering-drawing lines, accented corners, crisp rules. The grammar we inherit from that deck is the **8-tick corner bracket** ("corners are the design"), **mono numerals and labels**, thin rules, and status carried by solid colour and words, never blinking. We do not inherit its teal and gold; Signal keeps international orange on ink and paper.

What round 2 adds: orange corner ticks as the recording frame while listening, SF Mono for every number and label, a graticule under the trace, bracketed chips as an option beside the keyed ones, the history card as an engineering table with a title-block footer, a bracketed menu bar mark. Two live toggles in the prototype (Density: Quiet | Drawn; Chips: Keys | Brackets) so Atin can compare in place.

## Rounds 3 and 4, and the lock (2026-09-28)

Round 3: corners became a hover affordance, the LISTENING strip went, the timer moved to the trace row opposite the app icon, the mic name went bottom-centre. Round 4: square corners throughout, brackets outside the box. Atin: "Awesome. This looks great. Let's go." **Design locked.** See `../DESIGN.md`.

## Round 5 (2026-09-28): states from the newer branch

After the lock, the parent surface reported states the prototype missed. Added in the Signal grammar: Spoken Send in the trace row (SEND placard, orange drain bar, countdown in the timer; no fifth chip), a Sent outcome, one recovery-card family (timed out, recognition back, mic off, and three delivery-failure reasons), truthful "Pasted into" / "Sent to" wording, and the app icon (ink tile, five white bars, one orange square; three bars at 32 pt and below). Atin's calls: Spoken Send in the trace row ("Row, sounds good"), no preference on Pasted wording, recognition-back as a light notice row ("sure, great"), icon A unchallenged.

## Decisions so far

- Anatomy stays; the language changes. (Atin, round 1)
- Chips stay but are open to play. (Atin, round 1)
- Accent is not derived from the icon; the icon will follow the chosen language. (Atin, round 1)
- Direction: **Signal**. (Atin, 2026-09-28)
- Diagram grammar from the earlier deck design, colours not inherited. (Atin, 2026-09-28)
- Assumption, unconfirmed: dark is the default; the light variant follows the system appearance.
- Assumption, unconfirmed: the delivered line and the mic label row stay (Atin picked Signal with both present).
