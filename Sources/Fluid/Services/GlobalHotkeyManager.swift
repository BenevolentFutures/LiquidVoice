import AppKit
import Combine
import Foundation

nonisolated enum HotkeyHoldModeType: Hashable {
    case transcription
    case promptMode
    case commandMode
    case rewriteMode
    case promptAssignment
}

private nonisolated enum ActivePrimaryShortcutPress: Equatable {
    case keyboard(UInt16)
    case mouse(Int)
}

/// Snapshot of the modifier-only tracking state fed into `ModifierOnlyShortcutFlagsDecision`.
struct ModifierOnlyShortcutTrackingState: Equatable {
    /// Currently-pressed modifier key codes (output of `synchronizedPressedModifierKeyCodes`).
    let pressedModifierKeyCodes: Set<UInt16>
    /// The currently-active modifier-only mode, if any.
    let activeModifierOnlyType: HotkeyHoldModeType?
    /// The exact shortcut that owns the active modifier-only press.
    let activeModifierOnlyShortcut: HotkeyShortcut?
    /// Whether a non-configured key was pressed during the active modifier-only press.
    let otherKeyPressedDuringModifier: Bool
    /// Snapshot of the behavior's mode-key-pressed flag.
    let isModeKeyPressed: Bool
}

/// Pure, side-effect-free decision describing how a modifier-only shortcut responds to a single
/// `flagsChanged` event. Extracted from `GlobalHotkeyManager.handleModifierOnlyShortcutFlagsChanged`
/// so the modifier-only start/finish state machine is unit-testable without the global event tap.
struct ModifierOnlyShortcutFlagsDecision: Equatable {
    enum Outcome: Equatable {
        /// The event neither starts nor finishes the press.
        case ignore
        /// The configured modifier was pressed: arm the modifier-only press.
        case start
        /// The configured modifier was released: finish the press; a clean tap only when
        /// `wasCleanPress` is true.
        case finish(wasCleanPress: Bool)
    }

    let outcome: Outcome
    /// True when an extra modifier was pressed during an active press this event; the caller logs
    /// and marks the press interrupted.
    let markInterrupted: Bool
    /// Value `activeModifierOnlyType` should hold after this event.
    let activeModifierOnlyType: HotkeyHoldModeType?
    /// Shortcut that should own the active modifier-only press after this event.
    let activeModifierOnlyShortcut: HotkeyShortcut?
    /// Value `otherKeyPressedDuringModifier` should hold after this event.
    let otherKeyPressedDuringModifier: Bool

    /// Mirrors the decision logic of `handleModifierOnlyShortcutFlagsChanged`. Branch 1 handles
    /// shortcuts that carry explicit modifier key codes (e.g. a captured Left Option); branch 2
    /// handles the flag-only form.
    static func evaluate(
        shortcut: HotkeyShortcut,
        holdModeType: HotkeyHoldModeType,
        isEnabled: Bool,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        state: ModifierOnlyShortcutTrackingState
    ) -> ModifierOnlyShortcutFlagsDecision {
        let pressedModifierKeyCodes = state.pressedModifierKeyCodes
        let activeModifierOnlyType = state.activeModifierOnlyType
        let activeModifierOnlyShortcut = state.activeModifierOnlyShortcut
        let otherKeyPressedDuringModifier = state.otherKeyPressedDuringModifier
        let isModeKeyPressed = state.isModeKeyPressed

        guard isEnabled, shortcut.isModifierOnlyShortcut else {
            return .init(
                outcome: .ignore,
                markInterrupted: false,
                activeModifierOnlyType: activeModifierOnlyType,
                activeModifierOnlyShortcut: activeModifierOnlyShortcut,
                otherKeyPressedDuringModifier: otherKeyPressedDuringModifier
            )
        }

        let relevantModifiers = modifiers.intersection(HotkeyShortcut.relevantModifierMask)
        let expectedModifierKeyCodes = shortcut.normalizedModifierKeyCodes

        if !expectedModifierKeyCodes.isEmpty {
            let pressedKeyCodes = HotkeyShortcut.normalizedModifierKeyCodes(from: Array(pressedModifierKeyCodes))
            // Only arm on the FIRST press of the configured modifier itself. The `activeModifierOnlyType == nil`
            // precondition prevents a mid-press re-arm: without it, releasing an unrelated modifier (e.g. Shift)
            // or pressing a sibling modifier while the configured modifier is held can shrink `pressedModifierKeyCodes`
            // back to the expected set and re-enter this block, erasing `otherKeyPressedDuringModifier` so the
            // subsequent release reads as a clean tap and falsely starts recording (#688).
            if activeModifierOnlyType == nil,
               pressedKeyCodes == expectedModifierKeyCodes,
               expectedModifierKeyCodes.contains(keyCode)
            {
                return .init(
                    outcome: .start,
                    markInterrupted: false,
                    activeModifierOnlyType: holdModeType,
                    activeModifierOnlyShortcut: shortcut,
                    otherKeyPressedDuringModifier: false
                )
            }

            let isActiveModifierOnlyPress = activeModifierOnlyType == holdModeType && activeModifierOnlyShortcut == shortcut
            let isLegacyModePress = activeModifierOnlyShortcut == nil && isModeKeyPressed
            var markInterrupted = false
            if isActiveModifierOnlyPress || isLegacyModePress {
                let extraModifierKeyCodes = pressedKeyCodes.filter { !expectedModifierKeyCodes.contains($0) }
                markInterrupted = !extraModifierKeyCodes.isEmpty
            }

            guard isActiveModifierOnlyPress || isLegacyModePress,
                  expectedModifierKeyCodes.contains(keyCode),
                  !pressedKeyCodes.contains(keyCode)
            else {
                return .init(
                    outcome: .ignore,
                    markInterrupted: markInterrupted,
                    activeModifierOnlyType: activeModifierOnlyType,
                    activeModifierOnlyShortcut: activeModifierOnlyShortcut,
                    otherKeyPressedDuringModifier: markInterrupted ? true : otherKeyPressedDuringModifier
                )
            }

            let wasCleanPress = !(markInterrupted || otherKeyPressedDuringModifier)
            return .init(
                outcome: .finish(wasCleanPress: wasCleanPress),
                markInterrupted: markInterrupted,
                activeModifierOnlyType: nil,
                activeModifierOnlyShortcut: nil,
                otherKeyPressedDuringModifier: false
            )
        }

        guard let expectedPressedModifiers = shortcut.expectedModifierFlags,
              let triggerFlag = shortcut.modifierTriggerFlag
        else {
            return .init(
                outcome: .ignore,
                markInterrupted: false,
                activeModifierOnlyType: activeModifierOnlyType,
                activeModifierOnlyShortcut: activeModifierOnlyShortcut,
                otherKeyPressedDuringModifier: otherKeyPressedDuringModifier
            )
        }

        // Only arm on the FIRST press of a modifier that belongs to the shortcut. The
        // `activeModifierOnlyType == nil` precondition prevents a mid-press re-arm (same #688 class
        // as branch 1): a sibling-side modifier whose flag is in `expectedPressedModifiers` would
        // otherwise re-enter `.start` and erase `otherKeyPressedDuringModifier`. Matching the
        // modifier flag (not the literal key code) preserves the original side-agnostic start, so a
        // Left-Option-stored shortcut still arms on Right Option.
        if activeModifierOnlyType == nil,
           relevantModifiers == expectedPressedModifiers,
           let changedModifierFlag = HotkeyShortcut.modifierFlag(forKeyCode: keyCode),
           expectedPressedModifiers.contains(changedModifierFlag)
        {
            return .init(
                outcome: .start,
                markInterrupted: false,
                activeModifierOnlyType: holdModeType,
                activeModifierOnlyShortcut: shortcut,
                otherKeyPressedDuringModifier: false
            )
        }

        let isActiveModifierOnlyPress = activeModifierOnlyType == holdModeType && activeModifierOnlyShortcut == shortcut
        let isLegacyModePress = activeModifierOnlyShortcut == nil && isModeKeyPressed
        var markInterrupted = false
        if isActiveModifierOnlyPress || isLegacyModePress {
            let unexpectedModifiers = relevantModifiers.subtracting(expectedPressedModifiers)
            markInterrupted = !unexpectedModifiers.isEmpty
        }

        guard isActiveModifierOnlyPress || isLegacyModePress,
              keyCode == shortcut.keyCode,
              !relevantModifiers.contains(triggerFlag)
        else {
            return .init(
                outcome: .ignore,
                markInterrupted: markInterrupted,
                activeModifierOnlyType: activeModifierOnlyType,
                activeModifierOnlyShortcut: activeModifierOnlyShortcut,
                otherKeyPressedDuringModifier: markInterrupted ? true : otherKeyPressedDuringModifier
            )
        }

        let wasCleanPress = !(markInterrupted || otherKeyPressedDuringModifier)
        return .init(
            outcome: .finish(wasCleanPress: wasCleanPress),
            markInterrupted: markInterrupted,
            activeModifierOnlyType: nil,
            activeModifierOnlyShortcut: nil,
            otherKeyPressedDuringModifier: false
        )
    }
}

/// Remembers which mouse button's down a one-shot shortcut (paste last, reprocess last) consumed,
/// so only its paired up is swallowed. Any doubt clears it: an orphaned up reaching an app is
/// harmless, but swallowing a real up leaves the app thinking the button is still held (it drags).
nonisolated struct OneShotMouseUpSwallow: Equatable {
    private(set) var button: Int?

    mutating func consumedDown(button: Int) {
        self.button = button
    }

    /// Any down on the pending button proves its earlier up was missed (tap outage, capture).
    mutating func observedDown(button: Int) {
        if self.button == button { self.button = nil }
    }

    mutating func shouldSwallowUp(button: Int) -> Bool {
        guard self.button == button else { return false }
        self.button = nil
        return true
    }

    mutating func reset() {
        self.button = nil
    }
}

/// The task a hotkey's start callback dispatched to start a capture (ContentView's
/// `Task { await asr.start(...) }`), or nil when the callback started nothing.
typealias HotkeyCaptureStartTask = Task<Void, Never>

/// A hold-mode release must always end its recording. When the release arrives while the capture
/// is still starting (a direct Core Audio start can take seconds under DeadlineRace, before the
/// AVAudioEngine fallback), the stop is latched and honored the moment the start settles, through
/// the normal stop-and-transcribe path. It never cancels the start, which would drop the audio it
/// captures, and never gives up on a timer. A start that fails clears the latch.
///
/// "Starting" is explicit: `trackStart` counts a hotkey action as a start in flight from the
/// moment it is dispatched until the capture start it reports has finished. The latch does not
/// depend on when (after how many suspension points) the action or `ASRService.start()` first
/// becomes visible as `isStarting`.
@MainActor
final class HoldReleaseStopLatch {
    struct Request: Equatable {
        let type: HotkeyHoldModeType
        let label: String
        /// Skip the stop if a different recording mode is active by the time the start settles.
        /// A request without it (a tracking reset, an interrupted press) belongs to whatever start
        /// was in flight when it was made, so a newer starting press supersedes it.
        let requireTargetMode: Bool
        /// When the release happened; the stop-path trace starts here even when the stop waits.
        var releasedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    }

    enum Outcome: Equatable {
        case stoppedNow
        case latched
        case nothingToStop
    }

    private let isStarting: () -> Bool
    private let isRunning: () -> Bool
    private let isTargetActive: (HotkeyHoldModeType) -> Bool
    private let stop: (Request, _ wasLatched: Bool) -> Void
    private(set) var pending: [HotkeyHoldModeType: Request] = [:]
    /// Hotkey actions that may still start a capture ASR has not begun yet.
    private(set) var outstandingStartRequests = 0

    init(
        isStarting: @escaping () -> Bool,
        isRunning: @escaping () -> Bool,
        isTargetActive: @escaping (HotkeyHoldModeType) -> Bool,
        stop: @escaping (Request, _ wasLatched: Bool) -> Void
    ) {
        self.isStarting = isStarting
        self.isRunning = isRunning
        self.isTargetActive = isTargetActive
        self.stop = stop
    }

    var isStartInFlight: Bool {
        self.isStarting() || self.outstandingStartRequests > 0
    }

    /// A hotkey action that may start a capture was dispatched. A newer press supersedes any
    /// latched stop that is not bound to a recording mode.
    func startRequested() {
        self.outstandingStartRequests += 1
        let superseded = self.pending.filter { !$0.value.requireTargetMode }
        guard !superseded.isEmpty else { return }
        for type in superseded.keys {
            self.pending.removeValue(forKey: type)
        }
        DebugLogger.shared.info(
            "Release stop latch: a new starting press supersedes \(superseded.values.map(\.label))",
            source: "GlobalHotkeyManager"
        )
    }

    /// That action finished, and so did any capture start it dispatched.
    func startRequestSettled() {
        self.outstandingStartRequests = max(0, self.outstandingStartRequests - 1)
        self.resolve(reason: "start request settled")
    }

    /// Runs a hotkey action that may start a capture. The start counts as in flight from now
    /// until the capture start task the action returns has finished (or at once, if it returns
    /// nil), so a hold release that arrives at any point in between is latched, never lost.
    @discardableResult
    func trackStart(_ action: @escaping @MainActor () async -> HotkeyCaptureStartTask?) -> Task<Void, Never> {
        self.startRequested()
        return Task { @MainActor [weak self] in
            let captureStart = await action()
            await captureStart?.value
            self?.startRequestSettled()
        }
    }

    /// ASR finished a capture start, on either backend, successfully or not.
    func captureStartSettled() {
        self.resolve(reason: "capture start settled")
    }

    @discardableResult
    func release(_ request: Request) -> Outcome {
        if self.isRunning() {
            self.pending.removeValue(forKey: request.type)
            self.stop(request, false)
            return .stoppedNow
        }
        guard self.isStartInFlight else {
            self.pending.removeValue(forKey: request.type)
            return .nothingToStop
        }
        self.pending[request.type] = request
        DebugLogger.shared.info(
            "\(request.label) released while capture is starting - stop latched until the start settles",
            source: "GlobalHotkeyManager"
        )
        return .latched
    }

    /// A new press of the same shortcut supersedes its earlier release.
    func cancel(_ type: HotkeyHoldModeType) {
        self.pending.removeValue(forKey: type)
    }

    private func resolve(reason: String) {
        guard !self.pending.isEmpty, !self.isStartInFlight else { return }
        let requests = Array(self.pending.values)
        self.pending.removeAll()

        guard self.isRunning() else {
            DebugLogger.shared.info(
                "Release stop latch cleared (\(reason)) - the start did not produce a recording",
                source: "GlobalHotkeyManager"
            )
            return
        }
        guard let request = requests.first(where: { !$0.requireTargetMode || self.isTargetActive($0.type) }) else {
            DebugLogger.shared.debug(
                "Release stop latch skipped (\(reason)) - active mode changed",
                source: "GlobalHotkeyManager"
            )
            return
        }
        DebugLogger.shared.info(
            "\(request.label) release stop honored (\(reason)) - stopping now",
            source: "GlobalHotkeyManager"
        )
        self.stop(request, true)
    }
}

private final nonisolated class HotkeyState: @unchecked Sendable {
    private let lock = NSLock()
    var isKeyPressed = false
    var isPromptModeKeyPressed = false
    var isCommandModeKeyPressed = false
    var isRewriteKeyPressed = false
    var isPromptAssignmentKeyPressed = false
    var pressedModifierKeyCodes: Set<UInt16> = []
    var modifierOnlyKeyDown = false
    var activeModifierOnlyType: HotkeyHoldModeType?
    var activeModifierOnlyShortcut: HotkeyShortcut?
    var otherKeyPressedDuringModifier = false
    var modifierPressStartTime: Date?
    var holdModeStartTriggeredTypes: Set<HotkeyHoldModeType> = []
    var automaticPressStartTimes: [HotkeyHoldModeType: Date] = [:]
    var automaticPressWasTargetActive: [HotkeyHoldModeType: Bool] = [:]
    var automaticPressStartedTypes: Set<HotkeyHoldModeType> = []
    var activePrimaryShortcutPress: ActivePrimaryShortcutPress?
    var oneShotMouseUpSwallow = OneShotMouseUpSwallow()
    /// When the tap thread received the key event now being handled on main. Lets the stop-path
    /// trace start at the real release, before any wait for a busy main thread.
    var eventReceivedAt: TimeInterval?
    var keyboardEventTap: CFMachPort?

    func withLock<T>(_ block: () -> T) -> T {
        self.lock.lock()
        defer { self.lock.unlock() }
        return block()
    }
}

@MainActor
final class GlobalHotkeyManager: NSObject {
    private nonisolated(unsafe) var state = HotkeyState()
    /// The keyboard tap. Written on main, read on the tap thread (to re-enable it after macOS
    /// disables it), so it lives behind the state lock.
    private nonisolated var eventTap: CFMachPort? {
        get { self.state.withLock { self.state.keyboardEventTap } }
        set { self.state.withLock { self.state.keyboardEventTap = newValue } }
    }
    private nonisolated(unsafe) var runLoopSource: CFRunLoopSource?
    private nonisolated(unsafe) var mouseObserverTap: CFMachPort?
    private nonisolated(unsafe) var mouseObserverSource: CFRunLoopSource?
    private nonisolated(unsafe) var mouseShortcutTap: CFMachPort?
    private nonisolated(unsafe) var mouseShortcutSource: CFRunLoopSource?
    private nonisolated(unsafe) var monitoredMouseButtons: Set<Int> = []
    /// Dedicated run loop that services the keyboard tap, so a busy main thread
    /// never holds keystrokes (including our own synthesized paste) in the tap.
    private nonisolated(unsafe) var keyboardTapRunLoop: CFRunLoop?
    private nonisolated(unsafe) var keyboardTapThread: Thread?
    private let asrService: ASRService
    private var primaryShortcuts: [HotkeyShortcut]
    private var promptModeShortcut: HotkeyShortcut
    private var commandModeShortcut: HotkeyShortcut?
    private var rewriteModeShortcut: HotkeyShortcut
    private var promptShortcutAssignments: [(selection: SettingsStore.DictationPromptSelection, shortcut: HotkeyShortcut)]
    private var promptModeShortcutEnabled: Bool
    private var commandModeShortcutEnabled: Bool
    private var rewriteModeShortcutEnabled: Bool
    // Start callbacks return the task that runs the capture start they dispatched (nil if they
    // started nothing); the release-stop latch counts the start as in flight until it finishes.
    private var startRecordingCallback: (() async -> HotkeyCaptureStartTask?)?
    private var dictationModeCallback: (() async -> HotkeyCaptureStartTask?)?
    private var stopAndProcessCallback: (() async -> Void)?
    private var promptModeCallback: (() async -> HotkeyCaptureStartTask?)?
    private var promptSelectionCallback: ((SettingsStore.DictationPromptSelection) async -> HotkeyCaptureStartTask?)?
    private var commandModeCallback: (() async -> HotkeyCaptureStartTask?)?
    private var rewriteModeCallback: (() async -> HotkeyCaptureStartTask?)?
    private var isDictateRecordingProvider: (() -> Bool)?
    private var isPromptModeRecordingProvider: (() -> Bool)?
    private var isCommandRecordingProvider: (() -> Bool)?
    private var isRewriteRecordingProvider: (() -> Bool)?
    private var isShortcutCaptureActiveProvider: (() -> Bool)?
    private var cancelCallback: (() -> Bool)? // Returns true if handled
    /// Asked first when the cancel shortcut is pressed: drops a pending Spoken Send Return and
    /// returns true when one was showing (DESIGN.md §15), so the dictation goes on.
    private var spokenSendCancelCallback: (() -> Bool)?
    /// The cancel key's last press dropped a Spoken Send Return: its own auto-repeats are consumed
    /// and do nothing else (they must neither cancel the dictation nor reach the app).
    private var isSwallowingCancelKeyRepeats = false
    private var pasteLastTranscriptionCallback: (() -> Void)?
    private var reprocessLastDictationCallback: (() -> Void)?
    private var hotkeyMode: HotkeyActivationMode = SettingsStore.shared.hotkeyMode
    private let automaticTapThresholdSeconds: TimeInterval = 0.4

    private struct ModifierOnlyShortcutBehavior {
        let shortcut: HotkeyShortcut
        let isEnabled: Bool
        let holdModeType: HotkeyHoldModeType
        let holdStartMessage: String
        let holdReleaseMessage: String
        let toggleIgnoredMessage: String
        let isModeKeyPressed: () -> Bool
        let setModeKeyPressed: (Bool) -> Void
        let onHoldStart: () -> Void
        let onToggleRelease: () -> Void
        let isTargetModeActive: () -> Bool
    }

    enum ModifierTrackingResetReason {
        case shortcutCapture
        case tapDisabled
        case reinitialize
    }

    private nonisolated var isKeyPressed: Bool {
        get { self.state.withLock { self.state.isKeyPressed } }
        set { self.state.withLock { self.state.isKeyPressed = newValue } }
    }

    private nonisolated var isPromptModeKeyPressed: Bool {
        get { self.state.withLock { self.state.isPromptModeKeyPressed } }
        set { self.state.withLock { self.state.isPromptModeKeyPressed = newValue } }
    }

    private nonisolated var isCommandModeKeyPressed: Bool {
        get { self.state.withLock { self.state.isCommandModeKeyPressed } }
        set { self.state.withLock { self.state.isCommandModeKeyPressed = newValue } }
    }

    private nonisolated var isRewriteKeyPressed: Bool {
        get { self.state.withLock { self.state.isRewriteKeyPressed } }
        set { self.state.withLock { self.state.isRewriteKeyPressed = newValue } }
    }

    private nonisolated var isPromptAssignmentKeyPressed: Bool {
        get { self.state.withLock { self.state.isPromptAssignmentKeyPressed } }
        set { self.state.withLock { self.state.isPromptAssignmentKeyPressed = newValue } }
    }

    private nonisolated var activePrimaryShortcutPress: ActivePrimaryShortcutPress? {
        get { self.state.withLock { self.state.activePrimaryShortcutPress } }
        set { self.state.withLock { self.state.activePrimaryShortcutPress = newValue } }
    }

    private nonisolated var pressedModifierKeyCodes: Set<UInt16> {
        get { self.state.withLock { self.state.pressedModifierKeyCodes } }
        set { self.state.withLock { self.state.pressedModifierKeyCodes = newValue } }
    }

    /// Modifier-only shortcut tracking: detect if another key was pressed during modifier hold
    private nonisolated var modifierOnlyKeyDown: Bool {
        get { self.state.withLock { self.state.modifierOnlyKeyDown } }
        set { self.state.withLock { self.state.modifierOnlyKeyDown = newValue } }
    }

    private nonisolated var activeModifierOnlyType: HotkeyHoldModeType? {
        get { self.state.withLock { self.state.activeModifierOnlyType } }
        set { self.state.withLock { self.state.activeModifierOnlyType = newValue } }
    }

    private nonisolated var activeModifierOnlyShortcut: HotkeyShortcut? {
        get { self.state.withLock { self.state.activeModifierOnlyShortcut } }
        set { self.state.withLock { self.state.activeModifierOnlyShortcut = newValue } }
    }

    private nonisolated var otherKeyPressedDuringModifier: Bool {
        get { self.state.withLock { self.state.otherKeyPressedDuringModifier } }
        set { self.state.withLock { self.state.otherKeyPressedDuringModifier = newValue } }
    }

    /// Reserved for future tap-vs-hold timing detection (e.g., quick tap to toggle vs long hold)
    private nonisolated var modifierPressStartTime: Date? {
        get { self.state.withLock { self.state.modifierPressStartTime } }
        set { self.state.withLock { self.state.modifierPressStartTime = newValue } }
    }

    private func cancelPendingReleaseStop(for type: HotkeyHoldModeType) {
        self.holdReleaseStopLatch.cancel(type)
    }

    private func beginAutomaticPress(for type: HotkeyHoldModeType, wasTargetActive: Bool) {
        self.cancelPendingReleaseStop(for: type)
        self.state.withLock {
            self.state.automaticPressStartTimes[type] = Date()
            self.state.automaticPressWasTargetActive[type] = wasTargetActive
            _ = self.state.automaticPressStartedTypes.remove(type)
        }
    }

    private func markAutomaticPressStarted(for type: HotkeyHoldModeType) {
        self.state.withLock {
            _ = self.state.automaticPressStartedTypes.insert(type)
        }
    }

    private func clearHoldModeStartTriggered(for type: HotkeyHoldModeType) {
        self.state.withLock {
            _ = self.state.holdModeStartTriggeredTypes.remove(type)
        }
    }

    private func markHoldModeStartTriggered(for type: HotkeyHoldModeType) {
        self.state.withLock {
            _ = self.state.holdModeStartTriggeredTypes.insert(type)
        }
    }

    private func finishHoldModeStartTriggered(for type: HotkeyHoldModeType) -> Bool {
        self.state.withLock {
            self.state.holdModeStartTriggeredTypes.remove(type) != nil
        }
    }

    private func finishAutomaticPress(
        for type: HotkeyHoldModeType
    ) -> (duration: TimeInterval, wasTargetActive: Bool, started: Bool) {
        let now = Date()
        return self.state.withLock {
            let startTime = self.state.automaticPressStartTimes.removeValue(forKey: type) ?? now
            let wasTargetActive = self.state.automaticPressWasTargetActive.removeValue(forKey: type) ?? false
            let started = self.state.automaticPressStartedTypes.remove(type) != nil
            return (now.timeIntervalSince(startTime), wasTargetActive, started)
        }
    }

    /// Leaves latched release stops alone: each one is a release that already happened.
    private func clearAutomaticPressTracking() {
        self.state.withLock {
            self.state.holdModeStartTriggeredTypes.removeAll()
            self.state.automaticPressStartTimes.removeAll()
            self.state.automaticPressWasTargetActive.removeAll()
            self.state.automaticPressStartedTypes.removeAll()
        }
    }

    /// Busy flag to prevent race conditions during stop processing
    private var isProcessingStop = false

    private var isInitialized = false
    private var initializationTask: Task<Void, Never>?
    private var healthCheckTask: Task<Void, Never>?
    private var tapInstallPolicy = HotkeyTapInstallPolicy()
    private var tapRetryTask: Task<Void, Never>?
    private var trustObserver: AnyCancellable?
    private var activationObserver: AnyCancellable?
    private var healthCheckInterval: TimeInterval = 30.0
    private var activeShortcutLogScheduled = false
    private lazy var holdReleaseStopLatch = HoldReleaseStopLatch(
        isStarting: { [weak self] in self?.asrService.isStarting ?? false },
        isRunning: { [weak self] in self?.asrService.isRunning ?? false },
        isTargetActive: { [weak self] type in self?.isRecordingTargetActive(for: type) ?? false },
        stop: { [weak self] request, wasLatched in
            self?.stopRecordingIfNeeded(
                trigger: .holdRelease,
                triggeredAt: request.releasedAt,
                latched: wasLatched
            )
        }
    )
    private var captureStartSettledObserver: AnyCancellable?

    init(
        asrService: ASRService,
        primaryShortcuts: [HotkeyShortcut],
        promptModeShortcut: HotkeyShortcut,
        commandModeShortcut: HotkeyShortcut?,
        rewriteModeShortcut: HotkeyShortcut,
        promptShortcutAssignments: [(selection: SettingsStore.DictationPromptSelection, shortcut: HotkeyShortcut)] = [],
        promptModeShortcutEnabled: Bool,
        commandModeShortcutEnabled: Bool,
        rewriteModeShortcutEnabled: Bool,
        startRecordingCallback: (() async -> HotkeyCaptureStartTask?)? = nil,
        dictationModeCallback: (() async -> HotkeyCaptureStartTask?)? = nil,
        stopAndProcessCallback: (() async -> Void)? = nil,
        promptModeCallback: (() async -> HotkeyCaptureStartTask?)? = nil,
        promptSelectionCallback: ((SettingsStore.DictationPromptSelection) async -> HotkeyCaptureStartTask?)? = nil,
        commandModeCallback: (() async -> HotkeyCaptureStartTask?)? = nil,
        rewriteModeCallback: (() async -> HotkeyCaptureStartTask?)? = nil,
        isDictateRecordingProvider: (() -> Bool)? = nil,
        isPromptModeRecordingProvider: (() -> Bool)? = nil,
        isCommandRecordingProvider: (() -> Bool)? = nil,
        isRewriteRecordingProvider: (() -> Bool)? = nil,
        isShortcutCaptureActiveProvider: (() -> Bool)? = nil
    ) {
        self.asrService = asrService
        self.primaryShortcuts = primaryShortcuts
        self.promptModeShortcut = promptModeShortcut
        self.commandModeShortcut = commandModeShortcut
        self.rewriteModeShortcut = rewriteModeShortcut
        self.promptShortcutAssignments = promptShortcutAssignments
        self.promptModeShortcutEnabled = promptModeShortcutEnabled
        self.commandModeShortcutEnabled = commandModeShortcutEnabled
        self.rewriteModeShortcutEnabled = rewriteModeShortcutEnabled
        self.startRecordingCallback = startRecordingCallback
        self.dictationModeCallback = dictationModeCallback
        self.stopAndProcessCallback = stopAndProcessCallback
        self.promptModeCallback = promptModeCallback
        self.promptSelectionCallback = promptSelectionCallback
        self.commandModeCallback = commandModeCallback
        self.rewriteModeCallback = rewriteModeCallback
        self.isDictateRecordingProvider = isDictateRecordingProvider
        self.isPromptModeRecordingProvider = isPromptModeRecordingProvider
        self.isCommandRecordingProvider = isCommandRecordingProvider
        self.isRewriteRecordingProvider = isRewriteRecordingProvider
        self.isShortcutCaptureActiveProvider = isShortcutCaptureActiveProvider
        super.init()

        // A capture start settling (success or failure, either backend) resolves latched release
        // stops. @Published emits before the value changes, so resolve on the next main-actor turn.
        self.captureStartSettledObserver = asrService.$isStarting
            .removeDuplicates()
            .filter { $0 == false }
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.holdReleaseStopLatch.captureStartSettled()
                }
            }

        // A grant made in System Settings arms the tap at once, without waiting for the next
        // backoff tick or a relaunch.
        if !TestHostQuietMode.isActive {
            self.trustObserver = AccessibilityTrustMonitor.shared.$isTrusted
                .removeDuplicates()
                .dropFirst()
                .filter { $0 }
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.retryTapInstallNow(reason: "trust_granted")
                    }
                }
            self.activationObserver = NotificationCenter.default
                .publisher(for: NSApplication.didBecomeActiveNotification)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.retryTapInstallNow(reason: "app_active")
                    }
                }
        }

        self.initializeWithDelay()
    }

    private func initializeWithDelay() {
        DebugLogger.shared.debug("Starting delayed initialization...", source: "GlobalHotkeyManager")

        self.initializationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 second delay
            } catch {
                return
            }

            await MainActor.run { [weak self] in
                self?.attemptTapInstall(reason: "startup")
            }
        }
    }

    func setStopAndProcessCallback(_ callback: @escaping () async -> Void) {
        self.stopAndProcessCallback = callback
    }

    func setCommandModeCallback(_ callback: @escaping () async -> HotkeyCaptureStartTask?) {
        self.commandModeCallback = callback
    }

    func updatePrimaryShortcuts(_ newShortcuts: [HotkeyShortcut]) {
        self.primaryShortcuts = newShortcuts
        DebugLogger.shared.info("Updated transcription hotkeys", source: "GlobalHotkeyManager")
        self.refreshMouseShortcutTapIfNeeded()
        self.scheduleActiveShortcutLog(reason: "shortcuts updated")
    }

    func refreshMouseShortcutTapIfNeeded() {
        guard self.eventTap != nil else { return }
        let mouseButtons = self.configuredMouseButtons()
        guard mouseButtons != self.monitoredMouseButtons else { return }
        self.setupMouseShortcutTap(mouseButtons: mouseButtons)
    }

    func updateCommandModeShortcut(_ newShortcut: HotkeyShortcut?) {
        self.commandModeShortcut = newShortcut
        DebugLogger.shared.info("Updated command mode hotkey", source: "GlobalHotkeyManager")
        self.scheduleActiveShortcutLog(reason: "shortcuts updated")
    }

    func setRewriteModeCallback(_ callback: @escaping () async -> HotkeyCaptureStartTask?) {
        self.rewriteModeCallback = callback
    }

    func updateRewriteModeShortcut(_ newShortcut: HotkeyShortcut) {
        self.rewriteModeShortcut = newShortcut
        DebugLogger.shared.info("Updated rewrite mode hotkey", source: "GlobalHotkeyManager")
        self.scheduleActiveShortcutLog(reason: "shortcuts updated")
    }

    func updateCommandModeShortcutEnabled(_ enabled: Bool) {
        self.commandModeShortcutEnabled = enabled
        if !enabled {
            self.isCommandModeKeyPressed = false
        }
        DebugLogger.shared.info(
            "Command mode shortcut \(enabled ? "enabled" : "disabled")",
            source: "GlobalHotkeyManager"
        )
        self.scheduleActiveShortcutLog(reason: "shortcuts updated")
    }

    func updateRewriteModeShortcutEnabled(_ enabled: Bool) {
        self.rewriteModeShortcutEnabled = enabled
        if !enabled {
            self.isRewriteKeyPressed = false
        }
        DebugLogger.shared.info(
            "Rewrite mode shortcut \(enabled ? "enabled" : "disabled")",
            source: "GlobalHotkeyManager"
        )
        self.scheduleActiveShortcutLog(reason: "shortcuts updated")
    }

    func setPromptModeCallback(_ callback: @escaping () async -> HotkeyCaptureStartTask?) {
        self.promptModeCallback = callback
    }

    func updatePromptModeShortcut(_ newShortcut: HotkeyShortcut) {
        self.promptModeShortcut = newShortcut
        DebugLogger.shared.info("Updated prompt mode hotkey", source: "GlobalHotkeyManager")
        self.scheduleActiveShortcutLog(reason: "shortcuts updated")
    }

    func updatePromptModeShortcutEnabled(_ enabled: Bool) {
        self.promptModeShortcutEnabled = enabled
        if !enabled {
            self.isPromptModeKeyPressed = false
        }
        DebugLogger.shared.info(
            "Prompt mode shortcut \(enabled ? "enabled" : "disabled")",
            source: "GlobalHotkeyManager"
        )
        self.scheduleActiveShortcutLog(reason: "shortcuts updated")
    }

    func updatePromptShortcutAssignments(_ assignments: [(selection: SettingsStore.DictationPromptSelection, shortcut: HotkeyShortcut)]) {
        self.promptShortcutAssignments = assignments
        DebugLogger.shared.info("Updated prompt shortcut assignments", source: "GlobalHotkeyManager")
        self.scheduleActiveShortcutLog(reason: "shortcuts updated")
    }

    func setCancelCallback(_ callback: @escaping () -> Bool) {
        self.cancelCallback = callback
    }

    func setSpokenSendCancelCallback(_ callback: @escaping () -> Bool) {
        self.spokenSendCancelCallback = callback
    }

    #if DEBUG
    /// Tests: runs one key event through the tap's handling, as the tap does on main. Returns
    /// whether the tap consumed it.
    func handleKeyEventForTests(_ event: CGEvent, type: CGEventType) -> Bool {
        guard let proxy = OpaquePointer(bitPattern: 1) else { return false }
        return self.handleKeyEvent(proxy: proxy, type: type, event: event) == nil
    }
    #endif

    func setPasteLastTranscriptionCallback(_ callback: @escaping () -> Void) {
        self.pasteLastTranscriptionCallback = callback
    }

    func setReprocessLastDictationCallback(_ callback: @escaping () -> Void) {
        self.reprocessLastDictationCallback = callback
    }

    /// Tries to install the keyboard tap once and schedules the next try by
    /// `HotkeyTapInstallPolicy`: a capped backoff while macOS does not trust us yet, a few fast
    /// retries if it trusts us but refuses the tap. Only state changes are logged (`HOTKEY_TAP`).
    private func attemptTapInstall(reason: String) {
        self.tapRetryTask?.cancel()
        self.tapRetryTask = nil
        // A pending start-up or reinitialize attempt would tear down whatever this one installs.
        self.initializationTask?.cancel()
        self.initializationTask = nil

        let outcome = self.setupGlobalHotkey()
        let step = self.tapInstallPolicy.record(outcome)
        if step.transitioned {
            let line = HotkeyTapInstallPolicy.logLine(for: step, reason: reason)
            if step.state == .failedTrusted {
                DebugLogger.shared.error(
                    line + " detail=accessibility_on_but_tap_refused (a relaunch, or removing and re-adding the app in Accessibility, clears it)",
                    source: "GlobalHotkeyManager"
                )
            } else {
                DebugLogger.shared.info(line, source: "GlobalHotkeyManager")
            }
        }
        AccessibilityTrustMonitor.shared.reportHotkeyTapState(step.state)

        if outcome == .installed {
            self.isInitialized = true
            self.startHealthCheckTimer()
        } else {
            self.isInitialized = false
            // The retry below polls from here; the 30 s health check would only repeat its warning.
            self.healthCheckTask?.cancel()
            self.healthCheckTask = nil
        }

        guard let delay = step.retryAfter else { return }
        self.tapRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                self?.attemptTapInstall(reason: "retry")
            }
        }
    }

    /// Retries at once when the tap is not live (trust flipped, the app came to the front).
    func retryTapInstallNow(reason: String) {
        switch self.tapInstallPolicy.state {
        case .idle:
            return // the start-up attempt is still pending
        case .installed:
            guard !self.isEventTapEnabled() else { return }
            // macOS disables a live tap briefly on a timeout; re-enable before rebuilding it.
            if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                if self.isEventTapEnabled() { return }
            }
        case .installing, .waitingForAccessibility, .failedTrusted:
            break
        }
        self.attemptTapInstall(reason: reason)
    }

    /// Where the keyboard tap stands (tests and diagnostics).
    var tapState: HotkeyTapState {
        self.tapInstallPolicy.state
    }

    private func setupGlobalHotkey() -> HotkeyTapInstallPolicy.Outcome {
        self.finishInterruptedMouseShortcutPress(reason: "hotkey tap reinitialized")
        self.cleanupEventTap()

        // The XCTest host never intercepts the operator's keyboard or mouse.
        guard !TestHostQuietMode.isActive else {
            DebugLogger.shared.info("Hotkey event taps skipped in test host quiet mode", source: "GlobalHotkeyManager")
            return .installed
        }

        if !AXIsProcessTrusted() {
            return .untrusted
        }

        self.eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.keyboardEventMask(),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                // Our own synthesized keystrokes (paste, typed text) pass straight
                // through on the tap thread without waiting for the main thread.
                if GlobalHotkeyManager.isSelfPostedKeyboardEvent(type: type, event: event) {
                    return Unmanaged.passUnretained(event)
                }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon)
                    .takeUnretainedValue()
                if !Thread.isMainThread, GlobalHotkeyManager.isTapDisabledNotice(type) {
                    // Re-enable here so hotkeys come back even while main is stalled (a stall is
                    // what usually trips the timeout). The tracking reset, and a rebuild if this
                    // did not take, follow on main; the serial main queue runs that before any
                    // key event queued behind it.
                    manager.reenableKeyboardTapOnTapThread()
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            manager.recoverFromKeyboardTapDisable(type: type)
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }
                let receivedAt = ProcessInfo.processInfo.systemUptime
                // The stop-path trace starts at this receipt, before any wait for main.
                manager.noteEventReceived(at: receivedAt)
                defer { manager.clearEventReceived() }
                let result: Unmanaged<CGEvent>?
                if Thread.isMainThread {
                    result = MainActor.assumeIsolated {
                        manager.handleKeyEvent(proxy: proxy, type: type, event: event)
                    }
                } else {
                    // Real keys hop to main, where all hotkey state lives.
                    result = DispatchQueue.main.sync {
                        MainActor.assumeIsolated {
                            manager.handleKeyEvent(proxy: proxy, type: type, event: event)
                        }
                    }
                }
                // A key-down a hotkey took is ours, not the user moving elsewhere (Spoken Send).
                if GlobalHotkeyManager.isConsumedKeyDown(type: type, passedThrough: result != nil) {
                    ConsumedHotkeyKeyDowns.record(at: receivedAt)
                }
                return result
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        // Failures log at debug: the HOTKEY_TAP transition line is the one the log keeps.
        guard let tap = eventTap else {
            DebugLogger.shared.debug("Failed to create CGEvent tap", source: "GlobalHotkeyManager")
            return .tapFailed
        }

        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        guard let source = runLoopSource else {
            DebugLogger.shared.debug("Failed to create CFRunLoopSource", source: "GlobalHotkeyManager")
            self.cleanupEventTap()
            return .tapFailed
        }

        CFRunLoopAddSource(self.keyboardTapRunLoopStartingIfNeeded(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        if !self.isEventTapEnabled() {
            DebugLogger.shared.debug("Event tap could not be enabled", source: "GlobalHotkeyManager")
            self.cleanupEventTap()
            return .tapFailed
        }

        DebugLogger.shared.info("Event tap successfully created and enabled", source: "GlobalHotkeyManager")
        self.logActiveShortcuts(reason: "event tap ready")
        self.setupMouseTaps()
        return .installed
    }

    private nonisolated func cleanupEventTap() {
        Self.tearDown(tap: self.eventTap, source: self.runLoopSource, runLoop: self.keyboardTapRunLoop ?? CFRunLoopGetMain())
        self.eventTap = nil
        self.runLoopSource = nil
        self.clearPrimaryShortcutPressState()
        self.cleanupMouseTaps()
    }

    private nonisolated static func tearDown(
        tap: CFMachPort?,
        source: CFRunLoopSource?,
        runLoop: CFRunLoop = CFRunLoopGetMain()
    ) {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
    }

    /// Starts (once) a dedicated thread whose run loop services the keyboard tap.
    private nonisolated func keyboardTapRunLoopStartingIfNeeded() -> CFRunLoop {
        if let runLoop = self.keyboardTapRunLoop { return runLoop }

        let ready = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var createdRunLoop: CFRunLoop?
        let thread = Thread {
            createdRunLoop = CFRunLoopGetCurrent()
            // A port keeps the loop alive while no tap source is attached.
            let keepAlive = NSMachPort()
            RunLoop.current.add(keepAlive, forMode: .common)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "com.stage11.liquidvoice.hotkey-event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()

        let runLoop: CFRunLoop = createdRunLoop ?? CFRunLoopGetMain()
        self.keyboardTapRunLoop = runLoop
        self.keyboardTapThread = thread
        return runLoop
    }

    nonisolated static let ownProcessID = Int64(ProcessInfo.processInfo.processIdentifier)

    /// Records when an event tap received the event about to be handled (tap thread or main).
    private nonisolated func noteEventReceived(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.state.withLock { self.state.eventReceivedAt = time }
    }

    private nonisolated func clearEventReceived() {
        self.state.withLock { self.state.eventReceivedAt = nil }
    }

    /// When the event being handled reached the tap, or now outside event handling.
    private func currentEventReceivedAt() -> TimeInterval {
        self.state.withLock { self.state.eventReceivedAt } ?? ProcessInfo.processInfo.systemUptime
    }

    /// A key-down the tap swallowed: a hotkey press, recorded for Spoken Send's input check.
    nonisolated static func isConsumedKeyDown(type: CGEventType, passedThrough: Bool) -> Bool {
        type == .keyDown && !passedThrough
    }

    /// True for a key or modifier event this process posted itself (TypingService's
    /// synthesized paste and typed text). Tap-disabled notices never count, so the
    /// tap is always re-enabled.
    nonisolated static func isSelfPostedKeyboardEvent(
        type: CGEventType,
        event: CGEvent,
        ownProcessID: Int64 = GlobalHotkeyManager.ownProcessID
    ) -> Bool {
        switch type {
        case .keyDown, .keyUp, .flagsChanged:
            return event.getIntegerValueField(.eventSourceUnixProcessID) == ownProcessID
        default:
            return false
        }
    }

    nonisolated static func keyboardEventMask() -> CGEventMask {
        (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
    }

    nonisolated static func mouseObserverEventMask() -> CGEventMask {
        (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
    }

    nonisolated static func mouseShortcutEventMask(mouseButtons: Set<Int>) -> CGEventMask {
        var mask: CGEventMask = 0
        if mouseButtons.contains(0) {
            mask |= (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
                | (CGEventMask(1) << CGEventType.leftMouseUp.rawValue)
        }
        if mouseButtons.contains(1) {
            mask |= (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
                | (CGEventMask(1) << CGEventType.rightMouseUp.rawValue)
        }
        if mouseButtons.contains(where: { $0 >= 2 }) {
            mask |= (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
                | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
        }
        return mask
    }

    struct ActiveShortcutSummaryInput {
        let primary: [HotkeyShortcut]
        let promptAssignments: [(key: String, shortcut: HotkeyShortcut)]
        let secondaryPromptMode: HotkeyShortcut
        let secondaryPromptModeEnabled: Bool
        let command: HotkeyShortcut?
        let commandEnabled: Bool
        let edit: HotkeyShortcut
        let editEnabled: Bool
        let cancel: HotkeyShortcut
        let pasteLast: HotkeyShortcut?
        let pasteLastEnabled: Bool
        var reprocessLast: HotkeyShortcut? = nil
        var reprocessLastEnabled = false
        let mode: HotkeyActivationMode
    }

    /// One line listing every shortcut the manager will act on and where it came from.
    static func activeShortcutSummary(_ input: ActiveShortcutSummaryInput) -> String {
        func describe(_ shortcut: HotkeyShortcut?) -> String {
            guard let shortcut else { return "none" }
            if shortcut.isMouseShortcut {
                return "\(shortcut.displayString) [button=\(shortcut.mouseButton ?? -1) flags=\(shortcut.relevantModifierFlags.rawValue)]"
            }
            return "\(shortcut.displayString) [keyCode=\(shortcut.keyCode) flags=\(shortcut.relevantModifierFlags.rawValue)]"
        }

        var parts = ["mode=\(input.mode.rawValue)"]
        parts += input.primary.enumerated().map { "primary[\($0.offset)]=\(describe($0.element))" }
        parts += input.promptAssignments.map { "prompt[\($0.key)]=\(describe($0.shortcut))" }
        parts.append("secondaryPromptMode=\(describe(input.secondaryPromptMode)) enabled=\(input.secondaryPromptModeEnabled)")
        parts.append("command=\(describe(input.command)) enabled=\(input.commandEnabled)")
        parts.append("edit=\(describe(input.edit)) enabled=\(input.editEnabled)")
        parts.append("cancel=\(describe(input.cancel))")
        parts.append("pasteLast=\(describe(input.pasteLast)) enabled=\(input.pasteLastEnabled)")
        parts.append("reprocessLast=\(describe(input.reprocessLast)) enabled=\(input.reprocessLastEnabled)")
        return parts.joined(separator: " | ")
    }

    /// Coalesces the burst of shortcut updates into one log line.
    private func scheduleActiveShortcutLog(reason: String) {
        guard !self.activeShortcutLogScheduled else { return }
        self.activeShortcutLogScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.activeShortcutLogScheduled = false
            self.logActiveShortcuts(reason: reason)
        }
    }

    private func logActiveShortcuts(reason: String) {
        let settings = SettingsStore.shared
        let promptAssignments = self.promptShortcutAssignments.map { assignment in
            (
                key: settings.dictationPromptConfigurationKey(for: assignment.selection) ?? "?",
                shortcut: assignment.shortcut
            )
        }
        let summary = Self.activeShortcutSummary(.init(
            primary: self.primaryShortcuts,
            promptAssignments: promptAssignments,
            secondaryPromptMode: self.promptModeShortcut,
            secondaryPromptModeEnabled: self.promptModeShortcutEnabled,
            command: self.commandModeShortcut,
            commandEnabled: self.commandModeShortcutEnabled,
            edit: self.rewriteModeShortcut,
            editEnabled: self.rewriteModeShortcutEnabled,
            cancel: settings.cancelRecordingHotkeyShortcut,
            pasteLast: settings.pasteLastTranscriptionHotkeyShortcut,
            pasteLastEnabled: settings.pasteLastTranscriptionShortcutEnabled,
            reprocessLast: settings.reprocessLastDictationHotkeyShortcut,
            reprocessLastEnabled: settings.reprocessLastDictationShortcutEnabled,
            mode: self.hotkeyMode
        ))
        DebugLogger.shared.info("Active shortcuts (\(reason)) | \(summary)", source: "GlobalHotkeyManager")
    }

    nonisolated static func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        return modifiers
    }

    private nonisolated static func isTapEnabled(_ tap: CFMachPort?) -> Bool {
        guard let tap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    private func configuredMouseButtons() -> Set<Int> {
        let settings = SettingsStore.shared
        return Self.mouseButtons(
            primary: self.primaryShortcuts,
            oneShot: [
                settings.pasteLastTranscriptionShortcutEnabled ? settings.pasteLastTranscriptionHotkeyShortcut : nil,
                settings.reprocessLastDictationShortcutEnabled ? settings.reprocessLastDictationHotkeyShortcut : nil,
            ]
        )
    }

    /// Buttons the filtering mouse tap must see: every primary dictation mouse shortcut plus the
    /// enabled one-shot actions (paste last transcription, reprocess last dictation).
    static func mouseButtons(primary: [HotkeyShortcut], oneShot: [HotkeyShortcut?]) -> Set<Int> {
        let shortcuts = primary + oneShot.compactMap { $0 }
        return Set(shortcuts.compactMap { shortcut in
            shortcut.isMouseShortcut ? shortcut.mouseButton : nil
        })
    }

    private func setupMouseTaps() {
        self.setupMouseObserverTap()
        self.setupMouseShortcutTap(mouseButtons: self.configuredMouseButtons())
    }

    // Listen-only: macOS delivers clicks to apps whether or not this callback runs.
    private func setupMouseObserverTap() {
        self.cleanupMouseObserverTap()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: Self.mouseObserverEventMask(),
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleMouseObserverEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DebugLogger.shared.error("Failed to create mouse observer tap", source: "GlobalHotkeyManager")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            DebugLogger.shared.error("Failed to create mouse observer run loop source", source: "GlobalHotkeyManager")
            return
        }

        self.mouseObserverTap = tap
        self.mouseObserverSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        DebugLogger.shared.info("Mouse observer tap enabled (listen-only)", source: "GlobalHotkeyManager")
    }

    // Filter tap, created only for the button families that have a shortcut.
    private func setupMouseShortcutTap(mouseButtons: Set<Int>) {
        self.finishInterruptedMouseShortcutPress(reason: "mouse shortcut tap rebuilt")
        self.cleanupMouseShortcutTap()

        let mask = Self.mouseShortcutEventMask(mouseButtons: mouseButtons)
        guard mask != 0 else {
            DebugLogger.shared.info("Mouse shortcut tap not needed [mouseButtons=none]", source: "GlobalHotkeyManager")
            return
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.noteEventReceived()
                defer { manager.clearEventReceived() }
                return manager.handleMouseShortcutEvent(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            DebugLogger.shared.error("Failed to create mouse shortcut tap", source: "GlobalHotkeyManager")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            DebugLogger.shared.error("Failed to create mouse shortcut run loop source", source: "GlobalHotkeyManager")
            return
        }

        self.mouseShortcutTap = tap
        self.mouseShortcutSource = source
        self.monitoredMouseButtons = mouseButtons
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        let summary = mouseButtons.sorted().map(String.init).joined(separator: ",")
        DebugLogger.shared.info("Mouse shortcut tap enabled [mouseButtons=\(summary)]", source: "GlobalHotkeyManager")
    }

    private func recoverMouseTapsIfNeeded() {
        if !Self.isTapEnabled(self.mouseObserverTap) {
            DebugLogger.shared.warning("Mouse observer tap not enabled, rebuilding", source: "GlobalHotkeyManager")
            self.setupMouseObserverTap()
        }

        let mouseButtons = self.configuredMouseButtons()
        let shortcutTapMissing = !mouseButtons.isEmpty && !Self.isTapEnabled(self.mouseShortcutTap)
        if mouseButtons != self.monitoredMouseButtons || shortcutTapMissing {
            DebugLogger.shared.warning("Mouse shortcut tap out of date, rebuilding", source: "GlobalHotkeyManager")
            self.setupMouseShortcutTap(mouseButtons: mouseButtons)
        }
    }

    private nonisolated func cleanupMouseTaps() {
        self.cleanupMouseObserverTap()
        self.cleanupMouseShortcutTap()
    }

    private nonisolated func cleanupMouseObserverTap() {
        Self.tearDown(tap: self.mouseObserverTap, source: self.mouseObserverSource)
        self.mouseObserverTap = nil
        self.mouseObserverSource = nil
    }

    private nonisolated func cleanupMouseShortcutTap() {
        Self.tearDown(tap: self.mouseShortcutTap, source: self.mouseShortcutSource)
        self.mouseShortcutTap = nil
        self.mouseShortcutSource = nil
        self.monitoredMouseButtons = []
        self.clearPrimaryShortcutPressState(mouseOnly: true)
    }

    private func handleMouseObserverEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            self.reenableMouseTap(self.mouseObserverTap, label: "Mouse observer") { self.setupMouseObserverTap() }
            return Unmanaged.passUnretained(event)
        }

        if self.isShortcutCaptureActiveProvider?() ?? false {
            return Unmanaged.passUnretained(event)
        }

        self.markOtherInputDuringModifierOnly()
        return Unmanaged.passUnretained(event)
    }

    private func handleMouseShortcutEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Mouse events were lost while the tap was off; a pending one-shot up may be among them.
            self.state.withLock { self.state.oneShotMouseUpSwallow.reset() }
            self.finishInterruptedMouseShortcutPress(reason: "mouse shortcut tap disabled")
            self.reenableMouseTap(self.mouseShortcutTap, label: "Mouse shortcut") {
                self.setupMouseShortcutTap(mouseButtons: self.configuredMouseButtons())
            }
            return Unmanaged.passUnretained(event)
        }

        if self.isShortcutCaptureActiveProvider?() ?? false {
            // Capture sees the raw clicks, so no paired up will be swallowed while it is active.
            self.state.withLock { self.state.oneShotMouseUpSwallow.reset() }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            self.markOtherInputDuringModifierOnly()
            if self.handleMouseShortcutDown(event, modifiers: Self.modifierFlags(from: event.flags)) {
                return nil
            }
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if self.handleMouseShortcutUp(event) {
                return nil
            }
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func reenableMouseTap(_ tap: CFMachPort?, label: String, rebuild: @escaping @MainActor () -> Void) {
        DebugLogger.shared.warning("\(label) tap disabled by macOS, re-enabling", source: "GlobalHotkeyManager")
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        guard !Self.isTapEnabled(tap) else { return }

        DebugLogger.shared.warning("\(label) tap re-enable failed, rebuilding", source: "GlobalHotkeyManager")
        Task { @MainActor in
            rebuild()
        }
    }

    nonisolated static func sessionIsLocked(sessionInfo: [String: Any]) -> Bool {
        sessionInfo["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private nonisolated static func currentSessionIsLocked() -> Bool {
        self.sessionIsLocked(sessionInfo: CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:])
    }

    private nonisolated func clearPrimaryShortcutPressState(mouseOnly: Bool = false) {
        self.state.withLock {
            self.state.oneShotMouseUpSwallow.reset()
            if mouseOnly {
                guard case .mouse? = self.state.activePrimaryShortcutPress else { return }
            } else {
                guard self.state.activePrimaryShortcutPress != nil || self.state.isKeyPressed else { return }
            }
            self.state.activePrimaryShortcutPress = nil
            self.state.isKeyPressed = false
            self.state.holdModeStartTriggeredTypes.remove(.transcription)
            self.state.automaticPressStartTimes.removeValue(forKey: .transcription)
            self.state.automaticPressWasTargetActive.removeValue(forKey: .transcription)
            self.state.automaticPressStartedTypes.remove(.transcription)
        }
    }

    private func markOtherInputDuringModifierOnly() {
        guard self.modifierOnlyKeyDown else { return }
        self.otherKeyPressedDuringModifier = true
    }

    private func mouseButton(from event: CGEvent) -> Int {
        Int(event.getIntegerValueField(.mouseEventButtonNumber))
    }

    private func beginPrimaryShortcutPress(_ press: ActivePrimaryShortcutPress) -> Bool {
        self.state.withLock {
            guard self.state.activePrimaryShortcutPress == nil, !self.state.isKeyPressed else {
                return false
            }
            self.state.activePrimaryShortcutPress = press
            return true
        }
    }

    /// Ends an active primary mouse press whose mouse-up can no longer be trusted to arrive, and
    /// stops the recording it holds (hold and automatic modes), including one still starting.
    /// Returns true when there was a mouse press to finish.
    @discardableResult
    private func finishInterruptedMouseShortcutPress(reason: String) -> Bool {
        guard case .mouse? = self.activePrimaryShortcutPress else { return false }

        self.clearPrimaryShortcutPressState(mouseOnly: true)

        DebugLogger.shared.warning(
            "Finishing active mouse shortcut press before \(reason)",
            source: "GlobalHotkeyManager"
        )

        guard Self.shouldForceStopInterruptedPrimaryPress(activationMode: self.hotkeyMode) else { return true }
        // Same as a release: stop now if running, otherwise when the start in flight settles.
        self.stopRecordingAfterRelease(
            for: .transcription,
            label: "Interrupted mouse shortcut",
            requireTargetMode: false
        )
        return true
    }

    nonisolated static func shouldForceStopInterruptedPrimaryPress(activationMode: HotkeyActivationMode) -> Bool {
        activationMode != .toggle
    }

    private func finishPrimaryShortcutPress(_ press: ActivePrimaryShortcutPress) -> Bool {
        self.state.withLock {
            guard self.state.activePrimaryShortcutPress == press else {
                return false
            }
            self.state.activePrimaryShortcutPress = nil
            return true
        }
    }

    private func primaryModifierOnlyBehavior(for shortcut: HotkeyShortcut) -> ModifierOnlyShortcutBehavior {
        .init(
            shortcut: shortcut,
            isEnabled: true,
            holdModeType: .transcription,
            holdStartMessage: "Transcription modifier held (hold mode) - starting",
            holdReleaseMessage: "Transcription modifier released (hold mode) - stopping",
            toggleIgnoredMessage: "Transcription modifier released but another key was pressed - ignoring",
            isModeKeyPressed: { self.isKeyPressed },
            setModeKeyPressed: { self.isKeyPressed = $0 },
            onHoldStart: { self.startRecordingIfNeeded() },
            onToggleRelease: {
                if self.asrService.isRunningOrStarting {
                    let isSameMode = self.isDictateRecordingProvider?() ?? false
                    DebugLogger.shared.info(
                        "Hotkey route | pressed=dictate(mod) | active=\(isSameMode ? "dictate" : "other") | asrRunning=true | action=\(isSameMode ? "stop" : "switch")",
                        source: "GlobalHotkeyManager"
                    )
                    if isSameMode {
                        self.stopRecordingIfNeeded()
                    } else {
                        self.triggerDictationMode()
                    }
                } else {
                    DebugLogger.shared.info(
                        "Hotkey route | pressed=dictate(mod) | active=none | asrRunning=false | action=start",
                        source: "GlobalHotkeyManager"
                    )
                    self.triggerDictationMode()
                }
            },
            isTargetModeActive: { self.isDictateRecordingProvider?() ?? false }
        )
    }

    private func handleKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if let tapRecoveryResult = self.handleTapDisableEvent(type: type, event: event) {
            return tapRecoveryResult
        }

        if self.isShortcutCaptureActiveProvider?() ?? false {
            self.resetModifierOnlyShortcutTracking()
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let eventModifiers = Self.modifierFlags(from: event.flags)

        switch type {
        case .keyDown:
            self.markOtherInputDuringModifierOnly()

            // Check the configured cancel shortcut first.
            if SettingsStore.shared.cancelRecordingHotkeyShortcut.matches(keyCode: keyCode, modifiers: eventModifiers) {
                // While a Spoken Send Return is pending and the pill shows SEND, the first press
                // drops only the Return, and the key is consumed so it never reaches the app (Esc
                // would interrupt a Claude Code turn). The dictation goes on; a second press cancels
                // it (DESIGN.md §15). The callback is the one gate; otherwise nothing changes here.
                let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                if isAutorepeat, self.isSwallowingCancelKeyRepeats {
                    return nil
                }
                self.isSwallowingCancelKeyRepeats = false
                if !isAutorepeat, let cancelsSend = self.spokenSendCancelCallback, cancelsSend() {
                    DebugLogger.shared.info("Cancel shortcut pressed - canceled the Spoken Send Return", source: "GlobalHotkeyManager")
                    self.isSwallowingCancelKeyRepeats = true
                    return nil
                }

                var handled = false

                if self.asrService.isRunning || self.asrService.isStarting {
                    DebugLogger.shared.info("Cancel shortcut pressed - cancelling recording", source: "GlobalHotkeyManager")
                    Task { @MainActor in
                        await self.asrService.stopWithoutTranscription()
                    }
                    handled = true
                }

                // Trigger cancel callback to close mode views / reset state
                if let callback = cancelCallback, callback() {
                    DebugLogger.shared.info("Cancel shortcut pressed - cancel callback handled", source: "GlobalHotkeyManager")
                    handled = true
                }

                if handled {
                    return nil // Consume event only if we did something
                }
            }

            // Check the "paste last transcription" shortcut (a one-shot action, like cancel).
            if SettingsStore.shared.pasteLastTranscriptionShortcutEnabled,
               let pasteShortcut = SettingsStore.shared.pasteLastTranscriptionHotkeyShortcut,
               pasteShortcut.matches(keyCode: keyCode, modifiers: eventModifiers)
            {
                // Holding the chord emits auto-repeat key-downs; because the paste waits for the
                // modifiers to release, every repeat would otherwise queue another insertion and
                // paste N times. triggerPasteLastTranscription ignores repeats.
                self.triggerPasteLastTranscription(isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
                return nil
            }

            // Check the "reprocess last dictation" shortcut (a one-shot action, like paste last).
            if SettingsStore.shared.reprocessLastDictationShortcutEnabled,
               let reprocessShortcut = SettingsStore.shared.reprocessLastDictationHotkeyShortcut,
               reprocessShortcut.matches(keyCode: keyCode, modifiers: eventModifiers)
            {
                // Auto-repeat while the chord is held would queue a reprocess per repeat and
                // rewrite the entry N times; triggerReprocessLastDictation ignores repeats.
                self.triggerReprocessLastDictation(isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
                return nil
            }

            if let assignment = self.promptShortcutAssignments.first(where: { $0.shortcut.matches(keyCode: keyCode, modifiers: eventModifiers) }) {
                switch self.hotkeyMode {
                case .hold:
                    if !self.isPromptAssignmentKeyPressed {
                        self.cancelPendingReleaseStop(for: .promptAssignment)
                        self.clearHoldModeStartTriggered(for: .promptAssignment)
                        self.isPromptAssignmentKeyPressed = true
                        DebugLogger.shared.info("Prompt shortcut pressed (hold mode) - starting", source: "GlobalHotkeyManager")
                        self.triggerPromptSelection(assignment.selection)
                        self.markHoldModeStartTriggered(for: .promptAssignment)
                    }
                case .automatic:
                    if !self.isPromptAssignmentKeyPressed {
                        self.isPromptAssignmentKeyPressed = true
                        let isSameMode = self.asrService.isRunning && (self.isPromptModeRecordingProvider?() ?? false)
                        self.beginAutomaticPress(for: .promptAssignment, wasTargetActive: isSameMode)
                        if self.asrService.isRunning {
                            if isSameMode {
                                DebugLogger.shared.info("Prompt shortcut pressed (automatic, same mode) - waiting for release", source: "GlobalHotkeyManager")
                            } else {
                                DebugLogger.shared.info("Prompt shortcut pressed (automatic, switch mode)", source: "GlobalHotkeyManager")
                                self.triggerPromptSelection(assignment.selection)
                                self.markAutomaticPressStarted(for: .promptAssignment)
                            }
                        } else {
                            DebugLogger.shared.info("Prompt shortcut triggered (automatic) - starting", source: "GlobalHotkeyManager")
                            self.triggerPromptSelection(assignment.selection)
                            self.markAutomaticPressStarted(for: .promptAssignment)
                        }
                    }
                case .toggle:
                    if self.asrService.isRunningOrStarting {
                        if self.isPromptModeRecordingProvider?() ?? false {
                            DebugLogger.shared.info("Prompt shortcut pressed in Prompt mode - stopping", source: "GlobalHotkeyManager")
                            self.stopRecordingIfNeeded()
                        } else {
                            DebugLogger.shared.info("Prompt shortcut pressed while recording - switching mode", source: "GlobalHotkeyManager")
                            self.triggerPromptSelection(assignment.selection)
                        }
                    } else {
                        DebugLogger.shared.info("Prompt shortcut triggered - starting", source: "GlobalHotkeyManager")
                        self.triggerPromptSelection(assignment.selection)
                    }
                }
                return nil
            }

            // Check prompt mode hotkey
            if self.handlePromptModeKeyDown(keyCode: keyCode, modifiers: eventModifiers) { return nil }

            // Check command mode hotkey first
            if self.commandModeShortcutEnabled,
               let commandModeShortcut = self.commandModeShortcut,
               commandModeShortcut.matches(keyCode: keyCode, modifiers: eventModifiers)
            {
                switch self.hotkeyMode {
                case .hold:
                    // Press and hold: start on keyDown, stop on keyUp
                    if !self.isCommandModeKeyPressed {
                        self.cancelPendingReleaseStop(for: .commandMode)
                        self.clearHoldModeStartTriggered(for: .commandMode)
                        self.isCommandModeKeyPressed = true
                        DebugLogger.shared.info("Command mode shortcut pressed (hold mode) - starting", source: "GlobalHotkeyManager")
                        self.triggerCommandMode()
                        self.markHoldModeStartTriggered(for: .commandMode)
                    }
                case .automatic:
                    if !self.isCommandModeKeyPressed {
                        self.isCommandModeKeyPressed = true
                        let isSameMode = self.asrService.isRunning && (self.isCommandRecordingProvider?() ?? false)
                        self.beginAutomaticPress(for: .commandMode, wasTargetActive: isSameMode)
                        if self.asrService.isRunning {
                            if isSameMode {
                                DebugLogger.shared.info("Command mode shortcut pressed (automatic, same mode) - waiting for release", source: "GlobalHotkeyManager")
                            } else {
                                DebugLogger.shared.info("Command mode shortcut pressed (automatic, switch mode)", source: "GlobalHotkeyManager")
                                self.triggerCommandMode()
                                self.markAutomaticPressStarted(for: .commandMode)
                            }
                        } else {
                            DebugLogger.shared.info("Command mode shortcut triggered (automatic) - starting", source: "GlobalHotkeyManager")
                            self.triggerCommandMode()
                            self.markAutomaticPressStarted(for: .commandMode)
                        }
                    }
                case .toggle:
                    // Toggle mode: press to start, press again to stop
                    if self.asrService.isRunningOrStarting {
                        if self.isCommandRecordingProvider?() ?? false {
                            DebugLogger.shared.info("Command mode shortcut pressed in Command mode - stopping", source: "GlobalHotkeyManager")
                            self.stopRecordingIfNeeded()
                        } else {
                            DebugLogger.shared.info("Command mode shortcut pressed while recording - switching mode", source: "GlobalHotkeyManager")
                            self.triggerCommandMode()
                        }
                    } else {
                        DebugLogger.shared.info("Command mode shortcut triggered - starting", source: "GlobalHotkeyManager")
                        self.triggerCommandMode()
                    }
                }
                return nil
            }

            // Check dedicated rewrite mode hotkey
            if self.rewriteModeShortcutEnabled {
                if self.rewriteModeShortcut.matches(keyCode: keyCode, modifiers: eventModifiers) {
                    switch self.hotkeyMode {
                    case .hold:
                        // Press and hold: start on keyDown, stop on keyUp
                        if !self.isRewriteKeyPressed {
                            self.cancelPendingReleaseStop(for: .rewriteMode)
                            self.clearHoldModeStartTriggered(for: .rewriteMode)
                            self.isRewriteKeyPressed = true
                            DebugLogger.shared.info("Rewrite mode shortcut pressed (hold mode) - starting", source: "GlobalHotkeyManager")
                            self.triggerRewriteMode()
                            self.markHoldModeStartTriggered(for: .rewriteMode)
                        }
                    case .automatic:
                        if !self.isRewriteKeyPressed {
                            self.isRewriteKeyPressed = true
                            let isSameMode = self.asrService.isRunning && (self.isRewriteRecordingProvider?() ?? false)
                            self.beginAutomaticPress(for: .rewriteMode, wasTargetActive: isSameMode)
                            if self.asrService.isRunning {
                                if isSameMode {
                                    DebugLogger.shared.info("Rewrite mode shortcut pressed (automatic, same mode) - waiting for release", source: "GlobalHotkeyManager")
                                } else {
                                    DebugLogger.shared.info("Rewrite mode shortcut pressed (automatic, switch mode)", source: "GlobalHotkeyManager")
                                    self.triggerRewriteMode()
                                    self.markAutomaticPressStarted(for: .rewriteMode)
                                }
                            } else {
                                DebugLogger.shared.info("Rewrite mode shortcut triggered (automatic) - starting", source: "GlobalHotkeyManager")
                                self.triggerRewriteMode()
                                self.markAutomaticPressStarted(for: .rewriteMode)
                            }
                        }
                    case .toggle:
                        // Toggle mode: press to start, press again to stop
                        if self.asrService.isRunningOrStarting {
                            if self.isRewriteRecordingProvider?() ?? false {
                                DebugLogger.shared.info("Rewrite mode shortcut pressed in Edit mode - stopping", source: "GlobalHotkeyManager")
                                self.stopRecordingIfNeeded()
                            } else {
                                DebugLogger.shared.info("Rewrite mode shortcut pressed while recording - switching mode", source: "GlobalHotkeyManager")
                                self.triggerRewriteMode()
                            }
                        } else {
                            DebugLogger.shared.info("Rewrite mode shortcut triggered - starting", source: "GlobalHotkeyManager")
                            self.triggerRewriteMode()
                        }
                    }
                    return nil
                }
            }

            // Then check transcription hotkeys
            if let shortcut = self.primaryShortcuts.first(where: { $0.matches(keyCode: keyCode, modifiers: eventModifiers) }) {
                guard self.beginPrimaryShortcutPress(.keyboard(shortcut.keyCode)) else { return nil }
                self.handlePrimaryDictationTriggerDown()
                return nil
            }

        case .keyUp:
            // The cancel key is up: a later press is a new one.
            if keyCode == SettingsStore.shared.cancelRecordingHotkeyShortcut.keyCode {
                self.isSwallowingCancelKeyRepeats = false
            }
            // Prompt mode key up (press and hold mode)
            if self.handlePromptModeKeyUp(keyCode: keyCode) { return nil }

            // Command mode key up
            // Note: Only check keyCode, not modifiers - user may release modifier before/with main key
            if self.commandModeShortcutEnabled,
               self.isCommandModeKeyPressed,
               let commandModeShortcut = self.commandModeShortcut,
               keyCode == commandModeShortcut.keyCode
            {
                switch self.hotkeyMode {
                case .hold:
                    self.isCommandModeKeyPressed = false
                    _ = self.finishHoldModeStartTriggered(for: .commandMode)
                    DebugLogger.shared.info("Command mode shortcut released (hold mode) - stopping", source: "GlobalHotkeyManager")
                    self.stopRecordingAfterRelease(for: .commandMode, label: "Command mode")
                case .automatic:
                    self.isCommandModeKeyPressed = false
                    self.handleAutomaticKeyRelease(for: .commandMode, label: "Command mode")
                case .toggle:
                    break
                }
                return nil
            }

            // Rewrite mode key up
            // Note: Only check keyCode, not modifiers - user may release modifier before/with main key
            if self.rewriteModeShortcutEnabled, self.isRewriteKeyPressed, keyCode == self.rewriteModeShortcut.keyCode {
                switch self.hotkeyMode {
                case .hold:
                    self.isRewriteKeyPressed = false
                    _ = self.finishHoldModeStartTriggered(for: .rewriteMode)
                    DebugLogger.shared.info("Rewrite mode shortcut released (hold mode) - stopping", source: "GlobalHotkeyManager")
                    self.stopRecordingAfterRelease(for: .rewriteMode, label: "Rewrite mode")
                case .automatic:
                    self.isRewriteKeyPressed = false
                    self.handleAutomaticKeyRelease(for: .rewriteMode, label: "Rewrite mode")
                case .toggle:
                    break
                }
                return nil
            }

            // Prompt assignment key up
            // Note: Only check keyCode, not modifiers - user may release modifier before/with main key
            if self.isPromptAssignmentKeyPressed,
               let assignment = self.promptShortcutAssignments.first(where: { $0.shortcut.keyCode == keyCode })
            {
                _ = assignment
                switch self.hotkeyMode {
                case .hold:
                    self.isPromptAssignmentKeyPressed = false
                    _ = self.finishHoldModeStartTriggered(for: .promptAssignment)
                    DebugLogger.shared.info("Prompt shortcut released (hold mode) - stopping", source: "GlobalHotkeyManager")
                    self.stopRecordingAfterRelease(for: .promptAssignment, label: "Prompt shortcut")
                case .automatic:
                    self.isPromptAssignmentKeyPressed = false
                    self.handleAutomaticKeyRelease(for: .promptAssignment, label: "Prompt shortcut")
                case .toggle:
                    break
                }
                return nil
            }

            // Transcription key up
            // Note: Only check keyCode, not modifiers - user may release modifier before/with main key
            if self.finishPrimaryShortcutPress(.keyboard(keyCode)) {
                self.handlePrimaryDictationTriggerUp()
                return nil
            }

        case .flagsChanged:
            if HotkeyShortcut.modifierFlag(forKeyCode: keyCode) != nil {
                self.pressedModifierKeyCodes = self.synchronizedPressedModifierKeyCodes(
                    changedKeyCode: keyCode,
                    modifiers: eventModifiers
                )
            }

            for shortcut in self.primaryShortcuts where shortcut.isModifierOnlyShortcut {
                if self.handleModifierOnlyShortcutFlagsChanged(
                    behavior: self.primaryModifierOnlyBehavior(for: shortcut),
                    keyCode: keyCode,
                    modifiers: eventModifiers
                ) { return nil }
            }

            if self.handlePromptAssignmentFlagsChanged(keyCode: keyCode, modifiers: eventModifiers) { return nil }

            if self.handlePromptModeFlagsChanged(keyCode: keyCode, modifiers: eventModifiers) { return nil }

            if let commandModeShortcut = self.commandModeShortcut,
               self.handleModifierOnlyShortcutFlagsChanged(
                   behavior: .init(
                       shortcut: commandModeShortcut,
                       isEnabled: self.commandModeShortcutEnabled,
                       holdModeType: .commandMode,
                       holdStartMessage: "Command mode modifier held (hold mode) - starting",
                       holdReleaseMessage: "Command mode modifier released (hold mode) - stopping",
                       toggleIgnoredMessage: "Command mode modifier released but another key was pressed - ignoring",
                       isModeKeyPressed: { self.isCommandModeKeyPressed },
                       setModeKeyPressed: { self.isCommandModeKeyPressed = $0 },
                       onHoldStart: { self.triggerCommandMode() },
                       onToggleRelease: {
                           if self.asrService.isRunningOrStarting {
                               if self.isCommandRecordingProvider?() ?? false {
                                   DebugLogger.shared.info("Command mode modifier released (toggle, same mode) - stopping", source: "GlobalHotkeyManager")
                                   self.stopRecordingIfNeeded()
                               } else {
                                   DebugLogger.shared.info("Command mode modifier released (toggle, switch mode) - switching", source: "GlobalHotkeyManager")
                                   self.triggerCommandMode()
                               }
                           } else {
                               DebugLogger.shared.info("Command mode modifier released (toggle) - starting", source: "GlobalHotkeyManager")
                               self.triggerCommandMode()
                           }
                       },
                       isTargetModeActive: { self.isCommandRecordingProvider?() ?? false }
                   ),
                   keyCode: keyCode,
                   modifiers: eventModifiers
               )
            { return nil }

            if self.handleModifierOnlyShortcutFlagsChanged(
                behavior: .init(
                    shortcut: self.rewriteModeShortcut,
                    isEnabled: self.rewriteModeShortcutEnabled,
                    holdModeType: .rewriteMode,
                    holdStartMessage: "Rewrite mode modifier held (hold mode) - starting",
                    holdReleaseMessage: "Rewrite mode modifier released (hold mode) - stopping",
                    toggleIgnoredMessage: "Rewrite mode modifier released but another key was pressed - ignoring",
                    isModeKeyPressed: { self.isRewriteKeyPressed },
                    setModeKeyPressed: { self.isRewriteKeyPressed = $0 },
                    onHoldStart: { self.triggerRewriteMode() },
                    onToggleRelease: {
                        if self.asrService.isRunningOrStarting {
                            if self.isRewriteRecordingProvider?() ?? false {
                                DebugLogger.shared.info("Rewrite mode modifier released (toggle, same mode) - stopping", source: "GlobalHotkeyManager")
                                self.stopRecordingIfNeeded()
                            } else {
                                DebugLogger.shared.info("Rewrite mode modifier released (toggle, switch mode) - switching", source: "GlobalHotkeyManager")
                                self.triggerRewriteMode()
                            }
                        } else {
                            DebugLogger.shared.info("Rewrite mode modifier released (toggle) - starting", source: "GlobalHotkeyManager")
                            self.triggerRewriteMode()
                        }
                    },
                    isTargetModeActive: { self.isRewriteRecordingProvider?() ?? false }
                ),
                keyCode: keyCode,
                modifiers: eventModifiers
            ) { return nil }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    nonisolated static func isTapDisabledNotice(_ type: CGEventType) -> Bool {
        type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
    }

    /// Called on the keyboard tap thread when macOS disables the tap.
    private nonisolated func reenableKeyboardTapOnTapThread() {
        guard let tap = self.eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleTapDisableEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard Self.isTapDisabledNotice(type) else { return nil }
        self.recoverFromKeyboardTapDisable(type: type)
        return Unmanaged.passUnretained(event)
    }

    private func recoverFromKeyboardTapDisable(type: CGEventType) {
        // macOS can temporarily disable event taps (e.g. timeouts, user input protection).
        // If we don't immediately re-enable, hotkeys silently stop working until the periodic
        // health check kicks in, and the OS may handle the key (e.g. system dictation). The tap
        // thread normally re-enabled it already; key-ups may have been lost while it was off.
        let reason = (type == .tapDisabledByTimeout) ? "timeout" : "user input"
        DebugLogger.shared.warning("Event tap disabled by \(reason) — re-enabling and resetting tracking", source: "GlobalHotkeyManager")
        self.resetModifierOnlyShortcutTracking(reason: .tapDisabled)

        if let tap = self.eventTap, !self.isEventTapEnabled() {
            CGEvent.tapEnable(tap: tap, enable: true)
        }

        if !self.isEventTapEnabled() {
            DebugLogger.shared.warning("Event tap re-enable failed — recreating tap", source: "GlobalHotkeyManager")
            self.attemptTapInstall(reason: "tap_disabled")
        }
    }

    private func synchronizedPressedModifierKeyCodes(
        changedKeyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> Set<UInt16> {
        guard let changedFlag = HotkeyShortcut.modifierFlag(forKeyCode: changedKeyCode) else {
            return self.pressedModifierKeyCodes
        }

        let activeModifiers = modifiers.intersection(HotkeyShortcut.relevantModifierMask)
        let activeModifierGroups: [(NSEvent.ModifierFlags, [UInt16])] = [
            (.function, [63]),
            (.command, [55, 54]),
            (.option, [58, 61]),
            (.control, [59, 62]),
            (.shift, [56, 60]),
        ]

        // Flags tell us a modifier family is active, not which physical side. Preserve the
        // side-specific keys we already observed instead of rediscovering them from keyState.
        var synchronizedKeyCodes = self.pressedModifierKeyCodes.filter { keyCode in
            guard let flag = HotkeyShortcut.modifierFlag(forKeyCode: keyCode) else { return false }
            return activeModifiers.contains(flag)
        }

        guard let changedGroup = activeModifierGroups.first(where: { $0.0 == changedFlag }) else {
            return synchronizedKeyCodes
        }

        if activeModifiers.contains(changedFlag) {
            if synchronizedKeyCodes.contains(changedKeyCode) {
                let siblingKeyCodes = changedGroup.1.filter { $0 != changedKeyCode }
                let siblingIsTracked = siblingKeyCodes.contains { synchronizedKeyCodes.contains($0) }
                if siblingIsTracked,
                   !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(changedKeyCode))
                {
                    synchronizedKeyCodes.remove(changedKeyCode)
                }
            } else {
                synchronizedKeyCodes.insert(changedKeyCode)
            }
        } else {
            synchronizedKeyCodes.subtract(changedGroup.1)
        }

        return synchronizedKeyCodes
    }

    private func markModifierOnlyPressInterrupted(message: String) {
        self.otherKeyPressedDuringModifier = true
        DebugLogger.shared.info(message, source: "GlobalHotkeyManager")
    }

    private func handleAutomaticKeyRelease(
        for type: HotkeyHoldModeType,
        label: String,
        onUnstartedTap: (() -> Void)? = nil
    ) {
        let press = self.finishAutomaticPress(for: type)
        let duration = String(format: "%.2f", press.duration)

        if press.duration < self.automaticTapThresholdSeconds {
            if press.wasTargetActive {
                DebugLogger.shared.info("\(label) tap (\(duration)s) - stopping", source: "GlobalHotkeyManager")
                self.stopRecordingIfNeeded()
            } else if press.started {
                DebugLogger.shared.info("\(label) tap (\(duration)s) - continuing", source: "GlobalHotkeyManager")
            } else {
                DebugLogger.shared.info("\(label) tap (\(duration)s) - toggling", source: "GlobalHotkeyManager")
                onUnstartedTap?()
            }
            return
        }

        if press.wasTargetActive || press.started {
            DebugLogger.shared.info("\(label) hold (\(duration)s) - stopping", source: "GlobalHotkeyManager")
            self.stopRecordingAfterRelease(for: type, label: label)
        } else {
            DebugLogger.shared.debug("\(label) hold (\(duration)s) ignored - no automatic start", source: "GlobalHotkeyManager")
        }
    }

    private func handlePrimaryDictationTriggerDown() {
        switch self.hotkeyMode {
        case .hold:
            if !self.isKeyPressed {
                self.cancelPendingReleaseStop(for: .transcription)
                self.clearHoldModeStartTriggered(for: .transcription)
                self.isKeyPressed = true
                if self.asrService.isRunning {
                    let isSameMode = self.isDictateRecordingProvider?() ?? false
                    DebugLogger.shared.debug(
                        "GlobalHotkeyManager: dictation hold-press path",
                        source: "GlobalHotkeyManager"
                    )
                    DebugLogger.shared.info(
                        "Hotkey route | pressed=dictate | active=\(isSameMode ? "dictate" : "other") | asrRunning=true | action=\(isSameMode ? "stop" : "switch")",
                        source: "GlobalHotkeyManager"
                    )
                    if !isSameMode {
                        self.triggerDictationMode()
                    }
                } else {
                    DebugLogger.shared.info(
                        "Hotkey route | pressed=dictate | active=none | asrRunning=false | action=start",
                        source: "GlobalHotkeyManager"
                    )
                    self.startRecordingIfNeeded()
                }
                self.markHoldModeStartTriggered(for: .transcription)
            }
        case .automatic:
            if !self.isKeyPressed {
                self.isKeyPressed = true
                let isSameMode = self.asrService.isRunning && (self.isDictateRecordingProvider?() ?? false)
                self.beginAutomaticPress(for: .transcription, wasTargetActive: isSameMode)
                if self.asrService.isRunning {
                    DebugLogger.shared.info(
                        "Hotkey route | pressed=dictate | active=\(isSameMode ? "dictate" : "other") | asrRunning=true | action=\(isSameMode ? "release-stop" : "switch")",
                        source: "GlobalHotkeyManager"
                    )
                    if !isSameMode {
                        self.triggerDictationMode()
                        self.markAutomaticPressStarted(for: .transcription)
                    }
                } else {
                    DebugLogger.shared.info(
                        "Hotkey route | pressed=dictate | active=none | asrRunning=false | action=start",
                        source: "GlobalHotkeyManager"
                    )
                    self.triggerDictationMode()
                    self.markAutomaticPressStarted(for: .transcription)
                }
            }
        case .toggle:
            if self.asrService.isRunningOrStarting {
                let isSameMode = self.isDictateRecordingProvider?() ?? false
                DebugLogger.shared.debug(
                    "GlobalHotkeyManager: dictation tap path while already running",
                    source: "GlobalHotkeyManager"
                )
                DebugLogger.shared.info(
                    "Hotkey route | pressed=dictate | active=\(isSameMode ? "dictate" : "other") | asrRunning=true | action=\(isSameMode ? "stop" : "switch")",
                    source: "GlobalHotkeyManager"
                )
                if isSameMode {
                    self.stopRecordingIfNeeded()
                } else {
                    self.triggerDictationMode()
                }
            } else {
                DebugLogger.shared.info(
                    "Hotkey route | pressed=dictate | active=none | asrRunning=false | action=start",
                    source: "GlobalHotkeyManager"
                )
                self.triggerDictationMode()
            }
        }
    }

    private func handlePrimaryDictationTriggerUp() {
        switch self.hotkeyMode {
        case .hold:
            self.isKeyPressed = false
            _ = self.finishHoldModeStartTriggered(for: .transcription)
            self.stopRecordingAfterRelease(for: .transcription, label: "Transcription")
        case .automatic:
            self.isKeyPressed = false
            self.handleAutomaticKeyRelease(for: .transcription, label: "Transcription")
        case .toggle:
            break
        }
    }

    private func isRecordingTargetActive(for type: HotkeyHoldModeType) -> Bool {
        switch type {
        case .transcription:
            guard let provider = self.isDictateRecordingProvider else { return true }
            return provider()
        case .promptMode:
            guard let provider = self.isPromptModeRecordingProvider else { return true }
            return provider()
        case .commandMode:
            guard let provider = self.isCommandRecordingProvider else { return true }
            return provider()
        case .rewriteMode:
            guard let provider = self.isRewriteRecordingProvider else { return true }
            return provider()
        case .promptAssignment:
            guard let provider = self.isPromptModeRecordingProvider else { return true }
            return provider()
        }
    }

    /// Ends the recording a released hold owns: now if it is running, or as soon as a start still in
    /// flight settles (see HoldReleaseStopLatch). There is no timeout that gives up.
    private func stopRecordingAfterRelease(
        for type: HotkeyHoldModeType,
        label: String,
        requireTargetMode: Bool = true
    ) {
        let outcome = self.holdReleaseStopLatch.release(
            .init(
                type: type,
                label: label,
                requireTargetMode: requireTargetMode,
                releasedAt: self.currentEventReceivedAt()
            )
        )
        if outcome == .nothingToStop {
            DebugLogger.shared.debug("\(label) released with no recording or start in flight", source: "GlobalHotkeyManager")
        }
    }

    private func label(for type: HotkeyHoldModeType) -> String {
        switch type {
        case .transcription:
            return "Transcription"
        case .promptMode:
            return "Prompt mode"
        case .commandMode:
            return "Command mode"
        case .rewriteMode:
            return "Rewrite mode"
        case .promptAssignment:
            return "Prompt shortcut"
        }
    }

    private func scheduleModifierOnlyStart(for behavior: ModifierOnlyShortcutBehavior) {
        guard self.hotkeyMode != .toggle, !behavior.isModeKeyPressed() else { return }

        self.cancelPendingReleaseStop(for: behavior.holdModeType)
        self.clearHoldModeStartTriggered(for: behavior.holdModeType)
        behavior.setModeKeyPressed(true)

        let wasTargetActive = self.asrService.isRunning && behavior.isTargetModeActive()
        if self.hotkeyMode == .automatic {
            self.beginAutomaticPress(for: behavior.holdModeType, wasTargetActive: wasTargetActive)
        }

        guard self.hotkeyMode != .automatic || !wasTargetActive else { return }
        DebugLogger.shared.info(behavior.holdStartMessage, source: "GlobalHotkeyManager")
        if self.hotkeyMode == .hold {
            self.markHoldModeStartTriggered(for: behavior.holdModeType)
        }
        behavior.onHoldStart()
        if self.hotkeyMode == .automatic {
            self.markAutomaticPressStarted(for: behavior.holdModeType)
        }
    }

    private func finishModifierOnlyPress(
        for behavior: ModifierOnlyShortcutBehavior,
        wasCleanPress: Bool
    ) {
        switch self.hotkeyMode {
        case .hold:
            if behavior.isModeKeyPressed() {
                behavior.setModeKeyPressed(false)
                let didStart = self.finishHoldModeStartTriggered(for: behavior.holdModeType)
                if self.asrService.isRunning || didStart {
                    DebugLogger.shared.info(behavior.holdReleaseMessage, source: "GlobalHotkeyManager")
                    self.stopRecordingAfterRelease(for: behavior.holdModeType, label: self.label(for: behavior.holdModeType))
                }
            }
        case .automatic:
            if behavior.isModeKeyPressed() {
                behavior.setModeKeyPressed(false)
            }
            if wasCleanPress {
                self.handleAutomaticKeyRelease(
                    for: behavior.holdModeType,
                    label: self.label(for: behavior.holdModeType),
                    onUnstartedTap: behavior.onToggleRelease
                )
            } else {
                let press = self.finishAutomaticPress(for: behavior.holdModeType)
                if press.started {
                    DebugLogger.shared.info("\(self.label(for: behavior.holdModeType)) modifier released after combo - stopping automatic start", source: "GlobalHotkeyManager")
                    self.stopRecordingAfterRelease(for: behavior.holdModeType, label: self.label(for: behavior.holdModeType))
                } else {
                    DebugLogger.shared.debug(behavior.toggleIgnoredMessage, source: "GlobalHotkeyManager")
                }
            }
        case .toggle:
            if wasCleanPress {
                behavior.onToggleRelease()
            } else {
                DebugLogger.shared.debug(behavior.toggleIgnoredMessage, source: "GlobalHotkeyManager")
            }
        }
    }

    func resetModifierOnlyShortcutTracking(reason: ModifierTrackingResetReason = .shortcutCapture) {
        // An active mouse hold loses its press record below, so its mouse-up could no longer stop
        // it. End it first through the interrupted-press path, which also stops a still-starting
        // recording. (A keyboard-tap outage alone would not lose the mouse-up; stopping there is the
        // conservative choice and matches what a mouse-tap outage does.)
        let finishedMousePress = self.finishInterruptedMouseShortcutPress(reason: "shortcut tracking reset (\(reason))")
        // "Starting" includes a hotkey start dispatched but not yet visible in ASR (the latch's view).
        let shouldStopActiveHold = !finishedMousePress && Self.shouldStopHeldRecordingOnTrackingReset(
            activationMode: self.hotkeyMode,
            isRunningOrStarting: self.asrService.isRunning || self.holdReleaseStopLatch.isStartInFlight,
            isAnyHoldKeyPressed: self.isKeyPressed || self.isPromptModeKeyPressed || self.isCommandModeKeyPressed
                || self.isRewriteKeyPressed || self.isPromptAssignmentKeyPressed
        )

        self.pressedModifierKeyCodes = []
        self.modifierOnlyKeyDown = false
        self.activeModifierOnlyType = nil
        self.otherKeyPressedDuringModifier = false
        self.modifierPressStartTime = nil
        self.clearAutomaticPressTracking()
        self.isKeyPressed = false
        self.isPromptModeKeyPressed = false
        self.isCommandModeKeyPressed = false
        self.isRewriteKeyPressed = false
        self.isPromptAssignmentKeyPressed = false
        self.activePrimaryShortcutPress = nil

        if shouldStopActiveHold {
            switch reason {
            case .shortcutCapture:
                DebugLogger.shared.debug("Shortcut capture active - stopping active hold recording before reset", source: "GlobalHotkeyManager")
            case .tapDisabled:
                DebugLogger.shared.warning("Event tap disabled during active hold - stopping recording before reset", source: "GlobalHotkeyManager")
            case .reinitialize:
                DebugLogger.shared.info("Hotkey manager reinitializing - stopping active hold recording before reset", source: "GlobalHotkeyManager")
            }
            // Treated as a release: stop now if running, otherwise when the start in flight settles.
            self.stopRecordingAfterRelease(
                for: .transcription,
                label: "Shortcut tracking reset",
                requireTargetMode: false
            )
        }
    }

    /// A hold or automatic press that is reset mid-flight must stop its recording, and "recording"
    /// includes a start still in flight: a direct Core Audio start can take seconds.
    nonisolated static func shouldStopHeldRecordingOnTrackingReset(
        activationMode: HotkeyActivationMode,
        isRunningOrStarting: Bool,
        isAnyHoldKeyPressed: Bool
    ) -> Bool {
        activationMode != .toggle && isRunningOrStarting && isAnyHoldKeyPressed
    }

    private func handlePromptModeKeyDown(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard self.promptModeShortcutEnabled, self.promptModeShortcut.matches(keyCode: keyCode, modifiers: modifiers) else { return false }
        switch self.hotkeyMode {
        case .hold:
            if !self.isPromptModeKeyPressed {
                self.cancelPendingReleaseStop(for: .promptMode)
                self.clearHoldModeStartTriggered(for: .promptMode)
                self.isPromptModeKeyPressed = true
                DebugLogger.shared.info("Prompt mode shortcut pressed (hold mode) - starting", source: "GlobalHotkeyManager")
                self.triggerPromptMode()
                self.markHoldModeStartTriggered(for: .promptMode)
            }
        case .automatic:
            if !self.isPromptModeKeyPressed {
                self.isPromptModeKeyPressed = true
                let isSameMode = self.asrService.isRunning && (self.isPromptModeRecordingProvider?() ?? false)
                self.beginAutomaticPress(for: .promptMode, wasTargetActive: isSameMode)
                if self.asrService.isRunning {
                    if isSameMode {
                        DebugLogger.shared.info("Prompt mode shortcut pressed (automatic, same mode) - waiting for release", source: "GlobalHotkeyManager")
                    } else {
                        DebugLogger.shared.info("Prompt mode shortcut pressed (automatic, switch mode)", source: "GlobalHotkeyManager")
                        self.triggerPromptMode()
                        self.markAutomaticPressStarted(for: .promptMode)
                    }
                } else {
                    DebugLogger.shared.info("Prompt mode shortcut triggered (automatic) - starting", source: "GlobalHotkeyManager")
                    self.triggerPromptMode()
                    self.markAutomaticPressStarted(for: .promptMode)
                }
            }
        case .toggle:
            if self.asrService.isRunningOrStarting {
                if self.isPromptModeRecordingProvider?() ?? false {
                    DebugLogger.shared.info("Prompt mode shortcut pressed in Prompt mode - stopping", source: "GlobalHotkeyManager")
                    self.stopRecordingIfNeeded()
                } else {
                    DebugLogger.shared.info("Prompt mode shortcut pressed while recording - switching mode", source: "GlobalHotkeyManager")
                    self.triggerPromptMode()
                }
            } else {
                DebugLogger.shared.info("Prompt mode shortcut triggered - starting", source: "GlobalHotkeyManager")
                self.triggerPromptMode()
            }
        }
        return true
    }

    private func handlePromptModeKeyUp(keyCode: UInt16) -> Bool {
        guard self.promptModeShortcutEnabled,
              self.isPromptModeKeyPressed, keyCode == self.promptModeShortcut.keyCode else { return false }
        switch self.hotkeyMode {
        case .hold:
            self.isPromptModeKeyPressed = false
            _ = self.finishHoldModeStartTriggered(for: .promptMode)
            DebugLogger.shared.info("Prompt mode shortcut released (hold mode) - stopping", source: "GlobalHotkeyManager")
            self.stopRecordingAfterRelease(for: .promptMode, label: "Prompt mode")
        case .automatic:
            self.isPromptModeKeyPressed = false
            self.handleAutomaticKeyRelease(for: .promptMode, label: "Prompt mode")
        case .toggle:
            break
        }
        return true
    }

    private func handlePromptModeFlagsChanged(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        self.handleModifierOnlyShortcutFlagsChanged(
            behavior: .init(
                shortcut: self.promptModeShortcut,
                isEnabled: self.promptModeShortcutEnabled,
                holdModeType: .promptMode,
                holdStartMessage: "Prompt mode modifier held (hold mode) - starting",
                holdReleaseMessage: "Prompt mode modifier released (hold mode) - stopping",
                toggleIgnoredMessage: "Prompt mode modifier released but another key was pressed - ignoring",
                isModeKeyPressed: { self.isPromptModeKeyPressed },
                setModeKeyPressed: { self.isPromptModeKeyPressed = $0 },
                onHoldStart: { self.triggerPromptMode() },
                onToggleRelease: {
                    if self.asrService.isRunningOrStarting {
                        if self.isPromptModeRecordingProvider?() ?? false {
                            DebugLogger.shared.info("Prompt mode modifier released (toggle, same mode) - stopping", source: "GlobalHotkeyManager")
                            self.stopRecordingIfNeeded()
                        } else {
                            DebugLogger.shared.info("Prompt mode modifier released (toggle, switch mode) - switching", source: "GlobalHotkeyManager")
                            self.triggerPromptMode()
                        }
                    } else {
                        DebugLogger.shared.info("Prompt mode modifier released (toggle) - starting", source: "GlobalHotkeyManager")
                        self.triggerPromptMode()
                    }
                },
                isTargetModeActive: { self.isPromptModeRecordingProvider?() ?? false }
            ),
            keyCode: keyCode,
            modifiers: modifiers
        )
    }

    private func handlePromptAssignmentFlagsChanged(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        for assignment in self.promptShortcutAssignments where assignment.shortcut.isModifierOnlyShortcut {
            let handled = self.handleModifierOnlyShortcutFlagsChanged(
                behavior: .init(
                    shortcut: assignment.shortcut,
                    isEnabled: true,
                    holdModeType: .promptAssignment,
                    holdStartMessage: "Prompt shortcut modifier held (hold mode) - starting",
                    holdReleaseMessage: "Prompt shortcut modifier released (hold mode) - stopping",
                    toggleIgnoredMessage: "Prompt shortcut modifier released but another key was pressed - ignoring",
                    isModeKeyPressed: { self.isPromptAssignmentKeyPressed },
                    setModeKeyPressed: { self.isPromptAssignmentKeyPressed = $0 },
                    onHoldStart: { self.triggerPromptSelection(assignment.selection) },
                    onToggleRelease: {
                        if self.asrService.isRunningOrStarting {
                            if self.isPromptModeRecordingProvider?() ?? false {
                                DebugLogger.shared.info("Prompt shortcut modifier released (toggle, same mode) - stopping", source: "GlobalHotkeyManager")
                                self.stopRecordingIfNeeded()
                            } else {
                                DebugLogger.shared.info("Prompt shortcut modifier released (toggle, switch mode) - switching", source: "GlobalHotkeyManager")
                                self.triggerPromptSelection(assignment.selection)
                            }
                        } else {
                            DebugLogger.shared.info("Prompt shortcut modifier released (toggle) - starting", source: "GlobalHotkeyManager")
                            self.triggerPromptSelection(assignment.selection)
                        }
                    },
                    isTargetModeActive: { self.isPromptModeRecordingProvider?() ?? false }
                ),
                keyCode: keyCode,
                modifiers: modifiers
            )
            if handled {
                return true
            }
        }

        return false
    }

    private func handleModifierOnlyShortcutFlagsChanged(
        behavior: ModifierOnlyShortcutBehavior,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        let decision = ModifierOnlyShortcutFlagsDecision.evaluate(
            shortcut: behavior.shortcut,
            holdModeType: behavior.holdModeType,
            isEnabled: behavior.isEnabled,
            keyCode: keyCode,
            modifiers: modifiers,
            state: ModifierOnlyShortcutTrackingState(
                pressedModifierKeyCodes: self.pressedModifierKeyCodes,
                activeModifierOnlyType: self.activeModifierOnlyType,
                activeModifierOnlyShortcut: self.activeModifierOnlyShortcut,
                otherKeyPressedDuringModifier: self.otherKeyPressedDuringModifier,
                isModeKeyPressed: behavior.isModeKeyPressed()
            )
        )

        self.activeModifierOnlyType = decision.activeModifierOnlyType
        self.activeModifierOnlyShortcut = decision.activeModifierOnlyShortcut
        if decision.markInterrupted {
            self.markModifierOnlyPressInterrupted(
                message: "\(self.label(for: behavior.holdModeType)) modifier-only press interrupted - extra modifier pressed"
            )
        }
        self.otherKeyPressedDuringModifier = decision.otherKeyPressedDuringModifier

        switch decision.outcome {
        case .ignore:
            return false
        case .start:
            self.modifierOnlyKeyDown = true
            self.modifierPressStartTime = Date()

            self.scheduleModifierOnlyStart(for: behavior)
            return true
        case let .finish(wasCleanPress):
            self.modifierOnlyKeyDown = false
            self.modifierPressStartTime = nil

            self.finishModifierOnlyPress(for: behavior, wasCleanPress: wasCleanPress)
            return true
        }
    }

    /// Runs a hotkey action that may start a capture. Until the capture start it dispatched has
    /// finished, a hold release counts as arriving during a start, so it is latched rather than
    /// lost (see HoldReleaseStopLatch.trackStart).
    /// When the last starting press arrived, for START_SUMMARY: the start counts from the press,
    /// recorded only once the action's own checks accept it (`markStartAccepted`).
    private var startPressAt: TimeInterval?

    private func markStartAccepted() {
        StartPathTrace.hotkeyPressed(at: self.startPressAt ?? ProcessInfo.processInfo.systemUptime)
        self.startPressAt = nil
    }

    private func performStartingHotkeyAction(_ action: @escaping @MainActor () async -> HotkeyCaptureStartTask?) {
        self.startPressAt = ProcessInfo.processInfo.systemUptime
        self.holdReleaseStopLatch.trackStart(action)
    }

    private func triggerPromptMode() {
        self.performStartingHotkeyAction { [weak self] in
            guard let self = self else { return nil }
            guard self.canTriggerRecordingAction("Prompt mode hotkey") else { return nil }
            self.markStartAccepted()
            DebugLogger.shared.info("Prompt mode hotkey triggered", source: "GlobalHotkeyManager")
            return await self.promptModeCallback?() ?? nil
        }
    }

    private func triggerPromptSelection(_ selection: SettingsStore.DictationPromptSelection) {
        self.performStartingHotkeyAction { [weak self] in
            guard let self = self else { return nil }
            guard self.canTriggerRecordingAction("Prompt selection hotkey") else { return nil }
            self.markStartAccepted()
            DebugLogger.shared.info("Prompt selection hotkey triggered", source: "GlobalHotkeyManager")
            return await self.promptSelectionCallback?(selection) ?? nil
        }
    }

    private func triggerCommandMode() {
        self.performStartingHotkeyAction { [weak self] in
            guard let self = self else { return nil }
            guard self.canTriggerRecordingAction("Command mode hotkey") else { return nil }
            self.markStartAccepted()
            DebugLogger.shared.info("Command mode hotkey triggered", source: "GlobalHotkeyManager")
            DebugLogger.shared.debug(
                "GlobalHotkeyManager: command callback path, isRunning=\(self.asrService.isRunning), isReady=\(self.asrService.isAsrReady)",
                source: "GlobalHotkeyManager"
            )
            return await self.commandModeCallback?() ?? nil
        }
    }

    private func triggerRewriteMode() {
        self.performStartingHotkeyAction { [weak self] in
            guard let self = self else { return nil }
            guard self.canTriggerRecordingAction("Rewrite mode hotkey") else { return nil }
            self.markStartAccepted()
            DebugLogger.shared.info("Rewrite mode hotkey triggered", source: "GlobalHotkeyManager")
            DebugLogger.shared.debug(
                "GlobalHotkeyManager: rewrite callback path, isRunning=\(self.asrService.isRunning), isReady=\(self.asrService.isAsrReady)",
                source: "GlobalHotkeyManager"
            )
            return await self.rewriteModeCallback?() ?? nil
        }
    }

    /// Handles a mouse-button down event against the configured mouse shortcuts. Returns true when
    /// the event was consumed. "Paste Last Transcription" and "Reprocess Last Dictation" are one-shot
    /// triggers (mirroring the keyboard path) whose paired mouse-up is swallowed; primary dictation
    /// begins a press here and ends it on mouse-up.
    private func handleMouseShortcutDown(_ event: CGEvent, modifiers eventModifiers: NSEvent.ModifierFlags) -> Bool {
        let mouseButton = self.mouseButton(from: event)
        // A new down on a button still waiting for its swallowed up proves that up was missed.
        self.state.withLock { self.state.oneShotMouseUpSwallow.observedDown(button: mouseButton) }

        if SettingsStore.shared.pasteLastTranscriptionShortcutEnabled,
           let pasteShortcut = SettingsStore.shared.pasteLastTranscriptionHotkeyShortcut,
           pasteShortcut.matchesMouse(button: mouseButton, modifiers: eventModifiers)
        {
            self.state.withLock { self.state.oneShotMouseUpSwallow.consumedDown(button: mouseButton) }
            self.triggerPasteLastTranscription(isAutorepeat: false)
            return true
        }

        if SettingsStore.shared.reprocessLastDictationShortcutEnabled,
           let reprocessShortcut = SettingsStore.shared.reprocessLastDictationHotkeyShortcut,
           reprocessShortcut.matchesMouse(button: mouseButton, modifiers: eventModifiers)
        {
            self.state.withLock { self.state.oneShotMouseUpSwallow.consumedDown(button: mouseButton) }
            self.triggerReprocessLastDictation(isAutorepeat: false)
            return true
        }

        if self.primaryShortcuts.contains(where: { $0.matchesMouse(button: mouseButton, modifiers: eventModifiers) }) {
            guard self.beginPrimaryShortcutPress(.mouse(mouseButton)) else { return false }
            self.handlePrimaryDictationTriggerDown()
            return true
        }

        return false
    }

    /// Swallows only the mouse-up that pairs with a mouse-down this tap consumed.
    private func handleMouseShortcutUp(_ event: CGEvent) -> Bool {
        let mouseButton = self.mouseButton(from: event)

        let consumedOneShotDown = self.state.withLock {
            self.state.oneShotMouseUpSwallow.shouldSwallowUp(button: mouseButton)
        }
        if consumedOneShotDown {
            return true
        }

        guard self.finishPrimaryShortcutPress(.mouse(mouseButton)) else { return false }
        self.handlePrimaryDictationTriggerUp()
        return true
    }

    private func triggerPasteLastTranscription(isAutorepeat: Bool) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // Holding the chord auto-repeats the key-down; act only on the initial press.
            guard !isAutorepeat else { return }
            guard self.canTriggerRecordingAction("Paste last transcription hotkey") else { return }
            // Re-pasting mid-recording would be surprising; ignore while capture is active.
            guard !self.asrService.isRunning else {
                DebugLogger.shared.info(
                    "Paste last transcription hotkey ignored - recording in progress",
                    source: "GlobalHotkeyManager"
                )
                return
            }
            DebugLogger.shared.info("Paste last transcription hotkey triggered", source: "GlobalHotkeyManager")
            self.pasteLastTranscriptionCallback?()
        }
    }

    private func triggerReprocessLastDictation(isAutorepeat: Bool) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // Holding the chord auto-repeats the key-down; act only on the initial press.
            guard !isAutorepeat else { return }
            guard self.canTriggerRecordingAction("Reprocess last dictation hotkey") else { return }
            // Reprocessing mid-capture would race the in-flight transcription; ignore while recording.
            guard !self.asrService.isRunning else {
                DebugLogger.shared.info(
                    "Reprocess last dictation hotkey ignored - recording in progress",
                    source: "GlobalHotkeyManager"
                )
                return
            }
            DebugLogger.shared.info("Reprocess last dictation hotkey triggered", source: "GlobalHotkeyManager")
            self.reprocessLastDictationCallback?()
        }
    }

    private func triggerDictationMode() {
        self.performStartingHotkeyAction { [weak self] in
            guard let self = self else { return nil }
            guard self.canTriggerRecordingAction("Dictate mode hotkey") else { return nil }
            self.markStartAccepted()
            let model = SettingsStore.shared.selectedSpeechModel
            DebugLogger.shared.info("Dictate mode hotkey triggered", source: "GlobalHotkeyManager")
            DebugLogger.shared.debug(
                "GlobalHotkeyManager: dictate callback path, isRunning=\(self.asrService.isRunning), isReady=\(self.asrService.isAsrReady), model=\(model.displayName)",
                source: "GlobalHotkeyManager"
            )
            if let callback = self.dictationModeCallback {
                DebugLogger.shared.debug("GlobalHotkeyManager: invoking dictationModeCallback", source: "GlobalHotkeyManager")
                return await callback()
            } else if let startCallback = self.startRecordingCallback {
                DebugLogger.shared.debug(
                    "GlobalHotkeyManager: dictationModeCallback missing; invoking fallback callback",
                    source: "GlobalHotkeyManager"
                )
                return await startCallback()
            } else {
                DebugLogger.shared.warning(
                    "GlobalHotkeyManager: dictation callbacks missing; invoking ASRService.start directly",
                    source: "GlobalHotkeyManager"
                )
                // Awaited here, so the start has settled by the time the action returns.
                await self.asrService.start()
                return nil
            }
        }
    }

    func setHotkeyMode(_ mode: HotkeyActivationMode) {
        // A held press is about to lose its tracking, so its release could no longer stop it. That
        // includes a press whose capture is still starting.
        let shouldStopActivePress = self.hotkeyMode != .toggle
            && (self.asrService.isRunning || self.holdReleaseStopLatch.isStartInFlight)
            && (self.isKeyPressed || self.isPromptModeKeyPressed || self.isCommandModeKeyPressed || self.isRewriteKeyPressed || self.isPromptAssignmentKeyPressed)

        self.hotkeyMode = mode
        self.clearAutomaticPressTracking()
        self.isKeyPressed = false
        self.isPromptModeKeyPressed = false
        self.isCommandModeKeyPressed = false
        self.isRewriteKeyPressed = false
        self.isPromptAssignmentKeyPressed = false
        self.activePrimaryShortcutPress = nil

        if shouldStopActivePress {
            // Treated as a release: stop now if running, otherwise when the start in flight settles.
            self.stopRecordingAfterRelease(
                for: .transcription,
                label: "Hotkey mode change",
                requireTargetMode: false
            )
        }
        DebugLogger.shared.info("Hotkey activation mode set to \(mode.displayName)", source: "GlobalHotkeyManager")
        self.scheduleActiveShortcutLog(reason: "shortcuts updated")
    }

    func enablePressAndHoldMode(_ enable: Bool) {
        self.setHotkeyMode(enable ? .hold : .toggle)
    }

    private func canTriggerRecordingAction(_ label: String) -> Bool {
        guard !Self.currentSessionIsLocked() else {
            DebugLogger.shared.info("Ignoring \(label) - screen is locked", source: "GlobalHotkeyManager")
            return false
        }
        guard !self.isProcessingStop else {
            DebugLogger.shared.debug("Ignoring \(label) - stop already processing", source: "GlobalHotkeyManager")
            return false
        }
        guard !self.asrService.isDictionaryTrainingCaptureActive else {
            DebugLogger.shared.debug("Ignoring \(label) - dictionary training capture is active", source: "GlobalHotkeyManager")
            return false
        }
        return true
    }

    /// Start / Stop Dictation from the menu bar menu: the same guarded toggle as the hotkey.
    func toggleRecordingFromMenu() {
        self.toggleRecording()
    }

    private func toggleRecording() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Prevent new operations while stop is processing
            guard self.canTriggerRecordingAction("toggle") else { return }

            if self.asrService.isRunningOrStarting {
                await self.stopRecordingInternal()
            } else {
                // Use callback if available, otherwise fallback to direct start. A toggle press has
                // no release to latch, so the dispatched start is not tracked.
                if let callback = self.startRecordingCallback {
                    _ = await callback()
                } else {
                    await self.asrService.start()
                }
            }
        }
    }

    private func startRecordingIfNeeded() {
        self.performStartingHotkeyAction { [weak self] in
            guard let self = self else { return nil }

            // Prevent starting while stop is processing
            guard self.canTriggerRecordingAction("start") else { return nil }

            guard !self.asrService.isRunning else { return nil }
            self.markStartAccepted()
            // Use callback if available, otherwise fallback to direct start
            if let callback = self.startRecordingCallback {
                return await callback()
            }
            await self.asrService.start()
            return nil
        }
    }

    /// Whether a dictation shortcut is held down in hold or automatic mode, so letting go ends
    /// the recording. Spoken Send's pause countdown stays off while it is. A quick tap in
    /// automatic mode has been released by then, and counts as toggle.
    var isHoldingDictationShortcut: Bool {
        guard self.hotkeyMode != .toggle else { return false }
        return self.state.withLock {
            self.state.isKeyPressed || self.state.isPromptModeKeyPressed || self.state.isPromptAssignmentKeyPressed
                || self.state.activePrimaryShortcutPress != nil
        }
    }

    /// Stops the recording and processes it exactly as the stop hotkey does, through the same
    /// in-progress guard, so a stop requested by Spoken Send's quiet countdown and one from the
    /// hotkey can never both run.
    func requestStopAndProcess() {
        self.stopRecordingIfNeeded(trigger: .spokenSend, triggeredAt: ProcessInfo.processInfo.systemUptime)
    }

    /// - Parameters:
    ///   - trigger: what asked for the stop, for the stop-path trace.
    ///   - triggeredAt: when; defaults to when the tap received the event being handled.
    ///   - latched: the stop waited for a capture start to settle (see HoldReleaseStopLatch).
    private func stopRecordingIfNeeded(
        trigger: StopPathTrace.Trigger = .toggle,
        triggeredAt: TimeInterval? = nil,
        latched: Bool = false
    ) {
        let trace = StopPathTrace(
            trigger: trigger,
            at: triggeredAt ?? self.currentEventReceivedAt(),
            latched: latched
        )
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            if self.isProcessingStop {
                DebugLogger.shared.debug("Ignoring stop - already processing", source: "GlobalHotkeyManager")
                return
            }
            guard !self.asrService.isDictionaryTrainingCaptureActive else {
                DebugLogger.shared.debug("Ignoring stop - dictionary training capture is active", source: "GlobalHotkeyManager")
                return
            }

            guard self.asrService.isRunningOrStarting else {
                return
            }

            await self.stopRecordingInternal(trace: trace)
        }
    }

    @MainActor
    private func stopRecordingInternal(trace: StopPathTrace? = nil) async {
        if self.asrService.isStarting, self.asrService.isRunning == false {
            DebugLogger.shared.debug("Cancelling pending audio capture start", source: "GlobalHotkeyManager")
            await self.asrService.cancelPendingAudioCaptureStart(reason: "hotkey_released")
        }
        guard self.asrService.isRunning else { return }
        guard !self.asrService.isDictionaryTrainingCaptureActive else {
            DebugLogger.shared.debug("Stop ignored - dictionary training capture is active", source: "GlobalHotkeyManager")
            return
        }
        guard !self.isProcessingStop else {
            DebugLogger.shared.debug("Stop already in progress, ignoring", source: "GlobalHotkeyManager")
            return
        }

        self.isProcessingStop = true
        defer { isProcessingStop = false }

        if let callback = stopAndProcessCallback {
            // Taken by the stop pipeline on this same main-actor turn.
            StopPathTrace.stagePending(trace ?? StopPathTrace(trigger: .toggle))
            await callback()
        } else {
            await self.asrService.stopWithoutTranscription()
        }
    }

    func isEventTapEnabled() -> Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func validateEventTapHealth() -> Bool {
        // Treat an enabled event tap as "healthy", even if our internal `isInitialized` flag drifted.
        // This prevents false "initializing" UI while hotkeys are already working.
        let enabled = self.isEventTapEnabled()
        if enabled && !self.isInitialized {
            self.isInitialized = true
        }
        return enabled
    }

    func reinitialize() {
        DebugLogger.shared.info("Manual reinitialization requested", source: "GlobalHotkeyManager")

        self.initializationTask?.cancel()
        self.healthCheckTask?.cancel()
        self.tapRetryTask?.cancel()
        self.tapRetryTask = nil
        self.resetModifierOnlyShortcutTracking(reason: .reinitialize)
        self.isInitialized = false
        self.initializeWithDelay()
    }

    private func startHealthCheckTimer() {
        self.healthCheckTask?.cancel()
        self.healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let healthCheckInterval = self?.healthCheckInterval else { break }
                do {
                    try await Task.sleep(nanoseconds: UInt64(healthCheckInterval * 1_000_000_000))
                } catch {
                    break
                }

                guard !Task.isCancelled else { break }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if !self.validateEventTapHealth() {
                        DebugLogger.shared.warning("Health check failed, attempting to recover", source: "GlobalHotkeyManager")
                        // A revoked grant lands in waiting_for_accessibility and polls from there.
                        self.attemptTapInstall(reason: "health_check")
                    } else {
                        self.recoverMouseTapsIfNeeded()
                    }
                }
            }
        }
    }

    deinit {
        initializationTask?.cancel()
        healthCheckTask?.cancel()
        tapRetryTask?.cancel()
        cleanupEventTap()
    }
}
