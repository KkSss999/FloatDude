import Foundation
import XCTest
@testable import FloatDude

@MainActor
final class SettingsStoreTests: XCTestCase {
    func testFreshSettingsUseSessionOnlyForTheDefaultDeepSeekProfile() throws {
        let suiteName = "FloatDude.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.current.credentialMode, .thisSessionOnly)
        XCTAssertEqual(store.current.baseURL, URL(string: "https://api.deepseek.com/anthropic"))
        XCTAssertEqual(store.current.model, "deepseek-v4-flash")
        XCTAssertNil(defaults.persistentDomain(forName: suiteName))
    }

    func testMigratesLegacyNoAuthDeepSeekDefaultWithoutChangingCustomNoAuthEndpoints() throws {
        let deepSeekSuite = "FloatDude.SettingsStoreTests.\(UUID().uuidString)"
        let deepSeekDefaults = try XCTUnwrap(UserDefaults(suiteName: deepSeekSuite))
        defer { deepSeekDefaults.removePersistentDomain(forName: deepSeekSuite) }
        deepSeekDefaults.set("https://api.deepseek.com/anthropic", forKey: "floatdude.settings.baseURL")
        deepSeekDefaults.set("noAuthentication", forKey: "floatdude.settings.credentialMode")

        XCTAssertEqual(SettingsStore(defaults: deepSeekDefaults).current.credentialMode, .thisSessionOnly)

        let localSuite = "FloatDude.SettingsStoreTests.\(UUID().uuidString)"
        let localDefaults = try XCTUnwrap(UserDefaults(suiteName: localSuite))
        defer { localDefaults.removePersistentDomain(forName: localSuite) }
        localDefaults.set("http://127.0.0.1:11434", forKey: "floatdude.settings.baseURL")
        localDefaults.set("noAuthentication", forKey: "floatdude.settings.credentialMode")

        XCTAssertEqual(SettingsStore(defaults: localDefaults).current.credentialMode, .noAuthentication)
    }

    func testSettingsRoundTripPersistsOnlyNonSecretPreferences() throws {
        let suiteName = "FloatDude.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        let settings = AppSettings(
            baseURL: URL(string: "HTTPS://API.Example.com/v1/"),
            model: "  gpt-test  ",
            hotkeyDescription: "  Option-Space  ",
            credentialMode: .thisSessionOnly,
            userSystemPrompt: "  Reply in Chinese.  ",
            launchAtLogin: true,
            settingsLanguage: .simplifiedChinese
        )
        store.save(settings)

        let persisted = try XCTUnwrap(defaults.persistentDomain(forName: suiteName))
        XCTAssertEqual(Set(persisted.keys), [
            "floatdude.settings.baseURL",
            "floatdude.settings.model",
            "floatdude.settings.shortcutDescriptor",
            "floatdude.settings.credentialMode",
            "floatdude.settings.userSystemPrompt",
            "floatdude.settings.launchAtLogin",
            "floatdude.settings.settingsLanguage",
        ])
        XCTAssertEqual(persisted["floatdude.settings.baseURL"] as? String, "https://api.example.com/v1")
        XCTAssertEqual(persisted["floatdude.settings.model"] as? String, "gpt-test")
        XCTAssertEqual(persisted["floatdude.settings.shortcutDescriptor"] as? String, "Option-Space")
        XCTAssertEqual(persisted["floatdude.settings.credentialMode"] as? String, CredentialMode.thisSessionOnly.rawValue)
        XCTAssertEqual(persisted["floatdude.settings.userSystemPrompt"] as? String, "Reply in Chinese.")
        XCTAssertEqual(persisted["floatdude.settings.launchAtLogin"] as? Bool, true)
        XCTAssertEqual(persisted["floatdude.settings.settingsLanguage"] as? String, SettingsLanguage.simplifiedChinese.rawValue)
        XCTAssertFalse(persisted.values.contains { String(describing: $0).contains("secret") })

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.current, AppSettings(
            baseURL: URL(string: "https://api.example.com/v1"),
            model: "gpt-test",
            hotkeyDescription: "Option-Space",
            credentialMode: .thisSessionOnly,
            userSystemPrompt: "Reply in Chinese.",
            launchAtLogin: true,
            settingsLanguage: .simplifiedChinese
        ))
    }

    func testSettingsLanguageFallsBackSafelyAndPersistsIndependentlyOfCredentials() throws {
        let suiteName = "FloatDude.SettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("unsupported", forKey: "floatdude.settings.settingsLanguage")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.current.settingsLanguage, AppSettings.default.settingsLanguage)

        var updated = store.current
        updated.settingsLanguage = .english
        store.save(updated)

        XCTAssertEqual(SettingsStore(defaults: defaults).current.settingsLanguage, .english)
    }

    func testProductCopyProvidesMenuAndConversationChineseStrings() {
        let copy = ProductCopy(language: .simplifiedChinese)

        XCTAssertEqual(copy.text(.menuAsk), "呼出 FloatDude…")
        XCTAssertEqual(copy.text(.newConversation), "新建对话")
        XCTAssertEqual(PromptAction.explain.title(in: .simplifiedChinese), "解释")
        XCTAssertEqual(PromptAction.ask.title(in: .english), "Ask Anything")
    }

    func testCustomSystemPromptHasBoundedPersistedSize() {
        let oversized = AppSettings(
            baseURL: URL(string: "https://provider.example"),
            model: "model",
            hotkeyDescription: "Option-Space",
            userSystemPrompt: String(repeating: "x", count: 12_001)
        )
        XCTAssertThrowsError(try SettingsStore.validated(oversized)) { error in
            XCTAssertEqual(error as? SettingsValidationError, .systemPromptTooLong)
        }
    }

    func testCustomSystemPromptRejectsCredentialsBeforeUserDefaults() {
        let settings = AppSettings(
            baseURL: URL(string: "https://provider.example"),
            model: "model",
            hotkeyDescription: "Option-Space",
            userSystemPrompt: "Use sk-" + String(repeating: "a", count: 24)
        )
        XCTAssertThrowsError(try SettingsStore.validated(settings)) { error in
            XCTAssertEqual(error as? SettingsValidationError, .systemPromptContainsCredential)
        }
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
