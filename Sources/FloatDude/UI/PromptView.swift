import AppKit
import SwiftUI

/// The one-shot prompt surface. It deliberately owns no networking or context
/// persistence; a coordinator supplies the action and submit closures.
struct PromptView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Binding var prompt: String
    @Binding var selectedAction: PromptAction

    let selectedText: String
    let selectedSource: CapturedContext.Source?
    let contextGuidance: String?
    let isDisabled: Bool
    let onAction: ((PromptAction) -> Void)?
    let onSubmit: ((PromptAction, String) -> Void)?
    let onCancel: (() -> Void)?
    let onOpenAccessibilitySettings: (() -> Void)?
    @FocusState private var isPromptFocused: Bool

    init(
        prompt: Binding<String>,
        selectedText: String = "",
        selectedSource: CapturedContext.Source? = nil,
        contextGuidance: String? = nil,
        selectedAction: Binding<PromptAction> = .constant(.ask),
        isDisabled: Bool = false,
        onAction: ((PromptAction) -> Void)? = nil,
        onSubmit: ((PromptAction, String) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onOpenAccessibilitySettings: (() -> Void)? = nil
    ) {
        self._prompt = prompt
        self._selectedAction = selectedAction
        self.selectedText = selectedText
        self.selectedSource = selectedSource
        self.contextGuidance = contextGuidance
        self.isDisabled = isDisabled
        self.onAction = onAction
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onOpenAccessibilitySettings = onOpenAccessibilitySettings
    }

    private var canSubmit: Bool {
        let hasSelectedText = !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPrompt = !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasSelectedText || hasPrompt) && !isDisabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            selectedContext
            actionPicker
            promptEditor
            promptFooter
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.78 : 1)
    }

    private var selectedContext: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(selectedSource?.displayName ?? "Context", systemImage: "text.quote")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                if selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("No selection — ask anything")
                        .foregroundStyle(.secondary)
                } else {
                    Text(FloatingPanelText.selectedPreview(selectedText))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.thinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }

            if let contextGuidance {
                VStack(alignment: .leading, spacing: 6) {
                    Label(contextGuidance, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if contextGuidance.localizedCaseInsensitiveContains("Accessibility") {
                        Button("Open Accessibility Settings") {
                            onOpenAccessibilitySettings?()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                }
            }
        }
    }

    private var actionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose an action")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach([PromptAction.explain, .translate, .rewrite], id: \.self) { action in
                    actionButton(action)
                }
            }
        }
    }

    private func actionButton(_ action: PromptAction) -> some View {
        let isSelected = selectedAction == action

        return Button {
            selectedAction = action
            onAction?(action)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: action.symbolName)
                    .accessibilityHidden(true)
                Text(action.title)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityLabel("Active")
                }
            }
            .font(.body.weight(isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "Active action" : "Select this action")
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask Anything")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("What would you like to know?", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                }
                .focused($isPromptFocused)
                .onSubmit { submit() }
                .accessibilityLabel("Ask Anything")
                .accessibilityHint("Enter a question or instructions")
        }
        .onAppear {
            if selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isPromptFocused = true
            }
        }
    }

    private var promptFooter: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                onCancel?()
            } label: {
                Label("Press Esc to close", systemImage: "escape")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape)
            .foregroundStyle(.secondary)
            .accessibilityHint("Dismiss the panel")

            Spacer(minLength: 0)

            Button {
                submit()
            } label: {
                Label("Run \(selectedAction.title)", systemImage: "arrow.up.circle.fill")
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func submit() {
        guard canSubmit else { return }
        onSubmit?(selectedAction, prompt.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private extension PromptAction {
    var symbolName: String {
        switch self {
        case .explain: "lightbulb"
        case .translate: "globe"
        case .rewrite: "pencil.and.outline"
        case .ask: "questionmark"
        }
    }
}
