import Foundation

struct LLMConfiguration: Sendable, Equatable {
    let baseURL: URL
    let model: String
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

/// Provider boundary for an OpenAI-compatible Chat Completions streaming client.
protocol LLMClient: Sendable {
    func stream(_ request: LLMRequest) -> AsyncThrowingStream<LLMStreamEvent, Error>
}
