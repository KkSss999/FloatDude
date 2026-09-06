import Foundation

protocol ClipboardManaging: Sendable {
    func readText() -> String?
    func writeText(_ text: String)
}
