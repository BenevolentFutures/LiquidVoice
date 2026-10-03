import Foundation

/// The app log (`~/Library/Logs/MouthKeys/Fluid.log`, or `MouthKeys-Dev` for Debug builds).
///
/// Callable from any thread: formatting and the file write happen on a private serial queue,
/// and nothing here touches the main thread. (It used to mirror every line into a published
/// array on main for an in-app viewer that no longer exists; on the stop path that queued dozens
/// of main-thread blocks per dictation.)
///
/// Release builds keep `info`, `warning` and `error` lines. `debug` lines and `benchmark`
/// timing lines are Debug-only (or FLUIDVOICE_DIAGNOSTICS), and their messages are not even
/// built otherwise. A line an agent needs to diagnose the installed app must be `info` or above.
final nonisolated class DebugLogger: @unchecked Sendable {
    static let shared = DebugLogger()

    /// Verbose stage-by-stage diagnostics (the stop-path trace, benchmark lines). Debug builds
    /// only; a local Release investigation opts in with the FLUIDVOICE_DIAGNOSTICS flag.
    static let diagnosticsEnabled: Bool = {
        #if DEBUG || FLUIDVOICE_DIAGNOSTICS
        true
        #else
        false
        #endif
    }()

    private let queue = DispatchQueue(label: "debug.logger", qos: .utility)

    private static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    enum LogLevel: String, CaseIterable, Sendable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case debug = "DEBUG"
    }

    private init() {}

    func log(_ message: @autoclosure () -> String, level: LogLevel = .info, source: String = "App") {
        guard level != .debug || Self.diagnosticsEnabled else { return }
        let message = message()
        let timestamp = Date()
        self.queue.async {
            let line = "[\(Self.logFormatter.string(from: timestamp))] [\(level.rawValue)] [\(source)] \(message)"
            // Support logs are always written to disk, whatever the in-app settings say.
            FileLogger.shared.append(line: line)
            #if DEBUG || FLUIDVOICE_DIAGNOSTICS
            print(line)
            #endif
        }
    }
}

// Convenience functions for easier logging
nonisolated extension DebugLogger {
    func info(_ message: @autoclosure () -> String, source: String = "App") {
        self.log(message(), level: .info, source: source)
    }

    /// A timing line (`APP_BENCH t=<uptime> ...`). Debug builds only.
    func benchmark(_ marker: String, message: @autoclosure () -> String, source: String = "Benchmark") {
        guard Self.diagnosticsEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        self.info("\(marker) t=\(String(format: "%.6f", now)) \(message())", source: source)
    }

    func warning(_ message: @autoclosure () -> String, source: String = "App") {
        self.log(message(), level: .warning, source: source)
    }

    func error(_ message: @autoclosure () -> String, source: String = "App") {
        self.log(message(), level: .error, source: source)
    }

    /// Verbose detail. Debug builds only.
    func debug(_ message: @autoclosure () -> String, source: String = "App") {
        guard Self.diagnosticsEnabled else { return }
        self.log(message(), level: .debug, source: source)
    }
}
