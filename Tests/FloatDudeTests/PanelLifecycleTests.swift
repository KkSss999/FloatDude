import XCTest
@testable import FloatDude

@MainActor
final class PanelLifecycleTests: XCTestCase {
    func testRepeatedShortcutDismissesAndCancelsExactlyOnce() {
        let recorder = PanelLifecycleHookRecorder()
        let lifecycle = PanelLifecycle(
            onDismiss: { reason in recorder.events.append("dismiss:\(reason.rawValue)") },
            onCancel: { reason in recorder.events.append("cancel:\(reason.rawValue)") }
        )

        XCTAssertTrue(lifecycle.present())
        XCTAssertFalse(lifecycle.present())
        XCTAssertTrue(lifecycle.handle(.shortcut))
        XCTAssertFalse(lifecycle.isPresented)
        XCTAssertEqual(recorder.events, ["cancel:repeatedShortcut", "dismiss:repeatedShortcut"])
    }

    func testEscapeClickAwayAndTerminateAreIdempotentCancellationPaths() {
        let recorder = PanelLifecycleHookRecorder()
        let lifecycle = PanelLifecycle(
            onDismiss: { reason in recorder.reasons.append(reason) },
            onCancel: { reason in recorder.reasons.append(reason) }
        )

        XCTAssertTrue(lifecycle.present())
        XCTAssertTrue(lifecycle.handle(.escape))
        XCTAssertFalse(lifecycle.handle(.escape))

        XCTAssertTrue(lifecycle.present())
        XCTAssertTrue(lifecycle.handle(.clickAway))
        XCTAssertTrue(lifecycle.present())
        XCTAssertTrue(lifecycle.handle(.terminate))

        XCTAssertEqual(
            recorder.reasons,
            [.escape, .escape, .clickAway, .clickAway, .terminate, .terminate]
        )
    }

    func testProgrammaticDismissDoesNotInvokeCancelHook() {
        let recorder = PanelLifecycleHookRecorder()
        let lifecycle = PanelLifecycle(
            onDismiss: { _ in recorder.dismissCount += 1 },
            onCancel: { _ in recorder.cancelCount += 1 }
        )

        XCTAssertTrue(lifecycle.present())
        XCTAssertTrue(lifecycle.dismiss())
        XCTAssertEqual(recorder.dismissCount, 1)
        XCTAssertEqual(recorder.cancelCount, 0)
    }
}

@MainActor
private final class PanelLifecycleHookRecorder {
    var events: [String] = []
    var reasons: [PanelDismissReason] = []
    var dismissCount = 0
    var cancelCount = 0
}
