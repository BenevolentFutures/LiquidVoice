import ApplicationServices
import Foundation

// Ported from altic-dev/FluidVoice@5a67d658 (snapshot target and route at stop) and
// @adf0216e (make starting-field restoration optional) by altic-dev.
//
// Liquid Voice already fixes the formatting context and AI route at recording start
// (`recordingAppInfo`), so only the typing destination is frozen here. Upstream's route,
// prompt and overlay-label freezing depend on its Fluid Intelligence routing and are not
// ported.

/// A text destination captured from Accessibility: the app, its window and the focused
/// element. Window and element are nil when Accessibility could not read them.
nonisolated struct DictationTarget: @unchecked Sendable {
    let pid: pid_t
    let bundleIdentifier: String?
    let window: AXUIElement?
    let element: AXUIElement?
}

/// Where a finished dictation lands.
nonisolated enum DictationTargetPolicy {
    /// Chooses the destination when dictation stops, before transcription finishes, so
    /// switching apps while it completes cannot redirect the text.
    ///
    /// - The field focused at stop wins by default: dictation follows the cursor.
    /// - "Return to Starting Field" (off by default) sends it back to where recording began.
    /// - When Liquid Voice's own UI holds focus at stop (the overlay or a panel), the text
    ///   goes back to where recording began rather than into Liquid Voice.
    static func selectStopTarget(
        current: DictationTarget?,
        original: DictationTarget?,
        returnToStartingField: Bool,
        ownPID: pid_t
    ) -> DictationTarget? {
        if returnToStartingField, let original { return original }
        guard let current, current.pid > 0, current.pid != ownPID else {
            return original ?? current
        }
        return current
    }
}
