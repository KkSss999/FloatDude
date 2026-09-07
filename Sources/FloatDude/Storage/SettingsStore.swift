import Foundation

enum CredentialMode: String, CaseIterable, Codable, Identifiable, Sendable, Equatable {
    case noAuthentication
    case thisSessionOnly
    case rememberOnThisMac

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noAuthentication:
            "No Authentication"
        case .thisSessionOnly:
            "This Session Only"
        case .rememberOnThisMac:
            "Remember on This Mac"
        }
    }
}

/// Display language is deliberately product-scoped for now: provider values,
/// prompts, and the protected software policy retain their original text.
/// Settings can switch immediately without changing the rest of the app.
enum SettingsLanguage: String, CaseIterable, Codable, Identifiable, Sendable, Equatable {
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    static var systemDefault: SettingsLanguage {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
            ? .simplifiedChinese
            : .english
    }
}

struct AppSettings: Sendable, Equatable {
    var baseURL: URL?
    var model: String
    var hotkeyDescription: String
    var credentialMode: CredentialMode
    var userSystemPrompt: String
    var launchAtLogin: Bool
    var settingsLanguage: SettingsLanguage

    init(
        baseURL: URL?,
        model: String,
        hotkeyDescription: String,
        credentialMode: CredentialMode = .noAuthentication,
        userSystemPrompt: String = "",
        launchAtLogin: Bool = false,
        settingsLanguage: SettingsLanguage = .systemDefault
    ) {
        self.baseURL = baseURL
        self.model = model
        self.hotkeyDescription = hotkeyDescription
        self.credentialMode = credentialMode
        self.userSystemPrompt = userSystemPrompt
        self.launchAtLogin = launchAtLogin
        self.settingsLanguage = settingsLanguage
    }

    /// Compatibility name for callers that refer to the persisted value as a
    /// shortcut descriptor. The descriptor itself is owned by GlobalHotkey.
    var shortcutDescriptor: String {
        hotkeyDescription
    }

    static let `default` = AppSettings(
        baseURL: URL(string: "https://api.deepseek.com/anthropic"),
        model: "deepseek-v4-flash",
        hotkeyDescription: "Option-Space",
        credentialMode: .thisSessionOnly,
        userSystemPrompt: "",
        launchAtLogin: false,
        settingsLanguage: .systemDefault
    )
}

enum SettingsValidationError: LocalizedError, Sendable, Equatable {
    case emptyEndpoint
    case invalidEndpoint
    case endpointContainsCredentials
    case endpointContainsQuery
    case emptyModel
    case emptyShortcut
    case systemPromptTooLong
    case systemPromptContainsCredential

    var errorDescription: String? {
        switch self {
        case .emptyEndpoint:
            "Enter an endpoint URL."
        case .invalidEndpoint:
            "Enter a valid HTTP or HTTPS endpoint URL."
        case .endpointContainsCredentials:
            "Endpoint URLs cannot contain credentials."
        case .endpointContainsQuery:
            "Endpoint URLs cannot contain a query or fragment."
        case .emptyModel:
            "Enter a model name."
        case .emptyShortcut:
            "Enter a shortcut descriptor."
        case .systemPromptTooLong:
            "Keep the custom system prompt at 12,000 characters or fewer."
        case .systemPromptContainsCredential:
            "The custom system prompt appears to contain a credential and was not saved."
        }
    }
}

@MainActor
protocol SettingsStoring: AnyObject {
    var current: AppSettings { get }
    func save(_ settings: AppSettings)
}

@MainActor
final class SettingsStore: SettingsStoring {
    private enum Key {
        static let baseURL = "floatdude.settings.baseURL"
        static let model = "floatdude.settings.model"
        static let shortcutDescriptor = "floatdude.settings.shortcutDescriptor"
        static let credentialMode = "floatdude.settings.credentialMode"
        static let userSystemPrompt = "floatdude.settings.userSystemPrompt"
        static let launchAtLogin = "floatdude.settings.launchAtLogin"
        static let settingsLanguage = "floatdude.settings.settingsLanguage"
    }

    private let defaults: UserDefaults
    private(set) var current: AppSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.current = Self.load(from: defaults)
    }

    func save(_ settings: AppSettings) {
        guard let validated = try? Self.validated(settings) else {
            return
        }

        if let baseURL = validated.baseURL {
            defaults.set(baseURL.absoluteString, forKey: Key.baseURL)
        } else {
            defaults.removeObject(forKey: Key.baseURL)
        }
        defaults.set(validated.model, forKey: Key.model)
        defaults.set(validated.hotkeyDescription, forKey: Key.shortcutDescriptor)
        defaults.set(validated.credentialMode.rawValue, forKey: Key.credentialMode)
        defaults.set(validated.userSystemPrompt, forKey: Key.userSystemPrompt)
        defaults.set(validated.launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(validated.settingsLanguage.rawValue, forKey: Key.settingsLanguage)
        current = validated
    }

    static func normalizeBaseURL(_ rawValue: String) throws -> URL {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw SettingsValidationError.emptyEndpoint
        }
        guard let url = URL(string: value),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty
        else {
            throw SettingsValidationError.invalidEndpoint
        }
        guard components.user == nil, components.password == nil else {
            throw SettingsValidationError.endpointContainsCredentials
        }
        guard components.query == nil, components.fragment == nil else {
            throw SettingsValidationError.endpointContainsQuery
        }
        if scheme == "http" && !Self.isLoopback(host) {
            throw SettingsValidationError.invalidEndpoint
        }

        components.scheme = scheme
        components.host = host.lowercased()
        if components.path.count > 1 {
            components.path = components.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        }
        guard let normalized = components.url else {
            throw SettingsValidationError.invalidEndpoint
        }
        return normalized
    }

    private static func isLoopback(_ host: String) -> Bool {
        let value = host.lowercased()
        return value == "localhost" || value == "127.0.0.1" || value == "::1" || value == "[::1]"
    }

    static func validated(_ settings: AppSettings) throws -> AppSettings {
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw SettingsValidationError.emptyModel
        }
        let shortcut = settings.hotkeyDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shortcut.isEmpty else {
            throw SettingsValidationError.emptyShortcut
        }
        let userSystemPrompt = settings.userSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard userSystemPrompt.count <= 12_000 else {
            throw SettingsValidationError.systemPromptTooLong
        }
        guard !SensitiveTextDetector.containsCredential(in: userSystemPrompt) else {
            throw SettingsValidationError.systemPromptContainsCredential
        }

        let baseURL: URL?
        if let url = settings.baseURL {
            baseURL = try normalizeBaseURL(url.absoluteString)
        } else {
            baseURL = nil
        }
        return AppSettings(
            baseURL: baseURL,
            model: model,
            hotkeyDescription: shortcut,
            credentialMode: settings.credentialMode,
            userSystemPrompt: userSystemPrompt,
            launchAtLogin: settings.launchAtLogin,
            settingsLanguage: settings.settingsLanguage
        )
    }

    private static func load(from defaults: UserDefaults) -> AppSettings {
        let baseURL = defaults.string(forKey: Key.baseURL).flatMap { try? normalizeBaseURL($0) }
            ?? AppSettings.default.baseURL
        let model = defaults.string(forKey: Key.model)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? AppSettings.default.model
        let shortcut = defaults.string(forKey: Key.shortcutDescriptor)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? AppSettings.default.hotkeyDescription
        let storedCredentialMode = defaults.string(forKey: Key.credentialMode)
            .flatMap(CredentialMode.init(rawValue:))
            ?? AppSettings.default.credentialMode
        let credentialMode: CredentialMode
        let userSystemPrompt = defaults.string(forKey: Key.userSystemPrompt) ?? ""
        let launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        let settingsLanguage = defaults.string(forKey: Key.settingsLanguage)
            .flatMap(SettingsLanguage.init(rawValue:))
            ?? AppSettings.default.settingsLanguage
        if storedCredentialMode == .noAuthentication,
           baseURL == AppSettings.default.baseURL {
            // Early v0.1 builds persisted No Authentication even though the
            // default DeepSeek endpoint requires x-api-key. Migrate only this
            // impossible built-in combination; custom no-auth endpoints stay
            // untouched.
            credentialMode = .thisSessionOnly
        } else {
            credentialMode = storedCredentialMode
        }
        return AppSettings(
            baseURL: baseURL,
            model: model,
            hotkeyDescription: shortcut,
            credentialMode: credentialMode,
            userSystemPrompt: userSystemPrompt,
            launchAtLogin: launchAtLogin,
            settingsLanguage: settingsLanguage
        )
    }
}
