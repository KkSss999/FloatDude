import Foundation

struct CapturedContext: Sendable, Equatable {
    enum Source: String, Sendable, Equatable {
        case accessibilitySelection
        case clipboard
        case directInput
    }

    let text: String
    let source: Source
    let applicationName: String?
}

protocol ContextCapturing: Sendable {
    func captureContext() async -> CapturedContext?
}
