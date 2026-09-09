enum PromptAction: String, CaseIterable, Codable, Sendable {
    case explain
    case translate
    case rewrite
    case ask

    var title: String {
        return switch self {
        case .explain: "Explain"
        case .translate: "Translate"
        case .rewrite: "Rewrite"
        case .ask: "Ask Anything"
        }
    }

    func title(in language: SettingsLanguage) -> String {
        guard language == .simplifiedChinese else { return title }
        return switch self {
        case .explain: "解释"
        case .translate: "翻译"
        case .rewrite: "改写"
        case .ask: "自由提问"
        }
    }

    static func actionForSubmission(prompt: String, fallback: PromptAction) -> PromptAction {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : .ask
    }
}
