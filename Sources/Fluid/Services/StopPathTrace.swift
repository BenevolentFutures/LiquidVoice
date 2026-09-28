import Foundation

/// Times one dictation's stop path, from the hotkey release to the paste reaching the target app.
///
/// Local only: the marks go to the app log and nowhere else. Debug builds log every stage as it
/// happens (`STOP_TRACE`); every build logs one `STOP_SUMMARY` line per dictation with the
/// stage-to-stage deltas. `scripts/stop_path_latency.py` turns those lines into median and p90
/// per stage, for the installed app and for the fixture benchmark alike.
///
/// Ownership: `GlobalHotkeyManager` begins a trace when a stop is triggered and stages it with
/// `stagePending`; `ContentView`'s stop path takes it right away, on the same main-actor turn;
/// `ASRService.stop` and the typing worker mark their stages on the object they are handed.
/// Thread-safe: the paste is marked on the typing worker.
nonisolated final class StopPathTrace: @unchecked Sendable {
    enum Stage: String, CaseIterable, Sendable {
        /// The hotkey release (hold), the stopping press (toggle), or the UI action.
        case trigger
        /// The dictation stop pipeline started.
        case stopEnter = "stop_enter"
        /// The microphone stopped and the stop cue fired.
        case captureStopped = "capture_stopped"
        /// The final transcription was handed to the model.
        case asrBegin = "asr_begin"
        /// The model returned.
        case asrEnd = "asr_end"
        /// `ASRService.stop()` returned to the pipeline.
        case asrReturn = "asr_return"
        /// Formatting (and AI post-processing, if on) finished; the text is final.
        case textReady = "text_ready"
        /// The text was handed to the typing service.
        case handoff
        /// The paste (or typed text) was posted to the target app.
        case pastePosted = "paste_posted"
    }

    enum Trigger: String, Sendable {
        case holdRelease = "hold_release"
        case toggle
        case automatic
        case ui
        case benchmark
    }

    /// Stage pairs reported in the summary, in pipeline order. Each delta runs from the
    /// latest earlier mark present, so a skipped stage folds into the next one.
    static let summaryFields: [(name: String, stage: Stage)] = [
        ("releaseMs", .stopEnter),
        ("captureMs", .captureStopped),
        ("drainMs", .asrBegin),
        ("asrMs", .asrEnd),
        ("returnMs", .asrReturn),
        ("postMs", .textReady),
        ("handoffMs", .handoff),
        ("pasteMs", .pastePosted),
    ]

    let id: Int
    let trigger: Trigger
    let latched: Bool

    private let lock = NSLock()
    private var marks: [Stage: TimeInterval] = [:]
    private var details: [String: String] = [:]
    private var isFinished = false
    private var awaitsDelivery = false

    private static let idLock = NSLock()
    private nonisolated(unsafe) static var nextID = 0

    init(trigger: Trigger, at triggerTime: TimeInterval = ProcessInfo.processInfo.systemUptime, latched: Bool = false) {
        self.id = Self.idLock.withLock {
            Self.nextID += 1
            return Self.nextID
        }
        self.trigger = trigger
        self.latched = latched
        self.marks[.trigger] = triggerTime
    }

    // MARK: - Handoff from the hotkey manager to the stop pipeline

    @MainActor private static var pending: StopPathTrace?

    /// Staged by the hotkey manager immediately before it calls the stop pipeline.
    @MainActor
    static func stagePending(_ trace: StopPathTrace) {
        self.pending = trace
    }

    /// The staged trace, or a new one for a stop that did not come from a hotkey.
    @MainActor
    static func takePending(fallback trigger: Trigger = .ui) -> StopPathTrace {
        defer { self.pending = nil }
        return self.pending ?? StopPathTrace(trigger: trigger)
    }

    // MARK: - Marks

    func mark(_ stage: Stage, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let sinceTrigger: Double? = self.lock.withLock {
            guard !self.isFinished, self.marks[stage] == nil else { return nil }
            self.marks[stage] = time
            return self.marks[.trigger].map { (time - $0) * 1000 }
        }
        guard let sinceTrigger, DebugLogger.diagnosticsEnabled else { return }
        DebugLogger.shared.info(
            "STOP_TRACE id=\(self.id) stage=\(stage.rawValue) t=\(String(format: "%.6f", time)) " +
                "sinceTriggerMs=\(String(format: "%.1f", sinceTrigger))",
            source: "StopPath"
        )
    }

    /// Extra key=value fields for the summary (audio length, characters, delivery path).
    func note(_ key: String, _ value: String) {
        self.lock.withLock { self.details[key] = value }
    }

    /// The typing service now owns the end of this trace: it finishes it once the paste is
    /// posted or the delivery fails.
    func expectDelivery() {
        self.lock.withLock { self.awaitsDelivery = true }
    }

    /// Ends the trace unless the typing service owns its end. For the stop pipeline's exits.
    func finishUnlessDelivering(outcome: String) {
        let owned = self.lock.withLock { self.awaitsDelivery }
        guard !owned else { return }
        self.finish(outcome: outcome)
    }

    /// Logs the summary once. Later calls do nothing.
    func finish(outcome: String) {
        let snapshot: (marks: [Stage: TimeInterval], details: [String: String])? = self.lock.withLock {
            guard !self.isFinished else { return nil }
            self.isFinished = true
            return (self.marks, self.details)
        }
        guard let snapshot else { return }
        DebugLogger.shared.info(
            Self.summaryLine(
                id: self.id,
                trigger: self.trigger,
                latched: self.latched,
                marks: snapshot.marks,
                details: snapshot.details,
                outcome: outcome
            ),
            source: "StopPath"
        )
    }

    /// Milliseconds between two recorded stages, if both are present. For tests.
    func elapsedMilliseconds(from start: Stage, to end: Stage) -> Double? {
        self.lock.withLock {
            guard let startTime = self.marks[start], let endTime = self.marks[end] else { return nil }
            return (endTime - startTime) * 1000
        }
    }

    static func summaryLine(
        id: Int,
        trigger: Trigger,
        latched: Bool,
        marks: [Stage: TimeInterval],
        details: [String: String],
        outcome: String
    ) -> String {
        var fields = ["STOP_SUMMARY id=\(id)", "trigger=\(trigger.rawValue)", "latched=\(latched)"]
        var previous = marks[.trigger]
        for field in self.summaryFields {
            guard let time = marks[field.stage] else {
                fields.append("\(field.name)=-")
                continue
            }
            if let start = previous {
                fields.append("\(field.name)=\(Self.format((time - start) * 1000))")
            } else {
                fields.append("\(field.name)=-")
            }
            previous = time
        }
        let last = Stage.allCases.reversed().compactMap { marks[$0] }.first
        if let start = marks[.trigger], let last {
            fields.append("totalMs=\(Self.format((last - start) * 1000))")
        } else {
            fields.append("totalMs=-")
        }
        let lastStage = Stage.allCases.reversed().first { marks[$0] != nil }
        fields.append("lastStage=\(lastStage?.rawValue ?? "none")")
        for key in details.keys.sorted() {
            fields.append("\(key)=\(details[key] ?? "")")
        }
        fields.append("outcome=\(outcome)")
        return fields.joined(separator: " ")
    }

    private static func format(_ milliseconds: Double) -> String {
        String(format: "%.1f", milliseconds)
    }
}

#if DEBUG
/// Debug builds only: for a couple of seconds after a stop, logs every main run loop stretch
/// longer than 8 ms that was not spent waiting (`STOP_TRACE ... mainBusyMs=`), so the trace shows
/// what held the main thread. After altic-dev/FluidVoice@094b8d0e's run loop probe.
@MainActor
enum MainRunLoopProbe {
    private static var observer: CFRunLoopObserver?

    static func watch(traceID: Int, seconds: TimeInterval = 2) {
        guard self.observer == nil else { return }
        final class State: @unchecked Sendable {
            var previousAt = ProcessInfo.processInfo.systemUptime
            var previousActivity = CFRunLoopActivity.beforeWaiting.rawValue
        }
        let state = State()
        guard let observer = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.allActivities.rawValue, true, 0, { _, activity in
                let now = ProcessInfo.processInfo.systemUptime
                let busyMs = (now - state.previousAt) * 1000
                if state.previousActivity != CFRunLoopActivity.beforeWaiting.rawValue, busyMs > 8 {
                    DebugLogger.shared.info(
                        "STOP_TRACE id=\(traceID) mainBusyMs=\(String(format: "%.1f", busyMs)) " +
                            "from=\(String(format: "%.6f", state.previousAt)) " +
                            "phases=\(state.previousActivity)->\(activity.rawValue)",
                        source: "StopPath"
                    )
                }
                state.previousAt = now
                state.previousActivity = activity.rawValue
            }
        ) else { return }
        self.observer = observer
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
            self.observer = nil
        }
    }
}

/// Debug builds only: drives one fixture dictation through the real stop pipeline so its
/// stages can be timed headlessly (`StopPathLatencyBenchmarkTests`). The capture is synthetic
/// (`ASRService.beginSyntheticCaptureForBenchmark`), and the run stops at the handoff to the
/// typing service: it never touches the clipboard, restores focus, or types into another app,
/// and in the XCTest host (TestHostQuietMode) nothing it does is visible or audible.
@MainActor
enum StopPathBenchmark {
    /// Registered by `ContentView` when it appears. Returns the finished trace, or nil when a
    /// recording is already active.
    static var runDictation: ((_ samples: [Float], _ recordingSeconds: Double) async -> StopPathTrace?)?

    /// The app name benchmark dictations are recorded under, so their history entries can be
    /// found and removed.
    static let appName = "StopPathBenchmark"
}
#endif
