import AppKit
import SwiftUI

/// The record square beside the timer: solid while listening, a 1.5 pt outline once input is
/// closed, and nothing (its 6 pt still reserved) when delivered or on a card.
enum SignalRecordMark: Equatable {
    case recording
    case closed
    case none
}

/// Spoken Send's placard in the trace row (DESIGN.md §15): empty at rest, its width reserved.
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

/// The trace row (DESIGN.md §4, §11, §15): `[icon 20] 10 [trace] [placard 7 ch] 6 [square 6] 4
/// [timer 5 ch]`, all centred on the trace's midline. The icon keeps the shape the OS gives it;
/// its frame, the placard's and the timer's are reserved whatever they show.
struct SignalTraceRow: View {
    let geometry: SignalOverlayGeometry
    let icon: NSImage?
    let trace: SignalTraceModel
    let isLive: Bool
    let isSweeping: Bool
    var drain: SignalDrain?
    let mark: SignalRecordMark
    var placard: SignalPlacard = .none
    let timer: SignalTimerReadout

    @Environment(\.signalPalette) private var palette

    var body: some View {
        let metrics = SignalTheme.Metrics.self
        HStack(alignment: .top, spacing: 0) {
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
            .padding(.top, metrics.traceMidline - metrics.targetIcon / 2)
            .help("Dictation target app")

            SignalTraceView(model: self.trace, isLive: self.isLive, isSweeping: self.isSweeping, drain: self.drain)
                .padding(.leading, metrics.traceLeadingGap)

            Spacer(minLength: metrics.placardLeadingGap)

            SignalMonoLabel(text: self.placard.text, role: SignalTheme.Typography.placard, color: self.placardColor)
                .fixedSize()
                .frame(width: metrics.placardWidth, height: SignalTheme.Typography.placard.lineHeight, alignment: .trailing)
                .padding(.top, metrics.traceMidline - SignalTheme.Typography.placard.lineHeight / 2)
                .help("Spoken Send")

            HStack(spacing: metrics.readoutGap) {
                self.recordSquare
                self.timerView
                    .fixedSize()
                    .frame(width: metrics.timerBoxWidth, alignment: .trailing)
            }
            .frame(height: SignalTheme.Typography.timer.lineHeight)
            .padding(.top, metrics.traceMidline - SignalTheme.Typography.timer.lineHeight / 2)
            .padding(.leading, metrics.placardTrailingGap)
        }
        .frame(width: self.geometry.innerWidth, height: metrics.traceRowHeight, alignment: .top)
    }

    private var placardColor: Color {
        switch self.placard {
        case .none, .send: self.palette.accent
        case .noSend: self.palette.text
        case .noReturn: self.palette.textDim
        }
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

/// The microphone, mono uppercase, bottom-centre, the same in every visible state.
struct SignalMicRow: View {
    let text: String
    /// NO MICROPHONE reads in full ink.
    var isEmphasized = false
    @Environment(\.signalPalette) private var palette

    var body: some View {
        SignalMonoLabel(
            text: self.text,
            role: SignalTheme.Typography.micLabel,
            color: self.isEmphasized ? self.palette.text : self.palette.text2
        )
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
            .frame(height: SignalTheme.Metrics.micRowHeight)
            .help("Microphone")
    }
}

/// The live preview: SF Pro 13.5 medium on an 18 pt line, head-truncated so the newest words stay
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
            // CSS centres each line in its 18 pt box: half the extra leading sits above line one.
            .padding(.top, role.lineSpacing / 2)
            .frame(width: self.width, height: self.height, alignment: .topLeading)
            .clipped()
    }
}

/// Delivered: the orange stamp, the headline, and the word count, in place of the preview.
struct SignalDeliveredStatement: View {
    let delivery: SignalDelivery
    @Environment(\.signalPalette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(self.palette.onAccent)
                .frame(width: SignalTheme.Metrics.deliveredStamp, height: SignalTheme.Metrics.deliveredStamp)
                .background(self.palette.accent)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A rail: 30 pt chips in three slots, top at the pill's top corner, bottom at its bottom
/// corner, the middle slot centred between them (reserved, so nothing shifts).
struct SignalRail<Top: View, Middle: View, Bottom: View>: View {
    let height: CGFloat
    @ViewBuilder let top: Top
    @ViewBuilder let middle: Middle
    @ViewBuilder let bottom: Bottom

    var body: some View {
        VStack(spacing: 0) {
            self.top
            Spacer(minLength: 0)
            self.middle
                .frame(width: SignalTheme.Metrics.chip, height: SignalTheme.Metrics.chip)
            Spacer(minLength: 0)
            self.bottom
        }
        .frame(width: SignalTheme.Metrics.chip, height: self.height)
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
