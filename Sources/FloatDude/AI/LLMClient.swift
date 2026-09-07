import Foundation

enum LLMAPIFormat: String, Codable, Sendable, Equatable {
    case openAIChatCompletions
    case anthropicMessages

    static func inferred(from baseURL: URL) -> Self {
        let lastPathComponent = baseURL.path
            .split(separator: "/")
            .last
            .map(String.init)
            .map { $0.lowercased() }
        return lastPathComponent == "anthropic" ? .anthropicMessages : .openAIChatCompletions
    }
}

struct LLMConfiguration: Sendable, Equatable {
    let baseURL: URL
    let model: String
    let apiFormat: LLMAPIFormat

    init(baseURL: URL, model: String, apiFormat: LLMAPIFormat? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.apiFormat = apiFormat ?? .inferred(from: baseURL)
    }
}

struct LLMRequest: Sendable, Equatable {
    let action: PromptAction
    let context: CapturedContext?
    let userPrompt: String?
}

enum LLMStreamEvent: Sendable, Equatable {
    case textDelta(String)
    case completed
}

enum LLMClientError: LocalizedError, Sendable, Equatable {
    case invalidEndpoint
    case missingAPIKey
    case missingModel
    case cancelled
    case transport(String)
    case httpStatus(Int, String)
    case provider(String)
    case malformedPayload
    case incompleteStream

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "The configured endpoint is invalid or unsafe."
        case .missingAPIKey:
            "Configure an API key before using FloatDude."
        case .missingModel:
            "Configure a model before using FloatDude."
        case .cancelled:
            "The request was cancelled."
        case let .transport(message):
            message
        case let .httpStatus(status, message):
            message.isEmpty ? "The provider returned HTTP \(status)." : "The provider returned HTTP \(status): \(message)"
        case let .provider(message):
            "The provider returned an error: \(message)"
        case .malformedPayload:
            "The provider returned a malformed streaming response."
        case .incompleteStream:
            "The provider closed the streaming response before completion."
        }
    }
}

struct LLMHTTPResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: AsyncThrowingStream<Data, Error>
    private let cancellation: @Sendable () -> Void

    init(
        statusCode: Int = 200,
        headers: [String: String] = [:],
        body: AsyncThrowingStream<Data, Error>,
        cancellation: @escaping @Sendable () -> Void = {}
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation()
    }
}

protocol LLMStreamingTransport: Sendable {
    func open(_ request: URLRequest) async throws -> LLMHTTPResponse
}

enum LLMEndpoint {
    static func normalizedBaseURL(_ url: URL) throws -> URL {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty,
              ["https", "http"].contains(scheme),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw LLMClientError.invalidEndpoint
        }

        if scheme == "http" && !isLoopback(host) {
            throw LLMClientError.invalidEndpoint
        }

        var normalized = components
        var path = normalized.percentEncodedPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/" {
            path = ""
        }
        normalized.percentEncodedPath = path

        guard let result = normalized.url else {
            throw LLMClientError.invalidEndpoint
        }
        return result
    }

    static func chatCompletionsURL(for baseURL: URL) throws -> URL {
        let normalized = try normalizedBaseURL(baseURL)
        return normalized.appendingPathComponent("v1").appendingPathComponent("chat/completions")
    }

    static func anthropicMessagesURL(for baseURL: URL) throws -> URL {
        let normalized = try normalizedBaseURL(baseURL)
        return normalized.appendingPathComponent("v1").appendingPathComponent("messages")
    }

    private static func isLoopback(_ host: String) -> Bool {
        let lowercased = host.lowercased()
        return lowercased == "localhost"
            || lowercased == "127.0.0.1"
            || lowercased == "::1"
            || lowercased == "[::1]"
    }
}

enum LLMSecretRedactor {
    static func redact(_ message: String, apiKey: String) -> String {
        var result = message
        if !apiKey.isEmpty {
            result = result.replacingOccurrences(of: apiKey, with: "[REDACTED]")
        }

        let patterns = [
            #"(?i)(authorization\s*:\s*bearer\s+)[^\s,}\]]+"#,
            #"(?i)(bearer\s+)[^\s,}\]]+"#,
            #"(?i)(api[-_ ]?key\s*[=:]\s*["']?)[^\s,"'}]+"#,
            #"(?i)(x-api-key\s*:\s*)[^\s,}\]]+"#
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "$1[REDACTED]",
                options: .regularExpression
            )
        }
        return result
    }
}

/// Provider boundary for OpenAI Chat Completions and Anthropic Messages streaming clients.
protocol LLMClient: Sendable {
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error>
}
