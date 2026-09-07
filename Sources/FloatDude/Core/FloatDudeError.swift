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

enum SensitiveTextDetector {
    private static let patterns = [
        #"(?i)\bsk-[a-z0-9_-]{20,}\b"#,
        #"\bAIza[0-9A-Za-z_-]{20,}\b"#,
        #"\bxox[baprs]-[0-9A-Za-z-]{20,}\b"#,
        #"(?i)-----BEGIN\s+[A-Z ]*PRIVATE KEY-----"#,
        #"(?i)\b(?:authorization|api[-_ ]?key|x-api-key)\s*[:=]\s*(?:bearer\s+)?[\"']?[A-Za-z0-9._~+/=-]{16,}"#,
    ]

    static func containsCredential(in text: String) -> Bool {
        patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    static func containsSensitiveClipboardValue(_ text: String) -> Bool {
        if containsCredential(in: text) {
            return true
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.range(of: #"(?i)^[a-f0-9]{32,}$"#, options: .regularExpression) != nil
            || value.range(of: #"^[A-Za-z0-9_-]{40,}$"#, options: .regularExpression) != nil
    }
}
