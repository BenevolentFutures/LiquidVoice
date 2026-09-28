# Shared contract for the three direction prototypes

Every direction prototype is one file, `prototypes/<direction>/index.html`, with its CSS and JS inline. It loads `../shared/stage.css`, `../shared/mock-data.js` and `../shared/stage.js`, calls `LVStage.init(...)`, and renders its overlay into `LVStage.host()` and its menu bar item into `LVStage.menubarSlot()`. The stage supplies the desktop, the c11 window, the state switcher, the light/dark toggle, keyboard shortcuts, the simulated microphone level and the PROTOTYPE badge. The direction supplies everything the user would actually see from Liquid Voice.

## What Liquid Voice is

A macOS dictation app. Straight voice to text, nothing else. The owner uses it hundreds of times a day to dictate prompts into coding agents running in c11, a terminal multiplexer. The overlay is the surface he sees more than any other. It has to read at a glance, never shift under the cursor, and feel solid.

## Anatomy to preserve (from the current app, `notes/overlay-anatomy.md`)

The overlay is one horizontal row, bottom-centre of the screen, 50 px above the screen bottom:

```
[ History ]                                              [ Cancel  ]
[ (spacer)]   [ app icon | ~~~~~ voice trace ~~~~~ ]     [ (spacer)]
[ Copy    ]                                              [ Reprocess]
```

- **Pill**: 340 px wide at the default size, corner radius 18, padding 18 h × 12 v. It holds an optional live-transcript preview (up to 3 lines, 13 px medium) above a **voice trace** of 260 × 44.
- **Voice trace**: 65 bars, 2 px wide, 2 px gap, min height 2, max 40, mirrored about the midline (each bar is a capsule centred vertically). New samples enter at the right; history flows left. Older bars fade: opacity `0.35 + 0.65·t^1.4` with t = 0 oldest, 1 newest. Each new sample's height is multiplied by a grain factor `0.6 + 0.25·cos(1.7n) + 0.15·cos(4.3n)` (n = sample index) so neighbours differ visibly without looking periodic. The signal is `level^1.15` after a noise threshold of 0.4 (`adjusted = clamp((level − 0.4)/0.6)`). **Keep scrolling during silence** with tiny bars (the owner asked for this). Keep the trace wide, fine, and contrasty. Redesign its rendering (colour, glow, texture, line vs bars) freely within the direction's aesthetic, but keep it a wide scrolling trace.
- **App icon**: the *target* app's icon (the app that will receive the text, e.g. c11, Mail), 20 px, inside the pill at the left end of the trace row, centred on the trace midline. It is a state indicator, not a button. During model loading a mini spinner sits above it.
- **Rails**: a column on each side, 6 px from the pill. Left: History (top), Copy (bottom). Right: Cancel (top), Reprocess (bottom). A hidden middle slot keeps both rails the same height and lets the chips sit at the top and bottom corners of the pill. Chips are icon-only with tooltips. Chip icons today: `clock.arrow.circlepath`, `doc.on.doc`, `xmark`, `arrow.clockwise`. Use inline SVG stand-ins for SF Symbols (draw them simply and cleanly; note the SF Symbol name in a comment so the native build uses the real one).
- **Whole-surface drag with position memory, double-click resets**: use `LVStage.makeDraggable(node, "<direction>")` on the overlay root.
- **History card**: opens above the History chip, anchored to the chip's leading edge, 480 wide, up to 480 tall, 12 most recent entries newest first, each row is the transcript (up to ~4 lines here) with a meta line (time, duration, words, target app). Click a row to insert. Closes on outside click or re-tap.

The chips are the owner's; he wants to keep them but **play with them**: shape, edge, material, hover and pressed feedback, and how they relate to the pill are all open. Chips must have a real pressed state and Copy must give visible feedback.

## States to design (all six, switchable from the stage)

State ids and labels, in this order: `idle` "Idle", `listening` "Listening", `transcribing` "Transcribing", `delivered` "Delivered", `failed` "Failed → Copy", `history` "History".

1. **idle**: the overlay is hidden. Only the menu bar item shows. (Optionally a resting dot or nothing; the current app shows nothing.)
2. **listening**: trace live from `LVStage.onTick(level)`. Live preview text above the trace (use `LV_MOCK.livePreview` and reveal words over time, head-truncated so the newest words stay visible). A small elapsed timer in tabular numerals is welcome. Mic name may appear.
3. **transcribing**: recording stopped, the trace flattens to a line and a highlight sweeps across it every ~1 s. No words that say "Transcribing" (the owner filtered those out; the sweep carries the state). Nothing moves except the sweep.
4. **delivered** (new, does not exist today): a brief confirmation that the text landed in the target app: a check, the target app, word count and duration, e.g. "Delivered to c11 · 118 words · 0:41". Shown for ~1.2 s, then the overlay dismisses. Call `LVStage.insertText(LV_MOCK.history[0].text.slice(0, 90) + "…")` on entering delivered so the c11 window shows the text arriving; call `LVStage.clearInserted()` on idle.
5. **failed** (new): the paste could not be delivered (target refused focus, or the text is still on the clipboard). The overlay stays and shows a **Copy card**: a headline like "Couldn't paste into c11", the transcript preview (3–4 lines), a prominent Copy button and a Dismiss. Copy must show feedback (check + "Copied", reserved width, no jump). This is the recovery path, so it must be calm and legible, not alarming.
6. **history**: the history card open above the left rail, with the listening state underneath (the card can open while listening or idle).

## Rules that bind every direction

- **Nothing jumps.** The pill's height is reserved for the tallest content it can show in that state family; the rails stay put when the preview grows; chips are fixed-size; the delivered and failed rows appear in reserved space or by swapping content of equal height. Use `font-variant-numeric: tabular-nums` on every number.
- **Large, high-contrast text.** Body 13 px minimum inside the overlay, transcript preview 13–14 px, meta 11–12 px at ≥ 55% contrast on its surface. Chip glyphs 12–13 px stroke or filled with clear weight.
- **Light and dark.** Read `LVStage.theme` and `LVStage.onTheme`. The root has `data-appearance="dark|light"`. Design both. Dark is the default; the light variant is a real design, not an inversion.
- **Native-buildable.** Every choice must be reproducible in SwiftUI/AppKit on macOS 15 and 26: NSVisualEffectView materials (hudWindow, popover, sidebar, underWindowBackground) and vibrancy, macOS 26 Liquid Glass (`glassEffect`), SF Pro / SF Pro Rounded / SF Mono / New York, CoreAnimation gradients, shadows, layer masks, `TimelineView` animations. No web-only tricks that have no native equivalent (e.g. arbitrary SVG filters as the load-bearing look, backdrop-filter effects beyond blur/saturate). Note in comments how each effect maps to native.
- **Motion**: define durations and easings and use them consistently. Entrance can be instant (current app) or a very short reveal (≤ 120 ms). Dismiss ≤ 160 ms. No bouncy springs on the overlay. Respect `prefers-reduced-motion`.
- **Menu bar**: render a menu bar item (a 16–18 px template glyph, mono, that reads as Liquid Voice; the current app icon is a twin-peak five-bar waveform but the mark is open to redesign in the direction's language) with a state (idle, listening with a subtle live indication, transcribing). Clicking it opens a menu: "Start Dictation ⌥Space", a mic picker submenu-style row showing the current mic, "History…", "Settings…", a separator, "Quit Liquid Voice". Style the menu in the direction's language but keep it recognisably a macOS menu (it will be an NSMenu; only the menu bar glyph and what the row text says are really ours).
- **Realistic data**: use `LV_MOCK` from `mock-data.js` for everything. Long transcripts, ugly durations, real mic names.
- **PROTOTYPE badge**: the stage renders it. Never remove it.
- **One file per direction**, no build step, no external fonts or CDNs. System fonts only (`-apple-system, "SF Pro Text"…`).
- Every prototype must load with zero console errors in Chrome and Safari, and must look right at 1440 × 900 and 1728 × 1117 viewports.

## Stage API (see `stage.js`)

```js
LVStage.init({
  name: "Obsidian",
  states: [{id:"idle",label:"Idle"}, {id:"listening",label:"Listening"}, {id:"transcribing",label:"Transcribing"},
           {id:"delivered",label:"Delivered"}, {id:"failed",label:"Failed → Copy"}, {id:"history",label:"History"}],
  defaultState: "listening",
  sequence: [["listening", 4200], ["transcribing", 1100], ["delivered", 1300], ["idle", 0]],
  onState(next, prev) { /* render */ },
  onTheme(theme) { /* "dark" | "light" */ },
  onTick(level, t) { /* 0..1 mic level, 60 fps while listening */ },
});
LVStage.host()            // the bottom-centre overlay host element (flex, items at the bottom)
LVStage.menubarSlot()     // the span in the menu bar status area for the LV item
LVStage.makeDraggable(node, key)
LVStage.insertText(text) / LVStage.clearInserted()
LVStage.setState(id)      // e.g. after "delivered" timing out, call setState("idle")
LVStage.theme, LVStage.state, LVStage.level
```

`?state=<id>&theme=<dark|light>` in the URL selects the initial state and appearance (used for screenshots).

## Deliverables per direction

- `prototypes/<direction>/index.html`
- `prototypes/<direction>/DIRECTION.md`: the aesthetic thesis in three sentences, the colour tokens (light and dark), type scale, radii, materials, motion table, the native mapping for every effect, and a short "what to look at" list for the owner.
