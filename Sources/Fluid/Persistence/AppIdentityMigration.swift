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
///    hotkeys, settings) into this app's domain, checks each one landed, and only then sets a
///    marker, so it never runs twice. A partial copy is logged and left unmarked, to be redone.
///    Values already in this app's domain that it would replace (a failed earlier attempt the
///    app kept running after) are saved to a plist in `~/Backups` first.
/// 2. copies (never moves) the old Application Support folder, kept dictation and saved audio
///    included. When this app already has a folder, it adds only the files that folder lacks:
///    nothing there is ever overwritten.
/// 3. registers this app as a login item when the old one launched at startup. The old app's
///    registration belongs to its bundle identifier; only the user can remove it.
///
/// It never writes to the old domain or folder, so the previous app still runs from a backup
/// (rollback). Model caches (`Application Support/FluidAudio`) belong to the FluidAudio library,
/// are not tied to the bundle identifier, and stay where they are. Log lines carry counts,
/// outcomes and at most a few key or file names, never content: grep for `IDENTITY_MIGRATION`.
nonisolated struct AppIdentityMigration {
    /// Set once every UserDefaults key has been copied and checked.
    static let defaultsMarkerKey = "LiquidVoiceIdentityMigrationDefaults"
    /// Set once the Application Support step is settled (copied, merged, or nothing to copy).
    static let folderMarkerKey = "LiquidVoiceIdentityMigrationFolder"
    static let launchAtStartupKey = "LaunchAtStartup"
    static let logPrefix = "IDENTITY_MIGRATION"
    private static let markerKeys: Set<String> = [defaultsMarkerKey, folderMarkerKey]

    enum DefaultsOutcome: Equatable {
        case alreadyDone
        /// `replaced`: keys this app's domain already had. `displacedBackup`: the file their
        /// earlier values were saved to, when any of them differed.
        case copied(keys: Int, replaced: Int, displacedBackup: URL?)
        case nothingToCopy
        case failed(String)
    }

    enum FolderOutcome: Equatable {
        case alreadyDone
        case copied(files: Int, bytes: Int64)
        /// This app already had a folder: `added` files it lacked, `kept` its own where both had one.
        case merged(added: Int, kept: Int)
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
    }

    let legacyDomain: String
    /// This app's own domain, which `destination` writes into.
    let destinationDomain: String
    let destination: any AppIdentityMigrationDefaults
    let legacyFolder: URL
    let destinationFolder: URL
    /// Where values this app's domain already had are saved before being replaced.
    let displacedDefaultsBackupFolder: URL
    /// Every key of the old domain, or nil when it cannot be read.
    var readLegacyDefaults: () -> [String: Any]?
    /// Every key persisted in this app's own domain (not the global or argument domains).
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

    /// Runs before SwiftUI, AppKit or `SettingsStore` read a single default (see `LiquidVoiceMain`).
    @MainActor
    static func runAtLaunch() {
        guard let migration = self.forInstalledApp() else { return }
        self.launchReport = migration.runIfNeeded()
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
            displacedDefaultsBackupFolder: home.appendingPathComponent("Backups", isDirectory: true),
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

    /// Copies every key, then checks each one reads back equal from this app's own domain
    /// before setting the marker.
    private func migrateDefaults() -> (DefaultsOutcome, launchedAtStartup: Bool) {
        guard let legacy = self.readLegacyDefaults() else {
            return (self.defaultsFailed("could not read \(self.legacyDomain)"), false)
        }
        if legacy.isEmpty {
            if self.legacyDefaultsFileExists() {
                // The file is there but the read came back empty: never mark that as done.
                return (self.defaultsFailed("\(self.legacyDomain) has a preferences file but no keys were read"), false)
            }
            self.markDefaultsDone(keys: 0)
            self.log(.info, "\(Self.logPrefix) step=defaults outcome=nothing_to_copy from=\(self.legacyDomain)")
            return (.nothingToCopy, false)
        }

        // What this app's domain already holds, from a failed earlier attempt the app kept
        // running after. Anything the copy would change is saved first, never just dropped.
        let existing = (self.readDestinationDefaults() ?? [:]).filter { !Self.markerKeys.contains($0.key) }
        let replaced = legacy.keys.filter { existing[$0] != nil }.count
        let changing = legacy.compactMap { key, value -> String? in
            guard let current = existing[key] else { return nil }
            return Self.isEqual(current, value) ? nil : key
        }
        var displacedBackup: URL?
        if !changing.isEmpty {
            do {
                displacedBackup = try self.backUpDisplacedDefaults(existing)
            } catch {
                return (
                    self.defaultsFailed(
                        "could not save \(existing.count) existing keys before replacing \(changing.count) of them: "
                            + "\((error as NSError).domain) code=\((error as NSError).code)"
                    ),
                    false
                )
            }
            self.log(
                .warning,
                "\(Self.logPrefix) step=defaults displaced=\(changing.count) existing=\(existing.count) "
                    + "backup=\(displacedBackup?.path ?? "none")"
            )
        }

        for (key, value) in legacy {
            self.destination.set(value, forKey: key)
        }
        let flushed = self.destination.synchronize()

        guard let stored = self.readDestinationDefaults() else {
            return (self.defaultsFailed("could not read \(self.destinationDomain) back after the copy"), false)
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
                        + "flushed=\(flushed) sample=[\(sample)]"
                ),
                false
            )
        }

        self.markDefaultsDone(keys: legacy.count)
        self.log(
            .info,
            "\(Self.logPrefix) step=defaults outcome=copied keys=\(legacy.count) replaced=\(replaced) from=\(self.legacyDomain)"
        )
        return (
            .copied(keys: legacy.count, replaced: replaced, displacedBackup: displacedBackup),
            (legacy[Self.launchAtStartupKey] as? Bool) == true
        )
    }

    private static func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        (lhs as AnyObject).isEqual(rhs)
    }

    private func backUpDisplacedDefaults(_ values: [String: Any]) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        try self.fileManager.createDirectory(at: self.displacedDefaultsBackupFolder, withIntermediateDirectories: true)
        let url = self.displacedDefaultsBackupFolder.appendingPathComponent(
            "liquid-voice-displaced-defaults-\(formatter.string(from: self.now()))-\(UUID().uuidString.prefix(8)).plist",
            isDirectory: false
        )
        let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        try data.write(to: url, options: .withoutOverwriting)
        return url
    }

    private func defaultsFailed(_ reason: String) -> DefaultsOutcome {
        self.log(.error, "\(Self.logPrefix) step=defaults outcome=failed reason=\(reason) marker=unset (retried next launch)")
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

    /// Copies the old folder into place through a staging folder, so an interrupted copy never
    /// leaves a half-filled destination. When the destination already exists (the app created
    /// it after an earlier attempt failed), only the files it lacks are added.
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
            return self.mergeMissingFiles()
        }

        let staging = self.stagingFolder(named: UUID().uuidString)
        do {
            try self.fileManager.copyItem(at: self.legacyFolder, to: staging)
            let source = self.fileCount(at: self.legacyFolder)
            let copied = self.fileCount(at: staging)
            guard copied.files == source.files, copied.bytes == source.bytes else {
                try? self.fileManager.removeItem(at: staging)
                return self.folderFailed(
                    "copy incomplete files=\(copied.files)/\(source.files) bytes=\(copied.bytes)/\(source.bytes)"
                )
            }
            try self.fileManager.moveItem(at: staging, to: self.destinationFolder)
            self.markFolderDone(outcome: "copied", files: copied.files)
            self.log(
                .info,
                "\(Self.logPrefix) step=folder outcome=copied files=\(copied.files) bytes=\(copied.bytes) from=\(from) to=\(to) "
                    + "(\(from) left in place)"
            )
            return .copied(files: copied.files, bytes: copied.bytes)
        } catch {
            try? self.fileManager.removeItem(at: staging)
            return self.folderFailed("\((error as NSError).domain) code=\((error as NSError).code)")
        }
    }

    /// Adds every file of the old folder that the existing destination lacks. A file both have
    /// keeps the destination's version: nothing is overwritten.
    private func mergeMissingFiles() -> FolderOutcome {
        let from = self.legacyFolder.lastPathComponent
        let to = self.destinationFolder.lastPathComponent
        guard let relativePaths = self.fileManager.enumerator(atPath: self.legacyFolder.path)?.allObjects as? [String] else {
            return self.folderFailed("could not list \(from)")
        }
        var added = 0
        var kept: [String] = []
        do {
            for relativePath in relativePaths.sorted() {
                let source = self.legacyFolder.appendingPathComponent(relativePath)
                let target = self.destinationFolder.appendingPathComponent(relativePath)
                var isDirectory: ObjCBool = false
                guard self.fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else { continue }
                if isDirectory.boolValue {
                    try self.fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                    continue
                }
                if self.fileManager.fileExists(atPath: target.path) {
                    kept.append(relativePath)
                    continue
                }
                try self.fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try self.fileManager.copyItem(at: source, to: target)
                added += 1
            }
        } catch {
            return self.folderFailed("merge stopped after added=\(added): \((error as NSError).domain) code=\((error as NSError).code)")
        }
        self.markFolderDone(outcome: "merged", files: added)
        self.log(
            .warning,
            "\(Self.logPrefix) step=folder outcome=merged added=\(added) kept=\(kept.count) from=\(from) to=\(to) "
                + "(\(to) already existed; nothing overwritten; kept=[\(kept.prefix(5).joined(separator: ","))])"
        )
        return .merged(added: added, kept: kept.count)
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

    private func fileCount(at root: URL) -> (files: Int, bytes: Int64) {
        guard let enumerator = self.fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else { return (0, 0) }
        var files = 0
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true
            else { continue }
            files += 1
            bytes += Int64(values.fileSize ?? 0)
        }
        return (files, bytes)
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
        if case .failed = self { return true }
        return false
    }

    var logValue: String {
        switch self {
        case .alreadyDone: "already_done"
        case let .copied(keys, _, _): "copied(\(keys))"
        case .nothingToCopy: "nothing_to_copy"
        case .failed: "failed"
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
        case let .copied(files, _): "copied(\(files))"
        case let .merged(added, kept): "merged(added=\(added),kept=\(kept))"
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
