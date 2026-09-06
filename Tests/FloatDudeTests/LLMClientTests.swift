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
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages[0]["content"], "Translate the provided text to Chinese. If it is already in Chinese, translate it to English. Return only the translation.")
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
        XCTAssertEqual(json["system"] as? String, "Explain the provided text clearly and concisely.")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: String]])
        XCTAssertEqual(content[0]["type"], "text")
        XCTAssertEqual(content[0]["text"], "source")
    }

    func testNoAuthenticationSendsNoAuthenticationHeaders() async throws {
        let transport = FakeTransport { _ in
            FakeTransport.response(chunks: [
                Data("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n".utf8)
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
    }

    private static let state = State()

    static var lastRequest: URLRequest? {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.request
    }

    static func configure(chunks: [Data]) {
        state.lock.lock()
        state.chunks = chunks
        state.request = nil
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
        Self.state.lock.lock()
        Self.state.request = request
        chunks = Self.state.chunks
        Self.state.lock.unlock()

        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
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
