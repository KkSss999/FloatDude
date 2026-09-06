import Foundation
import Security

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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return KeychainReadResult(status: status, data: item as? Data)
    }

    func add(data: Data, service: String, account: String) -> OSStatus {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(data: Data, service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        return SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary)
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
