import Foundation

struct OpenAIChatCompletionsClient: LLMClient, Sendable {
    private let configuration: LLMConfiguration
    private let credentials: ProviderCredentials
    private let transport: any LLMStreamingTransport
    private let prompts: any PromptActionProviding
    private let endpointURL: URL
    private let toolExecutor: NativeToolExecutor

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
        prompts: any PromptActionProviding = PromptActions(),
        toolExecutor: NativeToolExecutor = NativeToolExecutor()
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
        self.toolExecutor = toolExecutor
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
        var exchanges: [ToolExchange] = []
        for _ in 0..<8 {
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
            urlRequest.httpBody = try requestBody(for: request, exchanges: exchanges)

            let response = try await transport.open(urlRequest)
            let pass = try await withTaskCancellationHandler(
                operation: {
                    defer { response.cancel() }
                    return try await consumePass(response, continuation: continuation, gate: gate)
                },
                onCancel: {
                    gate.cancel()
                    response.cancel()
                }
            )
            if pass.toolCalls.isEmpty {
                _ = continuation.yield(.completed)
                return
            }
            let results = try pass.toolCalls.map {
                try toolExecutor.execute($0, attachments: request.attachments)
            }
            exchanges.append(ToolExchange(calls: pass.toolCalls, results: results))
        }
        throw AgentEngineError.toolLimitReached
    }

    private func consumePass(
        _ response: LLMHTTPResponse,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation,
        gate: StreamCancellationGate
    ) async throws -> ModelPass {
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
        var pass = ModelPass()

        for try await chunk in response.body {
            try checkCancellation(gate)
            let events = try parser.append(chunk)
            for event in events {
                try consume(event, pass: &pass, continuation: continuation, gate: gate)
            }
            if pass.completed {
                return pass
            }
        }

        let finalEvents = try parser.finish()
        for event in finalEvents {
            try consume(event, pass: &pass, continuation: continuation, gate: gate)
        }
        if !pass.completed {
            throw LLMClientError.incompleteStream
        }
        return pass
    }

    private func consume(
        _ event: SSEEvent,
        pass: inout ModelPass,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation,
        gate: StreamCancellationGate
    ) throws {
        try checkCancellation(gate)
        switch configuration.apiFormat {
        case .openAIChatCompletions:
            try consumeOpenAI(
                event,
                pass: &pass,
                continuation: continuation,
                gate: gate
            )
        case .anthropicMessages:
            try consumeAnthropic(
                event,
                pass: &pass,
                continuation: continuation,
                gate: gate
            )
        }
    }

    private func consumeOpenAI(
        _ event: SSEEvent,
        pass: inout ModelPass,
        continuation: AsyncThrowingStream<LLMStreamEvent, Error>.Continuation,
        gate: StreamCancellationGate
    ) throws {
        if event.data == "[DONE]" {
            pass.completed = true
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
            if let content = choice.delta?.content, !content.isEmpty {
                try checkCancellation(gate)
                _ = continuation.yield(.textDelta(content))
            }
            for toolDelta in choice.delta?.toolCalls ?? [] {
                pass.openAITools.append(toolDelta)
            }
        }
    }

    private func consumeAnthropic(
        _ event: SSEEvent,
        pass: inout ModelPass,
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
            pass.completed = true
        case "error":
            let providerMessage = message.error?.message ?? "Unknown provider error"
            throw LLMClientError.provider(
                LLMSecretRedactor.redact(providerMessage, apiKey: credentials.apiKey ?? "")
            )
        case "content_block_delta":
            if message.delta?.type == "text_delta",
               let text = message.delta?.text,
               !text.isEmpty {
                try checkCancellation(gate)
                _ = continuation.yield(.textDelta(text))
            } else if message.delta?.type == "input_json_delta",
                      let partial = message.delta?.partialJSON,
                      let index = message.index {
                pass.anthropicTools.appendJSON(partial, at: index)
            }
        case "content_block_start":
            if let index = message.index,
               message.contentBlock?.type == "tool_use",
               let id = message.contentBlock?.id,
               let name = message.contentBlock?.name {
                pass.anthropicTools.start(
                    index: index,
                    id: id,
                    name: name,
                    initialInput: message.contentBlock?.input
                )
            }
        default:
            // message_start, content_block_start, message_delta, ping, and
            // other metadata events do not contribute visible answer text.
            return
        }
    }

    private func requestBody(for request: LLMRequest, exchanges: [ToolExchange]) throws -> Data {
        let context = request.context?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = request.userPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sensitiveContext = request.context.map {
            $0.source == .clipboard
                ? SensitiveTextDetector.containsSensitiveClipboardValue($0.text)
                : SensitiveTextDetector.containsCredential(in: $0.text)
        } ?? false
        guard !sensitiveContext,
              !SensitiveTextDetector.containsCredential(in: prompt ?? "")
        else {
            throw LLMClientError.sensitiveContent
        }
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

        let attachmentIndex = request.attachments.isEmpty ? "" : """

        Attached files available through the read tool:
        \(request.attachments.map { "- \($0.id.uuidString): \($0.displayName) (\($0.kind.displayName))" }.joined(separator: "\n"))
        """
        let actionInstruction = prompts.systemInstruction(for: request.action)
        let currentContent = """
        Requested action: \(request.action.title)
        Action instruction: \(actionInstruction)

        \(userContent)\(attachmentIndex)
        """
        switch configuration.apiFormat {
        case .openAIChatCompletions:
            var messages: [[String: Any]] = [
                ["role": "system", "content": SoftwareRootPrompt.text],
            ]
            if !request.userSystemPrompt.isEmpty {
                messages.append(["role": "system", "content": request.userSystemPrompt])
            }
            messages.append(contentsOf: request.history.map {
                ["role": $0.role.rawValue, "content": $0.content]
            })
            messages.append(["role": "user", "content": currentContent])
            for exchange in exchanges {
                messages.append([
                    "role": "assistant",
                    "content": NSNull(),
                    "tool_calls": exchange.calls.map { call in
                        [
                            "id": call.id,
                            "type": "function",
                            "function": ["name": call.name, "arguments": call.argumentsJSON],
                        ] as [String: Any]
                    },
                ])
                messages.append(contentsOf: exchange.results.map {
                    ["role": "tool", "tool_call_id": $0.callID, "content": $0.content]
                })
            }
            var body: [String: Any] = [
                "model": configuration.model,
                "stream": true,
                "messages": messages,
                "tools": Self.openAIToolDefinitions,
                "tool_choice": "auto",
            ]
            if configuration.baseURL.host?.lowercased() == "api.openai.com" {
                body["prompt_cache_key"] = "\(SoftwareRootPrompt.version):\(request.sessionID.uuidString)"
                body["prompt_cache_retention"] = "24h"
            }
            return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        case .anthropicMessages:
            let officialAnthropic = configuration.baseURL.host?.lowercased() == "api.anthropic.com"
            let system: Any
            var systemBlocks: [[String: Any]] = [[
                "type": "text",
                "text": SoftwareRootPrompt.text,
            ]]
            if officialAnthropic {
                systemBlocks[0]["cache_control"] = ["type": "ephemeral"]
            }
            if !request.userSystemPrompt.isEmpty {
                systemBlocks.append(["type": "text", "text": request.userSystemPrompt])
            }
            system = officialAnthropic
                ? systemBlocks
                : systemBlocks.compactMap { $0["text"] as? String }.joined(separator: "\n\n")

            var messages: [[String: Any]] = request.history.map {
                ["role": $0.role.rawValue, "content": [["type": "text", "text": $0.content]]]
            }
            messages.append(["role": "user", "content": [["type": "text", "text": currentContent]]])
            for exchange in exchanges {
                messages.append([
                    "role": "assistant",
                    "content": exchange.calls.map { call in
                        [
                            "type": "tool_use",
                            "id": call.id,
                            "name": call.name,
                            "input": (try? Self.argumentsObject(call.argumentsJSON)) ?? [:],
                        ] as [String: Any]
                    },
                ])
                messages.append([
                    "role": "user",
                    "content": exchange.results.map { result in
                        [
                            "type": "tool_result",
                            "tool_use_id": result.callID,
                            "content": result.content,
                            "is_error": result.isError,
                        ] as [String: Any]
                    },
                ])
            }
            let body: [String: Any] = [
                "model": configuration.model,
                "max_tokens": 4096,
                "system": system,
                "stream": true,
                "messages": messages,
                "tools": Self.anthropicToolDefinitions,
                "tool_choice": ["type": "auto"],
            ]
            return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
    }

    private static func argumentsObject(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AgentEngineError.invalidToolArguments }
        return object
    }

    private static var readParameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "attachment_id": ["type": "string", "description": "UUID shown in the attached-file index."],
                "offset": ["type": "integer", "minimum": 0],
                "limit": ["type": "integer", "minimum": 1, "maximum": 40_000],
            ],
            "required": ["attachment_id"],
            "additionalProperties": false,
        ]
    }

    private static var writeParameters: [String: Any] {
        [
            "type": "object",
            "properties": [
                "name": ["type": "string", "description": "Safe filename; .md is added when no extension is supplied."],
                "content": ["type": "string", "description": "UTF-8 text or Markdown content."],
            ],
            "required": ["name", "content"],
            "additionalProperties": false,
        ]
    }

    private static var openAIToolDefinitions: [[String: Any]] {
        NativeAgentTool.allCases.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.rawValue,
                    "description": tool.promptDescription,
                    "parameters": tool == .read ? readParameters : writeParameters,
                    "strict": true,
                ] as [String: Any],
            ]
        }
    }

    private static var anthropicToolDefinitions: [[String: Any]] {
        NativeAgentTool.allCases.map { tool in
            [
                "name": tool.rawValue,
                "description": tool.promptDescription,
                "input_schema": tool == .read ? readParameters : writeParameters,
            ]
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
        let toolCalls: [OpenAIToolCallDelta]?

        enum CodingKeys: String, CodingKey {
            case content
            case toolCalls = "tool_calls"
        }
    }
}

private struct OpenAIToolCallDelta: Decodable, Sendable {
    let index: Int
    let id: String?
    let function: FunctionDelta?

    struct FunctionDelta: Decodable, Sendable {
        let name: String?
        let arguments: String?
    }
}

private struct AnthropicStreamEvent: Decodable, Sendable {
    let type: String
    let index: Int?
    let delta: Delta?
    let contentBlock: ContentBlock?
    let error: ProviderError?

    enum CodingKeys: String, CodingKey {
        case type, index, delta, error
        case contentBlock = "content_block"
    }

    struct Delta: Decodable, Sendable {
        let type: String?
        let text: String?
        let partialJSON: String?

        enum CodingKeys: String, CodingKey {
            case type, text
            case partialJSON = "partial_json"
        }
    }

    struct ContentBlock: Decodable, Sendable {
        let type: String
        let id: String?
        let name: String?
        let input: [String: JSONValue]?
    }
}

private enum JSONValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private struct ToolExchange: Sendable {
    let calls: [AgentToolCall]
    let results: [AgentToolResult]
}

private struct ModelPass {
    var completed = false
    var openAITools = OpenAIToolAccumulator()
    var anthropicTools = AnthropicToolAccumulator()

    var toolCalls: [AgentToolCall] {
        let openAI = openAITools.calls
        return openAI.isEmpty ? anthropicTools.calls : openAI
    }
}

private struct OpenAIToolAccumulator {
    private struct Partial {
        var id = ""
        var name = ""
        var arguments = ""
    }

    private var partials: [Int: Partial] = [:]

    mutating func append(_ delta: OpenAIToolCallDelta) {
        var partial = partials[delta.index] ?? Partial()
        if let id = delta.id { partial.id = id }
        if let name = delta.function?.name { partial.name += name }
        if let arguments = delta.function?.arguments { partial.arguments += arguments }
        partials[delta.index] = partial
    }

    var calls: [AgentToolCall] {
        partials.keys.sorted().compactMap { index in
            guard let partial = partials[index], !partial.id.isEmpty, !partial.name.isEmpty else { return nil }
            return AgentToolCall(
                id: partial.id,
                name: partial.name,
                argumentsJSON: partial.arguments.isEmpty ? "{}" : partial.arguments
            )
        }
    }
}

private struct AnthropicToolAccumulator {
    private struct Partial {
        let id: String
        let name: String
        var json: String
    }

    private var partials: [Int: Partial] = [:]

    mutating func start(index: Int, id: String, name: String, initialInput: [String: JSONValue]?) {
        let json: String
        if let initialInput,
           let data = try? JSONEncoder().encode(initialInput),
           let value = String(data: data, encoding: .utf8),
           value != "{}" {
            json = value
        } else {
            json = ""
        }
        partials[index] = Partial(id: id, name: name, json: json)
    }

    mutating func appendJSON(_ fragment: String, at index: Int) {
        guard var partial = partials[index] else { return }
        partial.json += fragment
        partials[index] = partial
    }

    var calls: [AgentToolCall] {
        partials.keys.sorted().compactMap { index in
            guard let partial = partials[index] else { return nil }
            return AgentToolCall(
                id: partial.id,
                name: partial.name,
                argumentsJSON: partial.json.isEmpty ? "{}" : partial.json
            )
        }
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
