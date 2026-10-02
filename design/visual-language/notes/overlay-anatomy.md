# MouthKeys recording overlay: anatomy

Read-only survey of the bottom recording overlay as it stands on `design/visual-language` at `68afebce` (2026-09-27). Every number comes from the code. Values marked **(derived)** are arithmetic on those constants. Values marked **(est.)** depend on SF Symbol glyph metrics that were not measured on screen.

**File aliases used in citations**

| Alias | Path |
|---|---|
| `BOV` | `Sources/Fluid/Views/BottomOverlayView.swift` (4076 lines) |
| `NCV` | `Sources/Fluid/Views/NotchContentViews.swift` (state, mode colours, shimmer) |
| `AVS` | `Sources/Fluid/UI/Visualization/AudioVisualizationShared.swift` |
| `CV` | `Sources/Fluid/ContentView.swift` |
| `MBM` | `Sources/Fluid/Services/MenuBarManager.swift` |
| `NOM` | `Sources/Fluid/Services/NotchOverlayManager.swift` |
| `SS` | `Sources/Fluid/Persistence/SettingsStore.swift` |
| `ASR` | `Sources/Fluid/Services/ASRService.swift` |

`AVS` (`AudioVisualizationConfig`, `AudioVisualizationData`) is **not used** by the bottom overlay. Only `CustomAnimations.swift` uses it. The overlay trace reads `NotchContentState.bottomOverlayAudioLevel` directly (`BOV:3961`).

---

## 0. The shape in one paragraph

A borderless, non-activating floating `NSPanel` (`BOV:378-413`) holds one SwiftUI `HStack(spacing: 6)`. From left to right it contains a **leading rail**, the **black pill**, and a **trailing rail** (`BOV:3359-3364`). The pill is pure black (`Color.black`, `BOV:3655`). It has no material, vibrancy or blur anywhere in the file. It holds an optional live-transcript area on top and a wide **scrolling voice trace** below. The target app's icon sits inside the pill at the left end of the trace row (`BOV:3728-3732`). Each rail is a three-slot column with a chip at the top, an invisible spacer in the middle and a chip at the bottom. History (top) and Copy (bottom) sit on the left. Cancel (top) and Reprocess (bottom) sit on the right (`BOV:3406-3412`, `BOV:3477-3483`). The four chips frame the pill "symmetrically" (commit `abc7e477`).

---

## 1. States

| # | State | Trigger | What is shown | Motion |
|---|---|---|---|---|
| S0 | **Parked (hidden)** | Launch `prepare()` (`BOV:93-104`, called from `MBM:90-100` when position is `.bottom`). Also the end of every hide (`BOV:251`). | Nothing. The panel stays alive and ordered front, but it is moved past every display to `desktop.maxX + w + 1024, desktop.maxY + h + 1024` (`BOV:572-585`). Accessibility is disabled while parked (`BOV:574-575`). | None. The panel is parked so the WindowServer surface stays warm (`BOV:91-92`). |
| S1 | **Listening / recording** | Hotkey leads to `NOM.showBottomOverlay` (`NOM:201-212`) and then `BottomOverlayWindowController.show` (`BOV:106-161`). The screen is the one under the mouse pointer (`OverlayScreenResolver`, `BOV:141`). | Pill, trace scrolling right to left, and the tinted mode colour. The target-app icon appears in the pill. The live transcript tail appears above the trace when streaming preview is on and size ≠ pill (`BOV:2707-2710`). The pill-size border light rotates. | **No entrance animation.** The first frame is fully composed while offscreen, then moved in with `orderFrontRegardless` + `displayIfNeeded` + `CATransaction.flush()` (`BOV:126-151`). The comment says "Revealing the neutral shell first causes a visible flash that reads as the overlay appearing twice" (`BOV:126-128`). |
| S1a | **Model loading** | `!asr.isAsrReady && (isLoadingModel ‖ isDownloadingModel)` (`BOV:3493-3494`) | A `ProgressView().controlSize(.mini)` sits above the app icon in the corner (`BOV:3496-3499`). The old "Loading model…" text was retired (`50ececf4`). | System spinner. |
| S1b | **Mode tint** | `contentState.mode` (`BOV:2546-2548`) | The only mode signal is the trace colour: Dictate is white, Edit is blue, Command is red (`NCV:270-283`). The mode label was removed (`8626346a`). | Instant. |
| S2 | **Stop, plain dictation (no AI)** | `shouldHideOverlayOnStop` is true when the route is normal, the mode is not rewrite or command, no prompt test is active and AI is not configured (`CV:2078-2082`). | The overlay hides **at stop**, before transcription finishes (`CV:2091-2094`). No "transcribing" state is ever visible. | S6 dismiss. |
| S3 | **Release transition** | AI, edit or command stop: `beginReleaseTransition(duration: 0.28)` (`CV:2173-2175`, `BOV:286-308`, floor 0.12 s) | Audio unsubscribes and the level is forced to 0. The trace drops to a flat 2 pt line with the shimmer sweep (`BOV:3908-3910`, `4031-4033`). The preview is suppressed with animations disabled (`BOV:2763-2768`, `3734-3738`). Preview height is frozen so the pill does not jump (`BOV:3820-3834`). Resizes queue until the transition ends (`BOV:332-336`, `310-322`). | Bars flatten; the shimmer starts. |
| S4 | **Processing (transcribing / refining / thinking)** | `MBM.setProcessing(true)` (`MBM:339-361`, delay 0 ms). `CV` writes "Transcribing" and then "Refining" into the transcript (`CV:2101`, `CV:2238`). | These status words are **filtered out** (`BOV:2570-2587`, `2801-2806`). The `ShimmerText` label is commented out: "Temporarily hidden; the waveform sweep carries processing state" (`BOV:3528-3536`, `3612-3619`). You see a flat trace at 16 % mode colour (pill: white 32 %) with a white highlight sweeping left to right every 1.05 s. Non-status AI stream text, if written, shows as preview (`BOV:2808-2817`, `3525-3526`). | `setFlatProcessingBars`: `easeOut(0.18)` to min height (`BOV:4037-4044`). Linear, infinite sweep (§5). |
| S5 | **Delivered** | Typing is dispatched, then `hideOverlayAfterOutput`, then `finishProcessingAndHideOverlay`, then `hideAndWait` (`CV:2416-2428`, `MBM:401-413`) | **There is no delivered or pasted confirmation state.** The overlay just leaves. | S6. |
| S6 | **Dismiss** | `hide()` / `hideAndWait()` (`BOV:163-259`) | `isBottomOverlayDismissing` produces `scaleEffect(0.985)` and `offset(y: +8)` (downward). Opacity stays at `1.0` (`BOV:2844-2857`). | `.timingCurve(0.22, 0.0, 0.2, 1.0, duration: 0.02)` (`BOV:3751`). The controller sleeps `dismissalDuration = 0.02` s (`BOV:55`, `244`) and then parks. The result is a 20 ms nudge-and-vanish. The processing-end hide is scheduled 80 ms later (`MBM:57`, `391`). |
| S7 | **AI failure (retryable)** | AI post-processing throws. The raw text is still typed (`CV:2259-2279`). `showAIProcessingFailure()` (`CV:2346-2350`, `2860-2863`) plus `finishProcessingKeepingOverlayVisible` (`MBM:417-425`) | A row in the preview area shows "AI Enhancement failed" (white 0.9), then a ↻ "Try again" button and an ✕ "Dismiss" button (`BOV:3287-3314`). A system notification is also posted (`CV:2272-2276`). | Stays until Dismiss (which hides), Try again (which reprocesses) or the next recording lifecycle (`CV:2467-2470`). |
| S8 | **Warning (non-retryable)** | Edit mode invoked with the Fluid-1 provider (`CV:2430-2465`, commit `ce8f3b6e`) | The same row shows "Edit Mode cannot be used with Fluid-1" in **orange 0.9** with only ✕ (`BOV:3291-3306`) | Auto-clears and hides after **6 s** (`CV:2458-2463`). |
| S9 | **History browser open** | Tap the history chip (`BOV:3447-3459`) | A separate 480 pt card panel opens above the chip (§2.6). | No animation: `animationBehavior = .none`, plain `orderFrontRegardless` (`BOV:1499`, `1476`). It closes on an outside click (global and local mouse monitors, `BOV:425-470`), a chip re-tap, a row pick, any other chip tap, or overlay hide or show. |
| S10 | **Cancel** | Cancel chip or the cancel hotkey (default **Escape**, keyCode 53, `SS:2800`) leads to `handleCancelShortcut` (`CV:3260-3262`, `3487-3524`) | Recording stops without transcription, then `NOM.hide()`. | S6. |
| S11 | **Reprocess** | Reprocess chip, the reprocess hotkey, or ↻ in S7 leads to `reprocessLastDictation` (`CV:2550-2576`) and then `reprocessDictationText` (`CV:2775-2788`) | Processing state plus the text **"Reprocessing..."**. That string is *not* in the filtered status set (`BOV:2570-2579`), so it is the one processing state that shows words (white 0.9). If the overlay was hidden, `setProcessing(true)` re-shows it (`NOM:487-494`). | As in S4. |
| S12 | **Failed-to-deliver "Copy" card** | — | **Does not exist in this code.** Nothing in `Sources/` renders a delivery-failure card. The recovery paths are the Copy chip, the history browser's click-to-insert, and the `8ed75b9a` fix at the root cause (the modifier-flag leak and the c11 Reliable Paste path). | — |

**Pill-size caveat:** `showsPreview` is false for `.pill` (`BOV:2446`), so S7 and S8 render **nothing** in pill size.

---

## 2. Geometry

### 2.1 Layout constants per size (`BOV:2395-2532`)

The default size is **medium** (`SS:2127-2133`). Sizes are chosen in Settings with a picker (`SettingsView.swift:1385`).

| Constant | pill | small | **medium (default)** | large |
|---|---|---|---|---|
| hPadding / vPadding | 12 / 8 | 10 / 6 | 18 / 12 | 18 / 12 |
| Pill width (black) | `containerWidth` 100 | 200 | **340** | `overlayWidth` 600 (fixed canvas) |
| Corner radius | 23 | 14 | **18** | 24 |
| Trace frame (`visualizerWidth × waveformHeight`) | 46 × 30 | 150 × 20 | **260 × 44** | 420 × 48 |
| `waveformWidth` (preview math only) | 46 | 90 | 130 | 180 |
| Bars / width / gap | 15 / 1.5 / 1.5 | 43 / 1.5 / 2.0 | **65 / 2.0 / 2.0** | 93 / 2.0 / 2.5 |
| Drawn trace span **(derived)** | 43.5 | 148.5 | **258** | 416 |
| Bar height min / max | 2 / 28 | 2 / 18 | **2 / 40** | 2 / 44 |
| App icon | 18 | 16 | **20** | 26 |
| Transcript font (`transFontSize`) | 10 (unused) | 11 | **13** | 15 |
| `modeFontSize` (drives chip size) | 9 | 10 | 12 | 14 |
| `showsPreview` | no | yes | yes | yes |
| `showsTopControls` (**gates chip taps**, see §6) | **no** | **no** | yes | yes |
| Preview box | — | 1 line | ≤ 3 lines **(derived** `Int(54.6/16.25)`**)**, 304 wide | fixed 92 tall, scrolls |

`LayoutConstants` fields `overlayWidth` and `overlayHeight` apply only to large (`usesFixedCanvas`, `BOV:3740-3744`, `2712-2715`). The comment at `BOV:2478-2483` ("9 * 5 + 8 * 5.5 = 89pt") is **stale**. It predates the 65-bar trace.

### 2.2 Pill height (derived)

- Structure: `vPadding` + [preview area + `vPadding/2` gap] + `waveformHeight` + `vPadding` (`BOV:3513-3649`).
- **pill:** 8 + 30 + 8 = **46**, so the 23 radius makes a true capsule. The whole view is then padded **26 pt** on every side so the drop shadow is not clipped (`BOV:3746`).
- **small:** 6 + 19.75 (min preview) + 3 + 20 + 6 ≈ **55**. With preview off it is 32.
- **medium:** 12 + 28.25 (min preview = 16.25 line + 2 × 6 pad, `BOV:2725-2745`, `2797-2799`) + 6 + 44 + 12 ≈ **102** when idle. It grows to about 130 at three lines. With streaming preview off it is **68**.
- **large:** 12 + 92 + 6 + 48 + 12 = **170** of black, top-aligned inside a **600 × 288** canvas (`BOV:2521-2524`, `3740-3744`). This is derived and not screen-verified. The window bottom sits at the offset, so the black pill floats about 118 pt above it. The rails are centred on the 288 canvas, not on the 170 pill (`HStack(alignment: .center)`, `BOV:3360`).

### 2.3 Chips and rails

- **Chip** (`quickActionChip`, `BOV:3176-3208`; history chip `BOV:3424-3461`):
  - Icon font is `max(promptSelectorFontSize + 1, 10)`, where `promptSelectorFontSize = max(modeFontSize − 1, 9)` (`BOV:2675-2677`). That gives **10 / 10 / 12 / 14 pt** for pill / small / medium / large.
  - Padding is **9 h × 4 v** (`BOV:3190-3191`, `2687-2689`).
  - Corner radius is `max(cornerRadius × 0.42, 8)`, giving **9.66 / 8 / 8 / 10.08** (`BOV:2695-2697`).
  - Medium chip size **(est.)** ≈ 29–33 × 19–23 pt. The width varies by glyph (`clock.arrow.circlepath` is widest). Chips are centred in their column.
- **Rail:** `VStack(spacing: 6)` with three slots: chip, `railChipSpacer`, chip (`BOV:3406-3421`, `3477-3483`).
  - The spacer is a hidden `xmark` chip with identical padding. It keeps both rails equally tall so "nothing shifts".
  - Medium rail height **(est.)** ≈ 70–80 pt. The rail sits `6` pt from the pill on each side (`BOV:3360`).
  - Medium window width **(est.)** ≈ 30 + 6 + 340 + 6 + 30 ≈ **410–416 pt**. The window sizes itself to the SwiftUI `fittingSize` (`BOV:355-372`).
- **App icon:** `iconSize` square with corner radius `iconSize/4` (5 pt at medium) (`BOV:3500-3506`).
  - It overlays the pill's `.bottomLeading` corner with leading inset `pill ? 7 : hPadding × 0.6` (10.8 at medium).
  - Its bottom inset is `vPadding + (waveformHeight − iconSize)/2` (24 at medium), which puts its centre on the trace's horizontal midline (`BOV:3728-3732`).
  - The frame is reserved even with no icon (opacity 0, `BOV:3508-3509`).
- **Failure buttons:** 20 × 20 circles (`BOV:3277`).

### 2.4 Placement (`BOV:472-513`)

- **Default:** `x = screen.frame.midX − w/2`, which centres the whole window, rails included. `y = visibleFrame.minY + overlayBottomOffset`.
- **Offset:** defaults to **50** (`SS:2112`) and is clamped to 10…1000 (`SS:2118`). The Settings slider runs 20…500 and is labelled "N px" (`SettingsView.swift:1440-1444`).
- **Clamp:** `minY = visibleFrame.minY + 10` and `maxY = visibleFrame.maxY − h − 40`. x is clamped to the visible frame (`BOV:505-509`). Position changes are applied with `setFrameOrigin`, with no implicit animation (`BOV:511-512`).
- **Resize:** width and height changes over 0.5 pt resize from the current origin and then re-position, debounced **0.08 s** (`BOV:332-376`). Preview growth triggers a resize only when the estimated line-count bucket changes (`BOV:2770-2795`).

### 2.5 Drag, memory, reset (commit `af45c53b`)

- `DragGesture(minimumDistance: 3)` covers the whole HStack. It tracks `NSEvent.mouseLocation` deltas in screen space, not gesture translation, which would feed back as the window moves (`BOV:3373-3399`).
- The drag is free-form while held (`BOV:537-542`).
- On release, the window's **center-x and bottom-y are saved as fractions of the host screen frame**, each clamped to 0…1. They go to UserDefaults `OverlayDraggedPositionXFraction` / `…YFraction` (`BOV:529-530`, `546-559`), then `positionWindow` clamps into the visible frame.
- **Double-click anywhere** resets to the default anchor (`BOV:3367-3369`, `566-570`).
- Moving the Settings offset slider also clears the dragged position (`BOV:61-68`).
- Chip taps win over the drag because the gestures sit on the parent (`BOV:3365-3366`).
- **Hit testing, pill size only:** clicks within **26 pt** of the window edge (shadow radius 10 + |offset 4| + 12) pass through (`BOV:2326-2346`).

### 2.6 History card (`BOV:1393-1730`)

- **Panel:** its own borderless non-activating `NSPanel`, a child window `.above` the overlay (`BOV:1479-1537`).
- **Anchor:** the **leading edge** of the history chip, not its centre (`BOV:1546-1549`). y = chip top + gap. The gap is `max(0, vPadding × 0.05)`, so **0.6 pt** at medium (`BOV:2691-2693`). The panel is clamped 8 pt inside the visible frame (`BOV:1558-1574`).
- **Size:** **480 pt** wide exactly (`maxWidth: 480`, `BOV:3455`; floor 280, `BOV:1412`; `.frame(width:)`, `BOV:1711`). The list is capped at **480 pt tall** (`BOV:1603`, `1708`) and shows at most **12** entries, newest first (`BOV:1602`, `1611-1613`).
- **Card:** corner radius 10 (`BOV:1716-1720`).
- **Header:** padding h 10, top 8. A 1 pt hairline sits under it. Stack spacing is 6 (`BOV:1673-1690`).
- **List:** spacing 2, padding h 4, bottom 6 (`BOV:1699-1707`).
- **Row:** padding h 10 × v 8. Hover radius 7. Body text is capped at 10 lines. The meta line has 6 pt spacing (`BOV:1621-1670`).
- **Overlap (derived):** the medium pill (about 102 pt) is taller than the rail (about 75 pt), so the card's bottom edge covers roughly the top 13 pt of the pill's left end.

---

## 3. Colour and material

**There is no material, vibrancy, `NSVisualEffectView` or blur anywhere** in `BOV` (confirmed by grep). The overlay is appearance-independent: every colour is a literal. It has **no light-mode variant**. The pop-up menus force `.preferredColorScheme(.dark)` (`BOV:1721`, `1838`, `2064`, `2225`). `@Environment(\.theme)` is declared (`BOV:2367`) but never read.

| Element | Value | Cite |
|---|---|---|
| Pill fill | `Color.black` (#000000), "Solid pitch black" | `BOV:3652-3655` |
| Pill drop shadow | black 0.32, radius 10, y +4. **Pill size only**, none elsewhere. The window's own shadow is off. | `BOV:3656-3661`, `2328-2329`, `391` |
| Pill-size border ("glossy edge light") | `AngularGradient` white stops: 0.06 @0, **0.55 @0.13**, 0.10 @0.30, 0.03 @0.55, 0.22 @0.80, 0.06 @1.0. `strokeBorder` 1.2 pt. **Rotates 360° every 6.0 s** through `TimelineView(.animation(minimumInterval: 1/30))`. Static under Reduce Motion. | `BOV:3663-3707` |
| Other sizes' border | Vertical `LinearGradient` in white, top to bottom: small/medium **0.15 → 0.08**, large 0.10 → 0.05. Width 1 pt (large 0.8). The pill-case values 0.22 → 0.10 are defined but unused. | `BOV:2824-2842`, `3709-3721` |
| Mode colours (trace) | Dictate white 0.85. Edit / Write `rgb(0.4,0.6,1.0)` #6699FF. Rewrite `rgb(0.45,0.55,1.0)` #738CFF. Command `rgb(1.0,0.35,0.35)` #FF5959. | `NCV:270-283` |
| Trace fill | Non-pill: mode colour × **1.0**, or × **0.16** while processing or releasing. Pill: white **0.88**, or **0.32** while processing. | `BOV:3926-3931` |
| Trace age fade | Opacity `0.35 + 0.65·t^1.4`, where t runs 0 (oldest, left) to 1 (newest, right) | `BOV:4024-4028` |
| Trace glow | One composited shadow for the whole trace: mode colour at **0.5**, radius **4**. Off while processing or releasing, and off in pill size. | `BOV:3912-3924`, `4015-4021` |
| Processing sweep | `CAGradientLayer` white α 0 → **0.9** → 0, horizontal. Locations run `[-0.45,-0.15,0.15]` → `[0.85,1.15,1.45]`, linear, **1.05 s**, repeating forever. Masked to the bars, with a white 0.28 glow at radius 2.5. | `BOV:3953-3959`, `NCV:322-401` |
| Live transcript text | white 0.9 | `BOV:2821`, `3546`, `3593`, `3602` |
| Failure message | white 0.9 (retryable) or `Color.orange` 0.9 (warning) | `BOV:3291-3295` |
| Failure buttons | fill white 0.12 circle, glyph white 0.86 | `BOV:3276-3281` |
| Chip fill | Normal `Color.black`. Hover `rgb(0.13,0.13,0.16)` #212129. Disabled black 0.95. | `BOV:2859-2867` |
| Chip border | `strokeBorder` 1 pt, vertical gradient top/bottom: normal 0.14/0.08, **hover 0.36/0.22**, disabled 0.10/0.06 | `BOV:2869-2888` |
| Chip hover glow | white 0.16, radius 6, y +1 | `BOV:2871`, `2889` |
| Chip glyph | white **0.72**, disabled **0.32** | `BOV:3188`, `3429` |
| History card surface | `rgb(0.09,0.09,0.11)` #17171C, "a step lighter than the overlay's pure-black pill" | `BOV:1712-1715` |
| History card border | white **0.22**, 1 pt. The **system window shadow** is on (`hasShadow = true`); it is the only panel with one. | `BOV:1717-1720`, `1494-1496` |
| History hairline | white 0.08, 1 pt | `BOV:1686-1690` |
| History text | header 0.55, hint 0.35, entry 0.92, meta 0.45, empty-state 0.5 (all white) | `BOV:1641`, `1658`, `1677`, `1681`, `1695` |
| History row hover | fill white 0.20, stroke white 0.24 | `BOV:1621-1629` |
| Dormant menus | black, border white 0.12, radius 8. Selected 0.28 / 0.38, hover 0.20 / 0.24. | `BOV:1753-1779`, `1829-1836` |

---

## 4. Typography

Everything is `.system(size:weight:)`, which is SF Pro. There is **no `monospacedDigit`, monospaced, rounded or custom font** anywhere in `BOV` (grep count 0), so **no tabular numerals**. The history timestamps use `RelativeDateTimeFormatter` with `.abbreviated` style (`BOV:1605-1609`), for example "5 min. ago", in proportional digits.

| Text | Size / weight / colour | Cite |
|---|---|---|
| Live transcript | `transFontSize` (11 / **13** / 15) **medium**, white 0.9. Head truncation (`.head`) keeps the newest words visible. Small is 1 line. Medium has a line limit of `Int(previewMaxHeight / lineHeight)`. Large scrolls and auto-pins to the bottom. | `BOV:3337-3357`, `3540-3609` |
| Transcript tail length | The last **150** characters by default (range 50…800, step 50) | `NCV:115-145`, `SS:17-19` |
| Failure / warning message | `transFontSize` **semibold**, 1 line, tail truncation | `BOV:3289-3297` |
| Failure button glyph | `max(transFontSize − 1, 10)` semibold | `BOV:3275` |
| Chip glyphs | 10 / 10 / **12** / 14 semibold | `BOV:3187`, `3428` |
| History header "Recent Dictations" | 11 semibold | `BOV:1675-1677` |
| History hint "click to insert" | 10 medium | `BOV:1679-1681` |
| History entry | 12.5 regular, ≤ 10 lines | `BOV:1639-1645` |
| History meta line | 10.5 medium. `sparkles` glyph 9 semibold. | `BOV:1646-1658` |
| History empty state | 12.5 (default weight) | `BOV:1693-1695` |
| Dormant: mode menu row / shortcut badge | 15 semibold / 11 semibold in a capsule of white 0.08 | `BOV:1792-1802` |
| Dormant: actions menu row / glyph | 14 semibold / 11 semibold | `BOV:2153-2157` |

---

## 5. The voice trace (`BottomWaveformView`, `BOV:3873-4076`)

**Signal path**
1. `ASR.measureAudioLevel` computes the RMS of each captured buffer. There is a noise gate at RMS < 0.002. dB = `20·log10(rms)` is normalised as `(dB + 55)/55` and clamped to 0…1, so −55 dBFS maps to 0 and 0 dBFS to 1 (`ASR:5728-5746`).
2. Smoothing: `0.7·new + 0.3·mean(last 2)`. Anything below 0.04 returns exactly 0 (`ASR:5349-5353`, `5782-5800`).
3. The level is published on the main queue to `NotchContentState.bottomOverlayAudioLevel` (`ASR:1359-1363`, `BOV:155-160`).
4. **Cadence:** one sample per captured buffer. The AVAudioEngine tap requests `bufferSize: 4096` (`ASR:3430`), about 11–12 samples/s at 44.1–48 kHz. That gives the medium trace (65 samples) roughly **5–6 s of history** **(est., cadence not measured; the direct Core Audio path may differ)**.

**Sample to height** (`updateBars`, `BOV:4046-4071`)
- `adjusted = clamp((level − threshold)/(1 − threshold))`. The threshold is the user's **visualizer noise threshold**, default **0.4** (`SS:2015-2025`). It is re-read on any UserDefaults change (`BOV:3995-4001`). A level of 0.4 corresponds to about −33 dBFS.
- `amplified = adjusted^1.15`. This curve is "Slightly super-linear: keeps a steady background (music, hum) low while speech peaks stretch tall" (`BOV:4053-4055`). The previous exponent was 0.55 (`abc7e477`).
- **Grain:** `shimmer = 0.6 + 0.25·cos(1.7·n) + 0.15·cos(4.3·n)`, where n = `traceTick % 1024` and increments once per sample (`BOV:4057-4061`, `4073-4075`). "Grain" in the code means exactly this. Two incommensurate cosines scale each new sample by between **0.2 and 1.0**, so neighbours differ visibly without looking periodic. The previous version used `0.9 + 0.1·cos(1.7n)`, a ±10 % ripple (`abc7e477`).
- `height = clamp(min + (max − min)·amplified·shimmer, min, max)`.

**Scrolling**
- The heights array is a FIFO. Each tick `removeFirst()` + `append(new)` inside `withAnimation(.linear(duration: 0.06))` (`BOV:4067-4070`).
- `ForEach` is keyed by slot index (`BOV:4009`). Bars therefore do not translate. Each slot **morphs its height** to its right neighbour's value over 60 ms, which reads as flow to the left.
- The newest sample enters at the right edge (`BOV:4004-4006`). The buffer starts with 93 entries, and the newest `barCount` are read (`BOV:3878-3879`, `3937-3946`).

**Drawing**
- Bars are filled `RoundedRectangle` shapes with corner radius `barWidth/2`, i.e. capsules, in an `HStack(alignment: .center)` (`BOV:4007-4014`). They are **filled, not stroked**.
- Because the bars are vertically centred, each sample is **mirrored above and below the midline**. There is no left-right mirroring.
- The whole row is `.compositingGroup()` with one glow (`BOV:4015-4021`). Previously each bar carried its own shadow (`50ececf4`).

**Contrast treatment (commit `abc7e477`)**
- Tall speech against low background, via the 1.15 exponent.
- Per-sample height variance, via the grain.
- Right-weighted opacity (0.35 → 1.0).
- No dimming of the pill itself.

**States**
- **Processing or release:** every bar is forced to `minHeight` (2 pt) (`BOV:4030-4035`). On processing start the bars animate there with `easeOut(0.18)` (`BOV:4037-4044`). The fill dims to 16 % (pill 32 %), the glow turns off, and the §3 sweep turns the line into "a thin scanning line" (`50ececf4`).
- When processing ends, `updateBars(level: 0)` restarts the trace (`BOV:3967-3975`).
- **Silence (code-reading observation):** the trace advances only in `onChange(of: bottomOverlayAudioLevel)` (`BOV:3961-3966`). True silence emits a repeated exact 0, which is not a change, so the trace **stops scrolling during silence** and holds its last shape until sound returns.

---

## 6. Controls

| Control | Place | SF Symbol | Tooltip (enabled / disabled) | Enabled when | Action |
|---|---|---|---|---|---|
| **History** | Left rail, top | `clock.arrow.circlepath` | "Recent Dictations" / "No saved dictation history available" | History is non-empty. It stays usable while processing. | Toggles the history card (`BOV:3424-3461`) |
| **Copy** | Left rail, bottom | `doc.on.doc` | "Copy Last Transcription" / "No saved dictation history available" | History is non-empty and not processing (`BOV:3166-3170`) | Copies the latest entry to the pasteboard. There is **no on-screen confirmation** (`BOV:3210-3218`, `CV:2578-2586`). |
| **Cancel** | Right rail, top | `xmark` | "Cancel Dictation" | **Always** (`disabled: false`) | Same path as the cancel hotkey (default Esc) (`BOV:3230-3241`) |
| **Reprocess** | Right rail, bottom | `arrow.clockwise` | "Reprocess Last Dictation" / "No saved dictation history available" | History is non-empty and not processing | Reprocesses the pending failed text, else the latest raw entry (`BOV:3220-3228`, `CV:2550-2576`). It has a global hotkey that is **unbound by default** (`0e2948ac`). |
| **Target app icon** | Inside the pill, left of the trace | App icon (`NSImage`) | "Dictation target app" | — | **No chip chrome and no action.** It "reports state rather than accepting a click" (`BOV:3485-3511`). Source order: `targetAppIcon`, then `ActiveAppMonitor` icon, then the last known icon (`BOV:2558-2560`). |
| Try again | Failure row | `arrow.clockwise` | "Try again" | Retryable failures only | Clears the failure and reprocesses (`BOV:3301-3306`) |
| Dismiss | Failure row | `xmark` | "Dismiss" | Always | Clears the failure and hides (`BOV:3308-3311`) |
| History row | Card | (`sparkles` = AI-processed marker) | "Insert this dictation into the focused app" | — | Pastes that entry, re-activates the recording target PID after 0.05 s, and closes the card (`BOV:1631-1670`, `1724-1729`) |
| Whole surface | — | — | — | While presented | Drag moves the overlay; double-click resets it (§2.5) |

**Interaction states**
- **Hover** flips instantly, with no animation. The fill lifts to #212129, the border brightens to 0.36/0.22 and a white 0.16 glow appears (`BOV:2859-2890`). Disabled chips suppress hover (`BOV:3196-3198`).
- **Pressed:** there is no pressed state. Chips use `onTapGesture`, not `Button` (`BOV:3199`), and history rows use `.buttonStyle(.plain)`.
- **Disabled** chips dim rather than disappear, so "the controls beside them never shift position" (`0e2948ac`).
- Every chip tap first closes any open pop-up (`BOV:3200-3205`).

**Gate that breaks two sizes (finding)**
- Chip taps are guarded by `layout.showsTopControls` (`BOV:3200`, `3448`). That flag survives from the removed top row and is **false for pill and small** (`BOV:2445`, `2470`).
- In those sizes all four chips render and light up on hover, but **taps do nothing**.
- In pill size the rails also fall mostly inside the 26 pt click-through inset (`BOV:2335-2346`).

**Keyboard.** The panel is `.nonactivatingPanel` and never takes focus (`BOV:381`). Keyboard control is global:
- Cancel is **Escape** by default (`SS:2793-2801`).
- Reprocess Last Dictation is bindable (off by default).
- Paste Last Transcription is bindable.
- Each mode has its own hotkey. The mode menu is gone, so switching modes is hotkey-only (`8626346a`).

**Dormant controls** are still compiled but unreachable since `8626346a`:
- mode selector ("Mode:" + label + `chevron.up`)
- "AI Prompt:" selector with an "App" badge
- "Actions" menu
- `gearshape` settings chip
- their three pop-up menus (`BOV:588-1391`, `1732-2230`, `2985-3164`, `3243-3270`)

---

## 7. Text copy (every user-visible string)

**Visible in the live overlay**
- Live transcript tail (user speech)
- "Reprocessing..." (`CV:2787`)
- "AI Enhancement failed" (`NCV:26`, `NCV:102`)
- "Edit Mode cannot be used with Fluid-1" (`CV:2453`)

**Tooltips**
- "Recent Dictations"
- "No saved dictation history available"
- "Copy Last Transcription"
- "Reprocess Last Dictation"
- "Cancel Dictation"
- "Dictation target app"
- "Try again"
- "Dismiss"
- "Insert this dictation into the focused app"

**History card**
- "Recent Dictations"
- "click to insert"
- "No dictations yet"
- "·" separator
- relative time, e.g. "5 min. ago"
- source app name

**Written but deliberately not displayed** (filtered at `BOV:2570-2579`):
- "Transcribing"
- "Refining"
- "Thinking"
- "Working"
- each of the above with "..." appended
- `processingLabel`: "Refining..." / "Thinking..." / "Working..." (`BOV:2562-2568`)

**Dormant menus**
- "Mode:", "Dictate", "Edit", "Command", "Not set" (`BOV:21`)
- "AI Prompt:", "Default", "Off", "Untitled", "App", "N/A" (`BOV:2642`)
- "Use ⟨Private AI⟩" / "Select ⟨Private AI⟩ to enable this prompt"
- "Actions", "Reprocess Last Dictation", "Copy Last Transcription", "Paste Last Transcription", "Undo AI on Last"
- "Reprocess the latest dictation using current AI settings"
- "Open Preferences"

**Retired**
- "Loading model…" (`50ececf4`)
- the in-pill mode label "Dictate" / "Edit" / "Command" (`8626346a`)

---

## 8. Intent signals from the commit history

The last 12 commits on `BOV` run from `ce8f3b6e` (upstream, 2026-07-28) to `abc7e477` (2026-08-23). The owner's own passes are signed `Atin <atin@atin.me>`. `abc7e477` calls itself an "Operator pass".

**Subtraction**
- **Chrome is subtracted until only actions remain.** `8626346a` removed the whole top control row (mode, AI Prompt, Actions, settings gear) and the in-pill mode label. The reasoning: every mode already has a hotkey, Preferences is on Cmd-, and the Actions menu's "two useful entries are now the rail icons." The owner recorded the cost openly: "mode switching is now hotkey-only, with no visible affordance."
- **Icons, not labels.** Copy and Reprocess arrived as "icon-only chips … with tooltips instead of labels" (`0e2948ac`). Every chip since follows suit.
- **Redundant text goes.** "Loading model…" was retired because "the corner icon's spinner already carries that state" (`50ececf4`). The processing status words are hidden because "the waveform sweep carries processing state" (`BOV:3528`).
- **Colour carries meaning.** "The mode is still signalled by the waveform's colour" (`8626346a`). The trace colour is the only mode indicator left.

**Stability and symmetry**
- **Nothing may shift.** Disabled chips "stay visible and dim … so the controls beside them never shift position" (`0e2948ac`). The app icon's frame is reserved "so the two chips above it never shift position as the frontmost app changes" (`378fe4d2`). Hidden spacer slots keep "both columns the same height and nothing shifts as chips come and go" (`c572fdb7`).
- **Symmetry wins over grouping.** `c572fdb7` put all history actions on the left and let "the destructive action [cancel] stand alone." Twenty-seven minutes later, `abc7e477` moved Reprocess to the bottom-right "so the four chips frame the pill symmetrically instead of the left pair sitting stacked while the right pair spread."
- **State and action look different.** The app icon has no chip background "on purpose … chip chrome would imply a third button" (`378fe4d2`). It moved out of the rails and into the black pill so "the chrome columns hold only actions" (`c572fdb7`). It was then centred on the trace midline instead of "hugging the pill's bottom edge" (`abc7e477`).

**The trace**
- **Readable at a glance, then refined.** `378fe4d2` enlarged the bars because the indicator "was small enough to be hard to read at a glance." `50ececf4` then replaced "the centered dance of 7–11 chunky bars" with "a trace of the voice itself": 1.5–2 pt bars across roughly the pill's full usable width, with history flowing left and "fading as it ages."
- **Contrast and texture over smoothness.** `abc7e477` asked for "more height variance". It flipped the level curve from 0.55 (which pushed everything tall) to 1.15 so that "steady background (music, hum) [stays] low while speech stretches tall". It added grain "so the trace never plateaus."

**Craft and discipline**
- **Performance is part of craft.** "At ~90 bars, per-bar shadows are a real compositing cost", so one composited glow replaced them (`50ececf4`). The code also:
  - pauses the rotating border under Reduce Motion (`BOV:3664-3665`)
  - pre-renders the panel offscreen to avoid a double-appearance flash (`BOV:126-128`)
  - exits in 20 ms
- **Layers must read as layers.** The history card "was pure black on the pure-black pill with no shadow — the two surfaces read as one shape." The fix: a real window shadow, a surface "a step lighter", a doubled border (0.22) and a header hairline (`5653b418`).
- **Direct manipulation, safely remembered.** "Drag anywhere … the spot is remembered across launches", "Double-click returns it to the default bottom-center anchor" (`af45c53b`). The position is stored as screen fractions so it "can never restore off-screen."
- **Fix the cause, not the symptom.** The rail "grows along the overlay's free axis, so it cannot overflow as items are added" (`8626346a`). The clipped-rail regression was traced to the `previewMaxWidth` arithmetic and reverted to "the exact width geometry of the previously approved build" (`410539f4`). The c11 text-drop was traced to three compounding causes (`8ed75b9a`).
- **Verified on the running app.** `8626346a`: "Verified on the running app, not just compiled." `410539f4` refers to an "approved build", so visual sign-off is a gate.
- **Pure black, no glass.** The pill is "Solid pitch black" (`BOV:3652`). No material or blur has been introduced in any redesign commit.

---

## 9. Loose ends (code-reading findings, not screen-verified)

1. Chips are inert in **pill** and **small** sizes (`showsTopControls` gate, `BOV:3200`, `3448`).
2. The AI-failure and warning row cannot appear in **pill** size (`showsPreview: false`, `BOV:2446`, `2707-2710`).
3. In **large** size the black pill (170 tall) is top-aligned in a 288 pt canvas. The rails are centred on the canvas, and the pill sits about 118 pt above the configured offset (`BOV:2521-2524`, `3740-3747`).
4. The trace stops scrolling in true silence (`onChange` on a repeated 0, `BOV:3961`).
5. Copy gives no visual acknowledgement. Nothing in the overlay confirms delivery either.
6. There is no failed-to-deliver card.
7. The stale 9-bar comment at `BOV:2478-2483`.
8. Unused code:
   - `overlayBorder*Opacity` pill case (`BOV:2830`, `2838`)
   - `overlayAnimatedOpacity` is always 1 (`BOV:2855-2857`)
   - `theme` environment (`BOV:2367`)
   - dormant menus and selectors (§6)
