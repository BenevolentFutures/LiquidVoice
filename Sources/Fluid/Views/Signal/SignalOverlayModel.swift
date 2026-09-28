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
        /// The text was handed to the target app; held 1.2 s, then dismissed.
        case delivered(SignalDelivery)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var recordingStartedAt: Date?
    /// The recording's length once it stopped; the timer shows it from then on.
    @Published private(set) var frozenDuration: TimeInterval?
    /// The preview as it stood at the stop, so later clears of the live text never blank it.
    @Published private(set) var frozenPreview = ""
    /// The microphone in use, shown bottom-centre in every visible state.
    @Published var microphoneName = ""
    /// Fading out (120 ms linear); controls are inert.
    @Published private(set) var isFading = false

    private(set) var trace = SignalTraceModel()

    /// The last recording's facts, for a failure card about it.
    private(set) var lastRecording: (duration: TimeInterval, endedAt: Date)?

    private init() {}

    var isPostStop: Bool {
        switch self.phase {
        case .stopped, .transcribing, .delivered: true
        case .idle, .listening: false
        }
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
        self.trace.noiseThreshold = noiseThreshold
        self.trace.begin(at: date.timeIntervalSinceReferenceDate)
        self.recordingStartedAt = date
        self.frozenDuration = nil
        self.frozenPreview = ""
        self.isFading = false
        self.phase = .listening
    }

    /// Input closed: freeze the timer and the preview, flatten the trace (60 ms).
    func stopRecording(at date: Date = Date(), preview: String) {
        guard self.phase == .listening else { return }
        self.trace.stop(at: date.timeIntervalSinceReferenceDate)
        let duration = self.recordingStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        self.frozenDuration = duration
        self.frozenPreview = preview
        self.lastRecording = (duration, date)
        self.phase = .stopped
    }

    /// The final pass is slow (or a reprocess runs): show the working signals.
    func beginTranscribing() {
        switch self.phase {
        case .listening, .stopped, .idle:
            if self.phase == .listening {
                self.stopRecording(preview: self.frozenPreview)
            }
            if self.frozenDuration == nil { self.frozenDuration = 0 }
            self.trace.flatten()
            self.phase = .transcribing
        case .transcribing, .delivered:
            break
        }
    }

    func showDelivered(_ delivery: SignalDelivery) {
        self.phase = .delivered(delivery)
    }

    func beginFading() {
        self.isFading = true
    }

    /// Hidden: nothing to show until the next presentation.
    func reset() {
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

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

/// What the delivered state says. The c11 paste is posted, never read back, so the headline
/// only claims what happened on each path (provisional, awaiting round 5: DESIGN.md's "Delivered
/// to c11" would overclaim).
struct SignalDelivery: Equatable {
    enum Proof: Equatable {
        /// Cmd+V or keystrokes were posted to the app; nothing read the text back.
        case posted
        /// The Accessibility API accepted the text as the field's value.
        case inserted
        /// A read-back found the text in the field.
        case verified
    }

    let appName: String?
    let words: Int
    let proof: Proof

    var headline: String {
        let target = self.appName.map { " \($0)" } ?? ""
        switch self.proof {
        case .posted: return self.appName == nil ? "Sent" : "Sent to\(target)"
        case .inserted: return self.appName == nil ? "Inserted" : "Inserted into\(target)"
        case .verified: return self.appName == nil ? "Delivered" : "Delivered to\(target)"
        }
    }

    var meta: String {
        "\(self.words) \(self.words == 1 ? "word" : "words")"
    }
}

/// The pill's geometry for each overlay size. Medium is DESIGN.md §4 exactly (340 x 149); the
/// other sizes keep the same rows and change only how many preview lines are reserved and the
/// width (provisional: DESIGN.md designs the medium pill only).
struct SignalOverlayGeometry: Equatable {
    let pillWidth: CGFloat
    let previewLines: Int

    static func forSize(_ size: SettingsStore.OverlaySize) -> SignalOverlayGeometry {
        switch size {
        case .pill: SignalOverlayGeometry(pillWidth: SignalTheme.Metrics.pillWidth, previewLines: 0)
        case .small: SignalOverlayGeometry(pillWidth: SignalTheme.Metrics.pillWidth, previewLines: 1)
        case .medium: SignalOverlayGeometry(pillWidth: SignalTheme.Metrics.pillWidth, previewLines: 3)
        case .large: SignalOverlayGeometry(pillWidth: SignalTheme.Metrics.historyWidth, previewLines: 5)
        }
    }

    private var metrics: SignalTheme.Metrics.Type {
        SignalTheme.Metrics.self
    }

    /// The preview area: 3 lines of 18 in medium (54). The delivered statement and the AI
    /// failure row need at least 54, so the area never drops below it once anything shows there.
    var previewHeight: CGFloat {
        CGFloat(self.previewLines) * self.metrics.previewLineHeight
    }

    var showsPreview: Bool {
        self.previewLines > 0
    }

    /// Where the delivered statement goes: the preview area when there is one of at least 54.
    var topAreaHeight: CGFloat {
        self.showsPreview ? max(self.previewHeight, 54) : 0
    }

    var pillHeight: CGFloat {
        let top = self.showsPreview ? self.topAreaHeight + self.metrics.previewGap : 0
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

    /// Bars that fit between the icon and the readout, leaving at least 10 pt either side: 52 in
    /// the 340 pill, as in the prototype (SF Mono's timer box is 47 pt, Menlo's 45).
    var traceBars: Int {
        let available = self.innerWidth - self.metrics.targetIcon - self.readoutWidth - 20
        return SignalTraceModel.barCount(forWidth: available)
    }

    /// Rails are the pill's height and hold three 30 pt slots.
    var railHeight: CGFloat {
        max(self.pillHeight, 3 * self.metrics.chip)
    }
}
