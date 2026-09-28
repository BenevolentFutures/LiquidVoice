import CoreFoundation
import Foundation
import ServiceManagement

/// Where the migration writes UserDefaults: `UserDefaults`, or a test double that loses writes.
nonisolated protocol AppIdentityMigrationDefaults: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
    func synchronize() -> Bool
}

extension UserDefaults: AppIdentityMigrationDefaults {}

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
/// 2. copies (never moves) the old Application Support folder, kept dictation and saved audio
///    included, when this app has no folder yet. An existing folder is never overwritten.
/// 3. registers this app as a login item when the old one launched at startup. The old app's
///    registration belongs to its bundle identifier; only the user can remove it.
///
/// It never writes to the old domain or folder, so the previous app still runs from a backup
/// (rollback). Model caches (`Application Support/FluidAudio`) belong to the FluidAudio library,
/// are not tied to the bundle identifier, and stay where they are. Log lines carry counts and
/// outcomes, never content: grep the log for `IDENTITY_MIGRATION`.
nonisolated struct AppIdentityMigration {
    /// Set once every UserDefaults key has been copied and checked.
    static let defaultsMarkerKey = "LiquidVoiceIdentityMigrationDefaults"
    /// Set once the Application Support step is settled (copied, nothing to copy, or skipped
    /// because this app already had a folder).
    static let folderMarkerKey = "LiquidVoiceIdentityMigrationFolder"
    static let launchAtStartupKey = "LaunchAtStartup"
    static let logPrefix = "IDENTITY_MIGRATION"

    enum DefaultsOutcome: Equatable {
        case alreadyDone
        case copied(keys: Int, replaced: Int)
        case nothingToCopy
        case failed(String)
    }

    enum FolderOutcome: Equatable {
        case alreadyDone
        case copied(files: Int, bytes: Int64)
        case nothingToCopy
        case destinationExisted
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
            if case .copied = self.folder { return true }
            return false
        }
    }

    let legacyDomain: String
    let destination: any AppIdentityMigrationDefaults
    let legacyFolder: URL
    let destinationFolder: URL
    /// Every key of the old domain, or nil when it cannot be read.
    var readLegacyDefaults: () -> [String: Any]?
    /// Whether the old domain has a preferences file, which tells "nothing there" apart from a
    /// read that came back empty.
    var legacyDefaultsFileExists: () -> Bool
    /// Registers this app as a login item and returns what macOS reports afterwards.
    var registerLoginItem: () throws -> LoginItemOutcome
    var fileManager: FileManager = .default
    var log: (DebugLogger.LogLevel, String) -> Void = { level, message in
        DebugLogger.shared.log(message, level: level, source: "AppIdentityMigration")
    }

    // MARK: - Launch

    /// What the migration did during this launch (nil when it did not run: Debug builds, the
    /// test host, or a build with another bundle identifier).
    @MainActor private(set) static var launchReport: Report?

    /// Runs before SwiftUI, AppKit or `SettingsStore` read a single default (see `LiquidVoiceMain`).
    @MainActor
    static func runAtLaunch() {
        guard let migration = self.forInstalledApp() else { return }
        self.launchReport = migration.runIfNeeded()
    }

    /// The installed app's migration. Debug builds start fresh under their own identifier and
    /// never read the installed app's data; neither does the XCTest host or a build with another
    /// bundle identifier.
    static func forInstalledApp(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        isTestHost: Bool = TestHostQuietMode.isActive
    ) -> AppIdentityMigration? {
        #if DEBUG
        return nil
        #else
        guard !isTestHost, bundleIdentifier == AppStorageLocation.releaseBundleIdentifier else { return nil }
        let fileManager = FileManager.default
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        let legacyDomain = LegacyAppIdentity.bundleIdentifier
        let legacyPlist = library
            .appendingPathComponent("Preferences", isDirectory: true)
            .appendingPathComponent("\(legacyDomain).plist", isDirectory: false)
        return AppIdentityMigration(
            legacyDomain: legacyDomain,
            destination: UserDefaults.standard,
            legacyFolder: applicationSupport.appendingPathComponent(LegacyAppIdentity.folderName, isDirectory: true),
            destinationFolder: applicationSupport.appendingPathComponent(AppStorageLocation.folderName, isDirectory: true),
            readLegacyDefaults: { Self.readPreferencesDomain(legacyDomain) },
            legacyDefaultsFileExists: { fileManager.fileExists(atPath: legacyPlist.path) },
            registerLoginItem: Self.registerMainAppAsLoginItem
        )
        #endif
    }

    /// Every key of another app's preferences domain (current user, any host), read through
    /// cfprefsd so values the other app has not flushed yet are included. Read-only.
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
                + "to=\(self.destinationFolder.lastPathComponent)"
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

    /// Copies every key, then checks each one reads back equal before setting the marker.
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

        var replaced = 0
        for (key, value) in legacy {
            if self.destination.object(forKey: key) != nil { replaced += 1 }
            self.destination.set(value, forKey: key)
        }
        let flushed = self.destination.synchronize()

        let missing = legacy.keys.filter { self.destination.object(forKey: $0) == nil }.sorted()
        let differing = legacy.compactMap { key, value -> String? in
            guard let stored = self.destination.object(forKey: key) else { return nil }
            return (stored as AnyObject).isEqual(value) ? nil : key
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
        return (.copied(keys: legacy.count, replaced: replaced), (legacy[Self.launchAtStartupKey] as? Bool) == true)
    }

    private func defaultsFailed(_ reason: String) -> DefaultsOutcome {
        self.log(.error, "\(Self.logPrefix) step=defaults outcome=failed reason=\(reason) marker=unset (retried next launch)")
        return .failed(reason)
    }

    private func markDefaultsDone(keys: Int) {
        self.destination.set(
            ["from": self.legacyDomain, "at": Date(), "keys": keys] as [String: Any],
            forKey: Self.defaultsMarkerKey
        )
        _ = self.destination.synchronize()
    }

    /// Copies the old folder into place through a staging folder, so an interrupted copy never
    /// leaves a half-filled destination that a later launch would take as done.
    private func migrateFolder() -> FolderOutcome {
        let from = self.legacyFolder.lastPathComponent
        let to = self.destinationFolder.lastPathComponent
        var isDirectory: ObjCBool = false
        guard self.fileManager.fileExists(atPath: self.legacyFolder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            self.markFolderDone(outcome: "nothing_to_copy", files: 0)
            self.log(.info, "\(Self.logPrefix) step=folder outcome=nothing_to_copy from=\(from)")
            return .nothingToCopy
        }
        if self.fileManager.fileExists(atPath: self.destinationFolder.path) {
            let existing = self.fileCount(at: self.destinationFolder).files
            let legacyCount = self.fileCount(at: self.legacyFolder).files
            self.markFolderDone(outcome: "destination_existed", files: 0)
            self.log(
                .warning,
                "\(Self.logPrefix) step=folder outcome=destination_existed from=\(from) to=\(to) "
                    + "legacyFiles=\(legacyCount) existingFiles=\(existing) (nothing copied, nothing overwritten)"
            )
            return .destinationExisted
        }

        let staging = self.destinationFolder.deletingLastPathComponent()
            .appendingPathComponent(".\(to).migrating-\(UUID().uuidString)", isDirectory: true)
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
            return self.folderFailed("\(type(of: error)) code=\((error as NSError).code) \((error as NSError).localizedDescription)")
        }
    }

    private func folderFailed(_ reason: String) -> FolderOutcome {
        self.log(.error, "\(Self.logPrefix) step=folder outcome=failed reason=\(reason) marker=unset (retried next launch)")
        return .failed(reason)
    }

    private func markFolderDone(outcome: String, files: Int) {
        self.destination.set(
            ["from": self.legacyFolder.lastPathComponent, "at": Date(), "outcome": outcome, "files": files] as [String: Any],
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
        case let .copied(keys, _): "copied(\(keys))"
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
        case .nothingToCopy: "nothing_to_copy"
        case .destinationExisted: "destination_existed"
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
