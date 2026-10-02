import AppKit
import Combine
import Foundation

// Spoken Send for one dictation at a time: watches the live transcript for the send phrase,
// runs the quiet countdown, decides at stop whether a key follows the text, and hands the
// delivery to the typing worker. Behavior ported from altic-dev/FluidVoice by altic-dev
// (@c679506d, @95fe1b15, @60480451, and the Spoken Send parts of @4310f143 and @4cb6683f);
// upstream keeps this state in ContentView, MouthKeys keeps it here so the dictation stop
// path only asks two questions (what text, which key) and the overlay can observe it.

/// What Spoken Send decided for one finished dictation.
nonisolated struct SpokenSendDecision: Equatable, Sendable {
    /// The text to deliver: the phrase and its punctuation stripped when it was detected.
    let text: String
    /// The phrase ended the dictation (the text is stripped either way).
    let phraseDetected: Bool
    /// A key follows the text: the phrase was detected and the send was not canceled.
    let shouldSend: Bool

    /// Nothing is left to type once the phrase is stripped.
    var isPhraseOnly: Bool {
        self.phraseDetected && self.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func unchanged(_ text: String) -> SpokenSendDecision {
        SpokenSendDecision(text: text, phraseDetected: false, shouldSend: false)
    }
}

@MainActor
final class SpokenSendController: ObservableObject {
    static let shared = SpokenSendController()

    /// What the overlay's send chip shows.
    enum Indicator: Equatable {
        case hidden
        /// The phrase ends what was said so far: the key follows the text when dictation stops.
        case armed
        /// Waiting for a short silence, then dictation stops and sends.
        case countingDown
        /// The user canceled the send for this dictation. The phrase is still left out.
        case canceled

        var isVisible: Bool {
            self != .hidden
        }
    }

    @Published private(set) var indicator: Indicator = .hidden
    /// False when the app being dictated into never gets the key (a terminal other than c11).
    @Published private(set) var sendsInRecordingApp = true
    /// Changes with every countdown, so the overlay restarts its ring.
    @Published private(set) var countdownID: UInt64 = 0

    struct Configuration: Equatable {
        var enabled: Bool
        var phrase: String
        var stopsAfterPause: Bool
        var key: SettingsStore.SpokenSendKey
        var allowsC11: Bool

        static func current() -> Configuration {
            let settings = SettingsStore.shared
            return Configuration(
                enabled: settings.spokenSendEnabled,
                phrase: settings.spokenSendPhrase,
                stopsAfterPause: settings.spokenSendImmediatelyEnabled,
                key: settings.spokenSendKey,
                allowsC11: settings.spokenSendAllowsC11
            )
        }
    }

    /// How the controller reaches the dictation it serves. Set once by ContentView.
    struct Hooks {
        /// A dictation that may send is recording now (dictation mode, normal output route).
        var isDictating: () -> Bool
        /// The app being dictated into, for the indicator only. The stop target decides the send.
        var recordingApp: () -> (bundleIdentifier: String?, name: String?)?
        /// A hold-to-talk shortcut is held down: letting go ends the dictation, so the pause
        /// countdown stays off (it could cut off speech while the key is still held).
        var isHoldingShortcut: () -> Bool = { false }
        /// Stops the recording and processes it, exactly as the stop hotkey does.
        var stopAndProcess: () -> Void
    }

    var configuration: () -> Configuration = { Configuration.current() }
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var settleDuration: TimeInterval = SpokenSendParser.immediateStopSettleDuration

    private var hooks: Hooks?
    private var audioLevels: AnyPublisher<CGFloat, Never>?
    private var partialsSubscription: AnyCancellable?
    private var recordingSubscription: AnyCancellable?

    /// A recording is capturing now (the ASR's own running state, not the indicator).
    private(set) var isRecordingLive = false
    /// A stop has begun (`beginStop`) and the send is not decided yet (`finishDictation`, `endStop`).
    private(set) var isAwaitingSendDecision = false
    private var voiceActivitySubscription: AnyCancellable?
    private let typingService = TypingService()

    /// Bumped by every recording; a countdown from an earlier one can never stop a later one.
    private(set) var session: UInt64 = 0
    private var arming = SpokenSendArmingState()
    private var lastPartial = ""
    private var isCanceled = false
    private var autoStopTriggered = false
    private var countdownTask: Task<Void, Never>?
    private var countdownStartedAt: TimeInterval?
    private var lastVoiceActivityAt: TimeInterval = 0

    init() {}

    /// - Parameter recording: the ASR's running state. A recording that ends without the stop
    ///   pipeline (a cancel, a microphone dropout, Reprocess or a History pick while listening)
    ///   then leaves no send armed.
    func attach(
        partials: AnyPublisher<String, Never>,
        audioLevels: AnyPublisher<CGFloat, Never>,
        recording: AnyPublisher<Bool, Never>? = nil,
        hooks: Hooks
    ) {
        self.hooks = hooks
        self.audioLevels = audioLevels
        self.partialsSubscription = partials
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.handlePartial(text)
            }
        self.recordingSubscription = recording?
            .removeDuplicates()
            .sink { [weak self] isRunning in
                self?.recordingStateChanged(isRunning: isRunning)
            }
    }

    // MARK: - Is a Return pending?

    /// Whether a Return is genuinely pending: the phrase armed a send that is not canceled, in an
    /// app that gets one, and either the recording is live or its stop has begun and the send is
    /// not decided yet. The one input to "should Esc drop only the Return?" besides the pill
    /// visibly showing SEND (BottomOverlayWindowController.cancelSpokenSendIfArmed).
    var hasPendingReturn: Bool {
        (self.isRecordingLive || self.isAwaitingSendDecision)
            && (self.indicator == .armed || self.indicator == .countingDown)
            && self.sendsInRecordingApp
    }

    /// The ASR's running state changed. Ended outside the stop pipeline: nothing is pending.
    func recordingStateChanged(isRunning: Bool) {
        self.isRecordingLive = isRunning
        guard !isRunning, !self.isAwaitingSendDecision else { return }
        self.cancelCountdown()
        self.setIndicator(.hidden)
    }

    /// The mode left dictation (a command or edit switch mid-recording): no send applies.
    func leftDictationMode() {
        self.cancelCountdown()
        self.arming.reset()
        self.setIndicator(.hidden)
    }

    // MARK: - During a recording

    /// A new recording starts (any mode). Forgets everything about the previous one.
    func beginRecording() {
        self.session &+= 1
        self.isAwaitingSendDecision = false
        self.cancelCountdown()
        self.arming.reset()
        self.lastPartial = ""
        self.isCanceled = false
        self.autoStopTriggered = false
        self.lastVoiceActivityAt = self.now()
        self.setIndicator(.hidden)
        self.setSendsInRecordingApp(true)
    }

    func handlePartial(_ text: String) {
        let config = self.configuration()
        guard config.enabled, let hooks else { return }
        let isEligible = hooks.isDictating() && !self.autoStopTriggered
        // An ineligible partial (the stop's own) never disarms, so the final parse still knows.
        let isArmed = self.arming.update(partial: text, isEligible: isEligible, phrase: config.phrase)
        guard isEligible else { return }
        self.lastPartial = text
        if let app = hooks.recordingApp() {
            let verdict = SpokenSendPolicy.verdict(bundleIdentifier: app.bundleIdentifier, appName: app.name, allowsC11: config.allowsC11)
            self.setSendsInRecordingApp(verdict.allowsSend)
        }

        guard !self.isCanceled else { return }
        guard isArmed else {
            self.cancelCountdown()
            self.setIndicator(.hidden)
            return
        }
        guard config.stopsAfterPause, !hooks.isHoldingShortcut() else {
            self.setIndicator(.armed)
            return
        }
        // One countdown across harmless re-decodes of the same words (punctuation, casing).
        guard self.countdownTask == nil else { return }
        self.startCountdown()
    }

    /// Cancels the send for the rest of this dictation. The phrase is still left out of the text;
    /// only the key is dropped. Returns false when there was nothing to cancel (the send was
    /// already decided, canceled, or never armed).
    @discardableResult
    func cancelSend() -> Bool {
        guard self.indicator == .armed || self.indicator == .countingDown else { return false }
        self.isCanceled = true
        self.cancelCountdown()
        self.setIndicator(.canceled)
        DebugLogger.shared.info("SPOKEN_SEND canceled from overlay session=\(self.session)", source: "SpokenSend")
        return true
    }

    private func startCountdown() {
        let session = self.session
        self.countdownID &+= 1
        let countdownID = self.countdownID
        let startedAt = self.now()
        self.countdownStartedAt = startedAt
        self.lastVoiceActivityAt = startedAt
        self.startVoiceActivityMonitoring()
        self.setIndicator(.countingDown)
        let settle = self.settleDuration
        DebugLogger.shared.info("SPOKEN_SEND countdown_start session=\(session) settleMs=\(Int(settle * 1000))", source: "SpokenSend")
        self.countdownTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(settle, 0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.completeCountdown(session: session, countdownID: countdownID)
        }
    }

    private func completeCountdown(session: UInt64, countdownID: UInt64) {
        // A newer recording or countdown owns the state now.
        guard session == self.session, countdownID == self.countdownID else { return }
        self.countdownTask = nil
        self.countdownStartedAt = nil
        self.stopVoiceActivityMonitoring()
        let config = self.configuration()
        let quietDuration = self.now() - self.lastVoiceActivityAt
        guard let hooks,
              hooks.isDictating(),
              !self.isCanceled,
              !self.autoStopTriggered,
              SpokenSendParser.canCompleteImmediateStop(
                  self.lastPartial,
                  phrase: config.phrase,
                  spokenSendEnabled: config.enabled,
                  sendImmediatelyEnabled: config.stopsAfterPause,
                  quietDuration: quietDuration,
                  armedText: self.arming.armedText
              )
        else {
            if self.indicator == .countingDown {
                self.setIndicator(self.arming.wasArmed && !self.isCanceled ? .armed : .hidden)
            }
            DebugLogger.shared.info(
                "SPOKEN_SEND countdown_expired session=\(session) quietMs=\(Int(quietDuration * 1000)) stopped=false",
                source: "SpokenSend"
            )
            return
        }
        self.autoStopTriggered = true
        self.setIndicator(.armed)
        DebugLogger.shared.info("SPOKEN_SEND countdown_complete session=\(session) quietMs=\(Int(quietDuration * 1000)) stopping=true", source: "SpokenSend")
        hooks.stopAndProcess()
    }

    /// Speech after the grace period means the speaker went on: the countdown stops. The next
    /// partial decides whether the phrase still ends what was said.
    func handleVoiceLevel(_ level: CGFloat) {
        guard SpokenSendParser.isMeaningfulVoiceActivity(level) else { return }
        let activityAt = self.now()
        self.lastVoiceActivityAt = activityAt
        guard let startedAt = self.countdownStartedAt,
              self.countdownTask != nil,
              SpokenSendParser.shouldCancelCountdownForVoiceActivity(countdownStartedAt: startedAt, voiceActivityAt: activityAt)
        else { return }
        self.cancelCountdown()
        self.setIndicator(.armed)
        DebugLogger.shared.debug("SPOKEN_SEND countdown_canceled reason=voice_activity session=\(self.session)", source: "SpokenSend")
    }

    private func cancelCountdown() {
        self.countdownTask?.cancel()
        self.countdownTask = nil
        self.countdownStartedAt = nil
        self.stopVoiceActivityMonitoring()
    }

    private func startVoiceActivityMonitoring() {
        guard self.voiceActivitySubscription == nil, let audioLevels else { return }
        self.voiceActivitySubscription = audioLevels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.handleVoiceLevel(level)
            }
    }

    private func stopVoiceActivityMonitoring() {
        self.voiceActivitySubscription?.cancel()
        self.voiceActivitySubscription = nil
    }

    private func setIndicator(_ indicator: Indicator) {
        guard self.indicator != indicator else { return }
        self.indicator = indicator
    }

    private func setSendsInRecordingApp(_ sends: Bool) {
        guard self.sendsInRecordingApp != sends else { return }
        self.sendsInRecordingApp = sends
    }

    // MARK: - At stop

    /// This dictation's Spoken Send state as it stops, so a recording that starts while it still
    /// transcribes (which resets the controller) cannot change its outcome.
    struct StopSnapshot: Equatable {
        let session: UInt64
        /// When dictation stopped (system uptime): input after it drops the key.
        let stoppedAt: TimeInterval
        let wasArmed: Bool
        let isCanceled: Bool
        let autoStopped: Bool
        /// The recording app is a terminal (c11 included). Only used when no stop target was
        /// captured; the stop target decides otherwise.
        let recordingAppIsTerminal: Bool
    }

    /// Called as dictation stops, before anything awaits. Ends the countdown; a stop that is
    /// already under way needs no second one.
    func beginStop() -> StopSnapshot {
        self.isAwaitingSendDecision = true
        self.cancelCountdown()
        if self.indicator == .countingDown {
            self.setIndicator(.armed)
        }
        let app = self.hooks?.recordingApp()
        return StopSnapshot(
            session: self.session,
            stoppedAt: self.now(),
            wasArmed: self.arming.wasArmed,
            isCanceled: self.isCanceled,
            autoStopped: self.autoStopTriggered,
            recordingAppIsTerminal: app.map { SpokenSendPolicy.isTerminal(bundleIdentifier: $0.bundleIdentifier, appName: $0.name) } ?? false
        )
    }

    /// Called on every way out of the stop path (an empty transcript, a rewrite or command
    /// recording, a delivered one): the chip never outlives the dictation it belongs to.
    func endStop(_ stop: StopSnapshot) {
        guard stop.session == self.session else { return }
        self.isAwaitingSendDecision = false
        self.cancelCountdown()
        self.setIndicator(.hidden)
    }

    /// Strips a send phrase that ends `text` and says whether a key follows. `target` is the
    /// destination chosen at stop: for a terminal (c11 included) no sentence ending is added.
    /// `isNormalRoute` is false for the onboarding sandbox, which never sends.
    func finishDictation(_ text: String, stop: StopSnapshot, target: DictationTarget?, isNormalRoute: Bool) -> SpokenSendDecision {
        let config = self.configuration()
        let inTerminal = target.map {
            SpokenSendPolicy.isTerminal(
                bundleIdentifier: $0.bundleIdentifier,
                appName: NSRunningApplication(processIdentifier: $0.pid)?.localizedName
            )
        } ?? stop.recordingAppIsTerminal
        // Still this dictation's state: a cancel clicked while it transcribed counts too.
        let isCurrent = stop.session == self.session
        let wasArmed = isCurrent ? self.arming.wasArmed : stop.wasArmed
        let isCanceled = isCurrent ? self.isCanceled : stop.isCanceled
        if isCurrent {
            self.isAwaitingSendDecision = false
            self.setIndicator(.hidden)
        }
        guard config.enabled, isNormalRoute else { return .unchanged(text) }
        let parse = SpokenSendParser.parseArmed(
            text,
            phrase: config.phrase,
            enabled: true,
            wasArmed: wasArmed,
            forTerminal: inTerminal
        )
        let decision = SpokenSendDecision(
            text: parse.text,
            phraseDetected: parse.shouldSend,
            shouldSend: parse.shouldSend && !isCanceled
        )
        DebugLogger.shared.info(
            "SPOKEN_SEND decision session=\(stop.session) current=\(isCurrent) phrase=\(decision.phraseDetected) send=\(decision.shouldSend) " +
                "canceled=\(isCanceled) armed=\(wasArmed) autoStopped=\(stop.autoStopped) terminal=\(inTerminal) phraseOnly=\(decision.isPhraseOnly)",
            source: "SpokenSend"
        )
        return decision
    }

    /// The key to press after this dictation's text, or nil. Never when AI cleanup failed (the
    /// raw fallback is not what the user meant to submit), never without a destination chosen at
    /// stop, and never in a blocked terminal.
    /// `stoppedAt`: when dictation stopped; a key press or click after it drops the key.
    func sendKeyRequest(for decision: SpokenSendDecision, target: DictationTarget?, aiFailed: Bool, stoppedAt: TimeInterval) -> SendKeyRequest? {
        guard decision.shouldSend else { return nil }
        let config = self.configuration()
        guard !aiFailed else {
            DebugLogger.shared.info("SPOKEN_SEND skipped reason=ai_fallback", source: "SpokenSend")
            return nil
        }
        guard let target, target.pid > 0, target.pid != ProcessInfo.processInfo.processIdentifier else {
            DebugLogger.shared.info("SPOKEN_SEND skipped reason=no_stop_target", source: "SpokenSend")
            return nil
        }
        let appName = NSRunningApplication(processIdentifier: target.pid)?.localizedName
        let verdict = SpokenSendPolicy.verdict(bundleIdentifier: target.bundleIdentifier, appName: appName, allowsC11: config.allowsC11)
        let key = SpokenSendPolicy.effectiveKey(config.key, verdict: verdict)
        DebugLogger.shared.info(
            "SPOKEN_SEND target app=\(target.bundleIdentifier ?? "pid\(target.pid)") verdict=\(verdict.rawValue) key=\(key.rawValue)",
            source: "SpokenSend"
        )
        guard verdict.allowsSend else { return nil }
        return SendKeyRequest(key: key, target: target, stoppedAt: stoppedAt)
    }

    /// Delivers the text, then the key, through the typing worker (queued behind any delivery
    /// still in flight). A failed delivery shows the failure card and presses nothing.
    /// - Parameter stopTrace: the dictation's stop-path trace; the typing worker marks the paste
    ///   and the send key on it.
    func deliver(
        _ plan: DictationLiteralOutputPlan,
        sendKey: SendKeyRequest,
        textReadyAt: TimeInterval,
        transcriptInHistory: Bool,
        stopTrace: StopPathTrace? = nil
    ) {
        self.typingService.typeOutputPlanInstantly(
            plan,
            preferredTargetPID: sendKey.target.pid,
            textReadyAt: textReadyAt,
            transcriptInHistory: transcriptInHistory,
            sendKey: sendKey,
            onSendKey: { outcome in
                DebugLogger.shared.info("SPOKEN_SEND outcome=\(outcome.rawValue) phraseOnly=false", source: "SpokenSend")
            },
            stopTrace: stopTrace
        )
    }

    /// The dictation was only the phrase: press the key on what the target already holds.
    func sendExistingDraft(_ sendKey: SendKeyRequest) {
        self.typingService.pressSendKey(sendKey) { outcome in
            DebugLogger.shared.info("SPOKEN_SEND outcome=\(outcome.rawValue) phraseOnly=true", source: "SpokenSend")
        }
    }
}
