import Foundation
import Darwin

// Opt-in real-system probe. Compile with application sources excluding the App
// entrypoint, then run write/read/delete in separate processes with one UUID.
// Only a synthetic credential and an isolated validation service are touched.
@main
struct KeychainValidation {
    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3, let id = UUID(uuidString: args[2]) else { exit(2) }
        let store = KeychainStore(service: "FloatDude.Validation." + id.uuidString, account: "synthetic")
        let value = "invalid-keychain-validation-fixture"
        do {
            switch args[1] {
            case "write": try store.saveAPIKey(value)
            case "read":
                guard try store.apiKey() == value else { exit(1) }
            case "delete":
                try store.deleteAPIKey()
                guard try store.apiKey() == nil else { exit(1) }
            default: exit(2)
            }
            print("KEYCHAIN_\(args[1].uppercased())_OK")
        } catch {
            print("KEYCHAIN_VALIDATION_FAILED: \(error.localizedDescription)")
            exit(1)
        }
    }
}
