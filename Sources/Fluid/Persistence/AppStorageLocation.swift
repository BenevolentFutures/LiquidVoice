import Foundation

/// This app's identity and where each build keeps its files.
///
/// Liquid Voice is its own app (`com.stage11.liquidvoice`). Debug builds have their own bundle
/// identifier too (`com.stage11.liquidvoice.dev`, which also separates UserDefaults) and their
/// own folders, so a development or test run can never read or overwrite the data of the
/// installed app someone is dictating with.
///
/// Until 2026-09 the app ran under FluidVoice's identifier and folders; `AppIdentityMigration`
/// copies that data over once (see `LegacyAppIdentity`).
nonisolated enum AppStorageLocation {
    /// The installed (Release) app.
    static let releaseBundleIdentifier = "com.stage11.liquidvoice"
    /// The isolated Debug build, which is also the XCTest host.
    static let debugBundleIdentifier = "com.stage11.liquidvoice.dev"

    /// Folder under `~/Library/Application Support`.
    static let folderName: String = {
        #if DEBUG
        return "LiquidVoice-Dev"
        #else
        return "LiquidVoice"
        #endif
    }()

    /// Folder under `~/Library/Logs` for the file log. Debug builds log separately so a test or
    /// development run never mixes its lines into, or rotates away, the installed app's log.
    static let logFolderName: String = {
        #if DEBUG
        return "LiquidVoice-Dev"
        #else
        return "LiquidVoice"
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

/// The identity the app had before it was its own: FluidVoice's bundle identifier and folder.
/// Only `AppIdentityMigration` reads it, once, and nothing ever writes there.
nonisolated enum LegacyAppIdentity {
    static let bundleIdentifier = "com.FluidApp.app"
    static let folderName = "FluidVoice"
}
