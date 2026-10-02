@testable import MouthKeys_Debug
import Foundation
import XCTest

final class DeadlineRaceTests: XCTestCase {
    func testFastOperationReturnsItsValue() async throws {
        let value = try await DeadlineRace.run(deadlineNanoseconds: 1_000_000_000) {
            42
        }
        XCTAssertEqual(value, 42)
    }

    func testOperationErrorPropagates() async {
        struct Boom: Error {}
        do {
            _ = try await DeadlineRace.run(deadlineNanoseconds: 1_000_000_000) { () -> Int in
                throw Boom()
            }
            XCTFail("expected Boom")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }

    func testBlockedOperationTimesOutWithoutWaitingForIt() async {
        let lateCompletion = expectation(description: "late completion observed")
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await DeadlineRace.run(
                deadlineNanoseconds: 50_000_000,
                operation: { () -> Int in
                    try await Task.sleep(nanoseconds: 400_000_000)
                    return 7
                },
                onLateCompletion: { result in
                    if case let .success(value) = result, value == 7 {
                        lateCompletion.fulfill()
                    }
                }
            )
            XCTFail("expected TimedOut")
        } catch let timeout as DeadlineRace.TimedOut {
            XCTAssertEqual(timeout.deadlineNanoseconds, 50_000_000)
        } catch {
            XCTFail("unexpected error \(error)")
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        XCTAssertLessThan(elapsed, 0.3, "the race must not wait for the blocked operation")
        await fulfillment(of: [lateCompletion], timeout: 2.0)
    }

    func testAbandonAppliesOnlyToStartsThatBeganBeforeTheRequest() {
        XCTAssertFalse(
            DirectCoreAudioLifecycleController.startWasAbandoned(
                startBeganAt: 100, abandonRequestedAt: nil
            )
        )
        XCTAssertFalse(
            DirectCoreAudioLifecycleController.startWasAbandoned(
                startBeganAt: 100, abandonRequestedAt: 99
            ),
            "an abandon request from an earlier session must not poison a fresh start"
        )
        XCTAssertTrue(
            DirectCoreAudioLifecycleController.startWasAbandoned(
                startBeganAt: 100, abandonRequestedAt: 100.5
            )
        )
    }
}
