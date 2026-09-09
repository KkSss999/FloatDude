import AppKit
import Combine
import Foundation

@MainActor
final class AppRuntime: ObservableObject {
    static let shared = AppRuntime()

    let settingsStore: SettingsStore
    let keychainStore: KeychainStore
    let providerSession: ProviderSession
    let clipboardManager: ClipboardManager
    let contextCapturer: SelectionCapture
    let hotkeyManager: CarbonGlobalHotkey
    let panelController: FloatingPanelController
    let coordinator: TaskCoordinator
    @Published private(set) var startupError: String?

    private var started = false
    private var lastPanelSize = CGSize.zero
    private var measuredPanelContentHeight: CGFloat?
    private var settingsWindowController: SettingsWindowController?

    init() {
        let settingsStore = SettingsStore()
        let keychainStore = KeychainStore()
        let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        let providerSession = ProviderSession(
            // The Xcode UI-test host constructs the real App graph before its
            // test bundle loads. Never let that bootstrap touch a user's login
            // Keychain; credential persistence has dedicated injected tests.
            mode: isTestHost ? .noAuthentication : settingsStore.current.credentialMode,
            keychainStore: keychainStore,
            loadRememberedImmediately: isTestHost || settingsStore.current.credentialMode != .rememberOnThisMac
        )
        let clipboardManager = ClipboardManager()
        let contextCapturer = SelectionCapture(pasteboard: clipboardManager)
        let liveSelectionObserver = SystemLiveSelectionObserver()
        let streamFactory: LLMStreamFactory = { request, configuration, credentials in
            AsyncThrowingStream { continuation in
                do {
                    let client = try OpenAIChatCompletionsClient(
                        configuration: configuration,
                        credentials: credentials
                    )
                    let task = Task {
                        do {
                            for try await event in client.stream(request) {
                                continuation.yield(event)
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                    continuation.onTermination = { @Sendable _ in
                        task.cancel()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        let coordinator = TaskCoordinator(
            contextCapturer: contextCapturer,
            streamFactory: streamFactory,
            settingsStore: settingsStore,
            providerSession: providerSession,
            clipboardManager: clipboardManager,
            conversationPersistence: FileConversationPersistence(),
            liveSelectionObserver: liveSelectionObserver
        )
        let configuredDescriptor = (try? GlobalHotkeyDescriptor(parsing: settingsStore.current.hotkeyDescription))
            ?? .optionSpace
        let hotkeyManager = CarbonGlobalHotkey(descriptor: configuredDescriptor) { [weak coordinator] in
            coordinator?.toggleInvocation()
        }
        let panelController = FloatingPanelController(
            onDismiss: { [weak coordinator] _ in
                coordinator?.panelDidDismiss()
            },
            onCancel: { [weak coordinator] _ in
                coordinator?.cancelActiveRequest()
            }
        )
        self.settingsStore = settingsStore
        self.keychainStore = keychainStore
        self.providerSession = providerSession
        self.clipboardManager = clipboardManager
        self.contextCapturer = contextCapturer
        self.hotkeyManager = hotkeyManager
        self.panelController = panelController
        self.coordinator = coordinator
        self.startupError = nil
        self.settingsWindowController = nil

        coordinator.onPresentPanel = { [weak self] in
            self?.presentPanel()
        }
        coordinator.onDismissPanel = { [weak self] in
            self?.panelController.dismiss()
        }
        coordinator.onOpenSettings = { [weak self] in
            self?.openSettings()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        do {
            try hotkeyManager.register()
        } catch {
            startupError = "The global shortcut could not be registered. Open Settings to choose another shortcut."
        }
        loadRememberedCredentialInBackground()
    }

    func stop() {
        guard started else { return }
        started = false
        coordinator.cancelActiveRequest()
        providerSession.clear()
        panelController.dismiss()
        settingsWindowController?.close()
        hotkeyManager.unregister()
    }

    func openSettings() {
        let controller: SettingsWindowController
        if let settingsWindowController {
            controller = settingsWindowController
        } else {
            controller = SettingsWindowController(
                settingsStore: settingsStore,
                providerSession: providerSession,
                hotkeyManager: hotkeyManager,
                clipboardManager: clipboardManager,
                onCredentialsApplied: { [weak self] in
                    self?.clearCredentialStartupError()
                }
            )
            settingsWindowController = controller
        }
        controller.present()
    }

    func startNewConversation() {
        coordinator.newConversation()
        if coordinator.hasActiveInvocation {
            presentPanel()
        } else {
            coordinator.beginInvocation()
        }
    }

    func openExportsFolder() {
        let url = FileConversationPersistence.defaultRootURL()
            .appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func loadRememberedCredentialInBackground() {
        guard settingsStore.current.credentialMode == .rememberOnThisMac else { return }
        let keychainStore = self.keychainStore
        Task { [weak self] in
            let result = await Task.detached {
                Result { try keychainStore.apiKey() }
            }.value
            guard let self else { return }
            switch result {
            case let .success(key?):
                providerSession.acceptRememberedAPIKey(key)
            case .success(nil):
                startupError = "The remembered API key is missing. Apply credentials again in Settings."
            case .failure:
                startupError = "The remembered API key could not be loaded. Apply it again in Settings."
            }
        }
    }

    private func clearCredentialStartupError() {
        guard startupError?.hasPrefix("The remembered API key") == true else { return }
        startupError = nil
    }

    private func presentPanel() {
        settingsWindowController?.window?.orderOut(nil)
        if !panelController.isPresented {
            measuredPanelContentHeight = nil
        }
        let view = TaskPanelView(
            coordinator: coordinator,
            settingsStore: settingsStore,
            onStateChange: { [weak self] state in
                self?.resizePanel(for: state)
            },
            onContentHeightChange: { [weak self] contentHeight in
                self?.updateMeasuredPanelContentHeight(contentHeight)
            }
        )
        let size = panelSize(for: coordinator.panelState)
        lastPanelSize = size
        panelController.present(
            content: { view },
            panelSize: size,
            avoiding: coordinator.session.context?.selectionRect,
            activateForInput: coordinator.session.context == nil
        )
    }

    private func resizePanel(for state: FloatingPanelState) {
        let size = panelSize(for: state)
        guard size != lastPanelSize else { return }
        lastPanelSize = size
        panelController.update(
            panelSize: size,
            avoiding: coordinator.session.context?.selectionRect
        )
    }

    private func updateMeasuredPanelContentHeight(_ contentHeight: CGFloat) {
        let normalized = max(1, contentHeight)
        guard measuredPanelContentHeight.map({ abs($0 - normalized) > 1 }) ?? true else { return }
        measuredPanelContentHeight = normalized
        resizePanel(for: coordinator.panelState)
    }

    private func panelSize(for state: FloatingPanelState) -> CGSize {
        let minimumContentHeight: CGFloat
        switch state {
        case .loading, .streaming, .completed, .cancelled, .error:
            minimumContentHeight = 260
        case .idle, .prompting:
            minimumContentHeight = coordinator.session.context == nil ? 232 : 292
        }

        // Text character counts cannot predict Markdown layout. Use the real
        // SwiftUI content height once it is available; the fallback only avoids
        // a cramped first frame. WindowPositioner applies the iPhone canvas cap
        // and display-scale safe frame after this request.
        return CGSize(
            width: PanelSizePolicy.iPhone17ProMaxCanvas.width,
            height: min(
                PanelSizePolicy.iPhone17ProMaxCanvas.height,
                max(minimumContentHeight, measuredPanelContentHeight ?? minimumContentHeight)
            )
        )
    }
}
