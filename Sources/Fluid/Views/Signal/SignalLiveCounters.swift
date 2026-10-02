import Foundation
import SwiftUI

/// The foot row's live counters (DESIGN.md §16, Atin 2026-10-01): the word count at the left end
/// and words per minute at the right end. The streaming preview lands in bursts; this smooths
/// them. Pure: the view's frame clock drives `advance(to:words:elapsed:snaps:)`.
///
/// - Words step up one at a time toward the true count, each step `stepInterval(remaining:)`
///   after the last (30 to 110 ms: a burst of up to about 15 words plays out in about half a
///   second, a larger one at about 30 ms a word). They never pass the true count and drop at once
///   when it goes down (a revised partial).
/// - WPM eases toward `trueWords x 60 / max(6, elapsed)` with a 0.7 s time constant, so it drifts
///   rather than jumps, and keeps drifting through silence.
/// - `snaps` (Reduce Motion, or a settled pill) shows both targets at once.
struct SignalCounterSmoother: Equatable {
    /// The words box holds 4 digits, WPM 3; both clamp at their box.
    static let wordPlaces = 4
    static let wpmPlaces = 3
    static let maxWords = 9999
    static let maxWPM = 999
    /// The first 6 s of a recording count as 6, so its first burst does not spike WPM.
    static let wpmFloorSeconds: TimeInterval = 6
    static let wpmTimeConstant: TimeInterval = 0.7
    /// A burst plays out over about this long, one word a step, until the 30 ms floor.
    static let burstDuration: TimeInterval = 0.45
    static let shortestStep: TimeInterval = 0.030
    static let longestStep: TimeInterval = 0.110
    /// A frame gap longer than this (a stall, a paused clock) eases as if it were this long.
    static let longestFrame: TimeInterval = 0.1
    /// The first frame's ease, as the prototype's (a 60 Hz frame).
    static let firstFrame: TimeInterval = 0.016

    private(set) var shownWords: Int
    private(set) var shownWPM: Double
    private var lastStep: TimeInterval?
    private var lastFrame: TimeInterval?

    /// Starts at the truth: 0 when a dictation starts, the current count when the pill first
    /// shows a recording already under way.
    init(words: Int = 0, elapsed: TimeInterval = 0) {
        let words = max(0, words)
        self.shownWords = words
        self.shownWPM = words > 0 ? Self.wpmTarget(words: words, elapsed: elapsed) : 0
    }

    static func wpmTarget(words: Int, elapsed: TimeInterval) -> Double {
        Double(max(0, words)) * 60 / max(self.wpmFloorSeconds, elapsed)
    }

    /// The wait before the next word: `max(30, min(110, 450 / remaining))` ms.
    static func stepInterval(remaining: Int) -> TimeInterval {
        max(self.shortestStep, min(self.longestStep, self.burstDuration / Double(max(1, remaining))))
    }

    mutating func advance(to now: TimeInterval, words: Int, elapsed: TimeInterval, snaps: Bool) {
        let words = max(0, words)
        let target = Self.wpmTarget(words: words, elapsed: elapsed)
        let frame = self.lastFrame.map { min(Self.longestFrame, max(0, now - $0)) } ?? Self.firstFrame
        self.lastFrame = now
        if snaps {
            self.shownWords = words
            self.shownWPM = target
            return
        }
        if self.shownWords < words {
            let interval = Self.stepInterval(remaining: words - self.shownWords)
            if self.lastStep.map({ now - $0 >= interval }) ?? true {
                self.shownWords += 1
                self.lastStep = now
            }
        } else {
            self.shownWords = words
        }
        self.shownWPM += (target - self.shownWPM) * (1 - exp(-frame / Self.wpmTimeConstant))
    }

    /// How long the counters still move once the truth is frozen (the stop): the remaining words
    /// at up to 110 ms each, and the ease coming within half a word a minute of its target;
    /// at most `maxSettle`. The view's clock runs this long, then shows the targets.
    func settleDuration(words: Int, elapsed: TimeInterval, maxSettle: TimeInterval = 3) -> TimeInterval {
        let remaining = Double(max(0, words - self.shownWords))
        let gap = abs(Self.wpmTarget(words: words, elapsed: elapsed) - self.shownWPM)
        let ease = gap > 0.5 ? Self.wpmTimeConstant * log(gap / 0.5) : 0
        return min(maxSettle, max(remaining * Self.longestStep, ease))
    }

    var displayedWords: Int {
        min(self.shownWords, Self.maxWords)
    }

    var displayedWPM: Int {
        min(max(0, Int(self.shownWPM.rounded())), Self.maxWPM)
    }

    /// The number right-aligned in its fixed box, unused leading places blank (Atin, 2026-10-01):
    /// `padded(7, places: 4)` is "   7". SF Mono gives a space a digit's advance, so the string
    /// is the same width whatever the number, and the label after it never moves.
    static func padded(_ value: Int, places: Int) -> String {
        let clamped = min(max(0, value), Int(pow(10, Double(places))) - 1)
        let digits = String(clamped)
        return String(repeating: " ", count: places - digits.count) + digits
    }
}

/// What the counters count for one recording; nil hides them.
struct SignalCounterInput: Equatable {
    enum Clock: Equatable {
        /// Recording: elapsed runs from this start.
        case running(Date)
        /// Stopped: the recording's frozen length.
        case frozen(TimeInterval)
    }

    /// The recording these counts belong to: a new one starts the smoother over.
    let recording: Date
    /// The true count: the whole live text while live, frozen at the stop.
    let words: Int
    let clock: Clock

    func elapsed(at date: Date) -> TimeInterval {
        switch self.clock {
        case let .running(start): max(0, date.timeIntervalSince(start))
        case let .frozen(duration): duration
        }
    }

    var isRunning: Bool {
        if case .running = self.clock { return true }
        return false
    }
}

/// Holds the smoother across view updates (a reference, not view state: the frame clock advances
/// it while the view draws, which must not invalidate anything).
@MainActor
final class SignalCounterClock {
    private var recording: Date?
    private(set) var smoother = SignalCounterSmoother()

    func reading(_ input: SignalCounterInput, at date: Date, snaps: Bool) -> (words: Int, wpm: Int) {
        let elapsed = input.elapsed(at: date)
        if input.recording != self.recording {
            self.recording = input.recording
            self.smoother = SignalCounterSmoother(words: input.words, elapsed: elapsed)
        }
        self.smoother.advance(to: date.timeIntervalSinceReferenceDate, words: input.words, elapsed: elapsed, snaps: snaps)
        return (self.smoother.displayedWords, self.smoother.displayedWPM)
    }

    /// How long after the stop the clock must still run for `input` (frozen) to finish moving.
    func settleDuration(_ input: SignalCounterInput) -> TimeInterval {
        guard input.recording == self.recording else { return 0 }
        return self.smoother.settleDuration(words: input.words, elapsed: input.elapsed(at: Date()))
    }
}

/// The counters on the foot row: words at the left end, WPM at the right end (in the placard's
/// slot, which the foot row gives back to SEND / NO SEND whenever the placard has content). Its
/// own frame clock, at most 60 Hz, runs only while the counters show and, after the stop, only
/// until they have finished moving (usually well under a second, at most 3 s); nothing outside
/// this view is invalidated by it, and the face redraws only when a displayed number changes.
struct SignalLiveCounters: View {
    /// Nil: hidden, and the clock paused.
    let input: SignalCounterInput?
    let showsWPM: Bool
    let clock: SignalCounterClock

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// After the stop the counts finish catching up and WPM settles from the frozen length; then
    /// the clock pauses and the face shows the targets.
    @State private var isSettled = false

    var body: some View {
        let isRunning = self.input?.isRunning ?? false
        let settled = !isRunning && self.isSettled
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: self.input == nil || settled)) { context in
            let reading = self.input.map { self.clock.reading($0, at: context.date, snaps: self.reduceMotion || settled) }
            SignalCounterFace(words: reading?.words, wpm: self.showsWPM ? reading?.wpm : nil)
                .equatable()
        }
        .task(id: isRunning) {
            self.isSettled = false
            guard !isRunning else { return }
            let settle = self.input.map { self.clock.settleDuration($0) } ?? 0
            if settle > 0 {
                try? await Task.sleep(for: .seconds(settle))
                guard !Task.isCancelled else { return }
            }
            // Re-evaluates the view, which pauses the clock and shows the targets.
            self.isSettled = true
        }
    }
}

/// The two numbers in their fixed boxes: mono 10 medium, uppercase, tracked, `text-2`; the number
/// right-aligned in its box with blank leading places, the label 6 pt after it (the prototype's
/// 0.6 em). Digits change in place, with no transition.
struct SignalCounterFace: View, Equatable {
    let words: Int?
    let wpm: Int?

    @Environment(\.signalPalette) private var palette

    static let labelGap: CGFloat = 6

    var body: some View {
        HStack(spacing: 0) {
            if let words = self.words {
                self.counter(
                    SignalCounterSmoother.padded(words, places: SignalCounterSmoother.wordPlaces),
                    unit: words == 1 ? "word" : "words",
                    label: "Words",
                    value: "\(words)"
                )
                .help("Words so far")
            }
            Spacer(minLength: 0)
            if let wpm = self.wpm {
                self.counter(
                    SignalCounterSmoother.padded(wpm, places: SignalCounterSmoother.wpmPlaces),
                    unit: "wpm",
                    label: "Words per minute",
                    value: "\(wpm)"
                )
                .help("Words per minute")
            }
        }
    }

    private func counter(_ digits: String, unit: String, label: String, value: String) -> some View {
        let role = SignalTheme.Typography.micLabel
        return HStack(spacing: Self.labelGap) {
            SignalMonoLabel(text: digits, role: role, color: self.palette.text2)
                .fixedSize()
            SignalMonoLabel(text: unit, role: role, color: self.palette.text2)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityAddTraits(.updatesFrequently)
    }

    nonisolated static func == (lhs: SignalCounterFace, rhs: SignalCounterFace) -> Bool {
        lhs.words == rhs.words && lhs.wpm == rhs.wpm
    }
}
