import Foundation
import AppKit

/// Pasteboard seam used by context capture. Keeping it protocol-based makes
/// the priority chain deterministic in tests and keeps captured content in
/// memory only.
protocol PasteboardProviding: Sendable {
    func readText() -> String?
    func writeText(_ text: String)
}

protocol ClipboardManaging: PasteboardProviding {}

struct ClipboardManager: ClipboardManaging {
    func readText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func writeText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

typealias SystemClipboardManager = ClipboardManager
