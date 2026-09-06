import Foundation

enum FloatDudeError: LocalizedError, Sendable, Equatable {
    case missingContext
    case missingConfiguration
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingContext:
            "No selected text, clipboard text, or direct input is available."
        case .missingConfiguration:
            "Configure a model before using FloatDude."
        case let .unavailable(message):
            message
        }
    }
}
