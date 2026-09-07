import Foundation
import XCTest
@testable import FloatDude

final class LLMClientTests: XCTestCase {
    func testStreamsDeltasInOrderAndBuildsSafeChatCompletionsRequest() async throws {
        let transport = FakeTransport { _ in
            FakeTransport.response(chunks: [
                Data("data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}\n\n".utf8),
                Data("data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}\n\ndata: [DONE]\n\n".utf8)
            ])
        }
        let client = try OpenAIChatCompletionsClient(
            configuration: LLMConfiguration(baseURL: URL(string: "http://127.0.0.1:4321///")!, model: "demo-model"),
            apiKey: "test-api-key",
            transport: transport,
            prompts: PromptActions(preferredLanguage: "Chinese")
        )

        let request = LLMRequest(
            action: .translate,
            context: CapturedContext(text: "Hello", source: .directInput, applicationName: nil),
            userPrompt: nil
        )
        var events: [LLMStreamEvent] = []
        for try await event in client.stream(request) {
            events.append(event)
        }

        XCTAssertEqual(events, [.textDelta("Hel"), .textDelta("lo"), .completed])
        let sent = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.absoluteString, "http://127.0.0.1:4321/v1/chat/completions")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertTrue(sent.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")

        let body = try XCTUnwrap(sent.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "demo-model")
        XCTAssertEqual(json["stream"] as? Bool, true)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[0]["content"] as? String, SoftwareRootPrompt.text)
        XCTAssertTrue((messages.last?["content"] as? String)?.contains("Requested action: Translate") == true)
        XCTAssertEqual((json["tools"] as? [[String: Any]])?.count, 2)
        XCTAssertNil(json["prompt_cache_key"])
        XCTAssertNil(json["prompt_cache_retention"])
    }

    func testAnthropicDialectBuildsMessagesRequestAndStreamsTextDeltas() async throws {
        let transport = FakeTransport { _ in
            FakeTransport.response(chunks: [
                Data("event: message_start\ndata: {\"type\":\"message_start\"}\n\n".utf8),
                Data("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\n".utf8),
                Data("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\" DeepSeek\"}}\n\n".utf8),
                Data("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n".utf8)
            ])
        }
        let client = try OpenAIChatCompletionsClient(
            configuration: LLMConfiguration(
                baseURL: URL(string: "https://api.deepseek.com/anthropic")!,
                model: "deepseek-v4-flash"
            ),
            apiKey: "test-api-key",
            transport: transport
        )

        var events: [LLMStreamEvent] = []
        for try await event in client.stream(
            LLMRequest(
                action: .explain,
                context: CapturedContext(text: "source", source: .clipboard, applicationName: nil),
                userPrompt: nil
            )
        ) {
            events.append(event)
        }

        XCTAssertEqual(events, [.textDelta("Hello"), .textDelta(" DeepSeek"), .completed])
        let request = try XCTUnwrap(transport.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/anthropic/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-api-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "deepseek-v4-flash")
        XCTAssertEqual(json["max_tokens"] as? Int, 4096)
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertTrue((json["system"] as? String)?.hasPrefix(SoftwareRootPrompt.text) == true)
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: String]])
        XCTAssertEqual(content[0]["type"], "text")
        XCTAssertTrue(content[0]["text"]?.contains("Requested action: Explain") == true)
        XCTAssertTrue(content[0]["text"]?.contains("source") == true)
        XCTAssertEqual((json["tools"] as? [[String: Any]])?.count, 2)
    }

    func testNoAuthenticationSendsNoAuthenticationHeaders() async throws {
        let transport = FakeTransport { _ in
            FakeTransport.response(chunks: [
                Data("data: [DONE]\n\n".utf8)
            ])
        }
        let client = try OpenAIChatCompletionsClient(
            configuration: LLMConfiguration(
                baseURL: URL(string: "https://provider.example")!,
                model: "demo-model"
            ),
            credentials: ProviderCredentials(mode: .noAuthentication),
            transport: transport
        )

        var events: [LLMStreamEvent] = []
        for try await event in client.stream(
            LLMRequest(action: .ask, context: nil, userPrompt: "public request")
        ) {
            events.append(event)
        }

        XCTAssertEqual(events, [.completed])
        let request = try XCTUnwrap(transport.lastRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertNil(request.value(forHTTPHeaderField: "anthropic-version"))
    }

    func testOfficialProviderCacheControlsKeepStableRootPrefix() async throws {
        let response: @Sendable (URLRequest) -> LLMHTTPResponse = { _ in
            FakeTransport.response(chunks: [Data("data: [DONE]\n\n".utf8)])
        }
        let openAITransport = FakeTransport(handler: response)
        let openAI = try OpenAIChatCompletionsClient(
            configuration: LLMConfiguration(baseURL: URL(string: "https://api.openai.com")!, model: "gpt-test"),
            apiKey: "key",
            transport: openAITransport
        )
        let sessionID = UUID()
        for try await _ in openAI.stream(LLMRequest(
            action: .ask,
            context: nil,
            userPrompt: "Hello",
            sessionID: sessionID
        )) {}
        let openAIBody = try XCTUnwrap(openAITransport.lastRequest?.httpBody)
        let openAIJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: openAIBody) as? [String: Any])
        XCTAssertEqual(openAIJSON["prompt_cache_retention"] as? String, "24h")
        XCTAssertEqual(
            openAIJSON["prompt_cache_key"] as? String,
            "\(SoftwareRootPrompt.version):\(sessionID.uuidString)"
        )

        let anthropicTransport = FakeTransport { _ in
            FakeTransport.response(chunks: [Data("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n".utf8)])
        }
        let anthropic = try OpenAIChatCompletionsClient(
            configuration: LLMConfiguration(
                baseURL: URL(string: "https://api.anthropic.com")!,
                model: "claude-test",
                apiFormat: .anthropicMessages
            ),
            apiKey: "key",
            transport: anthropicTransport
        )
        for try await _ in anthropic.stream(LLMRequest(action: .ask, context: nil, userPrompt: "Hello")) {}
        let anthropicBody = try XCTUnwrap(anthropicTransport.lastRequest?.httpBody)
        let anthropicJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: anthropicBody) as? [String: Any])
        let system = try XCTUnwrap(anthropicJSON["system"] as? [[String: Any]])
        XCTAssertEqual(system[0]["text"] as? String, SoftwareRootPrompt.text)
        XCTAssertEqual((system[0]["cache_control"] as? [String: String])?["type"], "ephemeral")
    }

    func testModelCatalogClientRequestsModelsWithProviderAuthentication() async throws {
        URLProtocolStub.configure(chunks: [Data(#"{"data":[{"id":"model-b"},{"id":"model-a"}]}"#.utf8)])
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [URLProtocolStub.self]
        let client = ModelCatalogClient(session: URLSession(configuration: sessionConfiguration))

        let models = try await client.fetchModels(
            configuration: LLMConfiguration(
                baseURL: URL(string: "https://provider.example/api")!,
                model: "model-a"
            ),
            credentials: ProviderCredentials(mode: .thisSessionOnly, apiKey: "test-key")
        )

        XCTAssertEqual(models, ["model-a", "model-b"])
        XCTAssertEqual(URLProtocolStub.lastRequest?.url?.absoluteString, "https://provider.example/api/v1/models")
        XCTAssertEqual(URLProtocolStub.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
    }

    func testModelCatalogErrorRedactsStoredCredential() async throws {
        URLProtocolStub.configure(
            chunks: [Data(#"{"error":{"message":"rejected Bearer secret-model-key"}}"#.utf8)],
            statusCode: 401
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [URLProtocolStub.self]
        let client = ModelCatalogClient(session: URLSession(configuration: sessionConfiguration))

        do {
            _ = try await client.fetchModels(
                configuration: LLMConfiguration(baseURL: URL(string: "https://provider.example")!, model: "model"),
                credentials: ProviderCredentials(mode: .thisSessionOnly, apiKey: "secret-model-key")
            )
            XCTFail("Expected model test failure")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("secret-model-key"))
        }
    }

    func testIncompleteOpenAIAndAnthropicStreamsFailInsteadOfCompleting() async throws {
        let openAI = try OpenAIChatCompletionsClient(
            configuration: LLMConfiguration(baseURL: URL(string: "https://provider.example")!, model: "demo-model"),
            apiKey: "test-api-key",
            transport: FakeTransport { _ in
                FakeTransport.response(chunks: [
                    Data("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n".utf8)
                ])
            }
        )
        let anthropic = try OpenAIChatCompletionsClient(
            configuration: LLMConfiguration(
                baseURL: URL(string: "https://api.deepseek.com/anthropic")!,
                model: "deepseek-v4-flash"
            ),
            apiKey: "test-api-key",
            transport: FakeTransport { _ in
                FakeTransport.response(chunks: [
                    Data("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"partial\"}}\n\n".utf8)
                ])
            }
        )

        for client in [openAI, anthropic] {
            do {
                for try await _ in client.stream(LLMRequest(action: .ask, context: nil, userPrompt: "test")) {}
                XCTFail("Expected incomplete stream failure")
            } catch let error as LLMClientError {
                XCTAssertEqual(error, .incompleteStream)
            }
        }
    }

    func testCredentialLikeContextIsRejectedBeforeOpeningTransport() async throws {
        let transport = FakeTransport { _ in
            FakeTransport.response(chunks: [Data("data: [DONE]\n\n".utf8)])
        }
        let client = try makeClient(transport: transport)
        let sensitiveValue = String(repeating: "e", count: 32)

        do {
            for try await _ in client.stream(LLMRequest(
                action: .translate,
                context: CapturedContext(
                    text: sensitiveValue,
                    source: .clipboard,
                    applicationName: nil
                ),
                userPrompt: nil
            )) {}
            XCTFail("Expected sensitive-content rejection")
        } catch let error as LLMClientError {
            XCTAssertEqual(error, .sensitiveContent)
            XCTAssertFalse(error.localizedDescription.contains(sensitiveValue))
        }
        XCTAssertNil(transport.lastRequest)
    }

    func testProductionURLSessionTransportStreamsThroughURLProtocol() async throws {
        URLProtocolStub.configure(chunks: [
            Data("data: {\"choices\":[{\"delta\":{\"content\":\"local \"}}]}\n\n".utf8),
            Data("data: {\"choices\":[{\"delta\":{\"content\":\"transport\"}}]}\n\ndata: [DONE]\n\n".utf8)
        ])

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let client = try OpenAIChatCompletionsClient(
            configuration: LLMConfiguration(
                baseURL: URL(string: "https://provider.example")!,
                model: "demo-model"
            ),
            apiKey: "test-api-key",
            session: session
        )

        var events: [LLMStreamEvent] = []
        for try await event in client.stream(
            LLMRequest(action: .ask, context: nil, userPrompt: "local test")
        ) {
            events.append(event)
        }

        XCTAssertEqual(events, [.textDelta("local "), .textDelta("transport"), .completed])
        let request = try XCTUnwrap(URLProtocolStub.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://provider.example/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
    }

    func testNormalizesAndRejectsEndpoints() throws {
        let valid = try LLMEndpoint.normalizedBaseURL(URL(string: "https://provider.example///")!)
        XCTAssertEqual(valid.absoluteString, "https://provider.example")

        XCTAssertThrowsError(try LLMEndpoint.normalizedBaseURL(URL(string: "file:///tmp/provider")!))
        XCTAssertThrowsError(try LLMEndpoint.normalizedBaseURL(URL(string: "https://user:password@provider.example")!))
        XCTAssertThrowsError(try LLMEndpoint.normalizedBaseURL(URL(string: "http://provider.example")!))
    }

    func testReportsHTTPAndProviderErrorsWithoutSecretMaterial() async throws {
        let httpTransport = FakeTransport { _ in
            FakeTransport.response(
                statusCode: 401,
                chunks: [Data("{\"error\":{\"message\":\"invalid key test-api-key\"}}".utf8)]
            )
        }
        let client = try makeClient(transport: httpTransport)
        let request = LLMRequest(action: .ask, context: nil, userPrompt: "Hi")

        do {
            for try await _ in client.stream(request) {}
            XCTFail("Expected HTTP error")
        } catch let error as LLMClientError {
            XCTAssertEqual(error, .httpStatus(401, "invalid key [REDACTED]"))
            XCTAssertFalse(error.localizedDescription.contains("test-api-key"))
            XCTAssertFalse(error.localizedDescription.contains("Bearer"))
        }

        let providerTransport = FakeTransport { _ in
            FakeTransport.response(chunks: [
                Data("data: {\"error\":{\"message\":\"provider rejected Bearer test-api-key\"}}\n\n".utf8)
            ])
        }
        let providerClient = try makeClient(transport: providerTransport)
        do {
            for try await _ in providerClient.stream(request) {}
            XCTFail("Expected provider error")
        } catch let error as LLMClientError {
            XCTAssertFalse(error.localizedDescription.contains("test-api-key"))
            XCTAssertFalse(error.localizedDescription.contains("Bearer test-api-key"))
        }
    }

    func testMalformedJSONFailsTheStream() async throws {
        let transport = FakeTransport { _ in
            FakeTransport.response(chunks: [Data("data: {not-json}\n\n".utf8)])
        }
        let client = try makeClient(transport: transport)

        do {
            for try await _ in client.stream(LLMRequest(action: .explain, context: nil, userPrompt: "Hi")) {}
            XCTFail("Expected malformed payload")
        } catch let error as LLMClientError {
            XCTAssertEqual(error, .malformedPayload)
        }
    }

    func testCancellationCancelsTransportAndDiscardsLateDeltas() async throws {
        let body = ControlledBody()
        let cancellation = CancellationRecorder()
        let firstEvent = OneShotSignal()
        let transport = FakeTransport { _ in
            LLMHTTPResponse(body: body.stream, cancellation: {
                cancellation.mark()
                body.finish()
            })
        }
        let client = try makeClient(transport: transport)
        let consumingTask = Task<[LLMStreamEvent], Never> {
            var result: [LLMStreamEvent] = []
            do {
                for try await event in client.stream(LLMRequest(action: .ask, context: nil, userPrompt: "Hi")) {
                    result.append(event)
                    if result.count == 1 {
                        firstEvent.signal()
                    }
                }
            } catch {
                // Cancellation is asserted through the transport and returned events below.
            }
            return result
        }

        body.send(Data("data: {\"choices\":[{\"delta\":{\"content\":\"first\"}}]}\n\n".utf8))
        await firstEvent.wait()
        consumingTask.cancel()
        body.send(Data("data: {\"choices\":[{\"delta\":{\"content\":\"late\"}}]}\n\n".utf8))
        body.finish()
        let events = await consumingTask.value

        XCTAssertEqual(events, [.textDelta("first")])
        XCTAssertTrue(cancellation.wasCalled)
    }

    func testAgentExecutesWriteToolAndContinuesToFinalAnswer() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatDude-ToolLoop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let toolEvent = ##"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-1","function":{"name":"write","arguments":"{\"name\":\"tool-output\",\"content\":\"# Saved\"}"}}]}}]}"##
            + "\n\ndata: [DONE]\n\n"
        let finalEvent = #"data: {"choices":[{"delta":{"content":"Saved the artifact."}}]}"#
            + "\n\ndata: [DONE]\n\n"
        let transport = SequencedTransport(responses: [
            FakeTransport.response(chunks: [Data(toolEvent.utf8)]),
            FakeTransport.response(chunks: [Data(finalEvent.utf8)]),
        ])
        let client = try OpenAIChatCompletionsClient(
            configuration: LLMConfiguration(baseURL: URL(string: "https://provider.example")!, model: "demo"),
            credentials: ProviderCredentials(mode: .thisSessionOnly, apiKey: "test-key"),
            transport: transport,
            toolExecutor: NativeToolExecutor(exportDirectory: directory)
        )

        var events: [LLMStreamEvent] = []
        for try await event in client.stream(LLMRequest(
            action: .ask,
            context: nil,
            userPrompt: "Write an artifact",
            history: [AgentMessage(role: .user, content: "Earlier question"),
                      AgentMessage(role: .assistant, content: "Earlier answer")],
            userSystemPrompt: "Prefer concise answers."
        )) {
            events.append(event)
        }

        XCTAssertEqual(events, [.textDelta("Saved the artifact."), .completed])
        XCTAssertEqual(transport.requestCount, 2)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("tool-output.md"), encoding: .utf8), "# Saved")
        let finalBody = try XCTUnwrap(transport.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: finalBody) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertTrue(messages.contains { $0["role"] as? String == "tool" })
        XCTAssertEqual(messages[0]["content"] as? String, SoftwareRootPrompt.text)
        XCTAssertEqual(messages[1]["content"] as? String, "Prefer concise answers.")
    }

    func testAnthropicAgentExecutesReadToolAndContinues() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatDude-AnthropicTool-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("notes.md")
        try Data("Attachment evidence".utf8).write(to: file)
        let attachment = AgentAttachment(
            displayName: "notes.md",
            kind: .markdown,
            storedPath: file.path,
            byteCount: 19
        )
        let arguments = "{\"attachment_id\":\"\(attachment.id.uuidString)\",\"offset\":0,\"limit\":100}"
        let encodedArguments = arguments
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let toolEvents = [
            "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"read-1\",\"name\":\"read\",\"input\":{}}}\n\n",
            "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"\(encodedArguments)\"}}\n\n",
            "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n",
        ].map { Data($0.utf8) }
        let finalEvents = [
            Data("event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Read complete.\"}}\n\n".utf8),
            Data("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n".utf8),
        ]
        let transport = SequencedTransport(responses: [
            FakeTransport.response(chunks: toolEvents),
            FakeTransport.response(chunks: finalEvents),
        ])
        let client = try OpenAIChatCompletionsClient(
            configuration: LLMConfiguration(
                baseURL: URL(string: "https://provider.example/anthropic")!,
                model: "claude-test"
            ),
            credentials: ProviderCredentials(mode: .thisSessionOnly, apiKey: "key"),
            transport: transport,
            toolExecutor: NativeToolExecutor(
                exportDirectory: directory.appendingPathComponent("exports"),
                attachmentRoot: directory
            )
        )

        var events: [LLMStreamEvent] = []
        for try await event in client.stream(LLMRequest(
            action: .ask,
            context: nil,
            userPrompt: "Read the attachment",
            attachments: [attachment]
        )) {
            events.append(event)
        }

        XCTAssertEqual(events, [.textDelta("Read complete."), .completed])
        XCTAssertEqual(transport.requestCount, 2)
        let body = try XCTUnwrap(transport.lastRequest?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let toolResultMessage = try XCTUnwrap(messages.last)
        let content = try XCTUnwrap(toolResultMessage["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "tool_result")
        XCTAssertTrue((content[0]["content"] as? String)?.contains("Attachment evidence") == true)
    }

    private func makeClient(transport: any LLMStreamingTransport) throws -> OpenAIChatCompletionsClient {
        try OpenAIChatCompletionsClient(
            configuration: LLMConfiguration(baseURL: URL(string: "https://provider.example")!, model: "demo-model"),
            apiKey: "test-api-key",
            transport: transport
        )
    }
}

private final class FakeTransport: LLMStreamingTransport, @unchecked Sendable {
    private let handler: @Sendable (URLRequest) -> LLMHTTPResponse
    private let lock = NSLock()
    private var request: URLRequest?

    init(handler: @escaping @Sendable (URLRequest) -> LLMHTTPResponse) {
        self.handler = handler
    }

    var lastRequest: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }

    func open(_ request: URLRequest) async throws -> LLMHTTPResponse {
        record(request: request)
        return handler(request)
    }

    private func record(request: URLRequest) {
        lock.lock()
        self.request = request
        lock.unlock()
    }

    static func response(statusCode: Int = 200, chunks: [Data]) -> LLMHTTPResponse {
        let body = AsyncThrowingStream<Data, Error> { continuation in
            Task {
                for chunk in chunks {
                    _ = continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
        return LLMHTTPResponse(statusCode: statusCode, body: body)
    }
}

private final class SequencedTransport: LLMStreamingTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [LLMHTTPResponse]
    private var requests: [URLRequest] = []

    init(responses: [LLMHTTPResponse]) {
        self.responses = responses
    }

    var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return requests.count
    }

    var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests.last
    }

    func open(_ request: URLRequest) async throws -> LLMHTTPResponse {
        lock.withLock {
            requests.append(request)
            return responses.removeFirst()
        }
    }
}

private final class ControlledBody: @unchecked Sendable {
    let stream: AsyncThrowingStream<Data, Error>
    private let lock = NSLock()
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?

    init() {
        var continuation: AsyncThrowingStream<Data, Error>.Continuation!
        stream = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    func send(_ data: Data) {
        lock.lock()
        let continuation = self.continuation
        lock.unlock()
        _ = continuation?.yield(data)
    }

    func finish() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.finish()
    }
}

private final class CancellationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var wasCalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func mark() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

private final class OneShotSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var signalled = false

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if signalled {
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func signal() {
        lock.lock()
        signalled = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var chunks: [Data] = []
        var request: URLRequest?
        var statusCode = 200
    }

    private static let state = State()

    static var lastRequest: URLRequest? {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.request
    }

    static func configure(chunks: [Data], statusCode: Int = 200) {
        state.lock.lock()
        state.chunks = chunks
        state.request = nil
        state.statusCode = statusCode
        state.lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "provider.example"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let chunks: [Data]
        let statusCode: Int
        Self.state.lock.lock()
        Self.state.request = request
        chunks = Self.state.chunks
        statusCode = Self.state.statusCode
        Self.state.lock.unlock()

        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: statusCode,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["Content-Type": "text/event-stream"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
