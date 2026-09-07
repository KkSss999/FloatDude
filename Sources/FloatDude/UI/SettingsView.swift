import AppKit
import SwiftUI

/// Dedicated Settings scene content. API keys are selected explicitly as
/// either session-only or device-local remembered credentials.
@MainActor
struct SettingsView: View {
    private let settingsStore: any SettingsStoring
    private let providerSession: any ProviderSessionManaging
    private let hotkeyManager: (any GlobalHotkeyManaging)?
    private let clipboardManager: any ClipboardManaging

    @State private var endpoint: String
    @State private var model: String
    @State private var credentialMode: CredentialMode
    @State private var apiKey = ""
    @State private var shortcut: String
    @State private var hasAPIKey: Bool
    @State private var hasRememberedAPIKey: Bool
    @State private var accessibilityGranted: Bool
    @State private var statusMessage: String?
    @State private var statusIsError = false

    init(
        settingsStore: any SettingsStoring,
        providerSession: any ProviderSessionManaging,
        hotkeyManager: (any GlobalHotkeyManaging)? = nil,
        clipboardManager: any ClipboardManaging = ClipboardManager()
    ) {
        self.settingsStore = settingsStore
        self.providerSession = providerSession
        self.hotkeyManager = hotkeyManager
        self.clipboardManager = clipboardManager
        let settings = settingsStore.current
        _endpoint = State(initialValue: settings.baseURL?.absoluteString ?? "")
        _model = State(initialValue: settings.model)
        _credentialMode = State(initialValue: settings.credentialMode)
        _shortcut = State(initialValue: settings.hotkeyDescription)
        _hasAPIKey = State(initialValue: settings.credentialMode != .noAuthentication && providerSession.hasAPIKey)
        _hasRememberedAPIKey = State(initialValue: providerSession.hasRememberedAPIKey)
        _accessibilityGranted = State(initialValue: SystemAccessibilityProvider().isTrusted)
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

            Section("Context Access") {
                Label(
                    accessibilityGranted ? "Accessibility access granted" : "Accessibility access required for selected text",
                    systemImage: accessibilityGranted ? "checkmark.shield" : "exclamationmark.shield"
                )
                .foregroundStyle(accessibilityGranted ? Color.secondary : Color.orange)

                HStack {
                    Button("Request Access") {
                        accessibilityGranted = SystemAccessibilityProvider.requestAccessIfNeeded()
                    }
                    Button("Open Accessibility Settings") {
                        SystemAccessibilityProvider.openAccessibilitySettings()
                    }
                    Button("Refresh") {
                        accessibilityGranted = SystemAccessibilityProvider().isTrusted
                    }
                }
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = SystemAccessibilityProvider().isTrusted
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

/// App-owned settings window that is available immediately after an LSUIElement
/// app launches. It deliberately does not depend on SwiftUI's Settings scene or
/// on the floating panel having become key first.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(
        settingsStore: any SettingsStoring,
        providerSession: any ProviderSessionManaging,
        hotkeyManager: (any GlobalHotkeyManaging)? = nil,
        clipboardManager: any ClipboardManaging = ClipboardManager()
    ) {
        let view = SettingsView(
            settingsStore: settingsStore,
            providerSession: providerSession,
            hotkeyManager: hotkeyManager,
            clipboardManager: clipboardManager
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FloatDude Settings"
        window.contentViewController = NSHostingController(rootView: view)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("FloatDudeSettingsWindow")
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
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
