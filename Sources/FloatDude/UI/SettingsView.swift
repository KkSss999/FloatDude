import SwiftUI

/// Dedicated Settings scene content. Secrets are entered into a secure field
/// and are never loaded into AppSettings or UserDefaults.
@MainActor
struct SettingsView: View {
    private let settingsStore: any SettingsStoring
    private let keychainStore: any KeychainStoring
    private let hotkeyManager: (any GlobalHotkeyManaging)?

    @State private var endpoint: String
    @State private var model: String
    @State private var apiKey = ""
    @State private var shortcut: String
    @State private var hasStoredAPIKey: Bool
    @State private var statusMessage: String?
    @State private var statusIsError = false

    init(
        settingsStore: any SettingsStoring = SettingsStore(),
        keychainStore: any KeychainStoring = KeychainStore(),
        hotkeyManager: (any GlobalHotkeyManaging)? = nil
    ) {
        self.settingsStore = settingsStore
        self.keychainStore = keychainStore
        self.hotkeyManager = hotkeyManager
        let settings = settingsStore.current
        _endpoint = State(initialValue: settings.baseURL?.absoluteString ?? "")
        _model = State(initialValue: settings.model)
        _shortcut = State(initialValue: settings.hotkeyDescription)
        do {
            _hasStoredAPIKey = State(initialValue: try keychainStore.apiKey() != nil)
        } catch {
            _hasStoredAPIKey = State(initialValue: false)
            _statusMessage = State(initialValue: "The saved API key could not be checked. Try saving it again.")
            _statusIsError = State(initialValue: true)
        }
    }

    var body: some View {
        Form {
            Section("Provider") {
                TextField("Endpoint URL", text: $endpoint)
                    .textContentType(.URL)
                TextField("Model", text: $model)
                SecureField("API key", text: $apiKey)
                Text("API keys are stored only in the macOS Keychain. Leave blank to keep the saved key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if hasStoredAPIKey {
                    Label("API key saved", systemImage: "checkmark.seal")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Save API Key") { saveAPIKey() }
                        .disabled(apiKey.isEmpty)
                    Button("Delete API Key", role: .destructive) { deleteAPIKey() }
                        .disabled(!hasStoredAPIKey)
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
        .frame(minWidth: 460)
        .navigationTitle("FloatDude Settings")
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

            settingsStore.save(AppSettings(
                baseURL: normalizedEndpoint,
                model: normalizedModel,
                hotkeyDescription: parsedShortcut.displayName
            ))
            showSuccess("Settings saved.")
        } catch let error as SettingsValidationError {
            showError(error.localizedDescription)
        } catch let error as GlobalHotkeyDescriptorError {
            showError(error.localizedDescription)
        } catch {
            showError("Settings were not saved because the shortcut could not be registered. Choose another shortcut and try again.")
        }
    }

    private func saveAPIKey() {
        do {
            try keychainStore.saveAPIKey(apiKey)
            apiKey.removeAll(keepingCapacity: false)
            hasStoredAPIKey = true
            showSuccess("API key saved securely.")
        } catch let error as KeychainStoreError {
            showError(error.localizedDescription)
        } catch {
            showError("The API key could not be saved to Keychain. Try again.")
        }
    }

    private func deleteAPIKey() {
        do {
            try keychainStore.deleteAPIKey()
            apiKey.removeAll(keepingCapacity: false)
            hasStoredAPIKey = false
            showSuccess("API key deleted.")
        } catch let error as KeychainStoreError {
            showError(error.localizedDescription)
        } catch {
            showError("The API key could not be deleted from Keychain. Try again.")
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
