import AppKit
import SwiftUI

// Delivery failure card. Behavior ported from altic-dev/FluidVoice by altic-dev:
//   @d5cc5090 friendlier wording, @ff92b4b8 shorter title, @8a820022 one Copy action and a
//   10 s auto-dismiss, @088efe13 its own transient panel instead of an overlay state, and
//   @9c25e758 a card for every failure, with Open Settings for Accessibility.
// The look is Liquid Voice's own and follows the recording overlay (BottomOverlayView): a
// pure-black pill with the same inner border, framed by icon-only chips on two three-slot
// rails (Copy at the bottom-left like the overlay's Copy chip, Dismiss at the top-right like
// its Cancel chip). It appears where the overlay sits, including a dragged position, and its
// size never changes with the transcript length.

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

    private init() {}

    var isVisible: Bool {
        self.panel?.isVisible == true
    }

    func show(_ report: DeliveryFailureReport) {
        let failure = report.failure
        let transcript = report.transcript
        guard let title = failure.userFacingTitle else { return }
        self.present(DeliveryFailureCardView(
            title: title,
            transcript: transcript,
            detail: Self.detailText(clipboard: report.clipboard, inHistory: report.inHistory),
            offersAccessibilitySettings: failure == .accessibilityNotTrusted,
            onCopy: { [weak self] in
                ClipboardService.copyToClipboard(transcript)
                self?.hide(after: 0.9)
            },
            onOpenSettings: { [weak self] in
                if let url = Self.accessibilitySettingsURL { NSWorkspace.shared.open(url) }
                self?.hide()
            },
            onDismiss: { [weak self] in self?.hide() },
            onHoverChanged: { [weak self] hovering in self?.hoverChanged(hovering) }
        ))
        self.presentedFailure = failure
        self.presentedTranscript = transcript
        DebugLogger.shared.info("Delivery failure card shown failure=\(failure.rawValue) chars=\(transcript.count)", source: "DeliveryFailureCard")
    }

    /// A dictation whose transcription timed out (its audio is kept), or a recording refused
    /// while the model recovers. Same card; Reprocess takes Copy's place.
    func showTranscriptionTimeout(_ notice: TranscriptionTimeoutNotice) {
        let title: String
        let message: String
        let detail: String
        let offersReprocess: Bool
        switch notice {
        case .timedOut:
            title = "Transcription timed out"
            message = "The speech model didn't finish in time. Your recording is kept, even across a restart."
            detail = "Reprocess it once the model is back. Your next dictation replaces it."
            offersReprocess = true
        case .recovered:
            title = "Speech recognition is back"
            message = "Your timed-out recording is ready to transcribe."
            detail = "Reprocess it now. Your next dictation replaces it."
            offersReprocess = true
        case let .recordingRefused(hasKeptAudio):
            title = "Speech recognition is recovering"
            message = "The speech model is still busy with an earlier recording, so this one didn't start."
            detail = hasKeptAudio ? "The timed-out recording is kept for Reprocess." : "Try again in a moment."
            offersReprocess = hasKeptAudio
        case .reprocessUnavailable:
            title = "Speech recognition is recovering"
            message = "The model can't transcribe the kept recording yet."
            detail = "It stays kept. Reprocess again in a moment."
            offersReprocess = true
        }
        self.present(DeliveryFailureCardView(
            title: title,
            transcript: "",
            message: message,
            detail: detail,
            offersAccessibilitySettings: false,
            primaryAction: offersReprocess ? .reprocess : .none,
            iconName: "hourglass",
            onCopy: { [weak self] in
                // Reprocess: the same path as the overlay's Reprocess chip and hotkey.
                NotchContentState.shared.onReprocessLastRequested?()
                self?.hide()
            },
            onOpenSettings: {},
            onDismiss: { [weak self] in self?.hide() },
            onHoverChanged: { [weak self] hovering in self?.hoverChanged(hovering) }
        ))
        self.presentedTimeout = notice
        DebugLogger.shared.info("Transcription timeout card shown notice=\(notice)", source: "DeliveryFailureCard")
    }

    /// A dictation hotkey pressed while macOS denies the microphone: recording cannot start, so
    /// say so where the overlay would have appeared, with a way to the Microphone settings.
    func showMicrophoneAccessNeeded() {
        self.present(DeliveryFailureCardView(
            title: "Microphone access is off",
            transcript: "",
            message: "macOS doesn't let \(Bundle.main.fluidAppDisplayName) use the microphone, so recording didn't start.",
            detail: "Turn it on in Privacy & Security > Microphone.",
            offersAccessibilitySettings: true,
            settingsHelp: "Open Microphone Settings",
            primaryAction: .none,
            iconName: "mic.slash.fill",
            onCopy: {},
            onOpenSettings: { [weak self] in
                if let url = Self.microphoneSettingsURL { NSWorkspace.shared.open(url) }
                self?.hide()
            },
            onDismiss: { [weak self] in self?.hide() },
            onHoverChanged: { [weak self] hovering in self?.hoverChanged(hovering) }
        ))
        self.presentedMicrophoneAccessNeeded = true
        DebugLogger.shared.info("Microphone access card shown", source: "DeliveryFailureCard")
    }

    private func present(_ rootView: DeliveryFailureCardView) {
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
        self.positionPanel()
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
        self.presentedFailure = nil
        self.presentedTranscript = nil
        self.presentedTimeout = nil
        self.presentedMicrophoneAccessNeeded = false
        self.panel?.orderOut(nil)
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

    /// The card's third line: where the transcript is now, and why it is not on the clipboard
    /// when it is not (a newer copy of the user's is never replaced).
    static func detailText(clipboard: TranscriptBackupOutcome, inHistory: Bool) -> String {
        switch (clipboard, inHistory) {
        case (.copied, true), (.alreadyOnClipboard, true): "Kept on your clipboard and in history."
        case (.copied, false), (.alreadyOnClipboard, false): "Kept on your clipboard."
        case (.newerClipboardCopy, true): "In history. Your newer clipboard was left alone."
        case (.newerClipboardCopy, false): "Your newer clipboard was left alone. Use Copy."
        case (.writeFailed, true): "In history. The clipboard couldn't be written."
        case (.writeFailed, false): "The clipboard couldn't be written. Use Copy."
        case (.emptyText, _): "Nothing was captured."
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
        panel.hasShadow = false // SwiftUI draws the pill; same as the recording overlay.
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = false
        self.panel = panel
    }

    private func positionPanel() {
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
        // Never cover a recording overlay that is on screen: sit just above it instead.
        if let overlayFrame = BottomOverlayWindowController.shared.presentedFrame,
           overlayFrame.intersects(NSRect(origin: origin, size: size))
        {
            origin.y = min(overlayFrame.maxY + 8, visibleFrame.maxY - size.height - 12)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// The card itself: medium-overlay metrics, pure black, icon-only chips.
struct DeliveryFailureCardView: View {
    /// The bottom-left chip: Copy for an undelivered transcript, Reprocess for a timed-out one.
    enum PrimaryAction {
        case copy
        case reprocess
        case none
    }

    let title: String
    let transcript: String
    /// Shown instead of the quoted transcript when set (a card with no transcript).
    var message: String? = nil
    let detail: String
    let offersAccessibilitySettings: Bool
    /// The settings chip's tooltip (the chip opens whatever `onOpenSettings` opens).
    var settingsHelp: String = "Open Accessibility Settings"
    var primaryAction: PrimaryAction = .copy
    var iconName: String? = nil
    /// The primary chip's action (Copy or Reprocess).
    let onCopy: () -> Void
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void
    let onHoverChanged: (Bool) -> Void

    // Medium overlay geometry (BottomOverlayView.LayoutConstants.get(.medium)).
    static let pillWidth: CGFloat = 340
    private static let hPadding: CGFloat = 18
    private static let vPadding: CGFloat = 12
    private static let cornerRadius: CGFloat = 18
    private static let transcriptFontSize: CGFloat = 13
    private static let chipIconSize: CGFloat = 12
    private static let chipCornerRadius: CGFloat = 8

    @State private var didCopy = false
    @State private var hoveredChip: String?

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(spacing: 6) {
                if self.offersAccessibilitySettings {
                    self.chip("settings", systemName: "gearshape", help: self.settingsHelp, action: self.onOpenSettings)
                } else {
                    self.chipSpacer
                }
                self.chipSpacer
                switch self.primaryAction {
                case .copy:
                    self.chip(
                        "copy",
                        systemName: self.didCopy ? "checkmark" : "doc.on.doc",
                        help: self.didCopy ? "Copied" : "Copy Transcript",
                        action: self.copy
                    )
                case .reprocess:
                    self.chip("reprocess", systemName: "arrow.clockwise", help: "Reprocess", action: self.onCopy)
                case .none:
                    self.chipSpacer
                }
            }

            self.pill

            VStack(spacing: 6) {
                self.chip("dismiss", systemName: "xmark", help: "Dismiss", action: self.onDismiss)
                self.chipSpacer
                self.chipSpacer
            }
        }
        .padding(8)
        .onHover { self.onHoverChanged($0) }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(self.title)
    }

    private var pill: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: self.iconName ?? (self.offersAccessibilitySettings ? "lock.fill" : "text.cursor"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.9))
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                Text(self.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // Two lines are always reserved, so a short and a long transcript give the same card.
            Text(self.message ?? self.transcriptPreview)
                .font(.system(size: Self.transcriptFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(self.message == nil ? 0.9 : 0.75))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(
                    maxWidth: .infinity,
                    minHeight: Self.transcriptLineHeight * 2,
                    maxHeight: Self.transcriptLineHeight * 2,
                    alignment: .topLeading
                )

            Text(self.detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .padding(.horizontal, Self.hPadding)
        .padding(.vertical, Self.vPadding)
        .frame(width: Self.pillWidth, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .fill(Color.black)
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        )
    }

    private static var transcriptLineHeight: CGFloat {
        max(self.transcriptFontSize * 1.25, self.transcriptFontSize + 2)
    }

    private var transcriptPreview: String {
        let trimmed = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Nothing was captured" : "\u{201C}\(trimmed)\u{201D}"
    }

    private func copy() {
        guard !self.didCopy else { return }
        self.didCopy = true
        self.onCopy()
    }

    /// An icon-only chip matching the overlay's rail chips (`BottomOverlayView.chipBackground`).
    private func chip(_ id: String, systemName: String, help: String, action: @escaping () -> Void) -> some View {
        let isHovered = self.hoveredChip == id
        return Image(systemName: systemName)
            .font(.system(size: Self.chipIconSize, weight: .semibold))
            .foregroundStyle(.white.opacity(0.72))
            // Fixed glyph box: swapping doc.on.doc for checkmark must not resize the chip.
            .frame(width: 16, height: 16)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Self.chipBackground(isHovered: isHovered))
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    self.hoveredChip = id
                } else if self.hoveredChip == id {
                    self.hoveredChip = nil
                }
            }
            .onTapGesture(perform: action)
            .help(help)
            .accessibilityElement()
            .accessibilityLabel(help)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    /// A chip-sized transparent slot, so both rails stay three slots tall.
    private var chipSpacer: some View {
        Color.clear
            .frame(width: 16, height: 16)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }

    private static func chipBackground(isHovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: self.chipCornerRadius)
            .fill(isHovered ? Color(red: 0.13, green: 0.13, blue: 0.16) : Color.black)
            .overlay(
                RoundedRectangle(cornerRadius: self.chipCornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovered ? 0.36 : 0.14),
                                Color.white.opacity(isHovered ? 0.22 : 0.08),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: isHovered ? Color.white.opacity(0.16) : .clear, radius: 6, x: 0, y: 1)
    }
}
