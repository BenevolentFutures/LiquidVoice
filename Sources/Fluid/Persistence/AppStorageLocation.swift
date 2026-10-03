import Foundation

/// This app's identity and where each build keeps its files.
///
/// MouthKeys is its own app (`com.stage11.mouthkeys`). Debug builds have their own bundle
/// identifier too (`com.stage11.mouthkeys.dev`, which also separates UserDefaults) and their
/// own folders, so a development or test run can never read or overwrite the data of the
/// installed app someone is dictating with.
///
/// Earlier versions ran under other identifiers and folders; `AppIdentityMigration` copies the
/// newest of them over once (see `PreviousAppIdentity`).
nonisolated enum AppStorageLocation {
    /// The installed (Release) app.
    static let releaseBundleIdentifier = "com.stage11.mouthkeys"
    /// The isolated Debug build, which is also the XCTest host.
    static let debugBundleIdentifier = "com.stage11.mouthkeys.dev"

    /// Folder under `~/Library/Application Support`.
    static let folderName: String = {
        #if DEBUG
        return "MouthKeys-Dev"
        #else
        return "MouthKeys"
        #endif
    }()

    /// Folder under `~/Library/Logs` for the file log. Debug builds log separately so a test or
    /// development run never mixes its lines into, or rotates away, the installed app's log.
    static let logFolderName: String = {
        #if DEBUG
        return "MouthKeys-Dev"
        #else
        return "MouthKeys"
        #endif
    }()

    /// Bundle identifiers of this app: the installed build and the isolated Debug build.
    static let appBundleIdentifiers: Set<String> = [releaseBundleIdentifier, debugBundleIdentifier]

    /// This build's bundle identifier: the running bundle's, or the one this configuration builds.
    static var bundleIdentifier: String {
        if let identifier = Bundle.main.bundleIdentifier { return identifier }
        #if DEBUG
        return self.debugBundleIdentifier
        #else
        return self.releaseBundleIdentifier
        #endif
    }
}

/// An identity the installed app had before: its bundle identifier (the UserDefaults domain)
/// and its Application Support folder. Only `AppIdentityMigration` reads these, once, and
/// nothing ever writes there.
nonisolated struct PreviousAppIdentity: Equatable {
    let bundleIdentifier: String
    let folderName: String
    /// UserDefaults keys starting with this belong to that identity itself (its own migration
    /// markers, its Accessibility trust record) and are not copied. Nil copies every key.
    let ownKeyPrefix: String?

    /// MouthKeys 0.1.0 (the identifiers are from the app's earlier working name).
    static let mouthKeys010 = PreviousAppIdentity(
        bundleIdentifier: "com.stage11.liquidvoice", folderName: "LiquidVoice", ownKeyPrefix: "LiquidVoice"
    )
    /// The FluidVoice fork, before the app had its own identity.
    static let fluidVoice = PreviousAppIdentity(bundleIdentifier: "com.FluidApp.app", folderName: "FluidVoice", ownKeyPrefix: nil)

    /// Newest first. The migration copies from the first one that has data: each earlier
    /// identity's data was already copied into the next on its own first launch.
    static let newestFirst: [PreviousAppIdentity] = [.mouthKeys010, .fluidVoice]
}
