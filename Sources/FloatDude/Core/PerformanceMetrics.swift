import Foundation

struct PerformanceMetricsSnapshot: Equatable, Sendable {
    var shortcutToPanelMilliseconds: Double?
    var contextToPreviewMilliseconds: Double?
    var requestToFirstTokenMilliseconds: Double?
}

/// Local, content-free timing marks for the v0.1 performance gates.
@MainActor
final class PerformanceMetrics {
    private var invocationStart: UInt64?
    private var contextCapturedAt: UInt64?
    private var requestStartedAt: UInt64?

    private(set) var latest = PerformanceMetricsSnapshot(
        shortcutToPanelMilliseconds: nil,
        contextToPreviewMilliseconds: nil,
        requestToFirstTokenMilliseconds: nil
    )

    func beginInvocation(at nanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        invocationStart = nanoseconds
        contextCapturedAt = nil
        requestStartedAt = nil
        latest = PerformanceMetricsSnapshot(
            shortcutToPanelMilliseconds: nil,
            contextToPreviewMilliseconds: nil,
            requestToFirstTokenMilliseconds: nil
        )
    }

    func markPanelVisible(at nanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        guard let invocationStart else { return }
        latest.shortcutToPanelMilliseconds = elapsedMilliseconds(from: invocationStart, to: nanoseconds)
    }

    func markContextCaptured(at nanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        contextCapturedAt = nanoseconds
    }

    func markContextPreview(at nanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        guard let contextCapturedAt else { return }
        latest.contextToPreviewMilliseconds = elapsedMilliseconds(from: contextCapturedAt, to: nanoseconds)
    }

    func markRequestStarted(at nanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        requestStartedAt = nanoseconds
    }

    func markFirstToken(at nanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        guard let requestStartedAt else { return }
        latest.requestToFirstTokenMilliseconds = elapsedMilliseconds(from: requestStartedAt, to: nanoseconds)
    }

    private func elapsedMilliseconds(from start: UInt64, to end: UInt64) -> Double {
        guard end >= start else { return 0 }
        return Double(end - start) / 1_000_000
    }
}
