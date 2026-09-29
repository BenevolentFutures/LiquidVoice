import AppKit
import SwiftUI

// MARK: - Bottom Overlay SwiftUI View (Signal)

/// The recording overlay in the Signal language (DESIGN.md §4, §9): the pill between two rails of
/// chips, History / Copy on the left and Cancel / Reprocess on the right; Spoken Send lives in the
/// trace row (§15). The window keeps a transparent margin around the content (6 pt, 8 at the
/// bottom) so the selection brackets outside the boxes are never clipped; that margin paints
/// nothing, so clicks there reach the app beneath.
struct BottomOverlayView: View {
    @ObservedObject private var contentState = NotchContentState.shared
    @ObservedObject private var model = SignalOverlayModel.shared
    @ObservedObject private var appServices = AppServices.shared
    @ObservedObject private var activeAppMonitor = ActiveAppMonitor.shared
    @ObservedObject private var historyStore = TranscriptionHistoryStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var spokenSend = SpokenSendController.shared
    @ObservedObject private var historyCard = BottomOverlayHistoryMenuController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHoveringOverlay = false
    @State private var hoveredChips: Set<String> = []
    @State private var isCopyConfirming = false
    @State private var copyConfirmationID = 0
    /// Where the History chip is on screen, for the card's anchor. A reference, not view state:
    /// the anchor reader reports it during view updates, which must not invalidate the view.
    @State private var historyChipAnchor = SignalChipAnchor()
    @State private var lastResolvedAppIcon: NSImage?
    @State private var dragStartMouseLocation: NSPoint?
    @State private var dragStartWindowOrigin: NSPoint?

    /// The overlay panel's floating shadow, which the pill reports its box to. Only the overlay's
    /// own panel passes it; a render or another host reports nowhere.
    private let floatShadow: SignalFloatShadow.State?

    init(floatShadow: SignalFloatShadow.State? = nil) {
        self.floatShadow = floatShadow
    }

    /// What the pill shows, from the controller's phase and the shared flags.
    enum Display: Equatable {
        case listening
        case stopped
        case transcribing
        case delivered(SignalDelivery)
        /// The AI-enhancement failure row (provisional).
        case notice
        /// A notice row (DESIGN.md §15): "Speech recognition is back".
        case noticeRow(SignalNotice)
        case idle
    }

    var display: Display {
        Self.display(contentState: self.contentState, model: self.model)
    }

    static func display(contentState: NotchContentState, model: SignalOverlayModel) -> Display {
        if contentState.isProcessing { return .transcribing }
        if contentState.isAIProcessingFailureVisible { return .notice }
        switch model.phase {
        case .idle: return .idle
        case .listening: return .listening
        case .stopped: return .stopped
        case .transcribing: return .transcribing
        case let .delivered(delivery): return .delivered(delivery)
        case let .notice(notice): return .noticeRow(notice)
        }
    }

    private var geometry: SignalOverlayGeometry {
        SignalOverlayGeometry.forSize(self.settings.overlaySize)
    }

    /// On screen, not fading out: the overlay takes clicks only then.
    private var isInteractive: Bool {
        self.contentState.isBottomOverlayPresented && !self.contentState.isBottomOverlayDismissing && !self.model.isFading
    }

    // MARK: Chips

    enum ChipRole {
        /// History: live whenever the overlay is, except during the delivered hold.
        case history
        /// Cancel: live while recording or on a notice. After the stop it acts only while SEND shows
        /// (it then drops the Return); otherwise it could only hide the overlay while the paste
        /// still went out, so it rests.
        case cancel
        /// Copy and Reprocess: live only while listening or on a notice; dimmed while transcribing.
        case historyAction
    }

    private var hasHistory: Bool {
        !self.historyStore.entries.isEmpty
    }

    /// Inert: the chip looks at rest but acts on nothing. During the delivered hold no chip may
    /// re-fire a paste or copy; Copy and Reprocess wait until the final pass is done.
    /// `cancelHasWork`: after the stop, Cancel can still drop a pending Return, or dismiss a pill
    /// whose Return it already dropped.
    static func isChipInert(_ role: ChipRole, display: Display, cancelHasWork: Bool = false) -> Bool {
        switch display {
        case .delivered, .idle: return true
        case .stopped: return role == .historyAction || (role == .cancel && !cancelHasWork)
        case .transcribing: return role == .cancel && !cancelHasWork
        case .listening, .notice, .noticeRow: return false
        }
    }

    /// Disabled (dimmed): Copy and Reprocess without history, and while transcribing.
    static func isChipEnabled(_ role: ChipRole, display: Display, hasHistory: Bool) -> Bool {
        switch role {
        case .history, .cancel: return true
        case .historyAction: return hasHistory && display != .transcribing
        }
    }

    /// After the stop, Cancel acts while it still has something to do: drop a pending Return, or,
    /// once dropped, dismiss the pill (the text still pastes; it is already on its way).
    private func isInert(_ role: ChipRole) -> Bool {
        let cancelHasWork = self.canCancelSend || self.model.stopPlacard == .noSend
        return Self.isChipInert(role, display: self.display, cancelHasWork: cancelHasWork)
    }

    private func isEnabled(_ role: ChipRole) -> Bool {
        Self.isChipEnabled(role, display: self.display, hasHistory: self.hasHistory)
    }

    private func chipHover(_ id: String) -> (Bool) -> Void {
        { hovering in
            if hovering { self.hoveredChips.insert(id) } else { self.hoveredChips.remove(id) }
        }
    }

    /// Belt and braces with allowsHitTesting: a hidden overlay's chip must never act.
    private func perform(_ action: () -> Void) {
        guard self.isInteractive else { return }
        action()
    }

    private var historyChip: some View {
        SignalChip(
            systemName: "clock.arrow.circlepath",
            help: self.hasHistory ? "Recent Dictations" : "No saved dictation history available",
            isEnabled: self.hasHistory,
            isInert: self.isInert(.history),
            isLatched: self.historyCard.isOpen,
            isHoverForced: self.model.inspectionHover == "history",
            onHoverChanged: self.chipHover("history")
        ) {
            self.perform {
                BottomOverlayHistoryMenuController.shared.updateAnchor(
                    selectorFrameInScreen: self.historyChipAnchor.frameInScreen,
                    parentWindow: self.historyChipAnchor.window,
                    maxWidth: SignalTheme.Metrics.historyWidth,
                    menuGap: SignalTheme.Metrics.historyGapAboveChip
                )
                BottomOverlayHistoryMenuController.shared.toggleFromTap()
            }
        }
        .background(
            PromptSelectorAnchorReader { [historyChipAnchor] frameInScreen, window in
                historyChipAnchor.frameInScreen = frameInScreen
                historyChipAnchor.window = window
            }
            .allowsHitTesting(false)
        )
    }

    private var copyChip: some View {
        SignalChip(
            systemName: "doc.on.doc",
            help: self.hasHistory ? "Copy Last Transcription" : "No saved dictation history available",
            isEnabled: self.isEnabled(.historyAction),
            isInert: self.isInert(.historyAction),
            isConfirming: self.isCopyConfirming,
            isHoverForced: self.model.inspectionHover == "copy",
            onHoverChanged: self.chipHover("copy")
        ) {
            self.perform {
                BottomOverlayHistoryMenuController.shared.hide()
                self.contentState.onCopyLastRequested?()
                self.confirmCopy()
            }
        }
    }

    private var cancelChip: some View {
        SignalChip(
            systemName: "xmark",
            help: "Cancel Dictation (\(self.settings.cancelRecordingHotkeyShortcut.displayString))",
            isInert: self.isInert(.cancel),
            isHoverForced: self.model.inspectionHover == "cancel",
            onHoverChanged: self.chipHover("cancel")
        ) {
            self.perform {
                BottomOverlayHistoryMenuController.shared.hide()
                // On a notice row the Cancel chip dismisses it (DESIGN.md §15).
                if case .noticeRow = self.display {
                    BottomOverlayWindowController.shared.dismissNotice()
                    return
                }
                if self.display == .notice {
                    self.contentState.clearAIProcessingFailure()
                }
                self.contentState.onCancelRequested?()
            }
        }
    }

    private var reprocessChip: some View {
        SignalChip(
            systemName: "arrow.clockwise",
            help: self.hasHistory ? "Reprocess Last Dictation" : "No saved dictation history available",
            isEnabled: self.isEnabled(.historyAction),
            isInert: self.isInert(.historyAction),
            isHoverForced: self.model.inspectionHover == "reprocess",
            onHoverChanged: self.chipHover("reprocess")
        ) {
            self.perform {
                BottomOverlayHistoryMenuController.shared.hide()
                // On a notice row the chip is the row's Reprocess: once, and the row gives way.
                if case .noticeRow = self.display {
                    BottomOverlayWindowController.shared.reprocessFromNotice()
                    return
                }
                self.contentState.clearAIProcessingFailure()
                self.contentState.onReprocessLastRequested?()
            }
        }
    }

    private func confirmCopy() {
        self.copyConfirmationID &+= 1
        let id = self.copyConfirmationID
        self.isCopyConfirming = true
        DispatchQueue.main.asyncAfter(deadline: .now() + SignalTheme.Motion.copyFeedbackChip) {
            guard self.copyConfirmationID == id else { return }
            self.isCopyConfirming = false
        }
    }

    // MARK: Body

    var body: some View {
        let geometry = self.geometry
        HStack(alignment: .bottom, spacing: SignalTheme.Metrics.railGap) {
            SignalRail(height: geometry.railHeight) {
                self.historyChip
            } middle: {
                Color.clear
            } bottom: {
                self.copyChip
            }
            self.pill(geometry)
            SignalRail(height: geometry.railHeight) {
                self.cancelChip
            } middle: {
                // Reserved. Spoken Send lives in the trace row (DESIGN.md §15), not a fifth chip.
                Color.clear
            } bottom: {
                self.reprocessChip
            }
        }
        // The pill's bracket shows over the pill and the rails' gutter, but only one bracket at a
        // time: over a chip, that chip's own bracket draws instead.
        .onHover { hovering in
            self.isHoveringOverlay = hovering
            // A notice row's timer waits while the pointer is over the pill.
            BottomOverlayWindowController.shared.noticeHoverChanged(hovering)
        }
        .padding(SignalTheme.Metrics.windowInsets)
        // Whole-surface drag with position memory; double-click returns to the default anchor.
        // Both sit on the parent so the chips' own taps win where they overlap.
        .onTapGesture(count: 2) {
            guard self.isInteractive else { return }
            BottomOverlayWindowController.shared.resetDraggedPositionToDefault()
        }
        .gesture(self.windowDragGesture)
        .signalPalette()
        // A hiding or hidden overlay must never act on a click meant for the app beneath it.
        .allowsHitTesting(self.isInteractive)
        .modifier(BottomOverlayVisibility(
            isFading: self.model.isFading,
            isPresented: self.contentState.isBottomOverlayPresented,
            reduceMotion: self.reduceMotion
        ))
        .onChange(of: self.display) { _, display in
            switch display {
            case .delivered, .idle:
                BottomOverlayHistoryMenuController.shared.hide()
            case .listening, .stopped, .transcribing, .notice, .noticeRow:
                break
            }
        }
        .onChange(of: self.contentState.mode) { _, mode in
            switch mode {
            case .dictation: self.contentState.promptPickerMode = .dictate
            case .edit, .write, .rewrite: self.contentState.promptPickerMode = .edit
            case .command: break
            }
        }
        // A hidden overlay gets no hover-out: forget the hover so no bracket shows at rest next time.
        .onChange(of: self.contentState.isBottomOverlayPresented) { _, presented in
            guard !presented else { return }
            self.isHoveringOverlay = false
            self.hoveredChips.removeAll()
        }
        .onAppear {
            self.rememberAppIcon(self.contentState.targetAppIcon ?? self.activeAppMonitor.activeAppIcon)
        }
        .onReceive(self.contentState.$targetAppIcon) { icon in
            self.rememberAppIcon(icon)
        }
    }

    private func pill(_ geometry: SignalOverlayGeometry) -> some View {
        let display = self.display
        let pillBracket = (self.isHoveringOverlay && self.hoveredChips.isEmpty && !self.historyCard.isHovered
            && self.isInteractive) || self.model.inspectionHover == "pill"
        return SignalPill(
            geometry: geometry,
            topHeight: geometry.topAreaHeight,
            traceRow: self.traceRow(geometry, display: display),
            micText: self.micText,
            isBracketVisible: pillBracket
        ) {
            self.topArea(geometry, display: display)
        }
        // A click anywhere on the pill while SEND shows cancels the Return (DESIGN.md §15).
        // Simultaneous, so the whole surface's double-click (reset position) and drag still work.
        .simultaneousGesture(TapGesture().onEnded {
            // While SEND shows and the Return can still be dropped (listening, stopped or
            // transcribing, until the stop decides), a click cancels it.
            guard self.isInteractive, self.canCancelSend else { return }
            BottomOverlayWindowController.shared.cancelSpokenSendIfArmed()
        })
        .help(self.canCancelSend ? "Click to cancel Send" : "")
        .signalFloatShadowSource(self.floatShadow)
    }

    @ViewBuilder
    private func topArea(_ geometry: SignalOverlayGeometry, display: Display) -> some View {
        switch display {
        case let .delivered(delivery):
            SignalDeliveredStatement(delivery: delivery, isCompact: geometry.isCompactTop)
        case .notice:
            SignalNoticeRow(
                message: self.contentState.aiProcessingFailureMessage,
                canRetry: self.contentState.canRetryAIProcessingFailure,
                isCompact: geometry.isCompactTop,
                onRetry: {
                    self.perform {
                        self.contentState.clearAIProcessingFailure()
                        self.contentState.onReprocessLastRequested?()
                    }
                },
                onDismiss: {
                    self.perform {
                        self.contentState.clearAIProcessingFailure()
                        NotchOverlayManager.shared.hide()
                    }
                }
            )
        case let .noticeRow(notice):
            SignalInlineNotice(
                notice: notice,
                isHoverForced: self.model.inspectionHover,
                onHoverChanged: { id, hovering in self.chipHover(id)(hovering) },
                onReprocess: {
                    self.perform { BottomOverlayWindowController.shared.reprocessFromNotice() }
                },
                onDismiss: {
                    self.perform { BottomOverlayWindowController.shared.dismissNotice() }
                }
            )
        case .listening, .stopped, .transcribing, .idle:
            SignalPreview(
                text: SignalTextFitting.newestWords(
                    of: self.previewText(display),
                    wasCut: self.contentState.transcriptionText.count > self.contentState.cachedPreviewText.count,
                    font: SignalTheme.Typography.preview.nsFont,
                    width: geometry.innerWidth,
                    lines: geometry.previewLines
                ),
                lines: geometry.previewLines,
                height: geometry.topAreaHeight,
                width: geometry.innerWidth,
                isDimmed: display == .transcribing
            )
        }
    }

    /// Spoken Send's countdown is showing: the quiet countdown runs (or its cancel is held) while
    /// the phrase sends in this app.
    private var countdownDrain: SignalDrain? {
        guard self.display == .listening, let drain = self.model.sendDrain else { return nil }
        return drain
    }

    private var canCancelSend: Bool {
        self.placard == .send && self.spokenSend.hasPendingReturn
    }

    private var placard: SignalPlacard {
        if let placard = self.model.inspectionPlacard { return placard }
        return Self.placard(
            display: self.display,
            model: self.model,
            spokenSend: self.spokenSend,
            spokenSendEnabled: self.settings.spokenSendEnabled,
            mode: self.contentState.mode
        )
    }

    /// The placard the pill shows for `display`. The view draws it; the cancel gate reads it, so
    /// "the pill visibly shows SEND" means exactly what is on screen.
    static func placard(
        display: Display,
        model: SignalOverlayModel,
        spokenSend: SpokenSendController,
        spokenSendEnabled: Bool,
        mode: OverlayMode
    ) -> SignalPlacard {
        switch display {
        case .listening:
            // A canceled countdown keeps NO SEND while its bar is held (it only exists with Spoken Send).
            if model.sendDrain?.isCanceled == true { return .noSend }
            guard spokenSendEnabled, mode == .dictation else { return .none }
            return SignalOverlayModel.placard(indicator: spokenSend.indicator, sendsInApp: spokenSend.sendsInRecordingApp)
        case .stopped, .transcribing, .delivered:
            return model.stopPlacard
        case .notice, .noticeRow, .idle:
            return .none
        }
    }

    private func traceRow(_ geometry: SignalOverlayGeometry, display: Display) -> SignalTraceRow {
        let drain = self.countdownDrain
        let mark: SignalRecordMark
        switch display {
        case .listening: mark = drain == nil ? .recording : .closed
        case .stopped, .transcribing: mark = .closed
        case .delivered, .notice, .noticeRow, .idle: mark = .none
        }
        let timer: SignalTimerReadout
        if let drain {
            timer = .countdown(drain)
        } else if display == .listening, self.model.frozenDuration == nil, let start = self.model.recordingStartedAt {
            timer = .running(start)
        } else {
            timer = .frozen(self.model.timerText(at: Date()), dim: false)
        }
        return SignalTraceRow(
            geometry: geometry,
            icon: self.contentState.targetAppIcon ?? self.activeAppMonitor.activeAppIcon ?? self.lastResolvedAppIcon,
            trace: self.model.trace,
            isLive: display == .listening && self.model.trace.isLive,
            isSweeping: display == .transcribing,
            drain: drain,
            staticSweepProgress: self.model.inspectionSweepProgress,
            mark: mark,
            placard: self.placard,
            timer: timer
        )
    }

    // MARK: Text

    /// The live preview without the status words the stop path writes into it ("Transcribing"):
    /// the hollow square, the frozen timer and the sweep carry that state.
    private var livePreview: String {
        let text = self.contentState.cachedPreviewText
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return SignalOverlayModel.statusWords.contains(trimmed) ? "" : trimmed
    }

    private func previewText(_ display: Display) -> String {
        switch display {
        case .listening:
            return self.livePreview
        case .stopped, .transcribing:
            // A streamed AI answer replaces the frozen dictation while it refines.
            let live = self.livePreview
            return live.isEmpty || live == self.model.frozenPreview ? self.model.frozenPreview : live
        case .delivered, .notice, .noticeRow, .idle:
            return ""
        }
    }

    /// The microphone, and (provisional, awaiting round 5) the words that replace the retired
    /// mode tint and model spinner: "EDIT", "COMMAND", "LOADING MODEL".
    private var micText: String {
        var parts: [String] = []
        let asr = self.appServices.asr
        if !asr.isAsrReady, asr.isLoadingModel || asr.isDownloadingModel {
            parts.append("Loading model")
        }
        switch self.contentState.mode {
        case .dictation: break
        case .edit, .write, .rewrite: parts.append("Edit")
        case .command: parts.append("Command")
        }
        let microphone = self.model.microphoneName.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append(microphone.isEmpty ? "Microphone" : microphone)
        return parts.joined(separator: " · ")
    }

    private func rememberAppIcon(_ icon: NSImage?) {
        guard let icon else { return }
        self.lastResolvedAppIcon = icon
    }

    // MARK: Drag

    /// Moves the panel by tracking the pointer in screen coordinates. The gesture's own
    /// translation is in view space, which shifts as the window moves under the cursor.
    private var windowDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { _ in
                guard self.isInteractive else { return }
                let mouse = NSEvent.mouseLocation
                if self.dragStartMouseLocation == nil {
                    self.dragStartMouseLocation = mouse
                    self.dragStartWindowOrigin = BottomOverlayWindowController.shared.frameOriginForDrag
                }
                guard let startMouse = self.dragStartMouseLocation,
                      let startOrigin = self.dragStartWindowOrigin else { return }
                BottomOverlayWindowController.shared.dragWindow(to: NSPoint(
                    x: startOrigin.x + (mouse.x - startMouse.x),
                    y: startOrigin.y + (mouse.y - startMouse.y)
                ))
            }
            .onEnded { _ in
                let didMove = self.dragStartWindowOrigin != nil
                self.dragStartMouseLocation = nil
                self.dragStartWindowOrigin = nil
                if didMove {
                    BottomOverlayWindowController.shared.commitDraggedPosition()
                }
            }
    }
}

/// A chip's on-screen frame and window, reported by `PromptSelectorAnchorReader`.
final class SignalChipAnchor {
    var frameInScreen: CGRect = .zero
    weak var window: NSWindow?
}

/// The overlay's visibility (DESIGN.md §8), shared by the overlay and its floating shadow so the
/// shadow never outlives or precedes the pill: the dismiss fades over 120 ms linear (a cut under
/// reduced motion), and hidden paints nothing at all, at once, whatever the fade's progress (a
/// transparent panel passes clicks through wherever its pixels are clear, from the hide on; not
/// animated, so it never depends on a frame clock; ignoresMouseEvents is never touched).
struct BottomOverlayVisibility: ViewModifier {
    let isFading: Bool
    let isPresented: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(self.isFading ? 0 : 1)
            .animation(
                self.isFading && !self.reduceMotion ? .linear(duration: SignalTheme.Motion.dismiss) : nil,
                value: self.isFading
            )
            .opacity(self.isPresented ? 1 : 0)
    }
}

/// The pill's floating shadow (DESIGN.md §6), drawn in its own click-through panel under the
/// overlay's (SignalFloatShadow), fading and hiding exactly as the overlay does.
struct BottomOverlayShadowView: View {
    @ObservedObject var state: SignalFloatShadow.State
    @ObservedObject private var contentState = NotchContentState.shared
    @ObservedObject private var model = SignalOverlayModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SignalFloatShadowView(state: self.state)
            .signalPalette()
            .modifier(BottomOverlayVisibility(
                isFading: self.model.isFading,
                isPresented: self.contentState.isBottomOverlayPresented,
                reduceMotion: self.reduceMotion
            ))
    }
}
