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

/// Logging for delivery code that runs off the main actor. `DebugLogger` is callable from any
/// thread, so lines go straight to it: nothing hops to the main thread mid-paste.
nonisolated enum DeliveryLog {
    /// A delivery timing line. Debug builds only, like every benchmark line.
    static func bench(_ message: @autoclosure () -> String) {
        DebugLogger.shared.benchmark("TYPING_BENCH", message: message(), source: "TypingBenchmark")
    }

    static func warning(_ message: String, source: String = "TypingService") {
        DebugLogger.shared.warning(message, source: source)
    }

    static func info(_ message: String, source: String = "TypingService") {
        DebugLogger.shared.info(message, source: source)
    }
}

/// What happened when a transcript was put on the clipboard after a failed delivery.
nonisolated enum TranscriptBackupOutcome: String, Equatable, Sendable {
    case copied
    case alreadyOnClipboard = "already_on_clipboard"
    case emptyText = "empty_text"
    /// The user copied something after the failure; that copy is never replaced.
    case newerClipboardCopy = "newer_clipboard_copy"
    case writeFailed = "write_failed"

    var isOnClipboard: Bool {
        self == .copied || self == .alreadyOnClipboard
    }
}

/// What the failure card shows: the failure, the transcript, where the transcript is now.
nonisolated struct DeliveryFailureReport: Equatable, Sendable {
    let failure: TextDeliveryFailure
    let transcript: String
    let clipboard: TranscriptBackupOutcome
    /// The transcript is in transcription history (dictation with history on, paste-last).
    /// Rewrite output and debug deliveries are not.
    let inHistory: Bool
}
