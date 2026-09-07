import AppKit
import SwiftUI

/// Adapter between the MainActor session coordinator and the presentation-only
/// Adaptive Glass panel.
@MainActor
struct TaskPanelView: View {
    @ObservedObject var coordinator: TaskCoordinator
    let onStateChange: (FloatingPanelState) -> Void

    init(
        coordinator: TaskCoordinator,
        onStateChange: @escaping (FloatingPanelState) -> Void = { _ in }
    ) {
        self.coordinator = coordinator
        self.onStateChange = onStateChange
    }

    var body: some View {
        FloatingPanel(
            state: Binding(
                get: { coordinator.panelState },
                set: { _ in }
            ),
            prompt: $coordinator.userPrompt,
            selectedText: coordinator.session.context?.text ?? "",
            selectedSource: coordinator.session.context?.source,
            contextGuidance: coordinator.contextGuidance,
            selectedAction: $coordinator.selectedAction,
            handlers: FloatingPanelHandlers(
                onAction: { action in coordinator.runAction(action) },
                onSubmit: { action, prompt in
                    coordinator.submit(action: action, userPrompt: prompt)
                },
                onCopy: { _ in coordinator.copyResponse() },
                onCancel: { coordinator.cancelAndDismiss() },
                onRetry: { coordinator.retry() },
                onOpenSettings: { coordinator.openSettings() }
            ),
            onOpenAccessibilitySettings: {
                SystemAccessibilityProvider.openAccessibilitySettings()
            }
        )
        .onChange(of: coordinator.panelState) { _, newState in
            onStateChange(newState)
        }
    }
}
