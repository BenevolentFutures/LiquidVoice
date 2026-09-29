import AppKit
import SwiftUI

// Recovery cards (DESIGN.md §9.5, §15). Behavior ported from altic-dev/FluidVoice by altic-dev:
//   @d5cc5090 friendlier wording, @ff92b4b8 shorter title, @8a820022 one Copy action and a
//   10 s auto-dismiss, @088efe13 its own transient panel instead of an overlay state, and
//   @9c25e758 a card for every failure, with Open Settings for Accessibility.
// The look is Signal's recovery-card family: the pill grown upward from where the overlay sits
// (a dragged position included), with the orange 2 pt top rule, a headline, one reason line, the
// transcript for a failed paste, one orange primary action, Dismiss and mono meta, between the
// overlay's own rails. Its trace row, mic row, rails and chips sit exactly where the overlay's do.

@MainActor
final class DeliveryFailureOverlayController {
    static let shared = DeliveryFailureOverlayController()

    static let displayDuration: TimeInterval = 10
    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    static let microphoneSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")

    private var panel: NSPanel?
    private var hostingView: NSHostingView<DeliveryFailureCardView>?
    private var dismissTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    /// Set once Copy or Dismiss is chosen, so leaving the card cannot postpone the close.
    private var isClosing = false

    /// What the card currently shows. Read by tests and the debug triggers.
    private(set) var presentedFailure: TextDeliveryFailure?
    private(set) var presentedTranscript: String?
    private(set) var presentedTimeout: TranscriptionTimeoutNotice?
    private(set) var presentedMicrophoneAccessNeeded = false
    /// Transcripts whose paste failed this session, for the history card's NOT PASTED marker.
    private(set) var notPastedTranscripts: Set<String> = []

    private init() {}

    var isVisible: Bool {
        self.panel?.isVisible == true
    }

    func show(_ report: DeliveryFailureReport) {
        let failure = report.failure
        let transcript = report.transcript
        guard failure.isUserVisible else { return }
        let reason = Self.reasonText(failure: failure, clipboard: report.clipboard, inHistory: report.inHistory)
        let appName = BottomOverlayWindowController.shared.heldDictationAppName(forDictation: report.traceID)
        let isAccessibility = failure == .accessibilityNotTrusted
        let words = SignalOverlayModel.wordCount(transcript)
        let content = SignalCardContent(
            headline: isAccessibility
                ? "Accessibility is off"
                : appName.map { "Couldn\u{2019}t paste into \($0)" } ?? "Couldn\u{2019}t paste the text",
            reason: reason,
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            // Without Accessibility nothing can paste: the way out is the setting (the text is
            // already on the clipboard). Otherwise, Copy.
            primary: isAccessibility ? .openSystemSettings : .copy,
            meta: "\(words) \(words == 1 ? "word" : "words")"
        )
        self.present(content, yieldOverlay: {
            BottomOverlayWindowController.shared.yieldToCard(forDictation: report.traceID)
        }) { [weak self] in
            if isAccessibility {
                if let url = Self.accessibilitySettingsURL { NSWorkspace.shared.open(url) }
                self?.hide()
            } else {
                ClipboardService.copyToClipboard(transcript)
                // Close once the "✓ Copied" confirmation has shown.
                self?.hide(after: SignalTheme.Motion.copyFeedbackButton)
            }
        }
        self.presentedFailure = failure
        self.presentedTranscript = transcript
        if self.notPastedTranscripts.count > 200 { self.notPastedTranscripts.removeAll() }
        self.notPastedTranscripts.insert(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        DebugLogger.shared.info("Delivery failure card shown failure=\(failure.rawValue) chars=\(transcript.count)", source: "DeliveryFailureCard")
    }

    /// A dictation whose transcription timed out (its audio is kept), a recovered model, or a
    /// recording refused while the model recovers. Reprocess is the primary action.
    func showTranscriptionTimeout(_ notice: TranscriptionTimeoutNotice) {
        let content: SignalCardContent = switch notice {
        case .timedOut:
            SignalCardContent(headline: "Transcription timed out", reason: "Your audio is kept", primary: .reprocess)
        case .recovered:
            SignalCardContent(headline: "Speech recognition is back", reason: "A kept dictation is waiting", primary: .reprocess)
        case let .recordingRefused(hasKeptAudio):
            SignalCardContent(
                headline: "Speech recognition is recovering",
                reason: hasKeptAudio ? "This recording didn\u{2019}t start. Your earlier audio is kept" : "This recording didn\u{2019}t start. Try again in a moment",
                primary: hasKeptAudio ? .reprocess : .none
            )
        case .reprocessUnavailable:
            SignalCardContent(headline: "Speech recognition is recovering", reason: "Your audio is kept. Reprocess again in a moment", primary: .reprocess)
        }
        let refusedStart: Bool = if case .recordingRefused = notice { true } else { false }
        self.present(content, yieldOverlay: {
            BottomOverlayWindowController.shared.yieldToNoticeCard(refusedStart: refusedStart)
        }) { [weak self] in
            // Reprocess: the same path as the overlay's Reprocess chip and hotkey.
            NotchContentState.shared.onReprocessLastRequested?()
            self?.hide()
        }
        self.presentedTimeout = notice
        DebugLogger.shared.info("Transcription timeout card shown notice=\(notice)", source: "DeliveryFailureCard")
    }

    /// A dictation hotkey pressed while macOS denies the microphone: recording cannot start, so
    /// say so where the overlay would have appeared, with a way to the Microphone settings.
    func showMicrophoneAccessNeeded() {
        let content = SignalCardContent(
            headline: "Microphone access is off",
            reason: "Allow \(Bundle.main.fluidAppDisplayName) in Privacy & Security",
            primary: .openSystemSettings,
            isMicrophoneOff: true
        )
        self.present(content, yieldOverlay: { BottomOverlayWindowController.shared.yieldToNoticeCard() }) { [weak self] in
            if let url = Self.microphoneSettingsURL { NSWorkspace.shared.open(url) }
            self?.hide()
        }
        self.presentedMicrophoneAccessNeeded = true
        DebugLogger.shared.info("Microphone access card shown", source: "DeliveryFailureCard")
    }

    /// `yieldOverlay`: asks the overlay to give way (a cut) when the card is about the dictation it
    /// is holding, so the card reads as the pill growing upward; otherwise the card sits above it.
    private func present(_ content: SignalCardContent, yieldOverlay: () -> Bool, primary: @escaping () -> Void) {
        let overlayYielded = yieldOverlay()
        let model = SignalOverlayModel.shared
        let view = DeliveryFailureCardView(
            content: content,
            icon: NotchContentState.shared.targetAppIcon ?? ActiveAppMonitor.shared.activeAppIcon,
            timerText: model.lastRecording.map { SignalOverlayModel.formatDuration($0.duration) } ?? "0:00",
            microphoneName: BottomOverlayWindowController.cachedMicrophoneName(current: SignalOverlayModel.shared.microphoneName),
            onPrimary: primary,
            onDismiss: { [weak self] in self?.hide() },
            onHoverChanged: { [weak self] hovering in self?.hoverChanged(hovering) }
        )
        self.present(view, avoidingOverlay: !overlayYielded)
    }

    private func present(_ rootView: DeliveryFailureCardView, avoidingOverlay: Bool) {
        self.generation &+= 1
        self.dismissTask?.cancel()
        self.isClosing = false
        self.presentedFailure = nil
        self.presentedTranscript = nil
        self.presentedTimeout = nil
        self.presentedMicrophoneAccessNeeded = false
        // A fresh hosting view per card: the view's own state (Copied, hover) must never carry
        // over from the previous card.
        if self.panel == nil {
            self.createPanel()
        }
        guard let panel = self.panel else { return }
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView
        self.hostingView = hostingView
        // A card replacing one that was fading out starts opaque: a zero-length animation group
        // supersedes the fade still running on the animator.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        self.positionPanel(avoidingOverlay: avoidingOverlay)
        panel.orderFrontRegardless()
        self.scheduleDismiss(after: Self.displayDuration)
    }

    func hide(after delay: TimeInterval = 0) {
        self.isClosing = true
        self.dismissTask?.cancel()
        self.dismissTask = nil
        guard delay > 0 else {
            self.performHide()
            return
        }
        let expectedGeneration = self.generation
        self.dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.generation == expectedGeneration else { return }
            self.performHide()
        }
    }

    private func performHide() {
        self.generation &+= 1
        // A history card opened from this card's History chip goes with it.
        BottomOverlayHistoryMenuController.shared.hide()
        self.presentedFailure = nil
        self.presentedTranscript = nil
        self.presentedTimeout = nil
        self.presentedMicrophoneAccessNeeded = false
        guard let panel = self.panel, panel.isVisible, !SignalTheme.Motion.isReduced else {
            self.panel?.orderOut(nil)
            return
        }
        // Dismiss like the overlay: 120 ms linear to transparent, then out of the window list
        // (a cut under reduced motion). A card presented meanwhile keeps the panel.
        let generation = self.generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SignalTheme.Motion.dismiss
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    private func hoverChanged(_ hovering: Bool) {
        // Never vanish under the pointer; resume a short countdown once it leaves.
        guard !self.isClosing else { return }
        if hovering {
            self.dismissTask?.cancel()
            self.dismissTask = nil
        } else if self.isVisible {
            self.scheduleDismiss(after: 4)
        }
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        self.dismissTask?.cancel()
        let expectedGeneration = self.generation
        self.dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, self.generation == expectedGeneration else { return }
            self.performHide()
        }
    }

    /// The failed card's reason line (DESIGN.md §15): why nothing was pasted, or where the text
    /// is now. Never claims History for text that is not in it, and a newer copy of the user's is
    /// never replaced.
    static func reasonText(failure: TextDeliveryFailure, clipboard: TranscriptBackupOutcome, inHistory: Bool) -> String {
        if failure == .noEditableTarget { return "No text field focused" }
        switch clipboard {
        case .copied, .alreadyOnClipboard:
            return "The text is on your clipboard"
        case .newerClipboardCopy:
            return inHistory ? "Your newer clipboard was left alone, the text is in History" : "Your newer clipboard was left alone. Use Copy"
        case .writeFailed:
            return inHistory ? "The clipboard couldn\u{2019}t be written, the text is in History" : "The clipboard couldn\u{2019}t be written. Use Copy"
        case .emptyText:
            return "Nothing was captured"
        }
    }

    private func createPanel() {
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
        panel.hasShadow = false // Flat: the pill's 1 px edge and 2 pt drop rule, as in the overlay.
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = false
        self.panel = panel
    }

    private func positionPanel(avoidingOverlay: Bool) {
        guard let panel, let hostingView,
              let screen = OverlayScreenResolver.screenForCurrentPointer() ?? NSScreen.main
        else { return }
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let size = NSSize(width: ceil(fittingSize.width), height: ceil(fittingSize.height))
        guard size.width > 0, size.height > 0 else { return }
        hostingView.frame = NSRect(origin: .zero, size: size)

        let visibleFrame = screen.visibleFrame
        var origin: NSPoint
        if SettingsStore.shared.overlayPosition == .bottom {
            origin = BottomOverlayWindowController.anchoredOrigin(for: size, on: screen)
        } else {
            origin = NSPoint(x: screen.frame.midX - size.width / 2, y: visibleFrame.maxY - size.height - 12)
        }
        // Never cover a live recording overlay: sit just above it instead.
        if avoidingOverlay, let overlayFrame = BottomOverlayWindowController.shared.presentedFrame,
           overlayFrame.intersects(NSRect(origin: origin, size: size))
        {
            origin.y = min(overlayFrame.maxY + 8, visibleFrame.maxY - size.height - 12)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// The recovery card: the overlay's rails, and its pill grown upward by the card. The trace row
/// (flat, the frozen length), the mic row, the rails and the chips sit exactly where the overlay's
/// were, so the card reads as the same object; only the top moves.
struct DeliveryFailureCardView: View {
    let content: SignalCardContent
    let icon: NSImage?
    /// The dictation's frozen length ("0:41"); the microphone card shows a dim "0:00".
    let timerText: String
    let microphoneName: String
    let onPrimary: () -> Void
    let onDismiss: () -> Void
    let onHoverChanged: (Bool) -> Void

    @ObservedObject private var historyStore = TranscriptionHistoryStore.shared
    @ObservedObject private var historyCard = BottomOverlayHistoryMenuController.shared
    @State private var isHovered = false
    @State private var hoveredChips: Set<String> = []
    @State private var isCopyConfirming = false
    @State private var historyChipAnchor = SignalChipAnchor()
    @State private var trace = SignalTraceModel()

    private var geometry: SignalOverlayGeometry {
        SignalOverlayGeometry.forSize(SettingsStore.shared.overlaySize)
    }

    private var hasHistory: Bool {
        !self.historyStore.entries.isEmpty
    }

    var body: some View {
        let geometry = self.geometry
        let cardHeight = self.content.height(width: geometry.innerWidth)
        HStack(alignment: .bottom, spacing: SignalTheme.Metrics.railGap) {
            SignalRail(height: geometry.railHeight) {
                self.chip("history", "clock.arrow.circlepath", self.hasHistory ? "Recent Dictations" : "No saved dictation history available", enabled: self.hasHistory, latched: self.historyCard.isOpen) {
                    // The history card clears the grown pill: 6 pt above it, not above the chip.
                    let growth = self.pillHeight(geometry, cardHeight) - geometry.railHeight
                    BottomOverlayHistoryMenuController.shared.updateAnchor(
                        selectorFrameInScreen: self.historyChipAnchor.frameInScreen,
                        parentWindow: self.historyChipAnchor.window,
                        maxWidth: SignalTheme.Metrics.historyWidth,
                        menuGap: SignalTheme.Metrics.historyGapAboveChip + max(0, growth)
                    )
                    BottomOverlayHistoryMenuController.shared.toggleFromTap()
                }
                .background(
                    PromptSelectorAnchorReader { [historyChipAnchor] frame, window in
                        historyChipAnchor.frameInScreen = frame
                        historyChipAnchor.window = window
                    }
                    .allowsHitTesting(false)
                )
            } middle: {
                Color.clear
            } bottom: {
                self.chip("copy", "doc.on.doc", "Copy Last Transcription", enabled: self.hasHistory, confirming: self.isCopyConfirming) {
                    NotchContentState.shared.onCopyLastRequested?()
                    self.isCopyConfirming = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + SignalTheme.Motion.copyFeedbackChip) {
                        self.isCopyConfirming = false
                    }
                }
            }

            SignalPill(
                geometry: geometry,
                topHeight: cardHeight,
                traceRow: SignalTraceRow(
                    geometry: geometry,
                    icon: self.icon,
                    trace: self.trace,
                    isLive: false,
                    isSweeping: false,
                    mark: self.content.isMicrophoneOff ? .closed : .none,
                    timer: .frozen(self.content.isMicrophoneOff ? "0:00" : self.timerText, dim: self.content.isMicrophoneOff)
                ),
                micText: self.content.isMicrophoneOff ? "No microphone" : (self.microphoneName.isEmpty ? "Microphone" : self.microphoneName),
                micEmphasized: self.content.isMicrophoneOff,
                marksFailure: true,
                isBracketVisible: self.isHovered && self.hoveredChips.isEmpty && !self.historyCard.isHovered
            ) {
                SignalCardBody(
                    content: self.content,
                    width: geometry.innerWidth,
                    onPrimary: self.onPrimary,
                    onDismiss: self.onDismiss
                )
            }

            SignalRail(height: geometry.railHeight) {
                self.chip("cancel", "xmark", "Dismiss", enabled: true, action: self.onDismiss)
            } middle: {
                Color.clear
            } bottom: {
                self.chip("reprocess", "arrow.clockwise", "Reprocess Last Dictation", enabled: self.hasHistory) {
                    NotchContentState.shared.onReprocessLastRequested?()
                    self.onDismiss()
                }
            }
        }
        .onHover { hovering in
            self.isHovered = hovering
            self.onHoverChanged(hovering)
        }
        .padding(SignalTheme.Metrics.windowInsets)
        .signalPalette()
        .onAppear {
            if self.trace.barCount != geometry.traceBars {
                self.trace = SignalTraceModel(barCount: geometry.traceBars)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(self.content.headline)
    }

    private func pillHeight(_ geometry: SignalOverlayGeometry, _ cardHeight: CGFloat) -> CGFloat {
        let metrics = SignalTheme.Metrics.self
        return metrics.pillPaddingTop + cardHeight + metrics.previewGap + metrics.traceRowHeight + metrics.micGap
            + metrics.micRowHeight + metrics.pillPaddingBottom
    }

    private func chip(
        _ id: String,
        _ systemName: String,
        _ help: String,
        enabled: Bool,
        latched: Bool = false,
        confirming: Bool = false,
        action: @escaping () -> Void
    ) -> SignalChip {
        SignalChip(
            systemName: systemName,
            help: help,
            isEnabled: enabled,
            isLatched: latched,
            isConfirming: confirming,
            onHoverChanged: { hovering in
                if hovering { self.hoveredChips.insert(id) } else { self.hoveredChips.remove(id) }
            },
            action: action
        )
    }
}
