import Foundation

struct AppSettings: Sendable, Equatable {
    var baseURL: URL?
    var model: String
    var hotkeyDescription: String

    /// Compatibility name for callers that refer to the persisted value as a
    /// shortcut descriptor. The descriptor itself is owned by GlobalHotkey.
    var shortcutDescriptor: String {
        hotkeyDescription
    }

    static let `default` = AppSettings(
        baseURL: nil,
        model: "",
        hotkeyDescription: "Option-Space"
    )
}

enum SettingsValidationError: LocalizedError, Sendable, Equatable {
    case emptyEndpoint
    case invalidEndpoint
    case endpointContainsCredentials
    case endpointContainsQuery
    case emptyModel
    case emptyShortcut

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

        let baseURL: URL?
        if let url = settings.baseURL {
            baseURL = try normalizeBaseURL(url.absoluteString)
        } else {
            baseURL = nil
        }
        return AppSettings(baseURL: baseURL, model: model, hotkeyDescription: shortcut)
    }

    private static func load(from defaults: UserDefaults) -> AppSettings {
        let baseURL = defaults.string(forKey: Key.baseURL).flatMap { try? normalizeBaseURL($0) }
        let model = defaults.string(forKey: Key.model)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shortcut = defaults.string(forKey: Key.shortcutDescriptor)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? AppSettings.default.hotkeyDescription
        return AppSettings(baseURL: baseURL, model: model, hotkeyDescription: shortcut)
    }
}
