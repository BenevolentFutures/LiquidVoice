import AppKit
import CoreFoundation
import Foundation
import ServiceManagement

/// Where the migration writes UserDefaults: `UserDefaults`, or a test double that loses writes.
nonisolated protocol AppIdentityMigrationDefaults: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func synchronize() -> Bool
}

nonisolated extension UserDefaults: AppIdentityMigrationDefaults {}

/// One-time copy of FluidVoice-era data on the first launch of Liquid Voice's own identity.
///
/// Liquid Voice ran as `com.FluidApp.app`, with its files in `Application Support/FluidVoice`,
/// until it became its own app (`com.stage11.liquidvoice`, folder `LiquidVoice`). macOS keys
/// UserDefaults by bundle identifier, so without this the new app would start empty. On the
/// first launch of the installed app it:
///
/// 1. copies every UserDefaults key of the old domain (transcription history, custom dictionary,
///    hotkeys, settings) into this app's domain, checks each one, and only then sets a marker, so
///    it never runs twice. The old values win: anything this app's domain already held that the
///    copy changes is saved to a plist in `~/Backups` first. A failed copy is logged and retried
///    once on the next launch; a retry that displaced data and still failed stops retrying and
///    says so in an alert before the app starts (see `haltAlert`).
/// 2. copies (never moves) the old Application Support folder, kept dictation and saved audio
///    included. The old files win here too: a different file already in this app's folder is
///    moved to `~/Backups/liquid-voice-displaced-folder-*` before the old one replaces it. Files
///    only this app has stay. Symbolic links are not followed, and an unreadable old file is
///    skipped with a warning rather than retried forever.
/// 3. registers this app as a login item when the old one launched at startup. The old app's
///    registration belongs to its bundle identifier; only the user can remove it.
///
/// It never writes to the old domain or folder, so the previous app still runs from a backup
/// (rollback). Model caches (`Application Support/FluidAudio`) belong to the FluidAudio library,
/// are not tied to the bundle identifier, and stay where they are. Log lines carry counts,
/// outcomes and key or file names, never content: grep for `IDENTITY_MIGRATION`.
nonisolated struct AppIdentityMigration {
    /// Set once every UserDefaults key has been copied and checked.
    static let defaultsMarkerKey = "LiquidVoiceIdentityMigrationDefaults"
    /// Set once the Application Support step is settled.
    static let folderMarkerKey = "LiquidVoiceIdentityMigrationFolder"
    /// How many times the defaults step has started.
    static let defaultsAttemptsKey = "LiquidVoiceIdentityMigrationDefaultsAttempts"
    /// Set when the defaults step stopped retrying (a retry displaced data and still failed).
    static let defaultsHaltedKey = "LiquidVoiceIdentityMigrationDefaultsHalted"
    /// Every file that values or files displaced by the migration were saved to.
    static let displacedBackupsKey = "LiquidVoiceIdentityMigrationDisplacedBackups"
    static let launchAtStartupKey = "LaunchAtStartup"
    static let logPrefix = "IDENTITY_MIGRATION"
    static let logPath = "~/Library/Logs/LiquidVoice/Fluid.log"
    private static let bookkeepingKeys: Set<String> = [
        defaultsMarkerKey, folderMarkerKey, defaultsAttemptsKey, defaultsHaltedKey, displacedBackupsKey,
    ]

    enum DefaultsOutcome: Equatable {
        case alreadyDone
        /// `replaced`: keys this app's domain already had. `displacedBackup`: the file their
        /// earlier values were saved to, when any of them differed.
        case copied(keys: Int, replaced: Int, displacedBackup: URL?)
        case nothingToCopy
        /// Failed; retried on the next launch.
        case failed(String)
        /// Failed after a retry displaced data: no more automatic retries. `backups` holds every
        /// displaced-values file so far.
        case halted(reason: String, backups: [URL])
    }

    enum FolderOutcome: Equatable {
        case alreadyDone
        /// This app had no folder: the old one was copied (`skipped`: symlinks and unreadable files).
        case copied(files: Int, bytes: Int64, skipped: Int)
        /// This app already had a folder: `added` files it lacked, `replaced` differing files
        /// (moved to `displacedBackup` first), `identical` files left as they were.
        case merged(added: Int, replaced: Int, identical: Int, skipped: Int, displacedBackup: URL?)
        case nothingToCopy
        case failed(String)
    }

    enum LoginItemOutcome: Equatable {
        /// The old app did not launch at startup, or no defaults were copied this launch.
        case notNeeded
        case registered
        case requiresApproval
        case failed(String)
    }

    struct Report: Equatable {
        var defaults: DefaultsOutcome
        var folder: FolderOutcome
        var loginItem: LoginItemOutcome

        /// Data from the old identity arrived during this launch.
        var copiedData: Bool {
            if case .copied = self.defaults { return true }
            switch self.folder {
            case .copied, .merged: return true
            default: return false
            }
        }

        /// What to tell the user before the app starts, when the migration stopped retrying.
        var haltAlert: HaltAlert? {
            guard case let .halted(reason, backups) = self.defaults else { return nil }
            return HaltAlert(reason: reason, backups: backups)
        }
    }

    struct HaltAlert: Equatable {
        let reason: String
        let backups: [URL]

        var title: String {
            "Liquid Voice couldn't finish bringing over your settings"
        }

        var message: String {
            var lines = [
                "Copying your settings, history and dictionary from the previous version failed twice, so Liquid Voice has stopped retrying. Nothing was deleted: the previous version's data is untouched.",
            ]
            if self.backups.isEmpty {
                lines.append("Nothing had to be set aside.")
            } else {
                lines.append("What this version had saved before the retry (newer history included) is kept in:")
                lines.append(contentsOf: self.backups.map { "  \($0.path)" })
            }
            lines.append("Details: \(AppIdentityMigration.logPath) (search for IDENTITY_MIGRATION). Ask Cairn before dictating a lot.")
            return lines.joined(separator: "\n")
        }
    }

    let legacyDomain: String
    /// This app's own domain, which `destination` writes into.
    let destinationDomain: String
    let destination: any AppIdentityMigrationDefaults
    let legacyFolder: URL
    let destinationFolder: URL
    /// Where displaced values and files are saved before being replaced (`~/Backups`).
    let backupRoot: URL
    /// Every key of the old domain, or nil when it cannot be read.
    var readLegacyDefaults: () -> [String: Any]?
    /// Every key this process's preferences (cfprefsd) hold for this app's own domain, not the
    /// global or argument domains. The check after the copy compares against this in memory;
    /// it is not a read of the plist on disk.
    var readDestinationDefaults: () -> [String: Any]?
    /// Whether the old domain has a preferences file, which tells "nothing there" apart from a
    /// read that came back empty.
    var legacyDefaultsFileExists: () -> Bool
    /// Registers this app as a login item and returns what macOS reports afterwards.
    var registerLoginItem: () throws -> LoginItemOutcome
    var fileManager: FileManager = .default
    var log: (DebugLogger.LogLevel, String) -> Void = { level, message in
        DebugLogger.shared.log(message, level: level, source: "AppIdentityMigration")
    }
    var now: () -> Date = { Date() }

    // MARK: - Launch

    /// What the migration did during this launch (nil when it did not run: Debug builds, the
    /// test host, a build with another bundle identifier, or one outside Applications).
    @MainActor private(set) static var launchReport: Report?

    /// Shows the halt alert. Replaced in tests; the app shows a modal `NSAlert`.
    @MainActor static var presentHaltAlert: (HaltAlert) -> Void = { alert in
        Self.runModalHaltAlert(alert)
    }

    /// Runs before SwiftUI, AppKit or `SettingsStore` read a single default (see `LiquidVoiceMain`).
    @MainActor
    static func runAtLaunch() {
        guard let migration = self.forInstalledApp() else { return }
        let report = migration.runIfNeeded()
        self.launchReport = report
        if let alert = report.haltAlert {
            self.presentHaltAlert(alert)
        }
    }

    /// A modal alert before the SwiftUI app starts, so the stopped migration cannot go unnoticed.
    @MainActor
    private static func runModalHaltAlert(_ halt: HaltAlert) {
        guard !TestHostQuietMode.isActive else { return }
        NSApplication.shared.activate()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = halt.title
        alert.informativeText = halt.message
        alert.addButton(withTitle: "Continue")
        if !halt.backups.isEmpty {
            alert.addButton(withTitle: "Show Backup in Finder")
        }
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting(halt.backups)
        }
    }

    /// Only an app installed in an Applications folder migrates. A Release product launched from
    /// DerivedData shares the installed identity but must not take its one migration early.
    static func isInstalledLocation(_ bundleURL: URL) -> Bool {
        let path = bundleURL.standardizedFileURL.path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true).standardizedFileURL.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }

    /// The installed app's migration. Debug builds start fresh under their own identifier and
    /// never read the installed app's data; neither does the XCTest host, a build with another
    /// bundle identifier, or a Release product run from outside Applications.
    static func forInstalledApp(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        bundleURL: URL = Bundle.main.bundleURL,
        isTestHost: Bool = TestHostQuietMode.isActive
    ) -> AppIdentityMigration? {
        #if DEBUG
        return nil
        #else
        guard !isTestHost, bundleIdentifier == AppStorageLocation.releaseBundleIdentifier else { return nil }
        guard self.isInstalledLocation(bundleURL) else {
            DebugLogger.shared.warning(
                "\(self.logPrefix) skipped reason=not_installed path=\(bundleURL.path) (only the app in /Applications migrates)",
                source: "AppIdentityMigration"
            )
            return nil
        }
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library", isDirectory: true)
        let legacyDomain = LegacyAppIdentity.bundleIdentifier
        let destinationDomain = AppStorageLocation.releaseBundleIdentifier
        let legacyPlist = library
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("\(legacyDomain).plist", isDirectory: false)
        return AppIdentityMigration(
            legacyDomain: legacyDomain,
            destinationDomain: destinationDomain,
            destination: UserDefaults.standard,
            legacyFolder: applicationSupport.appendingPathComponent(LegacyAppIdentity.folderName, isDirectory: true),
            destinationFolder: applicationSupport.appendingPathComponent(AppStorageLocation.folderName, isDirectory: true),
            backupRoot: home.appendingPathComponent("Backups", isDirectory: true),
            readLegacyDefaults: { Self.readPreferencesDomain(legacyDomain) },
            readDestinationDefaults: { Self.readPreferencesDomain(destinationDomain) },
            legacyDefaultsFileExists: { fileManager.fileExists(atPath: legacyPlist.path) },
            registerLoginItem: Self.registerMainAppAsLoginItem
        )
        #endif
    }

    /// Every key of a preferences domain (current user, any host), read through cfprefsd so
    /// values another app has not flushed yet are included. Read-only.
    static func readPreferencesDomain(_ domain: String) -> [String: Any]? {
        let values = CFPreferencesCopyMultiple(nil, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return values as NSDictionary as? [String: Any]
    }

    static func registerMainAppAsLoginItem() throws -> LoginItemOutcome {
        let service = SMAppService.mainApp
        try service.register()
        switch service.status {
        case .enabled:
            return .registered
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .failed("status=\(service.status.rawValue) after register")
        @unknown default:
            return .failed("status=\(service.status.rawValue) after register")
        }
    }

    // MARK: - Run

    func runIfNeeded() -> Report {
        let defaultsDone = self.destination.object(forKey: Self.defaultsMarkerKey) != nil
        let folderDone = self.destination.object(forKey: Self.folderMarkerKey) != nil
        if defaultsDone, folderDone {
            self.log(.debug, "\(Self.logPrefix) skipped reason=already_done")
            return Report(defaults: .alreadyDone, folder: .alreadyDone, loginItem: .notNeeded)
        }

        let startedAt = Date()
        self.log(
            .info,
            "\(Self.logPrefix) start from=\(self.legacyDomain) folder=\(self.legacyFolder.lastPathComponent) "
                + "to=\(self.destinationDomain) folder=\(self.destinationFolder.lastPathComponent)"
        )

        var launchedAtStartup = false
        let defaults: DefaultsOutcome
        if defaultsDone {
            defaults = .alreadyDone
        } else {
            (defaults, launchedAtStartup) = self.migrateDefaults()
        }
        let folder = folderDone ? FolderOutcome.alreadyDone : self.migrateFolder()
        let loginItem = self.migrateLoginItem(defaults: defaults, launchedAtStartup: launchedAtStartup)

        let elapsedMs = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
        let succeeded = !defaults.isFailure && !folder.isFailure
        self.log(
            succeeded ? .info : .error,
            "\(Self.logPrefix) finished result=\(succeeded ? "ok" : "incomplete") defaults=\(defaults.logValue) "
                + "folder=\(folder.logValue) loginItem=\(loginItem.logValue) elapsedMs=\(elapsedMs)"
        )
        return Report(defaults: defaults, folder: folder, loginItem: loginItem)
    }

    // MARK: UserDefaults

    /// Copies every key, then checks each one against what this process now holds for this app's
    /// domain (an in-memory comparison through cfprefsd, not a read of the file on disk; the
    /// marker is written to the same domain once the check passes).
    private func migrateDefaults() -> (DefaultsOutcome, launchedAtStartup: Bool) {
        if let halted = self.destination.object(forKey: Self.defaultsHaltedKey) as? [String: Any] {
            let reason = halted["reason"] as? String ?? "unknown"
            let backups = self.recordedBackups()
            self.log(
                .error,
                "\(Self.logPrefix) step=defaults outcome=halted reason=\(reason) backups=\(backups.count) "
                    + "(not retried; clear \(Self.defaultsHaltedKey) to retry)"
            )
            return (.halted(reason: reason, backups: backups), false)
        }
        let attempt = ((self.destination.object(forKey: Self.defaultsAttemptsKey) as? Int) ?? 0) + 1
        self.destination.set(attempt, forKey: Self.defaultsAttemptsKey)
        _ = self.destination.synchronize()

        guard let legacy = self.readLegacyDefaults() else {
            return (self.defaultsFailed("could not read \(self.legacyDomain)", attempt: attempt, displacedBackup: nil), false)
        }
        if legacy.isEmpty {
            if self.legacyDefaultsFileExists() {
                // The file is there but the read came back empty: never mark that as done.
                return (
                    self.defaultsFailed(
                        "\(self.legacyDomain) has a preferences file but no keys were read",
                        attempt: attempt,
                        displacedBackup: nil
                    ),
                    false
                )
            }
            self.markDefaultsDone(keys: 0)
            self.log(.info, "\(Self.logPrefix) step=defaults outcome=nothing_to_copy from=\(self.legacyDomain)")
            return (.nothingToCopy, false)
        }

        // What this app's domain already holds (a failed earlier attempt the app kept running
        // after). The old values win, but anything they change is saved first, never dropped.
        let existing = (self.readDestinationDefaults() ?? [:]).filter { !Self.bookkeepingKeys.contains($0.key) }
        let replaced = legacy.keys.filter { existing[$0] != nil }.count
        let changing = legacy.compactMap { key, value -> String? in
            guard let current = existing[key] else { return nil }
            return Self.isEqual(current, value) ? nil : key
        }.sorted()
        var displacedBackup: URL?
        if !changing.isEmpty {
            do {
                displacedBackup = try self.backUpDisplacedDefaults(existing)
            } catch {
                return (
                    self.defaultsFailed(
                        "could not save \(existing.count) existing keys before replacing \(changing.count) of them: "
                            + "\((error as NSError).domain) code=\((error as NSError).code)",
                        attempt: attempt,
                        displacedBackup: nil
                    ),
                    false
                )
            }
            self.recordBackup(displacedBackup)
            self.log(
                .warning,
                "\(Self.logPrefix) step=defaults displaced=\(changing.count) existing=\(existing.count) "
                    + "keys=[\(changing.prefix(8).joined(separator: ","))] backup=\(displacedBackup?.path ?? "none")"
            )
        }

        for (key, value) in legacy {
            self.destination.set(value, forKey: key)
        }
        let flushed = self.destination.synchronize()

        guard let stored = self.readDestinationDefaults() else {
            return (
                self.defaultsFailed(
                    "could not read \(self.destinationDomain) back after the copy",
                    attempt: attempt,
                    displacedBackup: displacedBackup
                ),
                false
            )
        }
        let missing = legacy.keys.filter { stored[$0] == nil }.sorted()
        let differing = legacy.compactMap { key, value -> String? in
            guard let copied = stored[key] else { return nil }
            return Self.isEqual(copied, value) ? nil : key
        }.sorted()
        guard missing.isEmpty, differing.isEmpty, flushed else {
            // Key names only (never values), so the log says which part did not land.
            let sample = (missing + differing).prefix(5).joined(separator: ",")
            return (
                self.defaultsFailed(
                    "copy incomplete keys=\(legacy.count) missing=\(missing.count) differing=\(differing.count) "
                        + "flushed=\(flushed) sample=[\(sample)]",
                    attempt: attempt,
                    displacedBackup: displacedBackup
                ),
                false
            )
        }

        self.markDefaultsDone(keys: legacy.count)
        self.log(
            .info,
            "\(Self.logPrefix) step=defaults outcome=copied keys=\(legacy.count) replaced=\(replaced) "
                + "attempt=\(attempt) from=\(self.legacyDomain)"
        )
        return (
            .copied(keys: legacy.count, replaced: replaced, displacedBackup: displacedBackup),
            (legacy[Self.launchAtStartupKey] as? Bool) == true
        )
    }

    private static func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        (lhs as AnyObject).isEqual(rhs)
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: self.now()))-\(UUID().uuidString.prefix(8))"
    }

    private func backUpDisplacedDefaults(_ values: [String: Any]) throws -> URL {
        try self.fileManager.createDirectory(at: self.backupRoot, withIntermediateDirectories: true)
        let url = self.backupRoot.appendingPathComponent(
            "liquid-voice-displaced-defaults-\(self.timestamp()).plist",
            isDirectory: false
        )
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try data.write(to: url, options: .withoutOverwriting)
        return url
    }

    private func recordBackup(_ url: URL?) {
        guard let url else { return }
        var paths = (self.destination.object(forKey: Self.displacedBackupsKey) as? [String]) ?? []
        paths.append(url.path)
        self.destination.set(paths, forKey: Self.displacedBackupsKey)
        _ = self.destination.synchronize()
    }

    private func recordedBackups() -> [URL] {
        ((self.destination.object(forKey: Self.displacedBackupsKey) as? [String]) ?? [])
            .map { URL(fileURLWithPath: $0) }
    }

    /// A failure is retried on the next launch, except when a retry already displaced data:
    /// then another retry would copy the old values over the app's newer ones again, so it stops.
    private func defaultsFailed(_ reason: String, attempt: Int, displacedBackup: URL?) -> DefaultsOutcome {
        if attempt >= 2, displacedBackup != nil {
            self.destination.set(
                ["reason": reason, "at": self.now(), "attempt": attempt] as [String: Any],
                forKey: Self.defaultsHaltedKey
            )
            _ = self.destination.synchronize()
            let backups = self.recordedBackups()
            self.log(
                .error,
                "\(Self.logPrefix) step=defaults outcome=halted reason=\(reason) attempt=\(attempt) "
                    + "backups=\(backups.map(\.path).joined(separator: ",")) (no more automatic retries)"
            )
            return .halted(reason: reason, backups: backups)
        }
        self.log(
            .error,
            "\(Self.logPrefix) step=defaults outcome=failed reason=\(reason) attempt=\(attempt) marker=unset (retried next launch)"
        )
        return .failed(reason)
    }

    private func markDefaultsDone(keys: Int) {
        self.destination.set(
            ["from": self.legacyDomain, "at": self.now(), "keys": keys] as [String: Any],
            forKey: Self.defaultsMarkerKey
        )
        _ = self.destination.synchronize()
    }

    // MARK: Application Support

    private struct TreeCopy {
        var files = 0
        var bytes: Int64 = 0
        var added = 0
        var replaced = 0
        var identical = 0
        var skipped: [String] = []
        var displacedBackup: URL?
    }

    /// Copies the old folder. Into a staging folder first when this app has none, so an
    /// interrupted copy never leaves a half-filled destination; straight into the existing
    /// folder otherwise, where old files replace different ones (saved first) and files only
    /// this app has stay.
    private func migrateFolder() -> FolderOutcome {
        let from = self.legacyFolder.lastPathComponent
        let to = self.destinationFolder.lastPathComponent
        self.removeOrphanedStagingFolders()

        var isDirectory: ObjCBool = false
        guard self.fileManager.fileExists(atPath: self.legacyFolder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            self.markFolderDone(outcome: "nothing_to_copy", files: 0)
            self.log(.info, "\(Self.logPrefix) step=folder outcome=nothing_to_copy from=\(from)")
            return .nothingToCopy
        }

        if self.fileManager.fileExists(atPath: self.destinationFolder.path) {
            let result: TreeCopy
            do {
                result = try self.copyTree(into: self.destinationFolder)
            } catch {
                return self.folderFailed("merge into existing \(to): \((error as NSError).domain) code=\((error as NSError).code)")
            }
            let outcome = result.skipped.isEmpty ? "merged" : "merged_with_warnings"
            self.markFolderDone(outcome: outcome, files: result.files)
            self.log(
                result.replaced > 0 || !result.skipped.isEmpty ? .warning : .info,
                "\(Self.logPrefix) step=folder outcome=\(outcome) added=\(result.added) replaced=\(result.replaced) "
                    + "identical=\(result.identical) skipped=\(result.skipped.count) from=\(from) to=\(to) "
                    + "backup=\(result.displacedBackup?.path ?? "none") (\(to) already existed; \(from) left in place)"
            )
            return .merged(
                added: result.added,
                replaced: result.replaced,
                identical: result.identical,
                skipped: result.skipped.count,
                displacedBackup: result.displacedBackup
            )
        }

        let staging = self.stagingFolder(named: UUID().uuidString)
        do {
            try self.fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            let result = try self.copyTree(into: staging)
            try self.fileManager.moveItem(at: staging, to: self.destinationFolder)
            let outcome = result.skipped.isEmpty ? "copied" : "copied_with_warnings"
            self.markFolderDone(outcome: outcome, files: result.files)
            self.log(
                result.skipped.isEmpty ? .info : .warning,
                "\(Self.logPrefix) step=folder outcome=\(outcome) files=\(result.files) bytes=\(result.bytes) "
                    + "skipped=\(result.skipped.count) from=\(from) to=\(to) (\(from) left in place)"
            )
            return .copied(files: result.files, bytes: result.bytes, skipped: result.skipped.count)
        } catch {
            try? self.fileManager.removeItem(at: staging)
            return self.folderFailed("\((error as NSError).domain) code=\((error as NSError).code)")
        }
    }

    /// Copies every regular file of the old folder into `target`, without following symbolic
    /// links. A file `target` already has is left alone when identical; otherwise it is moved to
    /// a displaced-files backup and the old file takes its place. An unreadable old file is
    /// skipped with a warning (it would fail the same way on every launch). A failure to write
    /// throws, and the step is retried next launch.
    private func copyTree(into target: URL) throws -> TreeCopy {
        var result = TreeCopy()
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        let log = self.log
        let legacyName = self.legacyFolder.lastPathComponent
        // A folder that cannot be listed is logged and passed over, like an unreadable file.
        let enumerator = self.fileManager.enumerator(at: self.legacyFolder, includingPropertiesForKeys: keys, options: []) { url, error in
            log(.warning, "\(Self.logPrefix) step=folder skipped_unlistable=\(url.lastPathComponent) code=\((error as NSError).code) (left in \(legacyName))")
            return true
        }
        guard let enumerator else { throw CocoaError(.fileReadUnknown) }
        for case let source as URL in enumerator {
            // `level` is the depth below the old folder, so the last `level` components are the
            // path inside it, whatever form (/var or /private/var) the URLs come back in.
            let relative = source.pathComponents.suffix(enumerator.level).joined(separator: "/")
            let destination = target.appendingPathComponent(relative)
            let values = try source.resourceValues(forKeys: Set(keys))

            if values.isSymbolicLink == true {
                result.skipped.append(relative)
                self.log(.warning, "\(Self.logPrefix) step=folder skipped_symlink=\(relative) (not followed)")
                continue
            }
            if values.isDirectory == true {
                try self.fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            guard values.isRegularFile == true else {
                result.skipped.append(relative)
                self.log(.warning, "\(Self.logPrefix) step=folder skipped_special_file=\(relative)")
                continue
            }
            guard self.fileManager.isReadableFile(atPath: source.path) else {
                result.skipped.append(relative)
                self.log(.warning, "\(Self.logPrefix) step=folder skipped_unreadable=\(relative) (left in \(self.legacyFolder.lastPathComponent))")
                continue
            }

            if self.fileManager.fileExists(atPath: destination.path) {
                if self.fileManager.contentsEqual(atPath: source.path, andPath: destination.path) {
                    result.identical += 1
                    continue
                }
                let backup = try self.displacedFolderBackup(&result)
                let saved = backup.appendingPathComponent(relative)
                try self.fileManager.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
                try self.fileManager.moveItem(at: destination, to: saved)
                self.log(.warning, "\(Self.logPrefix) step=folder displaced=\(relative) backup=\(backup.path)")
                result.replaced += 1
            } else {
                result.added += 1
            }
            try self.fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try self.fileManager.copyItem(at: source, to: destination)
            result.files += 1
            result.bytes += Int64(values.fileSize ?? 0)
        }
        return result
    }

    private func displacedFolderBackup(_ result: inout TreeCopy) throws -> URL {
        if let existing = result.displacedBackup { return existing }
        let url = self.backupRoot.appendingPathComponent("liquid-voice-displaced-folder-\(self.timestamp())", isDirectory: true)
        try self.fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        result.displacedBackup = url
        self.recordBackup(url)
        return url
    }

    private func stagingFolder(named suffix: String) -> URL {
        self.destinationFolder.deletingLastPathComponent()
            .appendingPathComponent(".\(self.destinationFolder.lastPathComponent).migrating-\(suffix)", isDirectory: true)
    }

    /// A copy interrupted by a crash or a forced quit leaves its staging folder behind.
    private func removeOrphanedStagingFolders() {
        let parent = self.destinationFolder.deletingLastPathComponent()
        let prefix = ".\(self.destinationFolder.lastPathComponent).migrating-"
        guard let names = try? self.fileManager.contentsOfDirectory(atPath: parent.path) else { return }
        for name in names where name.hasPrefix(prefix) {
            try? self.fileManager.removeItem(at: parent.appendingPathComponent(name, isDirectory: true))
            self.log(.info, "\(Self.logPrefix) step=folder removed_orphaned_staging=\(name)")
        }
    }

    private func folderFailed(_ reason: String) -> FolderOutcome {
        self.log(.error, "\(Self.logPrefix) step=folder outcome=failed reason=\(reason) marker=unset (retried next launch)")
        return .failed(reason)
    }

    private func markFolderDone(outcome: String, files: Int) {
        self.destination.set(
            ["from": self.legacyFolder.lastPathComponent, "at": self.now(), "outcome": outcome, "files": files] as [String: Any],
            forKey: Self.folderMarkerKey
        )
        _ = self.destination.synchronize()
    }

    // MARK: Launch at startup

    private func migrateLoginItem(defaults: DefaultsOutcome, launchedAtStartup: Bool) -> LoginItemOutcome {
        guard case .copied = defaults else { return .notNeeded }
        guard launchedAtStartup else {
            self.log(.info, "\(Self.logPrefix) step=login_item outcome=not_needed (launch at startup was off)")
            return .notNeeded
        }
        let outcome: LoginItemOutcome
        do {
            outcome = try self.registerLoginItem()
        } catch {
            outcome = .failed("\((error as NSError).domain) code=\((error as NSError).code) \((error as NSError).localizedDescription)")
        }
        switch outcome {
        case .registered:
            self.log(.info, "\(Self.logPrefix) step=login_item outcome=registered")
        case .requiresApproval:
            self.log(
                .warning,
                "\(Self.logPrefix) step=login_item outcome=requires_approval (approve Liquid Voice in System Settings > General > Login Items)"
            )
        case let .failed(reason):
            self.log(
                .error,
                "\(Self.logPrefix) step=login_item outcome=failed reason=\(reason) (turn Launch at startup on again in Settings)"
            )
        case .notNeeded:
            break
        }
        return outcome
    }
}

private nonisolated extension AppIdentityMigration.DefaultsOutcome {
    var isFailure: Bool {
        switch self {
        case .failed, .halted: true
        default: false
        }
    }

    var logValue: String {
        switch self {
        case .alreadyDone: "already_done"
        case let .copied(keys, _, _): "copied(\(keys))"
        case .nothingToCopy: "nothing_to_copy"
        case .failed: "failed"
        case .halted: "halted"
        }
    }
}

private nonisolated extension AppIdentityMigration.FolderOutcome {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    var logValue: String {
        switch self {
        case .alreadyDone: "already_done"
        case let .copied(files, _, skipped): skipped == 0 ? "copied(\(files))" : "copied(\(files),skipped=\(skipped))"
        case let .merged(added, replaced, _, skipped, _): "merged(added=\(added),replaced=\(replaced),skipped=\(skipped))"
        case .nothingToCopy: "nothing_to_copy"
        case .failed: "failed"
        }
    }
}

private nonisolated extension AppIdentityMigration.LoginItemOutcome {
    var logValue: String {
        switch self {
        case .notNeeded: "not_needed"
        case .registered: "registered"
        case .requiresApproval: "requires_approval"
        case .failed: "failed"
        }
    }
}
