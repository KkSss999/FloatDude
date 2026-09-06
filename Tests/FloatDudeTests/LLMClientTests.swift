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
            LLMHTTPResponse(body: body.stream, cancellation: { cancellation.mark() })
        }
        let client = try makeClient(transport: transport)
        let consumingTask = Task { () -> [LLMStreamEvent] in
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
        lock.lock()
        self.request = request
        lock.unlock()
        return handler(request)
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
