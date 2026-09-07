import Foundation
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
        var query = itemQuery(service: service, account: account)
        query.merge([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, new in new }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return KeychainReadResult(status: status, data: item as? Data)
    }

    func add(data: Data, service: String, account: String) -> OSStatus {
        var attributes = itemQuery(service: service, account: account)
        attributes.merge([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]) { _, new in new }
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(data: Data, service: String, account: String) -> OSStatus {
        let query = itemQuery(service: service, account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(service: String, account: String) -> OSStatus {
        let query = itemQuery(service: service, account: account)
        return SecItemDelete(query as CFDictionary)
    }

    private func itemQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: true,
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

    var errorDescription: String? {
        switch self {
        case .emptyAPIKey:
            "Enter an API key before saving."
        case .invalidData:
            "The saved API key could not be read. Save it again."
        case .readFailed:
            "The API key could not be read from Keychain. Try again."
        case .saveFailed:
            "The API key could not be saved to Keychain. Try again."
        case .updateFailed:
            "The API key could not be updated in Keychain. Try again."
        case .deleteFailed:
            "The API key could not be deleted from Keychain. Try again."
        }
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
        keychainStore: any KeychainStoring
    ) {
        self.mode = mode
        self.keychainStore = keychainStore
        self.credentials = ProviderCredentials(mode: mode)
        self.initializationError = nil
        do {
            try reopen()
        } catch {
            initializationError = error
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
        clear()
        self.mode = mode
        do {
            try loadCredentials(apiKey: apiKey)
            isOpen = true
            initializationError = nil
        } catch {
            isOpen = false
            initializationError = error
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

    init(
        backend: any KeychainBackend = SecurityKeychainBackend(),
        service: String = "com.kks999.FloatDude",
        account: String = "api-key"
    ) {
        self.backend = backend
        self.service = service
        self.account = account
    }

    func apiKey() throws -> String? {
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
    }

    private func update(data: Data) throws {
        let status = backend.update(data: data, service: service, account: account)
        guard status == errSecSuccess else {
            throw KeychainStoreError.updateFailed(status)
        }
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
