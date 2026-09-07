import Foundation
import XCTest
@testable import FloatDude

@MainActor
final class TaskCoordinatorTests: XCTestCase {
    func testSelectedContextAndAskInstructionRemainSeparateThroughCompletion() async throws {
        let box = RequestBox()
        let coordinator = makeCoordinator(
            context: CapturedContext(text: "Hello FloatDude", source: .accessibilitySelection, applicationName: "TextEdit"),
            requestBox: box
        )
        coordinator.beginInvocation()
        await waitUntil { coordinator.session.phase == .contextCaptured }
        coordinator.submit(action: .ask, userPrompt: "翻译成中文")
        await waitUntil { coordinator.session.phase == .completed }
        XCTAssertEqual(box.request?.action, .ask)
        XCTAssertEqual(box.request?.context?.text, "Hello FloatDude")
        XCTAssertEqual(box.request?.userPrompt, "翻译成中文")
        XCTAssertEqual(coordinator.session.phase, .completed)
        XCTAssertEqual(coordinator.session.response, "first answer")
    }

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

    func testStreamedAssistantMessageKeepsOneIdentityWhenItBecomesConversationHistory() async throws {
        let coordinator = makeCoordinator()

        coordinator.beginInvocation()
        coordinator.submit(action: .ask, userPrompt: "question")
        await waitUntil { coordinator.session.phase == .completed }

        let displayID = try XCTUnwrap(coordinator.responseDisplayID)
        XCTAssertEqual(coordinator.activeConversation?.messages.last?.role, .assistant)
        XCTAssertEqual(coordinator.activeConversation?.messages.last?.id, displayID)
        XCTAssertEqual(coordinator.activeConversation?.messages.last?.content, "first answer")
    }

    func testMissingConfigurationOnlyOpensSettingsOnExplicitAction() async {
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
        XCTAssertFalse(didOpenSettings)
        coordinator.openSettings()
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
        XCTAssertNil(coordinator.session.context)
        XCTAssertEqual(coordinator.userPrompt, "")
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

    func testRewriteActionIsIgnoredForReadOnlySelection() async {
        let requestBox = RequestBox()
        let coordinator = makeCoordinator(
            context: CapturedContext(
                text: "read only",
                source: .accessibilitySelection,
                applicationName: "Preview",
                canReplaceSelection: false
            ),
            requestBox: requestBox
        )

        coordinator.beginInvocation()
        await waitUntil { coordinator.session.phase == .contextCaptured }
        coordinator.runAction(.rewrite)

        XCTAssertNil(requestBox.request)
        XCTAssertEqual(coordinator.session.phase, .contextCaptured)
    }

    func testSecondTurnIncludesPersistedConversationHistoryAndCustomInstructions() async {
        let requestBox = RequestBox()
        let settings = TestSettingsStore(settings: AppSettings(
            baseURL: URL(string: "https://provider.example"),
            model: "demo-model",
            hotkeyDescription: "Option-Space",
            userSystemPrompt: "Always answer in Chinese."
        ))
        let coordinator = makeCoordinator(settings: settings, requestBox: requestBox)

        coordinator.beginInvocation()
        coordinator.submit(action: .ask, userPrompt: "First question")
        await waitUntil { coordinator.session.phase == .completed }
        coordinator.beginInvocation()
        coordinator.submit(action: .ask, userPrompt: "Second question")
        await waitUntil { coordinator.session.phase == .completed }

        let request = try? XCTUnwrap(requestBox.request)
        XCTAssertEqual(request?.history.map(\.role), [.user, .assistant])
        XCTAssertEqual(request?.history.map(\.content), ["First question", "first answer"])
        XCTAssertEqual(request?.userSystemPrompt, "Always answer in Chinese.")
        XCTAssertEqual(coordinator.activeConversation?.messages.count, 4)
    }

    func testConversationCreationSelectionAndDeletionAreDeterministic() {
        let coordinator = makeCoordinator()
        let firstID = coordinator.activeConversationID

        coordinator.newConversation()
        let secondID = coordinator.activeConversationID
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(coordinator.conversations.count, 2)

        coordinator.selectConversation(firstID)
        XCTAssertEqual(coordinator.activeConversationID, firstID)
        coordinator.deleteConversation(firstID)
        XCTAssertEqual(coordinator.activeConversationID, secondID)
        XCTAssertEqual(coordinator.conversations.count, 1)
    }

    func testNewConversationCarriesTheLatestLiveSelectionIntoItsPendingContext() {
        let initial = CapturedContext(
            text: "original selection",
            source: .accessibilitySelection,
            applicationName: "TextEdit"
        )
        let latest = CapturedContext(
            text: "newly selected text",
            source: .accessibilitySelection,
            applicationName: "TextEdit",
            canReplaceSelection: true
        )
        let capturer = LiveSelectionCapturer(initial: initial, live: latest)
        let coordinator = makeCoordinator(contextCapturer: capturer)

        coordinator.beginInvocation()
        let previousConversationID = coordinator.activeConversationID
        coordinator.newConversation()

        XCTAssertNotEqual(coordinator.activeConversationID, previousConversationID)
        XCTAssertEqual(coordinator.session.context, latest)
        XCTAssertTrue(coordinator.activeConversation?.messages.isEmpty == true)
    }

    func testRepeatedHotkeyKeepsTheActiveConversationAndSynchronizesLiveSelection() {
        let initial = CapturedContext(
            text: "first selection",
            source: .accessibilitySelection,
            applicationName: "TextEdit"
        )
        let latest = CapturedContext(
            text: "latest selection",
            source: .accessibilitySelection,
            applicationName: "TextEdit"
        )
        let capturer = LiveSelectionCapturer(initial: initial, live: latest)
        let coordinator = makeCoordinator(contextCapturer: capturer)
        coordinator.newConversation()
        let activeConversationID = coordinator.activeConversationID

        coordinator.beginInvocation()
        coordinator.toggleInvocation()

        XCTAssertEqual(coordinator.activeConversationID, activeConversationID)
        XCTAssertEqual(coordinator.session.context, latest)
    }

    func testObservedSelectionEventSynchronizesImmediatelyAndStopsOnDismissal() {
        let initial = CapturedContext(
            text: "first selection",
            source: .accessibilitySelection,
            applicationName: "TextEdit"
        )
        let latest = CapturedContext(
            text: "event selection",
            source: .accessibilitySelection,
            applicationName: "TextEdit"
        )
        let capturer = LiveSelectionCapturer(initial: initial, live: latest)
        let observer = TestLiveSelectionObserver()
        let coordinator = makeCoordinator(
            contextCapturer: capturer,
            liveSelectionObserver: observer
        )

        coordinator.beginInvocation()
        observer.emit(processID: 42)

        XCTAssertEqual(observer.startCount, 1)
        XCTAssertEqual(coordinator.session.context, latest)
        coordinator.cancelActiveRequest()
        XCTAssertEqual(observer.stopCount, 1)
    }

    func testObservedDeselectionClearsPendingContextAndRewriteAction() {
        let initial = CapturedContext(
            text: "selected text",
            source: .accessibilitySelection,
            applicationName: "TextEdit",
            canReplaceSelection: true
        )
        let capturer = LiveSelectionCapturer(initial: initial, live: initial)
        let observer = TestLiveSelectionObserver()
        let coordinator = makeCoordinator(
            contextCapturer: capturer,
            liveSelectionObserver: observer
        )

        coordinator.beginInvocation()
        coordinator.selectAction(.rewrite)
        capturer.live = nil
        observer.emit(processID: 42)

        XCTAssertNil(coordinator.session.context)
        XCTAssertEqual(coordinator.selectedAction, .explain)
        XCTAssertEqual(coordinator.session.phase, .contextCaptured)
    }

    func testCorruptConversationArchiveIsNotSilentlyOverwritten() {
        let persistence = FailingConversationPersistence()
        let coordinator = makeCoordinator(conversationPersistence: persistence)

        coordinator.newConversation()

        XCTAssertEqual(persistence.saveCount, 0)
        XCTAssertTrue(coordinator.persistenceStatus?.contains("could not be loaded") == true)
    }

    private func makeCoordinator(
        context: CapturedContext? = CapturedContext(text: "context", source: .clipboard, applicationName: nil),
        contextCapturer: (any ContextCapturing)? = nil,
        settings: TestSettingsStore = TestSettingsStore(settings: AppSettings(
            baseURL: URL(string: "https://provider.example"),
            model: "demo-model",
            hotkeyDescription: "Option-Space"
        )),
        requestBox: RequestBox = RequestBox(),
        clipboard: TestClipboard = TestClipboard(),
        stream: ControlledStream? = nil,
        providerSession: ProviderSession? = nil,
        conversationPersistence: any ConversationPersisting = VolatileConversationPersistence(),
        liveSelectionObserver: (any LiveSelectionObserving)? = nil
    ) -> TaskCoordinator {
        let contextCapturer = contextCapturer ?? TestContextCapturer(context: context)
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
                clipboardManager: clipboard,
                conversationPersistence: conversationPersistence,
                liveSelectionObserver: liveSelectionObserver
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
            clipboardManager: clipboard,
            conversationPersistence: conversationPersistence,
            liveSelectionObserver: liveSelectionObserver
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

    func captureContext(directInput: String?) -> ContextCaptureResult {
        if let context {
            return .captured(context)
        }
        return .unavailable(reason: .noSelectionOrClipboard)
    }
}

private final class LiveSelectionCapturer: ContextCapturing, @unchecked Sendable {
    let initial: CapturedContext
    var live: CapturedContext?

    init(initial: CapturedContext, live: CapturedContext?) {
        self.initial = initial
        self.live = live
    }

    func captureContext(directInput: String?) -> ContextCaptureResult {
        .captured(initial)
    }

    func captureLiveSelection() -> ContextCaptureResult? {
        live.map(ContextCaptureResult.captured)
    }

    func captureLiveSelection(from processID: pid_t?) -> ContextCaptureResult? {
        live.map(ContextCaptureResult.captured)
    }
}

@MainActor
private final class TestLiveSelectionObserver: LiveSelectionObserving {
    private var handler: ((pid_t) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(onSelectionChange: @escaping (pid_t) -> Void) {
        startCount += 1
        handler = onSelectionChange
    }

    func stop() {
        guard handler != nil else { return }
        stopCount += 1
        handler = nil
    }

    func emit(processID: pid_t) {
        handler?(processID)
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

private final class FailingConversationPersistence: ConversationPersisting, @unchecked Sendable {
    private(set) var saveCount = 0

    func load() throws -> ConversationArchive {
        throw CocoaError(.fileReadCorruptFile)
    }

    func save(_ archive: ConversationArchive) throws {
        saveCount += 1
    }
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
