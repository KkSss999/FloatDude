import Foundation
import AppKit

/// Pasteboard seam used by context capture. Keeping it protocol-based makes
/// the priority chain deterministic in tests and keeps captured content in
/// memory only.
protocol PasteboardProviding: Sendable {
    func readText() -> String?
    func writeText(_ text: String)
}

protocol ClipboardManaging: PasteboardProviding {
    @discardableResult
    func clearText(ifMatching text: String) -> Bool
}

extension ClipboardManaging {
    @discardableResult
    func clearText(ifMatching text: String) -> Bool { false }
}

struct ClipboardManager: ClipboardManaging {
    func readText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func writeText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @discardableResult
    func clearText(ifMatching text: String) -> Bool {
        guard let clipboardText = readText(),
              clipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
                == text.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return false
        }
        NSPasteboard.general.clearContents()
        return true
    }
}

typealias SystemClipboardManager = ClipboardManager
