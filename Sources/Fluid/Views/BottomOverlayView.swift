//
//  BottomOverlayView.swift
//  Fluid
//
//  Bottom overlay for transcription (alternative to notch overlay)
//

import AppKit
import Combine
import QuartzCore
import SwiftUI

enum RecordingOverlayHideOutcome: Equatable {
    case hidden
    case superseded
}

private final class BottomOverlayPanel: NSPanel {
    var allowsOffscreenParking = false

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        self.allowsOffscreenParking ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

// MARK: - Bottom Overlay Window Controller

@MainActor
final class BottomOverlayWindowController {
    static let shared = BottomOverlayWindowController()

    private var window: NSPanel?
    /// Level ticks feed the Signal trace's sampler directly: no view is invalidated per tick.
    private var audioSubscription: AnyCancellable?
    private var spokenSendSubscription: AnyCancellable?
    /// The dictation whose delivery the overlay waits for after its stop (the delivered hold).
    private var pendingDelivery: PendingDelivery?
    private var deliveryWork: DispatchWorkItem?
    private var sendCancelHold: DispatchWorkItem?
    /// The next hide is a cut, not the 120 ms fade (a recovery card takes the overlay's place).
    private var nextHideIsCut = false
    private var pendingResizeWorkItem: DispatchWorkItem?
    private var pendingReleaseTransitionResetWorkItem: DispatchWorkItem?
    private var localMouseDownMonitor: Any?
    private var globalMouseDownMonitor: Any?
    private var targetScreen: NSScreen?
    private var releaseTransitionActiveUntil: Date?
    private var deferredResizePending = false
    private var presentationGeneration: UInt64 = 0
    private var isHideInProgress = false
    private var activeHideGeneration: UInt64?
    private var hideWaiters: [CheckedContinuation<RecordingOverlayHideOutcome, Never>] = []

    /// Whether the panel's content paints any non-transparent pixel right now. For tests.
    func contentPaintsPixelsForTests() -> Bool {
        guard let view = self.window?.contentView, view.bounds.width > 0, view.bounds.height > 0 else { return false }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                return true
            }
        }
        return false
    }

    /// The panel's alpha, and whether it sits outside every display. For tests.
    var windowStateForTests: (alpha: CGFloat, isParkedOffscreen: Bool, ignoresMouse: Bool)? {
        guard let window else { return nil }
        let onAnyScreen = NSScreen.screens.contains { $0.frame.intersects(window.frame) }
        return (window.alphaValue, !onAnyScreen && !NSScreen.screens.isEmpty, window.ignoresMouseEvents)
    }

    private init() {
        self.spokenSendSubscription = SpokenSendController.shared.$indicator
            .removeDuplicates()
            .sink { [weak self] indicator in
                Task { @MainActor [weak self] in self?.spokenSendIndicatorChanged(indicator) }
            }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("OverlayOffsetChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Adjusting the settings offset is an explicit "position it for me" —
                // it supersedes any position the user dragged the overlay to.
                self?.clearSavedDragPosition()
                self?.positionWindow()
            }
        }
        NotificationCenter.default.addObserver(forName: NSNotification.Name("OverlaySizeChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleSizeAndPositionUpdate(after: 0)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.targetScreen = OverlayScreenResolver.screenForCurrentPointer()
                if NotchContentState.shared.isBottomOverlayPresented {
                    self.positionWindow()
                } else {
                    self.parkWindowOffscreen()
                }
            }
        }
    }

    /// Pay the one-time SwiftUI/WindowServer surface cost after launch and keep
    /// the static panel outside the entire desktop so its surface is not evicted.
    func prepare() {
        guard self.window == nil else { return }
        self.createWindow()
        self.targetScreen = OverlayScreenResolver.screenForCurrentPointer()
        guard let window else { return }

        self.parkWindowOffscreen()
        window.alphaValue = 1
        window.orderFrontRegardless()
        CATransaction.flush()
        Self.overlayBench("bottom_prepared")
    }

    func show(audioPublisher: AnyPublisher<CGFloat, Never>, mode: OverlayMode) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        Self.overlayBench("bottom_show_start mode=\(mode.rawValue) windowExists=\(self.window != nil)")
        self.cancelInFlightHideForNewPresentation()
        self.presentationGeneration &+= 1

        self.endReleaseTransition(flushDeferredUpdate: false)
        self.pendingResizeWorkItem?.cancel()
        self.pendingResizeWorkItem = nil
        BottomOverlayHistoryMenuController.shared.hide()
        self.ensureMouseDownMonitors()

        // Create window if needed
        if self.window == nil {
            self.createWindow()
        }

        // Prepare the complete first frame while the cached panel is still
        // offscreen. Revealing the neutral shell first causes a visible flash
        // that reads as the overlay appearing twice.
        NotchContentState.shared.setBottomOverlayPresented(true)
        NotchContentState.shared.mode = mode
        switch mode {
        case .dictation: NotchContentState.shared.promptPickerMode = .dictate
        case .edit, .write, .rewrite: NotchContentState.shared.promptPickerMode = .edit
        case .command: break
        }
        NotchContentState.shared.updateTranscription("")
        NotchContentState.shared.setBottomOverlayDismissing(false)
        self.cancelDeliveryHold()
        self.nextHideIsCut = false
        let model = SignalOverlayModel.shared
        model.ensureTraceBars(SignalOverlayGeometry.forSize(SettingsStore.shared.overlaySize).traceBars)
        // No Core Audio lookup on the start path: the last name (capture corrects it once resolved).
        model.microphoneName = Self.cachedMicrophoneName(current: model.microphoneName)
        model.beginRecording(noiseThreshold: CGFloat(SettingsStore.shared.visualizerNoiseThreshold))

        self.targetScreen = OverlayScreenResolver.screenForCurrentPointer()
        self.positionWindow()

        // Submit one complete frame to WindowServer.
        self.window?.setAccessibilityChildren(nil)
        self.window?.setAccessibilityElement(true)
        self.window?.alphaValue = 1
        self.window?.orderFrontRegardless()
        self.window?.contentView?.displayIfNeeded()
        self.window?.displayIfNeeded()
        CATransaction.flush()
        Self.overlayBench("bottom_order_front elapsedMs=\(Self.elapsedMs(since: startedAt))")
        Self.overlayBench("bottom_visible elapsedMs=\(Self.elapsedMs(since: startedAt))")

        self.audioSubscription?.cancel()
        self.audioSubscription = audioPublisher
            .receive(on: DispatchQueue.main)
            .sink { level in
                SignalOverlayModel.shared.trace.ingest(level: level, at: Date().timeIntervalSinceReferenceDate)
            }
    }

    func hide() {
        guard !self.isHideInProgress else { return }
        self.isHideInProgress = true
        self.presentationGeneration &+= 1
        let currentGeneration = self.presentationGeneration
        self.activeHideGeneration = currentGeneration
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.performHideAndWait(generation: currentGeneration)
            self.completeHideOperation(generation: currentGeneration, outcome: outcome)
        }
    }

    /// Returns whether the panel finished hiding or a newer presentation
    /// superseded this request.
    func hideAndWait() async -> RecordingOverlayHideOutcome {
        if self.isHideInProgress {
            return await withCheckedContinuation { continuation in
                self.hideWaiters.append(continuation)
            }
        }

        self.isHideInProgress = true
        self.presentationGeneration &+= 1
        let currentGeneration = self.presentationGeneration
        self.activeHideGeneration = currentGeneration
        let outcome = await self.performHideAndWait(generation: currentGeneration)
        self.completeHideOperation(generation: currentGeneration, outcome: outcome)
        return outcome
    }

    private func completeHideOperation(generation: UInt64, outcome: RecordingOverlayHideOutcome) {
        guard self.activeHideGeneration == generation else { return }
        self.activeHideGeneration = nil
        self.isHideInProgress = false
        let waiters = self.hideWaiters
        self.hideWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume(returning: outcome) }
    }

    private func cancelInFlightHideForNewPresentation() {
        guard self.isHideInProgress else { return }
        self.activeHideGeneration = nil
        self.isHideInProgress = false
        let waiters = self.hideWaiters
        self.hideWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume(returning: .superseded) }
        Self.overlayBench("bottom_hide_cancelled_for_new_presentation")
    }

    private func performHideAndWait(generation currentGeneration: UInt64) async -> RecordingOverlayHideOutcome {
        let startedAt = ProcessInfo.processInfo.systemUptime
        Self.overlayBench("bottom_hide_start windowExists=\(self.window != nil)")
        guard self.presentationGeneration == currentGeneration else {
            Self.overlayBench("bottom_hide_return reason=stale_generation")
            return .superseded
        }

        guard let window = self.window, NotchContentState.shared.isBottomOverlayPresented else {
            self.clearPresentationResources()
            self.endReleaseTransition(flushDeferredUpdate: false)
            NotchContentState.shared.setBottomOverlayDismissing(false)
            NotchContentState.shared.targetAppIcon = nil
            Self.overlayBench("bottom_hide_return reason=no_window")
            return .hidden
        }

        // Freeze the trace the moment the hide begins: no level tick may reach it again
        // (from altic-dev/FluidVoice@fcb54e49).
        self.audioSubscription?.cancel()
        self.audioSubscription = nil
        self.pendingResizeWorkItem?.cancel()
        self.pendingResizeWorkItem = nil
        self.cancelDeliveryHold()

        // Dismiss (DESIGN.md §8): opacity 1 -> 0 over 120 ms, linear, no scale, no drop. A cut when
        // a recovery card takes the overlay's place, and under reduced motion. The overlay is inert
        // from here on (isBottomOverlayDismissing).
        let isCut = self.nextHideIsCut || SignalTheme.Motion.isReduced
        self.nextHideIsCut = false
        NotchContentState.shared.setBottomOverlayReleaseTransitioning(true)
        NotchContentState.shared.setBottomOverlayDismissing(true)
        if !isCut {
            SignalOverlayModel.shared.beginFading()
        }

        Self.overlayBench("bottom_hide_animation_start cut=\(isCut)")
        await Task.yield()
        guard self.presentationGeneration == currentGeneration else {
            Self.overlayBench("bottom_hide_return reason=stale_generation")
            return .superseded
        }
        self.clearPresentationResources()

        if !isCut {
            try? await Task.sleep(nanoseconds: UInt64(SignalTheme.Motion.dismiss * 1_000_000_000))
        }

        guard self.presentationGeneration == currentGeneration else {
            Self.overlayBench("bottom_hide_return reason=stale_generation")
            return .superseded
        }

        // Hide by alpha first: a plain WindowServer property, no window-management transaction.
        // Parking the panel offscreen (setFrameOrigin) blocks the main thread on a WindowServer
        // fence, 70-300 ms on a busy host, so it waits until no stop pipeline is running
        // (StopPipelineWindowWork). Parking, not ignoresMouseEvents: setting that even once makes
        // the panel's transparent margin around the pill take clicks for good. Until it is parked
        // the overlay's controls do nothing (BottomOverlayView.isInteractive). (Adapted from
        // altic-dev/FluidVoice@094b8d0e, @6f929124 and @fe05d7cb.)
        window.alphaValue = 0
        window.setAccessibilityChildren([])
        window.setAccessibilityElement(false)
        self.scheduleParkingAfterHandoff(generation: currentGeneration)
        NotchContentState.shared.setBottomOverlayPresented(false)
        SignalOverlayModel.shared.reset()
        self.endReleaseTransition(flushDeferredUpdate: false)
        NotchContentState.shared.setBottomOverlayDismissing(false)
        if NotchContentState.shared.targetAppIcon != nil {
            NotchContentState.shared.targetAppIcon = nil
        }
        Self.overlayBench("bottom_hide_complete elapsedMs=\(Self.elapsedMs(since: startedAt))")
        return .hidden
    }

    private func clearPresentationResources() {
        self.audioSubscription?.cancel()
        self.audioSubscription = nil
        self.pendingResizeWorkItem?.cancel()
        self.pendingResizeWorkItem = nil
        self.pendingReleaseTransitionResetWorkItem?.cancel()
        self.targetScreen = nil
        self.removeMouseDownMonitors()
        BottomOverlayHistoryMenuController.shared.hide()
        // Publish only real changes: each one re-renders the overlay.
        if NotchContentState.shared.isProcessing {
            NotchContentState.shared.setProcessing(false)
        }
    }

    /// Parks the hidden panel offscreen after a long idle, never while a stop pipeline runs, and
    /// not at all if a newer presentation showed it meanwhile. Hidden already takes no clicks (alpha
    /// 0 and nothing painted), so parking is only the backstop, and its WindowServer fence
    /// (70-300 ms) must not land where the next dictation starts: with the 1.2 s hold that is about
    /// 1.3-1.7 s after the paste, so it waits `idleParkingDelay` after the hide.
    private func scheduleParkingAfterHandoff(generation: UInt64) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleParkingDelay) { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            StopPipelineWindowWork.afterHandoff { [weak self] in
                guard let self,
                      self.presentationGeneration == generation,
                      !NotchContentState.shared.isBottomOverlayPresented
                else { return }
                self.parkWindowOffscreen()
                Self.overlayBench("bottom_parked")
            }
        }
    }

    /// How long a hidden overlay waits before it is parked offscreen. Tests shorten it.
    static var idleParkingDelay: TimeInterval = 8

    func setProcessing(_ processing: Bool) {
        Self.overlayBench("bottom_set_processing processing=\(processing)")
        NotchContentState.shared.setProcessing(processing)
        // Transcribing shows only once the final pass is slow (the caller defers it 250 ms).
        if processing, NotchContentState.shared.isBottomOverlayPresented {
            SignalOverlayModel.shared.beginTranscribing()
        }
    }

    // MARK: - Signal: stop, delivered hold, cards, Spoken Send

    /// The stopped dictation the overlay is holding, until the hold ends.
    private struct PendingDelivery {
        let traceID: Int
        let appName: String?
        let words: Int
        let generation: UInt64
        /// A failure was reported: a recovery card will take the overlay's place.
        var awaitsCard: Bool
        /// Pasted / Sent is on screen (a late Paste Check miss can still replace it with its card).
        var outcomeShown = false
    }

    /// The recording stopped and the overlay stays for its outcome: the trace goes flat (60 ms),
    /// the square hollow, the timer and preview freeze. Level ticks stop reaching the overlay.
    func markRecordingStopped() {
        guard NotchContentState.shared.isBottomOverlayPresented,
              !NotchContentState.shared.isBottomOverlayDismissing
        else { return }
        self.audioSubscription?.cancel()
        self.audioSubscription = nil
        self.sendCancelHold?.cancel()
        self.sendCancelHold = nil
        let model = SignalOverlayModel.shared
        let spokenSend = SpokenSendController.shared
        var placard = SignalPlacard.none
        if SettingsStore.shared.spokenSendEnabled, NotchContentState.shared.mode == .dictation {
            placard = model.sendDrain?.isCanceled == true
                ? .noSend
                : SignalOverlayModel.placard(indicator: spokenSend.indicator, sendsInApp: spokenSend.sendsInRecordingApp)
        }
        model.stopRecording(preview: Self.previewAtStop(), placard: placard)
        Self.overlayBench("bottom_recording_stopped placard=\(placard)")
    }

    /// The dictation's text was handed to the typing service: hold the overlay for its outcome.
    /// `failureReported`: the stop path already reported a failure (a card is coming).
    func awaitDelivery(traceID: Int, appName: String?, words: Int, failureReported: Bool) {
        guard NotchContentState.shared.isBottomOverlayPresented,
              !NotchContentState.shared.isBottomOverlayDismissing
        else { return }
        self.cancelDeliveryHold()
        self.pendingDelivery = PendingDelivery(
            traceID: traceID,
            appName: appName,
            words: words,
            generation: self.presentationGeneration,
            awaitsCard: failureReported
        )
        // The outcome normally arrives in well under a second; never hold on without one.
        self.scheduleHoldEnd(after: failureReported ? Self.cardWait : Self.outcomeWait, reason: "no_outcome")
        Self.overlayBench("bottom_await_delivery trace=\(traceID) failureReported=\(failureReported)")
    }

    /// The typing worker finished a dictation's delivery. Posted: the outcome state for 1.2 s,
    /// then dismiss. Failed: wait for the recovery card, which takes the overlay's place.
    func dictationDeliveryFinished(_ outcome: DictationDeliveryOutcome) {
        guard var pending = self.pendingDelivery,
              pending.traceID == outcome.traceID,
              pending.generation == self.presentationGeneration,
              !pending.outcomeShown
        else { return }
        switch outcome.result {
        case .dispatched:
            pending.outcomeShown = true
            self.pendingDelivery = pending
            SignalOverlayModel.shared.showDelivered(SignalDelivery(
                appName: pending.appName,
                words: pending.words,
                method: outcome.method?.signalMethod ?? .paste,
                sentReturn: outcome.sentReturn
            ))
            self.scheduleHoldEnd(after: Self.deliveredHold, reason: "delivered")
            DebugLogger.shared.info(
                "OVERLAY_OUTCOME trace=\(outcome.traceID) shown=\(outcome.sentReturn ? "sent" : "pasted") method=\(outcome.method?.rawValue ?? "none")",
                source: "BottomOverlay"
            )
        case let .recoverableFailure(failure):
            guard failure.isUserVisible else {
                self.endDeliveryHold(reason: "not_delivered")
                return
            }
            pending.awaitsCard = true
            self.pendingDelivery = pending
            self.scheduleHoldEnd(after: Self.cardWait, reason: "no_card")
        }
    }

    /// A delivery-failure card is about to show for the dictation traced `traceID`. If the overlay
    /// is holding that dictation (waiting for its outcome, or already showing Pasted when a late
    /// Paste Check miss arrives), it gives way at once (a cut), so the card reads as the pill
    /// growing upward. Anything else stays: a live recording, or another dictation's hold; the card
    /// then sits above it. Returns whether the overlay gave way.
    @discardableResult
    func yieldToCard(forDictation traceID: Int?) -> Bool {
        guard let traceID,
              NotchContentState.shared.isBottomOverlayPresented,
              !NotchContentState.shared.isBottomOverlayDismissing,
              SignalOverlayModel.shared.isPostStop,
              let pending = self.pendingDelivery,
              pending.traceID == traceID,
              pending.generation == self.presentationGeneration
        else { return false }
        return self.giveWayToCard()
    }

    /// A notice card (transcription timed out, recognition recovering or back, microphone off) is
    /// about to show. The overlay gives way when it holds a stopped dictation (its final pass timed
    /// out), or, for `refusedStart`, when it was shown for a start that was then refused. A live or
    /// starting recording always stays.
    @discardableResult
    func yieldToNoticeCard(refusedStart: Bool = false) -> Bool {
        guard NotchContentState.shared.isBottomOverlayPresented,
              !NotchContentState.shared.isBottomOverlayDismissing
        else { return false }
        let model = SignalOverlayModel.shared
        let heldAfterStop = model.isPostStop
        let refusedBeforeCapture = refusedStart && model.phase == .listening && !AppServices.shared.asr.isRunningOrStarting
        guard heldAfterStop || refusedBeforeCapture else { return false }
        return self.giveWayToCard()
    }

    private func giveWayToCard() -> Bool {
        self.cancelDeliveryHold()
        self.nextHideIsCut = true
        DebugLogger.shared.info("OVERLAY_OUTCOME shown=card", source: "BottomOverlay")
        Self.overlayBench("bottom_yield_to_card")
        self.hideThroughOwner()
        return true
    }

    /// Esc, the Cancel chip or a click on the pill while SEND shows: drop only the Return
    /// (DESIGN.md §15), and say NO SEND. Returns false when no Return was pending, so the caller
    /// goes on to cancel the dictation.
    @discardableResult
    func cancelSpokenSendIfArmed() -> Bool {
        let spokenSend = SpokenSendController.shared
        guard spokenSend.cancelsReturnFirst, spokenSend.cancelSend() else { return false }
        SignalOverlayModel.shared.markSendCanceled()
        return true
    }

    /// The app the held dictation traced `traceID` was pasted into, for its card's headline; nil
    /// for any other dictation, so a card never borrows another dictation's app.
    func heldDictationAppName(forDictation traceID: Int?) -> String? {
        guard let traceID,
              let pending = self.pendingDelivery,
              pending.traceID == traceID,
              pending.generation == self.presentationGeneration
        else { return nil }
        return pending.appName
    }

    /// How long the outcome stays (DESIGN.md §8: 1.2 s). Tests shorten it.
    static var deliveredHold: TimeInterval = SignalTheme.Motion.deliveredHold

    private static let outcomeWait: TimeInterval = 5
    private static let cardWait: TimeInterval = 1.5

    private func scheduleHoldEnd(after delay: TimeInterval, reason: String) {
        self.deliveryWork?.cancel()
        let generation = self.presentationGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            self.endDeliveryHold(reason: reason)
        }
        self.deliveryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func endDeliveryHold(reason: String) {
        self.cancelDeliveryHold()
        guard NotchContentState.shared.isBottomOverlayPresented,
              !NotchContentState.shared.isBottomOverlayDismissing,
              SignalOverlayModel.shared.isPostStop
        else { return }
        if reason != "delivered" {
            // The overlay held a stopped dictation but no outcome or card came: logged so a
            // silent path shows up (the text itself was handed to the typing service).
            DebugLogger.shared.info("OVERLAY_OUTCOME shown=none reason=\(reason)", source: "BottomOverlay")
        }
        Self.overlayBench("bottom_hold_end reason=\(reason)")
        self.hideThroughOwner()
    }

    /// Hides through NotchOverlayManager when it presented the overlay (its bookkeeping follows),
    /// else directly.
    private func hideThroughOwner() {
        if NotchOverlayManager.shared.isBottomOverlayVisible {
            NotchOverlayManager.shared.hide()
        } else {
            self.hide()
        }
    }

    private func cancelDeliveryHold() {
        self.deliveryWork?.cancel()
        self.deliveryWork = nil
        self.pendingDelivery = nil
    }

    /// Spoken Send's quiet countdown (DESIGN.md §15): the drain bar and the 1.5 -> 0.0 readout while
    /// it runs; a cancel stops the bar in ink and holds NO SEND 700 ms. The microphone is still
    /// open then, so the row returns to the live trace (the controller keeps recording).
    private func spokenSendIndicatorChanged(_ indicator: SpokenSendController.Indicator) {
        let model = SignalOverlayModel.shared
        guard NotchContentState.shared.isBottomOverlayPresented, model.phase == .listening else {
            model.clearSendCountdown()
            return
        }
        switch indicator {
        case .countingDown:
            guard SpokenSendController.shared.sendsInRecordingApp else {
                model.clearSendCountdown()
                return
            }
            self.sendCancelHold?.cancel()
            model.startSendCountdown(duration: SpokenSendController.shared.settleDuration)
        case .canceled:
            guard model.sendDrain?.isRunning == true else {
                model.clearSendCountdown()
                return
            }
            model.freezeSendCountdown()
            let generation = self.presentationGeneration
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.presentationGeneration == generation else { return }
                SignalOverlayModel.shared.clearSendCountdown()
            }
            self.sendCancelHold = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.sendCancelHoldDuration, execute: work)
        case .armed, .hidden:
            // A completed countdown turns back to armed just before its stop: keep the empty bar
            // briefly so the trace never flickers before the stop flattens the row. If no stop
            // follows (the countdown expired without one), the live row comes back.
            if let drain = model.sendDrain, !drain.isCanceled, drain.remaining(at: Date()) <= 0.05 {
                let generation = self.presentationGeneration
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self, self.presentationGeneration == generation,
                          SignalOverlayModel.shared.phase == .listening
                    else { return }
                    SignalOverlayModel.shared.clearSendCountdown()
                }
                return
            }
            model.clearSendCountdown()
        }
    }

    private static let sendCancelHoldDuration: TimeInterval = 0.7

    /// The live preview as it stood when the recording stopped, without the stop path's status words.
    private static func previewAtStop() -> String {
        let text = NotchContentState.shared.cachedPreviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        return SignalOverlayModel.statusWords.contains(text) ? "" : text
    }

    /// The microphone name without touching Core Audio (for the start path).
    static func cachedMicrophoneName(current: String) -> String {
        if let name = AppServices.shared.microphonePreferenceCoordinator.lastResolvedMicrophoneName, !name.isEmpty {
            return name
        }
        if !current.isEmpty { return current }
        return SettingsStore.shared.microphonePriority.first?.name ?? ""
    }

    /// The microphone to name in the mic row: the one capture resolved last, else the first in the
    /// priority list, else the system default input.
    static func currentMicrophoneName() -> String {
        if let name = AppServices.shared.microphonePreferenceCoordinator.lastResolvedMicrophoneName, !name.isEmpty {
            return name
        }
        if let name = SettingsStore.shared.microphonePriority.first?.name, !name.isEmpty {
            return name
        }
        return AudioDevice.getDefaultInputDevice()?.name ?? ""
    }

    func refreshSizeForContent() {
        self.scheduleSizeAndPositionUpdate()
    }

    func beginReleaseTransition(duration: TimeInterval = 0.28) {
        let now = Date()
        let deadline = now.addingTimeInterval(max(duration, 0.12))
        if let existingDeadline = self.releaseTransitionActiveUntil, existingDeadline > deadline {
            self.releaseTransitionActiveUntil = existingDeadline
        } else {
            self.releaseTransitionActiveUntil = deadline
        }

        self.pendingReleaseTransitionResetWorkItem?.cancel()

        guard let activeDeadline = self.releaseTransitionActiveUntil else { return }
        let resetWorkItem = DispatchWorkItem { [weak self] in
            self?.endReleaseTransition()
        }
        self.pendingReleaseTransitionResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(activeDeadline.timeIntervalSince(now), 0), execute: resetWorkItem)

        self.audioSubscription?.cancel()
        self.audioSubscription = nil
        NotchContentState.shared.setBottomOverlayReleaseTransitioning(true)
    }

    func endReleaseTransition(flushDeferredUpdate: Bool = true) {
        self.pendingReleaseTransitionResetWorkItem?.cancel()
        self.pendingReleaseTransitionResetWorkItem = nil
        self.releaseTransitionActiveUntil = nil
        NotchContentState.shared.setBottomOverlayReleaseTransitioning(false)

        let shouldFlush = flushDeferredUpdate && self.deferredResizePending
        self.deferredResizePending = false

        if shouldFlush, self.window?.isVisible == true {
            self.scheduleSizeAndPositionUpdate(after: 0)
        }
    }

    private static func overlayBench(_ message: String) {
        DebugLogger.shared.benchmark("OVERLAY_BENCH", message: message, source: "OverlayBenchmark")
    }

    private static func elapsedMs(since start: TimeInterval) -> Int {
        Int(((ProcessInfo.processInfo.systemUptime - start) * 1000).rounded())
    }

    private func scheduleSizeAndPositionUpdate(after delay: TimeInterval = 0.08) {
        if self.isReleaseTransitionActive {
            self.deferredResizePending = true
            return
        }

        self.pendingResizeWorkItem?.cancel()

        // Debounce rapid streaming updates to avoid resize thrash.
        let resizeWorkItem = DispatchWorkItem { [weak self] in
            self?.updateSizeAndPosition()
        }
        self.pendingResizeWorkItem = resizeWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: resizeWorkItem)
    }

    /// Update window size based on current SwiftUI content and re-position
    private func updateSizeAndPosition() {
        if self.isReleaseTransitionActive {
            self.deferredResizePending = true
            return
        }

        guard let window = window, let hostingView = window.contentView as? NSHostingView<BottomOverlayView> else { return }

        // Re-calculate fitting size for the new layout constants
        let newSize = hostingView.fittingSize

        // Avoid redundant content-size updates while AppKit is already resolving constraints.
        // Re-applying the same size can trigger unnecessary update-constraints churn.
        let currentSize = window.contentView?.frame.size ?? window.frame.size
        let widthChanged = abs(currentSize.width - newSize.width) > 0.5
        let heightChanged = abs(currentSize.height - newSize.height) > 0.5

        if widthChanged || heightChanged {
            // Resize from the current origin to avoid AppKit's default top-left anchoring,
            // which can visually push the overlay down before we re-position it.
            let currentOrigin = window.frame.origin
            let resizedFrame = NSRect(origin: currentOrigin, size: newSize)
            window.setFrame(resizedFrame, display: false)
        }

        // Re-position
        self.positionWindow()
    }

    private func createWindow() {
        let panel = BottomOverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // SwiftUI handles shadow
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let contentView = BottomOverlayView()
        let hostingView = BottomOverlayHostingView(rootView: contentView)

        // Let SwiftUI determine the size
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)

        // Make hosting view fully transparent
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.setContentSize(fittingSize)
        panel.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        hostingView.display()

        self.window = panel
    }

    private var isReleaseTransitionActive: Bool {
        guard let deadline = self.releaseTransitionActiveUntil else { return false }
        if deadline > Date() {
            return true
        }

        self.releaseTransitionActiveUntil = nil
        return false
    }

    private func ensureMouseDownMonitors() {
        if self.localMouseDownMonitor == nil {
            self.localMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                let clickPoint: NSPoint
                if let window = event.window {
                    clickPoint = window.convertPoint(toScreen: event.locationInWindow)
                } else {
                    clickPoint = NSEvent.mouseLocation
                }

                Task { @MainActor [weak self] in
                    self?.dismissMenusForClick(screenPoint: clickPoint)
                }
                return event
            }
        }

        if self.globalMouseDownMonitor == nil, !TestHostQuietMode.isActive {
            self.globalMouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                let clickPoint = NSEvent.mouseLocation
                Task { @MainActor [weak self] in
                    self?.dismissMenusForClick(screenPoint: clickPoint)
                }
            }
        }
    }

    private func removeMouseDownMonitors() {
        if let monitor = self.localMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            self.localMouseDownMonitor = nil
        }
        if let monitor = self.globalMouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            self.globalMouseDownMonitor = nil
        }
    }

    @MainActor
    private func dismissMenusForClick(screenPoint: NSPoint) {
        guard self.window?.isVisible == true else { return }
        BottomOverlayHistoryMenuController.shared.dismissIfNeeded(for: screenPoint)
    }

    private func positionWindow() {
        // Safe check for window and screen availability
        guard let window = window else { return }
        guard NotchContentState.shared.isBottomOverlayPresented else {
            self.parkWindowOffscreen()
            return
        }
        (window as? BottomOverlayPanel)?.allowsOffscreenParking = false

        let screen = self.targetScreen ?? window.screen ?? OverlayScreenResolver.screenForCurrentPointer()
        guard let screen = screen else { return }

        // Apply position directly to avoid implicit frame animations during hover-driven resizes.
        window.setFrameOrigin(Self.anchoredOrigin(for: window.frame.size, on: screen))
    }

    /// Where a window of `size` sits when anchored like the overlay: the user's dragged spot
    /// (center-x, bottom edge) or the default bottom-center offset, clamped into the visible
    /// frame. The recovery card uses it so it appears where the overlay was. `contentInset` is the
    /// transparent margin the window keeps around its content for the selection brackets; the
    /// anchor applies to the content's bottom edge, so the pill sits 50 pt above the visible bottom.
    static func anchoredOrigin(
        for windowSize: NSSize,
        on screen: NSScreen,
        contentInset: CGFloat = SignalTheme.Metrics.windowInsets.bottom
    ) -> NSPoint {
        let fullFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        let x: CGFloat
        var y: CGFloat
        if let saved = self.savedDragPositionFractions {
            // A user-dragged position, stored as fractions of the screen so it lands in the
            // same relative spot on whichever display dictation happens on — and can never
            // restore off-screen when a remembered display goes away or shrinks.
            x = fullFrame.minX + fullFrame.width * saved.x - windowSize.width / 2
            y = fullFrame.minY + fullFrame.height * saved.y
        } else {
            // Default: horizontally centered, settings offset above the bottom.
            x = fullFrame.midX - windowSize.width / 2
            y = visibleFrame.minY + CGFloat(SettingsStore.shared.overlayBottomOffset)
        }

        // Safety Clamping:
        // 1. Min: Ensure it's at least visibleFrame.minY (not below the dock/visible area)
        // 2. Max: Ensure it doesn't cross the top of the visible frame minus its own height
        let minY = visibleFrame.minY + 10 // Small buffer from absolute bottom
        let maxY = visibleFrame.maxY - windowSize.height - 40 // Buffer from top

        y = max(min(y, maxY), minY) - contentInset
        let clampedX = max(min(x, visibleFrame.maxX - windowSize.width), visibleFrame.minX)
        return NSPoint(x: clampedX, y: y)
    }

    // MARK: - User-dragged position

    /// The overlay's dragged position as fractions of the host screen's frame:
    /// `x` is the window's center-x, `y` the window's bottom edge. Fractional storage keeps
    /// the anchor meaningful across displays of different sizes; `positionWindow` clamps the
    /// result into the visible frame, so a vanished display falls back safely on-screen.
    private static var savedDragPositionFractions: (x: CGFloat, y: CGFloat)? {
        let defaults = UserDefaults.standard
        guard let x = defaults.object(forKey: Self.dragPositionXFractionKey) as? Double,
              let y = defaults.object(forKey: Self.dragPositionYFractionKey) as? Double
        else { return nil }
        return (CGFloat(x), CGFloat(y))
    }

    private static let dragPositionXFractionKey = "OverlayDraggedPositionXFraction"
    private static let dragPositionYFractionKey = "OverlayDraggedPositionYFraction"

    /// The live window origin, exposed for the view's drag gesture.
    var frameOriginForDrag: NSPoint? {
        self.window?.frame.origin
    }

    /// The overlay's on-screen frame while it is presented, else nil. Lets another panel
    /// (the delivery failure card) sit clear of it.
    var presentedFrame: NSRect? {
        guard NotchContentState.shared.isBottomOverlayPresented, let window = self.window, window.isVisible else {
            return nil
        }
        return window.frame
    }

    /// Follows the pointer during a drag. Free-form on purpose: clamping happens on
    /// release (`commitDraggedPosition`), so the drag itself never fights the hand.
    func dragWindow(to origin: NSPoint) {
        guard NotchContentState.shared.isBottomOverlayPresented else { return }
        self.window?.setFrameOrigin(origin)
    }

    /// Persists where a drag left the overlay, then re-runs positioning so the
    /// committed (clamped, fraction-quantized) spot is also the one on screen.
    func commitDraggedPosition() {
        guard let window = self.window, NotchContentState.shared.isBottomOverlayPresented else { return }
        let screen = window.screen ?? self.targetScreen ?? OverlayScreenResolver.screenForCurrentPointer()
        guard let screen, screen.frame.width > 0, screen.frame.height > 0 else { return }

        self.targetScreen = screen
        let frame = window.frame
        let xFraction = (frame.midX - screen.frame.minX) / screen.frame.width
        // The content's bottom edge, not the window's: the window keeps a transparent margin.
        let yFraction = (frame.minY + SignalTheme.Metrics.windowInsets.bottom - screen.frame.minY) / screen.frame.height
        let defaults = UserDefaults.standard
        defaults.set(Double(min(max(xFraction, 0), 1)), forKey: Self.dragPositionXFractionKey)
        defaults.set(Double(min(max(yFraction, 0), 1)), forKey: Self.dragPositionYFractionKey)
        self.positionWindow()
    }

    private func clearSavedDragPosition() {
        UserDefaults.standard.removeObject(forKey: Self.dragPositionXFractionKey)
        UserDefaults.standard.removeObject(forKey: Self.dragPositionYFractionKey)
    }

    /// Double-click: forget the dragged position and return to the default anchor.
    func resetDraggedPositionToDefault() {
        self.clearSavedDragPosition()
        self.positionWindow()
    }

    private func parkWindowOffscreen() {
        guard let window else { return }
        window.setAccessibilityChildren([])
        window.setAccessibilityElement(false)
        (window as? BottomOverlayPanel)?.allowsOffscreenParking = true
        let desktopFrame = NSScreen.screens.reduce(NSRect.null) { partial, screen in
            partial.union(screen.frame)
        }
        let edge = desktopFrame.isNull ? NSPoint(x: 100_000, y: 100_000) : NSPoint(
            x: desktopFrame.maxX + window.frame.width + 1024,
            y: desktopFrame.maxY + window.frame.height + 1024
        )
        window.setFrameOrigin(edge)
    }
}

final class BottomOverlayHistoryMenuController: ObservableObject {
    static let shared = BottomOverlayHistoryMenuController()

    /// Open: the History chip stays inverted (latched).
    @Published private(set) var isOpen = false
    /// The pointer is over the card: only the card's bracket draws.
    @Published var isHovered = false

    private var menuWindow: NSPanel?
    private var hostingView: NSHostingView<BottomOverlayHistoryMenuView>?
    private var selectorFrameInScreen: CGRect = .zero
    private weak var parentWindow: NSWindow?
    private var menuMaxWidth: CGFloat = 480
    private var menuGap: CGFloat = 6
    private var pendingPositionWorkItem: DispatchWorkItem?

    private init() {}

    func updateAnchor(selectorFrameInScreen: CGRect, parentWindow: NSWindow?, maxWidth: CGFloat, menuGap: CGFloat) {
        guard selectorFrameInScreen.width > 0, selectorFrameInScreen.height > 0 else { return }

        let resolvedMaxWidth = max(maxWidth, 280)
        let widthChanged = abs(self.menuMaxWidth - resolvedMaxWidth) > 0.5

        self.selectorFrameInScreen = selectorFrameInScreen
        self.parentWindow = parentWindow
        self.menuMaxWidth = resolvedMaxWidth
        self.menuGap = max(menuGap, 0)

        if self.menuWindow?.isVisible == true {
            if widthChanged {
                self.updateMenuContent()
            }
            self.attachToParentWindowIfNeeded()
            self.scheduleMenuPositionUpdate()
        }
    }

    func toggleFromTap() {
        if self.menuWindow?.isVisible == true {
            self.hide()
            return
        }
        self.showMenuIfPossible()
    }

    func hide() {
        self.pendingPositionWorkItem?.cancel()
        self.pendingPositionWorkItem = nil

        if let menuWindow = self.menuWindow, let parent = menuWindow.parent {
            parent.removeChildWindow(menuWindow)
        }
        self.menuWindow?.orderOut(nil)
        if self.isOpen { self.isOpen = false }
        if self.isHovered { self.isHovered = false }
    }

    func dismissIfNeeded(for screenPoint: NSPoint) {
        guard self.menuWindow?.isVisible == true else { return }
        let insideMenu = self.menuWindow?.frame.contains(screenPoint) ?? false
        let insideSelector = self.selectorFrameInScreen.contains(screenPoint)
        if !insideMenu, !insideSelector {
            self.hide()
        }
    }

    private func scheduleMenuPositionUpdate() {
        guard self.pendingPositionWorkItem == nil else { return }

        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingPositionWorkItem = nil
            self.updateMenuSizeAndPosition()
        }

        self.pendingPositionWorkItem = task
        DispatchQueue.main.async(execute: task)
    }

    private func showMenuIfPossible() {
        guard self.selectorFrameInScreen.width > 0, self.selectorFrameInScreen.height > 0 else { return }

        self.createWindowIfNeeded()
        self.updateMenuContent()
        self.attachToParentWindowIfNeeded()
        self.updateMenuSizeAndPosition()
        self.menuWindow?.orderFrontRegardless()
        self.isOpen = true
    }

    private func createWindowIfNeeded() {
        guard self.menuWindow == nil else { return }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // No window shadow (DESIGN.md §6): the card's own 1 px edge and flat 2 pt drop rule
        // separate it from the pill.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none

        let hostingView = NSHostingView(rootView: self.makeMenuContent())
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        panel.setContentSize(fittingSize)
        panel.contentView = hostingView

        self.hostingView = hostingView
        self.menuWindow = panel
    }

    private func makeMenuContent() -> BottomOverlayHistoryMenuView {
        BottomOverlayHistoryMenuView(
            maxWidth: self.menuMaxWidth,
            onDismissRequested: { [weak self] in
                self?.hide()
            }
        )
    }

    private func updateMenuContent() {
        self.hostingView?.rootView = self.makeMenuContent()
    }

    private func attachToParentWindowIfNeeded() {
        guard let menuWindow = self.menuWindow else { return }

        if let currentParent = menuWindow.parent, currentParent !== self.parentWindow {
            currentParent.removeChildWindow(menuWindow)
        }

        if let parentWindow = self.parentWindow, menuWindow.parent !== parentWindow {
            parentWindow.addChildWindow(menuWindow, ordered: .above)
        }
    }

    private func updateMenuSizeAndPosition() {
        guard let menuWindow = self.menuWindow, let hostingView = self.hostingView else { return }
        guard self.selectorFrameInScreen.width > 0, self.selectorFrameInScreen.height > 0 else { return }

        let fittingSize = hostingView.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else { return }

        // Anchored to the history chip's leading edge, `menuGap` (6 pt) above it (DESIGN.md §4).
        // The panel keeps a transparent bracket margin around the card.
        let insets = SignalTheme.Metrics.windowInsets
        let preferredX = self.selectorFrameInScreen.minX - insets.leading
        let preferredY = self.selectorFrameInScreen.maxY + self.menuGap - insets.bottom

        let screen = self.parentWindow?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: self.selectorFrameInScreen.midX, y: self.selectorFrameInScreen.midY)) })
            ?? NSScreen.main

        var targetX = preferredX
        var targetY = preferredY

        if let screen {
            let visible = screen.visibleFrame
            let horizontalInset: CGFloat = 8
            let verticalInset: CGFloat = 8

            if fittingSize.width < visible.width - (horizontalInset * 2) {
                targetX = max(visible.minX + horizontalInset, min(preferredX, visible.maxX - fittingSize.width - horizontalInset))
            } else {
                targetX = visible.minX + horizontalInset
            }

            if fittingSize.height < visible.height - (verticalInset * 2) {
                targetY = max(visible.minY + verticalInset, min(preferredY, visible.maxY - fittingSize.height - verticalInset))
            } else {
                targetY = visible.minY + verticalInset
            }
        }

        let targetFrame = NSRect(x: targetX, y: targetY, width: fittingSize.width, height: fittingSize.height)
        let currentFrame = menuWindow.frame
        let frameTolerance: CGFloat = 0.5
        let isSameFrame =
            abs(currentFrame.origin.x - targetFrame.origin.x) <= frameTolerance &&
            abs(currentFrame.origin.y - targetFrame.origin.y) <= frameTolerance &&
            abs(currentFrame.size.width - targetFrame.size.width) <= frameTolerance &&
            abs(currentFrame.size.height - targetFrame.size.height) <= frameTolerance

        if !isSameFrame {
            menuWindow.setFrame(targetFrame, display: false)
        }
    }
}

/// The history browser: the Signal history card (the newest 12, newest first). Clicking an entry
/// re-inserts its text into the dictation target app. Padded by the bracket margin.
private struct BottomOverlayHistoryMenuView: View {
    @ObservedObject private var historyStore = TranscriptionHistoryStore.shared

    let maxWidth: CGFloat
    let onDismissRequested: () -> Void

    private static let maxEntriesShown = 12

    var body: some View {
        SignalHistoryCard(
            entries: Array(self.historyStore.entries.prefix(Self.maxEntriesShown)),
            totalCount: self.historyStore.entries.count,
            notPasted: DeliveryFailureOverlayController.shared.notPastedTranscripts,
            onPick: { entry in
                NotchContentState.shared.onHistoryEntryPasteRequested?(entry)
                self.restoreTypingTargetApp()
                self.onDismissRequested()
            },
            onHoverChanged: { hovering in
                BottomOverlayHistoryMenuController.shared.isHovered = hovering
            }
        )
        .padding(SignalTheme.Metrics.windowInsets)
        .signalPalette()
    }

    private func restoreTypingTargetApp() {
        let pid = NotchContentState.shared.recordingTargetPID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let pid { _ = TypingService.activateApp(pid: pid) }
        }
    }
}

struct PromptSelectorAnchorReader: NSViewRepresentable {
    let onFrameChange: (CGRect, NSWindow?) -> Void

    func makeNSView(context: Context) -> AnchorReportingView {
        let view = AnchorReportingView()
        view.onFrameChange = self.onFrameChange
        return view
    }

    func updateNSView(_ nsView: AnchorReportingView, context: Context) {
        nsView.onFrameChange = self.onFrameChange
        nsView.reportFrame(force: true)
    }

    final class AnchorReportingView: NSView {
        var onFrameChange: ((CGRect, NSWindow?) -> Void)?
        private var windowObservers: [NSObjectProtocol] = []
        private var lastReportedFrameInScreen: CGRect = .null
        private weak var lastReportedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            self.installWindowObservers()
            self.reportFrame(force: true)
        }

        override func layout() {
            super.layout()
            self.reportFrame()
        }

        deinit {
            self.cleanup()
        }

        func cleanup() {
            for observer in self.windowObservers {
                NotificationCenter.default.removeObserver(observer)
            }
            self.windowObservers.removeAll()
        }

        private func installWindowObservers() {
            self.cleanup()
            guard let window = self.window else { return }

            let center = NotificationCenter.default
            self.windowObservers.append(
                center.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                    self?.reportFrame()
                }
            )
            self.windowObservers.append(
                center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                    self?.reportFrame()
                }
            )
            self.windowObservers.append(
                center.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                    self?.reportFrame()
                }
            )
        }

        func reportFrame(force: Bool = false) {
            guard let window = self.window else {
                if force || !self.lastReportedFrameInScreen.isNull {
                    self.lastReportedFrameInScreen = .null
                    self.lastReportedWindow = nil
                    self.onFrameChange?(CGRect.zero, nil)
                }
                return
            }

            let frameInWindow = self.convert(self.bounds, to: nil)
            let frameInScreen = window.convertToScreen(frameInWindow)
            let frameTolerance: CGFloat = 0.5
            let hasLastFrame = !self.lastReportedFrameInScreen.isNull
            let frameChanged = !hasLastFrame ||
                abs(frameInScreen.origin.x - self.lastReportedFrameInScreen.origin.x) > frameTolerance ||
                abs(frameInScreen.origin.y - self.lastReportedFrameInScreen.origin.y) > frameTolerance ||
                abs(frameInScreen.size.width - self.lastReportedFrameInScreen.size.width) > frameTolerance ||
                abs(frameInScreen.size.height - self.lastReportedFrameInScreen.size.height) > frameTolerance
            let windowChanged = self.lastReportedWindow !== window

            guard force || frameChanged || windowChanged else { return }

            self.lastReportedFrameInScreen = frameInScreen
            self.lastReportedWindow = window
            self.onFrameChange?(frameInScreen, window)
        }
    }
}

/// The recording overlay's hosting view. Signal draws no blurred shadow, so no margin needs to
/// be carved out of hit-testing: a click on a transparent pixel passes to the app beneath.
private final class BottomOverlayHostingView: NSHostingView<BottomOverlayView> {}
