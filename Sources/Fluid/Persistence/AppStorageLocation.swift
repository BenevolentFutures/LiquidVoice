import Foundation

/// Where this build keeps its files under Application Support.
///
/// Debug builds get their own folder here, and their own bundle identifier in the
/// project (`com.FluidApp.app.dev`, which also separates UserDefaults), so a
/// development or test run can never read or overwrite the data of the installed app
/// someone is dictating with.
nonisolated enum AppStorageLocation {
    static let folderName: String = {
        #if DEBUG
        return "FluidVoice-Dev"
        #else
        return "FluidVoice"
        #endif
    }()

    /// Folder under `~/Library/Logs` for the file log. Debug builds log separately so a test or
    /// development run never mixes its lines into, or rotates away, the installed app's log.
    static let logFolderName: String = {
        #if DEBUG
        return "Fluid-Dev"
        #else
        return "Fluid"
        #endif
    }()

    /// Bundle identifiers of this app: the installed build and the isolated Debug build.
    static let appBundleIdentifiers: Set<String> = ["com.FluidApp.app", "com.FluidApp.app.dev"]
}
