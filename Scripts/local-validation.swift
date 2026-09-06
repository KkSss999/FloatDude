import ApplicationServices
import Foundation

@main
struct LocalValidation {
    @MainActor
    static func main() async {
        validateEndpointAndSSE()
        await validateContextPrecedence()
        validateHotkeyRegistration()
        await validateCoordinatorFlow()
        print("LOCAL_VALIDATION_OK")
    }

    private static func validateEndpointAndSSE() {
        let endpoint = try! LLMEndpoint.normalizedBaseURL(URL(string: "https://provider.example///")!)
        precondition(endpoint.absoluteString == "https://provider.example")

        var parser = SSEParser()
        let payload = Array("data: 你\ndata: 好\n\n".utf8)
        let split = payload.firstIndex(of: 0xE4)! + 1
        precondition((try! parser.append(Data(payload[..<split]))).isEmpty)
        let events = try! parser.append(Data(payload[split...]))
        precondition(events == [SSEEvent(data: "你\n好")])
    }

    private static func validateContextPrecedence() async {
        let capture = SelectionCapture(
            accessibility: ValidationAccessibility(selectedText: "AX"),
            pasteboard: ValidationPasteboard(text: "clipboard")
        )
        let result = await capture.captureContext(directInput: "direct")
        precondition(result == .captured(CapturedContext(text: "AX", source: .accessibilitySelection, applicationName: nil)))

        let fallback = SelectionCapture(
            accessibility: ValidationAccessibility(),
            pasteboard: ValidationPasteboard(text: "clipboard")
        )
        let fallbackResult = await fallback.captureContext(directInput: "direct")
        precondition(fallbackResult == .captured(CapturedContext(text: "clipboard", source: .clipboard, applicationName: nil)))
    }

    @MainActor
    private static func validateHotkeyRegistration() {
        precondition((try! GlobalHotkeyDescriptor(parsing: "Command-K")).displayName == "Command-K")
        let hotkey = CarbonGlobalHotkey { }
        try! hotkey.register()
        precondition(hotkey.isRegistered)
        hotkey.unregister()
        precondition(!hotkey.isRegistered)
    }

    @MainActor
    private static func validateCoordinatorFlow() async {
        let settings = ValidationSettingsStore()
        let clipboard = ValidationPasteboard()
        let coordinator = TaskCoordinator(
            contextCapturer: ValidationContextCapturer(),
            streamFactory: { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(.textDelta("first "))
                    continuation.yield(.textDelta("answer"))
                    continuation.yield(.completed)
                    continuation.finish()
                }
            },
            settingsStore: settings,
            keychainStore: ValidationKeychain(),
            clipboardManager: clipboard
        )

        coordinator.beginInvocation()
        await waitUntil { coordinator.session.phase == .contextCaptured }
        coordinator.submit(action: .explain, userPrompt: "")
        await waitUntil { coordinator.session.phase == .completed }
        let response = coordinator.session.response
        precondition(response == "first answer")
        coordinator.copyResponse()
        precondition(clipboard.lastWrite == "first answer")
    }

    @MainActor
    private static func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if predicate() { return }
            await Task.yield()
        }
        preconditionFailure("local validation timed out")
    }
}

private struct ValidationAccessibility: AccessibilityProviding {
    let selectedText: String?
    var isTrusted: Bool { true }

    init(selectedText: String? = nil) {
        self.selectedText = selectedText
    }

    func focusedElement() throws -> AXUIElement? {
        AXUIElementCreateSystemWide()
    }

    func selectedText(from focusedElement: AXUIElement) throws -> String? {
        selectedText
    }
}

private final class ValidationPasteboard: ClipboardManaging, @unchecked Sendable {
    let text: String?
    var lastWrite: String?

    init(text: String? = nil) {
        self.text = text
    }

    func readText() -> String? { text }

    func writeText(_ text: String) {
        lastWrite = text
    }
}

private struct ValidationContextCapturer: ContextCapturing {
    func captureContext(directInput: String?) async -> ContextCaptureResult {
        .captured(CapturedContext(text: "context", source: .clipboard, applicationName: nil))
    }
}

@MainActor
private final class ValidationSettingsStore: SettingsStoring {
    private(set) var current = AppSettings(
        baseURL: URL(string: "https://provider.example"),
        model: "demo-model",
        hotkeyDescription: "Option-Space"
    )

    func save(_ settings: AppSettings) {
        current = settings
    }
}

private struct ValidationKeychain: KeychainStoring {
    func apiKey() throws -> String? { "validation-key" }
    func saveAPIKey(_ key: String) throws {}
    func updateAPIKey(_ key: String) throws {}
    func deleteAPIKey() throws {}
}
