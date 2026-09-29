import AppKit
import Combine
import SwiftUI

enum MenuBarNavigationDestination: String {
    case customDictionary
    case microphoneSettings
    case preferences
}

@MainActor
final class MenuBarManager: NSObject, ObservableObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var isSetup: Bool = false
    private var hostedWindow: NSWindow?

    // Cached menu items to avoid rebuilding entire menu
    private var statusMenuItem: NSMenuItem?
    private var headerView: SignalMenuHeaderView?
    private var toggleDictationMenuItem: NSMenuItem?
    private var headerRefreshTimer: Timer?

    // The Signal menu bar mark (DESIGN.md §10).
    private var markKind: SignalMenuBarMark.Kind = .idle
    private var markBars: [CGFloat] = SignalMenuBarMark.restingBars
    private var isMarkHovered = false
    private var isMenuOpen = false
    private var markTimer: Timer?
    private var markHoverTracker: MenuBarMarkHoverTracker?
    /// A mark change owed from while a stop pipeline held window work.
    private var hasDeferredMark = false
    /// When the current recording started, for the menu header (whichever overlay shows it).
    private var recordingStartedAt: Date?

    /// Start / Stop Dictation from the menu: the same toggle as the dictation hotkey.
    var onToggleDictationRequested: (() -> Void)?
    private var copyLastTranscriptMenuItem: NSMenuItem?
    private var microphoneMenuItem: NSMenuItem?
    private var microphoneSubmenu: NSMenu?

    // References to app state
    private weak var asrService: ASRService?
    private var cancellables = Set<AnyCancellable>()
    /// A menu rebuild owed from a stop that held UI refreshes (see ASRService.holdsStopUIRefresh).
    private var hasDeferredMenuRefresh = false
    private var configuredASRIdentifier: ObjectIdentifier?

    /// Overlay management (persistent, independent of window lifecycle)
    private var overlayVisible: Bool = false

    /// Track when AI processing is active.
    /// When recording stops, ASRService flips `isRunning` to false, which would normally hide the
    /// overlay. During post-processing we want the overlay to stay visible until processing ends.
    private var isProcessingActive: Bool = false

    @Published var isRecording: Bool = false

    /// One-shot navigation requests from the menu bar into the main window UI.
    /// The manager clears each generation after the front-most view has handled it.
    @Published var requestedNavigationDestination: MenuBarNavigationDestination? = nil
    private var navigationRequestGeneration: UInt64 = 0

    /// Track current overlay mode for notch
    private var currentOverlayMode: OverlayMode = .dictation

    // Track pending overlay operations to prevent spam
    private var pendingShowOperation: DispatchWorkItem?
    private var pendingHideOperation: DispatchWorkItem?
    private var pendingProcessingShowOperation: DispatchWorkItem?
    /// Show immediately so users see the processing state right away.
    private let processingVisualDelay: DispatchTimeInterval = .milliseconds(0)
    /// Legacy debounce used by generic processing callers. Successful dictation
    /// completion dispatches output first, then hides the overlay asynchronously.
    private let processingHideDelay: DispatchTimeInterval = .milliseconds(80)

    /// Subscription for forwarding audio levels to expanded command notch
    private var expandedModeAudioSubscription: AnyCancellable?

    override init() {
        super.init()
        NotificationCenter.default.publisher(for: .openMicrophoneSettingsRequested)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.openMicrophoneSettingsFromUI()
            }
            .store(in: &self.cancellables)
    }

    func initializeMenuBar() {
        guard !self.isSetup else { return }
        // The XCTest host shows nothing, a menu bar item included.
        guard !TestHostQuietMode.isActive else { return }

        // Ensure we're on main thread and app is active
        DispatchQueue.main.async { [weak self] in
            self?.setupMenuBarSafely()
        }
    }

    deinit {
        statusItem = nil
    }

    func configure(asrService: ASRService) {
        let identifier = ObjectIdentifier(asrService)
        guard self.configuredASRIdentifier != identifier else { return }
        self.configuredASRIdentifier = identifier
        self.asrService = asrService
        if SettingsStore.shared.overlayPosition == .bottom {
            DispatchQueue.main.async {
                guard SettingsStore.shared.overlayPosition == .bottom else { return }
                BottomOverlayWindowController.shared.prepare()
            }
        }
        NotificationCenter.default.publisher(for: NSNotification.Name("OverlayPositionChanged"))
            .receive(on: DispatchQueue.main)
            .sink { _ in
                guard SettingsStore.shared.overlayPosition == .bottom else { return }
                BottomOverlayWindowController.shared.prepare()
            }
            .store(in: &self.cancellables)

        // Subscribe to recording state changes
        asrService.$isRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak asrService] isRunning in
                guard let self else { return }
                self.isRecording = isRunning
                self.recordingStateChanged(isRunning: isRunning)
                // Rebuilding the menu is main-thread work nobody sees mid-stop: do it once the
                // stop pipeline has handed the text off (from altic-dev/FluidVoice#950).
                if !isRunning, asrService?.holdsStopUIRefresh == true {
                    self.hasDeferredMenuRefresh = true
                } else {
                    self.hasDeferredMenuRefresh = false
                    self.updateMenu()
                }

                // Handle overlay lifecycle (independent of window state)
                if let asrService {
                    self.handleOverlayState(isRunning: isRunning, asrService: asrService)
                }
            }
            .store(in: &self.cancellables)

        asrService.stopUIRefreshReleased
            .sink { [weak self] in
                guard let self, self.hasDeferredMenuRefresh else { return }
                self.hasDeferredMenuRefresh = false
                self.updateMenu()
            }
            .store(in: &self.cancellables)

        // Subscribe to partial transcription updates for streaming preview
        asrService.$partialTranscription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newText in
                guard self != nil else { return }
                if NotchOverlayManager.shared.shouldShowOrTrackLivePreviewText {
                    NotchOverlayManager.shared.updateTranscriptionText(newText)
                }
            }
            .store(in: &self.cancellables)
    }

    private func handleOverlayState(isRunning: Bool, asrService: ASRService) {
        self.overlayBench("handle_state isRunning=\(isRunning) overlayVisible=\(self.overlayVisible) processing=\(self.isProcessingActive) mode=\(self.currentOverlayMode.rawValue)")

        // Dictionary training owns its recording controls, so showing the
        // regular dictation notch here would create two competing overlays.
        if asrService.isDictionaryTrainingCaptureActive {
            self.pendingShowOperation?.cancel()
            self.pendingShowOperation = nil
            if self.overlayVisible {
                self.overlayVisible = false
                NotchOverlayManager.shared.hide()
            }
            return
        }

        // Don't hide the overlay while AI processing is active.
        // Without this, the notch can disappear during the short "Refining..." phase because
        // `isRunning` becomes false before post-processing completes.
        if !isRunning, self.isProcessingActive {
            self.overlayBench("handle_state_return reason=processing_active")
            return
        }

        // Prevent rapid state changes that could cause cycles
        guard self.overlayVisible != isRunning else {
            self.overlayBench("handle_state_return reason=visibility_unchanged")
            return
        }

        if isRunning {
            // A new recording supersedes an earlier delivery failure card.
            DeliveryFailureOverlayController.shared.hide()

            // Cancel any pending hide operation
            self.pendingHideOperation?.cancel()
            self.pendingHideOperation = nil

            self.overlayVisible = true
            self.overlayBench("show_request mode=\(self.currentOverlayMode.rawValue)")

            // If expanded command output is showing, check if we should keep it or close it
            if NotchOverlayManager.shared.isCommandOutputExpanded {
                // Only keep expanded notch if this is a command mode recording (follow-up)
                // For other modes (dictation, rewrite), close it and show regular notch
                if self.currentOverlayMode == .command, NotchOverlayManager.shared.supportsCommandNotchUI {
                    // Enable recording visualization in the expanded notch
                    NotchContentState.shared.setRecordingInExpandedMode(true)

                    // Subscribe to audio levels and forward to expanded notch
                    self.expandedModeAudioSubscription = asrService.audioLevelPublisher
                        .receive(on: DispatchQueue.main)
                        .sink { level in
                            NotchContentState.shared.updateExpandedModeAudioLevel(level)
                        }

                    self.pendingShowOperation = nil
                    return
                } else {
                    // Close expanded command notch to transition to regular notch
                    NotchOverlayManager.shared.hideExpandedCommandOutput()
                }
            }

            let showItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.overlayVisible else { return }

                // Double-check expanded notch isn't showing (could have changed during delay)
                // But only block if we're in command mode
                if NotchOverlayManager.shared.isCommandOutputExpanded,
                   self.currentOverlayMode == .command,
                   NotchOverlayManager.shared.supportsCommandNotchUI
                {
                    self.pendingShowOperation = nil
                    return
                }

                // Show notch overlay
                self.overlayBench("show_workitem_execute mode=\(self.currentOverlayMode.rawValue)")
                NotchOverlayManager.shared.show(
                    audioLevelPublisher: asrService.audioLevelPublisher,
                    mode: self.currentOverlayMode
                )
                self.overlayBench("show_workitem_return mode=\(self.currentOverlayMode.rawValue)")

                self.pendingShowOperation = nil
            }
            self.pendingShowOperation = showItem
            DispatchQueue.main.async(execute: showItem)
        } else {
            // Cancel any pending show operation
            self.pendingShowOperation?.cancel()
            self.pendingShowOperation = nil

            self.overlayVisible = false
            self.overlayBench("hide_request delayMs=30")

            // If expanded command output is showing, don't hide it - let it stay visible
            if NotchOverlayManager.shared.isCommandOutputExpanded {
                // Stop recording visualization in expanded notch
                NotchContentState.shared.setRecordingInExpandedMode(false)
                self.expandedModeAudioSubscription?.cancel()
                self.expandedModeAudioSubscription = nil

                self.pendingHideOperation = nil
                return
            }

            let hideItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.overlayVisible else { return }

                // Don't hide if expanded command output is now showing
                if NotchOverlayManager.shared.isCommandOutputExpanded {
                    self.pendingHideOperation = nil
                    return
                }

                // Hide notch overlay
                self.overlayBench("hide_workitem_execute")
                NotchOverlayManager.shared.hide()
                self.overlayBench("hide_workitem_return")

                self.pendingHideOperation = nil
            }
            self.pendingHideOperation = hideItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30), execute: hideItem)
        }
    }

    func showRecordingOverlayImmediately() {
        AutomaticDictionaryCorrectionTracker.shared.cancel()

        guard let asrService else {
            self.overlayBench("instant_show_return reason=no_asr_service")
            return
        }

        self.pendingHideOperation?.cancel()
        self.pendingHideOperation = nil
        self.pendingShowOperation?.cancel()
        self.pendingShowOperation = nil

        guard !self.overlayVisible else {
            self.overlayBench("instant_show_return reason=already_visible")
            return
        }

        self.overlayVisible = true
        self.overlayBench("instant_show_request mode=\(self.currentOverlayMode.rawValue)")

        if NotchOverlayManager.shared.isCommandOutputExpanded {
            if self.currentOverlayMode == .command, NotchOverlayManager.shared.supportsCommandNotchUI {
                NotchContentState.shared.setRecordingInExpandedMode(true)
                self.expandedModeAudioSubscription = asrService.audioLevelPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { level in
                        NotchContentState.shared.updateExpandedModeAudioLevel(level)
                    }
                return
            }
            NotchOverlayManager.shared.hideExpandedCommandOutput()
        }

        self.overlayBench("show_workitem_execute mode=\(self.currentOverlayMode.rawValue)")
        NotchOverlayManager.shared.show(
            audioLevelPublisher: asrService.audioLevelPublisher,
            mode: self.currentOverlayMode
        )
        self.overlayBench("show_workitem_return mode=\(self.currentOverlayMode.rawValue)")
    }

    func hideRecordingOverlayImmediately(reason: String) {
        self.pendingShowOperation?.cancel()
        self.pendingShowOperation = nil
        self.pendingHideOperation?.cancel()
        self.pendingHideOperation = nil

        guard !self.isProcessingActive else {
            self.overlayBench("instant_hide_return reason=\(reason) processing_active")
            return
        }

        guard self.overlayVisible else {
            self.overlayBench("instant_hide_return reason=\(reason) already_hidden")
            return
        }

        self.overlayVisible = false
        self.overlayBench("instant_hide_request reason=\(reason)")

        if NotchOverlayManager.shared.isCommandOutputExpanded {
            NotchContentState.shared.setRecordingInExpandedMode(false)
            self.expandedModeAudioSubscription?.cancel()
            self.expandedModeAudioSubscription = nil
            self.overlayBench("instant_hide_return reason=expanded_command_output")
            return
        }

        NotchOverlayManager.shared.hide()
        self.overlayBench("instant_hide_return")
    }

    // MARK: - Public API for overlay management

    func updateOverlayTranscription(_ text: String) {
        NotchOverlayManager.shared.updateTranscriptionText(text)
    }

    func setOverlayMode(_ mode: OverlayMode) {
        self.overlayBench("set_mode mode=\(mode.rawValue)")
        self.currentOverlayMode = mode
        NotchOverlayManager.shared.setMode(mode)
    }

    func setProcessing(_ processing: Bool) {
        self.overlayBench("set_processing_request processing=\(processing) overlayVisible=\(self.overlayVisible) active=\(self.isProcessingActive)")

        // Track processing state to prevent hide during AI refinement
        self.isProcessingActive = processing
        self.updateMenuItemsText()
        // The outlined square only once the final pass is slow (this call is deferred 250 ms).
        if processing, !self.isRecording {
            self.markKind = .transcribing
            self.applyMark()
        } else if !processing {
            self.refreshMarkKind()
        }

        if processing {
            self.pendingProcessingShowOperation?.cancel()
            // Cancel any pending hide - we want to keep the overlay visible for AI processing
            self.pendingHideOperation?.cancel()
            self.pendingHideOperation = nil
            self.overlayVisible = true

            let showItem = DispatchWorkItem { [weak self] in
                guard let self = self, self.isProcessingActive else { return }
                self.overlayBench("processing_show_workitem_execute delayMs=0")
                NotchOverlayManager.shared.setProcessing(true)
                self.overlayBench("processing_show_workitem_return")
                self.pendingProcessingShowOperation = nil
            }
            self.pendingProcessingShowOperation = showItem
            DispatchQueue.main.asyncAfter(deadline: .now() + self.processingVisualDelay, execute: showItem)
        } else {
            self.pendingProcessingShowOperation?.cancel()
            self.pendingProcessingShowOperation = nil
            // When processing ends, schedule the hide (unless expanded output is showing)
            self.overlayVisible = false

            // If expanded command output is showing, don't hide it
            if NotchOverlayManager.shared.isCommandOutputExpanded {
                self.pendingHideOperation = nil
                NotchOverlayManager.shared.setProcessing(processing)
                self.overlayBench("set_processing_return reason=expanded_command_output")
                return
            }

            let hideItem = DispatchWorkItem { [weak self] in
                guard let self = self, !self.overlayVisible else { return }

                // Don't hide if expanded command output is now showing
                if NotchOverlayManager.shared.isCommandOutputExpanded {
                    self.pendingHideOperation = nil
                    return
                }

                self.overlayBench("processing_hide_workitem_execute delayMs=80")
                NotchOverlayManager.shared.hide()
                self.overlayBench("processing_hide_workitem_return")
                self.pendingHideOperation = nil
            }
            self.pendingHideOperation = hideItem
            DispatchQueue.main.asyncAfter(deadline: .now() + self.processingHideDelay, execute: hideItem)
            NotchOverlayManager.shared.setProcessing(false)
            self.overlayBench("processing_forwarded processing=false hideDelayMs=80")
            return
        }
    }

    /// Keeps the recording overlay owned by the stop pipeline without showing processing yet:
    /// the "Transcribing" status follows only if the final pass is slow (`setProcessing(true)`).
    /// From altic-dev/FluidVoice#950.
    func reserveProcessingOverlay() {
        self.overlayBench("reserve_processing overlayVisible=\(self.overlayVisible) active=\(self.isProcessingActive)")
        self.isProcessingActive = true
        self.pendingProcessingShowOperation?.cancel()
        self.pendingProcessingShowOperation = nil
        self.pendingHideOperation?.cancel()
        self.pendingHideOperation = nil
        self.overlayVisible = true
    }

    /// Hands the stopped dictation's overlay to its outcome hold (Pasted / Sent, or a recovery
    /// card): processing ends and the recording lifecycle is released, so the next recording starts
    /// fresh, but nothing hides here. The overlay dismisses itself when the hold ends.
    func releaseOverlayForOutcomeHold() {
        self.cancelPendingProcessingCompletionOperations()
        self.isProcessingActive = false
        self.overlayVisible = false
        NotchOverlayManager.shared.setProcessing(false)
        self.refreshMarkKind()
        self.overlayBench("release_for_outcome_hold")
    }

    /// Ends processing and waits for the recording overlay's exit transition.
    /// Output paths normally call this asynchronously after insertion dispatch
    /// so the exit animation cannot delay text delivery.
    func finishProcessingAndHideOverlay() async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        self.cancelPendingProcessingCompletionOperations()
        self.isProcessingActive = false
        self.overlayVisible = false
        self.refreshMarkKind()

        NotchOverlayManager.shared.setProcessing(false)
        self.overlayBench("finish_hide_request")
        let hideOutcome = await NotchOverlayManager.shared.hideAndWait()
        self.overlayBench(
            "finish_hide_complete outcome=\(hideOutcome) elapsedMs=\(Int(((ProcessInfo.processInfo.systemUptime - startedAt) * 1000).rounded()))"
        )
    }

    /// Ends processing without dismissing an actionable overlay, such as the
    /// AI fallback state that offers reprocessing and settings actions.
    func finishProcessingKeepingOverlayVisible() {
        self.cancelPendingProcessingCompletionOperations()
        self.isProcessingActive = false
        self.refreshMarkKind()
        // Keep the physical overlay visible, but release recording/processing
        // ownership so the next recording can establish a fresh lifecycle.
        self.overlayVisible = false
        NotchOverlayManager.shared.setProcessing(false)
        self.overlayBench("finish_keep_visible")
    }

    private func cancelPendingProcessingCompletionOperations() {
        self.pendingProcessingShowOperation?.cancel()
        self.pendingProcessingShowOperation = nil
        self.pendingHideOperation?.cancel()
        self.pendingHideOperation = nil
        self.pendingShowOperation?.cancel()
        self.pendingShowOperation = nil
    }

    private func overlayBench(_ message: String) {
        DebugLogger.shared.benchmark("OVERLAY_BENCH", message: "manager \(message)", source: "OverlayBenchmark")
    }

    private func setupMenuBarSafely() {
        do {
            try self.setupMenuBar()
            self.isSetup = true
        } catch {
            // If setup fails, retry after delay
            DebugLogger.shared.error("MenuBar setup failed, retrying: \(error)", source: "MenuBarManager")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setupMenuBarSafely()
            }
        }
    }

    private func setupMenuBar() throws {
        // Ensure we're not already set up
        guard !self.isSetup else { return }

        // Create status item with error handling. Every mark is 22 x 16, so the width never changes.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let statusItem = statusItem else {
            throw NSError(domain: "MenuBarManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create status item"])
        }

        // Set initial icon, and draw the hover bracket inside the mark's box.
        self.applyMark()
        if let button = statusItem.button {
            let tracker = MenuBarMarkHoverTracker { [weak self] hovering in
                self?.isMarkHovered = hovering
                self?.applyMark()
            }
            button.addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: tracker,
                userInfo: nil
            ))
            self.markHoverTracker = tracker
        }

        // Create menu
        self.menu = NSMenu()
        self.menu?.autoenablesItems = false
        self.menu?.delegate = self
        statusItem.menu = self.menu

        self.updateMenu()
    }

    // MARK: - Menu bar mark

    /// Recording started or stopped. Neither redraws the status item on the spot: a status item
    /// image change is a WindowServer round trip, so the listening mark follows on the first 8 Hz
    /// tick (125 ms, off the start path) and the resting mark once the stop has handed its text
    /// off (never on the stop path).
    private func recordingStateChanged(isRunning: Bool) {
        if isRunning {
            self.recordingStartedAt = Date()
            self.startMarkTimer()
        } else {
            self.stopMarkTimer()
            StopPipelineWindowWork.afterHandoff { [weak self] in
                self?.refreshMarkKind()
            }
        }
    }

    private func startMarkTimer() {
        guard self.markTimer == nil else { return }
        let timer = Timer(timeInterval: SignalTheme.Motion.menuBarBars, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.markTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.markTimer = timer
    }

    private func stopMarkTimer() {
        self.markTimer?.invalidate()
        self.markTimer = nil
    }

    /// 8 Hz while listening: the bars follow the trace in 2 pt steps, and hold still during Spoken
    /// Send's countdown (the dictation is not finished until the send resolves).
    private func markTick() {
        // The recording flag reaches this manager one main-queue hop after the stop begins: read
        // the service itself, and never redraw while a stop pipeline runs.
        guard self.isRecording, self.asrService?.isRunning == true, !StopPipelineWindowWork.isHeld else {
            if self.asrService?.isRunning != true { self.stopMarkTimer() }
            return
        }
        self.markKind = .listening
        if SpokenSendController.shared.indicator != .countingDown,
           NotchContentState.shared.isBottomOverlayPresented
        {
            self.markBars = SignalMenuBarMark.listeningBars(from: SignalOverlayModel.shared.trace)
        }
        self.applyMark()
    }

    private func refreshMarkKind() {
        if self.isRecording {
            self.markKind = .listening
        } else if self.isProcessingActive, NotchContentState.shared.isProcessing {
            self.markKind = .transcribing
        } else {
            self.markKind = .idle
            self.markBars = SignalMenuBarMark.restingBars
        }
        self.applyMark()
    }

    /// Sets the mark for the current state. Never while a stop pipeline runs: a status item image
    /// change is a WindowServer round trip, so it waits for the handoff (a slow final pass keeps
    /// the listening mark until then instead of showing the outlined square).
    private func applyMark() {
        guard let button = self.statusItem?.button else { return }
        if StopPipelineWindowWork.isHeld {
            guard !self.hasDeferredMark else { return }
            self.hasDeferredMark = true
            StopPipelineWindowWork.afterHandoff { [weak self] in
                guard let self else { return }
                self.hasDeferredMark = false
                self.refreshMarkKind()
            }
            return
        }
        let image = SignalMenuBarMark.image(
            kind: self.markKind,
            bars: self.markKind == .listening ? self.markBars : SignalMenuBarMark.restingBars,
            bracket: self.isMarkHovered || self.isMenuOpen
        )
        // The images are cached, so an unchanged state costs nothing.
        if button.image !== image {
            button.image = image
        }
    }

    /// The menu (DESIGN.md §10): a plain NSMenu under a mono uppercase header. Start Dictation
    /// with its hotkey, the microphone, History…, then the items the app already had (Copy Last
    /// Transcript, Custom Dictionary, Open Liquid Voice), Settings… and Quit.
    private func buildMenuStructure() {
        guard let menu = menu else { return }

        menu.removeAllItems()

        let header = SignalMenuHeaderView(frame: NSRect(x: 0, y: 0, width: 262, height: 24))
        let headerItem = NSMenuItem()
        headerItem.view = header
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        self.headerView = header
        self.statusMenuItem = headerItem
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(title: "Start Dictation", action: #selector(toggleDictation), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        self.toggleDictationMenuItem = toggleItem

        let microphoneSubmenu = NSMenu(title: "Microphone")
        let microphoneMenuItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        microphoneMenuItem.submenu = microphoneSubmenu
        menu.addItem(microphoneMenuItem)
        self.microphoneMenuItem = microphoneMenuItem
        self.microphoneSubmenu = microphoneSubmenu

        let historyItem = NSMenuItem(title: "History…", action: #selector(openHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        let copyLastTranscriptItem = NSMenuItem(
            title: "Copy Last Transcript",
            action: #selector(copyLastTranscript(_:)),
            keyEquivalent: ""
        )
        copyLastTranscriptItem.target = self
        menu.addItem(copyLastTranscriptItem)
        self.copyLastTranscriptMenuItem = copyLastTranscriptItem

        let customDictionaryItem = NSMenuItem(
            title: "Custom Dictionary",
            action: #selector(openCustomDictionary),
            keyEquivalent: ""
        )
        customDictionaryItem.target = self
        menu.addItem(customDictionaryItem)

        let openItem = NSMenuItem(title: "Open Liquid Voice", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let preferencesItem = NSMenuItem(title: "Settings…", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        preferencesItem.keyEquivalentModifierMask = [.command]
        menu.addItem(preferencesItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Liquid Voice",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)

        // Now update the text content
        self.updateMenuItemsText()
    }

    private func updateMenu() {
        // If menu structure hasn't been built yet, build it
        if self.statusMenuItem == nil {
            self.buildMenuStructure()
        } else {
            // Just update the text of existing items
            self.updateMenuItemsText()
        }
    }

    private func updateMenuItemsText() {
        let live = self.isRecording
        let state: String
        if live {
            let start = self.recordingStartedAt ?? Date()
            state = SpokenSendController.shared.indicator == .countingDown
                ? "Sending"
                : "Listening \(SignalOverlayModel.formatDuration(Date().timeIntervalSince(start)))"
        } else {
            state = self.isProcessingActive ? "Working" : "Ready"
        }
        self.headerView?.stateText = state
        self.headerView?.isLive = live
        self.toggleDictationMenuItem?.attributedTitle = Self.titleWithDetail(
            live ? "Stop Dictation" : "Start Dictation",
            detail: SettingsStore.shared.primaryDictationShortcutDisplayString
        )
        // The microphone's name only while the menu is open: looking it up can touch Core Audio,
        // and this runs on every recording change and processing update.
        if self.isMenuOpen {
            self.microphoneMenuItem?.attributedTitle = Self.titleWithDetail(
                "Microphone",
                detail: BottomOverlayWindowController.currentMicrophoneName()
            )
        }
        self.copyLastTranscriptMenuItem?.isEnabled = self.canCopyLastTranscript
        self.microphoneMenuItem?.isEnabled = true
    }

    /// A menu row with a secondary detail right-aligned after a tab ("Start Dictation  ⌥Space").
    private static func titleWithDetail(_ title: String, detail: String) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 236)]
        let result = NSMutableAttributedString(string: title, attributes: [.font: font, .paragraphStyle: paragraph])
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result.append(NSAttributedString(string: "\t" + trimmed, attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph,
            ]))
        }
        return result
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === self.menu {
            AnalyticsService.shared.recordAppActivity()
            self.isMenuOpen = true
            self.applyMark()
            self.updateMenuItemsText()
            self.refreshMicrophoneMenu()
            self.headerRefreshTimer?.invalidate()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMenuItemsText() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.headerRefreshTimer = timer
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        self.isMenuOpen = false
        self.headerRefreshTimer?.invalidate()
        self.headerRefreshTimer = nil
        self.applyMark()
    }

    @objc private func toggleDictation() {
        self.onToggleDictationRequested?()
    }

    @objc private func openHistory() {
        self.openMainWindow()
        AppNavigationRouter.shared.request(.history)
    }

    private func refreshMicrophoneMenu() {
        guard let submenu = self.microphoneSubmenu else { return }

        submenu.removeAllItems()
        let loadingItem = NSMenuItem(title: "Loading...", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        submenu.addItem(loadingItem)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let inputDevices = AudioDevice.listInputDevicesRefreshingLiveness()
            let defaultInputUID = AudioDevice.getDefaultInputDevice()?.uid

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.populateMicrophoneMenu(
                    inputDevices: inputDevices,
                    defaultInputUID: defaultInputUID
                )
            }
        }
    }

    private func populateMicrophoneMenu(inputDevices: [AudioDevice.Device], defaultInputUID: String?) {
        guard let submenu = self.microphoneSubmenu else { return }

        submenu.removeAllItems()

        guard !inputDevices.isEmpty else {
            let emptyItem = NSMenuItem(title: "No microphones found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
            return
        }

        let microphonePreferenceCoordinator = AppServices.shared.microphonePreferenceCoordinator
        let currentUID = microphonePreferenceCoordinator.reconcileMicrophoneSelection(
            availableInputs: inputDevices,
            defaultInputUID: defaultInputUID
        )?.uid

        guard SettingsStore.shared.microphonePriority.isEmpty == false else {
            let emptyItem = NSMenuItem(title: "No microphones in priority", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
            return
        }

        let devicesByUID = Dictionary(
            inputDevices.map { ($0.uid, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        for (index, entry) in SettingsStore.shared.microphonePriority.enumerated() {
            guard let device = devicesByUID[entry.uid],
                  microphonePreferenceCoordinator.isInputDeviceAvailable(device)
            else {
                let item = NSMenuItem(
                    title: "\(index + 1). \(entry.name) (Unavailable)",
                    action: nil,
                    keyEquivalent: ""
                )
                item.isEnabled = false
                submenu.addItem(item)
                continue
            }
            let title = "\(index + 1). \(device.name)"
            let item = NSMenuItem(title: title, action: #selector(selectMicrophone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device
            item.state = device.uid == currentUID ? .on : .off
            item.isEnabled = !self.isRecording
            submenu.addItem(item)
        }

        if self.isRecording {
            submenu.addItem(.separator())
            let recordingItem = NSMenuItem(title: "Unavailable while recording", action: nil, keyEquivalent: "")
            recordingItem.isEnabled = false
            submenu.addItem(recordingItem)
        }
    }

    private var canCopyLastTranscript: Bool {
        !self.isProcessingActive && TranscriptionHistoryStore.shared.latestClipboardText != nil
    }

    @objc private func copyLastTranscript(_ sender: Any?) {
        guard self.canCopyLastTranscript,
              let text = TranscriptionHistoryStore.shared.latestClipboardText
        else {
            DebugLogger.shared.info("Menu action: Copy last transcript requested but history is empty", source: "MenuBarManager")
            return
        }

        _ = ClipboardService.copyToClipboard(text)
        DebugLogger.shared.info("Menu action: Copied latest transcription to clipboard", source: "MenuBarManager")
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard self.isRecording == false else { return }
        guard let device = sender.representedObject as? AudioDevice.Device else { return }

        SettingsStore.shared.recordInputDeviceSelection(device.uid, name: device.name)

        self.refreshMicrophoneMenu()
    }

    @objc private func openMainWindow() {
        // First, unhide the app if it's hidden
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }

        // Activate the app and bring it to the front
        NSApp.activate(ignoringOtherApps: true)

        var mainWindows = NSApp.windows.filter(self.isFluidMainWindow)
        if let hostedWindow,
           mainWindows.contains(where: { $0 !== hostedWindow })
        {
            hostedWindow.close()
            self.hostedWindow = nil
            mainWindows = NSApp.windows.filter(self.isFluidMainWindow)
        }

        // Find an existing *non-minimized* primary window.
        // Important: avoid programmatic deminiaturize() — it creates internal window transform animations
        // (NSWindowTransformAnimation) that have been unstable on macOS 26.x for this app.
        if let window = mainWindows.first {
            self.ensureUsableMainWindow(window)
            window.animationBehavior = .none
            self.bringToFront(window)
            if let hostedWindow, window !== hostedWindow {
                self.hostedWindow = nil
            }
        } else if let window = hostedWindow, window.isReleasedWhenClosed == false {
            self.ensureUsableMainWindow(window)
            window.animationBehavior = .none
            self.bringToFront(window)
        } else {
            // If there is no suitable window (or it's minimized), create a fresh one.
            self.createAndShowMainWindow()
        }

        // Final attempt: ensure app is active and visible
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func isFluidMainWindow(_ window: NSWindow) -> Bool {
        guard window.level == .normal else { return false }
        guard window.styleMask.contains(.titled) else { return false }
        guard window.canBecomeKey else { return false }
        guard window.isMiniaturized == false else { return false }
        return window.title == "Liquid Voice" || window.title.contains("Liquid Voice")
    }

    @objc private func openPreferences() {
        self.openNavigationDestination(.preferences)
    }

    @objc private func openCustomDictionary() {
        self.openNavigationDestination(.customDictionary)
    }

    private func openNavigationDestination(_ destination: MenuBarNavigationDestination) {
        self.navigationRequestGeneration &+= 1
        let requestGeneration = self.navigationRequestGeneration
        // Ensure a fresh one-shot request every time the menu item is clicked.
        self.requestedNavigationDestination = nil
        self.requestedNavigationDestination = destination

        self.openMainWindow()

        // Nudge again after the window is front-most, so an already-open ContentView
        // will still switch tabs even if it consumed a previous navigation request.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.navigationRequestGeneration == requestGeneration else { return }
            self.requestedNavigationDestination = nil
            self.requestedNavigationDestination = destination
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self,
                      self.navigationRequestGeneration == requestGeneration,
                      self.requestedNavigationDestination == destination
                else { return }
                self.requestedNavigationDestination = nil
            }
        }
    }

    /// Public entry-point for non-menu UI surfaces (e.g. overlay controls) to open Preferences.
    func openPreferencesFromUI() {
        self.openPreferences()
    }

    func openMicrophoneSettingsFromUI() {
        self.openNavigationDestination(.microphoneSettings)
    }

    /// Create and present a fresh main window hosting `ContentView`
    private func createAndShowMainWindow() {
        // Build the SwiftUI root view with required environment
        let rootView = AdaptiveAppTheme(accent: SettingsStore.shared.accentColor) {
            ContentView()
                .environmentObject(self)
                .environmentObject(AppServices.shared)
        }

        // Host inside an AppKit window
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Liquid Voice"
        window.animationBehavior = .none
        window.minSize = self.mainWindowMinimumSize
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.setFrame(self.defaultWindowFrame(), display: false)
        self.bringToFront(window)
        self.hostedWindow = window

        // Bring app to front in case we're running as an accessory app (no Dock)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func ensureUsableMainWindow(_ window: NSWindow) {
        // If the window is too small (e.g., height collapsed), reset to the default frame.
        let minSize = self.mainWindowMinimumSize
        window.minSize = minSize

        let frame = window.frame
        if frame.height < minSize.height || frame.width < minSize.width {
            window.setFrame(self.defaultWindowFrame(), display: false)
        }
    }

    private func defaultWindowFrame() -> NSRect {
        // Center a sensible default frame on the main screen.
        let size = NSSize(width: 1000, height: 700)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let origin = NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        )
        return NSRect(origin: origin, size: size)
    }

    private var mainWindowMinimumSize: NSSize {
        let window = AppTheme.dark.metrics.window
        return NSSize(width: window.mainMinWidth, height: window.mainMinHeight)
    }

    private func bringToFront(_ window: NSWindow) {
        // Keep ordering explicit to avoid "opened but behind other apps" behavior.
        if window.alphaValue <= 0.01 {
            window.alphaValue = 1
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Reports the pointer entering and leaving the status item, for the mark's hover bracket.
private final class MenuBarMarkHoverTracker: NSResponder {
    private let onChange: (Bool) -> Void

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func mouseEntered(with event: NSEvent) {
        self.onChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        self.onChange(false)
    }
}
