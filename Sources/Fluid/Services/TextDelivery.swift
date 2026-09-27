import Foundation

// Ported from altic-dev/FluidVoice@b0d64436 (Migrate to clipboard paste) by grohith327,
// with the user-facing wording of @d5cc5090 / @ff92b4b8 / @9c25e758 by altic-dev.
//
// The outcome of one attempt to put text where the user is typing. Every failure except an
// empty transcript is shown to the user: the transcript is kept on the clipboard and in
// history, and the failure card offers Copy. Nothing is dropped silently.

nonisolated enum TextDeliveryFailure: String, Equatable, CaseIterable, Sendable {
    case emptyText = "empty_text"
    case accessibilityNotTrusted = "accessibility_not_trusted"
    case clipboardSnapshotFailed = "clipboard_snapshot_failed"
    case clipboardWriteFailed = "clipboard_write_failed"
    case pasteCommandFailed = "paste_command_failed"
    case targetUnavailable = "target_unavailable"
    case targetRestoreFailed = "target_restore_failed"
    case noEditableTarget = "no_editable_target"
    case pasteNotLanded = "paste_not_landed"

    /// Title of the failure card. `nil` only for an empty transcript, which has nothing to show.
    var userFacingTitle: String? {
        switch self {
        case .emptyText:
            nil
        case .accessibilityNotTrusted:
            "Enable Accessibility to insert text"
        case .noEditableTarget:
            "No text field focused"
        case .pasteNotLanded, .clipboardSnapshotFailed, .clipboardWriteFailed,
             .pasteCommandFailed, .targetUnavailable, .targetRestoreFailed:
            "Text wasn't inserted"
        }
    }

    /// Whether the failure card should show at all.
    var isUserVisible: Bool {
        self.userFacingTitle != nil
    }
}

nonisolated enum TextDeliveryResult: Equatable, Sendable {
    /// The insertion was dispatched (keystrokes posted or Cmd+V sent). Landing is not
    /// guaranteed; the opt-in paste check reports a verified miss separately.
    case dispatched
    case recoverableFailure(TextDeliveryFailure)

    var wasDispatched: Bool {
        self == .dispatched
    }
}

/// Logging for delivery code that runs off the main actor. `DebugLogger` is main-actor
/// isolated in this target, so the line is timestamped here, at the call, and handed to it.
nonisolated enum DeliveryLog {
    static func bench(_ message: String) {
        let now = ProcessInfo.processInfo.systemUptime
        let line = "TYPING_BENCH t=\(String(format: "%.6f", now)) \(message)"
        DispatchQueue.main.async {
            DebugLogger.shared.info(line, source: "TypingBenchmark")
        }
    }

    static func warning(_ message: String, source: String = "TypingService") {
        DispatchQueue.main.async {
            DebugLogger.shared.warning(message, source: source)
        }
    }

    static func info(_ message: String, source: String = "TypingService") {
        DispatchQueue.main.async {
            DebugLogger.shared.info(message, source: source)
        }
    }
}

/// What the failure card shows: the failure, the transcript, and whether the transcript is on
/// the clipboard (it is not when the user copied something newer in the meantime).
nonisolated struct DeliveryFailureReport: Equatable, Sendable {
    let failure: TextDeliveryFailure
    let transcript: String
    let keptOnClipboard: Bool
}
