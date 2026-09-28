import SwiftUI

/// The process entry point. The one-time identity migration has to run before SwiftUI, AppKit or
/// `SettingsStore` read a single default (`FluidApp`'s stored properties already touch
/// `SettingsStore.shared`), so it runs here, and then the SwiftUI app starts as usual.
@main
enum LiquidVoiceMain {
    static func main() {
        AppIdentityMigration.runAtLaunch()
        FluidApp.main()
    }
}
