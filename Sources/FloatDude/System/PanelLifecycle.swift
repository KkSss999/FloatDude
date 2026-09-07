import Foundation

enum PanelDismissReason: String, Sendable, Equatable {
    case escape
    case clickAway
    case repeatedShortcut
    case terminate
    case programmatic
}

enum PanelLifecycleEvent: Sendable, Equatable {
    case shortcut
    case escape
    case clickAway
    case terminate
    case dismiss
}

/// Main-actor state machine for one floating panel. It deliberately has no
/// AppKit dependency, so every dismissal path can be tested deterministically.
@MainActor
final class PanelLifecycle {
    typealias Hook = @MainActor @Sendable (PanelDismissReason) -> Void

    private(set) var isPresented = false

    private let onDismiss: Hook
    private let onCancel: Hook

    init(
        onDismiss: @escaping Hook = { _ in },
        onCancel: @escaping Hook = { _ in }
    ) {
        self.onDismiss = onDismiss
        self.onCancel = onCancel
    }

    @discardableResult
    func present() -> Bool {
        guard !isPresented else { return false }
        isPresented = true
        return true
    }

    @discardableResult
    func handle(_ event: PanelLifecycleEvent) -> Bool {
        switch event {
        case .shortcut:
            if isPresented {
                return false
            }
            return present()
        case .escape:
            return cancelAndDismiss(reason: .escape)
        case .clickAway:
            // The agent panel remains available while the user works in other
            // apps. Only explicit close paths dismiss it.
            return false
        case .terminate:
            return cancelAndDismiss(reason: .terminate)
        case .dismiss:
            return dismiss(reason: .programmatic)
        }
    }

    @discardableResult
    func dismiss(reason: PanelDismissReason = .programmatic) -> Bool {
        guard isPresented else { return false }
        isPresented = false
        onDismiss(reason)
        return true
    }

    @discardableResult
    func cancelAndDismiss(reason: PanelDismissReason) -> Bool {
        guard isPresented else { return false }
        isPresented = false
        onCancel(reason)
        onDismiss(reason)
        return true
    }
}
