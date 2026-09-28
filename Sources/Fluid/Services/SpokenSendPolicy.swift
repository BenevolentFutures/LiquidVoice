import AppKit
import Carbon.HIToolbox
import Foundation

// Where Spoken Send may press its key, and how the key is pressed.
//
// Upstream (altic-dev/FluidVoice@c679506d, @9778fe46) blocks Spoken Send in every terminal,
// because Return in a shell runs a command. Liquid Voice keeps that block list and adds an
// allow list checked first: c11, where Atin dictates Claude Code prompts all day. c11 is
// allowed by its bundle ID even when its name or identity would match a blocked term.

/// Which apps get the Spoken Send key. Pure, so the c11 carve-out is tested.
nonisolated enum SpokenSendPolicy {
    enum Verdict: String, Equatable, Sendable {
        /// An ordinary app: the key follows the text.
        case allowed
        /// c11, on the allow list, with "Allow in c11" on.
        case allowedC11 = "allowed_c11"
        /// c11 with "Allow in c11" turned off.
        case c11Disabled = "c11_disabled"
        /// A terminal: Return would run a shell command. The text still lands.
        case blockedTerminal = "blocked_terminal"

        var allowsSend: Bool {
            self == .allowed || self == .allowedC11
        }
    }

    /// Checked before the block list: c11 and its own builds ("com.stage11.c11.<variant>").
    static let c11BundleIdentifier = "com.stage11.c11"

    static func isC11(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return bundleIdentifier == self.c11BundleIdentifier || bundleIdentifier.hasPrefix(self.c11BundleIdentifier + ".")
    }

    /// Upstream's block list, matched against "<app name> <bundle ID>" in lowercase.
    static let blockedIdentityTerms = ["terminal", "iterm", "warp", "ghostty", "kitty", "alacritty", "wezterm", "tabby"]

    /// Terminals whose name and bundle ID carry none of the terms above.
    static let blockedBundleIdentifiers: Set<String> = ["co.zeit.hyper", "com.raphaelamorim.rio"]

    static func verdict(bundleIdentifier: String?, appName: String?, allowsC11: Bool) -> Verdict {
        if self.isC11(bundleIdentifier: bundleIdentifier) {
            return allowsC11 ? .allowedC11 : .c11Disabled
        }
        if let bundleIdentifier, self.blockedBundleIdentifiers.contains(bundleIdentifier) {
            return .blockedTerminal
        }
        let identity = "\(appName ?? "") \(bundleIdentifier ?? "")".lowercased()
        if self.blockedIdentityTerms.contains(where: { identity.contains($0) }) {
            return .blockedTerminal
        }
        return .allowed
    }

    /// c11 or a blocked terminal: the text before the phrase is a prompt or a command, so the
    /// parser adds no sentence ending ("/compact", not "/compact.").
    static func isTerminal(bundleIdentifier: String?, appName: String?) -> Bool {
        self.verdict(bundleIdentifier: bundleIdentifier, appName: appName, allowsC11: true) != .allowed
    }

    /// The key actually pressed. c11 always gets a plain Return: it is what submits a Claude
    /// Code prompt, and Command + Return is a terminal binding (full screen in Ghostty).
    static func effectiveKey(_ key: SettingsStore.SpokenSendKey, verdict: Verdict) -> SettingsStore.SpokenSendKey {
        verdict == .allowedC11 ? .enter : key
    }
}

/// The key Spoken Send presses after a delivery, and the destination it belongs to.
nonisolated struct SendKeyRequest: @unchecked Sendable {
    let key: SettingsStore.SpokenSendKey
    /// The destination chosen when dictation stopped. The key goes to its PID only.
    let target: DictationTarget
}

/// What became of the send key. Only `.sent` means a key was posted.
nonisolated enum SendKeyOutcome: String, Equatable, Sendable {
    case sent
    /// The text did not go, so no key was pressed (the failure card covers the text).
    case textNotDelivered = "text_not_delivered"
    /// The target was not in front when the key was due. Nothing was pressed.
    case targetNotInFront = "target_not_in_front"
    /// Focus in the target is certainly not a text field (a button, a menu).
    case focusNotEditable = "focus_not_editable"
    /// Focus is a password field.
    case secureField = "secure_field"
    /// A modifier key was still held: the key would have become a shortcut.
    case modifiersHeld = "modifiers_held"
    /// The user pressed a key or clicked after the text went out (another c11 pane, say): the
    /// key could land where they moved to, so it is dropped.
    case userActed = "user_acted"
    /// The delivery went to another process than the send key's target.
    case targetMismatch = "target_mismatch"
    case eventsUnavailable = "events_unavailable"

    var wasSent: Bool {
        self == .sent
    }
}

/// The send key's CGEvents. Created by this process, so the hotkey tap passes them through by
/// their source PID (`GlobalHotkeyManager.isSelfPostedKeyboardEvent`); also tagged like the
/// paste events for diagnostics.
nonisolated enum SendKeyEvents {
    static func make(_ key: SettingsStore.SpokenSendKey) -> [CGEvent] {
        let returnKeyCode = CGKeyCode(kVK_Return)
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: returnKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: returnKeyCode, keyDown: false)
        else {
            return []
        }
        // Explicit flags: a nil-source event would otherwise inherit whatever modifier is held.
        keyDown.flags = key.eventFlags
        keyUp.flags = key.eventFlags
        for event in [keyDown, keyUp] {
            event.setIntegerValueField(.eventSourceUserData, value: PasteCommandEvents.synthesizedEventUserData)
        }
        return [keyDown, keyUp]
    }

    /// Posts key down and key up straight to `pid`, like the terminal paste.
    static func post(_ key: SettingsStore.SpokenSendKey, to pid: pid_t) -> Bool {
        let events = self.make(key)
        guard events.count == 2 else { return false }
        events[0].postToPid(pid)
        usleep(10_000)
        events[1].postToPid(pid)
        return true
    }
}

/// One send-key press, as the typing worker performs it. Dependencies are injectable so the
/// ordering and at-most-once guarantees are tested without posting keystrokes.
nonisolated struct SendKeyStep {
    /// How long after the paste the key waits, so the target has taken the paste in first (a
    /// terminal app then reads the Return as its own keystroke, not part of the paste).
    static let defaultDelay: TimeInterval = 0.15
    /// How long a still-held modifier may delay the key before the send is dropped.
    static let modifierReleaseTimeout: TimeInterval = 2

    let key: SettingsStore.SpokenSendKey
    var delay: TimeInterval = SendKeyStep.defaultDelay
    /// Waits briefly for the physical modifier keys to be released; false when still held.
    var modifiersReleased: () -> Bool = { TypingService.waitForPhysicalModifierRelease(timeout: SendKeyStep.modifierReleaseTimeout) }
    /// Whether the user pressed a key or clicked since the given system uptime (the paste).
    /// Modifier presses and mouse moves do not count.
    var userActedSince: (TimeInterval) -> Bool = { since in
        PasteVerifier.userActedAfterPaste(
            secondsSinceLastInput: PasteVerifier.secondsSinceLastUserInput(),
            secondsSincePaste: ProcessInfo.processInfo.systemUptime - since
        )
    }
    /// Posts key down and key up to the PID; false when the events could not be made.
    var post: (pid_t, SettingsStore.SpokenSendKey) -> Bool = { SendKeyEvents.post($1, to: $0) }

    init(key: SettingsStore.SpokenSendKey) {
        self.key = key
    }
}
