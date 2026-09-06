import Foundation
import Security
import XCTest
@testable import FloatDude

private final class TestKeychainBackend: KeychainBackend, @unchecked Sendable {
    var storedData: Data?
    var addStatus: OSStatus = errSecSuccess
    var updateStatus: OSStatus = errSecSuccess
    var readStatus: OSStatus = errSecSuccess
    var deleteStatus: OSStatus = errSecSuccess
    var operations: [String] = []

    func read(service: String, account: String) -> KeychainReadResult {
        operations.append("read")
        return KeychainReadResult(status: readStatus, data: storedData)
    }

    func add(data: Data, service: String, account: String) -> OSStatus {
        operations.append("add")
        if addStatus == errSecSuccess { storedData = data }
        return addStatus
    }

    func update(data: Data, service: String, account: String) -> OSStatus {
        operations.append("update")
        if updateStatus == errSecSuccess { storedData = data }
        return updateStatus
    }

    func delete(service: String, account: String) -> OSStatus {
        operations.append("delete")
        if deleteStatus == errSecSuccess { storedData = nil }
        return deleteStatus
    }
}

final class KeychainStoreTests: XCTestCase {
    func testReadSaveUpdateAndDeleteUseInjectedBackend() throws {
        let backend = TestKeychainBackend()
        let store = KeychainStore(backend: backend, service: "test", account: "api-key")

        XCTAssertNil(try store.apiKey())
        try store.saveAPIKey("unit-test-secret")
        XCTAssertEqual(try store.apiKey(), "unit-test-secret")
        backend.addStatus = errSecDuplicateItem
        try store.saveAPIKey("updated-unit-test-secret")
        XCTAssertEqual(try store.apiKey(), "updated-unit-test-secret")
        XCTAssertEqual(backend.operations, ["read", "add", "read", "add", "update", "read"])
        try store.updateAPIKey("direct-update")
        XCTAssertEqual(try store.apiKey(), "direct-update")
        try store.deleteAPIKey()
        XCTAssertNil(try store.apiKey())
    }

    func testMissingDeleteIsIdempotentAndEmptyKeyIsRejected() throws {
        let backend = TestKeychainBackend()
        let store = KeychainStore(backend: backend)
        backend.deleteStatus = errSecItemNotFound
        try store.deleteAPIKey()

        XCTAssertThrowsError(try store.saveAPIKey(" \n\t ")) { error in
            XCTAssertEqual(error as? KeychainStoreError, .emptyAPIKey)
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        }
    }

    func testBackendStatusesMapToSafeErrorsWithoutKeyMaterial() throws {
        let backend = TestKeychainBackend()
        let store = KeychainStore(backend: backend)

        backend.readStatus = errSecAuthFailed
        XCTAssertThrowsError(try store.apiKey()) { error in
            XCTAssertEqual(error as? KeychainStoreError, .readFailed(errSecAuthFailed))
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        }

        backend.readStatus = errSecSuccess
        backend.addStatus = errSecAuthFailed
        XCTAssertThrowsError(try store.saveAPIKey("unit-test-secret")) { error in
            XCTAssertEqual(error as? KeychainStoreError, .saveFailed(errSecAuthFailed))
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        }

        backend.addStatus = errSecSuccess
        try store.saveAPIKey("unit-test-secret")
        backend.updateStatus = errSecAuthFailed
        XCTAssertThrowsError(try store.updateAPIKey("another-unit-test-secret")) { error in
            XCTAssertEqual(error as? KeychainStoreError, .updateFailed(errSecAuthFailed))
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        }

        backend.deleteStatus = errSecAuthFailed
        XCTAssertThrowsError(try store.deleteAPIKey()) { error in
            XCTAssertEqual(error as? KeychainStoreError, .deleteFailed(errSecAuthFailed))
            XCTAssertFalse(error.localizedDescription.contains("secret"))
        }
    }
}
