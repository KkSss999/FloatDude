import AppKit
import SwiftUI
import XCTest
@testable import FloatDude

@MainActor
final class PanelLifecycleTests: XCTestCase {
    func testRepeatedShortcutLeavesPersistentPanelVisible() {
        let recorder = PanelLifecycleHookRecorder()
        let lifecycle = PanelLifecycle(
            onDismiss: { reason in recorder.events.append("dismiss:\(reason.rawValue)") },
            onCancel: { reason in recorder.events.append("cancel:\(reason.rawValue)") }
        )

        XCTAssertTrue(lifecycle.present())
        XCTAssertFalse(lifecycle.present())
        XCTAssertFalse(lifecycle.handle(.shortcut))
        XCTAssertTrue(lifecycle.isPresented)
        XCTAssertEqual(recorder.events, [])
    }

    func testEscapeAndTerminateDismissButClickAwayDoesNot() {
        let recorder = PanelLifecycleHookRecorder()
        let lifecycle = PanelLifecycle(
            onDismiss: { reason in recorder.reasons.append(reason) },
            onCancel: { reason in recorder.reasons.append(reason) }
        )

        XCTAssertTrue(lifecycle.present())
        XCTAssertTrue(lifecycle.handle(.escape))
        XCTAssertFalse(lifecycle.handle(.escape))

        XCTAssertTrue(lifecycle.present())
        XCTAssertFalse(lifecycle.handle(.clickAway))
        XCTAssertTrue(lifecycle.isPresented)
        XCTAssertTrue(lifecycle.handle(.terminate))

        XCTAssertEqual(
            recorder.reasons,
            [.escape, .escape, .terminate, .terminate]
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
    func testPhysicalPanelIsMovableAndResignKeyKeepsItVisible() {
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
        XCTAssertTrue(panel?.isMovable == true)
        XCTAssertTrue(panel?.isMovableByWindowBackground == true)

        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        XCTAssertTrue(controller.isPresented)
        XCTAssertEqual(recorder.cancelCount, 0)
        XCTAssertEqual(recorder.dismissCount, 0)
        XCTAssertFalse(panel?.hidesOnDeactivate == true)
        XCTAssertFalse(panel?.canHide == true)
        XCTAssertTrue(panel?.collectionBehavior.contains(.canJoinAllSpaces) == true)
        XCTAssertTrue(panel?.collectionBehavior.contains(.canJoinAllApplications) == true)
        XCTAssertTrue(panel?.collectionBehavior.contains(.fullScreenAuxiliary) == true)
        controller.dismiss()
    }

    @MainActor
    func testMovingPanelOutsideDisplayConstrainsItBackIntoVisibleFrame() throws {
        let controller = FloatingPanelController(positioner: FixedWindowPositioner())
        controller.present(content: { Text("Test") }, panelSize: CGSize(width: 300, height: 180))
        let panel = try XCTUnwrap(controller.window)
        let screen = try XCTUnwrap(panel.screen ?? NSScreen.main)

        panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.maxX + 500, y: screen.visibleFrame.maxY + 500))
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification))

        XCTAssertLessThanOrEqual(panel.frame.maxX, screen.visibleFrame.maxX - 8 + 0.5)
        XCTAssertLessThanOrEqual(panel.frame.maxY, screen.visibleFrame.maxY - 8 + 0.5)
        XCTAssertGreaterThanOrEqual(panel.frame.minX, screen.visibleFrame.minX + 8 - 0.5)
        XCTAssertGreaterThanOrEqual(panel.frame.minY, screen.visibleFrame.minY + 8 - 0.5)
        controller.dismiss()
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
    func testRaisingAnExistingPanelDoesNotRepositionUserMovedWindow() throws {
        let controller = FloatingPanelController(positioner: FixedWindowPositioner())
        controller.present(content: { Text("First") }, panelSize: CGSize(width: 300, height: 180))
        let panel = try XCTUnwrap(controller.window)
        panel.setFrameOrigin(CGPoint(x: 420, y: 360))
        let movedOrigin = panel.frame.origin

        controller.present(content: { Text("Updated") }, panelSize: CGSize(width: 300, height: 180))

        XCTAssertEqual(panel.frame.origin.x, movedOrigin.x, accuracy: 0.5)
        XCTAssertEqual(panel.frame.origin.y, movedOrigin.y, accuracy: 0.5)
        XCTAssertTrue(controller.isPresented)
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
        XCTAssertEqual(
            controller.window?.title,
            settingsStore.current.settingsLanguage == .simplifiedChinese
                ? "FloatDude 设置"
                : "FloatDude Settings"
        )
        XCTAssertNotNil(controller.window?.contentViewController)
        XCTAssertGreaterThanOrEqual(controller.window?.contentMinSize.height ?? 0, 480)
        XCTAssertGreaterThanOrEqual(controller.window?.contentView?.bounds.height ?? 0, 480)
        XCTAssertGreaterThanOrEqual(controller.window?.contentView?.bounds.width ?? 0, 520)
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
