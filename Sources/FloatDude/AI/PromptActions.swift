import Foundation

/// Contract for the prompt templates owned by the product, not by views.
protocol PromptActionProviding: Sendable {
    func systemInstruction(for action: PromptAction) -> String
}

struct PromptActions: PromptActionProviding, Sendable {
    let preferredLanguage: String

    init(preferredLanguage: String? = Locale.preferredLanguages.first) {
        self.preferredLanguage = preferredLanguage.flatMap { $0.isEmpty ? nil : $0 } ?? "English"
    }

    func systemInstruction(for action: PromptAction) -> String {
        switch action {
        case .explain:
            "Explain the provided text clearly and concisely."
        case .translate:
            "Translate the provided text to \(preferredLanguage). If it is already in \(preferredLanguage), translate it to English. Return only the translation."
        case .rewrite:
            "Rewrite the provided text for clarity and a natural tone. Return only the rewritten text."
        case .ask:
            "Answer the user's question accurately and concisely."
        }
    }
}
