enum PromptAction: String, CaseIterable, Codable, Sendable {
    case explain
    case translate
    case rewrite
    case ask

    var title: String {
        switch self {
        case .explain: "Explain"
        case .translate: "Translate"
        case .rewrite: "Rewrite"
        case .ask: "Ask Anything"
        }
    }

    static func actionForSubmission(prompt: String, fallback: PromptAction) -> PromptAction {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : .ask
    }
}
