import XCTest
@testable import FloatDude

final class TaskSessionTests: XCTestCase {
    func testStreamingDeltasAndCompletionPreserveOnlyOneResponse() {
        var snapshot = TaskSessionSnapshot.idle

        snapshot.apply(.contextCaptured(nil))
        snapshot.apply(.streaming)
        snapshot.apply(.textDelta("one"))
        snapshot.apply(.textDelta(" two"))
        snapshot.apply(.completed)

        XCTAssertEqual(snapshot.phase, .completed)
        XCTAssertEqual(snapshot.response, "one two")
    }

    func testLateDeltaAfterCancellationIsDiscarded() {
        var snapshot = TaskSessionSnapshot.idle

        snapshot.apply(.streaming)
        snapshot.apply(.cancelled)
        snapshot.apply(.textDelta("late"))

        XCTAssertEqual(snapshot.phase, .cancelled)
        XCTAssertEqual(snapshot.response, "")
    }

    @MainActor
    func testPerformanceMetricsUseMonotonicInjectedMarks() {
        let metrics = PerformanceMetrics()

        metrics.beginInvocation(at: 1_000_000_000)
        metrics.markPanelVisible(at: 1_150_000_000)
        metrics.markContextCaptured(at: 1_150_000_000)
        metrics.markContextPreview(at: 1_250_000_000)
        metrics.markRequestStarted(at: 2_000_000_000)
        metrics.markFirstToken(at: 2_125_000_000)

        XCTAssertEqual(metrics.latest.shortcutToPanelMilliseconds, 150)
        XCTAssertEqual(metrics.latest.contextToPreviewMilliseconds, 100)
        XCTAssertEqual(metrics.latest.requestToFirstTokenMilliseconds, 125)
    }
}
