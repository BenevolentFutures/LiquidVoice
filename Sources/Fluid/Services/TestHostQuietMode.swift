import AppKit
import ObjectiveC

/// Keeps the app invisible and silent when it runs as the XCTest host.
///
/// App-hosted tests launch `MouthKeys Debug.app` on the operator's machine while Atin is
/// working (and dictating with the installed app). In quiet mode the app:
/// - never activates or shows in the Dock (`.prohibited`), so it cannot take focus;
/// - never puts a window on screen: window ordering is swallowed process-wide (`install()`),
///   while windows and their SwiftUI views are still created, so ContentView's startup and the
///   services the tests use run as usual;
/// - creates no menu bar item, installs no global input monitor or event tap, posts no user
///   notification, and asks for no permission;
/// - creates no sound player, so nothing is ever audible.
///
/// Active whenever XCTest hosts the app (`XCTestConfigurationFilePath`), or when launched with
/// `-MouthKeysQuietMode YES`.
nonisolated enum TestHostQuietMode {
    static let isActive: Bool = Self.detect(
        environment: ProcessInfo.processInfo.environment,
        arguments: ProcessInfo.processInfo.arguments
    )

    static func detect(environment: [String: String], arguments: [String]) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if let index = arguments.firstIndex(of: "-MouthKeysQuietMode"), index + 1 < arguments.count {
            return ["YES", "yes", "1", "true"].contains(arguments[index + 1])
        }
        return false
    }

    /// The activation policy to apply: the requested one, or `.prohibited` in quiet mode.
    static func activationPolicy(_ requested: NSApplication.ActivationPolicy) -> NSApplication.ActivationPolicy {
        self.isActive ? .prohibited : requested
    }

    private static let installLock = NSLock()
    private nonisolated(unsafe) static var isInstalled = false

    /// Installs the window-ordering guard once, in quiet mode only. Call before any window can
    /// be created (the app's `init`).
    static func install() {
        guard self.isActive else { return }
        self.installLock.lock()
        defer { self.installLock.unlock() }
        guard !self.isInstalled else { return }
        self.isInstalled = true
        // Every way onto the screen: orderFront(_:), makeKeyAndOrderFront(_:) and
        // setIsVisible(_:) go through order(_:relativeTo:); orderFrontRegardless does not.
        Self.exchange(#selector(NSWindow.order(_:relativeTo:)), #selector(NSWindow.quietMode_order(_:relativeTo:)))
        Self.exchange(#selector(NSWindow.orderFrontRegardless), #selector(NSWindow.quietMode_orderFrontRegardless))
        DebugLogger.shared.info(
            "Test host quiet mode: no windows, sounds, menu bar item, monitors or activation",
            source: "TestHostQuietMode"
        )
    }

    private static func exchange(_ original: Selector, _ replacement: Selector) {
        guard let originalMethod = class_getInstanceMethod(NSWindow.self, original),
              let replacementMethod = class_getInstanceMethod(NSWindow.self, replacement)
        else {
            DebugLogger.shared.error("Quiet mode could not guard \(original)", source: "TestHostQuietMode")
            return
        }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

extension NSWindow {
    /// Quiet mode: ordering out still works; ordering in is swallowed.
    @objc fileprivate func quietMode_order(_ place: NSWindow.OrderingMode, relativeTo otherWindowNumber: Int) {
        guard place == .out else { return }
        // Exchanged: this calls the original implementation.
        self.quietMode_order(place, relativeTo: otherWindowNumber)
    }

    @objc fileprivate func quietMode_orderFrontRegardless() {}
}
