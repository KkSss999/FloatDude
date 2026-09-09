import AppKit
import SwiftUI

private enum SettingsTextKey: Hashable {
    case displayLanguage, provider, endpointURL, model, credentialMode, apiKey, apiKeyConfigured
    case rememberKey, applyCredentials, deleteRememberedKey, testing, testModels, modelsUnavailable
    case agentInstructions, instructionsPlaceholder, instructionsHelp
    case background, launchAtLogin, backgroundHelp, openLoginItems
    case shortcut, shortcutDescriptor, shortcutHelp
    case contextAccess, accessGranted, accessDenied, accessRebuildHelp, privacyPath
    case requestAccess, openPrivacy, showInFinder, refresh, save, saved
    case credentialsApplied, credentialsApplyFailed, rememberedKeyDeleted, rememberedKeyDeleteFailed
    case keychainLoaded, sessionKeyActive, noAuthenticationHelp, sessionOnlyHelp, rememberHelp
    case title
}

private struct SettingsCopy {
    let language: SettingsLanguage

    func text(_ key: SettingsTextKey) -> String {
        switch language {
        case .english: Self.english[key] ?? ""
        case .simplifiedChinese: Self.simplifiedChinese[key] ?? ""
        }
    }

    func connectedModels(_ count: Int) -> String {
        switch language {
        case .english:
            "Connected. /models returned \(count) model\(count == 1 ? "" : "s")."
        case .simplifiedChinese:
            "连接成功。/models 返回了 \(count) 个模型。"
        }
    }

    private static let english: [SettingsTextKey: String] = [
        .displayLanguage: "Display language", .provider: "Provider", .endpointURL: "Endpoint URL",
        .model: "Model", .credentialMode: "Credential mode", .apiKey: "API key", .apiKeyConfigured: "Configured",
        .rememberKey: "Remember this API key on this Mac", .applyCredentials: "Apply Credentials",
        .deleteRememberedKey: "Delete Remembered Key", .testing: "Testing…", .testModels: "Test /v1/models",
        .modelsUnavailable: "The provider returned 404 for /v1/models. This optional catalog endpoint is unavailable; the configured model can still be used.",
        .agentInstructions: "Agent Instructions",
        .instructionsPlaceholder: "Optional instructions for tone, language, output format, and working preferences…",
        .instructionsHelp: "These instructions are appended after FloatDude's protected software policy and reused across conversation turns.",
        .background: "Background", .launchAtLogin: "Launch FloatDude at login",
        .backgroundHelp: "FloatDude remains a menu-bar app and restores conversation metadata locally.",
        .openLoginItems: "Open Login Items Settings", .shortcut: "Shortcut",
        .shortcutDescriptor: "Shortcut descriptor", .shortcutHelp: "The shortcut is re-registered after a change.",
        .contextAccess: "Context Access", .accessGranted: "Accessibility access granted",
        .accessDenied: "This running build is not trusted by Accessibility",
        .accessRebuildHelp: "If FloatDude is already enabled in System Settings, its authorization may belong to another build. Local ad-hoc signatures change when rebuilt. Authorize the current app after the final build.",
        .privacyPath: "Privacy & Security → %@. Add this installed app, then enable its switch.",
        .requestAccess: "Request Access", .openPrivacy: "Open Privacy Settings", .showInFinder: "Show App in Finder",
        .refresh: "Refresh", .save: "Save Settings", .saved: "Settings saved.",
        .credentialsApplied: "Credentials applied.", .credentialsApplyFailed: "Credentials could not be applied. Try again.",
        .rememberedKeyDeleted: "Remembered API key deleted.", .rememberedKeyDeleteFailed: "The remembered API key could not be deleted. Try again.",
        .keychainLoaded: "API key loaded from this Mac's Keychain", .sessionKeyActive: "API key active for this session",
        .noAuthenticationHelp: "No Keychain lookup, API key, or authentication header is used.",
        .sessionOnlyHelp: "The API key stays in memory only until FloatDude quits, you disconnect, or the mode changes.",
        .rememberHelp: "The API key is saved only to this Mac's Keychain after you explicitly apply this mode.",
        .title: "FloatDude Settings",
    ]

    private static let simplifiedChinese: [SettingsTextKey: String] = [
        .displayLanguage: "显示语言", .provider: "模型服务", .endpointURL: "接口地址",
        .model: "模型", .credentialMode: "凭据模式", .apiKey: "API 密钥", .apiKeyConfigured: "已配置",
        .rememberKey: "在此 Mac 记住此 API 密钥", .applyCredentials: "应用凭据",
        .deleteRememberedKey: "删除已记住的密钥", .testing: "测试中…", .testModels: "测试 /v1/models",
        .modelsUnavailable: "服务商对 /v1/models 返回了 404。该可选模型目录不可用，但不影响已配置模型继续使用。",
        .agentInstructions: "Agent 指令",
        .instructionsPlaceholder: "可选：定义语气、语言、输出格式和工作偏好…",
        .instructionsHelp: "这些指令会追加在 FloatDude 受保护的软件策略之后，并在后续会话轮次中复用。",
        .background: "后台运行", .launchAtLogin: "登录时启动 FloatDude",
        .backgroundHelp: "FloatDude 会继续作为菜单栏应用运行，并在本机恢复会话元数据。",
        .openLoginItems: "打开登录项设置", .shortcut: "快捷键",
        .shortcutDescriptor: "快捷键描述", .shortcutHelp: "修改后会重新注册快捷键。",
        .contextAccess: "上下文访问", .accessGranted: "已授予辅助功能访问权限",
        .accessDenied: "当前运行的构建尚未获得辅助功能信任",
        .accessRebuildHelp: "如果系统设置里已启用 FloatDude，该授权可能属于另一份构建。本地 ad-hoc 签名会在重建后变化；请为最终安装版重新授权。",
        .privacyPath: "隐私与安全性 → %@。添加这个已安装的 App，并打开它的开关。",
        .requestAccess: "请求访问权限", .openPrivacy: "打开隐私设置", .showInFinder: "在访达中显示",
        .refresh: "刷新", .save: "保存设置", .saved: "设置已保存。",
        .credentialsApplied: "凭据已应用。", .credentialsApplyFailed: "无法应用凭据，请重试。",
        .rememberedKeyDeleted: "已删除记住的 API 密钥。", .rememberedKeyDeleteFailed: "无法删除记住的 API 密钥，请重试。",
        .keychainLoaded: "已从此 Mac 的钥匙串载入 API 密钥", .sessionKeyActive: "API 密钥已在本次会话中生效",
        .noAuthenticationHelp: "不会查询钥匙串、发送 API 密钥或认证请求头。",
        .sessionOnlyHelp: "API 密钥仅保留在内存中，退出 FloatDude、断开连接或切换模式后即消失。",
        .rememberHelp: "只有在你明确应用此模式后，API 密钥才会保存到这台 Mac 的钥匙串。",
        .title: "FloatDude 设置",
    ]
}

/// Dedicated Settings scene content. API keys are selected explicitly as
/// either session-only or device-local remembered credentials.
@MainActor
struct SettingsView: View {
    private let settingsStore: any SettingsStoring
    private let providerSession: any ProviderSessionManaging
    private let hotkeyManager: (any GlobalHotkeyManaging)?
    private let clipboardManager: any ClipboardManaging
    private let backgroundManager: any BackgroundServiceManaging
    private let modelCatalogClient: ModelCatalogClient
    private let onCredentialsApplied: () -> Void

    @State private var endpoint: String
    @State private var model: String
    @State private var credentialMode: CredentialMode
    @State private var apiKey = ""
    @State private var shortcut: String
    @State private var userSystemPrompt: String
    @State private var launchAtLogin: Bool
    @State private var settingsLanguage: SettingsLanguage
    @State private var hasAPIKey: Bool
    @State private var hasRememberedAPIKey: Bool
    @State private var accessibilityGranted: Bool
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var statusIsWarning = false
    @State private var isTestingConnection = false

    init(
        settingsStore: any SettingsStoring,
        providerSession: any ProviderSessionManaging,
        hotkeyManager: (any GlobalHotkeyManaging)? = nil,
        clipboardManager: any ClipboardManaging = ClipboardManager(),
        backgroundManager: (any BackgroundServiceManaging)? = nil,
        modelCatalogClient: ModelCatalogClient = ModelCatalogClient(),
        onCredentialsApplied: @escaping () -> Void = {}
    ) {
        self.settingsStore = settingsStore
        self.providerSession = providerSession
        self.hotkeyManager = hotkeyManager
        self.clipboardManager = clipboardManager
        self.backgroundManager = backgroundManager ?? BackgroundServiceManager()
        self.modelCatalogClient = modelCatalogClient
        self.onCredentialsApplied = onCredentialsApplied
        let settings = settingsStore.current
        _endpoint = State(initialValue: settings.baseURL?.absoluteString ?? "")
        _model = State(initialValue: settings.model)
        _credentialMode = State(initialValue: settings.credentialMode)
        _shortcut = State(initialValue: settings.hotkeyDescription)
        _userSystemPrompt = State(initialValue: settings.userSystemPrompt)
        _launchAtLogin = State(initialValue: self.backgroundManager.isEnabled)
        _settingsLanguage = State(initialValue: settings.settingsLanguage)
        _hasAPIKey = State(initialValue: settings.credentialMode != .noAuthentication && providerSession.hasAPIKey)
        _hasRememberedAPIKey = State(initialValue: providerSession.hasRememberedAPIKey)
        _accessibilityGranted = State(initialValue: SystemAccessibilityProvider().isTrusted)
    }

    var body: some View {
        Form {
            Section(copy.text(.displayLanguage)) {
                Picker(copy.text(.displayLanguage), selection: $settingsLanguage) {
                    ForEach(SettingsLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
            }

            Section(copy.text(.provider)) {
                TextField(copy.text(.endpointURL), text: $endpoint)
                    .textContentType(.URL)
                TextField(copy.text(.model), text: $model)

                Picker(copy.text(.credentialMode), selection: $credentialMode) {
                    ForEach(CredentialMode.allCases) { mode in
                        Text(credentialModeDisplayName(mode)).tag(mode)
                    }
                }

                apiKeyField
                    .disabled(credentialMode == .noAuthentication)

                Toggle(
                    copy.text(.rememberKey),
                    isOn: Binding(
                        get: { credentialMode == .rememberOnThisMac },
                        set: { shouldRemember in
                            credentialMode = shouldRemember ? .rememberOnThisMac : .thisSessionOnly
                        }
                    )
                )
                .disabled(credentialMode == .noAuthentication)

                Text(credentialHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if hasAPIKey || (credentialMode == .rememberOnThisMac && hasRememberedAPIKey) {
                    Label(
                        credentialMode == .rememberOnThisMac && hasRememberedAPIKey
                            ? copy.text(.keychainLoaded)
                            : copy.text(.sessionKeyActive),
                        systemImage: "checkmark.seal"
                    )
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Button(copy.text(.applyCredentials), action: applyCredentials)
                        .disabled(
                            credentialMode == .thisSessionOnly
                                && apiKey.isEmpty
                                && !hasAPIKey
                        )
                    Button(copy.text(.deleteRememberedKey), role: .destructive, action: deleteAPIKey)
                        .disabled(credentialMode != .rememberOnThisMac || !hasRememberedAPIKey)
                    Button(isTestingConnection ? copy.text(.testing) : copy.text(.testModels)) {
                        testConnection()
                    }
                    .disabled(isTestingConnection)
                }
            }

            Section(copy.text(.agentInstructions)) {
                TextEditor(text: $userSystemPrompt)
                    .font(.body)
                    .frame(minHeight: 96)
                    .overlay(alignment: .topLeading) {
                        if userSystemPrompt.isEmpty {
                            Text(copy.text(.instructionsPlaceholder))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                Text(copy.text(.instructionsHelp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(copy.text(.background)) {
                Toggle(copy.text(.launchAtLogin), isOn: $launchAtLogin)
                Text(copy.text(.backgroundHelp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(copy.text(.openLoginItems)) {
                    backgroundManager.openSystemSettings()
                }
            }

            Section(copy.text(.shortcut)) {
                TextField(copy.text(.shortcutDescriptor), text: $shortcut)
                Text(copy.text(.shortcutHelp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(copy.text(.contextAccess)) {
                Label(
                    accessibilityGranted ? copy.text(.accessGranted) : copy.text(.accessDenied),
                    systemImage: accessibilityGranted ? "checkmark.shield" : "exclamationmark.shield"
                )
                .foregroundStyle(accessibilityGranted ? Color.secondary : Color.orange)
                if !accessibilityGranted {
                    Text(copy.text(.accessRebuildHelp))
                        .font(.caption)
                    Text(String(format: copy.text(.privacyPath), SystemAccessibilityProvider.settingsPaneName))
                        .font(.caption)
                    Text(Bundle.main.bundleURL.path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                HStack {
                    Button(copy.text(.requestAccess)) {
                        accessibilityGranted = SystemAccessibilityProvider.requestAccessIfNeeded()
                    }
                    Button(copy.text(.openPrivacy)) {
                        SystemAccessibilityProvider.openAccessibilitySettings()
                    }
                    Button(copy.text(.showInFinder)) {
                        SystemAccessibilityProvider.revealRunningApp()
                    }
                    Button(copy.text(.refresh)) {
                        accessibilityGranted = SystemAccessibilityProvider().isTrusted
                    }
                }
            }

            Section {
                Button(copy.text(.save), action: saveSettings)
                    .keyboardShortcut(.defaultAction)
                if let statusMessage {
                    Label(statusMessage, systemImage: statusSymbol)
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 500, minHeight: 460)
        .navigationTitle(copy.text(.title))
        .onChange(of: credentialMode) { _, newMode in
            if newMode == .noAuthentication {
                apiKey.removeAll(keepingCapacity: false)
                hasAPIKey = false
            } else if newMode != providerSession.mode {
                hasAPIKey = false
            }
        }
        .onChange(of: settingsLanguage) { _, newLanguage in
            persistDisplayLanguage(newLanguage)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = SystemAccessibilityProvider().isTrusted
        }
    }

    private var copy: SettingsCopy {
        SettingsCopy(language: settingsLanguage)
    }

    private var apiKeyField: some View {
        LabeledContent(copy.text(.apiKey)) {
            ZStack(alignment: .leading) {
                SecureField("", text: $apiKey)
                    .accessibilityLabel(copy.text(.apiKey))
                    .accessibilityValue(hasConfiguredAPIKey ? copy.text(.apiKeyConfigured) : "")
                if apiKey.isEmpty, hasConfiguredAPIKey {
                    // A fixed number of bullets communicates presence without
                    // exposing any secret material or its actual length.
                    Text("••••••••••••")
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var hasConfiguredAPIKey: Bool {
        credentialMode != .noAuthentication && (hasAPIKey || hasRememberedAPIKey)
    }

    private func credentialModeDisplayName(_ mode: CredentialMode) -> String {
        switch (settingsLanguage, mode) {
        case (.english, .noAuthentication): "No Authentication"
        case (.english, .thisSessionOnly): "This Session Only"
        case (.english, .rememberOnThisMac): "Remember on This Mac"
        case (.simplifiedChinese, .noAuthentication): "无需认证"
        case (.simplifiedChinese, .thisSessionOnly): "仅本次会话"
        case (.simplifiedChinese, .rememberOnThisMac): "在此 Mac 记住"
        }
    }

    private var credentialHelpText: String {
        switch credentialMode {
        case .noAuthentication:
            copy.text(.noAuthenticationHelp)
        case .thisSessionOnly:
            copy.text(.sessionOnlyHelp)
        case .rememberOnThisMac:
            copy.text(.rememberHelp)
        }
    }

    private func saveSettings() {
        do {
            let normalizedEndpoint = try SettingsStore.normalizeBaseURL(endpoint)
            let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedShortcut = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedModel.isEmpty else { throw SettingsValidationError.emptyModel }
            guard !normalizedShortcut.isEmpty else { throw SettingsValidationError.emptyShortcut }
            guard userSystemPrompt.count <= 12_000 else { throw SettingsValidationError.systemPromptTooLong }
            guard !SensitiveTextDetector.containsCredential(in: userSystemPrompt) else {
                throw SettingsValidationError.systemPromptContainsCredential
            }

            let parsedShortcut = try GlobalHotkeyDescriptor(parsing: normalizedShortcut)
            let oldShortcut = settingsStore.current.hotkeyDescription
            if oldShortcut != parsedShortcut.displayName,
               let configurableManager = hotkeyManager as? any ConfigurableGlobalHotkeyManaging {
                try configurableManager.update(descriptor: parsedShortcut)
            }

            try applyCredentialSelection()
            try backgroundManager.setEnabled(launchAtLogin)
            settingsStore.save(AppSettings(
                baseURL: normalizedEndpoint,
                model: normalizedModel,
                hotkeyDescription: parsedShortcut.displayName,
                credentialMode: credentialMode,
                userSystemPrompt: userSystemPrompt,
                launchAtLogin: launchAtLogin,
                settingsLanguage: settingsLanguage
            ))
            onCredentialsApplied()
            showSuccess(copy.text(.saved))
        } catch let error as SettingsValidationError {
            showError(localizedValidationMessage(error))
        } catch let error as GlobalHotkeyDescriptorError {
            showError(error.localizedDescription)
        } catch let error as ProviderSessionError {
            showError(error.localizedDescription)
        } catch let error as KeychainStoreError {
            showError(error.localizedDescription)
        } catch let error as CocoaError {
            showError(error.localizedDescription)
        } catch {
            showError(LLMSecretRedactor.redact(error.localizedDescription, apiKey: apiKey))
        }
    }

    private func applyCredentials() {
        do {
            try applyCredentialSelection()
            var settings = settingsStore.current
            settings.credentialMode = credentialMode
            settingsStore.save(settings)
            onCredentialsApplied()
            showSuccess(copy.text(.credentialsApplied))
        } catch let error as ProviderSessionError {
            showError(error.localizedDescription)
        } catch let error as KeychainStoreError {
            showError(error.localizedDescription)
        } catch {
            showError(copy.text(.credentialsApplyFailed))
        }
    }

    private func applyCredentialSelection() throws {
        let enteredKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if enteredKey.isEmpty,
           credentialMode == providerSession.mode,
           providerSession.hasAPIKey {
            return
        }
        try providerSession.configure(
            mode: credentialMode,
            apiKey: enteredKey.isEmpty ? nil : enteredKey
        )
        if !enteredKey.isEmpty {
            clipboardManager.clearText(ifMatching: enteredKey)
        }
        apiKey.removeAll(keepingCapacity: false)
        hasAPIKey = providerSession.hasAPIKey
        hasRememberedAPIKey = providerSession.hasRememberedAPIKey
    }

    private func deleteAPIKey() {
        do {
            try providerSession.deleteRememberedAPIKey()
            hasAPIKey = false
            hasRememberedAPIKey = false
            apiKey.removeAll(keepingCapacity: false)
            showSuccess(copy.text(.rememberedKeyDeleted))
        } catch let error as KeychainStoreError {
            showError(error.localizedDescription)
        } catch {
            showError(copy.text(.rememberedKeyDeleteFailed))
        }
    }

    private func testConnection() {
        isTestingConnection = true
        statusMessage = nil
        Task {
            do {
                let normalizedEndpoint = try SettingsStore.normalizeBaseURL(endpoint)
                let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedModel.isEmpty else { throw SettingsValidationError.emptyModel }
                let enteredKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let credentials: ProviderCredentials
                if credentialMode == .noAuthentication {
                    credentials = ProviderCredentials(mode: .noAuthentication)
                } else if !enteredKey.isEmpty {
                    credentials = ProviderCredentials(mode: credentialMode, apiKey: enteredKey)
                } else {
                    credentials = try providerSession.credentialsForRequest()
                }
                let models = try await modelCatalogClient.fetchModels(
                    configuration: LLMConfiguration(baseURL: normalizedEndpoint, model: normalizedModel),
                    credentials: credentials
                )
                showSuccess(copy.connectedModels(models.count))
            } catch where ModelCatalogClient.isOptionalCatalogEndpointUnavailable(error) {
                showWarning(copy.text(.modelsUnavailable))
            } catch {
                showError(LLMSecretRedactor.redact(error.localizedDescription, apiKey: apiKey))
            }
            isTestingConnection = false
        }
    }

    private func showSuccess(_ message: String) {
        statusIsError = false
        statusIsWarning = false
        statusMessage = message
    }

    private func showError(_ message: String) {
        statusIsError = true
        statusIsWarning = false
        statusMessage = message
    }

    private func showWarning(_ message: String) {
        statusIsError = false
        statusIsWarning = true
        statusMessage = message
    }

    private var statusSymbol: String {
        statusIsError ? "exclamationmark.triangle" : (statusIsWarning ? "info.circle" : "checkmark.circle")
    }

    private var statusColor: Color {
        statusIsError ? .red : (statusIsWarning ? .orange : .green)
    }

    private func localizedValidationMessage(_ error: SettingsValidationError) -> String {
        guard settingsLanguage == .simplifiedChinese else { return error.localizedDescription }
        return switch error {
        case .emptyEndpoint: "请输入接口地址。"
        case .invalidEndpoint: "请输入有效的 HTTP 或 HTTPS 接口地址。"
        case .endpointContainsCredentials: "接口地址中不能包含凭据。"
        case .endpointContainsQuery: "接口地址中不能包含查询参数或片段。"
        case .emptyModel: "请输入模型名称。"
        case .emptyShortcut: "请输入快捷键描述。"
        case .systemPromptTooLong: "自定义系统提示词最多为 12,000 个字符。"
        case .systemPromptContainsCredential: "自定义系统提示词疑似包含凭据，因此未保存。"
        }
    }

    private func persistDisplayLanguage(_ language: SettingsLanguage) {
        var settings = settingsStore.current
        guard settings.settingsLanguage != language else { return }
        settings.settingsLanguage = language
        settingsStore.save(settings)
    }
}

/// App-owned settings window that is available immediately after an LSUIElement
/// app launches. It deliberately does not depend on SwiftUI's Settings scene or
/// on the floating panel having become key first.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(
        settingsStore: any SettingsStoring,
        providerSession: any ProviderSessionManaging,
        hotkeyManager: (any GlobalHotkeyManaging)? = nil,
        clipboardManager: any ClipboardManaging = ClipboardManager(),
        onCredentialsApplied: @escaping () -> Void = {}
    ) {
        let view = SettingsView(
            settingsStore: settingsStore,
            providerSession: providerSession,
            hotkeyManager: hotkeyManager,
            clipboardManager: clipboardManager,
            onCredentialsApplied: onCredentialsApplied
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FloatDude Settings"
        let hostingController = NSHostingController(rootView: view)
        // The grouped Form is scrollable and has no useful intrinsic window
        // height. Let AppKit own the window size instead of fitting to the Form.
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentMinSize = NSSize(width: 520, height: 480)
        window.setContentSize(NSSize(width: 560, height: 620))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
