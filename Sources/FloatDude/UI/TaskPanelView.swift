import AppKit
import SwiftUI

/// Adapter between the MainActor session coordinator and the presentation-only
/// Adaptive Glass panel.
@MainActor
struct TaskPanelView: View {
    @ObservedObject var coordinator: TaskCoordinator
    @ObservedObject var settingsStore: SettingsStore
    let onStateChange: (FloatingPanelState) -> Void
    let onContentHeightChange: (CGFloat) -> Void

    init(
        coordinator: TaskCoordinator,
        settingsStore: SettingsStore,
        onStateChange: @escaping (FloatingPanelState) -> Void = { _ in },
        onContentHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.coordinator = coordinator
        self.settingsStore = settingsStore
        self.onStateChange = onStateChange
        self.onContentHeightChange = onContentHeightChange
    }

    var body: some View {
        FloatingPanel(
            state: Binding(
                get: { coordinator.panelState },
                set: { _ in }
            ),
            prompt: $coordinator.userPrompt,
            language: settingsStore.current.settingsLanguage,
            selectedText: coordinator.session.context?.text ?? "",
            selectedSource: coordinator.session.context?.source,
            canRewriteSelection: coordinator.session.context?.canReplaceSelection ?? false,
            contextGuidance: coordinator.contextGuidance,
            selectedAction: $coordinator.selectedAction,
            conversations: coordinator.conversations,
            activeConversationID: coordinator.activeConversationID,
            conversationMessages: transcriptMessages,
            attachments: coordinator.activeConversation?.attachments ?? [],
            attachmentStatus: coordinator.attachmentStatus ?? coordinator.persistenceStatus,
            handlers: FloatingPanelHandlers(
                onAction: { action in coordinator.runAction(action) },
                onSubmit: { action, prompt in
                    coordinator.submit(action: action, userPrompt: prompt)
                },
                onCopy: { _ in coordinator.copyResponse() },
                onCancel: { coordinator.cancelAndDismiss() },
                onRetry: { coordinator.retry() },
                onOpenSettings: { coordinator.openSettings() },
                onNewConversation: { coordinator.newConversation() },
                onSelectConversation: { coordinator.selectConversation($0) },
                onDeleteConversation: { coordinator.deleteConversation($0) },
                onAddAttachments: { coordinator.addAttachments($0) },
                onRemoveAttachment: { coordinator.removeAttachment($0) }
            ),
            onOpenAccessibilitySettings: {
                SystemAccessibilityProvider.openAccessibilitySettings()
            },
            onContentHeightChange: onContentHeightChange
        )
        .onChange(of: coordinator.panelState) { _, newState in
            onStateChange(newState)
        }
        .onChange(of: coordinator.activeConversation?.messages.count ?? 0) { _, _ in
            onStateChange(coordinator.panelState)
        }
        .onChange(of: coordinator.activeConversation?.attachments.count ?? 0) { _, _ in
            onStateChange(coordinator.panelState)
        }
        .onChange(of: coordinator.activeConversationID) { _, _ in
            onStateChange(coordinator.panelState)
        }
        .onChange(of: coordinator.session.context) { _, _ in
            onStateChange(coordinator.panelState)
        }
    }

    private var transcriptMessages: [AgentMessage] {
        var messages = coordinator.activeConversation?.messages ?? []
        let state = coordinator.panelState
        guard state.isResponseVisible else { return messages }

        let transientContent: String
        switch state {
        case .loading:
            transientContent = "…"
        case .streaming, .completed:
            transientContent = coordinator.session.response
        case .cancelled, .error:
            transientContent = coordinator.session.response
        case .idle, .prompting:
            return messages
        }

        guard !transientContent.isEmpty else { return messages }
        let transientID = coordinator.responseDisplayID ?? UUID()
        if messages.last?.id != transientID {
            messages.append(.init(id: transientID, role: .assistant, content: transientContent))
        }
        return messages
    }
}
