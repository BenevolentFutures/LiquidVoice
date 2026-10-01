import AppKit
import SwiftUI

// Signal: Liquid Voice's visual language (design/visual-language/DESIGN.md, binding prototype
// design/visual-language/prototypes/signal/index.html). The single source of colour, type,
// spacing and motion for the recording overlay, its cards, the history card and the menu bar.
//
// Square solid surfaces, 1 px rules, square-ended ink bars, SF Mono for every number and label,
// and one colour, international orange, only for something live or actionable. No radius, no
// gradients, no glow, no materials, and one blur: the soft floating shadow under the pill and
// cards (DESIGN.md §6, Atin 2026-09-29), drawn by SignalFloatShadow. Dark is the default; light is print on paper and
// follows the system appearance.

enum SignalTheme {
    // MARK: - Colour

    /// The colour tokens (DESIGN.md §2) for one appearance.
    struct Palette {
        /// Record square, write head, sweep, delivered stamp, failed top rule, Copy, NOT DELIVERED.
        let accent: Color
        /// Glyphs and text on `accent`.
        let onAccent: Color
        /// Pill, cards, history card, menu.
        let surface: Color
        /// 1 px pill and card edge.
        let edge: Color
        /// Chip fill (no edge at rest).
        let chip: Color
        /// The flat, unblurred 2 pt drop rule under the pill and cards.
        let drop: Color
        /// The soft floating shadow under the pill and cards (DESIGN.md §6, Atin 2026-09-29):
        /// neutral black, lighter on paper. Dark floats more (Atin, 2026-10-01): deeper, wider,
        /// further down.
        let floatShadow: Color
        /// The floating shadow's blur radius and downward offset, per appearance.
        let floatShadowRadius: CGFloat
        let floatShadowY: CGFloat
        /// Trace bars.
        let ink: Color
        /// The 1 px rule behind the trace.
        let midline: Color
        /// Preview, headlines, timer.
        let text: Color
        /// Mic label, meta, table labels. True ink in light: size, case and face carry it.
        let text2: Color
        /// The frozen preview while transcribing.
        let textDim: Color
        /// Chip glyphs at rest, and disabled.
        let glyph: Color
        let glyphOff: Color
        /// Table rules inside the history card.
        let rule: Color
        /// Pressed and latched chips, hovered history rows.
        let invBackground: Color
        let invForeground: Color
        let invForeground2: Color
        /// Selection brackets (hover only).
        let bracket: Color
        /// Age ruler ticks.
        let graticule: Color

        static let dark = Palette(
            accent: SignalTheme.rgb(0xFF4F1F),
            onAccent: SignalTheme.rgb(0x111214),
            surface: SignalTheme.rgb(0x111214),
            edge: SignalTheme.rgb(0x2C2E33),
            chip: SignalTheme.rgb(0x1A1B1F),
            drop: Color.black.opacity(0.35),
            floatShadow: Color.black.opacity(0.55),
            floatShadowRadius: 18,
            floatShadowY: 9,
            ink: .white,
            midline: SignalTheme.rgb(0x2C2E33),
            text: Color.white.opacity(0.92),
            text2: Color.white.opacity(0.58),
            textDim: Color.white.opacity(0.46),
            glyph: Color.white.opacity(0.85),
            glyphOff: Color.white.opacity(0.28),
            rule: SignalTheme.rgb(0x2C2E33),
            invBackground: .white,
            invForeground: SignalTheme.rgb(0x111214),
            invForeground2: SignalTheme.rgb(0x111214).opacity(0.62),
            bracket: Color.white.opacity(0.78),
            graticule: Color.white.opacity(0.20)
        )

        static let light = Palette(
            accent: SignalTheme.rgb(0xFF4F1F),
            onAccent: SignalTheme.rgb(0x111214),
            surface: .white,
            edge: SignalTheme.rgb(0x111214),
            chip: SignalTheme.rgb(0xF2F2F4),
            drop: SignalTheme.rgb(0x111214),
            floatShadow: Color.black.opacity(0.16),
            floatShadowRadius: 12,
            floatShadowY: 5,
            ink: SignalTheme.rgb(0x111214),
            midline: SignalTheme.rgb(0xD3D4D8),
            text: SignalTheme.rgb(0x111214),
            text2: SignalTheme.rgb(0x111214),
            textDim: SignalTheme.rgb(0x111214).opacity(0.50),
            glyph: SignalTheme.rgb(0x111214),
            glyphOff: SignalTheme.rgb(0x111214).opacity(0.28),
            rule: SignalTheme.rgb(0x111214),
            invBackground: SignalTheme.rgb(0x111214),
            invForeground: .white,
            invForeground2: Color.white.opacity(0.66),
            bracket: SignalTheme.rgb(0x111214),
            graticule: SignalTheme.rgb(0x111214).opacity(0.30)
        )

        static func forScheme(_ scheme: ColorScheme) -> Palette {
            scheme == .light ? .light : .dark
        }
    }

    /// AppKit colours for drawing outside SwiftUI (the menu bar header row).
    enum AppKitColors {
        static let accent = NSColor(srgbRed: 1.0, green: 0x4F / 255.0, blue: 0x1F / 255.0, alpha: 1)
    }

    fileprivate static func rgb(_ hex: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }

    // MARK: - Type

    /// One type role (DESIGN.md §3). Mono roles are every number and label, tabular by
    /// construction; labels are uppercase and tracked +0.06 em.
    struct TypeRole {
        let size: CGFloat
        let weight: Font.Weight
        let isMono: Bool
        /// The CSS line height the prototype sets; SwiftUI frames reserve it.
        let lineHeight: CGFloat
        /// Letter spacing in points (+0.06 em for mono labels).
        let tracking: CGFloat

        var font: Font {
            self.isMono
                ? .system(size: self.size, weight: self.weight, design: .monospaced)
                : .system(size: self.size, weight: self.weight)
        }

        var nsFont: NSFont {
            self.isMono
                ? .monospacedSystemFont(ofSize: self.size, weight: self.weight.nsWeight)
                : .systemFont(ofSize: self.size, weight: self.weight.nsWeight)
        }

        /// Extra space between lines so a wrapped paragraph advances by `lineHeight`.
        var lineSpacing: CGFloat {
            let natural = NSLayoutManager().defaultLineHeight(for: self.nsFont)
            return max(0, self.lineHeight - natural)
        }
    }

    enum Typography {
        /// "0:38", right-aligned in a box reserved for "99:59".
        static let timer = TypeRole(size: 15, weight: .semibold, isMono: true, lineHeight: 18, tracking: 0)
        /// The microphone, bottom-centre of the pill.
        static let micLabel = TypeRole(size: 10.5, weight: .medium, isMono: true, lineHeight: 13, tracking: 0.63)
        /// Spoken Send's placard: "SEND" / "NO SEND" (round 5).
        static let placard = TypeRole(size: 10.5, weight: .semibold, isMono: true, lineHeight: 14, tracking: 0.63)
        /// "118 WORDS", "0:41 · 118 WORDS · C11".
        static let meta = TypeRole(size: 10.5, weight: .medium, isMono: true, lineHeight: 15, tracking: 0.63)
        /// History index "01".
        static let historyIndex = TypeRole(size: 11.5, weight: .semibold, isMono: true, lineHeight: 17, tracking: 0)
        /// History time "3:04 PM".
        static let historyTime = TypeRole(size: 10, weight: .medium, isMono: true, lineHeight: 14, tracking: 0.4)
        /// Table header, day rows, title block, menu header.
        static let tableLabel = TypeRole(size: 10, weight: .medium, isMono: true, lineHeight: 12, tracking: 0.6)
        /// "Sent to c11".
        static let deliveredHeadline = TypeRole(size: 16, weight: .semibold, isMono: false, lineHeight: 20, tracking: 0)
        /// The live preview, head-truncated so the newest words stay visible.
        static let preview = TypeRole(size: 13.5, weight: .medium, isMono: false, lineHeight: 18, tracking: 0)
        /// "Couldn't paste into c11".
        static let failedHeadline = TypeRole(size: 13.5, weight: .semibold, isMono: false, lineHeight: 18, tracking: 0)
        /// Transcripts in the failed card and the history card.
        static let transcript = TypeRole(size: 13, weight: .regular, isMono: false, lineHeight: 17, tracking: 0)
        static let historyTranscript = TypeRole(size: 13, weight: .regular, isMono: false, lineHeight: 18, tracking: 0)
        /// A recovery card's reason line: at most two lines.
        static let reason = TypeRole(size: 13, weight: .regular, isMono: false, lineHeight: 17, tracking: 0)
        /// Copy (semibold) and Dismiss (medium) in the failed card.
        static let button = TypeRole(size: 13, weight: .semibold, isMono: false, lineHeight: 28, tracking: 0)
        static let textButton = TypeRole(size: 13, weight: .medium, isMono: false, lineHeight: 28, tracking: 0)
    }

    // MARK: - Geometry

    enum Metrics {
        // Pill (DESIGN.md §4): 340 x 149, square.
        static let pillWidth: CGFloat = 340
        static let pillPaddingTop: CGFloat = 12
        static let previewLineHeight: CGFloat = 18
        static let previewGap: CGFloat = 6
        static let traceRowHeight: CGFloat = 50
        static let micGap: CGFloat = 4
        static let micRowHeight: CGFloat = 13
        static let pillPaddingBottom: CGFloat = 10
        static let pillPaddingHorizontal: CGFloat = 18
        static let edgeWidth: CGFloat = 1
        static let dropRule: CGFloat = 2
        /// The margin the floating shadow's click-through panel keeps around the surface's panel,
        /// so the blur is never clipped (DESIGN.md §6). The radius and offset are per appearance
        /// (`Palette.floatShadowRadius`, `floatShadowY`); the deepest, dark's radius 18 at y 9,
        /// stays well inside 48 pt.
        static let floatShadowMargin: CGFloat = 48
        /// The failed card's top rule.
        static let failedTopRule: CGFloat = 2

        // Rails and chips.
        static let railGap: CGFloat = 6
        static let chip: CGFloat = 30
        static let chipGlyphSize: CGFloat = 13
        /// Every window that draws brackets keeps this transparent margin around its content, so
        /// a bracket outside a box is never clipped: 6 pt on the sides and top (gap 3 + stroke 1.5
        /// + halo 1 = 5.5), 8 at the bottom, where the bracket also clears the 2 pt drop rule (7.5).
        static let windowInsets = EdgeInsets(top: 6, leading: 6, bottom: 8, trailing: 6)

        // Trace row: icon, trace, record square, timer.
        static let targetIcon: CGFloat = 20
        static let recordSquare: CGFloat = 6
        static let recordSquareOutline: CGFloat = 1.5
        static let readoutGap: CGFloat = 4
        /// Spoken Send's placard (round 5): 10 pt after the icon to the trace, at least 8 pt from
        /// the trace to the placard, 6 pt from the placard to the square.
        static let traceLeadingGap: CGFloat = 10
        static let placardLeadingGap: CGFloat = 8
        static let placardTrailingGap: CGFloat = 6
        /// The placard's reserved width: "NO SEND", seven SF Mono characters with their tracking.
        static let placardWidth: CGFloat = {
            let role = Typography.placard
            let advance = ("0" as NSString).size(withAttributes: [.font: role.nsFont]).width
            return advance * 7 + role.tracking * 6
        }()

        // Voice trace.
        static let barWidth: CGFloat = 2
        static let barPitch: CGFloat = 4
        static let traceHeight: CGFloat = 44
        static let rulerHeight: CGFloat = 6
        static let traceMidline: CGFloat = 22
        static let minBarHeight: CGFloat = 2
        static let maxBarHeight: CGFloat = 40
        static let writeHeadBars = 6
        static let sweepWidth: CGFloat = 24
        static let sweepHeight: CGFloat = 4
        static let samplesPerSecond: Double = 12

        // Failed card body.
        static let copyButtonWidth: CGFloat = 88
        static let buttonHeight: CGFloat = 28
        static let deliveredStamp: CGFloat = 30

        // History card.
        static let historyWidth: CGFloat = 480
        static let historyMaxHeight: CGFloat = 480
        static let historyHeader: CGFloat = 36
        static let historyDayRow: CGFloat = 28
        static let historyIndexColumn: CGFloat = 68
        static let historyFooter: CGFloat = 28
        static let historyPaddingHorizontal: CGFloat = 19
        /// The history card sits this far above the overlay's visible top (DESIGN.md §4).
        static let historyGapAboveOverlay: CGFloat = 6

        // Screen placement: bottom-centre, 50 pt above the visible bottom.
        static let screenBottomOffset: CGFloat = 50

        /// The timer's reserved box: five SF Mono characters ("99:59"), so it never shifts.
        static let timerBoxWidth: CGFloat = {
            let font = Typography.timer.nsFont
            let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
            return advance * 5
        }()
    }

    // MARK: - Selection brackets (DESIGN.md §7)

    struct BracketSpec: Equatable {
        /// Clear space between the box edge and the bracket's inner edge.
        let gap: CGFloat
        /// Arm length from the outer vertex.
        let length: CGFloat
        /// Added to the bottom gap on a surface with the drop rule.
        let drop: CGFloat

        static let pill = BracketSpec(gap: 3, length: 10, drop: Metrics.dropRule)
        static let chip = BracketSpec(gap: 2, length: 6, drop: 0)
        static let card = BracketSpec(gap: 3, length: 10, drop: Metrics.dropRule)

        static let stroke: CGFloat = 1.5
        /// The knockout halo under every bracket, in the surface colour.
        static let halo: CGFloat = 1
    }

    // MARK: - Motion (DESIGN.md §8)

    enum Motion {
        /// Dismiss: opacity 1 -> 0, linear. No scale, no drop.
        static let dismiss: TimeInterval = 0.12
        /// Brackets fade in and out, linear.
        static let bracketFade: TimeInterval = 0.06
        /// One trace sample: 12 per second.
        static let traceSample: TimeInterval = 1.0 / 12.0
        /// Each drawn bar eases toward its target height, settling in about this long (Atin,
        /// 2026-09-29: smoother than the 60 ms linear, 2 pt-snapped morph).
        static let barEase: TimeInterval = 0.135
        /// The trace advances only while the voice is on, and stays on this long after the last
        /// level above the gate, so it does not stutter between words (Atin, 2026-09-29).
        static let voiceHangover: TimeInterval = 0.25
        /// Stop: every bar to 2 pt; the write head goes ink.
        static let stopToFlat: TimeInterval = 0.06
        /// The transcribing sweep, stepped on the bar pitch.
        static let sweepPeriod: TimeInterval = 1.05
        /// A chip press shows for at least this long; its colour changes linearly over it.
        static let chipPress: TimeInterval = 0.06
        /// Copy feedback on the chip and on the card's Copy button.
        static let copyFeedbackChip: TimeInterval = 0.9
        static let copyFeedbackButton: TimeInterval = 1.4
        /// Delivered stays this long after the paste, then dismisses.
        static let deliveredHold: TimeInterval = 0.6
        /// The menu bar mark's bars follow the level at 8 Hz while listening.
        static let menuBarBars: TimeInterval = 1.0 / 8.0

        /// Whether motion is reduced right now (bars jump, the sweep holds four positions,
        /// fades become cuts).
        static var isReduced: Bool {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }
}

extension Font.Weight {
    fileprivate var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        default: .regular
        }
    }
}

// MARK: - Environment

private struct SignalPaletteKey: EnvironmentKey {
    static let defaultValue = SignalTheme.Palette.dark
}

extension EnvironmentValues {
    /// The Signal palette for this view's appearance. Set by `.signalPalette()` from the
    /// colour scheme, so overlay views follow the system appearance.
    var signalPalette: SignalTheme.Palette {
        get { self[SignalPaletteKey.self] }
        set { self[SignalPaletteKey.self] = newValue }
    }
}

private struct SignalPaletteFromScheme: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.signalPalette, SignalTheme.Palette.forScheme(self.colorScheme))
    }
}

extension View {
    /// Resolves the Signal palette from the current colour scheme (dark default, light when the
    /// system appearance is light).
    func signalPalette() -> some View {
        self.modifier(SignalPaletteFromScheme())
    }

    /// A Signal type role: face, size and weight, tracking, and the prototype's line height.
    func signalType(_ role: SignalTheme.TypeRole) -> some View {
        self
            .font(role.font)
            .tracking(role.tracking)
            .lineSpacing(role.lineSpacing)
    }
}
