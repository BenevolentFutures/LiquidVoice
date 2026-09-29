import Foundation

/// Times one dictation's start for the log (`START_SUMMARY`, Release info level, one line per
/// capture start): from the start hotkey (or, without one, from `ASRService.start`) to capture
/// running (first PCM), beside how long the pill took to show, whether it came out of its offscreen
/// park, and when its floating shadow followed. Compare starts after an idle park
/// (`overlayWasParked=true`) with quick restarts.
///
/// The marks sit where every start passes: the hotkey's start action (GlobalHotkeyManager), the
/// overlay's show, and `ASRService.start` itself (its entry and its first PCM). They were first put
/// in `ContentView.startRecording()`, which the hotkey's dictation path does not call (it goes
/// through `beginDictationRecording`), so the installed build never logged a line.
@MainActor
enum StartPathTrace {
    private static var requestedAt: TimeInterval?
    private static var trigger = "other"
    private static var overlayShownAt: TimeInterval?
    private static var overlayVisibleMs: Int?
    private static var overlayWasParked: Bool?
    private static var shadowAfterMs: Int?

    /// Where the line goes. Tests collect it instead.
    static var emit: (String) -> Void = { line in
        DebugLogger.shared.info(line, source: "StartPath")
    }

    /// A hotkey chose "start" (before its action runs): the start counts from here.
    static func hotkeyPressed(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.requestedAt = now
        self.trigger = "hotkey"
        self.overlayShownAt = nil
        self.overlayVisibleMs = nil
        self.overlayWasParked = nil
        self.shadowAfterMs = nil
    }

    /// `ASRService.start` begins. With no hotkey just before it, the start counts from here, and a
    /// pill shown for it in the second before still counts.
    static func captureRequested(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if let requestedAt, now - requestedAt < 2 { return }
        self.requestedAt = now
        self.trigger = "other"
        if let shownAt = self.overlayShownAt, now - shownAt > 1 {
            self.overlayShownAt = nil
            self.overlayVisibleMs = nil
            self.overlayWasParked = nil
            self.shadowAfterMs = nil
        }
    }

    /// The pill is on screen (`bottom_visible`): milliseconds inside its show, and whether it was
    /// parked offscreen before it.
    static func overlayShown(visibleMs: Int, wasParked: Bool) {
        self.overlayShownAt = ProcessInfo.processInfo.systemUptime
        self.overlayVisibleMs = visibleMs
        self.overlayWasParked = wasParked
        self.shadowAfterMs = nil
    }

    /// The pill's shadow was ordered in, this long after the show began.
    static func shadowPresented(afterMs: Int) {
        self.shadowAfterMs = afterMs
    }

    /// Capture is running (first PCM): logs the start, once.
    static func captureStarted(at now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard let requestedAt else { return }
        self.requestedAt = nil
        self.emit(Self.summary(
            trigger: self.trigger,
            captureMs: Int(((now - requestedAt) * 1000).rounded()),
            overlayVisibleMs: self.overlayVisibleMs,
            overlayWasParked: self.overlayWasParked,
            shadowAfterMs: self.shadowAfterMs
        ))
    }

    static func summary(trigger: String, captureMs: Int, overlayVisibleMs: Int?, overlayWasParked: Bool?, shadowAfterMs: Int?) -> String {
        "START_SUMMARY trigger=\(trigger) hotkeyToCaptureMs=\(captureMs) " +
            "overlayVisibleMs=\(overlayVisibleMs.map(String.init) ?? "-") " +
            "overlayWasParked=\(overlayWasParked.map { $0 ? "true" : "false" } ?? "-") " +
            "shadowAfterMs=\(shadowAfterMs.map(String.init) ?? "-")"
    }
}
