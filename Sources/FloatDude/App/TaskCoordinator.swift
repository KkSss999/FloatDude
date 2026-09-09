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
    @Published private(set) var conversations: [AgentConversation]
    @Published private(set) var activeConversationID: UUID
    @Published private(set) var attachmentStatus: String?
    @Published private(set) var persistenceStatus: String?
    @Published private(set) var responseDisplayID: UUID?

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
    private let conversationPersistence: any ConversationPersisting
    private let attachmentImporter: AttachmentImporter
    private let liveSelectionObserver: (any LiveSelectionObserving)?
    private let conversationPersistenceEnabled: Bool
    private var streamTask: Task<Void, Never>?
    private var liveContextTask: Task<Void, Never>?
    private var activeInvocationID: UUID?
    private var responseConversationID: UUID?
    private var retryRequest: LLMRequest?

    init(
        contextCapturer: any ContextCapturing,
        streamFactory: @escaping LLMStreamFactory,
        settingsStore: any SettingsStoring,
        providerSession: any ProviderSessionManaging,
        clipboardManager: any ClipboardManaging,
        conversationPersistence: any ConversationPersisting = VolatileConversationPersistence(),
        attachmentImporter: AttachmentImporter = AttachmentImporter(),
        liveSelectionObserver: (any LiveSelectionObserving)? = nil,
        metrics: PerformanceMetrics? = nil
    ) {
        let archive: ConversationArchive
        let persistenceError: String?
        do {
            archive = try conversationPersistence.load()
            persistenceError = nil
        } catch {
            archive = .empty
            persistenceError = "Conversation history could not be loaded. The original archive was left unchanged."
        }
        let initialConversation = AgentConversation()
        self.conversations = archive.conversations.isEmpty ? [initialConversation] : archive.conversations
        self.activeConversationID = archive.activeConversationID.flatMap { candidate in
            archive.conversations.contains(where: { $0.id == candidate }) ? candidate : nil
        } ?? archive.conversations.first?.id ?? initialConversation.id
        self.contextCapturer = contextCapturer
        self.streamFactory = streamFactory
        self.settingsStore = settingsStore
        self.providerSession = providerSession
        self.clipboardManager = clipboardManager
        self.conversationPersistence = conversationPersistence
        self.attachmentImporter = attachmentImporter
        self.liveSelectionObserver = liveSelectionObserver
        self.conversationPersistenceEnabled = persistenceError == nil
        self.persistenceStatus = persistenceError
        self.responseDisplayID = nil
        self.metrics = metrics ?? PerformanceMetrics()
    }

    deinit {
        streamTask?.cancel()
        liveContextTask?.cancel()
    }

    func beginInvocation() {
        cancelAllTasks()

        let invocationID = UUID()
        activeInvocationID = invocationID
        session = .idle
        selectedAction = .explain
        userPrompt = ""
        contextGuidance = nil
        retryRequest = nil
        responseConversationID = nil
        responseDisplayID = nil
        metrics.beginInvocation()

        // AX reads are intentionally short and synchronous. Finishing them in
        // this hot-key turn prevents the source app from changing focus or
        // replacing the selection before capability and bounds are captured.
        let result = contextCapturer.captureContext(directInput: nil)
        finishCapture(result, invocationID: invocationID)
        liveSelectionObserver?.start { [weak self] processID in
            self?.refreshLiveContext(from: processID)
        }
        startLiveContextUpdates(invocationID: invocationID)
    }

    func selectAction(_ action: PromptAction) {
        selectedAction = action
        if session.phase == .idle || session.phase == .contextCaptured {
            session.apply(.prompting)
        }
    }

    func runAction(_ action: PromptAction) {
        guard action != .rewrite || session.context?.canReplaceSelection == true else { return }
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

        let sensitiveContext = context.map {
            $0.source == .clipboard || $0.source == .selectionCopy
                ? SensitiveTextDetector.containsSensitiveClipboardValue($0.text)
                : SensitiveTextDetector.containsCredential(in: $0.text)
        } ?? false
        guard !sensitiveContext,
              !SensitiveTextDetector.containsCredential(in: normalizedPrompt)
        else {
            session.apply(.failed("This content appears to contain a credential and was not sent."))
            return
        }

        let credentials: ProviderCredentials
        do {
            credentials = try providerSession.credentialsForRequest()
        } catch {
            session.apply(.failed(Self.safeMessage(for: error)))
            return
        }

        cancelStreamTask()
        let conversationID = activeConversationID
        let history = AgentContextPolicy.historyForRequest(activeConversation?.messages ?? [])
        let attachments = activeConversation?.attachments ?? []
        let actionTitle = selectedAction.title(in: settingsStore.current.settingsLanguage)
        let visibleUserMessage: String
        if !normalizedPrompt.isEmpty {
            visibleUserMessage = normalizedPrompt
        } else if session.context != nil {
            visibleUserMessage = "\(actionTitle) \(settingsStore.current.settingsLanguage == .simplifiedChinese ? "选中的内容" : "the selected context")"
        } else {
            visibleUserMessage = actionTitle
        }
        appendMessage(.init(role: .user, content: visibleUserMessage), to: conversationID)
        responseConversationID = conversationID
        let request = LLMRequest(
            action: selectedAction,
            context: context,
            userPrompt: session.context == nil || normalizedPrompt.isEmpty ? nil : normalizedPrompt,
            history: history,
            sessionID: conversationID,
            userSystemPrompt: settingsStore.current.userSystemPrompt,
            attachments: attachments
        )
        retryRequest = request
        userPrompt = ""
        startStream(
            request: request,
            configuration: configuration,
            credentials: credentials,
            invocationID: invocationID
        )
    }

    func submit(action: PromptAction, userPrompt: String) {
        selectedAction = action
        self.userPrompt = userPrompt
        submit()
    }

    func toggleInvocation() {
        if hasActiveInvocation {
            // A repeated shortcut raises the persistent panel. Closing is an
            // explicit Esc or close-button action. Refresh synchronously here
            // so a just-selected range is visible without waiting for the
            // background sampler's next short interval.
            refreshShortcutContext()
            onPresentPanel?()
        } else {
            beginInvocation()
        }
    }

    func retry() {
        guard session.phase == .failed,
              let request = retryRequest,
              let invocationID = activeInvocationID,
              let configuration = currentConfiguration
        else { return }
        do {
            let credentials = try providerSession.credentialsForRequest()
            responseConversationID = activeConversationID
            startStream(
                request: request,
                configuration: configuration,
                credentials: credentials,
                invocationID: invocationID
            )
        } catch {
            session.apply(.failed(Self.safeMessage(for: error)))
        }
    }

    var activeConversation: AgentConversation? {
        conversations.first(where: { $0.id == activeConversationID })
    }

    func newConversation() {
        let synchronizedContext = refreshedSelectionContext() ?? session.context
        cancelStreamTask()
        let conversation = AgentConversation()
        conversations.insert(conversation, at: 0)
        activeConversationID = conversation.id
        resetConversationSurface(with: synchronizedContext)
        userPrompt = ""
        attachmentStatus = nil
        retryRequest = nil
        responseDisplayID = nil
        persistConversations()
    }

    func selectConversation(_ id: UUID) {
        guard conversations.contains(where: { $0.id == id }) else { return }
        let synchronizedContext = refreshedSelectionContext() ?? session.context
        cancelStreamTask()
        activeConversationID = id
        resetConversationSurface(with: synchronizedContext)
        userPrompt = ""
        attachmentStatus = nil
        retryRequest = nil
        responseDisplayID = nil
        persistConversations()
    }

    func deleteConversation(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        let removed = conversations.remove(at: index)
        for attachment in removed.attachments {
            try? attachmentImporter.remove(attachment)
        }
        if conversations.isEmpty {
            conversations = [AgentConversation()]
        }
        if activeConversationID == id {
            activeConversationID = conversations[0].id
        }
        persistConversations()
    }

    func addAttachments(_ urls: [URL]) {
        let conversationID = activeConversationID
        let importer = attachmentImporter
        attachmentStatus = "Importing \(urls.count) file\(urls.count == 1 ? "" : "s")…"
        Task { [weak self] in
            let results = await Task.detached {
                urls.map { url -> Result<AgentAttachment, Error> in
                    Result { try importer.importFile(at: url, conversationID: conversationID) }
                }
            }.value
            guard let self, self.activeConversationID == conversationID else { return }
            var imported = 0
            var failures: [String] = []
            for result in results {
                switch result {
                case let .success(attachment):
                    self.addAttachment(attachment, to: conversationID)
                    imported += 1
                case let .failure(error):
                    failures.append(error.localizedDescription)
                }
            }
            if failures.isEmpty {
                self.attachmentStatus = "Added \(imported) file\(imported == 1 ? "" : "s")."
            } else {
                self.attachmentStatus = failures.joined(separator: " ")
            }
        }
    }

    func removeAttachment(_ id: UUID) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == activeConversationID }),
              let attachmentIndex = conversations[conversationIndex].attachments.firstIndex(where: { $0.id == id })
        else { return }
        let attachment = conversations[conversationIndex].attachments.remove(at: attachmentIndex)
        try? attachmentImporter.remove(attachment)
        conversations[conversationIndex].updatedAt = Date()
        persistConversations()
    }

    func copyResponse() {
        guard session.phase == .completed, !session.response.isEmpty else { return }
        clipboardManager.writeText(session.response)
    }

    func openSettings() {
        onOpenSettings?()
    }

    func cancelAndDismiss() {
        cancelActiveRequest()
        onDismissPanel?()
    }

    /// Called when the user explicitly closes the panel or the app terminates.
    func cancelActiveRequest() {
        activeInvocationID = nil
        cancelAllTasks()
        session = .idle
        session.apply(.cancelled)
        userPrompt = ""
        contextGuidance = nil
        retryRequest = nil
        responseConversationID = nil
        responseDisplayID = nil
    }

    func panelDidDismiss() {
        cancelActiveRequest()
    }

    func dismissWithoutCancellation() {
        cancelAndDismiss()
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

    /// While the panel remains open, keep its pending context aligned with a
    /// selection the user makes in another application. The initial hot-key
    /// capture still owns clipboard fallback; live refreshes are AX-only so a
    /// background clipboard change can never silently replace the context.
    private func startLiveContextUpdates(invocationID: UUID) {
        liveContextTask?.cancel()
        liveContextTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self, self.activeInvocationID == invocationID else {
                    return
                }
                self.refreshLiveContext()
            }
        }
    }

    private func refreshLiveContext(from processID: pid_t? = nil) {
        guard session.phase != .streaming else { return }
        if let context = refreshedSelectionContext(from: processID) {
            guard context != session.context else { return }
            session.apply(.contextCaptured(context))
            contextGuidance = context.guidance
            if selectedAction == .rewrite, !context.canReplaceSelection {
                selectedAction = .explain
            }
            return
        }

        // A process-scoped observer reports selection changes from another
        // application, including deselection. That is an explicit clear. The
        // polling path has no such provenance, so it deliberately keeps the
        // pending context when AX is merely unavailable or FloatDude owns focus.
        guard processID != nil, session.context != nil else { return }
        session.apply(.contextCaptured(nil))
        contextGuidance = "No selection is active. Enter a prompt below."
        if selectedAction == .rewrite {
            selectedAction = .explain
        }
    }

    private func refreshShortcutContext() {
        guard session.phase != .streaming,
              let result = contextCapturer.captureShortcutSelection()
        else { return }
        switch result {
        case let .captured(context):
            guard context != session.context else { return }
            session.apply(.contextCaptured(context))
            contextGuidance = context.guidance
            if selectedAction == .rewrite, !context.canReplaceSelection {
                selectedAction = .explain
            }
        case .unavailable:
            guard session.context != nil else { return }
            session.apply(.contextCaptured(nil))
            contextGuidance = "No selection is active. Enter a prompt below."
            if selectedAction == .rewrite {
                selectedAction = .explain
            }
        case let .rejected(error):
            contextGuidance = nil
            session.apply(.failed(error.localizedDescription))
        }
    }

    private func refreshedSelectionContext(from processID: pid_t? = nil) -> CapturedContext? {
        let result = if let processID {
            contextCapturer.captureLiveSelection(from: processID)
        } else {
            contextCapturer.captureLiveSelection()
        }
        guard case let .captured(context)? = result else {
            return nil
        }
        return context
    }

    private func resetConversationSurface(with context: CapturedContext?) {
        session = .idle
        session.apply(.contextCaptured(context))
        if context == nil {
            session.apply(.prompting)
        } else {
            contextGuidance = context?.guidance
            if selectedAction == .rewrite, context?.canReplaceSelection != true {
                selectedAction = .explain
            }
        }
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
            if let responseConversationID, !session.response.isEmpty {
                appendMessage(
                    .init(
                        id: responseDisplayID ?? UUID(),
                        role: .assistant,
                        content: session.response
                    ),
                    to: responseConversationID
                )
                self.responseConversationID = nil
            }
        }
    }

    private func fail(_ message: String, invocationID: UUID) {
        guard activeInvocationID == invocationID else { return }
        session.apply(.failed(message))
    }

    private func failConfiguration() {
        session.apply(.failed(FloatDudeError.missingConfiguration.localizedDescription))
    }

    private func startStream(
        request: LLMRequest,
        configuration: LLMConfiguration,
        credentials: ProviderCredentials,
        invocationID: UUID
    ) {
        cancelStreamTask()
        responseDisplayID = UUID()
        session.apply(.streaming)
        metrics.markRequestStarted()
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

    private func appendMessage(_ message: AgentMessage, to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()
        if conversations[index].title == "New conversation", message.role == .user {
            let normalized = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            conversations[index].title = String(normalized.prefix(48))
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        persistConversations()
    }

    private func addAttachment(_ attachment: AgentAttachment, to conversationID: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == conversationID }) else { return }
        conversations[index].attachments.append(attachment)
        conversations[index].updatedAt = Date()
        persistConversations()
    }

    private func persistConversations() {
        guard conversationPersistenceEnabled else { return }
        do {
            try conversationPersistence.save(ConversationArchive(
                activeConversationID: activeConversationID,
                conversations: conversations
            ))
        } catch {
            persistenceStatus = "Conversation history could not be saved."
        }
    }

    private func cancelStreamTask() {
        streamTask?.cancel()
        streamTask = nil
    }

    private func cancelAllTasks() {
        cancelStreamTask()
        liveContextTask?.cancel()
        liveContextTask = nil
        liveSelectionObserver?.stop()
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
