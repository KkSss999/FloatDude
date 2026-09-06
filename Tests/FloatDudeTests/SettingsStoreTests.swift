import Foundation
import XCTest
@testable import FloatDude

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testFreshSettingsDefaultToNoAuthentication() throws {
        let suiteName = "FloatDude.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.current.credentialMode, .noAuthentication)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName))
    }

    func testSettingsRoundTripUsesOnlyTheThreeAllowedUserDefaultsValues() throws {
        let suiteName = "FloatDude.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        let settings = AppSettings(
            baseURL: URL(string: "HTTPS://API.Example.com/v1/"),
            model: "  gpt-test  ",
            hotkeyDescription: "  Option-Space  ",
            credentialMode: .thisSessionOnly
        )
        store.save(settings)

        let persisted = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
        XCTAssertEqual(Set(persisted.keys), [
            "floatdude.settings.baseURL",
            "floatdude.settings.model",
            "floatdude.settings.shortcutDescriptor",
            "floatdude.settings.credentialMode",
        ])
        XCTAssertEqual(persisted["floatdude.settings.baseURL"] as? String, "https://api.example.com/v1")
        XCTAssertEqual(persisted["floatdude.settings.model"] as? String, "gpt-test")
        XCTAssertEqual(persisted["floatdude.settings.shortcutDescriptor"] as? String, "Option-Space")
        XCTAssertEqual(persisted["floatdude.settings.credentialMode"] as? String, CredentialMode.thisSessionOnly.rawValue)
        XCTAssertFalse(persisted.values.contains { String(describing: $0).contains("secret") })

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.current, AppSettings(
            baseURL: URL(string: "https://api.example.com/v1"),
            model: "gpt-test",
            hotkeyDescription: "Option-Space",
            credentialMode: .thisSessionOnly
        ))
    }

    func testEndpointNormalizationAndValidation() throws {
        XCTAssertEqual(
            try SettingsStore.normalizeBaseURL("  HTTPS://API.Example.com/v1///  "),
            URL(string: "https://api.example.com/v1")
        )
        XCTAssertThrowsError(try SettingsStore.normalizeBaseURL("")) { error in
            XCTAssertEqual(error as? SettingsValidationError, .emptyEndpoint)
        }
        XCTAssertThrowsError(try SettingsStore.normalizeBaseURL("ftp://api.example.com")) { error in
            XCTAssertEqual(error as? SettingsValidationError, .invalidEndpoint)
        }
        XCTAssertThrowsError(try SettingsStore.normalizeBaseURL("https://user:password@api.example.com")) { error in
            XCTAssertEqual(error as? SettingsValidationError, .endpointContainsCredentials)
        }
        XCTAssertThrowsError(try SettingsStore.normalizeBaseURL("https://api.example.com?token=secret")) { error in
            XCTAssertEqual(error as? SettingsValidationError, .endpointContainsQuery)
        }
        XCTAssertThrowsError(try SettingsStore.normalizeBaseURL("http://api.example.com")) { error in
            XCTAssertEqual(error as? SettingsValidationError, .invalidEndpoint)
        }
    }

    func testInvalidModelAndShortcutAreNotPersisted() {
        let suiteName = "FloatDude.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.save(AppSettings(baseURL: URL(string: "https://api.example.com"), model: "", hotkeyDescription: "Option-Space"))
        XCTAssertNil(defaults.persistentDomain(forName: suiteName))
        store.save(AppSettings(baseURL: URL(string: "https://api.example.com"), model: "model", hotkeyDescription: "  "))
        XCTAssertNil(defaults.persistentDomain(forName: suiteName))
    }
}
