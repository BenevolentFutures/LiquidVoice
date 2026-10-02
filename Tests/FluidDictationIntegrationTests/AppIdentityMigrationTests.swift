import AppKit
import AVFoundation
@testable import MouthKeys_Debug
import XCTest

/// The one-time copy of FluidVoice-era data into the app's own identity. Every test runs on
/// throwaway preferences suites and temporary folders; nothing here reads or writes the
/// installed app's domain or folders.
@MainActor
final class AppIdentityMigrationTests: XCTestCase {
    private var sourceSuite: String!
    private var destinationSuite: String!
    private var destination: UserDefaults!
    private var root: URL!
    private var legacyFolder: URL!
    private var destinationFolder: URL!
    private var logLines: [(DebugLogger.LogLevel, String)] = []
    private var loginItemRegistrations = 0

    override func setUpWithError() throws {
        try super.setUpWithError()
        let id = UUID().uuidString
        // Two fixed suites, emptied around every test, so no run leaves preference files behind.
        self.sourceSuite = "LiquidVoiceIdentityMigrationTests.Source"
        self.destinationSuite = "LiquidVoiceIdentityMigrationTests.Destination"
        Self.erase(suite: self.sourceSuite)
        Self.erase(suite: self.destinationSuite)
        self.destination = try XCTUnwrap(UserDefaults(suiteName: self.destinationSuite))
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppIdentityMigrationTests-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        self.legacyFolder = self.root.appendingPathComponent("FluidVoice", isDirectory: true)
        self.destinationFolder = self.root.appendingPathComponent("LiquidVoice", isDirectory: true)
        self.logLines = []
        self.loginItemRegistrations = 0
    }

    override func tearDownWithError() throws {
        for suite in [self.sourceSuite, self.destinationSuite].compactMap({ $0 }) {
            Self.erase(suite: suite)
        }
        try? FileManager.default.removeItem(at: self.root)
        try super.tearDownWithError()
    }

    /// Empties a test suite and deletes its file only after cfprefsd has flushed, so the
    /// daemon does not write an empty plist back afterwards.
    private static func erase(suite: String) {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        CFPreferencesAppSynchronize(suite as CFString)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suite).plist")
        try? FileManager.default.removeItem(at: plist)
    }

    // MARK: Helpers

    /// Writes `values` into the source suite, the way the old app's domain holds them.
    private func seedSource(_ values: [String: Any]) throws {
        let source = try XCTUnwrap(UserDefaults(suiteName: self.sourceSuite))
        for (key, value) in values {
            source.set(value, forKey: key)
        }
        XCTAssertTrue(source.synchronize())
    }

    private var backupFolder: URL {
        self.root.appendingPathComponent("Backups", isDirectory: true)
    }

    private func makeMigration(
        destination: (any AppIdentityMigrationDefaults)? = nil,
        readLegacyDefaults: (() -> [String: Any]?)? = nil,
        legacyDefaultsFileExists: @escaping () -> Bool = { true },
        backupFolder: URL? = nil,
        loginItemOutcome: AppIdentityMigration.LoginItemOutcome = .registered
    ) -> AppIdentityMigration {
        let sourceSuite = self.sourceSuite!
        let destinationSuite = self.destinationSuite!
        return AppIdentityMigration(
            legacyDomain: sourceSuite,
            destinationDomain: destinationSuite,
            destination: destination ?? self.destination,
            legacyFolder: self.legacyFolder,
            destinationFolder: self.destinationFolder,
            backupRoot: backupFolder ?? self.backupFolder,
            // The production reader (CFPreferencesCopyMultiple), pointed at the test suites.
            readLegacyDefaults: readLegacyDefaults ?? { AppIdentityMigration.readPreferencesDomain(sourceSuite) },
            readDestinationDefaults: { AppIdentityMigration.readPreferencesDomain(destinationSuite) },
            legacyDefaultsFileExists: legacyDefaultsFileExists,
            registerLoginItem: { [weak self] in
                self?.loginItemRegistrations += 1
                return loginItemOutcome
            },
            log: { [weak self] level, message in self?.logLines.append((level, message)) }
        )
    }

    private func writeFile(_ relativePath: String, _ contents: String, under folder: URL) throws {
        let url = folder.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func contents(of relativePath: String, under folder: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(relativePath).path) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private var sampleSource: [String: Any] {
        [
            "TranscriptionHistoryEntries": Data(repeating: 7, count: 256 * 1024),
            "CustomDictionaryEntries": Data("dictionary".utf8),
            "HotkeyShortcutKey": Data([1, 2, 3]),
            "OnboardingCompleted": true,
            "OverlayBottomOffset": 50.0,
            "UserTypingWPM": 40,
            "SelectedSpeechModel": "parakeet-tdt",
            "FillerWords": ["um", "uh"],
            "SelectedModelByProvider": ["openai": "gpt"],
            "AnalyticsFirstOpenAt": 1_782_605_814.467,
            "LaunchAtStartup": false,
        ]
    }

    // MARK: UserDefaults

    func testEveryKeyIsCopiedAndTheMarkerIsSet() throws {
        let source = self.sampleSource
        try self.seedSource(source)

        let report = self.makeMigration().runIfNeeded()

        XCTAssertEqual(report.defaults, .copied(keys: source.count, replaced: 0, displacedBackup: nil))
        XCTAssertTrue(report.copiedData)
        for (key, value) in source {
            let copied = try XCTUnwrap(self.destination.object(forKey: key), "missing \(key)")
            XCTAssertTrue((copied as AnyObject).isEqual(value), "differs: \(key)")
        }
        let marker = try XCTUnwrap(self.destination.dictionary(forKey: AppIdentityMigration.defaultsMarkerKey))
        XCTAssertEqual(marker["keys"] as? Int, source.count)
        XCTAssertEqual(marker["from"] as? String, self.sourceSuite)
        // The same line format docs/INSTALL-CHECKLIST.md shows.
        XCTAssertTrue(self.logLines.contains {
            $0.1 == "IDENTITY_MIGRATION step=defaults outcome=copied keys=\(source.count) replaced=0 attempt=1 from=\(self.sourceSuite!)"
        })
        XCTAssertTrue(self.logLines.contains { $0.1.contains("IDENTITY_MIGRATION finished result=ok") })
    }

    func testTheSourceDomainIsOnlyRead() throws {
        try self.seedSource(self.sampleSource)
        let before = try XCTUnwrap(AppIdentityMigration.readPreferencesDomain(self.sourceSuite))

        _ = self.makeMigration().runIfNeeded()

        let after = try XCTUnwrap(AppIdentityMigration.readPreferencesDomain(self.sourceSuite))
        XCTAssertEqual(NSDictionary(dictionary: after), NSDictionary(dictionary: before))
        XCTAssertNil(after[AppIdentityMigration.defaultsMarkerKey])
    }

    func testTheMarkerPreventsASecondRun() throws {
        try self.seedSource(["SelectedSpeechModel": "first", "UserTypingWPM": 40])
        XCTAssertEqual(self.makeMigration().runIfNeeded().defaults, .copied(keys: 2, replaced: 0, displacedBackup: nil))

        // The old app changes after the migration; the new app's data must not be replaced.
        try self.seedSource(["SelectedSpeechModel": "second", "LateKey": true])
        self.destination.set(55, forKey: "UserTypingWPM")
        let second = self.makeMigration().runIfNeeded()

        XCTAssertEqual(second.defaults, .alreadyDone)
        XCTAssertEqual(second.folder, .alreadyDone)
        XCTAssertFalse(second.copiedData)
        XCTAssertEqual(self.destination.string(forKey: "SelectedSpeechModel"), "first")
        XCTAssertEqual(self.destination.integer(forKey: "UserTypingWPM"), 55)
        XCTAssertNil(self.destination.object(forKey: "LateKey"))
    }

    func testAPartialCopyIsLoggedLeftUnmarkedAndRedoneNextLaunch() throws {
        let source = self.sampleSource
        try self.seedSource(source)
        let lossy = LossyDefaults(backing: self.destination, droppedKeys: ["TranscriptionHistoryEntries"])

        let failed = self.makeMigration(destination: lossy).runIfNeeded()

        guard case let .failed(reason) = failed.defaults else {
            return XCTFail("expected a failure, got \(failed.defaults)")
        }
        XCTAssertTrue(reason.contains("missing=1"), reason)
        XCTAssertFalse(failed.copiedData)
        XCTAssertNil(self.destination.object(forKey: AppIdentityMigration.defaultsMarkerKey))
        XCTAssertEqual(failed.loginItem, .notNeeded)
        let errors = self.logLines.filter { $0.0 == .error }.map(\.1)
        XCTAssertTrue(errors.contains { $0.contains("step=defaults outcome=failed") && $0.contains("TranscriptionHistoryEntries") })
        XCTAssertTrue(errors.contains { $0.contains("finished result=incomplete") })

        // Next launch, with writes that stick, finishes the job.
        let retried = self.makeMigration().runIfNeeded()
        // The keys that landed the first time are identical, so nothing needs saving first.
        XCTAssertEqual(retried.defaults, .copied(keys: source.count, replaced: source.count - 1, displacedBackup: nil))
        XCTAssertNotNil(self.destination.object(forKey: AppIdentityMigration.defaultsMarkerKey))
        XCTAssertNotNil(self.destination.data(forKey: "TranscriptionHistoryEntries"))
    }

    func testValuesTheAppWroteAfterAFailedAttemptAreSavedBeforeTheyAreReplaced() throws {
        try self.seedSource(["TranscriptionHistoryEntries": Data("old history".utf8), "UserTypingWPM": 40])
        // The app ran on after a failed attempt: a new history, and a key only it has.
        self.destination.set(Data("new history".utf8), forKey: "TranscriptionHistoryEntries")
        self.destination.set(true, forKey: "OnlyInTheNewApp")
        XCTAssertTrue(self.destination.synchronize())

        let report = self.makeMigration().runIfNeeded()

        guard case let .copied(keys, replaced, backup?) = report.defaults else {
            return XCTFail("expected a copy with a backup, got \(report.defaults)")
        }
        XCTAssertEqual(keys, 2)
        XCTAssertEqual(replaced, 1)
        XCTAssertEqual(backup.deletingLastPathComponent().standardizedFileURL, self.backupFolder.standardizedFileURL)
        let saved = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: backup), format: nil) as? [String: Any]
        )
        XCTAssertEqual(saved["TranscriptionHistoryEntries"] as? Data, Data("new history".utf8))
        XCTAssertEqual(saved["OnlyInTheNewApp"] as? Bool, true)
        XCTAssertEqual(self.destination.data(forKey: "TranscriptionHistoryEntries"), Data("old history".utf8))
        XCTAssertTrue(self.destination.bool(forKey: "OnlyInTheNewApp"))
        XCTAssertTrue(self.logLines.contains { $0.0 == .warning && $0.1.contains("displaced=1") })
    }

    func testNothingIsReplacedWhenTheBackupCannotBeWritten() throws {
        try self.seedSource(["UserTypingWPM": 40])
        self.destination.set(55, forKey: "UserTypingWPM")
        XCTAssertTrue(self.destination.synchronize())
        let blocker = self.root.appendingPathComponent("not-a-folder")
        try Data().write(to: blocker)

        let report = self.makeMigration(backupFolder: blocker.appendingPathComponent("Backups")).runIfNeeded()

        guard case .failed = report.defaults else { return XCTFail("expected a failure, got \(report.defaults)") }
        XCTAssertEqual(self.destination.integer(forKey: "UserTypingWPM"), 55)
        XCTAssertNil(self.destination.object(forKey: AppIdentityMigration.defaultsMarkerKey))
    }

    func testAFirstFailureRetriesOnceAndARetryThatDisplacedDataStops() throws {
        try self.seedSource(["TranscriptionHistoryEntries": Data("old history".utf8), "UserTypingWPM": 40])
        let lossy = LossyDefaults(backing: self.destination, droppedKeys: ["TranscriptionHistoryEntries"])

        // Attempt 1 fails; nothing had to be displaced, so it will be retried.
        let first = self.makeMigration(destination: lossy).runIfNeeded()
        guard case .failed = first.defaults else { return XCTFail("expected a failure, got \(first.defaults)") }
        XCTAssertNil(first.haltAlert)

        // The app ran on and dictated; attempt 2 displaces that and fails again: it stops.
        self.destination.set(Data("newer history".utf8), forKey: "TranscriptionHistoryEntries")
        self.destination.set(41, forKey: "UserTypingWPM")
        XCTAssertTrue(self.destination.synchronize())
        let second = self.makeMigration(destination: lossy).runIfNeeded()
        guard case let .halted(_, backups) = second.defaults else { return XCTFail("expected a halt, got \(second.defaults)") }
        XCTAssertEqual(backups.count, 1)
        let saved = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: Data(contentsOf: backups[0]), format: nil) as? [String: Any]
        )
        XCTAssertEqual(saved["TranscriptionHistoryEntries"] as? Data, Data("newer history".utf8))
        XCTAssertNotNil(self.destination.object(forKey: AppIdentityMigration.defaultsHaltedKey))
        XCTAssertNil(self.destination.object(forKey: AppIdentityMigration.defaultsMarkerKey))

        let alert = try XCTUnwrap(second.haltAlert)
        XCTAssertTrue(alert.message.contains("~/Library/Logs/LiquidVoice/Fluid.log"))
        XCTAssertTrue(alert.message.contains(backups[0].path))
        XCTAssertTrue(self.logLines.contains { $0.0 == .error && $0.1.contains("step=defaults outcome=halted") })

        // Later launches do not copy again: the app's values stay, and the alert comes back.
        self.destination.set(42, forKey: "UserTypingWPM")
        let third = self.makeMigration().runIfNeeded()
        guard case .halted = third.defaults else { return XCTFail("expected a halt, got \(third.defaults)") }
        XCTAssertEqual(self.destination.integer(forKey: "UserTypingWPM"), 42)
        XCTAssertNotNil(third.haltAlert)
    }

    func testAnUnreadableSourceIsNeverMarkedDone() {
        let unreadable = self.makeMigration(readLegacyDefaults: { nil }).runIfNeeded()
        XCTAssertEqual(unreadable.defaults, .failed("could not read \(self.sourceSuite!)"))
        XCTAssertNil(self.destination.object(forKey: AppIdentityMigration.defaultsMarkerKey))

        // A preferences file that reads back empty is a failed read, not an empty domain.
        let empty = self.makeMigration(readLegacyDefaults: { [:] }, legacyDefaultsFileExists: { true }).runIfNeeded()
        guard case .failed = empty.defaults else { return XCTFail("expected a failure, got \(empty.defaults)") }
        XCTAssertNil(self.destination.object(forKey: AppIdentityMigration.defaultsMarkerKey))
    }

    func testAFreshMachineWithNoOldDataIsMarkedDone() {
        let report = self.makeMigration(readLegacyDefaults: { [:] }, legacyDefaultsFileExists: { false }).runIfNeeded()
        XCTAssertEqual(report.defaults, .nothingToCopy)
        XCTAssertEqual(report.folder, .nothingToCopy)
        XCTAssertFalse(report.copiedData)
        XCTAssertNotNil(self.destination.object(forKey: AppIdentityMigration.defaultsMarkerKey))
        XCTAssertNotNil(self.destination.object(forKey: AppIdentityMigration.folderMarkerKey))
    }

    func testTheLogCarriesCountsNeverContent() throws {
        let secret = "dictated-words-that-must-never-reach-the-log"
        try self.seedSource(["TranscriptionHistoryEntries": Data(secret.utf8), "SelectedSpeechModel": secret])
        try self.writeFile("parakeet_custom_vocabulary.json", secret, under: self.legacyFolder)

        _ = self.makeMigration().runIfNeeded()

        XCTAssertFalse(self.logLines.isEmpty)
        XCTAssertFalse(self.logLines.contains { $0.1.contains(secret) })
    }

    // MARK: Launch at startup

    func testLaunchAtStartupIsRegisteredForTheNewAppOnlyWhenItWasOn() throws {
        try self.seedSource(["LaunchAtStartup": true])
        let report = self.makeMigration().runIfNeeded()
        XCTAssertEqual(report.loginItem, .registered)
        XCTAssertEqual(self.loginItemRegistrations, 1)
        XCTAssertTrue(self.logLines.contains { $0.1.contains("step=login_item outcome=registered") })

        // Never again once migrated.
        _ = self.makeMigration().runIfNeeded()
        XCTAssertEqual(self.loginItemRegistrations, 1)
    }

    func testLaunchAtStartupOffRegistersNothing() throws {
        try self.seedSource(["LaunchAtStartup": false, "OnboardingCompleted": true])
        let report = self.makeMigration().runIfNeeded()
        XCTAssertEqual(report.loginItem, .notNeeded)
        XCTAssertEqual(self.loginItemRegistrations, 0)
    }

    func testALoginItemNeedingApprovalIsSaidInTheLog() throws {
        try self.seedSource(["LaunchAtStartup": true])
        let report = self.makeMigration(loginItemOutcome: .requiresApproval).runIfNeeded()
        XCTAssertEqual(report.loginItem, .requiresApproval)
        XCTAssertTrue(self.logLines.contains { $0.0 == .warning && $0.1.contains("outcome=requires_approval") })
    }

    // MARK: Application Support

    func testTheFolderIsCopiedNotMoved() throws {
        try self.seedSource(["OnboardingCompleted": true])
        try self.writeFile("parakeet_custom_vocabulary.json", "{\"words\":[\"Cairn\"]}", under: self.legacyFolder)
        try self.writeFile("KeptDictation/kept-1.wav", "RIFF-kept", under: self.legacyFolder)
        try self.writeFile("DictationAudioHistory/a.wav", "RIFF-a", under: self.legacyFolder)

        let report = self.makeMigration().runIfNeeded()

        XCTAssertEqual(report.folder, .copied(files: 3, bytes: Int64(19 + 9 + 6), skipped: 0))
        for (path, expected) in [
            ("parakeet_custom_vocabulary.json", "{\"words\":[\"Cairn\"]}"),
            ("KeptDictation/kept-1.wav", "RIFF-kept"),
            ("DictationAudioHistory/a.wav", "RIFF-a"),
        ] {
            XCTAssertEqual(self.contents(of: path, under: self.destinationFolder), expected, path)
            // The old folder is untouched, so the old app still works after a rollback.
            XCTAssertEqual(self.contents(of: path, under: self.legacyFolder), expected, path)
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: self.root.path)
        XCTAssertEqual(Set(leftovers), ["FluidVoice", "LiquidVoice"], "no staging folder may remain")
        XCTAssertNotNil(self.destination.object(forKey: AppIdentityMigration.folderMarkerKey))
        XCTAssertTrue(self.logLines.contains {
            $0.1 == "IDENTITY_MIGRATION step=folder outcome=copied files=3 bytes=34 skipped=0 from=FluidVoice to=LiquidVoice (FluidVoice left in place)"
        })
        XCTAssertTrue(self.logLines.contains { $0.1.hasPrefix("IDENTITY_MIGRATION finished result=ok defaults=copied(1) folder=copied(3) loginItem=not_needed elapsedMs=") })
    }

    private let fiveBoostTerms = #"{"terms":["Cairn","c11","Gregorovich","Atlas","Hyperion"]}"#
    private let defaultVocabulary = #"{"terms":["MouthKeys"]}"#

    /// The reviewer's case: opening Custom Dictionary writes a default vocabulary file into the
    /// new folder. Atin's own five boost terms must still win, and the default is kept aside.
    func testTheOldFileWinsOverADefaultOneTheNewAppAlreadyWrote() throws {
        try self.seedSource(["OnboardingCompleted": true])
        try self.writeFile("parakeet_custom_vocabulary.json", self.fiveBoostTerms, under: self.legacyFolder)
        try self.writeFile("KeptDictation/kept-1.wav", "RIFF-kept", under: self.legacyFolder)
        try self.writeFile("pronunciations.json", "same", under: self.legacyFolder)
        try self.writeFile("parakeet_custom_vocabulary.json", self.defaultVocabulary, under: self.destinationFolder)
        try self.writeFile("pronunciations.json", "same", under: self.destinationFolder)
        try self.writeFile("OnlyNew/notes.txt", "the new app's own", under: self.destinationFolder)

        let report = self.makeMigration().runIfNeeded()

        guard case let .merged(added, replaced, identical, skipped, backup?) = report.folder else {
            return XCTFail("expected a merge with a backup, got \(report.folder)")
        }
        XCTAssertEqual([added, replaced, identical, skipped], [1, 1, 1, 0])
        XCTAssertTrue(report.copiedData)
        XCTAssertEqual(self.contents(of: "parakeet_custom_vocabulary.json", under: self.destinationFolder), self.fiveBoostTerms)
        XCTAssertEqual(self.contents(of: "KeptDictation/kept-1.wav", under: self.destinationFolder), "RIFF-kept")
        XCTAssertEqual(self.contents(of: "OnlyNew/notes.txt", under: self.destinationFolder), "the new app's own")
        // The displaced default is kept, under the same relative path, in ~/Backups.
        XCTAssertEqual(backup.deletingLastPathComponent().standardizedFileURL, self.backupFolder.standardizedFileURL)
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("liquid-voice-displaced-folder-"))
        XCTAssertEqual(self.contents(of: "parakeet_custom_vocabulary.json", under: backup), self.defaultVocabulary)
        XCTAssertNil(self.contents(of: "pronunciations.json", under: backup), "identical files are not displaced")
        // The old folder is untouched.
        XCTAssertEqual(self.contents(of: "parakeet_custom_vocabulary.json", under: self.legacyFolder), self.fiveBoostTerms)
        XCTAssertNotNil(self.destination.object(forKey: AppIdentityMigration.folderMarkerKey))
        XCTAssertTrue(self.logLines.contains { $0.0 == .warning && $0.1.contains("displaced=parakeet_custom_vocabulary.json") })
        XCTAssertTrue(self.logLines.contains { $0.1.contains("outcome=merged added=1 replaced=1 identical=1 skipped=0") })
        let recorded = self.destination.stringArray(forKey: AppIdentityMigration.displacedBackupsKey) ?? []
        XCTAssertEqual(recorded, [backup.path])
    }

    func testSymbolicLinksAreNotFollowed() throws {
        try self.seedSource(["OnboardingCompleted": true])
        try self.writeFile("parakeet_custom_vocabulary.json", "vocabulary", under: self.legacyFolder)
        let outside = self.root.appendingPathComponent("outside", isDirectory: true)
        try self.writeFile("secret.txt", "outside the folder", under: outside)
        try FileManager.default.createSymbolicLink(
            at: self.legacyFolder.appendingPathComponent("linked-dir"),
            withDestinationURL: outside
        )
        try FileManager.default.createSymbolicLink(
            at: self.legacyFolder.appendingPathComponent("linked-file.txt"),
            withDestinationURL: outside.appendingPathComponent("secret.txt")
        )

        let report = self.makeMigration().runIfNeeded()

        XCTAssertEqual(report.folder, .copied(files: 1, bytes: 10, skipped: 2))
        XCTAssertFalse(FileManager.default.fileExists(atPath: self.destinationFolder.appendingPathComponent("linked-dir").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: self.destinationFolder.appendingPathComponent("linked-file.txt").path))
        XCTAssertNil(self.contents(of: "linked-dir/secret.txt", under: self.destinationFolder))
        XCTAssertTrue(self.logLines.contains { $0.1.contains("skipped_symlink=linked-dir") })
        XCTAssertTrue(self.logLines.contains { $0.1.contains("outcome=copied_with_warnings") })
    }

    func testAnUnreadableOldFileIsSkippedWithAWarningNotRetriedForever() throws {
        try self.seedSource(["OnboardingCompleted": true])
        try self.writeFile("parakeet_custom_vocabulary.json", "vocabulary", under: self.legacyFolder)
        try self.writeFile("locked.json", "locked", under: self.legacyFolder)
        let locked = self.legacyFolder.appendingPathComponent("locked.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

        let report = self.makeMigration().runIfNeeded()

        XCTAssertEqual(report.folder, .copied(files: 1, bytes: 10, skipped: 1))
        XCTAssertEqual(self.contents(of: "parakeet_custom_vocabulary.json", under: self.destinationFolder), "vocabulary")
        XCTAssertTrue(self.logLines.contains { $0.0 == .warning && $0.1.contains("skipped_unreadable=locked.json") })
        let marker = try XCTUnwrap(self.destination.dictionary(forKey: AppIdentityMigration.folderMarkerKey))
        XCTAssertEqual(marker["outcome"] as? String, "copied_with_warnings")
        XCTAssertEqual(self.makeMigration().runIfNeeded().folder, .alreadyDone)
    }

    func testAStagingFolderLeftByAnInterruptedCopyIsRemoved() throws {
        try self.seedSource(["OnboardingCompleted": true])
        try self.writeFile("parakeet_custom_vocabulary.json", "vocabulary", under: self.legacyFolder)
        let orphan = self.root.appendingPathComponent(".LiquidVoice.migrating-crashed", isDirectory: true)
        try self.writeFile("partial.json", "half", under: orphan)

        let report = self.makeMigration().runIfNeeded()

        XCTAssertEqual(report.folder, .copied(files: 1, bytes: 10, skipped: 0))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }

    func testAFailedFolderCopyLeavesNoHalfFolderAndIsRetried() throws {
        try self.seedSource(["OnboardingCompleted": true])
        try self.writeFile("parakeet_custom_vocabulary.json", "vocabulary", under: self.legacyFolder)
        var migration = self.makeMigration()
        migration.fileManager = FailingCopyFileManager()

        let failed = migration.runIfNeeded()

        guard case .failed = failed.folder else { return XCTFail("expected a failure, got \(failed.folder)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: self.destinationFolder.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: self.root.path), ["FluidVoice"])
        XCTAssertNil(self.destination.object(forKey: AppIdentityMigration.folderMarkerKey))
        // The defaults step succeeded and keeps its own marker; it is not redone.
        XCTAssertNotNil(self.destination.object(forKey: AppIdentityMigration.defaultsMarkerKey))

        let retried = self.makeMigration().runIfNeeded()
        XCTAssertEqual(retried.defaults, .alreadyDone)
        XCTAssertEqual(retried.folder, .copied(files: 1, bytes: 10, skipped: 0))
    }

    func testAFailedFolderCopyIsStillCompletedAfterTheAppCreatedItsOwnFolder() throws {
        try self.seedSource(["OnboardingCompleted": true])
        try self.writeFile("parakeet_custom_vocabulary.json", "vocabulary", under: self.legacyFolder)
        try self.writeFile("DictationAudioHistory/a.wav", "RIFF-a", under: self.legacyFolder)
        var migration = self.makeMigration()
        migration.fileManager = FailingCopyFileManager()
        guard case .failed = migration.runIfNeeded().folder else { return XCTFail("expected the first copy to fail") }

        // The app kept running and wrote its own vocabulary file.
        try self.writeFile("parakeet_custom_vocabulary.json", "written by the new app", under: self.destinationFolder)
        let retried = self.makeMigration().runIfNeeded()

        guard case let .merged(added, replaced, _, _, backup?) = retried.folder else {
            return XCTFail("expected a merge with a backup, got \(retried.folder)")
        }
        XCTAssertEqual([added, replaced], [1, 1])
        XCTAssertEqual(self.contents(of: "DictationAudioHistory/a.wav", under: self.destinationFolder), "RIFF-a")
        XCTAssertEqual(self.contents(of: "parakeet_custom_vocabulary.json", under: self.destinationFolder), "vocabulary")
        XCTAssertEqual(self.contents(of: "parakeet_custom_vocabulary.json", under: backup), "written by the new app")
    }

    // MARK: The new identity

    func testDebugBuildsNeverMigrateTheInstalledAppsData() {
        XCTAssertNil(AppIdentityMigration.forInstalledApp())
        XCTAssertNil(AppIdentityMigration.forInstalledApp(
            bundleIdentifier: "com.stage11.liquidvoice",
            bundleURL: URL(fileURLWithPath: "/Applications/MouthKeys.app"),
            isTestHost: false
        ))
        XCTAssertNil(AppIdentityMigration.launchReport)
    }

    func testOnlyAnAppInApplicationsCountsAsInstalled() {
        XCTAssertTrue(AppIdentityMigration.isInstalledLocation(URL(fileURLWithPath: "/Applications/MouthKeys.app")))
        XCTAssertTrue(AppIdentityMigration.isInstalledLocation(
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/MouthKeys.app")
        ))
        XCTAssertFalse(AppIdentityMigration.isInstalledLocation(
            URL(fileURLWithPath: "/Users/someone/Projects/LiquidVoice/DerivedData/Build/Products/Release/MouthKeys.app")
        ))
        XCTAssertFalse(AppIdentityMigration.isInstalledLocation(URL(fileURLWithPath: "/ApplicationsElsewhere/MouthKeys.app")))
    }

    func testTheNewIdentifiersAreUsedEverywhereTheOldOnesWere() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.stage11.liquidvoice.dev")
        XCTAssertEqual(AppStorageLocation.bundleIdentifier, "com.stage11.liquidvoice.dev")
        XCTAssertEqual(AppStorageLocation.appBundleIdentifiers, ["com.stage11.liquidvoice", "com.stage11.liquidvoice.dev"])
        XCTAssertEqual(AppStorageLocation.folderName, "LiquidVoice-Dev")
        XCTAssertEqual(AppStorageLocation.logFolderName, "LiquidVoice-Dev")
        XCTAssertEqual(LegacyAppIdentity.bundleIdentifier, "com.FluidApp.app")
        XCTAssertEqual(LegacyAppIdentity.folderName, "FluidVoice")

        XCTAssertTrue(MicrophoneChangeOverlayController.supportsAlerts(bundleIdentifier: "com.stage11.liquidvoice"))
        XCTAssertFalse(MicrophoneChangeOverlayController.supportsAlerts(bundleIdentifier: "com.FluidApp.app.dev"))
        XCTAssertEqual(SystemPasteboardManager.sessionType.rawValue, "com.stage11.liquidvoice.dev.PasteSession")
        for name in [
            DeliveryDebugTriggers.deliverText,
            DeliveryDebugTriggers.pasteLastTranscript,
            DeliveryDebugTriggers.showDeliveryFailure,
            DeliveryDebugTriggers.deliverTextAndSend,
        ] {
            XCTAssertTrue(name.rawValue.hasPrefix("com.stage11.liquidvoice.debug."), name.rawValue)
        }
        // Kept on purpose: the keychain service is not tied to the bundle identifier.
        XCTAssertEqual(KeychainService.serviceName, "com.fluidvoice.provider-api-keys")
    }
}

/// A start refused for a missing microphone permission says so instead of doing nothing.
@MainActor
final class MicrophoneAccessAtStartTests: XCTestCase {
    func testADeniedMicrophoneShowsTheCardInsteadOfFailingSilently() async {
        let asr = AppServices.shared.asr
        let savedStatus = asr.micStatus
        let savedReader = ASRService.microphoneAuthorizationStatus
        let savedHandler = ASRService.microphoneAccessNeededHandler
        var announced = 0
        ASRService.microphoneAuthorizationStatus = { .denied }
        ASRService.microphoneAccessNeededHandler = { announced += 1 }
        defer {
            ASRService.microphoneAuthorizationStatus = savedReader
            ASRService.microphoneAccessNeededHandler = savedHandler
            asr.micStatus = savedStatus
        }

        asr.micStatus = .denied
        let outcome = await asr.start()

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(announced, 1)
        XCTAssertFalse(asr.isRunning)
    }

    func testTheMicrophoneCardOpensMicrophoneSettingsAndStaysOffScreenInTests() {
        let controller = DeliveryFailureOverlayController.shared
        controller.showMicrophoneAccessNeeded()
        XCTAssertTrue(controller.presentedMicrophoneAccessNeeded)
        XCTAssertNil(controller.presentedFailure)
        XCTAssertNil(controller.presentedTimeout)
        XCTAssertEqual(
            DeliveryFailureOverlayController.microphoneSettingsURL?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
        controller.hide()
        XCTAssertFalse(controller.presentedMicrophoneAccessNeeded)
        XCTAssertEqual(TestHostQuietModeTests.onScreenWindowCount(), 0)
    }
}

/// UserDefaults that silently loses some writes, the partial failure the migration must catch.
private final class LossyDefaults: AppIdentityMigrationDefaults {
    let backing: UserDefaults
    let droppedKeys: Set<String>

    init(backing: UserDefaults, droppedKeys: Set<String>) {
        self.backing = backing
        self.droppedKeys = droppedKeys
    }

    func object(forKey defaultName: String) -> Any? {
        self.backing.object(forKey: defaultName)
    }

    func set(_ value: Any?, forKey defaultName: String) {
        guard !self.droppedKeys.contains(defaultName) else { return }
        self.backing.set(value, forKey: defaultName)
    }

    func synchronize() -> Bool {
        self.backing.synchronize()
    }
}

/// A file manager whose copy fails halfway, after writing part of the destination.
private final class FailingCopyFileManager: FileManager {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        try self.createDirectory(at: dstURL, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: dstURL.appendingPathComponent("partial.tmp"))
        throw CocoaError(.fileWriteOutOfSpace)
    }
}
