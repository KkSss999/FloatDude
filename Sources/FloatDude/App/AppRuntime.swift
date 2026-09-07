import AppKit
import Combine
import Foundation

@MainActor
final class AppRuntime: ObservableObject {
    static let shared = AppRuntime()

    let settingsStore: SettingsStore
    let providerSession: ProviderSession
    let clipboardManager: ClipboardManager
    let contextCapturer: SelectionCapture
    let hotkeyManager: CarbonGlobalHotkey
    let panelController: FloatingPanelController
    let settingsWindowController: SettingsWindowController
    let coordinator: TaskCoordinator
    @Published private(set) var startupError: String?

    private var started = false
    private var lastResponseVisibility = false

    init() {
        let settingsStore = SettingsStore()
        let keychainStore = KeychainStore()
        let providerSession = ProviderSession(
            mode: settingsStore.current.credentialMode,
            keychainStore: keychainStore
        )
        let clipboardManager = ClipboardManager()
        let contextCapturer = SelectionCapture(pasteboard: clipboardManager)
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
            clipboardManager: clipboardManager
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
        let settingsWindowController = SettingsWindowController(
            settingsStore: settingsStore,
            providerSession: providerSession,
            hotkeyManager: hotkeyManager,
            clipboardManager: clipboardManager
        )

        self.settingsStore = settingsStore
        self.providerSession = providerSession
        self.clipboardManager = clipboardManager
        self.contextCapturer = contextCapturer
        self.hotkeyManager = hotkeyManager
        self.panelController = panelController
        self.settingsWindowController = settingsWindowController
        self.coordinator = coordinator
        self.startupError = nil

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
    }

    func stop() {
        guard started else { return }
        started = false
        coordinator.cancelActiveRequest()
        providerSession.clear()
        panelController.dismiss()
        settingsWindowController.close()
        hotkeyManager.unregister()
    }

    func openSettings() {
        settingsWindowController.present()
    }

    private func presentPanel() {
        let view = TaskPanelView(coordinator: coordinator) { [weak self] state in
            self?.resizePanel(for: state)
        }
        lastResponseVisibility = coordinator.panelState.isResponseVisible
        panelController.present(
            content: { view },
            panelSize: panelSize(for: coordinator.panelState),
            avoiding: coordinator.session.context?.selectionRect,
            activateForInput: coordinator.session.context == nil
        )
    }

    private func resizePanel(for state: FloatingPanelState) {
        guard state.isResponseVisible != lastResponseVisibility else { return }
        lastResponseVisibility = state.isResponseVisible
        panelController.update(
            panelSize: panelSize(for: state),
            avoiding: coordinator.session.context?.selectionRect
        )
    }

    private func panelSize(for state: FloatingPanelState) -> CGSize {
        let hasContext = coordinator.session.context != nil
        return switch state {
        case .loading, .streaming, .completed, .cancelled, .error:
            CGSize(width: 400, height: 420)
        case .idle, .prompting:
            CGSize(width: 400, height: hasContext ? 236 : 176)
        }
    }
}
