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
    /// is a Ghostty derivative with its own bundle ID, so it needs the same carve-out.
    nonisolated static let ghosttyFamilyBundleIdentifiers: Set<String> = [
        "com.mitchellh.ghostty",
        "com.stage11.c11",
    ]

    nonisolated static func isGhosttyFamily(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return self.ghosttyFamilyBundleIdentifiers.contains(bundleIdentifier)
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

        guard let bundleIdentifier = app.bundleIdentifier else { return false }
        return Self.ghosttyFamilyBundleIdentifiers.contains(bundleIdentifier)
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
    static let focusRestoreActivationOptions: NSApplication.ActivationOptions = [
        .activateIgnoringOtherApps,
    ]

    /// Best-effort: activates the app with the given PID, unless it's Fluid itself.
    @discardableResult
    static func activateApp(pid: pid_t) -> Bool {
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
    // @b0d64436 (restore the exact recording target) by altic-dev / grohith327. Liquid Voice
    // keeps every Accessibility read bounded, and a c11/Ghostty target counts as ready as soon
    // as the terminal app is focused: its panes take Cmd+V whatever element AX reports.

    enum FocusPreparationResult: String {
        case alreadyFocused = "already_focused"
        case restoredExactTarget = "restored_exact_target"
        case activatedForRecovery = "activated_for_recovery"
        case failed

        var isReady: Bool {
            self != .failed
        }
    }

    /// Read-only capture of the focused app, window and element. Unlike
    /// `captureSystemFocusedPID`, it does not replace the stored focus snapshot.
    static func captureDictationTarget() -> DictationTarget? {
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

    private static func frontmostDictationTarget() -> DictationTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return DictationTarget(pid: app.processIdentifier, bundleIdentifier: app.bundleIdentifier, window: nil, element: nil)
    }

    /// Read-only focus observation: the PID owning the focused element, else the frontmost app.
    static func currentFocusedPID() -> pid_t? {
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

    static func isTargetStillFocused(_ target: DictationTarget) -> Bool {
        guard AXIsProcessTrusted(), let element = target.element else { return false }
        return Self.isCurrentlyFocusedElement(element, expectedPID: target.pid)
    }

    /// Puts focus back on the captured target before delivery. Returns `.failed` only when the
    /// target app cannot be brought back, or its exact field cannot be re-focused.
    static func prepareTargetForDelivery(_ target: DictationTarget) async -> FocusPreparationResult {
        let isTerminal = Self.isGhosttyFamily(bundleIdentifier: target.bundleIdentifier)
        let focusedPID = self.currentFocusedPID()
        if target.pid == focusedPID,
           target.element == nil || isTerminal || self.isTargetStillFocused(target)
        {
            return .alreadyFocused
        }

        if await self.restoreExactTarget(target) {
            return .restoredExactTarget
        }

        guard self.activateApp(pid: target.pid) else { return .failed }
        try? await Task.sleep(nanoseconds: 50_000_000)
        if target.element == nil || isTerminal {
            // Nothing finer to restore: the app itself is the destination.
            return self.currentFocusedPID() == target.pid ? .activatedForRecovery : .failed
        }
        return await self.restoreExactTarget(target) ? .activatedForRecovery : .failed
    }

    private static func restoreExactTarget(_ target: DictationTarget) async -> Bool {
        guard AXIsProcessTrusted(), let element = target.element else { return false }

        Self.logFocusState("[TypingService] Before restoreExactTarget")
        let appElement = Self.boundedAXElement(AXUIElementCreateApplication(target.pid))
        if let window = target.window {
            _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            _ = AXUIElementSetAttributeValue(appElement, kAXMainWindowAttribute as CFString, window)
            _ = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, window)
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        for attempt in 0..<3 {
            let result = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            if result == .success, Self.isCurrentlyFocusedElement(element, expectedPID: target.pid) {
                Self.logFocusState("[TypingService] After restoreExactTarget success")
                return true
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
        }

        let isFocused = Self.isCurrentlyFocusedElement(element, expectedPID: target.pid)
        Self.logFocusState("[TypingService] After restoreExactTarget final result=\(isFocused)")
        return isFocused
    }

    // MARK: - Delivery failures

    /// Where a failed delivery is announced. The app shows the failure card; tests replace it.
    static var deliveryFailureHandler: (TextDeliveryFailure, String) -> Void = { failure, transcript in
        DeliveryFailureOverlayController.shared.show(failure: failure, transcript: transcript)
    }

    /// Keeps the transcript and tells the user. Safe to call from any thread.
    ///
    /// The transcript is put on the clipboard as an ordinary copy (it is already in history),
    /// unless the user copied something newer in the meantime, and the failure card appears
    /// with a Copy action. Nothing is dropped silently.
    nonisolated static func reportDeliveryFailure(
        _ failure: TextDeliveryFailure,
        transcript: String,
        pasteSession: ClipboardPasteSession = .shared
    ) {
        DeliveryLog.bench("delivery_failed reason=\(failure.rawValue) chars=\(transcript.count)")
        DeliveryLog.warning("Text delivery failed reason=\(failure.rawValue) chars=\(transcript.count)")
        guard failure.isUserVisible, !transcript.isEmpty else { return }
        pasteSession.keepTranscript(transcript)
        Task { @MainActor in
            TypingService.deliveryFailureHandler(failure, transcript)
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
    ///   - completion: called on the main actor once the attempt finishes. A failure has
    ///     already been reported to the user (card + transcript kept) by then.
    func typeOutputPlanInstantly(
        _ plan: DictationLiteralOutputPlan,
        preferredTargetPID: pid_t?,
        textReadyAt: TimeInterval?,
        tracksDictionaryCorrections: Bool = false,
        verifiesLanding: Bool = true,
        completion: ((TextDeliveryResult) -> Void)? = nil
    ) {
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
            self.bench("request_return reason=empty_text")
            self.log("[TypingService] ERROR: Empty text provided, aborting")
            completion?(.recoverableFailure(.emptyText))
            return
        }

        // Check accessibility permissions first
        guard AXIsProcessTrusted() else {
            self.bench("request_return reason=accessibility_not_trusted")
            self.log("[TypingService] ERROR: Accessibility permissions required for text injection")
            Self.reportDeliveryFailure(.accessibilityNotTrusted, transcript: text, pasteSession: self.pasteSession)
            completion?(.recoverableFailure(.accessibilityNotTrusted))
            return
        }

        self.log("[TypingService] Accessibility check passed, proceeding with text injection")
        self.pendingCountLock.lock()
        self.pendingInsertions += 1
        let queuedBehind = self.pendingInsertions - 1
        self.pendingCountLock.unlock()
        if queuedBehind > 0 {
            self.bench("request_queued behind=\(queuedBehind)")
            self.log("[TypingService] Insertion queued behind \(queuedBehind) in-flight operation(s)")
        }

        Self.typingWorkQueue.async {
            let workerStartedAt = ProcessInfo.processInfo.systemUptime
            self.bench("worker_start queueDelayMs=\(Self.elapsedMs(from: requestedAt, to: workerStartedAt))")

            var result: TextDeliveryResult = .recoverableFailure(.targetUnavailable)
            defer {
                let completedAt = ProcessInfo.processInfo.systemUptime
                self.pendingCountLock.lock()
                self.pendingInsertions -= 1
                self.pendingCountLock.unlock()
                self.bench(
                    "complete result=\(Self.describe(result)) totalMs=\(Self.elapsedMs(from: requestedAt, to: completedAt)) textReadyToCompleteMs=\(textReadyAt.map { String(Self.elapsedMs(from: $0, to: completedAt)) } ?? "nil")"
                )
                self.log("[TypingService] Typing operation completed")
                let finalResult = result
                if let completion {
                    Task { @MainActor in completion(finalResult) }
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
            result = self.deliver(text, preferredTargetPID: preferredTargetPID, verifiesLanding: verifiesLanding)
            self.bench(
                "insert_return result=\(Self.describe(result)) elapsedMs=\(Self.elapsedMs(since: insertStartedAt)) totalMs=\(Self.elapsedMs(since: requestedAt))"
            )
            if case let .recoverableFailure(failure) = result {
                Self.reportDeliveryFailure(failure, transcript: text, pasteSession: self.pasteSession)
            } else if tracksDictionaryCorrections {
                Task { @MainActor in
                    AutomaticDictionaryCorrectionTracker.shared.beginObservingInsertion(
                        text,
                        targetPID: preferredTargetPID
                    )
                }
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

    private func bench(_ message: String) {
        DebugLogger.shared.benchmark("TYPING_BENCH", message: message, source: "TypingBenchmark")
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
    private func deliver(_ text: String, preferredTargetPID: pid_t?, verifiesLanding: Bool) -> TextDeliveryResult {
        let terminalPID = self.ghosttyTargetPID(preferredTargetPID: preferredTargetPID)

        // Ported from altic-dev/FluidVoice@51e62364 / @a1a65772: refuse only when the focused
        // element certainly cannot take text (a button, a menu, static text). Terminals are
        // never refused: c11 and Ghostty draw their own surface and always take Cmd+V.
        if terminalPID == nil {
            let assessStartedAt = ProcessInfo.processInfo.systemUptime
            let assessment = DeliveryTargetAssessment.assessFocusedElement(messagingTimeout: Self.axMessagingTimeoutSeconds)
            self.bench("focus_assess \(assessment.logDescription) elapsedMs=\(Self.elapsedMs(since: assessStartedAt))")
            if assessment.isCertainlyNotEditable {
                return .recoverableFailure(.noEditableTarget)
            }
        } else {
            self.bench("focus_assess skipped reason=terminal_target")
        }

        // The read-back baseline costs AX reads, so it is taken only when the opt-in check
        // will run: clipboard paths, not terminals (no readable field text).
        let checksLanding = verifiesLanding && terminalPID == nil && SettingsStore.shared.showPasteCheckAlerts
        var verificationBaseline: PasteVerifier.Snapshot?
        let path = self.insertTextInstantly(
            text,
            preferredTargetPID: preferredTargetPID,
            terminalPID: terminalPID,
            beforeClipboardPaste: {
                if checksLanding, verificationBaseline == nil {
                    verificationBaseline = PasteVerifier.capture()
                }
            }
        )
        self.bench("insert_path path=\(path.rawValue)")

        if path.usesClipboard, let verificationBaseline {
            Self.verifyPasteLanded(
                text,
                before: verificationBaseline,
                pastedAt: ProcessInfo.processInfo.systemUptime,
                pasteSession: self.pasteSession
            )
        }
        return .dispatched
    }

    /// Off-worker read-back after a paste. Logs every verdict; only a certain `notLanded`
    /// reaches the user. Ported from altic-dev/FluidVoice@fadaed91 / @788d04b6.
    private nonisolated static func verifyPasteLanded(
        _ text: String,
        before: PasteVerifier.Snapshot,
        pastedAt: TimeInterval,
        pasteSession: ClipboardPasteSession
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
            TypingService.reportDeliveryFailure(.pasteNotLanded, transcript: text, pasteSession: pasteSession)
        }
    }

    private func insertTextInstantly(
        _ text: String,
        preferredTargetPID: pid_t?,
        terminalPID: pid_t?,
        beforeClipboardPaste: () -> Void
    ) -> InsertionPath {
        self.log("[TypingService] insertTextInstantly called with \(text.count) characters")
        self.log("[TypingService] Attempting to type text: \"\(text.prefix(50))\(text.count > 50 ? "..." : "")\"")

        if self.textInsertionMode == .standard, let terminalPID {
            self.log("[TypingService] Ghostty target detected in standard mode (PID \(terminalPID)); forcing Reliable Paste path")
            if let path = self.tryReliablePasteInsertion(text, preferredTargetPID: terminalPID, beforeClipboardPaste: beforeClipboardPaste) {
                self.log("[TypingService] SUCCESS: Ghostty Reliable Paste path completed")
                return path
            }
            self.log("[TypingService] Ghostty Reliable Paste path fell through to direct-typing fallbacks")
        }

        if self.textInsertionMode == .reliablePaste {
            self.log("[TypingService] Reliable Paste mode enabled")
            if let path = self.tryReliablePasteInsertion(text, preferredTargetPID: preferredTargetPID, beforeClipboardPaste: beforeClipboardPaste) {
                self.log("[TypingService] SUCCESS: Reliable Paste mode completed")
                return path
            }
            self.log("[TypingService] Reliable Paste mode fell through to direct-typing fallbacks")
        } else if let preferredTargetPID, preferredTargetPID > 0 {
            self.log("[TypingService] Experimental Direct Typing mode: trying preferred PID unicode insertion first")
            if self.insertTextBulkInstant(text, targetPID: preferredTargetPID) {
                self.log("[TypingService] SUCCESS: Preferred PID CGEvent insertion completed")
                return .directToPID
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
                return .directToPID
            }
        }

        // Secondary: Try Accessibility insertion into the actual focused element
        self.log("[TypingService] Trying Accessibility focused-element insertion")
        if self.insertTextViaAccessibility(text) {
            self.log("[TypingService] SUCCESS: Accessibility insertion completed")
            return .accessibility
        }

        // HID Fallback if PID targeting failed
        if focusInfo?.pid == nil {
            self.log("[TypingService] No focused PID available, trying HID CGEvent insertion")
            if self.insertTextBulkHIDInstant(text) {
                self.log("[TypingService] SUCCESS: CGEvent HID insertion completed")
                return .directHID
            }
        }

        // Fallback: Use clipboard-based insertion (more reliable)
        self.log("[TypingService] CGEvent failed, trying clipboard fallback")
        beforeClipboardPaste()
        if self.insertTextViaClipboard(text) {
            self.log("[TypingService] SUCCESS: Clipboard insertion completed")
            return .clipboardGlobal
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
        return .characterByCharacter
    }

    private func tryReliablePasteInsertion(
        _ text: String,
        preferredTargetPID: pid_t?,
        beforeClipboardPaste: () -> Void
    ) -> InsertionPath? {
        if let preferredTargetPID, preferredTargetPID > 0 {
            self.log("[TypingService] Trying clipboard-to-PID insertion first")
            beforeClipboardPaste()
            if self.insertTextViaClipboardToPid(text, targetPID: preferredTargetPID) {
                self.log("[TypingService] Reliable Paste dispatched via clipboard-to-PID")
                return .clipboardToPID
            }
        }

        self.log("[TypingService] Trying global clipboard insertion")
        beforeClipboardPaste()
        if self.insertTextViaClipboard(text) {
            self.log("[TypingService] Reliable Paste dispatched via global clipboard paste")
            return .clipboardGlobal
        }

        self.log("[TypingService] Global clipboard insertion failed, trying menu paste")
        if self.insertTextViaMenuPaste(text) {
            self.log("[TypingService] Reliable Paste dispatched via menu paste")
            return .menuPaste
        }

        return nil
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

    private static func copyAXElementAttribute(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
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

    private static func isCurrentlyFocusedElement(_ expectedElement: AXUIElement, expectedPID: pid_t) -> Bool {
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
    /// AX text; other apps are watched until the text shows up in the field, up to 5 s.
    private func pasteConsumptionWait(isTerminalTarget: Bool, expectedText: String) -> () -> Void {
        if isTerminalTarget {
            return { usleep(1_000_000) }
        }
        let focusedTextSnapshot = self.captureFocusedTextSnapshot()
        return {
            let verification = self.waitForFocusedTextVerification(
                from: focusedTextSnapshot,
                expectedText: expectedText,
                timeoutMicros: 5_000_000
            )
            DeliveryLog.bench("paste_consumption_wait result=\(verification.rawValue)")
        }
    }

    /// Clipboard-paste insertion targeted at a specific PID.
    /// Uses postToPid for Cmd+V while preserving the full previous pasteboard payload.
    private func insertTextViaClipboardToPid(_ text: String, targetPID: pid_t, activateTargetFirst: Bool = true) -> Bool {
        self.log("[TypingService] Starting clipboard-to-PID insertion to PID \(targetPID)")

        guard targetPID > 0 else {
            self.log("[TypingService] ERROR: Invalid target PID \(targetPID)")
            return false
        }

        if activateTargetFirst, NSWorkspace.shared.frontmostApplication?.processIdentifier != targetPID {
            _ = Self.activateApp(pid: targetPID)
            usleep(80_000)
        }

        // Terminals consume a paste within ~100ms and expose no verifiable AX text, so
        // holding the pasteboard session for the full 5s verification window only stalls
        // (and previously dropped) back-to-back dictations.
        let isTerminalTarget = self.isGhosttyApplication(pid: targetPID)
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
            holdUntilConsumed: self.pasteConsumptionWait(isTerminalTarget: isTerminalTarget, expectedText: text)
        )
        if let failure {
            self.bench("clipboard_pid_failed reason=\(failure.rawValue)")
        }
        return failure == nil
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
    private func insertTextViaClipboard(_ text: String) -> Bool {
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
            holdUntilConsumed: self.pasteConsumptionWait(isTerminalTarget: false, expectedText: text)
        )
        if let failure {
            self.bench("clipboard_global_failed reason=\(failure.rawValue)")
        }
        return failure == nil
    }

    private func insertTextViaMenuPaste(_ text: String) -> Bool {
        self.log("[TypingService] Starting menu-based paste insertion")
        guard let appName = NSWorkspace.shared.frontmostApplication?.localizedName, !appName.isEmpty else {
            self.log("[TypingService] ERROR: No frontmost app name available for menu paste")
            return false
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
            holdUntilConsumed: self.pasteConsumptionWait(isTerminalTarget: false, expectedText: text)
        )
        if let failure {
            self.bench("menu_paste_failed reason=\(failure.rawValue)")
        }
        return failure == nil
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
