import Foundation

protocol KeychainStoring: Sendable {
    func apiKey() throws -> String?
    func saveAPIKey(_ key: String) throws
    func deleteAPIKey() throws
}
