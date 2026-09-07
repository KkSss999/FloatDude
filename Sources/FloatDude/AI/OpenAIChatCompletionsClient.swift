import Foundation

struct OpenAIChatCompletionsClient: LLMClient, Sendable {
    private let configuration: LLMConfiguration
    private let credentials: ProviderCredentials
    private let transport: any LLMStreamingTransport
    private let prompts: any PromptActionProviding
    private let endpointURL: URL

    init(
        configuration: LLMConfiguration,
        apiKey: String,
        session: URLSession = .shared,
        prompts: any PromptActionProviding = PromptActions()
    ) throws {
        try self.init(
            configuration: configuration,
            credentials: ProviderCredentials(mode: .thisSessionOnly, apiKey: apiKey),
            transport: URLSessionStreamingTransport(session: session),
            prompts: prompts
        )
    }

    init(
        configuration: LLMConfiguration,
        credentials: ProviderCredentials,
        session: URLSession = .shared,
        prompts: any PromptActionProviding = PromptActions()
    ) throws {
        try self.init(
            configuration: configuration,
            credentials: credentials,
            transport: URLSessionStreamingTransport(session: session),
            prompts: prompts
        )
    }

    init(
        configuration: LLMConfiguration,
        apiKey: String,
        transport: any LLMStreamingTransport,
        prompts: any PromptActionProviding = PromptActions()
    ) throws {
        try self.init(
            configuration: configuration,
            credentials: ProviderCredentials(mode: .thisSessionOnly, apiKey: apiKey),
            transport: transport,
            prompts: prompts
        )
    }

    init(
        configuration: LLMConfiguration,
        credentials: ProviderCredentials,
        transport: any LLMStreamingTransport,
        prompts: any PromptActionProviding = PromptActions()
    ) throws {
        guard credentials.mode == .noAuthentication || credentials.hasAPIKey else {
            throw LLMClientError.missingAPIKey
        }
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMClientError.missingModel
        }

        self.configuration = configuration
        self.credentials = credentials
        self.transport = transport
        self.prompts = prompts
        self.endpointURL = try configuration.apiFormat == .anthropicMessages
            ? LLMEndpoint.anthropicMessagesURL(for: configuration.baseURL)
            : LLMEndpoint.chatCompletionsURL(for: configuration.baseURL)
    }

    init(
        baseURL: URL,
        model: String,
        apiKey: String,
        session: URLSession = .shared,
        prompts: any PromptActionProviding = PromptActions()
    ) throws {
        try self.init(
            configuration: LLMConfiguration(baseURL: baseURL, model: model),
            credentials: ProviderCredentials(mode: .thisSessionOnly, apiKey: apiKey),
            session: session,
            prompts: prompts
        )
    }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let gate = StreamCancellationGate()
        let taskBox = StreamTaskBox()

        let result = AsyncThrowingStream<LLMStreamEvent, Error> { continuation in
            let task = Task {
                do {
                    try await self.run(request, continuation: continuation, gate: gate)
                    continuation.finish()
                } catch {
                    if gate.isCancelled || Task.isCancelled || Self.isCancellation(error) {
                        continuation.finish(throwing: LLMClientError.cancelled)
                    } else {
                        continuation.finish(throwing: Self.redacted(error, apiKey: self.credentials.apiKey ?? ""))
                    }
                }
            }
            taskBox.set(task)
            continuation.onTermination = { @Sendable _ in
                gate.cancel()
                taskBox.cancel()
            }
        }
        return result
    }

    private func run(
        _ request: LLMRequest,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation,
        gate: StreamCancellationGate
    ) async throws {
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        switch credentials.mode {
        case .noAuthentication:
            break
        case .thisSessionOnly, .rememberOnThisMac:
            guard let apiKey = credentials.apiKey, !apiKey.isEmpty else {
                throw LLMClientError.missingAPIKey
            }
            switch configuration.apiFormat {
            case .openAIChatCompletions:
                urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            case .anthropicMessages:
                urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            }
        }
        urlRequest.httpBody = try requestBody(for: request)

        let response = try await transport.open(urlRequest)
        try await withTaskCancellationHandler(
            operation: {
                defer { response.cancel() }
                try await consume(
                    response,
                    continuation: continuation,
                    gate: gate
                )
            },
            onCancel: {
                gate.cancel()
                response.cancel()
            }
        )
    }

    private func consume(
        _ response: LLMHTTPResponse,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation,
        gate: StreamCancellationGate
    ) async throws {
        try checkCancellation(gate)
        guard (200..<300).contains(response.statusCode) else {
            let body = try await collect(response.body, gate: gate, limit: 64 * 1024)
            let message = LLMSecretRedactor.redact(
                Self.providerMessage(from: body) ?? "",
                apiKey: credentials.apiKey ?? ""
            )
            throw LLMClientError.httpStatus(response.statusCode, message)
        }

        var parser = SSEParser()
        var completed = false

        for try await chunk in response.body {
            try checkCancellation(gate)
            let events = try parser.append(chunk)
            for event in events {
                try emit(event, completed: &completed, continuation: continuation, gate: gate)
            }
            if completed {
                return
            }
        }

        let finalEvents = try parser.finish()
        for event in finalEvents {
            try emit(event, completed: &completed, continuation: continuation, gate: gate)
        }
        if !completed {
            throw LLMClientError.incompleteStream
        }
    }

    private func emit(
        _ event: SSEEvent,
        completed: inout Bool,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation,
        gate: StreamCancellationGate
    ) throws {
        try checkCancellation(gate)
        switch configuration.apiFormat {
        case .openAIChatCompletions:
            try emitOpenAI(
                event,
                completed: &completed,
                continuation: continuation,
                gate: gate
            )
        case .anthropicMessages:
            try emitAnthropic(
                event,
                completed: &completed,
                continuation: continuation,
                gate: gate
            )
        }
    }

    private func emitOpenAI(
        _ event: SSEEvent,
        completed: inout Bool,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation,
        gate: StreamCancellationGate
    ) throws {
        if event.data == "[DONE]" {
            if !completed {
                _ = continuation.yield(.completed)
                completed = true
            }
            return
        }
        guard let data = event.data.data(using: .utf8) else {
            throw LLMClientError.malformedPayload
        }
        let chunk: ChatCompletionChunk
        do {
            chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
        } catch {
            throw LLMClientError.malformedPayload
        }

        if let providerError = chunk.error {
            let message = LLMSecretRedactor.redact(providerError.message, apiKey: credentials.apiKey ?? "")
            throw LLMClientError.provider(message)
        }

        for choice in chunk.choices ?? [] {
            guard let content = choice.delta?.content, !content.isEmpty else {
                continue
            }
            try checkCancellation(gate)
            _ = continuation.yield(.textDelta(content))
        }
    }

    private func emitAnthropic(
        _ event: SSEEvent,
        completed: inout Bool,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation,
        gate: StreamCancellationGate
    ) throws {
        guard let data = event.data.data(using: .utf8) else {
            throw LLMClientError.malformedPayload
        }

        let message: AnthropicStreamEvent
        do {
            message = try JSONDecoder().decode(AnthropicStreamEvent.self, from: data)
        } catch {
            throw LLMClientError.malformedPayload
        }

        switch message.type {
        case "message_stop":
            if !completed {
                _ = continuation.yield(.completed)
                completed = true
            }
        case "error":
            let providerMessage = message.error?.message ?? "Unknown provider error"
            throw LLMClientError.provider(
                LLMSecretRedactor.redact(providerMessage, apiKey: credentials.apiKey ?? "")
            )
        case "content_block_delta":
            guard message.delta?.type == "text_delta",
                  let text = message.delta?.text,
                  !text.isEmpty
            else { return }
            try checkCancellation(gate)
            _ = continuation.yield(.textDelta(text))
        default:
            // message_start, content_block_start, message_delta, ping, and
            // other metadata events do not contribute visible answer text.
            return
        }
    }

    private func requestBody(for request: LLMRequest) throws -> Data {
        let context = request.context?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = request.userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let userContent: String
        switch (context?.isEmpty == false, prompt?.isEmpty == false) {
        case (true, true):
            userContent = "Context:\n\(context!)\n\nUser request:\n\(prompt!)"
        case (true, false):
            userContent = context!
        case (false, true):
            userContent = prompt!
        case (false, false):
            userContent = "Please respond to the requested action."
        }

        let systemInstruction = prompts.systemInstruction(for: request.action)
        switch configuration.apiFormat {
        case .openAIChatCompletions:
            let body = ChatCompletionRequest(
                model: configuration.model,
                stream: true,
                messages: [
                    .init(role: "system", content: systemInstruction),
                    .init(role: "user", content: userContent)
                ]
            )
            return try JSONEncoder().encode(body)
        case .anthropicMessages:
            let body = AnthropicMessagesRequest(
                model: configuration.model,
                maxTokens: 4096,
                system: systemInstruction,
                stream: true,
                messages: [
                    .init(role: "user", content: [.init(type: "text", text: userContent)])
                ]
            )
            return try JSONEncoder().encode(body)
        }
    }

    private func collect(
        _ body: AsyncThrowingStream<Data, Error>,
        gate: StreamCancellationGate,
        limit: Int
    ) async throws -> Data {
        var result = Data()
        for try await chunk in body {
            try checkCancellation(gate)
            guard result.count < limit else { break }
            result.append(chunk.prefix(limit - result.count))
        }
        return result
    }

    private func checkCancellation(_ gate: StreamCancellationGate) throws {
        if gate.isCancelled || Task.isCancelled {
            throw LLMClientError.cancelled
        }
    }

    private static func providerMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any]
        else {
            return nil
        }
        return error["message"] as? String
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }

    private static func redacted(_ error: Error, apiKey: String) -> Error {
        guard let clientError = error as? LLMClientError else {
            return LLMClientError.transport(
                LLMSecretRedactor.redact(error.localizedDescription, apiKey: apiKey)
            )
        }
        switch clientError {
        case let .transport(message):
            return LLMClientError.transport(LLMSecretRedactor.redact(message, apiKey: apiKey))
        case let .httpStatus(status, message):
            return LLMClientError.httpStatus(status, LLMSecretRedactor.redact(message, apiKey: apiKey))
        case let .provider(message):
            return LLMClientError.provider(LLMSecretRedactor.redact(message, apiKey: apiKey))
        default:
            return clientError
        }
    }
}

private struct ChatCompletionRequest: Encodable, Sendable {
    let model: String
    let stream: Bool
    let messages: [Message]

    struct Message: Encodable, Sendable {
        let role: String
        let content: String
    }
}

private struct AnthropicMessagesRequest: Encodable, Sendable {
    let model: String
    let maxTokens: Int
    let system: String
    let stream: Bool
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case stream
        case messages
    }

    struct Message: Encodable, Sendable {
        let role: String
        let content: [ContentBlock]
    }

    struct ContentBlock: Encodable, Sendable {
        let type: String
        let text: String
    }
}

private struct ChatCompletionChunk: Decodable, Sendable {
    let choices: [Choice]?
    let error: ProviderError?

    struct Choice: Decodable, Sendable {
        let delta: Delta?
    }

    struct Delta: Decodable, Sendable {
        let content: String?
    }
}

private struct AnthropicStreamEvent: Decodable, Sendable {
    let type: String
    let delta: Delta?
    let error: ProviderError?

    struct Delta: Decodable, Sendable {
        let type: String?
        let text: String?
    }
}

private struct ProviderError: Decodable, Sendable {
    let message: String

    init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(),
           let message = try? singleValue.decode(String.self) {
            self.message = message
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.message = try container.decodeIfPresent(String.self, forKey: .message) ?? "Unknown provider error"
    }

    private enum CodingKeys: String, CodingKey {
        case message
    }
}

private final class StreamCancellationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

private final class StreamTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancelled = false

    func set(_ task: Task<Void, Never>) {
        lock.lock()
        self.task = task
        let shouldCancel = cancelled
        lock.unlock()
        if shouldCancel {
            task.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}

struct URLSessionStreamingTransport: LLMStreamingTransport, @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    init(session: URLSession = .shared) {
        configuration = session.configuration
    }

    func open(_ request: URLRequest) async throws -> LLMHTTPResponse {
        let stream = URLSessionBodyStream(configuration: configuration, request: request)
        return try await withTaskCancellationHandler(
            operation: {
                try await stream.start()
            },
            onCancel: {
                stream.cancel()
            }
        )
    }
}

private final class URLSessionBodyStream: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Metadata: Sendable {
        let statusCode: Int
        let headers: [String: String]
    }

    private let lock = NSLock()
    private let bodyContinuation: AsyncThrowingStream<Data, Error>.Continuation
    private let body: AsyncThrowingStream<Data, Error>
    private let configuration: URLSessionConfiguration
    private let request: URLRequest
    private var responseContinuation: CheckedContinuation<Metadata, Error>?
    private var response: Metadata?
    private var task: URLSessionDataTask?
    private var session: URLSession?

    init(configuration: URLSessionConfiguration, request: URLRequest) {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        body = AsyncThrowingStream { continuation = $0 }
        bodyContinuation = continuation
        self.configuration = configuration
        self.request = request
    }

    func start() async throws -> LLMHTTPResponse {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        install(session: session, task: task)
        task.resume()

        let metadata: Metadata
        do {
            metadata = try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let response {
                    lock.unlock()
                    continuation.resume(returning: response)
                } else {
                    responseContinuation = continuation
                    lock.unlock()
                }
            }
        } catch {
            cancel()
            throw error
        }

        return LLMHTTPResponse(
            statusCode: metadata.statusCode,
            headers: metadata.headers,
            body: body,
            cancellation: { [weak self] in self?.cancel() }
        )
    }

    func cancel() {
        lock.lock()
        let task = self.task
        let waiter = responseContinuation
        responseContinuation = nil
        lock.unlock()
        task?.cancel()
        bodyContinuation.finish(throwing: CancellationError())
        waiter?.resume(throwing: CancellationError())
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            finish(with: LLMClientError.transport("The provider returned an invalid response."))
            return
        }

        let metadata = Metadata(
            statusCode: httpResponse.statusCode,
            headers: httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, item in
                result[String(describing: item.key)] = String(describing: item.value)
            }
        )
        lock.lock()
        self.response = metadata
        let waiter = responseContinuation
        responseContinuation = nil
        lock.unlock()
        waiter?.resume(returning: metadata)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        bodyContinuation.yield(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            bodyContinuation.finish(throwing: error)
        } else {
            bodyContinuation.finish()
        }

        guard response == nil else { return }
        finish(with: error ?? LLMClientError.transport("The provider closed the connection before responding."))
    }

    private func finish(with error: Error) {
        lock.lock()
        let waiter = responseContinuation
        responseContinuation = nil
        lock.unlock()
        waiter?.resume(throwing: error)
    }

    private func install(session: URLSession, task: URLSessionDataTask) {
        lock.lock()
        self.session = session
        self.task = task
        lock.unlock()
    }
}
