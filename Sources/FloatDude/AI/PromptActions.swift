import Foundation

/// Contract for the prompt templates owned by the product, not by views.
protocol PromptActionProviding: Sendable {
    func systemInstruction(for action: PromptAction) -> String
}
