import Foundation

#if canImport(Combine)
import Combine
#endif

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

enum ProductTextKey: Hashable {
    case menuReady, menuAsk, menuNewConversation, menuExports, menuSettings, menuQuit
    case selectedText, accessibilitySelection, feishuSnapshot, clipboard, directInput
    case askPlaceholder, askAnything, askHint, attachHelp, openAccessibilitySettings
    case active, selectAction, removeAttachment, jumpLatest, deleteConversationQuestion
    case deleteConversation, deleteCurrentConversation, conversationDeleteHelp, newConversation
    case closeFloatDude, conversations, copy, complete, cancelled, responseError, tryAgain
    case you, floatDude, jumpToUserMessage, capturedFeishuSnapshot, noSelection
}

struct ProductCopy: Sendable {
    let language: SettingsLanguage

    func text(_ key: ProductTextKey) -> String {
        switch language {
        case .english: Self.english[key] ?? ""
        case .simplifiedChinese: Self.simplifiedChinese[key] ?? ""
        }
    }

    func localizedGuidance(_ raw: String) -> String {
        guard language == .simplifiedChinese else { return raw }
        if raw.localizedCaseInsensitiveContains("Accessibility access is unavailable") {
            return "辅助功能不可用。仍可使用剪贴板回退或直接输入。"
        }
        if raw.localizedCaseInsensitiveContains("No selection is active") || raw.localizedCaseInsensitiveContains("No selection or clipboard") {
            return "当前没有选中文本。请在下方输入问题。"
        }
        if raw.localizedCaseInsensitiveContains("Captured from Feishu") {
            return "已在快捷键触发时获取飞书选区。此渲染器不支持实时选区更新。"
        }
        if raw.localizedCaseInsensitiveContains("Using Clipboard") {
            return "由于辅助功能不可用，正在使用剪贴板内容。"
        }
        if raw.localizedCaseInsensitiveContains("Clipboard content looks like a credential") {
            return "剪贴板内容疑似包含凭据，已被拦截。请重新选择文本或直接输入。"
        }
        return raw
    }

    private static let english: [ProductTextKey: String] = [
        .menuReady: "Ready in the menu bar", .menuAsk: "Ask FloatDude…",
        .menuNewConversation: "New Conversation", .menuExports: "Open Exports Folder",
        .menuSettings: "Settings…", .menuQuit: "Quit FloatDude",
        .selectedText: "Selected text", .accessibilitySelection: "Accessibility selection",
        .feishuSnapshot: "Feishu shortcut snapshot", .clipboard: "Clipboard", .directInput: "Direct input",
        .askPlaceholder: "Ask FloatDude…", .askAnything: "Ask Anything",
        .askHint: "Enter a question or instructions", .attachHelp: "Attach PDF, Markdown, Word, or spreadsheet",
        .openAccessibilitySettings: "Open Accessibility Settings", .active: "Active",
        .selectAction: "Select this action", .removeAttachment: "Remove %@", .jumpLatest: "Jump to latest message",
        .deleteConversationQuestion: "Delete this conversation?", .deleteConversation: "Delete Conversation",
        .deleteCurrentConversation: "Delete Current Conversation",
        .conversationDeleteHelp: "Its local messages and managed attachment copies will be removed.",
        .newConversation: "New Conversation", .closeFloatDude: "Close FloatDude",
        .conversations: "Conversations", .copy: "Copy", .complete: "Complete",
        .cancelled: "Cancelled", .responseError: "Response error", .tryAgain: "Try Again",
        .you: "YOU", .floatDude: "FLOATDUDE", .jumpToUserMessage: "Jump to your message",
        .capturedFeishuSnapshot: "Captured from Feishu when you invoked the shortcut. Live selection updates are unavailable in this renderer.",
        .noSelection: "No selection is active. Enter a prompt below.",
    ]

    private static let simplifiedChinese: [ProductTextKey: String] = [
        .menuReady: "已在菜单栏就绪", .menuAsk: "呼出 FloatDude…",
        .menuNewConversation: "新建对话", .menuExports: "打开导出文件夹",
        .menuSettings: "设置…", .menuQuit: "退出 FloatDude",
        .selectedText: "选中文本", .accessibilitySelection: "辅助功能选区",
        .feishuSnapshot: "飞书快捷键快照", .clipboard: "剪贴板", .directInput: "直接输入",
        .askPlaceholder: "问问 FloatDude…", .askAnything: "自由提问",
        .askHint: "输入问题或指令", .attachHelp: "添加 PDF、Markdown、Word 或电子表格",
        .openAccessibilitySettings: "打开辅助功能设置", .active: "当前操作",
        .selectAction: "选择此操作", .removeAttachment: "移除 %@", .jumpLatest: "跳转到最新消息",
        .deleteConversationQuestion: "删除此对话？", .deleteConversation: "删除对话",
        .deleteCurrentConversation: "删除当前对话",
        .conversationDeleteHelp: "本地消息和托管的附件副本将被删除。",
        .newConversation: "新建对话", .closeFloatDude: "关闭 FloatDude",
        .conversations: "对话", .copy: "复制", .complete: "完成",
        .cancelled: "已取消", .responseError: "回答出错", .tryAgain: "重试",
        .you: "你", .floatDude: "FLOATDUDE", .jumpToUserMessage: "跳转到你的消息",
        .capturedFeishuSnapshot: "已在快捷键触发时获取飞书选区。此渲染器不支持实时选区更新。",
        .noSelection: "当前没有选中文本。请在下方输入问题。",
    ]
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
final class SettingsStore: ObservableObject, SettingsStoring {
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
    @Published private(set) var current: AppSettings

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
