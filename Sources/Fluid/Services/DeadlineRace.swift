import Foundation

/// Runs an async operation that cannot be cancelled cooperatively (for example a
/// call that blocks a serial dispatch queue inside Core Audio) and gives up
/// waiting on it after a deadline, without waiting for the operation to unwind.
///
/// The operation keeps running after a timeout. Callers must make the late
/// completion harmless themselves (see `DirectCoreAudioLifecycleController
/// .abandonPendingStart`), and can observe it via `onLateCompletion`.
enum DeadlineRace {
    struct TimedOut: Error, Equatable {
        let deadlineNanoseconds: UInt64
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false

        /// Returns true for exactly the first caller.
        func claim() -> Bool {
            self.lock.lock()
            defer { self.lock.unlock() }
            if self.fired { return false }
            self.fired = true
            return true
        }
    }

    static func run<T>(
        deadlineNanoseconds: UInt64,
        operation: @escaping () async throws -> T,
        onLateCompletion: @escaping (Result<T, Error>) -> Void = { _ in }
    ) async throws -> T {
        let once = Once()
        return try await withCheckedThrowingContinuation { continuation in
            let sleeper = Task {
                do {
                    try await Task.sleep(nanoseconds: deadlineNanoseconds)
                } catch {
                    return
                }
                if once.claim() {
                    continuation.resume(
                        throwing: TimedOut(deadlineNanoseconds: deadlineNanoseconds)
                    )
                }
            }
            Task {
                let result: Result<T, Error>
                do {
                    result = .success(try await operation())
                } catch {
                    result = .failure(error)
                }
                if once.claim() {
                    sleeper.cancel()
                    continuation.resume(with: result)
                } else {
                    onLateCompletion(result)
                }
            }
        }
    }
}
