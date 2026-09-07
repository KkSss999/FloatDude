import SwiftUI

/// Dedicated Settings scene content. API keys are selected explicitly as
/// either session-only or device-local remembered credentials.
@MainActor
struct SettingsView: View {
    private let settingsStore: any SettingsStoring
    private let providerSession: any ProviderSessionManaging
    private let hotkeyManager: (any GlobalHotkeyManaging)?

    @State private var endpoint: String
    @State private var model: String
    @State private var credentialMode: CredentialMode
    @State private var apiKey = ""
    @State private var shortcut: String
    @State private var hasAPIKey: Bool
    @State private var hasRememberedAPIKey: Bool
    @State private var statusMessage: String?
    @State private var statusIsError = false

    init(
        settingsStore: any SettingsStoring,
        providerSession: any ProviderSessionManaging,
        hotkeyManager: (any GlobalHotkeyManaging)? = nil
    ) {
        self.settingsStore = settingsStore
        self.providerSession = providerSession
        self.hotkeyManager = hotkeyManager
        let settings = settingsStore.current
        _endpoint = State(initialValue: settings.baseURL?.absoluteString ?? "")
        _model = State(initialValue: settings.model)
        _credentialMode = State(initialValue: settings.credentialMode)
        _shortcut = State(initialValue: settings.hotkeyDescription)
        _hasAPIKey = State(initialValue: settings.credentialMode != .noAuthentication && providerSession.hasAPIKey)
        _hasRememberedAPIKey = State(initialValue: providerSession.hasRememberedAPIKey)
    }

    var body: some View {
        Form {
            Section("Provider") {
                TextField("Endpoint URL", text: $endpoint)
                    .textContentType(.URL)
                TextField("Model", text: $model)

                Picker("Credential mode", selection: $credentialMode) {
                    ForEach(CredentialMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                SecureField("API key", text: $apiKey)
                    .disabled(credentialMode == .noAuthentication)

                Toggle(
                    "Remember this API key on this Mac",
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
                            ? "API key loaded from this Mac's Keychain"
                            : "API key active for this session",
                        systemImage: "checkmark.seal"
                    )
                    .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Apply Credentials", action: applyCredentials)
                        .disabled(
                            credentialMode == .thisSessionOnly
                                && apiKey.isEmpty
                                && !hasAPIKey
                        )
                    Button("Delete Remembered Key", role: .destructive, action: deleteAPIKey)
                        .disabled(credentialMode != .rememberOnThisMac || !hasRememberedAPIKey)
                }
            }

            Section("Shortcut") {
                TextField("Shortcut descriptor", text: $shortcut)
                Text("The shortcut is re-registered after a change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Save Settings", action: saveSettings)
                    .keyboardShortcut(.defaultAction)
                if let statusMessage {
                    Label(statusMessage, systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(statusIsError ? .red : .green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 500)
        .navigationTitle("FloatDude Settings")
        .onChange(of: credentialMode) { _, newMode in
            if newMode == .noAuthentication {
                apiKey.removeAll(keepingCapacity: false)
                hasAPIKey = false
            } else if newMode != providerSession.mode {
                hasAPIKey = false
            }
        }
    }

    private var credentialHelpText: String {
        switch credentialMode {
        case .noAuthentication:
            "No Keychain lookup, API key, or authentication header is used."
        case .thisSessionOnly:
            "The API key stays in memory only until FloatDude quits, you disconnect, or the mode changes."
        case .rememberOnThisMac:
            "The API key is saved only to this Mac's Keychain after you explicitly apply this mode."
        }
    }

    private func saveSettings() {
        do {
            let normalizedEndpoint = try SettingsStore.normalizeBaseURL(endpoint)
            let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedShortcut = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedModel.isEmpty else { throw SettingsValidationError.emptyModel }
            guard !normalizedShortcut.isEmpty else { throw SettingsValidationError.emptyShortcut }

            let parsedShortcut = try GlobalHotkeyDescriptor(parsing: normalizedShortcut)
            let oldShortcut = settingsStore.current.hotkeyDescription
            if oldShortcut != parsedShortcut.displayName,
               let configurableManager = hotkeyManager as? any ConfigurableGlobalHotkeyManaging {
                try configurableManager.update(descriptor: parsedShortcut)
            }

            try applyCredentialSelection()
            settingsStore.save(AppSettings(
                baseURL: normalizedEndpoint,
                model: normalizedModel,
                hotkeyDescription: parsedShortcut.displayName,
                credentialMode: credentialMode
            ))
            showSuccess("Settings saved.")
        } catch let error as SettingsValidationError {
            showError(error.localizedDescription)
        } catch let error as GlobalHotkeyDescriptorError {
            showError(error.localizedDescription)
        } catch let error as ProviderSessionError {
            showError(error.localizedDescription)
        } catch let error as KeychainStoreError {
            showError(error.localizedDescription)
        } catch {
            showError("Settings were not saved. Check the credential and shortcut configuration and try again.")
        }
    }

    private func applyCredentials() {
        do {
            try applyCredentialSelection()
            var settings = settingsStore.current
            settings.credentialMode = credentialMode
            settingsStore.save(settings)
            showSuccess("Credentials applied.")
        } catch let error as ProviderSessionError {
            showError(error.localizedDescription)
        } catch let error as KeychainStoreError {
            showError(error.localizedDescription)
        } catch {
            showError("Credentials could not be applied. Try again.")
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
            showSuccess("Remembered API key deleted.")
        } catch let error as KeychainStoreError {
            showError(error.localizedDescription)
        } catch {
            showError("The remembered API key could not be deleted. Try again.")
        }
    }

    private func showSuccess(_ message: String) {
        statusIsError = false
        statusMessage = message
    }

    private func showError(_ message: String) {
        statusIsError = true
        statusMessage = message
    }
}
