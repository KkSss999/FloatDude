import AppKit
import SwiftUI

/// The one-shot prompt surface. It deliberately owns no networking or context
/// persistence; a coordinator supplies the action and submit closures.
struct PromptView: View {
    @Environment(\.colorScheme) private var scheme

    @Binding var prompt: String
    @Binding var selectedAction: PromptAction

    let selectedText: String
    let selectedSource: CapturedContext.Source?
    let canRewriteSelection: Bool
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
        canRewriteSelection: Bool = false,
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
        self.canRewriteSelection = canRewriteSelection
        self.contextGuidance = contextGuidance
        self.isDisabled = isDisabled
        self.onAction = onAction
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onOpenAccessibilitySettings = onOpenAccessibilitySettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || contextGuidance != nil {
                selectedContext
            }
            promptEditor
            actionPicker
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.78 : 1)
    }

    private var selectedContext: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top, spacing: 9) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(GlassPalette.coral(scheme).opacity(0.65))
                        .frame(width: 2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text((selectedSource?.displayName ?? "Selected text").uppercased())
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(.secondary)
                        Text(FloatingPanelText.selectedPreview(selectedText))
                            .font(.callout)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 3)
            }

            if let contextGuidance {
                VStack(alignment: .leading, spacing: 4) {
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
        HStack(spacing: 6) {
            ForEach(availableActions, id: \.self) { action in
                actionButton(action)
            }
        }
    }

    private var availableActions: [PromptAction] {
        canRewriteSelection ? [.explain, .translate, .rewrite] : [.explain, .translate]
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
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityLabel("Active")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .center)
            .contentShape(Rectangle())

        }
        .buttonStyle(GlassActionStyle(selected: isSelected))
        .foregroundStyle(isSelected ? GlassPalette.coral(scheme) : Color.primary)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(isSelected ? "Active action" : "Select this action")
    }

    private var promptEditor: some View {
        HStack(spacing: 8) {
            TextField("Ask FloatDude…", text: $prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...2)
                .focused($isPromptFocused)
                .onSubmit { submitAsk() }
                .accessibilityLabel("Ask Anything")
                .accessibilityHint("Enter a question or instructions")

            Button {
                submitAsk()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(GlassPalette.coral(scheme), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(scheme == .dark ? Color.black : Color.white)
            .opacity(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDisabled ? 0.4 : 1)
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDisabled)
            .accessibilityLabel("Ask FloatDude")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassInset(cornerRadius: 17, emphasized: isPromptFocused)
        .onAppear {
            if selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isPromptFocused = true
            }
        }
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
