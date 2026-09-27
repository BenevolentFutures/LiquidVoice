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

    /// Bundle identifiers of this app: the installed build and the isolated Debug build.
    static let appBundleIdentifiers: Set<String> = ["com.FluidApp.app", "com.FluidApp.app.dev"]
}
