import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

final class TypingService {
    // Logging toggle (off by default). Enable by setting env FLUID_TYPING_LOGS=1
    // or UserDefaults bool for key "enableTypingLogs".
    private static var isLoggingEnabled: Bool {
        if let env = ProcessInfo.processInfo.environment["FLUID_TYPING_LOGS"], env == "1" { return true }
        return UserDefaults.standard.bool(forKey: "enableTypingLogs")
    }

    private func log(_ message: @autoclosure () -> String) {
        guard TypingService.isLoggingEnabled else { return }
        DebugLogger.shared.debug(message(), source: "TypingService")
    }

    /// Serial worker for insertions. Consecutive dictations queue here instead of being
    /// dropped: the old `isCurrentlyTyping` guard silently discarded any dictation that
    /// arrived while a previous insertion (or its pasteboard-restore session) was still
    /// in flight — user speech vanished with only an "already_typing" bench line.
    private static let typingWorkQueue = DispatchQueue(label: "TypingService.Work", qos: .userInitiated)
    private let pendingCountLock = NSLock()
    private var pendingInsertions = 0

    /// Owns the pasteboard for clipboard pastes and transcript backups. Tests pass a session
    /// on a private pasteboard so they never touch the user's clipboard.
    private let pasteSession: ClipboardPasteSession

    /// Set by `deliver` while a Spoken Send key follows the delivery in progress. Touched only
    /// on the serial typing worker.
    private var sendKeyFollowsCurrentDelivery = false

    init(pasteSession: ClipboardPasteSession = .shared) {
        self.pasteSession = pasteSession
    }

    private struct FocusSnapshot {
        let pid: pid_t
        let window: AXUIElement?
        let element: AXUIElement?
    }

    private struct FocusedTextSnapshot {
        let pid: pid_t
        let bundleIdentifier: String?
        let value: String?
        let selectedRange: CFRange?
        let appScriptValue: String?
        let appScriptSelectedRange: CFRange?
    }

    private enum PasteVerificationResult: String {
        case appScriptContainsText = "appscript_contains_text"
        case appScriptCaretMovedExpectedDistance = "appscript_caret_moved_expected_distance"
        case fieldContainsText = "field_contains_text"
        case caretMovedExpectedDistance = "caret_moved_expected_distance"
        case timeout
        case unavailable
    }

    private static let focusSnapshotQueue = DispatchQueue(label: "TypingService.FocusSnapshot")
    private static var focusSnapshot: FocusSnapshot?
    /// Terminals built on Ghostty's input stack, where direct CGEvent unicode insertion is
    /// unreliable and the Reliable Paste path must be forced. c11 (Stage 11's multiplexer)
    /// is a Ghostty derivative with its own bundle IDs (see `isC11`), so it needs the same
    /// carve-out.
    nonisolated static let ghosttyFamilyBundleIdentifiers: Set<String> = [
        "com.mitchellh.ghostty",
        "com.stage11.c11",
    ]

    nonisolated static func isGhosttyFamily(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return self.ghosttyFamilyBundleIdentifiers.contains(bundleIdentifier) || self.isC11(bundleIdentifier: bundleIdentifier)
    }

    /// c11 in any of its builds: `com.stage11.c11`, its variants (`com.stage11.c11.debug`), and
    /// the legacy `com.stage11.c11mux`. The one c11 predicate, for the paste path and for
    /// Spoken Send's policy alike.
    nonisolated static func isC11(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return ["com.stage11.c11", "com.stage11.c11mux"].contains { base in
            bundleIdentifier == base || bundleIdentifier.hasPrefix(base + ".")
        }
    }

    private var textInsertionMode: SettingsStore.TextInsertionMode {
        SettingsStore.shared.textInsertionMode
    }

    // MARK: - Layout-aware key code lookup

    // Ported from altic-dev/FluidVoice@fb896ebe (support different keyboard layouts) by
    // grohith327, using the cache from @42e33e68. The previous lookup hopped to the main thread
    // with `DispatchQueue.main.sync` on every paste; the cache is refreshed on input-source
    // changes instead, and resolves the key that produces "v" with Command held.
    private nonisolated static let pasteKeyCache = PasteKeyCodeCache {
        let key = PasteKeyCodeResolver.current()
        DeliveryLog.bench("paste_key_cache_refresh keyCode=\(key)")
        return key
    }

    /// Called during application launch, before any paste requests can arrive.
    static func startKeyboardLayoutTracking() {
        self.pasteKeyCache.start()
    }

    /// The virtual key code for "v" in the current keyboard layout (used for Cmd+V paste).
    /// Refreshed by the input-source notification, never by a background paste request.
    nonisolated static var pasteVirtualKeyCode: CGKeyCode {
        self.pasteKeyCache.snapshot()
    }

    // MARK: - Focus helpers (shared)

    /// Best-effort: returns the PID owning the currently focused accessibility element.
    /// This is more reliable than NSWorkspace.frontmostApplication for floating overlays/launchers.
    static func captureSystemFocusedPID() -> pid_t? {
        // Accessibility is required to query system-focused AX element.
        guard AXIsProcessTrusted() else {
            self.storeFocusSnapshot(nil)
            return nil
        }

        let systemWideElement = Self.boundedSystemWideElement()
        var focusedElementRef: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard result == .success, let focusedElementRef else {
            Self.storeFocusSnapshot(nil)
            return nil
        }
        guard CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else {
            Self.storeFocusSnapshot(nil)
            return nil
        }

        let element = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid > 0 else {
            Self.storeFocusSnapshot(nil)
            return nil
        }
        let appElement = AXUIElementCreateApplication(pid)
        let window = Self.copyAXElementAttribute(from: appElement, attribute: kAXFocusedWindowAttribute as CFString)
            ?? Self.copyAXElementAttribute(from: appElement, attribute: kAXMainWindowAttribute as CFString)
        Self.storeFocusSnapshot(FocusSnapshot(pid: pid, window: window, element: element))
        Self.logFocusState("[TypingService] Captured focus snapshot")
        return pid
    }

    /// Best-effort: returns the text immediately before the caret in the currently focused
    /// text field. Used by Continuous Dictation Mode to decide capitalization when chaining
    /// transcribed segments. Returns "" when the focused field/context is unavailable.
    static func textBeforeCursorInFocusedField() -> String {
        TypingService().captureTextBeforeCursorInFocusedField()
    }

    @discardableResult
    static func restoreCapturedFocus(in pid: pid_t) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let snapshot = loadFocusSnapshot(),
              snapshot.pid == pid else { return false }

        Self.logFocusState("[TypingService] Before restoreCapturedFocus")
        let appElement = AXUIElementCreateApplication(pid)

        if let window = snapshot.window {
            _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            _ = AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, window)
            _ = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
            usleep(40_000)
        }

        guard let element = snapshot.element else { return false }

        for _ in 0..<3 {
            let result = AXUIElementSetAttributeValue(
                element,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            if result == .success, Self.isCurrentlyFocusedElement(element, expectedPID: pid) {
                Self.logFocusState("[TypingService] After restoreCapturedFocus success")
                return true
            }
            usleep(50_000)
        }

        let isFocused = Self.isCurrentlyFocusedElement(element, expectedPID: pid)
        Self.logFocusState("[TypingService] After restoreCapturedFocus final result=\(isFocused)")
        return isFocused
    }

    static func isCapturedFocusStillActive(for pid: pid_t) -> Bool {
        guard AXIsProcessTrusted(),
              let snapshot = loadFocusSnapshot(),
              snapshot.pid == pid,
              let element = snapshot.element
        else {
            return false
        }

        return Self.isCurrentlyFocusedElement(element, expectedPID: pid)
    }

    private func isGhosttyApplication(pid: pid_t) -> Bool {
        guard pid > 0,
              let app = NSRunningApplication(processIdentifier: pid)
        else {
            return false
        }

        return Self.isGhosttyFamily(bundleIdentifier: app.bundleIdentifier)
    }

    private func ghosttyTargetPID(preferredTargetPID: pid_t?) -> pid_t? {
        if let preferredTargetPID, preferredTargetPID > 0 {
            return self.isGhosttyApplication(pid: preferredTargetPID) ? preferredTargetPID : nil
        }

        if let focusedPID = self.getSystemFocusedElementAndPID()?.pid,
           self.isGhosttyApplication(pid: focusedPID)
        {
            return focusedPID
        }

        if let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           self.isGhosttyApplication(pid: frontmostPID)
        {
            return frontmostPID
        }

        return nil
    }

    /// Activation options used to restore focus to the external target app after dictation.
    /// `.activateAllWindows` is intentionally omitted: raising every window of a multi-window
    /// app (e.g. WebStorm) destroys the user's window layout on each dictation (issue #748).
    nonisolated static let focusRestoreActivationOptions: NSApplication.ActivationOptions = [
        .activateIgnoringOtherApps,
    ]

    /// Best-effort: activates the app with the given PID, unless it's Fluid itself.
    @discardableResult
    nonisolated static func activateApp(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }

        // Never try to re-activate ourselves; callers want focus to go back to the external app.
        if let selfBundleID = Bundle.main.bundleIdentifier,
           let targetBundleID = app.bundleIdentifier,
           selfBundleID == targetBundleID
        {
            return false
        }

        return app.activate(options: Self.focusRestoreActivationOptions)
    }

    // MARK: - Delivery target (captured at stop)

    // Ported from altic-dev/FluidVoice@5a67d658 (snapshot target and route at stop) and
    // @b0d64436 (restore the exact recording target) by altic-dev / grohith327. MouthKeys
    // keeps every Accessibility read bounded and off the main thread (the hotkey tap runs on
    // it), gives the whole preparation one deadline, and counts a c11/Ghostty target as ready
    // once the terminal is in front: its panes take Cmd+V whatever element AX reports.

    enum FocusPreparationResult: String, Sendable {
        case alreadyFocused = "already_focused"
        /// The app is in front, but its exact field could not be confirmed; still ready.
        case appInFrontFieldUnconfirmed = "app_in_front_field_unconfirmed"
        case restoredExactTarget = "restored_exact_target"
        case activatedForRecovery = "activated_for_recovery"
        case failed

        var isReady: Bool {
            self != .failed
        }
    }

    /// Read-only capture of the focused app, window and element. Unlike
    /// `captureSystemFocusedPID`, it does not replace the stored focus snapshot. Safe off-main.
    nonisolated static func captureDictationTarget() -> DictationTarget? {
        guard AXIsProcessTrusted() else {
            return self.frontmostDictationTarget()
        }
        var focusedElementRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            Self.boundedSystemWideElement(),
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard result == .success, let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
        else { return self.frontmostDictationTarget() }

        let element = Self.boundedAXElement(unsafeBitCast(focusedElementRef, to: AXUIElement.self))
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid > 0 else { return self.frontmostDictationTarget() }
        let appElement = Self.boundedAXElement(AXUIElementCreateApplication(pid))
        let window = Self.copyAXElementAttribute(from: appElement, attribute: kAXFocusedWindowAttribute as CFString)
            ?? Self.copyAXElementAttribute(from: appElement, attribute: kAXMainWindowAttribute as CFString)
        return DictationTarget(
            pid: pid,
            bundleIdentifier: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
            window: window,
            element: element
        )
    }

    /// The target stored by the most recent `captureSystemFocusedPID()`, without new AX reads.
    static func lastCapturedDictationTarget() -> DictationTarget? {
        guard let snapshot = self.loadFocusSnapshot() else { return nil }
        return DictationTarget(
            pid: snapshot.pid,
            bundleIdentifier: NSRunningApplication(processIdentifier: snapshot.pid)?.bundleIdentifier,
            window: snapshot.window,
            element: snapshot.element
        )
    }

    private nonisolated static func frontmostDictationTarget() -> DictationTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return DictationTarget(pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier, window: nil, element: nil)
    }

    /// Read-only focus observation: the PID owning the focused element, else the frontmost app.
    nonisolated static func currentFocusedPID() -> pid_t? {
        guard AXIsProcessTrusted() else {
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        var focusedElementRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            Self.boundedSystemWideElement(),
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard result == .success, let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
        else {
            return NSWorkspace.shared.frontmostApplication?.processIdentifier
        }
        var pid: pid_t = 0
        AXUIElementGetPid(unsafeBitCast(focusedElementRef, to: AXUIElement.self), &pid)
        return pid > 0 ? pid : NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    nonisolated static func isTargetStillFocused(_ target: DictationTarget) -> Bool {
        guard AXIsProcessTrusted(), let element = target.element else { return false }
        return Self.isCurrentlyFocusedElement(element, expectedPID: target.pid)
    }

    /// The budget for the window raise and field-focus steps of the focus preparation. Every
    /// such step checks it before starting; one bounded AX call in flight can overrun it by at
    /// most `axMessagingTimeoutSeconds`. The frontmost wait is not part of it: it always gets
    /// its own `frontmostWaitLimit`, so slow AX steps can never starve it into a false failure.
    nonisolated static let focusPreparationDeadline: TimeInterval = 2.0
    /// How long to wait for an app brought back to actually come to the front.
    nonisolated static let frontmostWaitLimit: TimeInterval = 1.0

    /// Puts focus back on the captured target before delivery. Runs off the main thread.
    ///
    /// Refuses (`.failed`) only on positive evidence: the target app is not in front after
    /// recovery. When the app is in front but its exact field cannot be confirmed (the element
    /// is recreated per AX query, or its role is not one we recognise as text: Word, Excel,
    /// Zed, Warp, kitty), delivery goes ahead and the "certainly not a text field" check
    /// decides.
    @concurrent
    nonisolated static func prepareTargetForDelivery(_ target: DictationTarget) async -> FocusPreparationResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let deadline = startedAt + self.focusPreparationDeadline
        let isTerminal = Self.isGhosttyFamily(bundleIdentifier: target.bundleIdentifier)
        let hasField = target.element != nil && !isTerminal

        let result: FocusPreparationResult
        if self.isAppInFront(pid: target.pid) {
            // The app never lost the front. Nothing to recover unless the field moved.
            var fieldConfirmed = !hasField || self.isTargetStillFocused(target)
            if !fieldConfirmed {
                fieldConfirmed = await self.restoreExactTarget(target, deadline: deadline)
            }
            result = self.preparationVerdict(appInFront: true, broughtBack: false, fieldConfirmed: fieldConfirmed)
        } else if isTerminal {
            // Terminals: raise the stop-time window (c11 can have several), bring the app
            // forward, and give the frontmost wait its full second. No field focusing: panes
            // take Cmd+V whatever element AX reports, and the focus attempts could eat the
            // deadline and turn a slow activation into a false "Text wasn't inserted".
            if ProcessInfo.processInfo.systemUptime < deadline {
                await self.raiseWindow(of: target)
            }
            let broughtForward = self.bringToFront(pid: target.pid)
            let wait = await self.waitUntilAppInFront(pid: target.pid, limit: self.frontmostWaitLimit)
            Self.logFrontmostCheck(
                stage: "prepare", target: target.pid, waitedMs: wait.waitedMs, inFront: wait.inFront, via: broughtForward.rawValue
            )
            result = self.preparationVerdict(appInFront: wait.inFront, broughtBack: true, fieldConfirmed: true)
        } else {
            var fieldConfirmed = false
            if target.element != nil {
                // Raising the target window and focusing its field often brings the app back.
                fieldConfirmed = await self.restoreExactTarget(target, deadline: deadline)
            }
            var broughtForward = BringToFrontOutcome.alreadyInFront
            if !fieldConfirmed || !self.isAppInFront(pid: target.pid) {
                broughtForward = self.bringToFront(pid: target.pid)
            }
            // The frontmost wait always gets its full second, however long the field steps took.
            let wait = await self.waitUntilAppInFront(pid: target.pid, limit: self.frontmostWaitLimit)
            Self.logFrontmostCheck(
                stage: "prepare", target: target.pid, waitedMs: wait.waitedMs, inFront: wait.inFront, via: broughtForward.rawValue
            )
            if wait.inFront, hasField, !fieldConfirmed {
                fieldConfirmed = self.isTargetStillFocused(target)
                if !fieldConfirmed {
                    fieldConfirmed = await self.restoreExactTarget(target, deadline: deadline)
                }
            }
            result = self.preparationVerdict(appInFront: wait.inFront, broughtBack: true, fieldConfirmed: !hasField || fieldConfirmed)
        }
        DeliveryLog.info(
            "prepare_target app=\(target.bundleIdentifier ?? "pid\(target.pid)") terminal=\(isTerminal) " +
                "result=\(result.rawValue) elapsedMs=\(Int(((ProcessInfo.processInfo.systemUptime - startedAt) * 1000).rounded()))"
        )
        return result
    }

    /// The preparation verdict. Delivery is ready exactly when the target app is in front;
    /// whether its field could be confirmed only changes how the outcome is logged.
    nonisolated static func preparationVerdict(appInFront: Bool, broughtBack: Bool, fieldConfirmed: Bool) -> FocusPreparationResult {
        guard appInFront else { return .failed }
        switch (broughtBack, fieldConfirmed) {
        case (false, true): return .alreadyFocused
        case (false, false): return .appInFrontFieldUnconfirmed
        case (true, true): return .restoredExactTarget
        case (true, false): return .activatedForRecovery
        }
    }

    /// Whether `pid` is the app the user is in: the frontmost app, or the owner of the focused
    /// element.
    nonisolated static func isAppInFront(pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid || self.currentFocusedPID() == pid
    }

    nonisolated enum BringToFrontOutcome: String, Sendable {
        case alreadyInFront = "already_in_front"
        case activated
        /// Plain activation did not take within the grace period; the AX frontmost flag was set.
        case axFallback = "ax_fallback"
        case notInFront = "not_in_front"
    }

    /// How long a plain activation gets before the Accessibility frontmost flag is tried.
    nonisolated static let axFrontmostFallbackDelay: TimeInterval = 0.25

    /// Asks for `pid` to come to the front. A plain activation first: it raises only the
    /// app's key window, keeping the "don't activate all windows" choice (upstream #748). Only
    /// when that has not made the app frontmost within `axFallbackAfter` is the Accessibility
    /// frontmost flag set: it works where macOS declines a background app's activation
    /// request, but on AppKit apps it can raise every window. Blocks briefly; call off-main.
    nonisolated static func bringToFront(
        pid: pid_t,
        axFallbackAfter: TimeInterval = TypingService.axFrontmostFallbackDelay,
        pollInterval: TimeInterval = 0.025,
        activate: (pid_t) -> Bool = { TypingService.activateApp(pid: $0) },
        isInFront: (pid_t) -> Bool = { TypingService.isAppInFront(pid: $0) },
        setAXFrontmost: (pid_t) -> Bool = { TypingService.setAXFrontmostFlag(pid: $0) }
    ) -> BringToFrontOutcome {
        if isInFront(pid) { return .alreadyInFront }
        _ = activate(pid)
        let fallbackAt = ProcessInfo.processInfo.systemUptime + axFallbackAfter
        repeat {
            if isInFront(pid) { return .activated }
            usleep(useconds_t(max(pollInterval, 0.001) * 1_000_000))
        } while ProcessInfo.processInfo.systemUptime < fallbackAt
        if isInFront(pid) { return .activated }
        return setAXFrontmost(pid) ? .axFallback : .notInFront
    }

    private nonisolated static func setAXFrontmostFlag(pid: pid_t) -> Bool {
        guard AXIsProcessTrusted(), pid != ProcessInfo.processInfo.processIdentifier else { return false }
        let appElement = self.boundedAXElement(AXUIElementCreateApplication(pid))
        return AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue) == .success
    }

    private nonisolated static func waitUntilAppInFront(pid: pid_t, limit: TimeInterval) async -> (inFront: Bool, waitedMs: Int) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let deadline = startedAt + limit
        repeat {
            if self.isAppInFront(pid: pid) {
                return (true, Int(((ProcessInfo.processInfo.systemUptime - startedAt) * 1000).rounded()))
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        } while ProcessInfo.processInfo.systemUptime < deadline
        let inFront = self.isAppInFront(pid: pid)
        return (inFront, Int(((ProcessInfo.processInfo.systemUptime - startedAt) * 1000).rounded()))
    }

    /// One log line per frontmost check, so a missing paste can be diagnosed from the log.
    nonisolated static func logFrontmostCheck(stage: String, target pid: pid_t, waitedMs: Int, inFront: Bool, via: String? = nil) {
        let targetApp = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "pid\(pid)"
        let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        DeliveryLog.info(
            "frontmost_check stage=\(stage) app=\(targetApp) waitedMs=\(waitedMs) " +
                "result=\(inFront ? "in_front" : "not_in_front") frontmost=\(frontApp)" +
                (via.map { " via=\($0)" } ?? "")
        )
    }

    /// Raises the captured window and makes it the app's main and focused window, so a
    /// multi-window app comes back on the window the user dictated into.
    private nonisolated static func raiseWindow(of target: DictationTarget) async {
        guard AXIsProcessTrusted(), let window = target.window else { return }
        let appElement = Self.boundedAXElement(AXUIElementCreateApplication(target.pid))
        Self.boundedAXElement(window)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, window)
        _ = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
        try? await Task.sleep(nanoseconds: 25_000_000)
    }

    private nonisolated static func restoreExactTarget(_ target: DictationTarget, deadline: TimeInterval) async -> Bool {
        guard AXIsProcessTrusted(), let element = target.element else { return false }
        guard ProcessInfo.processInfo.systemUptime < deadline else { return false }

        await self.raiseWindow(of: target)

        Self.boundedAXElement(element)
        for attempt in 0..<3 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            let result = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            if result == .success, Self.isCurrentlyFocusedElement(element, expectedPID: target.pid) {
                DeliveryLog.info("restore_exact_target result=restored attempt=\(attempt)")
                return true
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
        }

        guard ProcessInfo.processInfo.systemUptime < deadline else {
            DeliveryLog.info("restore_exact_target result=deadline")
            return false
        }
        let isFocused = Self.isCurrentlyFocusedElement(element, expectedPID: target.pid)
        DeliveryLog.info("restore_exact_target result=\(isFocused ? "restored" : "unconfirmed")")
        return isFocused
    }

    // MARK: - Delivery failures

    /// Where a failed delivery is announced. The app shows the failure card; tests replace it.
    static var deliveryFailureHandler: (DeliveryFailureReport) -> Void = { report in
        DeliveryFailureOverlayController.shared.show(report)
    }

    /// Where a dictation's delivery outcome goes, on the main actor: the overlay's delivered hold.
    /// Only deliveries that carry a stop-path trace (dictations) report one. Tests replace it.
    static var dictationOutcomeHandler: (DictationDeliveryOutcome) -> Void = { outcome in
        BottomOverlayWindowController.shared.dictationDeliveryFinished(outcome)
    }

    /// Reports `result` for the dictation traced by `stopTrace`, on the main actor.
    nonisolated static func reportDictationOutcome(
        _ result: TextDeliveryResult,
        path: InsertionPath?,
        sendKey: SendKeyOutcome?,
        stopTrace: StopPathTrace?
    ) {
        guard let stopTrace else { return }
        let outcome = DictationDeliveryOutcome(
            traceID: stopTrace.id,
            result: result,
            method: path.map(Self.deliveryMethod),
            sentReturn: sendKey == .sent
        )
        Task { @MainActor in
            TypingService.dictationOutcomeHandler(outcome)
        }
    }

    nonisolated static func deliveryMethod(for path: InsertionPath) -> DictationDeliveryOutcome.Method {
        switch path {
        case .clipboardToPID, .clipboardGlobal, .menuPaste: .paste
        case .directToPID, .directHID, .characterByCharacter: .keystrokes
        case .accessibility: .accessibility
        }
    }

    /// Keeps the transcript and tells the user. Safe to call from any thread.
    ///
    /// The transcript is put on the clipboard as an ordinary copy (it is already in history),
    /// unless the user copied something since `revision` (default: now). The failure card then
    /// appears with a Copy action and says whether the clipboard holds the transcript.
    nonisolated static func reportDeliveryFailure(
        _ failure: TextDeliveryFailure,
        transcript: String,
        inHistory: Bool,
        since revision: Int? = nil,
        pasteSession: ClipboardPasteSession = .shared,
        traceID: Int? = nil
    ) {
        DeliveryLog.bench("delivery_failed reason=\(failure.rawValue) chars=\(transcript.count)")
        DeliveryLog.warning("Text delivery failed reason=\(failure.rawValue) chars=\(transcript.count)")
        guard failure.isUserVisible, !transcript.isEmpty else { return }
        pasteSession.keepTranscript(transcript, since: revision) { outcome in
            DeliveryLog.info("delivery_failure_transcript_kept clipboard=\(outcome.rawValue) inHistory=\(inHistory)")
            let report = DeliveryFailureReport(
                failure: failure,
                transcript: transcript,
                clipboard: outcome,
                inHistory: inHistory,
                traceID: traceID
            )
            Task { @MainActor in
                TypingService.deliveryFailureHandler(report)
            }
        }
    }

    // MARK: - Public API

    func typeTextInstantly(_ text: String) {
        self.typeTextInstantly(text, preferredTargetPID: nil, textReadyAt: nil)
    }

    /// Types/inserts text, optionally preferring a specific target PID for CGEvent posting.
    /// This helps when our overlay temporarily has focus; we can still target the original app.
    func typeTextInstantly(_ text: String, preferredTargetPID: pid_t?) {
        self.typeTextInstantly(text, preferredTargetPID: preferredTargetPID, textReadyAt: nil)
    }

    /// Types/inserts text, optionally preferring a specific target PID for CGEvent posting.
    /// This helps when our overlay temporarily has focus; we can still target the original app.
    func typeTextInstantly(_ text: String, preferredTargetPID: pid_t?, textReadyAt: TimeInterval?) {
        self.typeOutputPlanInstantly(.plain(text), preferredTargetPID: preferredTargetPID, textReadyAt: textReadyAt)
    }

    /// Inserts `plan` where the user is typing. Insertions run one at a time on a serial
    /// worker, so back-to-back dictations queue instead of dropping.
    ///
    /// - Parameters:
    ///   - verifiesLanding: run the opt-in paste read-back (Settings > Notifications > Paste
    ///     Check) after a clipboard paste. Pass `false` when a send key follows the paste: the
    ///     field empties right after it and the read-back would report a false miss
    ///     (ported from altic-dev/FluidVoice@98b5a278).
    ///   - transcriptInHistory: whether the text is already in transcription history, so the
    ///     failure card can say where it is kept.
    ///   - sendKey: Spoken Send. The key is pressed in `sendKey.target` strictly after the
    ///     text was dispatched there, at most once, and never when the delivery failed. It
    ///     turns the paste read-back off (see `verifiesLanding`).
    ///   - onSendKey: called on the main actor with the send key's outcome, when one was asked for.
    ///   - completion: called on the main actor once the attempt finishes. A failure has
    ///     already been reported to the user (card + transcript kept) by then.
    func typeOutputPlanInstantly(
        _ plan: DictationLiteralOutputPlan,
        preferredTargetPID: pid_t?,
        textReadyAt: TimeInterval?,
        tracksDictionaryCorrections: Bool = false,
        verifiesLanding: Bool = true,
        transcriptInHistory: Bool = false,
        sendKey: SendKeyRequest? = nil,
        onSendKey: ((SendKeyOutcome) -> Void)? = nil,
        stopTrace: StopPathTrace? = nil,
        completion: ((TextDeliveryResult) -> Void)? = nil
    ) {
        let verifiesLanding = verifiesLanding && sendKey == nil
        let requestedAt = ProcessInfo.processInfo.systemUptime
        let text = plan.plainText
        let mode = self.textInsertionMode
        let settleDelayMs: Int = {
            if mode == .reliablePaste {
                return preferredTargetPID == nil ? 80 : 0
            }
            return preferredTargetPID == nil ? 200 : 0
        }()
        let textReadyAge = textReadyAt.map { Self.elapsedMs(from: $0, to: requestedAt) }
        self.bench(
            "request chars=\(text.count) mode=\(mode.rawValue) autocompleteSteps=\(plan.steps.count) preferredPID=\(preferredTargetPID.map { String($0) } ?? "nil") textReadyAgeMs=\(textReadyAge.map { String($0) } ?? "nil")"
        )
        self.log("[TypingService] ENTRY: typeTextInstantly called with text length: \(text.count)")
        self.log("[TypingService] Text preview: \"\(String(text.prefix(100)))\"")

        guard text.isEmpty == false else {
            self.decision("request_return reason=empty_text")
            self.log("[TypingService] ERROR: Empty text provided, aborting")
            stopTrace?.finish(outcome: TextDeliveryFailure.emptyText.rawValue)
            Self.reportDictationOutcome(.recoverableFailure(.emptyText), path: nil, sendKey: nil, stopTrace: stopTrace)
            completion?(.recoverableFailure(.emptyText))
            if sendKey != nil { onSendKey?(.textNotDelivered) }
            return
        }

        // Check accessibility permissions first
        guard AXIsProcessTrusted() else {
            self.decision("request_return reason=accessibility_not_trusted")
            self.log("[TypingService] ERROR: Accessibility permissions required for text injection")
            Self.reportDeliveryFailure(.accessibilityNotTrusted, transcript: text, inHistory: transcriptInHistory, pasteSession: self.pasteSession, traceID: stopTrace?.id)
            stopTrace?.finish(outcome: TextDeliveryFailure.accessibilityNotTrusted.rawValue)
            Self.reportDictationOutcome(.recoverableFailure(.accessibilityNotTrusted), path: nil, sendKey: nil, stopTrace: stopTrace)
            completion?(.recoverableFailure(.accessibilityNotTrusted))
            if sendKey != nil { onSendKey?(.textNotDelivered) }
            return
        }

        self.log("[TypingService] Accessibility check passed, proceeding with text injection")
        self.pendingCountLock.lock()
        self.pendingInsertions += 1
        let queuedBehind = self.pendingInsertions - 1
        self.pendingCountLock.unlock()
        if queuedBehind > 0 {
            self.decision("request_queued behind=\(queuedBehind)")
            self.log("[TypingService] Insertion queued behind \(queuedBehind) in-flight operation(s)")
        }

        Self.typingWorkQueue.async {
            let workerStartedAt = ProcessInfo.processInfo.systemUptime
            self.bench("worker_start queueDelayMs=\(Self.elapsedMs(from: requestedAt, to: workerStartedAt))")

            var result: TextDeliveryResult = .recoverableFailure(.targetUnavailable)
            var sendKeyOutcome: SendKeyOutcome = .textNotDelivered
            var deliveredPath: InsertionPath?
            defer {
                let completedAt = ProcessInfo.processInfo.systemUptime
                self.pendingCountLock.lock()
                self.pendingInsertions -= 1
                self.pendingCountLock.unlock()
                self.bench(
                    "complete result=\(Self.describe(result)) totalMs=\(Self.elapsedMs(from: requestedAt, to: completedAt)) textReadyToCompleteMs=\(textReadyAt.map { String(Self.elapsedMs(from: $0, to: completedAt)) } ?? "nil")"
                        + (sendKey != nil ? " sendKey=\(sendKeyOutcome.rawValue)" : "")
                )
                self.log("[TypingService] Typing operation completed")
                let finalResult = result
                Self.reportDictationOutcome(
                    finalResult,
                    path: deliveredPath,
                    sendKey: sendKey == nil ? nil : sendKeyOutcome,
                    stopTrace: stopTrace
                )
                if let completion {
                    Task { @MainActor in completion(finalResult) }
                }
                let finalSendKeyOutcome = sendKeyOutcome
                if sendKey != nil, let onSendKey {
                    Task { @MainActor in onSendKey(finalSendKeyOutcome) }
                }
            }

            self.log("[TypingService] Starting async text insertion process")
            if settleDelayMs > 0 {
                usleep(useconds_t(settleDelayMs * 1000))
            }
            self.bench("settle_delay_done delayMs=\(settleDelayMs) elapsedMs=\(Self.elapsedMs(since: requestedAt))")
            // Fast transcriptions can complete before the user releases the stop hotkey's
            // modifiers. A physically-held modifier corrupts every insertion path that posts
            // keyboard events (terminals interpret ⌥/⌘ + key as bindings), so wait briefly
            // for a clean keyboard before typing.
            let modifiersReleased = Self.awaitModifierKeyRelease(timeoutMs: 1000)
            self.bench("modifier_release_wait_done released=\(modifiersReleased) elapsedMs=\(Self.elapsedMs(since: requestedAt))")
            if !modifiersReleased {
                self.log("[TypingService] WARNING: modifier keys still held after wait (\(Self.heldPhysicalModifiers())); proceeding anyway")
            }

            let insertStartedAt = ProcessInfo.processInfo.systemUptime
            self.bench("insert_call")
            // Bound for this delivery so the paste session marks the moment Cmd+V is posted.
            let delivery = StopPathTrace.$current.withValue(stopTrace) {
                self.deliver(
                    text,
                    preferredTargetPID: preferredTargetPID,
                    verifiesLanding: verifiesLanding,
                    transcriptInHistory: transcriptInHistory,
                    sendKey: sendKey
                )
            }
            result = delivery.result
            deliveredPath = delivery.path
            sendKeyOutcome = delivery.sendKey ?? .textNotDelivered
            switch result {
            case .dispatched:
                // Typed or AX paths post no Cmd+V: the text was handed over when deliver returned.
                stopTrace?.mark(.pastePosted)
                if delivery.sendKey == .sent {
                    stopTrace?.mark(.sendKeyPosted)
                }
                stopTrace?.note("sendKey", delivery.sendKey?.rawValue ?? "none")
                stopTrace?.finish(outcome: "delivered")
            case let .recoverableFailure(failure):
                stopTrace?.finish(outcome: failure.rawValue)
            }
            self.bench(
                "insert_return result=\(Self.describe(result)) elapsedMs=\(Self.elapsedMs(since: insertStartedAt)) totalMs=\(Self.elapsedMs(since: requestedAt))"
            )
            if case let .recoverableFailure(failure) = result {
                Self.reportDeliveryFailure(failure, transcript: text, inHistory: transcriptInHistory, pasteSession: self.pasteSession, traceID: stopTrace?.id)
            } else if tracksDictionaryCorrections, sendKey == nil {
                // Not after a send key: the field empties on submit and the tracker would misread it.
                Task { @MainActor in
                    AutomaticDictionaryCorrectionTracker.shared.beginObservingInsertion(
                        text,
                        targetPID: preferredTargetPID
                    )
                }
            }
        }
    }

    /// Spoken Send with nothing to type (the dictation was only the phrase): presses the send
    /// key in `request.target`, submitting what is already there. It queues behind any delivery
    /// still in flight, and goes only while the target is in front.
    func pressSendKey(_ request: SendKeyRequest, completion: ((SendKeyOutcome) -> Void)? = nil) {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        self.decision("send_key_request pid=\(request.target.pid) key=\(request.key.rawValue)")
        guard AXIsProcessTrusted() else {
            self.decision("send_key_return reason=accessibility_not_trusted")
            completion?(.eventsUnavailable)
            return
        }
        Self.typingWorkQueue.async {
            let isTerminal = Self.isGhosttyFamily(bundleIdentifier: request.target.bundleIdentifier)
            var step = SendKeyStep(request: request)
            // Nothing was pasted, so there is nothing to wait for.
            step.delay = 0
            let outcome: SendKeyOutcome = if isTerminal {
                TerminalPaster(session: self.pasteSession) { _ in false }
                    .pressSendKeyAlone(step, to: request.target.pid)
            } else {
                Self.pressSendKeyInApp(step, target: request.target, focusAtPaste: .same)
            }
            self.decision("send_key_return outcome=\(outcome.rawValue) terminal=\(isTerminal) elapsedMs=\(Self.elapsedMs(since: requestedAt))")
            if let completion {
                Task { @MainActor in completion(outcome) }
            }
        }
    }

    private static func describe(_ result: TextDeliveryResult) -> String {
        switch result {
        case .dispatched: "dispatched"
        case let .recoverableFailure(failure): failure.rawValue
        }
    }

    // Physical modifier keys, read from the HID state (ported from
    // altic-dev/FluidVoice@c0118882). The session flag state is not reliable here: a
    // synthesized Cmd+V that only flags V can leave Command reported as held until the next
    // real event, which made this wait time out for nothing.
    private nonisolated static let physicalModifierKeys: [(name: String, code: CGKeyCode)] = [
        ("cmd", CGKeyCode(kVK_Command)), ("rcmd", CGKeyCode(kVK_RightCommand)),
        ("shift", CGKeyCode(kVK_Shift)), ("rshift", CGKeyCode(kVK_RightShift)),
        ("opt", CGKeyCode(kVK_Option)), ("ropt", CGKeyCode(kVK_RightOption)),
        ("ctrl", CGKeyCode(kVK_Control)), ("rctrl", CGKeyCode(kVK_RightControl)),
        ("fn", CGKeyCode(kVK_Function)),
    ]

    nonisolated static func heldPhysicalModifiers() -> [String] {
        self.physicalModifierKeys
            .filter { CGEventSource.keyState(.hidSystemState, key: $0.code) }
            .map(\.name)
    }

    /// Blocks until every physical modifier key is released, or the timeout passes.
    /// Returns whether the keyboard was clean when it returned. Called on the typing
    /// worker queue only — never on the main thread.
    private nonisolated static func awaitModifierKeyRelease(timeoutMs: Int) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + Double(timeoutMs) / 1000.0
        while !self.heldPhysicalModifiers().isEmpty {
            if ProcessInfo.processInfo.systemUptime >= deadline { return false }
            usleep(10_000)
        }
        return true
    }

    /// `awaitModifierKeyRelease` for the send key. Blocks; call off the main thread.
    nonisolated static func waitForPhysicalModifierRelease(timeout: TimeInterval) -> Bool {
        let released = self.awaitModifierKeyRelease(timeoutMs: Int(timeout * 1000))
        if !released {
            DeliveryLog.warning("Send key suppressed: modifiers still held after \(Int(timeout * 1000))ms held=\(self.heldPhysicalModifiers())")
        }
        return released
    }

    private func bench(_ message: @autoclosure () -> String) {
        DebugLogger.shared.benchmark("TYPING_BENCH", message: message(), source: "TypingBenchmark")
    }

    /// A per-delivery decision (which path, why a target or send key was refused). Kept in
    /// Release, unlike timing lines: it is how a lost or misplaced paste gets diagnosed in the
    /// installed app. Never carries transcript text.
    private func decision(_ message: String) {
        DeliveryLog.info(message)
    }

    private static func elapsedMs(since start: TimeInterval) -> Int {
        Int(((ProcessInfo.processInfo.systemUptime - start) * 1000).rounded())
    }

    private static func elapsedMs(from start: TimeInterval, to end: TimeInterval) -> Int {
        Int(((end - start) * 1000).rounded())
    }

    // MARK: - Internal insertion pipeline

    /// How an insertion was dispatched.
    enum InsertionPath: String {
        case clipboardToPID = "clipboard_pid"
        case clipboardGlobal = "clipboard_global"
        case menuPaste = "menu_paste"
        case directToPID = "direct_pid"
        case accessibility = "ax_value"
        case directHID = "direct_hid"
        case characterByCharacter = "char_by_char"

        var usesClipboard: Bool {
            self == .clipboardToPID || self == .clipboardGlobal || self == .menuPaste
        }
    }

    /// One delivery on the typing worker: refuse a target that certainly cannot take text,
    /// insert, then (opt-in) read the field back after a clipboard paste.
    private func deliver(
        _ text: String,
        preferredTargetPID: pid_t?,
        verifiesLanding: Bool,
        transcriptInHistory: Bool,
        sendKey: SendKeyRequest? = nil
    ) -> (result: TextDeliveryResult, sendKey: SendKeyOutcome?, path: InsertionPath?) {
        let terminalPID = self.ghosttyTargetPID(preferredTargetPID: preferredTargetPID)
        let route = DeliveryRoute.decide(
            isTerminal: terminalPID != nil,
            mode: self.textInsertionMode,
            pasteCheckEnabled: SettingsStore.shared.showPasteCheckAlerts,
            sendKeyFollows: !verifiesLanding
        )
        self.bench(
            "delivery_route terminal=\(terminalPID != nil) refusesNonEditable=\(route.refusesNonEditableFocus) " +
                "pastesFirst=\(route.pastesFirst) globalFallback=\(route.fallsBackToGlobalPaste) " +
                "directFallback=\(route.fallsBackToDirectTyping) readBack=\(route.readsPasteBack)" +
                (sendKey.map { " sendKey=\($0.key.rawValue)" } ?? "")
        )
        // The key goes only to the process the text goes to.
        let deliveryPID = terminalPID ?? preferredTargetPID
        var sendStep: SendKeyStep?
        var sendKeyOutcome: SendKeyOutcome?
        if let sendKey {
            if deliveryPID == sendKey.target.pid {
                sendStep = SendKeyStep(request: sendKey)
            } else {
                self.decision("send_key_skipped reason=target_mismatch deliveryPID=\(deliveryPID.map { String($0) } ?? "nil") sendPID=\(sendKey.target.pid)")
                sendKeyOutcome = .targetMismatch
            }
        }

        // Ported from altic-dev/FluidVoice@51e62364 / @a1a65772: refuse only when the focused
        // element certainly cannot take text (a button, a menu, static text). Terminals are
        // never refused: c11 and Ghostty draw their own surface and always take Cmd+V.
        if route.refusesNonEditableFocus {
            let assessStartedAt = ProcessInfo.processInfo.systemUptime
            let assessment = DeliveryTargetAssessment.assessFocusedElement(messagingTimeout: Self.axMessagingTimeoutSeconds)
            self.decision("focus_assess \(assessment.logDescription) elapsedMs=\(Self.elapsedMs(since: assessStartedAt))")
            if assessment.isCertainlyNotEditable {
                return (.recoverableFailure(.noEditableTarget), sendKey.map { _ in .textNotDelivered }, nil)
            }
        } else {
            self.decision("focus_assess skipped reason=terminal_target")
        }

        // The read-back baseline costs AX reads, so it is taken only when the opt-in check
        // will run, and inside the paste session (after earlier queued pastes have landed),
        // just before this paste is sent.
        var verificationBaseline: PasteVerifier.Snapshot?
        // A terminal paste presses the send key itself, behind its own frontmost gate.
        var terminalSendKeyOutcome: SendKeyOutcome?
        // Elsewhere the key empties the field, so a paste's clipboard hold must not wait to see
        // the text there (see pasteConsumptionWait).
        self.sendKeyFollowsCurrentDelivery = sendStep != nil
        defer { self.sendKeyFollowsCurrentDelivery = false }
        // Right before the paste: is the element focused at stop still the focused one? (A
        // terminal paste looks at its own dispatch instant instead.)
        let focusAtPaste = terminalPID == nil ? sendStep?.targetFocus() : nil
        let outcome = self.insertTextInstantly(
            text,
            preferredTargetPID: preferredTargetPID,
            terminalPID: terminalPID,
            route: route,
            terminalSendKey: terminalPID != nil ? sendStep : nil,
            terminalSendKeyOutcome: &terminalSendKeyOutcome,
            beforeClipboardDispatch: {
                if route.readsPasteBack {
                    verificationBaseline = PasteVerifier.capture()
                }
            }
        )
        switch outcome {
        case let .failed(failure):
            self.decision("insert_path path=none failure=\(failure.rawValue)")
            return (.recoverableFailure(failure), sendKey.map { _ in .textNotDelivered }, nil)
        case let .dispatched(path):
            self.decision("insert_path path=\(path.rawValue)")
            if path.usesClipboard, let verificationBaseline {
                Self.verifyPasteLanded(
                    text,
                    before: verificationBaseline,
                    pastedAt: ProcessInfo.processInfo.systemUptime,
                    pasteRevision: self.pasteSession.changeCount,
                    transcriptInHistory: transcriptInHistory,
                    pasteSession: self.pasteSession,
                    traceID: StopPathTrace.current?.id
                )
            }
            guard let sendKey, let sendStep else { return (.dispatched, sendKeyOutcome, path) }
            if terminalPID != nil {
                // The terminal paste pressed the key after its V key-up, or refused to.
                return (.dispatched, terminalSendKeyOutcome ?? .eventsUnavailable, path)
            }
            return (.dispatched, Self.pressSendKeyInApp(sendStep, target: sendKey.target, focusAtPaste: focusAtPaste ?? .unreadable), path)
        }
    }

    /// The send key in an ordinary app, after its text was dispatched: only while focus is still
    /// on the element focused at stop (as it was right before the paste), with no key press or
    /// click since the stop, not on a password field, and not on something that certainly takes
    /// no text (Return would press a focused button). Blocks; runs on the typing worker.
    private nonisolated static func pressSendKeyInApp(_ step: SendKeyStep, target: DictationTarget, focusAtPaste: TargetFocus) -> SendKeyOutcome {
        if step.delay > 0 {
            usleep(useconds_t(step.delay * 1_000_000))
        }
        guard step.modifiersReleased() else { return .modifiersHeld }
        guard !step.userActedSince(step.inputCutoff) else {
            DeliveryLog.info("send_key_refused reason=user_acted pid=\(target.pid)")
            return .userActed
        }
        let focus = self.focusedElementForSendKey()
        let focusNow = step.targetFocus()
        let verdict = self.sendKeyVerdict(
            targetPID: target.pid,
            focusedPID: self.currentFocusedPID(),
            focus: focus,
            targetFocus: TargetFocus.worst([focusAtPaste, focusNow])
        )
        if let verdict {
            DeliveryLog.info(
                "send_key_refused reason=\(verdict.rawValue) pid=\(target.pid) focus=\(focus.assessment.logDescription) " +
                    "atPaste=\(focusAtPaste.rawValue) now=\(focusNow.rawValue)"
            )
            return verdict
        }
        return step.post(target.pid, step.key) ? .sent : .eventsUnavailable
    }

    /// Why the send key may not go into an ordinary app, or nil when it may. Pure, so it is tested.
    /// `targetFocus`: whether the element focused at stop was still the focused one at every look
    /// (upstream's exact-focus check).
    nonisolated static func sendKeyVerdict(
        targetPID: pid_t,
        focusedPID: pid_t?,
        focus: (assessment: DeliveryTargetAssessment, isSecure: Bool),
        targetFocus: TargetFocus
    ) -> SendKeyOutcome? {
        guard focusedPID == targetPID else { return .targetNotInFront }
        if let refusal = targetFocus.outcome { return refusal }
        if focus.isSecure { return .secureField }
        if focus.assessment.isCertainlyNotEditable { return .focusNotEditable }
        return nil
    }

    /// Whether the element focused when dictation stopped (a c11 pane, a text field) is still the
    /// focused element of its app. Compared with `CFEqual`; c11 exposes each pane as its own
    /// AXTextArea, stable across reads. Bounded AX reads; call off the main thread.
    nonisolated static func stopTimeFocus(of target: DictationTarget) -> TargetFocus {
        guard AXIsProcessTrusted(), let element = target.element else { return .unreadable }
        let appElement = self.boundedAXElement(AXUIElementCreateApplication(target.pid))
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return .unreadable }
        return CFEqual(focusedRef, element) ? .same : .moved
    }

    /// The focused element's editability and whether it is a password field. Bounded AX reads.
    private nonisolated static func focusedElementForSendKey() -> (assessment: DeliveryTargetAssessment, isSecure: Bool) {
        let assessment = DeliveryTargetAssessment.assessFocusedElement(messagingTimeout: self.axMessagingTimeoutSeconds)
        guard AXIsProcessTrusted() else { return (assessment, false) }
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self.boundedSystemWideElement(), kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return (assessment, false) }
        let element = self.boundedAXElement(unsafeBitCast(focusedRef, to: AXUIElement.self))
        var subroleRef: CFTypeRef?
        let subrole = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success
            ? subroleRef as? String
            : nil
        return (assessment, subrole == (kAXSecureTextFieldSubrole as String))
    }

    private enum InsertionOutcome {
        case dispatched(InsertionPath)
        case failed(TextDeliveryFailure)
    }

    /// Which delivery steps run for a target. Pure, so the c11/Ghostty guarantees are tested.
    struct DeliveryRoute: Equatable {
        /// Refuse when focus is certainly not a text field (a button, a menu, static text).
        let refusesNonEditableFocus: Bool
        /// Try the clipboard paths before direct typing.
        let pastesFirst: Bool
        /// After a paste to the target's PID fails, try a global Cmd+V (it goes to whatever
        /// app is in front).
        let fallsBackToGlobalPaste: Bool
        /// Fall back to direct typing when every clipboard path fails.
        let fallsBackToDirectTyping: Bool
        /// Run the opt-in read-back after a clipboard paste.
        let readsPasteBack: Bool

        static func decide(
            isTerminal: Bool,
            mode: SettingsStore.TextInsertionMode,
            pasteCheckEnabled: Bool,
            sendKeyFollows: Bool
        ) -> DeliveryRoute {
            if isTerminal {
                // c11 and Ghostty: always the clipboard paste to the terminal's PID, never
                // refused (their surface takes Cmd+V whatever AX reports), never direct typing
                // (it silently drops text there), and no read-back (no readable field text).
                // No global Cmd+V either: if the terminal is not in front it would land in
                // another app. The terminal paste retries itself once on a clipboard race.
                return DeliveryRoute(
                    refusesNonEditableFocus: false,
                    pastesFirst: true,
                    fallsBackToGlobalPaste: false,
                    fallsBackToDirectTyping: false,
                    readsPasteBack: false
                )
            }
            return DeliveryRoute(
                refusesNonEditableFocus: true,
                pastesFirst: mode == .reliablePaste,
                fallsBackToGlobalPaste: true,
                fallsBackToDirectTyping: true,
                readsPasteBack: pasteCheckEnabled && !sendKeyFollows
            )
        }
    }

    /// Off-worker read-back after a paste. Logs every verdict; only a certain `notLanded`
    /// reaches the user. Ported from altic-dev/FluidVoice@fadaed91 / @788d04b6.
    private nonisolated static func verifyPasteLanded(
        _ text: String,
        before: PasteVerifier.Snapshot,
        pastedAt: TimeInterval,
        pasteRevision: Int,
        transcriptInHistory: Bool,
        pasteSession: ClipboardPasteSession,
        traceID: Int?
    ) {
        Task.detached(priority: .utility) {
            var verdict = await PasteVerifier.verify(before: before, pastedText: text)
            let now = ProcessInfo.processInfo.systemUptime
            if case .notLanded = verdict, PasteVerifier.userActedAfterPaste(
                secondsSinceLastInput: PasteVerifier.secondsSinceLastUserInput(),
                secondsSincePaste: now - pastedAt
            ) {
                verdict = .unknown(reason: "user_input_after_paste")
            }
            let app = NSRunningApplication(processIdentifier: before.pid)?.bundleIdentifier ?? "pid\(before.pid)"
            DeliveryLog.info(
                "PASTE_VERIFY \(verdict.logDescription) app=\(app) before[\(before.summary)] " +
                    "elapsedMs=\(Int(((now - pastedAt) * 1000).rounded()))"
            )
            guard case .notLanded = verdict else { return }
            // Only clipboard changes since the paste that were our own (its restore) may be
            // replaced by the backup; anything the user copied in the meantime stays.
            TypingService.reportDeliveryFailure(
                .pasteNotLanded,
                transcript: text,
                inHistory: transcriptInHistory,
                since: pasteRevision,
                pasteSession: pasteSession,
                traceID: traceID
            )
        }
    }

    private func insertTextInstantly(
        _ text: String,
        preferredTargetPID: pid_t?,
        terminalPID: pid_t?,
        route: DeliveryRoute,
        terminalSendKey: SendKeyStep?,
        terminalSendKeyOutcome: inout SendKeyOutcome?,
        beforeClipboardDispatch: () -> Void
    ) -> InsertionOutcome {
        self.log("[TypingService] insertTextInstantly called with \(text.count) characters")
        self.log("[TypingService] Attempting to type text: \"\(text.prefix(50))\(text.count > 50 ? "..." : "")\"")

        if route.pastesFirst {
            // c11 and Ghostty silently drop direct CGEvent text, so a terminal never falls back
            // to it: when every clipboard path fails, the failure is reported and the transcript
            // kept instead of typing into the void.
            let pastePID = terminalPID ?? preferredTargetPID
            self.log("[TypingService] Clipboard paste first (terminal=\(terminalPID != nil), PID \(pastePID.map { String($0) } ?? "nil"))")
            let attempt = self.tryReliablePasteInsertion(
                text,
                preferredTargetPID: pastePID,
                allowsGlobalFallback: route.fallsBackToGlobalPaste,
                terminalSendKey: terminalSendKey,
                terminalSendKeyOutcome: &terminalSendKeyOutcome,
                beforeDispatch: beforeClipboardDispatch
            )
            if let path = attempt.path {
                self.log("[TypingService] SUCCESS: Reliable Paste completed via \(path.rawValue)")
                return .dispatched(path)
            }
            guard route.fallsBackToDirectTyping else {
                self.log("[TypingService] Reliable Paste failed; this target never falls back to direct typing")
                return .failed(attempt.failure ?? .pasteCommandFailed)
            }
            self.log("[TypingService] Reliable Paste fell through to direct-typing fallbacks")
        } else if let preferredTargetPID, preferredTargetPID > 0 {
            self.log("[TypingService] Experimental Direct Typing mode: trying preferred PID unicode insertion first")
            if self.insertTextBulkInstant(text, targetPID: preferredTargetPID) {
                self.log("[TypingService] SUCCESS: Preferred PID CGEvent insertion completed")
                return .dispatched(.directToPID)
            }
            self.log("[TypingService] Preferred PID CGEvent insertion failed, continuing fallback pipeline")
        }

        // Get frontmost app info
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            self.log("[TypingService] Target app: \(frontApp.localizedName ?? "Unknown") (\(frontApp.bundleIdentifier ?? "Unknown"))")
        } else {
            self.log("[TypingService] WARNING: Could not get frontmost application")
        }

        // Determine the actual focused element + owning PID (more reliable than "frontmost app" for floating launchers)
        let focusInfo = self.getSystemFocusedElementAndPID()
        if let focusedPID = focusInfo?.pid {
            self.log("[TypingService] Focused AX element PID: \(focusedPID)")
        } else {
            self.log("[TypingService] WARNING: Could not determine focused AX element PID")
        }
        Self.logFocusState("[TypingService] Before insertion pipeline")

        if let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            self.log("[TypingService] Frontmost PID: \(frontPID)")
        }

        // Check if we have permission to create events
        self.log("[TypingService] Accessibility trusted: \(AXIsProcessTrusted())")

        // Primary: Try CGEvent unicode insertion, targeting the focused PID when available
        // This is the most reliable method for Terminals, Electron apps (Discord, VSCode), etc.
        if let focusedPID = focusInfo?.pid {
            self.log("[TypingService] Trying CGEvent insertion targeting focused PID \(focusedPID)")
            if self.insertTextBulkInstant(text, targetPID: focusedPID) {
                self.log("[TypingService] SUCCESS: CGEvent focused-PID insertion completed")
                return .dispatched(.directToPID)
            }
        }

        // Secondary: Try Accessibility insertion into the actual focused element
        self.log("[TypingService] Trying Accessibility focused-element insertion")
        if self.insertTextViaAccessibility(text) {
            self.log("[TypingService] SUCCESS: Accessibility insertion completed")
            return .dispatched(.accessibility)
        }

        // HID Fallback if PID targeting failed
        if focusInfo?.pid == nil {
            self.log("[TypingService] No focused PID available, trying HID CGEvent insertion")
            if self.insertTextBulkHIDInstant(text) {
                self.log("[TypingService] SUCCESS: CGEvent HID insertion completed")
                return .dispatched(.directHID)
            }
        }

        // Fallback: Use clipboard-based insertion (more reliable)
        self.log("[TypingService] CGEvent failed, trying clipboard fallback")
        if self.insertTextViaClipboard(text, beforeDispatch: beforeClipboardDispatch) == nil {
            self.log("[TypingService] SUCCESS: Clipboard insertion completed")
            return .dispatched(.clipboardGlobal)
        }

        // Last resort: Character-by-character
        self.log("[TypingService] WARNING: All methods failed, trying character-by-character")
        for (index, char) in text.enumerated() {
            if index % 10 == 0 {
                self.log("[TypingService] Typing character \(index + 1)/\(text.count)")
            }
            self.typeCharacter(char)
            usleep(1000)
        }
        self.log("[TypingService] Character-by-character typing completed")
        return .dispatched(.characterByCharacter)
    }

    /// Tries the clipboard paths in order. Returns the path that dispatched, or the last failure.
    private func tryReliablePasteInsertion(
        _ text: String,
        preferredTargetPID: pid_t?,
        allowsGlobalFallback: Bool = true,
        terminalSendKey: SendKeyStep?,
        terminalSendKeyOutcome: inout SendKeyOutcome?,
        beforeDispatch: () -> Void
    ) -> (path: InsertionPath?, failure: TextDeliveryFailure?) {
        var lastFailure: TextDeliveryFailure?
        if let preferredTargetPID, preferredTargetPID > 0 {
            self.log("[TypingService] Trying clipboard-to-PID insertion first")
            lastFailure = self.insertTextViaClipboardToPid(
                text,
                targetPID: preferredTargetPID,
                terminalSendKey: terminalSendKey,
                terminalSendKeyOutcome: &terminalSendKeyOutcome,
                beforeDispatch: beforeDispatch
            )
            if lastFailure == nil {
                self.log("[TypingService] Reliable Paste dispatched via clipboard-to-PID")
                return (.clipboardToPID, nil)
            }
            // A terminal that is not in front must not get a global Cmd+V either: it would go
            // to whatever app is in front instead.
            if lastFailure == .targetRestoreFailed || !allowsGlobalFallback {
                return (nil, lastFailure)
            }
        }

        self.log("[TypingService] Trying global clipboard insertion")
        lastFailure = self.insertTextViaClipboard(text, beforeDispatch: beforeDispatch)
        if lastFailure == nil {
            self.log("[TypingService] Reliable Paste dispatched via global clipboard paste")
            return (.clipboardGlobal, nil)
        }

        self.log("[TypingService] Global clipboard insertion failed, trying menu paste")
        lastFailure = self.insertTextViaMenuPaste(text, beforeDispatch: beforeDispatch)
        if lastFailure == nil {
            self.log("[TypingService] Reliable Paste dispatched via menu paste")
            return (.menuPaste, nil)
        }

        return (nil, lastFailure)
    }

    private static let cgEventUnicodeChunkSize = 200

    private static func storeFocusSnapshot(_ snapshot: FocusSnapshot?) {
        self.focusSnapshotQueue.sync {
            Self.focusSnapshot = snapshot
        }
    }

    private static func loadFocusSnapshot() -> FocusSnapshot? {
        self.focusSnapshotQueue.sync { Self.focusSnapshot }
    }

    private nonisolated static func copyAXElementAttribute(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func stringAXAttribute(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private static func currentFocusDebugDescription() -> String {
        let systemWideElement = Self.boundedSystemWideElement()
        var focusedElementRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard result == .success, let focusedElementRef else {
            return "focusedElement=unavailable result=\(result.rawValue)"
        }
        guard CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else {
            return "focusedElement=unexpectedType"
        }

        let element = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let role = Self.stringAXAttribute(from: element, attribute: kAXRoleAttribute as CFString) ?? "unknown"
        let subrole = Self.stringAXAttribute(from: element, attribute: kAXSubroleAttribute as CFString) ?? "none"
        let title = Self.stringAXAttribute(from: element, attribute: kAXTitleAttribute as CFString) ?? "none"
        let description = Self.stringAXAttribute(from: element, attribute: kAXDescriptionAttribute as CFString) ?? "none"
        return "focusedPID=\(pid) role=\(role) subrole=\(subrole) title=\(title) description=\(description)"
    }

    private static func logFocusState(_ prefix: String) {
        guard self.isLoggingEnabled else { return }
        DebugLogger.shared.debug("\(prefix) | \(self.currentFocusDebugDescription())", source: "TypingService")
    }

    private nonisolated static func isCurrentlyFocusedElement(_ expectedElement: AXUIElement, expectedPID: pid_t) -> Bool {
        let systemWideElement = Self.boundedSystemWideElement()
        var focusedElementRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard result == .success, let focusedElementRef else { return false }
        guard CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else { return false }

        let currentElement = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        if CFEqual(currentElement, expectedElement) { return true }

        var currentPID: pid_t = 0
        AXUIElementGetPid(currentElement, &currentPID)
        guard currentPID == expectedPID else { return false }

        var currentRoleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(
            currentElement,
            kAXRoleAttribute as CFString,
            &currentRoleRef
        )
        guard roleResult == .success, let currentRole = currentRoleRef as? String else { return false }
        return ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXWebArea", "AXGroup"].contains(currentRole)
    }

    /// How long a clipboard paste keeps the transcript on the pasteboard before the user's
    /// clipboard comes back. Terminals consume a paste within ~100 ms and expose no verifiable
    /// AX text; other apps are watched until the text shows up in the field, up to 5 s. Called by
    /// the paste session while it owns the pasteboard, so the field baseline is read after any
    /// earlier queued paste has landed.
    private func pasteConsumptionWait(isTerminalTarget: Bool, expectedText: String) -> () -> Void {
        // With a send key following, the app has read the paste by the time it takes the key
        // (events reach it in order), and the key empties the field the wait would watch.
        if isTerminalTarget || self.sendKeyFollowsCurrentDelivery {
            return { usleep(1_000_000) }
        }
        let focusedTextSnapshot = self.captureFocusedTextSnapshot()
        return {
            let verification = self.waitForFocusedTextVerification(
                from: focusedTextSnapshot,
                expectedText: expectedText,
                timeoutMicros: 5_000_000
            )
            DeliveryLog.info("paste_consumption_wait result=\(verification.rawValue)")
        }
    }

    /// Clipboard-paste insertion targeted at a specific PID.
    /// Uses postToPid for Cmd+V while preserving the full previous pasteboard payload.
    private func insertTextViaClipboardToPid(
        _ text: String,
        targetPID: pid_t,
        activateTargetFirst: Bool = true,
        terminalSendKey: SendKeyStep? = nil,
        terminalSendKeyOutcome: inout SendKeyOutcome?,
        beforeDispatch: () -> Void = {}
    ) -> TextDeliveryFailure? {
        self.log("[TypingService] Starting clipboard-to-PID insertion to PID \(targetPID)")

        guard targetPID > 0 else {
            self.log("[TypingService] ERROR: Invalid target PID \(targetPID)")
            return .targetUnavailable
        }

        // Terminals consume a paste within ~100ms and expose no verifiable AX text, so
        // holding the pasteboard session for the full 5s verification window only stalls
        // (and previously dropped) back-to-back dictations.
        let isTerminalTarget = self.isGhosttyApplication(pid: targetPID)

        if isTerminalTarget {
            let pasteKeyCode = Self.pasteVirtualKeyCode
            let paster = TerminalPaster(session: self.pasteSession) { pid in
                let events = PasteCommandEvents.makeTargetedPasteEvents(pasteKeyCode: pasteKeyCode)
                guard events.count == 2 else { return false }
                events[0].postToPid(pid)
                usleep(10_000)
                events[1].postToPid(pid)
                return true
            }
            guard let terminalSendKey else {
                return paster.paste(
                    text,
                    to: targetPID,
                    activateFirst: activateTargetFirst,
                    beforeDispatch: beforeDispatch,
                    makeConsumptionWait: { self.pasteConsumptionWait(isTerminalTarget: true, expectedText: text) }
                )
            }
            let pasted = paster.pasteThenSend(
                text,
                to: targetPID,
                activateFirst: activateTargetFirst,
                send: terminalSendKey,
                beforeDispatch: beforeDispatch,
                makeConsumptionWait: { self.pasteConsumptionWait(isTerminalTarget: true, expectedText: text) }
            )
            terminalSendKeyOutcome = pasted.sendKey
            return pasted.failure
        }
        if activateTargetFirst, NSWorkspace.shared.frontmostApplication?.processIdentifier != targetPID {
            _ = Self.activateApp(pid: targetPID)
            usleep(80_000)
        }

        let failure = self.pasteSession.paste(
            text,
            dispatch: {
                let events = PasteCommandEvents.makeTargetedPasteEvents(pasteKeyCode: Self.pasteVirtualKeyCode)
                guard events.count == 2 else {
                    self.log("[TypingService] ERROR: Failed to create Cmd+V events for PID insertion")
                    return false
                }
                events[0].postToPid(targetPID)
                usleep(10_000)
                events[1].postToPid(targetPID)
                self.log("[TypingService] Cmd+V posted to PID \(targetPID)")
                return true
            },
            makeConsumptionWait: {
                beforeDispatch()
                return self.pasteConsumptionWait(isTerminalTarget: false, expectedText: text)
            }
        )
        if let failure {
            self.decision("clipboard_pid_failed reason=\(failure.rawValue)")
        }
        return failure
    }

    /// The c11/Ghostty paste: Cmd+V posted straight to the terminal's PID, only while the
    /// terminal is really in front, through the clipboard session. Dependencies are injectable
    /// so the guarantees are tested without posting keystrokes.
    nonisolated struct TerminalPaster {
        let session: ClipboardPasteSession
        /// Posts the Cmd+V pair to the PID; reports whether the events were created.
        let postPaste: (pid_t) -> Bool
        var isInFront: (pid_t) -> Bool = { TypingService.isAppInFront(pid: $0) }
        var bringToFront: (pid_t) -> Void = { _ = TypingService.bringToFront(pid: $0) }
        var frontmostWaitLimit: TimeInterval = TypingService.frontmostWaitLimit
        var pollInterval: TimeInterval = 0.025
        var retryDelay: TimeInterval = 0.05

        init(session: ClipboardPasteSession, postPaste: @escaping (pid_t) -> Bool) {
            self.session = session
            self.postPaste = postPaste
        }

        /// Returns nil once the paste is sent. `.targetRestoreFailed` when the terminal is not in
        /// front (nothing is sent; the clipboard is left or put back as it was). A clipboard
        /// race (snapshot or write) is retried once; a terminal that is not in front never is.
        /// `atDispatch` runs right before the dispatch instant's frontmost look and the Cmd+V.
        func paste(
            _ text: String,
            to pid: pid_t,
            activateFirst: Bool,
            beforeDispatch: () -> Void,
            makeConsumptionWait: () -> () -> Void,
            atDispatch: () -> Void = {}
        ) -> TextDeliveryFailure? {
            let first = self.attempt(
                text, to: pid, activateFirst: activateFirst, beforeDispatch: beforeDispatch,
                makeConsumptionWait: makeConsumptionWait, atDispatch: atDispatch
            )
            guard let first, Self.isClipboardRace(first) else { return first }
            DeliveryLog.info("terminal_paste_retry reason=\(first.rawValue)")
            usleep(useconds_t(self.retryDelay * 1_000_000))
            return self.attempt(
                text, to: pid, activateFirst: activateFirst, beforeDispatch: beforeDispatch,
                makeConsumptionWait: makeConsumptionWait, atDispatch: atDispatch
            )
        }

        static func isClipboardRace(_ failure: TextDeliveryFailure) -> Bool {
            failure == .clipboardSnapshotFailed || failure == .clipboardWriteFailed
        }

        /// Spoken Send in c11: the paste, then the send key, strictly after the paste's V key-up,
        /// to the same PID, behind the same frontmost gate, at most once. No paste, no key: a
        /// refused or failed paste returns its failure and `.textNotDelivered`. The clipboard
        /// race retry cannot double the key either: a race fails before anything is sent, and the
        /// key follows only the one paste that went out.
        ///
        /// The frontmost gate sees c11, not the pane. So the key also needs the pane focused at
        /// stop to be the focused one right before the paste and again right before the key, and
        /// no key press or click since the stop (Cmd+2, a click into a shell pane). Otherwise the
        /// text still lands where focus is, and the key is dropped.
        func pasteThenSend(
            _ text: String,
            to pid: pid_t,
            activateFirst: Bool,
            send: SendKeyStep,
            beforeDispatch: () -> Void,
            makeConsumptionWait: () -> () -> Void
        ) -> (failure: TextDeliveryFailure?, sendKey: SendKeyOutcome) {
            var focusAtPaste: TargetFocus?
            if let failure = self.paste(
                text,
                to: pid,
                activateFirst: activateFirst,
                beforeDispatch: beforeDispatch,
                makeConsumptionWait: makeConsumptionWait,
                atDispatch: { focusAtPaste = send.targetFocus() }
            ) {
                return (failure, .textNotDelivered)
            }
            return (nil, self.pressSendKey(send, to: pid, focusAtPaste: focusAtPaste ?? .unreadable))
        }

        /// The send key with nothing pasted first (the dictation was only the phrase): brought
        /// forward like a paste, then the same gates.
        func pressSendKeyAlone(_ send: SendKeyStep, to pid: pid_t) -> SendKeyOutcome {
            if !self.isInFront(pid) {
                self.bringToFront(pid)
            }
            let wait = self.waitUntilInFront(pid)
            TypingService.logFrontmostCheck(stage: "before_send_key_alone", target: pid, waitedMs: wait.waitedMs, inFront: wait.inFront)
            guard wait.inFront else { return .targetNotInFront }
            return self.pressSendKey(send, to: pid, focusAtPaste: .same)
        }

        private func pressSendKey(_ send: SendKeyStep, to pid: pid_t, focusAtPaste: TargetFocus) -> SendKeyOutcome {
            if send.delay > 0 {
                usleep(useconds_t(send.delay * 1_000_000))
            }
            guard send.modifiersReleased() else { return .modifiersHeld }
            guard !send.userActedSince(send.inputCutoff) else {
                DeliveryLog.info("send_key_refused reason=user_acted pid=\(pid)")
                return .userActed
            }
            // The paste's gate, looked at again right before the key: never press Return blind.
            guard self.isInFront(pid) else {
                TypingService.logFrontmostCheck(stage: "before_send_key", target: pid, waitedMs: 0, inFront: false)
                return .targetNotInFront
            }
            let focusNow = send.targetFocus()
            if let refusal = TargetFocus.worst([focusAtPaste, focusNow]).outcome {
                DeliveryLog.info(
                    "send_key_refused reason=\(refusal.rawValue) pid=\(pid) atPaste=\(focusAtPaste.rawValue) now=\(focusNow.rawValue)"
                )
                return refusal
            }
            return send.post(pid, send.key) ? .sent : .eventsUnavailable
        }

        private func attempt(
            _ text: String,
            to pid: pid_t,
            activateFirst: Bool,
            beforeDispatch: () -> Void,
            makeConsumptionWait: () -> () -> Void,
            atDispatch: () -> Void
        ) -> TextDeliveryFailure? {
            // A Cmd+V posted to a terminal that is not in front is dropped without a trace, so
            // the terminal must really be in front before the paste, not merely asked to come.
            if activateFirst, !self.isInFront(pid) {
                self.bringToFront(pid)
            }
            let wait = self.waitUntilInFront(pid)
            TypingService.logFrontmostCheck(stage: "before_paste", target: pid, waitedMs: wait.waitedMs, inFront: wait.inFront)
            guard wait.inFront else { return .targetRestoreFailed }

            var leftFront = false
            let failure = self.session.paste(
                text,
                dispatch: {
                    // Before the last look, so a slow read here (Spoken Send's AX focus check)
                    // cannot open a gap between the look and the Cmd+V.
                    atDispatch()
                    // Last look, with the transcript already on the clipboard: never send blind.
                    guard self.isInFront(pid) else {
                        leftFront = true
                        TypingService.logFrontmostCheck(stage: "at_dispatch", target: pid, waitedMs: 0, inFront: false)
                        return false
                    }
                    return self.postPaste(pid)
                },
                makeConsumptionWait: {
                    beforeDispatch()
                    return makeConsumptionWait()
                }
            )
            if leftFront { return .targetRestoreFailed }
            if let failure {
                DeliveryLog.info("terminal_paste_failed reason=\(failure.rawValue)")
            }
            return failure
        }

        private func waitUntilInFront(_ pid: pid_t) -> (inFront: Bool, waitedMs: Int) {
            let startedAt = ProcessInfo.processInfo.systemUptime
            let deadline = startedAt + self.frontmostWaitLimit
            while !self.isInFront(pid) {
                if ProcessInfo.processInfo.systemUptime >= deadline {
                    return (false, Int(((ProcessInfo.processInfo.systemUptime - startedAt) * 1000).rounded()))
                }
                usleep(useconds_t(max(self.pollInterval, 0.001) * 1_000_000))
            }
            return (true, Int(((ProcessInfo.processInfo.systemUptime - startedAt) * 1000).rounded()))
        }
    }

    private func insertTextBulkInstant(_ text: String, targetPID: pid_t) -> Bool {
        self.log("[TypingService] Starting chunked bulk CGEvent insertion (NO CLIPBOARD) to PID \(targetPID)")

        guard targetPID > 0 else {
            self.log("[TypingService] ERROR: Invalid target PID \(targetPID)")
            return false
        }

        let utf16Array = Array(text.utf16)
        self.log("[TypingService] Converting \(text.count) characters to CGEvents (UTF16 count \(utf16Array.count))")

        return self.postUnicodeChunks(utf16Array, destinationDescription: "PID \(targetPID)") { event in
            event.postToPid(targetPID)
        }
    }

    private func insertTextBulkHIDInstant(_ text: String) -> Bool {
        self.log("[TypingService] Starting chunked bulk CGEvent insertion via HID (NO PID)")

        let utf16Array = Array(text.utf16)

        return self.postUnicodeChunks(utf16Array, destinationDescription: "HID tap") { event in
            event.post(tap: .cghidEventTap)
        }
    }

    private func postUnicodeChunks(
        _ utf16Array: [UInt16],
        destinationDescription: String,
        post: (CGEvent) -> Void
    ) -> Bool {
        guard utf16Array.isEmpty == false else { return true }

        let chunkCount: Int = utf16Array.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }

            var chunkStart = 0
            var chunkCount = 0
            while chunkStart < buffer.count {
                let chunkEnd = Self.unicodeChunkEnd(in: utf16Array, start: chunkStart)
                let chunkLength = chunkEnd - chunkStart

                guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
                else {
                    self.log("[TypingService] ERROR: Failed to create unicode chunk CGEvents")
                    return -1
                }

                let chunkPointer = baseAddress.advanced(by: chunkStart)
                keyDown.keyboardSetUnicodeString(stringLength: chunkLength, unicodeString: chunkPointer)
                keyUp.keyboardSetUnicodeString(stringLength: chunkLength, unicodeString: chunkPointer)

                // Events created with a nil source inherit the CURRENT hardware modifier
                // state. Dictation is stopped by a modifier hotkey (e.g. ⌥Space), and fast
                // local transcription can finish while the modifier is still physically held —
                // the target app then sees ⌥+<unicode> instead of plain text. Terminals
                // (Ghostty/c11) interpret that as a keybinding and silently drop the text.
                keyDown.flags = []
                keyUp.flags = []

                post(keyDown)
                post(keyUp)

                chunkStart = chunkEnd
                chunkCount += 1
            }
            return chunkCount
        }

        guard chunkCount >= 0 else { return false }

        self.log("[TypingService] Posted \(chunkCount) unicode CGEvent chunk(s) to \(destinationDescription) with chunkSize=\(Self.cgEventUnicodeChunkSize) interChunkDelayMs=0")
        return true
    }

    private static func unicodeChunkEnd(in utf16Array: [UInt16], start: Int) -> Int {
        var end = min(start + Self.cgEventUnicodeChunkSize, utf16Array.count)
        if end < utf16Array.count,
           end > start,
           Self.isHighSurrogate(utf16Array[end - 1]),
           Self.isLowSurrogate(utf16Array[end])
        {
            end -= 1
        }
        return max(end, start + 1)
    }

    private static func isHighSurrogate(_ value: UInt16) -> Bool {
        (0xd800...0xdbff).contains(value)
    }

    private static func isLowSurrogate(_ value: UInt16) -> Bool {
        (0xdc00...0xdfff).contains(value)
    }

    /// Clipboard-based text insertion as fallback
    /// More reliable but slightly slower - copies text to clipboard then pastes
    private func insertTextViaClipboard(_ text: String, beforeDispatch: () -> Void = {}) -> TextDeliveryFailure? {
        self.log("[TypingService] Starting clipboard-based insertion")
        let failure = self.pasteSession.paste(
            text,
            dispatch: {
                // Command down, V down, V up, Command up: Command is always released again.
                let events = PasteCommandEvents.makeGlobalPasteEvents(pasteKeyCode: Self.pasteVirtualKeyCode)
                guard events.count == 4 else {
                    self.log("[TypingService] ERROR: Failed to create Cmd+V events")
                    return false
                }
                for event in events {
                    event.post(tap: .cghidEventTap)
                }
                self.log("[TypingService] Cmd+V sent via clipboard insertion")
                return true
            },
            makeConsumptionWait: {
                beforeDispatch()
                return self.pasteConsumptionWait(isTerminalTarget: false, expectedText: text)
            }
        )
        if let failure {
            self.decision("clipboard_global_failed reason=\(failure.rawValue)")
        }
        return failure
    }

    private func insertTextViaMenuPaste(_ text: String, beforeDispatch: () -> Void = {}) -> TextDeliveryFailure? {
        self.log("[TypingService] Starting menu-based paste insertion")
        guard let appName = NSWorkspace.shared.frontmostApplication?.localizedName, !appName.isEmpty else {
            self.log("[TypingService] ERROR: No frontmost app name available for menu paste")
            return .targetUnavailable
        }

        let failure = self.pasteSession.paste(
            text,
            dispatch: {
                let escapedAppName = appName.replacingOccurrences(of: "\"", with: "\\\"")
                let script = """
                tell application "System Events"
                    tell process "\(escapedAppName)"
                        click menu item "Paste" of menu "Edit" of menu bar 1
                    end tell
                end tell
                """

                guard let appleScript = NSAppleScript(source: script) else {
                    self.log("[TypingService] ERROR: Failed to create AppleScript for menu paste")
                    return false
                }

                var errorInfo: NSDictionary?
                let result = appleScript.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    self.log("[TypingService] ERROR: Menu paste AppleScript failed: \(errorInfo)")
                    return false
                }

                self.log("[TypingService] Menu paste executed for app \(appName), result: \(result.stringValue ?? "ok")")
                return true
            },
            makeConsumptionWait: {
                beforeDispatch()
                return self.pasteConsumptionWait(isTerminalTarget: false, expectedText: text)
            }
        )
        if let failure {
            self.decision("menu_paste_failed reason=\(failure.rawValue)")
        }
        return failure
    }

    private func insertTextViaAccessibility(_ text: String) -> Bool {
        self.log("[TypingService] Starting Accessibility API insertion")

        // Try multiple strategies to find text input element

        // Strategy 1: Get focused element directly (system-wide)
        self.log("[TypingService] Strategy 1: Getting focused UI element...")
        if let textElement = getFocusedTextElement() {
            self.log("[TypingService] Found focused text element")
            if self.tryAllTextInsertionMethods(textElement, text) {
                return true
            }
        }

        // Strategy 2: Traverse frontmost app UI hierarchy to find text elements
        self.log("[TypingService] Strategy 2: Traversing app UI hierarchy...")
        if let textElement = findTextElementInFrontmostApp() {
            self.log("[TypingService] Found text element in app hierarchy")
            if self.tryAllTextInsertionMethods(textElement, text) {
                return true
            }
        }

        // Strategy 3: Find element with keyboard focus
        self.log("[TypingService] Strategy 3: Looking for keyboard focus...")
        if let textElement = findKeyboardFocusedElement() {
            self.log("[TypingService] Found keyboard focused element")
            if self.tryAllTextInsertionMethods(textElement, text) {
                return true
            }
        }

        self.log("[TypingService] All Accessibility API strategies failed")
        return false
    }

    private func getFocusedTextElement() -> AXUIElement? {
        let systemWideElement = Self.boundedSystemWideElement()
        var focusedElement: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if result == .success, let focusedElement {
            guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else { return nil }
            let axElement = unsafeBitCast(focusedElement, to: AXUIElement.self)
            if let role = getElementAttribute(axElement, kAXRoleAttribute as CFString) {
                self.log("[TypingService] Found focused element with role: \(role)")
                return axElement
            }
        } else {
            self.log("[TypingService] Could not get focused UI element - result: \(result.rawValue)")
        }

        return nil
    }

    private func findTextElementInFrontmostApp() -> AXUIElement? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            self.log("[TypingService] Could not get frontmost app")
            return nil
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        return self.findTextElementRecursively(appElement, depth: 0, maxDepth: 8)
    }

    private func findTextElementRecursively(_ element: AXUIElement, depth: Int, maxDepth: Int) -> AXUIElement? {
        if depth > maxDepth { return nil }

        // Check if this element is a text input element
        if let role = getElementAttribute(element, kAXRoleAttribute as CFString) {
            let textRoles = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXStaticText"]
            if textRoles.contains(role) {
                self.log("[TypingService] Found text element at depth \(depth) with role: \(role)")
                return element
            }
        }

        // Get children and search recursively
        var children: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)

        if result == .success, let childrenArray = children as? [AXUIElement] {
            for child in childrenArray.prefix(10) { // Limit to first 10 children per level
                if let found = findTextElementRecursively(child, depth: depth + 1, maxDepth: maxDepth) {
                    return found
                }
            }
        }

        return nil
    }

    private func findKeyboardFocusedElement() -> AXUIElement? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        var focusedElement: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if result == .success, let focusedElement {
            guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else { return nil }
            let axElement = unsafeBitCast(focusedElement, to: AXUIElement.self)
            if let role = getElementAttribute(axElement, kAXRoleAttribute as CFString) {
                self.log("[TypingService] Found app-level focused element with role: \(role)")
                return axElement
            }
        }

        return nil
    }

    private func tryAllTextInsertionMethods(_ element: AXUIElement, _ text: String) -> Bool {
        // Get element info for debugging
        if let role = getElementAttribute(element, kAXRoleAttribute as CFString) {
            self.log("[TypingService] Trying insertion on element with role: \(role)")

            if let title = getElementAttribute(element, kAXTitleAttribute as CFString) {
                self.log("[TypingService] Element title: \(title)")
            }
        }

        self.log("[TypingService] Trying approach 0: Insert at cursor via kAXSelectedTextRangeAttribute + kAXValueAttribute")
        if self.insertTextAtCursorUsingSelectedRange(element, text) {
            return true
        }

        // Try multiple approaches for text insertion
        self.log("[TypingService] Trying approach 1: Direct kAXValueAttribute")
        if self.setTextViaValue(element, text) {
            return true
        }

        self.log("[TypingService] Trying approach 2: kAXSelectedTextAttribute (replace selection)")
        if self.setTextViaSelection(element, text) {
            return true
        }

        self.log("[TypingService] Trying approach 3: Insert text at insertion point")
        if self.insertTextAtInsertionPoint(element, text) {
            return true
        }

        return false
    }

    private func getElementAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        if result == .success, let stringValue = value as? String {
            return stringValue
        }
        return nil
    }

    /// AX requests default to a 6-second messaging timeout when the target app's main
    /// thread is busy (a TUI mid-redraw, an app processing a paste). That stall sits on
    /// the typing worker and delays — previously dropped — subsequent dictations, so all
    /// AX reads in this pipeline are bounded to a fraction of a second instead.
    nonisolated static let axMessagingTimeoutSeconds: Float = 0.3

    /// The system-wide AX element with the bounded messaging timeout. Setting it on the
    /// system-wide element also applies it process-wide.
    nonisolated static func boundedSystemWideElement() -> AXUIElement {
        self.boundedAXElement(AXUIElementCreateSystemWide())
    }

    @discardableResult
    nonisolated static func boundedAXElement(_ element: AXUIElement) -> AXUIElement {
        AXUIElementSetMessagingTimeout(element, self.axMessagingTimeoutSeconds)
        return element
    }

    private func getSystemFocusedElementAndPID() -> (element: AXUIElement, pid: pid_t)? {
        let systemWideElement = Self.boundedSystemWideElement()
        var focusedElementRef: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)
        guard result == .success, let focusedElementRef else { return nil }
        guard CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() else { return nil }

        let element = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeoutSeconds)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid > 0 else { return nil }
        return (element: element, pid: pid)
    }

    private func getElementStringValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard result == .success, let str = value as? String else { return nil }
        return str
    }

    private func getSelectedTextRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard result == .success, let axValue = value else { return nil }
        guard CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }

        var range = CFRange()
        let ok = AXValueGetValue(unsafeBitCast(axValue, to: AXValue.self), .cfRange, &range)
        return ok ? range : nil
    }

    private func captureFocusedTextSnapshot() -> FocusedTextSnapshot? {
        guard let focusInfo = self.getSystemFocusedElementAndPID() else { return nil }
        let bundleIdentifier = NSRunningApplication(processIdentifier: focusInfo.pid)?.bundleIdentifier
        let appScriptSnapshot = self.captureAppScriptTextSnapshot(forBundleIdentifier: bundleIdentifier)
        return FocusedTextSnapshot(
            pid: focusInfo.pid,
            bundleIdentifier: bundleIdentifier,
            value: self.getElementStringValue(focusInfo.element),
            selectedRange: self.getSelectedTextRange(focusInfo.element),
            appScriptValue: appScriptSnapshot?.value,
            appScriptSelectedRange: appScriptSnapshot?.selectedRange
        )
    }

    private func captureTextBeforeCursorInFocusedField() -> String {
        guard let snapshot = self.captureFocusedTextSnapshot() else { return "" }

        if let scriptValue = snapshot.appScriptValue,
           let scriptRange = snapshot.appScriptSelectedRange
        {
            return Self.prefix(in: scriptValue, before: scriptRange.location)
        }

        if let value = snapshot.value,
           let selectedRange = snapshot.selectedRange
        {
            return Self.prefix(in: value, before: selectedRange.location)
        }

        return ""
    }

    private static func prefix(in text: String, before location: Int) -> String {
        let nsText = text as NSString
        let safeLocation = max(0, min(location, nsText.length))
        guard safeLocation > 0 else { return "" }
        return nsText.substring(with: NSRange(location: 0, length: safeLocation))
    }

    private struct AppScriptTextSnapshot {
        let value: String?
        let selectedRange: CFRange?
    }

    private func waitForFocusedTextVerification(
        from snapshot: FocusedTextSnapshot?,
        expectedText: String,
        timeoutMicros: useconds_t
    ) -> PasteVerificationResult {
        guard let snapshot else {
            usleep(timeoutMicros)
            return .unavailable
        }

        let pollMicros: useconds_t = 50_000
        let expectedLength = max(1, (expectedText as NSString).length)
        let tolerance = max(2, expectedLength / 5)
        var waited: useconds_t = 0

        while waited < timeoutMicros {
            usleep(pollMicros)
            waited += pollMicros

            guard let current = self.captureFocusedTextSnapshot(),
                  current.pid == snapshot.pid
            else {
                continue
            }

            if let currentValue = current.appScriptValue,
               currentValue.contains(expectedText),
               currentValue != snapshot.appScriptValue
            {
                return .appScriptContainsText
            }

            if let before = snapshot.appScriptSelectedRange,
               let after = current.appScriptSelectedRange,
               after.length == 0
            {
                let expectedCaretLocation = before.location + expectedLength
                let caretDelta = abs(after.location - expectedCaretLocation)
                if caretDelta <= tolerance {
                    return .appScriptCaretMovedExpectedDistance
                }
            }

            if let currentValue = current.value,
               currentValue.contains(expectedText),
               currentValue != snapshot.value
            {
                return .fieldContainsText
            }

            if let before = snapshot.selectedRange,
               let after = current.selectedRange,
               after.length == 0
            {
                let expectedCaretLocation = before.location + expectedLength
                let caretDelta = abs(after.location - expectedCaretLocation)
                if caretDelta <= tolerance {
                    return .caretMovedExpectedDistance
                }
            }
        }

        return .timeout
    }

    private func captureAppScriptTextSnapshot(forBundleIdentifier bundleIdentifier: String?) -> AppScriptTextSnapshot? {
        switch bundleIdentifier {
        case "com.apple.dt.Xcode":
            return self.captureXcodeScriptSnapshot()
        case "com.apple.Notes":
            return self.captureNotesScriptSnapshot()
        default:
            return nil
        }
    }

    private func captureXcodeScriptSnapshot() -> AppScriptTextSnapshot? {
        guard let value = self.runAppleScript("""
        tell application "Xcode"
            if (count of source documents) is 0 then return ""
            return text of source document 1
        end tell
        """) else {
            return nil
        }

        let selectedRange = self.runAppleScript("""
        tell application "Xcode"
            if (count of source documents) is 0 then return ""
            return selected character range of source document 1
        end tell
        """).flatMap(self.parseAppleScriptRange)

        return AppScriptTextSnapshot(value: value, selectedRange: selectedRange)
    }

    private func captureNotesScriptSnapshot() -> AppScriptTextSnapshot? {
        guard let value = self.runAppleScript("""
        tell application "Notes"
            set selectedNotes to selection as list
            if (count of selectedNotes) is 0 then return ""
            set noteId to id of item 1 of selectedNotes
            return plaintext of note id noteId
        end tell
        """) else {
            return nil
        }
        return AppScriptTextSnapshot(value: value, selectedRange: nil)
    }

    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            self.log("[TypingService] AppleScript verification failed: \(error)")
            return nil
        }
        return result.stringValue
    }

    private func parseAppleScriptRange(_ rawValue: String) -> CFRange? {
        let components = rawValue
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard components.count == 2 else { return nil }
        let start = max(0, components[0] - 1)
        let end = max(start, components[1] - 1)
        return CFRange(location: start, length: end - start)
    }

    private func insertTextAtCursorUsingSelectedRange(_ element: AXUIElement, _ text: String) -> Bool {
        guard let currentValue = self.getElementStringValue(element) else {
            self.log("[TypingService] Cursor insert failed: could not read kAXValueAttribute")
            return false
        }
        guard var range = self.getSelectedTextRange(element) else {
            self.log("[TypingService] Cursor insert failed: could not read kAXSelectedTextRangeAttribute")
            return false
        }

        // CFRange is in UTF16 units. Use NSString to apply NSRange safely.
        let currentNSString = currentValue as NSString
        let maxLen = currentNSString.length

        let safeLoc = max(0, min(range.location, maxLen))
        let safeLen = max(0, min(range.length, maxLen - safeLoc))
        range = CFRange(location: safeLoc, length: safeLen)

        let mutable = NSMutableString(string: currentValue)
        mutable.replaceCharacters(in: NSRange(location: range.location, length: range.length), with: text)
        let newValue = mutable as String

        let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFString)
        guard setResult == .success else {
            self.log("[TypingService] Cursor insert failed: setting kAXValueAttribute error \(setResult.rawValue)")
            return false
        }

        // Move caret to just after inserted text (best-effort)
        let insertedLen = (text as NSString).length
        var newRange = CFRange(location: range.location + insertedLen, length: 0)
        if let axRange = AXValueCreate(.cfRange, &newRange) {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
        }

        self.log("[TypingService] SUCCESS: Inserted text using selected range + value")
        return true
    }

    // Why is it working now? And why is it not working now?
    private func setTextViaValue(_ element: AXUIElement, _ text: String) -> Bool {
        let cfText = text as CFString
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, cfText)

        if result == .success {
            self.log("[TypingService] SUCCESS: Set text via kAXValueAttribute")
            return true
        } else {
            self.log("[TypingService] FAILED: kAXValueAttribute - error: \(result.rawValue)")
            return false
        }
    }

    private func setTextViaSelection(_ element: AXUIElement, _ text: String) -> Bool {
        // First, select all existing text
        let selectAllResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, "" as CFString)
        self.log("[TypingService] Select all result: \(selectAllResult.rawValue)")

        // Then replace the selection with our text
        let cfText = text as CFString
        let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, cfText)

        if result == .success {
            self.log("[TypingService] SUCCESS: Set text via kAXSelectedTextAttribute")
            return true
        } else {
            self.log("[TypingService] FAILED: kAXSelectedTextAttribute - error: \(result.rawValue)")
            return false
        }
    }

    private func insertTextAtInsertionPoint(_ element: AXUIElement, _ text: String) -> Bool {
        // Try to get the insertion point
        var insertionPoint: CFTypeRef?
        let getResult = AXUIElementCopyAttributeValue(element, kAXInsertionPointLineNumberAttribute as CFString, &insertionPoint)
        self.log("[TypingService] Get insertion point result: \(getResult.rawValue)")

        // Try to insert text using parameterized attribute
        let cfText = text as CFString
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, cfText)

        if result == .success {
            self.log("[TypingService] SUCCESS: Inserted text at insertion point")
            return true
        } else {
            self.log("[TypingService] FAILED: Insertion point method - error: \(result.rawValue)")
            return false
        }
    }

    private func typeCharacter(_ char: Character) {
        let charString = String(char)
        let utf16Array = Array(charString.utf16)

        // Create keyboard events for this character
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else {
            self.log("[TypingService] ERROR: Failed to create CGEvents for character: \(char)")
            return
        }

        // Set the unicode string for both events
        keyDownEvent.keyboardSetUnicodeString(stringLength: utf16Array.count, unicodeString: utf16Array)
        keyUpEvent.keyboardSetUnicodeString(stringLength: utf16Array.count, unicodeString: utf16Array)

        // Post the events
        keyDownEvent.post(tap: .cghidEventTap)
        usleep(2000) // Short delay between key down and up (2ms)
        keyUpEvent.post(tap: .cghidEventTap)
    }
}
