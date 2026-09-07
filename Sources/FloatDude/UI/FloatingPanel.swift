import Foundation
import SwiftUI

enum FloatingPanelState: Equatable, Sendable {
    case idle
    case prompting
    case loading(action: PromptAction)
    case streaming(text: String)
    case completed(text: String)
    case cancelled
    case error(message: String)

    var isBusy: Bool {
        switch self {
        case .loading, .streaming: true
        default: false
        }
    }

    var isResponseVisible: Bool {
        switch self {
        case .loading, .streaming, .completed, .cancelled, .error: true
        case .idle, .prompting: false
        }
    }

    var responseText: String? {
        switch self {
        case .streaming(let text), .completed(let text): text
        default: nil
        }
    }

    var statusTitle: String {
        switch self {
        case .idle: "Ready"
        case .prompting: "Prompt"
        case .loading: "Loading"
        case .streaming: "Streaming"
        case .completed: "Complete"
        case .cancelled: "Cancelled"
        case .error: "Error"
        }
    }

    var headerSymbolName: String {
        switch self {
        case .loading, .streaming: "sparkles"
        case .completed: "checkmark.circle"
        case .cancelled: "pause.circle"
        case .error: "exclamationmark.triangle"
        case .idle, .prompting: "text.bubble"
        }
    }
}

/// Pure state and transition model for deterministic coordinator and UI tests.
struct FloatingPanelViewModel: Equatable, Sendable {
    var selectedText: String
    var prompt: String
    var selectedAction: PromptAction
    private(set) var state: FloatingPanelState

    init(
        selectedText: String = "",
        prompt: String = "",
        selectedAction: PromptAction = .ask,
        state: FloatingPanelState = .idle
    ) {
        self.selectedText = selectedText
        self.prompt = prompt
        self.selectedAction = selectedAction
        self.state = state
    }

    var selectedTextPreview: String {
        FloatingPanelText.selectedPreview(selectedText)
    }

    mutating func beginPrompting() {
        guard !state.isBusy else { return }
        state = .prompting
    }

    mutating func choose(_ action: PromptAction) {
        selectedAction = action
        if !state.isBusy { state = .prompting }
    }

    @discardableResult
    mutating func submit() -> Bool {
        guard !state.isBusy,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        state = .loading(action: selectedAction)
        return true
    }

    mutating func appendStream(_ delta: String) {
        guard !delta.isEmpty else { return }
        switch state {
        case .loading:
            state = .streaming(text: delta)
        case .streaming(let text):
            state = .streaming(text: text + delta)
        default:
            break
        }
    }

    mutating func complete(with text: String? = nil) {
        let resolved: String
        if let text {
            resolved = text
        } else {
            resolved = state.responseText ?? ""
        }
        state = .completed(text: resolved)
    }

    mutating func cancel() {
        guard state.isBusy else { return }
        state = .cancelled
    }

    mutating func fail(with message: String) {
        state = .error(message: message)
    }
}

struct FloatingPanelHandlers {
    var onAction: ((PromptAction) -> Void)?
    var onSubmit: ((PromptAction, String) -> Void)?
    var onCopy: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?

    init(
        onAction: ((PromptAction) -> Void)? = nil,
        onSubmit: ((PromptAction, String) -> Void)? = nil,
        onCopy: ((String) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.onAction = onAction
        self.onSubmit = onSubmit
        self.onCopy = onCopy
        self.onCancel = onCancel
        self.onRetry = onRetry
    }
}

enum FloatingPanelText {
    static func selectedPreview(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .prefix(2)
            .joined(separator: "\n")
    }
}

/// SwiftUI content boundary for the AppKit-backed floating panel.
/// Window level, focus, and actual dismissal remain coordinator concerns.
struct FloatingPanel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding private var state: FloatingPanelState
    @Binding private var prompt: String
    @Binding private var selectedAction: PromptAction

    private let selectedText: String
    private let selectedSource: CapturedContext.Source?
    private let contextGuidance: String?
    private let onOpenAccessibilitySettings: (() -> Void)?
    private let handlers: FloatingPanelHandlers
    private let customContent: AnyView?
    @State private var didExpandOnce = false

    init(
        state: Binding<FloatingPanelState>,
        prompt: Binding<String>,
        selectedText: String = "",
        selectedSource: CapturedContext.Source? = nil,
        contextGuidance: String? = nil,
        selectedAction: Binding<PromptAction> = .constant(.ask),
        handlers: FloatingPanelHandlers = .init(),
        onOpenAccessibilitySettings: (() -> Void)? = nil
    ) {
        self._state = state
        self._prompt = prompt
        self._selectedAction = selectedAction
        self.selectedText = selectedText
        self.selectedSource = selectedSource
        self.contextGuidance = contextGuidance
        self.onOpenAccessibilitySettings = onOpenAccessibilitySettings
        self.handlers = handlers
        self.customContent = nil
    }

    /// Keeps the original presentation-only content boundary available for
    /// callers that want to supply a custom panel surface.
    init<Content: View>(@ViewBuilder content: () -> Content) {
        self._state = .constant(.idle)
        self._prompt = .constant("")
        self._selectedAction = .constant(.ask)
        self.selectedText = ""
        self.selectedSource = nil
        self.contextGuidance = nil
        self.onOpenAccessibilitySettings = nil
        self.handlers = .init()
        self.customContent = AnyView(content())
    }

    var body: some View {
        Group {
            if let customContent {
                customContent
            } else {
                panelSurface
            }
        }
    }

    private var panelSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            panelHeader

            PromptView(
                prompt: $prompt,
                    selectedText: selectedText,
                    selectedSource: selectedSource,
                    contextGuidance: contextGuidance,
                    selectedAction: $selectedAction,
                    isDisabled: state.isBusy,
                    onAction: handlers.onAction,
                    onSubmit: submit,
                    onCancel: handlers.onCancel,
                    onOpenAccessibilitySettings: onOpenAccessibilitySettings
            )

            if state.isResponseVisible {
                ResponseView(
                    response: state.responseText ?? "",
                    state: state,
                    onCopy: handlers.onCopy,
                    onCancel: handlers.onCancel,
                    onRetry: handlers.onRetry
                )
                .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .padding(16)
        .frame(minWidth: 336, idealWidth: 400, maxWidth: 456, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .glassMaterial(cornerRadius: 22)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: didExpandOnce)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear {
            updateExpansion(for: state)
        }
        .onChange(of: state) { _, newState in
            updateExpansion(for: newState)
        }
    }

    private var panelHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("FloatDude")
                    .font(.headline)
                Text(state.isResponseVisible ? state.statusTitle : "One-shot assistant")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text("Esc")
                .font(.caption2.weight(.bold).monospaced())
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityLabel("Press Escape to close")
        }
    }

    private func submit(action: PromptAction, prompt: String) {
        handlers.onSubmit?(action, prompt)
    }

    private func updateExpansion(for newState: FloatingPanelState) {
        guard newState.isResponseVisible else { return }
        // The response phase has one expansion event for the lifetime of this
        // panel; subsequent stream chunks only update content within the same
        // response region.
        if !didExpandOnce { didExpandOnce = true }
    }
}
