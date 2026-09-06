import Foundation

struct CapturedContext: Sendable, Equatable {
    enum Source: String, Sendable, Equatable {
        case accessibilitySelection
        case clipboard
        case directInput

        var displayName: String {
            switch self {
            case .accessibilitySelection: "Accessibility selection"
            case .clipboard: "Clipboard"
            case .directInput: "Direct input"
            }
        }
    }

    let text: String
    let source: Source
    let applicationName: String?
}

enum ContextCaptureError: Error, LocalizedError, Sendable, Equatable {
    case exceedsCharacterLimit(source: CapturedContext.Source, count: Int, limit: Int)

    var errorDescription: String? {
        switch self {
        case let .exceedsCharacterLimit(source, count, limit):
            "The \(source.rawValue) context contains \(count) characters; the maximum is \(limit)."
        }
    }
}

enum ContextCaptureUnavailableReason: String, Sendable, Equatable {
    case accessibilityPermissionDenied
    case noSelectionOrClipboard

    var guidance: String {
        switch self {
        case .accessibilityPermissionDenied:
            "Accessibility access is unavailable. Clipboard fallback and direct input are still available."
        case .noSelectionOrClipboard:
            "No selection or clipboard text is available. Enter a prompt below."
        }
    }
}

enum ContextCaptureResult: Sendable, Equatable {
    case captured(CapturedContext)
    case unavailable(reason: ContextCaptureUnavailableReason)
    case rejected(ContextCaptureError)
}

protocol ContextCapturing: Sendable {
    /// Capture before activating the panel. `directInput` is supplied by the
    /// coordinator's editable input field and is the final fallback.
    func captureContext(directInput: String?) async -> ContextCaptureResult
}

struct SelectionCapture: ContextCapturing {
    static let maximumContextCharacters = 12_000

    private let accessibility: any AccessibilityProviding
    private let pasteboard: any PasteboardProviding

    init(
        accessibility: any AccessibilityProviding = SystemAccessibilityProvider(),
        pasteboard: any PasteboardProviding = SystemClipboardManager()
    ) {
        self.accessibility = accessibility
        self.pasteboard = pasteboard
    }

    init(
        accessibility: any AccessibilityProviding,
        clipboard: any ClipboardManaging
    ) {
        self.init(accessibility: accessibility, pasteboard: clipboard)
    }

    func captureContext(directInput: String? = nil) async -> ContextCaptureResult {
        // This method performs only short, synchronous system reads. The
        // coordinator must call it before showing/activating the panel.
        if let selectedText = readSelectedText(),
           let result = makeResult(text: selectedText, source: .accessibilitySelection) {
            return result
        }

        if let clipboardText = readClipboardText(),
           let result = makeResult(text: clipboardText, source: .clipboard) {
            return result
        }

        guard let directInput else {
            return .unavailable(
                reason: accessibility.isTrusted
                    ? .noSelectionOrClipboard
                    : .accessibilityPermissionDenied
            )
        }

        return makeResult(text: directInput, source: .directInput)
            ?? .unavailable(reason: .noSelectionOrClipboard)
    }

    private func readSelectedText() -> String? {
        do {
            guard let focusedElement = try accessibility.focusedElement() else {
                return nil
            }
            return try accessibility.selectedText(from: focusedElement)
        } catch {
            // Accessibility is intentionally non-blocking. AX errors and
            // permission changes simply advance the fallback chain.
            return nil
        }
    }

    private func readClipboardText() -> String? {
        pasteboard.readText()
    }

    private func makeResult(text: String, source: CapturedContext.Source) -> ContextCaptureResult? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let count = text.count
        guard count <= Self.maximumContextCharacters else {
            return .rejected(
                .exceedsCharacterLimit(
                    source: source,
                    count: count,
                    limit: Self.maximumContextCharacters
                )
            )
        }

        return .captured(
            CapturedContext(
                text: text,
                source: source,
                applicationName: nil
            )
        )
    }
}
