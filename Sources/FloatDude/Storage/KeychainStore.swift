import Foundation
import LocalAuthentication
import Security

struct ProviderCredentials: Sendable, Equatable {
    let mode: CredentialMode
    let apiKey: String?

    init(mode: CredentialMode, apiKey: String? = nil) {
        self.mode = mode
        let normalizedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = mode == .noAuthentication ? nil : normalizedKey
    }

    var hasAPIKey: Bool {
        guard let apiKey else { return false }
        return !apiKey.isEmpty
    }
}

enum ProviderSessionError: LocalizedError, Sendable, Equatable {
    case sessionClosed
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .sessionClosed:
            "The credential session is closed. Enter the API key again before retrying."
        case .missingAPIKey:
            "Enter an API key for the selected credential mode."
        }
    }
}

struct KeychainReadResult: Sendable {
    let status: OSStatus
    let data: Data?
}

protocol KeychainBackend: Sendable {
    func read(service: String, account: String) -> KeychainReadResult
    func add(data: Data, service: String, account: String) -> OSStatus
    func update(data: Data, service: String, account: String) -> OSStatus
    func delete(service: String, account: String) -> OSStatus
}

struct SecurityKeychainBackend: KeychainBackend {
    func read(service: String, account: String) -> KeychainReadResult {
        let query = Self.readQuery(service: service, account: account)
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return KeychainReadResult(status: status, data: item as? Data)
    }

    func add(data: Data, service: String, account: String) -> OSStatus {
        var attributes = Self.itemQuery(service: service, account: account)
        attributes.merge([
            kSecValueData as String: data,
        ]) { _, new in new }
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(data: Data, service: String, account: String) -> OSStatus {
        let query = Self.itemQuery(service: service, account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        return SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(service: String, account: String) -> OSStatus {
        let query = Self.itemQuery(service: service, account: account)
        return SecItemDelete(query as CFDictionary)
    }

    static func readQuery(service: String, account: String) -> [String: Any] {
        var query = itemQuery(service: service, account: account)
        let context = LAContext()
        context.interactionNotAllowed = true
        query.merge([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // A rebuilt/ad-hoc identity may no longer satisfy the item's ACL.
            // Never block a menu-bar app behind an invisible Keychain prompt;
            // fail fast and let Settings explicitly replace the credential.
            kSecUseAuthenticationContext as String: context,
        ]) { _, new in new }
        return query
    }

    private static func itemQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // v0.1 is an ad-hoc signed, unsandboxed macOS app. Use the
            // file-based login keychain with its default per-app ACL. The
            // data-protection implementation requires signing entitlements
            // absent from this build (-34018). Never relax the default ACL.
            kSecUseDataProtectionKeychain as String: false,
        ]
    }
}

enum KeychainStoreError: LocalizedError, Sendable, Equatable {
    case emptyAPIKey
    case invalidData
    case readFailed(OSStatus)
    case saveFailed(OSStatus)
    case updateFailed(OSStatus)
    case deleteFailed(OSStatus)
    case identityChanged

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            "Enter an API key before saving."
        case .invalidData:
            "The saved API key could not be read. Save it again."
        case let .readFailed(status):
            "The API key could not be read from Keychain (OSStatus \(status))."
        case let .saveFailed(status):
            "The API key could not be saved to Keychain (OSStatus \(status))."
        case let .updateFailed(status):
            "The API key could not be updated in Keychain (OSStatus \(status))."
        case let .deleteFailed(status):
            "The API key could not be deleted from Keychain (OSStatus \(status))."
        case .identityChanged:
            "This build has a different code identity. Apply the remembered API key again in Settings."
        }
    }
}

protocol KeychainIdentityMarking: Sendable {
    func matchesCurrentIdentity() -> Bool
    func markCurrentIdentity() throws
    func clear() throws
}

struct VolatileKeychainIdentityMarker: KeychainIdentityMarking {
    func matchesCurrentIdentity() -> Bool { true }
    func markCurrentIdentity() throws {}
    func clear() throws {}
}

struct FileKeychainIdentityMarker: KeychainIdentityMarking {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = fileURL
            ?? root.appendingPathComponent("FloatDude", isDirectory: true)
                .appendingPathComponent("keychain-identity.txt")
    }

    func matchesCurrentIdentity() -> Bool {
        guard let stored = try? String(contentsOf: fileURL, encoding: .utf8),
              let current = Self.currentIdentity()
        else { return false }
        return stored == current
    }

    func markCurrentIdentity() throws {
        guard let identity = Self.currentIdentity() else {
            throw KeychainStoreError.identityChanged
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(identity.utf8).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func currentIdentity() -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code
        else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
              let values = information as? [String: Any],
              let identifier = values[kSecCodeInfoIdentifier as String] as? String
        else { return nil }
        if let team = values[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return "team:\(team)|identifier:\(identifier)"
        }
        guard let unique = values[kSecCodeInfoUnique as String] as? Data else { return nil }
        return "adhoc:\(identifier)|cdhash:\(unique.base64EncodedString())"
    }
}

protocol KeychainStoring: Sendable {
    func apiKey() throws -> String?
    func saveAPIKey(_ key: String) throws
    func updateAPIKey(_ key: String) throws
    func deleteAPIKey() throws
}

@MainActor
protocol ProviderSessionManaging: AnyObject {
    var mode: CredentialMode { get }
    var hasAPIKey: Bool { get }
    var hasRememberedAPIKey: Bool { get }
    func credentialsForRequest() throws -> ProviderCredentials
    func configure(mode: CredentialMode, apiKey: String?) throws
    func reopen() throws
    func clear()
    func deleteRememberedAPIKey() throws
}

/// Owns the in-memory credentials used by provider requests. Keychain is read
/// only while this session is initialized or explicitly reopened/configured;
/// request execution never reaches into Keychain.
@MainActor
final class ProviderSession: ProviderSessionManaging {
    private let keychainStore: any KeychainStoring
    private(set) var mode: CredentialMode
    private var credentials: ProviderCredentials
    private var isOpen = false
    private var initializationError: Error?
    private(set) var hasRememberedAPIKey = false

    var hasAPIKey: Bool {
        credentials.hasAPIKey
    }

    init(
        mode: CredentialMode,
        keychainStore: any KeychainStoring,
        loadRememberedImmediately: Bool = true
    ) {
        self.mode = mode
        self.keychainStore = keychainStore
        self.credentials = ProviderCredentials(mode: mode)
        self.initializationError = nil
        if mode == .rememberOnThisMac && !loadRememberedImmediately {
            isOpen = false
        } else {
            do {
                try reopen()
            } catch {
                initializationError = error
            }
        }
    }

    func credentialsForRequest() throws -> ProviderCredentials {
        guard isOpen else {
            if let initializationError {
                throw initializationError
            }
            throw ProviderSessionError.sessionClosed
        }
        guard mode == .noAuthentication || credentials.hasAPIKey else {
            throw ProviderSessionError.missingAPIKey
        }
        return credentials
    }

    func configure(mode: CredentialMode, apiKey: String?) throws {
        let previousMode = self.mode
        let previousCredentials = credentials
        let previousOpen = isOpen
        let previousError = initializationError
        let previousRemembered = hasRememberedAPIKey
        clear()
        self.mode = mode
        do {
            try loadCredentials(apiKey: apiKey)
            isOpen = true
            initializationError = nil
        } catch {
            self.mode = previousMode
            credentials = previousCredentials
            isOpen = previousOpen
            initializationError = previousError
            hasRememberedAPIKey = previousRemembered
            throw error
        }
    }

    func reopen() throws {
        clear()
        do {
            try loadCredentials(apiKey: nil)
            isOpen = true
            initializationError = nil
        } catch {
            isOpen = false
            initializationError = error
            throw error
        }
    }

    func clear() {
        credentials = ProviderCredentials(mode: mode)
        isOpen = false
        initializationError = nil
    }

    func acceptRememberedAPIKey(_ key: String) {
        guard mode == .rememberOnThisMac else { return }
        let loaded = ProviderCredentials(mode: .rememberOnThisMac, apiKey: key)
        guard loaded.hasAPIKey else { return }
        credentials = loaded
        hasRememberedAPIKey = true
        isOpen = true
        initializationError = nil
    }

    func deleteRememberedAPIKey() throws {
        try keychainStore.deleteAPIKey()
        hasRememberedAPIKey = false
        clear()
    }

    private func loadCredentials(apiKey: String?) throws {
        switch mode {
        case .noAuthentication:
            credentials = ProviderCredentials(mode: .noAuthentication)
        case .thisSessionOnly:
            let sessionCredentials = ProviderCredentials(mode: .thisSessionOnly, apiKey: apiKey)
            guard sessionCredentials.hasAPIKey else {
                throw ProviderSessionError.missingAPIKey
            }
            credentials = sessionCredentials
        case .rememberOnThisMac:
            if let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try keychainStore.saveAPIKey(apiKey)
                credentials = ProviderCredentials(mode: .rememberOnThisMac, apiKey: apiKey)
                hasRememberedAPIKey = true
            } else {
                let rememberedKey = try keychainStore.apiKey()
                let rememberedCredentials = ProviderCredentials(mode: .rememberOnThisMac, apiKey: rememberedKey)
                guard rememberedCredentials.hasAPIKey else {
                    throw ProviderSessionError.missingAPIKey
                }
                credentials = rememberedCredentials
                hasRememberedAPIKey = true
            }
        }
    }
}

struct KeychainStore: KeychainStoring, Sendable {
    private let backend: any KeychainBackend
    private let service: String
    private let account: String
    private let identityMarker: any KeychainIdentityMarking

    init(
        backend: any KeychainBackend = SecurityKeychainBackend(),
        service: String = "com.kks999.FloatDude",
        account: String = "api-key",
        identityMarker: (any KeychainIdentityMarking)? = nil
    ) {
        self.backend = backend
        self.service = service
        self.account = account
        self.identityMarker = identityMarker
            ?? (backend is SecurityKeychainBackend
                ? FileKeychainIdentityMarker()
                : VolatileKeychainIdentityMarker())
    }

    func apiKey() throws -> String? {
        guard identityMarker.matchesCurrentIdentity() else {
            throw KeychainStoreError.identityChanged
        }
        let result = backend.read(service: service, account: account)
        switch result.status {
        case errSecSuccess:
            guard let data = result.data, let key = String(data: data, encoding: .utf8) else {
                throw KeychainStoreError.invalidData
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.readFailed(result.status)
        }
    }

    func saveAPIKey(_ key: String) throws {
        let data = try validatedData(for: key)
        let status = backend.add(data: data, service: service, account: account)
        if status == errSecSuccess {
            try identityMarker.markCurrentIdentity()
            return
        }
        if status == errSecDuplicateItem {
            try update(data: data)
            return
        }
        throw KeychainStoreError.saveFailed(status)
    }

    func updateAPIKey(_ key: String) throws {
        try update(data: validatedData(for: key))
    }

    func deleteAPIKey() throws {
        let status = backend.delete(service: service, account: account)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.deleteFailed(status)
        }
        try identityMarker.clear()
    }

    private func update(data: Data) throws {
        let status = backend.update(data: data, service: service, account: account)
        guard status == errSecSuccess else {
            throw KeychainStoreError.updateFailed(status)
        }
        try identityMarker.markCurrentIdentity()
    }

    private func validatedData(for key: String) throws -> Data {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = key.data(using: .utf8)
        else {
            throw KeychainStoreError.emptyAPIKey
        }
        return data
    }
}
