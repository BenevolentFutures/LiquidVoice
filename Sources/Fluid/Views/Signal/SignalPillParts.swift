import AppKit
import SwiftUI

/// The record square beside the timer: solid while listening, a 1.5 pt outline once input is
/// closed, and nothing (its 6 pt still reserved) when delivered or on a card.
enum SignalRecordMark: Equatable {
    case recording
    case closed
    case none
}

/// Spoken Send's placard at the foot row's right end (DESIGN.md §15, round 6): empty at rest, its
/// width reserved.
enum SignalPlacard: Equatable {
    case none
    /// The phrase was heard; Return follows the paste. Orange.
    case send
    /// The send was canceled. Ink.
    case noSend
    /// A terminal that never gets Return. Dim.
    case noReturn

    var text: String {
        switch self {
        case .none: ""
        case .send: "Send"
        case .noSend, .noReturn: "No send"
        }
    }
}

/// What the timer box shows.
enum SignalTimerReadout: Equatable {
    /// The recording's length, running from this start.
    case running(Date)
    /// A frozen length ("0:41"); `dim` for the microphone card's "0:00".
    case frozen(String, dim: Bool)
    /// Spoken Send's countdown, "1.5" to "0.0" with one decimal: orange, ink once canceled.
    case countdown(SignalDrain)
}

/// The trace row (DESIGN.md §4, §11, round 6): `[trace] >=12 [square 6] 4 [timer 5 ch]`, the trace
/// from the left edge and the readout flush right, centred on the trace's midline. The timer's box
/// is reserved whatever it shows. The target-app icon and Spoken Send's placard live in the foot row.
struct SignalTraceRow: View {
    let geometry: SignalOverlayGeometry
    let trace: SignalTraceModel
    let isLive: Bool
    let isSweeping: Bool
    var drain: SignalDrain?
    var staticSweepProgress: Double?
    let mark: SignalRecordMark
    let timer: SignalTimerReadout

    @Environment(\.signalPalette) private var palette

    var body: some View {
        let metrics = SignalTheme.Metrics.self
        HStack(alignment: .top, spacing: 0) {
            SignalTraceView(
                model: self.trace,
                isLive: self.isLive,
                isSweeping: self.isSweeping,
                drain: self.drain,
                staticSweepProgress: self.staticSweepProgress
            )

            Spacer(minLength: metrics.traceReadoutGap)

            HStack(spacing: metrics.readoutGap) {
                self.recordSquare
                self.timerView
                    .fixedSize()
                    .frame(width: metrics.timerBoxWidth, alignment: .trailing)
            }
            .frame(height: SignalTheme.Typography.timer.lineHeight)
            .padding(.top, metrics.traceMidline - SignalTheme.Typography.timer.lineHeight / 2)
        }
        .frame(width: self.geometry.innerWidth, height: metrics.traceRowHeight, alignment: .top)
    }

    @ViewBuilder
    private var recordSquare: some View {
        let size = SignalTheme.Metrics.recordSquare
        switch self.mark {
        case .recording:
            Rectangle().fill(self.palette.accent).frame(width: size, height: size)
        case .closed:
            Rectangle()
                .strokeBorder(self.palette.accent, lineWidth: SignalTheme.Metrics.recordSquareOutline)
                .frame(width: size, height: size)
        case .none:
            Color.clear.frame(width: size, height: size)
        }
    }

    @ViewBuilder
    private var timerView: some View {
        switch self.timer {
        case let .running(start):
            TimelineView(.periodic(from: start, by: 1)) { context in
                self.timerText(SignalOverlayModel.formatDuration(context.date.timeIntervalSince(start)), color: self.palette.text)
            }
        case let .frozen(text, dim):
            self.timerText(text, color: dim ? self.palette.textDim : self.palette.text)
        case let .countdown(drain):
            TimelineView(.animation(minimumInterval: 0.05, paused: !drain.isRunning)) { context in
                self.timerText(
                    String(format: "%.1f", drain.remaining(at: context.date)),
                    color: drain.isCanceled ? self.palette.text : self.palette.accent
                )
            }
        }
    }

    private func timerText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(SignalTheme.Typography.timer.font)
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .accessibilityLabel(text)
    }
}

/// The Hollyland lapel mic's battery, for the foot row's mic label (DESIGN.md §16, Atin
/// 2026-10-01: "Hollyland lapel and then the percentage level"). Set on the overlay model by
/// `LapelMicBatteryMonitor` only while the selected input is the Lark A1 receiver (directly or
/// through an aggregate); nil for every other microphone, which keeps its own name.
struct SignalMicBattery: Equatable {
    /// Linked transmitters, 0–2: how many percent places the label reserves.
    var linkedCount: Int
    /// Each linked mic's percent, mic 1 first. Empty with no reading yet, none linked, or a reading
    /// older than `freshness`.
    var percents: [Int]

    /// A reading older than this reads as no reading.
    static let freshness: TimeInterval = 120
    /// At or below this the percent is drawn in `accent`: orange is for something actionable now
    /// (DESIGN.md §2). An assumption, not yet confirmed with Atin.
    static let lowPercent = 15

    static func isLow(_ percent: Int) -> Bool {
        percent <= self.lowPercent
    }

    /// The label's state from the monitor's cache: nil unless the input is the receiver; a stale
    /// (or missing) reading shows the name alone.
    static func from(inputIsReceiver: Bool, reading: LarkA1Status?, readAt: Date?, now: Date) -> SignalMicBattery? {
        guard inputIsReceiver else { return nil }
        guard let reading, let readAt, now.timeIntervalSince(readAt) <= self.freshness else {
            return SignalMicBattery(linkedCount: 0, percents: [])
        }
        return SignalMicBattery(linkedCount: reading.linkedCount, percents: reading.linkedPercents)
    }
}

/// The lapel mic's label: "HOLLYLAND LAPEL 33%", the name alone with no reading. Its width is
/// reserved for the widest reading ("100%" in every place), so the icon and label, centred as a
/// pair, never move as a percent appears or changes width; the text sits leading in that box. The
/// name is the longest whose widest reading fits the mic's 160 pt: with two mics linked ("HOLLYLAND
/// LAPEL 100% 100%" is 170) or a mode word in front ("EDIT · "), it is "HOLLYLAND", whatever the
/// reading, so the name never switches as the numbers change and the pair keeps clear of the word
/// count (a full 160 would touch "9999 WORDS").
enum SignalMicLabel {
    static let names = ["Hollyland lapel", "Hollyland"]

    struct Layout: Equatable {
        let name: String
        let percents: [Int]
        /// The label's frame, its tracking included, plus 1 pt so SwiftUI's measure never truncates.
        let width: CGFloat
    }

    static func layout(
        prefix: String,
        battery: SignalMicBattery,
        maxWidth: CGFloat,
        width: (String) -> CGFloat
    ) -> Layout {
        let places = max(1, min(2, max(battery.linkedCount, battery.percents.count)))
        let widest = String(repeating: " 100%", count: places)
        for name in self.names {
            let reserved = width((prefix + name + widest).uppercased()) + 1
            if reserved <= maxWidth {
                return Layout(name: name, percents: battery.percents, width: reserved)
            }
        }
        // A long mode prefix ("LOADING MODEL · EDIT · "): the mic's full width, tail-truncated.
        return Layout(name: self.names[self.names.count - 1], percents: battery.percents, width: maxWidth)
    }
}

/// The foot row (DESIGN.md §4, round 6, Atin 2026-10-01): the target-app icon (16 pt) and the
/// microphone, centred as a pair, the same in every visible state; the live word count at the left
/// end and, at the right end, Spoken Send's placard or (while the placard is empty) words per
/// minute, all absolute so the pair never moves (DESIGN.md §16, Atin 2026-10-01).
struct SignalFootRow: View {
    let icon: NSImage?
    let micText: String
    /// NO MICROPHONE reads in full ink.
    var isMicEmphasized = false
    /// The live counters while a dictation is live, stopped, transcribing or counting down; nil
    /// hides them.
    var counters: SignalCounterInput?
    /// Holds the counters' smoothing across updates (the overlay model's).
    var counterClock: SignalCounterClock?
    var placard: SignalPlacard = .none
    /// The lapel mic's battery while it is the input: the label reads "HOLLYLAND LAPEL 33%" in
    /// place of `micText`, after `micPrefix` ("EDIT · ").
    var micBattery: SignalMicBattery?
    var micPrefix = ""

    @Environment(\.signalPalette) private var palette

    var body: some View {
        let metrics = SignalTheme.Metrics.self
        let role = SignalTheme.Typography.micLabel
        ZStack {
            HStack(spacing: metrics.footGap) {
                Group {
                    if let icon = self.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: metrics.targetIcon, height: metrics.targetIcon)
                .help("Dictation target app")

                if let battery = self.micBattery {
                    self.lapelLabel(battery, role: role)
                } else {
                    SignalMonoLabel(
                        text: self.micText,
                        role: role,
                        color: self.isMicEmphasized ? self.palette.text : self.palette.text2
                    )
                        .truncationMode(.tail)
                        // Its own width (plus 1 pt so SwiftUI's measure never truncates a name that
                        // fits), at most 160, so the icon and the name centre as a pair.
                        .frame(width: min(metrics.micMaxWidth, role.width(of: self.micText.uppercased()) + 1))
                        .help("Microphone")
                }
            }

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                SignalMonoLabel(text: self.placard.text, role: SignalTheme.Typography.placard, color: self.placardColor)
                    .fixedSize()
                    .frame(width: metrics.placardWidth, alignment: .trailing)
                    .help("Spoken Send")
            }

            // Above the placard, so WPM's tooltip is its own; SEND / NO SEND takes the right end
            // back whenever the placard has content.
            if let clock = self.counterClock {
                SignalLiveCounters(input: self.counters, showsWPM: self.placard == .none, clock: clock)
            }
        }
        .frame(height: metrics.micRowHeight)
    }

    /// "HOLLYLAND LAPEL 33%" in the mic label's face, a low percent in `accent`, in a box reserved
    /// for the widest reading so nothing beside it moves (`SignalMicLabel`).
    private func lapelLabel(_ battery: SignalMicBattery, role: SignalTheme.TypeRole) -> some View {
        let layout = SignalMicLabel.layout(
            prefix: self.micPrefix,
            battery: battery,
            maxWidth: SignalTheme.Metrics.micMaxWidth,
            width: role.width(of:)
        )
        var text = Text((self.micPrefix + layout.name).uppercased())
        for percent in layout.percents {
            text = text + Text(" ") + Text("\(percent)%")
                .foregroundStyle(SignalMicBattery.isLow(percent) ? self.palette.accent : self.palette.text2)
        }
        let spoken = layout.percents.isEmpty
            ? "Hollyland lapel"
            : "Hollyland lapel, battery " + layout.percents.map { "\($0) percent" }.joined(separator: " and ")
        return text
            .font(role.font)
            .tracking(role.tracking)
            .monospacedDigit()
            .foregroundStyle(self.palette.text2)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: layout.width, alignment: .leading)
            .help("Microphone and battery")
            .accessibilityLabel(spoken)
    }

    private var placardColor: Color {
        switch self.placard {
        case .none, .send: self.palette.accent
        case .noSend: self.palette.text
        case .noReturn: self.palette.textDim
        }
    }
}

/// The live preview: SF Pro 12.5 medium on a 16 pt line, head-truncated so the newest words stay
/// visible; dimmed and frozen while transcribing.
struct SignalPreview: View {
    let text: String
    let lines: Int
    let height: CGFloat
    let width: CGFloat
    let isDimmed: Bool
    @Environment(\.signalPalette) private var palette

    var body: some View {
        let role = SignalTheme.Typography.preview
        Text(self.text)
            .signalType(role)
            .foregroundStyle(self.isDimmed ? self.palette.textDim : self.palette.text)
            .multilineTextAlignment(.leading)
            .lineLimit(self.lines)
            .truncationMode(.head)
            .fixedSize(horizontal: false, vertical: true)
            // CSS centres each line in its 16 pt box: half the extra leading sits above line one.
            .padding(.top, role.lineSpacing / 2)
            .frame(width: self.width, height: self.height, alignment: .topLeading)
            .clipped()
    }
}

/// The outcome: the orange stamp, the headline, and the word count, in place of the preview.
/// Compact (a one-line preview area): a small stamp and one line.
struct SignalDeliveredStatement: View {
    let delivery: SignalDelivery
    var isCompact = false
    @Environment(\.signalPalette) private var palette

    var body: some View {
        Group {
            if self.isCompact {
                HStack(spacing: 8) {
                    self.stamp(size: 16, glyph: 9)
                    Text(self.delivery.headline)
                        .font(SignalTheme.Typography.failedHeadline.font)
                        .foregroundStyle(self.palette.text)
                        .lineLimit(1)
                    SignalMonoLabel(text: self.delivery.meta, color: self.palette.text2)
                }
            } else {
                HStack(spacing: 14) {
                    self.stamp(size: SignalTheme.Metrics.deliveredStamp, glyph: 15)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(self.delivery.headline)
                            .font(SignalTheme.Typography.deliveredHeadline.font)
                            .foregroundStyle(self.palette.text)
                            .lineLimit(1)
                            .frame(height: SignalTheme.Typography.deliveredHeadline.lineHeight)
                        SignalMonoLabel(text: self.delivery.meta, color: self.palette.text2)
                            .frame(height: 14)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func stamp(size: CGFloat, glyph: CGFloat) -> some View {
        Image(systemName: "checkmark")
            .font(.system(size: glyph, weight: .bold))
            .foregroundStyle(self.palette.onAccent)
            .frame(width: size, height: size)
            .background(self.palette.accent)
    }
}

/// A rail (round 6, Atin 2026-10-01): its two chips spaced evenly down the rail (`space-evenly`:
/// 23 pt above, between and below on the 130 pt rail) instead of pinned to the pill's corners. The
/// middle slot (the retired Spoken Send chip's) is reserved at the rail's centre and takes no
/// part in the spacing, as in the prototype.
struct SignalRail<Top: View, Middle: View, Bottom: View>: View {
    let height: CGFloat
    @ViewBuilder let top: Top
    @ViewBuilder let middle: Middle
    @ViewBuilder let bottom: Bottom

    var body: some View {
        let chip = SignalTheme.Metrics.chip
        let gap = Self.gap(height: self.height)
        VStack(spacing: 0) {
            self.top
            Spacer(minLength: 0)
            self.bottom
        }
        .padding(.vertical, gap)
        .frame(width: chip, height: self.height)
        .overlay {
            // Reserved and empty: in the shorter sizes it overlaps the chips, so it takes no clicks.
            self.middle
                .frame(width: chip, height: chip)
                .allowsHitTesting(false)
        }
    }

    /// The even gap above the top chip and below the bottom one: the rail's free height split three
    /// ways, on whole points (the gap between takes the remainder).
    static func gap(height: CGFloat) -> CGFloat {
        max(0, ((height - 2 * SignalTheme.Metrics.chip) / 3).rounded(.down))
    }
}

/// The prototype's head truncation for the live preview: drop whole leading words until the rest
/// fits the reserved lines, with "…" in front, so the newest words are always visible. (SwiftUI's
/// `.head` truncation trims only the last line of a wrapped paragraph.)
@MainActor
enum SignalTextFitting {
    private static var cache: (key: String, value: String)?

    /// `wasCut`: the text is already the tail of something longer (the preview's character limit),
    /// so its first word may be partial and it starts with "…" whatever fits.
    static func newestWords(of text: String, wasCut: Bool, font: NSFont, width: CGFloat, lines: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard lines > 0, width > 0, !trimmed.isEmpty else { return "" }
        let key = "\(wasCut)|\(font.pointSize)|\(width)|\(lines)|\(trimmed)"
        if let cache = self.cache, cache.key == key { return cache.value }

        var words = trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        if wasCut, words.count > 1 { words.removeFirst() }
        func candidate(dropping count: Int) -> String {
            let rest = words[count...].joined(separator: " ")
            return count > 0 || wasCut ? "…" + rest : rest
        }
        var result = candidate(dropping: 0)
        if self.lineCount(result, font: font, width: width) > lines, words.count > 1 {
            var low = 1
            var high = words.count - 1
            while low < high {
                let middle = (low + high) / 2
                if self.lineCount(candidate(dropping: middle), font: font, width: width) <= lines {
                    high = middle
                } else {
                    low = middle + 1
                }
            }
            result = candidate(dropping: low)
        }
        self.cache = (key, result)
        return result
    }

    static func lineCount(_ text: String, font: NSFont, width: CGFloat) -> Int {
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        var lines = 0
        var index = 0
        let glyphs = layout.numberOfGlyphs
        while index < glyphs {
            var range = NSRange()
            layout.lineFragmentRect(forGlyphAt: index, effectiveRange: &range)
            index = NSMaxRange(range)
            lines += 1
        }
        return lines
    }
}
