import Foundation
import CoreGraphics

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
    /// AppKit desktop coordinates for placement avoidance when Accessibility
    /// exposes the bounds of the source selection.
    let selectionRect: CGRect?
    /// Safe, non-sensitive explanation for why a fallback source was used.
    let guidance: String?

    init(
        text: String,
        source: Source,
        applicationName: String?,
        selectionRect: CGRect? = nil,
        guidance: String? = nil
    ) {
        self.text = text
        self.source = source
        self.applicationName = applicationName
        self.selectionRect = selectionRect
        self.guidance = guidance
    }
}

enum ContextCaptureError: Error, LocalizedError, Sendable, Equatable {
    case exceedsCharacterLimit(source: CapturedContext.Source, count: Int, limit: Int)
    case sensitiveContent(source: CapturedContext.Source)

    var errorDescription: String? {
        switch self {
        case let .exceedsCharacterLimit(source, count, limit):
            "The \(source.rawValue) context contains \(count) characters; the maximum is \(limit)."
        case let .sensitiveContent(source):
            "The \(source.displayName.lowercased()) appears to contain a credential and was not sent."
        }
    }
}

enum ContextCaptureUnavailableReason: String, Sendable, Equatable {
    case accessibilityPermissionDenied
    case noSelectionOrClipboard
    case sensitiveClipboardBlocked

    var guidance: String {
        switch self {
        case .accessibilityPermissionDenied:
            "Accessibility access is unavailable. Clipboard fallback and direct input are still available."
        case .noSelectionOrClipboard:
            "No selection or clipboard text is available. Enter a prompt below."
        case .sensitiveClipboardBlocked:
            "Clipboard content looks like a credential and was blocked. Select text again or type a prompt instead."
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
        if let selection = readSelection(),
           let result = makeResult(
               text: selection.text,
               source: .accessibilitySelection,
               selectionRect: selection.rect
           ) {
            return result
        }

        if let clipboardText = readClipboardText() {
            guard !SensitiveTextDetector.containsCredential(in: clipboardText) else {
                return .unavailable(reason: .sensitiveClipboardBlocked)
            }
            if let result = makeResult(
                text: clipboardText,
                source: .clipboard,
                guidance: accessibility.isTrusted
                    ? nil
                    : "Using Clipboard because Accessibility access is unavailable."
            ) {
                return result
            }
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

    private func readSelection() -> (text: String, rect: CGRect?)? {
        do {
            guard let focusedElement = try accessibility.focusedElement() else {
                return nil
            }
            guard let text = try accessibility.selectedText(from: focusedElement) else {
                return nil
            }
            return (text, try? accessibility.selectedTextBounds(from: focusedElement))
        } catch {
            // Accessibility is intentionally non-blocking. AX errors and
            // permission changes simply advance the fallback chain.
            return nil
        }
    }

    private func readClipboardText() -> String? {
        pasteboard.readText()
    }

    private func makeResult(
        text: String,
        source: CapturedContext.Source,
        selectionRect: CGRect? = nil,
        guidance: String? = nil
    ) -> ContextCaptureResult? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard !SensitiveTextDetector.containsCredential(in: text) else {
            return .rejected(.sensitiveContent(source: source))
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
                applicationName: nil,
                selectionRect: selectionRect,
                guidance: guidance
            )
        )
    }
}
