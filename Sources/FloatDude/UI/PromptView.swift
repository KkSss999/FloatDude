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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        HStack(spacing: 8) {
            ForEach([PromptAction.explain, .translate, .rewrite], id: \.self) { action in
                actionButton(action)
            }
        }
    }

    private func actionButton(_ action: PromptAction) -> some View {
        let isSelected = selectedAction == action

        return Button {
            selectedAction = action
            onAction?(action)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: action.symbolName)
                    .accessibilityHidden(true)
                Text(action.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityLabel("Active")
                }
            }
            .font(.body.weight(isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
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
        HStack(spacing: 8) {
            TextField("What would you like to know?", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                }
                .focused($isPromptFocused)
                .onSubmit { submitAsk() }
                .accessibilityLabel("Ask Anything")
                .accessibilityHint("Enter a question or instructions")

            Button {
                submitAsk()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDisabled)
            .accessibilityLabel("Ask FloatDude")
        }
        .onAppear {
            if selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isPromptFocused = true
            }
        }
    }

    private var promptFooter: some View {
        EmptyView()
    }

    private func submitAsk() {
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty, !isDisabled else { return }
        onSubmit?(PromptAction.actionForSubmission(prompt: normalizedPrompt, fallback: selectedAction), normalizedPrompt)
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
