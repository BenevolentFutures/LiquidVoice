import Foundation

/// Times one dictation's start for the log (`START_SUMMARY`, Release info level, one line per
/// start): from the start hotkey to capture running (first PCM), beside how long the pill took
/// to show, whether it came out of its offscreen park, and when its floating shadow followed.
/// Compare starts after an idle park (`overlayWasParked=true`) with quick restarts.
@MainActor
enum StartPathTrace {
    private static var hotkeyAt: TimeInterval?
    private static var requestedAt: TimeInterval?
    private static var trigger = "other"
    private static var overlayVisibleMs: Int?
    private static var overlayWasParked: Bool?
    private static var shadowAfterMs: Int?

    /// A hotkey chose "start" (before its action runs).
    static func hotkeyPressed() {
        self.hotkeyAt = ProcessInfo.processInfo.systemUptime
    }

    /// A dictation start begins. It counts from the hotkey when one was pressed just now.
    static func begin() {
        let now = ProcessInfo.processInfo.systemUptime
        if let hotkeyAt, now - hotkeyAt < 2 {
            self.requestedAt = hotkeyAt
            self.trigger = "hotkey"
        } else {
            self.requestedAt = now
            self.trigger = "other"
        }
        self.hotkeyAt = nil
        self.overlayVisibleMs = nil
        self.overlayWasParked = nil
        self.shadowAfterMs = nil
    }

    /// The pill is on screen (`bottom_visible`): milliseconds inside its show, and whether it was
    /// parked offscreen before it.
    static func overlayShown(visibleMs: Int, wasParked: Bool) {
        self.overlayVisibleMs = visibleMs
        self.overlayWasParked = wasParked
    }

    /// The pill's shadow was ordered in, this long after the show began.
    static func shadowPresented(afterMs: Int) {
        self.shadowAfterMs = afterMs
    }

    /// Capture is running: logs the start once.
    static func captureStarted() {
        guard let requestedAt else { return }
        self.requestedAt = nil
        DebugLogger.shared.info(Self.summary(
            trigger: self.trigger,
            captureMs: Int(((ProcessInfo.processInfo.systemUptime - requestedAt) * 1000).rounded()),
            overlayVisibleMs: self.overlayVisibleMs,
            overlayWasParked: self.overlayWasParked,
            shadowAfterMs: self.shadowAfterMs
        ), source: "StartPath")
    }

    static func summary(trigger: String, captureMs: Int, overlayVisibleMs: Int?, overlayWasParked: Bool?, shadowAfterMs: Int?) -> String {
        "START_SUMMARY trigger=\(trigger) hotkeyToCaptureMs=\(captureMs) " +
            "overlayVisibleMs=\(overlayVisibleMs.map(String.init) ?? "-") " +
            "overlayWasParked=\(overlayWasParked.map { $0 ? "true" : "false" } ?? "-") " +
            "shadowAfterMs=\(shadowAfterMs.map(String.init) ?? "-")"
    }
}
