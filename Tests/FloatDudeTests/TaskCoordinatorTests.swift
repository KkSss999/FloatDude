import Foundation
import XCTest
@testable import FloatDude

@MainActor
final class TaskCoordinatorTests: XCTestCase {
    func testSuccessfulSingleTurnFlowStreamsAndCopiesFinalVisibleText() async throws {
        let clipboard = TestClipboard()
        let requestBox = RequestBox()
        let coordinator = makeCoordinator(
            context: CapturedContext(text: "source", source: .accessibilitySelection, applicationName: "TestApp"),
            requestBox: requestBox,
            clipboard: clipboard
        )

        coordinator.beginInvocation()
        await waitUntil { coordinator.session.phase == .contextCaptured }
        coordinator.submit(action: .explain, userPrompt: "")
        await waitUntil { coordinator.session.phase == .completed }

        XCTAssertEqual(coordinator.session.response, "first answer")
        XCTAssertEqual(requestBox.request?.action, .explain)
        XCTAssertEqual(requestBox.request?.context?.text, "source")

        coordinator.copyResponse()
        XCTAssertEqual(clipboard.lastWrite, "first answer")
    }

    func testMissingConfigurationOpensSettingsWithoutStartingStream() async {
        let settings = TestSettingsStore(settings: AppSettings(
            baseURL: nil,
            model: "",
            hotkeyDescription: "Option-Space"
        ))
        var didOpenSettings = false
        let coordinator = makeCoordinator(settings: settings)
        coordinator.onOpenSettings = { didOpenSettings = true }

        coordinator.beginInvocation()
        await waitUntil { coordinator.session.phase == .contextCaptured }
        coordinator.submit(action: .explain, userPrompt: "")

        XCTAssertEqual(coordinator.session.phase, .failed)
        XCTAssertTrue(didOpenSettings)
    }

    func testCancellationDropsLateStreamDeltas() async {
        let gate = ControlledStream()
        let providerSession = ProviderSession(
            mode: .thisSessionOnly,
            keychainStore: TestKeychain()
        )
        try! providerSession.configure(mode: .thisSessionOnly, apiKey: "test-key")
        let coordinator = makeCoordinator(stream: gate, providerSession: providerSession)

        coordinator.beginInvocation()
        await waitUntil { coordinator.session.phase == .contextCaptured }
        coordinator.submit(action: .ask, userPrompt: "question")
        await waitUntil { coordinator.session.phase == .streaming }

        coordinator.cancelAndDismiss()
        gate.send(.textDelta("late"))
        gate.send(.completed)
        await Task.yield()

        XCTAssertEqual(coordinator.session.phase, .cancelled)
        XCTAssertEqual(coordinator.session.response, "")
        XCTAssertTrue(providerSession.hasAPIKey)
    }

    func testContextActionStreamsImmediatelyAndKeepsSessionCredentials() async throws {
        let requestBox = RequestBox()
        let providerSession = ProviderSession(
            mode: .thisSessionOnly,
            keychainStore: TestKeychain()
        )
        try providerSession.configure(mode: .thisSessionOnly, apiKey: "test-key")
        let coordinator = makeCoordinator(requestBox: requestBox, providerSession: providerSession)

        coordinator.beginInvocation()
        await waitUntil { coordinator.session.phase == .contextCaptured }
        coordinator.runAction(.translate)
        await waitUntil { coordinator.session.phase == .completed }

        XCTAssertEqual(requestBox.request?.action, .translate)
        XCTAssertTrue(providerSession.hasAPIKey)
    }

    func testCredentialLikeContextNeverStartsAProviderRequest() async {
        let requestBox = RequestBox()
        let coordinator = makeCoordinator(
            context: CapturedContext(
                text: String(repeating: "f", count: 32),
                source: .clipboard,
                applicationName: nil
            ),
            requestBox: requestBox
        )

        coordinator.beginInvocation()
        await waitUntil { coordinator.session.phase == .contextCaptured }
        coordinator.runAction(.translate)

        XCTAssertEqual(coordinator.session.phase, .failed)
        XCTAssertNil(requestBox.request)
        XCTAssertFalse(coordinator.session.errorMessage?.contains(String(repeating: "f", count: 32)) == true)
    }

    private func makeCoordinator(
        context: CapturedContext? = CapturedContext(text: "context", source: .clipboard, applicationName: nil),
        settings: TestSettingsStore = TestSettingsStore(settings: AppSettings(
            baseURL: URL(string: "https://provider.example"),
            model: "demo-model",
            hotkeyDescription: "Option-Space"
        )),
        requestBox: RequestBox = RequestBox(),
        clipboard: TestClipboard = TestClipboard(),
        stream: ControlledStream? = nil,
        providerSession: ProviderSession? = nil
    ) -> TaskCoordinator {
        let contextCapturer = TestContextCapturer(context: context)
        let keychain = TestKeychain()
        let providerSession = providerSession ?? ProviderSession(mode: .thisSessionOnly, keychainStore: keychain)
        if !providerSession.hasAPIKey {
            try! providerSession.configure(mode: .thisSessionOnly, apiKey: "test-key")
        }
        if let stream {
            return TaskCoordinator(
                contextCapturer: contextCapturer,
                streamFactory: stream.factory,
                settingsStore: settings,
                providerSession: providerSession,
                clipboardManager: clipboard
            )
        }

        let streamFactory: LLMStreamFactory = { request, _, _ in
            requestBox.request = request
            return AsyncThrowingStream { continuation in
                continuation.yield(.textDelta("first "))
                continuation.yield(.textDelta("answer"))
                continuation.yield(.completed)
                continuation.finish()
            }
        }
        return TaskCoordinator(
            contextCapturer: contextCapturer,
            streamFactory: streamFactory,
            settingsStore: settings,
            providerSession: providerSession,
            clipboardManager: clipboard
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if predicate() { return }
            await Task.yield()
        }
    }
}

@MainActor
private final class TestSettingsStore: SettingsStoring {
    private(set) var current: AppSettings

    init(settings: AppSettings) {
        current = settings
    }

    func save(_ settings: AppSettings) {
        current = settings
    }
}

private struct TestContextCapturer: ContextCapturing {
    let context: CapturedContext?

    func captureContext(directInput: String?) async -> ContextCaptureResult {
        if let context {
            return .captured(context)
        }
        return .unavailable(reason: .noSelectionOrClipboard)
    }
}

private struct TestKeychain: KeychainStoring {
    func apiKey() throws -> String? { "test-key" }
    func saveAPIKey(_ key: String) throws {}
    func updateAPIKey(_ key: String) throws {}
    func deleteAPIKey() throws {}
}

private final class TestClipboard: ClipboardManaging, @unchecked Sendable {
    var lastWrite: String?

    func readText() -> String? { nil }

    func writeText(_ text: String) {
        lastWrite = text
    }
}

private final class RequestBox: @unchecked Sendable {
    var request: LLMRequest?
}

private final class ControlledStream: @unchecked Sendable {
    private var continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation?

    var factory: LLMStreamFactory {
        { [weak self] _, _, _ in
            AsyncThrowingStream { continuation in
                self?.continuation = continuation
            }
        }
    }

    func send(_ event: LLMStreamEvent) {
        continuation?.yield(event)
    }
}
