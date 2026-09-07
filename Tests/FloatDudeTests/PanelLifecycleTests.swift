import AppKit
import SwiftUI
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

    @MainActor
    func testPhysicalPanelIsMovableAndResignKeyDismissesIt() {
        let recorder = PanelLifecycleHookRecorder()
        let controller = FloatingPanelController(
            positioner: FixedWindowPositioner(),
            onDismiss: { _ in recorder.dismissCount += 1 },
            onCancel: { _ in recorder.cancelCount += 1 }
        )

        controller.present(content: { Text("Test") }, panelSize: CGSize(width: 300, height: 180))
        let panel = controller.window
        XCTAssertNotNil(panel)
        XCTAssertTrue(panel?.canBecomeKey == true)
        XCTAssertTrue(panel?.isKeyWindow == true)
        XCTAssertTrue(panel?.isMovable == true)
        XCTAssertTrue(panel?.isMovableByWindowBackground == true)

        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        XCTAssertFalse(controller.isPresented)
        XCTAssertEqual(recorder.cancelCount, 1)
        XCTAssertEqual(recorder.dismissCount, 1)
    }

    @MainActor
    func testPanelResizePreservesTopAnchorAfterUserMovement() throws {
        let controller = FloatingPanelController(positioner: FixedWindowPositioner())
        controller.present(content: { Text("Test") }, panelSize: CGSize(width: 300, height: 180))
        let panel = try XCTUnwrap(controller.window)
        panel.setFrameOrigin(CGPoint(x: 300, y: 300))
        let originalTop = panel.frame.maxY

        controller.update(panelSize: CGSize(width: 300, height: 260))

        XCTAssertEqual(panel.frame.minX, 300, accuracy: 0.5)
        XCTAssertEqual(panel.frame.maxY, originalTop, accuracy: 0.5)
        controller.dismiss()
    }

    @MainActor
    func testSettingsWindowOpensBeforeAnyPanelInvocation() throws {
        let suiteName = "FloatDude.SettingsWindowControllerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settingsStore = SettingsStore(defaults: defaults)
        settingsStore.save(AppSettings(
            baseURL: URL(string: "http://127.0.0.1:11434"),
            model: "local-model",
            hotkeyDescription: "Option-Space",
            credentialMode: .noAuthentication
        ))
        let providerSession = ProviderSession(
            mode: .noAuthentication,
            keychainStore: KeychainStore(service: suiteName, account: "test")
        )
        let controller = SettingsWindowController(
            settingsStore: settingsStore,
            providerSession: providerSession
        )

        XCTAssertFalse(controller.window?.isVisible == true)
        controller.present()
        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertTrue(controller.window?.canBecomeKey == true)
        XCTAssertEqual(controller.window?.title, "FloatDude Settings")
        controller.close()
    }
}

@MainActor
private final class PanelLifecycleHookRecorder {
    var events: [String] = []
    var reasons: [PanelDismissReason] = []
    var dismissCount = 0
    var cancelCount = 0
}

@MainActor
private struct FixedWindowPositioner: WindowPositioning {
    func origin(forPanelSize size: CGSize) -> CGPoint {
        CGPoint(x: 300, y: 300)
    }

    func fittedPanelSize(for size: CGSize) -> CGSize {
        size
    }
}
