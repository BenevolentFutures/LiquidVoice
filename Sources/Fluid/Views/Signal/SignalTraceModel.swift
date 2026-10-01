import CoreGraphics
import Foundation

/// The voice trace's samples (DESIGN.md §4, §8). Levels arrive about 94 times a second.
///
/// Motion (Atin, 2026-09-29): the trace advances only while the voice is on, and smoothly.
/// - Voice-gated: a level above the gate (the calibrated quiet floor plus the Sensitivity share)
///   marks the voice on, and it stays on for a 250 ms hangover, so the trace does not stutter
///   between words. Only then does the advance clock run; in silence the trace holds still.
/// - Continuous: the advance clock pushes one bar every 83.3 ms (12 a second; round 6's 63 bars hold 5.25 s
///   of speech), and between pushes every bar slides left by the elapsed fraction of the 4 pt
///   pitch (`scrollFraction`), driven by the frame clock, instead of jumping a pitch at once.
/// - Eased: each drawn bar eases toward its target height (about 135 ms to settle), unsnapped;
///   the view snaps edges to device pixels, so bars stay square-ended and crisp.
/// The stop is as before: every bar to 2 pt over 60 ms, linear, and nothing moves after.
///
/// Heights are calibrated to the recording itself: a level draws by how far it rises above this
/// recording's quiet floor, scaled to its loud peak. A fixed gate (level 0.4, about -33 dBFS)
/// left a quiet microphone's speech at the 2 pt floor for whole dictations (Atin's fifine USB
/// microphone, 2026-09-29), while the frame clock, sampler and feed all ran. The floor and peak
/// follow real-time 83.3 ms windows whether or not the trace advances.
///
/// A plain reference type, not observed by SwiftUI: a level tick costs no view invalidation. The
/// trace's Canvas reads it from a `TimelineView` and drives `advance(to:)` from its frame clock.
/// Main actor only. Times are seconds since the reference date.
@MainActor
final class SignalTraceModel {
    let barCount: Int
    /// Settings > Visualizer > Sensitivity (0.01 "More" to 0.8 "Less", 0.4 by default): how far
    /// above the recording's quiet floor a level must rise to draw, `sensitivitySpan` at 1.0.
    var noiseThreshold: CGFloat

    /// Each bar's target height, oldest first (the menu bar mark reads these).
    private(set) var current: [CGFloat]
    /// Each bar's drawn height, easing toward `current`.
    private(set) var shown: [CGFloat]
    /// When the last bar was pushed (real time), and how many were pushed this recording.
    private(set) var lastPush: TimeInterval = 0
    private(set) var pushes = 0
    /// True while recording: the newest bars are the orange write head.
    private(set) var isLive = false
    /// The last level above the gate: the voice is on until `voiceHangover` after it.
    private(set) var lastVoice: TimeInterval?
    /// Seconds the trace has advanced (the clock runs only while the voice is on), and where it
    /// stood at the last push.
    private var advanced: TimeInterval = 0
    private var advancedAtPush: TimeInterval = 0
    private var lastFrame: TimeInterval = 0
    /// The loudest level since the last push: the next bar's height.
    private var pendingPeak: CGFloat = 0
    /// The real-time calibration window.
    private var windowStart: TimeInterval = 0
    private var windowPeak: CGFloat = 0
    private var grainTick = 0
    var reducesMotion = false
    /// The stop: when, and the drawn heights and scroll it started from.
    private var stoppedAt: TimeInterval?
    private var stopFrom: [CGFloat]
    private var stoppedFraction: CGFloat = 0

    /// The recording's quiet floor: the quietest recent window, falling at once and rising slowly,
    /// so a steady background settles under the gate. Levels are linear in dB, 55 dB per unit.
    private(set) var quietFloor: CGFloat?
    /// The recording's loud peak: the loudest recent window, rising at once and falling slowly.
    private(set) var loudPeak: CGFloat = 0
    /// What this recording drew, for the stop's TRACE_SUMMARY log line.
    private(set) var stats = Stats()

    struct Stats: Equatable {
        /// Real-time 83.3 ms windows while live.
        var windows = 0
        /// Windows whose peak cleared the gate (voice).
        var voiced = 0
        /// Bars pushed (the trace advanced).
        var pushed = 0
        /// Bars pushed above the 2 pt floor.
        var raised = 0
        /// The loudest window peak.
        var loudest: CGFloat = 0
    }

    /// The gate at Sensitivity 1.0: 15 dB, so the default 0.4 asks for 6 dB above the floor.
    static let sensitivitySpan: CGFloat = 15.0 / 55.0
    /// The loud peak stays at least this far above the gate (11 dB): room noise never fills the trace.
    static let minimumSpan: CGFloat = 0.2
    /// How fast the floor rises toward a louder steady background: 1.65 dB a second.
    static let floorRise: CGFloat = 0.03
    /// How fast the peak falls after loud speech: 1.1 dB a second.
    static let peakFall: CGFloat = 0.02

    static let floor = SignalTheme.Metrics.minBarHeight
    static let ceiling = SignalTheme.Metrics.maxBarHeight

    init(barCount: Int = 63, noiseThreshold: CGFloat = 0.4) {
        self.barCount = barCount
        self.noiseThreshold = noiseThreshold
        self.current = Array(repeating: Self.floor, count: barCount)
        self.shown = self.current
        self.stopFrom = self.current
    }

    /// A new recording: a flat trace, live from `now`, holding still until the voice comes on.
    func begin(at now: TimeInterval) {
        self.current = Array(repeating: Self.floor, count: self.barCount)
        self.shown = self.current
        self.lastPush = now
        self.pushes = 0
        self.lastVoice = nil
        self.advanced = 0
        self.advancedAtPush = 0
        self.lastFrame = now
        self.pendingPeak = 0
        self.windowStart = now
        self.windowPeak = 0
        self.grainTick = 0
        self.stoppedAt = nil
        self.stoppedFraction = 0
        self.quietFloor = nil
        self.loudPeak = 0
        self.stats = Stats()
        self.isLive = true
    }

    /// One audio level (0...1): feeds the calibration window and the next bar, and turns the voice
    /// on when it clears the gate.
    func ingest(level: CGFloat, at now: TimeInterval) {
        guard self.isLive else { return }
        let level = min(max(level, 0), 1)
        self.windowPeak = max(self.windowPeak, level)
        self.pendingPeak = max(self.pendingPeak, level)
        if level > self.gate {
            self.lastVoice = now
        }
        self.advance(to: now)
    }

    /// Whether the voice is on at `now`: a level cleared the gate within the hangover.
    func isVoiceActive(at now: TimeInterval) -> Bool {
        guard let lastVoice else { return false }
        return now - lastVoice <= SignalTheme.Motion.voiceHangover
    }

    /// Called on every level and every frame while live: closes real-time calibration windows,
    /// runs the advance clock while the voice is on (one bar per 83.3 ms of it), and eases the
    /// drawn heights. After a stall (a hidden or busy frame clock) it moves at most a quarter
    /// second and pushes at most one trace's worth, so it never loops long or leaps.
    func advance(to now: TimeInterval) {
        guard self.isLive else { return }
        let sample = SignalTheme.Motion.traceSample
        let dt = min(max(now - self.lastFrame, 0), 0.25)
        self.lastFrame = max(self.lastFrame, now)

        var windows = 0
        while now - self.windowStart >= sample, windows < self.barCount {
            self.calibrate(with: self.windowPeak)
            self.stats.windows += 1
            self.stats.loudest = max(self.stats.loudest, self.windowPeak)
            if self.windowPeak > self.gate { self.stats.voiced += 1 }
            self.windowPeak = 0
            self.windowStart += sample
            windows += 1
        }
        if now - self.windowStart >= sample {
            self.windowStart = now
        }

        if self.isVoiceActive(at: now) {
            self.advanced += dt
            var pushed = 0
            while self.advanced - self.advancedAtPush >= sample, pushed < self.barCount {
                self.push(self.height(for: self.pendingPeak), at: now)
                self.pendingPeak = 0
                self.advancedAtPush += sample
                pushed += 1
            }
            if self.advanced - self.advancedAtPush >= sample {
                self.advancedAtPush = self.advanced
            }
        }

        let ease = self.reducesMotion ? 1 : 1 - CGFloat(exp(-dt / (SignalTheme.Motion.barEase / 3)))
        for index in 0..<self.barCount {
            self.shown[index] += (self.current[index] - self.shown[index]) * ease
        }
    }

    /// How far the bars have slid toward the next slot, 0..<1 of the pitch: the advance clock's
    /// progress through the current sample. Held in silence; 0 under reduced motion.
    var scrollFraction: CGFloat {
        if self.stoppedAt != nil { return self.stoppedFraction }
        guard !self.reducesMotion else { return 0 }
        let sample = SignalTheme.Motion.traceSample
        return CGFloat(min(max((self.advanced - self.advancedAtPush) / sample, 0), 0.999))
    }

    /// The recording stopped: every bar goes to 2 pt over 60 ms, linear, the write head goes ink,
    /// and nothing moves after (the stop path's cost is as before).
    func stop(at now: TimeInterval) {
        guard self.isLive else { return }
        self.stoppedFraction = self.scrollFraction
        self.stopFrom = self.shown
        self.stoppedAt = now
        self.current = Array(repeating: Self.floor, count: self.barCount)
        self.isLive = false
    }

    /// A flat, idle trace (a card's trace row, or the hidden overlay).
    func flatten() {
        self.current = Array(repeating: Self.floor, count: self.barCount)
        self.shown = self.current
        self.stoppedAt = nil
        self.stoppedFraction = 0
        self.advanced = 0
        self.advancedAtPush = 0
        self.isLive = false
    }

    /// The height to draw for slot `index` (0 = oldest): the eased height while live; after a
    /// stop, the 60 ms linear run down to the floor.
    func shownHeight(at index: Int, now: TimeInterval) -> CGFloat {
        guard let stoppedAt else { return max(Self.floor, self.shown[index]) }
        let progress = self.reducesMotion ? 1 : min(1, max(0, (now - stoppedAt) / SignalTheme.Motion.stopToFlat))
        return self.stopFrom[index] + (Self.floor - self.stopFrom[index]) * CGFloat(progress)
    }

    /// The level that draws above the floor: the quiet floor plus the Sensitivity setting's share.
    var gate: CGFloat {
        (self.quietFloor ?? 0) + max(self.noiseThreshold, 0) * Self.sensitivitySpan
    }

    /// Follows one window's peak: the floor falls to a quieter window at once and rises 1.65 dB/s;
    /// the peak rises to a louder window at once, falls 1.1 dB/s, and keeps 11 dB above the gate.
    func calibrate(with level: CGFloat) {
        let sample = CGFloat(SignalTheme.Motion.traceSample)
        let level = min(max(level, 0), 1)
        if let floor = self.quietFloor {
            self.quietFloor = level < floor ? level : min(level, floor + Self.floorRise * sample)
        } else {
            self.quietFloor = level
        }
        self.loudPeak = max(level, self.loudPeak - Self.peakFall * sample, self.gate + Self.minimumSpan)
    }

    /// The prototype's level curve on the calibrated range: above the gate, scaled to the loud
    /// peak, a slightly super-linear rise (speech stretches tall while a steady background stays
    /// low), and the grain of two incommensurate cosines so neighbouring samples differ without
    /// looking periodic.
    func height(for level: CGFloat) -> CGFloat {
        let gate = self.gate
        let denominator = max(self.loudPeak - gate, 0.001)
        let adjusted = min(max((level - gate) / denominator, 0), 1)
        let amplitude = pow(adjusted, 1.15)
        let phase = CGFloat(self.grainTick)
        let grain = 0.6 + 0.25 * cos(1.7 * phase) + 0.15 * cos(4.3 * phase)
        self.grainTick = (self.grainTick + 1) % 1024
        let span = Self.ceiling - Self.floor
        return min(Self.ceiling, max(Self.floor, Self.floor + span * amplitude * grain))
    }

    /// One bar in at the right: every slot takes its right neighbour's target and drawn height (the
    /// scroll offset returns to 0 at the same moment, so nothing jumps) and the new bar grows from
    /// the floor.
    private func push(_ height: CGFloat, at now: TimeInterval) {
        self.current.removeFirst()
        self.current.append(height)
        self.shown.removeFirst()
        self.shown.append(Self.floor)
        self.lastPush = now
        self.pushes += 1
        self.stats.pushed += 1
        if height >= Self.floor + 1 { self.stats.raised += 1 }
    }

    /// The four printed opacity steps by age (0 = newest), as fractions of the trace so a shorter
    /// trace keeps the same proportions (round 6: 63 bars in the medium pill).
    static func bandOpacity(age: Int, of count: Int) -> Double {
        let fraction = Double(age) / Double(max(count, 1))
        switch fraction {
        case ..<0.34: return 1
        case ..<0.56: return 0.7
        case ..<0.77: return 0.45
        default: return 0.25
        }
    }

    /// Bars that fit a trace of `width` on the 4 pt pitch (2 pt bars, 2 pt gaps).
    static func barCount(forWidth width: CGFloat) -> Int {
        max(1, Int(((width + 2) / SignalTheme.Metrics.barPitch).rounded(.down)))
    }

    static func width(forBars bars: Int) -> CGFloat {
        CGFloat(bars) * SignalTheme.Metrics.barPitch - (SignalTheme.Metrics.barPitch - SignalTheme.Metrics.barWidth)
    }
}
