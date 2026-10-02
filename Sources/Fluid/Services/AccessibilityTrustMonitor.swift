import AppKit
import ApplicationServices
import AVFoundation
import Combine
import Foundation
import Security

// MARK: - Hotkey event tap install policy

/// Where the keyboard event tap stands. The raw values are what `HOTKEY_TAP state=` logs.
nonisolated enum HotkeyTapState: String, Equatable, Sendable {
    /// Nothing tried yet (the manager's start-up delay).
    case idle
    /// Accessibility is on but the last tap creation failed; a fast retry is pending.
    case installing
    /// macOS does not trust this process yet. Hotkeys are paused until it does.
    case waitingForAccessibility = "waiting_for_accessibility"
    /// The tap is live.
    case installed
    /// Accessibility is on, yet macOS refused the tap after every fast retry. Usually a grant
    /// recorded for an older build of the app; a relaunch (or re-adding the app) clears it.
    case failedTrusted = "failed_trusted"

    /// Configured hotkeys exist but cannot fire because of permissions.
    var isPausedForPermission: Bool {
        self == .waitingForAccessibility || self == .failedTrusted
    }
}

/// The retry rules for installing the keyboard event tap. Pure, so the backoff and the state
/// transitions are unit-tested without an event tap.
///
/// - Untrusted: poll trust with a backoff of 0.5, 1, then every 2 s, forever (checking trust is
///   cheap, and a grant made in System Settings must arm hotkeys without a relaunch). The
///   manager also retries at once when trust flips or the app is re-activated.
/// - Trusted but the tap fails: four fast retries (0.5, 1, 2, 4 s), then `failedTrusted`, which
///   retries every 30 s in case macOS comes round.
/// - Only a change of state is logged (`transitioned`), so a long wait is one log line.
nonisolated struct HotkeyTapInstallPolicy: Equatable {
    enum Outcome: Equatable {
        case installed
        case untrusted
        case tapFailed
    }

    struct Step: Equatable {
        let state: HotkeyTapState
        /// Consecutive attempts that ended in this state (1-based; 0 once installed).
        let attempt: Int
        /// When to try again, or nil when no retry is needed.
        let retryAfter: TimeInterval?
        /// True when `state` differs from the state before this attempt.
        let transitioned: Bool
    }

    static let untrustedRetryDelays: [TimeInterval] = [0.5, 1, 2]
    static let trustedRetryDelays: [TimeInterval] = [0.5, 1, 2, 4]
    static let failedTrustedRetryDelay: TimeInterval = 30

    private(set) var state: HotkeyTapState = .idle
    private(set) var attempt = 0

    mutating func record(_ outcome: Outcome) -> Step {
        let previous = self.state
        let retryAfter: TimeInterval?
        switch outcome {
        case .installed:
            self.state = .installed
            self.attempt = 0
            retryAfter = nil
        case .untrusted:
            self.attempt = previous == .waitingForAccessibility ? self.attempt + 1 : 1
            self.state = .waitingForAccessibility
            let delays = Self.untrustedRetryDelays
            retryAfter = delays[min(self.attempt, delays.count) - 1]
        case .tapFailed:
            let continuing = previous == .installing || previous == .failedTrusted
            self.attempt = continuing ? self.attempt + 1 : 1
            let delays = Self.trustedRetryDelays
            if self.attempt > delays.count {
                self.state = .failedTrusted
                retryAfter = Self.failedTrustedRetryDelay
            } else {
                self.state = .installing
                retryAfter = delays[self.attempt - 1]
            }
        }
        return Step(state: self.state, attempt: self.attempt, retryAfter: retryAfter, transitioned: self.state != previous)
    }

    /// The `HOTKEY_TAP` log line for a step.
    static func logLine(for step: Step, reason: String) -> String {
        var line = "HOTKEY_TAP state=\(step.state.rawValue) attempt=\(step.attempt) reason=\(reason)"
        if let retry = step.retryAfter {
            line += " retry_in=\(String(format: "%.1f", retry))s"
        }
        return line
    }
}

// MARK: - The "switched on but not working" hint

/// What a permission step or card should add below its usual content.
nonisolated enum AccessibilityHint: Equatable, Sendable {
    case none
    /// Untrusted although the user has been to System Settings (or the app was trusted before):
    /// macOS may be holding an entry for an older build. Remove it and add the app again.
    case staleGrant
    /// As `staleGrant`, and other copies of this bundle ID signed by someone else are registered
    /// with LaunchServices. System Settings may record one of those copies' code requirement when
    /// the switch is flipped, so the switch shows on and never matches this binary until they are
    /// deleted (2026-10-02: ~/.Trash, a SwiftUI drag cache and a DerivedData Release build).
    case conflictingCopies
    /// Trusted, but the event tap still cannot be created. A relaunch clears it.
    case relaunch
}

nonisolated enum AccessibilityHintPolicy {
    /// How long after the user comes back from System Settings before we suggest the stale-entry
    /// fix. Long enough for a fresh grant to register (the poll runs every 0.5 s), short enough
    /// that the user is still looking.
    static let settleDelay: TimeInterval = 3

    static let staleGrantHeadline = "Already switched on?"
    static let staleGrantBody =
        "macOS may be holding an entry for an older copy. In Accessibility settings, select MouthKeys, click −, then add it again."
    static let relaunchHeadline = "Accessibility is on, but hotkeys could not start"
    static let relaunchBody = "macOS usually needs MouthKeys to relaunch once after a new build is allowed."
    static let pausedSummary = "Hotkeys paused: needs Accessibility"
    static let conflictingCopiesHeadline = "An older copy of MouthKeys is confusing macOS"
    static let conflictingCopiesBody =
        "Delete it (and empty the Trash), then switch MouthKeys off and on again in Accessibility settings."

    /// - Parameters:
    ///   - returnedFromSettingsAt: uptime when the app was re-activated after a visit to System
    ///     Settings, nil if that has not happened since the last grant.
    ///   - wasTrustedBefore: this app (this bundle identifier) has seen itself trusted before.
    static func hint(
        isTrusted: Bool,
        tapState: HotkeyTapState,
        wasTrustedBefore: Bool,
        returnedFromSettingsAt: TimeInterval?,
        now: TimeInterval,
        conflictingCopyCount: Int = 0
    ) -> AccessibilityHint {
        if isTrusted {
            return tapState == .failedTrusted ? .relaunch : .none
        }
        let looksStuck: Bool
        if wasTrustedBefore {
            looksStuck = true
        } else if let returned = returnedFromSettingsAt, now - returned >= self.settleDelay {
            looksStuck = true
        } else {
            looksStuck = false
        }
        guard looksStuck else { return .none }
        return conflictingCopyCount > 0 ? .conflictingCopies : .staleGrant
    }
}

// MARK: - Conflicting copies of this bundle ID

/// Finds other registered copies of this app's bundle ID whose code requirement the running
/// binary does not satisfy. A TCC grant recorded for one of them never matches us (tccd logs
/// "Failed to match existing code requirement"). Read-only: it never deletes anything.
nonisolated enum ConflictingAppCopyDetector {
    /// - Parameters:
    ///   - ownURL: the running bundle, always excluded.
    ///   - candidates: every URL LaunchServices lists for our bundle ID.
    ///   - exists: whether a path is still on disk (LaunchServices keeps stale records).
    ///   - ownCodeSatisfiesRequirement: whether the running code satisfies that copy's
    ///     designated requirement; nil when it cannot be read (unsigned, unreadable), which is
    ///     not reported as a conflict.
    static func conflictingCopies(
        ownURL: URL,
        candidates: [URL],
        exists: (URL) -> Bool,
        ownCodeSatisfiesRequirement: (URL) -> Bool?
    ) -> [URL] {
        let own = self.normalized(ownURL)
        var seen: Set<String> = [own]
        var result: [URL] = []
        for candidate in candidates {
            let path = self.normalized(candidate)
            guard seen.insert(path).inserted else { continue }
            guard exists(candidate) else { continue }
            if ownCodeSatisfiesRequirement(candidate) == false {
                result.append(candidate)
            }
        }
        return result
    }

    /// `~/...` for display and logs.
    static func displayPath(_ url: URL, home: String = NSHomeDirectory()) -> String {
        let path = url.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func logLine(conflicts: [URL], home: String = NSHomeDirectory()) -> String {
        let paths = conflicts.map { self.displayPath($0, home: home) }.joined(separator: " | ")
        return "PERMISSION_DIAG conflicting_copies=\(conflicts.count) paths=\(paths.isEmpty ? "-" : paths)"
    }

    private static func normalized(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Scans for other copies of this process's bundle ID. Call off the main thread.
    ///
    /// LaunchServices' own lookups skip copies in the Trash, yet tccd matched a grant against one
    /// (2026-10-02), so the Trash and SwiftUI's drag caches are listed by hand and Spotlight
    /// covers the rest (DerivedData Release builds, backups).
    static func scanRegisteredCopies() -> [URL] {
        guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var candidates = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID)
        candidates += self.appBundles(
            in: [home.appendingPathComponent(".Trash")] + self.dragCacheDirectories(home: home),
            matching: bundleID
        )
        candidates += self.spotlightCopies(of: bundleID)
        return self.conflictingCopies(
            ownURL: Bundle.main.bundleURL,
            candidates: candidates,
            exists: { FileManager.default.fileExists(atPath: $0.path) },
            ownCodeSatisfiesRequirement: { self.runningCodeSatisfiesDesignatedRequirement(of: $0) }
        )
    }

    /// `.app` bundles directly inside `directories` whose Info.plist names `bundleID`.
    static func appBundles(in directories: [URL], matching bundleID: String) -> [URL] {
        let fileManager = FileManager.default
        var result: [URL] = []
        for directory in directories {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsSubdirectoryDescendants]
            ) else { continue }
            for entry in entries where entry.pathExtension == "app" {
                if self.bundleIdentifier(of: entry) == bundleID {
                    result.append(entry)
                }
            }
        }
        return result
    }

    static func bundleIdentifier(of appURL: URL) -> String? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) else { return nil }
        return info["CFBundleIdentifier"] as? String
    }

    private static func dragCacheDirectories(home: URL) -> [URL] {
        let caches = home.appendingPathComponent("Library/Caches")
        let entries = (try? FileManager.default.contentsOfDirectory(at: caches, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { $0.lastPathComponent.hasPrefix("com.apple.SwiftUI.Drag-") }
    }

    /// `mdfind` for the bundle ID, bounded to 5 s.
    private static func spotlightCopies(of bundleID: String) -> [URL] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemCFBundleIdentifier == '\(bundleID)'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        // Read on another thread so a full pipe can never stall the wait.
        let output = SpotlightOutput()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output.data = pipe.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        guard done.wait(timeout: .now() + 5) == .success else {
            process.terminate()
            return []
        }
        return String(decoding: output.data, as: UTF8.self)
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) }
            .filter { $0.pathExtension == "app" }
    }

    /// Whether this process satisfies the designated requirement of the bundle at `url`. That is
    /// the check tccd makes against a grant recorded for that copy.
    static func runningCodeSatisfiesDesignatedRequirement(of url: URL) -> Bool? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement else {
            return nil
        }
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else {
            return nil
        }
        return SecCodeCheckValidity(selfCode, [], requirement) == errSecSuccess
    }
}

private nonisolated final class SpotlightOutput: @unchecked Sendable {
    var data = Data()
}

// MARK: - Relaunch

nonisolated enum AppRelauncher {
    /// A shell script that waits (at most 10 s) for `pid` to exit, then opens the bundle again.
    /// Opening only after the old process is gone keeps two copies of one bundle from running.
    static func relaunchArguments(bundlePath: String, pid: Int32) -> [String] {
        let script = "for _ in $(seq 1 50); do kill -0 \"$1\" 2>/dev/null || break; sleep 0.2; done; /usr/bin/open \"$0\""
        return ["-c", script, bundlePath, String(pid)]
    }

    /// Relaunches the running app: spawns the waiter, then terminates.
    @MainActor
    static func relaunch(reason: String) {
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        DebugLogger.shared.info("APP_RELAUNCH reason=\(reason) path=\(bundlePath)", source: "AppRelauncher")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = self.relaunchArguments(bundlePath: bundlePath, pid: pid)
        do {
            try process.run()
        } catch {
            DebugLogger.shared.error("APP_RELAUNCH failed to spawn: \(error.localizedDescription)", source: "AppRelauncher")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Live permission state

/// The one live source of Accessibility and Microphone permission state for the UI.
///
/// While any permission surface is on screen (`beginObserving`), it re-reads both every 0.5 s,
/// and always on app activation, so a grant turns its step green within about a second without
/// a relaunch. The hotkey manager reports its tap state here and listens for trust flips to arm
/// the tap at once. In the XCTest host it observes nothing.
@MainActor
final class AccessibilityTrustMonitor: ObservableObject {
    static let shared = AccessibilityTrustMonitor()

    static let trustedOnceKey = "LiquidVoiceAccessibilityTrustedOnce"
    static let pollInterval: TimeInterval = 0.5
    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    private nonisolated static let systemSettingsBundleIDs: Set<String> = ["com.apple.systempreferences", "com.apple.SystemSettings"]

    @Published private(set) var isTrusted: Bool
    @Published private(set) var microphoneStatus: AVAuthorizationStatus
    @Published private(set) var hotkeyTapState: HotkeyTapState = .idle
    @Published private(set) var hint: AccessibilityHint = .none
    /// Other registered copies of our bundle ID we do not satisfy (see `ConflictingAppCopyDetector`).
    @Published private(set) var conflictingCopies: [URL] = []

    private let trustProvider: () -> Bool
    private let microphoneStatusProvider: () -> AVAuthorizationStatus
    private let clock: () -> TimeInterval
    private let defaults: UserDefaults
    private var observerCount = 0
    private var pollTimer: Timer?
    private var settingsVisitedAt: TimeInterval?
    private var returnedFromSettingsAt: TimeInterval?
    private var notificationTokens: [NSObjectProtocol] = []
    private let conflictScanner: () -> [URL]
    private var conflictScanInFlight = false
    private var lastConflictLog: String?

    init(
        trustProvider: @escaping () -> Bool = { AXIsProcessTrusted() },
        microphoneStatusProvider: @escaping () -> AVAuthorizationStatus = { AVCaptureDevice.authorizationStatus(for: .audio) },
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        defaults: UserDefaults = .standard,
        observeSystem: Bool = !TestHostQuietMode.isActive,
        conflictScanner: @escaping () -> [URL] = { ConflictingAppCopyDetector.scanRegisteredCopies() }
    ) {
        self.conflictScanner = conflictScanner
        self.trustProvider = trustProvider
        self.microphoneStatusProvider = microphoneStatusProvider
        self.clock = clock
        self.defaults = defaults
        self.isTrusted = trustProvider()
        self.microphoneStatus = microphoneStatusProvider()
        if self.isTrusted {
            defaults.set(true, forKey: Self.trustedOnceKey)
        }
        if observeSystem {
            self.installSystemObservers()
        }
        self.recomputeHint()
        if observeSystem, !self.isTrusted, self.wasTrustedBefore {
            self.scanForConflictingCopies()
        }
    }

    var wasTrustedBefore: Bool {
        self.defaults.bool(forKey: Self.trustedOnceKey)
    }

    /// A permission surface appeared: poll while at least one is on screen.
    func beginObserving() {
        self.observerCount += 1
        self.refresh()
        guard self.pollTimer == nil, !TestHostQuietMode.isActive else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.pollTimer = timer
    }

    func endObserving() {
        self.observerCount = max(0, self.observerCount - 1)
        if self.observerCount == 0 {
            self.pollTimer?.invalidate()
            self.pollTimer = nil
        }
    }

    /// Re-reads both permissions now.
    func refresh() {
        let trusted = self.trustProvider()
        if trusted != self.isTrusted {
            DebugLogger.shared.info("ACCESSIBILITY trusted=\(trusted)", source: "AccessibilityTrustMonitor")
            self.isTrusted = trusted
        }
        if trusted {
            if !self.wasTrustedBefore {
                self.defaults.set(true, forKey: Self.trustedOnceKey)
            }
            self.settingsVisitedAt = nil
            self.returnedFromSettingsAt = nil
            if !self.conflictingCopies.isEmpty {
                self.conflictingCopies = []
            }
        }
        let microphone = self.microphoneStatusProvider()
        if microphone != self.microphoneStatus {
            DebugLogger.shared.info("MICROPHONE_PERMISSION status=\(microphone.rawValue)", source: "AccessibilityTrustMonitor")
            self.microphoneStatus = microphone
        }
        self.recomputeHint()
    }

    /// The app opened Accessibility settings for the user.
    func noteOpenedAccessibilitySettings() {
        self.noteSettingsVisit()
    }

    /// The user came back to the app. Public for tests; the activation observer calls it.
    func noteAppActivated() {
        if self.settingsVisitedAt != nil, self.returnedFromSettingsAt == nil, !self.isTrusted {
            self.returnedFromSettingsAt = self.clock()
            self.scanForConflictingCopies()
        }
        self.refresh()
    }

    /// System Settings came to the front. Public for tests; the workspace observer calls it.
    func noteSettingsVisit() {
        guard !self.isTrusted else { return }
        self.settingsVisitedAt = self.clock()
        self.returnedFromSettingsAt = nil
        self.recomputeHint()
    }

    func reportHotkeyTapState(_ state: HotkeyTapState) {
        if state != self.hotkeyTapState {
            self.hotkeyTapState = state
        }
        // The manager checks trust itself; when it disagrees with us, re-read now.
        if (state == .waitingForAccessibility) == self.isTrusted {
            self.refresh()
        } else {
            self.recomputeHint()
        }
    }

    func openAccessibilitySettings() {
        self.noteOpenedAccessibilitySettings()
        if let url = Self.accessibilitySettingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    /// Looks for other registered copies of our bundle ID, off the main thread. Logs the result
    /// once per distinct finding (`PERMISSION_DIAG`).
    func scanForConflictingCopies() {
        guard !self.conflictScanInFlight else { return }
        self.conflictScanInFlight = true
        let scanner = self.conflictScanner
        Task.detached(priority: .utility) { [weak self] in
            let found = scanner()
            await MainActor.run { [weak self] in
                self?.applyConflictScan(found)
            }
        }
    }

    func applyConflictScan(_ found: [URL]) {
        self.conflictScanInFlight = false
        let line = ConflictingAppCopyDetector.logLine(conflicts: found)
        if line != self.lastConflictLog {
            self.lastConflictLog = line
            if found.isEmpty {
                DebugLogger.shared.info(line, source: "AccessibilityTrustMonitor")
            } else {
                DebugLogger.shared.warning(line, source: "AccessibilityTrustMonitor")
            }
        }
        if found != self.conflictingCopies {
            self.conflictingCopies = self.isTrusted ? [] : found
        }
        self.recomputeHint()
    }

    private func recomputeHint() {
        let hint = AccessibilityHintPolicy.hint(
            isTrusted: self.isTrusted,
            tapState: self.hotkeyTapState,
            wasTrustedBefore: self.wasTrustedBefore,
            returnedFromSettingsAt: self.returnedFromSettingsAt,
            now: self.clock(),
            conflictingCopyCount: self.conflictingCopies.count
        )
        if hint != self.hint {
            DebugLogger.shared.info("PERMISSION_HINT hint=\(hint)", source: "AccessibilityTrustMonitor")
            self.hint = hint
        }
    }

    private func installSystemObservers() {
        let center = NotificationCenter.default
        self.notificationTokens.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteAppActivated() }
        })
        self.notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let bundleID = app?.bundleIdentifier, Self.systemSettingsBundleIDs.contains(bundleID) else { return }
            MainActor.assumeIsolated { self?.noteSettingsVisit() }
        })
    }
}
