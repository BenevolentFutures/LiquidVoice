import CoreGraphics
import Foundation

/// The voice trace's samples (DESIGN.md §4, §8). Levels arrive about 94 times a second; the trace
/// keeps the peak of each 83.3 ms window and pushes one bar per window, 12 a second, so 39 bars
/// hold 3.25 s. It keeps scrolling through silence at 2 pt. Each push morphs every slot to its
/// right neighbour's height over 60 ms, snapped to 2 pt steps.
///
/// Heights are calibrated to the recording itself: a level draws by how far it rises above this
/// recording's quiet floor, scaled to its loud peak. A fixed gate (level 0.4, about -33 dBFS)
/// left a quiet microphone's speech at the 2 pt floor for whole dictations (Atin's fifine USB
/// microphone, 2026-09-29), while the frame clock, sampler and feed all ran.
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

    private(set) var previous: [CGFloat]
    private(set) var current: [CGFloat]
    private(set) var lastPush: TimeInterval = 0
    /// True while recording: the newest bars are the orange write head.
    private(set) var isLive = false
    private var windowStart: TimeInterval = 0
    private var windowPeak: CGFloat = 0
    private var grainTick = 0
    var reducesMotion = false

    /// The recording's quiet floor: the quietest recent window, falling at once and rising slowly,
    /// so a steady background settles under the gate. Levels are linear in dB, 55 dB per unit.
    private(set) var quietFloor: CGFloat?
    /// The recording's loud peak: the loudest recent window, rising at once and falling slowly.
    private(set) var loudPeak: CGFloat = 0
    /// What this recording drew, for the stop's TRACE_SUMMARY log line.
    private(set) var stats = Stats()

    struct Stats: Equatable {
        /// Windows pushed while live.
        var windows = 0
        /// Windows drawn above the 2 pt floor.
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

    init(barCount: Int = 39, noiseThreshold: CGFloat = 0.4) {
        self.barCount = barCount
        self.noiseThreshold = noiseThreshold
        self.previous = Array(repeating: Self.floor, count: barCount)
        self.current = Array(repeating: Self.floor, count: barCount)
    }

    /// A new recording: a flat trace, live from `now`.
    func begin(at now: TimeInterval) {
        self.previous = Array(repeating: Self.floor, count: self.barCount)
        self.current = self.previous
        self.lastPush = now
        self.windowStart = now
        self.windowPeak = 0
        self.grainTick = 0
        self.quietFloor = nil
        self.loudPeak = 0
        self.stats = Stats()
        self.isLive = true
    }

    /// One audio level (0...1). Only its window's peak survives.
    func ingest(level: CGFloat, at now: TimeInterval) {
        guard self.isLive else { return }
        self.windowPeak = max(self.windowPeak, min(max(level, 0), 1))
        self.advance(to: now)
    }

    /// Pushes one bar per elapsed sample window, including silent ones. Called on every level and
    /// on every frame while live. After a stall (a hidden or busy frame clock) it pushes at most
    /// one trace's worth, so it never loops long.
    func advance(to now: TimeInterval) {
        guard self.isLive else { return }
        let sample = SignalTheme.Motion.traceSample
        var pushes = 0
        while now - self.windowStart >= sample, pushes < self.barCount {
            self.calibrate(with: self.windowPeak)
            let height = self.height(for: self.windowPeak)
            self.stats.windows += 1
            self.stats.loudest = max(self.stats.loudest, self.windowPeak)
            if Self.snapped(height) > Self.floor { self.stats.raised += 1 }
            self.push(height, at: now)
            self.windowPeak = 0
            self.windowStart += sample
            pushes += 1
        }
        if now - self.windowStart >= sample {
            self.windowStart = now
        }
    }

    /// The recording stopped: every bar goes to 2 pt over 60 ms and the write head goes ink.
    func stop(at now: TimeInterval) {
        guard self.isLive else { return }
        for index in 0..<self.barCount {
            self.previous[index] = self.shownHeight(at: index, now: now)
        }
        self.current = Array(repeating: Self.floor, count: self.barCount)
        self.lastPush = now
        self.isLive = false
    }

    /// A flat, idle trace (a card's trace row, or the hidden overlay).
    func flatten() {
        self.previous = Array(repeating: Self.floor, count: self.barCount)
        self.current = self.previous
        self.isLive = false
    }

    /// Whether a morph is still running at `now` (the frame clock may pause after it).
    func isMorphing(at now: TimeInterval) -> Bool {
        !self.reducesMotion && now - self.lastPush < SignalTheme.Motion.barMorph
    }

    /// The height to draw for slot `index` (0 = oldest): the morph between the last two pushes,
    /// snapped to even whole points so every bar is symmetric about the midline.
    func shownHeight(at index: Int, now: TimeInterval) -> CGFloat {
        let fraction = self.reducesMotion ? 1 : min(1, max(0, (now - self.lastPush) / SignalTheme.Motion.barMorph))
        let raw = self.previous[index] + (self.current[index] - self.previous[index]) * CGFloat(fraction)
        return Self.snapped(raw)
    }

    static func snapped(_ height: CGFloat) -> CGFloat {
        max(self.floor, (height / 2).rounded() * 2)
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

    private func push(_ height: CGFloat, at now: TimeInterval) {
        for index in 0..<self.barCount {
            self.previous[index] = self.shownHeight(at: index, now: now)
        }
        self.current.removeFirst()
        self.current.append(height)
        self.lastPush = now
    }

    /// The four printed opacity steps by age (0 = newest), as fractions of the trace so a shorter
    /// trace keeps the same proportions (round 5: 39 bars).
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
