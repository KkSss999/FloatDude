import Foundation

#if canImport(Combine)
import Combine
#endif

typealias LLMStreamFactory = @Sendable (
    _ request: LLMRequest,
    _ configuration: LLMConfiguration,
    _ credentials: ProviderCredentials
) -> AsyncThrowingStream<LLMStreamEvent, Error>

/// MainActor-owned orchestration for exactly one invocation at a time.
@MainActor
final class TaskCoordinator: ObservableObject {
    @Published private(set) var session = TaskSessionSnapshot.idle
    @Published var selectedAction: PromptAction = .explain
    @Published var userPrompt = ""
    @Published private(set) var contextGuidance: String?

    var hasActiveInvocation: Bool {
        activeInvocationID != nil
    }

    var panelState: FloatingPanelState {
        switch session.phase {
        case .idle, .contextCaptured, .prompting:
            .prompting
        case .streaming:
            session.response.isEmpty ? .loading(action: selectedAction) : .streaming(text: session.response)
        case .completed:
            .completed(text: session.response)
        case .cancelled:
            .cancelled
        case .failed:
            .error(message: session.errorMessage ?? "The request could not be completed.")
        }
    }

    let metrics: PerformanceMetrics

    var onPresentPanel: (() -> Void)?
    var onDismissPanel: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let contextCapturer: any ContextCapturing
    private let streamFactory: LLMStreamFactory
    private let settingsStore: any SettingsStoring
    private let providerSession: any ProviderSessionManaging
    private let clipboardManager: any ClipboardManaging
    private var captureTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var activeInvocationID: UUID?

    init(
        contextCapturer: any ContextCapturing,
        streamFactory: @escaping LLMStreamFactory,
        settingsStore: any SettingsStoring,
        providerSession: any ProviderSessionManaging,
        clipboardManager: any ClipboardManaging,
        metrics: PerformanceMetrics? = nil
    ) {
        self.contextCapturer = contextCapturer
        self.streamFactory = streamFactory
        self.settingsStore = settingsStore
        self.providerSession = providerSession
        self.clipboardManager = clipboardManager
        self.metrics = metrics ?? PerformanceMetrics()
    }

    deinit {
        captureTask?.cancel()
        streamTask?.cancel()
    }

    func beginInvocation() {
        cancelTasks()

        let invocationID = UUID()
        activeInvocationID = invocationID
        session = .idle
        selectedAction = .explain
        userPrompt = ""
        contextGuidance = nil
        metrics.beginInvocation()

        // Capture runs before the panel is activated so the focused AX element
        // still belongs to the user's foreground application.
        captureTask = Task { [weak self] in
            guard let self else { return }
            let result = await contextCapturer.captureContext(directInput: nil)
            guard !Task.isCancelled else { return }
            self.finishCapture(result, invocationID: invocationID)
        }
    }

    func selectAction(_ action: PromptAction) {
        selectedAction = action
        if session.phase == .idle || session.phase == .contextCaptured {
            session.apply(.prompting)
        }
    }

    func runAction(_ action: PromptAction) {
        selectAction(action)
        guard session.context != nil else { return }
        submit(action: action, userPrompt: "")
    }

    func submit() {
        guard let invocationID = activeInvocationID else {
            beginInvocation()
            return
        }

        guard let configuration = currentConfiguration else {
            failConfiguration()
            return
        }

        let context = resolvedContext
        guard context != nil || !normalizedPrompt.isEmpty else {
            session.apply(.failed(FloatDudeError.missingContext.localizedDescription))
            return
        }

        let contextCharacterCount = context?.text.count ?? 0
        guard contextCharacterCount <= SelectionCapture.maximumContextCharacters,
              normalizedPrompt.count <= SelectionCapture.maximumContextCharacters,
              contextCharacterCount + normalizedPrompt.count <= SelectionCapture.maximumContextCharacters
        else {
            session.apply(.failed("Reduce the context to 12,000 characters or fewer before trying again."))
            return
        }

        guard ![context?.text, normalizedPrompt]
            .compactMap({ $0 })
            .contains(where: SensitiveTextDetector.containsCredential)
        else {
            session.apply(.failed("This content appears to contain a credential and was not sent."))
            return
        }

        let credentials: ProviderCredentials
        do {
            do {
                credentials = try providerSession.credentialsForRequest()
            } catch ProviderSessionError.sessionClosed {
                try providerSession.reopen()
                credentials = try providerSession.credentialsForRequest()
            }
        } catch {
            session.apply(.failed(Self.safeMessage(for: error)))
            onOpenSettings?()
            return
        }

        streamTask?.cancel()
        session.apply(.streaming)
        metrics.markRequestStarted()

        let request = LLMRequest(
            action: selectedAction,
            context: context,
            userPrompt: session.context == nil || normalizedPrompt.isEmpty ? nil : normalizedPrompt
        )

        streamTask = Task { [weak self, streamFactory] in
            do {
                for try await event in streamFactory(request, configuration, credentials) {
                    guard !Task.isCancelled else { return }
                    self?.receive(event, invocationID: invocationID)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail(
                    Self.safeMessage(for: error, apiKey: credentials.apiKey ?? ""),
                    invocationID: invocationID
                )
            }
        }
    }

    func submit(action: PromptAction, userPrompt: String) {
        selectedAction = action
        self.userPrompt = userPrompt
        submit()
    }

    func toggleInvocation() {
        if hasActiveInvocation {
            cancelAndDismiss()
        } else {
            beginInvocation()
        }
    }

    func retry() {
        guard session.phase == .failed else { return }
        submit()
    }

    func copyResponse() {
        guard session.phase == .completed, !session.response.isEmpty else { return }
        clipboardManager.writeText(session.response)
    }

    func openSettings() {
        onOpenSettings?()
    }

    func cancelAndDismiss() {
        activeInvocationID = nil
        cancelTasks()
        session.apply(.cancelled)
        onDismissPanel?()
    }

    /// Called by the AppKit panel when the user dismisses it through Esc,
    /// click-away, or application termination.
    func cancelActiveRequest() {
        activeInvocationID = nil
        cancelTasks()
        if session.phase != .cancelled {
            session.apply(.cancelled)
        }
    }

    func panelDidDismiss() {
        cancelActiveRequest()
    }

    func dismissWithoutCancellation() {
        activeInvocationID = nil
        cancelTasks()
        session.apply(.cancelled)
        onDismissPanel?()
    }

    private var normalizedPrompt: String {
        userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedContext: CapturedContext? {
        if let context = session.context {
            return context
        }
        guard !normalizedPrompt.isEmpty else { return nil }
        return CapturedContext(
            text: normalizedPrompt,
            source: .directInput,
            applicationName: nil
        )
    }

    private var currentConfiguration: LLMConfiguration? {
        let settings = settingsStore.current
        guard let baseURL = settings.baseURL, !settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return LLMConfiguration(baseURL: baseURL, model: settings.model)
    }

    private func finishCapture(_ result: ContextCaptureResult, invocationID: UUID) {
        guard activeInvocationID == invocationID else { return }
        let context: CapturedContext?
        switch result {
        case let .captured(captured):
            context = captured
            contextGuidance = captured.guidance
        case let .unavailable(reason):
            context = nil
            contextGuidance = reason.guidance
        case let .rejected(error):
            contextGuidance = nil
            session.apply(.failed(error.localizedDescription))
            onPresentPanel?()
            return
        }
        metrics.markContextCaptured()
        session.apply(.contextCaptured(context))
        metrics.markPanelVisible()
        metrics.markContextPreview()
        onPresentPanel?()
    }

    private func receive(_ event: LLMStreamEvent, invocationID: UUID) {
        guard activeInvocationID == invocationID, session.phase == .streaming else { return }
        switch event {
        case let .textDelta(delta):
            if session.response.isEmpty {
                metrics.markFirstToken()
            }
            session.apply(.textDelta(delta))
        case .completed:
            session.apply(.completed)
        }
    }

    private func fail(_ message: String, invocationID: UUID) {
        guard activeInvocationID == invocationID else { return }
        session.apply(.failed(message))
    }

    private func failConfiguration() {
        session.apply(.failed(FloatDudeError.missingConfiguration.localizedDescription))
        onOpenSettings?()
    }

    private func cancelTasks() {
        captureTask?.cancel()
        streamTask?.cancel()
        captureTask = nil
        streamTask = nil
    }

    private static func safeMessage(for error: Error, apiKey: String? = nil) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            if let apiKey {
                return LLMSecretRedactor.redact(description, apiKey: apiKey)
            }
            return description
        }
        return "The request could not be completed. Check Settings and try again."
    }
}
