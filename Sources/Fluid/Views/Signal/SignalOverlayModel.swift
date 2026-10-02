import AppKit
import Combine
import SwiftUI

/// What the Signal overlay shows (DESIGN.md §9), beside `NotchContentState`'s shared flags.
/// Driven by `BottomOverlayWindowController`; read by `BottomOverlayView`.
@MainActor
final class SignalOverlayModel: ObservableObject {
    static let shared = SignalOverlayModel()

    enum Phase: Equatable {
        /// Hidden, or never shown.
        case idle
        /// Recording: live preview, live trace, solid square, running timer.
        case listening
        /// The recording stopped and the final pass runs: flat trace, hollow square, frozen timer
        /// and preview. It reads as transcribing only once the pass turns out slow (250 ms).
        case stopped
        /// The final pass is slow: the preview dims, the sweep crosses, Copy and Reprocess dim.
        case transcribing
        /// The text was handed to the target app; held briefly, then dismissed.
        case delivered(SignalDelivery)
        /// A notice row in the preview slot (DESIGN.md §15): news that needs no rescue. No growth,
        /// no top rule; the rest of the pill as at rest.
        case notice(SignalNotice)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var recordingStartedAt: Date?
    /// The recording's length once it stopped; the timer shows it from then on.
    @Published private(set) var frozenDuration: TimeInterval?
    /// The preview as it stood at the stop, so later clears of the live text never blank it.
    @Published private(set) var frozenPreview = ""
    /// The live word count as it stood at the stop (round 6), so clearing the live text never
    /// zeroes it while the final pass runs.
    @Published private(set) var frozenWordCount: Int?
    /// The microphone in use, shown bottom-centre in every visible state.
    @Published var microphoneName = ""
    /// Fading out (120 ms linear); controls are inert.
    @Published private(set) var isFading = false
    /// Spoken Send's quiet countdown while it runs, or where a cancel stopped it (held 700 ms).
    @Published private(set) var sendDrain: SignalDrain?
    /// Spoken Send's placard as the recording stopped; the post-stop states keep showing it.
    @Published private(set) var stopPlacard: SignalPlacard = .none

    private(set) var trace = SignalTraceModel()
    /// The foot row's live counters' smoothing (DESIGN.md §16), kept across view updates.
    let counterClock = SignalCounterClock()
    /// The pill holds a recording of this session, so its live counters mean something; false for
    /// a reprocess, which has no live text (DESIGN.md §16).
    private(set) var countsLiveWords = false

    /// Holds a hover state for renders and inspection, like the prototype's `?hover=1` and
    /// `?hoverChip=`: "pill", or a chip id ("history", "copy", "cancel", "reprocess").
    @Published var inspectionHover: String?
    /// Holds Spoken Send's placard for renders and inspection (the prototype's `?armed=1`).
    @Published var inspectionPlacard: SignalPlacard?
    /// Holds the transcribing sweep at a fraction of its period (renders and inspection).
    @Published var inspectionSweepProgress: Double?

    /// The last recording's facts, for a failure card about it.
    private(set) var lastRecording: (duration: TimeInterval, endedAt: Date)?

    private init() {}

    var isPostStop: Bool {
        switch self.phase {
        case .stopped, .transcribing, .delivered: true
        case .idle, .listening, .notice: false
        }
    }

    var isNotice: Bool {
        if case .notice = self.phase { return true }
        return false
    }

    /// A notice row on a pill with no recording: flat trace, the kept recording's frozen length.
    func showNotice(_ notice: SignalNotice, frozenDuration: TimeInterval?) {
        self.trace.flatten()
        self.recordingStartedAt = nil
        self.frozenDuration = frozenDuration ?? 0
        self.frozenPreview = ""
        self.frozenWordCount = nil
        self.countsLiveWords = false
        self.sendDrain = nil
        self.stopPlacard = .none
        self.isFading = false
        self.phase = .notice(notice)
    }

    var isDelivered: Bool {
        if case .delivered = self.phase { return true }
        return false
    }

    /// The trace matching the pill's width (the bar count depends on the overlay size).
    func ensureTraceBars(_ bars: Int) {
        guard self.trace.barCount != bars else { return }
        let replacement = SignalTraceModel(barCount: bars, noiseThreshold: self.trace.noiseThreshold)
        self.trace = replacement
        self.objectWillChange.send()
    }

    func beginRecording(at date: Date = Date(), noiseThreshold: CGFloat) {
        self.sendDrain = nil
        self.stopPlacard = .none
        self.trace.noiseThreshold = noiseThreshold
        self.trace.begin(at: date.timeIntervalSinceReferenceDate)
        self.recordingStartedAt = date
        self.frozenDuration = nil
        self.frozenPreview = ""
        self.frozenWordCount = nil
        self.countsLiveWords = true
        self.isFading = false
        self.phase = .listening
    }

    /// Input closed: freeze the timer and the preview, flatten the trace (60 ms).
    func stopRecording(at date: Date = Date(), preview: String, placard: SignalPlacard = .none) {
        guard self.phase == .listening else { return }
        self.sendDrain = nil
        self.stopPlacard = placard
        self.trace.stop(at: date.timeIntervalSinceReferenceDate)
        let duration = self.recordingStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        self.frozenDuration = duration
        self.frozenPreview = preview
        self.frozenWordCount = NotchContentState.shared.liveWordCount
        self.lastRecording = (duration, date)
        self.phase = .stopped
    }

    /// The final pass is slow (or a reprocess runs): show the working signals.
    func beginTranscribing() {
        switch self.phase {
        case .listening, .stopped, .idle:
            if self.phase == .listening {
                self.stopRecording(preview: self.frozenPreview)
            } else if self.phase == .idle {
                self.countsLiveWords = false
            }
            if self.frozenDuration == nil { self.frozenDuration = 0 }
            self.trace.flatten()
            self.phase = .transcribing
        case .transcribing, .delivered, .notice:
            break
        }
    }

    func showDelivered(_ delivery: SignalDelivery) {
        // "Sent" clears the placard; a canceled send or a terminal without Return keeps it.
        if delivery.sentReturn || self.stopPlacard == .send {
            self.stopPlacard = .none
        }
        self.phase = .delivered(delivery)
    }

    // MARK: Spoken Send (DESIGN.md §15)

    /// The placard for Spoken Send's current state.
    static func placard(indicator: SpokenSendController.Indicator, sendsInApp: Bool) -> SignalPlacard {
        switch indicator {
        case .hidden: .none
        case .armed, .countingDown: sendsInApp ? .send : .noReturn
        case .canceled: .noSend
        }
    }

    func startSendCountdown(duration: TimeInterval, at date: Date = Date()) {
        guard self.phase == .listening else { return }
        self.sendDrain = SignalDrain(startedAt: date, duration: duration)
    }

    /// A cancel stops the drain bar in ink where it was.
    func freezeSendCountdown(at date: Date = Date()) {
        guard var drain = self.sendDrain, !drain.isCanceled else { return }
        drain.frozenRemaining = drain.remaining(at: date)
        self.sendDrain = drain
    }

    func setStopPlacard(_ placard: SignalPlacard) {
        if self.stopPlacard != placard { self.stopPlacard = placard }
    }

    /// The Return was canceled after the stop: the held pill's placard reads NO SEND.
    func markSendCanceled() {
        if self.stopPlacard == .send { self.stopPlacard = .noSend }
    }

    func clearSendCountdown() {
        if self.sendDrain != nil { self.sendDrain = nil }
    }

    func beginFading() {
        self.isFading = true
    }

    /// Hidden: nothing to show until the next presentation.
    func reset() {
        self.countsLiveWords = false
        self.sendDrain = nil
        self.stopPlacard = .none
        self.trace.flatten()
        self.isFading = false
        self.phase = .idle
    }

    /// "0:38", from the start of the recording to `date`, or the frozen length.
    func timerText(at date: Date) -> String {
        if let frozen = self.frozenDuration {
            return Self.formatDuration(frozen)
        }
        guard let start = self.recordingStartedAt else { return Self.formatDuration(0) }
        return Self.formatDuration(date.timeIntervalSince(start))
    }

    /// m:ss, capped at the reserved "99:59".
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = min(max(Int(seconds.rounded(.down)), 0), 99 * 60 + 59)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// Status words the stop and reprocess paths write into the live text. Signal never shows
    /// them (DESIGN.md §12): the square, the frozen timer and the sweep carry the state.
    static let statusWords: Set<String> = [
        "Transcribing", "Refining", "Thinking", "Working", "Reprocessing",
        "Transcribing...", "Refining...", "Thinking...", "Working...", "Reprocessing...",
    ]

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

/// What the outcome state says (DESIGN.md §9.4, §15). The paste is posted, never read back, so
/// the headline names the action taken on each path and claims nothing more.
struct SignalDelivery: Equatable {
    enum Method: Equatable {
        /// Cmd+V was posted to the app (c11 and Ghostty always).
        case paste
        /// Keystrokes were posted to the app.
        case keystrokes
        /// The Accessibility API accepted the text as the field's value.
        case accessibility
    }

    let appName: String?
    let words: Int
    let method: Method
    /// Spoken Send pressed Return after the text: the outcome is "Sent".
    let sentReturn: Bool

    var headline: String {
        let app = self.appName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = app.flatMap { $0.isEmpty ? nil : $0 }
        if self.sentReturn { return target.map { "Sent to \($0)" } ?? "Sent" }
        switch self.method {
        case .paste: return target.map { "Pasted into \($0)" } ?? "Pasted"
        case .keystrokes: return target.map { "Typed into \($0)" } ?? "Typed"
        case .accessibility: return target.map { "Inserted into \($0)" } ?? "Inserted"
        }
    }

    var meta: String {
        let words = "\(self.words) \(self.words == 1 ? "word" : "words")"
        return self.sentReturn ? words + " · Return" : words
    }
}

/// The pill's geometry for each overlay size. Medium is DESIGN.md §4 exactly (340 x 130); the
/// other sizes keep the same rows and change only how many preview lines are reserved and the
/// width (provisional: DESIGN.md designs the medium pill only).
struct SignalOverlayGeometry: Equatable {
    let pillWidth: CGFloat
    let previewLines: Int

    static func forSize(_ size: SettingsStore.OverlaySize) -> SignalOverlayGeometry {
        switch size {
        // No preview; the one-line row still carries the outcome and the notice.
        case .pill: SignalOverlayGeometry(pillWidth: SignalTheme.Metrics.pillWidth, previewLines: 0)
        case .small: SignalOverlayGeometry(pillWidth: SignalTheme.Metrics.pillWidth, previewLines: 1)
        case .medium: SignalOverlayGeometry(pillWidth: SignalTheme.Metrics.pillWidth, previewLines: 3)
        case .large: SignalOverlayGeometry(pillWidth: SignalTheme.Metrics.historyWidth, previewLines: 5)
        }
    }

    private var metrics: SignalTheme.Metrics.Type {
        SignalTheme.Metrics.self
    }

    /// The preview area: 3 lines of 16 in medium (48).
    var previewHeight: CGFloat {
        CGFloat(self.previewLines) * self.metrics.previewLineHeight
    }

    /// The top area: the preview's lines, and at least one line, which the outcome statement and
    /// the notice need. They take a compact one-line form when it is shorter than 48.
    var topAreaHeight: CGFloat {
        max(self.previewHeight, self.metrics.previewLineHeight)
    }

    var isCompactTop: Bool {
        self.topAreaHeight < 3 * self.metrics.previewLineHeight
    }

    var pillHeight: CGFloat {
        let top = self.topAreaHeight + self.metrics.previewGap
        return self.metrics.pillPaddingTop + top + self.metrics.traceRowHeight + self.metrics.micGap
            + self.metrics.micRowHeight + self.metrics.pillPaddingBottom
    }

    var innerWidth: CGFloat {
        self.pillWidth - 2 * self.metrics.pillPaddingHorizontal
    }

    /// The readout: the 6 pt square, a 4 pt gap, and the timer's "99:59" box.
    var readoutWidth: CGFloat {
        self.metrics.recordSquare + self.metrics.readoutGap + self.metrics.timerBoxWidth
    }

    /// Bars that fit the row `[trace] >=12 [readout]` (round 6: the icon moved to the foot row and
    /// the SEND placard to its right end, so the trace takes their room).
    var traceBars: Int {
        SignalTraceModel.barCount(forWidth: self.innerWidth - self.metrics.traceReadoutGap - self.readoutWidth)
    }

    /// Rails are the pill's height and hold three 30 pt slots.
    var railHeight: CGFloat {
        max(self.pillHeight, 3 * self.metrics.chip)
    }
}

extension DictationDeliveryOutcome.Method {
    var signalMethod: SignalDelivery.Method {
        switch self {
        case .paste: .paste
        case .keystrokes: .keystrokes
        case .accessibility: .accessibility
        }
    }
}

/// A notice row (DESIGN.md §15): a headline, a reason, and inline text actions, in the pill's
/// reserved preview slot. "Speech recognition is back" is the one notice today.
enum SignalNotice: Equatable {
    /// The model recovered while a timed-out recording is kept: Reprocess it, or dismiss.
    case recognitionBack

    var headline: String {
        switch self {
        case .recognitionBack: "Speech recognition is back"
        }
    }

    var reason: String {
        switch self {
        case .recognitionBack: "A kept dictation is waiting"
        }
    }
}
