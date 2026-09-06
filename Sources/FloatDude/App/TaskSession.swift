import Foundation

enum TaskSessionPhase: String, Codable, Equatable, Sendable {
    case idle
    case contextCaptured
    case prompting
    case streaming
    case completed
    case cancelled
    case failed
}

/// The complete in-memory state of one invocation. It deliberately has no
/// persistence or history representation: a new invocation starts from idle.
struct TaskSessionSnapshot: Equatable, Sendable {
    var phase: TaskSessionPhase
    var context: CapturedContext?
    var action: PromptAction
    var userPrompt: String
    var response: String
    var errorMessage: String?

    static let idle = TaskSessionSnapshot(
        phase: .idle,
        context: nil,
        action: .explain,
        userPrompt: "",
        response: "",
        errorMessage: nil
    )
}

enum TaskSessionEvent: Equatable, Sendable {
    case reset
    case contextCaptured(CapturedContext?)
    case prompting
    case streaming
    case textDelta(String)
    case completed
    case cancelled
    case failed(String)
}

extension TaskSessionSnapshot {
    mutating func apply(_ event: TaskSessionEvent) {
        switch event {
        case .reset:
            self = .idle
        case let .contextCaptured(context):
            phase = .contextCaptured
            self.context = context
            response = ""
            errorMessage = nil
        case .prompting:
            phase = .prompting
            errorMessage = nil
        case .streaming:
            phase = .streaming
            response = ""
            errorMessage = nil
        case let .textDelta(delta):
            guard phase == .streaming else { return }
            response += delta
        case .completed:
            guard phase == .streaming else { return }
            phase = .completed
        case .cancelled:
            phase = .cancelled
        case let .failed(message):
            phase = .failed
            errorMessage = message
        }
    }
}
